#!/usr/bin/env bash
# Stop hook: log session activity to .docs/session-log/ in YAML+Markdown format

set -euo pipefail

# Consume stdin (some hook events provide JSON payload)
cat > /dev/null

LOG_DIR=".docs/session-log"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/session-log-${TIMESTAMP}.md"

# Collect metadata for YAML frontmatter
DATE_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git branch --show-current 2>/dev/null || echo "N/A")
LAST_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "N/A")
CHANGED_FILES=$(git status --short 2>/dev/null | wc -l | tr -d ' ')

{
  echo "---"
  echo "date: ${DATE_ISO}"
  echo "branch: ${BRANCH}"
  echo "last_commit: ${LAST_COMMIT}"
  echo "changed_files: ${CHANGED_FILES}"
  echo "---"
  echo ""
  echo "# Session Work Log"
  echo ""
  echo "## Final Status"
  git status --short 2>/dev/null || echo "(not a git repo)"
  echo ""
  echo "## Recent Commits"
  git log --oneline -5 2>/dev/null || echo "(no commits)"
} > "$LOG_FILE"

exit 0
