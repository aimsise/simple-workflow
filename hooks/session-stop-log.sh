#!/usr/bin/env bash
set -euo pipefail
cat > /dev/null  # consume stdin

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
LOG_FILE=".docs/reviews/session-log-${TIMESTAMP}.md"

mkdir -p .docs/reviews

{
  echo "# Session Work Log"
  echo "- Date: $(date -Iseconds)"
  echo "- Branch: $BRANCH"
  echo ""
  echo "## Final State"
  git status --short 2>/dev/null || true
  echo ""
  echo "## Recent Commits"
  git log --oneline -5 2>/dev/null || true
} > "$LOG_FILE"

exit 0
