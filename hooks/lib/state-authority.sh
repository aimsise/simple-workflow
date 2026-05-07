#!/usr/bin/env bash
# state-authority.sh — autopilot-state file resolver + hook-owned-field registry
#
# Sourced by:
#   - hooks/pre-edit-safety.sh (PreToolUse:Edit guard, lazy-source inside case arm)
#   - hooks/pre-write-safety.sh (PreToolUse:Write guard, lazy-source inside case arm)
#
# Public contract (do not change without updating the consumers above):
#
#   HOOK_OWNED_FIELDS  — associative array (declared empty). Callers that own
#     specific YAML fields register patterns here (e.g. ".some_top_level_field"
#     or ".phases.*.completed_at"). The registry ships empty; follow-on plans
#     add entries. Never pre-populate this file with per-key insertions.
#
#   resolve_active_state_file [start_dir]
#     - Walks upward from start_dir (default: PWD) to find the repo root,
#       then returns the path of the first autopilot-state.yaml found under:
#         1. .simple-workflow/backlog/briefs/active/<slug>/
#         2. .simple-workflow/backlog/product_backlog/<slug>/
#         3. .simple-workflow/backlog/briefs/done/<slug>/  (conditional — every
#            phase.*.status must equal "completed" for adoption)
#     - Prints the absolute path to stdout and exits 0. Empty stdout when none
#       found; exits 0 in all cases.
#
#   is_hook_owned_field <yaml_key_path>
#     - Returns 0 when <yaml_key_path> matches a key registered in
#       HOOK_OWNED_FIELDS; 1 otherwise. Glob segments use * in the registry
#       (converted to extglob +([!.]) so * matches exactly one path segment
#       with no dots, i.e., a single YAML key).
#
#   state_field_change_blocked <state_file> <old_string> <new_string>
#     - Returns 0 (block) when old_string contains a hook-owned field with one
#       value and new_string changes that value. Returns 1 (allow) otherwise,
#       including when HOOK_OWNED_FIELDS is empty (AC-10) and when the key is
#       being set for the first time (old_string lacks the key — AC-13).
#     - Does NOT emit any JSON. The hook caller is responsible for emitting
#       {"decision":"block","reason":"hook_owned_field_violation"}.
#
# This file does not introduce any environment-variable knob that disables
# the helpers. If a downstream caller needs to bypass detection (e.g. for
# tests), source the lib in a subshell with a controlled registry override.

# ---------------------------------------------------------------------------
# Registry: hook-owned fields (shipped empty — Negative AC-2 enforced).
# ---------------------------------------------------------------------------
declare -A HOOK_OWNED_FIELDS=()

# ---------------------------------------------------------------------------
# Internal helpers (not part of the public contract; prefix _sa_).
# ---------------------------------------------------------------------------

# _sa_have <command> -> 0 if the command is on PATH, 1 otherwise.
_sa_have() {
  command -v "$1" >/dev/null 2>&1
}

# _sa_repo_root [start_dir] -> prints the nearest ancestor that contains
# `.simple-workflow/` or `.git/` (canonical anchor). Prints start_dir when
# no anchor is found (rather than returning 1 — callers check for the dir).
_sa_repo_root() {
  local dir
  dir="${1:-$PWD}"
  # Resolve to absolute path in case a relative path is given.
  dir="$(cd "$dir" 2>/dev/null && pwd -P)" || { printf '%s\n' "${1:-$PWD}"; return 1; }
  local orig="$dir"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -d "$dir/.simple-workflow" ] || [ -d "$dir/.git" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # No anchor found — return the original dir (callers should check .simple-workflow exists).
  printf '%s\n' "$orig"
  return 1
}

