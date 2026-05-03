#!/usr/bin/env bash
# test-runtime-metrics-write-window.sh — PX-03: verify the Stop hook
# (`hooks/autopilot-continue.sh`) and the PreCompact hook
# (`hooks/pre-compact-save.sh`) discover `autopilot-state.yaml` in three
# lookup roots — `briefs/active/`, `product_backlog/`, `briefs/done/` —
# in that priority order, and that the new `briefs/done/` fallback is
# only adopted when every pipeline step has reached `completed`.
#
# Five scenarios exercised (matching PX-03 AC #3 (a)–(e)):
#   (a) state file in briefs/active/ only → append (existing behaviour)
#   (b) state file in product_backlog/ only → append (existing behaviour)
#   (c) state file in briefs/done/ only, all steps completed → append
#       (new behaviour — boundary `session_end`)
#   (d) state file in briefs/done/ only, pending step remains → no append
#       (NAC #7 protection against premature partial_completion)
#   (e) state file in BOTH briefs/active/ AND briefs/done/ for the same
#       slug → briefs/active/ wins, briefs/done/ left untouched
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_STOP="$REPO_DIR/hooks/autopilot-continue.sh"

# --- helpers ---

_setup_temp_repo() {
  TMP_REPO=$(mktemp -d)
  mkdir -p "$TMP_REPO/.simple-workflow/backlog/briefs/active"
  mkdir -p "$TMP_REPO/.simple-workflow/backlog/briefs/done"
  mkdir -p "$TMP_REPO/.simple-workflow/backlog/product_backlog"
}

_cleanup_temp_repo() {
  if [ -n "${TMP_REPO:-}" ] && [ -d "$TMP_REPO" ]; then
    rm -rf "$TMP_REPO"
    unset TMP_REPO
  fi
  rm -f /tmp/.autopilot-continue-test-* 2>/dev/null || true
  rm -f /tmp/.autopilot-notool-test-* 2>/dev/null || true
}

_write_completed_state_file() {
  # $1 = path. Writes a state file whose every step is `completed`.
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'YAML'
version: 1
parent_slug: window-fixture
started: 2026-04-29T00:00:00Z
execution_mode: split
total_tickets: 1
ticket_mapping:
  window-fixture-part-1: 001-done
tickets:
  - logical_id: window-fixture-part-1
    ticket_dir: .simple-workflow/backlog/active/window-fixture/001-done
    status: completed
    steps: {scout: completed, impl: completed, ship: completed}
    invocation_method: {scout: skill, impl: skill, ship: skill}
manual_bash_fallbacks: []
runtime_metrics: []
YAML
}

_write_pending_state_file() {
  # $1 = path. Writes a state file with at least one pending step.
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'YAML'
version: 1
parent_slug: window-fixture-pending
started: 2026-04-29T00:00:00Z
execution_mode: split
total_tickets: 1
ticket_mapping:
  window-fixture-pending-part-1: 001-pending
tickets:
  - logical_id: window-fixture-pending-part-1
    ticket_dir: .simple-workflow/backlog/active/window-fixture-pending/001-pending
    status: in_progress
    steps: {scout: completed, impl: pending, ship: pending}
    invocation_method: {scout: skill, impl: unknown, ship: unknown}
manual_bash_fallbacks: []
runtime_metrics: []
YAML
}

