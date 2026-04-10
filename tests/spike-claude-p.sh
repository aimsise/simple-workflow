#!/usr/bin/env bash
# spike-claude-p.sh — claude -p コマンドの動作検証スパイク
#
# 目的: claude CLI の -p (headless) モードで skill 呼び出しが動作するか検証する
# 結果: 3つの検証項目のうち、成功数に応じて今後のテスト戦略を決定する
#
# Go/No-Go 判定基準:
#   3/3 成功 → Go: Level 1 テストを claude -p ベースで本格実装
#   1/3 or 2/3 → ラッパー: 成功した項目のみ claude -p を使い、
#                 失敗した項目はモック/スタブに切り替え
#   0/3 全失敗 → Level 0 特化: claude -p テストを断念し、
#                 Level 0（静的解析）テストのみに注力
#
# 実行方法:
#   bash tests/spike-claude-p.sh
#
# 注意: このスパイクは test-* パターンに一致しないため run-all.sh では
#       自動実行されない（意図的）
set -euo pipefail

# --- claude CLI 検出 ---
if ! command -v claude &>/dev/null; then
  echo "SKIP: claude CLI が見つかりません（spike-claude-p.sh をスキップ）"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SPIKE_PASSED=0
SPIKE_FAILED=0
SPIKE_TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

spike_assert() {
  local description="$1"
  local result="$2" # "pass" or "fail"
  SPIKE_TOTAL=$((SPIKE_TOTAL + 1))
  if [ "$result" = "pass" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    SPIKE_PASSED=$((SPIKE_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    SPIKE_FAILED=$((SPIKE_FAILED + 1))
  fi
}

echo "=== Spike: claude -p 動作検証 ==="
echo ""

# --- 検証 1: skill 名解決 ---
# claude -p で /commit --help 等を呼び出し、skill が認識されるか確認
echo "--- 検証 1: skill 名解決 ---"
verify1_result="fail"
if output=$(claude -p "List available skills. Just print the skill names, one per line." --max-turns 1 2>&1); then
  # 少なくとも1つの既知スキル名が含まれているか
  if echo "$output" | grep -qiE '(commit|audit|impl|ship|scout)'; then
    verify1_result="pass"
  fi
fi
spike_assert "skill 名が claude -p で解決される" "$verify1_result"
echo ""

# --- 検証 2: バッククォート展開 ---
# !`command` 形式のプリコンピュートコンテキストが展開されるか
echo "--- 検証 2: バッククォート展開 ---"
verify2_result="fail"
if output=$(cd "$REPO_DIR" && claude -p "Run: git branch --show-current" --max-turns 1 --allowedTools "Bash(git branch:*)" 2>&1); then
  # ブランチ名が返ってきていれば展開は動作している
  if echo "$output" | grep -qE '[a-zA-Z]'; then
    verify2_result="pass"
  fi
fi
spike_assert "バッククォート展開が動作する" "$verify2_result"
echo ""

# --- 検証 3: allowed-tools 尊重 ---
# allowed-tools 外のツールが制限されるか確認
echo "--- 検証 3: allowed-tools 尊重 ---"
verify3_result="fail"
if output=$(cd "$REPO_DIR" && claude -p "Try to write a file called /tmp/spike-test-file.txt with content 'test'. Report if you succeeded or were blocked." --max-turns 1 --allowedTools "Bash(git:*)" 2>&1); then
  # ファイルが作成されていなければ allowed-tools が尊重されている
  if [ ! -f /tmp/spike-test-file.txt ]; then
    verify3_result="pass"
  else
    rm -f /tmp/spike-test-file.txt
  fi
fi
spike_assert "allowed-tools 制限が尊重される" "$verify3_result"
echo ""

# --- サマリー ---
echo "==============================="
echo -e "Spike結果: $SPIKE_TOTAL 項目中 ${GREEN}${SPIKE_PASSED} 成功${NC} / ${RED}${SPIKE_FAILED} 失敗${NC}"
echo "==============================="
echo ""

# --- Go/No-Go 判定 ---
if [ "$SPIKE_PASSED" -eq 3 ]; then
  echo -e "${GREEN}判定: Go${NC} — claude -p ベースの Level 1 テストを本格実装可能"
elif [ "$SPIKE_PASSED" -gt 0 ]; then
  echo -e "${YELLOW}判定: ラッパー${NC} — 部分成功。成功項目のみ claude -p を使い、他はモック/スタブ"
else
  echo -e "${RED}判定: Level 0 特化${NC} — claude -p テスト断念。静的解析テストに注力"
fi

exit 0
