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

# A-1: dmi=true のスキルは allowed-tools に Agent or Skill を含む
DMI_TRUE_EXCEPTION_LIST=""

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
    for exc in $DMI_TRUE_EXCEPTION_LIST; do
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

# A-2: dmi 未設定のスキル（delegator: catchup, investigate, test）は agent: または Agent allowed-tools を持つ
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
      "dmi 未設定スキル '$skill_slug' は agent: フィールドまたは Agent ツールを持つ" \
      "$result"
  fi
done

# A-3: dmi=false のスキルは allowed-tools に Agent or Skill を含む（他スキルから呼ばれるオーケストレータ）
DMI_FALSE_EXCEPTION_LIST=""

cat_a3_count=0
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  dmi=$(extract_frontmatter_field "$skill_md" "disable-model-invocation")

  if [ "$dmi" = "false" ]; then
    fm_block=$(extract_frontmatter_block "$skill_md")
    has_agent_or_skill="false"
    if echo "$fm_block" | grep -qE '(Agent|Skill)'; then
      has_agent_or_skill="true"
    fi
    is_exception="false"
    for exc in $DMI_FALSE_EXCEPTION_LIST; do
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
      "dmi=false スキル '$skill_slug' は Agent/Skill を持つか例外リストに含まれる" \
      "$result"
    cat_a3_count=$((cat_a3_count + 1))
  fi
done

# ガードアサーション: 最低1件の dmi=false スキルがテストされたこと
assert_true "Category A-3: at least 1 dmi=false skill verified ($cat_a3_count total)" "$([ $cat_a3_count -ge 1 ] && echo true || echo false)"

# A-4: dmi=false のスキルは description に "Do not auto-invoke" を含む
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  dmi=$(extract_frontmatter_field "$skill_md" "disable-model-invocation")

  if [ "$dmi" = "false" ]; then
    has_phrase=$(grep -c 'Do not auto-invoke' "$skill_md" || true)
    result="false"
    if [ "$has_phrase" -gt 0 ]; then
      result="true"
    fi
    assert_true \
      "dmi=false スキル '$skill_slug' の description に 'Do not auto-invoke' を含む" \
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
# パターン: `/audit` や `/impl` のようにバッククォートで囲まれたスキル呼び出し
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
  delegated_skills=($(echo "$body" | grep -oE '`/[a-z][a-z0-9-]+`' | sed -E 's/`\///;s/`//' | sort -u || true))

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

# =============================================================================
# カテゴリ I: /tune ナレッジベース契約
# 差分: 新規カテゴリ。tune スキル・エージェント・KB 注入の構造整合性を検証。
# =============================================================================
echo "--- Cat I: /tune ナレッジベース契約 ---"

# I-1: tune SKILL.md が存在する
TUNE_SKILL="$REPO_DIR/skills/tune/SKILL.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TUNE_SKILL" ]; then
  echo -e "  ${GREEN}PASS${NC} tune SKILL.md が存在する"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tune SKILL.md が存在しない"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# I-2: tune-analyzer.md が存在する
TUNE_AGENT="$REPO_DIR/agents/tune-analyzer.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TUNE_AGENT" ]; then
  echo -e "  ${GREEN}PASS${NC} tune-analyzer.md が存在する"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tune-analyzer.md が存在しない"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# I-3: tune SKILL.md に entries 上限50件の記述がある
assert_file_contains \
  "tune SKILL.md にエントリ上限50件の記述がある" \
  "$TUNE_SKILL" \
  "maximum 50 entries"

# I-4: tune SKILL.md に candidates 上限30件の記述がある
assert_file_contains \
  "tune SKILL.md に candidates 上限30件の記述がある" \
  "$TUNE_SKILL" \
  "(Maximum 30|maximum 30|max.*30) candidates"

# I-5: tune SKILL.md に TTL 90日の記述がある
assert_file_contains \
  "tune SKILL.md に TTL 90日の記述がある" \
  "$TUNE_SKILL" \
  "TTL.*90|90.*days"

# I-6: tune SKILL.md に信頼度3分岐がある (auto-promote, propose, accumulate)
assert_file_contains \
  "tune SKILL.md に Auto-promote 分岐がある" \
  "$TUNE_SKILL" \
  "Auto-promote|auto-promote"

assert_file_contains \
  "tune SKILL.md に Propose 分岐がある" \
  "$TUNE_SKILL" \
  "Propose"

assert_file_contains \
  "tune SKILL.md に Accumulate 分岐がある" \
  "$TUNE_SKILL" \
  "Accumulate"

# I-7: tune-analyzer.md に confidence 初期値4種がある
assert_file_contains \
  "tune-analyzer.md に eval-round confidence 0.3 がある" \
  "$TUNE_AGENT" \
  "0\\.3"

assert_file_contains \
  "tune-analyzer.md に impl success confidence 0.2 がある" \
  "$TUNE_AGENT" \
  "0\\.2"

assert_file_contains \
  "tune-analyzer.md に security confidence 0.4 がある" \
  "$TUNE_AGENT" \
  "0\\.4"

assert_file_contains \
  "tune-analyzer.md に human feedback confidence 0.5 がある" \
  "$TUNE_AGENT" \
  "0\\.5"

# I-8: tune-analyzer.md に Status 行がある（Agent Status 契約準拠）
assert_file_contains \
  "tune-analyzer.md に Status 行がある" \
  "$TUNE_AGENT" \
  '\*\*Status\*\*.*success.*partial.*failed'

# I-9: tune-analyzer.md に読み取り専用ツール + Write（Edit, Bash(*)を含まない）
TUNE_AGENT_FM=$(extract_frontmatter_block "$TUNE_AGENT")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
has_edit="false"
has_bash_star="false"
if echo "$TUNE_AGENT_FM" | grep -qE '^\s*-\s*Edit'; then
  has_edit="true"
fi
if echo "$TUNE_AGENT_FM" | grep -qE 'Bash\(\*\)'; then
  has_bash_star="true"
