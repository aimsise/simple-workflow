#!/usr/bin/env bash
# shellcheck disable=SC2034
# テストヘルパー - 外部依存なし

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0
CURRENT_TEST=""

# テスト対象フックのルートディレクトリ
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"

# カラー出力
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# pre-bash-safety.sh にJSON入力を渡してexit codeとstderrをキャプチャする関数
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

# コマンドが許可されること（exit 0）を検証
assert_allowed() {
  local description="$1"
  local command="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
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

# コマンドがブロックされること（exit 2）を検証
assert_blocked() {
  local description="$1"
  local command="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
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

# コマンドがブロックされ、stderrに期待するメッセージを含むことを検証
assert_blocked_message() {
  local description="$1"
  local command="$2"
  local expected_message="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
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

# 一括ステージングテスト用: 一時gitリポジトリ作成
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

# 一時gitリポジトリの削除
cleanup_test_repo() {
  if [ -n "${TEST_REPO:-}" ] && [ -d "$TEST_REPO" ]; then
    rm -rf "$TEST_REPO"
    unset TEST_REPO
  fi
}

# フック実行（一般用: 任意フックにstdinを渡す）
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
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

# テスト結果サマリー表示
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
