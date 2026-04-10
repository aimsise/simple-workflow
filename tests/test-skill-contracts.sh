#!/usr/bin/env bash
# test-skill-contracts.sh — スキル間契約・構造整合性テスト (Level 0)
#
# test-path-consistency.sh のカテゴリ 1-20 と重複しない新規カテゴリ A-H を実装。
# 各カテゴリの差分コメントで既存テストとの境界を明記。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Local helpers ---

# YAML frontmatter からスカラーフィールドを抽出（test-path-consistency.sh と同パターン）
extract_frontmatter_field() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    BEGIN { in_fm = 0; depth = 0 }
    /^---[[:space:]]*$/ {
      depth++
      if (depth == 1) { in_fm = 1; next }
      if (depth == 2) { exit }
    }
    in_fm && $0 ~ "^"field":" {
      sub("^"field":[[:space:]]*", "", $0)
      sub(/^"/, "", $0); sub(/"$/, "", $0)
      sub(/^>-?[[:space:]]*$/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

# frontmatter 全体をテキストとして抽出
extract_frontmatter_block() {
  local file="$1"
  awk '
    BEGIN { in_fm = 0; depth = 0 }
    /^---[[:space:]]*$/ {
      depth++
      if (depth == 1) { in_fm = 1; next }
      if (depth == 2) { exit }
    }
    in_fm { print }
  ' "$file"
}

assert_file_contains() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qE -- "$pattern" "$file"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       File: $file"
    echo -e "       Expected pattern: $pattern"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_true() {
  local description="$1"
  local condition="$2" # "true" or "false"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$condition" = "true" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo "=== Skill Contract Tests ==="
echo ""

# =============================================================================
# カテゴリ A: disable-model-invocation 契約
# 差分: 既存 Cat 5 は name/description の存在のみ検証。
#        本カテゴリは dmi 設定と Agent/Skill 委譲の論理整合性を検証する。
# =============================================================================
echo "--- Cat A: disable-model-invocation 契約 ---"

# A-1: dmi=true のスキルは allowed-tools に Agent or Skill を含む、
#      OR 例外リスト（commit, ticket-move）に含まれる
DMI_EXCEPTION_LIST="commit ticket-move"

for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  dmi=$(extract_frontmatter_field "$skill_md" "disable-model-invocation")

  if [ "$dmi" = "true" ]; then
    fm_block=$(extract_frontmatter_block "$skill_md")
    has_agent_or_skill="false"
    if echo "$fm_block" | grep -qE '(Agent|Skill)'; then
      has_agent_or_skill="true"
    fi
    is_exception="false"
    for exc in $DMI_EXCEPTION_LIST; do
      if [ "$skill_slug" = "$exc" ]; then
        is_exception="true"
        break
      fi
    done

    result="false"
    if [ "$has_agent_or_skill" = "true" ] || [ "$is_exception" = "true" ]; then
      result="true"
    fi
    assert_true \
      "dmi=true スキル '$skill_slug' は Agent/Skill を持つか例外リストに含まれる" \
      "$result"
  fi
done

# A-2: dmi がないスキル（catchup, investigate, test）は agent: または Agent allowed-tools を持つ
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  dmi=$(extract_frontmatter_field "$skill_md" "disable-model-invocation")

  if [ -z "$dmi" ]; then
    fm_block=$(extract_frontmatter_block "$skill_md")
    has_agent_field="false"
    if [ -n "$(extract_frontmatter_field "$skill_md" "agent")" ]; then
      has_agent_field="true"
    fi
    has_agent_tool="false"
    if echo "$fm_block" | grep -qE 'Agent'; then
      has_agent_tool="true"
    fi

    result="false"
    if [ "$has_agent_field" = "true" ] || [ "$has_agent_tool" = "true" ]; then
      result="true"
    fi
    assert_true \
      "dmi なしスキル '$skill_slug' は agent: フィールドまたは Agent ツールを持つ" \
      "$result"
  fi
done

echo ""

# =============================================================================
# カテゴリ B: AskUserQuestion 非対話フォールバック契約
# 差分: 既存テストにはこの検証なし。
#        allowed-tools に AskUserQuestion を含むスキル、
#        および本文で AskUserQuestion を言及するスキルの Non-interactive 記述を検証。
# =============================================================================
echo "--- Cat B: AskUserQuestion 非対話フォールバック契約 ---"

# B-1: allowed-tools に AskUserQuestion を含むスキルを動的検出
cat_b1_skills=()
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  fm_block=$(extract_frontmatter_block "$skill_md")
  if echo "$fm_block" | grep -qE 'AskUserQuestion'; then
    cat_b1_skills+=("$skill_slug")
    assert_file_contains \
      "$skill_slug: allowed-tools に AskUserQuestion あり → Non-interactive 記述あり" \
      "$skill_md" \
      "Non-interactive"
  fi
done

# B-2: 本文で AskUserQuestion を使用指示するスキル（B-1 対象外）を動的検出
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  # B-1 で既にカバー済みのスキルはスキップ
  skip="false"
  for covered in "${cat_b1_skills[@]}"; do
    if [ "$skill_slug" = "$covered" ]; then
      skip="true"
      break
    fi
  done
  [ "$skip" = "true" ] && continue

  body=$(awk 'BEGIN{depth=0} /^---[[:space:]]*$/{depth++;next} depth>=2{print}' "$skill_md")
  # AskUserQuestion をツールとして使用指示しているスキルのみ対象
  if echo "$body" | grep -qE '(Use.*AskUserQuestion|AskUserQuestion.*to ask|AskUserQuestion.*unavailable|AskUserQuestion.*fallback)'; then
    assert_file_contains \
      "$skill_slug: 本文に AskUserQuestion 使用指示 → Non-interactive 記述あり" \
      "$skill_md" \
      "Non-interactive"
  fi
done

echo ""

# =============================================================================
# カテゴリ C: Skill 委譲グラフ整合性
# 差分: 既存 Cat 4 は特定ファイル固定の cross-reference。
#        本カテゴリは Skill allowed-tools 持ちスキルの /呼び出しを動的に検出し、
#        参照先 SKILL.md の存在を検証する。
# =============================================================================
echo "--- Cat C: Skill 委譲グラフ整合性 ---"

# Skill allowed-tools を持つスキルの本文からバッククォート囲みの `/skillname` を抽出
# パターン: `/commit` や `/audit` のようにバッククォートで囲まれたスキル呼び出し
# /Error, /Phase 等の非スキル参照や .backlog/active/ 等のパス内スラッシュは除外
cat_c_count=0
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  fm_block=$(extract_frontmatter_block "$skill_md")
  if ! echo "$fm_block" | grep -qE '\bSkill\b'; then
    continue
  fi

  # 本文からバッククォート囲みの /name パターンを抽出（実際のスキル委譲参照のみ）
  body=$(awk 'BEGIN{depth=0} /^---[[:space:]]*$/{depth++;next} depth>=2{print}' "$skill_md")
  # shellcheck disable=SC2207
  delegated_skills=($(echo "$body" | grep -oE '`/[a-z][a-z0-9-]+`' | sed -E 's/`\///;s/`//' | sort -u))

  if [ ${#delegated_skills[@]} -eq 0 ]; then
    continue
  fi

  for target in "${delegated_skills[@]}"; do
    # 自己参照は除外（スキル自身への言及）
    if [ "$target" = "$skill_slug" ]; then
      continue
    fi
    target_md="$REPO_DIR/skills/$target/SKILL.md"
    result="false"
    if [ -f "$target_md" ]; then
      result="true"
    fi
    assert_true \
      "$skill_slug が委譲する /$target の SKILL.md が存在する" \
      "$result"
    cat_c_count=$((cat_c_count + 1))
  done
done

# ガードアサーション: 最低1件のスキル委譲がテストされたこと
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$cat_c_count" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} Category C: at least 1 skill delegation verified ($cat_c_count total)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Category C: no skill delegations found to verify (expected >= 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# カテゴリ D: Agent 委譲整合性
# 差分: 既存 Cat 7 は agent→skill 方向の到達可能性検証。
#        本カテゴリは skill→agent 方向の検証（agent: フィールドおよび本文参照）。
# =============================================================================
echo "--- Cat D: Agent 委譲整合性 ---"

# D-1: agent: フィールドの値に対応する agents/{name}.md が存在
cat_d1_count=0
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  agent_field=$(extract_frontmatter_field "$skill_md" "agent")
  if [ -n "$agent_field" ]; then
    agent_md="$REPO_DIR/agents/$agent_field.md"
    result="false"
    if [ -f "$agent_md" ]; then
      result="true"
    fi
    assert_true \
      "$skill_slug の agent: '$agent_field' に対応する agents/$agent_field.md が存在" \
      "$result"
    cat_d1_count=$((cat_d1_count + 1))
  fi
done

# ガードアサーション: 最低1件の agent: フィールドがテストされたこと
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$cat_d1_count" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} Category D-1: at least 1 agent field verified ($cat_d1_count total)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Category D-1: no agent fields found to verify (expected >= 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# D-2: Agent を allowed-tools に持つスキルの本文で参照されるエージェント名
# agents/*.md から動的にエージェント名を取得
KNOWN_AGENTS=""
for agent_file in "$REPO_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_basename=$(basename "$agent_file" .md)
  KNOWN_AGENTS="$KNOWN_AGENTS $agent_basename"
done
KNOWN_AGENTS="${KNOWN_AGENTS# }" # 先頭スペースを除去

cat_d2_count=0
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  fm_block=$(extract_frontmatter_block "$skill_md")
  if ! echo "$fm_block" | grep -qE '\bAgent\b'; then
    continue
  fi

  body=$(awk 'BEGIN{depth=0} /^---[[:space:]]*$/{depth++;next} depth>=2{print}' "$skill_md")

  for agent_name in $KNOWN_AGENTS; do
    if echo "$body" | grep -qF "$agent_name"; then
      agent_md="$REPO_DIR/agents/$agent_name.md"
      result="false"
      if [ -f "$agent_md" ]; then
        result="true"
      fi
      assert_true \
        "$skill_slug が本文参照するエージェント '$agent_name' の agents/$agent_name.md が存在" \
        "$result"
      cat_d2_count=$((cat_d2_count + 1))
    fi
  done
done

# ガードアサーション: 最低1件のエージェント本文参照がテストされたこと
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$cat_d2_count" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} Category D-2: at least 1 agent body reference verified ($cat_d2_count total)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Category D-2: no agent body references found to verify (expected >= 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# カテゴリ E: argument-hint と $ARGUMENTS の整合性
# 差分: 既存テストにはこの検証なし。
#        argument-hint を持つスキルの本文に $ARGUMENTS が含まれることを検証。
# =============================================================================
echo "--- Cat E: argument-hint と \$ARGUMENTS の整合性 ---"

for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  arg_hint=$(extract_frontmatter_field "$skill_md" "argument-hint")
  if [ -n "$arg_hint" ]; then
    assert_file_contains \
      "$skill_slug: argument-hint あり → 本文に \$ARGUMENTS が含まれる" \
      "$skill_md" \
      '\$ARGUMENTS'
  fi
done

echo ""

# =============================================================================
# カテゴリ F: context:fork と agent: の共起契約
# 差分: 既存テストにはこの検証なし。
#        context:fork を持つスキルは agent: も持ち、逆もまた然り。
# =============================================================================
echo "--- Cat F: context:fork と agent: の共起契約 ---"

for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  context_val=$(extract_frontmatter_field "$skill_md" "context")
  agent_val=$(extract_frontmatter_field "$skill_md" "agent")

  # F-1: context:fork → agent: あり
  if [ "$context_val" = "fork" ]; then
    result="false"
    if [ -n "$agent_val" ]; then
      result="true"
    fi
    assert_true \
      "$skill_slug: context:fork を持つ → agent: フィールドも持つ" \
      "$result"
  fi

  # F-2: agent: あり → context:fork あり
  if [ -n "$agent_val" ]; then
    result="false"
    if [ "$context_val" = "fork" ]; then
      result="true"
    fi
    assert_true \
      "$skill_slug: agent: を持つ → context:fork も持つ" \
      "$result"
  fi
done

echo ""

# =============================================================================
# カテゴリ G: /audit → /impl Status 契約の型整合性
# 差分: 既存 Cat 10 は agent の Status 語彙検証。
#        本カテゴリは skill 間の出力-入力の型整合性（3値: PASS, PASS_WITH_CONCERNS, FAIL）。
# =============================================================================
echo "--- Cat G: /audit → /impl Status 契約の型整合性 ---"

# G-1: audit SKILL.md に PASS_WITH_CONCERNS が含まれる
assert_file_contains \
  "audit SKILL.md に PASS_WITH_CONCERNS が含まれる" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "PASS_WITH_CONCERNS"

# G-2: impl SKILL.md に PASS_WITH_CONCERNS が含まれる
assert_file_contains \
  "impl SKILL.md に PASS_WITH_CONCERNS が含まれる" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "PASS_WITH_CONCERNS"

# G-3: audit SKILL.md に PASS, PASS_WITH_CONCERNS, FAIL の3値が全て含まれる
TESTS_TOTAL=$((TESTS_TOTAL + 1))
audit_md="$REPO_DIR/skills/audit/SKILL.md"
has_pass=$(grep -cE '\bPASS\b' "$audit_md" || true)
has_pwc=$(grep -cE 'PASS_WITH_CONCERNS' "$audit_md" || true)
has_fail=$(grep -cE '\bFAIL\b' "$audit_md" || true)
if [ "$has_pass" -gt 0 ] && [ "$has_pwc" -gt 0 ] && [ "$has_fail" -gt 0 ]; then
  echo -e "  ${GREEN}PASS${NC} audit SKILL.md に PASS, PASS_WITH_CONCERNS, FAIL の3値全てが含まれる"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} audit SKILL.md に3値が不足 (PASS=$has_pass, PWC=$has_pwc, FAIL=$has_fail)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# カテゴリ H: hook→skill データフロー整合性
# 差分: 既存テストにはこの検証なし。
#        pre-compact-save.sh が書き出すフィールドを catchup SKILL.md が読み取ること。
# =============================================================================
echo "--- Cat H: hook→skill データフロー整合性 ---"

HOOK_FILE="$REPO_DIR/hooks/pre-compact-save.sh"
CATCHUP_FILE="$REPO_DIR/skills/catchup/SKILL.md"

DATA_FIELDS="latest_eval_round latest_audit_round last_round_outcome in_progress_phase"

# H-1: pre-compact-save.sh に4フィールド全てが含まれる
for field in $DATA_FIELDS; do
  assert_file_contains \
    "pre-compact-save.sh に '$field' が含まれる" \
    "$HOOK_FILE" \
    "$field"
done

# H-2: catchup SKILL.md に4フィールド全てが含まれる
for field in $DATA_FIELDS; do
  assert_file_contains \
    "catchup SKILL.md に '$field' が含まれる" \
    "$CATCHUP_FILE" \
    "$field"
done

echo ""

# --- サマリー ---
print_summary
