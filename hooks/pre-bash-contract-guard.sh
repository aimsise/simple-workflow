#!/usr/bin/env bash
# pre-bash-contract-guard.sh -- PreToolUse:Bash hook (PX-02a) that blocks
# Manual Bash Fallback contract violations at the moment a Bash tool call
# is about to fire.
#
# Companion to:
#   - hooks/lib/forbidden-rationale-patterns.sh (PX-01): single source of
#     truth for the FORBIDDEN_RATIONALE_PATTERNS array. This hook MUST NOT
#     redefine the patterns locally -- it iterates the imported array.
#   - hooks/lib/parse-state-file.sh (PX-01): provides is_autopilot_context
#     so the hook only activates when the caller is operating inside an
#     autopilot run.
#   - hooks/pre-bash-safety.sh: pre-existing destructive-command guard.
#     This hook is registered as an additional PreToolUse:Bash entry and
#     does NOT change pre-bash-safety.sh behaviour. It runs alongside it.
#
# Public contract (hook input / output):
#   stdin:  JSON payload provided by the Claude Code harness, e.g.
#           {"tool_name": "Bash", "tool_input": {"command": "..."},
#            "cwd": "/path/to/repo", "session_id": "...",
#            "transcript_path": "..."}
#   stdout: empty when the command is allowed; otherwise a single JSON
#           object with shape {"decision":"block","reason":"<text>"}.
#   exit:   0 in both allow and block paths (block is conveyed via the
#           JSON decision field). Non-zero only on internal errors that
#           prevent the hook from making a decision.
#
# Detection scope (PX-02a Acceptance Criteria #4):
#   1. autopilot context outside  -> always allow (pass-through). The hook
#      does NOT police Bash commands run outside an autopilot tree.
#   2. autopilot context inside, `git commit ...` direct invocation:
#        - Allowed when the /ship Skill has written a `.ship-commit-nonce`
#          sentinel under the active autopilot tree BEFORE its Step-3 commit
#          (skills/ship/SKILL.md Step 2.5) -- a non-forgeable file-existence
#          signal (FIX-2, v9.0.1; replaces the prior forgeable
#          `phases.ship.status: in-progress` proxy a model could write).
#        - Blocked otherwise as `unauthorized_ship_inline` (UNCONDITIONAL --
#          NOT gated by SW_REVIEW_FIREWALL_MODE; only the SIGNAL was re-keyed).
#   2b. autopilot context inside, a review/evaluator agent (`.agent_type` in
#        the FOUR Bash-bearing review agents ac-evaluator / ac-evaluator-hi /
#        doc-verifier / code-reviewer) running `git add|commit|mv|push` ->
#        `unauthorized_commit_by_review_agent`, gated by SW_REVIEW_FIREWALL_MODE
#        (default metric-only). `git worktree` is exempt. (security-scanner /
#        ticket-evaluator carry no Bash, so they have no git surface here; their
#        phase-advance Write vector is covered by pre-state-transition.sh
#        Detection 4, whose denylist holds all SIX.) The FIX-2 firewall.
#   3. autopilot context inside, append to `manual_bash_fallbacks[]` whose
#      reason text matches any FORBIDDEN_RATIONALE_PATTERNS entry:
#        - Blocked as `context_budget_fallback`. Other rationales (e.g.
#          "subagent could not handle") are allowed -- only context-pressure
#          phrasing is rejected, matching the PX-01 prose contract.
#
# Negative-AC posture:
#   - This hook does not introduce any environment-variable knob that
#     disables the guard. Recovery from a context-pressure event flows
#     through auto-compaction (PreCompact hook) or the
#     `unexpected_error.action: stop` policy gate, both documented in
#     `skills/autopilot/SKILL.md ## Context-Pressure Response Paths`.
#   - The guard has no rate or threshold concept. A single hit on a
#     forbidden rationale rejects the call.
#   - Detection scope is the textual content of the candidate command
#     (the rationale string inside a manual_bash_fallbacks list append).
#     The structured field name itself is never treated as a contract
#     breach -- legitimate subagent-failure recovery paths remain free
#     to record their rationale.
#   - Existing destructive-command handling lives in pre-bash-safety.sh
#     and is left untouched here.
#   - ASCII only (no non-ASCII characters in the script).

