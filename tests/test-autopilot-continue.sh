#!/usr/bin/env bash
# Tests for hooks/autopilot-continue.sh — autopilot pipeline Stop hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== autopilot-continue.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/autopilot-continue.sh"

# Trap to ensure cleanup on exit
trap 'cleanup_test_repo' EXIT

# Helper: create autopilot-state.yaml with given content
create_state_file() {
  local slug="$1"
  local content="$2"
  mkdir -p ".backlog/briefs/active/${slug}"
  echo "$content" > ".backlog/briefs/active/${slug}/autopilot-state.yaml"
}

# Helper: run the autopilot-continue hook with optional env vars
run_autopilot_hook() {
  local input="${1:-{}}"
  local cwd="${2:-.}"
  local env_count="${3:-}"

  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)

  set +e
  if [ -n "$env_count" ]; then
    echo "$input" | (cd "$cwd" && _AUTOPILOT_CONTINUE_COUNT="$env_count" bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  else
    echo "$input" | (cd "$cwd" && bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  fi
  local exit_code=$?
  set -e

  LAST_EXIT_CODE=$exit_code
  # shellcheck disable=SC2034
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

# ============================================================
# AC-1: No autopilot-state.yaml — allow stop
# ============================================================
echo "--- AC-1: No state file ---"

setup_test_repo
run_autopilot_hook '{}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} No state file: exit 0, no stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} No state file: exit 0, no stdout"
  echo -e "       Exit code: $LAST_EXIT_CODE, Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# AC-2: All tickets completed — allow stop
# ============================================================
echo "--- AC-2: All tickets completed ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: completed
    steps:
      create-ticket: completed
      scout: completed
      impl: completed
      ship: completed"

run_autopilot_hook '{}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} All completed: exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} All completed: exit 0"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# AC-3: All tickets failed/skipped — allow stop
# ============================================================
echo "--- AC-3: All tickets failed/skipped ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: split
total_tickets: 2
tickets:
  - logical_id: test-slug-part-1
    ticket_dir: 001-test
    status: failed
    steps:
      create-ticket: completed
      scout: failed
      impl: failed
      ship: failed
  - logical_id: test-slug-part-2
    ticket_dir: null
    status: skipped
    steps:
      create-ticket: skipped
      scout: skipped
      impl: skipped
      ship: skipped"

run_autopilot_hook '{}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} All failed/skipped: exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} All failed/skipped: exit 0"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# AC-4: scout in_progress — block stop
# ============================================================
echo "--- AC-4: scout in_progress ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: in_progress
      impl: pending
      ship: pending"

run_autopilot_hook '{"session_id":"test-ac4"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} scout in_progress: decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} scout in_progress: decision=block"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac4
cleanup_test_repo

# ============================================================
# AC-5: impl in_progress — block stop
# ============================================================
echo "--- AC-5: impl in_progress ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: completed
      impl: in_progress
      ship: pending"

run_autopilot_hook '{"session_id":"test-ac5"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} impl in_progress: decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} impl in_progress: decision=block"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac5
cleanup_test_repo

# ============================================================
# AC-6: ship in_progress — block stop
# ============================================================
echo "--- AC-6: ship in_progress ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: completed
      impl: completed
      ship: in_progress"

run_autopilot_hook '{"session_id":"test-ac6"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} ship in_progress: decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ship in_progress: decision=block"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac6
cleanup_test_repo

# ============================================================
# AC-7: reason contains required fields
# ============================================================
echo "--- AC-7: reason content ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: completed
      impl: in_progress
      ship: pending"

run_autopilot_hook '{"session_id":"test-ac7"}' "$TEST_REPO"
REASON=$(echo "$LAST_STDOUT" | jq -r '.reason // ""' 2>/dev/null || echo "")

# Check for autopilot-state.yaml mention
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -q "autopilot-state.yaml"; then
  echo -e "  ${GREEN}PASS${NC} reason mentions autopilot-state.yaml"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason mentions autopilot-state.yaml"
  echo -e "       Reason: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Check for autopilot mention
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -q "autopilot"; then
  echo -e "  ${GREEN}PASS${NC} reason mentions autopilot"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason mentions autopilot"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Check for next step name (impl in this case)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -q "impl"; then
  echo -e "  ${GREEN}PASS${NC} reason mentions next step (impl)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason mentions next step (impl)"
  echo -e "       Reason: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac7
cleanup_test_repo

# ============================================================
# AC-8: Loop guard — env var >= 5 allows stop
# ============================================================
echo "--- AC-8: Loop guard ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: in_progress
      impl: pending
      ship: pending"

# With _AUTOPILOT_CONTINUE_COUNT=5, should allow stop
run_autopilot_hook '{}' "$TEST_REPO" "5"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} Loop guard (count=5): exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Loop guard (count=5): exit 0"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# With _AUTOPILOT_CONTINUE_COUNT=10, should also allow stop
run_autopilot_hook '{}' "$TEST_REPO" "10"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} Loop guard (count=10): exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Loop guard (count=10): exit 0"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# With _AUTOPILOT_CONTINUE_COUNT=4, should still block
run_autopilot_hook '{"session_id":"test-ac8"}' "$TEST_REPO" "4"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} Loop guard (count=4): still blocks"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Loop guard (count=4): still blocks"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac8
cleanup_test_repo

