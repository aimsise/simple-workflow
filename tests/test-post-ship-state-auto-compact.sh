#!/usr/bin/env bash
# tests/test-post-ship-state-auto-compact.sh — T-006 wave-unit auto-compact
# coverage for hooks/post-ship-state-auto-compact.sh.
#
# The serial behaviour of this hook (the de-facto PRIMARY auto-compact
# trigger that fires on a `steps.ship: completed` write) is unchanged by
# T-006 and is covered by tests/test-skill-contracts.sh CT-AC-* plus the
# field-evidence regression suite. This file adds the PARALLEL wave-unit
# cases the T-006 ticket mandates:
#
#   AC-1  parallel_mode=on + a `wave_status: drained` payload -> ONE inject.
#   AC-2  (M1 — make-or-break) parallel_mode=on + a `wave_status: drained`
#         payload that does NOT carry `ship: completed` -> still injects
#         exactly once (proves the L126 `_detect_ship_completed_in_payload
#         || exit 0` early-exit was SUPPLANTED under parallel, not bypassed).
#         Conversely a mid-wave `ship: completed` payload whose `wave_status`
#         is NOT drained -> NO inject (defer to the wave barrier). A grep
#         asserts `resolve_parallel_mode` is invoked BEFORE the L126 line.
#   AC-3  same-wave second `drained` write -> dedup via the `wave-{N}:`
#         marker; the serial `{int}:{ts}` marker round-trips byte-identically
#         (the shared `%%:*`/`##*:` split is untouched — asserted on BOTH
#         `5:1700` and `wave-2:1700`).
#   AC-4  IS_LAST_WAVE -> the post-loop-phase instruction text (identical to
#         the serial last-ticket text), firing on `current_wave + 1 >=
#         wave_count && wave_status == drained` even when a skipped ticket
#         leaves shipped_count < total_tickets.
#   AC-6  parallel_mode=off -> the serial `ship: completed` trigger is
#         byte-identical (a drained-only payload does NOT inject off-path;
#         a ship: completed payload DOES; no parallel stderr line is emitted).
#
# Hermeticity mirrors tests/test-pre-next-scout-auto-compact.sh: each case
# builds a self-contained autopilot sandbox under mktemp -d, seeds a
# brief-level autopilot-state.yaml + the shipped ticket dirs under
# backlog/done/ so Gate 5 (state-lie protection) passes, and routes the
# hook through a PATH-scoped `tmux` stub from tests/fixtures/tmux-stub.sh
# so the inject-keys library exercises the real tmux backend without a live
# tmux server. The stub honours SW_TEST_TMUX_SENDKEYS_RC / _CAPTURE_OUT.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/hooks/post-ship-state-auto-compact.sh"
TMUX_STUB="$SCRIPT_DIR/fixtures/tmux-stub.sh"

if [ ! -x "$HOOK" ]; then
  echo "ERROR: hook not executable: $HOOK" >&2
  exit 2
fi
if [ ! -x "$TMUX_STUB" ]; then
  echo "ERROR: tmux stub not executable: $TMUX_STUB" >&2
  exit 2
fi

# Hermetic PATH bin/ — `tmux` symlink to the fixture stub. Other binaries
# (jq, yq, python3, date, mktemp, cat, ...) inherit from the host PATH.
PATH_BIN="$(mktemp -d)"
ln -sf "$TMUX_STUB" "$PATH_BIN/tmux"
trap 'rm -rf "$PATH_BIN"' EXIT

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       expected: $expected"
    echo -e "       actual:   $actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qF -- "$needle" <<<"$haystack"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       expected substring: $needle"
    echo -e "       actual haystack:    $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_not_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qF -- "$needle" <<<"$haystack"; then
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       unexpected substring present: $needle"
    echo -e "       actual haystack:              $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
}

