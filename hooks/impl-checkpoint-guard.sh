#!/usr/bin/env bash
# impl-checkpoint-guard.sh — Stop hook: prevent premature end_turn after
# /audit's structured block emit, before /impl Step 18 + Phase 3 finalize.
#
# Failure mode (recurring): when /impl invokes /audit via the Skill tool,
# the agent emits /audit's structured block (`**Status**: ... **Reports**:
# ...`) and immediately ends the turn — skipping /impl Step 18 (Combined
# Decision) and Phase 3 (`## [SW-CHECKPOINT]` emit, `phases.impl.status:
# completed`). This hook is the harness-side last-resort backstop; the
# prompt-side first-line defense lives in audit/SKILL.md Step 4-bis and
# impl/SKILL.md Step 17.
#
# Block when ALL of:
#   (a) transcript tail (50 lines) contains both `**Status**:` AND
#       `**Reports**:` literals (audit-block-pattern.sh)
#   (b) phases.impl.next_action ∉ {null, "", proceed-to-phase-3, stop-critical}
#       (denylist; fail-closed on unknown values)
#   (c) phases.impl.status != completed
#   (d) `## [SW-CHECKPOINT]` is NOT present in the recent assistant turn
#   (e) transcript contains a `Skill(name=simple-workflow:impl)` invocation
#       (cross-session staleness guard)
#
# Kill switch (default `block`):
#   SW_IMPL_CHECKPOINT_MODE=block        — return decision:"block" up to 3x
#   SW_IMPL_CHECKPOINT_MODE=metric-only  — record metric only, never block
#   SW_IMPL_CHECKPOINT_MODE=off          — record `phasegate_disabled` and exit;
#                                           CI / debug only — never production.
#
# Loop guard: counter at /tmp/.impl-checkpoint-${SESSION_ID}; release at 3.
# Release stdout pattern: `[IMPL-CHECKPOINT-RELEASE] ... Resume with: /impl
# <plan-path>` outside autopilot context, or `... Resume with: /autopilot
# <parent-slug>` inside autopilot context (mirrors autopilot-continue.sh:295).
#
# Stop chain order (registered in hooks/hooks.json): impl-checkpoint-guard.sh
# runs BEFORE autopilot-continue.sh. Both hooks evaluate INDEPENDENTLY in
# /autopilot context — this hook does NOT short-circuit on
# `is_autopilot_context()` for the block decision (only for the release UX
# branch). Counter file is independent of autopilot-continue.sh's
# `/tmp/.autopilot-continue-${SESSION_ID}`. The asymmetric release threshold
# (impl-checkpoint at 3, autopilot at 5+ FILE_COUNT) is intentional: the
# point-pinpoint detection here catches post-/audit handoff failures while
# autopilot-continue.sh preserves the broader phase-level loop guard.
# Cumulative max attempts before pipeline halt in autopilot context: ~8.
# (See addendum §13.A-3 for the design rationale.)

set -euo pipefail

INPUT=$(cat 2>/dev/null || echo '{}')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/audit-block-pattern.sh
source "$SCRIPT_DIR/lib/audit-block-pattern.sh"
# shellcheck source=hooks/lib/parse-state-file.sh
source "$SCRIPT_DIR/lib/parse-state-file.sh"
# shellcheck source=hooks/lib/jsonl-tail-audit.sh
source "$SCRIPT_DIR/lib/jsonl-tail-audit.sh"
# shellcheck source=hooks/lib/runtime-metrics.sh
source "$SCRIPT_DIR/lib/runtime-metrics.sh"
# shellcheck source=hooks/lib/detect-policy-gate-stop.sh
# `last_turn_declares_policy_gate_stop` — single source of truth for the
# model-declared policy-gate-stop marker (AC-6). Honoured below, right
# before the decision:block emit.
source "$SCRIPT_DIR/lib/detect-policy-gate-stop.sh"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

