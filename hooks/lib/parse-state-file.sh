#!/usr/bin/env bash
# parse-state-file.sh — shared YAML parse + autopilot-context detection
# helpers used by hook scripts and tests.
#
# Schema reference: docs/state-schema.md
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
#     - WI-4 schema-tolerance: accepts BOTH the canonical list form
#       (`tickets: - logical_id: ...`) and the map form
#       (`pomodoro-timer-part-1: { status: ... }`) that the autopilot
#       orchestrator silently produced in test_simple_workflow28. yq's
#       `.[]` iterates either; python3 tier branches on
#       `isinstance(tickets, dict|list)`; the awk fallback recognises
#       both the `^  -` dash-form and `^  <key>:` map-form item
#       openers. Mirrors the WI-3 pattern used by
#       `parse_ticket_ship_dirs`.
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
#   parse_yaml_scalar <file_path> <key>
#     - Generic top-level YAML scalar reader. Walks the same three-tier
#       fallback (yq -> python3+PyYAML -> awk) as the phase-state /
#       autopilot-state helpers above. Prints the literal scalar value
#       for `<key>:` at the document root (no dotted traversal — for
#       nested keys callers should use a more specific helper). Empty
#       output when the key is absent, the value is null/`~`, or the
#       file is unreadable. Exit non-zero only on file-not-found /
#       missing-key arguments. Used by
#       `hooks/post-ship-state-auto-compact.sh` Gate 5.5 (post-ship
#       integrity self-heal) to read `overall_status:` from each
#       done-ticket's `phase-state.yaml` without re-implementing the
#       three-tier strategy.
#
#   get_risk_tolerance <state_dir>
#     - Reads `risk_tolerance:` from <state_dir>/autopilot-policy.yaml.
#       Prints one of "aggressive" / "moderate" / "conservative" to stdout.
#       Fallback (file missing / key absent / unparsable / unknown value)
#       is the literal "conservative" -- the most permissive tier on the
#       policy-gate axis, chosen so that an absent or malformed policy
#       file does NOT silently flip every header to deny and break the
#       recovery paths that the SKILL prose still expects to remain open
#       (e.g. `audit-fail` / `ac-eval` AskUserQuestion). Uses the same
#       three-tier strategy as the other helpers in this lib (yq ->
#       python3+PyYAML -> awk).
#
#   resolve_parallel_mode <state_file>
#     - The single parallel-execution mode resolver shared by every
#       parallel-aware hook (the T-004/5/6 rework). Precedence:
#       SW_PARALLEL_HOOKS_MODE (env override; unknown SET value -> off, no
#       fall-through) > `parallel_mode:` scalar in <state_file> (absent /
#       null / unknown -> off) > `off`. Prints exactly one of
#       `on` / `metric-only` / `off`, NEVER empty; every ambiguity fails
#       CLOSED to `off` (the proven serial / byte-identical path). A
#       missing / unreadable <state_file> resolves `off`. (B) harness-own
#       plumbing — consumed by hooks, not by any agent.
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
# `.simple-workflow/backlog/` (the canonical anchor). Falls back to
# start_dir when no anchor is found.
#
# F-RR: Intentionally diverges from `_sa_repo_root` in state-authority.sh:
#   - No `.git` fallback (this lib only matters inside an autopilot context,
#     so a hit on a bare `.git` parent without `.simple-workflow` would be
#     a false positive for the callers below).
#   - No `pwd -P` canonicalisation (callers compare against literal $PWD;
#     resolving symlinks would break those comparisons).
# Reconciliation into a shared helper is deferred — see the matching note
# in state-authority.sh.
#
# Stricter anchor (T-01 / test_simple_workflow29): the candidate must also
# contain `.simple-workflow/backlog/` so a nested decoy
# `.simple-workflow/<subdir>/.simple-workflow/` accidentally created by a
# cwd-relative write (e.g. a tune-skill artifact under
# `.simple-workflow/kb/` writing to `.simple-workflow/docs/session-log/`
# while cwd is `.simple-workflow/kb/`) cannot be mistaken for the real
# autopilot root. The post-compact SessionStart resume injection silently
# no-op'd in the field when `_psf_repo_root` accepted any `.simple-workflow/`
# child as the root and returned the decoy. The F-RR note above stays
# intact: still walks via `dirname` only, no symlink canonicalisation.
_psf_repo_root() {
  local dir
  dir="${1:-$PWD}"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -d "$dir/.simple-workflow" ] && [ -d "$dir/.simple-workflow/backlog" ]; then
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
#
# WI-4 schema-tolerance: accepts BOTH canonical list form
# (`tickets: - logical_id: …`) and map form
# (`pomodoro-timer-part-1: { status: … }`) — field evidence
# `test_simple_workflow28`. Mirrors `parse_ticket_ship_dirs` (WI-3).
# Tier 1 / tier 2 also fall through to the next tier on non-zero exit
# so PATH stubs in tests can force a specific tier deterministically.
# ---------------------------------------------------------------------------
parse_ticket_statuses() {
  local file="$1"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    return 1
  fi

  if _psf_have yq; then
    local _yq_out
    if _yq_out="$(yq -r '.tickets | .[] | .status // ""' "$file" 2>/dev/null)"; then
      [ -n "$_yq_out" ] && printf '%s\n' "$_yq_out"
      return 0
    fi
    # yq present but exited non-zero -> fall through to python tier.
  fi

  # Tier 2: python3 + PyYAML. Same gating rationale as parse_phase_status:
  # without the up-front `import yaml` probe a stock macOS without PyYAML
  # would short-circuit here on ImportError and skip the awk tier.
  if _psf_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    if python3 - "$file" <<'PY' 2>/dev/null
import sys
import yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
tickets = doc.get("tickets")
if isinstance(tickets, dict):
    entries = list(tickets.values())
elif isinstance(tickets, list):
    entries = tickets
else:
    entries = []
for entry in entries:
    val = entry.get("status", "") if isinstance(entry, dict) else ""
    print(val if val is not None else "")
PY
    then
      return 0
    fi
    # python tier failed -> fall through to awk.
  fi

  # awk fallback: walk the `tickets:` block looking for `status:` values
  # inside each element. POSIX awk only — uses `sub()` strip-by-prefix
  # instead of the gawk-specific 3-arg `match(s, re, arr)` so macOS's
  # stock BSD awk handles this tier.
  #
  # Two element-opener shapes are recognised (WI-4):
  #   - list form: `^[[:space:]]*-[[:space:]]` (e.g. `  - logical_id: …`)
  #   - map form: `^  <key>:[[:space:]]*$` (e.g. `  pomodoro-timer-part-1:`)
  # In both shapes the sibling `status:` line sits at 4-space indent and
  # is captured the same way. Inline-flow `{status: pending}` maps are not
  # produced by autopilot writers, so a line-oriented parser is sufficient.
  awk '
    BEGIN { in_tickets = 0; in_item = 0 }
    /^tickets:[[:space:]]*$/ { in_tickets = 1; next }
    in_tickets && /^[^[:space:]-]/ { in_tickets = 0; in_item = 0 }
    # list form: dash-prefixed element start.
    in_tickets && /^[[:space:]]*-[[:space:]]/ { in_item = 1 }
    # map form: bare 2-space-indented key under tickets: opens a new element.
    in_tickets && /^  [A-Za-z0-9._-]+:[[:space:]]*$/ { in_item = 1 }
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
# Public function: find_done_autopilot_state_file
# Usage: find_done_autopilot_state_file [ttl_seconds] [start_dir]
#
# Counterpart to `find_any_autopilot_state_file` that scans
# `.simple-workflow/backlog/briefs/done/` instead of briefs/active +
# product_backlog. Used by `hooks/scout-checkpoint-guard.sh` Step 2a
# (autopilot-completion gate) to detect the "autopilot just finished"
# state independently of phase-state.yaml location.
#
# Returns the absolute path of the most-recently-modified
# `autopilot-state.yaml` under briefs/done/. When the first positional
# argument is a positive integer, the helper additionally requires the
# match's mtime to be strictly newer than (now - ttl_seconds); matches
# at exactly the TTL boundary fall through to a return-1 (defensive
# strict-less-than). A zero or empty ttl_seconds disables the TTL
# check; the helper then returns the newest match unconditionally
# (useful for the SW_AUTOPILOT_DONE_GATE_TTL_SEC=0 kill switch).
#
# Returns 1 (no stdout) when briefs/done/ is absent, empty, or the
# newest match is older than the TTL. Symlink resolution mirrors the
# pattern in find_state_file / find_any_autopilot_state_file: the
# emitted path is the canonical absolute path resolved via
# `cd ... && pwd -P`.
# ---------------------------------------------------------------------------
find_done_autopilot_state_file() {
  local ttl_seconds="${1:-0}"
  local start_dir="${2:-$PWD}"

  # Defensive coercion: only positive integers are honored. A non-numeric
  # value collapses to 0 (disabled TTL check) so a typo in the caller's
  # env-var passthrough cannot accidentally silent-exit the gate by
  # treating an arbitrary string as a giant TTL.
  case "$ttl_seconds" in
    ''|*[!0-9]*) ttl_seconds=0 ;;
  esac

  local root
  root="$(_psf_repo_root "$start_dir")"
  [ -d "$root/.simple-workflow" ] || return 1

  local done_dir="$root/.simple-workflow/backlog/briefs/done"
  [ -d "$done_dir" ] || return 1

  local match=""
  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    if [ -z "$match" ] || [ "$_f" -nt "$match" ]; then
      match="$_f"
    fi
  done < <(find "$done_dir" -type f -name 'autopilot-state.yaml' 2>/dev/null)
  unset _f

  [ -n "$match" ] || return 1

  # TTL check: when ttl_seconds > 0, the file mtime must satisfy
  # (now - mtime) < ttl_seconds. POSIX `stat -c %Y` is GNU; on BSD/macOS
  # it is `stat -f %m`. Use the portable awk-on-find combination to
  # avoid OS-specific stat invocations.
  if [ "$ttl_seconds" -gt 0 ] 2>/dev/null; then
    local now mtime age
    now="$(date +%s)"
    # find with -printf is GNU-only; use a portable two-step instead.
    if mtime="$(stat -f %m "$match" 2>/dev/null)" && [ -n "$mtime" ]; then
      :
    elif mtime="$(stat -c %Y "$match" 2>/dev/null)" && [ -n "$mtime" ]; then
      :
    else
      # stat unavailable in both forms — fail closed (do not silently
      # accept the match; the gate should fall through to existing
      # logic rather than silent-exit on unknown freshness).
      return 1
    fi
    age=$((now - mtime))
    [ "$age" -lt "$ttl_seconds" ] || return 1
  fi

  local d b
  d="$(cd "$(dirname "$match")" && pwd -P)"
  b="$(basename "$match")"
  printf '%s/%s\n' "$d" "$b"
  return 0
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

  # WI-3 schema-tolerance: accept BOTH canonical-flat
  # (`steps.ship: completed`) and nested (`steps.ship.status: completed`)
  # forms. The autopilot SKILL canonical schema is flat (state-file.md
  # §"`autopilot-state.yaml` schema"), but real autopilot runs have
  # produced the nested form (test_simple_workflow27 evidence). Tolerate
  # both at the hook layer so a model schema slip does not silently
  # disable auto-compact; the SKILL layer enforces canonical for fresh
  # writes. Also tolerate `tickets:` as both list (`- logical_id: …`)
  # and map (`pomodoro-timer-part-1:`) — yq's `.[]` iterates either.
  if _psf_have yq; then
    yq -r '
      .tickets | .[] |
      select(
        (.steps.ship // "") == "completed"
        or (.steps.ship.status // "") == "completed"
      ) |
      (.ticket_dir // "")
    ' "$file" 2>/dev/null
    return 0
  fi

  if _psf_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY' 2>/dev/null
import sys
import yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
tickets = doc.get("tickets")
if isinstance(tickets, dict):
    entries = list(tickets.values())
elif isinstance(tickets, list):
    entries = tickets
else:
    entries = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    steps = entry.get("steps") or {}
    if not isinstance(steps, dict):
        continue
    ship = steps.get("ship")
    ship_done = False
    if ship == "completed":
        ship_done = True
    elif isinstance(ship, dict) and ship.get("status") == "completed":
        ship_done = True
    if not ship_done:
        continue
    val = entry.get("ticket_dir", "")
    print(val if val is not None else "")
PY
    return 0
  fi

  # awk fallback: stateful walk. POSIX awk only. Handles both
  # `tickets:` list form (`- logical_id: ...`) and map form
  # (`pomodoro-timer-part-1:`), and both `ship: completed` (flat) and
  # `ship:\n  status: completed` (nested) ship-status shapes. The
  # single-quote in `gsub(/^'\''|'\''$/, "", val)` is escaped via bash
  # string concat — same idiom as parse_ticket_statuses above.
  awk '
    function emit() {
      if (in_item && pending_ship == "completed" && pending_dir != "") {
        print pending_dir
      }
      pending_dir = ""
      pending_ship = ""
      in_nested_ship = 0
    }
    BEGIN {
      in_tickets = 0; in_item = 0; pending_dir = ""; pending_ship = ""
      in_nested_ship = 0; nested_ship_line = 0
    }
    /^tickets:[[:space:]]*$/ { in_tickets = 1; next }
    in_tickets && /^[^[:space:]-]/ { emit(); in_tickets = 0; in_item = 0; next }
    # List form: `  - logical_id: ...` (or `  - ticket_dir: ...`) — new element.
    in_tickets && /^[[:space:]]*-[[:space:]]/ { emit(); in_item = 1; next }
    # Map form: top-level (2-space-indent) key under tickets: opens new element.
    in_tickets && /^  [A-Za-z0-9._-]+:[[:space:]]*$/ { emit(); in_item = 1; next }
    in_tickets && in_item && /^[[:space:]]+ticket_dir:[[:space:]]+/ {
      val = $0
      sub(/^[[:space:]]+ticket_dir:[[:space:]]+/, "", val)
      gsub(/^"|"$/, "", val)
      gsub(/^'\''|'\''$/, "", val)
      sub(/[[:space:]]+#.*$/, "", val)
      pending_dir = val
      next
    }
    # Flat: `      ship: completed`
    in_tickets && in_item && /^[[:space:]]+ship:[[:space:]]+completed[[:space:]]*$/ {
      pending_ship = "completed"
      in_nested_ship = 0
      next
    }
    # Nested opener: `      ship:` (no value on same line) starts nested block.
    in_tickets && in_item && /^[[:space:]]+ship:[[:space:]]*$/ {
      in_nested_ship = 1; nested_ship_line = NR
      next
    }
    # Inside nested ship: look for `status: completed` within 4 lines.
    in_nested_ship && /^[[:space:]]+status:[[:space:]]+completed[[:space:]]*$/ {
      pending_ship = "completed"
      in_nested_ship = 0
      next
    }
    in_nested_ship && (NR - nested_ship_line) > 4 { in_nested_ship = 0 }
    END { emit() }
  ' "$file"
  return 0
}

# ---------------------------------------------------------------------------
# Public function: parse_active_steps
# Usage: parse_active_steps <state_file>
#
# Emits one line per pipeline step whose status is `in_progress` or `pending`,
# across every ticket, in document order, formatted as `<step_key>:<status>`
# (e.g. `scout:in_progress`). The autopilot Stop hook
# (`hooks/autopilot-continue.sh`) consumes this to decide whether unfinished
# step-level work remains (line count) and which step runs next (first
# `in_progress`, else first `pending`).
#
# WI-3 schema-tolerance: accepts the canonical-flat (`scout: in_progress`),
# inline-flow (`steps: {scout: in_progress, ...}`), and nested
# (`scout:\n  status: in_progress`) step shapes — the same forms the
# auto-compact path tolerates — so a model schema slip does not silently
# strand the continuation driver. Returns 1 only on a missing/empty file
# argument; an empty step set is a normal rc=0 result.
# ---------------------------------------------------------------------------
parse_active_steps() {
  local file="$1"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    return 1
  fi

  if _psf_have yq; then
    yq -r '
      .tickets[].steps // {} | to_entries[] |
      select((.value.status // .value) == "in_progress"
             or (.value.status // .value) == "pending") |
      .key + ":" + (.value.status // .value)
    ' "$file" 2>/dev/null
    return 0
  fi

  if _psf_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" <<'PY' 2>/dev/null
import sys
import yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
tickets = doc.get("tickets")
if isinstance(tickets, dict):
    entries = list(tickets.values())
elif isinstance(tickets, list):
    entries = tickets
else:
    entries = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    steps = entry.get("steps") or {}
    if not isinstance(steps, dict):
        continue
    for key, val in steps.items():
        st = val.get("status") if isinstance(val, dict) else val
        if st in ("in_progress", "pending"):
            print("%s:%s" % (key, st))
PY
    return 0
  fi

  # awk fallback: stateful walk, POSIX awk only. Handles flat
  # (`scout: in_progress`), inline-flow (`steps: {scout: in_progress, ...}`),
  # and nested (`scout:\n  status: in_progress`) step shapes. Only the four
  # known step keys (create-ticket|scout|impl|ship) are matched directly, so
  # there is no collision with the ticket-level `status:` field; the nested
  # `status:` line is consumed only while a step opener is pending (cur_key).
  awk '
    BEGIN { in_tickets = 0; cur_key = "" }
    /^tickets:[[:space:]]*$/ { in_tickets = 1; next }
    in_tickets && /^[^[:space:]-]/ { in_tickets = 0; cur_key = "" }
    in_tickets && /^[[:space:]]+steps:[[:space:]]*\{.*\}[[:space:]]*$/ {
      line = $0
      sub(/^[[:space:]]+steps:[[:space:]]*\{/, "", line)
      sub(/\}[[:space:]]*$/, "", line)
      n = split(line, pairs, /,/)
      for (i = 1; i <= n; i++) {
        kv = pairs[i]; ci = index(kv, ":")
        if (ci > 0) {
          k = substr(kv, 1, ci - 1); v = substr(kv, ci + 1)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
          if (v == "in_progress" || v == "pending") print k ":" v
        }
      }
      cur_key = ""
      next
    }
    in_tickets && /^[[:space:]]+(create-ticket|scout|impl|ship):/ {
      line = $0; sub(/^[[:space:]]+/, "", line); ci = index(line, ":")
      k = substr(line, 1, ci - 1); v = substr(line, ci + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      sub(/[[:space:]]+#.*$/, "", v)
      if (v == "") { cur_key = k }
      else { if (v == "in_progress" || v == "pending") print k ":" v; cur_key = "" }
      next
    }
    in_tickets && cur_key != "" && /^[[:space:]]+status:[[:space:]]*/ {
      line = $0; sub(/^[[:space:]]+status:[[:space:]]*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "in_progress" || line == "pending") print cur_key ":" line
      cur_key = ""
      next
    }
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

# ---------------------------------------------------------------------------
# Public function: parse_yaml_scalar
# Usage: parse_yaml_scalar <file_path> <key>
#
# Generic top-level YAML scalar reader. Mirrors the three-tier strategy of
# parse_phase_status / parse_impl_next_action so a new top-level invariant
# (e.g. `overall_status:` for the post-ship integrity self-heal) does not
# need its own bespoke parser. The contract is intentionally narrow:
#   - Only top-level keys are supported (no `.phases.ship.status` dotted
#     paths — callers needing nested traversal should use a dedicated
#     helper such as parse_phase_status).
#   - `null` / `~` / missing key all normalise to an empty string on
#     stdout so consumers can test `[ -n "$out" ]` uniformly.
#   - File-not-found returns rc 1 with no stdout; missing-args returns rc 2.
# ---------------------------------------------------------------------------
parse_yaml_scalar() {
  local file="$1"
  local key="$2"
  if [ -z "$file" ] || [ -z "$key" ]; then
    return 2
  fi
  if [ ! -f "$file" ]; then
    return 1
  fi

  if _psf_have yq; then
    local out
    out="$(yq -r ".${key} // \"\"" "$file" 2>/dev/null || true)"
    [ "$out" = "null" ] && out=""
    printf '%s\n' "$out"
    return 0
  fi

  # Tier 2: python3 + PyYAML. Gated on `import yaml` probe so a stock
  # macOS without PyYAML falls through to the awk tier rather than
  # silently short-circuiting empty on ImportError.
  if _psf_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$file" "$key" <<'PY' 2>/dev/null || return 1
import sys
import yaml
path, key = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
val = doc.get(key, "") if isinstance(doc, dict) else ""
if val is None:
    val = ""
print(val)
PY
    return 0
  fi

  # awk fallback: locate `<key>:` at column 0 (top-level scalar) and emit
  # the value with the same normalisation as the other awk fallbacks in
  # this lib (strip quotes, strip trailing comments, treat `null`/`~`
  # as empty). POSIX awk only — uses `sub()` strip-by-prefix instead of
  # the gawk-specific 3-arg `match()` form so macOS BSD awk works.
  awk -v key="$key" '
    $0 ~ "^"key":[[:space:]]" {
      val = $0
      sub("^"key":[[:space:]]+", "", val)
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
# Public function: get_risk_tolerance
# Usage: get_risk_tolerance <state_dir>
#
# Reads `risk_tolerance:` from <state_dir>/autopilot-policy.yaml and prints
# one of "aggressive" / "moderate" / "conservative" to stdout. Fallback for
# file-missing / key-absent / unparsable / unknown-value is the literal
# "conservative" -- see header doc comment for rationale.
#
# Three-tier strategy matches the other helpers in this lib:
#   1. yq -r '.risk_tolerance // ""' <file>
#   2. python3 + PyYAML (gated on `import yaml` probe so macOS without
#      PyYAML falls through to tier 3 rather than short-circuiting empty)
#   3. POSIX awk fallback walking `^risk_tolerance:[[:space:]]+(\S+)`
#
# The trailing case validator normalises unknown values (NAC-5 evidence
# in P1-3B): an `aggressive` fallback would gridlock recovery paths so
# `conservative` is the deliberate fail-open choice.
# ---------------------------------------------------------------------------
get_risk_tolerance() {
  local state_dir="$1"
  local file="${state_dir%/}/autopilot-policy.yaml"
  local out=""
  if [ -f "$file" ]; then
    if _psf_have yq; then
      out="$(yq -r '.risk_tolerance // ""' "$file" 2>/dev/null || true)"
      [ "$out" = "null" ] && out=""
    fi
    if [ -z "$out" ] && _psf_have python3 \
        && python3 -c 'import yaml' >/dev/null 2>&1; then
      out="$(python3 - "$file" <<'PY' 2>/dev/null
import sys, yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
val = doc.get("risk_tolerance", "")
print(val if val is not None else "")
PY
)"
    fi
    if [ -z "$out" ]; then
      out="$(awk '
        /^risk_tolerance:[[:space:]]+/ {
          val=$0
          sub(/^risk_tolerance:[[:space:]]+/, "", val)
          gsub(/^"|"$/, "", val)
          gsub(/^'\''|'\''$/, "", val)
          sub(/[[:space:]]+#.*$/, "", val)
          if (val == "null" || val == "~") val = ""
          print val
          exit 0
        }
      ' "$file" 2>/dev/null || true)"
    fi
  fi
  case "$out" in
    aggressive|moderate|conservative) printf '%s\n' "$out" ;;
    *) printf '%s\n' "conservative" ;;
  esac
}

# ---------------------------------------------------------------------------
# Public function: resolve_parallel_mode
# Usage: resolve_parallel_mode <state_file>
#
# The single parallel-execution mode resolver that every parallel-aware hook
# reads identically (the T-004/5/6 rework consumes it; it is (B) harness-own
# plumbing, used by hooks, not by any agent). Resolves with precedence:
#   1. SW_PARALLEL_HOOKS_MODE  (env override; a SET-but-unknown value -> off)
#   2. parallel_mode: scalar in <state_file>  (absent / null / unknown -> off)
#   3. off  (the default / fail-closed direction)
#
# Prints EXACTLY one of `on` / `metric-only` / `off` to stdout, NEVER empty.
# Every ambiguity fails CLOSED to `off` — the proven serial / byte-identical
# path (the conservative direction, mirroring the tri-value
# SW_AUTOPILOT_POLICY_STOP_HONOR / SW_SCOUT_CHECKPOINT_MODE convention and the
# `get_risk_tolerance` case-validator above). Env precedence: a SET env value
# is authoritative and an unknown SET value returns `off` WITHOUT falling
# through to the state scalar (an explicit-but-garbage override must not
# silently re-enable a state mode the operator was trying to suppress); an
# unset / empty env value falls through to the state scalar (the documented
# "default = follow parallel_mode"). A missing / unreadable <state_file>
# resolves `off` at the state tier.
# ---------------------------------------------------------------------------
resolve_parallel_mode() {
  local state_file="$1"
  local env_mode="${SW_PARALLEL_HOOKS_MODE:-}"

  # Tier 1: env override. A non-empty env value is authoritative.
  if [ -n "$env_mode" ]; then
    case "$env_mode" in
      on|metric-only|off) printf '%s\n' "$env_mode"; return 0 ;;
      *) printf '%s\n' "off"; return 0 ;;   # unknown SET value -> off (no fall-through)
    esac
  fi

  # Tier 2: parallel_mode: scalar in the state file (unset/empty env falls here).
  local state_mode=""
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    state_mode="$(parse_yaml_scalar "$state_file" parallel_mode 2>/dev/null || true)"
  fi
  case "$state_mode" in
    on|metric-only|off) printf '%s\n' "$state_mode"; return 0 ;;
    *) printf '%s\n' "off"; return 0 ;;   # absent / null / unknown / missing-file -> off
  esac
}

# Export the public functions so children that re-enter bash via `bash -c`
# can pick them up without re-sourcing. (Bash only — POSIX `sh` ignores
# `export -f`. Hooks already require Bash, so this is safe.)
export -f is_autopilot_context parse_phase_status parse_ticket_statuses find_state_file find_any_autopilot_state_file find_done_autopilot_state_file parse_ticket_ship_dirs find_phase_state_file parse_impl_next_action parse_yaml_scalar get_risk_tolerance resolve_parallel_mode 2>/dev/null || true
