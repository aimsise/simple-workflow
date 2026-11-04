#!/usr/bin/env bash
# Behaviour tests for hooks/create-ticket-metrics.sh -- the SubagentStop hook
# that appends one JSON row per /create-ticket Phase 4 ticket-evaluator stop to
# <cwd>/.simple-workflow/metrics/create-ticket.jsonl (schema:
# docs/state-schema.md `## Phase 4 verdict log`).
#
# Every case asserts exit 0 AND an empty stdout: exit 2 on SubagentStop would
# keep the subagent from stopping, and stdout JSON would be read as a decision.
#
# Matrix: verdict parsing (PASS / FAIL / ERROR / UNKNOWN / unfilled template),
# the verdict policy (FAIL words outside the Status line, the region after the
# LAST `## Result` heading, the first Status line in it winning, unfenced lines
# before fenced ones, a fully fenced Result block, case-insensitive tokens,
# `*` / backtick decoration, CRLF, trailing spaces, `PASSED`), per-session seq
# (incl. a session_id that extends another, a missing session_id), agent_type
# normalisation and the non-matching no-op, stop_hook_active, the log root
# (cwd fallback, relative cwd, a subdirectory or `.simple-workflow/kb/` cwd
# raised to the `.simple-workflow/backlog/` anchor), a corrupt pre-existing
# line, the effort shapes, the kill-switch tri-state plus an unknown value
# (silent for a non-matching agent), the fail-open paths (jq absent, empty and
# unparsable stdin, unwritable directory, append failure, stale lock, a lock
# that cannot be taken), the no-path / no-PII guarantee on rows AND stderr,
# per-line JSON validity and 8 concurrent appends.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$HOOK_DIR/create-ticket-metrics.sh"
PLUGIN_VERSION=$(jq -r '.version' "$REPO_DIR/.claude-plugin/plugin.json")
BASH_BIN=$(command -v bash)

FIXROOT=$(mktemp -d)
cleanup() {
  chmod -R u+w "$FIXROOT" 2>/dev/null || true
  rm -rf "$FIXROOT"
}
trap cleanup EXIT

# The hook raises its log root to the nearest ancestor holding
# .simple-workflow/backlog/; with such an ancestor above the fixtures (TMPDIR
# inside a project) every row would land there, so fail legibly instead.
_anc="$(dirname "$FIXROOT")"
while [ "$_anc" != "/" ] && [ -n "$_anc" ]; do
  if [ -d "$_anc/.simple-workflow/backlog" ]; then
    echo "test-create-ticket-metrics.sh: a fixture ancestor holds .simple-workflow/backlog/; point TMPDIR outside any project" >&2
    exit 1
  fi
  _anc="$(dirname "$_anc")"
done

echo "=== create-ticket-metrics.sh Tests ==="
echo ""

pass_local() { echo -e "  ${GREEN}PASS${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1)); }
fail_local() {
  echo -e "  ${RED}FAIL${NC} $1"
  echo -e "       RC=$LAST_EXIT_CODE OUT=[$LAST_STDOUT] ERR=[$LAST_STDERR]"
  TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
}
skip_local() { echo -e "  ${YELLOW}SKIP${NC} $1"; }

# check <description> <true|false>: the case passes only when the hook also
# exited 0 with an empty stdout.
check() {
  if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ] && [ "$2" = "true" ]; then
    pass_local "$1"
  else
    fail_local "$1"
  fi
}

# cond <test args...>: prints true / false for use as check's second argument.
cond() { if "$@"; then echo true; else echo false; fi; }

newproj() { mktemp -d "$FIXROOT/proj.XXXXXX"; }
mfile() { printf '%s/.simple-workflow/metrics/create-ticket.jsonl' "$1"; }
line_count() {
  if [ -f "$1" ]; then wc -l < "$1" | tr -d '[:space:]'; else printf '0'; fi
}
# row_field <file> <line-number> <jq-expression>
row_field() { sed -n "${2}p" "$1" | jq -r "$3" 2>/dev/null; }

MSG_PASS=$'## Result\n**Status**: PASS\n**Output**: eval-report.md\n**Gate Results**:\n- [x] Testability: every AC is mechanically checkable\n**Issues**: none\n**Feedback**: none'
MSG_FAIL=$'## Result\n**Status**: FAIL\n**Output**: eval-report.md\n**Gate Results**:\n- [ ] Unambiguity: AC #2 -- FAILED: vague threshold\n**Issues**: [Unambiguity] AC #2\n**Feedback**: state the threshold'
MSG_ERROR=$'Status: ERROR\nERROR: canonical AC rubric missing from spawn prompt (expected <canonical_ac_criteria>...</canonical_ac_criteria> marker block)'
MSG_NONE=$'## Result\nThe evaluation could not be completed.'
MSG_TEMPLATE=$'## Result\n**Status**: PASS | FAIL\n**Output**: [evaluation report file path]'

