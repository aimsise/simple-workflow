#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== session-stop-log.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/session-stop-log.sh"

# Trap to ensure cleanup on exit
trap 'cleanup_test_repo' EXIT

# Test 1: .simple-workflow/docs/session-log/session-log-*.md file is created
setup_test_repo
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
LOG_FILE=$(ls "$TEST_REPO"/.simple-workflow/docs/session-log/session-log-*.md 2>/dev/null | head -1)
if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
  echo -e "  ${GREEN}PASS${NC} session-log-*.md file is created"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} session-log-*.md file is created"
  echo -e "       No matching file found in $TEST_REPO/.simple-workflow/docs/session-log/"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: File begins with YAML frontmatter delimiter (---)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && [ "$(head -n 1 "$LOG_FILE")" = "---" ]; then
  echo -e "  ${GREEN}PASS${NC} File begins with YAML frontmatter delimiter '---'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File begins with YAML frontmatter delimiter '---'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: YAML frontmatter contains 'date:' key
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qE "^date:" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'date:' key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'date:' key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: YAML frontmatter contains 'branch:' key
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qE "^branch:" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'branch:' key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'branch:' key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: YAML frontmatter contains 'last_commit:' key
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qE "^last_commit:" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'last_commit:' key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'last_commit:' key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: YAML frontmatter contains 'changed_files:' key
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qE "^changed_files:" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'changed_files:' key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'changed_files:' key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: File content contains "# Session Work Log" heading
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qF "# Session Work Log" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains '# Session Work Log'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains '# Session Work Log'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: File content contains "## Final Status" section
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qF "## Final Status" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains '## Final Status'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains '## Final Status'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 9: File content contains "## Recent Commits" section
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$LOG_FILE" ] && grep -qF "## Recent Commits" "$LOG_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains '## Recent Commits'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains '## Recent Commits'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 10: Exit code is 0
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
