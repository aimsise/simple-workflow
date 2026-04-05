#!/usr/bin/env bash
set -euo pipefail
cat > /dev/null  # consume stdin

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
SAVE_FILE=".docs/reviews/compact-state-${TIMESTAMP}.md"

mkdir -p .docs/reviews

{
  echo "# Work State Before Compact"
  echo "- Date: $(date -Iseconds)"
  echo "- Branch: $BRANCH"
  echo ""
  echo "## Changed Files"
  git diff --name-only 2>/dev/null || true
  echo ""
  echo "## Git Status"
  git status --short 2>/dev/null || true
} > "$SAVE_FILE"

exit 0
