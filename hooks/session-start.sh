#!/usr/bin/env bash
set -euo pipefail
cat > /dev/null  # consume stdin

# --- Cleanup old session logs (30+ days) ---
if [ -d ".docs/compact-state" ]; then
  find .docs/compact-state -name "compact-state-*.md" -mtime +30 -delete 2>/dev/null || true
fi
if [ -d ".docs/session-log" ]; then
  find .docs/session-log -name "session-log-*.md" -mtime +30 -delete 2>/dev/null || true
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
CHANGED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')

CONTEXT="Branch: ${BRANCH} | Changed files: ${CHANGED}"

# Output as additionalContext JSON
jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