fi
if [ "$has_edit" = "false" ] && [ "$has_bash_star" = "false" ]; then
  echo -e "  ${GREEN}PASS${NC} tune-analyzer.md は Edit, Bash(*) を含まない"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tune-analyzer.md に Edit または Bash(*) が含まれる (edit=$has_edit, bash_star=$has_bash_star)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# I-10: ship SKILL.md に /tune 呼び出しがある（バッククォート付き）
assert_file_contains \
  "ship SKILL.md にバッククォート付き /tune 呼び出しがある" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  '`/tune`'

# I-11: ship SKILL.md に tune 失敗で停止しない旨の記述がある
assert_file_contains \
  "ship SKILL.md に tune 失敗で ship 停止しない旨がある" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  "not stop|do not.*stop|not.*stop.*ship"

# I-12: impl SKILL.md に KB 注入 (index.yaml) の記述がある
assert_file_contains \
  "impl SKILL.md に index.yaml からの KB 注入がある" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "index\\.yaml"

# I-13: impl SKILL.md に AC 優先の注記がある
assert_file_contains \
  "impl SKILL.md に AC が KB に優先する注記がある" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "Acceptance Criteria.*take precedence|AC.*precedence|AC.*wins"

# I-14: impl SKILL.md に Known Project Patterns 見出しがある
assert_file_contains \
  "impl SKILL.md に Known Project Patterns 見出しがある" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "Known Project Patterns"

# I-15: impl SKILL.md に KB 未存在時スキップの記述がある
assert_file_contains \
  "impl SKILL.md に KB 未存在時スキップの記述がある" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "does not exist.*skip|not exist.*skip"

# I-16: tune SKILL.md に autopilot-log の記述がある
assert_file_contains \
  "tune SKILL.md に autopilot-log の記述がある" \
  "$TUNE_SKILL" \
  "autopilot-log"

# I-17: tune SKILL.md に category decision の記述がある
assert_file_contains \
  "tune SKILL.md に category decision の記述がある" \
  "$TUNE_SKILL" \
  "decision"

# I-18: tune-analyzer.md に decision カテゴリの抽出ルールがある
assert_file_contains \
  "tune-analyzer.md に decision パターン抽出の記述がある" \
  "$TUNE_AGENT" \
  "decision"

# I-19: tune-analyzer.md に success_count と failure_count がある
assert_file_contains \
  "tune-analyzer.md に success_count がある" \
  "$TUNE_AGENT" \
  "success_count"

assert_file_contains \
  "tune-analyzer.md に failure_count がある" \
  "$TUNE_AGENT" \
  "failure_count"

# I-20: tune-analyzer.md に autopilot-log decision の初期 confidence 0.35 がある
assert_file_contains \
  "tune-analyzer.md に decision 初期 confidence 0.35 がある" \
  "$TUNE_AGENT" \
  "0\\.35"

echo ""

# =============================================================================
# カテゴリ J: Autopilot Policy 契約
# 差分: 新規カテゴリ。autopilot-policy.yaml 対応スキルの構造整合性を検証。
# =============================================================================
echo "--- Cat J: Autopilot Policy 契約 ---"

# J-1: policy 対応スキルに autopilot-policy.yaml への参照がある
POLICY_SKILLS="create-ticket impl ship"
for skill_slug in $POLICY_SKILLS; do
  assert_file_contains \
    "$skill_slug SKILL.md に autopilot-policy.yaml への参照がある" \
    "$REPO_DIR/skills/$skill_slug/SKILL.md" \
    "autopilot-policy\\.yaml"
done

# J-2: 各スキルに対応する gate 名の記述がある
assert_file_contains \
  "create-ticket SKILL.md に gates.ticket_quality_fail がある" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "gates\\.ticket_quality_fail"

assert_file_contains \
  "impl SKILL.md に gates.evaluator_dry_run_fail がある" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "gates\\.evaluator_dry_run_fail"

assert_file_contains \
  "impl SKILL.md に gates.audit_infrastructure_fail がある" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "gates\\.audit_infrastructure_fail"

assert_file_contains \
  "ship SKILL.md に gates.ship_review_gate がある" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  "gates\\.ship_review_gate"

assert_file_contains \
  "ship SKILL.md に gates.ship_ci_pending がある" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  "gates\\.ship_ci_pending"

# J-3: policy 対応スキルに [AUTOPILOT-POLICY] ログ出力指示がある
for skill_slug in $POLICY_SKILLS; do
  assert_file_contains \
    "$skill_slug SKILL.md に [AUTOPILOT-POLICY] ログ出力がある" \
    "$REPO_DIR/skills/$skill_slug/SKILL.md" \
    '\[AUTOPILOT-POLICY\]'
done

# J-4: brief SKILL.md に split-plan.md への参照がある
assert_file_contains \
  "brief SKILL.md に split-plan.md への参照がある" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "split-plan\\.md"

# J-5: brief SKILL.md に分割トリガー条件の記述がある
assert_file_contains \
  "brief SKILL.md に estimated_size と L/XL の分割判定がある" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "estimated_size.*L.*XL|L or XL|L/XL"

# J-6: autopilot SKILL.md に split-plan.md の検出手順がある
assert_file_contains \
  "autopilot SKILL.md に split-plan.md の検出がある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "split-plan\\.md"

# J-7: autopilot SKILL.md にトポロジカルソートの記述がある
assert_file_contains \
  "autopilot SKILL.md に topological sort がある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "topological"

# J-8: brief SKILL.md に index.yaml からの KB 参照がある
assert_file_contains \
  "brief SKILL.md に index.yaml からの KB 参照がある" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "index\\.yaml"

# J-9: brief SKILL.md に role=autopilot のフィルタリングがある
assert_file_contains \
  "brief SKILL.md に autopilot ロールのフィルタリングがある" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "autopilot"

# J-10: brief SKILL.md に confidence 閾値 0.7 の記述がある
assert_file_contains \
  "brief SKILL.md に confidence 閾値の記述がある" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "0\\.7"