# --- Step 0: parallel-mode resolution (T-005) ------------------------------
# Net-new event-aware machinery for parallel autopilot. Under parallel_mode=on,
# /impl runs inside the ticket-executor, so the /audit block + Skill signature
# land in the EXECUTOR's transcript, delivered to THIS hook on the executor's
# SubagentStop event — NOT on the main Stop. The dual-event design mirrors
# scout-checkpoint-guard.sh (Modifications-rule peer symmetry):
#   - SubagentStop (parallel)         -> enforce on the executor transcript.
#   - Stop / missing event (parallel) -> stand down (the main Stop never sees
#                                        the executor signal).
#
# This block resolves the mode + the orchestrator-written main_checkout_root
# (T-003) BEFORE Step 1, because Step 1 HARD-REQUIRES phase-state.yaml and
# silent-exits when it is absent. Under a worktree the phase-state lives at
# the main-checkout path, so the main_checkout_root preference is what keeps
# impl's SubagentStop enforcement (and the main-Stop stand-down log) alive in
# a worktree — without it, Step 1 would exit before the Step 2b branch.
#
# CRITICAL byte-identity invariant: when parallel_mode is absent/off this is
# inert — PARALLEL_MODE resolves to `off`, PSF_START_DIR stays empty (Step 1
# uses the default $PWD ancestor-walk), the Step 2b `!= off` guards are false,
# and the hook behaves EXACTLY as before. The mode resolves via the shared
# resolve_parallel_mode (T-003): SW_PARALLEL_HOOKS_MODE env > the autopilot
# state's parallel_mode: scalar > off; a missing state file -> off.
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
# A missing/empty hook_event_name is treated as "Stop" (the safe direction:
# fail toward standing-down on the main transcript under parallel).
[ -n "$HOOK_EVENT" ] || HOOK_EVENT="Stop"

PARALLEL_STATE_FILE=$(find_any_autopilot_state_file 2>/dev/null || true)
PARALLEL_MODE=$(resolve_parallel_mode "${PARALLEL_STATE_FILE:-}")

# Prefer the orchestrator-written main_checkout_root over the _psf_repo_root
# ancestor-walk for phase-state resolution under parallel. Gated behind
# `!= off` so the off path is byte-identical (PSF_START_DIR empty).
PSF_START_DIR=""
if [ "$PARALLEL_MODE" != "off" ] \
   && [ -n "${PARALLEL_STATE_FILE:-}" ] && [ -f "$PARALLEL_STATE_FILE" ]; then
  MAIN_CHECKOUT_ROOT=$(parse_yaml_scalar "$PARALLEL_STATE_FILE" main_checkout_root 2>/dev/null || true)
  if [ -n "${MAIN_CHECKOUT_ROOT:-}" ] && [ -d "$MAIN_CHECKOUT_ROOT" ]; then
    PSF_START_DIR="$MAIN_CHECKOUT_ROOT"
  fi
fi

# --- Step 1: phase-state.yaml not found → silent exit ---
if [ -n "$PSF_START_DIR" ]; then
  STATE_FILE=$(find_phase_state_file "$PSF_START_DIR" 2>/dev/null || true)
  # Observability (dogfood63 AC-8 owed): the main_checkout_root resolution is
  # invisible in subagent transcripts (they do not capture hook stderr), so emit
  # a behaviour-neutral marker that makes the resolution unit-testable.
  echo "[IMPL-CHECKPOINT] main_checkout_root resolution: root=$PSF_START_DIR phase-state=${STATE_FILE:-none}" >&2
else
  STATE_FILE=$(find_phase_state_file 2>/dev/null || true)
