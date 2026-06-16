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
#     Registry keys MUST NOT contain glob meta other than `*` (no `?`, `[`,
#     `]`, brace groups). Such keys are rejected at the first call to
#     `is_hook_owned_field` with a stderr diagnostic and exit code 2 — see
#     `_sa_validate_registry`. Programmer-error fail-fast (F-M1).
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
#     - Captures and restores the parent shell's `extglob` state (F-EXTGLOB)
#       so that sourcing this lib does not flip extglob in the caller.
#
#   state_field_change_blocked <state_file> <old_string> <new_string>
#     - Returns 0 (block) when old_string contains a hook-owned field with one
#       value and new_string changes that value (including blank-out — F-BLANK).
#       Returns 1 (allow) otherwise, including when HOOK_OWNED_FIELDS is empty
#       (AC-10) and when the key is being set for the first time (old_string
#       lacks the key — AC-13).
#     - Does NOT emit any JSON. The hook caller is responsible for emitting
#       {"decision":"block","reason":"hook_owned_field_violation"}.
#
# This file does not introduce any environment-variable knob that disables
# the helpers. If a downstream caller needs to bypass detection (e.g. for
# tests), source the lib in a subshell with a controlled registry override.

# ---------------------------------------------------------------------------
# Registry: hook-owned fields (Foundation 3 — proposal 4 / ST-03).
# `.runtime_metrics` is an append-only telemetry list written EXCLUSIVELY by the
# autopilot Stop / PreCompact / checkpoint hooks (see hooks/lib/runtime-metrics.sh
# header). Registering it lets pre-write/pre-edit-safety detect a model full-file
# Write/Edit that would clobber hook-appended entries (the ST-03 lost-update).
# The actual DENY is gated by SW_STATE_FIELD_GUARD_MODE in those callers
# (default `metric-only` — observe, do not block — so this enforcement ships
# opt-in and the prior no-op behaviour is the default until promoted to `on`).
# ---------------------------------------------------------------------------
declare -A HOOK_OWNED_FIELDS=([".runtime_metrics"]=1)

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
#
# F-RR: Intentionally diverges from `_psf_repo_root` in parse-state-file.sh:
#   - `.git` fallback (allows running outside a `.simple-workflow` tree
#     during repo-root walks; downstream callers re-check for the
#     `.simple-workflow` directory before acting).
#   - `pwd -P` canonicalisation (resolves symlinks to a single canonical
#     form so that paths compared by hooks are stable).
# Reconciliation into a shared helper is deferred — see the matching note
# in parse-state-file.sh.
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

# _sa_ere_escape <string> -> escapes POSIX ERE metacharacters in $1 and emits
# the result to stdout. Used to neutralise leaf names spliced into `grep -E`
# patterns (F-H1). The character class lists every POSIX ERE meta plus `/`
# (sed delimiter) and `\` (escape itself) so they survive the sed pipe.
_sa_ere_escape() {
  printf '%s' "$1" | sed 's/[][\\.*^$|()+?{}/]/\\&/g'
}

# _sa_validate_registry — verify every key in HOOK_OWNED_FIELDS contains
# only `.`, alphanumerics, underscore, hyphen, and the `*` glob meta.
# Anything else (e.g. `?`, `[`, `]`, brace groups) is a programmer error
# and produces a fail-fast diagnostic on stderr (F-M1).
#
# Result is cached in the script-scope `_SA_REGISTRY_VALIDATED` flag so
# subsequent calls are O(1). Callers that mutate the registry MUST unset
# `_SA_REGISTRY_VALIDATED` to force re-validation (this lib does not, since
# the registry is intended to be set once at lib-load time).
_sa_validate_registry() {
  if [ "${_SA_REGISTRY_VALIDATED:-0}" = "1" ]; then
    return 0
  fi
  # Bracket class `[][?{}]`: `]` first → literal `]`; then `[`, `?`, `{`, `}`.
  # Anything in this class is a glob meta we explicitly reject (only `*` is
  # allowed; that's handled in is_hook_owned_field via the +([!.]) rewrite).
  local reg_key
  for reg_key in "${!HOOK_OWNED_FIELDS[@]}"; do
    case "$reg_key" in
      *[][?{}]*)
        printf 'state-authority: registry key "%s" contains glob meta other than * (rejected)\n' \
          "$reg_key" >&2
        return 2
        ;;
    esac
  done
  _SA_REGISTRY_VALIDATED=1
  return 0
}

