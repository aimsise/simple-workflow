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
  echo ""
  echo "## Active Tickets"
  ls .backlog/active/*/ticket.md 2>/dev/null || echo "(none)"
  echo ""
  echo "## Active Plans"
  ls .backlog/active/*/plan.md 2>/dev/null || echo "(none)"
  ls .docs/plans/*.md 2>/dev/null || echo "(none in .docs/plans/)"
  echo ""
  echo "## Evaluation State"
  ls .backlog/active/*/eval-round-*.md 2>/dev/null || echo "(none)"
  ls .backlog/active/*/quality-round-*.md 2>/dev/null || echo "(none)"
} > "$SAVE_FILE"

exit 0
