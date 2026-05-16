#!/usr/bin/env bash
# parse-state-file.sh — shared YAML parse + autopilot-context detection
# helpers used by hook scripts and tests.
#
# Sourced by:
#   - hooks/pre-bash-contract-guard.sh (PreToolUse:Bash guard, PX-02a)
#   - hooks/pre-state-transition.sh (PreToolUse:Write/Edit guard, PX-04)
#   - hooks/post-phase-checkpoint.sh (PostToolUse:Write/Edit observer, PX-05)
#   - hooks/post-ship-auto-compact.sh (PostToolUse:Skill auto-/compact, v7)
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
#   find_any_autopilot_state_file [start_dir]
#     - Slug-free counterpart to `find_state_file`. Returns the absolute
#       path of an active `autopilot-state.yaml` under
#       `.simple-workflow/backlog/briefs/active/` (preferred) or
#       `.simple-workflow/backlog/product_backlog/` (fallback), picking the
#       most-recently-modified candidate when several exist. Returns 1 if
#       none are present. Used by hooks that need the state directory
#       without knowing the parent slug (e.g. the auto-compact sentinel).
#
#   parse_ticket_ship_dirs <file_path>
#     - Walks the `tickets:` list in an autopilot-state.yaml document (or any
#       payload snippet that uses the canonical schema) and prints the
#       `ticket_dir:` value of every element whose `steps.ship == "completed"`,
#       one per line, in document order. Used by the post-ship-state auto-
#       compact safety net to scope state-lie protection to the SPECIFIC
#       tickets[] elements whose ship status was just flipped — not the
#       single first match a global grep would yield (CD-1 / CD-2 in the
#       v7 review). Callers pass a payload by writing it to a temp file
#       (mktemp + printf > tmp) and passing that path here, so the helper
#       can use the same three-tier file-based strategy as the other
#       parsers in this lib.
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

  # Tier 2: python3 + PyYAML. macOS ships /usr/bin/python3 WITHOUT PyYAML,
  # so we must gate on PyYAML availability up front — otherwise a fresh
  # macOS without PyYAML would short-circuit here on ImportError and
  # never reach the awk tier (a fail-CLOSED silent-empty result against
  # the failure mode the consumers depend on detecting).
  if _psf_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" "$phase" <<'PY' 2>/dev/null || return 1