# _sa_all_phases_completed <yaml_file> -> 0 when every phase status in the
# file's `phases:` map equals "completed", 1 otherwise. Reads the file with
# a simple grep/awk pass — no yq or PyYAML dependency required.
# Uses POSIX-compatible awk (no gawk array-match extension).
_sa_all_phases_completed() {
  local file="$1"
  [ -f "$file" ] || return 1

  # Extract all status: values under the phases: block using awk.
  # Uses sub() for POSIX compatibility (no match(, m) array form).
  # The trailing-strip regex includes `,` and `}` so inline YAML flow
  # mapping like `scout: {status: completed}` yields `completed` (not
  # `completed}`). Block form `    status: completed` still works since
  # `+` requires only that at least one char be strippable (whitespace
  # alone matches).
  # If any status value is not "completed" (or the block is empty) return 1.
  awk '
    BEGIN { in_phases = 0; found = 0; all_completed = 1 }
    /^phases:[[:space:]]*$/ { in_phases = 1; next }
    in_phases && /^[^[:space:]]/ { in_phases = 0 }
    in_phases && /status:[[:space:]]*[A-Za-z0-9_-]/ {
      val = $0
      sub(/^.*status:[[:space:]]*/, "", val)
      sub(/[[:space:],}]+$/, "", val)
      found = 1
      if (val != "completed") { all_completed = 0 }
    }
    END {
      if (found && all_completed) exit 0
      else exit 1
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Public function: resolve_active_state_file
# ---------------------------------------------------------------------------
resolve_active_state_file() {
  local start_dir="${1:-$PWD}"
  local repo_root
  repo_root="$(_sa_repo_root "$start_dir")" || true

  # Require the .simple-workflow anchor to exist.
  if [ -z "$repo_root" ] || [ ! -d "$repo_root/.simple-workflow" ]; then
    return 0
  fi

  local base candidate
  # Walk candidate bases in priority order (no done/ yet).
  for base in "briefs/active" "product_backlog"; do
    local search_dir="$repo_root/.simple-workflow/backlog/$base"
    if [ -d "$search_dir" ]; then
      candidate="$(find "$search_dir" -mindepth 2 -maxdepth 2 -name autopilot-state.yaml -print -quit 2>/dev/null || true)"
      if [ -n "$candidate" ]; then
        # Resolve to absolute path.
        local abs_dir abs_path
        abs_dir="$(cd "$(dirname "$candidate")" && pwd -P)"
        abs_path="$abs_dir/$(basename "$candidate")"
        printf '%s\n' "$abs_path"
        return 0
      fi
    fi
  done

  # briefs/done: conditional adoption — all phase statuses must be "completed".
  local done_dir="$repo_root/.simple-workflow/backlog/briefs/done"
  if [ -d "$done_dir" ]; then
    # Enumerate all done state files.
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if _sa_all_phases_completed "$candidate"; then
        local abs_dir abs_path
        abs_dir="$(cd "$(dirname "$candidate")" && pwd -P)"
        abs_path="$abs_dir/$(basename "$candidate")"
        printf '%s\n' "$abs_path"
        return 0
      fi
    done < <(find "$done_dir" -mindepth 2 -maxdepth 2 -name autopilot-state.yaml 2>/dev/null || true)
  fi

  # No state file found — emit empty stdout, exit 0.
  return 0
}

# ---------------------------------------------------------------------------
# Public function: is_hook_owned_field
# ---------------------------------------------------------------------------
# IMPORTANT: $pat MUST be unquoted in the case arm for glob expansion.
# shopt -s extglob MUST be inside the function body (not at file top) to
# avoid polluting the parent shell's glob semantics permanently.
# The sed conversion 's/\*/+([!.])/g' ensures * matches exactly one YAML key
# segment (no dots). Do NOT use [!.]* — investigation §3 proves it incorrectly
# allows multi-segment paths because * after [!.] still allows dots.
is_hook_owned_field() {
  local key="$1"
  shopt -s extglob
  local reg_key pat
  for reg_key in "${!HOOK_OWNED_FIELDS[@]}"; do
    # Convert * to +([!.]) so a single * matches one segment with no dots.
    pat=$(printf '%s' "$reg_key" | sed 's/\*/+([!.])/g')
    case "$key" in
      $pat) return 0 ;;   # UNQUOTED $pat — required for glob expansion
    esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# Public function: state_field_change_blocked
# ---------------------------------------------------------------------------
state_field_change_blocked() {
  local state_file="$1"
  local old_string="$2"
  local new_string="$3"

  # Empty registry always allows (AC-10).
  if [ "${#HOOK_OWNED_FIELDS[@]}" -eq 0 ]; then
    return 1
  fi

  local reg_key leaf old_val new_val
  for reg_key in "${!HOOK_OWNED_FIELDS[@]}"; do
    # Extract the leaf YAML key name: the last dot-separated segment.
    # e.g. ".some_top_level_field" -> "some_top_level_field"
    #      ".phases.*.completed_at" -> "completed_at"
    leaf="${reg_key##*.}"

    # Detect the key+value line in old_string.
    old_val="$(printf '%s' "$old_string" | grep -E "^[[:space:]]*${leaf}:[[:space:]]" | head -1 | sed 's/^[[:space:]]*[^:]*:[[:space:]]*//' | tr -d '\r' || true)"

    # If the key is absent in old_string, this is an initial set — allow (AC-13).
    if ! printf '%s' "$old_string" | grep -qE "^[[:space:]]*${leaf}:[[:space:]]"; then
      continue
    fi

    # Detect the key+value line in new_string.
    new_val="$(printf '%s' "$new_string" | grep -E "^[[:space:]]*${leaf}:[[:space:]]" | head -1 | sed 's/^[[:space:]]*[^:]*:[[:space:]]*//' | tr -d '\r' || true)"

    # Block when both strings contain the key AND the value changed.
    if [ -n "$old_val" ] && [ -n "$new_val" ] && [ "$old_val" != "$new_val" ]; then
      return 0
    fi
  done

  return 1
}

# ---------------------------------------------------------------------------
# Exports — allow subshells that do not re-source the file to inherit these.
# ---------------------------------------------------------------------------
export -f resolve_active_state_file is_hook_owned_field state_field_change_blocked 2>/dev/null || true
