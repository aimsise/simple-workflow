#!/usr/bin/env bash
set -euo pipefail
cat > /dev/null  # consume stdin

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
CHANGED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')

CONTEXT="Branch: ${BRANCH} | Changed files: ${CHANGED}"

# Read active feature from project memory
MEMORY_DIR="$HOME/.claude/projects/-$(echo "$PWD" | tr '/' '-')/memory"
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  ACTIVE=$(grep -A1 "Active Feature" "$MEMORY_DIR/MEMORY.md" 2>/dev/null | tail -1 | sed 's/^- //' | head -c 200)
  [ -n "$ACTIVE" ] && CONTEXT="${CONTEXT} | Active: ${ACTIVE}"
fi

# Find latest plan document (check both .backlog/active/ and .docs/plans/)
BACKLOG_PLAN=$(ls -t .backlog/active/*/plan.md 2>/dev/null | head -1)
DOCS_PLAN=$(ls -t .docs/plans/*.md 2>/dev/null | head -1)

if [ -n "${BACKLOG_PLAN:-}" ] && [ -n "${DOCS_PLAN:-}" ]; then
  # Compare modification times, pick the newer one
  if [ "${BACKLOG_PLAN}" -nt "${DOCS_PLAN}" ]; then
    LATEST_PLAN="$BACKLOG_PLAN"
  else
    LATEST_PLAN="$DOCS_PLAN"
  fi
elif [ -n "${BACKLOG_PLAN:-}" ]; then
  LATEST_PLAN="$BACKLOG_PLAN"
elif [ -n "${DOCS_PLAN:-}" ]; then
  LATEST_PLAN="$DOCS_PLAN"
else
  LATEST_PLAN=""
fi

[ -n "${LATEST_PLAN:-}" ] && CONTEXT="${CONTEXT} | Latest Plan: ${LATEST_PLAN}"

# Output as additionalContext JSON
jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
