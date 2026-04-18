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

# --- Active-ticket phase-state.yaml summary ---
# Scan .backlog/active/*/phase-state.yaml and extract current_phase,
# last_completed_phase, overall_status per ticket. Uses grep+sed only
# (no yq) to match pre-compact-save.sh and avoid runtime dependencies.
# All reads are guarded so that a missing or corrupt file never blocks
# session start (AC 3.4).
_sw_extract_scalar() {
  # $1 = file, $2 = top-level YAML key
  # Matches only top-level (column 0) scalar definitions to avoid picking
  # up nested keys of the same name inside `phases:`.
  grep -m 1 -E "^${2}:[[:space:]]" "$1" 2>/dev/null \
    | sed -E "s/^${2}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^[\"']//; s/[\"']$//" \
    || true
}

shopt -s nullglob
_sw_state_files=(.backlog/active/*/phase-state.yaml)
shopt -u nullglob

_sw_ticket_lines=""
for _sw_sf in "${_sw_state_files[@]}"; do
  # Skip unreadable files silently.
  [ -r "$_sw_sf" ] || continue
  _sw_ticket_dir=$(dirname "$_sw_sf")
  _sw_cur=$(_sw_extract_scalar "$_sw_sf" "current_phase")
  _sw_last=$(_sw_extract_scalar "$_sw_sf" "last_completed_phase")
  _sw_status=$(_sw_extract_scalar "$_sw_sf" "overall_status")
  # If all three are empty, treat the file as malformed and skip.
  if [ -z "$_sw_cur" ] && [ -z "$_sw_last" ] && [ -z "$_sw_status" ]; then
    continue
  fi
  # Empty fields become literal "null" / "unknown" placeholders so the
  # output stays parseable even with partially-written state files.
  [ -z "$_sw_cur" ] && _sw_cur="unknown"
  [ -z "$_sw_last" ] && _sw_last="null"
  [ -z "$_sw_status" ] && _sw_status="unknown"
  _sw_ticket_lines+=$'\n'"  - ${_sw_ticket_dir}: phase=${_sw_cur} last_completed=${_sw_last} status=${_sw_status}"
done
unset _sw_state_files _sw_sf _sw_ticket_dir _sw_cur _sw_last _sw_status

if [ -n "$_sw_ticket_lines" ]; then
  CONTEXT+=$'\n'"Active tickets:${_sw_ticket_lines}"$'\n'"Tip: run /catchup for full recovery."
fi
unset _sw_ticket_lines

# Output as additionalContext JSON
jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