fi
if [ -z "${STATE_FILE:-}" ] || [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# --- Helpers ---

_runtime_metrics_payload_field() {
  local field="$1"
  local payload="$INPUT"
  [ -n "$payload" ] || payload='{}'
  local value
  value=$(printf '%s' "$payload" | jq -r --arg f "$field" '.[$f] // "null"' 2>/dev/null) || value="null"
  if [ -z "$value" ] || [ "$value" = "null" ]; then printf 'null'; else printf '%s' "$value"; fi
}

_emit_metrics() {
  local stop_reason="$1"
  local consecutive="${2:-null}"
  [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ] || return 0
  local timestamp cache_creation cache_read input_tokens
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  cache_creation=$(_runtime_metrics_payload_field cache_creation_input_tokens)
  cache_read=$(_runtime_metrics_payload_field cache_read_input_tokens)
  input_tokens=$(_runtime_metrics_payload_field input_tokens)
  append_runtime_metrics_entry "$STATE_FILE" "session_end" "$stop_reason" "$timestamp" \
    "$cache_creation" "$cache_read" "$input_tokens" "$consecutive"
}

# Patch 2: inline `get_plan_path` (3-tier fallback) — phases.scout.artifacts.plan.
# Kept local to this hook to avoid bloating parse-state-file.sh with a single-
# caller helper.
get_plan_path() {
  local file="$1"
  [ -n "$file" ] && [ -f "$file" ] || return 1

  if command -v yq >/dev/null 2>&1; then
    local out
    out="$(yq -r '.phases.scout.artifacts.plan // ""' "$file" 2>/dev/null || true)"
    [ "$out" = "null" ] && out=""
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    return 1
  fi

  # Tier 2: python3 + PyYAML — gate on PyYAML availability so macOS's
  # bundled /usr/bin/python3 (no PyYAML) does NOT short-circuit here and
  # bypass the awk tier with a silent failure.
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    local out
    out=$(python3 - "$file" <<'PY' 2>/dev/null
import sys
import yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
phases = doc.get("phases") or {}
scout = phases.get("scout") or {}
artifacts = scout.get("artifacts") or {}
val = artifacts.get("plan") or ""
print(val)
PY
)
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    return 1
  fi

  # awk fallback: walk phases -> scout -> artifacts -> plan. POSIX awk only;
  # uses `sub()` strip-by-prefix instead of the gawk-specific 3-arg
  # `match(s, re, arr)` so macOS's stock BSD awk handles this tier. Indent
  # is anchored at exactly 2 / 4 / 6 spaces (canonical yq output) so the
  # phase-key matcher does not falsely promote `    artifacts:` to phase
  # status.
  local out
  out=$(awk '
    BEGIN { in_phases = 0; in_scout = 0; in_artifacts = 0 }
    /^phases:[[:space:]]*$/ { in_phases = 1; next }
    in_phases && /^[^[:space:]]/ { in_phases = 0; in_scout = 0; in_artifacts = 0 }
    in_phases && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      name = $0
      sub(/^  /, "", name)
      sub(/:[[:space:]]*$/, "", name)
      in_scout = (name == "scout") ? 1 : 0
      in_artifacts = 0
      next
    }
    in_scout && /^    artifacts:[[:space:]]*$/ {
      in_artifacts = 1
      next
    }
    in_scout && in_artifacts && /^      plan:[[:space:]]*/ {
      val = $0
      sub(/^      plan:[[:space:]]*/, "", val)
      gsub(/^"|"$/, "", val)
      gsub(/^'\''|'\''$/, "", val)
      sub(/[[:space:]]+#.*$/, "", val)
      if (val == "null" || val == "~") val = ""
      print val
      exit 0
    }
  ' "$file" 2>/dev/null || true)
  [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  return 1
}

# Patch 3: discover the autopilot parent-slug for the Resume command. The
# slug is the path between `briefs/active/` (or `product_backlog/`) and
# `/autopilot-state.yaml` — possibly nested for split runs.
#
# Two-pass search:
#   1. Walk upward from $PWD; if any ancestor sits directly under
#      `<root>/.simple-workflow/backlog/(briefs/active|product_backlog)/`
#      AND contains an `autopilot-state.yaml`, prefer that slug. This
#      pins the suggestion to the autopilot run the user is actually
#      working in (worktree pattern), not whichever lex-first run lives
#      under briefs/active/.
#   2. Fall back to the mtime-newest candidate so concurrent autopilot
#      runs do not silently mis-attribute via lex order.
get_autopilot_parent_slug() {
  local root
  root="$(_psf_repo_root "$PWD" 2>/dev/null || echo "$PWD")"

  # Pass 1: $PWD ancestor walk-up.
  local dir="$PWD"
  local active_root_briefs="$root/.simple-workflow/backlog/briefs/active"
  local active_root_pb="$root/.simple-workflow/backlog/product_backlog"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    local parent
    parent="$(dirname "$dir")"
    if [ "$parent" = "$active_root_briefs" ] || [ "$parent" = "$active_root_pb" ]; then
      if [ -f "$dir/autopilot-state.yaml" ]; then
        basename "$dir"
        return 0
      fi
    fi
    [ "$dir" = "$root" ] && break
    dir="$parent"
  done

  # Pass 2: mtime-newest across both roots.
  local newest=""
  for sub in "briefs/active" "product_backlog"; do
    [ -d "$root/.simple-workflow/backlog/$sub" ] || continue
    while IFS= read -r _f; do
      [ -f "$_f" ] || continue
      if [ -z "$newest" ] || [ "$_f" -nt "$newest" ]; then
        newest="$_f"
      fi
    done < <(find "$root/.simple-workflow/backlog/$sub" -name 'autopilot-state.yaml' -type f 2>/dev/null)
    unset _f
  done

  if [ -n "$newest" ]; then
    printf '%s\n' "$newest" | sed -E 's|^.*/(briefs/active\|product_backlog)/||; s|/autopilot-state.yaml$||'
    return 0
  fi
  return 1
}

# --- Step 2: kill switch ---
MODE="${SW_IMPL_CHECKPOINT_MODE:-block}"
case "$MODE" in
  off)
    _emit_metrics "phasegate_disabled"
    exit 0
    ;;
  metric-only|block)
    : # continue
    ;;
  *)
    # Unknown value: fail-closed to block (default behaviour).
    MODE=block
    ;;
