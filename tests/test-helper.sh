#!/usr/bin/env bash
# Test helper - no external dependencies

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0
# shellcheck disable=SC2034
CURRENT_TEST=""

# Root directory of the hooks under test
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
# shellcheck disable=SC2034
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Pipe a JSON input into pre-bash-safety.sh and capture the exit code and stderr
run_safety_hook() {
  local command="$1"
  local cwd="${2:-.}"
  local json
  json=$(jq -n --arg cmd "$command" --arg cwd "$cwd" '{"tool_input": {"command": $cmd}, "cwd": $cwd}')

  local stderr_file
  stderr_file=$(mktemp)

  set +e
  echo "$json" | bash "$HOOK_DIR/pre-bash-safety.sh" 2>"$stderr_file"
  local exit_code=$?
  set -e

  LAST_EXIT_CODE=$exit_code
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stderr_file"
}

# Assert that a command is allowed (exit 0)
assert_allowed() {
  local description="$1"
  local command="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  # shellcheck disable=SC2034
  CURRENT_TEST="$description"

  run_safety_hook "$command"

  if [ "$LAST_EXIT_CODE" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       Expected: exit 0 (allowed)"
    echo -e "       Got: exit $LAST_EXIT_CODE"
    echo -e "       Stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Assert that a command is blocked (exit 2)
assert_blocked() {
  local description="$1"
  local command="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  # shellcheck disable=SC2034
  CURRENT_TEST="$description"

  run_safety_hook "$command"

  if [ "$LAST_EXIT_CODE" -eq 2 ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       Expected: exit 2 (blocked)"
    echo -e "       Got: exit $LAST_EXIT_CODE"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Assert that a command is blocked and stderr contains the expected message
assert_blocked_message() {
  local description="$1"
  local command="$2"
  local expected_message="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  # shellcheck disable=SC2034
  CURRENT_TEST="$description"

  run_safety_hook "$command"

  if [ "$LAST_EXIT_CODE" -eq 2 ] && echo "$LAST_STDERR" | grep -qF "$expected_message"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    if [ "$LAST_EXIT_CODE" -ne 2 ]; then
      echo -e "       Expected: exit 2, Got: exit $LAST_EXIT_CODE"
    fi
    if ! echo "$LAST_STDERR" | grep -qF "$expected_message"; then
      echo -e "       Expected stderr to contain: $expected_message"
      echo -e "       Actual stderr: $LAST_STDERR"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# For bulk staging tests: create a temporary git repository
setup_test_repo() {
  TEST_REPO=$(mktemp -d)
  cd "$TEST_REPO"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > README.md
  git add README.md
  git commit -q -m "initial"
}

# Clean up the temporary git repository
cleanup_test_repo() {
  if [ -n "${TEST_REPO:-}" ] && [ -d "$TEST_REPO" ]; then
    rm -rf "$TEST_REPO"
    unset TEST_REPO
  fi
}

# Generic hook runner: pipe stdin to an arbitrary hook
run_hook() {
  local hook_path="$1"
  local input="$2"
  local cwd="${3:-.}"

  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)

  set +e
  echo "$input" | (cd "$cwd" && bash "$hook_path") >"$stdout_file" 2>"$stderr_file"
  local exit_code=$?
  set -e

  LAST_EXIT_CODE=$exit_code
  # shellcheck disable=SC2034
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

# Print the test result summary
print_summary() {
  echo ""
  echo "==============================="
  echo -e "Total: $TESTS_TOTAL | ${GREEN}Passed: $TESTS_PASSED${NC} | ${RED}Failed: $TESTS_FAILED${NC}"
  echo "==============================="

  if [ "$TESTS_FAILED" -gt 0 ]; then
    return 1
  fi
  return 0
}
