#!/usr/bin/env bash
# parse-state-file.sh — shared YAML parse + autopilot-context detection
# helpers used by hook scripts and tests.
#
# Sourced by:
#   - hooks/pre-bash-contract-guard.sh (PreToolUse:Bash guard, PX-02a)
#   - hooks/pre-state-transition.sh (PreToolUse:Write/Edit guard, PX-04)
#   - hooks/post-phase-checkpoint.sh (PostToolUse:Write/Edit observer, PX-05)
#   - tests/test-hooks-lib.sh (unit tests for these helpers)
#
# Public contract (do not change without updating the consumers above):
#
#   is_autopilot_context [start_dir]
#     - Walks upward from start_dir (default: PWD) looking for a directory
#       that holds an autopilot-state.yaml under either:
#         .simple-workflow/backlog/briefs/active/<slug>/
#         .simple-workflow/backlog/product_backlog/<slug>/
#     - Returns 0 when such a state file exists, 1 otherwise.
#
#   parse_phase_status <file_path> <phase_name>
#     - Reads `phases.<phase_name>.status` from a phase-state.yaml-style
#       YAML document. Prints the value to stdout. Empty when missing.
#       Exit non-zero only on file-not-found / unreadable input.
#
#   parse_ticket_statuses <state_yaml_path>
#     - Prints every `tickets[].status` value, one per line, in document
#       order. Exit 0 even when the list is empty.
#
#   find_state_file <parent_slug>
#     - Locates the autopilot-state.yaml for <parent_slug> using the
#       canonical search order:
#         1. .simple-workflow/backlog/briefs/active/<parent_slug>/autopilot-state.yaml
#         2. .simple-workflow/backlog/product_backlog/<parent_slug>/autopilot-state.yaml
#         3. .simple-workflow/backlog/briefs/done/<parent_slug>/autopilot-state.yaml
#       Prints the absolute path of the first match to stdout, or exits 1.
#
#   find_phase_state_file [start_dir]
#     - Depth-agnostic search for the first
#       `.simple-workflow/backlog/active/*/phase-state.yaml` under start_dir
#       (default: the repo root resolved from $PWD). Prints the absolute path
#       of the first match (sorted) to stdout, or returns 1 when no match.
#       Thin wrapper over `find` — does not duplicate yaml-parsing logic.
#
#   parse_impl_next_action <file_path>
#     - Reads `phases.impl.next_action` from the given phase-state.yaml-style
#       YAML document. Prints the value to stdout (empty when null / unset).
#       Thin wrapper that re-uses the same three-tier strategy as
#       `parse_phase_status`. Exits non-zero only on file-not-found.
#
# Implementation strategy: prefer `yq` (mikefarah v4), fall back to
# `python3 + PyYAML`, and finally to a portable `awk` shell parser. This
# matches the graceful-degrade contract documented in CLAUDE.md
# `## Dependencies` and the existing autopilot-state writers
# (hooks/autopilot-continue.sh, hooks/pre-compact-save.sh).
#
# This file does not introduce any environment-variable knob that disables
# the helpers. If a downstream caller needs to bypass detection (e.g. for
# tests), it should call into the helper with a controlled fixture path.

# ---------------------------------------------------------------------------
# Internal helpers (not part of the public contract).
# ---------------------------------------------------------------------------

# _psf_have <command> -> 0 if the command is on PATH, 1 otherwise.
_psf_have() {
  command -v "$1" >/dev/null 2>&1
}

# _psf_repo_root [start_dir] -> prints the nearest ancestor that contains
# `.simple-workflow/` (the canonical anchor). Falls back to start_dir when
# no anchor is found.
#
# F-RR: Intentionally diverges from `_sa_repo_root` in state-authority.sh:
#   - No `.git` fallback (this lib only matters inside an autopilot context,
#     so a hit on a bare `.git` parent without `.simple-workflow` would be
#     a false positive for the callers below).
#   - No `pwd -P` canonicalisation (callers compare against literal $PWD;
#     resolving symlinks would break those comparisons).
# Reconciliation into a shared helper is deferred — see the matching note
# in state-authority.sh.
_psf_repo_root() {
  local dir
  dir="${1:-$PWD}"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -d "$dir/.simple-workflow" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  printf '%s\n' "${1:-$PWD}"
  return 1
}

