#!/usr/bin/env bash
# pre-askuserquestion-guard.sh -- PreToolUse:AskUserQuestion hook (P1-3B)
# that denies interactive prompts while the autopilot orchestrator is
# inside its non-interactive window, using a 3-tier risk_tolerance x
# 6-header allow-list matrix to decide allow / deny per call.
#
# Companion to:
#   - hooks/lib/parse-state-file.sh: provides is_autopilot_context,
#     find_any_autopilot_state_file, parse_ticket_statuses,
#     get_risk_tolerance.
#   - skills/autopilot/SKILL.md ## Non-interactive orchestrator contract
#     (3-tier, risk_tolerance-aware) -- P0-3A prose layer enforced
#     structurally by this hook. The matrix below MUST stay in sync with
#     the SKILL.md table; tests/test-skill-contracts.sh AP-26 and the
#     P1-3B meta block enforce that parity by grep across both files.
#   - hooks/pre-level1-guard.sh: prior example using the
#     hookSpecificOutput.permissionDecision shape on PreToolUse.
#
# Public contract:
#   stdin:  JSON payload from harness, e.g.
#           {"tool_name":"AskUserQuestion",
#            "tool_input":{"questions":[{"question":"...","header":"audit-fail"}]},
#            "cwd":"...","session_id":"...","transcript_path":"..."}
#   stdout: single JSON object of shape
#           {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#                                  "permissionDecision":"allow"|"deny",
#                                  "permissionDecisionReason":"..."}}.
#   exit:   0 in both allow and deny paths.
#
# Kill-switch (CLAUDE.md ### Runtime env knobs):
#   SW_AUTOPILOT_ASK_GUARD unset / on  -> matrix active (default)
#   SW_AUTOPILOT_ASK_GUARD=metric-only -> compute decision, log
#                                          "would deny" to stderr, allow
#   SW_AUTOPILOT_ASK_GUARD=off         -> silent allow (any unknown value
#                                          also collapses here)
#
# Header schema constraint: AskUserQuestion `header` is capped at 12
# chars. The known set is {audit-fail, ac-eval, ship-review, ship-ci,
# eval-dry, tkt-quality}; anything else triggers an
# `[ASK-GUARD] unknown-header=<value>` stderr line for operator visibility
# and defaults to deny (matches matrix).
#
# Note: hook is mounted under matcher "AskUserQuestion" in hooks.json.
# It is a single-purpose hook with no ordering dependency on its sibling
# hooks; if a second hook is later registered under the same matcher,
# split it into a separate top-level entry per CLAUDE.md ## Hooks
# (`hooks.json: ordering-dependent hooks MUST be top-level entries`).
#
# ASCII only.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/parse-state-file.sh
source "$SCRIPT_DIR/lib/parse-state-file.sh"

emit_allow() {
  jq -c -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow"}}'
  exit 0
}

emit_deny() {
  local reason="$1"
  jq -c -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Read and parse the harness payload.
INPUT=$(cat 2>/dev/null || echo '{}')
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
HEADER=$(printf '%s' "$INPUT" | jq -r '.tool_input.header // ""' 2>/dev/null || true)

# AskUserQuestion stores `header` inside each question object under
# `tool_input.questions[]`. The harness payload shape used by tests and
# real calls is to put a single header at the top level for matcher
# routing; we also probe `.tool_input.questions[0].header` as a fallback
# so a SKILL that lists multiple questions still surfaces the leading
# header for matrix lookup.
if [ -z "$HEADER" ]; then
  HEADER=$(printf '%s' "$INPUT" | jq -r '.tool_input.questions[0].header // ""' 2>/dev/null || true)
fi

# Matcher safety-net: the hooks.json matcher is already "AskUserQuestion".
if [ "$TOOL_NAME" != "AskUserQuestion" ]; then
  emit_allow
fi

# Kill-switch resolution. `on` and `metric-only` continue into the matrix;
# `off` and any unknown value collapse to silent allow (NAC-4: unknown
# strings deliberately fail-open to avoid runaway denies from a typo).
MODE="${SW_AUTOPILOT_ASK_GUARD:-on}"
case "$MODE" in
  on|metric-only) ;;
  off|*)
    emit_allow
    ;;
esac

# cwd switch so is_autopilot_context walks the right tree.
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD" || true
fi

# Detection gate 1: must be inside an autopilot tree.
if ! is_autopilot_context; then
  emit_allow
fi

# Detection gate 2: autopilot-state.yaml must exist + parse_ticket_statuses
# must return at least one non-terminal status.
STATE_FILE_PATH="$(find_any_autopilot_state_file 2>/dev/null || true)"
if [ -z "$STATE_FILE_PATH" ] || [ ! -f "$STATE_FILE_PATH" ]; then
  emit_allow
fi

non_terminal=0
while IFS= read -r status_line; do
  [ -z "$status_line" ] && continue
  case "$status_line" in
    completed|failed|skipped) ;;
    *) non_terminal=$((non_terminal + 1)) ;;
  esac
done < <(parse_ticket_statuses "$STATE_FILE_PATH" 2>/dev/null || true)

if [ "$non_terminal" -eq 0 ]; then
  emit_allow
fi

# All detection gates passed -> resolve tier and apply matrix.
STATE_DIR="$(dirname "$STATE_FILE_PATH")"
TIER="$(get_risk_tolerance "$STATE_DIR")"

# unknown-header operator visibility (deny still applies via matrix
# default; this log is the trigger for keeping prose/test/hook in sync
# when a new gate header is introduced).
case "$HEADER" in
  audit-fail|ac-eval|ship-review|ship-ci|eval-dry|tkt-quality) ;;
  *)
    echo "[ASK-GUARD] unknown-header=${HEADER}" >&2
    ;;
esac

# Decision matrix (3 tiers x 6 known headers + 1 catch-all). Single
# source of truth shared verbatim with P0-3A SKILL prose; the meta grep
# assertion in tests/test-skill-contracts.sh enforces parity.
decision="deny"
case "$TIER" in
  aggressive) decision="deny" ;;
  moderate)
    case "$HEADER" in
      audit-fail|ac-eval) decision="allow" ;;
      *) decision="deny" ;;
    esac
    ;;
  conservative)
    case "$HEADER" in
      audit-fail|ac-eval|ship-review|ship-ci|eval-dry|tkt-quality)
        decision="allow"
        ;;
      *) decision="deny" ;;
    esac
    ;;
  *) decision="deny" ;;
esac

if [ "$decision" = "allow" ]; then
  emit_allow
fi

# Compose the per-tier allow-list literal for the reason text.
case "$TIER" in
  aggressive)   allow_list="{} (aggressive denies every header)" ;;
  moderate)     allow_list="{audit-fail, ac-eval}" ;;
  conservative) allow_list="{audit-fail, ac-eval, ship-review, ship-ci, eval-dry, tkt-quality}" ;;
  *)            allow_list="{} (unknown tier collapses to deny)" ;;
esac

REASON="autopilot non-interactive contract: risk_tolerance=${TIER}, header='${HEADER}' is not in ${TIER} allow-list ${allow_list}. Allowed paths: (1) write to state file and exit via policy_gate_stop, (2) wait for /compact ticket boundary, (3) raise risk_tolerance to conservative in autopilot-policy.yaml."

if [ "$MODE" = "metric-only" ]; then
  echo "[ASK-GUARD] metric-only: would deny tier=${TIER} header=${HEADER} state=${STATE_FILE_PATH}" >&2
  emit_allow
fi

emit_deny "$REASON"
