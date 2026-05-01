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
#        - Allowed when any per-ticket phase-state.yaml under the active
#          autopilot tree has `phases.ship.status: in_progress` (the
#          /ship Skill is the legitimate caller).
#        - Blocked otherwise as `unauthorized_ship_inline`. This is the
#          "/ship Skill bypass" path described in the ticket Implementation
#          Notes (option 4 fallback -- the hook input does not carry
#          parent_skill_id metadata, so phase status is the closest signal).
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
# Detection 2: direct `git commit` outside the /ship Skill context.
# ---------------------------------------------------------------------------
# Token-position aware match: at start, after pipe, after `;`, after `&&`
# / `||`, or inside a `$(...)` / backtick subshell. This mirrors the
# token-position regex used in pre-bash-safety.sh's destructive guard.
GIT_COMMIT_RE='(^|[|;&]|\$\(|`)[[:space:]]*(env[[:space:]]+|command[[:space:]]+)?git[[:space:]]+commit([[:space:]]|$)'

if printf '%s' "$COMMAND" | grep -qE "$GIT_COMMIT_RE"; then
  # Look for a per-ticket phase-state.yaml underneath
  # .simple-workflow/backlog/active/ that records phases.ship.status:
  # in_progress. The /ship Skill flips this status as its first step, so
  # an in_progress state is the strongest available proxy for "Bash was
  # invoked inside /ship". When no such file is found we treat the call
  # as a Skill bypass and block it.
  ROOT="$(_psf_repo_root "$PWD")"
  SHIP_IN_PROGRESS="false"
  if [ -d "$ROOT/.simple-workflow/backlog/active" ]; then
    while IFS= read -r ps_file; do
      [ -z "$ps_file" ] && continue
      status="$(parse_phase_status "$ps_file" ship 2>/dev/null || true)"
      if [ "$status" = "in_progress" ]; then
        SHIP_IN_PROGRESS="true"
        break
      fi
    done < <(find "$ROOT/.simple-workflow/backlog/active" \
               -mindepth 1 -maxdepth 6 -name phase-state.yaml \
               -print 2>/dev/null)
  fi

  if [ "$SHIP_IN_PROGRESS" != "true" ]; then
    emit_block "unauthorized_ship_inline" \
      "Direct 'git commit' is not allowed inside an autopilot run. Route through the /ship Skill (which flips phases.ship.status: in_progress) so the artifact-presence gate, ticket-move, and PR creation stay atomic. See skills/autopilot/SKILL.md Mandatory Skill Invocations."
  fi
fi

# All checks passed -> allow.
exit 0