# payload <cwd> <session_id> <agent_type|__absent__> <message> [stop_hook_active] [agent_id]
# The transcript paths are derived from <cwd> so the PII case can prove that no
# payload path reaches the row.
payload() {
  jq -n --arg cwd "$1" --arg sid "$2" --arg at "$3" --arg msg "$4" \
    --argjson sha "${5:-false}" --arg aid "${6:-agent-1}" \
    '{session_id: $sid,
      transcript_path: ($cwd + "/.claude/projects/p/" + $sid + ".jsonl"),
      cwd: $cwd, permission_mode: "default", hook_event_name: "SubagentStop",
      effort: {level: "high"}, stop_hook_active: $sha, agent_id: $aid,
      agent_transcript_path: ($cwd + "/.claude/projects/p/subagents/agent-" + $aid + ".jsonl"),
      last_assistant_message: $msg}
     + (if $at == "__absent__" then {} else {agent_type: $at} end)'
}

# run_ctm <payload> [VAR=value ...]: runs the hook from $RUN_DIR with the mode
# knob unset unless an assignment is passed.
RUN_DIR="$FIXROOT"
run_ctm() {
  local p="$1" so se
  shift
  so=$(mktemp); se=$(mktemp)
  printf '%s' "$p" | (cd "$RUN_DIR" && env -u SW_CREATE_TICKET_METRICS_MODE "$@" bash "$HOOK") >"$so" 2>"$se"
  LAST_EXIT_CODE=$?
  LAST_STDOUT=$(cat "$so"); LAST_STDERR=$(cat "$se"); rm -f "$so" "$se"
}

# ---- recording --------------------------------------------------------------
echo "--- recording: verdicts, seq, normalisation ---"
P1=$(newproj); F1=$(mfile "$P1")

run_ctm "$(payload "$P1" sess-A simple-workflow:ticket-evaluator "$MSG_PASS")"
check "PASS row written with seq 1" \
  "$( [ "$(line_count "$F1")" = 1 ] && [ "$(row_field "$F1" 1 .verdict)" = PASS ] && [ "$(row_field "$F1" 1 .seq)" = 1 ] && echo true || echo false)"
check "namespaced agent_type simple-workflow:ticket-evaluator normalised to ticket-evaluator" \
  "$(cond [ "$(row_field "$F1" 1 .agent_type)" = ticket-evaluator ])"
check "row carries event / session_id / agent_id / effort.level / plugin_version / stop_hook_active / UTC ts" \
  "$( [ "$(row_field "$F1" 1 .event)" = ticket_eval ] \
      && [ "$(row_field "$F1" 1 .session_id)" = sess-A ] \
      && [ "$(row_field "$F1" 1 .agent_id)" = agent-1 ] \
      && [ "$(row_field "$F1" 1 .effort)" = high ] \
      && [ "$(row_field "$F1" 1 .plugin_version)" = "$PLUGIN_VERSION" ] \
      && [ "$(row_field "$F1" 1 .stop_hook_active)" = false ] \
      && row_field "$F1" 1 .ts | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
      && echo true || echo false)"
check "row key order is ts,event,session_id,agent_id,agent_type,verdict,seq,effort,plugin_version,stop_hook_active" \
  "$(cond [ "$(row_field "$F1" 1 'keys_unsorted | join(",")')" = "ts,event,session_id,agent_id,agent_type,verdict,seq,effort,plugin_version,stop_hook_active" ])"
check "write emits [TICKET-EVAL-METRICS] verdict=PASS seq=1 on stderr" \
  "$(cond grep -qxF '[TICKET-EVAL-METRICS] verdict=PASS seq=1' <<<"$LAST_STDERR")"

run_ctm "$(payload "$P1" sess-A ticket-evaluator "$MSG_FAIL" false agent-2)"
check "second stop in the same session -> FAIL row with seq 2 (bare agent_type)" \
  "$( [ "$(line_count "$F1")" = 2 ] && [ "$(row_field "$F1" 2 .verdict)" = FAIL ] \
      && [ "$(row_field "$F1" 2 .seq)" = 2 ] && [ "$(row_field "$F1" 2 .agent_type)" = ticket-evaluator ] \
      && grep -qxF '[TICKET-EVAL-METRICS] verdict=FAIL seq=2' <<<"$LAST_STDERR" && echo true || echo false)"

