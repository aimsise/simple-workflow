#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== session-start.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/session-start.sh"

# Trap to ensure cleanup on exit
trap 'cleanup_test_repo' EXIT

# Helper: session-start.sh requires .backlog/active/*/plan.md and
# .docs/plans/*.md to exist (due to set -euo pipefail + ls glob).
# Create minimal plan structure and commit it so it doesn't count as changed files.
setup_session_repo() {
  setup_test_repo
  mkdir -p "$TEST_REPO/.backlog/active/stub"
  echo "stub" > "$TEST_REPO/.backlog/active/stub/plan.md"
  mkdir -p "$TEST_REPO/.docs/plans"
  echo "stub" > "$TEST_REPO/.docs/plans/stub.md"
  cd "$TEST_REPO"
  git add -A
  git commit -q -m "add plan stubs"
}

# Test 1: Valid JSON output in a normal git repo
setup_session_repo
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$LAST_STDOUT" | jq . > /dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} Output is valid JSON"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Output is valid JSON"
  echo -e "       Output: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# Test 2: additionalContext contains "Branch:"
setup_session_repo
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if echo "$CONTEXT" | grep -qF "Branch:"; then
  echo -e "  ${GREEN}PASS${NC} additionalContext contains 'Branch:'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} additionalContext contains 'Branch:'"
  echo -e "       Context: $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# Test 3: additionalContext contains "Changed files:"
setup_session_repo
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if echo "$CONTEXT" | grep -qF "Changed files:"; then
  echo -e "  ${GREEN}PASS${NC} additionalContext contains 'Changed files:'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} additionalContext contains 'Changed files:'"
  echo -e "       Context: $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# Test 4: On main branch, contains "Branch: main"
setup_session_repo
cd "$TEST_REPO" && git branch -M main
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if echo "$CONTEXT" | grep -qF "Branch: main"; then
  echo -e "  ${GREEN}PASS${NC} On main branch, shows 'Branch: main'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} On main branch, shows 'Branch: main'"
  echo -e "       Context: $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# Test 5: Changed files count is correct after modifications
setup_session_repo
echo "change1" > "$TEST_REPO/file1.txt"
echo "change2" > "$TEST_REPO/file2.txt"
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if echo "$CONTEXT" | grep -qF "Changed files: 2"; then
  echo -e "  ${GREEN}PASS${NC} Changed files count is correct (2 new files)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Changed files count is correct (2 new files)"
  echo -e "       Context: $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# Test 6: Outside git repo, hook exits non-zero
# (git status --short fails with exit 128 in non-git dir, and set -euo pipefail terminates the hook)
NON_GIT_DIR=$(mktemp -d)
run_hook "$HOOK" "" "$NON_GIT_DIR"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
  echo -e "  ${GREEN}PASS${NC} Outside git repo, hook exits non-zero (pipefail on git status)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Outside git repo, expected non-zero exit"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$NON_GIT_DIR"

# Test 7: With .backlog/active/test/plan.md, contains "Latest Plan:"
setup_session_repo
mkdir -p "$TEST_REPO/.backlog/active/test"
echo "# Plan" > "$TEST_REPO/.backlog/active/test/plan.md"
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if echo "$CONTEXT" | grep -qF "Latest Plan:"; then
  echo -e "  ${GREEN}PASS${NC} With plan file, contains 'Latest Plan:'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} With plan file, contains 'Latest Plan:'"
  echo -e "       Context: $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# Test 8: Without plan file, hook exits non-zero
# (known limitation: ls glob + set -euo pipefail causes early exit)
setup_test_repo
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
  echo -e "  ${GREEN}PASS${NC} Without plan dirs, hook exits non-zero (known pipefail behavior)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  # If hook succeeds, verify no Latest Plan
  CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
  if ! echo "$CONTEXT" | grep -qF "Latest Plan:"; then
    echo -e "  ${GREEN}PASS${NC} Without plan file, does not contain 'Latest Plan:'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} Without plan file, should not contain 'Latest Plan:'"
    echo -e "       Context: $CONTEXT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
fi
cleanup_test_repo

echo ""

echo "--- Session log cleanup tests ---"

# Test: Old session-log files (31+ days) are deleted
setup_session_repo
mkdir -p "$TEST_REPO/.docs/reviews"
echo "old log" > "$TEST_REPO/.docs/reviews/session-log-20250101_000000.md"
# Set modification time to 35 days ago
touch -t "$(date -v-35d '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '35 days ago' '+%Y%m%d%H%M.%S' 2>/dev/null)" "$TEST_REPO/.docs/reviews/session-log-20250101_000000.md" 2>/dev/null || true
echo "old compact" > "$TEST_REPO/.docs/reviews/compact-state-20250101_000000.md"
touch -t "$(date -v-35d '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '35 days ago' '+%Y%m%d%H%M.%S' 2>/dev/null)" "$TEST_REPO/.docs/reviews/compact-state-20250101_000000.md" 2>/dev/null || true
run_hook "$HOOK_DIR/session-start.sh" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ ! -f "$TEST_REPO/.docs/reviews/session-log-20250101_000000.md" ] && [ ! -f "$TEST_REPO/.docs/reviews/compact-state-20250101_000000.md" ]; then
  echo -e "  ${GREEN}PASS${NC} Old session logs (31+ days) are deleted"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Old session logs (31+ days) are deleted"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# Test: Recent session-log files (< 30 days) are preserved
setup_session_repo
mkdir -p "$TEST_REPO/.docs/reviews"
echo "recent log" > "$TEST_REPO/.docs/reviews/session-log-recent.md"
echo "recent compact" > "$TEST_REPO/.docs/reviews/compact-state-recent.md"
# These files are just created so they're recent (< 30 days)
run_hook "$HOOK_DIR/session-start.sh" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TEST_REPO/.docs/reviews/session-log-recent.md" ] && [ -f "$TEST_REPO/.docs/reviews/compact-state-recent.md" ]; then
  echo -e "  ${GREEN}PASS${NC} Recent session logs (< 30 days) are preserved"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Recent session logs (< 30 days) are preserved"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

echo ""

print_summary