assert_file_exists() {
  local description="$1"
  local path="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ -f "$path" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       expected file: $path"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_file_absent() {
  local description="$1"
  local path="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ ! -f "$path" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       expected absent: $path"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Build a hermetic autopilot sandbox with a brief-level autopilot-state.yaml
# describing two tickets, both already in backlog/done/ (so Gate 5 state-lie
# protection passes for any `ship: completed` element). The wave cursor
# fields (parallel_mode / current_wave / wave_count / wave_status) are
# parameters so each case shapes the state document it needs.
#
# Sets globals: $LAST_SANDBOX, $LAST_STATE_DIR, $LAST_STATE_FILE,
#               $LAST_ATTEMPT_FILE, $LAST_PENDING.
#
# Args:
#   $1 label
#   $2 parallel_mode  (one of on / metric-only / off; "" = omit the key)
#   $3 current_wave   ("" = omit)
#   $4 wave_count     ("" = omit)
#   $5 wave_status    ("" = omit)
make_sandbox() {
  local label="$1" pmode="$2" cwave="$3" wcount="$4" wstatus="$5"
  LAST_SANDBOX=$(mktemp -d)
  LAST_STATE_DIR="$LAST_SANDBOX/.simple-workflow/backlog/briefs/active/$label"
  mkdir -p "$LAST_STATE_DIR"
  LAST_STATE_FILE="$LAST_STATE_DIR/autopilot-state.yaml"
  mkdir -p "$LAST_SANDBOX/.simple-workflow/backlog/done/$label/T-001"
  mkdir -p "$LAST_SANDBOX/.simple-workflow/backlog/done/$label/T-002"
  {
    echo "parent_slug: $label"
    [ -n "$pmode" ]   && echo "parallel_mode: $pmode"
    [ -n "$cwave" ]   && echo "current_wave: $cwave"
    [ -n "$wcount" ]  && echo "wave_count: $wcount"
    [ -n "$wstatus" ] && echo "wave_status: $wstatus"
    cat <<EOF
tickets:
  - logical_id: T-001
    ticket_dir: .simple-workflow/backlog/done/$label/T-001
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
  - logical_id: T-002
    ticket_dir: .simple-workflow/backlog/done/$label/T-002
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
EOF
  } > "$LAST_STATE_FILE"
  LAST_ATTEMPT_FILE="$LAST_STATE_DIR/.auto-compact-last-attempt"
  LAST_PENDING="$LAST_STATE_DIR/.auto-compact-pending"
}

# Pipe a synthesised PostToolUse(Write) payload into the hook. The payload's
# `tool_input.content` is the just-written autopilot-state.yaml fragment;
# `file_path` is the on-disk state file (Gate 1 + Gate 5 read it).
#
# Args:
#   $1 sandbox cwd
#   $2 payload content (the YAML the orchestrator "wrote")
#   $3 sendkeys_rc  ("0" success)
#   $4 capture_out  (capture-pane echo; non-empty -> verify passes)
#
# Stores result in $LAST_EXIT_CODE / $LAST_STDOUT / $LAST_STDERR.
run_hook_for() {
  local sandbox="$1" content="$2" sendkeys_rc="$3" capture_out="$4"
  local payload
  payload=$(jq -n --arg fp "$LAST_STATE_FILE" --arg c "$content" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  set +e
  printf '%s' "$payload" | env -i \
    HOME="$HOME" \
    PATH="$PATH_BIN:$PATH" \
    TMUX="fake-socket,1,0" \
    TMUX_PANE="%test-pane" \
    TERM="${TERM:-xterm}" \
    SW_AUTO_COMPACT_ON_SHIP_MODE="on" \
    SW_TEST_TMUX_SENDKEYS_RC="$sendkeys_rc" \
    SW_TEST_TMUX_CAPTURE_OUT="$capture_out" \
    SW_INJECT_KEYS_VERIFY_SLEEP_MS=0 \
    bash -c "cd \"$sandbox\" && bash \"$HOOK\"" >"$stdout_file" 2>"$stderr_file"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

# A capture-pane line that echoes `/compact` back so the P1-1 verify passes
# and inject_keys returns rc=0 (a real inject).
CAP_OK="user@host > /compact (echoed back)"

# Canonical YAML fragments used as Write payloads.
DRAINED_NO_SHIP=$'parallel_mode: on\ncurrent_wave: 0\nwave_count: 2\nwave_status: drained\n'
DRAINED_WITH_SHIP=$'parallel_mode: on\ncurrent_wave: 0\nwave_count: 2\nwave_status: drained\ntickets:\n  - logical_id: T-001\n    steps:\n      ship: completed\n'
MID_WAVE_SHIP=$'parallel_mode: on\ncurrent_wave: 0\nwave_count: 2\nwave_status: running\ntickets:\n  - logical_id: T-001\n    steps:\n      ship: completed\n'
SHIP_COMPLETED=$'tickets:\n  - logical_id: T-001\n    steps:\n      ship: completed\n'

echo "=== hooks/post-ship-state-auto-compact.sh — T-006 wave-unit auto-compact ==="
echo ""

# ---------------------------------------------------------------------------
# AC-1: parallel_mode=on + a `wave_status: drained` payload -> ONE inject.
# ---------------------------------------------------------------------------
echo "--- AC-1: parallel_mode=on + wave_status: drained -> one inject ---"
make_sandbox ac1 on 0 2 drained
run_hook_for "$LAST_SANDBOX" "$DRAINED_WITH_SHIP" "0" "$CAP_OK"
assert_eq        "AC-1: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_file_exists "AC-1: inject fired -> .auto-compact-pending written" "$LAST_PENDING"
assert_contains  "AC-1: success additionalContext emitted (state-write safety-net)" \
  "auto-compact-on-ship (state-write safety-net)" "$LAST_STDOUT"
# The wave-keyed marker was written with the `wave-{N}:` form.
assert_contains  "AC-1: marker re-keyed to wave-0: form" \
  "wave-0:" "$(cat "$LAST_ATTEMPT_FILE" 2>/dev/null || echo MISSING)"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# AC-2 (M1): parallel_mode=on + a `wave_status: drained` payload that does
# NOT carry `ship: completed` -> still injects exactly once. Proves the L126
# ship-detector early-exit was SUPPLANTED, not bypassed.
# ---------------------------------------------------------------------------
echo "--- AC-2 (M1): parallel + drained WITHOUT ship: completed -> still injects ---"
make_sandbox ac2 on 0 2 drained
# Sanity: the payload genuinely lacks `ship: completed` so a regression
# that kept the L126 ship-detector gate would exit 0 with no inject.
assert_not_contains "AC-2: fixture payload carries NO ship: completed" \
  "ship: completed" "$DRAINED_NO_SHIP"
run_hook_for "$LAST_SANDBOX" "$DRAINED_NO_SHIP" "0" "$CAP_OK"
assert_eq        "AC-2: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_file_exists "AC-2: drained-only payload STILL injects -> .auto-compact-pending written" \
  "$LAST_PENDING"
assert_contains  "AC-2: drained-only payload emits the wave inject additionalContext" \
  "auto-compact-on-ship (state-write safety-net)" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# AC-2 (M1) — mechanical: resolve_parallel_mode is invoked BEFORE the L126
# `_detect_ship_completed_in_payload || exit 0` line in the hook source.
# ---------------------------------------------------------------------------
echo "--- AC-2 (M1): resolve_parallel_mode precedes the ship-detector early-exit ---"
RESOLVE_LINE=$(grep -n 'PARALLEL_MODE="\$(resolve_parallel_mode "\$TOOL_FILE_PATH")"' "$HOOK" | head -1 | cut -d: -f1)
EARLYEXIT_LINE=$(grep -n '_detect_ship_completed_in_payload "\$TOOL_PAYLOAD" || exit 0' "$HOOK" | head -1 | cut -d: -f1)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$RESOLVE_LINE" ] && [ -n "$EARLYEXIT_LINE" ] && [ "$RESOLVE_LINE" -lt "$EARLYEXIT_LINE" ]; then
  echo -e "  ${GREEN}PASS${NC} AC-2: resolve_parallel_mode (L$RESOLVE_LINE) precedes the L126 ship-detector early-exit (L$EARLYEXIT_LINE)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-2: resolve (L${RESOLVE_LINE:-?}) must precede ship-detector early-exit (L${EARLYEXIT_LINE:-?})"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
# And the ship-detector early-exit is now inside a `parallel_mode = off`
# branch (serial-only), not the unconditional top-level gate.
assert_contains "AC-2: serial early-exit guarded by the off branch" \
  'if [ "$PARALLEL_MODE" = "off" ]; then' "$(cat "$HOOK")"
echo ""

# ---------------------------------------------------------------------------
# AC-2 (defer): parallel_mode=on + a mid-wave `ship: completed` payload whose
# `wave_status` is NOT drained -> NO inject (defer to the wave barrier).
# ---------------------------------------------------------------------------
echo "--- AC-2 (defer): parallel + mid-wave ship: completed, wave NOT drained -> no inject ---"
make_sandbox ac2d on 0 2 running
run_hook_for "$LAST_SANDBOX" "$MID_WAVE_SHIP" "0" "$CAP_OK"
assert_eq        "AC-2 defer: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_file_absent "AC-2 defer: NO inject (wave not drained) -> .auto-compact-pending absent" \
  "$LAST_PENDING"
assert_eq        "AC-2 defer: NO additionalContext on stdout" "" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# AC-3: same-wave second `drained` write dedups via the `wave-{N}:` marker.
# First write injects; a second drained write within the wave short-circuits
# at the loop-guard (marker key unchanged within 300s).
# ---------------------------------------------------------------------------
echo "--- AC-3: same-wave second drained write -> dedup via wave-{N}: marker ---"
make_sandbox ac3 on 1 3 drained
run_hook_for "$LAST_SANDBOX" "$DRAINED_NO_SHIP" "0" "$CAP_OK"  # note: content's own wave_status flips it; first inject
# First write should have injected and written the wave-1: marker
# (current_wave=1 from the on-disk state file).
assert_contains  "AC-3: first write wrote the wave-1: marker" \
  "wave-1:" "$(cat "$LAST_ATTEMPT_FILE" 2>/dev/null || echo MISSING)"
# Remove the .auto-compact-pending sentinel so Gate 6 (sentinel dedup) is
# NOT the thing that short-circuits — we want to prove the Gate 7 wave-keyed
# loop-guard is what dedups the second same-wave write.
rm -f "$LAST_PENDING"
run_hook_for "$LAST_SANDBOX" "$DRAINED_NO_SHIP" "0" "$CAP_OK"
assert_eq        "AC-3: second same-wave write exits 0" "0" "$LAST_EXIT_CODE"
assert_contains  "AC-3: second write short-circuits at the wave-keyed loop-guard" \
  "loop-guard: marker key=wave-1 unchanged" "$LAST_STDERR"
assert_file_absent "AC-3: second write did NOT re-inject (.auto-compact-pending absent)" \
  "$LAST_PENDING"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# AC-3: marker-split round-trip — the shared `%%:*`/`##*:` split is byte-
# untouched and extracts key/ts correctly for BOTH the serial `{int}:{ts}`
# form AND the parallel `wave-{N}:{ts}` form (single colon, hyphen in key).
# ---------------------------------------------------------------------------
echo "--- AC-3: marker-split round-trips for serial 5:1700 AND parallel wave-2:1700 ---"
SERIAL_MARKER="5:1700"
S_KEY="${SERIAL_MARKER%%:*}"; S_TS="${SERIAL_MARKER##*:}"
assert_eq "AC-3: serial 5:1700 -> key extracts to 5"  "5"    "$S_KEY"
assert_eq "AC-3: serial 5:1700 -> ts extracts to 1700" "1700" "$S_TS"
PARALLEL_MARKER="wave-2:1700"
P_KEY="${PARALLEL_MARKER%%:*}"; P_TS="${PARALLEL_MARKER##*:}"
assert_eq "AC-3: parallel wave-2:1700 -> key extracts to wave-2" "wave-2" "$P_KEY"
assert_eq "AC-3: parallel wave-2:1700 -> ts extracts to 1700"    "1700"   "$P_TS"
echo ""

# ---------------------------------------------------------------------------
# AC-4: IS_LAST_WAVE -> the post-loop-phase instruction. current_wave=1,
# wave_count=2 (1 + 1 >= 2) and wave_status=drained, so the FINAL-wave branch
# fires from the CURSOR alone (not from shipped_count). make_sandbox seeds 2/2
# completed here, so this case proves the cursor drives IS_LAST; AC-4c below
# proves the positive correctness gain on the real edge (shipped_count < total
# via a skipped ticket — the case the old count-based serial check would miss).
# ---------------------------------------------------------------------------
echo "--- AC-4: IS_LAST_WAVE -> post-loop-phase instruction text ---"
make_sandbox ac4 on 1 2 drained
run_hook_for "$LAST_SANDBOX" "$DRAINED_NO_SHIP" "0" "$CAP_OK"
assert_eq        "AC-4: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_contains  "AC-4: last-wave branch emits the FINAL-ticket post-loop instruction" \
  "was the FINAL ticket of this pipeline" "$LAST_STDOUT"
assert_contains  "AC-4: last-wave instruction names the post-loop phase (Completion Report)" \
  "Complete the post-loop phase FIRST" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

# A non-last drained wave (current_wave=0, wave_count=2) takes the NON-last
# branch (end the turn now, no FINAL-ticket text).
echo "--- AC-4: non-last drained wave -> non-last (end-turn-now) instruction ---"
make_sandbox ac4b on 0 2 drained
run_hook_for "$LAST_SANDBOX" "$DRAINED_NO_SHIP" "0" "$CAP_OK"
assert_eq        "AC-4: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_not_contains "AC-4: non-last wave does NOT emit the FINAL-ticket text" \
  "was the FINAL ticket of this pipeline" "$LAST_STDOUT"
assert_contains  "AC-4: non-last wave emits the end-turn-now instruction" \
  "end this turn now without proceeding to the next ticket" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# AC-4c: the IS_LAST_WAVE positive correctness gain on the REAL edge — the
# cursor-based last-wave check fires even when shipped_count < total_tickets (a
# skipped ticket on the last drained wave). The old count-based serial check
# (`shipped_count == total_tickets`) would have MISSED the post-loop
# instruction here. make_sandbox seeds 2/2 completed, so this builds a
# 1-shipped + 1-skipped state directly (Wave-2 adversarial-verify gap fix).
# ---------------------------------------------------------------------------
echo "--- AC-4c: IS_LAST_WAVE fires with shipped_count(1) < total(2) (skipped ticket) ---"
AC4C_SB=$(mktemp -d)
AC4C_DIR="$AC4C_SB/.simple-workflow/backlog/briefs/active/ac4c"
mkdir -p "$AC4C_DIR" "$AC4C_SB/.simple-workflow/backlog/done/ac4c/T-001"
cat > "$AC4C_DIR/autopilot-state.yaml" <<'EOF'
parent_slug: ac4c
parallel_mode: on
current_wave: 1
wave_count: 2
wave_status: drained
total_tickets: 2
tickets:
  - logical_id: T-001
    ticket_dir: .simple-workflow/backlog/done/ac4c/T-001
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
  - logical_id: T-002
    ticket_dir: .simple-workflow/backlog/active/ac4c/T-002
    status: skipped
    steps:
      scout: completed
      impl: pending
      ship: pending
EOF
LAST_STATE_FILE="$AC4C_DIR/autopilot-state.yaml"
run_hook_for "$AC4C_SB" "$DRAINED_NO_SHIP" "0" "$CAP_OK"
assert_eq        "AC-4c: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_contains  "AC-4c: cursor-based last-wave fires despite shipped_count(1) < total(2)" \
  "was the FINAL ticket of this pipeline" "$LAST_STDOUT"
rm -rf "$AC4C_SB"
echo ""

# ---------------------------------------------------------------------------
# AC-6: parallel_mode=off byte-identity. The serial `ship: completed` trigger
# is unchanged: a `ship: completed` payload DOES inject; a drained-only
# payload does NOT (the wave detector is never reached); no parallel stderr
# line is ever emitted.
# ---------------------------------------------------------------------------
echo "--- AC-6: parallel_mode=off + ship: completed -> serial inject (byte-identical) ---"
make_sandbox off1 off "" "" ""
run_hook_for "$LAST_SANDBOX" "$SHIP_COMPLETED" "0" "$CAP_OK"
assert_eq        "AC-6: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_file_exists "AC-6: off path injects on ship: completed -> .auto-compact-pending written" \
  "$LAST_PENDING"
assert_contains  "AC-6: off path emits the serial state-write additionalContext" \
  "auto-compact-on-ship (state-write safety-net)" "$LAST_STDOUT"
# Serial marker form: `{shipped_count}:{ts}` — 2 tickets shipped -> key `2`,
# NOT a `wave-` prefix.
assert_contains  "AC-6: off path wrote the serial {count}: marker (key=2)" \
  "2:" "$(cat "$LAST_ATTEMPT_FILE" 2>/dev/null || echo MISSING)"
assert_not_contains "AC-6: off path marker is NOT wave-keyed" \
  "wave-" "$(cat "$LAST_ATTEMPT_FILE" 2>/dev/null || echo NONE)"
assert_not_contains "AC-6: off path emits NO parallel stderr line" \
  "metric-only parallel" "$LAST_STDERR"
rm -rf "$LAST_SANDBOX"
echo ""

# Off path + a drained-only payload (no ship: completed) -> NO inject (the
# wave detector is never reached on the serial path; the ship-detector
# early-exit fires verbatim).
echo "--- AC-6: parallel_mode=off + drained-only payload -> NO inject (serial gate) ---"
make_sandbox off2 off "" "" ""
run_hook_for "$LAST_SANDBOX" "$DRAINED_NO_SHIP" "0" "$CAP_OK"
assert_eq        "AC-6: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_file_absent "AC-6: off path does NOT inject on a drained-only payload" \
  "$LAST_PENDING"
assert_eq        "AC-6: off path drained-only -> empty stdout" "" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

# metric-only parallel: logs the would-be wave gate and takes the SERIAL
# path (gate on ship: completed). A ship: completed payload still injects;
# the metric-only parallel stderr line is present.
echo "--- AC-6: parallel_mode=metric-only -> log + serial path ---"
make_sandbox mo1 metric-only 0 2 drained
run_hook_for "$LAST_SANDBOX" "$SHIP_COMPLETED" "0" "$CAP_OK"
assert_eq        "AC-6: hook exits 0 under metric-only" "0" "$LAST_EXIT_CODE"
assert_contains  "AC-6: metric-only emits the would-gate-on-wave log" \
  "metric-only parallel: would gate on wave_status: drained" "$LAST_STDERR"
assert_file_exists "AC-6: metric-only takes the serial path and injects on ship: completed" \
  "$LAST_PENDING"
rm -rf "$LAST_SANDBOX"
echo ""

print_summary
