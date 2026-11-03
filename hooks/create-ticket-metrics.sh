#!/usr/bin/env bash
# create-ticket-metrics.sh -- SubagentStop hook (P1-13) that records every
# /create-ticket Phase 4 ticket-evaluator verdict as ONE JSON line in
# <root>/.simple-workflow/metrics/create-ticket.jsonl, so the first-PASS rate
# and the retry count of the ticket-quality gate can be measured.
#
# Why a hook and why a dedicated log file:
#   - The orchestrator never writes this file (skills/create-ticket/SKILL.md
#     Phase 4 forbids it); a hook records the outcome deterministically, with
#     no model recall.
#   - At Phase 4 time no state file exists yet: the ticket dir and its
#     phase-state.yaml are created only after a PASS (Common Write Path), and
#     autopilot-state.yaml exists only under /autopilot or /brief chain=on. So
#     the row cannot ride `runtime_metrics:`; it goes to an append-only JSONL
#     log of its own (schema: docs/state-schema.md, `Phase 4 verdict log`).
#
# Registration (hooks/hooks.json): its OWN top-level SubagentStop entry with
# matcher `^(simple-workflow:)?ticket-evaluator$`. Hooks on one event run in
# parallel with no ordering (CLAUDE.md `## Hooks`), so this hook depends on no
# sibling and shares no file with one. The agent_type is re-checked below in
# case the matcher is absent or ignored on an older CLI.
#
# Depends on:
#   - hooks/lib/parse-state-file.sh: `_psf_repo_root`, the strict
#     `.simple-workflow/backlog/` anchor that hooks/session-stop-log.sh also
#     uses. Sourced only when present; without it <root> is the payload cwd.
#
# Public contract (hook input / output):
#   stdin:  SubagentStop JSON payload, e.g.
#           {"session_id":"...","cwd":"...","hook_event_name":"SubagentStop",
#            "effort":{"level":"high"},"stop_hook_active":false,
#            "agent_id":"...","agent_type":"simple-workflow:ticket-evaluator",
#            "last_assistant_message":"## Result\n**Status**: PASS\n...", ...}
#   stdout: empty on EVERY path. SubagentStop reads stdout JSON as a decision;
#           this hook never emits one.
#   stderr: `[TICKET-EVAL-METRICS] verdict=<v> seq=<n>` once per written row;
#           `[TICKET-EVAL-METRICS] metric-only: would append <row>` in
#           metric-only mode; `[TICKET-EVAL-METRICS] WARN: ...` /
#           `[TICKET-EVAL-METRICS] WARNING ...` on best-effort failures and
#           on an unknown knob value, both only for a ticket-evaluator stop.
#           No path is ever printed: the shell's own diagnostics on the append
#           and the parse (a failed redirection, an ignored NUL byte), which
#           name the hook path or the log path, are discarded.
#   exit:   ALWAYS 0. Exit 2 on SubagentStop PREVENTS the subagent from
#           stopping, so every failure (unparsable payload, missing jq,
#           unwritable directory, lock timeout) degrades to a silent or
#           warned exit 0.
#
# <root>: the payload `cwd` (the hook's working directory when the field is
# missing, relative, or names no existing directory), raised to the nearest
# ancestor that holds `.simple-workflow/backlog/` when one exists. A session
# that `cd`s into a subdirectory, or into `.simple-workflow/kb/`, therefore
# keeps one log (and one seq count) instead of starting a decoy
# `<subdir>/.simple-workflow/` tree.
#
# Verdict: parsed from `last_assistant_message`, the text of the subagent's
# final response, which agents/ticket-evaluator.md (Context Conservation
# Protocol) makes the `## Result` block carrying `**Status**: PASS | FAIL`
# (Status: ERROR on the rubric fail-fast). A Status line is
# `Status: <V>` with V in PASS | FAIL | ERROR, matched case-insensitively and
# stored upper-cased; `*` and backtick decoration around the key and the value
# is allowed (`**Status**:`, `**Status:**`, `` `PASS` ``). Not a verdict: a
# longer word (`PASSED`) and the unfilled template line `**Status**: PASS |
# FAIL`. Two passes, the first that finds a Status line wins:
#   1. lines outside triple-backtick fences only (a fenced Status is a quote);
#   2. every line, fences included (the agent's return-format template is
#      itself fenced, so a model that echoes the fence wraps the real verdict
#      in one; the tests/helpers/audit-summary.sh `strip_masked` convention of
#      always masking fences would record those stops as UNKNOWN).
# In each pass, when a `## Result` heading exists only the lines after the LAST
# one count (a preamble `- Status: FAIL` before it is ignored), otherwise the
# whole message counts; the first Status line in that region wins. Nothing
# found -> verdict UNKNOWN. `agent_transcript_path` is NEVER read (it is
# written asynchronously and can lag the stop).
#
# Row (one line, serialised by `jq -c -n --arg ...` so every value is
# escaped): ts (null only when `date` fails), event ("ticket_eval"),
# session_id, agent_id, agent_type (the `simple-workflow:` prefix stripped),
# verdict, seq, effort (the payload's `effort.level`), plugin_version (the
# plugin.json next to this hook), stop_hook_active. `seq` = the number of rows
# already in the file with the same session_id, plus one, taken under the
# lock. No path (cwd, transcript_path, report path), no ticket text and no
# evaluator feedback is ever written into a row.
#
# Lock: the count + append is serialised by a `<file>.lock` mkdir lock with a
# bounded wait (100 x 20 ms) and a stale-lock takeover, the same pattern as
# hooks/lib/runtime-metrics.sh. That file's `_rm_lock_acquire` is NOT reused:
# it is a private (underscore) helper of the runtime_metrics YAML writer, and
# sourcing that library would make this hook one of its `Sourced by:` callers,
# the list CT-RM-WRITERS treats as the runtime_metrics writer set, which this
# hook is not. When the lock cannot be taken the row is still appended (one
# small O_APPEND write, so lines never interleave); only its seq may repeat.
# Known limits, shared with that library: the takeover is time-based, with no
# check that the holder is dead, so a holder still counting after the 2 s
# wait (a log of hundreds of thousands of rows) can lose the lock and seq can
# then repeat; and a regular file or a non-empty directory at the `.lock` path
# cannot be taken over, so every stop waits the full 2 s and appends unlocked
# until someone removes it.
#
# jq is required both to parse the payload and to serialise the row. When it
# is missing the hook exits 0 silently: there is deliberately no pure-shell
# JSON fallback, because one malformed line would poison the log.
#
# Kill switch SW_CREATE_TICKET_METRICS_MODE:
#   on (DEFAULT)  -> append the row.
#   metric-only   -> log the would-be row to stderr, write nothing.
#   off           -> silent exit 0.
#   unknown       -> collapses to `on` with a one-line WARNING (printed only
#                    for a ticket-evaluator stop, so a CLI that ignores the
#                    matcher does not warn on every subagent). A deliberate
#                    inversion of the usual unknown -> metric-only/off rule:
#                    the hook can never block or alter a run, so the
#                    fail-safe direction is to keep recording.