run_ctm "$(payload "$P1" sess-B ticket-evaluator "$MSG_PASS" false agent-3)"
check "a different session starts at seq 1" \
  "$( [ "$(line_count "$F1")" = 3 ] && [ "$(row_field "$F1" 3 .session_id)" = sess-B ] \
      && [ "$(row_field "$F1" 3 .seq)" = 1 ] && echo true || echo false)"

run_ctm "$(payload "$P1" sess-C ticket-evaluator "$MSG_ERROR" false agent-4)"
check "Status: ERROR without bold -> verdict ERROR" \
  "$(cond [ "$(row_field "$F1" 4 .verdict)" = ERROR ])"

run_ctm "$(payload "$P1" sess-C ticket-evaluator "$MSG_NONE" false agent-5)"
check "no Status line -> verdict UNKNOWN (seq 2 in sess-C)" \
  "$( [ "$(row_field "$F1" 5 .verdict)" = UNKNOWN ] && [ "$(row_field "$F1" 5 .seq)" = 2 ] && echo true || echo false)"

run_ctm "$(payload "$P1" sess-C ticket-evaluator "$MSG_TEMPLATE" false agent-6)"
check "unfilled template line '**Status**: PASS | FAIL' -> verdict UNKNOWN" \
  "$(cond [ "$(row_field "$F1" 6 .verdict)" = UNKNOWN ])"

run_ctm "$(payload "$P1" sess-C ticket-evaluator "$MSG_PASS" true agent-6)"
check "stop_hook_active true still writes (stop_hook_active recorded true, same agent_id, seq advances)" \
  "$( [ "$(line_count "$F1")" = 7 ] && [ "$(row_field "$F1" 7 .stop_hook_active)" = true ] \
      && [ "$(row_field "$F1" 7 .agent_id)" = agent-6 ] && [ "$(row_field "$F1" 7 .seq)" = 4 ] \
      && [ "$(row_field "$F1" 7 .verdict)" = PASS ] && echo true || echo false)"

# ---- verdict policy ----------------------------------------------------------
# One fresh project per case; the expected value is the verdict of its only row.
echo "--- verdict policy: scope, precedence, fences, case, decoration ---"
verdict_case() {
  # verdict_case <expected> <description> <message>
  local pv
  pv=$(newproj)
  run_ctm "$(payload "$pv" sess-V ticket-evaluator "$3")"
  check "$2 -> verdict $1" \
    "$( [ "$(line_count "$(mfile "$pv")")" = 1 ] && [ "$(row_field "$(mfile "$pv")" 1 .verdict)" = "$1" ] \
        && grep -qxF "[TICKET-EVAL-METRICS] verdict=$1 seq=1" <<<"$LAST_STDERR" && echo true || echo false)"
}
FENCE='```'
verdict_case PASS "FAIL / FAILED in a preamble, a gate bullet and Issues, Status PASS" \
  $'Previous round FAIL fixed.\n## Result\n**Status**: PASS\n**Gate Results**:\n- [ ] Unambiguity: AC #2 -- FAILED earlier, now fixed\n**Issues**: the FAIL from round 1 is resolved'
verdict_case FAIL "two Status lines after the heading: the first one wins" \
  $'## Result\n**Status**: FAIL\n**Status**: PASS'
verdict_case PASS "a preamble '- Status: FAIL' before the heading is ignored" \
  $'- Status: FAIL (gate 1 draft)\n## Result\n**Status**: PASS'
verdict_case FAIL "only the region after the LAST ## Result heading counts" \
  $'## Result\n**Status**: PASS\n(re-graded)\n## Result\n**Status**: FAIL'
verdict_case UNKNOWN "a Status line only before the heading, none after it" \
  $'**Status**: PASS\n## Result\nno verdict line here'
verdict_case FAIL "a fenced Status: PASS quote before the unfenced Result block" \
  "$(printf '%s\n**Status**: PASS\n%s\n## Result\n**Status**: FAIL' "$FENCE" "$FENCE")"
verdict_case FAIL "no heading: a fenced Status: PASS quote before the unfenced Status: FAIL line" \
  "$(printf 'Quoted from the last round:\n%s\n**Status**: PASS\n%s\n**Status**: FAIL' "$FENCE" "$FENCE")"
verdict_case PASS "a fully fenced Result block (the echoed return-format template)" \
  "$(printf '%s\n## Result\n**Status**: PASS\n**Output**: eval-report.md\n%s' "$FENCE" "$FENCE")"
