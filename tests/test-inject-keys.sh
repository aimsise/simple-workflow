#!/usr/bin/env bash
# test-inject-keys.sh — exercises the P1-1 post-inject verify added to
# hooks/lib/inject-keys.sh's tmux backend.
#
# Test cases:
#   AC-1: verify failure path -> rc=1 + `[INJECT-VERIFY] missed` stderr.
#   AC-2: verify success path -> rc=0, no `[INJECT-VERIFY] missed`.
#   AC-3: inject_keys_failure_hint emits a string containing
#         `verify window` for a verify-missed log.
#   AC-4: opt-out (`SW_INJECT_KEYS_VERIFY=0`) preserves rc=0 even when
#         capture-pane is empty (legacy / pre-P1-1 behaviour).
#   AC-5: DRY_RUN path unchanged — verify block does not run; stderr
#         carries the canonical `[inject-keys] DRY_RUN backend=tmux ...`
#         line and rc=0.
#   AC-6: `SW_INJECT_KEYS_VERIFY_SLEEP_MS` override is reflected in the
#         miss-log "after Nms" suffix.
#
# Hermetic via tests/fixtures/tmux-stub.sh: a `tmux` symlink at the
# front of PATH redirects `send-keys` + `capture-pane` to the stub so
# the test never touches a real tmux server.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INJ_LIB="$REPO_DIR/hooks/lib/inject-keys.sh"
TMUX_STUB="$SCRIPT_DIR/fixtures/tmux-stub.sh"

# Standalone assert helpers (the shared test-helper.sh assertions are
# tailored to pre-bash-safety.sh; inject-keys needs richer return-value
# + stderr-substring checks).
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

assert_not_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       forbidden substring: $needle"
    echo -e "       actual haystack:     $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo "=== hooks/lib/inject-keys.sh — P1-1 post-inject verify ==="
echo ""

# Pre-flight: the production lib and the tmux stub must exist.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -r "$INJ_LIB" ] && [ -x "$TMUX_STUB" ]; then
  echo -e "  ${GREEN}PASS${NC} pre-flight: inject-keys.sh + tmux stub are present and executable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} pre-flight: missing $INJ_LIB or $TMUX_STUB"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  print_summary || exit 1
  exit 1
fi

# Build a hermetic bin/ that contains ONLY a `tmux` symlink pointing
# at the stub, and prepend it to PATH for every invocation below.
INJ_BIN="$(mktemp -d)"
trap 'rm -rf "$INJ_BIN"' EXIT
ln -sf "$TMUX_STUB" "$INJ_BIN/tmux"

# Common harness: run inject_keys under the stubbed PATH with a fake
# TMUX socket + pane so the tmux branch is selected, and capture both
# the rc and the merged stdout+stderr.
#
# Reads pass-through env assignments from named globals (we cannot
# concatenate them into one string and let bash word-split because the
# canned `SW_TEST_TMUX_CAPTURE_OUT` payloads contain spaces that must
# stay inside the value). Each caller sets the globals it needs, calls
# run_inject_keys, then unsets them.
#
# Globals (all optional; unset = not exported):
#   IK_DRY_RUN, IK_HARNESS, IK_VERIFY, IK_SLEEP_MS,
#   IK_CAPTURE_OUT, IK_SENDKEYS_RC
#
# Args: text -- string to inject
# Side effects: sets INJ_RC and INJ_OUT.
run_inject_keys() {
  local text="$1"
  local out
  set +e
  out=$(env -i \
        HOME="$HOME" \
        PATH="$INJ_BIN:/usr/bin:/bin" \
        TMUX="fake-socket,1,0" \
        TMUX_PANE="%test-pane" \
        TERM="${TERM:-xterm}" \
        ${IK_DRY_RUN+INJECT_KEYS_DRY_RUN="$IK_DRY_RUN"} \
        ${IK_HARNESS+SW_TEST_HARNESS="$IK_HARNESS"} \
        ${IK_VERIFY+SW_INJECT_KEYS_VERIFY="$IK_VERIFY"} \
        ${IK_SLEEP_MS+SW_INJECT_KEYS_VERIFY_SLEEP_MS="$IK_SLEEP_MS"} \
        ${IK_CAPTURE_OUT+SW_TEST_TMUX_CAPTURE_OUT="$IK_CAPTURE_OUT"} \
        ${IK_SENDKEYS_RC+SW_TEST_TMUX_SENDKEYS_RC="$IK_SENDKEYS_RC"} \
        bash -c "source \"$INJ_LIB\" && inject_keys \"$text\" --enter" 2>&1)
  INJ_RC=$?
  INJ_OUT="$out"
  set -e
}