set -uo pipefail

# NUL bytes are dropped before the shell sees them: a command substitution
# would otherwise print a warning that names this hook's path.
INPUT=$(tr -d '\000' 2>/dev/null || true)

MODE_RAW="${SW_CREATE_TICKET_METRICS_MODE:-on}"
MODE_WARN=""
case "$MODE_RAW" in
  on|metric-only|off) MODE="$MODE_RAW" ;;
  *)
    MODE="on"
    MODE_WARN="$MODE_RAW"
    ;;
esac
[ "$MODE" = "off" ] && exit 0

# jq is a hard dependency for both parse and serialise; silent skip without it.
command -v jq >/dev/null 2>&1 || exit 0

_ctm_warn() {
  printf '[TICKET-EVAL-METRICS] WARN: %s\n' "$*" >&2
}

# Extract a non-empty string field, empty otherwise (missing, null, non-string,
# or an unparsable payload).
_ctm_jq_str() {
  printf '%s' "$INPUT" | jq -r "($1) | if type == \"string\" then . else empty end" 2>/dev/null | tr -d '\000' || true
}

# --- agent_type guard ---------------------------------------------------------
# The matcher already scopes the entry; this re-check keeps the hook inert for
# every other agent when the matcher is absent or ignored (older CLI).
AGENT_TYPE=$(_ctm_jq_str '.agent_type')
AGENT_TYPE="${AGENT_TYPE#simple-workflow:}"
[ "$AGENT_TYPE" = "ticket-evaluator" ] || exit 0