set -uo pipefail

# Resolve the directory this script lives in so we can locate the helper
# library regardless of how the harness invokes it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/hooks"
# shellcheck source=lib/forbidden-rationale-patterns.sh
source "$REPO_HOOKS_DIR/lib/forbidden-rationale-patterns.sh"  # hooks/lib/forbidden-rationale-patterns.sh
# shellcheck source=lib/parse-state-file.sh
source "$REPO_HOOKS_DIR/lib/parse-state-file.sh"  # hooks/lib/parse-state-file.sh

# Read and parse the harness payload. `jq -r` returns an empty string when
# the field is absent, which keeps the rest of the script in a defined
# state without requiring strict input validation.
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)

# Empty command -> nothing to evaluate.
if [ -z "$COMMAND" ]; then
  exit 0
fi

# Switch to the harness-provided cwd so is_autopilot_context walks the
# correct tree. Fall back to the existing PWD when the field is missing.
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD" || true
fi

# Outside an autopilot context the hook is a no-op (NAC #1).
if ! is_autopilot_context; then
  exit 0
fi

# Emit a `decision: block` JSON object on stdout. The harness reads this
# and rejects the Bash invocation; the textual reason is surfaced to the
# model so it can recover by routing through the proper Skill instead.
emit_block() {
  local kind="$1"
  local detail="$2"
  jq -nc \
    --arg reason "$kind: $detail" \
    '{decision:"block", reason:$reason}'
  exit 0
}

# ---------------------------------------------------------------------------
# Detection 1: manual_bash_fallbacks[] append with a forbidden rationale.
# ---------------------------------------------------------------------------
# We only inspect commands that look like they are appending to the
# `manual_bash_fallbacks` list. The textual signal is the literal token
# `manual_bash_fallbacks` somewhere in the command (yq, sed, awk, printf
# with heredoc, etc. all carry it verbatim). When that token is present we
# iterate the imported FORBIDDEN_RATIONALE_PATTERNS array and case-fold
# match the full command -- one hit suffices to reject the call.
if printf '%s' "$COMMAND" | grep -q 'manual_bash_fallbacks'; then
  for pat in "${FORBIDDEN_RATIONALE_PATTERNS[@]}"; do
    if printf '%s' "$COMMAND" | grep -iE -q "$pat"; then
      emit_block "context_budget_fallback" \
        "Manual Bash Fallback rationale matches forbidden pattern '$pat'. Context window / context budget pressure is never a valid Manual Bash Fallback rationale; route through auto-compaction or unexpected_error.action: stop instead. See skills/autopilot/SKILL.md ## Context-Pressure Response Paths."
    fi
  done
fi

# ---------------------------------------------------------------------------
# Detection 2: review/evaluator-agent git firewall + the /ship nonce gate.
# ---------------------------------------------------------------------------
# Identity extraction (S2-validated). The PreToolUse payload natively carries
# `.agent_type` when the tool call originates from a subagent (the agent name,
# possibly namespaced as `simple-workflow:<name>`); it is ABSENT/null for an
# orchestrator / main-loop call. The unconditional prefix strip below
# normalizes BOTH the bare and the namespaced forms, so a live namespaced
# value is never a silent no-op. An EMPTY result (no agent_type) == the
# orchestrator / generator == ALLOW (fail-open-on-empty is load-bearing).
#
# GOVERNANCE (B) harness-own: the REVIEW_AGENTS denylist below gates the
# review/evaluator ROLE (a property of the agent's job), NOT a named product /
# language / domain. CT-DECONTAM-1 / a reviewer MUST read these agent names as
# harness-own role identities, not product cues.
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)
AGENT_TYPE="${AGENT_TYPE#simple-workflow:}"   # UNCONDITIONAL strip -- bare AND namespaced