verdict_case FAIL "unfenced heading with the Status line fenced below it" \
  "$(printf '## Result\n%s\n**Status**: FAIL\n%s' "$FENCE" "$FENCE")"
verdict_case PASS "trailing spaces after the token" $'## Result\n**Status**: PASS   \n**Issues**: none'
verdict_case FAIL "CRLF line endings" $'## Result\r\n**Status**: FAIL\r\n**Issues**: AC #1\r\n'
verdict_case FAIL "colon inside the bold ('**Status:** FAIL')" $'## Result\n**Status:** FAIL'
verdict_case UNKNOWN "a longer word ('**Status**: PASSED')" $'## Result\n**Status**: PASSED'
verdict_case PASS "mixed-case token ('**Status**: Pass'), stored upper-cased" $'## Result\n**Status**: Pass'
verdict_case PASS "lower-case key and token ('**status**: pass')" $'## Result\n**status**: pass'
verdict_case PASS "backticked token ('**Status**: \`PASS\`')" $'## Result\n**Status**: `PASS`'
verdict_case UNKNOWN "backticked unfilled template ('**Status**: \`PASS\` | \`FAIL\`')" $'## Result\n**Status**: `PASS` | `FAIL`'

# ---- non-matching agents -----------------------------------------------------
echo "--- non-matching agent_type -> silent no-op ---"
for at in ac-evaluator simple-workflow:ac-evaluator simple-workflow:ticket-evaluator-x "" __absent__; do
  PN=$(newproj)
  run_ctm "$(payload "$PN" sess-N "$at" "$MSG_PASS")"
  check "agent_type '${at}' writes nothing (no metrics dir, silent stderr)" \
    "$( [ ! -e "$PN/.simple-workflow" ] && [ -z "$LAST_STDERR" ] && echo true || echo false)"
done

PN=$(newproj)
run_ctm "$(payload "$PN" sess-N ac-evaluator "$MSG_PASS")" SW_CREATE_TICKET_METRICS_MODE=bogus
check "non-matching agent_type with an unknown mode value -> nothing written, stderr silent (no WARNING)" \
  "$( [ ! -e "$PN/.simple-workflow" ] && [ -z "$LAST_STDERR" ] && echo true || echo false)"

PN=$(newproj)
RUN_DIR="$PN"
run_ctm "this is not json {"
check "unparsable stdin -> exit 0, nothing written" "$(cond [ ! -e "$PN/.simple-workflow" ])"
run_ctm ""
check "empty stdin -> exit 0, nothing written, stderr silent" \
  "$( [ ! -e "$PN/.simple-workflow" ] && [ -z "$LAST_STDERR" ] && echo true || echo false)"
RUN_DIR="$FIXROOT"

# ---- missing fields, session_id prefixes -------------------------------------
echo "--- missing session_id / agent_id / message, session_id prefixes ---"
PM=$(newproj); FM=$(mfile "$PM")
PMSG=$(payload "$PM" unused ticket-evaluator "$MSG_PASS" | jq -c 'del(.session_id, .agent_id, .last_assistant_message)')
run_ctm "$PMSG"
run_ctm "$PMSG"
check "no session_id / agent_id / message, twice -> null ids, verdict UNKNOWN, seq 1 then 2" \
  "$( [ "$(line_count "$FM")" = 2 ] && [ "$(row_field "$FM" 1 '.session_id == null and .agent_id == null')" = true ] \
      && [ "$(row_field "$FM" 1 .verdict)" = UNKNOWN ] && [ "$(row_field "$FM" 1 .seq)" = 1 ] \
      && [ "$(row_field "$FM" 2 .seq)" = 2 ] && echo true || echo false)"

PA=$(newproj); FA=$(mfile "$PA")
run_ctm "$(payload "$PA" sess-A ticket-evaluator "$MSG_PASS")"
run_ctm "$(payload "$PA" sess-AB ticket-evaluator "$MSG_PASS")"
run_ctm "$(payload "$PA" sess-A ticket-evaluator "$MSG_PASS")"
check "session_id sess-AB after sess-A starts at seq 1 (exact match, not a prefix); sess-A continues at 2" \
  "$( [ "$(row_field "$FA" 2 .session_id)" = sess-AB ] && [ "$(row_field "$FA" 2 .seq)" = 1 ] \
      && [ "$(row_field "$FA" 3 .seq)" = 2 ] && echo true || echo false)"