# Deferred until after the guard: a non-matching stop stays silent.
if [ -n "$MODE_WARN" ]; then
  printf '[TICKET-EVAL-METRICS] WARNING unknown SW_CREATE_TICKET_METRICS_MODE=%s; using on\n' "$MODE_WARN" >&2
fi

# --- verdict ------------------------------------------------------------------
# _ctm_scan <include_fenced 0|1> <message>: prints the upper-cased token of the
# first Status line in the scoped region (see the header), or nothing.
_ctm_scan() {
  local include_fenced="$1" msg="$2" line token rest
  local fenced=0 seen_heading=0 before="" after=""
  local re='^[[:space:]#>*`-]*Status[*`]*[[:space:]]*:[[:space:]*`]*(PASS|FAIL|ERROR)(.*)$'
  local rest_re_word='^[A-Za-z0-9_-]'
  local rest_re_placeholder='^[[:space:]*`]*[|]'
  local fence_re='^[[:space:]]{0,3}```'
  local heading_re='^[[:space:]]{0,3}#{1,6}[[:space:]]+Result[[:space:]]*:?[[:space:]]*$'
  # Case-insensitive matching; this runs inside a command substitution, so the
  # option does not leak into the rest of the hook.
  shopt -s nocasematch
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$include_fenced" = "0" ]; then
      if [[ "$line" =~ $fence_re ]]; then
        fenced=$((1 - fenced))
        continue
      fi
      [ "$fenced" = "1" ] && continue
    fi
    if [[ "$line" =~ $heading_re ]]; then
      seen_heading=1
      after=""
      continue
    fi
    if [[ "$line" =~ $re ]]; then
      # Copy the captures first: every later =~ overwrites BASH_REMATCH.
      token="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
      # `PASSED`, `PASS-WITH-...`: not the contract token.
      [[ "$rest" =~ $rest_re_word ]] && continue
      # The unfilled template line `**Status**: PASS | FAIL`.
      [[ "$rest" =~ $rest_re_placeholder ]] && continue
      if [ "$seen_heading" = "1" ]; then
        [ -n "$after" ] || after="$token"
      else
        [ -n "$before" ] || before="$token"
      fi
    fi
  done <<< "$msg"
  if [ "$seen_heading" = "1" ]; then token="$after"; else token="$before"; fi
  [ -n "$token" ] && printf '%s' "$token" | tr '[:lower:]' '[:upper:]'
  return 0
}

_ctm_verdict() {
  local v
  v=$(_ctm_scan 0 "$1")
  [ -n "$v" ] || v=$(_ctm_scan 1 "$1")
  printf '%s' "${v:-UNKNOWN}"
}

LAST_MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message | if type == "string" then . else "" end' 2>/dev/null | tr -d '\000' || true)
VERDICT=$(_ctm_verdict "$LAST_MSG" 2>/dev/null)
case "$VERDICT" in
  PASS|FAIL|ERROR|UNKNOWN) ;;
  *) VERDICT="UNKNOWN" ;;
esac

# --- remaining row fields -----------------------------------------------------
SESSION_ID=$(_ctm_jq_str '.session_id')
AGENT_ID=$(_ctm_jq_str '.agent_id')
# `effort` is an object `{level: ...}`; accept a bare string from an older CLI.
EFFORT=$(_ctm_jq_str '.effort | if type == "object" then (.level // empty) else . end')
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r 'if .stop_hook_active == true then "true" else "false" end' 2>/dev/null || true)
[ "$STOP_HOOK_ACTIVE" = "true" ] || STOP_HOOK_ACTIVE="false"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_VERSION=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../.claude-plugin/plugin.json" ]; then
  PLUGIN_VERSION=$(jq -r '.version | if type == "string" then . else empty end' "$SCRIPT_DIR/../.claude-plugin/plugin.json" 2>/dev/null || true)
fi
# Keep only a version-shaped value so nothing path-like can reach the row.
case "$PLUGIN_VERSION" in
  *[!0-9A-Za-z.+-]*) PLUGIN_VERSION="" ;;
esac

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)