_run_stop_hook() {
  # $1 = json payload, $2 = optional _AUTOPILOT_CONTINUE_COUNT (default 0)
  local payload="$1"
  local continue_count="${2:-0}"
  local stdout_file stderr_file
  stdout_file=$(mktemp); stderr_file=$(mktemp)
  set +e
  ( cd "$TMP_REPO" && _AUTOPILOT_CONTINUE_COUNT="$continue_count" bash "$HOOK_STOP" <<<"$payload" ) >"$stdout_file" 2>"$stderr_file"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

_count_runtime_metrics_entries() {
  # $1 = state file path. Returns the count of `boundary:` lines (one per entry).
  local path="$1"
  if [ ! -f "$path" ]; then
    echo 0
    return
  fi
  local count
  count=$(grep -c '^[[:space:]]*-[[:space:]]*boundary:' "$path" 2>/dev/null || true)
  # grep -c emits "0" on no matches but exits non-zero; `|| true` swallows the
  # exit. Strip any stray newlines so the caller sees a single integer.
  count=$(printf '%s' "$count" | tr -d '[:space:]')
  echo "${count:-0}"
}

_assert_metrics_count() {
  local description="$1"
  local path="$2"
  local expected="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local actual
  actual=$(_count_runtime_metrics_entries "$path")
  if [ "$actual" = "$expected" ]; then
    echo -e "  ${GREEN}PASS${NC} $description (entries=$actual)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       Expected entries: $expected"
    echo -e "       Actual entries:   $actual"
    echo -e "       --- file: $path ---"
    sed 's/^/       /' "$path" 1>&2 || true
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

_assert_grep() {
  local description="$1"
  local path="$2"
  local pattern="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ -f "$path" ] && grep -qE -- "$pattern" "$path"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       File: $path"
    echo -e "       Expected pattern: $pattern"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

_assert_exit_zero() {
  local description="$1"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$LAST_EXIT_CODE" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (exit=$LAST_EXIT_CODE)"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo "=== runtime_metrics write-window tests (PX-03) ==="
echo ""

# --- Sanity: hook source contracts for AC #1 / AC #2 -----------------------
echo "--- Sanity: lookup-root sequence in hook source files ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DONE_HITS_STOP=$(grep -cE 'find .*briefs/done.*autopilot-state\.yaml' "$HOOK_STOP" || true)
if [ "$DONE_HITS_STOP" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} autopilot-continue.sh references briefs/done find for autopilot-state.yaml"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} autopilot-continue.sh missing briefs/done find for autopilot-state.yaml"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DONE_HITS_PC=$(grep -cE 'find .*briefs/done.*autopilot-state\.yaml' "$REPO_DIR/hooks/pre-compact-save.sh" || true)
if [ "$DONE_HITS_PC" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} pre-compact-save.sh references briefs/done find for autopilot-state.yaml"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} pre-compact-save.sh missing briefs/done find for autopilot-state.yaml"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Order check: briefs/active → product_backlog → briefs/done in line-number order
# (the autopilot-state.yaml find calls — we filter on filename so the
# unrelated auto-kick.yaml find in autopilot-continue.sh does not interfere).
_check_order() {
  local description="$1"
  local file="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local active_line product_line done_line
  active_line=$(grep -nE 'find .*backlog/briefs/active.*autopilot-state\.yaml' "$file" | head -1 | awk -F: '{print $1}')
  product_line=$(grep -nE 'find .*backlog/product_backlog.*autopilot-state\.yaml' "$file" | head -1 | awk -F: '{print $1}')
  done_line=$(grep -nE 'find .*backlog/briefs/done.*autopilot-state\.yaml' "$file" | head -1 | awk -F: '{print $1}')
  if [ -n "$active_line" ] && [ -n "$product_line" ] && [ -n "$done_line" ] \
     && [ "$active_line" -lt "$product_line" ] && [ "$product_line" -lt "$done_line" ]; then
    echo -e "  ${GREEN}PASS${NC} $description (active=$active_line < product_backlog=$product_line < done=$done_line)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (active=$active_line product_backlog=$product_line done=$done_line)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}
_check_order "autopilot-continue.sh lookup order is active → product_backlog → done" "$HOOK_STOP"
_check_order "pre-compact-save.sh lookup order is active → product_backlog → done" "$REPO_DIR/hooks/pre-compact-save.sh"

PAYLOAD='{"session_id":"test-window","cache_creation_input_tokens":111,"cache_read_input_tokens":222,"input_tokens":333}'

# ---------------------------------------------------------------------------
# Scenario (a): state file in briefs/active/ only → append (existing behaviour)
# ---------------------------------------------------------------------------
echo ""
echo "--- (a) briefs/active/ only — append preserved ---"
_setup_temp_repo
ACTIVE_PATH="$TMP_REPO/.simple-workflow/backlog/briefs/active/win-a/autopilot-state.yaml"
_write_completed_state_file "$ACTIVE_PATH"
_run_stop_hook "$PAYLOAD"
_assert_exit_zero "(a) Stop hook exits 0"
_assert_metrics_count "(a) one runtime_metrics entry appended" "$ACTIVE_PATH" 1
_assert_grep "(a) boundary is session_end" "$ACTIVE_PATH" 'boundary: session_end'
_assert_grep "(a) stop_reason is normal_completion" "$ACTIVE_PATH" 'stop_reason: normal_completion'
_cleanup_temp_repo

# ---------------------------------------------------------------------------
# Scenario (b): state file in product_backlog/ only → append (existing behaviour)
# ---------------------------------------------------------------------------
echo ""
echo "--- (b) product_backlog/ only — append preserved ---"
_setup_temp_repo
PB_PATH="$TMP_REPO/.simple-workflow/backlog/product_backlog/win-b/autopilot-state.yaml"
_write_completed_state_file "$PB_PATH"
_run_stop_hook "$PAYLOAD"
_assert_exit_zero "(b) Stop hook exits 0"
_assert_metrics_count "(b) one runtime_metrics entry appended" "$PB_PATH" 1
_assert_grep "(b) boundary is session_end" "$PB_PATH" 'boundary: session_end'
_cleanup_temp_repo

# ---------------------------------------------------------------------------
# Scenario (c): briefs/done/ only, all steps completed → append (new)
# ---------------------------------------------------------------------------
echo ""
echo "--- (c) briefs/done/ only, all steps completed — new fallback append ---"
_setup_temp_repo
DONE_PATH="$TMP_REPO/.simple-workflow/backlog/briefs/done/win-c/autopilot-state.yaml"
_write_completed_state_file "$DONE_PATH"
_run_stop_hook "$PAYLOAD"
_assert_exit_zero "(c) Stop hook exits 0"
_assert_metrics_count "(c) one runtime_metrics entry appended" "$DONE_PATH" 1
_assert_grep "(c) boundary is session_end" "$DONE_PATH" 'boundary: session_end'
_assert_grep "(c) stop_reason is normal_completion" "$DONE_PATH" 'stop_reason: normal_completion'
_cleanup_temp_repo

# ---------------------------------------------------------------------------
# Scenario (d): briefs/done/ only, pending step remains → NO append
# ---------------------------------------------------------------------------
echo ""
echo "--- (d) briefs/done/ with pending step — no append (NAC #7) ---"
_setup_temp_repo
DONE_PATH="$TMP_REPO/.simple-workflow/backlog/briefs/done/win-d/autopilot-state.yaml"
_write_pending_state_file "$DONE_PATH"
PRE_BYTES=$(wc -c < "$DONE_PATH")
_run_stop_hook "$PAYLOAD"
_assert_exit_zero "(d) Stop hook exits 0 (graceful no-op)"
_assert_metrics_count "(d) zero runtime_metrics entries (no premature partial_completion)" "$DONE_PATH" 0
POST_BYTES=$(wc -c < "$DONE_PATH")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$PRE_BYTES" = "$POST_BYTES" ]; then
  echo -e "  ${GREEN}PASS${NC} (d) state file unchanged in size ($PRE_BYTES bytes)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (d) state file mutated: pre=$PRE_BYTES post=$POST_BYTES"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
_cleanup_temp_repo

# ---------------------------------------------------------------------------
# Scenario (e): both briefs/active/ AND briefs/done/ have same-slug state
#               file → briefs/active/ wins, briefs/done/ untouched
# ---------------------------------------------------------------------------
echo ""
echo "--- (e) duplicate slug across active & done — active wins, done untouched ---"
_setup_temp_repo
ACTIVE_PATH="$TMP_REPO/.simple-workflow/backlog/briefs/active/win-e/autopilot-state.yaml"
DONE_PATH="$TMP_REPO/.simple-workflow/backlog/briefs/done/win-e/autopilot-state.yaml"
_write_completed_state_file "$ACTIVE_PATH"
_write_completed_state_file "$DONE_PATH"
DONE_PRE_HASH=$(shasum "$DONE_PATH" | awk '{print $1}')
DONE_PRE_MTIME=$(stat -f %m "$DONE_PATH" 2>/dev/null || stat -c %Y "$DONE_PATH" 2>/dev/null)
# Sleep one second so any mutation produces an mtime delta we can detect.
sleep 1
_run_stop_hook "$PAYLOAD"
_assert_exit_zero "(e) Stop hook exits 0"
_assert_metrics_count "(e) briefs/active/ state file has one new entry" "$ACTIVE_PATH" 1
_assert_metrics_count "(e) briefs/done/ state file has zero entries" "$DONE_PATH" 0
DONE_POST_HASH=$(shasum "$DONE_PATH" | awk '{print $1}')
DONE_POST_MTIME=$(stat -f %m "$DONE_PATH" 2>/dev/null || stat -c %Y "$DONE_PATH" 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DONE_PRE_HASH" = "$DONE_POST_HASH" ]; then
  echo -e "  ${GREEN}PASS${NC} (e) briefs/done/ state file content unchanged (sha1 stable)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (e) briefs/done/ state file content mutated: pre=$DONE_PRE_HASH post=$DONE_POST_HASH"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DONE_PRE_MTIME" = "$DONE_POST_MTIME" ]; then
  echo -e "  ${GREEN}PASS${NC} (e) briefs/done/ state file mtime unchanged"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (e) briefs/done/ mtime mutated: pre=$DONE_PRE_MTIME post=$DONE_POST_MTIME"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
_cleanup_temp_repo

# --- Summary ---
print_summary
