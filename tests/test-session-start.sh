#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== session-start.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/session-start.sh"

# Trap to ensure cleanup on exit
trap 'cleanup_test_repo' EXIT

# Helper: alias for setup_test_repo (basic git repo with initial commit)
setup_session_repo() {
  setup_test_repo
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
# Pre-seed .gitignore so session-start hook won't create one (which would inflate the count)
printf '.docs/\n.backlog/\n.simple-wf-knowledge/\n' > "$TEST_REPO/.gitignore"
cd "$TEST_REPO" && git add .gitignore && git commit -q -m "add gitignore"
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

# Test 6: Outside git repo, hook exits 0 with a graceful fallback context
# (guarded by `git rev-parse --git-dir` so the hook never aborts on non-git dirs)
NON_GIT_DIR=$(mktemp -d)
run_hook "$HOOK" "" "$NON_GIT_DIR"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} Outside git repo, hook exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Outside git repo, expected exit 0 but got $LAST_EXIT_CODE"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if echo "$CONTEXT" | grep -qF "(not a git repo)"; then
  echo -e "  ${GREEN}PASS${NC} Outside git repo, additionalContext reports '(not a git repo)'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Outside git repo, expected '(not a git repo)' marker in context"
  echo -e "       Context: $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$NON_GIT_DIR"

# Test 7: Output does not contain "Latest Plan:" or "Active:" (simplified hook)
setup_session_repo
mkdir -p "$TEST_REPO/.backlog/active/test"
echo "# Plan" > "$TEST_REPO/.backlog/active/test/plan.md"
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if ! echo "$CONTEXT" | grep -qE "Latest Plan:|Active:"; then
  echo -e "  ${GREEN}PASS${NC} Simplified hook does not contain 'Latest Plan:' or 'Active:'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Simplified hook should not contain 'Latest Plan:' or 'Active:'"
  echo -e "       Context: $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

echo ""

echo "--- Session log cleanup tests ---"

# Test: Old session-log files (31+ days) are deleted
setup_session_repo
mkdir -p "$TEST_REPO/.docs/session-log"
echo "old log" > "$TEST_REPO/.docs/session-log/session-log-20250101_000000.md"
# Set modification time to 35 days ago
touch -t "$(date -v-35d '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '35 days ago' '+%Y%m%d%H%M.%S' 2>/dev/null)" "$TEST_REPO/.docs/session-log/session-log-20250101_000000.md" 2>/dev/null || true
mkdir -p "$TEST_REPO/.docs/compact-state"
echo "old compact" > "$TEST_REPO/.docs/compact-state/compact-state-20250101_000000.md"
touch -t "$(date -v-35d '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '35 days ago' '+%Y%m%d%H%M.%S' 2>/dev/null)" "$TEST_REPO/.docs/compact-state/compact-state-20250101_000000.md" 2>/dev/null || true
run_hook "$HOOK_DIR/session-start.sh" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ ! -f "$TEST_REPO/.docs/session-log/session-log-20250101_000000.md" ] && [ ! -f "$TEST_REPO/.docs/compact-state/compact-state-20250101_000000.md" ]; then
  echo -e "  ${GREEN}PASS${NC} Old session logs (31+ days) are deleted"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Old session logs (31+ days) are deleted"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# Test: Recent session-log files (< 30 days) are preserved
setup_session_repo
mkdir -p "$TEST_REPO/.docs/session-log"
echo "recent log" > "$TEST_REPO/.docs/session-log/session-log-recent.md"
mkdir -p "$TEST_REPO/.docs/compact-state"
echo "recent compact" > "$TEST_REPO/.docs/compact-state/compact-state-recent.md"
# These files are just created so they're recent (< 30 days)
run_hook "$HOOK_DIR/session-start.sh" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TEST_REPO/.docs/session-log/session-log-recent.md" ] && [ -f "$TEST_REPO/.docs/compact-state/compact-state-recent.md" ]; then
  echo -e "  ${GREEN}PASS${NC} Recent session logs (< 30 days) are preserved"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Recent session logs (< 30 days) are preserved"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

echo ""