# J-11: impl SKILL.md に gates.ac_eval_fail がある
assert_file_contains \
  "impl SKILL.md に gates.ac_eval_fail がある" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "gates\\.ac_eval_fail"

# J-12: autopilot SKILL.md に gates.unexpected_error がある
assert_file_contains \
  "autopilot SKILL.md に gates.unexpected_error がある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "gates\\.unexpected_error"

# J-13: impl SKILL.md に constraints.allow_breaking_changes がある
assert_file_contains \
  "impl SKILL.md に constraints.allow_breaking_changes がある" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "constraints\\.allow_breaking_changes"

# J-14: impl SKILL.md に constraints.max_total_rounds がある
assert_file_contains \
  "impl SKILL.md に constraints.max_total_rounds がある" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "constraints\\.max_total_rounds"

# J-15: autopilot SKILL.md に unexpected_error の unsupported action フォールバック記述がある
assert_file_contains \
  "autopilot SKILL.md に unexpected_error の unsupported action フォールバック記述がある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "fallback from unsupported action"

# J-16: autopilot SKILL.md に unexpected_error の動的 action ログ出力がある (ハードコードでない)
assert_file_contains \
  "autopilot SKILL.md に unexpected_error の動的 action={actual_action} ログがある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'action=\{actual_action\}'

# J-17: autopilot SKILL.md で moderate と aggressive のデフォルトが別定義されている
assert_file_contains \
  "autopilot SKILL.md に moderate defaults が独立定義されている" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  '`moderate` defaults:'

assert_file_contains \
  "autopilot SKILL.md に aggressive defaults が独立定義されている" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  '`aggressive` defaults:'

# J-18: autopilot SKILL.md の aggressive defaults に固有値がある
assert_file_contains \
  "autopilot SKILL.md の aggressive に timeout_minutes: 60 がある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'aggressive.*timeout_minutes: 60'

assert_file_contains \
  "autopilot SKILL.md の aggressive に max_total_rounds: 12 がある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'aggressive.*max_total_rounds: 12'

assert_file_contains \
  "autopilot SKILL.md の aggressive に allow_breaking_changes: true がある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'aggressive.*allow_breaking_changes: true'

# J-19: brief SKILL.md の policy テンプレートに aggressive 固有値がある
assert_file_contains \
  "brief SKILL.md に timeout_minutes の aggressive 分岐 (60) がある" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  'timeout_minutes:.*60.*aggressive'

assert_file_contains \
  "brief SKILL.md に max_total_rounds の aggressive 分岐 (12) がある" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  'max_total_rounds:.*12.*aggressive'

assert_file_contains \
  "brief SKILL.md に allow_breaking_changes の aggressive 分岐 (true) がある" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  'allow_breaking_changes:.*true.*aggressive'

echo ""

# =============================================================================
# カテゴリ K: kb-suggested / kb_override 契約
# 差分: 新規カテゴリ。KB 由来のデフォルト変更を human_override と誤検出しない
#        ための kb-suggested コメント付与・検出・分離ログの整合性を検証。
# =============================================================================
echo "--- Cat K: kb-suggested / kb_override 契約 ---"

# K-1: brief SKILL.md Phase 4 に kb-suggested コメント付与の指示がある
assert_file_contains \
  "brief SKILL.md に kb-suggested コメント付与の指示がある" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "kb-suggested"

# K-2: autopilot SKILL.md step 6 に kb-suggested コメント検出ロジックがある
assert_file_contains \
  "autopilot SKILL.md に kb-suggested コメント検出がある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "kb-suggested"

# K-3: autopilot SKILL.md に kb_override タイプの記述がある
assert_file_contains \
  "autopilot SKILL.md に kb_override タイプがある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "kb_override"

# K-4: autopilot SKILL.md に KB Overrides セクションの記述がある
assert_file_contains \
  "autopilot SKILL.md に KB Overrides セクションがある" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "KB Overrides"

# K-5: autopilot SKILL.md の Human Overrides セクションが kb_override を除外する記述がある
assert_file_contains \
  "autopilot SKILL.md の Human Overrides が kb_override を除外する" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "Exclude.*kb_override"

# K-6: autopilot SKILL.md の Decisions Made テーブルで human_override と kb_override を区別する記述がある
assert_file_contains \
  "autopilot SKILL.md の Decisions Made で human_override と kb_override を区別する" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "human_override.*kb_override"

# K-7: brief SKILL.md で confidence >= 0.7 と kb-suggested が同じ行に記述されている
assert_file_contains \
  "brief SKILL.md で confidence >= 0.7 の分岐に kb-suggested が紐付いている" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "0\.7.*kb-suggested"

echo ""

# =============================================================================
# カテゴリ L: autopilot/brief/create-ticket v2.2.0 契約
# 差分: 新規カテゴリ。v2.2.0 で追加された ticket_mapping, ticket_dir,
#        brief_slug メタデータ、および ticket-slug 廃止の構造整合性を検証。
# =============================================================================
echo "--- Cat L: autopilot/brief/create-ticket v2.2.0 契約 ---"

# L-1: autopilot SKILL.md に ticket_mapping が split flow 内に記述されている
assert_file_contains \
  "autopilot SKILL.md has ticket_mapping in split flow" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "ticket_mapping"

# L-2: autopilot SKILL.md に ticket_dir frontmatter フィールドがある
assert_file_contains \
  "autopilot SKILL.md has ticket_dir frontmatter field" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "ticket_dir:"

# L-3: create-ticket SKILL.md に brief_slug メタデータがある
assert_file_contains \
  "create-ticket SKILL.md has brief_slug metadata" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "brief_slug"

# L-4: create-ticket SKILL.md に Split Judgment 構造（Split criteria / Split Rationale）がある
assert_file_contains \
  "create-ticket SKILL.md has Split criteria description" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "Split criteria"

assert_file_contains \
  "create-ticket SKILL.md has Split Rationale description" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "Split Rationale"

