#!/usr/bin/env bash
# pre-level1-guard.sh — Block claude -p integration test runs unless opted in
#
# Fires on every Bash tool use. If the command targets test-integration.sh or
# spike-claude-p.sh without RUN_LEVEL1_TESTS=true, the tool use is denied and
# Claude is told how to proceed.

set -euo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Match EXECUTION forms only (bash/sh/source/./ prefixes) — a read-only
# `cat`/`grep`/`sed` that merely mentions the file name must pass.
if echo "$command" | grep -qE '(^|[;&|[:space:]])((bash|sh|source|\.)[[:space:]]+[^;&|]*|\./[^;&|[:space:]]*)(test-integration|spike-claude-p)\.sh'; then
  if ! echo "$command" | grep -q 'RUN_LEVEL1_TESTS=true'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"This command runs claude -p integration tests which incur Anthropic API costs. Ask the user whether to proceed, then re-run with RUN_LEVEL1_TESTS=true prefixed to the command."}}'
    exit 0
  fi
fi

# No decision for every other command: exit 0 with no output so the normal
# permission flow applies (an explicit "allow" here would auto-approve EVERY
# Bash command in the dev repo, bypassing permission prompts).
exit 0