echo "--- .gitignore auto-append tests ---"

# Test: session-start.sh contains .gitignore handling logic
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF '.gitignore' "$HOOK"; then
  echo -e "  ${GREEN}PASS${NC} session-start.sh contains .gitignore logic"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} session-start.sh contains .gitignore logic"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: session-start.sh references all three gitignore entries
for entry in ".docs/" ".backlog/" ".simple-wf-knowledge/"; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qF "$entry" "$HOOK"; then
    echo -e "  ${GREEN}PASS${NC} session-start.sh references '$entry' entry"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} session-start.sh references '$entry' entry"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# --- Behavioral tests: .gitignore auto-append ---

# AC1 + AC2: No .gitignore exists -> hook creates it with all 3 entries and comment header
setup_test_repo
# Remove any .gitignore that setup_test_repo may have produced
rm -f "$TEST_REPO/.gitignore"
run_hook "$HOOK" "" "$TEST_REPO"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TEST_REPO/.gitignore" ]; then
  echo -e "  ${GREEN}PASS${NC} .gitignore created when none existed"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} .gitignore created when none existed"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

for entry in ".docs/" ".backlog/" ".simple-wf-knowledge/"; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qxF "$entry" "$TEST_REPO/.gitignore"; then
    echo -e "  ${GREEN}PASS${NC} .gitignore contains '$entry' after creation"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} .gitignore contains '$entry' after creation"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF '# simple-workflow plugin' "$TEST_REPO/.gitignore"; then
  echo -e "  ${GREEN}PASS${NC} .gitignore contains comment header '# simple-workflow plugin'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} .gitignore contains comment header '# simple-workflow plugin'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# AC3: Idempotency - running hook twice does not duplicate entries
setup_test_repo
rm -f "$TEST_REPO/.gitignore"
run_hook "$HOOK" "" "$TEST_REPO"
run_hook "$HOOK" "" "$TEST_REPO"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
DOCS_COUNT=$(grep -cxF '.docs/' "$TEST_REPO/.gitignore")
BACKLOG_COUNT=$(grep -cxF '.backlog/' "$TEST_REPO/.gitignore")
KNOWLEDGE_COUNT=$(grep -cxF '.simple-wf-knowledge/' "$TEST_REPO/.gitignore")
if [ "$DOCS_COUNT" -eq 1 ] && [ "$BACKLOG_COUNT" -eq 1 ] && [ "$KNOWLEDGE_COUNT" -eq 1 ]; then
  echo -e "  ${GREEN}PASS${NC} Idempotency: no duplicate entries after running hook twice"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Idempotency: entries duplicated (.docs/=$DOCS_COUNT .backlog/=$BACKLOG_COUNT .simple-wf-knowledge/=$KNOWLEDGE_COUNT)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# AC4: Existing .gitignore with user entries is preserved
setup_test_repo
printf 'node_modules/\n' > "$TEST_REPO/.gitignore"
run_hook "$HOOK" "" "$TEST_REPO"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qxF 'node_modules/' "$TEST_REPO/.gitignore"; then
  echo -e "  ${GREEN}PASS${NC} Existing user entry 'node_modules/' preserved after hook"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Existing user entry 'node_modules/' preserved after hook"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

for entry in ".docs/" ".backlog/" ".simple-wf-knowledge/"; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qxF "$entry" "$TEST_REPO/.gitignore"; then
    echo -e "  ${GREEN}PASS${NC} Plugin entry '$entry' added alongside existing entries"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} Plugin entry '$entry' added alongside existing entries"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done
cleanup_test_repo

# AC5: Non-git directory - .gitignore should NOT be created
NON_GIT_DIR_GITIGNORE=$(mktemp -d)
run_hook "$HOOK" "" "$NON_GIT_DIR_GITIGNORE"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ ! -f "$NON_GIT_DIR_GITIGNORE/.gitignore" ]; then
  echo -e "  ${GREEN}PASS${NC} .gitignore not created in non-git directory"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} .gitignore should not be created in non-git directory"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$NON_GIT_DIR_GITIGNORE"

echo ""

print_summary