import sys
import yaml
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
  # `status:` underneath. POSIX awk only — does NOT use the gawk-specific
  # 3-arg `match(s, re, arr)` form, so this works on macOS's stock BSD
  # awk as well as gawk. Capture-group extraction is replaced by `sub()`
  # strip-by-prefix on a local copy of the line. Phase keys are anchored
  # at exactly 2 spaces and `status:` at exactly 4 spaces (canonical yq
  # output indent) so deeper-nested keys like `      next_action:` cannot
  # falsely promote to phase status.
  awk -v phase="$phase" '
    BEGIN { in_phases = 0; in_target = 0 }
    /^phases:[[:space:]]*$/ { in_phases = 1; next }
    in_phases && /^[^[:space:]]/ { in_phases = 0; in_target = 0 }
    in_phases && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      name = $0
      sub(/^  /, "", name)
      sub(/:[[:space:]]*$/, "", name)
      in_target = (name == phase) ? 1 : 0
      next
    }
    in_target && /^    status:[[:space:]]*/ {
      val = $0
      sub(/^    status:[[:space:]]*/, "", val)
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

  # Tier 2: python3 + PyYAML. Same gating rationale as parse_phase_status:
  # without the up-front `import yaml` probe a stock macOS without PyYAML
  # would short-circuit here on ImportError and skip the awk tier.
  if _psf_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY' 2>/dev/null
import sys
import yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
for entry in (doc.get("tickets") or []):
    val = entry.get("status", "") if isinstance(entry, dict) else ""
    print(val if val is not None else "")
PY
    return 0
  fi

  # awk fallback: walk the `tickets:` list looking for `status:` values
  # inside each `- ` element. POSIX awk only — uses `sub()` strip-by-prefix
  # instead of the gawk-specific 3-arg `match(s, re, arr)` so macOS's
  # stock BSD awk handles this tier. `status:` is anchored at exactly 4
  # spaces (canonical yq output for `tickets[].status`: the `- key:` line
  # sits at 2-space indent, sibling keys at 4-space). Inline-flow
  # `{status: pending}` maps are not produced by autopilot writers, so
  # the line-oriented parser is sufficient for the canonical schema.
  awk '
    BEGIN { in_tickets = 0; in_item = 0 }
    /^tickets:[[:space:]]*$/ { in_tickets = 1; next }
    in_tickets && /^[^[:space:]-]/ { in_tickets = 0; in_item = 0 }
    in_tickets && /^[[:space:]]*-[[:space:]]/ { in_item = 1 }
    in_tickets && in_item && /^    status:[[:space:]]*/ {
      val = $0
      sub(/^    status:[[:space:]]*/, "", val)
      gsub(/^"|"$/, "", val)
      gsub(/^'\''|'\''$/, "", val)
      sub(/[[:space:]]+#.*$/, "", val)
      if (val == "null" || val == "~") val = ""
      print val
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
# Public function: find_any_autopilot_state_file
# Usage: find_any_autopilot_state_file [start_dir]
#
# Returns the absolute path of an active autopilot-state.yaml without
# requiring the caller to know the parent slug. Used by
# `hooks/post-ship-auto-compact.sh` to place an auto-compact sentinel in
# the brief directory, and as a generic counterpart to the slug-keyed
# `find_state_file` helper. Search order matches `is_autopilot_context`:
# briefs/active first (live runs), then product_backlog (split-plan-only).
# Among multiple candidates the most-recently-modified file wins, matching
# the disambiguation policy used by `find_phase_state_file` and the inline
# scan in `hooks/autopilot-continue.sh`.
# ---------------------------------------------------------------------------
find_any_autopilot_state_file() {
  local start_dir root
  start_dir="${1:-$PWD}"
  root="$(_psf_repo_root "$start_dir")"
  [ -d "$root/.simple-workflow" ] || return 1

  local match=""
  for base in briefs/active product_backlog; do
    local dir="$root/.simple-workflow/backlog/$base"
    [ -d "$dir" ] || continue
    while IFS= read -r _f; do
      [ -f "$_f" ] || continue
      if [ -z "$match" ] || [ "$_f" -nt "$match" ]; then
        match="$_f"
      fi
    done < <(find "$dir" -type f -name 'autopilot-state.yaml' 2>/dev/null)
    unset _f
    if [ -n "$match" ]; then
      local d b
      d="$(cd "$(dirname "$match")" && pwd -P)"
      b="$(basename "$match")"
      printf '%s/%s\n' "$d" "$b"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Public function: parse_ticket_ship_dirs
# Usage: parse_ticket_ship_dirs <file_path>
#
# Prints the `ticket_dir:` value of every `tickets[]` element whose
# `steps.ship == "completed"`, one per line, in document order.
#
# Designed for the post-ship-state auto-compact safety net (CD-1 / CD-2 in
# the v7 review): the previous awk implementation exited at the first
# `ship: completed` match and returned the last `ticket_dir:` seen so far,
# which silently passed Gate 5 when a multi-ticket payload had a genuine
# done/-dir T-001 followed by a lying active/-dir T-002. This helper
# pairs each ship status with the ticket_dir of the SAME `tickets[]`
# element, so the safety net can refuse to inject when ANY element's
# just-flipped ship status references a directory that is not yet
# under backlog/done/.
#
# Element boundary detection (awk tier): each `^[[:space:]]*-[[:space:]]`
# line starts a new element; any line that is non-indented and not a
# top-level `-` (i.e. a sibling top-level key) closes the `tickets:`
# section. Within an element, both `ticket_dir:` and `ship:` are captured
# in any order, and the pair is emitted at element close (next `-` or
# end-of-section / end-of-file).
# ---------------------------------------------------------------------------
parse_ticket_ship_dirs() {
  local file="$1"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    return 1
  fi

  if _psf_have yq; then
    yq -r '.tickets[] | select((.steps.ship // "") == "completed") | (.ticket_dir // "")' "$file" 2>/dev/null
    return 0
  fi

  if _psf_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY' 2>/dev/null
import sys
import yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
for entry in (doc.get("tickets") or []):
    if not isinstance(entry, dict):
        continue
    steps = entry.get("steps") or {}
    if (steps.get("ship") if isinstance(steps, dict) else None) != "completed":
        continue
    val = entry.get("ticket_dir", "")
    print(val if val is not None else "")
PY
    return 0
  fi

  # awk fallback: stateful walk over the tickets list. POSIX awk only.
  # `ticket_dir:` is anchored at exactly 4 spaces (sibling-of-element key),
  # `ship:` at exactly 6 spaces (nested under `steps:`). The single-quote
  # in `gsub(/^'\''|'\''$/, "", val)` is escaped via bash string concat —
  # same idiom as parse_ticket_statuses above.
  awk '
    function emit() {
      if (in_item && pending_ship == "completed" && pending_dir != "") {
        print pending_dir
      }
      pending_dir = ""
      pending_ship = ""
    }
    BEGIN { in_tickets = 0; in_item = 0; pending_dir = ""; pending_ship = "" }
    /^tickets:[[:space:]]*$/ { in_tickets = 1; next }
    in_tickets && /^[^[:space:]-]/ { emit(); in_tickets = 0; in_item = 0; next }
    in_tickets && /^[[:space:]]*-[[:space:]]/ { emit(); in_item = 1; next }
    in_tickets && in_item && /^    ticket_dir:[[:space:]]+/ {
      val = $0
      sub(/^    ticket_dir:[[:space:]]+/, "", val)
      gsub(/^"|"$/, "", val)
      gsub(/^'\''|'\''$/, "", val)
      sub(/[[:space:]]+#.*$/, "", val)
      pending_dir = val
      next
    }
    in_tickets && in_item && /^      ship:[[:space:]]+completed[[:space:]]*$/ {
      pending_ship = "completed"
      next
    }
    END { emit() }
  ' "$file"
  return 0
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
export -f is_autopilot_context parse_phase_status parse_ticket_statuses find_state_file find_any_autopilot_state_file parse_ticket_ship_dirs find_phase_state_file parse_impl_next_action 2>/dev/null || true