# ---- cwd fallback, corrupt line, effort shapes -------------------------------
echo "--- cwd fallback, corrupt pre-existing line, effort shapes ---"
PW=$(newproj)
RUN_DIR="$PW"
run_ctm "$(payload "$FIXROOT/does-not-exist" sess-W ticket-evaluator "$MSG_PASS" | jq -c 'del(.cwd)')"
check "payload without cwd -> row appended under the hook's working directory" \
  "$(cond [ "$(line_count "$(mfile "$PW")")" = 1 ])"
run_ctm "$(payload "$FIXROOT/does-not-exist" sess-W ticket-evaluator "$MSG_PASS")"
check "payload cwd that is not a directory -> falls back to the working directory (seq 2), creates no directory" \
  "$( [ "$(line_count "$(mfile "$PW")")" = 2 ] && [ "$(row_field "$(mfile "$PW")" 2 .seq)" = 2 ] \
      && [ ! -e "$FIXROOT/does-not-exist" ] && echo true || echo false)"
mkdir -p "$PW/sub"
run_ctm "$(payload "$PW" sess-W ticket-evaluator "$MSG_PASS" | jq -c '.cwd = "sub"')"
check "relative payload cwd -> falls back to the working directory (seq 3), nothing under the relative dir" \
  "$( [ "$(line_count "$(mfile "$PW")")" = 3 ] && [ ! -e "$PW/sub/.simple-workflow" ] && echo true || echo false)"
RUN_DIR="$FIXROOT"

# The log root is raised to the nearest ancestor holding .simple-workflow/backlog/
# (the _psf_repo_root anchor), so a session that cd's around keeps one log.
PB=$(newproj); FB=$(mfile "$PB")
mkdir -p "$PB/.simple-workflow/backlog" "$PB/src/deep" "$PB/.simple-workflow/kb"
run_ctm "$(payload "$PB" sess-B ticket-evaluator "$MSG_FAIL")"
run_ctm "$(payload "$PB/src/deep" sess-B ticket-evaluator "$MSG_FAIL")"
run_ctm "$(payload "$PB/.simple-workflow/kb" sess-B ticket-evaluator "$MSG_PASS")"
check "cwd at <proj>, <proj>/src/deep and <proj>/.simple-workflow/kb -> one log under <proj>, seq 1..3, no decoy trees" \
  "$( [ "$(line_count "$FB")" = 3 ] && [ "$(row_field "$FB" 3 .seq)" = 3 ] && [ "$(row_field "$FB" 3 .verdict)" = PASS ] \
      && [ ! -e "$PB/src/deep/.simple-workflow" ] && [ ! -e "$PB/src/.simple-workflow" ] \
      && [ ! -e "$PB/.simple-workflow/kb/.simple-workflow" ] && echo true || echo false)"

PC=$(newproj); FC=$(mfile "$PC")
mkdir -p "$PC/.simple-workflow/metrics"
{
  printf '%s\n' 'garbage {not json'
  printf '%s\n' '{"ts":"2026-01-01T00:00:00Z","event":"ticket_eval","session_id":"sess-Z","agent_id":"old","agent_type":"ticket-evaluator","verdict":"FAIL","seq":1,"effort":null,"plugin_version":null,"stop_hook_active":false}'
  printf '%s\n' 'null'
} > "$FC"
run_ctm "$(payload "$PC" sess-Z ticket-evaluator "$MSG_PASS")"
check "corrupt and non-object lines are skipped when counting (seq 2) and left in place (append-only)" \
  "$( [ "$(line_count "$FC")" = 4 ] && [ "$(sed -n 1p "$FC")" = 'garbage {not json' ] \
      && [ "$(row_field "$FC" 4 .seq)" = 2 ] && echo true || echo false)"

PE=$(newproj); FE=$(mfile "$PE")
run_ctm "$(payload "$PE" sess-E ticket-evaluator "$MSG_PASS" | jq -c 'del(.effort)')"
run_ctm "$(payload "$PE" sess-E ticket-evaluator "$MSG_PASS" | jq -c '.effort = "medium"')"
run_ctm "$(payload "$PE" sess-E ticket-evaluator "$MSG_PASS" | jq -c '.effort = {}')"
check "effort: absent -> null, bare string -> kept, object without level -> null" \
  "$( [ "$(row_field "$FE" 1 '.effort == null')" = true ] && [ "$(row_field "$FE" 2 .effort)" = medium ] \
      && [ "$(row_field "$FE" 3 '.effort == null')" = true ] && echo true || echo false)"

