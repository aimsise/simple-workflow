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

# Export the four functions so children that re-enter bash via `bash -c`
# can pick them up without re-sourcing. (Bash only — POSIX `sh` ignores
# `export -f`. Hooks already require Bash, so this is safe.)
export -f is_autopilot_context parse_phase_status parse_ticket_statuses find_state_file 2>/dev/null || true
