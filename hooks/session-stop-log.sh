#!/usr/bin/env bash
# Stop hook: log session activity to .simple-workflow/docs/session-log/ in YAML+Markdown format

set -euo pipefail

# Consume stdin (some hook events provide JSON payload)
cat > /dev/null

# Resolve the repo root via the strict `_psf_repo_root` anchor (requires
# `.simple-workflow/backlog/`) so a cwd inside a nested `.simple-workflow/`
# subdir (e.g. tune-skill bodies writing under `.simple-workflow/kb/`)
# cannot bootstrap a decoy `.simple-workflow/<subdir>/.simple-workflow/`
# tree. Matches the absolute-path strategy used by session-start.sh and
# the strict anchor introduced in T-01.
_sw_self_dir_t03="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/parse-state-file.sh
source "$_sw_self_dir_t03/lib/parse-state-file.sh"
# `_psf_repo_root` returns 1 when no anchor is found but still prints a
# usable fallback (the start dir). Tolerate that exit code under `set -e`.
_sw_repo_root="$(_psf_repo_root "$PWD" || true)"
unset _sw_self_dir_t03

LOG_DIR="$_sw_repo_root/.simple-workflow/docs/session-log"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/session-log-${TIMESTAMP}.md"

# Collect metadata for YAML frontmatter
DATE_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git branch --show-current 2>/dev/null || echo "N/A")
LAST_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "N/A")
CHANGED_FILES=$(git status --short 2>/dev/null | wc -l | tr -d ' ') || CHANGED_FILES="0"

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