# ---- kill switch -------------------------------------------------------------
echo "--- SW_CREATE_TICKET_METRICS_MODE ---"
PK=$(newproj)
run_ctm "$(payload "$PK" sess-K ticket-evaluator "$MSG_PASS")" SW_CREATE_TICKET_METRICS_MODE=off
check "mode off -> nothing written, silent" \
  "$( [ ! -e "$PK/.simple-workflow" ] && [ -z "$LAST_STDERR" ] && echo true || echo false)"

run_ctm "$(payload "$PK" sess-K ticket-evaluator "$MSG_FAIL")" SW_CREATE_TICKET_METRICS_MODE=metric-only
check "mode metric-only -> nothing written (not even the directory), would-be row logged" \
  "$( [ ! -e "$PK/.simple-workflow" ] \
      && grep -qF '[TICKET-EVAL-METRICS] metric-only: would append {' <<<"$LAST_STDERR" \
      && grep -qF '"verdict":"FAIL"' <<<"$LAST_STDERR" && echo true || echo false)"

run_ctm "$(payload "$PK" sess-K ticket-evaluator "$MSG_PASS")" SW_CREATE_TICKET_METRICS_MODE=bogus
check "unknown mode value -> collapses to on: row recorded + one WARNING line" \
  "$( [ "$(line_count "$(mfile "$PK")")" = 1 ] \
      && grep -qF '[TICKET-EVAL-METRICS] WARNING unknown SW_CREATE_TICKET_METRICS_MODE=bogus; using on' <<<"$LAST_STDERR" \
      && echo true || echo false)"

run_ctm "$(payload "$PK" sess-K ticket-evaluator "$MSG_PASS")" SW_CREATE_TICKET_METRICS_MODE=on
check "explicit mode on -> row recorded (seq 2)" \
  "$(cond [ "$(row_field "$(mfile "$PK")" 2 .seq)" = 2 ])"

# ---- fail-open paths -----------------------------------------------------------
echo "--- fail-open paths (exit 0 on every one) ---"
PJ=$(newproj)
RBIN=$(mktemp -d)
for c in bash cat grep sed awk head tr basename dirname printf date mkdir rmdir wc sleep env; do
  p=$(command -v "$c" 2>/dev/null) && ln -s "$p" "$RBIN/$c" 2>/dev/null
done
so=$(mktemp); se=$(mktemp)
printf '%s' "$(payload "$PJ" sess-J ticket-evaluator "$MSG_PASS")" | PATH="$RBIN" "$BASH_BIN" "$HOOK" >"$so" 2>"$se"
LAST_EXIT_CODE=$?
LAST_STDOUT=$(cat "$so"); LAST_STDERR=$(cat "$se"); rm -f "$so" "$se"
check "jq absent (PATH-restricted) -> exit 0, no file, silent" \
  "$( [ ! -e "$PJ/.simple-workflow" ] && [ -z "$LAST_STDERR" ] && echo true || echo false)"
rm -rf "$RBIN"

PU=$(newproj)
mkdir -p "$PU/.simple-workflow"
printf 'not a directory\n' > "$PU/.simple-workflow/metrics"
run_ctm "$(payload "$PU" sess-U ticket-evaluator "$MSG_PASS")"
check "metrics path blocked by a regular file -> exit 0, no row, WARN on stderr" \
  "$( [ -f "$PU/.simple-workflow/metrics" ] && [ "$(cat "$PU/.simple-workflow/metrics")" = 'not a directory' ] \
      && grep -qF '[TICKET-EVAL-METRICS] WARN:' <<<"$LAST_STDERR" && echo true || echo false)"

if [ "$(id -u)" -eq 0 ]; then
  skip_local "read-only metrics directory (running as root: permission bits do not apply)"
else
  PR=$(newproj)
  mkdir -p "$PR/.simple-workflow/metrics"
  chmod 555 "$PR/.simple-workflow/metrics"
  run_ctm "$(payload "$PR" sess-R ticket-evaluator "$MSG_PASS")"
  check "read-only metrics directory -> exit 0, no row, WARN on stderr" \
    "$( [ ! -e "$(mfile "$PR")" ] && [ ! -e "$(mfile "$PR").lock" ] \
        && grep -qF '[TICKET-EVAL-METRICS] WARN:' <<<"$LAST_STDERR" && echo true || echo false)"
  chmod 755 "$PR/.simple-workflow/metrics"
fi

PS=$(newproj); FS=$(mfile "$PS")
mkdir -p "$FS.lock"
run_ctm "$(payload "$PS" sess-S ticket-evaluator "$MSG_PASS")"
check "stale lock left by a crashed holder -> taken over after the bounded wait, row written, lock released" \
  "$( [ "$(line_count "$FS")" = 1 ] && [ ! -e "$FS.lock" ] && echo true || echo false)"