reset_ik_env() {
  unset IK_DRY_RUN IK_HARNESS IK_VERIFY IK_SLEEP_MS IK_CAPTURE_OUT IK_SENDKEYS_RC
}

# ---------------------------------------------------------------------------
# AC-1: verify failure (capture-pane is empty so the injected text is
# not visible). Expect rc=1 + `[INJECT-VERIFY] missed`.
# ---------------------------------------------------------------------------
echo "--- AC-1: verify failure path ---"
reset_ik_env
IK_SLEEP_MS=0
IK_CAPTURE_OUT=""
run_inject_keys "/compact"
assert_eq    "AC-1: rc is 1 when capture-pane lacks injected text" "1" "$INJ_RC"
assert_contains "AC-1: stderr carries '[INJECT-VERIFY] missed'" "[INJECT-VERIFY] missed" "$INJ_OUT"
assert_contains "AC-1: miss log includes TMUX_PANE marker" "TMUX_PANE=%test-pane" "$INJ_OUT"
assert_contains "AC-1: miss log echoes the injected text"  "text=/compact" "$INJ_OUT"
echo ""

# ---------------------------------------------------------------------------
# AC-2: verify success (capture-pane returns a line containing the
# injected text). Expect rc=0 and no miss marker.
# ---------------------------------------------------------------------------
echo "--- AC-2: verify success path ---"
reset_ik_env
IK_SLEEP_MS=0
IK_CAPTURE_OUT="user@host: > /compact (echoed)"
run_inject_keys "/compact"
assert_eq    "AC-2: rc is 0 when capture-pane shows injected text" "0" "$INJ_RC"
assert_not_contains "AC-2: stderr has no '[INJECT-VERIFY] missed'" "[INJECT-VERIFY] missed" "$INJ_OUT"
assert_contains "AC-2: status line still emits backend=tmux"        "[inject-keys] backend=tmux" "$INJ_OUT"
echo ""

# ---------------------------------------------------------------------------
# AC-3: inject_keys_failure_hint substring contract — given a stderr
# log shaped like the AC-1 stderr, the hint MUST contain "verify window".
# This is what `pre-next-scout-auto-compact.sh` / `post-ship-state-auto-compact.sh`
# feed into `additionalContext` after `auto-compact-on-ship: injection failed — `.
# ---------------------------------------------------------------------------
echo "--- AC-3: inject_keys_failure_hint emits 'verify window' for verify-missed log ---"
set +e
AC3_HINT=$(bash -c "source \"$INJ_LIB\" && inject_keys_failure_hint '[INJECT-VERIFY] missed: text=/compact not in capture-pane after 150ms (TMUX_PANE=%42)'" 2>&1)
set -e
assert_contains "AC-3: failure-hint includes substring 'verify window'" "verify window" "$AC3_HINT"
# Defense in depth: ensure the hint references SW_INJECT_KEYS_VERIFY so users
# can find the kill-switch from the surfaced additionalContext.
assert_contains "AC-3: failure-hint references SW_INJECT_KEYS_VERIFY"  "SW_INJECT_KEYS_VERIFY" "$AC3_HINT"
# Sanity: the generic tmux-failed branch is NOT what fires here (verify-missed
# branch must precede it in the case ladder).
assert_not_contains "AC-3: failure-hint does NOT fall through to 'tmux backend failed'" \
  "tmux backend failed" "$AC3_HINT"