# ============================================================
# AC-9: Split execution — multiple tickets
# ============================================================
echo "--- AC-9: Split execution ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: split
total_tickets: 4
tickets:
  - logical_id: test-slug-part-1
    ticket_dir: 001-done
    status: completed
    steps:
      create-ticket: completed
      scout: completed
      impl: completed
      ship: completed
  - logical_id: test-slug-part-2
    ticket_dir: 002-active
    status: in_progress
    steps:
      create-ticket: completed
      scout: in_progress
      impl: pending
      ship: pending
  - logical_id: test-slug-part-3
    ticket_dir: null
    status: pending
    steps:
      create-ticket: pending
      scout: pending
      impl: pending
      ship: pending
  - logical_id: test-slug-part-4
    ticket_dir: null
    status: pending
    steps:
      create-ticket: pending
      scout: pending
      impl: pending
      ship: pending"

run_autopilot_hook '{"session_id":"test-ac9"}' "$TEST_REPO"
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
REASON=$(echo "$LAST_STDOUT" | jq -r '.reason // ""' 2>/dev/null || echo "")

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} Split: decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Split: decision=block"
  echo -e "       Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Check reason mentions ticket 2's ticket_dir
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -q "002-active"; then
  echo -e "  ${GREEN}PASS${NC} Split: reason mentions ticket 2 dir (002-active)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Split: reason mentions ticket 2 dir (002-active)"
  echo -e "       Reason: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac9
cleanup_test_repo

# ============================================================
# AC-12: Empty stdin — no crash
# ============================================================
echo "--- AC-12: Empty stdin ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: in_progress
      impl: pending
      ship: pending"

# Run with completely empty stdin
AC12_STDOUT=$(mktemp)
AC12_STDERR=$(mktemp)
set +e
echo -n "" | (cd "$TEST_REPO" && bash "$HOOK") >"$AC12_STDOUT" 2>"$AC12_STDERR"
LAST_EXIT_CODE=$?
LAST_STDOUT=$(cat "$AC12_STDOUT")
LAST_STDERR=$(cat "$AC12_STDERR")
rm -f "$AC12_STDOUT" "$AC12_STDERR"
set -e

TESTS_TOTAL=$((TESTS_TOTAL + 1))
# Should not crash — either exit 0 or output valid JSON
if [ "$LAST_EXIT_CODE" -eq 0 ] || echo "$LAST_STDOUT" | jq -e '.decision' >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} Empty stdin: no crash"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Empty stdin: no crash"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

echo ""
print_summary
