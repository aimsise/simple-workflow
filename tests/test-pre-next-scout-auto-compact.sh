#!/usr/bin/env bash
# tests/test-pre-next-scout-auto-compact.sh — P2-1 sentinel lifecycle
# coverage for hooks/pre-next-scout-auto-compact.sh.
#
# AC mapping (from
# `.docs/dogfooding/33-34/P2-1-sentinel-file-based-session-resume.md`):
#
#   AC-1 (implicit): the hook creates `<state_dir>/.next-compact-pending`
#                    before the `inject_keys` call. Confirmed indirectly
#                    via AC-3 (sentinel still on disk after rc=1).
#   AC-2:  inject_keys rc=0 -> sentinel DELETED post-run; the success
#          path also writes `.auto-compact-pending` (Stop hook yield
#          signal) which must coexist on the deterministic success
#          boundary.
#   AC-3:  inject_keys rc=1 -> sentinel RETAINED post-run; stderr
#          contains `retaining .next-compact-pending for session-start
#          retry`.
#
# Hermeticity: each case builds a self-contained autopilot sandbox
# under mktemp -d, seeds a brief-level autopilot-state.yaml + a
# committed-shipped ticket dir under backlog/done/ so the loop-guard
# / shipped-count gate passes, and routes the hook through a PATH-
# scoped `tmux` stub from `tests/fixtures/tmux-stub.sh` so the
# inject-keys library exercises the real tmux backend without
# touching a live tmux server. The stub honours
# `SW_TEST_TMUX_SENDKEYS_RC` to force rc!=0 (AC-3) and
# `SW_TEST_TMUX_CAPTURE_OUT` to make capture-pane echo back the
# injected text (AC-2 verify success).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/hooks/pre-next-scout-auto-compact.sh"
TMUX_STUB="$SCRIPT_DIR/fixtures/tmux-stub.sh"

if [ ! -x "$HOOK" ]; then
  echo "ERROR: hook not executable: $HOOK" >&2
  exit 2
fi
if [ ! -x "$TMUX_STUB" ]; then
  echo "ERROR: tmux stub not executable: $TMUX_STUB" >&2
  exit 2
fi

# Hermetic PATH bin/ — `tmux` symlink to the fixture stub. Other
# binaries (jq, yq, python3, date, mktemp, cat, ...) inherit from the
# host PATH because the hook itself relies on them and replicating
# them in the sandbox would defeat the test.
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
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       expected substring: $needle"
    echo -e "       actual haystack:    $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
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

# Build a hermetic autopilot sandbox with:
#   - parent brief: .simple-workflow/backlog/briefs/active/<label>/
#   - autopilot-state.yaml listing two tickets — T-001 already
#     shipped (so the ticket-boundary gate fires), T-002 pending.
#   - backlog/done/<label>/T-001/ directory present (matches the
#     ticket_dir written into state.yaml so the post-ship state-lie
#     protection passes).
#
# Sets globals: $LAST_SANDBOX, $LAST_STATE_DIR, $LAST_STATE_FILE,
#               $LAST_SENTINEL.
make_sandbox() {
  local label="$1"
  LAST_SANDBOX=$(mktemp -d)
  LAST_STATE_DIR="$LAST_SANDBOX/.simple-workflow/backlog/briefs/active/$label"
  mkdir -p "$LAST_STATE_DIR"
  LAST_STATE_FILE="$LAST_STATE_DIR/autopilot-state.yaml"
  # T-001 is already in done/, T-002 is still pending. The hook's
  # Gate 4 counts elements whose `steps.ship` reached completed; one
  # is enough to mark the upcoming /scout call as a NON-FIRST ticket
  # boundary.
  mkdir -p "$LAST_SANDBOX/.simple-workflow/backlog/done/$label/T-001"
  cat > "$LAST_STATE_FILE" <<EOF
parent_slug: $label
tickets:
  - logical_id: T-001
    ticket_dir: .simple-workflow/backlog/done/$label/T-001
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
  - logical_id: T-002
    ticket_dir: .simple-workflow/backlog/active/$label/T-002
    status: pending
    steps:
      scout: pending
EOF
  LAST_SENTINEL="$LAST_STATE_DIR/.next-compact-pending"
}