# (A) Nonce gate (UNCONDITIONALLY enforced -- NOT gated by SW_REVIEW_FIREWALL_MODE).
# Token-position aware match: at start, after pipe, after `;`, after `&&`
# / `||`, or inside a `$(...)` / backtick subshell. This mirrors the
# token-position regex used in pre-bash-safety.sh's destructive guard.
#
# A direct `git commit` inside an autopilot run is authorized ONLY when the
# /ship Skill has written a `.ship-commit-nonce` sentinel BEFORE its Step-3
# commit (skills/ship/SKILL.md Step 2.5). The nonce is a non-forgeable
# file-existence signal: unlike the prior `phases.ship.status: in-progress`
# proxy (which a model can write into any phase-state.yaml), the nonce is
# dropped by /ship itself immediately before the commit and removed on every
# exit path, so its presence is the closest available evidence that "Bash was
# invoked inside /ship". This re-keys the authorization SIGNAL only;
# enforcement strength is unchanged (still an unconditional block), so the
# metric-only default of the NEW (B) review-deny below MUST NOT downgrade it.
GIT_COMMIT_RE='(^|[|;&]|\$\(|`)[[:space:]]*(env[[:space:]]+|command[[:space:]]+)?git[[:space:]]+commit([[:space:]]|$)'

if printf '%s' "$COMMAND" | grep -qE "$GIT_COMMIT_RE"; then
  ROOT="$(_psf_repo_root "$PWD")"
  NONCE_PRESENT="false"
  if [ -f "$ROOT/.simple-workflow/backlog/active/.ship-commit-nonce" ]; then
    NONCE_PRESENT="true"
  elif [ -d "$ROOT/.simple-workflow/backlog/active" ]; then
    if find "$ROOT/.simple-workflow/backlog/active" \
         -mindepth 1 -maxdepth 6 -name .ship-commit-nonce -type f \
         -print 2>/dev/null | grep -q .; then
      NONCE_PRESENT="true"
    fi
  fi

  if [ "$NONCE_PRESENT" != "true" ]; then
    emit_block "unauthorized_ship_inline" \
      "Direct 'git commit' is not allowed inside an autopilot run. Route through the /ship Skill (which writes a .ship-commit-nonce before the Step-3 commit) so the artifact-presence gate, ticket-move, and PR creation stay atomic. See skills/autopilot/SKILL.md Mandatory Skill Invocations."
  fi
fi

