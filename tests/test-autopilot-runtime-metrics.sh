#!/usr/bin/env bash
# test-autopilot-runtime-metrics.sh — Plan 01: verify Stop / PreCompact hooks
# append runtime_metrics entries to autopilot-state.yaml with the correct
# `boundary` and `stop_reason` discrimination.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_STOP="$REPO_DIR/hooks/autopilot-continue.sh"
HOOK_PRECOMPACT="$REPO_DIR/hooks/pre-compact-save.sh"
FIXTURE_STATE_DIR="$REPO_DIR/tests/fixtures/autopilot-state-samples"
FIXTURE_PAYLOAD_DIR="$REPO_DIR/tests/fixtures/payloads"

# --- helpers ---

_setup_temp_repo() {
  TMP_REPO=$(mktemp -d)
  mkdir -p "$TMP_REPO/.simple-workflow/backlog/briefs/active/test-slug"
  STATE_PATH="$TMP_REPO/.simple-workflow/backlog/briefs/active/test-slug/autopilot-state.yaml"
}

_cleanup_temp_repo() {
  if [ -n "${TMP_REPO:-}" ] && [ -d "$TMP_REPO" ]; then
    rm -rf "$TMP_REPO"
    unset TMP_REPO
  fi
  rm -f /tmp/.autopilot-continue-test-* 2>/dev/null || true
}

_assert_state_contains() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qE -- "$pattern" "$file"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       File: $file"
    echo -e "       Expected pattern: $pattern"
    echo -e "       --- file contents ---"
    sed 's/^/       /' "$file" 1>&2 || true
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

_run_stop_hook() {
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

_run_precompact_hook() {
  local payload="$1"
  local stdout_file stderr_file
  stdout_file=$(mktemp); stderr_file=$(mktemp)
  set +e
  ( cd "$TMP_REPO" && bash "$HOOK_PRECOMPACT" <<<"$payload" ) >"$stdout_file" 2>"$stderr_file"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

echo "=== Autopilot runtime_metrics tests ==="
echo ""

# ---------------------------------------------------------------------------
# AC #3: stop hook writes session_end
# ---------------------------------------------------------------------------
echo "--- AC #3: stop hook writes session_end ---"
_setup_temp_repo
cp "$FIXTURE_STATE_DIR/multi-ticket.yaml" "$STATE_PATH"
PAYLOAD=$(cat "$FIXTURE_PAYLOAD_DIR/stop-hook-end-turn.json")
# multi-ticket.yaml has pending tickets, so the hook would normally block.
# Force the env-var loop guard release path to exercise the session_end write.
_run_stop_hook "$PAYLOAD" 5
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} stop hook writes session_end (exit 0)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} stop hook writes session_end (exit=$LAST_EXIT_CODE)"
  echo "       stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
_assert_state_contains "stop hook writes session_end (boundary)" "$STATE_PATH" 'boundary: session_end'
_assert_state_contains "stop hook writes session_end (cache_creation_input_tokens populated)" "$STATE_PATH" 'cache_creation_input_tokens: 716586'
_cleanup_temp_repo

# ---------------------------------------------------------------------------
# AC #4 case A: stop_reason is normal_completion when all tickets completed
# ---------------------------------------------------------------------------
echo ""
echo "--- AC #4: stop_reason is normal_completion when all tickets completed ---"
_setup_temp_repo
cat > "$STATE_PATH" <<'YAML'
version: 1
parent_slug: completed-fixture
started: 2026-04-29T00:00:00Z
execution_mode: split
total_tickets: 1
ticket_mapping:
  completed-fixture-part-1: 001-done
tickets:
  - logical_id: completed-fixture-part-1
    ticket_dir: .simple-workflow/backlog/active/completed-fixture/001-done
    status: completed
    steps: {scout: completed, impl: completed, ship: completed}
    invocation_method: {scout: skill, impl: skill, ship: skill}
manual_bash_fallbacks: []
runtime_metrics: []
YAML
_run_stop_hook '{"session_id":"test-normal","cache_creation_input_tokens":100,"cache_read_input_tokens":200,"input_tokens":300}'
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} stop hook normal_completion exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} stop hook normal_completion exit=$LAST_EXIT_CODE stderr=$LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
_assert_state_contains "stop_reason is normal_completion when all tickets completed" "$STATE_PATH" 'stop_reason: normal_completion'
_assert_state_contains "boundary: session_end (normal_completion case)" "$STATE_PATH" 'boundary: session_end'
_cleanup_temp_repo

