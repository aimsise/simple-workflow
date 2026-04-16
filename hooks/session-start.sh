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

if git rev-parse --git-dir >/dev/null 2>&1; then
  # --- Ensure at least one commit exists (empty repository detection) ---
  # Idempotent: if HEAD already resolves to a commit, this block is skipped.
  if ! git rev-parse HEAD >/dev/null 2>&1; then
    if [ -f .gitignore ]; then
      git add .gitignore >/dev/null 2>&1 || true
      git commit -q -m "Initial commit: project baseline" >/dev/null 2>&1 || true
    else
      git commit -q --allow-empty -m "Initial commit: project baseline" >/dev/null 2>&1 || true
    fi
  fi

  # --- Ensure .gitignore contains simple-workflow entries ---
  _sw_gitignore_entries=(.docs/ .backlog/ .simple-wf-knowledge/)
  _sw_needs_header=false
  _sw_missing_entries=()
  for _sw_entry in "${_sw_gitignore_entries[@]}"; do
    if ! grep -qxF "$_sw_entry" .gitignore 2>/dev/null; then
      _sw_missing_entries+=("$_sw_entry")
      _sw_needs_header=true
    fi
  done
  if [[ "$_sw_needs_header" == "true" ]]; then
    # Add a blank line separator if .gitignore exists and is non-empty
    if [[ -s .gitignore ]]; then
      printf '\n' >> .gitignore
    fi
    printf '# simple-workflow plugin\n' >> .gitignore
    for _sw_entry in "${_sw_missing_entries[@]}"; do
      printf '%s\n' "$_sw_entry" >> .gitignore
    done
  fi
  unset _sw_gitignore_entries _sw_needs_header _sw_missing_entries _sw_entry

  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  CHANGED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
  CONTEXT="Branch: ${BRANCH} | Changed files: ${CHANGED}"
else
  CONTEXT="Branch: (not a git repo) | Changed files: 0"
fi

# Output as additionalContext JSON
jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