# --- target file (the path is used, never written into the row) ---------------
CWD=$(_ctm_jq_str '.cwd')
case "$CWD" in
  /*) [ -d "$CWD" ] || CWD="$PWD" ;;
  *) CWD="$PWD" ;;
esac
ROOT="$CWD"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/lib/parse-state-file.sh" ]; then
  # shellcheck source=lib/parse-state-file.sh
  . "$SCRIPT_DIR/lib/parse-state-file.sh" 2>/dev/null || true
fi
if declare -F _psf_repo_root >/dev/null 2>&1; then
  # Prints the anchored ancestor, or the start directory (rc 1) when none.
  ROOT=$(_psf_repo_root "$CWD" 2>/dev/null || true)
  if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then ROOT="$CWD"; fi
fi
METRICS_DIR="$ROOT/.simple-workflow/metrics"
METRICS_FILE="$METRICS_DIR/create-ticket.jsonl"

# Rows already in the file for this session. Lines that do not parse are
# skipped, so one corrupt line cannot skew every later seq.
_ctm_prior_count() {
  local n
  [ -f "$METRICS_FILE" ] || { printf '0'; return 0; }
  n=$(jq -R --arg sid "$SESSION_ID" \
        'fromjson? // empty | select(type == "object") | select(.session_id == (if $sid == "" then null else $sid end)) | 1' \
        "$METRICS_FILE" 2>/dev/null | wc -l | tr -d '[:space:]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

_ctm_row() {
  # $1 seq (validated non-negative integer)
  jq -c -n \
    --arg ts "$TS" \
    --arg sid "$SESSION_ID" \
    --arg aid "$AGENT_ID" \
    --arg at "$AGENT_TYPE" \
    --arg v "$VERDICT" \
    --argjson seq "$1" \
    --arg eff "$EFFORT" \
    --arg pv "$PLUGIN_VERSION" \
    --argjson sha "$STOP_HOOK_ACTIVE" \
    'def nz: if . == "" then null else . end;
     {ts: ($ts | nz), event: "ticket_eval", session_id: ($sid | nz),
      agent_id: ($aid | nz), agent_type: $at, verdict: $v, seq: $seq,
      effort: ($eff | nz), plugin_version: ($pv | nz), stop_hook_active: $sha}' \
    2>/dev/null || true
}

if [ "$MODE" = "metric-only" ]; then
  SEQ=$(( $(_ctm_prior_count) + 1 ))
  ROW=$(_ctm_row "$SEQ")
  [ -n "$ROW" ] && printf '[TICKET-EVAL-METRICS] metric-only: would append %s\n' "$ROW" >&2
  exit 0
fi

# --- mode on: locked count + append --------------------------------------------
if ! mkdir -p "$METRICS_DIR" 2>/dev/null || [ ! -d "$METRICS_DIR" ] || [ ! -w "$METRICS_DIR" ]; then
  _ctm_warn "metrics directory is not writable; verdict=$VERDICT not recorded"
  exit 0
fi

LOCK_DIR="$METRICS_FILE.lock"
LOCK_HELD=0
_ctm_release() {
  if [ "$LOCK_HELD" = "1" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_HELD=0
  fi
}
trap _ctm_release EXIT

_ctm_lock_acquire() {
  local i=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
      # Stale lock (holder crashed) or pathological contention: take it over.
      rmdir "$LOCK_DIR" 2>/dev/null || true
      mkdir "$LOCK_DIR" 2>/dev/null && return 0
      return 1
    fi
    sleep 0.02
  done
  return 0
}

if _ctm_lock_acquire; then
  LOCK_HELD=1
else
  _ctm_warn "lock not acquired after the bounded wait; appending unlocked (seq may repeat)"
fi

SEQ=$(( $(_ctm_prior_count) + 1 ))
ROW=$(_ctm_row "$SEQ")
if [ -z "$ROW" ]; then
  _ctm_warn "row serialisation failed; verdict=$VERDICT not recorded"
  exit 0
fi

# The group's 2>/dev/null also covers the redirection itself: a failed `>>`
# would otherwise print the log path on the hook's stderr.
if { printf '%s\n' "$ROW" >> "$METRICS_FILE"; } 2>/dev/null; then
  printf '[TICKET-EVAL-METRICS] verdict=%s seq=%s\n' "$VERDICT" "$SEQ" >&2
else
  _ctm_warn "append failed; verdict=$VERDICT not recorded"
fi

exit 0