# A regular file at the lock path can be neither removed by rmdir nor replaced
# by mkdir: the hook waits the bounded 2 s, then appends unlocked.
PL=$(newproj); FL=$(mfile "$PL")
mkdir -p "$PL/.simple-workflow/metrics"
printf 'x' > "$FL.lock"
run_ctm "$(payload "$PL" sess-L ticket-evaluator "$MSG_PASS")"
check "lock path held by a regular file -> appended unlocked (1 row, 'appending unlocked' WARN), lock file untouched" \
  "$( [ "$(line_count "$FL")" = 1 ] && [ "$(row_field "$FL" 1 .verdict)" = PASS ] \
      && grep -qF '[TICKET-EVAL-METRICS] WARN: lock not acquired after the bounded wait; appending unlocked' <<<"$LAST_STDERR" \
      && [ -f "$FL.lock" ] && [ "$(cat "$FL.lock")" = x ] && echo true || echo false)"

# ---- no path / no PII in rows or on stderr -----------------------------------
# The repository holding the hook usually sits under a home path too, so a shell
# diagnostic naming the hook path or the log path would trip the stderr check.
echo "--- no path in rows or on stderr, even when cwd is a home-like path ---"
u=Users; h=home
for seg in "$u" "$h"; do
  PH="$FIXROOT/$seg/tester/project"
  mkdir -p "$PH"
  run_ctm "$(payload "$PH" sess-H ticket-evaluator "$MSG_PASS")"
  FH=$(mfile "$PH")
  check "cwd under /$seg/<name>/ -> row written, no '/$seg/' substring or cwd / transcript path in the file or on stderr" \
    "$( [ "$(line_count "$FH")" = 1 ] && ! grep -qE '/(Users|home)/' "$FH" \
        && ! grep -qF "$PH" "$FH" && ! grep -qF '.claude/projects' "$FH" \
        && ! grep -qE '/(Users|home)/' <<<"$LAST_STDERR" && ! grep -qF "$PH" <<<"$LAST_STDERR" \
        && echo true || echo false)"
done

# A directory at the log path makes the append itself fail (mkdir -p and the
# writability check pass); the shell's redirection error would name the path.
PD="$FIXROOT/$u/tester/appendfail"
mkdir -p "$PD/.simple-workflow/metrics/create-ticket.jsonl"
run_ctm "$(payload "$PD" sess-D ticket-evaluator "$MSG_PASS")"
check "directory at the log path under /$u/<name>/ -> exit 0, no row, 'append failed' WARN, no path on stderr" \
  "$( [ -d "$(mfile "$PD")" ] && [ -z "$(ls -A "$(mfile "$PD")")" ] \
      && grep -qxF '[TICKET-EVAL-METRICS] WARN: append failed; verdict=PASS not recorded' <<<"$LAST_STDERR" \
      && ! grep -qE '/(Users|home)/' <<<"$LAST_STDERR" && ! grep -qF "$PD" <<<"$LAST_STDERR" \
      && ! grep -qF 'create-ticket.jsonl' <<<"$LAST_STDERR" && echo true || echo false)"

if [ "$(id -u)" -eq 0 ]; then
  skip_local "read-only log file (running as root: permission bits do not apply)"
else
  PO="$FIXROOT/$h/tester/readonly"
  mkdir -p "$PO/.simple-workflow/metrics"
  printf '%s\n' '{"ts":"2026-01-01T00:00:00Z","event":"ticket_eval","session_id":"sess-O","agent_id":"old","agent_type":"ticket-evaluator","verdict":"FAIL","seq":1,"effort":null,"plugin_version":null,"stop_hook_active":false}' > "$(mfile "$PO")"
  chmod 444 "$(mfile "$PO")"
  run_ctm "$(payload "$PO" sess-O ticket-evaluator "$MSG_PASS")"
  check "read-only log file under /$h/<name>/ -> exit 0, no new row, 'append failed' WARN, no path on stderr, lock released" \
    "$( [ "$(line_count "$(mfile "$PO")")" = 1 ] && [ ! -e "$(mfile "$PO").lock" ] \
        && grep -qxF '[TICKET-EVAL-METRICS] WARN: append failed; verdict=PASS not recorded' <<<"$LAST_STDERR" \
        && ! grep -qE '/(Users|home)/' <<<"$LAST_STDERR" && echo true || echo false)"
  chmod 644 "$(mfile "$PO")"
fi

