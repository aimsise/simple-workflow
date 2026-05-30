#!/usr/bin/env bash
# tests/test-session-start-next-compact.sh — P2-1 sentinel-based
# session-start `/compact` retry coverage for hooks/session-start.sh.
#
# AC mapping (verbatim from
# `.docs/dogfooding/33-34/P2-1-sentinel-file-based-session-resume.md`):
#
#   AC-5: source=startup OR source=resume + TTL-valid sentinel ->
#         calls `inject_keys '/compact' --enter`; sentinel timestamp
#         refreshed before the call. Detected via the canonical
#         `[inject-keys] DRY_RUN backend=tmux text=/compact ...` line.
#   AC-6: source=compact + sentinel present -> delete only, no
#         inject_keys call; stderr carries `sentinel cleared on
#         source=compact`.
#   AC-7: TTL-exceeded sentinel under startup/resume -> deleted
#         without retry; stderr carries
#         `stale sentinel ... removed without retry`.
#   AC-8: SW_AUTO_COMPACT_ON_SHIP_MODE=off -> entire P2-1 block is a
#         no-op (sentinel survives, no inject, no log line).
#
# Hermeticity: every case builds a self-contained `.simple-workflow/`
# tree under a `mktemp -d` sandbox, seeds an autopilot-state.yaml so
# `find_any_autopilot_state_file` resolves to the sandbox path, and
# uses `INJECT_KEYS_DRY_RUN=1` + `SW_TEST_HARNESS=1` so the
# `inject-keys` library short-circuits BEFORE the tmux verify path —
# the DRY_RUN stderr line is the proof that `inject_keys` was
# actually called. No real tmux server is required.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/hooks/session-start.sh"
TMUX_STUB="$SCRIPT_DIR/fixtures/tmux-stub.sh"

if [ ! -x "$HOOK" ]; then
  echo "ERROR: hook not executable: $HOOK" >&2
  exit 2
fi
if [ ! -x "$TMUX_STUB" ]; then
  echo "ERROR: tmux stub not executable: $TMUX_STUB" >&2
  exit 2
fi

# Hermetic PATH bin/ containing only a `tmux` symlink pointing at the
# fixture stub. `_inject_detect_backend` requires `command -v tmux` to
# succeed before it returns the tmux branch, so PATH must surface the
# stub even though the DRY_RUN short-circuit short-circuits before any
# subcommand is invoked.
PATH_BIN="$(mktemp -d)"
ln -sf "$TMUX_STUB" "$PATH_BIN/tmux"
trap 'rm -rf "$PATH_BIN"' EXIT

# Initialize state globals so `set -u` does not trip when the hook
# bails out before assigning them.
LAST_EXIT_CODE=0
LAST_STDOUT=""
LAST_STDERR=""
LAST_STATE_DIR=""
LAST_SENTINEL=""

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

# Build a hermetic sandbox with a minimal autopilot brief and seed a
# `.next-compact-pending` sentinel containing the requested timestamp.
#
# Args:
#   $1 — case label (used as a subdir name).
#   $2 — sentinel UNIX timestamp ("" to skip sentinel creation).
#
# Sets globals (no stdout output to avoid command-substitution subshells
# losing global assignments):
#   $LAST_SANDBOX   — absolute sandbox dir.
#   $LAST_STATE_DIR — brief dir (parent of autopilot-state.yaml).
#   $LAST_SENTINEL  — `.next-compact-pending` path under brief dir.
make_sandbox() {
  local label="$1"
  local sentinel_ts="$2"
  LAST_SANDBOX=$(mktemp -d)
  LAST_STATE_DIR="$LAST_SANDBOX/.simple-workflow/backlog/briefs/active/$label"
  mkdir -p "$LAST_STATE_DIR"
  cat > "$LAST_STATE_DIR/autopilot-state.yaml" <<EOF
parent_slug: $label
tickets:
  - logical_id: T-001
    status: in_progress
EOF
  LAST_SENTINEL="$LAST_STATE_DIR/.next-compact-pending"
  if [ -n "$sentinel_ts" ]; then
    printf '%s' "$sentinel_ts" > "$LAST_SENTINEL"
  fi
}

