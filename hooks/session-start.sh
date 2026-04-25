#!/usr/bin/env bash
set -euo pipefail
cat > /dev/null  # consume stdin

# --- Cleanup old session logs (30+ days) ---
# Rationale: only ephemeral state (compact-state, session-log) is aged out.
# These files capture transient session context that loses value once the
# session is gone. Evaluation logs (eval-round-*.md, audit-round-*.md,
# quality-round-*.md, security-scan-*.md) and reviews/ are permanent
# records of ticket-level decisions and are NEVER auto-deleted — they
# stay forever inside their ticket directory (active/ or done/).
if [ -d ".simple-workflow/docs/compact-state" ]; then
  find .simple-workflow/docs/compact-state -name "compact-state-*.md" -mtime +30 -delete 2>/dev/null || true
fi
if [ -d ".simple-workflow/docs/session-log" ]; then
  find .simple-workflow/docs/session-log -name "session-log-*.md" -mtime +30 -delete 2>/dev/null || true
fi

# --- v4.1.0 gitignore setup block ---
# Runs once per repo: installs a minimal git environment (init if missing,
# initial commit if empty, appends simple-workflow .gitignore entries, commits
# the gitignore if HEAD exists), then writes a setup flag to prevent any
# future modification of .gitignore by this hook. Respecting the user's
# decision to delete entries later is the reason for the flag.
if [ ! -f .simple-workflow/.setup-done ]; then

  # 1. Ensure a git repo exists
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    git init -b main >/dev/null 2>&1 || git init >/dev/null 2>&1 || true
  fi

  # 2. Empty-repo initial commit (idempotent: skipped when HEAD resolves).
  if git rev-parse --git-dir >/dev/null 2>&1 && ! git rev-parse HEAD >/dev/null 2>&1; then
    if [ -f .gitignore ]; then
      git add .gitignore >/dev/null 2>&1 || true
      git commit -q -m "Initial commit: project baseline" >/dev/null 2>&1 || true
    else
      git commit -q --allow-empty -m "Initial commit: project baseline" >/dev/null 2>&1 || true
    fi
  fi

  # 3. Ensure .gitignore contains the required entries AND is fully committed.
  #    - Append missing entries (idempotent: never re-appends an entry that
  #      already matches by exact line).
  #    - Commit .gitignore when it is not in a clean state vs HEAD — whether
  #      the non-clean state was produced by this run's append OR by a prior
  #      run whose commit failed (e.g. missing git identity, rejected
  #      pre-commit hook). The retry-commit path is what lets a prior failure
  #      self-heal once the user resolves the underlying issue.
  #    - Never uses `-f` with `git add`.
  _sw_gitignore_modified=0
  if git rev-parse --git-dir >/dev/null 2>&1; then
    _sw_gitignore_entries=(.simple-workflow/)
    _sw_missing_entries=()
    for _sw_entry in "${_sw_gitignore_entries[@]}"; do
      if ! grep -qxF "$_sw_entry" .gitignore 2>/dev/null; then
        _sw_missing_entries+=("$_sw_entry")
      fi
    done
    if [ ${#_sw_missing_entries[@]} -gt 0 ]; then
      [ -s .gitignore ] && printf '\n' >> .gitignore
      printf '# simple-workflow plugin artifacts (local-only; delete entries to share via git)\n' >> .gitignore
      for _sw_entry in "${_sw_missing_entries[@]}"; do
        printf '%s\n' "$_sw_entry" >> .gitignore
      done
      _sw_gitignore_modified=1
    fi
    # Commit .gitignore when we have a HEAD and the file is in a non-clean
    # state: either because we just appended, or because a prior run left
    # staged/unstaged/untracked changes behind. `git status --porcelain`
    # detects all three states (`git diff --quiet HEAD` misses untracked).
    if git rev-parse HEAD >/dev/null 2>&1; then
      if [ "$_sw_gitignore_modified" = "1" ] || \
         [ -n "$(git status --porcelain -- .gitignore 2>/dev/null)" ]; then
        git add .gitignore >/dev/null 2>&1 && \
          git commit -q -m "chore: add simple-workflow artifacts to .gitignore" >/dev/null 2>&1 || true
      fi
    fi
    unset _sw_gitignore_entries _sw_missing_entries _sw_entry
  fi

  # 4. Write the setup flag only when the setup actually finalized.
  #    "Finalized" means: git repo exists AND .gitignore working-tree state
  #    equals HEAD (no uncommitted modifications). If .gitignore was mutated
  #    but the commit failed (e.g. missing `git config user.email`), the flag
  #    is NOT written — the warning is surfaced to stderr and the next session
  #    retries. Writing the flag in that state would permanently lock the
  #    repo into a staged-but-uncommitted .gitignore (silent inconsistency).
  _sw_setup_ok=1
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    _sw_setup_ok=0
  elif git rev-parse HEAD >/dev/null 2>&1; then
    # Clean state = `git status --porcelain -- .gitignore` produces no output
    # (no staged, unstaged, OR untracked changes). Covers the case where a
    # prior commit failed and left .gitignore staged-but-uncommitted.
    if [ -n "$(git status --porcelain -- .gitignore 2>/dev/null)" ]; then
      _sw_setup_ok=0
    fi
  else
    # No HEAD yet — only safe if we did not modify .gitignore this run.
    if [ "$_sw_gitignore_modified" = "1" ]; then
      _sw_setup_ok=0
    fi
  fi

  if [ "$_sw_setup_ok" = "1" ]; then
    mkdir -p .simple-workflow 2>/dev/null || true
    touch .simple-workflow/.setup-done 2>/dev/null || true
  else
    printf '[simple-wf-setup] WARNING: .gitignore was modified but the setup commit did not finalize. Configure `git config user.email` / `user.name` (or resolve a pre-commit hook failure) and re-open the session to retry. The setup flag will NOT be written until the commit succeeds.\n' >&2
  fi
  unset _sw_setup_ok _sw_gitignore_modified
fi

if git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  CHANGED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
  CONTEXT="Branch: ${BRANCH} | Changed files: ${CHANGED}"
else
  CONTEXT="Branch: (not a git repo) | Changed files: 0"
fi

# --- Active-ticket phase-state.yaml summary ---
# Scan phase-state.yaml files depth-agnostically under
# .simple-workflow/backlog/active/ and .simple-workflow/backlog/product_backlog/
# so both the flat layout (.simple-workflow/backlog/active/{NNN}-{slug}/) and
# nested layouts (.simple-workflow/backlog/active/{parent}/{NNN}-{slug}/, or
# deeper) are surfaced.
# Uses grep+sed only (no yq) to match pre-compact-save.sh and avoid runtime
# dependencies. All reads are guarded so that a missing or corrupt file
# never blocks session start.
_sw_extract_scalar() {
  # $1 = file, $2 = top-level YAML key
  # Matches only top-level (column 0) scalar definitions to avoid picking
  # up nested keys of the same name inside `phases:`.
  grep -m 1 -E "^${2}:[[:space:]]" "$1" 2>/dev/null \
    | sed -E "s/^${2}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^[\"']//; s/[\"']$//" \
    || true
}

# Scan BOTH active and product_backlog locations. /create-ticket writes the
# initial phase-state.yaml into .simple-workflow/backlog/product_backlog/ for
# tickets that have not yet entered /scout. Readers that skip that directory
# miss every ticket sitting at last_completed_phase: create_ticket.
#
# The scan is anchored at the repo root (via `git rev-parse`) so that the
# hook still finds `.simple-workflow/backlog/` when a session opens in a
# subdirectory of the repo. When we are not inside a git worktree the anchor
# falls back to $PWD.
#
# `find` with no -maxdepth produces depth-agnostic matches. We sort -u on
# resolved paths to guarantee a single entry per phase-state.yaml even if
# multiple search roots match the same file (AC 10 idempotent rendering).
_sw_repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_sw_state_files=()
for _sw_scan_root in \
  "${_sw_repo_root}/.simple-workflow/backlog/active" \
  "${_sw_repo_root}/.simple-workflow/backlog/product_backlog"; do
  [ -d "$_sw_scan_root" ] || continue
  while IFS= read -r _sw_found; do
    [ -n "$_sw_found" ] && _sw_state_files+=("$_sw_found")
  done < <(find "$_sw_scan_root" -type f -name 'phase-state.yaml' 2>/dev/null | sort -u)
done
unset _sw_scan_root _sw_found

# De-duplicate by resolved absolute path. Same file reachable via two paths
# (symlinks, overlapping scan roots) must only be rendered once.
_sw_seen_abs=""
_sw_ticket_lines=""
for _sw_sf in "${_sw_state_files[@]:-}"; do
  [ -n "$_sw_sf" ] || continue
  # Skip unreadable files silently.
  [ -r "$_sw_sf" ] || continue
  # Resolve the absolute path for the dedup key. If python is unavailable
  # or resolution fails, fall back to the file path itself (less strict
  # but still covers the common case).
  _sw_abs=""
  _sw_abs=$(cd "$(dirname "$_sw_sf")" 2>/dev/null && pwd -P)/$(basename "$_sw_sf") || _sw_abs="$_sw_sf"
  case $'\n'"$_sw_seen_abs"$'\n' in
    *$'\n'"$_sw_abs"$'\n'*) continue ;;  # already rendered
  esac
  _sw_seen_abs+=$'\n'"$_sw_abs"

  _sw_ticket_dir_abs=$(dirname "$_sw_sf")
  # Present the ticket path relative to the repo root so the output stays
  # identical across `pwd == repo root` and `pwd == some/subdir/` invocations.
  case "$_sw_ticket_dir_abs" in
    "${_sw_repo_root}/"*) _sw_ticket_dir="${_sw_ticket_dir_abs#${_sw_repo_root}/}" ;;
    *)                    _sw_ticket_dir="$_sw_ticket_dir_abs" ;;
  esac
  _sw_cur=$(_sw_extract_scalar "$_sw_sf" "current_phase")
  _sw_last=$(_sw_extract_scalar "$_sw_sf" "last_completed_phase")
  _sw_status=$(_sw_extract_scalar "$_sw_sf" "overall_status")
  # If all three are empty, treat the file as malformed and skip.
  if [ -z "$_sw_cur" ] && [ -z "$_sw_last" ] && [ -z "$_sw_status" ]; then
    continue
  fi
  # Skip tickets that are already done — the negative AC requires
  # `overall_status: done` under any location to be omitted from the
  # "Active tickets" listing (even if the path happens to sit under
  # .simple-workflow/backlog/active/ by accident of filesystem state).
  if [ "$_sw_status" = "done" ]; then
    continue
  fi
  # Empty fields become literal "null" / "unknown" placeholders so the
  # output stays parseable even with partially-written state files.
  [ -z "$_sw_cur" ] && _sw_cur="unknown"
  [ -z "$_sw_last" ] && _sw_last="null"
  [ -z "$_sw_status" ] && _sw_status="unknown"
  # Append a location marker so users can tell at a glance whether a ticket
  # is in active/ (ready for /scout continuation or later) or product_backlog/
  # (awaits initial /scout invocation). Nested/triple-nested paths are
  # matched by prefix so the marker still attaches correctly.
  _sw_location_marker=""
  case "$_sw_ticket_dir" in
    .simple-workflow/backlog/product_backlog/*) _sw_location_marker=" (product_backlog)" ;;
    .simple-workflow/backlog/active/*)          _sw_location_marker=" (active)" ;;
  esac
  _sw_ticket_lines+=$'\n'"  - ${_sw_ticket_dir}: phase=${_sw_cur} last_completed=${_sw_last} status=${_sw_status}${_sw_location_marker}"
done
unset _sw_state_files _sw_sf _sw_ticket_dir _sw_ticket_dir_abs _sw_cur _sw_last _sw_status _sw_location_marker _sw_repo_root _sw_seen_abs _sw_abs

if [ -n "$_sw_ticket_lines" ]; then
  CONTEXT+=$'\n'"Active tickets:${_sw_ticket_lines}"$'\n'"Tip: run /catchup for full recovery."
fi
unset _sw_ticket_lines

# Output as additionalContext JSON
jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