# NUL bytes, as a JSON escape in the message and raw on stdin: no shell warning
# (which would name the hook path) reaches stderr.
PZ="$FIXROOT/$u/tester/nul"
mkdir -p "$PZ"
run_ctm "$(payload "$PZ" sess-Z0 ticket-evaluator "$(printf '## Result\n**Status**: PASS\n**Issues**: none')" \
  | jq -c '.last_assistant_message += "\u0000 trailing"')"
check "NUL byte in last_assistant_message -> PASS row, stderr is exactly the verdict line" \
  "$( [ "$(row_field "$(mfile "$PZ")" 1 .verdict)" = PASS ] \
      && [ "$LAST_STDERR" = '[TICKET-EVAL-METRICS] verdict=PASS seq=1' ] && echo true || echo false)"
so=$(mktemp); se=$(mktemp)
printf 'a\000b' | (cd "$PZ" && env -u SW_CREATE_TICKET_METRICS_MODE bash "$HOOK") >"$so" 2>"$se"
LAST_EXIT_CODE=$?
LAST_STDOUT=$(cat "$so"); LAST_STDERR=$(cat "$se"); rm -f "$so" "$se"
check "raw NUL bytes on stdin -> exit 0, stderr silent" "$(cond [ -z "$LAST_STDERR" ])"

# ---- concurrency -----------------------------------------------------------------
echo "--- 8 concurrent appends ---"
PX=$(newproj); FX=$(mfile "$PX")
CDIR=$(mktemp -d)
for i in 1 2 3 4 5 6 7 8; do
  (
    printf '%s' "$(payload "$PX" sess-X ticket-evaluator "$MSG_PASS" false "agent-c$i")" \
      | env -u SW_CREATE_TICKET_METRICS_MODE bash "$HOOK" >"$CDIR/out.$i" 2>"$CDIR/err.$i"
    echo "$?" > "$CDIR/rc.$i"
  ) &
done
wait
conc_rc_ok=true; conc_out_ok=true
for i in 1 2 3 4 5 6 7 8; do
  [ "$(cat "$CDIR/rc.$i" 2>/dev/null)" = 0 ] || conc_rc_ok=false
  [ -s "$CDIR/out.$i" ] && conc_out_ok=false
done
conc_valid=$(jq -R 'fromjson? | select(type == "object" and .event == "ticket_eval") | 1' "$FX" 2>/dev/null | wc -l | tr -d '[:space:]')
conc_seqs=$(jq -r '.seq' "$FX" 2>/dev/null | sort -n | tr '\n' ' ')
conc_agents=$(jq -r '.agent_id' "$FX" 2>/dev/null | sort -u | wc -l | tr -d '[:space:]')
LAST_EXIT_CODE=0; LAST_STDOUT=""; LAST_STDERR="rc_ok=$conc_rc_ok out_ok=$conc_out_ok lines=$(line_count "$FX") valid=$conc_valid seqs=[$conc_seqs] agents=$conc_agents"
$conc_rc_ok || LAST_EXIT_CODE=1
$conc_out_ok || LAST_STDOUT="non-empty stdout from a concurrent instance"
check "8 concurrent appends -> 8 well-formed lines, seq exactly 1..8, 8 agent_ids, lock released, every exit 0" \
  "$( [ "$(line_count "$FX")" = 8 ] && [ "$conc_valid" = 8 ] && [ "$conc_seqs" = "1 2 3 4 5 6 7 8 " ] \
      && [ "$conc_agents" = 8 ] && [ ! -e "$FX.lock" ] && echo true || echo false)"
rm -rf "$CDIR"

# ---- every written line is valid JSON --------------------------------------------
echo "--- per-line JSON validity ---"
bad_lines=0; files=0
while IFS= read -r f; do
  [ "$f" = "$FC" ] && continue   # the deliberately corrupt fixture
  files=$((files + 1))
  while IFS= read -r line; do
    printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1 || bad_lines=$((bad_lines + 1))
  done < "$f"
done < <(find "$FIXROOT" -type f -name create-ticket.jsonl)
LAST_EXIT_CODE=0; LAST_STDOUT=""; LAST_STDERR="files=$files bad_lines=$bad_lines"
check "every line of every metrics file the hook wrote passes jq -e (files=$files)" \
  "$( [ "$files" -ge 8 ] && [ "$bad_lines" -eq 0 ] && echo true || echo false)"

# The deliberately corrupt fixture: every line the HOOK appended is valid.
LAST_STDERR=""
check "the row appended after a corrupt line is itself valid JSON" \
  "$(sed -n 4p "$FC" | jq -e 'type == "object"' >/dev/null 2>&1 && echo true || echo false)"

print_summary