# ---------------------------------------------------------------------------
# Public function: is_autopilot_context
# ---------------------------------------------------------------------------
is_autopilot_context() {
  local start_dir root
  start_dir="${1:-$PWD}"
  root="$(_psf_repo_root "$start_dir")"
  [ -d "$root/.simple-workflow" ] || return 1

  # Look under briefs/active first (most common for live autopilot runs),
  # then product_backlog (split-plan-only runs).
  if find "$root/.simple-workflow/backlog/briefs/active" \
        -mindepth 2 -maxdepth 2 -name autopilot-state.yaml \
        -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  if find "$root/.simple-workflow/backlog/product_backlog" \
        -mindepth 2 -maxdepth 2 -name autopilot-state.yaml \
        -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Public function: parse_phase_status
# Usage: parse_phase_status <file_path> <phase_name>
# ---------------------------------------------------------------------------
parse_phase_status() {
  local file="$1"
  local phase="$2"
  if [ -z "$file" ] || [ -z "$phase" ]; then
    return 2
  fi
  if [ ! -f "$file" ]; then
    return 1
  fi

  if _psf_have yq; then
    local out
    out="$(yq -r ".phases.${phase}.status // \"\"" "$file" 2>/dev/null || true)"
    # yq returns the literal string "null" when the key is absent; normalise.
    [ "$out" = "null" ] && out=""
    printf '%s\n' "$out"
    return 0
  fi

  if _psf_have python3; then
    python3 - "$file" "$phase" <<'PY' 2>/dev/null || return 1
import sys
try:
    import yaml
except ImportError:
    sys.exit(1)
path, phase = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
phases = doc.get("phases") or {}
entry = phases.get(phase) or {}
val = entry.get("status", "")
print(val if val is not None else "")
PY
    return 0
  fi

  # awk fallback: locate `phases:` then the indented `<phase>:` then the
  # `status:` underneath. Works for the canonical phase-state.yaml shape:
  #   phases:
  #     <name>:
  #       status: <value>
  awk -v phase="$phase" '
    BEGIN { in_phases = 0; in_target = 0 }
    /^phases:[[:space:]]*$/ { in_phases = 1; next }
    in_phases && /^[^[:space:]]/ { in_phases = 0; in_target = 0 }
    in_phases && match($0, /^[[:space:]]+([A-Za-z0-9_-]+):[[:space:]]*$/, m) {
      in_target = (m[1] == phase) ? 1 : 0
      next
    }
    in_target && match($0, /^[[:space:]]+status:[[:space:]]*(.*)$/, m) {
      val = m[1]
      gsub(/^"|"$/, "", val)
      gsub(/^'\''|'\''$/, "", val)
      print val
      exit 0
    }
  ' "$file"
  return 0
}

# ---------------------------------------------------------------------------
# Public function: parse_ticket_statuses
# Usage: parse_ticket_statuses <state_yaml_path>
# ---------------------------------------------------------------------------
parse_ticket_statuses() {
  local file="$1"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    return 1
  fi

  if _psf_have yq; then
    yq -r '.tickets[].status // ""' "$file" 2>/dev/null
    return 0
  fi

  if _psf_have python3; then
    python3 - "$file" <<'PY' 2>/dev/null
import sys
try:
    import yaml
except ImportError:
    sys.exit(1)
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
for entry in (doc.get("tickets") or []):
    val = entry.get("status", "") if isinstance(entry, dict) else ""
    print(val if val is not None else "")
PY
    return 0
  fi

  # awk fallback: walk the `tickets:` list looking for top-level `status:`
  # values inside each `- ` element. Inline-flow `{status: pending}` maps
  # are not produced by autopilot writers, so the line-oriented parser is
  # sufficient for the canonical schema.
  awk '
    BEGIN { in_tickets = 0; in_item = 0 }
    /^tickets:[[:space:]]*$/ { in_tickets = 1; next }
    in_tickets && /^[^[:space:]-]/ { in_tickets = 0; in_item = 0 }
    in_tickets && /^[[:space:]]*-[[:space:]]/ { in_item = 1 }
    in_tickets && in_item && match($0, /status:[[:space:]]*([A-Za-z0-9_-]+)/, m) {
      print m[1]
      in_item = 0
    }
  ' "$file"
  return 0
}

# ---------------------------------------------------------------------------
# Public function: find_state_file
# Usage: find_state_file <parent_slug>
# ---------------------------------------------------------------------------
find_state_file() {
  local slug="$1"
  if [ -z "$slug" ]; then
    return 1
  fi
  local root
  root="$(_psf_repo_root "$PWD")"
  local candidate
  for sub in \
      ".simple-workflow/backlog/briefs/active/${slug}/autopilot-state.yaml" \
      ".simple-workflow/backlog/product_backlog/${slug}/autopilot-state.yaml" \
      ".simple-workflow/backlog/briefs/done/${slug}/autopilot-state.yaml"; do
    candidate="${root}/${sub}"
    if [ -f "$candidate" ]; then
      # Print absolute path. Use `cd` + `pwd -P` to resolve symlinks
      # consistently with the way hooks compare paths.
      local dir base
      dir="$(cd "$(dirname "$candidate")" && pwd -P)"
      base="$(basename "$candidate")"
      printf '%s/%s\n' "$dir" "$base"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Public function: find_phase_state_file
# Usage: find_phase_state_file [start_dir]
#
# Thin wrapper over `find`. Located here (alongside `find_state_file` for
# autopilot-state.yaml) to keep all backlog state-file lookups in one
# helper, even though phase-state.yaml lives under
# `.simple-workflow/backlog/active/<ticket-dir>/` rather than briefs/.
# ---------------------------------------------------------------------------
find_phase_state_file() {
  local start_dir root
  start_dir="${1:-$PWD}"
  root="$(_psf_repo_root "$start_dir")"
  [ -d "$root/.simple-workflow/backlog/active" ] || return 1

  # Pick the most-recently-modified candidate as a proxy for "the active
  # ticket". Lex-first selection (the earlier behaviour) misroutes the
  # Stop hook to ticket 001 when the user is actually working on ticket
  # 002 — bash's `-nt` test is portable across BSD and GNU find. Ties
  # within the same mtime resolve to the order produced by `find`.
  local match=""
  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    if [ -z "$match" ] || [ "$_f" -nt "$match" ]; then
      match="$_f"
    fi
  done < <(find "$root/.simple-workflow/backlog/active" -type f -name 'phase-state.yaml' 2>/dev/null)
  unset _f

  if [ -n "$match" ]; then
    local dir base
    dir="$(cd "$(dirname "$match")" && pwd -P)"
    base="$(basename "$match")"
    printf '%s/%s\n' "$dir" "$base"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Public function: parse_impl_next_action
# Usage: parse_impl_next_action <file_path>
#
# Thin wrapper that reads `phases.impl.next_action` via the same three-tier
# fallback as `parse_phase_status`. yq returns the literal string "null"
# when the key is unset; that is normalised to an empty string here so
# callers can do a single empty-check against either.
# ---------------------------------------------------------------------------
parse_impl_next_action() {
  local file="$1"
  if [ -z "$file" ]; then
    return 2
  fi
  if [ ! -f "$file" ]; then
    return 1
  fi

  if _psf_have yq; then
    local out
    out="$(yq -r '.phases.impl.next_action // ""' "$file" 2>/dev/null || true)"
    [ "$out" = "null" ] && out=""
    printf '%s\n' "$out"
    return 0
  fi

  # Tier 2: python3 + PyYAML. macOS ships /usr/bin/python3 WITHOUT PyYAML,
  # so we must gate on PyYAML availability up front — otherwise a fresh
  # macOS without PyYAML would short-circuit here on ImportError and
  # never reach the awk tier (a fail-closed silent-empty result against
  # the failure mode this hook is supposed to detect).
  if _psf_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY' 2>/dev/null || return 1
import sys
import yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
phases = doc.get("phases") or {}
impl = phases.get("impl") or {}
val = impl.get("next_action", "")
if val is None:
    val = ""
print(val)
PY
    return 0
  fi

  # awk fallback: walk into `phases:` -> `impl:` -> `next_action:` and emit
  # the value. POSIX awk only — does NOT use the gawk-specific 3-arg
  # `match(s, re, arr)` form, so this works on macOS's stock BSD awk as
  # well as gawk. Capture-group extraction is replaced by `sub()`
  # strip-by-prefix on a local copy of the line. The phase-key matcher is
  # anchored at exactly 2 spaces (canonical yq output indent) so it does
  # not falsely match deeper nested keys like `    artifacts:`.
  #
  # NOTE: existing `parse_phase_status` / `parse_ticket_statuses` (defined
  # above) still use the gawk-only form and remain incompatible with BSD
  # awk; their migration is tracked separately to keep this v6.4.1 patch
  # scoped to the new functions added in v6.4.0.
  awk '
    BEGIN { in_phases = 0; in_impl = 0 }
    /^phases:[[:space:]]*$/ { in_phases = 1; next }
    in_phases && /^[^[:space:]]/ { in_phases = 0; in_impl = 0 }
    in_phases && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      name = $0
      sub(/^  /, "", name)
      sub(/:[[:space:]]*$/, "", name)
      in_impl = (name == "impl") ? 1 : 0
      next
    }
    in_impl && /^    next_action:[[:space:]]*/ {
      val = $0
      sub(/^    next_action:[[:space:]]*/, "", val)
      gsub(/^"|"$/, "", val)
      gsub(/^'\''|'\''$/, "", val)
      sub(/[[:space:]]+#.*$/, "", val)
      if (val == "null" || val == "~") val = ""
      print val
      exit 0
    }
  ' "$file"
  return 0
}

# Export the public functions so children that re-enter bash via `bash -c`
# can pick them up without re-sourcing. (Bash only — POSIX `sh` ignores
# `export -f`. Hooks already require Bash, so this is safe.)
export -f is_autopilot_context parse_phase_status parse_ticket_statuses find_state_file find_phase_state_file parse_impl_next_action 2>/dev/null || true