esac

# --- Step 2b: parallel-mode event branch (T-005) ---------------------------
# Symmetric to scout-checkpoint-guard.sh Step 2b (Modifications-rule peer
# uniformity). PARALLEL_MODE / HOOK_EVENT were resolved in Step 0 above (they
# had to precede Step 1's hard phase-state requirement). Here the actual
# event branch runs, after the kill switch (Step 2) so SW_IMPL_CHECKPOINT_MODE
# still wins. Fully inert under parallel_mode=off (byte-identical).
if [ "$PARALLEL_MODE" != "off" ]; then
  if [ "$HOOK_EVENT" != "SubagentStop" ]; then
    # Main Stop (or missing event) under parallel: stand down.
    if [ "$PARALLEL_MODE" = "metric-only" ]; then
      echo "[IMPL-CHECKPOINT] parallel stand-down (metric-only): would stand down on main Stop (hook_event=$HOOK_EVENT, parallel_mode=$PARALLEL_MODE); falling through to the serial path." >&2
      # metric-only: fall through to the existing serial logic below.
    else
      echo "[IMPL-CHECKPOINT] parallel stand-down: enforcement is relocated to the executor SubagentStop under parallel_mode=on (hook_event=$HOOK_EVENT); the main Stop does not see the executor signal." >&2
      exit 0
    fi
  else
    # SubagentStop under parallel: enforce on the executor transcript. Cheap
    # no-op on unrelated subagent stops (R-SUBSTOP-SERIAL) before any further
    # I/O. (The main_checkout_root phase-state preference already ran in
    # Step 0 so Step 1 resolved phase-state from the main checkout.)
    is_autopilot_context || exit 0
  fi
fi

# --- Step 3: phases.impl.status == completed → silent exit ---
IMPL_STATUS=$(parse_phase_status "$STATE_FILE" "impl" 2>/dev/null || echo "")
if [ "$IMPL_STATUS" = "completed" ]; then
  exit 0
fi

# Compute COUNTER_FILE up-front so the SW-CHECKPOINT-seen branch (below)
# can clean it on the prompt-side success path. Without this cleanup, a
# session that emitted SW-CHECKPOINT after N false-blocks would carry the
# stale counter into a subsequent re-entry of the same SESSION_ID and
# release on the next match (instead of giving a fresh 3-attempt budget).
COUNTER_FILE="/tmp/.impl-checkpoint-${SESSION_ID}"