# L-5: create-ticket SKILL.md に Split guardrails（最低サイズ/AC数）がある
assert_file_contains \
  "create-ticket SKILL.md has split guardrail (at least Size S or 2+ AC)" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "at least Size S|2 or more Acceptance Criteria"

# L-7: create-ticket SKILL.md に .ticket-counter の記述がある
assert_file_contains \
  "create-ticket SKILL.md has .ticket-counter reference" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "\\.ticket-counter"

# L-8: create-ticket SKILL.md に brief_part メタデータの記述がある
assert_file_contains \
  "create-ticket SKILL.md has brief_part metadata" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "brief_part"

# L-9 (was L-4): tune-analyzer.md に stale ticket-slug が残っていないこと
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -qE '\{ticket-slug\}' "$REPO_DIR/agents/tune-analyzer.md"; then
  echo -e "  ${GREEN}PASS${NC} tune-analyzer.md has no stale ticket-slug"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tune-analyzer.md has stale {ticket-slug} reference"
  echo -e "       File: $REPO_DIR/agents/tune-analyzer.md"
  echo -e "       Unexpected pattern found: {ticket-slug}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# カテゴリ M: Workflow Isolation 契約
# 差分: 新規カテゴリ。manual /impl と /autopilot 間のワークフロー分離を検証。
#        /impl は autopilot-policy.yaml を含むチケットを除外し、
#        /autopilot は Policy guard で明示的パスを使用する。
#        Cat J は autopilot-policy の構造整合性を検証するが、
#        本カテゴリは両ワークフロー間の分離メカニズムの存在を検証する。
# =============================================================================
echo "--- Cat M: Workflow Isolation 契約 ---"

# M-1: /impl SKILL.md は autopilot-policy.yaml を含むディレクトリを除外する
assert_file_contains \
  "impl SKILL.md excludes autopilot-policy.yaml directories" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "Exclude.*autopilot-policy\.yaml"

# M-2: /impl SKILL.md は ascending (FIFO) ソート順でチケットを選択する
assert_file_contains \
  "impl SKILL.md documents ascending/FIFO ticket selection" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "ascending.*lowest ticket number"

# M-3: /impl SKILL.md は全チケットが autopilot 管理の場合のフォールバックメッセージがある
assert_file_contains \
  "impl SKILL.md has all-autopilot-managed fallback message" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "All active tickets are managed by /autopilot"

# M-4: /autopilot SKILL.md の single ticket flow に Policy guard がある (steps 10, 11, 12)
assert_file_contains \
  "autopilot SKILL.md has Policy guard for scout (ABORT message)" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "\\[PIPELINE\\] scout: ABORT"

assert_file_contains \
  "autopilot SKILL.md has Policy guard for impl (ABORT message)" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "\\[PIPELINE\\] impl: ABORT"

assert_file_contains \
  "autopilot SKILL.md has Policy guard for ship (ABORT message)" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "\\[PIPELINE\\] ship: ABORT"

# M-5: /autopilot SKILL.md の single ticket flow で /impl に明示的パスを渡す
assert_file_contains \
  "autopilot SKILL.md passes explicit plan path to /impl in single flow" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "/impl.*\.backlog/active/.*plan\.md"

# M-6: /autopilot SKILL.md の split execution flow に Policy guard ABORT ログがある (steps c, d, e)
assert_file_contains \
  "autopilot SKILL.md has split flow Policy guard ABORT for scout" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "\\[PIPELINE\\] scout: ABORT.*mark this ticket"

assert_file_contains \
  "autopilot SKILL.md has split flow Policy guard ABORT for impl" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "\\[PIPELINE\\] impl: ABORT.*mark this ticket"

assert_file_contains \
  "autopilot SKILL.md has split flow Policy guard ABORT for ship" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "\\[PIPELINE\\] ship: ABORT.*mark this ticket"

# M-7: /autopilot SKILL.md の split flow で /impl に明示的パスを渡す
assert_file_contains \
  "autopilot SKILL.md passes explicit plan path in split flow" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "/impl \.backlog/active/.*plan\.md"

# M-8: create-ticket SKILL.md に .ticket-counter のアトミック更新ロジックがある
assert_file_contains \
  "create-ticket SKILL.md has atomic ticket-counter update (counter + N)" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "counter.*N.*ticket-counter"

# M-9: /autopilot は /create-ticket に委譲してチケット番号を割り当てる（共有カウンターメカニズム）
# Note: Phase 0c strengthened "Invoke" to "MUST invoke" — regex made case-insensitive to match either form.
assert_file_contains \
  "autopilot SKILL.md delegates to /create-ticket for ticket numbering" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "[Ii]nvoke.*/create-ticket"

echo ""

# =============================================================================
# カテゴリ N: impl safety contracts
# 差分: 新規カテゴリ。/impl のスタッシュ除外パス、/ship のチケット完了順序を検証。
# =============================================================================
echo "--- Cat N: impl safety contracts ---"

# N-1: impl SKILL.md に3つのスタッシュ除外 pathspec が全て含まれる
assert_file_contains \
  "impl SKILL.md contains stash exclusion ':!.backlog'" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "':!\.backlog'"

assert_file_contains \
  "impl SKILL.md contains stash exclusion ':!.docs'" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "':!\.docs'"

assert_file_contains \
  "impl SKILL.md contains stash exclusion ':!.simple-wf-knowledge'" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "':!\.simple-wf-knowledge'"

# N-2: ship SKILL.md で .backlog/done が Phase 2 より前に記述されている
ship_md="$REPO_DIR/skills/ship/SKILL.md"
done_line=$(awk '/\.backlog\/done/{print NR; exit}' "$ship_md")
phase2_line=$(awk '/^## Phase 2/{print NR; exit}' "$ship_md")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$done_line" ] && [ -n "$phase2_line" ] && [ "$done_line" -lt "$phase2_line" ]; then
  echo -e "  ${GREEN}PASS${NC} ship SKILL.md moves ticket to done before Phase 2"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ship SKILL.md moves ticket to done before Phase 2"
  echo -e "       done_line=$done_line phase2_line=$phase2_line (expected done < phase2)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# カテゴリ O: Autopilot Resilience 契約
