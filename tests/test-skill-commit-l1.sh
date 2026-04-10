#!/usr/bin/env bash
# test-skill-commit-l1.sh — /commit スキルの Level 1 統合テスト
#
# claude -p を使って実際に /commit を呼び出し、動作を検証する。
# Level 1 テストは CI では条件付き実行（RUN_LEVEL1_TESTS=true 必須）。
#
# 前提条件:
#   - claude CLI がインストールされている
#   - RUN_LEVEL1_TESTS=true が設定されている
#
# 安全策:
#   - テスト用一時リポジトリで実行
#   - trap で EXIT 時にクリーンアップ
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

# --- claude CLI 検出 ---
if ! command -v claude &>/dev/null; then
  echo "SKIP: claude CLI が見つかりません（test-skill-commit-l1.sh をスキップ）"
  exit 0
fi

# --- RUN_LEVEL1_TESTS 環境変数チェック ---
if [ "${RUN_LEVEL1_TESTS:-}" != "true" ]; then
  echo "SKIP: RUN_LEVEL1_TESTS が未設定です（test-skill-commit-l1.sh をスキップ）"
  exit 0
fi

# --- クリーンアップ ---
trap cleanup_test_repo EXIT

echo "=== Level 1: /commit スキル統合テスト ==="
echo ""

# --- テスト 1: 変更ありの状態で /commit を実行し、コミット数が増加する ---
echo "--- /commit でコミットが作成される ---"

setup_test_repo

# テスト用変更を作成
echo "new feature code" > feature.txt
git add feature.txt

# 現在のコミット数を記録
commit_count_before=$(git rev-list --count HEAD)

# /commit を claude -p で実行
# --max-turns を制限してハングを防止、timeout で CI 無限ブロックを防止
timeout 120 claude -p "/commit feat: add feature.txt" \
  --max-turns 5 \
  --allowedTools "Bash(git add:*),Bash(git status:*),Bash(git commit:*),Bash(git diff:*),Bash(git log:*)" \
  > /dev/null 2>&1 || true

# コミット数を再取得
commit_count_after=$(git rev-list --count HEAD)

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$commit_count_after" -gt "$commit_count_before" ]; then
  echo -e "  ${GREEN}PASS${NC} /commit 実行後にコミット数が増加 ($commit_count_before → $commit_count_after)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /commit 実行後にコミット数が増加しなかった ($commit_count_before → $commit_count_after)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- テスト 2: conventional commit 形式チェック ---
echo "--- conventional commit 形式の検証 ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$commit_count_after" -gt "$commit_count_before" ]; then
  latest_msg=$(git log -1 --format='%s')
  if echo "$latest_msg" | grep -qE '^(feat|fix|improve|chore|docs|test|perf)'; then
    echo -e "  ${GREEN}PASS${NC} 最新コミットが conventional commit 形式: '$latest_msg'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} 最新コミットが conventional commit 形式でない: '$latest_msg'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  echo -e "  ${RED}FAIL${NC} コミットが作成されなかったため形式チェックをスキップ"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- サマリー ---
print_summary
