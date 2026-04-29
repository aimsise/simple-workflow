#!/usr/bin/env bash
# post-skill-cleanup.sh — PostToolUse hook: physical defense-in-depth for
# the /autopilot Phase 1 step 0 "Auto-kick cleanup" MUST clause.
#
# When the model invokes the `simple-workflow:autopilot` Skill, the SKILL.md
# contract requires it to delete any stale `auto-kick.yaml` left over by the
# /brief → /create-ticket → /autopilot auto-chain. The model can skip this
# clause; this hook physically removes the file regardless of what the model
# did, so the contract is preserved by the harness rather than only by the
# model.
#
# Behavior:
#   - reads stdin JSON (PostToolUse payload), extracts tool_input.skill
#   - if skill name matches simple-workflow:autopilot, removes every
#     auto-kick.yaml found under .simple-workflow/backlog/briefs/active/
#     (depth-agnostic, mirroring hooks/autopilot-continue.sh discovery)
#   - logs every removal to stderr; stdout stays empty (PostToolUse stdout
#     can flow back to the model, so we keep it clean)
#   - idempotent: missing file is not an error
#   - scope-locked: only auto-kick.yaml is touched

set -euo pipefail

# Read stdin JSON payload (may be empty).
INPUT=$(cat 2>/dev/null || echo '{}')

# Extract the skill name. jq returning empty / non-zero MUST NOT abort the hook.
SKILL_NAME=""
if command -v jq >/dev/null 2>&1; then
  SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")
fi

case "$SKILL_NAME" in
  "simple-workflow:autopilot")
    if [ -d .simple-workflow/backlog/briefs/active ]; then
      while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && rm -f "$f" && \
          echo "[POST-SKILL] removed stale auto-kick.yaml: $f" >&2
      done < <(find .simple-workflow/backlog/briefs/active -type f -name 'auto-kick.yaml' 2>/dev/null | sort -u)
    fi
    ;;
  *)
    # Non-autopilot Skill invocations are no-ops.
    :
    ;;
esac

exit 0