# ---------------------------------------------------------------------------
# AC #4 case B: stop_reason is partial_completion when pending exists
# ---------------------------------------------------------------------------
echo ""
echo "--- AC #4: stop_reason is partial_completion when pending exists ---"
_setup_temp_repo
# Crafted fixture: ticket-level status is pending, but step-level all completed,
# so ACTIVE_STEPS=0 and the hook reaches the all-done exit path. The taxonomy
# heuristic then resolves to partial_completion based on ticket-level pending.
cat > "$STATE_PATH" <<'YAML'
version: 1
parent_slug: partial-fixture
started: 2026-04-29T00:00:00Z
execution_mode: split
total_tickets: 2
ticket_mapping:
  partial-fixture-part-1: 001-pending
  partial-fixture-part-2: 002-done
tickets:
  - logical_id: partial-fixture-part-1
    ticket_dir: .simple-workflow/backlog/active/partial-fixture/001-pending
    status: pending
    steps: {scout: completed, impl: completed, ship: completed}
    invocation_method: {scout: skill, impl: skill, ship: skill}
  - logical_id: partial-fixture-part-2
    ticket_dir: .simple-workflow/backlog/active/partial-fixture/002-done
    status: completed
    steps: {scout: completed, impl: completed, ship: completed}
    invocation_method: {scout: skill, impl: skill, ship: skill}
manual_bash_fallbacks: []
runtime_metrics: []
YAML
_run_stop_hook '{"session_id":"test-partial","cache_creation_input_tokens":50}'
_assert_state_contains "stop_reason is partial_completion when pending exists" "$STATE_PATH" 'stop_reason: partial_completion'
_cleanup_temp_repo

# ---------------------------------------------------------------------------
# AC #4 case C: stop_reason is loop_guard_release when AUTOPILOT-STALL emitted
# ---------------------------------------------------------------------------
echo ""
echo "--- AC #4: stop_reason is loop_guard_release when AUTOPILOT-STALL emitted ---"
_setup_temp_repo
cp "$FIXTURE_STATE_DIR/multi-ticket.yaml" "$STATE_PATH"
_run_stop_hook '{"session_id":"test-loop","cache_creation_input_tokens":99}' 5
_assert_state_contains "stop_reason is loop_guard_release when AUTOPILOT-STALL emitted" "$STATE_PATH" 'stop_reason: loop_guard_release'
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE -- '\[AUTOPILOT-STALL\]' <<<"$LAST_STDERR"; then
  echo -e "  ${GREEN}PASS${NC} hook emitted [AUTOPILOT-STALL] marker on stderr"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} hook did not emit [AUTOPILOT-STALL] marker on stderr"
  echo "       stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
_cleanup_temp_repo

# ---------------------------------------------------------------------------
# AC #5: precompact hook writes session_compaction
# ---------------------------------------------------------------------------
echo ""
echo "--- AC #5: precompact hook writes session_compaction ---"
_setup_temp_repo
cp "$FIXTURE_STATE_DIR/single-ticket.yaml" "$STATE_PATH"
_run_precompact_hook '{"session_id":"test-precompact","cache_creation_input_tokens":42,"cache_read_input_tokens":7,"input_tokens":3}'
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} precompact hook exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} precompact hook exit=$LAST_EXIT_CODE stderr=$LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
_assert_state_contains "precompact hook writes session_compaction (boundary)" "$STATE_PATH" 'boundary: session_compaction'
_assert_state_contains "precompact hook writes session_compaction (stop_reason: null)" "$STATE_PATH" 'stop_reason: null'
_cleanup_temp_repo

# ---------------------------------------------------------------------------
# AC #6: empty payload — hook exits 0 and writes literal `null` for missing fields
# ---------------------------------------------------------------------------
echo ""
echo "--- AC #6: empty payload populates literal null fields ---"
_setup_temp_repo
cat > "$STATE_PATH" <<'YAML'
version: 1
parent_slug: empty-payload-fixture
started: 2026-04-29T00:00:00Z
execution_mode: split
total_tickets: 1
ticket_mapping:
  empty-payload-fixture-part-1: 001-done
tickets:
  - logical_id: empty-payload-fixture-part-1
    ticket_dir: .simple-workflow/backlog/active/empty-payload-fixture/001-done
    status: completed
    steps: {scout: completed, impl: completed, ship: completed}
    invocation_method: {scout: skill, impl: skill, ship: skill}
manual_bash_fallbacks: []
runtime_metrics: []
YAML
EMPTY_PAYLOAD=$(cat "$FIXTURE_PAYLOAD_DIR/empty.json")
_run_stop_hook "$EMPTY_PAYLOAD"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} empty payload — hook exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} empty payload — hook exit=$LAST_EXIT_CODE stderr=$LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
_assert_state_contains "empty payload — entry has cache_creation_input_tokens: null" "$STATE_PATH" 'cache_creation_input_tokens: null'
_assert_state_contains "empty payload — entry has cache_read_input_tokens: null" "$STATE_PATH" 'cache_read_input_tokens: null'
_assert_state_contains "empty payload — entry has input_tokens: null" "$STATE_PATH" 'input_tokens: null'
_cleanup_temp_repo

# --- Summary ---
print_summary