# --- Step 4: ## [SW-CHECKPOINT] in recent assistant turn → silent exit ---
# The grep is anchored on either `"text":"## [SW-CHECKPOINT]` (start of a
# JSON-encoded text block) or `\n## [SW-CHECKPOINT]` (mid-text after a
# JSON-escaped newline). This excludes backtick-quoted prose mentions
# (e.g. instructions in audit/SKILL.md or audit Summary text saying
# "emit `## [SW-CHECKPOINT]` next") which would otherwise trigger a
# false positive lag-tolerance exit.
SW_CHECKPOINT_SEEN="false"
TAIL_50=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  TAIL_50=$(tail -n 50 "$TRANSCRIPT_PATH" 2>/dev/null || echo "")
  if printf '%s\n' "$TAIL_50" | grep -qE '("text":"|\\n)## \[SW-CHECKPOINT\]'; then
    SW_CHECKPOINT_SEEN="true"
  fi
fi

if [ "$SW_CHECKPOINT_SEEN" = "true" ]; then
  # Positive observation: prompt-side AuditTail completed Phase 3. Record
  # `audit_handoff_via_prompt` only when an audit block AND a /impl Skill
  # invocation are also visible — otherwise a pre-existing SW-CHECKPOINT
  # in the tail would inflate the SLO denominator on unrelated turns.
  if [ -n "$TAIL_50" ] \
     && printf '%s\n' "$TAIL_50" | grep -qE -- "$AUDIT_BLOCK_PATTERN_STATUS" \
     && printf '%s\n' "$TAIL_50" | grep -qE -- "$AUDIT_BLOCK_PATTERN_REPORTS" \
     && transcript_contains_skill_invocation "simple-workflow:impl" "$TRANSCRIPT_PATH"; then
    _emit_metrics "audit_handoff_via_prompt"
  fi
  # H6: clean the counter on the prompt-side success path so a stale
  # value cannot leak into a future re-entry under the same SESSION_ID.
  rm -f "$COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- Step 5: next_action denylist ---
NEXT_ACTION=$(parse_impl_next_action "$STATE_FILE" 2>/dev/null || echo "")
case "$NEXT_ACTION" in
  ""|"null"|"proceed-to-phase-3"|"stop-critical")
    exit 0
    ;;
esac

# --- Step 6: transcript tail must contain Status AND Reports literals ---
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] || [ -z "$TAIL_50" ]; then
  exit 0
fi
if ! printf '%s\n' "$TAIL_50" | grep -qE -- "$AUDIT_BLOCK_PATTERN_STATUS"; then
  exit 0
fi
if ! printf '%s\n' "$TAIL_50" | grep -qE -- "$AUDIT_BLOCK_PATTERN_REPORTS"; then
  exit 0
fi

# --- Step 7: cross-session guard ---
if ! transcript_contains_skill_invocation "simple-workflow:impl" "$TRANSCRIPT_PATH"; then
  exit 0
fi

# --- 5-AND met. Counter management (COUNTER_FILE was defined above for
# the SW-CHECKPOINT cleanup branch). ---
BLOCK_COUNT=0
if [ "$SESSION_ID" != "unknown" ] && [ -f "$COUNTER_FILE" ]; then
  BLOCK_COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  case "$BLOCK_COUNT" in *[!0-9]*|"") BLOCK_COUNT=0 ;; esac
  # Reset on state-file progress (mirrors autopilot-continue.sh).
  if [ "$STATE_FILE" -nt "$COUNTER_FILE" ]; then
    BLOCK_COUNT=0
  fi
fi

# --- metric-only mode: record observation, never block ---
if [ "$MODE" = "metric-only" ]; then
  _emit_metrics "premature_audit_handoff_blocked" "$BLOCK_COUNT"
  exit 0
fi

