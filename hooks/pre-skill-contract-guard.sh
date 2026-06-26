#!/usr/bin/env bash
# pre-skill-contract-guard.sh -- PreToolUse:Skill hook (FIX-2, v9.0.1) that
# blocks a review/evaluator subagent from invoking a pipeline orchestrator
# Skill (/impl, /audit, /ship, /autopilot, /refactor). A verdict actor that
# re-enters the pipeline it is grading contaminates pipeline state and is the
# generator->evaluator->audit firewall breach observed in dogfood62
# (a doc-verifier-class subagent issuing /impl).
#
# Identity mechanism (S2-validated, decisive). The PreToolUse payload natively
# carries `.agent_type`: a subagent tool call -> agent_type = the agent name
# (possibly namespaced as `simple-workflow:<name>`); an orchestrator /
# main-loop tool call -> agent_type ABSENT/null. The unconditional prefix
# strip normalizes BOTH the bare and namespaced forms. An EMPTY result (no
# agent_type) == the orchestrator == ALLOW (fail-open-on-empty). This is the
# sole mechanism: S3 FAIL means the per-agent `tools:` allowlist does NOT
# enforce Skill / Bash-subcommand granularity, so a tool-scoping carve-out
# cannot close the Skill vector.
#
# GOVERNANCE (B) harness-own: the REVIEW_AGENTS denylist gates the
# review/evaluator ROLE (a property of the agent's job), NOT a named product /
# language / domain. CT-DECONTAM-1 / a reviewer MUST read these agent names as
# harness-own role identities, not product cues. This guard governs the
# plugin's own orchestration engine (the Skill / Agent machinery), not the
# user's product.
#
# Public contract (hook input / output):
#   stdin:  JSON payload provided by the Claude Code harness, e.g.
#           {"tool_name":"Skill","tool_input":{"skill":"simple-workflow:impl"},
#            "agent_type":"doc-verifier", "cwd":"...", ...}
#   stdout: empty when allowed; otherwise a single JSON object with shape
#           {"decision":"block","reason":"<text>"}.
#   exit:   ALWAYS 0 (fail-open -- a block is conveyed via the JSON decision
#           field, never via a non-zero exit). jq-absent is a silent exit 0.
#
# Kill switch: SW_REVIEW_FIREWALL_MODE (shared with pre-bash-contract-guard.sh
# Detection 2 (B)). Values: on (emit decision:block), metric-only (default --
# log `[REVIEW-FIREWALL] metric-only: would deny ...` to stderr and ALLOW),
# off (skip). Unknown values collapse to metric-only (safe downgrade).
#
# ASCII only (no non-ASCII characters in this script).

set -uo pipefail

# jq is a documented hard dependency; without it the payload cannot be parsed.
# Silent exit 0 -- this hook must NEVER block a Skill call on internal failure.
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/hooks"
# shellcheck source=lib/parse-state-file.sh
source "$REPO_HOOKS_DIR/lib/parse-state-file.sh"  # hooks/lib/parse-state-file.sh

INPUT=$(cat)
SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)

# Identity extraction + UNCONDITIONAL prefix strip (handles bare AND namespaced).
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)
AGENT_TYPE="${AGENT_TYPE#simple-workflow:}"

# Empty skill or empty identity (orchestrator / main-loop) -> allow.
if [ -z "$SKILL" ] || [ -z "$AGENT_TYPE" ]; then
  exit 0
fi

# Switch to the harness-provided cwd so is_autopilot_context walks the correct
# tree. Fall back to the existing PWD when the field is missing.
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD" || true
fi

# Outside an autopilot context the hook is a no-op.
if ! is_autopilot_context; then
  exit 0
fi

# Emit a `decision: block` JSON object on stdout, then exit 0 (fail-open).
emit_block() {
  local kind="$1"
  local detail="$2"
  jq -nc \
    --arg reason "$kind: $detail" \
    '{decision:"block", reason:$reason}'
  exit 0
}

# Pipeline orchestrator skills are NAMESPACED in `.tool_input.skill` -- a bare
# `impl` will not match the live value (precedent:
# pre-next-scout-auto-compact.sh matches `simple-workflow:scout`).
PIPELINE_SKILLS=("simple-workflow:impl" "simple-workflow:audit" "simple-workflow:ship" "simple-workflow:autopilot" "simple-workflow:refactor")

# Skill-bearing review/evaluator agents. security-scanner / ticket-evaluator do
# NOT carry the Skill tool, so Skill-deny is N/A for them (their phase-advance
# Write vector is covered by FIX-3 Detection 4 instead).
REVIEW_AGENTS=("ac-evaluator" "ac-evaluator-hi" "doc-verifier" "code-reviewer")

REVIEW_FIREWALL_MODE="${SW_REVIEW_FIREWALL_MODE:-metric-only}"
if [ "$REVIEW_FIREWALL_MODE" = "off" ]; then
  exit 0
fi

_is_review_agent=false
for a in "${REVIEW_AGENTS[@]}"; do
  if [ "$AGENT_TYPE" = "$a" ]; then
    _is_review_agent=true
    break
  fi
done

_is_pipeline_skill=false
for s in "${PIPELINE_SKILLS[@]}"; do
  if [ "$SKILL" = "$s" ]; then
    _is_pipeline_skill=true
    break
  fi
done

if [ "$_is_review_agent" = true ] && [ "$_is_pipeline_skill" = true ]; then
  case "$REVIEW_FIREWALL_MODE" in
    on)
      emit_block "unauthorized_pipeline_skill_by_review_agent" \
        "A review/evaluator agent ('$AGENT_TYPE') may not invoke a pipeline orchestrator Skill ('$SKILL'). Pipeline skills (/impl, /audit, /ship, /autopilot, /refactor) are owned by the parent thread; a verdict actor re-entering the pipeline it grades contaminates pipeline state. See skills/autopilot/SKILL.md." ;;
    metric-only|*)
      printf '[REVIEW-FIREWALL] metric-only: would deny unauthorized_pipeline_skill_by_review_agent (agent=%s skill=%s)\n' "$AGENT_TYPE" "$SKILL" >&2 ;;
  esac
fi

# All checks passed -> allow.
exit 0
