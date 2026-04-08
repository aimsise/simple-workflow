#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== session-stop-log.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/session-stop-log.sh"

# Trap to ensure cleanup on exit
trap 'cleanup_test_repo' EXIT

# Test 1: .docs/reviews/session-log-*.md file is created
setup_test_repo
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
LOG_FILE=$(ls "$TEST_REPO"/.docs/reviews/session-log-*.md 2>/dev/null | head -1)
if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
  echo -e "  ${GREEN}PASS${NC} session-log-*.md file is created"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} session-log-*.md file is created"
  echo -e "       No matching file found in $TEST_REPO/.docs/reviews/"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: File content contains "Branch:"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qF "Branch:" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains 'Branch:'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains 'Branch:'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: File content contains "Final State"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qF "Final State" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains 'Final State'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains 'Final State'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: File content contains "Recent Commits"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qF "Recent Commits" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains 'Recent Commits'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains 'Recent Commits'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: Exit code is 0
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} Exit code is 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Exit code is 0"
  echo -e "       Got: exit $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

cleanup_test_repo

echo ""

print_summary