# Run hooks/session-start.sh in the sandbox with hermetic env: DRY_RUN
# tmux backend so inject_keys logs `[inject-keys] DRY_RUN ...` instead
# of touching a real tmux pane. PATH stripped of non-essentials so
# `find_any_autopilot_state_file` only sees the seeded state file.
run_session_start() {
  local sandbox="$1"
  local source="$2"
  local mode="${3:-on}"
  local ttl="${4:-}"
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  local env_ttl=()
  if [ -n "$ttl" ]; then
    env_ttl=(SW_NEXT_COMPACT_PENDING_TTL_SEC="$ttl")
  fi
  set +e
  printf '{"source":"%s"}' "$source" | env -i \
    HOME="$HOME" \
    PATH="$PATH_BIN:/usr/bin:/bin:/usr/local/bin" \
    TMUX="fake-socket,1,0" \
    TMUX_PANE="%test-pane" \
    TERM="${TERM:-xterm}" \
    INJECT_KEYS_DRY_RUN=1 \
    SW_TEST_HARNESS=1 \
    SW_AUTO_COMPACT_ON_SHIP_MODE="$mode" \
    "${env_ttl[@]}" \
    bash -c "cd \"$sandbox\" && bash \"$HOOK\"" >"$stdout_file" 2>"$stderr_file"
  LAST_EXIT_CODE=$?
  set -e
  # shellcheck disable=SC2034  # captured for symmetry with LAST_STDERR; available for stdout assertions
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

echo "=== hooks/session-start.sh — P2-1 .next-compact-pending sentinel ==="
echo ""

# ---------------------------------------------------------------------------
# AC-5: source=startup + TTL-valid sentinel -> inject_keys called.
# Sentinel timestamp is refreshed BEFORE the inject call, so after the
# hook returns the sentinel still exists (DRY_RUN does not advance to
# the success deletion path — that lives in the writer hooks, not in
# session-start.sh) and its timestamp is >= the seeded timestamp.
# ---------------------------------------------------------------------------
echo "--- AC-5: source=startup + TTL-valid sentinel -> /compact replayed ---"
TS_BEFORE=$(($(date +%s) - 100))
make_sandbox ac5-startup "$TS_BEFORE"
run_session_start "$LAST_SANDBOX" "startup"
assert_eq        "AC-5: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_contains  "AC-5: DRY_RUN inject-keys line emitted" \
  "[inject-keys] DRY_RUN backend=tmux target=%test-pane text=/compact enter=--enter" "$LAST_STDERR"
assert_contains  "AC-5: retry log carries source label" \
  "[SESSION-START-NEXT-COMPACT] retried /compact injection on source=startup" "$LAST_STDERR"
assert_file_exists "AC-5: sentinel still present (retained across retry attempts)" "$LAST_SENTINEL"
# Sentinel timestamp must have advanced past the seeded value (refresh
# before replay so subsequent attempts TTL-check against the new ts).
if [ -f "$LAST_SENTINEL" ]; then
  TS_AFTER=$(cat "$LAST_SENTINEL")
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$TS_AFTER" -ge "$TS_BEFORE" ]; then
    echo -e "  ${GREEN}PASS${NC} AC-5: sentinel timestamp refreshed (before=$TS_BEFORE after=$TS_AFTER)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AC-5: sentinel timestamp not refreshed (before=$TS_BEFORE after=$TS_AFTER)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
fi
rm -rf "$LAST_SANDBOX"
echo ""

# AC-5 (resume variant): source=resume MUST follow the same code path.
echo "--- AC-5: source=resume + TTL-valid sentinel -> /compact replayed ---"
TS_BEFORE=$(($(date +%s) - 50))
make_sandbox ac5-resume "$TS_BEFORE"
run_session_start "$LAST_SANDBOX" "resume"
assert_contains  "AC-5 (resume): DRY_RUN inject-keys line emitted" \
  "[inject-keys] DRY_RUN backend=tmux target=%test-pane text=/compact enter=--enter" "$LAST_STDERR"
assert_contains  "AC-5 (resume): retry log carries source=resume" \
  "[SESSION-START-NEXT-COMPACT] retried /compact injection on source=resume" "$LAST_STDERR"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# AC-6: source=compact + sentinel present -> delete only, no inject.
# ---------------------------------------------------------------------------
echo "--- AC-6: source=compact + sentinel present -> cleared, no inject ---"
make_sandbox ac6 "$(date +%s)"
run_session_start "$LAST_SANDBOX" "compact"
assert_eq        "AC-6: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_contains  "AC-6: 'sentinel cleared on source=compact' logged to stderr" \
  "sentinel cleared on source=compact" "$LAST_STDERR"
assert_not_contains "AC-6: NO DRY_RUN inject-keys line for /compact" \
  "DRY_RUN backend=tmux target=%test-pane text=/compact" "$LAST_STDERR"
assert_file_absent "AC-6: sentinel deleted after source=compact" "$LAST_SENTINEL"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# AC-7: TTL-exceeded sentinel under source=startup -> delete only.
# Force expiry by setting SW_NEXT_COMPACT_PENDING_TTL_SEC=1 and seeding
# the sentinel with a timestamp >5s in the past.
# ---------------------------------------------------------------------------
echo "--- AC-7: stale sentinel (TTL exceeded) -> removed without retry ---"
TS_STALE=$(($(date +%s) - 100))
make_sandbox ac7 "$TS_STALE"
run_session_start "$LAST_SANDBOX" "startup" "on" "1"
assert_eq        "AC-7: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_contains  "AC-7: stale-sentinel log emitted" \
  "stale sentinel" "$LAST_STDERR"
assert_contains  "AC-7: stale-sentinel log carries 'removed without retry'" \
  "removed without retry" "$LAST_STDERR"
assert_not_contains "AC-7: NO DRY_RUN inject-keys line for /compact" \
  "DRY_RUN backend=tmux target=%test-pane text=/compact" "$LAST_STDERR"
assert_file_absent "AC-7: sentinel deleted after TTL expiry" "$LAST_SENTINEL"
rm -rf "$LAST_SANDBOX"
echo ""

# ---------------------------------------------------------------------------
# AC-8: SW_AUTO_COMPACT_ON_SHIP_MODE=off -> entire P2-1 block is no-op.
# Sentinel survives, no inject, no log line.
# ---------------------------------------------------------------------------
echo "--- AC-8: SW_AUTO_COMPACT_ON_SHIP_MODE=off -> P2-1 no-op ---"
make_sandbox ac8 "$(date +%s)"
run_session_start "$LAST_SANDBOX" "startup" "off"
assert_eq        "AC-8: hook exits 0" "0" "$LAST_EXIT_CODE"
assert_not_contains "AC-8: NO inject-keys DRY_RUN line emitted" \
  "DRY_RUN backend=tmux target=%test-pane text=/compact" "$LAST_STDERR"
assert_not_contains "AC-8: NO [SESSION-START-NEXT-COMPACT] log line" \
  "[SESSION-START-NEXT-COMPACT]" "$LAST_STDERR"
assert_file_exists "AC-8: sentinel survives under kill-switch" "$LAST_SENTINEL"
rm -rf "$LAST_SANDBOX"
echo ""

print_summary