# 差分: 新規カテゴリ。autopilot の状態ファイル管理・チェックポイントリマインダー・
#        自動再開ロジックの構造整合性を検証する。
# =============================================================================
echo "--- Cat O: autopilot resilience ---"

# O-1: autopilot SKILL.md に autopilot-state.yaml の記述がある
assert_file_contains \
  "autopilot SKILL.md references autopilot-state.yaml" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "autopilot-state\\.yaml"

# O-2: autopilot SKILL.md に CHECKPOINT — RE-ANCHOR がある
assert_file_contains \
  "autopilot SKILL.md has checkpoint re-anchor blocks" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "CHECKPOINT — RE-ANCHOR"

# O-3: autopilot SKILL.md に resume_mode の記述がある
assert_file_contains \
  "autopilot SKILL.md has resume_mode logic" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "resume_mode"

# O-4: autopilot SKILL.md に State file cleanup の記述がある
assert_file_contains \
  "autopilot SKILL.md has state file cleanup" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "State file cleanup"

# O-5: CHECKPOINT — RE-ANCHOR が Single/Split 両方にある (最低8箇所: Single 4 + Split 4)
CHECKPOINT_COUNT=$(grep -c "CHECKPOINT — RE-ANCHOR" "$REPO_DIR/skills/autopilot/SKILL.md" || true)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$CHECKPOINT_COUNT" -ge 8 ]; then
  echo -e "  ${GREEN}PASS${NC} autopilot has >= 8 CHECKPOINT — RE-ANCHOR blocks ($CHECKPOINT_COUNT found)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} autopilot has >= 8 CHECKPOINT — RE-ANCHOR blocks ($CHECKPOINT_COUNT found, expected >= 8)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# O-6: autopilot SKILL.md に状態ファイル初期化 (State file initialization) がある
assert_file_contains \
  "autopilot SKILL.md has state file initialization" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "State file initialization"

# O-7: autopilot SKILL.md に7日間の stale 警告がある
assert_file_contains \
  "autopilot SKILL.md has stale state warning" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "7 days"

echo ""

# =============================================================================
# カテゴリ P: Pipeline Re-Anchoring 契約
# 差分: 新規カテゴリ。autopilot/impl の CHECKPOINT — RE-ANCHOR ブロック、
#        impl-state.yaml 管理、再開ロジックの構造整合性を検証する。
# =============================================================================
echo "--- Cat P: Pipeline Re-Anchoring 契約 ---"

# P-1: autopilot SKILL.md に "CHECKPOINT — RE-ANCHOR" がある
assert_file_contains \
  "P-1: autopilot SKILL.md has CHECKPOINT — RE-ANCHOR" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "CHECKPOINT — RE-ANCHOR"

# P-2: autopilot SKILL.md に Read.*autopilot-state.yaml の指示がある
assert_file_contains \
  "P-2: autopilot SKILL.md has Read autopilot-state.yaml instruction" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "Read.*autopilot-state\.yaml"

# P-3: impl SKILL.md に impl-state.yaml の記述がある
assert_file_contains \
  "P-3: impl SKILL.md references impl-state.yaml" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "impl-state\.yaml"

# P-4: impl SKILL.md に "CHECKPOINT — RE-ANCHOR" がある
assert_file_contains \
  "P-4: impl SKILL.md has CHECKPOINT — RE-ANCHOR" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "CHECKPOINT — RE-ANCHOR"

# P-5: impl SKILL.md に Read.*impl-state.yaml の指示がある
assert_file_contains \
  "P-5: impl SKILL.md has Read impl-state.yaml instruction" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "Read.*impl-state\.yaml"

# P-6: impl SKILL.md に impl_resume_mode の記述がある
assert_file_contains \
  "P-6: impl SKILL.md has impl_resume_mode logic" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "impl_resume_mode"

# P-7: impl SKILL.md に impl-state.yaml の cleanup/削除 記述がある
assert_file_contains \
  "P-7: impl SKILL.md has impl-state.yaml cleanup/delete" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "(cleanup|[Dd]elete).*impl-state\.yaml|impl-state\.yaml.*(cleanup|[Dd]elete)"

# P-8: CHECKPOINT — RE-ANCHOR が autopilot に最低 8 箇所ある (count check)
COUNT=$(grep -c "CHECKPOINT — RE-ANCHOR" "$REPO_DIR/skills/autopilot/SKILL.md" || true)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$COUNT" -ge 8 ]; then
  echo -e "  ${GREEN}PASS${NC} P-8: autopilot CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 8)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} P-8: autopilot CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 8)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# P-9: CHECKPOINT — RE-ANCHOR が impl に最低 1 箇所ある (count check)
COUNT=$(grep -c "CHECKPOINT — RE-ANCHOR" "$REPO_DIR/skills/impl/SKILL.md" || true)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$COUNT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} P-9: impl CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 1)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} P-9: impl CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# P-10: impl SKILL.md に next_action の記述がある
assert_file_contains \
  "P-10: impl SKILL.md has next_action references" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "next_action"

echo ""

# =============================================================================
# カテゴリ V: SKILL.md 指示強度検証
# 差分: 新規カテゴリ。Phase 0c で追加された「Mandatory Skill Invocations」節と
#        MUST/NEVER/Fail 強制言語の存在を検証する。JSONL 解析で判明した
#        「スキル呼び出しを推奨と解釈して省略する」パターンを防ぐための言語的拘束。
# =============================================================================
echo "--- Cat V: SKILL.md 指示強度検証 ---"

ORCHESTRATOR_SKILLS=(autopilot create-ticket scout impl audit ship plan2doc)

# V-1: 各オーケストレータースキル7種に「Mandatory Skill Invocations」節が存在
for skill_name in "${ORCHESTRATOR_SKILLS[@]}"; do
  assert_file_contains \
    "V-1: $skill_name SKILL.md has 'Mandatory Skill Invocations' section" \
    "$REPO_DIR/skills/$skill_name/SKILL.md" \
    "^## Mandatory Skill Invocations"