# (B) Review-agent git-source firewall (NEW, gated by SW_REVIEW_FIREWALL_MODE,
# default metric-only). A review/evaluator subagent (ac-evaluator,
# ac-evaluator-hi, doc-verifier, code-reviewer) legitimately runs read-only git
# (`git diff/status/log/show`) and `git worktree add/remove/list` for scratch
# probes, but MUST NOT mutate history or staging: `git add`, `git commit`,
# `git mv`, `git push`. S3 FAIL means the per-agent `tools:` allowlist does not
# enforce Bash subcommand granularity, so this hook is the sole mechanism.
# CARVE-OUT: `git worktree` is NOT matched (review agents legitimately use
# `git worktree add/remove/list`).
REVIEW_FIREWALL_MODE="${SW_REVIEW_FIREWALL_MODE:-metric-only}"
if [ "$REVIEW_FIREWALL_MODE" != "off" ] && [ -n "$AGENT_TYPE" ]; then
  case "$AGENT_TYPE" in
    ac-evaluator|ac-evaluator-hi|doc-verifier|code-reviewer)
      # Match `git add|commit|mv|push` directly after `git ` (token-position
      # aware). `git worktree ...` does not match this alternation -> exempt.
      GIT_SRC_RE='(^|[|;&]|\$\(|`)[[:space:]]*(env[[:space:]]+|command[[:space:]]+)?git[[:space:]]+(add|commit|mv|push)([[:space:]]|$)'
      if printf '%s' "$COMMAND" | grep -qE "$GIT_SRC_RE"; then
        case "$REVIEW_FIREWALL_MODE" in
          on)
            emit_block "unauthorized_commit_by_review_agent" \
              "A review/evaluator agent ('$AGENT_TYPE') may not mutate git history or staging (git add / commit / mv / push). Review agents are read-only on the product source; the generator->evaluator->audit firewall forbids a verdict actor from committing the code it grades. (git worktree add/remove/list remain permitted.) See skills/autopilot/SKILL.md." ;;
          metric-only|*)
            printf '[REVIEW-FIREWALL] metric-only: would deny unauthorized_commit_by_review_agent (agent=%s): %s\n' "$AGENT_TYPE" "${COMMAND:0:140}" >&2 ;;
        esac
      fi
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Detection 3 (knob-gated, M-03 / ST-04): Bash-mediated state-file status
# mutation. The skip-transition guard (pre-state-transition.sh) is wired only
# to Write/Edit, so a model blocked there can reroute to a raw `yq -i` /
# `sed -i` / shell-redirect on autopilot-state.yaml / phase-state.yaml and flip
# a `status:` to skipped/completed unobserved (the autopilot Stop hook then
# honours the Bash-written transition as pipeline progress).
#
# This NEW deny ships OFF-by-default. It is gated by SW_BASH_STATE_GUARD_MODE so
# the behaviour change is opt-in (matches the repo's metric-only-first rollout
# convention for intrusive guards):
#   on          -> emit decision:block (deny)
#   metric-only -> (default) log `[PRE-BASH-CONTRACT-GUARD] metric-only: would
#                  deny ...` to stderr and ALLOW the call
#   off         -> skip detection 3 entirely
# Detections 1 and 2 above are NOT gated by this knob (the hook's NAC posture is
# preserved). A typo collapses to metric-only (the observe-only default).
STATE_GUARD_MODE="${SW_BASH_STATE_GUARD_MODE:-metric-only}"
if [ "$STATE_GUARD_MODE" != "off" ] \
   && printf '%s' "$COMMAND" | grep -qE '(autopilot-state|phase-state)\.yaml'; then
  _sg_mutation=false
  # `yq -i` / `sed -i` (with any flags/args before -i), or a `>` / `>>` redirect
  # whose target is a state file.
  if printf '%s' "$COMMAND" | grep -qE '(^|[|;&[:space:]])(yq|sed)([[:space:]]+[^|;&]*)?[[:space:]]-i([[:space:]]|=|$)'; then
    _sg_mutation=true
  fi
  if printf '%s' "$COMMAND" | grep -qE '>>?[[:space:]]*[^[:space:]|;&]*(autopilot-state|phase-state)\.yaml'; then
    _sg_mutation=true
  fi
  # A step/ticket status / phase being driven to a terminal/skip/advancement
  # value. The `[^[:alpha:]]{0,15}` gap tolerates `= "..."`, `: ...`,
  # `= \"...\"`, `[].`. FIX-3 (v9.0.1) widened the advancement set to mirror
  # pre-state-transition.sh's PART-A detector: `current_phase` / `overall_status`
  # field names + a bare `ship` value, closing the `current_phase: ship` gap a
  # Bash `yq -i current_phase=ship` would otherwise drive unobserved. This is
  # an advancement-SET extension only -- FIX-3 deliberately adds NO identity
  # gate here (the review/evaluator agent_type deny is FIX-2 (B)'s job on the
  # git surface and Detection 4's job on the Write/Edit surface). The existing
  # _sg_mutation gate + SW_BASH_STATE_GUARD_MODE knob are unchanged.
  _sg_transition=false
  if printf '%s' "$COMMAND" | grep -qiE '(status|steps|ship|scout|impl|create-ticket|current_phase|overall_status)[^[:alpha:]]{0,15}(skipped|completed|failed|in_progress|in-progress|ship)'; then
    _sg_transition=true
  fi
  if [ "$_sg_mutation" = true ] && [ "$_sg_transition" = true ]; then
    case "$STATE_GUARD_MODE" in
      on)
        emit_block "unauthorized_state_mutate_bash" \
          "Direct Bash mutation of a state-file status (yq -i / sed -i / redirect on autopilot-state.yaml / phase-state.yaml) bypasses the Write/Edit skip-transition guard (pre-state-transition.sh). Route state transitions through the owning Skill (/scout, /impl, /ship) or a Write/Edit so the hook-layer guards fire. Field reference: docs/state-schema.md; see also skills/autopilot/SKILL.md." ;;
      metric-only|*)
        printf '[PRE-BASH-CONTRACT-GUARD] metric-only: would deny unauthorized_state_mutate_bash (Bash state-file status mutation): %s\n' "${COMMAND:0:140}" >&2 ;;
    esac
  fi
fi

# All checks passed -> allow.
exit 0