echo ""

# ---------------------------------------------------------------------------
# AC-4: SW_INJECT_KEYS_VERIFY=0 -> opt-out. Even with empty capture-pane
# (which would otherwise be a verify miss), rc MUST track tmux send-keys
# exit code only. The stub returns rc=0 for send-keys, so we expect 0.
# ---------------------------------------------------------------------------
echo "--- AC-4: SW_INJECT_KEYS_VERIFY=0 opt-out preserves rc=0 ---"
reset_ik_env
IK_VERIFY=0
IK_CAPTURE_OUT=""
run_inject_keys "/compact"
assert_eq    "AC-4: rc is 0 when opt-out is set, even with empty capture" "0" "$INJ_RC"
assert_not_contains "AC-4: stderr has no '[INJECT-VERIFY] missed' under opt-out" \
  "[INJECT-VERIFY] missed" "$INJ_OUT"
assert_contains "AC-4: status line still emits backend=tmux under opt-out" \
  "[inject-keys] backend=tmux" "$INJ_OUT"

# Cross-check: opt-out + a non-zero send-keys rc should still surface
# failure (so the kill-switch only disables the verify block, not the
# downstream S5 rc check).
reset_ik_env
IK_VERIFY=0
IK_SENDKEYS_RC=42
IK_CAPTURE_OUT=""
run_inject_keys "/compact"
assert_eq    "AC-4: opt-out still surfaces send-keys rc=42 as inject_keys rc=1" "1" "$INJ_RC"
assert_contains "AC-4: opt-out failure status line carries rc=42 detail" "failed (rc=42)" "$INJ_OUT"
echo ""

# ---------------------------------------------------------------------------
# AC-5: DRY_RUN path unchanged. With INJECT_KEYS_DRY_RUN=1 +
# SW_TEST_HARNESS=1 the library short-circuits BEFORE the verify block,
# so the canonical stderr line must appear verbatim, and the rc must
# be 0 regardless of capture-pane state.
# ---------------------------------------------------------------------------
echo "--- AC-5: DRY_RUN early-return is unchanged by P1-1 ---"
reset_ik_env
IK_DRY_RUN=1
IK_HARNESS=1
IK_CAPTURE_OUT=""
run_inject_keys "/compact"
assert_eq    "AC-5: DRY_RUN rc is 0" "0" "$INJ_RC"
assert_contains "AC-5: DRY_RUN stderr carries the canonical line" \
  "[inject-keys] DRY_RUN backend=tmux target=%test-pane text=/compact enter=--enter" "$INJ_OUT"
assert_not_contains "AC-5: DRY_RUN does NOT trigger the verify block" \
  "[INJECT-VERIFY] missed" "$INJ_OUT"
assert_not_contains "AC-5: DRY_RUN does NOT emit a real backend status line" \
  "[inject-keys] backend=tmux" "$INJ_OUT"
echo ""

# ---------------------------------------------------------------------------
# AC-6: SW_INJECT_KEYS_VERIFY_SLEEP_MS override reflected in miss log.
# ---------------------------------------------------------------------------
echo "--- AC-6: SW_INJECT_KEYS_VERIFY_SLEEP_MS=300 override ---"
reset_ik_env
IK_SLEEP_MS=300
IK_CAPTURE_OUT=""
run_inject_keys "/compact"
assert_eq    "AC-6: rc is still 1 on miss with 300ms sleep" "1" "$INJ_RC"
assert_contains "AC-6: miss log reflects 'after 300ms'" "after 300ms" "$INJ_OUT"
echo ""

# Print summary and propagate the failure count as exit code.
print_summary