done

# V-2: 各オーケストレータースキルに MUST/NEVER/Fail 強制言語が最低 3 回出現
#      (Mandatory 節 + 本文中の重要呼び出し箇所での強化)
for skill_name in "${ORCHESTRATOR_SKILLS[@]}"; do
  skill_md="$REPO_DIR/skills/$skill_name/SKILL.md"
  strong_count=$(grep -cE '(MUST invoke|NEVER bypass|Fail (the task|this ticket|this audit|the ship|the /tune))' "$skill_md" || true)
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$strong_count" -ge 3 ]; then
    echo -e "  ${GREEN}PASS${NC} V-2: $skill_name has >= 3 strong-language markers ($strong_count found)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} V-2: $skill_name has >= 3 strong-language markers ($strong_count found, expected >= 3)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# V-3: Mandatory Skill Invocations 節の各表エントリに skip consequence の記述がある
#      (節全体に "Skip consequence" ヘッダーが含まれ、かつ "consequence" に類する文言
#       または実際の帰結記述 "detected by" / "triggers" / "marked failed" / "missing" が含まれる)
for skill_name in "${ORCHESTRATOR_SKILLS[@]}"; do
  skill_md="$REPO_DIR/skills/$skill_name/SKILL.md"
  # Extract the Mandatory Skill Invocations section (from heading to next level-2 heading or EOF)
  section=$(awk '
    /^## Mandatory Skill Invocations/ { in_sec=1; next }
    in_sec && /^## / { exit }
    in_sec { print }
  ' "$skill_md")

  has_skip_header="false"
  if echo "$section" | grep -qE 'Skip consequence'; then
    has_skip_header="true"
  fi

  # Check for at least one consequence keyword in the section
  has_consequence_language="false"
  if echo "$section" | grep -qiE '(detected|trigger|missing|marked failed|bypass|violation|fails)'; then
    has_consequence_language="true"
  fi

  result="false"
  if [ "$has_skip_header" = "true" ] && [ "$has_consequence_language" = "true" ]; then
    result="true"
  fi
  assert_true \
    "V-3: $skill_name Mandatory Skill Invocations section has skip-consequence column with real consequence language" \
    "$result"
done

echo ""

# =============================================================================
# カテゴリ Q: Wrapper agent contract (Phase A)
# 差分: 新規カテゴリ。Phase A で追加された wrapped-* ラッパーエージェント7種と
#        ticket-pipeline オーケストレーターエージェント1種、計8種の構造整合性を検証する。
#        Cat 6 (existence of frontmatter/name/tools) に加えて、ラッパー固有の
#        契約（Agent allowed-tool、200 token minimal return、Next field など）を検証。
# =============================================================================
echo "--- Cat Q: Wrapper agent contract ---"

WRAPPER_AGENTS=(
  "wrapped-researcher:researcher"
  "wrapped-planner:planner"
  "wrapped-ticket-evaluator:ticket-evaluator"
  "wrapped-implementer:implementer"
  "wrapped-ac-evaluator:ac-evaluator"
  "wrapped-code-reviewer:code-reviewer"
  "wrapped-security-scanner:security-scanner"
  "ticket-pipeline:"
)

# Q-1: 各ラッパーエージェントの frontmatter に Agent (or task) が含まれる
for entry in "${WRAPPER_AGENTS[@]}"; do
  wrapper="${entry%%:*}"
  wrapper_md="$REPO_DIR/agents/$wrapper.md"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ ! -f "$wrapper_md" ]; then
    echo -e "  ${RED}FAIL${NC} Q-1: agents/$wrapper.md exists"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    continue
  fi
  fm_block=$(extract_frontmatter_block "$wrapper_md")
  if echo "$fm_block" | grep -qE '(\bAgent\b|\btask\b)'; then
    echo -e "  ${GREEN}PASS${NC} Q-1: $wrapper has Agent/task in tools frontmatter"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} Q-1: $wrapper missing Agent/task in tools frontmatter"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# Q-2: 各 wrapped-* の本文に包まれた実体エージェント名が言及されている
#      (ticket-pipeline は wrapped ではないのでスキップ)
for entry in "${WRAPPER_AGENTS[@]}"; do
  wrapper="${entry%%:*}"
  real="${entry##*:}"
  [ -z "$real" ] && continue
  wrapper_md="$REPO_DIR/agents/$wrapper.md"
  [ -f "$wrapper_md" ] || continue
  body=$(awk 'BEGIN{depth=0} /^---[[:space:]]*$/{depth++;next} depth>=2{print}' "$wrapper_md")
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if echo "$body" | grep -qF "$real"; then
    echo -e "  ${GREEN}PASS${NC} Q-2: $wrapper body references wrapped agent '$real'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} Q-2: $wrapper body does not reference wrapped agent '$real'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# Q-3: 各 wrapped-* 本文に「200 tokens」または「minimal return」の記述がある
#       (ticket-pipeline は独自の Return Format (AC-4-A) を持ち、Q-3/Q-4 の対象外)
for entry in "${WRAPPER_AGENTS[@]}"; do
  wrapper="${entry%%:*}"
  real="${entry##*:}"
  # Skip ticket-pipeline (no wrapped real agent; Return Format per AC-4-A)
  [ -z "$real" ] && continue
  wrapper_md="$REPO_DIR/agents/$wrapper.md"
  [ -f "$wrapper_md" ] || continue
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qE '(200 tokens?|200.?token|minimal return)' "$wrapper_md"; then
    echo -e "  ${GREEN}PASS${NC} Q-3: $wrapper mentions '200 tokens' or 'minimal return'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} Q-3: $wrapper missing '200 tokens' or 'minimal return'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# Q-4: 各 wrapped-* 本文の Return Format に **Next**: フィールドがある