# _sa_extract_leaf_value <leaf> <yaml_blob>
#   Returns the trimmed value of the first `<leaf>:` line in the blob,
#   or empty string if no such line. Always exits 0. The leaf is
#   ERE-escaped before splicing into the grep pattern (F-H1), so registry
#   keys whose final segment contains POSIX ERE meta cannot inject the
#   pattern with covert matches in unrelated namespaces.
_sa_extract_leaf_value() {
  local leaf="$1" blob="$2" leaf_re
  leaf_re=$(_sa_ere_escape "$leaf")
  printf '%s' "$blob" \
    | grep -E "^[[:space:]]*${leaf_re}:[[:space:]]" \
    | head -1 \
    | sed 's/^[[:space:]]*[^:]*:[[:space:]]*//' \
    | tr -d '\r' \
    || true
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
  # The character-class on the line filter admits a leading `"` or `'` so
  # quoted scalars are caught (F-QYAML). The strip pipeline removes
  # trailing `# comment` segments (F-COMMENT) and surrounding quotes
  # (F-QYAML) before equality testing.
  # If any status value is not "completed" (or the block is empty) return 1.
  awk '
    BEGIN { in_phases = 0; found = 0; all_completed = 1 }
    /^phases:[[:space:]]*$/ { in_phases = 1; next }
    in_phases && /^[^[:space:]]/ { in_phases = 0 }
    in_phases && /status:[[:space:]]*["\x27A-Za-z0-9_-]/ {
      val = $0
      sub(/^.*status:[[:space:]]*/, "", val)
      sub(/[[:space:]]*#.*$/, "", val)         # F-COMMENT: strip trailing comment
      sub(/[[:space:],}]+$/, "", val)          # existing trailing-strip
      sub(/^["\x27]/, "", val)                 # F-QYAML: strip leading quote
      sub(/["\x27]$/, "", val)                 # F-QYAML: strip trailing quote
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
# The function captures and restores the parent shell's `extglob` state
# (F-EXTGLOB) so sourcing this lib does not flip the option in the caller.
# The sed conversion 's/\*/+([!.])/g' ensures * matches exactly one YAML key
# segment (no dots). Do NOT use [!.]* — investigation §3 proves it incorrectly
# allows multi-segment paths because * after [!.] still allows dots.
is_hook_owned_field() {
  _sa_validate_registry || return 2
  local key="$1" _prev result=1
  _prev=$(shopt -p extglob)
  shopt -s extglob
  local reg_key pat
  for reg_key in "${!HOOK_OWNED_FIELDS[@]}"; do
    # Convert * to +([!.]) so a single * matches one segment with no dots.
    pat=$(printf '%s' "$reg_key" | sed 's/\*/+([!.])/g')
    # $pat is intentionally UNQUOTED in the case arm below — the extglob pattern must
    # be expanded as a glob to match `key`; quoting it would break is_hook_owned_field.
    # shellcheck disable=SC2254
    case "$key" in
      $pat) result=0; break ;;
    esac
  done
  eval "$_prev"
  return "$result"
}

# ---------------------------------------------------------------------------
# Public function: state_field_change_blocked
# ---------------------------------------------------------------------------
state_field_change_blocked() {
  # 'state_file' is part of the public signature but unused on this path.
  # shellcheck disable=SC2034
  local state_file="$1"
  local old_string="$2"
  local new_string="$3"

  # Empty registry always allows (AC-10).
  if [ "${#HOOK_OWNED_FIELDS[@]}" -eq 0 ]; then
    return 1
  fi

  # Reject misregistered keys (e.g. containing glob meta other than *) — F-M1.
  _sa_validate_registry || return 2

  local reg_key leaf old_val new_val
  for reg_key in "${!HOOK_OWNED_FIELDS[@]}"; do
    # Extract the leaf YAML key name: the last dot-separated segment.
    # e.g. ".some_top_level_field" -> "some_top_level_field"
    #      ".phases.*.completed_at" -> "completed_at"
    leaf="${reg_key##*.}"

    # Detect the key+value line in old_string.
    old_val=$(_sa_extract_leaf_value "$leaf" "$old_string")

    # If the key is absent in old_string, this is an initial set — allow (AC-13).
    if [ -z "$old_val" ]; then
      continue
    fi

    # Detect the key+value line in new_string.
    new_val=$(_sa_extract_leaf_value "$leaf" "$new_string")

    # F-BLANK: block whenever old_val is non-empty AND new_val differs,
    # including blank-out (new_val empty). Initial-set is already handled
    # by the early-exit above. Echo the matched registry key so the caller
    # can name the violated field in its block reason (proposal 4 / UX-10).
    if [ "$old_val" != "$new_val" ]; then
      printf '%s\n' "$reg_key"
      return 0
    fi
  done

  return 1
}

# ---------------------------------------------------------------------------
# Exports — allow subshells that do not re-source the file to inherit these.
# ---------------------------------------------------------------------------
export -f resolve_active_state_file is_hook_owned_field state_field_change_blocked 2>/dev/null || true