# Pipe a synthesised PreToolUse(Skill) payload into the hook.
#
# Args:
#   $1 — sandbox cwd
#   $2 — `tmux_sendkeys_rc` ("0" = success, anything else = failure)
#   $3 — `capture_pane_out` (the canned `tmux capture-pane` stdout)
#
# Stores result in $LAST_EXIT_CODE / $LAST_STDOUT / $LAST_STDERR.
run_hook_for() {
  local sandbox="$1"
  local sendkeys_rc="$2"
  local capture_out="$3"
  local payload
  payload=$(printf '{"tool_input":{"skill":"simple-workflow:scout"}}')
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

# T-006 parallel stand-down runner. Same as run_hook_for but threads
# SW_PARALLEL_HOOKS_MODE into the hermetic env so the hook's Gate 2.5
# parallel stand-down (resolve_parallel_mode) is exercised. Uses a
# capture-pane output that WOULD make inject succeed, so a non-stand-down
# (regression) would visibly write `.auto-compact-pending` and reach the
# success additionalContext — the stand-down assertion then proves the
# hook exited 0 BEFORE injecting.
run_hook_parallel() {
  local sandbox="$1"
  local parallel_mode="$2"
  local payload
  payload=$(printf '{"tool_input":{"skill":"simple-workflow:scout"}}')
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
    SW_PARALLEL_HOOKS_MODE="$parallel_mode" \
    SW_TEST_TMUX_SENDKEYS_RC="0" \
    SW_TEST_TMUX_CAPTURE_OUT="user@host > /compact (echoed back)" \
    SW_INJECT_KEYS_VERIFY_SLEEP_MS=0 \
    bash -c "cd \"$sandbox\" && bash \"$HOOK\"" >"$stdout_file" 2>"$stderr_file"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

echo "=== hooks/pre-next-scout-auto-compact.sh — P2-1 .next-compact-pending lifecycle ==="
echo ""

# ---------------------------------------------------------------------------
# AC-2: inject_keys rc=0 (capture-pane echoes the text -> P1-1 verify
# passes) -> sentinel DELETED, `.auto-compact-pending` written.
# ---------------------------------------------------------------------------
echo "--- AC-2: inject_keys rc=0 -> sentinel deleted, auto-compact-pending present ---"
make_sandbox ac2
# Verify success requires the capture-pane stub to echo back the
# injected text within the verify window. tmux-stub.sh prints
# SW_TEST_TMUX_CAPTURE_OUT verbatim, so we seed a line that contains
# `/compact`.
run_hook_for "$LAST_SANDBOX" "0" "user@host > /compact (echoed back)"
assert_eq        "AC-2: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_file_absent "AC-2: .next-compact-pending deleted on inject success" "$LAST_SENTINEL"
assert_file_exists "AC-2: .auto-compact-pending written on inject success" \
  "$LAST_STATE_DIR/.auto-compact-pending"
# Defensive sanity: the success additionalContext landed on stdout
# (not the failure branch).
assert_contains  "AC-2: success additionalContext emitted" \
  "auto-compact-on-ship (ticket-boundary)" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# AC-3: inject_keys rc=1 (capture-pane returns empty -> P1-1 verify
# downgrades rc to 1) -> sentinel RETAINED, stderr carries the
# retention log line.
# ---------------------------------------------------------------------------
echo "--- AC-3: inject_keys rc=1 -> sentinel retained, stderr has retention log ---"
make_sandbox ac3
# Empty capture-pane output makes inject_keys downgrade to rc=1 via
# the P1-1 verify miss branch (matches the failure mode the P2-1
# sentinel was designed to defend against).
run_hook_for "$LAST_SANDBOX" "0" ""
assert_eq        "AC-3: hook exits 0 (failure branch still emits no-op envelope)" \
  "0" "$LAST_EXIT_CODE"
assert_file_exists "AC-3: .next-compact-pending retained on inject failure" "$LAST_SENTINEL"
assert_contains  "AC-3: stderr contains 'retaining .next-compact-pending for session-start retry'" \
  "retaining .next-compact-pending for session-start retry" "$LAST_STDERR"
# .auto-compact-pending MUST NOT be written when the inject failed —
# yield-tick coordination only fires on confirmed success.
assert_file_absent "AC-3: .auto-compact-pending NOT written on inject failure" \
  "$LAST_STATE_DIR/.auto-compact-pending"
# Defensive sanity: the failure additionalContext landed on stdout.
assert_contains  "AC-3: failure additionalContext emitted" \
  "auto-compact-on-ship: injection failed" "$LAST_STDOUT"
assert_contains  "AC-3: failure additionalContext mentions session-start retry" \
  "next session start" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# T-006 AC-5: parallel_mode=on -> the hook STANDS DOWN (exits 0, no inject),
# so post-ship-state-auto-compact.sh is the sole wave-trigger.
# ---------------------------------------------------------------------------
echo "--- T-006 AC-5: parallel_mode=on -> stand down (exit 0, no inject) ---"
make_sandbox p_on
run_hook_parallel "$LAST_SANDBOX" "on"
assert_eq        "T-006 AC-5: hook exits 0 under parallel_mode=on" "0" "$LAST_EXIT_CODE"
assert_contains  "T-006 AC-5: stderr carries the parallel stand-down log" \
  "parallel stand-down" "$LAST_STDERR"
# Stand-down means NO inject -> neither sentinel nor the success
# additionalContext was produced.
assert_file_absent "T-006 AC-5: .auto-compact-pending NOT written (stood down before inject)" \
  "$LAST_STATE_DIR/.auto-compact-pending"
assert_eq        "T-006 AC-5: no inject -> empty stdout (no additionalContext)" \
  "" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# T-006 AC-5: parallel_mode=metric-only -> log "would stand down" and FALL
# THROUGH to the existing serial path (which injects on a real boundary).
# ---------------------------------------------------------------------------
echo "--- T-006 AC-5: parallel_mode=metric-only -> log + fall through to serial ---"
make_sandbox p_mo
run_hook_parallel "$LAST_SANDBOX" "metric-only"
assert_eq        "T-006 AC-5: hook exits 0 under metric-only" "0" "$LAST_EXIT_CODE"
assert_contains  "T-006 AC-5: stderr carries 'metric-only parallel: would stand down'" \
  "metric-only parallel: would stand down" "$LAST_STDERR"
# Fall-through means the serial path ran: a real boundary (T-001 shipped)
# with a successful inject writes `.auto-compact-pending` and emits the
# serial ticket-boundary additionalContext.
assert_file_exists "T-006 AC-5: metric-only falls through -> .auto-compact-pending written" \
  "$LAST_STATE_DIR/.auto-compact-pending"
assert_contains  "T-006 AC-5: metric-only falls through -> serial additionalContext emitted" \
  "auto-compact-on-ship (ticket-boundary)" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# T-006 AC-6: parallel_mode=off (explicit) -> existing serial behaviour,
# byte-identical (no stand-down log, injects as before).
# ---------------------------------------------------------------------------
echo "--- T-006 AC-6: parallel_mode=off -> existing serial behaviour (no new log) ---"
make_sandbox p_off
run_hook_parallel "$LAST_SANDBOX" "off"
assert_eq        "T-006 AC-6: hook exits 0 under parallel_mode=off" "0" "$LAST_EXIT_CODE"
# Byte-identity: NO parallel stand-down stderr line of any kind.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if printf '%s' "$LAST_STDERR" | grep -qiE 'parallel stand-down|metric-only parallel'; then
  echo -e "  ${RED}FAIL${NC} T-006 AC-6: off path emits NO parallel stand-down log"
  echo -e "       actual stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} T-006 AC-6: off path emits NO parallel stand-down log"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi
assert_file_exists "T-006 AC-6: off path injects -> .auto-compact-pending written" \
  "$LAST_STATE_DIR/.auto-compact-pending"
assert_contains  "T-006 AC-6: off path emits serial ticket-boundary additionalContext" \
  "auto-compact-on-ship (ticket-boundary)" "$LAST_STDOUT"
rm -rf "$LAST_SANDBOX"
echo ""

print_summary