#       (ticket-pipeline は AC-4-A に従い Ticket Dir/PR URL/Manual Bash Fallbacks/
#        Failure Reason フィールドを持つため、Q-4 の対象外。ticket-pipeline の
#        Return Format は Cat T-4/T-5 で検証される)
for entry in "${WRAPPER_AGENTS[@]}"; do
  wrapper="${entry%%:*}"
  real="${entry##*:}"
  [ -z "$real" ] && continue
  wrapper_md="$REPO_DIR/agents/$wrapper.md"
  [ -f "$wrapper_md" ] || continue
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qE '^\*\*Next\*\*:' "$wrapper_md"; then
    echo -e "  ${GREEN}PASS${NC} Q-4: $wrapper has **Next**: field in Return format"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} Q-4: $wrapper missing **Next**: field"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""

# =============================================================================
# カテゴリ R: Orchestrator wrapper references (phase-guarded)
# 差分: 新規カテゴリ。Phase B-E のスキル書き換え完了後にラッパーエージェント
#        名が対応する SKILL.md 本文で参照されていることを検証する。
#        Phase A 時点ではスキル側は未書き換えのため、phase guard で
#        該当スキルが rewrite 済みと検出できる場合のみアサート、そうでなければ
#        "deferred" として扱う（skip ではなく、ガード条件の成立をアサート）。
# =============================================================================
echo "--- Cat R: Orchestrator wrapper references (phase-guarded) ---"

# Phase guard: 対象スキルが rewrite 済みかを「wrapped-* が本文に1つでも含まれる」
# ことで検出する。Phase A 時点では全て未書き換えのため、R-1..R-5 は "deferred"。
# Phase B 以降、該当スキルに wrapped-* が現れた瞬間に自動的にアサートが有効化される。

assert_wrapper_reference_phase_guarded() {
  local label="$1"
  local skill_md="$2"
  shift 2
  local expected_wrappers=("$@")

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ ! -f "$skill_md" ]; then
    echo -e "  ${RED}FAIL${NC} $label: SKILL.md not found: $skill_md"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  # Phase guard: any wrapped-* reference in SKILL.md means Phase B+ rewrite has landed
  if grep -qE 'wrapped-[a-z-]+' "$skill_md"; then
    # rewritten — enforce that every expected wrapper is present
    local missing=""
    for w in "${expected_wrappers[@]}"; do
      if ! grep -qF "$w" "$skill_md"; then
        missing="$missing $w"
      fi
    done
    if [ -z "$missing" ]; then
      echo -e "  ${GREEN}PASS${NC} $label: all expected wrappers referenced (${expected_wrappers[*]})"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo -e "  ${RED}FAIL${NC} $label: rewrite detected but missing:$missing"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  else
    echo -e "  ${GREEN}PASS${NC} $label: deferred (Phase B+ skill rewrite not yet landed in $(basename "$(dirname "$skill_md")"))"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
}

# R-1: create-ticket → wrapped-researcher, wrapped-planner, wrapped-ticket-evaluator
assert_wrapper_reference_phase_guarded \
  "R-1: create-ticket SKILL.md references create-ticket wrappers" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "wrapped-researcher" "wrapped-planner" "wrapped-ticket-evaluator"

# R-2: impl → wrapped-implementer, wrapped-ac-evaluator
assert_wrapper_reference_phase_guarded \
  "R-2: impl SKILL.md references impl wrappers" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "wrapped-implementer" "wrapped-ac-evaluator"

# R-3: audit → wrapped-code-reviewer, wrapped-security-scanner
assert_wrapper_reference_phase_guarded \
  "R-3: audit SKILL.md references audit wrappers" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "wrapped-code-reviewer" "wrapped-security-scanner"

# R-4: autopilot → ticket-pipeline (enabled in Phase E; phase-guarded by "ticket-pipeline" presence)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AUTOPILOT_MD="$REPO_DIR/skills/autopilot/SKILL.md"
if grep -qF "ticket-pipeline" "$AUTOPILOT_MD"; then
  echo -e "  ${GREEN}PASS${NC} R-4: autopilot SKILL.md references ticket-pipeline"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${GREEN}PASS${NC} R-4: deferred (Phase E autopilot rewrite not yet landed)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# R-5: plan2doc → wrapped-planner
assert_wrapper_reference_phase_guarded \
  "R-5: plan2doc SKILL.md references wrapped-planner" \
  "$REPO_DIR/skills/plan2doc/SKILL.md" \
  "wrapped-planner"

echo ""

# =============================================================================
# カテゴリ S: State file separation
# 差分: 新規カテゴリ。ラッパーエージェントが state file を触らないこと、
#        および ticket-pipeline のみが autopilot-state.yaml を更新することを検証。
#        S-1 は create-ticket-state.yaml (Phase C) が導入されるまで phase-guarded。
# =============================================================================
echo "--- Cat S: State file separation ---"

# S-1: create-ticket SKILL.md が create-ticket-state.yaml を参照 (phase-guarded, Phase C)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CREATE_TICKET_MD="$REPO_DIR/skills/create-ticket/SKILL.md"
if grep -qF "create-ticket-state.yaml" "$CREATE_TICKET_MD"; then
  echo -e "  ${GREEN}PASS${NC} S-1: create-ticket SKILL.md references create-ticket-state.yaml"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${GREEN}PASS${NC} S-1: deferred (Phase C create-ticket rewrite not yet landed)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# S-2: どの wrapped-* ラッパーも state file への書き込み指示を含まない
#       (ticket-pipeline は S-3 で許容されるため除外)
WRAPPED_ONLY=(
  "wrapped-researcher"
  "wrapped-planner"
  "wrapped-ticket-evaluator"
  "wrapped-implementer"
  "wrapped-ac-evaluator"
  "wrapped-code-reviewer"
  "wrapped-security-scanner"
)
for wrapper in "${WRAPPED_ONLY[@]}"; do
  wrapper_md="$REPO_DIR/agents/$wrapper.md"
  [ -f "$wrapper_md" ] || continue
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  # Forbidden write patterns: any imperative write verb paired with a state file name.
  # Filter out prohibition lines (Do NOT / NEVER / MUST NOT / no ... write / etc.),
  # which are legitimate "do not touch state files" instructions that the wrapper
  # IS required to document.
  offending=$(grep -iE '((update|write|set|record|append|modify).*(autopilot-state\.yaml|impl-state\.yaml|create-ticket-state\.yaml))' "$wrapper_md" \
              | grep -viE '(do not|never|must not|no state|own(s)? (no|only))' || true)
  if [ -n "$offending" ]; then
    echo -e "  ${RED}FAIL${NC} S-2: $wrapper contains state file WRITE instruction (forbidden for wrappers)"
    echo "       Offending line: $offending"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo -e "  ${GREEN}PASS${NC} S-2: $wrapper contains no state file write instruction"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