# --- block mode: release at 3 ---
if [ "$BLOCK_COUNT" -ge 3 ] 2>/dev/null; then
  if is_autopilot_context; then
    PARENT_SLUG=$(get_autopilot_parent_slug 2>/dev/null || echo "")
    if [ -z "$PARENT_SLUG" ]; then
      PARENT_SLUG="<parent-slug>"
    fi
    echo "[IMPL-CHECKPOINT-RELEASE] Pipeline halted: 3 consecutive end_turn attempts after /audit. Resume with: /autopilot ${PARENT_SLUG}"
  else
    PLAN_PATH=$(get_plan_path "$STATE_FILE" 2>/dev/null || true)
    if [ -n "${PLAN_PATH:-}" ]; then
      echo "[IMPL-CHECKPOINT-RELEASE] Pipeline halted: 3 consecutive end_turn attempts after /audit. Resume with: /impl ${PLAN_PATH}"
    else
      echo "[IMPL-CHECKPOINT-RELEASE] Pipeline halted: 3 consecutive end_turn attempts after /audit. Resume with: /impl <path-to-plan.md> (auto-detect failed; specify manually)"
    fi
  fi
  echo "[IMPL-CHECKPOINT-RELEASE] release after $BLOCK_COUNT blocks" >&2
  _emit_metrics "phasegate_released_after_N_blocks" "$BLOCK_COUNT"
  rm -f "$COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- Policy-gate-stop honour gate (SW_AUTOPILOT_POLICY_STOP_HONOR) ---
# When the orchestrator model legitimately hard-stops it emits the marker
# `[AUTOPILOT-POLICY] gate=<name> action=stop reason=<...>` in its last
# assistant turn (mandated by skills/autopilot/SKILL.md). A Stop is blocked
# if ANY of the three autopilot Stop hooks blocks, so this hook must honour
# the declaration too. On honour: clear THIS hook's counter and exit 0
# without blocking. runtime_metrics is intentionally NOT written here — the
# session_end / policy_gate_stop entry is autopilot-continue.sh's job (it
# owns the runtime_metrics axis); this hook only stands down.
#
# PURELY ADDITIVE: sits right before the decision:block emit. With the kill
# switch off OR no marker present, the existing 3-counter block behaviour is
# unchanged. Same tri-value kill switch as the other two Stop hooks:
#   on (default)  — honour: clear counter, exit 0 (no block).
#   metric-only   — detect + log `[POLICY-GATE-STOP]` (would honour) but
#                   STILL block.
#   off / unknown — ignore (block as before); unknown fails closed here.
POLICY_STOP_HONOR="${SW_AUTOPILOT_POLICY_STOP_HONOR:-on}"
case "$POLICY_STOP_HONOR" in
  on)
    if last_turn_declares_policy_gate_stop "$TRANSCRIPT_PATH"; then
      echo "[POLICY-GATE-STOP] honouring model-declared policy_gate_stop (last assistant turn emitted [AUTOPILOT-POLICY] ... action=stop); standing down without blocking." >&2
      rm -f "$COUNTER_FILE" 2>/dev/null || true
      exit 0
    fi
    ;;
  metric-only)
    if last_turn_declares_policy_gate_stop "$TRANSCRIPT_PATH"; then
      echo "[POLICY-GATE-STOP] metric-only: would honour model-declared policy_gate_stop; still blocking per SW_AUTOPILOT_POLICY_STOP_HONOR=metric-only." >&2
    fi
    ;;
  *)
    : # off / unknown → ignore (block as before); unknown fails closed.
    ;;
esac

# --- block: increment counter, emit decision:block, record metric ---
BLOCK_COUNT=$((BLOCK_COUNT + 1))
if [ "$SESSION_ID" != "unknown" ]; then
  echo "$BLOCK_COUNT" > "$COUNTER_FILE"
fi

_emit_metrics "premature_audit_handoff_blocked" "$BLOCK_COUNT"

jq -n \
  --arg path "$STATE_FILE" \
  --arg next_action "$NEXT_ACTION" \
  '{
    decision: "block",
    reason: ("/audit emitted its structured block (Status / Reports), but /impl Phase 3 has not finalized. Read " + $path + ", execute phases.impl.next_action (" + $next_action + ") immediately to continue through Step 18 → Phase 3 → ## [SW-CHECKPOINT]. Do NOT end your turn or summarize the audit.")
  }'
exit 0
