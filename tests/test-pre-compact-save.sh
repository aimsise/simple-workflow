#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== pre-compact-save.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/pre-compact-save.sh"

# Trap to ensure cleanup on exit
trap 'cleanup_test_repo' EXIT

# Test 1: .docs/reviews/compact-state-*.md file is created
setup_test_repo
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
COMPACT_FILE=$(ls "$TEST_REPO"/.docs/reviews/compact-state-*.md 2>/dev/null | head -1)
if [ -n "$COMPACT_FILE" ] && [ -f "$COMPACT_FILE" ]; then
  echo -e "  ${GREEN}PASS${NC} compact-state-*.md file is created"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} compact-state-*.md file is created"
  echo -e "       No matching file found in $TEST_REPO/.docs/reviews/"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: File content contains "Branch:"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qF "Branch:" "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains 'Branch:'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains 'Branch:'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: File content contains "Changed Files"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qF "Changed Files" "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains 'Changed Files'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains 'Changed Files'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: File content contains "Git Status"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qF "Git Status" "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains 'Git Status'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains 'Git Status'"
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