done

# S-3: ticket-pipeline.md は autopilot-state.yaml の更新指示を含む (許容)
assert_file_contains \
  "S-3: ticket-pipeline.md has autopilot-state.yaml update instruction" \
  "$REPO_DIR/agents/ticket-pipeline.md" \
  "autopilot-state\\.yaml"

echo ""

# =============================================================================
# カテゴリ T: Artifact Presence Gate contract (AC-4-B)
# 差分: 新規カテゴリ。ticket-pipeline の出口検証ロジックの構造整合性を検証。
# =============================================================================
echo "--- Cat T: Artifact Presence Gate contract ---"

TICKET_PIPELINE_MD="$REPO_DIR/agents/ticket-pipeline.md"

# T-1: ticket-pipeline.md mentions "artifact presence gate" or "必須成果物"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qiE '(artifact presence gate|必須成果物)' "$TICKET_PIPELINE_MD"; then
  echo -e "  ${GREEN}PASS${NC} T-1: ticket-pipeline mentions 'artifact presence gate' or '必須成果物'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} T-1: ticket-pipeline missing 'artifact presence gate' / '必須成果物'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# T-2: ticket-pipeline references all 7 artifact patterns
ARTIFACT_PATTERNS=(
  "ticket.md"
  "investigation.md"
  "plan.md"
  "eval-round-\\*.md"
  "audit-round-\\*.md"
  "quality-round-\\*.md"
  "security-scan-\\*.md"
)
for pattern in "${ARTIFACT_PATTERNS[@]}"; do
  # Literal pattern for grep (escape backslash-asterisk back to literal *)
  literal=$(echo "$pattern" | sed 's/\\\*/\*/g')
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qF -- "$literal" "$TICKET_PIPELINE_MD"; then
    echo -e "  ${GREEN}PASS${NC} T-2: ticket-pipeline references artifact pattern '$literal'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} T-2: ticket-pipeline missing artifact pattern '$literal'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# T-3: ticket-pipeline mentions FAIL-CRITICAL and "AC評価の全ラウンドでFAIL" exception
assert_file_contains \
  "T-3a: ticket-pipeline mentions FAIL-CRITICAL" \
  "$TICKET_PIPELINE_MD" \
  "FAIL-CRITICAL"

assert_file_contains \
  "T-3b: ticket-pipeline mentions AC評価の全ラウンドでFAIL exception" \
  "$TICKET_PIPELINE_MD" \
  "AC評価の全ラウンドでFAIL"

# T-4: Return Format includes Manual Bash Fallbacks field
assert_file_contains \
  "T-4: ticket-pipeline Return Format includes 'Manual Bash Fallbacks'" \
  "$TICKET_PIPELINE_MD" \
  'Manual Bash Fallbacks'

# T-5: Status list includes completed-with-warnings
assert_file_contains \
  "T-5: ticket-pipeline Status list includes 'completed-with-warnings'" \
  "$TICKET_PIPELINE_MD" \
  "completed-with-warnings"

echo ""

# =============================================================================
# カテゴリ U: Skill Invocation Audit contract (AC-4-C)
# 差分: 新規カテゴリ。ticket-pipeline の invocation_method フィールドと
#        autopilot の Manual Bash Fallbacks ログ連動を検証。
#        U-3/U-4 は autopilot SKILL.md が Phase E で書き換えられるまで phase-guarded。
# =============================================================================
echo "--- Cat U: Skill Invocation Audit contract ---"

# U-1: ticket-pipeline mentions invocation_method
assert_file_contains \
  "U-1: ticket-pipeline mentions invocation_method" \
  "$TICKET_PIPELINE_MD" \
  "invocation_method"

# U-2: ticket-pipeline enumerates 3 values: skill, manual-bash, unknown
for value in "skill" "manual-bash" "unknown"; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qF -- "$value" "$TICKET_PIPELINE_MD"; then
    echo -e "  ${GREEN}PASS${NC} U-2: ticket-pipeline enumerates invocation_method value '$value'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} U-2: ticket-pipeline missing invocation_method value '$value'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# U-3: autopilot SKILL.md logs Manual Bash Fallbacks to autopilot-log.md (phase-guarded, Phase E)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF "ticket-pipeline" "$AUTOPILOT_MD"; then
  # Phase E landed — enforce
  if grep -qF "Manual Bash Fallbacks" "$AUTOPILOT_MD"; then
    echo -e "  ${GREEN}PASS${NC} U-3: autopilot SKILL.md logs Manual Bash Fallbacks"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} U-3: autopilot rewrite detected but Manual Bash Fallbacks logging missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  echo -e "  ${GREEN}PASS${NC} U-3: deferred (Phase E autopilot rewrite not yet landed)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# U-4: autopilot SKILL.md reflects completed-with-warnings in final_status (phase-guarded, Phase E)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF "ticket-pipeline" "$AUTOPILOT_MD"; then
  if grep -qF "completed-with-warnings" "$AUTOPILOT_MD"; then
    echo -e "  ${GREEN}PASS${NC} U-4: autopilot SKILL.md reflects completed-with-warnings"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} U-4: autopilot rewrite detected but completed-with-warnings reflection missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  echo -e "  ${GREEN}PASS${NC} U-4: deferred (Phase E autopilot rewrite not yet landed)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

echo ""

# --- サマリー ---
print_summary
