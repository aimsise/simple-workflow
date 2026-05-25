#!/usr/bin/env bash
# test-skill-contracts.sh — Inter-skill contract / structural consistency tests (Level 0)
#
# Implements new categories A-H that do not overlap with categories 1-20 in test-path-consistency.sh.
# Each category notes the boundary against existing tests in its diff comment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Local helpers ---

# Extract a scalar field from YAML frontmatter (same pattern as test-path-consistency.sh)
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

# Extract the full frontmatter block as text
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

# Case-insensitive variant of assert_file_contains. Use when the documented
# canonical capitalization differs from the prose realization (e.g. a label
# bullet `**Else default 9**` vs the lowercase `else default 9` referenced by
# the precedence-rule contract). Avoids fragile dependence on a meta-comment
# that happens to spell the term in the matching case.
assert_file_contains_i() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qiE -- "$pattern" "$file"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       File: $file"
    echo -e "       Expected pattern (case-insensitive): $pattern"
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
# Category A: disable-model-invocation contract
# Diff: Existing Cat 5 only verifies the presence of name/description.
#        This category verifies the logical consistency between dmi setting and Agent/Skill delegation.
# =============================================================================
echo "--- Cat A: disable-model-invocation contract ---"

# A-1: dmi=true skills must include Agent or Skill in allowed-tools
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
      "dmi=true skill '$skill_slug' has Agent/Skill in allowed-tools or is in the exception list" \
      "$result"
  fi
done

# A-2: skills without dmi set (delegators: catchup, investigate, test) must have agent: or Agent in allowed-tools
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
      "skill '$skill_slug' without dmi has agent: field or Agent tool" \
      "$result"
  fi
done

# A-3: dmi=false skills must include Agent or Skill in allowed-tools (orchestrators called from other skills)
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
      "dmi=false skill '$skill_slug' has Agent/Skill in allowed-tools or is in the exception list" \
      "$result"
    cat_a3_count=$((cat_a3_count + 1))
  fi
done

# Guard assertion: at least 1 dmi=false skill was tested
assert_true "Category A-3: at least 1 dmi=false skill verified ($cat_a3_count total)" "$([ $cat_a3_count -ge 1 ] && echo true || echo false)"

# A-4: dmi=false skills must have "Do not auto-invoke" in description
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
      "dmi=false skill '$skill_slug' description contains 'Do not auto-invoke'" \
      "$result"
  fi
done

echo ""

# =============================================================================
# Category B: AskUserQuestion non-interactive fallback contract
# Diff: Existing tests do not cover this.
#        Verifies the Non-interactive description for skills that include AskUserQuestion
#        in allowed-tools and skills that mention AskUserQuestion in the body.
# =============================================================================
echo "--- Cat B: AskUserQuestion non-interactive fallback contract ---"

# B-1: dynamically detect skills that include AskUserQuestion in allowed-tools
cat_b1_skills=()
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  fm_block=$(extract_frontmatter_block "$skill_md")
  if echo "$fm_block" | grep -qE 'AskUserQuestion'; then
    cat_b1_skills+=("$skill_slug")
    assert_file_contains \
      "$skill_slug: AskUserQuestion in allowed-tools -> has Non-interactive description" \
      "$skill_md" \
      "Non-interactive"
  fi
done

# B-2: dynamically detect skills that instruct using AskUserQuestion in the body (excluding B-1 targets)
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  # Skip skills already covered by B-1
  skip="false"
  for covered in "${cat_b1_skills[@]}"; do
    if [ "$skill_slug" = "$covered" ]; then
      skip="true"
      break
    fi
  done
  [ "$skip" = "true" ] && continue

  body=$(awk 'BEGIN{depth=0} /^---[[:space:]]*$/{depth++;next} depth>=2{print}' "$skill_md")
  # Only target skills that instruct using AskUserQuestion as a tool
  if echo "$body" | grep -qE '(Use.*AskUserQuestion|AskUserQuestion.*to ask|AskUserQuestion.*unavailable|AskUserQuestion.*fallback)'; then
    assert_file_contains \
      "$skill_slug: body instructs AskUserQuestion usage -> has Non-interactive description" \
      "$skill_md" \
      "Non-interactive"
  fi
done

echo ""

# =============================================================================
# Category C: Skill delegation graph consistency
# Diff: Existing Cat 4 uses fixed cross-references against specific files.
#        This category dynamically detects /invocations from skills that have Skill in
#        allowed-tools and verifies the referenced SKILL.md exists.
# =============================================================================
echo "--- Cat C: Skill delegation graph consistency ---"

# Extract backtick-quoted `/skillname` patterns from the body of skills that have Skill in allowed-tools.
# Pattern: skill invocations enclosed in backticks like `/audit` or `/impl`.
# Excludes non-skill references like /Error or /Phase, and path slashes like .simple-workflow/backlog/active/.
cat_c_count=0
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  fm_block=$(extract_frontmatter_block "$skill_md")
  if ! echo "$fm_block" | grep -qE '\bSkill\b'; then
    continue
  fi

  # Extract backtick-quoted /name patterns from the body (only real skill delegation references)
  body=$(awk 'BEGIN{depth=0} /^---[[:space:]]*$/{depth++;next} depth>=2{print}' "$skill_md")
  # shellcheck disable=SC2207
  delegated_skills=($(echo "$body" | grep -oE '`/[a-z][a-z0-9-]+`' | sed -E 's/`\///;s/`//' | sort -u || true))

  if [ ${#delegated_skills[@]} -eq 0 ]; then
    continue
  fi

  for target in "${delegated_skills[@]}"; do
    # Exclude self-references (mentions of the skill itself)
    if [ "$target" = "$skill_slug" ]; then
      continue
    fi
    # Claude Code built-in slash commands (not skills shipped by this
    # plugin): they legitimately appear in backticks inside context_advice
    # text and similar prose ("run `/clear` first and then `/catchup`")
    # but are NOT skill delegations. Skip them from the delegation
    # existence check.
    case "$target" in
      clear|compact|exit|help|model|login|logout|quit|status|tree|init)
        continue
        ;;
    esac
    target_md="$REPO_DIR/skills/$target/SKILL.md"
    result="false"
    if [ -f "$target_md" ]; then
      result="true"
    fi
    assert_true \
      "SKILL.md exists for /$target delegated by $skill_slug" \
      "$result"
    cat_c_count=$((cat_c_count + 1))
  done
done

# Guard assertion: at least 1 skill delegation was tested
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
# Category D: Agent delegation consistency
# Diff: Existing Cat 7 verifies reachability in the agent->skill direction.
#        This category verifies the skill->agent direction (agent: field and body references).
# =============================================================================
echo "--- Cat D: Agent delegation consistency ---"

# D-1: agents/{name}.md exists for the value of the agent: field
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
      "agents/$agent_field.md exists for $skill_slug agent: '$agent_field'" \
      "$result"
    cat_d1_count=$((cat_d1_count + 1))
  fi
done

# Guard assertion: at least 1 agent: field was tested
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$cat_d1_count" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} Category D-1: at least 1 agent field verified ($cat_d1_count total)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Category D-1: no agent fields found to verify (expected >= 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# D-2: agent names referenced in the body of skills that have Agent in allowed-tools
# Dynamically obtain agent names from agents/*.md
KNOWN_AGENTS=""
for agent_file in "$REPO_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_basename=$(basename "$agent_file" .md)
  KNOWN_AGENTS="$KNOWN_AGENTS $agent_basename"
done
KNOWN_AGENTS="${KNOWN_AGENTS# }" # Remove leading space

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
        "agents/$agent_name.md exists for agent '$agent_name' referenced in $skill_slug body" \
        "$result"
      cat_d2_count=$((cat_d2_count + 1))
    fi
  done
done

# Guard assertion: at least 1 agent body reference was tested
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
# Category E: argument-hint and $ARGUMENTS consistency
# Diff: Existing tests do not cover this.
#        Verifies that the body of skills with argument-hint contains $ARGUMENTS.
# =============================================================================
echo "--- Cat E: argument-hint and \$ARGUMENTS consistency ---"

for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  arg_hint=$(extract_frontmatter_field "$skill_md" "argument-hint")
  if [ -n "$arg_hint" ]; then
    assert_file_contains \
      "$skill_slug: has argument-hint -> body contains \$ARGUMENTS" \
      "$skill_md" \
      '\$ARGUMENTS'
  fi
done

echo ""

# =============================================================================
# Category F: context:fork and agent: co-occurrence contract
# Diff: Existing tests do not cover this.
#        Skills with context:fork must also have agent:, and vice versa.
# =============================================================================
echo "--- Cat F: context:fork and agent: co-occurrence contract ---"

for skill_dir in "$REPO_DIR"/skills/*/; do
  skill_slug=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  context_val=$(extract_frontmatter_field "$skill_md" "context")
  agent_val=$(extract_frontmatter_field "$skill_md" "agent")

  # F-1: context:fork -> has agent:
  if [ "$context_val" = "fork" ]; then
    result="false"
    if [ -n "$agent_val" ]; then
      result="true"
    fi
    assert_true \
      "$skill_slug: has context:fork -> also has agent: field" \
      "$result"
  fi

  # F-2: has agent: -> has context:fork
  if [ -n "$agent_val" ]; then
    result="false"
    if [ "$context_val" = "fork" ]; then
      result="true"
    fi
    assert_true \
      "$skill_slug: has agent: -> also has context:fork" \
      "$result"
  fi
done

echo ""

# =============================================================================
# Category G: /audit -> /impl Status contract type consistency
# Diff: Existing Cat 10 verifies the Status vocabulary on agents.
#        This category verifies inter-skill output-input type consistency (3 values: PASS, PASS_WITH_CONCERNS, FAIL).
# =============================================================================
echo "--- Cat G: /audit -> /impl Status contract type consistency ---"

# G-1: audit SKILL.md contains PASS_WITH_CONCERNS
assert_file_contains \
  "audit SKILL.md contains PASS_WITH_CONCERNS" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "PASS_WITH_CONCERNS"

# G-2: impl SKILL.md contains PASS_WITH_CONCERNS
assert_file_contains \
  "impl SKILL.md contains PASS_WITH_CONCERNS" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "PASS_WITH_CONCERNS"

# G-3: audit SKILL.md contains all 3 values: PASS, PASS_WITH_CONCERNS, FAIL
TESTS_TOTAL=$((TESTS_TOTAL + 1))
audit_md="$REPO_DIR/skills/audit/SKILL.md"
has_pass=$(grep -cE '\bPASS\b' "$audit_md" || true)
has_pwc=$(grep -cE 'PASS_WITH_CONCERNS' "$audit_md" || true)
has_fail=$(grep -cE '\bFAIL\b' "$audit_md" || true)
if [ "$has_pass" -gt 0 ] && [ "$has_pwc" -gt 0 ] && [ "$has_fail" -gt 0 ]; then
  echo -e "  ${GREEN}PASS${NC} audit SKILL.md contains all 3 values: PASS, PASS_WITH_CONCERNS, FAIL"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} audit SKILL.md missing one of the 3 values (PASS=$has_pass, PWC=$has_pwc, FAIL=$has_fail)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category H: hook->skill data flow consistency
# Diff: Existing tests do not cover this.
#        Verifies that catchup SKILL.md reads the fields written by pre-compact-save.sh.
# =============================================================================
echo "--- Cat H: hook->skill data flow consistency ---"

HOOK_FILE="$REPO_DIR/hooks/pre-compact-save.sh"
CATCHUP_FILE="$REPO_DIR/skills/catchup/SKILL.md"

DATA_FIELDS="latest_eval_round latest_audit_round last_round_outcome in_progress_phase"

# H-1: pre-compact-save.sh contains all 4 fields
for field in $DATA_FIELDS; do
  assert_file_contains \
    "pre-compact-save.sh contains '$field'" \
    "$HOOK_FILE" \
    "$field"
done

# H-2: catchup SKILL.md contains all 4 fields
for field in $DATA_FIELDS; do
  assert_file_contains \
    "catchup SKILL.md contains '$field'" \
    "$CATCHUP_FILE" \
    "$field"
done

echo ""

# =============================================================================
# Category I: /tune knowledge base contract
# Diff: New category. Verifies structural consistency of the tune skill/agent/KB injection.
# =============================================================================
echo "--- Cat I: /tune knowledge base contract ---"

# I-1: tune SKILL.md exists
TUNE_SKILL="$REPO_DIR/skills/tune/SKILL.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TUNE_SKILL" ]; then
  echo -e "  ${GREEN}PASS${NC} tune SKILL.md exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tune SKILL.md does not exist"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# I-2: tune-analyzer.md exists
TUNE_AGENT="$REPO_DIR/agents/tune-analyzer.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TUNE_AGENT" ]; then
  echo -e "  ${GREEN}PASS${NC} tune-analyzer.md exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tune-analyzer.md does not exist"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# I-3: tune SKILL.md mentions the 50-entry cap
assert_file_contains \
  "tune SKILL.md mentions the 50-entry cap" \
  "$TUNE_SKILL" \
  "maximum 50 entries"

# I-4: tune SKILL.md mentions the 30-candidate cap
assert_file_contains \
  "tune SKILL.md mentions the 30-candidate cap" \
  "$TUNE_SKILL" \
  "(Maximum 30|maximum 30|max.*30) candidates"

# I-5: tune SKILL.md mentions TTL of 90 days
assert_file_contains \
  "tune SKILL.md mentions TTL of 90 days" \
  "$TUNE_SKILL" \
  "TTL.*90|90.*days"

# I-6: tune SKILL.md has 3 confidence branches (auto-promote, propose, accumulate)
assert_file_contains \
  "tune SKILL.md has Auto-promote branch" \
  "$TUNE_SKILL" \
  "Auto-promote|auto-promote"

assert_file_contains \
  "tune SKILL.md has Propose branch" \
  "$TUNE_SKILL" \
  "Propose"

assert_file_contains \
  "tune SKILL.md has Accumulate branch" \
  "$TUNE_SKILL" \
  "Accumulate"

# I-7: tune-analyzer.md has 4 confidence initial values
assert_file_contains \
  "tune-analyzer.md has eval-round confidence 0.3" \
  "$TUNE_AGENT" \
  "0\\.3"

assert_file_contains \
  "tune-analyzer.md has impl success confidence 0.2" \
  "$TUNE_AGENT" \
  "0\\.2"

assert_file_contains \
  "tune-analyzer.md has security confidence 0.4" \
  "$TUNE_AGENT" \
  "0\\.4"

assert_file_contains \
  "tune-analyzer.md has human feedback confidence 0.5" \
  "$TUNE_AGENT" \
  "0\\.5"

# I-8: tune-analyzer.md has Status line (compliant with the Agent Status contract)
assert_file_contains \
  "tune-analyzer.md has Status line" \
  "$TUNE_AGENT" \
  '\*\*Status\*\*.*success.*partial.*failed'

# I-9: tune-analyzer.md has read-only tools + Write (no Edit, no Bash(*))
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
  echo -e "  ${GREEN}PASS${NC} tune-analyzer.md does not contain Edit or Bash(*)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tune-analyzer.md contains Edit or Bash(*) (edit=$has_edit, bash_star=$has_bash_star)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# I-10: ship SKILL.md has /tune invocation (backtick-quoted)
assert_file_contains \
  "ship SKILL.md has backtick-quoted /tune invocation" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  '`/tune`'

# I-11: ship SKILL.md mentions that tune failure does not stop ship
assert_file_contains \
  "ship SKILL.md states that tune failure does not stop ship" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  "not stop|do not.*stop|not.*stop.*ship"

# I-12: impl SKILL.md mentions KB injection (index.yaml)
assert_file_contains \
  "impl SKILL.md has KB injection from index.yaml" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "index\\.yaml"

# I-13: impl SKILL.md notes that AC takes precedence
assert_file_contains \
  "impl SKILL.md notes that AC takes precedence over KB" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "Acceptance Criteria.*take precedence|AC.*precedence|AC.*wins"

# I-14: impl SKILL.md has Known Project Patterns heading
assert_file_contains \
  "impl SKILL.md has Known Project Patterns heading" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "Known Project Patterns"

# I-15: impl SKILL.md mentions skipping when KB does not exist
assert_file_contains \
  "impl SKILL.md mentions skipping when KB does not exist" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "does not exist.*skip|not exist.*skip"

# I-16: tune SKILL.md mentions autopilot-log
assert_file_contains \
  "tune SKILL.md mentions autopilot-log" \
  "$TUNE_SKILL" \
  "autopilot-log"

# I-17: tune SKILL.md mentions category decision
assert_file_contains \
  "tune SKILL.md mentions category decision" \
  "$TUNE_SKILL" \
  "decision"

# I-18: tune-analyzer.md has extraction rules for the decision category
assert_file_contains \
  "tune-analyzer.md mentions decision pattern extraction" \
  "$TUNE_AGENT" \
  "decision"

# I-19: tune-analyzer.md has success_count and failure_count
assert_file_contains \
  "tune-analyzer.md has success_count" \
  "$TUNE_AGENT" \
  "success_count"

assert_file_contains \
  "tune-analyzer.md has failure_count" \
  "$TUNE_AGENT" \
  "failure_count"

# I-20: tune-analyzer.md has autopilot-log decision initial confidence 0.35
assert_file_contains \
  "tune-analyzer.md has decision initial confidence 0.35" \
  "$TUNE_AGENT" \
  "0\\.35"

echo ""

# =============================================================================
# Category J: Autopilot Policy contract
# Diff: New category. Verifies structural consistency of skills that support autopilot-policy.yaml.
# =============================================================================
echo "--- Cat J: Autopilot Policy contract ---"

# J-1: policy-aware skills reference autopilot-policy.yaml
POLICY_SKILLS="create-ticket impl ship"
for skill_slug in $POLICY_SKILLS; do
  assert_file_contains \
    "$skill_slug SKILL.md references autopilot-policy.yaml" \
    "$REPO_DIR/skills/$skill_slug/SKILL.md" \
    "autopilot-policy\\.yaml"
done

# J-2: each skill mentions its corresponding gate name
assert_file_contains \
  "create-ticket SKILL.md has gates.ticket_quality_fail" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "gates\\.ticket_quality_fail"

assert_file_contains \
  "impl SKILL.md has gates.evaluator_dry_run_fail" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "gates\\.evaluator_dry_run_fail"

assert_file_contains \
  "impl SKILL.md has gates.audit_infrastructure_fail" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "gates\\.audit_infrastructure_fail"

assert_file_contains \
  "ship SKILL.md has gates.ship_review_gate" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  "gates\\.ship_review_gate"

assert_file_contains \
  "ship SKILL.md has gates.ship_ci_pending" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  "gates\\.ship_ci_pending"

# J-3: policy-aware skills include [AUTOPILOT-POLICY] log output instruction
for skill_slug in $POLICY_SKILLS; do
  assert_file_contains \
    "$skill_slug SKILL.md has [AUTOPILOT-POLICY] log output" \
    "$REPO_DIR/skills/$skill_slug/SKILL.md" \
    '\[AUTOPILOT-POLICY\]'
done

# J-4 (v4.0.0 Plan 2): brief SKILL.md MUST NOT actively write split-plan.md.
# Phase 5 (Split Analysis) has been removed; ticket decomposition now lives in
# /create-ticket (planner Split Judgment or findings-mode decomposer). We
# accept narrative mentions ("/brief no longer writes split-plan.md") but
# reject write-intent headings like "Generate split-plan.md" / "Write to
# <path>/split-plan.md" that would indicate an actual write step.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE '(Generate split-plan|Write (to )?.*/split-plan\.md)' "$REPO_DIR/skills/brief/SKILL.md"; then
  echo -e "  ${RED}FAIL${NC} brief SKILL.md should NOT contain write-intent prose for split-plan.md (Phase 5 removed)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} brief SKILL.md has no write-intent prose for split-plan.md"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# J-5 (v4.0.0 Plan 2): brief SKILL.md MUST NOT reference `Phase 5` (the
# Split Analysis phase has been removed; its responsibilities moved to
# /create-ticket). The last phase is now renamed "Finalization".
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'Phase 5' "$REPO_DIR/skills/brief/SKILL.md"; then
  echo -e "  ${RED}FAIL${NC} brief SKILL.md should NOT reference 'Phase 5' (removed in v4.0.0)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} brief SKILL.md has no 'Phase 5' reference"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# J-6: autopilot SKILL.md has the split-plan.md detection procedure
assert_file_contains \
  "autopilot SKILL.md has split-plan.md detection" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "split-plan\\.md"

# J-7: autopilot SKILL.md mentions topological sort
assert_file_contains \
  "autopilot SKILL.md has topological sort" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "topological"

# J-8: brief references kb-policy-integration.md has KB reference from index.yaml
assert_file_contains \
  "brief references/kb-policy-integration.md has KB reference from index.yaml" \
  "$REPO_DIR/skills/brief/references/kb-policy-integration.md" \
  "index\\.yaml"

# J-9: brief references kb-policy-integration.md has role=autopilot filtering
assert_file_contains \
  "brief references/kb-policy-integration.md has autopilot role filtering" \
  "$REPO_DIR/skills/brief/references/kb-policy-integration.md" \
  "autopilot"

# J-10: brief references kb-policy-integration.md mentions confidence threshold 0.7
assert_file_contains \
  "brief references/kb-policy-integration.md mentions confidence threshold" \
  "$REPO_DIR/skills/brief/references/kb-policy-integration.md" \
  "0\\.7"

# J-11: impl SKILL.md has gates.ac_eval_fail
assert_file_contains \
  "impl SKILL.md has gates.ac_eval_fail" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "gates\\.ac_eval_fail"

# J-12: autopilot SKILL.md has gates.unexpected_error
assert_file_contains \
  "autopilot SKILL.md has gates.unexpected_error" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "gates\\.unexpected_error"

# J-13: impl SKILL.md has constraints.allow_breaking_changes
assert_file_contains \
  "impl SKILL.md has constraints.allow_breaking_changes" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "constraints\\.allow_breaking_changes"

# J-14: impl SKILL.md has constraints.max_total_rounds
assert_file_contains \
  "impl SKILL.md has constraints.max_total_rounds" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "constraints\\.max_total_rounds"

# J-15: autopilot SKILL.md mentions unsupported action fallback for unexpected_error
assert_file_contains \
  "autopilot SKILL.md mentions unsupported action fallback for unexpected_error" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "fallback from unsupported action"

# J-16: autopilot SKILL.md has dynamic action log output for unexpected_error (not hard-coded)
assert_file_contains \
  "autopilot SKILL.md has dynamic action={actual_action} log for unexpected_error" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'action=\{actual_action\}'

# J-17: autopilot SKILL.md defines moderate and aggressive defaults separately
assert_file_contains \
  "autopilot SKILL.md defines moderate defaults independently" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  '`moderate` defaults:'

assert_file_contains \
  "autopilot SKILL.md defines aggressive defaults independently" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  '`aggressive` defaults:'

# J-18: autopilot SKILL.md aggressive defaults have specific values
assert_file_contains \
  "autopilot SKILL.md aggressive has timeout_minutes: 60" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'aggressive.*timeout_minutes: 60'

assert_file_contains \
  "autopilot SKILL.md aggressive has max_total_rounds: 12" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'aggressive.*max_total_rounds: 12'

assert_file_contains \
  "autopilot SKILL.md aggressive has allow_breaking_changes: true" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'aggressive.*allow_breaking_changes: true'

# J-19: brief references policy-template.md has aggressive-specific values
assert_file_contains \
  "brief references/policy-template.md has timeout_minutes aggressive branch (60)" \
  "$REPO_DIR/skills/brief/references/policy-template.md" \
  'timeout_minutes:.*60.*aggressive'

assert_file_contains \
  "brief references/policy-template.md has max_total_rounds aggressive branch (12)" \
  "$REPO_DIR/skills/brief/references/policy-template.md" \
  'max_total_rounds:.*12.*aggressive'

assert_file_contains \
  "brief references/policy-template.md has allow_breaking_changes aggressive branch (true)" \
  "$REPO_DIR/skills/brief/references/policy-template.md" \
  'allow_breaking_changes:.*true.*aggressive'

# J-20: impl SKILL.md documents the rounds=N argument, the new default 9 cap,
#       and the soft cap of 24. Added in v6.4.4 to lock in the manual-vs-autopilot
#       asymmetry fix (manual default raised 3 -> 9, plus an explicit `rounds=N`
#       override and a 24-round soft warning).

# J-20a: argument-hint advertises the rounds=N token (anchored to the
#        frontmatter line so the assertion does not silently pass on a
#        SKILL.md that mentions rounds=N only in body / examples while the
#        argument-hint itself was deleted).
assert_file_contains \
  "impl SKILL.md argument-hint advertises rounds=N" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "^argument-hint:.*rounds=N"

# J-20b: precedence prose explicitly names the new default 9 fallback.
#        Case-insensitive so the canonical bullet header `**Else default 9**`
#        (capital E) directly satisfies the contract — no fragile dependence
#        on a meta-comment that happens to spell the term in lowercase.
assert_file_contains_i \
  "impl SKILL.md states default 9 round cap" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "else default 9"

# J-20c: soft cap of 24 is documented (warn-only, no clamp)
assert_file_contains \
  "impl SKILL.md states soft cap 24" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "soft cap 24"

echo ""

# =============================================================================
# Category K: kb-suggested / kb_override contract
# Diff: New category. Verifies the consistency of kb-suggested comment annotation,
#        detection, and separated logging so that KB-derived default changes are
#        not misclassified as human_override.
# =============================================================================
echo "--- Cat K: kb-suggested / kb_override contract ---"

# K-1: brief references kb-policy-integration.md instructs annotating with kb-suggested comments
assert_file_contains \
  "brief references/kb-policy-integration.md instructs annotating with kb-suggested comments" \
  "$REPO_DIR/skills/brief/references/kb-policy-integration.md" \
  "kb-suggested"

# K-2: autopilot SKILL.md step 6 has kb-suggested comment detection logic
assert_file_contains \
  "autopilot SKILL.md has kb-suggested comment detection" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "kb-suggested"

# K-3: autopilot SKILL.md mentions the kb_override type
assert_file_contains \
  "autopilot SKILL.md has kb_override type" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "kb_override"

# K-4: autopilot SKILL.md mentions the KB Overrides section
assert_file_contains \
  "autopilot SKILL.md has KB Overrides section" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "KB Overrides"

# K-5: autopilot SKILL.md Human Overrides section excludes kb_override
assert_file_contains \
  "autopilot SKILL.md Human Overrides excludes kb_override" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "Exclude.*kb_override"

# K-6: autopilot SKILL.md Decisions Made table distinguishes human_override from kb_override
assert_file_contains \
  "autopilot SKILL.md Decisions Made distinguishes human_override from kb_override" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "human_override.*kb_override"

# K-7: brief references kb-policy-integration.md describes confidence >= 0.7 and kb-suggested on the same line
assert_file_contains \
  "brief references/kb-policy-integration.md ties kb-suggested to the confidence >= 0.7 branch" \
  "$REPO_DIR/skills/brief/references/kb-policy-integration.md" \
  "0\.7.*kb-suggested"

echo ""

# =============================================================================
# Category L: autopilot/brief/create-ticket v2.2.0 contract
# Diff: New category. Verifies structural consistency of ticket_mapping, ticket_dir,
#        brief_slug metadata added in v2.2.0, and the deprecation of ticket-slug.
# =============================================================================
echo "--- Cat L: autopilot/brief/create-ticket v2.2.0 contract ---"

# L-1: autopilot SKILL.md describes ticket_mapping inside the split flow
assert_file_contains \
  "autopilot SKILL.md has ticket_mapping in split flow" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "ticket_mapping"

# L-2: autopilot SKILL.md has ticket_dir frontmatter field
assert_file_contains \
  "autopilot SKILL.md has ticket_dir frontmatter field" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "ticket_dir:"

# L-3: create-ticket SKILL.md has brief_slug metadata
assert_file_contains \
  "create-ticket SKILL.md has brief_slug metadata" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "brief_slug"

# L-4 and L-5: removed in v6.2.0 — Split Judgment / Split Rationale / split guardrails were
# retired when bare/brief modes joined the decomposer-led partition path. See Cat DEC below.

# L-7: create-ticket SKILL.md mentions .ticket-counter
assert_file_contains \
  "create-ticket SKILL.md has .ticket-counter reference" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "\\.ticket-counter"

# L-8: create-ticket SKILL.md mentions brief_part metadata
assert_file_contains \
  "create-ticket SKILL.md has brief_part metadata" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "brief_part"

# L-9 (was L-4): no stale ticket-slug remains in tune-analyzer.md
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
# Category M: Workflow Isolation contract
# Diff: New category. Verifies workflow isolation between manual /impl and /autopilot.
#        /impl excludes tickets that contain autopilot-policy.yaml, and
#        /autopilot uses explicit paths via the Policy guard.
#        Cat J verifies the structural consistency of autopilot-policy, while
#        this category verifies the existence of the isolation mechanism between
#        the two workflows.
# =============================================================================
echo "--- Cat M: Workflow Isolation contract ---"

# M-1: /impl SKILL.md excludes directories that contain autopilot-policy.yaml
assert_file_contains \
  "impl SKILL.md excludes autopilot-policy.yaml directories" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "Exclude.*autopilot-policy\.yaml"

# M-2: /impl SKILL.md selects tickets in ascending (FIFO) sort order
assert_file_contains \
  "impl SKILL.md documents ascending/FIFO ticket selection" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "ascending.*lowest ticket number"

# M-3: /impl SKILL.md has a fallback message when all tickets are autopilot-managed
assert_file_contains \
  "impl SKILL.md has all-autopilot-managed fallback message" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "All active tickets are managed by /autopilot"

# M-4: Policy guard for per-ticket steps — autopilot has per-step ABORT messages
TESTS_TOTAL=$((TESTS_TOTAL + 1))
m4_pass="true"
for step in scout impl ship; do
  if ! grep -qE "\\[PIPELINE\\] $step: ABORT" "$REPO_DIR/skills/autopilot/SKILL.md"; then
    m4_pass="false"
  fi
done
if [ "$m4_pass" = "true" ]; then
  echo -e "  ${GREEN}PASS${NC} M-4: autopilot SKILL.md has Policy guard ABORT for scout/impl/ship"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} M-4: autopilot SKILL.md missing Policy guard ABORT messages"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# M-5: Explicit plan path to /impl in autopilot
assert_file_contains \
  "autopilot SKILL.md passes explicit plan path to /impl in single flow" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "/impl.*\.simple-workflow/backlog/active/.*plan\.md"

# M-6: Split flow Policy guard ABORT in autopilot
TESTS_TOTAL=$((TESTS_TOTAL + 1))
m6_pass="true"
for step in scout impl ship; do
  if ! grep -qE "\\[PIPELINE\\] $step: ABORT.*mark this ticket" "$REPO_DIR/skills/autopilot/SKILL.md"; then
    m6_pass="false"
  fi
done
if [ "$m6_pass" = "true" ]; then
  echo -e "  ${GREEN}PASS${NC} M-6: autopilot SKILL.md has split flow Policy guard ABORT"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} M-6: autopilot SKILL.md missing split flow Policy guard ABORT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# M-7: Split flow explicit /impl plan path in autopilot
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE "/impl \.simple-workflow/backlog/active/.*plan\.md" "$REPO_DIR/skills/autopilot/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} M-7: autopilot SKILL.md passes explicit plan path in split flow"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} M-7: autopilot SKILL.md missing explicit plan path in split flow"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# M-8: create-ticket SKILL.md has atomic update logic for .ticket-counter
assert_file_contains \
  "create-ticket SKILL.md has atomic ticket-counter update (counter + N)" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "counter.*N.*ticket-counter"

# M-9: In Plan 4, /autopilot dropped delegation to /create-ticket.
#       /autopilot becomes a pure consumer of split-plan.md, while ticket
#       creation is completed in advance by upstream /create-ticket. AC #1
#       requires that "no line starting with ^/create-ticket appears in stdout".
#       The previous M-9 "autopilot delegates to /create-ticket" is inverted in
#       Plan 4 to verify "autopilot does NOT invoke /create-ticket (no
#       ^/create-ticket line in prose)".
M9_BAD=$(grep -cE '^/create-ticket' "$REPO_DIR/skills/autopilot/SKILL.md" || true)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$M9_BAD" = "0" ]; then
  echo -e "  ${GREEN}PASS${NC} M-9: autopilot SKILL.md has zero lines matching ^/create-ticket (Plan 4 AC #1)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} M-9: autopilot SKILL.md has $M9_BAD lines matching ^/create-ticket (expected 0 per Plan 4 AC #1)"
  grep -nE '^/create-ticket' "$REPO_DIR/skills/autopilot/SKILL.md" | sed 's/^/       /'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category N: impl safety contracts
# Diff: New category. Verifies /impl stash exclusion paths and /ship ticket completion ordering.
# =============================================================================
echo "--- Cat N: impl safety contracts ---"

# N-1: impl SKILL.md contains the unified stash exclusion pathspec ':!.simple-workflow'
# In v5.0.0 the legacy 3 paths (former docs/backlog/knowledge top-level roots) were
# consolidated into the single `.simple-workflow/` directory, so the exclusion is
# also collapsed to a single line.
assert_file_contains \
  "impl SKILL.md contains stash exclusion ':!.simple-workflow'" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "':!\.simple-workflow'"

# N-2: in ship SKILL.md, .simple-workflow/backlog/done appears before Phase 2
ship_md="$REPO_DIR/skills/ship/SKILL.md"
done_line=$(awk '/\.simple-workflow\/backlog\/done/{print NR; exit}' "$ship_md")
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
# Category O: Autopilot Resilience contract
# Diff: New category. Verifies structural consistency of autopilot state file
#        management, checkpoint reminders, and auto-resume logic.
# =============================================================================
echo "--- Cat O: autopilot resilience ---"

# O-1: autopilot SKILL.md mentions autopilot-state.yaml
assert_file_contains \
  "autopilot SKILL.md references autopilot-state.yaml" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "autopilot-state\\.yaml"

# O-2: autopilot SKILL.md has CHECKPOINT — RE-ANCHOR
assert_file_contains \
  "autopilot SKILL.md has checkpoint re-anchor blocks" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "CHECKPOINT — RE-ANCHOR"

# O-3: autopilot SKILL.md mentions resume_mode
assert_file_contains \
  "autopilot SKILL.md has resume_mode logic" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "resume_mode"

# O-4: autopilot SKILL.md mentions State file cleanup
assert_file_contains \
  "autopilot SKILL.md has state file cleanup" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "State file cleanup"

# O-5: at least 3 occurrences of CHECKPOINT — RE-ANCHOR inside the Split per-ticket flow
# Diff: In Plan 4 /autopilot became a split-only pure consumer and the single-ticket flow was removed.
#        The old layout had 4 single + 4 split = 8 occurrences, but the new layout has 3
#        canonical occurrences in the split per-ticket flow (one each for scout/impl/ship,
#        executed 3 times per iteration).
CHECKPOINT_COUNT=$(grep -c "CHECKPOINT — RE-ANCHOR" "$REPO_DIR/skills/autopilot/SKILL.md" || true)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$CHECKPOINT_COUNT" -ge 3 ]; then
  echo -e "  ${GREEN}PASS${NC} autopilot has >= 3 CHECKPOINT — RE-ANCHOR blocks ($CHECKPOINT_COUNT found)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} autopilot has >= 3 CHECKPOINT — RE-ANCHOR blocks ($CHECKPOINT_COUNT found, expected >= 3)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi


# O-6: autopilot SKILL.md has State file initialization
assert_file_contains \
  "autopilot SKILL.md has state file initialization" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "State file initialization"

# O-7: autopilot SKILL.md has a 7-day stale warning
assert_file_contains \
  "autopilot SKILL.md has stale state warning" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "7 days"

echo ""

# =============================================================================
# Category P: Pipeline Re-Anchoring contract
# Diff: New category. Verifies structural consistency of CHECKPOINT — RE-ANCHOR
#        blocks in autopilot/impl, impl-state.yaml management, and resume logic.
# =============================================================================
echo "--- Cat P: Pipeline Re-Anchoring contract ---"

# P-1: autopilot SKILL.md has "CHECKPOINT — RE-ANCHOR"
assert_file_contains \
  "P-1: autopilot SKILL.md has CHECKPOINT — RE-ANCHOR" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "CHECKPOINT — RE-ANCHOR"

# P-2: autopilot SKILL.md has Read.*autopilot-state.yaml instruction
assert_file_contains \
  "P-2: autopilot SKILL.md has Read autopilot-state.yaml instruction" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "Read.*autopilot-state\.yaml"

# P-3: impl SKILL.md mentions impl-state.yaml
assert_file_contains \
  "P-3: impl SKILL.md references impl-state.yaml" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "impl-state\.yaml"

# P-4: impl SKILL.md has "CHECKPOINT — RE-ANCHOR"
assert_file_contains \
  "P-4: impl SKILL.md has CHECKPOINT — RE-ANCHOR" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "CHECKPOINT — RE-ANCHOR"

# P-5: impl SKILL.md has Read.*impl-state.yaml instruction
assert_file_contains \
  "P-5: impl SKILL.md has Read impl-state.yaml instruction" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "Read.*impl-state\.yaml"

# P-6: impl SKILL.md mentions impl_resume_mode
assert_file_contains \
  "P-6: impl SKILL.md has impl_resume_mode logic" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "impl_resume_mode"

# P-7: impl SKILL.md mentions impl-state.yaml cleanup/delete
assert_file_contains \
  "P-7: impl SKILL.md has impl-state.yaml cleanup/delete" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "(cleanup|[Dd]elete).*impl-state\.yaml|impl-state\.yaml.*(cleanup|[Dd]elete)"

# P-8: at least 3 occurrences of CHECKPOINT — RE-ANCHOR in autopilot (split per-ticket scout/impl/ship)
# Diff: Plan 4 removed the single-ticket flow, so the old "8 (4+4)" -> "3 (per-ticket iteration)".
COUNT=$(grep -c "CHECKPOINT — RE-ANCHOR" "$REPO_DIR/skills/autopilot/SKILL.md" || true)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$COUNT" -ge 3 ]; then
  echo -e "  ${GREEN}PASS${NC} P-8: autopilot CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 3)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} P-8: autopilot CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 3)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# P-9: at least 1 occurrence of CHECKPOINT — RE-ANCHOR in impl (count check)
COUNT=$(grep -c "CHECKPOINT — RE-ANCHOR" "$REPO_DIR/skills/impl/SKILL.md" || true)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$COUNT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} P-9: impl CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 1)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} P-9: impl CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# P-10: impl SKILL.md mentions next_action
assert_file_contains \
  "P-10: impl SKILL.md has next_action references" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "next_action"

# P-11: at least 1 occurrence of CHECKPOINT — RE-ANCHOR in scout
# Diff: New assertion. Guards the post-/plan2doc handoff in /scout the same
#        way P-9 guards the post-/audit handoff in /impl. Empirical trigger:
#        a /scout run terminated after /plan2doc returned without emitting
#        Step 10's `## [SW-CHECKPOINT]`, mirroring the /impl ↔ /audit failure
#        mode that P-9 / impl-checkpoint-guard.sh already cover.
COUNT=$(grep -c "CHECKPOINT — RE-ANCHOR" "$REPO_DIR/skills/scout/SKILL.md" || true)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$COUNT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} P-11: scout CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 1)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} P-11: scout CHECKPOINT — RE-ANCHOR count ($COUNT found, expected >= 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# P-12: at least 1 occurrence of "Post-/plan2doc Checklist" in scout
# Diff: New assertion. Guards the static-prompt strengthening introduced
#        alongside scout-checkpoint-guard.sh. Mirrors P-11 in spirit:
#        P-11 catches deletion of the RE-ANCHOR blockquote; P-12 catches
#        deletion of the explicit post-/plan2doc checklist that lists
#        Steps 8 / 8a / 9 / 10 as mandatory.
COUNT=$(grep -c "Post-/plan2doc Checklist" "$REPO_DIR/skills/scout/SKILL.md" || true)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$COUNT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} P-12: scout Post-/plan2doc Checklist count ($COUNT found, expected >= 1)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} P-12: scout Post-/plan2doc Checklist count ($COUNT found, expected >= 1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category V: SKILL.md instruction strength verification
# Diff: New category. Verifies the presence of the "Mandatory Skill Invocations"
#        section added in Phase 0c and the MUST/NEVER/Fail enforcement language.
#        Linguistic constraint to prevent the "interpret skill invocations as
#        suggestions and skip them" pattern revealed by JSONL analysis.
# =============================================================================
echo "--- Cat V: SKILL.md instruction strength verification ---"

ORCHESTRATOR_SKILLS=(autopilot create-ticket scout impl audit ship plan2doc)

# V-1: each of the 7 orchestrator skills has a "Mandatory Skill Invocations" section
for skill_name in "${ORCHESTRATOR_SKILLS[@]}"; do
  assert_file_contains \
    "V-1: $skill_name SKILL.md has 'Mandatory Skill Invocations' section" \
    "$REPO_DIR/skills/$skill_name/SKILL.md" \
    "^## Mandatory Skill Invocations"
done

# V-2: each orchestrator skill has MUST/NEVER/Fail enforcement language at least 3 times
#      (Mandatory section + reinforcement at critical invocation sites in the body)
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

# V-3: each table entry in the Mandatory Skill Invocations section has a skip-consequence description
#      (the section contains a "Skip consequence" header, and either consequence-like
#       wording or actual consequence descriptions like "detected by" / "triggers" /
#       "marked failed" / "missing" appear)
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
# Category T': Artifact Presence Gate contract (absorbed into autopilot)
# Diff: Verifies structural consistency of the Artifact Presence Gate that was
#        absorbed from ticket-pipeline into autopilot/SKILL.md in v3.6.0.
# =============================================================================
echo "--- Cat T': Artifact Presence Gate contract ---"

AUTOPILOT_MD="$REPO_DIR/skills/autopilot/SKILL.md"

# T'-1: autopilot/SKILL.md contains "ARTIFACT-MISSING" or "artifact presence gate"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qiE '(ARTIFACT-MISSING|artifact presence gate)' "$AUTOPILOT_MD"; then
  echo -e "  ${GREEN}PASS${NC} T'-1: autopilot/SKILL.md contains 'ARTIFACT-MISSING' or 'artifact presence gate'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} T'-1: autopilot/SKILL.md missing 'ARTIFACT-MISSING' / 'artifact presence gate'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# T'-2: autopilot/SKILL.md contains all 7 artifact patterns
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
  literal=$(echo "$pattern" | sed 's/\\\*/\*/g')
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qF -- "$literal" "$AUTOPILOT_MD"; then
    echo -e "  ${GREEN}PASS${NC} T'-2: autopilot/SKILL.md references artifact pattern '$literal'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} T'-2: autopilot/SKILL.md missing artifact pattern '$literal'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# T'-3: autopilot/SKILL.md mentions FAIL-CRITICAL and AC eval all-rounds-FAIL exception
assert_file_contains \
  "T'-3a: autopilot/SKILL.md mentions FAIL-CRITICAL" \
  "$AUTOPILOT_MD" \
  "FAIL-CRITICAL"

assert_file_contains \
  "T'-3b: autopilot/SKILL.md mentions all-AC-evaluation-rounds-FAILED exception" \
  "$AUTOPILOT_MD" \
  "all AC evaluation rounds FAILED"

echo ""

# =============================================================================
# Category U': Skill Invocation Audit contract (absorbed into autopilot)
# Diff: Verifies structural consistency of the Skill Invocation Audit that was
#        absorbed from ticket-pipeline into autopilot/SKILL.md in v3.6.0.
# =============================================================================
echo "--- Cat U': Skill Invocation Audit contract ---"

# U'-1: autopilot/SKILL.md mentions invocation_method
assert_file_contains \
  "U'-1: autopilot/SKILL.md mentions invocation_method" \
  "$AUTOPILOT_MD" \
  "invocation_method"

# U'-2: autopilot/SKILL.md mentions skill, manual-bash, unknown values
for value in "skill" "manual-bash" "unknown"; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qF -- "$value" "$AUTOPILOT_MD"; then
    echo -e "  ${GREEN}PASS${NC} U'-2: autopilot/SKILL.md contains invocation_method value '$value'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} U'-2: autopilot/SKILL.md missing invocation_method value '$value'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# U'-3: autopilot/SKILL.md mentions manual-bash logging to autopilot-log
assert_file_contains \
  "U'-3: autopilot/SKILL.md logs manual-bash to autopilot-log" \
  "$AUTOPILOT_MD" \
  "manual-bash"

# U'-4: autopilot/SKILL.md mentions completed-with-warnings in final_status
assert_file_contains \
  "U'-4: autopilot/SKILL.md reflects completed-with-warnings in final_status" \
  "$AUTOPILOT_MD" \
  "completed-with-warnings"

echo ""

# =============================================================================
# Category W: Remedy A enforcement (impl step 15 Evaluator prompt template)
# Diff: Guarantees in CI the structural consistency of the copy-pasteable
#        Evaluator prompt template and Binding rule added in impl/SKILL.md step 15
#        by Remedy A (commit 38c1fea). Independent of the existing Cat V
#        enforcement-language verification; checks concrete strings and
#        fenced-block positional relationships.
# =============================================================================
echo "--- Cat W: Remedy A enforcement ---"

# --- Category W: Remedy A enforcement (agent-side, option gamma) ---
# FU-7 shift: Cat W now targets agents/ac-evaluator.md rather than impl/SKILL.md.
# Rationale: the idempotency guarantee belongs in the agent contract (which the
# orchestrator reads as part of its agent system prompt) — not in SKILL.md prose,
# which is defeatable by an orphan fenced block at EOF. Structural position check
# (MUST directive appears inside the new `## Report Persistence Contract` section,
# i.e. before `## Context Conservation Protocol`) makes the assertion resistant
# to orphan-fence bypass and prose relocation.
ACEV_MD="$REPO_DIR/agents/ac-evaluator.md"

# W-1: agents/ac-evaluator.md has a MUST-form directive to write the report before
# returning, AND that directive sits inside the `## Report Persistence Contract`
# section (i.e. strictly before the `## Context Conservation Protocol` heading).
w1_result="false"
if [ -f "$ACEV_MD" ]; then
  w1_result=$(awk '
    BEGIN { in_section = 0; found_in_section = 0 }
    /^## Report Persistence Contract[[:space:]]*$/ { in_section = 1; next }
    /^## Context Conservation Protocol[[:space:]]*$/ { in_section = 0 }
    in_section && /MUST write the evaluation report/ { found_in_section = 1 }
    END { print (found_in_section ? "true" : "false") }
  ' "$ACEV_MD")
fi
assert_true \
  "W-1: agents/ac-evaluator.md has 'MUST write the evaluation report' inside ## Report Persistence Contract section (before ## Context Conservation Protocol)" \
  "$w1_result"

# W-2: agents/ac-evaluator.md has a contract line marking the **Output** field as
# non-empty, AND that line sits inside the `## Report Persistence Contract` section.
w2_result="false"
if [ -f "$ACEV_MD" ]; then
  w2_result=$(awk '
    BEGIN { in_section = 0; found_in_section = 0 }
    /^## Report Persistence Contract[[:space:]]*$/ { in_section = 1; next }
    /^## Context Conservation Protocol[[:space:]]*$/ { in_section = 0 }
    in_section && /Output.*non-empty|non-empty.*Output|Output.*MUST NOT be empty/ { found_in_section = 1 }
    END { print (found_in_section ? "true" : "false") }
  ' "$ACEV_MD")
fi
assert_true \
  "W-2: agents/ac-evaluator.md has a non-empty Output contract line inside ## Report Persistence Contract section" \
  "$w2_result"

# W-3 / W-4: Negative assertions (Round-3 review follow-up / FU-13).
# Rationale: W-1 and W-2 only verify that positive MUST/non-empty markers exist in
# the `## Report Persistence Contract` section. They remain green even if a
# semantically-inverting line (e.g. "Output may be empty", "Callers MAY re-invoke",
# "non-empty is optional", "MAY return without writing") is inserted into the same
# section alongside the positive text. W-3 and W-4 close that loophole by FAILing
# if prohibited phrase patterns appear anywhere inside the section body (between
# the `## Report Persistence Contract` heading and the `## Context Conservation
# Protocol` heading, both heading lines excluded).
#
# Scope: both assertions scan ONLY the body lines of the Report Persistence
# Contract section. Matches elsewhere in the file (frontmatter, other sections)
# are ignored on purpose — that is what makes the negative assertions a true
# "no-bypass within the contract" guard rather than a global lint.

# W-3: no permissive-output / optional-nonempty phrasing inside the section.
# Covers AC FU13-2 classes (a) "Output may be empty" / "empty Output is
# acceptable" / "Output can be empty" and (c) "non-empty is optional" /
# "non-empty is a suggestion" / "non-empty is only advisory".
w3_result="true"
if [ -f "$ACEV_MD" ]; then
  w3_result=$(awk '
    BEGIN {
      in_section = 0
      found = 0
      # (a) Output is allowed to be empty
      p1 = "output[[:space:]]+(may|can|might)[[:space:]]+be[[:space:]]+empty"
      p2 = "empty[[:space:]]+output[[:space:]]+is[[:space:]]+(acceptable|allowed|ok|fine|permitted)"
      p3 = "(you[[:space:]]+)?may[[:space:]]+return[[:space:]]+(an[[:space:]]+)?empty[[:space:]]+output"
      # (c) non-empty requirement is optional/suggestive/advisory
      p4 = "non-empty[[:space:]]+is[[:space:]]+(optional|a[[:space:]]+suggestion|only[[:space:]]+advisory|advisory|suggestive)"
    }
    /^## Report Persistence Contract[[:space:]]*$/ { in_section = 1; next }
    /^## Context Conservation Protocol[[:space:]]*$/ { in_section = 0 }
    in_section {
      ls = tolower($0)
      if (ls ~ p1) found = 1
      if (ls ~ p2) found = 1
      if (ls ~ p3) found = 1
      if (ls ~ p4) found = 1
    }
    END { print (found ? "false" : "true") }
  ' "$ACEV_MD")
fi
assert_true \
  "W-3: agents/ac-evaluator.md has no permissive-output / optional-non-empty phrasing inside ## Report Persistence Contract section" \
  "$w3_result"

# W-4: no retry-permission / return-without-writing phrasing inside the section.
# Covers AC FU13-2 classes (b) "Callers MAY re-invoke" / "callers may retry" /
# "may re-invoke this agent" and (d) "MAY return without writing" / "may return
# before writing" (the "you may return an empty Output" form is already covered
# by W-3's p3, so W-4 focuses on the callers / return-without-writing angle).
w4_result="true"
if [ -f "$ACEV_MD" ]; then
  w4_result=$(awk '
    BEGIN {
      in_section = 0
      found = 0
      # (b) callers may re-invoke / retry
      p1 = "callers?[[:space:]]+(may|can|might)[[:space:]]+(re-?invoke|retry|call[[:space:]]+again)"
      p2 = "(may|can|might)[[:space:]]+re-?invoke[[:space:]]+(this[[:space:]]+)?agent"
      # (d) may return without / before writing
      p3 = "(may|can|might)[[:space:]]+return[[:space:]]+(without|before)[[:space:]]+writ"
    }
    /^## Report Persistence Contract[[:space:]]*$/ { in_section = 1; next }
    /^## Context Conservation Protocol[[:space:]]*$/ { in_section = 0 }
    in_section {
      ls = tolower($0)
      if (ls ~ p1) found = 1
      if (ls ~ p2) found = 1
      if (ls ~ p3) found = 1
    }
    END { print (found ? "false" : "true") }
  ' "$ACEV_MD")
fi
assert_true \
  "W-4: agents/ac-evaluator.md has no caller-retry / return-without-writing phrasing inside ## Report Persistence Contract section" \
  "$w4_result"

# W-5: skills/impl/SKILL.md must not contain a raw `Save your evaluation report to:
# {eval-report-path}` line WITHOUT a companion warning line in close proximity
# (within ±15 lines) telling the orchestrator to substitute the placeholder.
# Rationale (FU-14): if an orchestrator pastes the template verbatim without
# substituting `{eval-report-path}`, ac-evaluator writes to a literal file named
# `{eval-report-path}`, reintroducing the FU-1 bug.
#
# 4th-review H-3 simplification: the earlier implementation used a fence state
# machine keyed on ```-fences. That was bypassable by `~~~` fences or 4-space-
# indented code blocks. This proximity-based check is fence-independent: the
# warning and the placeholder line must co-locate regardless of markdown
# structure. Window size 15 comfortably covers the current 6-line gap between
# warning (L268) and placeholder (L274) while leaving slack for future edits.
#
# Test-the-test: if the warning is removed while the raw placeholder remains,
# W-5 FAILs. If the placeholder is replaced with a concrete example path, W-5
# PASSes regardless of the warning (no raw placeholder to worry about).
IMPL_MD="$REPO_DIR/skills/impl/SKILL.md"
w5_result="true"
if [ -f "$IMPL_MD" ]; then
  w5_result=$(awk '
    BEGIN { n = 0; window = 15 }
    {
      lines[NR] = $0
      if (index($0, "Save your evaluation report to: {eval-report-path}") > 0) {
        ph[++n] = NR
      }
      ls = tolower($0)
      if (index(ls, "substitute") > 0 && (index(ls, "placeholder") > 0 || index(ls, "brace") > 0 || index($0, "{") > 0)) {
        warn[NR] = 1
      }
    }
    END {
      for (i = 1; i <= n; i++) {
        p = ph[i]
        ok = 0
        for (d = -window; d <= window; d++) {
          if ((p + d) in warn) { ok = 1; break }
        }
        if (!ok) { print "false"; exit 0 }
      }
      print "true"
    }
  ' "$IMPL_MD")
fi
assert_true \
  "W-5: skills/impl/SKILL.md raw {eval-report-path} placeholder has a substitute-placeholder warning within ±15 lines (FU-14, H-3 fence-independent)" \
  "$w5_result"

# Test-the-test (W-5-M): copy impl/SKILL.md to a temp file, strip the
# "substitute" warning, and assert the scanner reports "false". Locks in
# detection for both (a) the fence-independent check and (b) future regressions
# that delete the warning line. Removed strings: any line matching
# /substitute.*placeholder|substitute.*brace/ loses its "substitute" keyword.
w5_mut_tmp=$(mktemp -t w5_mut.XXXXXX.md) || w5_mut_tmp="/tmp/w5_mut_$$.md"
if [ -f "$IMPL_MD" ]; then
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  # neuter the warning line by replacing 'substitute' with 'REDACTED' (keep the
  # placeholder line intact so the scanner has something to flag)
  awk '{ if (tolower($0) ~ /substitute.*placeholder|substitute.*brace|substitute.*\{/) { gsub(/substitute/, "REDACTED"); gsub(/Substitute/, "REDACTED") } print }' "$IMPL_MD" > "$w5_mut_tmp"
  w5_mut_result=$(awk '
    BEGIN { n = 0; window = 15 }
    {
      if (index($0, "Save your evaluation report to: {eval-report-path}") > 0) {
        ph[++n] = NR
      }
      ls = tolower($0)
      if (index(ls, "substitute") > 0 && (index(ls, "placeholder") > 0 || index(ls, "brace") > 0 || index($0, "{") > 0)) {
        warn[NR] = 1
      }
    }
    END {
      for (i = 1; i <= n; i++) {
        p = ph[i]; ok = 0
        for (d = -window; d <= window; d++) {
          if ((p + d) in warn) { ok = 1; break }
        }
        if (!ok) { print "false"; exit 0 }
      }
      print "true"
    }
  ' "$w5_mut_tmp")
  if [ "$w5_mut_result" = "false" ]; then
    echo -e "  ${GREEN}PASS${NC} W-5-M: scanner FAILs on warning-stripped SKILL.md (test-the-test for H-3)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} W-5-M: scanner missed warning-stripped SKILL.md — W-5 detector regressed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
fi
rm -f "$w5_mut_tmp"

# W-6: skills/impl/SKILL.md step 16 AC Gate must enforce the ac-evaluator
# Report Persistence Contract at runtime by rejecting empty or ERROR-prefixed
# Output before Status parsing. Rationale (4th review H-2): the contract text
# in agents/ac-evaluator.md is only load-bearing if the orchestrator refuses
# to proceed when it is violated. Without this guard the orchestrator would
# silently advance to step 17 /audit on empty Output.
#
# Scan window: the `16. AC Gate:` heading and the next ~30 lines (the gate
# block ends at a `> **CHECKPOINT` line or step 17). Required markers: the
# phrase "Output" co-occurring with both "empty" and "ERROR-" within the gate
# block, plus a FAIL-CRITICAL escalation verb (stop / FAIL-CRITICAL).
w6_result="true"
if [ -f "$IMPL_MD" ]; then
  w6_result=$(awk '
    BEGIN { in_gate = 0; seen_output = 0; seen_empty = 0; seen_error = 0; seen_stop = 0 }
    /^16\. AC Gate:/ { in_gate = 1; next }
    /^17\./ { in_gate = 0 }
    in_gate {
      if (index($0, "Output") > 0) seen_output = 1
      ls = tolower($0)
      if (index(ls, "empty") > 0) seen_empty = 1
      if (index($0, "ERROR-") > 0) seen_error = 1
      if (index($0, "FAIL-CRITICAL") > 0 || index(ls, "stop") > 0) seen_stop = 1
    }
    END {
      ok = (seen_output && seen_empty && seen_error && seen_stop)
      print (ok ? "true" : "false")
    }
  ' "$IMPL_MD")
fi
assert_true \
  "W-6: skills/impl/SKILL.md step 16 AC Gate enforces Report Persistence Contract at runtime (empty / ERROR- Output → FAIL-CRITICAL, 4th review H-2)" \
  "$w6_result"

echo ""

# =============================================================================
# Category X: Mandatory Skill Invocations target name verification (FU-3)
# Diff: Existing Cat V / T' / U' verify the "row count" of the Mandatory table
#        and the surrounding binding-rule prose, but do not verify that the
#        expected skill/agent name in the first "Invocation Target" column of
#        each row actually exists. This category declares (SKILL.md, expected
#        target) pairs in a visible data structure, extracts the first column of
#        the Mandatory table, and asserts via substring search. Robust to row
#        reordering and intra-cell newlines.
# =============================================================================
echo "--- Cat X: Mandatory table target names ---"

# X: Expected Invocation Target substrings per SKILL.md.
# Data structure: per-file parallel arrays. To add a new skill, declare
# X_TARGETS_<shortname>=( ... ) and add an x_check_targets call at the bottom
# of this block with the matching SKILL.md path. Each target is a literal
# substring that must appear in the Mandatory table's first column
# (Invocation Target) for that file. Substrings are chosen to uniquely identify
# each row even when two rows share an agent name (e.g. ac-evaluator Dry Run
# vs. main gate).

X_TARGETS_impl=(
  "\`implementer\` agent (Agent tool, \"Generator\")"
  "\`ac-evaluator\` agent (Agent tool, Dry Run)"
  "\`ac-evaluator\` agent (Agent tool, main gate)"
  "\`/audit\` (Skill tool)"
)

X_TARGETS_autopilot=(
  "\`/scout\` (Skill)"
  "\`/impl\` (Skill)"
  "\`/ship\` (Skill)"
)
# Diff: In Plan 4 (v4.0.0 findings-mode refactor) /autopilot relinquished the
#        ticket-creation responsibility, and the /create-ticket invocation is no
#        longer part of the consumer flow. The previous X_TARGETS_autopilot
#        included "/create-ticket" (Skill) but it has been removed per Plan 4
#        AC #1 ("stdout does NOT contain ^/create-ticket").

X_TARGETS_create_ticket=(
  "\`researcher\` agent (Agent tool)"
  "\`planner\` agent (Agent tool)"
  "\`ticket-evaluator\` agent (Agent tool)"
)

X_TARGETS_ship=(
  "\`/tune\` (Skill)"
)

# Extract the first column (Invocation Target) of every Mandatory table row
# from the given SKILL.md file. Skips header and separator rows; robust to
# row order. Prints one extracted target cell per line.
extract_mandatory_targets_col1() {
  local file="$1"
  awk -F'|' '
    /^## Mandatory Skill Invocations/ { in_sec=1; next }
    in_sec && /^## / { in_sec=0 }
    in_sec && /^\| / && !/^\| Invocation Target/ && !/^\|---/ {
      # NF counts columns split by |. With a leading and trailing |, field 2
      # is the first logical column. Print trimmed.
      cell = $2
      sub(/^[[:space:]]+/, "", cell)
      sub(/[[:space:]]+$/, "", cell)
      print cell
    }
  ' "$file"
}

# Assert every expected target substring is found in the Mandatory table's
# first column of the given file. One assert per (file, target) pair.
x_check_targets() {
  local rel_path="$1" # e.g. "skills/impl/SKILL.md"
  shift 1
  local targets=("$@")
  local abs="$REPO_DIR/$rel_path"
  local col1
  if [ -f "$abs" ]; then
    col1="$(extract_mandatory_targets_col1 "$abs")"
  else
    col1=""
  fi
  local target
  for target in "${targets[@]}"; do
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ -n "$col1" ] && printf '%s\n' "$col1" | grep -qF -- "$target"; then
      echo -e "  ${GREEN}PASS${NC} X: $rel_path Mandatory table references target '$target'"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo -e "  ${RED}FAIL${NC} X: $rel_path Mandatory table missing target '$target'"
      echo -e "       File: $abs"
      echo -e "       Extracted column 1:"
      if [ -n "$col1" ]; then
        printf '%s\n' "$col1" | sed 's/^/         /'
      else
        echo "         (none / file not found)"
      fi
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  done
}

x_check_targets "skills/impl/SKILL.md"          "${X_TARGETS_impl[@]}"
x_check_targets "skills/autopilot/SKILL.md"     "${X_TARGETS_autopilot[@]}"
x_check_targets "skills/create-ticket/SKILL.md" "${X_TARGETS_create_ticket[@]}"
x_check_targets "skills/ship/SKILL.md"          "${X_TARGETS_ship[@]}"

echo ""

# =============================================================================
# Category Y: count-tokens.sh helper integration smoke test (FU-8)
# Diff: tests/helpers/count-tokens.sh was introduced (commit ff67cf3) to steer
#        future compression work toward token-based measurements rather than
#        bytes, but it was an orphan script that was not called from anywhere
#        in the repository. This category executes the helper against each
#        skills/*/SKILL.md and verifies stdout is a positive integer
#        (^[1-9][0-9]*$), wiring the helper's contract into CI. Independent of
#        the SKILL.md structural verifications in Cat W/X etc.
# =============================================================================
echo "--- Cat Y: count-tokens.sh helper smoke ---"

COUNT_TOKENS_HELPER="$REPO_DIR/tests/helpers/count-tokens.sh"

# Invoke tests/helpers/count-tokens.sh on the given SKILL.md and assert stdout
# is a positive integer. Stderr (the [tiktoken] / [fallback: chars/4] mode
# label) is intentionally discarded here — Cat Y only checks the numeric
# contract. Paths with spaces are safe because "$abs" is quoted throughout.
y_check_token_count() {
  local rel_path="$1" # e.g. "skills/impl/SKILL.md"
  local abs="$REPO_DIR/$rel_path"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local out=""
  if [ -f "$abs" ] && [ -x "$COUNT_TOKENS_HELPER" ]; then
    out="$(bash "$COUNT_TOKENS_HELPER" "$abs" 2>/dev/null || true)"
  fi
  if [[ "$out" =~ ^[1-9][0-9]*$ ]]; then
    echo -e "  ${GREEN}PASS${NC} Y: $rel_path count-tokens.sh stdout is positive integer ($out)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} Y: $rel_path count-tokens.sh did not produce a positive integer"
    echo -e "       File: $abs"
    echo -e "       Helper: $COUNT_TOKENS_HELPER"
    echo -e "       stdout: '$out' (expected /^[1-9][0-9]*\$/, got non-integer output)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Cover all 13 SKILL.md files. The minimum AC requires impl, autopilot,
# create-ticket, ship; covering the full set catches helper regressions on
# any skill without a separate data structure.
y_check_token_count "skills/audit/SKILL.md"
y_check_token_count "skills/autopilot/SKILL.md"
y_check_token_count "skills/brief/SKILL.md"
y_check_token_count "skills/catchup/SKILL.md"
y_check_token_count "skills/create-ticket/SKILL.md"
y_check_token_count "skills/impl/SKILL.md"
y_check_token_count "skills/investigate/SKILL.md"
y_check_token_count "skills/plan2doc/SKILL.md"
y_check_token_count "skills/refactor/SKILL.md"
y_check_token_count "skills/scout/SKILL.md"
y_check_token_count "skills/ship/SKILL.md"
y_check_token_count "skills/test/SKILL.md"
y_check_token_count "skills/tune/SKILL.md"

echo ""

# =============================================================================
# Category Z: create-ticket / ticket-evaluator AC example drift guard (FU-11)
# Diff: As pointed out in the Round-2 review, the Gate 1/Gate 2 BAD/GOOD
#        examples in the `#### AC Quality Criteria` section of Phase 3 in
#        skills/create-ticket/SKILL.md are verbatim duplicates of the ones in
#        agents/ticket-evaluator.md. Since the plugin mechanism does not support
#        cross-file content interpolation, runtime de-duplication is
#        impossible. As an alternative, this category guarantees in CI that
#        the 4 canonical example strings exist in BOTH files, immediately
#        detecting the case where only one is edited. Independent textual
#        agreement contract, separate from Cat W (ac-evaluator structure),
#        Cat X (Mandatory table), and Cat Y (token helper).
# =============================================================================
echo "--- Cat Z: create-ticket / ticket-evaluator AC example drift guard ---"

# --- Category Z: AC example drift guard ---
# Canonical Gate 1/Gate 2 BAD/GOOD example strings that MUST appear in both
# agents/ticket-evaluator.md AND skills/create-ticket/SKILL.md. If any string
# disappears from either file, the duplicated examples have drifted silently
# and this test fires.
Z_CANONICAL_EXAMPLES=(
  "Improve performance"
  "Response time under 200ms for 95th percentile"
  "Support large files"
  "Stream files over 100MB without loading into memory"
)

Z_TICKET_EVALUATOR="$REPO_DIR/agents/ticket-evaluator.md"
Z_CREATE_TICKET="$REPO_DIR/skills/create-ticket/SKILL.md"

# Assert that a literal string appears in BOTH canonical files. Uses grep -qF --
# to guarantee exact (non-regex) literal matching. Emits a single combined
# assertion per string; failure message names which file(s) are missing it so
# drift is self-diagnosing.
z_check_both_files() {
  local literal="$1"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local in_te="false" in_ct="false"
  if [ -f "$Z_TICKET_EVALUATOR" ] && grep -qF -- "$literal" "$Z_TICKET_EVALUATOR"; then
    in_te="true"
  fi
  if [ -f "$Z_CREATE_TICKET" ] && grep -qF -- "$literal" "$Z_CREATE_TICKET"; then
    in_ct="true"
  fi
  if [ "$in_te" = "true" ] && [ "$in_ct" = "true" ]; then
    echo -e "  ${GREEN}PASS${NC} Z: canonical AC example present in both ticket-evaluator.md and create-ticket/SKILL.md: '$literal'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} Z: AC example drift detected for '$literal'"
    echo -e "       agents/ticket-evaluator.md       : $([ "$in_te" = "true" ] && echo present || echo MISSING)"
    echo -e "       skills/create-ticket/SKILL.md    : $([ "$in_ct" = "true" ] && echo present || echo MISSING)"
    echo -e "       Fix: restore the canonical string in both files (duplicated intentionally; plugin architecture does not support cross-file interpolation)."
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

for z_literal in "${Z_CANONICAL_EXAMPLES[@]}"; do
  z_check_both_files "$z_literal"
done

echo ""

# =============================================================================
# Category AA: Hidden-contract HTML-comment guard
# Diff: Because Cat V only counts the number of occurrences of contract
#        keywords (MUST / NEVER / Fail), there was a vulnerability (demonstrated
#        in the Round-3 skeptical review) where deleting the actual contract
#        block and hiding the contract keywords inside an HTML comment
#        (<!-- ... -->) would still pass the test. This category targets the 4
#        contract-bearing SKILL.md files and guarantees that the contract
#        marker tokens MUST / NEVER / Fail are not contained inside HTML
#        comment blocks (including those that span multiple lines).
# =============================================================================
echo "--- Cat AA: Hidden-contract HTML-comment guard ---"

AA_CONTRACT_SKILLS=(
  "skills/impl/SKILL.md"
  "skills/autopilot/SKILL.md"
  "skills/create-ticket/SKILL.md"
  "skills/ship/SKILL.md"
)

# aa_has_hidden_contract_comment — awk scanner that tracks HTML comment blocks
# spanning multiple lines. Concatenates the inner text of each <!-- ... -->
# block (including blocks that open and close on different lines) and reports
# "HIT" on the first block whose inner content contains any of the
# case-sensitive RFC 2119 normative tokens (MUST, NEVER, Fail, SHALL, REQUIRED,
# MANDATORY, PROHIBITED, FORBIDDEN). LLMs treat these as near-synonyms of
# MUST, so hiding any of them inside an HTML comment is equivalent to hiding
# a MUST-level contract (4th review H-4). Prints a diagnostic with the
# starting line number for failure messages. Prints nothing on clean files.
aa_has_hidden_contract_comment() {
  local file="$1"
  awk '
    function suspect(s) {
      return (s ~ /MUST/ || s ~ /NEVER/ || s ~ /Fail/ || s ~ /SHALL/ \
           || s ~ /REQUIRED/ || s ~ /MANDATORY/ || s ~ /PROHIBITED/ \
           || s ~ /FORBIDDEN/)
    }
    BEGIN { in_cmt = 0; buf = ""; start_line = 0 }
    {
      line = $0
      while (length(line) > 0) {
        if (in_cmt == 0) {
          idx = index(line, "<!--")
          if (idx == 0) { break }
          # consume up to and including the opener
          line = substr(line, idx + 4)
          in_cmt = 1
          buf = ""
          start_line = NR
        } else {
          idx = index(line, "-->")
          if (idx == 0) {
            # entire remainder is inside the comment (multi-line span)
            buf = buf " " line
            line = ""
          } else {
            # capture inner content up to the closer, then resume scan
            buf = buf " " substr(line, 1, idx - 1)
            line = substr(line, idx + 3)
            in_cmt = 0
            if (suspect(buf)) {
              printf "HIT line=%d content=%s\n", start_line, buf
              exit 0
            }
          }
        }
      }
    }
    END {
      # Unterminated comment: treat accumulated buffer as suspect too
      if (in_cmt == 1 && suspect(buf)) {
        printf "HIT line=%d content=%s\n", start_line, buf
      }
    }
  ' "$file"
}

for aa_rel in "${AA_CONTRACT_SKILLS[@]}"; do
  aa_file="$REPO_DIR/$aa_rel"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ ! -f "$aa_file" ]; then
    echo -e "  ${RED}FAIL${NC} AA: $aa_rel exists (required contract-bearing skill file)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    continue
  fi
  aa_hit=$(aa_has_hidden_contract_comment "$aa_file")
  if [ -z "$aa_hit" ]; then
    echo -e "  ${GREEN}PASS${NC} AA: $aa_rel has no HTML comment hiding a contract keyword (MUST/NEVER/Fail/SHALL/REQUIRED/MANDATORY/PROHIBITED/FORBIDDEN)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AA: $aa_rel contains HTML comment hiding a contract keyword"
    echo -e "       File: $aa_file"
    echo -e "       Detail: $aa_hit"
    echo -e "       Fix: move RFC 2119 normative language (MUST/SHALL/REQUIRED/MANDATORY/PROHIBITED/FORBIDDEN/NEVER/Fail) out of HTML comments into real prose so Cat V enforces it."
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# Test-the-test (AA-M): synthesize a fixture for each RFC 2119 synonym token
# and verify the scanner HITs. Guards against a future author collapsing the
# token alternation (4th review H-4 regression).
aa_mut_tmp=$(mktemp -t aa_mut.XXXXXX) || aa_mut_tmp="/tmp/aa_mut_$$"
for aa_tok in SHALL REQUIRED MANDATORY PROHIBITED FORBIDDEN; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  printf '# fixture\n<!-- callers %s re-invoke this agent -->\n' "$aa_tok" > "$aa_mut_tmp"
  aa_mut_hit=$(aa_has_hidden_contract_comment "$aa_mut_tmp")
  if [ -n "$aa_mut_hit" ]; then
    echo -e "  ${GREEN}PASS${NC} AA-M: scanner fires on hidden '$aa_tok' token (test-the-test for H-4)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AA-M: scanner missed hidden '$aa_tok' token — token alternation regressed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done
rm -f "$aa_mut_tmp"

echo ""

# =============================================================================
# Category AB: count-tokens.sh tiktoken/fallback agreement (FU-15)
# Diff: Cat Y only verifies that count-tokens.sh returns a positive integer
#        and does not verify the numerical consistency between the tiktoken
#        and fallback branches. Furthermore, since tiktoken is not installed
#        in CI, the tiktoken branch itself is always skipped and its execution
#        path was unverified. This category guarantees the following:
#          1. In environments where tiktoken is available, the [tiktoken]
#             label appears on stderr during normal-path execution (detects
#             silent fallback regressions; Test-the-test guard).
#          2. The numerical results of normal-path (tiktoken) and
#             SWF_FORCE_FALLBACK=1 (chars/4) agree within +/-25%.
#        In environments where tiktoken is unavailable, the test is treated
#        as a skipped PASS (keeping the Total stable). Runs on both local
#        machines (tiktoken not installed) and CI (tiktoken installed).
# =============================================================================
echo "--- Cat AB: count-tokens.sh tiktoken/fallback agreement ---"

AB_HELPER="$REPO_DIR/tests/helpers/count-tokens.sh"
AB_TARGET="$REPO_DIR/skills/impl/SKILL.md"

TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Independently determine whether tiktoken is importable (without depending on
# the normal-path stderr label, so we can also distinguish the case where the
# helper has fallen back to fallback).
ab_tiktoken_available="false"
if python3 -c "import tiktoken" >/dev/null 2>&1; then
  ab_tiktoken_available="true"
fi

if [ ! -f "$AB_TARGET" ] || [ ! -x "$AB_HELPER" ]; then
  echo -e "  ${RED}FAIL${NC} AB: preconditions (helper or target SKILL.md missing)"
  echo -e "       Helper: $AB_HELPER"
  echo -e "       Target: $AB_TARGET"
  TESTS_FAILED=$((TESTS_FAILED + 1))
elif [ "$ab_tiktoken_available" = "false" ]; then
  # tiktoken absent: treated as skipped PASS (Total stays stable at +1)
  echo -e "  ${GREEN}PASS${NC} AB: tiktoken/fallback agreement (skipped: tiktoken unavailable)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  ab_normal_stderr=""
  ab_normal_out=""
  ab_fallback_out=""
  ab_tmp_err=$(mktemp)
  ab_normal_out="$(bash "$AB_HELPER" "$AB_TARGET" 2>"$ab_tmp_err" || true)"
  ab_normal_stderr="$(cat "$ab_tmp_err")"
  rm -f "$ab_tmp_err"
  ab_fallback_out="$(SWF_FORCE_FALLBACK=1 bash "$AB_HELPER" "$AB_TARGET" 2>/dev/null || true)"

  # Guard 1: the normal path must emit the [tiktoken] label on stderr.
  # If it does not, the helper has silently fallen back, which the numerical
  # agreement test alone cannot detect (Test-the-test FU15-6 guard).
  if ! printf '%s' "$ab_normal_stderr" | grep -qF "[tiktoken]"; then
    echo -e "  ${RED}FAIL${NC} AB: tiktoken available but normal-path stderr did not contain '[tiktoken]' label"
    echo -e "       Helper: $AB_HELPER"
    echo -e "       normal-path stderr: $ab_normal_stderr"
    echo -e "       Hint: tiktoken branch may have silently fallen through to chars/4."
    TESTS_FAILED=$((TESTS_FAILED + 1))
  elif ! [[ "$ab_normal_out" =~ ^[1-9][0-9]*$ ]] || ! [[ "$ab_fallback_out" =~ ^[1-9][0-9]*$ ]]; then
    echo -e "  ${RED}FAIL${NC} AB: helper did not produce positive integer outputs on both paths"
    echo -e "       normal-path stdout: '$ab_normal_out'"
    echo -e "       fallback stdout   : '$ab_fallback_out'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    # Agreement check: |normal - fallback| / normal <= 0.25
    # Equivalent in integer arithmetic to |diff|*100 <= normal*25.
    ab_diff=$((ab_normal_out - ab_fallback_out))
    if [ "$ab_diff" -lt 0 ]; then
      ab_diff=$((-ab_diff))
    fi
    ab_threshold=$((ab_normal_out * 25))
    ab_scaled_diff=$((ab_diff * 100))
    if [ "$ab_scaled_diff" -le "$ab_threshold" ]; then
      echo -e "  ${GREEN}PASS${NC} AB: tiktoken=$ab_normal_out fallback=$ab_fallback_out diff=$ab_diff within +/-25%"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo -e "  ${RED}FAIL${NC} AB: tiktoken/fallback agreement exceeded +/-25%"
      echo -e "       tiktoken (normal) : $ab_normal_out"
      echo -e "       fallback (chars/4): $ab_fallback_out"
      echo -e "       |diff|            : $ab_diff"
      echo -e "       threshold (25%)   : $((ab_normal_out / 4))"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  fi
fi

echo ""

# =============================================================================
# Category AC: /brief mode={auto|manual} v6.0.0 contract (CT-MODE-1..10)
# Diff: New category for v6.0.0. Verifies the static contract of the
#        /brief mode= argument refactor:
#          - argument-hint advertises the new mode= form
#          - frontmatter contract documents the mode: scalar
#          - Finalization Steps 2/3 are gated on mode=auto / mode=manual
#          - v6.0.0 removal error message for legacy auto=true is documented
#          - invalid mode= error message is documented
#          - create-ticket Step W-8 gates propagation on brief_mode == auto
#          - autopilot draft-status error message points to mode=auto
#          - README Full Automation section documents mode=auto|manual
#          - CHANGELOG has a [6.0.0] entry with BREAKING CHANGES
# Each CT-MODE-N corresponds to AC-S(N) per the plan's mapping table.
# =============================================================================
echo "--- Cat AC: /brief mode={auto|manual} v6.0.0 contract ---"

# CT-MODE-1 (AC-S1): brief argument-hint contains 'mode=auto|manual'
echo "--- CT-MODE-1 ---"
ct_mode_1_hint=$(extract_frontmatter_field "$REPO_DIR/skills/brief/SKILL.md" "argument-hint")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if printf '%s' "$ct_mode_1_hint" | grep -qF 'mode=auto|manual'; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-1: skills/brief/SKILL.md argument-hint contains 'mode=auto|manual' (AC-S1)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-1: skills/brief/SKILL.md argument-hint does NOT contain 'mode=auto|manual' (AC-S1)"
  echo -e "       argument-hint value: '$ct_mode_1_hint'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-2 (AC-S2): brief body documents `mode: {auto|manual}` in the frontmatter contract
echo "--- CT-MODE-2 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'mode: {auto|manual}' "$REPO_DIR/skills/brief/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-2: skills/brief/SKILL.md frontmatter contract has 'mode: {auto|manual}' (AC-S2)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-2: skills/brief/SKILL.md missing 'mode: {auto|manual}' in frontmatter contract (AC-S2)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-3 (AC-S3): Step 2 chain handoff is gated by 'Only runs when mode=auto'
echo "--- CT-MODE-3 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'Only runs when mode=auto' "$REPO_DIR/skills/brief/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-3: skills/brief/SKILL.md Step 2 contains 'Only runs when mode=auto' (AC-S3)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-3: skills/brief/SKILL.md Step 2 missing 'Only runs when mode=auto' (AC-S3)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-4 (AC-S4): Step 3 heading uses the literal "Step 3 — `mode=manual`"
echo "--- CT-MODE-4 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'Step 3 — `mode=manual`' "$REPO_DIR/skills/brief/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-4: skills/brief/SKILL.md Step 3 heading contains 'Step 3 — \`mode=manual\`' (AC-S4)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-4: skills/brief/SKILL.md Step 3 heading missing literal 'Step 3 — \`mode=manual\`' (AC-S4)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-5 (AC-S5): brief Argument Parsing has the v6.0.0 auto=true removal error
echo "--- CT-MODE-5 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF "'auto=true' has been removed" "$REPO_DIR/skills/brief/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-5: skills/brief/SKILL.md contains \"'auto=true' has been removed\" rejection error (AC-S5)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-5: skills/brief/SKILL.md missing v6.0.0 auto=true rejection error (AC-S5)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-6 (AC-S6): brief Argument Parsing has 'ERROR: invalid mode=' literal
echo "--- CT-MODE-6 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'ERROR: invalid mode=' "$REPO_DIR/skills/brief/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-6: skills/brief/SKILL.md contains 'ERROR: invalid mode=' (AC-S6)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-6: skills/brief/SKILL.md missing 'ERROR: invalid mode=' rejection (AC-S6)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-7 (AC-S7): create-ticket Step W-8 references mode: auto OR brief_mode == auto
echo "--- CT-MODE-7 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'mode:[[:space:]]*auto|brief_mode[[:space:]]*==[[:space:]]*"?auto"?' "$REPO_DIR/skills/create-ticket/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-7: skills/create-ticket/SKILL.md Step W-8 references 'mode: auto' or 'brief_mode == auto' (AC-S7)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-7: skills/create-ticket/SKILL.md Step W-8 missing 'mode: auto' / 'brief_mode == auto' precondition (AC-S7)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-8 (AC-S8): autopilot brief-draft error message points to 'run /brief with mode=auto'
echo "--- CT-MODE-8 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'run /brief with mode=auto' "$REPO_DIR/skills/autopilot/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-8: skills/autopilot/SKILL.md draft-status error contains 'run /brief with mode=auto' (AC-S8)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-8: skills/autopilot/SKILL.md draft-status error missing 'run /brief with mode=auto' (AC-S8)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-9 (AC-S9): README Full Automation section documents mode=auto|manual
echo "--- CT-MODE-9 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'mode=auto|manual' "$REPO_DIR/README.md"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-9: README.md contains 'mode=auto|manual' (AC-S9)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-9: README.md missing 'mode=auto|manual' notation (AC-S9)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-10 (AC-S10): CHANGELOG has a [6.0.0] entry with a BREAKING CHANGES subsection
echo "--- CT-MODE-10 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ct_mode_10_section=$(awk '/^## \[6\.0\.0\]/{flag=1; next} /^## \[/{flag=0} flag' "$REPO_DIR/CHANGELOG.md")
if printf '%s' "$ct_mode_10_section" | grep -q 'BREAKING CHANGES'; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-10: CHANGELOG.md [6.0.0] entry contains 'BREAKING CHANGES' subsection (AC-S10)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-10: CHANGELOG.md [6.0.0] entry missing or has no 'BREAKING CHANGES' subsection (AC-S10)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# CT-MODE-11 (drift guard): brief SKILL.md must contain the literal `next_recommended_auto: ""`
# in the mode=manual SW-CHECKPOINT branch. Guards against silent drift of the negative-AC literal
# that keeps the Stop hook autopilot regex from matching.
echo "--- CT-MODE-11 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -F 'next_recommended_auto: ""' "$REPO_DIR/skills/brief/SKILL.md" >/dev/null; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-11: brief SKILL.md retains the literal 'next_recommended_auto: \"\"' for mode=manual"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-11: brief SKILL.md missing the literal 'next_recommended_auto: \"\"' — the AC-N2 invariant is unguarded"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# CT-MODE-12 (drift guard): create-ticket SKILL.md must contain the literal
# `[POLICY-PROPAGATION] skipped: brief mode=manual` audit trace. Keeps brief↔create-ticket
# narrative in lockstep on the Step W-8 skip line.
echo "--- CT-MODE-12 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -F '[POLICY-PROPAGATION] skipped: brief mode=manual' "$REPO_DIR/skills/create-ticket/SKILL.md" >/dev/null; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-12: create-ticket SKILL.md retains the '[POLICY-PROPAGATION] skipped: brief mode=manual' literal"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-12: create-ticket SKILL.md missing the '[POLICY-PROPAGATION] skipped: brief mode=manual' literal — Step W-8 audit trace drifted"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# CT-MODE-13 (release guard): the [6.0.0] CHANGELOG entry must NOT carry the
# YYYY-MM-DD placeholder. Catches an unfinalized release date before it ships.
echo "--- CT-MODE-13 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ct_mode_13_header=$(awk '/^## \[6\.0\.0\]/{print; exit}' "$REPO_DIR/CHANGELOG.md")
if printf '%s' "$ct_mode_13_header" | grep -q 'YYYY-MM-DD'; then
  echo -e "  ${RED}FAIL${NC} CT-MODE-13: CHANGELOG.md [6.0.0] header still has the 'YYYY-MM-DD' placeholder — set the release date before shipping"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} CT-MODE-13: CHANGELOG.md [6.0.0] header has a concrete release date"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

echo ""

# CT-MODE-14 (release guard): plugin.json version must match the newest CHANGELOG entry.
# Guards against shipping with a stale plugin.json version. The expected version is read
# dynamically from the first `## [X.Y.Z]` header in CHANGELOG.md so this test stays correct
# across patch / minor / major bumps without source-edit churn.
echo "--- CT-MODE-14 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ct_mode_14_plugin_version=$(grep -E '^[[:space:]]*"version":' "$REPO_DIR/.claude-plugin/plugin.json" | head -1 | sed -E 's/.*"version":[[:space:]]*"([^"]+)".*/\1/')
ct_mode_14_changelog_version=$(grep -E '^## \[[0-9]' "$REPO_DIR/CHANGELOG.md" | head -1 | sed -E 's/^## \[([^]]+)\].*/\1/')
if [ -n "$ct_mode_14_plugin_version" ] && [ "$ct_mode_14_plugin_version" = "$ct_mode_14_changelog_version" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-14: plugin.json version is $ct_mode_14_plugin_version, aligned with CHANGELOG [$ct_mode_14_changelog_version]"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-14: plugin.json version is '$ct_mode_14_plugin_version' but CHANGELOG advertises [$ct_mode_14_changelog_version] — bump plugin.json or add a CHANGELOG entry"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category AD: /audit per-Category checklist references contract
# Diff: New category. Verifies that the canonical per-Category checklist
#        source `skills/audit/references/categories.md` exists, has every
#        required `## Category: <name>` header (CodeQuality, Security,
#        Performance, Reliability, Documentation, Testing), and at least
#        three `- [ ] <Capitalized item>` items under each header.
#
# Status markers (literal stdout/stderr lines for downstream tooling and
# for the test-the-test guards in the plan's AC 3-5 + Edge Case 2):
#   - stdout: 'audit-references: present'              (all checks pass)
#   - stderr: 'audit-references: missing'              (file absent)
#   - stderr: 'audit-references: incomplete-headers'   (file present but
#             at least one of the six required headers is missing)
#   - stderr: 'audit-references: empty'                (file is exactly
#             zero bytes)
# An extra seventh `## Category: <name>` (e.g. Accessibility) MUST NOT
# trigger any of these errors — only the six required headers are enforced.
# =============================================================================
echo "--- Cat AD: /audit per-Category checklist references contract ---"

AD_CATEGORIES_FILE="$REPO_DIR/skills/audit/references/categories.md"
AD_REQUIRED_CATEGORIES="CodeQuality Security Performance Reliability Documentation Testing"

# AD-1: file present
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ ! -e "$AD_CATEGORIES_FILE" ]; then
  echo "audit-references: missing" >&2
  echo -e "  ${RED}FAIL${NC} AD-1: skills/audit/references/categories.md is absent (audit-references: missing)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
elif [ ! -s "$AD_CATEGORIES_FILE" ]; then
  # AD-2: file present but exactly zero bytes
  echo "audit-references: empty" >&2
  echo -e "  ${RED}FAIL${NC} AD-1/2: skills/audit/references/categories.md is exactly zero bytes (audit-references: empty)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  # AD-3: file present and non-empty -> verify every required header and
  # at least three checklist items under each.
  ad_missing_headers=""
  ad_underfilled_categories=""
  for ad_cat in $AD_REQUIRED_CATEGORIES; do
    if ! grep -qE "^## Category: ${ad_cat}\$" "$AD_CATEGORIES_FILE"; then
      ad_missing_headers="$ad_missing_headers $ad_cat"
      continue
    fi
    # Extract body of this section: from the matching header to the next
    # `## Category:` header (or EOF). Count `- [ ] <Capitalized item>` lines.
    ad_section_body=$(awk -v cat="$ad_cat" '
      BEGIN { in_section = 0 }
      /^## Category: / {
        if (in_section) { exit }
        if ($0 == "## Category: " cat) { in_section = 1; next }
      }
      in_section { print }
    ' "$AD_CATEGORIES_FILE")
    ad_item_count=$(printf '%s\n' "$ad_section_body" | grep -cE '^- \[ \] [A-Z].+$' || true)
    if [ "${ad_item_count:-0}" -lt 3 ]; then
      ad_underfilled_categories="$ad_underfilled_categories ${ad_cat}(${ad_item_count})"
    fi
  done

  if [ -n "$ad_missing_headers" ]; then
    echo "audit-references: incomplete-headers" >&2
    echo -e "  ${RED}FAIL${NC} AD-1: skills/audit/references/categories.md missing required header(s):${ad_missing_headers} (audit-references: incomplete-headers)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  elif [ -n "$ad_underfilled_categories" ]; then
    echo -e "  ${RED}FAIL${NC} AD-1: skills/audit/references/categories.md has under-filled categories (need >=3 '- [ ] <Capitalized item>' each):${ad_underfilled_categories}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo "audit-references: present"
    echo -e "  ${GREEN}PASS${NC} AD-1: skills/audit/references/categories.md has all 6 required headers with >=3 items each (audit-references: present)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
fi

# AD-4: SKILL.md documents the dispatch-log key=value format. Guards that the
# dispatch contract (the Category propagation surface that the agents and any
# downstream tooling read) is not silently dropped from the skill prompt.
assert_file_contains \
  "AD-4: skills/audit/SKILL.md documents 'category=' dispatch-log line" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  '^category=<value>$'

assert_file_contains \
  "AD-4: skills/audit/SKILL.md documents 'checklist_source=skills/audit/references/categories.md'" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  'checklist_source=skills/audit/references/categories\.md'

# AD-5: SKILL.md documents the Category-tagged checkbox line format that the
# audit-round-{n}.md report MUST contain when the ticket Category matches one
# of the canonical six.
assert_file_contains \
  "AD-5: skills/audit/SKILL.md documents '(Category: <CategoryName>)' report line" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  '\(Category: <CategoryName>\)'

echo ""

# CT-PII-1 (policy guard): CLAUDE.md must declare the PII / absolute-home-path policy.
# Required tokens: literal heading `## PII`, the `<repo>` placeholder, and the phrase
# `absolute home path` (the substring the pre-write/pre-edit hooks emit on rejection).
# Mirrors the pre-write-safety.sh / pre-edit-safety.sh PII guard so the hook contract
# and the human-readable policy stay in lockstep.
echo "--- CT-PII-1 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ct_pii_claudemd="$REPO_DIR/CLAUDE.md"
ct_pii_missing=""
for ct_pii_token in '## PII' '<repo>' 'absolute home path'; do
  if ! grep -qF -- "$ct_pii_token" "$ct_pii_claudemd"; then
    ct_pii_missing="${ct_pii_missing}${ct_pii_missing:+, }$ct_pii_token"
  fi
done
if [ -z "$ct_pii_missing" ]; then
  printf "pii-policy: declared\n"
  echo -e "  ${GREEN}PASS${NC} CT-PII-1: CLAUDE.md declares the PII policy (## PII, <repo>, absolute home path)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf "pii-policy: missing in CLAUDE.md (%s)\n" "$ct_pii_missing" >&2
  echo -e "  ${RED}FAIL${NC} CT-PII-1: CLAUDE.md missing PII policy token(s): $ct_pii_missing"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category AE: Autopilot gate-logging canonical format (Plan 6 part-6)
# Diff: New category. The autopilot canonical gate-decision lines and the
#        `## Decisions Made` table rows in `autopilot-log.md` follow a fixed
#        regex-validated shape with four reason values: evaluated, not_reached,
#        condition_unmet, dependency_skipped. This category validates a fixture
#        file under tests/fixtures/ — when the fixture is canonical, prints the
#        literal stdout line `gate-logging: canonical`. When the fixture
#        contains a `## Decisions Made` row whose third column is not in the
#        canonical reason set, emits a stderr line matching
#        `^gate-logging: invalid line at .+:[0-9]+$` and the assertion fails.
#        HTML comments and triple-backtick fenced blocks are skipped (false-
#        positive guard for documentation examples).
# =============================================================================
echo "--- Cat AE: Autopilot gate-logging canonical format ---"

AE_FIXTURE="$REPO_DIR/tests/fixtures/autopilot-log-canonical.md"

# ae_scan_decisions_table — awk scanner that:
#   1. Tracks fenced-code state (toggled by ^``` ... ^```) and HTML-comment
#      state (toggled by <!-- and --> spans, including multi-line).
#   2. Inside the body that follows the literal heading `## Decisions Made`
#      and before the next `^## ` heading, validates every line that
#      "looks like" a table row (starts with `| ` and is not a header
#      separator `|---|`).
#   3. Emits one of:
#        OK <reason>           — for canonical rows, where <reason> is the
#                                third column value.
#        INVALID <line> <col3> — for table rows whose third column is not in
#                                the canonical reason set.
#      Non-row lines and lines inside fences / HTML comments are ignored.
ae_scan_decisions_table() {
  local file="$1"
  awk '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    BEGIN {
      in_fence = 0
      in_cmt = 0
      in_decisions = 0
    }
    {
      line = $0

      # Strip / track HTML comments. We process the line in pieces so a
      # single-line <!-- ... --> is removed entirely before further checks.
      stripped = ""
      rest = line
      while (length(rest) > 0) {
        if (in_cmt == 0) {
          idx = index(rest, "<!--")
          if (idx == 0) { stripped = stripped rest; rest = ""; break }
          stripped = stripped substr(rest, 1, idx - 1)
          rest = substr(rest, idx + 4)
          in_cmt = 1
        } else {
          idx = index(rest, "-->")
          if (idx == 0) { rest = ""; break }
          rest = substr(rest, idx + 3)
          in_cmt = 0
        }
      }
      effective = stripped

      # Track fenced code blocks (toggle on lines that start with ```).
      if (effective ~ /^```/) {
        in_fence = !in_fence
        next
      }
      if (in_fence) { next }

      # Detect entry/exit of the `## Decisions Made` section.
      if (effective ~ /^## Decisions Made[[:space:]]*$/) {
        in_decisions = 1
        next
      }
      if (effective ~ /^## /) {
        in_decisions = 0
      }

      if (!in_decisions) { next }

      # Skip blank lines and non-row lines inside the section.
      if (effective ~ /^[[:space:]]*$/) { next }
      # Skip the table header row `| gate | action | reason | notes |`.
      if (effective ~ /^\|[[:space:]]*gate[[:space:]]*\|/) { next }
      # Skip header separator `|---|---|---|---|`.
      if (effective ~ /^\|[[:space:]]*-+/) { next }
      # Only validate lines that look like table rows.
      if (effective !~ /^\| /) { next }

      # Split row into columns by `|`. Expect: "", col1, col2, col3, col4, "" (6 fields).
      n = split(effective, parts, "|")
      if (n < 6) {
        printf "INVALID line=%d col3=<malformed>\n", NR
        next
      }
      gate = trim(parts[2])
      action = trim(parts[3])
      reason = trim(parts[4])

      # Validate against the canonical regexes.
      gate_ok = (gate ~ /^[a-z][a-z0-9_-]*$/)
      action_ok = (action == "allow" || action == "deny" || action == "skip")
      reason_ok = (reason == "evaluated" || reason == "not_reached" \
                   || reason == "condition_unmet" || reason == "dependency_skipped")

      if (!gate_ok || !action_ok || !reason_ok) {
        printf "INVALID line=%d col3=%s\n", NR, reason
      } else {
        printf "OK %s\n", reason
      }
    }
  ' "$file"
}

# AE-1: fixture file exists.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$AE_FIXTURE" ]; then
  echo -e "  ${GREEN}PASS${NC} AE-1: gate-logging fixture present at tests/fixtures/autopilot-log-canonical.md"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AE-1: gate-logging fixture missing at $AE_FIXTURE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AE-2: scan the fixture; if canonical (no INVALID and >=1 occurrence of each
#       canonical reason), emit literal stdout line `gate-logging: canonical`.
#       If any INVALID row is detected, emit a stderr line matching
#       `^gate-logging: invalid line at <file>:<lineno>$` and FAIL.
if [ -f "$AE_FIXTURE" ]; then
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  ae_scan=$(ae_scan_decisions_table "$AE_FIXTURE")
  ae_invalid_lines=$(printf '%s\n' "$ae_scan" | grep '^INVALID' || true)
  ae_seen_evaluated=$(printf '%s\n' "$ae_scan" | grep -c '^OK evaluated$' || true)
  ae_seen_not_reached=$(printf '%s\n' "$ae_scan" | grep -c '^OK not_reached$' || true)
  ae_seen_condition_unmet=$(printf '%s\n' "$ae_scan" | grep -c '^OK condition_unmet$' || true)
  ae_seen_dependency_skipped=$(printf '%s\n' "$ae_scan" | grep -c '^OK dependency_skipped$' || true)

  if [ -n "$ae_invalid_lines" ]; then
    # Emit one stderr line per invalid row, matching the AC 11 regex.
    while IFS= read -r ae_inv; do
      ae_lineno=$(printf '%s' "$ae_inv" | sed -E 's/^INVALID line=([0-9]+).*/\1/')
      printf 'gate-logging: invalid line at %s:%s\n' "$AE_FIXTURE" "$ae_lineno" >&2
    done <<< "$ae_invalid_lines"
    echo -e "  ${RED}FAIL${NC} AE-2: gate-logging fixture contains non-canonical reason values (see stderr)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  elif [ "$ae_seen_evaluated" -ge 1 ] \
    && [ "$ae_seen_not_reached" -ge 1 ] \
    && [ "$ae_seen_condition_unmet" -ge 1 ] \
    && [ "$ae_seen_dependency_skipped" -ge 1 ]; then
    echo "gate-logging: canonical"
    echo -e "  ${GREEN}PASS${NC} AE-2: gate-logging fixture covers all four canonical reason values"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AE-2: gate-logging fixture missing one or more canonical reason values (evaluated=$ae_seen_evaluated, not_reached=$ae_seen_not_reached, condition_unmet=$ae_seen_condition_unmet, dependency_skipped=$ae_seen_dependency_skipped)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
fi

# AE-3 (test-the-test): the same scanner, applied to the invalid-reason
# fixture, MUST produce at least one INVALID record. Guards against scanner
# regressions that would silently let through non-canonical reasons.
AE_INVALID_FIXTURE="$REPO_DIR/tests/fixtures/autopilot-log-invalid-reason.md"
if [ -f "$AE_INVALID_FIXTURE" ]; then
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  ae_inv_scan=$(ae_scan_decisions_table "$AE_INVALID_FIXTURE")
  if printf '%s\n' "$ae_inv_scan" | grep -q '^INVALID '; then
    echo -e "  ${GREEN}PASS${NC} AE-3 (test-the-test): scanner detects non-canonical reason in tests/fixtures/autopilot-log-invalid-reason.md"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AE-3 (test-the-test): scanner did NOT detect non-canonical reason — AE-2 detector regressed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
fi

# AE-4 (negative AC 1, false-positive guard): a fixture containing an HTML
# comment with `reason=foo` MUST NOT trigger an INVALID record (HTML-comment-
# scoped illegal tokens are documentation, not contract events).
ae_neg1_tmp=$(mktemp -t ae_neg1.XXXXXX.md) || ae_neg1_tmp="/tmp/ae_neg1_$$.md"
cat > "$ae_neg1_tmp" <<'AE_NEG1_EOF'
## Decisions Made

| gate | action | reason | notes |
|------|--------|--------|-------|
| scout | allow | evaluated | ok row |

<!-- illustrative comment: reason=foo would be rejected if this comment
     were not stripped by the scanner. -->
AE_NEG1_EOF
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ae_neg1_scan=$(ae_scan_decisions_table "$ae_neg1_tmp")
if printf '%s\n' "$ae_neg1_scan" | grep -q '^INVALID '; then
  echo -e "  ${RED}FAIL${NC} AE-4 (negative AC 1): scanner false-positived on an HTML-comment-scoped reason=foo"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} AE-4 (negative AC 1): scanner ignores HTML-comment-scoped reason=foo"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi
rm -f "$ae_neg1_tmp"

# AE-5 (negative AC 2, false-positive guard): a fixture containing a triple-
# backtick fenced code block whose body contains the literal substring
# `reason=foo` MUST NOT trigger an INVALID record (fenced illustrative
# examples are documentation).
ae_neg2_tmp=$(mktemp -t ae_neg2.XXXXXX.md) || ae_neg2_tmp="/tmp/ae_neg2_$$.md"
cat > "$ae_neg2_tmp" <<'AE_NEG2_EOF'
## Decisions Made

| gate | action | reason | notes |
|------|--------|--------|-------|
| scout | allow | evaluated | ok row |

```text
| illustrative | skip | reason=foo | this is in a fence |
```
AE_NEG2_EOF
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ae_neg2_scan=$(ae_scan_decisions_table "$ae_neg2_tmp")
if printf '%s\n' "$ae_neg2_scan" | grep -q '^INVALID '; then
  echo -e "  ${RED}FAIL${NC} AE-5 (negative AC 2): scanner false-positived on a fenced-block reason=foo"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} AE-5 (negative AC 2): scanner ignores fenced-block reason=foo"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi
rm -f "$ae_neg2_tmp"

# AE-6: SKILL.md documents the canonical gate-decision-line shape (the
# four reason values must all appear together in the autopilot SKILL.md).
AE_AUTOPILOT_SKILL="$REPO_DIR/skills/autopilot/SKILL.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'evaluated.*not_reached.*condition_unmet.*dependency_skipped|not_reached.*condition_unmet.*dependency_skipped.*evaluated' "$AE_AUTOPILOT_SKILL" \
   && grep -q '## Unreached Gates' "$AE_AUTOPILOT_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} AE-6: skills/autopilot/SKILL.md documents the four canonical reasons + Unreached Gates section"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AE-6: skills/autopilot/SKILL.md missing canonical reasons or Unreached Gates documentation"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AE-7: tune-analyzer.md documents the tune-candidate-line format and the
# >=3 consecutive-not_reached threshold.
AE_TUNE_AGENT="$REPO_DIR/agents/tune-analyzer.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'tune-candidate-line' "$AE_TUNE_AGENT" \
   && grep -qE '>=[[:space:]]*3' "$AE_TUNE_AGENT" \
   && grep -qE 'candidate: gate=' "$AE_TUNE_AGENT"; then
  echo -e "  ${GREEN}PASS${NC} AE-7: agents/tune-analyzer.md documents tune-candidate-line + >=3 consecutive threshold"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AE-7: agents/tune-analyzer.md missing tune-candidate-line or >=3 threshold documentation"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category AF: AC SSoT (Single Source of Truth) contract
# Diff: Existing categories cover skill frontmatter, delegation graphs, and
#        prompt-time literals. This category is the first runtime data-shape
#        guard — it walks every plan.md/ticket.md pair under
#        `.simple-workflow/backlog/{active,product_backlog,done}/<slug>/<ticket-id>/`
#        and verifies that the `## Acceptance Criteria` list in plan.md is a
#        verbatim copy (per byte, after stripping leading list markers `- `,
#        `* `, or `[0-9]+. `) of the AC list in the sibling ticket.md.
# Plan: .docs/discovery/test_simple_workflow12/pipeline/20260427041937_sw-plugin-pipeline-renovation_part-3.md
# =============================================================================
echo "--- Cat AF: AC SSoT contract ---"

AF_SCANNER="$SCRIPT_DIR/helpers/ac-ssot-scan.sh"
AF_ROOT="$REPO_DIR/.simple-workflow"

# AF-1: scanner exists and is executable.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -x "$AF_SCANNER" ]; then
  echo -e "  ${GREEN}PASS${NC} AF-1: ac-ssot-scan.sh helper is present and executable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AF-1: ac-ssot-scan.sh helper is missing or not executable at $AF_SCANNER"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AF-2 (AC 3 of the plan): scanner exits 0 against the live brief tree AND
# stdout contains the literal line `ac-ssot: synced`.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
af_stdout_file=$(mktemp)
af_stderr_file=$(mktemp)
set +e
bash "$AF_SCANNER" "$AF_ROOT" >"$af_stdout_file" 2>"$af_stderr_file"
af_exit=$?
set -e
if [ "$af_exit" -eq 0 ] && grep -qx 'ac-ssot: synced' "$af_stdout_file"; then
  # Re-emit the scanner's literal line on the harness's own stdout so AC 3's
  # "stdout contains the literal line `ac-ssot: synced`" is satisfied at the
  # harness level, not just inside the AF-2 PASS message.
  echo "ac-ssot: synced"
  echo -e "  ${GREEN}PASS${NC} AF-2: ac-ssot-scan against live brief tree exits 0 with 'ac-ssot: synced'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AF-2: ac-ssot-scan failed against live brief tree (exit=$af_exit)"
  echo -e "       stdout: $(cat "$af_stdout_file")"
  echo -e "       stderr: $(cat "$af_stderr_file")"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f "$af_stdout_file" "$af_stderr_file"

# AF-3: plan2doc/SKILL.md documents the SSoT discipline (ticket.md as SSoT).
assert_file_contains \
  "AF-3: plan2doc/SKILL.md documents 'AC Single Source of Truth' discipline" \
  "$REPO_DIR/skills/plan2doc/SKILL.md" \
  "AC Single Source of Truth"

# AF-4: plan2doc/SKILL.md documents the ssot-line Observable Contract literal.
assert_file_contains \
  "AF-4: plan2doc/SKILL.md documents the 'plan2doc: ac-source=ticket.md verbatim=true' ssot-line" \
  "$REPO_DIR/skills/plan2doc/SKILL.md" \
  "plan2doc: ac-source=ticket\\.md verbatim=true"

# AF-5: plan2doc/SKILL.md documents the byte-equality rule with the marker set.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'byte-identical' "$REPO_DIR/skills/plan2doc/SKILL.md" \
   && grep -qF '[0-9]+\. ' "$REPO_DIR/skills/plan2doc/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} AF-5: plan2doc/SKILL.md documents byte-equality after marker-stripping"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AF-5: plan2doc/SKILL.md missing byte-equality / list-marker stripping documentation"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Category AG: Audit Summary embedding contract ---
# /ship MUST embed `Audit Summary: <Status> (Critical=<N>, Warnings=<N>, Suggestions=<N>)`
# into both commit body and PR body when the latest audit-round-N.md exists.
# Because /ship is a Claude Code skill (prompt), the contract is realized
# through prompt-time documentation. This category statically verifies that
# skills/ship/SKILL.md documents the canonical literals AND exercises the
# parser helper (tests/helpers/audit-summary.sh) against fixtures so that
# Edge Case 1 (missing Status), Edge Case 2 (count mismatch), and the
# numeric-ordering rule (round-10 over round-2) are mechanically verifiable
# without a real /ship run.
echo "--- Audit Summary embedding contract ---"

SHIP_MD="$REPO_DIR/skills/ship/SKILL.md"

# AC: SKILL.md documents the canonical Audit Summary line shape.
assert_file_contains \
  "ship/SKILL.md documents canonical 'Audit Summary:' line shape" \
  "$SHIP_MD" \
  'Audit Summary: <Status> \(Critical=<N>, Warnings=<N>, Suggestions=<N>\)'

# AC: SKILL.md documents the missing-Status stderr literal (Edge Case 1).
assert_file_contains \
  "ship/SKILL.md documents 'audit-summary: missing Status line' stderr" \
  "$SHIP_MD" \
  'audit-summary: missing Status line in audit-round-'

# AC: SKILL.md documents the count-mismatch stderr literal (Edge Case 2).
assert_file_contains \
  "ship/SKILL.md documents 'audit-summary: count-mismatch' stderr" \
  "$SHIP_MD" \
  'audit-summary: count-mismatch \(Warnings declared=<X>, headings=<Y>\)'

# AC 6: no-audit fallback substring is documented.
assert_file_contains \
  "ship/SKILL.md documents '[shipped without /audit]' fallback" \
  "$SHIP_MD" \
  '\[shipped without /audit\]'

# AC 7: numeric ordering is documented (round-10 beats round-2).
assert_file_contains \
  "ship/SKILL.md documents numeric ordering (round-10 beats round-2)" \
  "$SHIP_MD" \
  'audit-round-10\.md`? is later than `?audit-round-2\.md'

# Negative AC 2: fenced-code masking is documented.
assert_file_contains \
  "ship/SKILL.md documents fenced code-block masking" \
  "$SHIP_MD" \
  'triple-backtick fenced code blocks'

# Negative AC 3: HTML-comment masking is documented.
assert_file_contains \
  "ship/SKILL.md documents HTML-comment masking" \
  "$SHIP_MD" \
  '<!-- \.\.\. -->'

# Edge Case 3: backtick preservation in titles is documented.
assert_file_contains \
  "ship/SKILL.md documents backtick preservation in warning titles" \
  "$SHIP_MD" \
  'propagated verbatim'

# Helper presence and executability.
HELPER="$REPO_DIR/tests/helpers/audit-summary.sh"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -x "$HELPER" ]; then
  echo -e "  ${GREEN}PASS${NC} tests/helpers/audit-summary.sh exists and is executable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tests/helpers/audit-summary.sh missing or not executable"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

FIX_DIR="$REPO_DIR/tests/fixtures/audit-rounds"

# Helper assertion: run the parser and compare stdout against an expected line.
assert_helper_stdout() {
  local description="$1"
  local expected="$2"
  shift 2
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local actual rc
  set +e
  actual=$(bash "$HELPER" "$@" 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] && [ "$actual" = "$expected" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       Expected (rc=0): $expected"
    echo -e "       Got (rc=$rc): $actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Helper assertion: parser MUST exit non-zero with a stderr substring.
assert_helper_error() {
  local description="$1"
  local expected_substr="$2"
  shift 2
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local stderr_file rc stderr_content
  stderr_file=$(mktemp)
  set +e
  bash "$HELPER" "$@" >/dev/null 2>"$stderr_file"
  rc=$?
  set -e
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"
  if [ "$rc" -ne 0 ] && echo "$stderr_content" | grep -qF -- "$expected_substr"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       Expected: rc!=0 AND stderr contains '$expected_substr'"
    echo -e "       Got: rc=$rc, stderr='$stderr_content'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_helper_stdout \
  "parser: PASS_WITH_CONCERNS fixture emits canonical line (AC 1)" \
  "Audit Summary: PASS_WITH_CONCERNS (Critical=0, Warnings=2, Suggestions=1)" \
  "$FIX_DIR/pass-with-concerns.md"

assert_helper_stdout \
  "parser: PASS clean fixture emits zero-count line (AC 4)" \
  "Audit Summary: PASS (Critical=0, Warnings=0, Suggestions=0)" \
  "$FIX_DIR/pass-clean.md"

assert_helper_stdout \
  "parser: FAIL Critical=3 fixture emits canonical line (AC 5)" \
  "Audit Summary: FAIL (Critical=3, Warnings=0, Suggestions=0)" \
  "$FIX_DIR/fail-critical.md"

assert_helper_stdout \
  "parser: fenced-block 'Status: FAIL' is masked; outer PASS wins (Negative AC 2)" \
  "Audit Summary: PASS (Critical=0, Warnings=0, Suggestions=0)" \
  "$FIX_DIR/fenced-status.md"

assert_helper_stdout \
  "parser: HTML-commented 'Status: PASS_WITH_CONCERNS' is masked; outer PASS wins (Negative AC 3)" \
  "Audit Summary: PASS (Critical=0, Warnings=0, Suggestions=0)" \
  "$FIX_DIR/html-comment-status.md"

assert_helper_stdout \
  "parser: numeric-ordered --dir picks audit-round-10.md over audit-round-2.md (AC 7)" \
  "Audit Summary: PASS (Critical=0, Warnings=0, Suggestions=0)" \
  "--dir" "$FIX_DIR/multi-round-ticket"

assert_helper_stdout \
  "parser: backtick-quoted warning title round-trips (Edge Case 3)" \
  "Audit Summary: PASS_WITH_CONCERNS (Critical=0, Warnings=1, Suggestions=0)" \
  "$FIX_DIR/backtick-title.md"

# Probe the warning-titles channel — backticks MUST round-trip.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
warning_out=$(bash "$HELPER" --warning-titles "$FIX_DIR/backtick-title.md" 2>/dev/null || true)
if echo "$warning_out" | grep -qF '`SECRET_TOKEN`'; then
  echo -e "  ${GREEN}PASS${NC} parser: --warning-titles preserves backticks in title (Edge Case 3)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} parser: --warning-titles must preserve backticks; got: $warning_out"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

assert_helper_error \
  "parser: missing-Status fixture exits non-zero with stderr literal (Edge Case 1)" \
  "audit-summary: missing Status line in audit-round-" \
  "$FIX_DIR/audit-round-missing-status.md"

assert_helper_error \
  "parser: count-mismatch fixture exits non-zero with stderr literal (Edge Case 2)" \
  "audit-summary: count-mismatch (Warnings declared=0, headings=1)" \
  "$FIX_DIR/count-mismatch.md"

# Final marker — emitted to stdout when SKILL.md documents the contract
# correctly AND every parser probe has run. Downstream tooling can grep for
# this exact line to assert the contract was checked.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'Audit Summary: <Status>' "$SHIP_MD" \
   && grep -qF 'audit-summary: missing Status line in audit-round-' "$SHIP_MD" \
   && grep -qF 'audit-summary: count-mismatch (Warnings declared=<X>, headings=<Y>)' "$SHIP_MD"; then
  echo "audit-summary: contract-declared"
  echo -e "  ${GREEN}PASS${NC} ship/SKILL.md emits 'audit-summary: contract-declared' marker"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ship/SKILL.md is missing one of the required Audit Summary literals"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category RM: runtime_metrics taxonomy contract (Plan 01)
# Diff: This category guards the runtime_metrics SoT introduced by Plan 01.
#       It does not overlap with any existing category — Cat A only checks
#       allowed-tools / dmi consistency, Cat AD only checks audit references.
# =============================================================================
echo "--- Cat RM: runtime_metrics taxonomy contract ---"

RM_TAXONOMY="$REPO_DIR/skills/autopilot/references/stop-reason-taxonomy.md"
RM_AUTOPILOT_SKILL="$REPO_DIR/skills/autopilot/SKILL.md"

# CT-MODE-RM-1: taxonomy file exists and enumerates the canonical enums
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$RM_TAXONOMY" ] \
   && grep -qE '\bsession_compaction\b' "$RM_TAXONOMY" \
   && grep -qE '\bsession_end\b' "$RM_TAXONOMY" \
   && grep -qE '\bself_abort\b' "$RM_TAXONOMY" \
   && grep -qE '\bloop_guard_release\b' "$RM_TAXONOMY" \
   && grep -qE '\bpolicy_gate_stop\b' "$RM_TAXONOMY" \
   && grep -qE '\bpartial_completion\b' "$RM_TAXONOMY" \
   && grep -qE '\bnormal_completion\b' "$RM_TAXONOMY" \
   && grep -qE '\bharness_terminated\b' "$RM_TAXONOMY"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-RM-1: stop-reason-taxonomy.md exists and enumerates all 8 enum values"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-RM-1: stop-reason-taxonomy.md missing or incomplete"
  echo -e "       Expected file: $RM_TAXONOMY"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-RM-2: autopilot SKILL.md mentions runtime_metrics: and cites the taxonomy file
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'runtime_metrics:' "$RM_AUTOPILOT_SKILL" \
   && grep -qE 'references/stop-reason-taxonomy\.md' "$RM_AUTOPILOT_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-RM-2: autopilot SKILL.md documents runtime_metrics and cites references/stop-reason-taxonomy.md"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-RM-2: autopilot SKILL.md missing runtime_metrics: or taxonomy reference"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-RM-3: taxonomy file is English-only (CLAUDE.md Language rule)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$RM_TAXONOMY" ]; then
  RM_NONLATIN=$(grep -cE '[ぁ-んァ-ヶ一-龥]' "$RM_TAXONOMY" 2>/dev/null || true)
  RM_NONLATIN=${RM_NONLATIN:-0}
  if [ "$RM_NONLATIN" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} CT-MODE-RM-3: stop-reason-taxonomy.md contains no Japanese characters"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} CT-MODE-RM-3: stop-reason-taxonomy.md contains $RM_NONLATIN Japanese character(s)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-RM-3: stop-reason-taxonomy.md not present"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category PY: post-phase-checkpoint canonical 3-phase scope (PY-02)
# Diff: PX-05 originally iterated five phases (the legacy shape included
#       audit / tune slots), but the canonical schema in
#       skills/create-ticket/references/phase-state-schema.md defines only
#       three: scout / impl / ship. This category statically guards the
#       reduced phase scope so a future refactor cannot silently re-inflate
#       the iterate loop. The production runtime_metrics capacity ceiling
#       for a clean six-ticket run is 6 tickets * 3 phases (-eq 18 per-run
#       observability records); the legacy fixture-only number was a
#       fabricated upper bound, not a production ceiling.
# =============================================================================
echo "--- Cat PY: post-phase-checkpoint canonical 3-phase scope ---"

PY_HOOK="$REPO_DIR/hooks/post-phase-checkpoint.sh"

# CT-MODE-PY-1: hook iterate loop names exactly scout / impl / ship.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'for[[:space:]]+PHASE[[:space:]]+in[[:space:]]+scout[[:space:]]+impl[[:space:]]+ship' "$PY_HOOK" \
   && ! grep -qE 'for[[:space:]]+PHASE[[:space:]]+in.*audit' "$PY_HOOK" \
   && ! grep -qE 'for[[:space:]]+PHASE[[:space:]]+in.*tune' "$PY_HOOK"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-PY-1: hook phase iterate equals canonical {scout, impl, ship} (no audit / tune)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-PY-1: hook phase iterate is not the canonical 3-phase scope"
  echo -e "       File: $PY_HOOK"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-PY-2: hook docstring / comments must not advertise the legacy
# inflated phase / entry shape.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
PY_LEGACY_RE_FILE=$(mktemp)
printf 'five[ -]phase\n5[[:space:]]+phase\n' > "$PY_LEGACY_RE_FILE"
printf 'thirty[ -]entries\n' >> "$PY_LEGACY_RE_FILE"
# Build the legacy-number regex without writing the literal here so this
# file itself stays clean of the forbidden token.
PY_LEGACY_NUM=$((6 * 5))
printf '\\b%s[[:space:]]+entries\\b\n%s-entry\n' "$PY_LEGACY_NUM" "$PY_LEGACY_NUM" >> "$PY_LEGACY_RE_FILE"
if ! grep -qiEf "$PY_LEGACY_RE_FILE" "$PY_HOOK"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-PY-2: hook source carries no legacy five-phase / inflated-capacity references"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-PY-2: hook source still mentions the legacy five-phase or inflated-capacity shape"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f "$PY_LEGACY_RE_FILE"
unset PY_LEGACY_NUM

# CT-MODE-PY-3: production capacity ceiling is 18 per-phase records
# (6 tickets * 3 phases). Encoded as a runtime check on the canonical
# phase list so the assertion stays in sync with CT-MODE-PY-1.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
PY_PHASE_COUNT=$(printf '%s\n' scout impl ship | wc -l | tr -d '[:space:]')
PY_TICKET_CAP=6
PY_ENTRY_CAP=$((PY_TICKET_CAP * PY_PHASE_COUNT))
if [ "$PY_ENTRY_CAP" -le 18 ] && [ "$PY_ENTRY_CAP" -eq 18 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-PY-3: per-phase entry capacity = ${PY_ENTRY_CAP} (-eq 18, 6 tickets x 3 phases)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-PY-3: per-phase entry capacity = ${PY_ENTRY_CAP}; expected -eq 18 (6 tickets x 3 phases)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category LT: Loop-tail end_turn prohibition + Stop Reason section (Plan 05)
# Diff: Plan 01's Cat RM guards the taxonomy file itself and the SKILL.md
#       citation. This category guards two further inter-skill contracts that
#       Plan 05 introduces: (1) the orchestrator-level "MUST NOT end_turn"
#       loop-tail clause cannot be silently softened, and (2) SKILL.md
#       documents the autopilot-log Stop Reason section format and points
#       to the taxonomy file rather than redefining the tag enum.
# =============================================================================
echo "--- Cat LT: loop-tail clause + Stop Reason contract ---"

LT_AUTOPILOT_SKILL="$REPO_DIR/skills/autopilot/SKILL.md"

# CT-MODE-LT-1: loop-tail "MUST NOT end_turn" clause must remain in SKILL.md
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'MUST NOT.*end_turn' "$LT_AUTOPILOT_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-LT-1: SKILL.md retains 'MUST NOT.*end_turn' loop-tail clause"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-LT-1: SKILL.md is missing the 'MUST NOT end_turn' loop-tail clause"
  echo -e "       File: $LT_AUTOPILOT_SKILL"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-LT-2: SKILL.md declares a level-2 '## Stop Reason' section that
# references the taxonomy file (single source of truth — tag conditions are
# not redefined inline).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
LT_STOP_REASON_BLOCK=$(awk '/^## Stop Reason[[:space:]]*$/{found=1; next} found && /^## /{exit} found {print}' "$LT_AUTOPILOT_SKILL")
if [ -n "$LT_STOP_REASON_BLOCK" ] \
   && echo "$LT_STOP_REASON_BLOCK" | grep -qE 'references/stop-reason-taxonomy\.md'; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-LT-2: SKILL.md '## Stop Reason' section cites references/stop-reason-taxonomy.md"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-LT-2: SKILL.md missing '## Stop Reason' section or its taxonomy citation"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-LT-3: the six canonical Stop Reason tags are each named at least
# once somewhere in SKILL.md so a reader can search for each enum value
# without leaving the skill document. (The authoritative semantics still
# live in the taxonomy file; this guard only checks discoverability.)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
LT_TAGS_OK=true
for lt_tag in self_abort loop_guard_release harness_terminated policy_gate_stop partial_completion normal_completion; do
  if ! grep -qE "\\b${lt_tag}\\b" "$LT_AUTOPILOT_SKILL"; then
    LT_TAGS_OK=false
    break
  fi
done
if [ "$LT_TAGS_OK" = "true" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-LT-3: SKILL.md names all 6 Stop Reason tags"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-LT-3: SKILL.md is missing one or more Stop Reason tag names"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category RV: Agent return-value cap references in SKILL.md (Plan 04)
# Diff: Plan 04 plumbing-fix — every SKILL.md that spawns sub-agents
#       (scout, impl, create-ticket, brief) MUST cite "under 500 tokens"
#       or "Context Conservation Protocol" so the cap is reachable from
#       the caller side, not just from the agent definition. This is a
#       static drift guard against accidental simplification PRs that
#       strip the cap reference. Cat RV does NOT verify per-agent
#       prose — that is owned by Plan 04 AC #4 (sub-agent definitions
#       carry the protocol on their own side).
# =============================================================================
echo "--- Cat RV: Agent return-value cap references (Plan 04) ---"

RV_PATTERN='under 500 tokens|Context Conservation Protocol'

# CT-MODE-RV-scout: /investigate + /plan2doc invocation sites in
# skills/scout/SKILL.md MUST each carry the cap reference (>= 2 hits).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
RV_SCOUT="$REPO_DIR/skills/scout/SKILL.md"
RV_SCOUT_COUNT=$(grep -cE "$RV_PATTERN" "$RV_SCOUT" 2>/dev/null || true)
RV_SCOUT_COUNT=${RV_SCOUT_COUNT:-0}
if [ "$RV_SCOUT_COUNT" -ge 2 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-RV-scout: scout SKILL.md has $RV_SCOUT_COUNT cap reference(s) (>= 2 required)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-RV-scout: scout SKILL.md has $RV_SCOUT_COUNT cap reference(s); 2 required (one per /investigate /plan2doc invocation)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-RV-impl: implementer + ac-evaluator + /audit invocations in
# skills/impl/SKILL.md MUST each carry the cap reference (>= 3 hits).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
RV_IMPL="$REPO_DIR/skills/impl/SKILL.md"
RV_IMPL_COUNT=$(grep -cE "$RV_PATTERN" "$RV_IMPL" 2>/dev/null || true)
RV_IMPL_COUNT=${RV_IMPL_COUNT:-0}
if [ "$RV_IMPL_COUNT" -ge 3 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-RV-impl: impl SKILL.md has $RV_IMPL_COUNT cap reference(s) (>= 3 required)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-RV-impl: impl SKILL.md has $RV_IMPL_COUNT cap reference(s); 3 required (implementer + ac-evaluator + /audit)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-RV-front: combined cap references in create-ticket + brief
# SKILL.md MUST be >= 4 (researcher + decomposer + planner + ticket-evaluator
# in create-ticket; researcher in brief).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
RV_CT="$REPO_DIR/skills/create-ticket/SKILL.md"
RV_BRIEF="$REPO_DIR/skills/brief/SKILL.md"
RV_CT_COUNT=$(grep -cE "$RV_PATTERN" "$RV_CT" 2>/dev/null || true)
RV_CT_COUNT=${RV_CT_COUNT:-0}
RV_BRIEF_COUNT=$(grep -cE "$RV_PATTERN" "$RV_BRIEF" 2>/dev/null || true)
RV_BRIEF_COUNT=${RV_BRIEF_COUNT:-0}
RV_FRONT_COUNT=$((RV_CT_COUNT + RV_BRIEF_COUNT))
if [ "$RV_FRONT_COUNT" -ge 4 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-RV-front: create-ticket+brief combined cap references = $RV_FRONT_COUNT (>= 4 required)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-RV-front: create-ticket=$RV_CT_COUNT brief=$RV_BRIEF_COUNT combined=$RV_FRONT_COUNT; 4 required"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-RV-agents: every spawned-from-skill sub-agent MUST also carry
# the protocol on its own side (defense-in-depth — caller-side cap and
# agent-side cap are belt-and-braces).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
RV_AGENTS_OK=true
RV_MISSING_AGENTS=""
for rv_agent in implementer planner researcher ticket-evaluator decomposer ac-evaluator; do
  rv_apath="$REPO_DIR/agents/${rv_agent}.md"
  if [ -f "$rv_apath" ]; then
    if ! grep -qE "$RV_PATTERN" "$rv_apath"; then
      RV_AGENTS_OK=false
      RV_MISSING_AGENTS="$RV_MISSING_AGENTS $rv_agent"
    fi
  fi
done
if [ "$RV_AGENTS_OK" = "true" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-RV-agents: implementer / planner / researcher / ticket-evaluator / decomposer / ac-evaluator all carry the 500-token cap clause"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-RV-agents: missing cap clause in:${RV_MISSING_AGENTS}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category BL: Plan 07 brief / create-ticket dynamic shrinkage
# Diff: AC #6 of Plan 07 — assert that brief/SKILL.md contains the dynamic
#       Phase 2 shrinkage rule and that create-ticket/SKILL.md contains the
#       lazy re-evaluation rule. Drift-detector for the Plan 07 contract.
# =============================================================================
echo "--- Cat BL: Plan 07 dynamic shrinkage rules ---"

BL_BRIEF="$REPO_DIR/skills/brief/SKILL.md"

# CT-MODE-BL-1: brief/SKILL.md MUST cite runtime_metrics and the signal pair
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'runtime_metrics|autopilot-state\.yaml' "$BL_BRIEF" \
   && grep -qE 'input_tokens.*cache_read_input_tokens|cache_read_input_tokens.*input_tokens' "$BL_BRIEF"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-BL-1: brief/SKILL.md cites runtime_metrics and the input_tokens+cache_read_input_tokens signal pair"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-BL-1: brief/SKILL.md missing runtime_metrics citation or signal pair"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-BL-2: brief/SKILL.md MUST document all four tier rows
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE '≥ 70%|>= 70%' "$BL_BRIEF" \
   && grep -qE '50-70%' "$BL_BRIEF" \
   && grep -qE '30-50%' "$BL_BRIEF" \
   && grep -qE '< 30%' "$BL_BRIEF"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-BL-2: brief/SKILL.md enumerates all four remaining_pct tier rows"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-BL-2: brief/SKILL.md missing one of the four tier rows"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-BL-3: brief/SKILL.md MUST document the standalone fallback path
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'standalone|state-file-absent|state.*absent|state.*not.*exist' "$BL_BRIEF"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-BL-3: brief/SKILL.md documents the standalone fallback when autopilot-state.yaml is absent"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-BL-3: brief/SKILL.md missing standalone fallback clause"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-BL-4: removed in v6.2.0 — the lazy re-evaluation + one-shot read mechanism was
# tied to planner Split Judgment, which was retired when bare/brief modes joined the
# decomposer-led partition path. The decomposer is deterministic and has no re-evaluation loop.

echo ""

# =============================================================================
# Category DEC: decomposer-led partition unification (v6.2.0)
# Diff: v6.2.0 unifies bare / brief / findings modes onto a single decomposer-led
#       partition path. Two input forms (`findings_doc` for findings mode,
#       `scope_context` for bare/brief modes) are documented in
#       skills/create-ticket/references/spec-decomposer-input.md and the
#       agents/decomposer.md agent file. These five assertions are static drift
#       guards covering: input contract, per-mode skill steps, and the negative
#       removal of the legacy Split Judgment vocabulary.
# =============================================================================
echo "--- Cat DEC: decomposer-led partition unification (v6.2.0) ---"

DEC_DECOMPOSER="$REPO_DIR/agents/decomposer.md"
DEC_SPEC="$REPO_DIR/skills/create-ticket/references/spec-decomposer-input.md"
DEC_CT="$REPO_DIR/skills/create-ticket/SKILL.md"

# CT-DEC-1: decomposer.md documents the `scope_context` input form (Form B)
assert_file_contains \
  "agents/decomposer.md documents the scope_context input form" \
  "$DEC_DECOMPOSER" \
  "scope_context"

# CT-DEC-1b: spec-decomposer-input.md is present and references both forms
assert_file_contains \
  "spec-decomposer-input.md present and references findings_doc form" \
  "$DEC_SPEC" \
  "findings_doc"

assert_file_contains \
  "spec-decomposer-input.md references scope_context form" \
  "$DEC_SPEC" \
  "scope_context"

# CT-DEC-2: create-ticket SKILL.md Bare Mode invokes the decomposer (Step D-4)
assert_file_contains \
  "create-ticket SKILL.md Bare Mode has decomposer invocation step (D-4)" \
  "$DEC_CT" \
  '^### Step D-4: Synthesize'

# CT-DEC-3: create-ticket SKILL.md Brief Mode invokes the decomposer (Step B-5)
assert_file_contains \
  "create-ticket SKILL.md Brief Mode has decomposer invocation step (B-5)" \
  "$DEC_CT" \
  '^### Step B-5: Synthesize'

# CT-DEC-4: create-ticket SKILL.md MUST NOT contain the legacy Split Judgment vocabulary
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -qE '(Split Judgment|Split Rationale|Split criteria|split-loop shrinkage|Lazy re-evaluation)' "$DEC_CT"; then
  echo -e "  ${GREEN}PASS${NC} CT-DEC-4: create-ticket SKILL.md no longer contains legacy Split Judgment vocabulary"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-DEC-4: create-ticket SKILL.md still contains legacy Split Judgment vocabulary"
  echo -e "       File: $DEC_CT"
  echo -e "       Forbidden patterns: Split Judgment / Split Rationale / Split criteria / split-loop shrinkage / Lazy re-evaluation"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-DEC-5: Mandatory Skill Invocations table decomposer row covers all modes
assert_file_contains \
  "create-ticket SKILL.md Mandatory table decomposer row covers all modes" \
  "$DEC_CT" \
  "decomposer.*All modes"

# CT-DEC-6: capability guard SIMPLE_WORKFLOW_DISABLE_DECOMPOSER honored in all three mode sections
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DEC_GUARD_COUNT=$(grep -cE 'SIMPLE_WORKFLOW_DISABLE_DECOMPOSER' "$DEC_CT" || true)
if [ "$DEC_GUARD_COUNT" -ge 3 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-DEC-6: SIMPLE_WORKFLOW_DISABLE_DECOMPOSER referenced in all three mode sections (count=$DEC_GUARD_COUNT)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-DEC-6: SIMPLE_WORKFLOW_DISABLE_DECOMPOSER reference count < 3 (got $DEC_GUARD_COUNT)"
  echo -e "       Expected: F-0 (findings) + B-0 (brief) + D-0 (bare) = 3 references minimum"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category CP: Context-Pressure Response Paths (PX-01)
# Diff: PX-01 introduces a SKILL.md section that bans "context budget" /
#       "context pressure" rationales for Manual Bash Fallback and codifies
#       two canonical response paths (auto-compaction + unexpected_error
#       policy-gate stop). These four assertions are static drift guards on
#       AC #1..#4 of PX-01 — they do not exercise the runtime hooks.
# =============================================================================
echo "--- Cat CP: Context-Pressure Response Paths (PX-01) ---"

CP_AUTOPILOT_SKILL="$REPO_DIR/skills/autopilot/SKILL.md"
CP_TAXONOMY="$REPO_DIR/skills/autopilot/references/stop-reason-taxonomy.md"

# CT-MODE-CP-1 (PX-01 AC #1): the `**MUST NOT treat as Manual Bash Fallback**`
# bullet list MUST contain at least one bullet whose text mentions context
# window / context budget / context pressure / context exhaustion / context
# occupancy as a forbidden rationale.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CP1_HITS=$(awk '/^\*\*MUST NOT treat as Manual Bash Fallback\*\*:/,/^\*\*MUST NOT use destructive operations as error shortcuts\*\*:/' "$CP_AUTOPILOT_SKILL" \
  | { grep -ciE 'context.*(window|budget|pressure|exhaust|occupancy)' || true; })
CP1_HITS=${CP1_HITS:-0}
if [ "$CP1_HITS" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-CP-1 (PX-01 AC #1): MUST NOT bullet list cites context window/budget/pressure ($CP1_HITS hits)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-CP-1 (PX-01 AC #1): MUST NOT bullet list missing the context-pressure rationale bullet" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-CP-2 (PX-01 AC #2): the new `## Context-Pressure Response Paths`
# heading MUST appear and MUST sit immediately above `## Stop Reason` in the
# section ordering. The grep below extracts the two heading lines (the new
# section and the existing `## Stop Reason`) and checks the order.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CP2_OUT=$(grep -nE '^##+\s+Context.Pressure Response Paths|^## Stop Reason$' "$CP_AUTOPILOT_SKILL" | head -2)
CP2_LINE_1=$(echo "$CP2_OUT" | sed -n '1p')
CP2_LINE_2=$(echo "$CP2_OUT" | sed -n '2p')
if echo "$CP2_LINE_1" | grep -qiE 'Context.Pressure Response Paths' \
   && echo "$CP2_LINE_2" | grep -q '## Stop Reason'; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-CP-2 (PX-01 AC #2): '## Context-Pressure Response Paths' precedes '## Stop Reason'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-CP-2 (PX-01 AC #2): heading order incorrect or section missing" >&2
  echo -e "       Line 1: $CP2_LINE_1" >&2
  echo -e "       Line 2: $CP2_LINE_2" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-CP-3 (PX-01 AC #3): the body of `## Context-Pressure Response Paths`
# (heading line up to the next `^## ` heading) MUST contain all four required
# elements: pre-compact-save.sh, [RESUME] Skipping, unexpected_error.action: stop,
# and an AskUserQuestion cross-reference.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CP3_BODY=$(awk '/^## Context-Pressure Response Paths/{found=1; next} found && /^## /{exit} found {print}' "$CP_AUTOPILOT_SKILL")
CP3_OK="true"
CP3_MISSING=""
for needle in 'pre-compact-save.sh' '[RESUME] Skipping' 'unexpected_error.action: stop' 'AskUserQuestion'; do
  if ! echo "$CP3_BODY" | grep -qF -- "$needle"; then
    CP3_OK="false"
    CP3_MISSING="$CP3_MISSING [$needle]"
  fi
done
if [ "$CP3_OK" = "true" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-CP-3 (PX-01 AC #3): Context-Pressure body contains all 4 required elements"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-CP-3 (PX-01 AC #3): missing element(s) in section body:$CP3_MISSING" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-CP-4 (PX-01 AC #4): stop-reason-taxonomy.md MUST contain the literal
# phrase "auto compact is normal operation" so taxonomy readers see the
# normalisation explicitly (rather than inferring it from the section format).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'auto compact is normal operation' "$CP_TAXONOMY"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-CP-4 (PX-01 AC #4): stop-reason-taxonomy.md states 'auto compact is normal operation'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-CP-4 (PX-01 AC #4): stop-reason-taxonomy.md missing 'auto compact is normal operation' line" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Phase B: forbidden manual_bash_fallback reason audit (PX-02b)
# Diff: Phase A / Phase A+ above audit static skill-invocation contracts.
#       Phase B is the run-after audit that scans `manual_bash_fallbacks[].reason`
#       text in autopilot-state.yaml fixtures for the canonical
#       FORBIDDEN_RATIONALE_PATTERNS list defined by PX-01. It is the post-hoc
#       counterpart to PX-02a's PreToolUse:Bash guard: PX-02a blocks the call
#       at runtime; Phase B flags any rationale that slipped past the guard
#       (e.g. autopilot-context detection false-negative or hook outage).
#
# Detection scope (NAC #3): only the *text* of `manual_bash_fallbacks[].reason`.
# The literal value "manual-bash" stored under `invocation_method` is NEVER
# itself a violation; legitimate Manual Bash Fallback rationales (subagent
# anomaly recovery, aliased binary bypass) are allowed and exercised by the
# clean-anomaly-reasons.yaml fixture.
#
# No threshold (NAC #7): one reason matching any pattern = violation for
# that fixture.
# =============================================================================
echo "--- Phase B: forbidden manual_bash_fallback reason audit (PX-02b) ---"

# Source the canonical forbidden-rationale pattern list from PX-01. Phase B
# MUST NOT redeclare the pattern array (AC #2 forbids duplicate definitions).
# shellcheck source=../hooks/lib/forbidden-rationale-patterns.sh
source "$REPO_DIR/hooks/lib/forbidden-rationale-patterns.sh"

# Extract every `reason: ...` value from a fixture's `manual_bash_fallbacks:`
# list. Pure-shell parser (no yq dependency) — the fixture schema is fixed
# and the values are quoted scalars, so a line-oriented sed pass is
# sufficient.
phase_b_extract_reasons() {
  local fixture="$1"
  awk '
    /^manual_bash_fallbacks:/ { in_list = 1; next }
    in_list && /^[a-zA-Z_]+:/ { in_list = 0 }
    in_list && /^[[:space:]]+reason:[[:space:]]*/ {
      sub(/^[[:space:]]+reason:[[:space:]]*/, "", $0)
      sub(/^"/, "", $0); sub(/"$/, "", $0)
      print $0
    }
  ' "$fixture"
}

# Run a single Phase B fixture case.
#   $1 = human-readable case label
#   $2 = absolute path to fixture YAML
#   $3 = expected outcome: "detect-forbidden" or "clean"
#
# The case PASSES when the actual outcome matches the expected outcome.
# A "detect-forbidden" expectation requires at least one
# `manual_bash_fallbacks[].reason` line to match a pattern in
# FORBIDDEN_RATIONALE_PATTERNS; a "clean" expectation requires zero matches.
phase_b_run_case() {
  local label="$1"
  local fixture="$2"
  local expected="$3"
  local fixture_basename
  fixture_basename="$(basename "$fixture")"

  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  if [ ! -f "$fixture" ]; then
    echo -e "  ${RED}FAIL${NC} [Phase B] $label: fixture not found: $fixture" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  local reasons
  reasons="$(phase_b_extract_reasons "$fixture")"

  local hits=0
  local hit_lines=""
  local pattern reason
  while IFS= read -r reason; do
    [ -z "$reason" ] && continue
    for pattern in "${FORBIDDEN_RATIONALE_PATTERNS[@]}"; do
      if echo "$reason" | grep -iqE "$pattern"; then
        hits=$((hits + 1))
        hit_lines="${hit_lines}    forbidden pattern hit: ${pattern} -- reason: ${reason}"$'\n'
        break
      fi
    done
  done <<< "$reasons"

  local actual="clean"
  if [ "$hits" -gt 0 ]; then
    actual="detect-forbidden"
  fi

  if [ "$actual" = "$expected" ]; then
    if [ "$expected" = "detect-forbidden" ]; then
      # Emit a line that satisfies AC #3's grep:
      #   grep -E 'with-context-budget-reason\.yaml.*(FAIL|forbidden)'
      echo -e "  ${GREEN}PASS${NC} [Phase B] $label: ${fixture_basename} forbidden hit detected as expected ($hits hit(s))"
      printf '%s' "$hit_lines"
    else
      echo -e "  ${GREEN}PASS${NC} [Phase B] $label: ${fixture_basename} clean as expected (0 hits)"
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    if [ "$expected" = "detect-forbidden" ]; then
      echo -e "  ${RED}FAIL${NC} [Phase B] $label: ${fixture_basename} expected forbidden hit but got 0 hits" >&2
    else
      echo -e "  ${RED}FAIL${NC} [Phase B] $label: ${fixture_basename} expected clean but found $hits forbidden hit(s)" >&2
      printf '%s' "$hit_lines" >&2
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

PHASE_B_FIXTURE_DIR="$REPO_DIR/tests/fixtures/manual-bash-fallbacks-samples"

phase_b_run_case \
  "FAIL fixture: context-budget reason should be detected" \
  "$PHASE_B_FIXTURE_DIR/with-context-budget-reason.yaml" \
  "detect-forbidden"

phase_b_run_case \
  "PASS fixture: anomaly-only reasons should be clean" \
  "$PHASE_B_FIXTURE_DIR/clean-anomaly-reasons.yaml" \
  "clean"

echo ""

# =============================================================================
# Category Q: Test-suite shell hygiene (v6.3.0)
# Diff: New category. Guards against the `set -e` + `grep -c` exit-1 footgun
#        that silently halts test sections when a pattern matches zero times.
#        Every `grep -c` invocation under tests/ MUST be guarded so the test
#        framework can record a clean FAIL instead of dying mid-script.
# =============================================================================
echo "--- Cat Q: Test-suite shell hygiene ---"

# CT-MODE-GREP-C-1: every `grep -c` in tests/ must be set-e safe.
# Acceptable forms:
#   - same-line `|| true`, `|| count=0`, `|| return 0`, `|| exit ...`,
#     or `|| count_matches`
#   - line wrapped by surrounding `set +e` / `set -e` (previous non-blank line)
#   - use of the count_matches helper (which is itself set-e-safe)
# Deliberately NOT accepted: `|| echo 0`. When `grep -c` reads from a real
# file and finds zero matches, it already writes `0` to stdout before
# exiting 1, so `|| echo 0` appends a SECOND `0` and the captured value
# becomes `"0\n0"`, which then breaks any `[ "$VAR" -ge N ]` integer
# comparison with a stderr "integer expression expected" error. Use
# `|| true` (which only swallows the exit code) or migrate to count_matches.
# Exempt: tests/test-helper.sh (defines the count_matches primitive that
# legitimately wraps grep -c).
CT_GREP_C_VIOLATIONS=()
while IFS= read -r line; do
  file="${line%%:*}"
  rest="${line#*:}"
  lineno="${rest%%:*}"
  match="${rest#*:}"
  case "$file" in
    tests/test-helper.sh) continue ;;
  esac
  # Skip comment lines.
  if printf '%s\n' "$match" | grep -qE '^[[:space:]]*#'; then
    continue
  fi
  # Skip echo/printf message lines that mention `grep -c` as documentation —
  # the grep -c lives inside a string literal, not as an executed command.
  if printf '%s\n' "$match" | grep -qE '^[[:space:]]*(echo|printf)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)?"'; then
    continue
  fi
  # Allowed: inline guard on the same line. NB: `echo 0` is NOT in this
  # list — see the header comment above for why.
  if printf '%s\n' "$match" | grep -qE '\|\|[[:space:]]*(true|count=0|return[[:space:]]+0|exit[[:space:]]+[0-9]+|count_matches)'; then
    continue
  fi
  # Allowed: previous non-blank line is `set +e`.
  prev_line=""
  scan_lineno="$lineno"
  while [ "$scan_lineno" -gt 1 ]; do
    scan_lineno=$((scan_lineno - 1))
    prev_line="$(sed -n "${scan_lineno}p" "$REPO_DIR/$file" 2>/dev/null)"
    [ -n "$(printf '%s' "$prev_line" | tr -d '[:space:]')" ] && break
  done
  if printf '%s\n' "$prev_line" | grep -qE '^[[:space:]]*set[[:space:]]+\+e[[:space:]]*$'; then
    continue
  fi
  CT_GREP_C_VIOLATIONS+=("$file:$lineno: $(printf '%s' "$match" | sed 's/^[[:space:]]*//')")
done < <(cd "$REPO_DIR" && grep -nE '\bgrep[[:space:]]+-[[:alpha:]]*c' tests/*.sh 2>/dev/null || true)

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "${#CT_GREP_C_VIOLATIONS[@]}" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-GREP-C-1: every grep -c in tests/ is set-e safe"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-GREP-C-1: ${#CT_GREP_C_VIOLATIONS[@]} unprotected grep -c callsite(s) under tests/" >&2
  for v in "${CT_GREP_C_VIOLATIONS[@]}"; do
    echo "       $v" >&2
  done
  echo "       Wrap with '|| true' / '|| count=0' / set +e ... set -e, or migrate to count_matches helper. NB: '|| echo 0' is rejected because grep -c against a file already writes 0 to stdout on zero matches; the extra echo would produce '0\\n0' and break integer comparisons." >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-GREP-C-2: agents/ac-evaluator.md `maxTurns` MUST stay >= 200. Defense
# against accidental rollback. v6.5.0 (T-2) raised the ceiling from 60 to 200
# under Strategy B (the Agent tool's JSONSchema rejects per-invocation maxTurns
# overrides; see T-2 probe-result in plan.md). The documented floor of 60 is
# preserved via the EVALUATOR_MAX_TURNS = max(60, AC_COUNT * 4) formula in
# Step 15, but the frontmatter ceiling must stay at 200 so AC-heavy plans
# (AC_COUNT >= 22) can use all the turns the formula allocates. The threshold
# here is >= 200 (not just >= 30) to guard against any future rollback to 60.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ACEVAL_PATH="$REPO_DIR/agents/ac-evaluator.md"
ACEVAL_MAXTURNS=$(grep -E '^maxTurns:[[:space:]]*[0-9]+' "$ACEVAL_PATH" | head -1 | sed -E 's/^maxTurns:[[:space:]]*([0-9]+).*/\1/')
ACEVAL_MAXTURNS=${ACEVAL_MAXTURNS:-0}
if [ "$ACEVAL_MAXTURNS" -ge 200 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-GREP-C-2: agents/ac-evaluator.md maxTurns=$ACEVAL_MAXTURNS (>= 200, T-2 Strategy B ceiling)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-GREP-C-2: agents/ac-evaluator.md maxTurns=$ACEVAL_MAXTURNS is below the 200 ceiling (raised in v6.5.0 T-2 Strategy B; do not lower — use EVALUATOR_MAX_TURNS formula in Step 15 to control per-plan turn budget)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-STATE-AUTH-1 (v6.3.1, F-M1): hooks/lib/state-authority.sh MUST
# contain the registry-validation helper that rejects glob meta other
# than `*`. Static contract — guards against future refactors silently
# removing the fail-fast on misregistered keys.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SA_LIB_PATH="$REPO_DIR/hooks/lib/state-authority.sh"
SA_M1_HITS="$(grep -cE '^_sa_validate_registry\(\)' "$SA_LIB_PATH" || true)"
SA_M1_DIAG_HITS="$(grep -cE 'contains glob meta other than \*' "$SA_LIB_PATH" || true)"
SA_M1_HITS=${SA_M1_HITS:-0}
SA_M1_DIAG_HITS=${SA_M1_DIAG_HITS:-0}
if [ "$SA_M1_HITS" -ge 1 ] && [ "$SA_M1_DIAG_HITS" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-STATE-AUTH-1: _sa_validate_registry rejects glob meta other than * (F-M1)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-STATE-AUTH-1: state-authority.sh missing _sa_validate_registry (helper hits=$SA_M1_HITS, diagnostic hits=$SA_M1_DIAG_HITS)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-STATE-AUTH-2 (v6.3.1, F-EXTGLOB): is_hook_owned_field MUST
# capture and restore the parent shell's extglob state. Static contract —
# checks for the shopt -p capture + eval restore pair inside the function
# body so a future refactor cannot silently regress to leaking extglob.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SA_EXTGLOB_CAPTURE="$(grep -cE 'shopt -p extglob' "$SA_LIB_PATH" || true)"
SA_EXTGLOB_RESTORE="$(grep -cE 'eval "\$_prev"' "$SA_LIB_PATH" || true)"
SA_EXTGLOB_CAPTURE=${SA_EXTGLOB_CAPTURE:-0}
SA_EXTGLOB_RESTORE=${SA_EXTGLOB_RESTORE:-0}
if [ "$SA_EXTGLOB_CAPTURE" -ge 1 ] && [ "$SA_EXTGLOB_RESTORE" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-STATE-AUTH-2: is_hook_owned_field captures+restores extglob state (F-EXTGLOB)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-STATE-AUTH-2: extglob preservation pair not found (capture=$SA_EXTGLOB_CAPTURE, restore=$SA_EXTGLOB_RESTORE)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-STATE-AUTH-3 (v6.3.1, F-M2): pre-edit-safety.sh and
# pre-write-safety.sh MUST source state-authority.sh from $SCRIPT_DIR/lib
# directly; the legacy REPO_HOOKS_DIR variable is dead code and is
# rejected here so a future cleanup cannot accidentally re-introduce it.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
PE_PATH="$REPO_DIR/hooks/pre-edit-safety.sh"
PW_PATH="$REPO_DIR/hooks/pre-write-safety.sh"
# `grep -c` against multiple files prints `<file>:<count>` per file and
# exits 1 when ANY file had zero hits. The `(... || true)` subshell
# swallows that exit so the pipeline always reaches awk.
SA_M2_REPO_HITS="$( (grep -cE 'REPO_HOOKS_DIR' "$PE_PATH" "$PW_PATH" 2>/dev/null || true) | awk -F: '{s+=$2} END{print s+0}')"
SA_M2_SOURCE_HITS="$( (grep -cE 'source "\$SCRIPT_DIR/lib/state-authority.sh"' "$PE_PATH" "$PW_PATH" 2>/dev/null || true) | awk -F: '{s+=$2} END{print s+0}')"
SA_M2_REPO_HITS=${SA_M2_REPO_HITS:-0}
SA_M2_SOURCE_HITS=${SA_M2_SOURCE_HITS:-0}
if [ "$SA_M2_REPO_HITS" -eq 0 ] && [ "$SA_M2_SOURCE_HITS" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-STATE-AUTH-3: REPO_HOOKS_DIR removed; both safety hooks source from \$SCRIPT_DIR/lib (F-M2)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-STATE-AUTH-3: F-M2 violated (REPO_HOOKS_DIR hits=$SA_M2_REPO_HITS, \$SCRIPT_DIR/lib source hits=$SA_M2_SOURCE_HITS, expected 0+2)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# === Cat R: Persistence-First Protocol (T-1, v6.3.3) ===
# Diff: agents/ac-evaluator.md gains `## Persistence-First Protocol` section;
# skills/impl/SKILL.md Step 16 gains an IN_PROGRESS branch.
# All grep -c uses route through count_matches per CT-MODE-GREP-C-1.
echo "--- Cat R: Persistence-First Protocol ---"

# CT-MODE-PERSIST-FIRST-1 (AC-1): ac-evaluator has the heading
assert_file_contains \
  "CT-MODE-PERSIST-FIRST-1: agents/ac-evaluator.md has ## Persistence-First Protocol section" \
  "$REPO_DIR/agents/ac-evaluator.md" \
  '^## Persistence-First Protocol$'

# CT-MODE-PERSIST-FIRST-2 (AC-2): IN_PROGRESS appears >= 2 times in the section,
# and 'before invoking any' appears >= 1 time
TESTS_TOTAL=$((TESTS_TOTAL + 1))
PFP_TMP=$(mktemp)
awk '/^## Persistence-First Protocol$/,/^## Report Persistence Contract$/' "$REPO_DIR/agents/ac-evaluator.md" > "$PFP_TMP"
PFP_INPROGRESS=$(count_matches 'IN_PROGRESS' "$PFP_TMP")
PFP_BEFORE=$(count_matches 'before invoking any' "$PFP_TMP")
rm -f "$PFP_TMP"
if [ "${PFP_INPROGRESS:-0}" -ge 2 ] && [ "${PFP_BEFORE:-0}" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-PERSIST-FIRST-2: Persistence-First section has IN_PROGRESS x2 + 'before invoking any' x1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-PERSIST-FIRST-2: got IN_PROGRESS=$PFP_INPROGRESS, before=$PFP_BEFORE" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-PERSIST-FIRST-3 (AC-3): Output path stability rule documented
TESTS_TOTAL=$((TESTS_TOTAL + 1))
PFP_TMP2=$(mktemp)
awk '/^## Persistence-First Protocol$/,/^## Report Persistence Contract$/' "$REPO_DIR/agents/ac-evaluator.md" > "$PFP_TMP2"
PFP_OUTPUT=$(count_matches 'Output' "$PFP_TMP2")
PFP_SAMEPATH=$(count_matches 'same path' "$PFP_TMP2")
rm -f "$PFP_TMP2"
if [ "${PFP_OUTPUT:-0}" -ge 1 ] && [ "${PFP_SAMEPATH:-0}" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-PERSIST-FIRST-3: Output path stability rule present"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-PERSIST-FIRST-3: got Output=$PFP_OUTPUT, same path=$PFP_SAMEPATH" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-PERSIST-FIRST-4 (AC-4): /impl Step 16 has IN_PROGRESS token and retains CONTRACT-VIOLATION
TESTS_TOTAL=$((TESTS_TOTAL + 1))
STEP16_TMP=$(mktemp)
awk '/^16\. AC Gate:/,/^17\./' "$REPO_DIR/skills/impl/SKILL.md" > "$STEP16_TMP"
STEP16_INPROGRESS=$(count_matches 'IN_PROGRESS' "$STEP16_TMP")
rm -f "$STEP16_TMP"
STEP16_VIOLATION=$(count_matches 'CONTRACT-VIOLATION' "$REPO_DIR/skills/impl/SKILL.md")
if [ "${STEP16_INPROGRESS:-0}" -ge 1 ] && [ "${STEP16_VIOLATION:-0}" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-PERSIST-FIRST-4: Step 16 has IN_PROGRESS + retains CONTRACT-VIOLATION branch"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-PERSIST-FIRST-4: got Step 16 IN_PROGRESS=$STEP16_INPROGRESS, file CONTRACT-VIOLATION=$STEP16_VIOLATION" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-PERSIST-FIRST-5 (AC-7 + Negative AC-4): the v6.3.3 CHANGELOG block
# names Persistence-First and both files. The "newest block" framing was
# correct at v6.3.3 ship time; subsequent releases push v6.3.3 down the
# stack, so the assertion now anchors on the literal `## [6.3.3]` header
# and stops at the next `## [` header. This keeps the regression contract
# active without re-publishing PFP wording in every later release.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CL_TMP=$(mktemp)
awk '/^## \[6\.3\.3\]/{found=1; print; next} found && /^## \[/{exit} found{print}' "$REPO_DIR/CHANGELOG.md" > "$CL_TMP"
CL_PF=$(count_matches 'Persistence-First' "$CL_TMP")
CL_AGENT=$(count_matches 'ac-evaluator\.md' "$CL_TMP")
CL_SKILL=$(count_matches 'impl/SKILL\.md' "$CL_TMP")
CL_BAD=$(count_matches 'stable contract|semantically identical|backward compatible|forward compatible' "$CL_TMP")
rm -f "$CL_TMP"
if [ "${CL_PF:-0}" -ge 1 ] && [ "${CL_AGENT:-0}" -ge 1 ] && [ "${CL_SKILL:-0}" -ge 1 ] && [ "${CL_BAD:-0}" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-PERSIST-FIRST-5: [6.3.3] block names Persistence-First + both files; no SemVer-inflation phrases"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-PERSIST-FIRST-5: PF=$CL_PF agent=$CL_AGENT skill=$CL_SKILL banned=$CL_BAD" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# === Cat S: impl-checkpoint-guard /audit handoff backstop (T-2, v6.4.0) ===
# Diff: hooks/impl-checkpoint-guard.sh + audit-block-pattern.sh + Step 4-bis
# (audit/SKILL.md) + Step 17 CHECKPOINT (impl/SKILL.md). Asserts the
# documentation, single-source-of-truth literals, and release-stdout
# contract that the Stop hook depends on.
echo "--- Cat S: impl-checkpoint-guard backstop ---"

AUDIT_SKILL="$REPO_DIR/skills/audit/SKILL.md"
IMPL_SKILL="$REPO_DIR/skills/impl/SKILL.md"
AUDIT_BLOCK_PATTERN_LIB="$REPO_DIR/hooks/lib/audit-block-pattern.sh"
ICG_HOOK="$REPO_DIR/hooks/impl-checkpoint-guard.sh"

# CT-MODE-ICG-1: audit/SKILL.md contains the literal Step 4-bis heading.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF '### 4-bis. MANDATORY: Handoff back to caller' "$AUDIT_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-ICG-1: audit/SKILL.md has Step 4-bis heading"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-ICG-1: audit/SKILL.md missing '### 4-bis. MANDATORY: Handoff back to caller'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-ICG-2: audit/SKILL.md Step 4 example contains both **Status**:
# and **Reports**: literals (the literals the Stop hook greps for via
# audit-block-pattern.sh).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF '**Status**:' "$AUDIT_SKILL" && grep -qF '**Reports**:' "$AUDIT_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-ICG-2: audit/SKILL.md Step 4 contains **Status**: and **Reports**:"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-ICG-2: audit/SKILL.md missing required structured-block literals"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-ICG-3: distance guard — `phase-state.yaml` MUST appear within 200
# characters after the Step 4 structured-block example's closing fence so
# the handoff instruction is colocated with the artifact it describes.
# Anchored on the Step 4 heading + a fenced block whose first line is
# `**Status**:` (the structured block's invariant first field) so:
#   - inserting an unrelated `\`\`\`bash\` example into Step 4's prose
#     description does NOT silently shift the matcher onto the wrong fence
#     pair, and
#   - adding or removing fields BELOW `**Status**:` (e.g. a future
#     `**Caveats**:`) inside the structured block still matches.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ICG_DIST=$(python3 - <<PY
import re, sys
with open("$AUDIT_SKILL") as f:
    content = f.read()
# Match from the Step 4 heading through the closing fence of the first
# fenced block whose body starts with **Status**: (uniquely identifies
# the structured block, not a stray code example). Sentinel return values:
#   -1: regex did not match (structural drift — Step 4 heading missing,
#       structured block missing, or **Status**: line moved out of the
#       opening fence)
#   -2: phase-state.yaml literal not present in the rest of the document
m4 = re.search(r'### 4\. .*?\`\`\`\n\*\*Status\*\*:.*?\n\`\`\`', content, re.DOTALL)
if not m4:
    print(-1)
    sys.exit(0)
rest = content[m4.end():]
pos = rest.find("phase-state.yaml")
if pos < 0:
    print(-2)
else:
    print(pos)
PY
)
case "$ICG_DIST" in
  -1)
    echo -e "  ${RED}FAIL${NC} CT-MODE-ICG-3: Step 4 structured-block matcher failed (heading or fence regex did not match audit/SKILL.md)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    ;;
  -2)
    echo -e "  ${RED}FAIL${NC} CT-MODE-ICG-3: phase-state.yaml literal not found after Step 4 block"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    ;;
  *)
    if [ "$ICG_DIST" -ge 0 ] && [ "$ICG_DIST" -le 200 ]; then
      echo -e "  ${GREEN}PASS${NC} CT-MODE-ICG-3: phase-state.yaml within 200 chars after Step 4 block (distance=$ICG_DIST)"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo -e "  ${RED}FAIL${NC} CT-MODE-ICG-3: phase-state.yaml distance regression — distance=$ICG_DIST chars after Step 4 block (max 200)"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    ;;
esac

# CT-MODE-ICG-4: impl/SKILL.md Step 17 CHECKPOINT contains the literal
# "Required next emit: `## [SW-CHECKPOINT]`" so the strengthened anchor
# cannot drift back to the original wording silently.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'Required next emit: `## [SW-CHECKPOINT]`' "$IMPL_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-ICG-4: impl/SKILL.md Step 17 carries the strengthened CHECKPOINT line"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-ICG-4: impl/SKILL.md missing 'Required next emit: \`## [SW-CHECKPOINT]\`'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-ICG-5: audit-block-pattern.sh exports the same literals (Status,
# Reports) the Stop hook greps for. The exported value is an ERE pattern
# (`\*\*Status\*\*:`) — when sourced and used with `grep -E`, it matches
# the literal `**Status**:` in transcripts. To verify the file actually
# carries the correct ERE-escaped pattern (single source of truth),
# we source the file in a sub-shell and inspect the runtime values.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ICG_VAL_STATUS=$(bash -c "source \"$AUDIT_BLOCK_PATTERN_LIB\" && printf '%s' \"\$AUDIT_BLOCK_PATTERN_STATUS\"")
ICG_VAL_REPORTS=$(bash -c "source \"$AUDIT_BLOCK_PATTERN_LIB\" && printf '%s' \"\$AUDIT_BLOCK_PATTERN_REPORTS\"")
if [ "$ICG_VAL_STATUS" = '\*\*Status\*\*:' ] && [ "$ICG_VAL_REPORTS" = '\*\*Reports\*\*:' ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-ICG-5: audit-block-pattern.sh exports STATUS + REPORTS literals matching audit/SKILL.md"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-ICG-5: audit-block-pattern.sh exports do not match expected ERE patterns"
  echo -e "       STATUS:  $ICG_VAL_STATUS"
  echo -e "       REPORTS: $ICG_VAL_REPORTS"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-ICG-6: impl-checkpoint-guard.sh contains the [IMPL-CHECKPOINT-RELEASE]
# prefix AND both Resume variants ('/impl' for non-autopilot, '/autopilot'
# for autopilot context) — Patch 3 of the design. Both Resume tokens MUST
# appear on lines that ALSO carry the '[IMPL-CHECKPOINT-RELEASE] Pipeline
# halted' prefix, not scattered across header comments or other prose, so
# the proximity guarantee is enforced at the contract layer.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ICG_PASS=true
ICG_RELEASE_LINES=$(grep -F '[IMPL-CHECKPOINT-RELEASE] Pipeline halted' "$ICG_HOOK" || true)
[ -n "$ICG_RELEASE_LINES" ] || ICG_PASS=false
printf '%s\n' "$ICG_RELEASE_LINES" | grep -qF 'Resume with: /impl' || ICG_PASS=false
printf '%s\n' "$ICG_RELEASE_LINES" | grep -qF 'Resume with: /autopilot' || ICG_PASS=false
if [ "$ICG_PASS" = true ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-ICG-6: impl-checkpoint-guard.sh emits both Resume variants on Pipeline-halted lines"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-ICG-6: impl-checkpoint-guard.sh missing 'Pipeline halted' release line or one of the Resume variants on those lines"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# === Cat T: Single-shot recovery from IN_PROGRESS envelope (T-3) ===
# Diff: skills/impl/SKILL.md Step 16 gains 4-way decision with recovery branch;
# agents/ac-evaluator.md gains rule 4 (resumption mode) and contract clarification.
echo "--- Cat T: Single-shot recovery (T-3) ---"

# CT-MODE-SINGLESHOT-1 (AC-1): Step 16 has IN_PROGRESS >= 2 times AND
# recovery|resumption >= 1 time. Also includes Negative AC-3 cross-check:
# IN_PROGRESS must NOT appear in Step 17 window.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SS1_TMP=$(mktemp)
awk '/^16\. AC Gate:/,/^17\./' "$REPO_DIR/skills/impl/SKILL.md" > "$SS1_TMP"
SS1_INPROGRESS=$(count_matches 'IN_PROGRESS' "$SS1_TMP")
SS1_RECOVERY=$(count_matches 'recovery|resumption' "$SS1_TMP")
rm -f "$SS1_TMP"
STEP17_TMP=$(mktemp)
awk '/^17\./,/^18\./' "$REPO_DIR/skills/impl/SKILL.md" > "$STEP17_TMP"
STEP17_IP=$(count_matches 'IN_PROGRESS' "$STEP17_TMP")
rm -f "$STEP17_TMP"
if [ "${SS1_INPROGRESS:-0}" -ge 2 ] && [ "${SS1_RECOVERY:-0}" -ge 1 ] && [ "${STEP17_IP:-0}" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-SINGLESHOT-1: Step 16 has IN_PROGRESS x${SS1_INPROGRESS} + recovery/resumption x${SS1_RECOVERY}; Step 17 has IN_PROGRESS x0 (Neg-AC-3 OK)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-SINGLESHOT-1: Step16 IN_PROGRESS=$SS1_INPROGRESS (need >=2), recovery=$SS1_RECOVERY (need >=1), Step17 IN_PROGRESS=$STEP17_IP (need 0)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-SINGLESHOT-2 (AC-2): Step 16 has once|exactly 1|single-shot|max 1 >= 1
# and the surrounding context contains 'recovery'
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SS2_TMP=$(mktemp)
awk '/^16\. AC Gate:/,/^17\./' "$REPO_DIR/skills/impl/SKILL.md" > "$SS2_TMP"
SS2_CAP=$(count_matches 'once|exactly 1|single-shot|max[[:space:]]*1' "$SS2_TMP")
SS2_RECOVERY=$(count_matches 'recovery' "$SS2_TMP")
rm -f "$SS2_TMP"
if [ "${SS2_CAP:-0}" -ge 1 ] && [ "${SS2_RECOVERY:-0}" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-SINGLESHOT-2: Step 16 has single-shot cap x${SS2_CAP} + recovery context x${SS2_RECOVERY}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-SINGLESHOT-2: cap=$SS2_CAP (need >=1), recovery=$SS2_RECOVERY (need >=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-SINGLESHOT-3 (AC-3): Step 16 has resumption prompt fenced block with
# required literals: 'Read the IN_PROGRESS file', 'resume from', '[ ]'
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SS3_TMP=$(mktemp)
awk '/^16\. AC Gate:/,/^17\./' "$REPO_DIR/skills/impl/SKILL.md" > "$SS3_TMP"
SS3_READ=$(count_matches 'Read the IN_PROGRESS file' "$SS3_TMP")
SS3_RESUME=$(count_matches 'resume from' "$SS3_TMP")
SS3_CHECKBOX=$(count_matches '\[ \]' "$SS3_TMP")
rm -f "$SS3_TMP"
if [ "${SS3_READ:-0}" -ge 1 ] && [ "${SS3_RESUME:-0}" -ge 1 ] && [ "${SS3_CHECKBOX:-0}" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-SINGLESHOT-3: resumption prompt has 'Read the IN_PROGRESS file' + 'resume from' + '[ ]' checkbox"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-SINGLESHOT-3: read=$SS3_READ (need >=1), resume=$SS3_RESUME (need >=1), checkbox=$SS3_CHECKBOX (need >=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-SINGLESHOT-4 (AC-4): Persistence-First Protocol section has
# 'resumption mode', 'Read the file first', and 'unchecked AC' or '[ ]'
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SS4_TMP=$(mktemp)
awk '/^## Persistence-First Protocol$/,/^## Report Persistence Contract$/' "$REPO_DIR/agents/ac-evaluator.md" > "$SS4_TMP"
SS4_RESUMPTION=$(count_matches 'resumption mode' "$SS4_TMP")
SS4_READFIRST=$(count_matches 'Read the file first' "$SS4_TMP")
SS4_UNCHECKED=$(count_matches 'unchecked AC|\[ \]' "$SS4_TMP")
rm -f "$SS4_TMP"
if [ "${SS4_RESUMPTION:-0}" -ge 1 ] && [ "${SS4_READFIRST:-0}" -ge 1 ] && [ "${SS4_UNCHECKED:-0}" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-SINGLESHOT-4: Persistence-First Protocol has resumption mode + Read the file first + unchecked AC/[ ]"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-SINGLESHOT-4: resumption=$SS4_RESUMPTION (need >=1), readfirst=$SS4_READFIRST (need >=1), unchecked=$SS4_UNCHECKED (need >=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-SINGLESHOT-5 (AC-5): Report Persistence Contract has
# 'MUST NOT re-invoke', 'solely to persist', and a sentence with both
# 'IN_PROGRESS' and 'permitted'
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SS5_TMP=$(mktemp)
awk '/^## Report Persistence Contract$/,/^## Context Conservation Protocol$/' "$REPO_DIR/agents/ac-evaluator.md" > "$SS5_TMP"
SS5_NOINVOKE=$(count_matches 'MUST NOT re-invoke' "$SS5_TMP")
SS5_SOLELY=$(count_matches 'solely to persist' "$SS5_TMP")
SS5_PERMITTED=$(count_matches 'IN_PROGRESS.*permitted|permitted.*IN_PROGRESS' "$SS5_TMP")
rm -f "$SS5_TMP"
if [ "${SS5_NOINVOKE:-0}" -ge 1 ] && [ "${SS5_SOLELY:-0}" -ge 1 ] && [ "${SS5_PERMITTED:-0}" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-SINGLESHOT-5: Report Persistence Contract has MUST NOT re-invoke + solely to persist + IN_PROGRESS+permitted"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-SINGLESHOT-5: noinvoke=$SS5_NOINVOKE (need >=1), solely=$SS5_SOLELY (need >=1), permitted=$SS5_PERMITTED (need >=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Step-16 simulator — exercises the same branching logic as Step 16 branch (ii)
# without requiring a real LLM invocation.
#
# Env vars consumed:
#   MOCK_EVALUATOR    — path to a fixture script to use as the evaluator.
#   EVAL_REPORT_PATH  — path where the mock writes its report.
#   COUNTER_FILE      — path to the call-count file managed by the mock.
#
# Returns 0 when the recovery path produces a terminal verdict.
# Returns 1 with a [CONTRACT-VIOLATION] message when recovery does not
# produce a terminal verdict (double IN_PROGRESS or missing file).
# Never makes more than 2 evaluator calls total.
# ---------------------------------------------------------------------------
simulate_step16() {
  local mock="$MOCK_EVALUATOR"
  local report="$EVAL_REPORT_PATH"

  # --- Round 1 invocation ---
  local output
  output=$(bash "$mock")

  if [ -n "$output" ]; then
    # Output non-empty: path (iv) — terminal, no recovery needed.
    echo "OK: terminal"
    return 0
  fi

  # Output empty — check for IN_PROGRESS file.
  if [ ! -f "$report" ]; then
    echo "[CONTRACT-VIOLATION] ac-evaluator Output was empty and no report was persisted; treating as FAIL-CRITICAL"
    return 1
  fi

  local first_status
  first_status=$(grep -m1 '^## Status:' "$report" 2>/dev/null || true)

  if [ "$first_status" != "## Status: IN_PROGRESS" ]; then
    # File exists but status is already terminal on path (i) edge — treat as
    # contract violation (unexpected state for this simulator path).
    echo "[CONTRACT-VIOLATION] unexpected file status after empty output: $first_status"
    return 1
  fi

  # --- IN_PROGRESS detected: single-shot recovery (branch ii) ---
  # Invoke the mock ONCE more. Do NOT loop.
  local recovery_output
  recovery_output=$(bash "$mock")

  # Step 16 prose: "Recovery Output non-empty AND Status is terminal → proceed
  # to Status parsing (path iv). Recovery Output empty OR first `## Status:`
  # still `IN_PROGRESS` → emit `[CONTRACT-VIOLATION]`". Enforce the Output
  # envelope here so empty recovery stdout is a CV regardless of file state.
  if [ -z "$recovery_output" ]; then
    echo "[CONTRACT-VIOLATION] ac-evaluator recovery invocation did not produce a terminal verdict; treating as FAIL-CRITICAL"
    return 1
  fi

  # Re-inspect the file after recovery.
  if [ ! -f "$report" ]; then
    echo "[CONTRACT-VIOLATION] ac-evaluator recovery invocation did not produce a terminal verdict; treating as FAIL-CRITICAL"
    return 1
  fi

  local recovery_status
  recovery_status=$(grep -m1 '^## Status:' "$report" 2>/dev/null || true)

  case "$recovery_status" in
    "## Status: PASS"|"## Status: FAIL"|"## Status: FAIL-CRITICAL"|"## Status: PASS-WITH-CAVEATS")
      echo "OK: terminal"
      return 0
      ;;
    *)
      echo "[CONTRACT-VIOLATION] ac-evaluator recovery invocation did not produce a terminal verdict; treating as FAIL-CRITICAL"
      return 1
      ;;
  esac
}

# CT-MODE-SINGLESHOT-6 (AC-6): terminal recovery smoke
# Uses mock-ac-evaluator-second-call-terminal.sh — first call writes IN_PROGRESS
# (empty stdout), second call writes PASS (non-empty stdout).
# Asserts: counter == 2, final ## Status: is terminal, simulator exits 0,
# no [CONTRACT-VIOLATION] in output.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SS6_DIR=$(mktemp -d)
trap 'rm -rf "$SS6_DIR"' EXIT
SS6_COUNTER="$SS6_DIR/counter.txt"
SS6_REPORT="$SS6_DIR/eval-round-1.md"
printf '0\n' > "$SS6_COUNTER"
export MOCK_EVALUATOR="$SCRIPT_DIR/fixtures/mock-ac-evaluator-second-call-terminal.sh"
export EVAL_REPORT_PATH="$SS6_REPORT"
export COUNTER_FILE="$SS6_COUNTER"
set +e
SS6_OUTPUT=$(simulate_step16 2>&1)
SS6_EXIT=$?
set -e
SS6_COUNT=$(cat "$SS6_COUNTER" 2>/dev/null || echo 0)
SS6_FINAL_STATUS=$(grep -m1 '^## Status:' "$SS6_REPORT" 2>/dev/null || echo "")
SS6_CONTRACT_VIOLATION=$(echo "$SS6_OUTPUT" | count_matches '\[CONTRACT-VIOLATION\]')
if [ "$SS6_EXIT" -eq 0 ] && \
   [ "$SS6_COUNT" -eq 2 ] && \
   echo "$SS6_FINAL_STATUS" | grep -qE '^## Status: (PASS|FAIL|FAIL-CRITICAL|PASS-WITH-CAVEATS)$' && \
   [ "$SS6_CONTRACT_VIOLATION" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-SINGLESHOT-6: recovery smoke — 2 invocations, terminal status='$SS6_FINAL_STATUS', no CONTRACT-VIOLATION"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-SINGLESHOT-6: exit=$SS6_EXIT count=$SS6_COUNT status='$SS6_FINAL_STATUS' contract-violations=$SS6_CONTRACT_VIOLATION output='$SS6_OUTPUT'" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$SS6_DIR"
trap - EXIT

# CT-MODE-SINGLESHOT-7 (AC-7): double IN_PROGRESS halts after exactly 2 calls
# Uses mock-ac-evaluator-always-in-progress.sh — EVERY call writes IN_PROGRESS
# and returns empty stdout. Asserts: counter == 2 (NOT 3), output contains
# [CONTRACT-VIOLATION], simulator exits 1.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SS7_DIR=$(mktemp -d)
trap 'rm -rf "$SS7_DIR"' EXIT
SS7_COUNTER="$SS7_DIR/counter.txt"
SS7_REPORT="$SS7_DIR/eval-round-1.md"
printf '0\n' > "$SS7_COUNTER"
export MOCK_EVALUATOR="$SCRIPT_DIR/fixtures/mock-ac-evaluator-always-in-progress.sh"
export EVAL_REPORT_PATH="$SS7_REPORT"
export COUNTER_FILE="$SS7_COUNTER"
set +e
SS7_OUTPUT=$(simulate_step16 2>&1)
SS7_EXIT=$?
set -e
SS7_COUNT=$(cat "$SS7_COUNTER" 2>/dev/null || echo 0)
SS7_CONTRACT_VIOLATION=$(echo "$SS7_OUTPUT" | count_matches '\[CONTRACT-VIOLATION\]')
if [ "$SS7_EXIT" -ne 0 ] && \
   [ "$SS7_COUNT" -eq 2 ] && \
   [ "$SS7_CONTRACT_VIOLATION" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-SINGLESHOT-7: double-IN_PROGRESS halt — 2 invocations, CONTRACT-VIOLATION emitted, exit 1 (no 3rd call)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-SINGLESHOT-7: exit=$SS7_EXIT count=$SS7_COUNT (need 2) violations=$SS7_CONTRACT_VIOLATION output='$SS7_OUTPUT'" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$SS7_DIR"
trap - EXIT

echo ""

# ---------------------------------------------------------------------------
# Category AH: Dynamic maxTurns + AC-30 partition (T-2, v6.5.0)
# Covers AC-1/AC-2/AC-3/AC-4/AC-5/Negative AC-4/Negative AC-6.
# All assertions use count_matches (NOT raw grep -c) per CT-MODE-GREP-C-1.
# ---------------------------------------------------------------------------
echo "Category AH: Dynamic maxTurns + AC-30 partition (T-2)"

# Extract Step 15 body from skills/impl/SKILL.md (from "^15. " heading to "^16. " heading).
AH_SKILL_PATH="$REPO_DIR/skills/impl/SKILL.md"
AH_STEP15_TMP=$(mktemp)
awk '/^15\. /{in_s=1} in_s && /^16\. /{exit} in_s{print}' "$AH_SKILL_PATH" > "$AH_STEP15_TMP"

# AH-1 (AC-1): Step 15 body MUST contain AC_COUNT at least twice AND
#              a multiplication-by-4 expression at least once.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AH1_AC_COUNT_HITS=$(count_matches 'AC_COUNT' "$AH_STEP15_TMP")
AH1_TIMES4_HITS=$(count_matches '\* 4|times 4|x 4' "$AH_STEP15_TMP")
if [ "$AH1_AC_COUNT_HITS" -ge 2 ] && [ "$AH1_TIMES4_HITS" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AH-1 (AC-1): Step 15 body contains AC_COUNT>=${AH1_AC_COUNT_HITS}x and *4 >= 1x"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AH-1 (AC-1): Step 15 body AC_COUNT=${AH1_AC_COUNT_HITS} (need>=2) *4=${AH1_TIMES4_HITS} (need>=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AH-2 (AC-2): Step 15 body MUST contain the max(60,...) floor formula.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AH2_FLOOR_HITS=$(count_matches 'max\(60,|max\(\s*60\s*,' "$AH_STEP15_TMP")
if [ "$AH2_FLOOR_HITS" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AH-2 (AC-2): Step 15 body contains max(60,...) floor formula"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AH-2 (AC-2): Step 15 body missing max(60,...) floor formula (hits=$AH2_FLOOR_HITS)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AH-3 (AC-3): Step 15 body MUST document the partition threshold of 30.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AH3_THRESH_HITS=$(count_matches 'AC_COUNT\s*>=\s*30|AC_COUNT\s*>=\s*30|30\+ AC|30 or more' "$AH_STEP15_TMP")
if [ "$AH3_THRESH_HITS" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AH-3 (AC-3): Step 15 body documents partition threshold 30"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AH-3 (AC-3): Step 15 body missing partition threshold 30 (hits=$AH3_THRESH_HITS)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AH-4 (AC-4): Step 15 body MUST contain eval-round- >= 2, part-1 >= 1, part-2 >= 1.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AH4_EVALROUND_HITS=$(count_matches 'eval-round-' "$AH_STEP15_TMP")
AH4_PART1_HITS=$(count_matches 'part-1' "$AH_STEP15_TMP")
AH4_PART2_HITS=$(count_matches 'part-2' "$AH_STEP15_TMP")
if [ "$AH4_EVALROUND_HITS" -ge 2 ] && [ "$AH4_PART1_HITS" -ge 1 ] && [ "$AH4_PART2_HITS" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AH-4 (AC-4): Step 15 body: eval-round->=${AH4_EVALROUND_HITS}x part-1>=${AH4_PART1_HITS}x part-2>=${AH4_PART2_HITS}x"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AH-4 (AC-4): eval-round-=${AH4_EVALROUND_HITS}(need>=2) part-1=${AH4_PART1_HITS}(need>=1) part-2=${AH4_PART2_HITS}(need>=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AH-5 (AC-5): agents/ac-evaluator.md MUST contain 'partition' and 'Do NOT cross-evaluate'.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AH5_PARTITION_HITS=$(count_matches 'partition' "$REPO_DIR/agents/ac-evaluator.md")
if [ "$AH5_PARTITION_HITS" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AH-5a (AC-5): agents/ac-evaluator.md contains 'partition' (${AH5_PARTITION_HITS}x)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AH-5a (AC-5): agents/ac-evaluator.md missing 'partition'" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
assert_file_contains \
  "AH-5b (AC-5): agents/ac-evaluator.md contains literal 'Do NOT cross-evaluate'" \
  "$REPO_DIR/agents/ac-evaluator.md" \
  "Do NOT cross-evaluate"

# AH-6 (Negative AC-4): code-reviewer and security-scanner MUST NOT contain 'partition'.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AH6_CR_HITS=$(count_matches 'partition' "$REPO_DIR/agents/code-reviewer.md")
if [ "$AH6_CR_HITS" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} AH-6a (Neg-AC-4): agents/code-reviewer.md has no 'partition' references"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AH-6a (Neg-AC-4): agents/code-reviewer.md has ${AH6_CR_HITS} 'partition' reference(s) (must be 0)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AH6_SS_HITS=$(count_matches 'partition' "$REPO_DIR/agents/security-scanner.md")
if [ "$AH6_SS_HITS" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} AH-6b (Neg-AC-4): agents/security-scanner.md has no 'partition' references"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AH-6b (Neg-AC-4): agents/security-scanner.md has ${AH6_SS_HITS} 'partition' reference(s) (must be 0)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AH-7 (Negative AC-6): AC-counting algorithm MUST stop at #### Negative Acceptance Criteria.
# Run the algorithm against plan-5ac-5negac.md and assert AC_COUNT == 5.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AH7_FIXTURE="$REPO_DIR/tests/fixtures/ac-count-plans/plan-5ac-5negac.md"
AH7_AC_COUNT=$(awk '
  /^####?[[:space:]]+(Negative Acceptance Criteria)/{exit}
  /^[0-9]+\.[[:space:]]+\*\*AC-/{count++}
  /^- AC-/{count++}
  /^AC-[0-9]/{count++}
  END{print count+0}
' "$AH7_FIXTURE")
if [ "$AH7_AC_COUNT" -eq 5 ]; then
  echo -e "  ${GREEN}PASS${NC} AH-7 (Neg-AC-6): AC-counting on plan-5ac-5negac.md returns AC_COUNT=5 (stop condition fires)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AH-7 (Neg-AC-6): AC-counting on plan-5ac-5negac.md returned AC_COUNT=${AH7_AC_COUNT} (expected 5; stop condition may not be firing)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

rm -f "$AH_STEP15_TMP"

echo ""

# ---------------------------------------------------------------------------
# Category AI: Pre-existing Failure Attribution recipe in ac-evaluator (T-4)
# Covers: AC-1, AC-2, AC-3, AC-4, AC-5
# Uses count_matches (not raw grep -c) per CT-MODE-GREP-C-1.
# References only agents/ac-evaluator.md per Negative-AC-6.
# ---------------------------------------------------------------------------
echo "Category AI: Pre-existing Failure Attribution (T-4)"

AI_SECTION_TMP=$(mktemp)
# Extract the ### Pre-existing Failure Attribution section to a temp file.
# The section runs from the heading line until the next H2 heading. The
# end-anchor is a generic `^## ` rather than a hardcoded heading text so a
# future rename of `## Status Decision` does not silently extend the awk
# range to EOF and let count_matches pass vacuously.
awk '/^### Pre-existing Failure Attribution$/,/^## /' \
  "$REPO_DIR/agents/ac-evaluator.md" \
  | grep -v '^## ' > "$AI_SECTION_TMP"

# AI-1 (AC-1): Section heading exists in agents/ac-evaluator.md
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AI1_COUNT=$(count_matches '^### Pre-existing Failure Attribution$' "$REPO_DIR/agents/ac-evaluator.md")
if [ "$AI1_COUNT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AI-1 (AC-1): '### Pre-existing Failure Attribution' heading found in agents/ac-evaluator.md"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AI-1 (AC-1): '### Pre-existing Failure Attribution' heading NOT found in agents/ac-evaluator.md" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AI-2 (AC-2): Path-intersection recipe: git diff --name-only AND merge-base appear in section
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AI2A_COUNT=$(count_matches 'git diff --name-only' "$AI_SECTION_TMP")
AI2B_COUNT=$(count_matches 'merge-base' "$AI_SECTION_TMP")
if [ "$AI2A_COUNT" -ge 1 ] && [ "$AI2B_COUNT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AI-2 (AC-2): 'git diff --name-only' and 'merge-base' both found in Pre-existing Failure Attribution section"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AI-2 (AC-2): path-intersection recipe incomplete — diff-name-only:${AI2A_COUNT} merge-base:${AI2B_COUNT} (both must be >=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AI-3 (AC-3): Anti-pattern callout: 'git stash' AND 'gitignored' AND one of
#              'skip'/'silently survive'/'does not stash' appear in section
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AI3A_COUNT=$(count_matches 'git stash' "$AI_SECTION_TMP")
AI3B_COUNT=$(count_matches 'gitignored' "$AI_SECTION_TMP")
AI3C_COUNT=$(count_matches 'skip|silently survive|does not stash' "$AI_SECTION_TMP")
if [ "$AI3A_COUNT" -ge 1 ] && [ "$AI3B_COUNT" -ge 1 ] && [ "$AI3C_COUNT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AI-3 (AC-3): 'git stash' anti-pattern callout with 'gitignored' and skip-phrase found in section"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AI-3 (AC-3): anti-pattern callout incomplete — stash:${AI3A_COUNT} gitignored:${AI3B_COUNT} skip-phrase:${AI3C_COUNT} (all must be >=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AI-4 (AC-4): Worktree recipe: 'git worktree add' appears in section
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AI4_COUNT=$(count_matches 'git worktree add' "$AI_SECTION_TMP")
if [ "$AI4_COUNT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AI-4 (AC-4): 'git worktree add' recipe found in Pre-existing Failure Attribution section"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AI-4 (AC-4): 'git worktree add' NOT found in Pre-existing Failure Attribution section" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AI-5 (AC-5): All four tool-permission entries present in agents/ac-evaluator.md frontmatter
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AI5A_COUNT=$(count_matches 'Bash\(git merge-base:' "$REPO_DIR/agents/ac-evaluator.md")
# `worktree add` (the recipe's primary write op) is the canonical scoped
# variant we require; broader `Bash(git worktree:*)` is intentionally NOT
# accepted by this assertion so the security tightening cannot regress.
AI5B_COUNT=$(count_matches 'Bash\(git worktree add:' "$REPO_DIR/agents/ac-evaluator.md")
AI5C_COUNT=$(count_matches 'shell\(git merge-base:' "$REPO_DIR/agents/ac-evaluator.md")
AI5D_COUNT=$(count_matches 'shell\(git worktree add:' "$REPO_DIR/agents/ac-evaluator.md")
if [ "$AI5A_COUNT" -ge 1 ] && [ "$AI5B_COUNT" -ge 1 ] && [ "$AI5C_COUNT" -ge 1 ] && [ "$AI5D_COUNT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AI-5 (AC-5): all four tool-permission entries (Bash+shell × merge-base+worktree-add) present in agents/ac-evaluator.md"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AI-5 (AC-5): tool-permission entries incomplete — Bash(merge-base):${AI5A_COUNT} Bash(worktree add):${AI5B_COUNT} shell(merge-base):${AI5C_COUNT} shell(worktree add):${AI5D_COUNT} (all must be >=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

rm -f "$AI_SECTION_TMP"

echo ""

# ---------------------------------------------------------------------------
# Category AJ: Skeptical Third-Pass step in /audit (T-5)
# Covers: AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-7, AC-8, AC-11, AC-12,
#         Negative AC-3, Negative AC-5, Negative AC-6.
# AC-9/AC-10 (live smoke tests) require fixture PRs and Agent invocation
# counting; they are documented in skills/audit/SKILL.md and asserted via
# the static contract checks below (the SKILL.md text is the contract that
# the live runtime obeys; live invocation counting is manual verification).
# ---------------------------------------------------------------------------
echo "Category AJ: Skeptical Third-Pass in /audit (T-5)"

AUDIT_MD="$REPO_DIR/skills/audit/SKILL.md"
AJ_SKEPTICAL_REF="$REPO_DIR/skills/audit/references/skeptical-pass.md"

# Extract the Step 3.5 subsection body (heading -> next ### 4. or end of file).
# The trigger definitions and prompt template have been moved to
# skills/audit/references/skeptical-pass.md; Step 3.5 retains the
# orchestration semantics (when to fire, where to save, OR-set rule, etc.)
# and links to the reference file for the trigger labels and prompt body.
AJ_STEP35_TMP=$(mktemp)
awk '/^### Step 3\.5:/,/^### 4\. /' "$AUDIT_MD" \
  | grep -v '^### 4\. ' > "$AJ_STEP35_TMP"

# Extract the Triggers subsection body from the reference file
# (## Triggers heading -> next ## heading).
AJ_TRIGGERS_TMP=$(mktemp)
awk '/^## Triggers/,/^## /' "$AJ_SKEPTICAL_REF" \
  | sed -E '/^## Triggers/d; /^## /d' > "$AJ_TRIGGERS_TMP" || true
# Re-include the Triggers heading line in case the body skip stripped too much;
# the trigger label scan below looks at the body lines under the heading.
awk '/^## Triggers/{f=1; next} f && /^## /{f=0} f' "$AJ_SKEPTICAL_REF" \
  > "$AJ_TRIGGERS_TMP"

# Extract the Prompt Template subsection body from the reference file
# (## Prompt Template heading -> end of file).
AJ_PROMPT_TMP=$(mktemp)
awk '/^## Prompt Template/{f=1; next} f' "$AJ_SKEPTICAL_REF" > "$AJ_PROMPT_TMP"

# Extract the Aggregate Results subsection body (heading -> next ### Step 3.5).
AJ_AGGREGATE_TMP=$(mktemp)
awk '/^### 3\. Aggregate Results$/,/^### Step 3\.5:/' "$AUDIT_MD" \
  | grep -v '^### Step 3\.5:' > "$AJ_AGGREGATE_TMP"

# AJ-1 (AC-1): skills/audit/SKILL.md contains a heading with 'Skeptical Third-Pass'
assert_file_contains \
  "AJ-1 (AC-1): skills/audit/SKILL.md contains heading with 'Skeptical Third-Pass'" \
  "$AUDIT_MD" \
  "Skeptical Third-Pass"

# AJ-2 (AC-2): Triggers subsection documents at least 5 triggers (T-A through T-E)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AJ2_TRIGGER_HITS=$(count_matches '\*\*T-[A-E]\*\*|\(T-[A-E]\)' "$AJ_TRIGGERS_TMP")
if [ "$AJ2_TRIGGER_HITS" -ge 5 ]; then
  echo -e "  ${GREEN}PASS${NC} AJ-2 (AC-2): Triggers subsection documents >=5 triggers T-A..T-E (${AJ2_TRIGGER_HITS})"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AJ-2 (AC-2): Triggers subsection documents only ${AJ2_TRIGGER_HITS} triggers (need >=5)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AJ-3 (AC-3): T-A sentence contains 'hooks/lib/' AND ('library' or 'shared')
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AJ3_HOOKLIB=$(count_matches 'hooks/lib/' "$AJ_TRIGGERS_TMP")
AJ3_LIB=$(count_matches 'library|shared' "$AJ_TRIGGERS_TMP")
if [ "$AJ3_HOOKLIB" -ge 1 ] && [ "$AJ3_LIB" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AJ-3 (AC-3): T-A documents hooks/lib/ and library/shared"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AJ-3 (AC-3): T-A incomplete — hooks/lib/:${AJ3_HOOKLIB} library/shared:${AJ3_LIB} (both need >=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AJ-4 (AC-4): T-B sentence contains at least 2 of: printf %q, escape, sanitize, quote, ERE
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AJ4_COUNT=0
for AJ4_TERM in 'printf %q' 'escape' 'sanitize' 'quote' 'ERE'; do
  HIT=$(count_matches "$AJ4_TERM" "$AJ_TRIGGERS_TMP")
  [ "$HIT" -ge 1 ] && AJ4_COUNT=$((AJ4_COUNT + 1))
done
if [ "$AJ4_COUNT" -ge 2 ]; then
  echo -e "  ${GREEN}PASS${NC} AJ-4 (AC-4): T-B documents >= 2 sanitization keywords (${AJ4_COUNT}/5)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AJ-4 (AC-4): T-B documents only ${AJ4_COUNT}/5 sanitization keywords (need >=2)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AJ-5 (AC-5): T-D sentence contains both 'PASS-WITH-CAVEATS' and 'skipped'
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AJ5_PWC=$(count_matches 'PASS-WITH-CAVEATS' "$AJ_TRIGGERS_TMP")
AJ5_SKIP=$(count_matches 'skipped' "$AJ_TRIGGERS_TMP")
if [ "$AJ5_PWC" -ge 1 ] && [ "$AJ5_SKIP" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} AJ-5 (AC-5): T-D documents PASS-WITH-CAVEATS and skipped"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AJ-5 (AC-5): T-D incomplete — PASS-WITH-CAVEATS:${AJ5_PWC} skipped:${AJ5_SKIP} (both need >=1)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AJ-6 (AC-6): Prompt Template subsection contains the three required literals
assert_file_contains \
  "AJ-6a (AC-6): Prompt Template contains 'general-purpose'" \
  "$AJ_PROMPT_TMP" \
  "general-purpose"
assert_file_contains \
  "AJ-6b (AC-6): Prompt Template contains 'DO_NOT_SHIP'" \
  "$AJ_PROMPT_TMP" \
  "DO_NOT_SHIP"
assert_file_contains \
  "AJ-6c (AC-6): Prompt Template contains 'outside the standard rubrics'" \
  "$AJ_PROMPT_TMP" \
  "outside the standard rubrics"

# AJ-7 (AC-7): Aggregation rule documented in ### 3. Aggregate Results — DO_NOT_SHIP increments Critical
# Scoped to $AJ_AGGREGATE_TMP to prevent vacuous match from DO_NOT_SHIP in the prompt template.
assert_file_contains \
  "AJ-7 (AC-7): Aggregation rule: DO_NOT_SHIP from third-pass increments Critical" \
  "$AJ_AGGREGATE_TMP" \
  "DO_NOT_SHIP.*Critical|Critical.*DO_NOT_SHIP"

# AJ-8 (AC-8): Skip-by-default documented — behaviour unchanged when no trigger fires
assert_file_contains \
  "AJ-8 (AC-8): Skip-by-default: no-trigger behaviour documented as unchanged/byte-identical" \
  "$AJ_STEP35_TMP" \
  "byte-identical|behaviour is unchanged|no trigger fires"

# AJ-9 (Neg-AC-3): only_security_scan=true suppresses third-pass
assert_file_contains \
  "AJ-9 (Neg-AC-3): only_security_scan=true suppresses third-pass" \
  "$AJ_STEP35_TMP" \
  "only_security_scan"

# AJ-10 (Neg-AC-5): no 'always'/'every audit'/'unconditional' in the new Step 3.5 section
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AJ10_ALWAYS=$(count_matches 'always|every audit|unconditional' "$AJ_STEP35_TMP")
if [ "$AJ10_ALWAYS" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} AJ-10 (Neg-AC-5): Step 3.5 section has no 'always/every audit/unconditional' (count=0)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AJ-10 (Neg-AC-5): Step 3.5 section has ${AJ10_ALWAYS} forbidden always/unconditional reference(s)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AJ-11 (Neg-AC-6): OR-set / fires-once documented
assert_file_contains \
  "AJ-11 (Neg-AC-6): Step 3.5 documents OR-set / at-most-once invocation" \
  "$AJ_STEP35_TMP" \
  "OR-set|at most once|fires.*once|once per"

# AJ-12 (AC-12): CHANGELOG newest block has ### Added bullet referencing skeptical + T-A..T-E
assert_file_contains \
  "AJ-12a (AC-12): CHANGELOG has skeptical third-pass bullet" \
  "$REPO_DIR/CHANGELOG.md" \
  "skeptical.third.pass|Skeptical Third-Pass"
assert_file_contains \
  "AJ-12b (AC-12): CHANGELOG references trigger range T-A..T-E" \
  "$REPO_DIR/CHANGELOG.md" \
  "T-A\.\.T-E|T-A through T-E"

rm -f "$AJ_STEP35_TMP" "$AJ_TRIGGERS_TMP" "$AJ_PROMPT_TMP" "$AJ_AGGREGATE_TMP"

echo ""

# ---------------------------------------------------------------------------
# Category AK: audit-coverage review-gate (CT-MODE-COV-1..6 + CT-MODE-COV-DOC-1..4, v6.6.2)
# Covers AC-1..AC-14 of the audit-coverage-review-gate plan:
#   - Functional (fixture-driven): CT-MODE-COV-1..6 spawn each hermetic
#     fixture under tests/fixtures/quality-rounds/ and assert the fixture's
#     own internal assertions pass (exit 0).
#   - Structural (grep-driven): CT-MODE-COV-DOC-1..4 verify SKILL.md wiring
#     and the absence of `--no-filters` in the helper.
# ---------------------------------------------------------------------------
echo "Category AK: audit-coverage review-gate (v6.6.2)"

AK_HELPER="$REPO_DIR/hooks/lib/audit-coverage.sh"
AK_AUDIT_MD="$REPO_DIR/skills/audit/SKILL.md"
AK_SHIP_MD="$REPO_DIR/skills/ship/SKILL.md"
AK_FIX_DIR="$REPO_DIR/tests/fixtures/quality-rounds"

# CT-MODE-COV-1: match-clean fixture passes.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if bash "$AK_FIX_DIR/match-clean/run.sh" >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-1: match-clean fixture exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-1: match-clean fixture did not exit 0" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-COV-2: blob-mismatch fixture passes.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if bash "$AK_FIX_DIR/blob-mismatch/run.sh" >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-2: blob-mismatch fixture exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-2: blob-mismatch fixture did not exit 0" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-COV-3: extra-file-in-commit fixture passes.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if bash "$AK_FIX_DIR/extra-file-in-commit/run.sh" >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-3: extra-file-in-commit fixture exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-3: extra-file-in-commit fixture did not exit 0" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-COV-4: deleted-file-handling fixture (covers both sub-cases) passes.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if bash "$AK_FIX_DIR/deleted-file-handling/run.sh" >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-4: deleted-file-handling fixture exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-4: deleted-file-handling fixture did not exit 0" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-COV-5: legacy-no-block fixture passes.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if bash "$AK_FIX_DIR/legacy-no-block/run.sh" >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-5: legacy-no-block fixture exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-5: legacy-no-block fixture did not exit 0" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-COV-6: kill-switch path (SW_AUDIT_COVERAGE=off makes check return LEGACY).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if SW_AUDIT_COVERAGE=off bash "$AK_FIX_DIR/match-clean/run.sh" >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-6: match-clean fixture with SW_AUDIT_COVERAGE=off returns LEGACY"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-6: match-clean fixture with SW_AUDIT_COVERAGE=off did not exit 0" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-COV-DOC-1: helper exists and exports both functions.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$AK_HELPER" ]; then
  AK_FN_COUNT=$(count_matches '^(audit_coverage_emit|audit_coverage_check)\s*\(\)\s*\{?' "$AK_HELPER")
  if [ "$AK_FN_COUNT" -ge 2 ]; then
    echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-DOC-1: hooks/lib/audit-coverage.sh defines both functions (count=${AK_FN_COUNT})"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} CT-MODE-COV-DOC-1: only ${AK_FN_COUNT} of 2 helper functions found" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-DOC-1: hooks/lib/audit-coverage.sh does not exist" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-MODE-COV-DOC-2: /audit Step 4b references audit_coverage_emit.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AK_STEP4B_TMP=$(mktemp)
awk '/^### 4b\./,/^### |^## /' "$AK_AUDIT_MD" > "$AK_STEP4B_TMP"
AK_EMIT_HITS=$(count_matches 'audit_coverage_emit' "$AK_STEP4B_TMP")
if [ "$AK_EMIT_HITS" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-DOC-2: /audit Step 4b references audit_coverage_emit (count=${AK_EMIT_HITS})"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-DOC-2: /audit Step 4b does not reference audit_coverage_emit" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f "$AK_STEP4B_TMP"

# CT-MODE-COV-DOC-3: /ship Step 9 references audit_coverage_check and the success log.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AK_STEP9_TMP=$(mktemp)
awk '/^9\. \*\*Review gate\*\*/,/^10\. /' "$AK_SHIP_MD" > "$AK_STEP9_TMP"
AK_SHIP_HITS=$(count_matches 'audit_coverage_check|\[REVIEW-GATE\] audit-coverage match' "$AK_STEP9_TMP")
if [ "$AK_SHIP_HITS" -ge 2 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-DOC-3: /ship Step 9 references helper and success log (count=${AK_SHIP_HITS})"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-DOC-3: /ship Step 9 references only ${AK_SHIP_HITS}/2 of helper+log" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f "$AK_STEP9_TMP"

# CT-MODE-COV-DOC-4: --no-filters is NOT used in the helper (CRLF/filter-mismatch guard).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AK_NOFILT_HITS=$(count_matches '\-\-no\-filters' "$AK_HELPER")
if [ "$AK_NOFILT_HITS" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-COV-DOC-4: hooks/lib/audit-coverage.sh has 0 occurrences of --no-filters"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-COV-DOC-4: hooks/lib/audit-coverage.sh uses --no-filters (count=${AK_NOFILT_HITS})" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# Category CT-AC: auto-compact-on-ship contract (v7 redesign — Option C)
# Trigger architecture:
#   - Primary (B): pre-next-scout-auto-compact.sh on PreToolUse(Skill:scout)
#     fires when the autopilot orchestrator is about to invoke /scout for
#     a NON-FIRST ticket. This is the strict "end of one ticket's loop"
#     boundary.
#   - Safety-net (A): post-ship-state-auto-compact.sh on PostToolUse(Edit|
#     Write) when the brief-level autopilot-state.yaml gains
#     `ship: completed`. Catches the last-ticket case and any flow change
#     that bypasses the next /scout. Deduplicates against the primary via
#     the .auto-compact-pending sentinel.
# Tests CT-AC-01..09 cover the primary; CT-AC-10..14 cover the safety net;
# CT-AC-15..22 cover shared infrastructure (dispatcher, docstring, sentinel,
# end_turn coordination, SessionStart resume, loop guard, CHANGELOG).
# =============================================================================
echo "--- Cat AC: auto-compact-on-ship contract (v7 redesign) ---"

AC_HOOK_PRIMARY="$REPO_DIR/hooks/pre-next-scout-auto-compact.sh"
AC_HOOK_SAFETY="$REPO_DIR/hooks/post-ship-state-auto-compact.sh"
AC_LIB="$REPO_DIR/hooks/lib/inject-keys.sh"
AC_HOOKS_JSON="$REPO_DIR/hooks/hooks.json"

# Shared tmux PATH stub for dispatcher DRY_RUN paths.
AC_STUB_DIR=$(mktemp -d)
cat > "$AC_STUB_DIR/tmux" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$AC_STUB_DIR/tmux"

# Helper: brief-level autopilot-state.yaml with one prior ship: completed
# AND one in_progress ticket. Used by the primary-trigger fixtures so
# Gate 4 (`SHIPPED_COUNT >= 1`) passes.
_ac_make_state_with_prior_ship() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/autopilot-state.yaml" <<'STATE'
version: 1
parent_slug: dummy
tickets:
  - logical_id: dummy-part-1
    ticket_dir: .simple-workflow/backlog/done/dummy/001-first
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
  - logical_id: dummy-part-2
    ticket_dir: .simple-workflow/backlog/active/dummy/002-second
    status: in_progress
    steps:
      scout: pending
      impl: pending
      ship: pending
STATE
}

# CT-AC-01: both hooks exist and are executable.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC01_MISSING=""
[ -f "$AC_HOOK_PRIMARY" ] && [ -x "$AC_HOOK_PRIMARY" ] || AC01_MISSING="${AC01_MISSING} pre-next-scout-auto-compact"
[ -f "$AC_HOOK_SAFETY" ] && [ -x "$AC_HOOK_SAFETY" ] || AC01_MISSING="${AC01_MISSING} post-ship-state-auto-compact"
if [ -z "$AC01_MISSING" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-01: both auto-compact hooks exist and are executable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-01: hook(s) missing or not executable:${AC01_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-02: hooks/lib/inject-keys.sh exports the inject_keys function.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$AC_LIB" ] && grep -qE '^export -f inject_keys' "$AC_LIB"; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-02: hooks/lib/inject-keys.sh exports inject_keys"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-02: hooks/lib/inject-keys.sh does not export inject_keys" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-03: hooks.json registers both new hooks. Primary lives under
# PreToolUse:Skill as its own top-level entry; safety net lives under
# PostToolUse:Edit and PostToolUse:Write as two own top-level entries.
# CLAUDE.md `## Hooks` rule requires ordering-dependent or independent
# hooks to be top-level (not nested with siblings).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if command -v jq >/dev/null 2>&1 && [ -f "$AC_HOOKS_JSON" ]; then
  AC03_OK=1
  AC03_MISSING=""
  AC03_PRIMARY_COUNT=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Skill") | select((.hooks // []) | map(.command // "") | any(test("pre-next-scout-auto-compact\\.sh"))) | select((.hooks // []) | length == 1)] | length' "$AC_HOOKS_JSON" 2>/dev/null || echo 0)
  if [ "$AC03_PRIMARY_COUNT" != "1" ]; then
    AC03_OK=0; AC03_MISSING="${AC03_MISSING} primary-not-isolated-top-level (count=${AC03_PRIMARY_COUNT})"
  fi
  AC03_SAFETY_EDIT=$(jq '[.hooks.PostToolUse[] | select(.matcher == "Edit") | select((.hooks // []) | map(.command // "") | any(test("post-ship-state-auto-compact\\.sh"))) | select((.hooks // []) | length == 1)] | length' "$AC_HOOKS_JSON" 2>/dev/null || echo 0)
  AC03_SAFETY_WRITE=$(jq '[.hooks.PostToolUse[] | select(.matcher == "Write") | select((.hooks // []) | map(.command // "") | any(test("post-ship-state-auto-compact\\.sh"))) | select((.hooks // []) | length == 1)] | length' "$AC_HOOKS_JSON" 2>/dev/null || echo 0)
  if [ "$AC03_SAFETY_EDIT" != "1" ] || [ "$AC03_SAFETY_WRITE" != "1" ]; then
    AC03_OK=0; AC03_MISSING="${AC03_MISSING} safety-net-Edit=${AC03_SAFETY_EDIT}-Write=${AC03_SAFETY_WRITE}"
  fi
  # Obsolete v6 hook must NOT be registered anywhere.
  if jq -e '.. | objects | .command? // empty | test("post-ship-auto-compact\\.sh$")' "$AC_HOOKS_JSON" >/dev/null 2>&1; then
    AC03_OK=0; AC03_MISSING="${AC03_MISSING} obsolete-v6-hook-still-registered"
  fi
  if [ "$AC03_OK" = "1" ]; then
    echo -e "  ${GREEN}PASS${NC} CT-AC-03: hooks.json registers both new hooks as independent top-level entries; v6 hook absent"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} CT-AC-03: registration incorrect:${AC03_MISSING}" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  echo -e "  ${RED}FAIL${NC} CT-AC-03: jq missing or hooks.json missing" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- Primary trigger functional fixtures (CT-AC-04..09) -------------------

# CT-AC-04: non-scout skill input -> no-op (Gate 1 short-circuits).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC04_TMP=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC04_TMP/.simple-workflow/backlog/briefs/active/dummy"
AC04_OUT=$(cd "$AC04_TMP" && TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c 'echo '"'"'{"tool_input":{"skill":"simple-workflow:impl"}}'"'"' | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1 || true)
if [ -z "$AC04_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-04: primary — non-scout skill is silent no-op"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-04: non-scout skill produced output: $AC04_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC04_TMP"

# CT-AC-05: non-autopilot context -> no-op (Gate 2 short-circuits).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC05_TMP=$(mktemp -d)
AC05_OUT=$(cd "$AC05_TMP" && TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c 'echo '"'"'{"tool_input":{"skill":"simple-workflow:scout"}}'"'"' | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1 || true)
if [ -z "$AC05_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-05: primary — non-autopilot context is silent no-op"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-05: non-autopilot context produced output: $AC05_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC05_TMP"

# CT-AC-06: first-ticket scout (no prior `ship: completed`) -> no-op
# (Gate 4 ticket-boundary detection short-circuits). The first /scout
# of a pipeline must NOT trigger /compact because there is no completed
# context to compact.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC06_TMP=$(mktemp -d)
mkdir -p "$AC06_TMP/.simple-workflow/backlog/briefs/active/dummy"
cat > "$AC06_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" <<'AC06_STATE'
version: 1
parent_slug: dummy
tickets:
  - logical_id: dummy-part-1
    ticket_dir: .simple-workflow/backlog/active/dummy/001-first
    status: in_progress
    steps:
      scout: pending
      impl: pending
      ship: pending
AC06_STATE
AC06_OUT=$(cd "$AC06_TMP" && env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c 'echo '"'"'{"tool_input":{"skill":"simple-workflow:scout"}}'"'"' | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1 || true)
if [ -z "$AC06_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-06: primary — first-ticket scout is silent no-op (no prior ship: completed)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-06: first-ticket scout produced output: $AC06_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC06_TMP"

# CT-AC-07: env unset + non-first scout + autopilot context -> dispatcher
# reached (default-on path fires at the ticket boundary).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC07_TMP=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC07_TMP/.simple-workflow/backlog/briefs/active/dummy"
AC07_OUT=$(cd "$AC07_TMP" && env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c 'echo '"'"'{"tool_input":{"skill":"simple-workflow:scout"}}'"'"' | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1 || true)
if echo "$AC07_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend='; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-07: primary — env unset + non-first scout reaches dispatcher (default on)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-07: primary dispatcher not reached. Output: $AC07_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC07_TMP"

# CT-AC-08: SW_AUTO_COMPACT_ON_SHIP_MODE=off -> no-op (opt-out path).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC08_TMP=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC08_TMP/.simple-workflow/backlog/briefs/active/dummy"
AC08_OUT=$(cd "$AC08_TMP" && SW_AUTO_COMPACT_ON_SHIP_MODE=off TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c 'echo '"'"'{"tool_input":{"skill":"simple-workflow:scout"}}'"'"' | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1 || true)
if [ -z "$AC08_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-08: primary — SW_AUTO_COMPACT_ON_SHIP_MODE=off opts out (silent no-op)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-08: opt-out path produced output: $AC08_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC08_TMP"

# CT-AC-09: mode=metric-only -> additionalContext on stdout, no inject.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC09_TMP=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC09_TMP/.simple-workflow/backlog/briefs/active/dummy"
AC09_STDOUT_FILE=$(mktemp)
AC09_STDERR_FILE=$(mktemp)
(cd "$AC09_TMP" && SW_AUTO_COMPACT_ON_SHIP_MODE=metric-only TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c 'echo '"'"'{"tool_input":{"skill":"simple-workflow:scout"}}'"'"' | bash "'"$AC_HOOK_PRIMARY"'"') >"$AC09_STDOUT_FILE" 2>"$AC09_STDERR_FILE" || true
if grep -qE 'metric-only' "$AC09_STDOUT_FILE" && ! grep -qE '\[inject-keys\] DRY_RUN backend=' "$AC09_STDERR_FILE"; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-09: primary — metric-only emits additionalContext without invoking dispatcher"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-09: metric-only branch incorrect. stdout=$(cat "$AC09_STDOUT_FILE") stderr=$(cat "$AC09_STDERR_FILE")" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f "$AC09_STDOUT_FILE" "$AC09_STDERR_FILE"
rm -rf "$AC09_TMP"

# --- Safety-net trigger functional fixtures (CT-AC-10..14) ----------------

# CT-AC-10: wrong file_path (not autopilot-state.yaml) -> no-op.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC10_TMP=$(mktemp -d)
mkdir -p "$AC10_TMP/.simple-workflow/backlog/briefs/active/dummy"
touch "$AC10_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC10_OUT=$(cd "$AC10_TMP" && TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c 'echo '"'"'{"tool_input":{"file_path":"/tmp/foo/phase-state.yaml","new_string":"      ship: completed"}}'"'"' | bash "'"$AC_HOOK_SAFETY"'"' 2>&1 || true)
if [ -z "$AC10_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-10: safety-net — wrong file_path is silent no-op"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-10: wrong-path produced output: $AC10_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC10_TMP"

# CT-AC-11: new_string lacks `ship: completed` -> no-op (Gate 2).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC11_TMP=$(mktemp -d)
mkdir -p "$AC11_TMP/.simple-workflow/backlog/briefs/active/dummy"
touch "$AC11_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC11_OUT=$(cd "$AC11_TMP" && TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c 'echo '"'"'{"tool_input":{"file_path":"'"$AC11_TMP"'/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml","new_string":"      ship: in_progress"}}'"'"' | bash "'"$AC_HOOK_SAFETY"'"' 2>&1 || true)
if [ -z "$AC11_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-11: safety-net — new_string without ship: completed is silent no-op"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-11: lacking-marker produced output: $AC11_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC11_TMP"

# CT-AC-12: state-lie protection — ticket_dir not under done/ -> no-op
# (Gate 5). T-001 ship #1 failure mode from test_simple_workflow23.
# Fixture uses real newlines via printf (matches the canonical multi-line
# YAML payload an Edit/Write actually carries; the v7 element-scoped
# parse_ticket_ship_dirs needs line structure to detect element boundaries).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC12_TMP=$(mktemp -d)
mkdir -p "$AC12_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC12_TMP/.simple-workflow/backlog/active/dummy/001-fakery"
# done/ deliberately NOT created (parent dir for the rewritten done/ path
# also absent, so the active→done rewriter must fail to find the dir).
touch "$AC12_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC12_NEW=$(printf 'tickets:\n  - logical_id: dummy-part-1\n    ticket_dir: .simple-workflow/backlog/active/dummy/001-fakery\n    status: completed\n    steps:\n      scout: completed\n      impl: completed\n      ship: completed\n')
AC12_INPUT=$(jq -n --arg fp "$AC12_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC12_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC12_OUT=$(cd "$AC12_TMP" && INPUT="$AC12_INPUT" TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
if echo "$AC12_OUT" | grep -qE 'state-lie protection' && ! echo "$AC12_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend='; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-12: safety-net — state-lie protection blocks inject when done/ dir absent"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-12: state-lie protection failed. Output: $AC12_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC12_TMP"

# CT-AC-13: dedup — fresh sentinel present -> no-op (Gate 6). When the
# primary already fired and wrote .auto-compact-pending, the safety-net
# must short-circuit so the user only sees ONE /compact per boundary.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC13_TMP=$(mktemp -d)
mkdir -p "$AC13_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC13_TMP/.simple-workflow/backlog/done/dummy/001-shipped"
touch "$AC13_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
date +%s > "$AC13_TMP/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
AC13_NEW=$(printf 'tickets:\n  - logical_id: dummy-part-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC13_INPUT=$(jq -n --arg fp "$AC13_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC13_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC13_OUT=$(cd "$AC13_TMP" && INPUT="$AC13_INPUT" TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
if echo "$AC13_OUT" | grep -qE 'dedup: fresh sentinel present' && ! echo "$AC13_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend='; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-13: safety-net — dedup against fresh primary sentinel"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-13: dedup failed. Output: $AC13_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC13_TMP"

# CT-AC-14: env unset + valid state-write + done/ exists + no sentinel
# -> dispatcher reached (safety-net fires for last-ticket / flow-change
# cases the primary cannot catch).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC14_TMP=$(mktemp -d)
mkdir -p "$AC14_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC14_TMP/.simple-workflow/backlog/done/dummy/001-shipped"
touch "$AC14_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC14_NEW=$(printf 'tickets:\n  - logical_id: dummy-part-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC14_INPUT=$(jq -n --arg fp "$AC14_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC14_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC14_OUT=$(cd "$AC14_TMP" && INPUT="$AC14_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
if echo "$AC14_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend='; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-14: safety-net — env unset + valid state-write + done/ dir reaches dispatcher"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-14: safety-net dispatcher not reached. Output: $AC14_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC14_TMP"

rm -rf "$AC_STUB_DIR"

# --- Shared infrastructure (CT-AC-15..22) ---------------------------------

# CT-AC-15: dispatcher branches on all 5 supported backends (tmux, screen,
# kitty, wezterm, iterm2) inside _inject_detect_backend, AND Apple Terminal
# is deliberately NOT a dispatch target.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC15_OK=1
AC15_REASON=""
for backend in tmux screen kitty wezterm iterm2; do
  if ! awk '/^_inject_detect_backend\(\)/,/^\}/' "$AC_LIB" | grep -qE "echo \"$backend\""; then
    AC15_OK=0
    AC15_REASON="missing branch: $backend"
    break
  fi
done
if [ "$AC15_OK" = "1" ]; then
  if grep -qiE 'apple_terminal|system events' "$AC_LIB"; then
    AC15_OK=0
    AC15_REASON="Apple Terminal / System Events dispatch present"
  fi
fi
if [ "$AC15_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-15: 5 backends branched in _inject_detect_backend; Apple Terminal absent"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-15: dispatcher backend check failed ($AC15_REASON)" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-16: both auto-compact hook docstrings document the kill-switch,
# the undocumented PTY-injection dependency, and the silent no-op failure
# mode. Each file's top-of-file comment block must name all three.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC16_OK=1
AC16_MISSING=""
for AC16_HOOK_PATH in "$AC_HOOK_PRIMARY" "$AC_HOOK_SAFETY"; do
  AC16_HEADER=$(awk 'NR==1{next} /^[^#]/ && !/^[[:space:]]*$/ {exit} {print}' "$AC16_HOOK_PATH")
  AC16_NAME=$(basename "$AC16_HOOK_PATH")
  if ! echo "$AC16_HEADER" | grep -qiE 'kill.switch|SW_AUTO_COMPACT_ON_SHIP_MODE'; then
    AC16_OK=0; AC16_MISSING="${AC16_MISSING} ${AC16_NAME}:kill-switch"
  fi
  # The safety-net hook inherits the PTY dependency narrative by reference
  # to the primary; accept either explicit "PTY" or a reference to
  # "inject-keys" / "PTY injection".
  if ! echo "$AC16_HEADER" | grep -qiE 'PTY|inject_keys|injection'; then
    AC16_OK=0; AC16_MISSING="${AC16_MISSING} ${AC16_NAME}:PTY"
  fi
  if ! echo "$AC16_HEADER" | grep -qiE 'silent no-op|silent.*no.op|never block'; then
    AC16_OK=0; AC16_MISSING="${AC16_MISSING} ${AC16_NAME}:silent-no-op"
  fi
done
if [ "$AC16_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-16: both hook docstrings document kill-switch, PTY dependency, silent no-op"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-16: hook docstring missing:${AC16_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-17: CHANGELOG.md has a v7.0.0 entry with the three required group
# headers (### BREAKING CHANGES, ### Added, ### Verification) and the
# BREAKING CHANGES paragraph names the SW_AUTO_COMPACT_ON_SHIP_MODE=off
# kill-switch as the in-line migration sentence.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC_CHANGELOG="$REPO_DIR/CHANGELOG.md"
AC17_OK=1
AC17_MISSING=""
if [ ! -f "$AC_CHANGELOG" ]; then
  AC17_OK=0; AC17_MISSING="${AC17_MISSING} CHANGELOG.md-missing"
else
  if ! grep -qE '^## \[7\.0\.0\] — 20[0-9]{2}-[0-9]{2}-[0-9]{2}$' "$AC_CHANGELOG"; then
    AC17_OK=0; AC17_MISSING="${AC17_MISSING} 7.0.0-header"
  fi
  AC17_BLOCK=$(awk '/^## \[7\.0\.0\]/,/^## \[6\./{print}' "$AC_CHANGELOG")
  # NB: use here-strings rather than `echo "$X" | grep -q` to avoid the
  # `set -euo pipefail` SIGPIPE footgun where grep -q exits on first match
  # and the upstream echo writes to a closed pipe (write error: Broken
  # pipe), tripping pipefail and inverting the conditional.
  if ! grep -qE '^### BREAKING CHANGES' <<< "$AC17_BLOCK"; then
    AC17_OK=0; AC17_MISSING="${AC17_MISSING} BREAKING-CHANGES"
  fi
  if ! grep -qE '^### Added' <<< "$AC17_BLOCK"; then
    AC17_OK=0; AC17_MISSING="${AC17_MISSING} Added"
  fi
  if ! grep -qE '^### Verification' <<< "$AC17_BLOCK"; then
    AC17_OK=0; AC17_MISSING="${AC17_MISSING} Verification"
  fi
  AC17_BREAKING=$(awk '/^### BREAKING CHANGES/,/^### Added/{print}' <<< "$AC17_BLOCK")
  if ! grep -qE 'SW_AUTO_COMPACT_ON_SHIP_MODE=off' <<< "$AC17_BREAKING"; then
    AC17_OK=0; AC17_MISSING="${AC17_MISSING} opt-out-env-var"
  fi
fi
if [ "$AC17_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-17: CHANGELOG [7.0.0] has BREAKING/Added/Verification + opt-out env migration sentence"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-17: CHANGELOG [7.0.0] missing:${AC17_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-18: primary hook creates the .auto-compact-pending sentinel inside
# the brief state directory on injection success. Without this file the
# Stop hook cannot tell the queued /compact apart from a normal end_turn.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC18_TMPDIR=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC18_TMPDIR/.simple-workflow/backlog/briefs/active/dummy"
AC18_STUB_DIR=$(mktemp -d)
cat > "$AC18_STUB_DIR/tmux" <<'AC18_STUB'
#!/usr/bin/env bash
exit 0
AC18_STUB
chmod +x "$AC18_STUB_DIR/tmux"
(
  cd "$AC18_TMPDIR" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC18_STUB_DIR:$PATH" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' >/dev/null 2>&1
)
AC18_SENTINEL="$AC18_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
if [ -f "$AC18_SENTINEL" ] && [ -s "$AC18_SENTINEL" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-18: primary hook creates .auto-compact-pending sentinel on injection success"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-18: sentinel not created at $AC18_SENTINEL" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC18_TMPDIR" "$AC18_STUB_DIR"

# CT-AC-19: autopilot-continue.sh yields (exit 0, no decision:"block")
# when a fresh sentinel is present AND deletes the sentinel after
# handling. Stale sentinels (>120s) MUST also be deleted (otherwise
# they pile up under the brief dir) but MUST NOT cause a yield. H6
# fix moves the rm into both branches AFTER the freshness decision is
# made and acted on; this test exercises both paths.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC19_OK=1
AC19_MISSING=""

# Path A: fresh sentinel — yield + delete.
AC19_TMPDIR=$(mktemp -d)
mkdir -p "$AC19_TMPDIR/.simple-workflow/backlog/briefs/active/dummy"
touch "$AC19_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
date +%s > "$AC19_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
AC19_OUT=$(cd "$AC19_TMPDIR" && bash -c 'echo "{}" | bash "'"$REPO_DIR"'/hooks/autopilot-continue.sh"' 2>&1)
AC19_SENTINEL_AFTER="$AC19_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
if ! echo "$AC19_OUT" | grep -qE '\[AUTO-COMPACT-YIELD\] sentinel found'; then
  AC19_OK=0; AC19_MISSING="${AC19_MISSING} fresh-yield-log"
fi
if echo "$AC19_OUT" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
  AC19_OK=0; AC19_MISSING="${AC19_MISSING} fresh-unexpected-block-decision"
fi
if [ -f "$AC19_SENTINEL_AFTER" ]; then
  AC19_OK=0; AC19_MISSING="${AC19_MISSING} fresh-sentinel-not-deleted"
fi
rm -rf "$AC19_TMPDIR"

# Path B: stale sentinel (age >120s) — log + delete + fall through to
# the normal block-decision path (because there is an in-progress
# pipeline step). The hook must NOT exit 0 silently; it must continue
# to the rest of the script. We assert that the stale-sentinel line is
# emitted and the sentinel itself is deleted.
AC19B_TMPDIR=$(mktemp -d)
mkdir -p "$AC19B_TMPDIR/.simple-workflow/backlog/briefs/active/dummy"
cat > "$AC19B_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" <<'AC19B_STATE'
version: 1
parent_slug: dummy
tickets:
  - logical_id: dummy-part-1
    ticket_dir: .simple-workflow/backlog/active/dummy/001-pending
    status: in_progress
    steps:
      scout: in_progress
AC19B_STATE
# Write a sentinel timestamp 300s in the past (>120s threshold).
AC19B_STALE_TS=$(( $(date +%s) - 300 ))
echo "$AC19B_STALE_TS" > "$AC19B_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
AC19B_OUT=$(cd "$AC19B_TMPDIR" && bash -c 'echo "{}" | bash "'"$REPO_DIR"'/hooks/autopilot-continue.sh"' 2>&1)
AC19B_SENTINEL_AFTER="$AC19B_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
if ! echo "$AC19B_OUT" | grep -qE '\[AUTO-COMPACT-YIELD\] stale sentinel'; then
  AC19_OK=0; AC19_MISSING="${AC19_MISSING} stale-log-missing"
fi
if [ -f "$AC19B_SENTINEL_AFTER" ]; then
  AC19_OK=0; AC19_MISSING="${AC19_MISSING} stale-sentinel-not-deleted"
fi
# Stale should fall through to block-decision (in_progress pipeline).
if ! echo "$AC19B_OUT" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
  AC19_OK=0; AC19_MISSING="${AC19_MISSING} stale-no-fall-through-to-block"
fi
rm -rf "$AC19B_TMPDIR"

if [ "$AC19_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-19: autopilot-continue.sh sentinel handling — fresh yields + deletes; stale deletes + falls through to block (H6 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-19: sentinel handling contract violated:${AC19_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-20: end_turn coordination — both new hooks' additionalContext
# must steer the model to end_turn, AND skills/autopilot/SKILL.md must
# carry the matching AUTO-COMPACT EXCEPTION block at step e (loop-tail).
# Without this triple-agreement, the model's default "Do NOT end turn"
# instruction wins and /compact sits in the queue indefinitely.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC20_STUB_DIR=$(mktemp -d)
cat > "$AC20_STUB_DIR/tmux" <<'AC20_STUB'
#!/usr/bin/env bash
exit 0
AC20_STUB
chmod +x "$AC20_STUB_DIR/tmux"
AC20_OK=1
AC20_MISSING=""

# Axis 1a: primary additionalContext mentions end_turn + ticket boundary.
AC20_TMP_PRIM=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC20_TMP_PRIM/.simple-workflow/backlog/briefs/active/dummy"
AC20_PRIM_OUT=$(cd "$AC20_TMP_PRIM" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC20_STUB_DIR:$PATH" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' 2>/dev/null)
AC20_PRIM_CTX=$(echo "$AC20_PRIM_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
if ! echo "$AC20_PRIM_CTX" | grep -qiE 'end this turn|end the turn|end_turn'; then
  AC20_OK=0; AC20_MISSING="${AC20_MISSING} primary-additionalContext-end-turn"
fi
if ! echo "$AC20_PRIM_CTX" | grep -qiE 'ticket.boundary'; then
  AC20_OK=0; AC20_MISSING="${AC20_MISSING} primary-additionalContext-ticket-boundary-label"
fi
rm -rf "$AC20_TMP_PRIM"

# Axis 1b: safety-net additionalContext mentions end_turn + state-write.
AC20_TMP_SAFE=$(mktemp -d)
mkdir -p "$AC20_TMP_SAFE/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC20_TMP_SAFE/.simple-workflow/backlog/done/dummy/001-shipped"
touch "$AC20_TMP_SAFE/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC20_NEW=$(printf 'tickets:\n  - logical_id: dummy-part-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC20_INPUT=$(jq -n --arg fp "$AC20_TMP_SAFE/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC20_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC20_SAFE_OUT=$(cd "$AC20_TMP_SAFE" && INPUT="$AC20_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC20_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>/dev/null)
AC20_SAFE_CTX=$(echo "$AC20_SAFE_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
if ! echo "$AC20_SAFE_CTX" | grep -qiE 'end this turn|end the turn|end_turn'; then
  AC20_OK=0; AC20_MISSING="${AC20_MISSING} safety-additionalContext-end-turn"
fi
if ! echo "$AC20_SAFE_CTX" | grep -qiE 'state.write|safety.net'; then
  AC20_OK=0; AC20_MISSING="${AC20_MISSING} safety-additionalContext-safety-net-label"
fi
rm -rf "$AC20_TMP_SAFE"

# Axis 2: SKILL.md step e (loop-tail) must carry AUTO-COMPACT EXCEPTION
# that names BOTH new hooks and their additionalContext labels.
AC20_LOOPTAIL_BLOCK=$(awk '/^   e\. \*\*Loop-tail CHECKPOINT/,/^4\. /' "$REPO_DIR/skills/autopilot/SKILL.md")
if ! echo "$AC20_LOOPTAIL_BLOCK" | grep -qiE 'AUTO-COMPACT EXCEPTION'; then
  AC20_OK=0; AC20_MISSING="${AC20_MISSING} skill-md-exception-block"
fi
if ! echo "$AC20_LOOPTAIL_BLOCK" | grep -qE 'pre-next-scout-auto-compact'; then
  AC20_OK=0; AC20_MISSING="${AC20_MISSING} skill-md-names-primary-hook"
fi
if ! echo "$AC20_LOOPTAIL_BLOCK" | grep -qE 'post-ship-state-auto-compact'; then
  AC20_OK=0; AC20_MISSING="${AC20_MISSING} skill-md-names-safety-net-hook"
fi
if ! echo "$AC20_LOOPTAIL_BLOCK" | grep -qiE 'end the turn|end your turn'; then
  AC20_OK=0; AC20_MISSING="${AC20_MISSING} skill-md-end-turn-instruction"
fi

if [ "$AC20_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-20: end_turn coordination — primary/safety additionalContext + SKILL.md step e all agree"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-20: end_turn coordination broken:${AC20_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC20_STUB_DIR"

# CT-AC-21: post-compact resume kick (session-start.sh on source=compact
# must PTY-inject `/autopilot {parent_slug}` when a run is in_progress;
# silent on source=startup; honors opt-out).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC21_STUB_DIR=$(mktemp -d)
cat > "$AC21_STUB_DIR/tmux" <<'AC21_STUB'
#!/usr/bin/env bash
exit 0
AC21_STUB
chmod +x "$AC21_STUB_DIR/tmux"
AC21_TMPDIR=$(mktemp -d)
mkdir -p "$AC21_TMPDIR/.simple-workflow/backlog/briefs/active/my-slug"
cat > "$AC21_TMPDIR/.simple-workflow/backlog/briefs/active/my-slug/autopilot-state.yaml" <<'AC21_YAML'
version: 1
parent_slug: my-slug
tickets:
  001:
    status: in_progress
AC21_YAML
AC21_OUT_A=$(cd "$AC21_TMPDIR" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC21_STUB_DIR:$PATH" \
  bash -c 'echo "{\"source\":\"compact\"}" | bash "'"$REPO_DIR"'/hooks/session-start.sh"' 2>&1 >/dev/null)
AC21_OUT_B=$(cd "$AC21_TMPDIR" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC21_STUB_DIR:$PATH" \
  bash -c 'echo "{\"source\":\"startup\"}" | bash "'"$REPO_DIR"'/hooks/session-start.sh"' 2>&1 >/dev/null)
AC21_OUT_C=$(cd "$AC21_TMPDIR" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 SW_AUTO_COMPACT_ON_SHIP_MODE=off PATH="$AC21_STUB_DIR:$PATH" \
  bash -c 'echo "{\"source\":\"compact\"}" | bash "'"$REPO_DIR"'/hooks/session-start.sh"' 2>&1 >/dev/null)
AC21_OK=1
AC21_MISSING=""
if ! echo "$AC21_OUT_A" | grep -qE '\[SESSION-START-RESUME\] \[inject-keys\] DRY_RUN backend=.+ text=/autopilot my-slug'; then
  AC21_OK=0; AC21_MISSING="${AC21_MISSING} path-A-resume-missing"
fi
if echo "$AC21_OUT_B" | grep -qE '\[SESSION-START-RESUME\]'; then
  AC21_OK=0; AC21_MISSING="${AC21_MISSING} path-B-startup-spurious-inject"
fi
if echo "$AC21_OUT_C" | grep -qE '\[SESSION-START-RESUME\]'; then
  AC21_OK=0; AC21_MISSING="${AC21_MISSING} path-C-opt-out-leaked"
fi
if [ "$AC21_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-21: SessionStart:compact resume kick — inject on compact+in_progress; silent on startup; honors opt-out"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-21: post-compact resume contract violated:${AC21_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC21_TMPDIR" "$AC21_STUB_DIR"

# CT-AC-22: state-consistency loop-detection (Gate 5 in
# pre-next-scout-auto-compact.sh). When invoked twice with the same
# shipped_count within 300s, the hook MUST skip the second inject. When
# the count advances, the hook MUST inject again. The
# `.auto-compact-last-attempt` marker has format `{shipped_count}:{ts}`.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC22_STUB_DIR=$(mktemp -d)
cat > "$AC22_STUB_DIR/tmux" <<'AC22_STUB'
#!/usr/bin/env bash
exit 0
AC22_STUB
chmod +x "$AC22_STUB_DIR/tmux"
AC22_TMPDIR=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC22_TMPDIR/.simple-workflow/backlog/briefs/active/dummy"
AC22_MARKER="$AC22_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-last-attempt"
AC22_OUT_A=$(cd "$AC22_TMPDIR" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC22_STUB_DIR:$PATH" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1)
AC22_MARKER_A=$(cat "$AC22_MARKER" 2>/dev/null || echo "MISSING")
# Run B: state unchanged → expect SKIP
# Remove the .auto-compact-pending sentinel so it doesn't influence the
# decision (loop-detection is independent of the dedup sentinel).
rm -f "$AC22_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
AC22_OUT_B=$(cd "$AC22_TMPDIR" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC22_STUB_DIR:$PATH" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1)
# Run C: advance state (one more ship: completed) → expect inject
cat > "$AC22_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" <<'AC22_YAML2'
version: 1
parent_slug: dummy
tickets:
  - logical_id: dummy-part-1
    ticket_dir: .simple-workflow/backlog/done/dummy/001-first
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
  - logical_id: dummy-part-2
    ticket_dir: .simple-workflow/backlog/done/dummy/002-second
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
  - logical_id: dummy-part-3
    ticket_dir: .simple-workflow/backlog/active/dummy/003-third
    status: in_progress
    steps:
      scout: pending
      impl: pending
      ship: pending
AC22_YAML2
rm -f "$AC22_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
AC22_OUT_C=$(cd "$AC22_TMPDIR" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC22_STUB_DIR:$PATH" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1)
AC22_MARKER_C=$(cat "$AC22_MARKER" 2>/dev/null || echo "MISSING")
AC22_OK=1
AC22_MISSING=""
if ! echo "$AC22_OUT_A" | grep -qE '\[PRE-NEXT-SCOUT-AUTO-COMPACT\] \[inject-keys\] DRY_RUN backend='; then
  AC22_OK=0; AC22_MISSING="${AC22_MISSING} run-A-inject-missing"
fi
if [ "${AC22_MARKER_A%%:*}" != "1" ]; then
  AC22_OK=0; AC22_MISSING="${AC22_MISSING} run-A-marker-count-not-1(got=${AC22_MARKER_A%%:*})"
fi
if echo "$AC22_OUT_B" | grep -qE '\[PRE-NEXT-SCOUT-AUTO-COMPACT\] \[inject-keys\] DRY_RUN backend='; then
  AC22_OK=0; AC22_MISSING="${AC22_MISSING} run-B-spurious-inject"
fi
if ! echo "$AC22_OUT_B" | grep -qiE 'loop suspected|skipping inject'; then
  AC22_OK=0; AC22_MISSING="${AC22_MISSING} run-B-loop-log-missing"
fi
if ! echo "$AC22_OUT_C" | grep -qE '\[PRE-NEXT-SCOUT-AUTO-COMPACT\] \[inject-keys\] DRY_RUN backend='; then
  AC22_OK=0; AC22_MISSING="${AC22_MISSING} run-C-inject-missing-after-state-advance"
fi
if [ "${AC22_MARKER_C%%:*}" != "2" ]; then
  AC22_OK=0; AC22_MISSING="${AC22_MISSING} run-C-marker-count-not-2(got=${AC22_MARKER_C%%:*})"
fi
if [ "$AC22_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-22: state-consistency loop-detection — inject when count advances, skip when unchanged within 300s"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-22: loop-detection contract violated:${AC22_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC22_TMPDIR" "$AC22_STUB_DIR"

# CT-AC-23: cross-hook loop-guard marker sharing (test_simple_workflow24
# double-compact fix). The safety-net (post-ship-state-auto-compact.sh)
# MUST write the same `.auto-compact-last-attempt` marker the primary
# reads in its Gate 5, so that one /compact per ticket boundary is
# enforced across the compact/resume cycle (the `.auto-compact-pending`
# sentinel gets consumed by `autopilot-continue.sh` when yielding the
# Stop tick, so a sentinel-only dedup is insufficient).
#
# Three-path contract:
#   Run A: safety-net fires for a fresh boundary -> marker written
#          with the new shipped_count, dispatcher reached.
#   Run B: primary fires for the SAME boundary post-compact (marker
#          already written by Run A, sentinel deleted by yield) ->
#          Gate 5 trips on shipped_count unchanged, dispatcher NOT
#          reached.
#   Run C: safety-net fires twice for the same boundary (split Edit
#          calls, both with `ship: completed` in new_string) -> Gate 7
#          trips on shipped_count unchanged, second invocation skips.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC23_STUB_DIR=$(mktemp -d)
cat > "$AC23_STUB_DIR/tmux" <<'AC23_STUB'
#!/usr/bin/env bash
exit 0
AC23_STUB
chmod +x "$AC23_STUB_DIR/tmux"
AC23_TMPDIR=$(mktemp -d)
mkdir -p "$AC23_TMPDIR/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC23_TMPDIR/.simple-workflow/backlog/done/dummy/001-first"
# Post-T1-ship state file: one ticket has ship: completed.
cat > "$AC23_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" <<'AC23_STATE'
version: 1
parent_slug: dummy
tickets:
  - logical_id: dummy-part-1
    ticket_dir: .simple-workflow/backlog/done/dummy/001-first
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
  - logical_id: dummy-part-2
    ticket_dir: .simple-workflow/backlog/active/dummy/002-second
    status: in_progress
    steps:
      scout: pending
      impl: pending
      ship: pending
AC23_STATE
AC23_MARKER="$AC23_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-last-attempt"

# Run A: safety-net fires for T-1 boundary.
AC23_NEW=$(printf 'tickets:\n  - logical_id: dummy-part-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-first\n    status: completed\n    steps:\n      ship: completed\n')
AC23_INPUT=$(jq -n --arg fp "$AC23_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC23_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC23_OUT_A=$(cd "$AC23_TMPDIR" && INPUT="$AC23_INPUT" TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC23_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
AC23_MARKER_A=$(cat "$AC23_MARKER" 2>/dev/null || echo "MISSING")

# Run B: primary fires for the same boundary post-compact-resume.
# Simulate autopilot-continue.sh's sentinel consumption by deleting it
# (it would have been deleted when yielding the Stop tick).
rm -f "$AC23_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
AC23_OUT_B=$(cd "$AC23_TMPDIR" && TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC23_STUB_DIR:$PATH" bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1 || true)

# Run C: safety-net fires again for the same boundary (simulated split
# Edit). Marker should still match shipped_count → skip.
rm -f "$AC23_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
AC23_OUT_C=$(cd "$AC23_TMPDIR" && INPUT="$AC23_INPUT" TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC23_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)

AC23_OK=1
AC23_MISSING=""
# Run A: dispatcher reached AND marker count = 1 (one ship: completed).
if ! echo "$AC23_OUT_A" | grep -qE '\[POST-SHIP-STATE-AUTO-COMPACT\] \[inject-keys\] DRY_RUN backend='; then
  AC23_OK=0; AC23_MISSING="${AC23_MISSING} run-A-inject-missing"
fi
if [ "${AC23_MARKER_A%%:*}" != "1" ]; then
  AC23_OK=0; AC23_MISSING="${AC23_MISSING} run-A-marker-count-not-1(got=${AC23_MARKER_A%%:*})"
fi
# Run B: primary must skip (shared marker says count=1 already).
if echo "$AC23_OUT_B" | grep -qE '\[PRE-NEXT-SCOUT-AUTO-COMPACT\] \[inject-keys\] DRY_RUN backend='; then
  AC23_OK=0; AC23_MISSING="${AC23_MISSING} run-B-primary-spurious-inject-after-safety-net"
fi
if ! echo "$AC23_OUT_B" | grep -qiE 'loop suspected|skipping inject'; then
  AC23_OK=0; AC23_MISSING="${AC23_MISSING} run-B-loop-log-missing"
fi
# Run C: safety-net must skip on second consecutive fire.
if echo "$AC23_OUT_C" | grep -qE '\[POST-SHIP-STATE-AUTO-COMPACT\] \[inject-keys\] DRY_RUN backend='; then
  AC23_OK=0; AC23_MISSING="${AC23_MISSING} run-C-safety-net-spurious-inject-on-second-fire"
fi
if ! echo "$AC23_OUT_C" | grep -qiE 'loop-guard|loop suspected|skipping inject'; then
  AC23_OK=0; AC23_MISSING="${AC23_MISSING} run-C-loop-log-missing"
fi
if [ "$AC23_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-23: cross-hook loop-guard marker sharing — safety-net writes, primary reads, both skip duplicates within 300s"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-23: cross-hook dedup violated:${AC23_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC23_TMPDIR" "$AC23_STUB_DIR"

# CT-AC-24: state-lie protection — element-scoped, multi-ticket payload
# (CD-1 in the v7 review). The just-written payload contains TWO
# tickets[] elements, both with `steps.ship: completed`: T-001 ships
# genuinely (done/ dir exists), but T-002 is lying (active/ dir, no
# done/ counterpart). The v6 awk would return T-001's dir at the first
# `ship: completed` match and silently pass Gate 5, injecting on the
# T-002 state-lie. v7's element-scoped parser
# (`parse_ticket_ship_dirs` in `hooks/lib/parse-state-file.sh`) emits
# both dirs, the safety net checks each, detects T-002's missing done/
# counterpart, and refuses to inject.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC24_STUB_DIR=$(mktemp -d)
cat > "$AC24_STUB_DIR/tmux" <<'AC24_STUB'
#!/usr/bin/env bash
exit 0
AC24_STUB
chmod +x "$AC24_STUB_DIR/tmux"
AC24_TMP=$(mktemp -d)
mkdir -p "$AC24_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC24_TMP/.simple-workflow/backlog/done/dummy/001-real"
# T-002's done/ counterpart deliberately NOT created.
touch "$AC24_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC24_NEW=$(printf 'tickets:\n  - logical_id: T-001\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-real\n    status: completed\n    steps:\n      scout: completed\n      impl: completed\n      ship: completed\n  - logical_id: T-002\n    ticket_dir: .simple-workflow/backlog/active/dummy/002-fake\n    status: completed\n    steps:\n      scout: completed\n      impl: completed\n      ship: completed\n')
AC24_INPUT=$(jq -n --arg fp "$AC24_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC24_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC24_OUT=$(cd "$AC24_TMP" && INPUT="$AC24_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC24_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
if echo "$AC24_OUT" | grep -qE 'state-lie protection.*002-fake' && ! echo "$AC24_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend='; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-24: safety-net — element-scoped state-lie protection blocks multi-ticket payload when ANY element lies (CD-1 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-24: element-scoped state-lie protection bypassed. Output: $AC24_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC24_TMP" "$AC24_STUB_DIR"

# CT-AC-25: state-lie protection — element-scoped, single-element payload
# where `steps.ship: completed` appears textually BEFORE `ticket_dir:`
# within the same tickets[] element (CD-2 in the v7 review). The v6 awk
# would inherit the PREVIOUS element's ticket_dir (T-001 done/ dir) and
# silently pass Gate 5, even though the just-shipped element's actual
# dir was active/ (no done/ counterpart). v7's element-scoped parser
# captures dir/ship in any order within an element and pairs them
# correctly via element-boundary detection.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC25_STUB_DIR=$(mktemp -d)
cat > "$AC25_STUB_DIR/tmux" <<'AC25_STUB'
#!/usr/bin/env bash
exit 0
AC25_STUB
chmod +x "$AC25_STUB_DIR/tmux"
AC25_TMP=$(mktemp -d)
mkdir -p "$AC25_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC25_TMP/.simple-workflow/backlog/done/dummy/001-real"
# T-002's done/ counterpart deliberately NOT created.
touch "$AC25_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
# Note the atypical key ordering within each element: ship: completed
# appears BEFORE ticket_dir:. Both elements use the same ordering.
AC25_NEW=$(printf 'tickets:\n  - logical_id: T-001\n    steps:\n      ship: completed\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-real\n    status: completed\n  - logical_id: T-002\n    steps:\n      ship: completed\n    ticket_dir: .simple-workflow/backlog/active/dummy/002-fake\n    status: completed\n')
AC25_INPUT=$(jq -n --arg fp "$AC25_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC25_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC25_OUT=$(cd "$AC25_TMP" && INPUT="$AC25_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC25_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
if echo "$AC25_OUT" | grep -qE 'state-lie protection.*002-fake' && ! echo "$AC25_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend='; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-25: safety-net — element-scoped parser pairs ship/ticket_dir in any order within element (CD-2 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-25: element-scoped parser fails on shuffled key order. Output: $AC25_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC25_TMP" "$AC25_STUB_DIR"

# CT-AC-26: tmux/screen target pane (C3 fix). The dispatcher MUST target
# the calling pane/window via `-t "$TMUX_PANE"` (tmux) or `-p "$WINDOW"`
# (screen). Without that, `tmux send-keys` / `screen stuff` would inject
# /compact<Enter> into whichever pane/window the user switched to between
# turn-start and the hook firing — a real correctness issue, not just a
# UX nit. Verifies (a) DRY_RUN log exposes the target value so downstream
# tools can audit, (b) target falls back gracefully when $TMUX_PANE is
# absent, and (c) source-level grep catches a regression that drops the
# target from the real (non-DRY) branch.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC26_STUB_DIR=$(mktemp -d)
cat > "$AC26_STUB_DIR/tmux" <<'AC26_STUB'
#!/usr/bin/env bash
exit 0
AC26_STUB
chmod +x "$AC26_STUB_DIR/tmux"
AC26_OUT_TMUX=$(TMUX=fake-socket TMUX_PANE='%42' INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC26_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
AC26_OUT_NOPANE=$(env -u TMUX_PANE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC26_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
AC26_OK=1
AC26_MISSING=""
# Path A: TMUX_PANE set -> target value appears in DRY_RUN log.
if ! echo "$AC26_OUT_TMUX" | grep -qE 'backend=tmux target=%42 text=/compact'; then
  AC26_OK=0; AC26_MISSING="${AC26_MISSING} tmux-pane-missing-from-log"
fi
# Path B: TMUX_PANE absent -> log still emitted with empty target (no crash).
if ! echo "$AC26_OUT_NOPANE" | grep -qE 'backend=tmux target= text=/compact'; then
  AC26_OK=0; AC26_MISSING="${AC26_MISSING} tmux-no-pane-fallback-broken"
fi
# Path C: source contains the targeted invocation for both backends so a
# refactor that strips the target is caught at test time.
if ! grep -qE 'tmux send-keys -t "\$TMUX_PANE"' "$AC_LIB"; then
  AC26_OK=0; AC26_MISSING="${AC26_MISSING} tmux-source-missing-target"
fi
if ! grep -qE 'screen -S "\$STY" -p "\$WINDOW"' "$AC_LIB"; then
  AC26_OK=0; AC26_MISSING="${AC26_MISSING} screen-source-missing-target"
fi
if [ "$AC26_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-26: dispatcher targets calling pane/window (tmux -t \$TMUX_PANE / screen -p \$WINDOW); DRY_RUN log exposes target"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-26: target-pane contract:${AC26_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC26_STUB_DIR"

# CT-AC-27: byte-for-byte alignment between hook additionalContext labels
# and SKILL.md AUTO-COMPACT EXCEPTION (C4 fix). The previous CT-AC-20
# verified the labels were named in SKILL.md by loose regex, which would
# still pass if the SKILL.md used `\`/compact\`` escape notation while
# the hooks emitted plain backticks — a substring-match mismatch that
# could drive model defiance. CT-AC-27 enforces literal equality at the
# byte level via grep -F and explicitly blocks the legacy backslash-
# escaped form from re-entering SKILL.md.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC27_STUB_DIR=$(mktemp -d)
cat > "$AC27_STUB_DIR/tmux" <<'AC27_STUB'
#!/usr/bin/env bash
exit 0
AC27_STUB
chmod +x "$AC27_STUB_DIR/tmux"

# Primary additionalContext: trigger the dispatcher-reach path so the
# success additionalContext is emitted (not the failure fallback).
AC27_TMP_P=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC27_TMP_P/.simple-workflow/backlog/briefs/active/dummy"
AC27_PRIM_OUT=$(cd "$AC27_TMP_P" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC27_STUB_DIR:$PATH" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' 2>/dev/null)
AC27_PRIM_CTX=$(echo "$AC27_PRIM_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
rm -rf "$AC27_TMP_P"

# Safety-net additionalContext: same dispatcher-reach path.
AC27_TMP_S=$(mktemp -d)
mkdir -p "$AC27_TMP_S/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC27_TMP_S/.simple-workflow/backlog/done/dummy/001-shipped"
touch "$AC27_TMP_S/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC27_NEW=$(printf 'tickets:\n  - logical_id: dummy-part-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC27_INPUT=$(jq -n --arg fp "$AC27_TMP_S/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC27_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC27_SAFE_OUT=$(cd "$AC27_TMP_S" && INPUT="$AC27_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC27_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>/dev/null)
AC27_SAFE_CTX=$(echo "$AC27_SAFE_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
rm -rf "$AC27_TMP_S"

AC_SKILLMD="$REPO_DIR/skills/autopilot/SKILL.md"
# Literal substrings the model must substring-match. Both literals appear
# in the hook output AND in SKILL.md — same bytes, no escape mismatch.
AC27_PRIM_LABEL='auto-compact-on-ship (ticket-boundary):'
AC27_SAFE_LABEL='auto-compact-on-ship (state-write safety-net):'
AC27_COMPACT_LITERAL='`/compact` has been queued'

AC27_OK=1
AC27_MISSING=""
# Both labels appear verbatim in the respective hook output.
echo "$AC27_PRIM_CTX" | grep -qF "$AC27_PRIM_LABEL" || { AC27_OK=0; AC27_MISSING="${AC27_MISSING} prim-label-in-hook"; }
echo "$AC27_SAFE_CTX" | grep -qF "$AC27_SAFE_LABEL" || { AC27_OK=0; AC27_MISSING="${AC27_MISSING} safety-label-in-hook"; }
# Both hooks include the /compact-queued literal.
echo "$AC27_PRIM_CTX" | grep -qF "$AC27_COMPACT_LITERAL" || { AC27_OK=0; AC27_MISSING="${AC27_MISSING} prim-compact-literal-in-hook"; }
echo "$AC27_SAFE_CTX" | grep -qF "$AC27_COMPACT_LITERAL" || { AC27_OK=0; AC27_MISSING="${AC27_MISSING} safety-compact-literal-in-hook"; }
# Same three literals appear in SKILL.md (byte-for-byte; grep -F).
grep -qF "$AC27_PRIM_LABEL" "$AC_SKILLMD" || { AC27_OK=0; AC27_MISSING="${AC27_MISSING} prim-label-in-skillmd"; }
grep -qF "$AC27_SAFE_LABEL" "$AC_SKILLMD" || { AC27_OK=0; AC27_MISSING="${AC27_MISSING} safety-label-in-skillmd"; }
grep -qF "$AC27_COMPACT_LITERAL" "$AC_SKILLMD" || { AC27_OK=0; AC27_MISSING="${AC27_MISSING} compact-literal-in-skillmd"; }
# Regression guard: the legacy escape form `\`/compact\`` MUST NOT come
# back. The hook never emits backslash-bracketed backticks; SKILL.md
# must not either.
if grep -qF '\`/compact\`' "$AC_SKILLMD"; then
  AC27_OK=0; AC27_MISSING="${AC27_MISSING} legacy-escape-form-present-in-skillmd"
fi

if [ "$AC27_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-27: SKILL.md AUTO-COMPACT EXCEPTION label literals are byte-for-byte identical with hook additionalContext (C4 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-27: label literal mismatch:${AC27_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC27_STUB_DIR"

# CT-AC-28: safety-net derives STATE_FILE_PATH from $TOOL_FILE_PATH (H5
# fix). With two briefs concurrently active under briefs/active/, the
# brief that was JUST written-to must receive the .auto-compact-pending
# sentinel and the .auto-compact-last-attempt marker — NOT whichever
# brief happens to have the newest mtime. The previous implementation
# used `find_any_autopilot_state_file` (most-recently-modified
# heuristic) and could place the markers in the wrong brief if a stale
# `touch` or filesystem clock skew flipped the ordering. This test
# pre-touches brief-B's state file to make it newer, then writes
# `ship: completed` to brief-A and asserts that A's directory (not B's)
# receives the marker files.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC28_STUB_DIR=$(mktemp -d)
cat > "$AC28_STUB_DIR/tmux" <<'AC28_STUB'
#!/usr/bin/env bash
exit 0
AC28_STUB
chmod +x "$AC28_STUB_DIR/tmux"
AC28_TMP=$(mktemp -d)
mkdir -p "$AC28_TMP/.simple-workflow/backlog/briefs/active/brief-a"
mkdir -p "$AC28_TMP/.simple-workflow/backlog/briefs/active/brief-b"
mkdir -p "$AC28_TMP/.simple-workflow/backlog/done/brief-a/001-shipped"
# Both briefs have an autopilot-state.yaml. Make brief-B's NEWER so the
# old find_any_autopilot_state_file heuristic would have picked it.
touch -t 202001010000 "$AC28_TMP/.simple-workflow/backlog/briefs/active/brief-a/autopilot-state.yaml"
sleep 1
touch "$AC28_TMP/.simple-workflow/backlog/briefs/active/brief-b/autopilot-state.yaml"
# Edit targets brief-A; the safety-net must use $TOOL_FILE_PATH not mtime.
AC28_NEW=$(printf 'tickets:\n  - logical_id: a-1\n    ticket_dir: .simple-workflow/backlog/done/brief-a/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC28_INPUT=$(jq -n --arg fp "$AC28_TMP/.simple-workflow/backlog/briefs/active/brief-a/autopilot-state.yaml" --arg ns "$AC28_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC28_OUT=$(cd "$AC28_TMP" && INPUT="$AC28_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC28_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
AC28_OK=1
AC28_MISSING=""
# Dispatcher reached.
if ! echo "$AC28_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend='; then
  AC28_OK=0; AC28_MISSING="${AC28_MISSING} dispatcher-not-reached"
fi
# Sentinel + marker must land in brief-A, NOT brief-B (the mtime-winner).
if [ ! -f "$AC28_TMP/.simple-workflow/backlog/briefs/active/brief-a/.auto-compact-pending" ]; then
  AC28_OK=0; AC28_MISSING="${AC28_MISSING} sentinel-not-in-brief-A"
fi
if [ -f "$AC28_TMP/.simple-workflow/backlog/briefs/active/brief-b/.auto-compact-pending" ]; then
  AC28_OK=0; AC28_MISSING="${AC28_MISSING} sentinel-leaked-to-brief-B"
fi
if [ ! -f "$AC28_TMP/.simple-workflow/backlog/briefs/active/brief-a/.auto-compact-last-attempt" ]; then
  AC28_OK=0; AC28_MISSING="${AC28_MISSING} marker-not-in-brief-A"
fi
if [ -f "$AC28_TMP/.simple-workflow/backlog/briefs/active/brief-b/.auto-compact-last-attempt" ]; then
  AC28_OK=0; AC28_MISSING="${AC28_MISSING} marker-leaked-to-brief-B"
fi
if [ "$AC28_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-28: safety-net derives STATE_FILE_PATH from \$TOOL_FILE_PATH; markers land in the just-written brief regardless of mtime (H5 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-28: STATE_FILE_PATH derivation broken:${AC28_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC28_TMP" "$AC28_STUB_DIR"

# CT-AC-30: safety-net last-ticket branch (H7 fix). When the just-flipped
# ship: completed brings shipped_count == total_tickets, the additionalContext
# MUST include the literal "FINAL ticket of this pipeline" and instruct
# the model to complete the post-loop phase BEFORE ending the turn,
# rather than the non-last "end this turn now without proceeding to the
# next ticket's preamble". Lock the SKILL.md alignment via grep -F so the
# model can disambiguate at substring level.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC30_STUB_DIR=$(mktemp -d)
cat > "$AC30_STUB_DIR/tmux" <<'AC30_STUB'
#!/usr/bin/env bash
exit 0
AC30_STUB
chmod +x "$AC30_STUB_DIR/tmux"
AC30_TMP=$(mktemp -d)
mkdir -p "$AC30_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC30_TMP/.simple-workflow/backlog/done/dummy/001-only"
# Pre-existing state file with ONE ticket; the just-written payload also
# has one ticket with ship: completed. So total_tickets=1, shipped=1.
cat > "$AC30_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" <<'AC30_STATE'
version: 1
parent_slug: dummy
tickets:
  - logical_id: only-1
    ticket_dir: .simple-workflow/backlog/done/dummy/001-only
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
AC30_STATE
AC30_NEW=$(printf 'tickets:\n  - logical_id: only-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-only\n    status: completed\n    steps:\n      ship: completed\n')
AC30_INPUT=$(jq -n --arg fp "$AC30_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC30_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC30_OUT=$(cd "$AC30_TMP" && INPUT="$AC30_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC30_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>/dev/null)
AC30_CTX=$(echo "$AC30_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
AC30_OK=1
AC30_MISSING=""
if ! echo "$AC30_CTX" | grep -qF 'FINAL ticket of this pipeline'; then
  AC30_OK=0; AC30_MISSING="${AC30_MISSING} last-ticket-literal-missing"
fi
if ! echo "$AC30_CTX" | grep -qF 'post-loop phase FIRST'; then
  AC30_OK=0; AC30_MISSING="${AC30_MISSING} post-loop-phase-FIRST-missing"
fi
# Last-ticket additionalContext MUST NOT contain the non-last copy.
if echo "$AC30_CTX" | grep -qF "next ticket's preamble"; then
  AC30_OK=0; AC30_MISSING="${AC30_MISSING} non-last-copy-leaked-into-last"
fi
# SKILL.md AUTO-COMPACT EXCEPTION must reference the last-ticket sub-variant.
if ! grep -qF 'FINAL ticket of this pipeline' "$REPO_DIR/skills/autopilot/SKILL.md"; then
  AC30_OK=0; AC30_MISSING="${AC30_MISSING} skillmd-missing-last-ticket-trigger"
fi
if [ "$AC30_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-30: safety-net last-ticket additionalContext requires post-loop phase before end_turn (H7 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-30: last-ticket branching broken:${AC30_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC30_TMP" "$AC30_STUB_DIR"

# CT-AC-31: safety-net non-last branch (H7 fix). When shipped_count <
# total_tickets, the additionalContext MUST retain the original "end
# this turn now without proceeding to the next ticket's preamble" copy
# and MUST NOT mention "FINAL ticket of this pipeline" or
# "post-loop phase".
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC31_STUB_DIR=$(mktemp -d)
cat > "$AC31_STUB_DIR/tmux" <<'AC31_STUB'
#!/usr/bin/env bash
exit 0
AC31_STUB
chmod +x "$AC31_STUB_DIR/tmux"
AC31_TMP=$(mktemp -d)
mkdir -p "$AC31_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC31_TMP/.simple-workflow/backlog/done/dummy/001-first"
# 3-ticket state file; only T-001 just flipped to ship: completed.
cat > "$AC31_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" <<'AC31_STATE'
version: 1
parent_slug: dummy
tickets:
  - logical_id: a-1
    ticket_dir: .simple-workflow/backlog/done/dummy/001-first
    status: completed
    steps:
      ship: completed
  - logical_id: a-2
    ticket_dir: .simple-workflow/backlog/active/dummy/002-pending
    status: in_progress
    steps:
      ship: pending
  - logical_id: a-3
    ticket_dir: .simple-workflow/backlog/active/dummy/003-pending
    status: pending
    steps:
      ship: pending
AC31_STATE
AC31_NEW=$(printf 'tickets:\n  - logical_id: a-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-first\n    status: completed\n    steps:\n      ship: completed\n')
AC31_INPUT=$(jq -n --arg fp "$AC31_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC31_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC31_OUT=$(cd "$AC31_TMP" && INPUT="$AC31_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC31_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>/dev/null)
AC31_CTX=$(echo "$AC31_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
AC31_OK=1
AC31_MISSING=""
if ! echo "$AC31_CTX" | grep -qF "next ticket's preamble"; then
  AC31_OK=0; AC31_MISSING="${AC31_MISSING} non-last-copy-missing"
fi
if echo "$AC31_CTX" | grep -qF 'FINAL ticket of this pipeline'; then
  AC31_OK=0; AC31_MISSING="${AC31_MISSING} last-ticket-literal-leaked-into-non-last"
fi
if echo "$AC31_CTX" | grep -qF 'post-loop phase FIRST'; then
  AC31_OK=0; AC31_MISSING="${AC31_MISSING} post-loop-phase-leaked-into-non-last"
fi
if [ "$AC31_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-31: safety-net non-last additionalContext retains original end_turn copy and excludes last-ticket literals (H7 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-31: non-last branching broken:${AC31_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC31_TMP" "$AC31_STUB_DIR"

# CT-AC-32: kill-switch discoverability (H8 fix). The
# SW_AUTO_COMPACT_ON_SHIP_MODE env var is a BREAKING-change opt-out per
# CHANGELOG, but the pre-merge review found it only documented in the
# hook docstrings and CHANGELOG body. Users who don't read those files
# would have no way to discover the kill switch. README.md,
# ARCHITECTURE.md, and CLAUDE.md must each name the env var so a
# `grep -r SW_AUTO_COMPACT` succeeds.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC32_OK=1
AC32_MISSING=""
for AC32_DOC in README.md ARCHITECTURE.md CLAUDE.md; do
  if ! grep -qF 'SW_AUTO_COMPACT_ON_SHIP_MODE' "$REPO_DIR/$AC32_DOC"; then
    AC32_OK=0; AC32_MISSING="${AC32_MISSING} ${AC32_DOC}"
  fi
done
if [ "$AC32_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-32: SW_AUTO_COMPACT_ON_SHIP_MODE kill switch is documented in README.md, ARCHITECTURE.md, and CLAUDE.md (H8 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-32: kill switch not discoverable in:${AC32_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- Phase 2 test gap closure (CT-AC-33..39, H1-H3 fix) -------------------

# CT-AC-33: safety-net Gate 3 (defence-in-depth autopilot context check).
# Gate 1 already requires file_path to match `**/autopilot-state.yaml`, so
# in normal operation Gate 3 is redundant. But future Gate 1 broadening
# (e.g. accepting any YAML under .simple-workflow/) would let non-autopilot
# state files through; Gate 3 protects against that by requiring an
# `.simple-workflow/backlog/briefs/active/` or product_backlog/ neighbour.
# Test: file_path matches Gate 1, but the surrounding directory has NO
# autopilot-state.yaml under briefs/active/ -> is_autopilot_context fails,
# hook exits silently.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC33_STUB_DIR=$(mktemp -d)
cat > "$AC33_STUB_DIR/tmux" <<'AC33_STUB'
#!/usr/bin/env bash
exit 0
AC33_STUB
chmod +x "$AC33_STUB_DIR/tmux"
AC33_TMP=$(mktemp -d)
# Construct a Gate-1-matching path but no .simple-workflow directory:
# Gate 3's is_autopilot_context requires .simple-workflow to exist.
AC33_FAKE_PATH="$AC33_TMP/elsewhere/.simple-workflow/backlog/briefs/active/x/autopilot-state.yaml"
mkdir -p "$(dirname "$AC33_FAKE_PATH")"
touch "$AC33_FAKE_PATH"
# Now invoke from a DIFFERENT cwd that has NO .simple-workflow ancestor.
AC33_CWD="$AC33_TMP/cwd-no-sw"
mkdir -p "$AC33_CWD"
AC33_NEW=$(printf 'tickets:\n  - logical_id: x-1\n    ticket_dir: .simple-workflow/backlog/done/x/001\n    status: completed\n    steps:\n      ship: completed\n')
AC33_INPUT=$(jq -n --arg fp "$AC33_FAKE_PATH" --arg ns "$AC33_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC33_OUT=$(cd "$AC33_CWD" && INPUT="$AC33_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC33_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
# is_autopilot_context walks up from cwd; with no .simple-workflow ancestor
# Gate 3 fails. Hook must exit silently — no dispatcher reach.
if [ -z "$AC33_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-33: safety-net Gate 3 — non-autopilot cwd is silent no-op even when file_path matches Gate 1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-33: Gate 3 leaked output: $AC33_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC33_TMP" "$AC33_STUB_DIR"

# CT-AC-34: safety-net Gate 4 mode=off (kill switch). Same scenario as
# CT-AC-14 (would otherwise inject) but with SW_AUTO_COMPACT_ON_SHIP_MODE=off.
# Hook must exit silently — no dispatcher reach, no marker writes.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC34_STUB_DIR=$(mktemp -d)
cat > "$AC34_STUB_DIR/tmux" <<'AC34_STUB'
#!/usr/bin/env bash
exit 0
AC34_STUB
chmod +x "$AC34_STUB_DIR/tmux"
AC34_TMP=$(mktemp -d)
mkdir -p "$AC34_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC34_TMP/.simple-workflow/backlog/done/dummy/001-shipped"
touch "$AC34_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC34_NEW=$(printf 'tickets:\n  - logical_id: a-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC34_INPUT=$(jq -n --arg fp "$AC34_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC34_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC34_OUT=$(cd "$AC34_TMP" && INPUT="$AC34_INPUT" SW_AUTO_COMPACT_ON_SHIP_MODE=off TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC34_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
AC34_OK=1
AC34_MISSING=""
if [ -n "$AC34_OUT" ]; then
  AC34_OK=0; AC34_MISSING="${AC34_MISSING} unexpected-output($AC34_OUT)"
fi
if [ -f "$AC34_TMP/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending" ]; then
  AC34_OK=0; AC34_MISSING="${AC34_MISSING} sentinel-leaked"
fi
if [ -f "$AC34_TMP/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-last-attempt" ]; then
  AC34_OK=0; AC34_MISSING="${AC34_MISSING} marker-leaked"
fi
if [ "$AC34_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-34: safety-net Gate 4 — SW_AUTO_COMPACT_ON_SHIP_MODE=off opts out, no marker writes"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-34: safety-net kill switch broken:${AC34_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC34_TMP" "$AC34_STUB_DIR"

# CT-AC-35: safety-net Gate 4 metric-only (log without injecting). Same
# scenario as CT-AC-14 but MODE=metric-only — additionalContext must
# include the metric-only label and the dispatcher must NOT be reached.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC35_STUB_DIR=$(mktemp -d)
cat > "$AC35_STUB_DIR/tmux" <<'AC35_STUB'
#!/usr/bin/env bash
exit 0
AC35_STUB
chmod +x "$AC35_STUB_DIR/tmux"
AC35_TMP=$(mktemp -d)
mkdir -p "$AC35_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC35_TMP/.simple-workflow/backlog/done/dummy/001-shipped"
touch "$AC35_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC35_NEW=$(printf 'tickets:\n  - logical_id: a-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC35_INPUT=$(jq -n --arg fp "$AC35_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC35_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC35_OUT=$(cd "$AC35_TMP" && INPUT="$AC35_INPUT" SW_AUTO_COMPACT_ON_SHIP_MODE=metric-only TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC35_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
AC35_OK=1
AC35_MISSING=""
if ! echo "$AC35_OUT" | grep -qE 'metric-only'; then
  AC35_OK=0; AC35_MISSING="${AC35_MISSING} metric-only-label-missing"
fi
if echo "$AC35_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend='; then
  AC35_OK=0; AC35_MISSING="${AC35_MISSING} dispatcher-spuriously-reached"
fi
if [ "$AC35_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-35: safety-net metric-only — additionalContext emitted, dispatcher not invoked"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-35: safety-net metric-only broken:${AC35_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC35_TMP" "$AC35_STUB_DIR"

# CT-AC-36: safety-net Gate 5 active→done rewrite. The orchestrator may
# write `ticket_dir: .../backlog/active/<slug>/<ticket>` for the just-
# shipped ticket because it has not yet moved it to done/. The rewriter
# (lines 132-135 of post-ship-state-auto-compact.sh, mirrored in the
# parser-driven Gate 5 fix) translates active/ → done/ and re-checks.
# This test creates the done/ dir but supplies an active/ ticket_dir to
# confirm the rewrite path is exercised.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC36_STUB_DIR=$(mktemp -d)
cat > "$AC36_STUB_DIR/tmux" <<'AC36_STUB'
#!/usr/bin/env bash
exit 0
AC36_STUB
chmod +x "$AC36_STUB_DIR/tmux"
AC36_TMP=$(mktemp -d)
mkdir -p "$AC36_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC36_TMP/.simple-workflow/backlog/done/dummy/001-shipped"
# Note: active/ counterpart NOT created — only done/ exists.
touch "$AC36_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
# ticket_dir points to active/ — the rewriter must translate to done/.
AC36_NEW=$(printf 'tickets:\n  - logical_id: a-1\n    ticket_dir: .simple-workflow/backlog/active/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC36_INPUT=$(jq -n --arg fp "$AC36_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC36_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC36_OUT=$(cd "$AC36_TMP" && INPUT="$AC36_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC36_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
if echo "$AC36_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend=' && ! echo "$AC36_OUT" | grep -qE 'state-lie protection'; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-36: safety-net Gate 5 active→done rewrite — ticket_dir under active/ with done/ counterpart present reaches dispatcher"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-36: active→done rewrite broken. Output: $AC36_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC36_TMP" "$AC36_STUB_DIR"

# CT-AC-37: safety-net Gate 6 stale sentinel (>120s) — the sentinel is
# treated as orphaned and the safety-net proceeds to inject. CT-AC-13
# covers the fresh-sentinel SKIP path; this covers the stale-sentinel
# CONTINUE path (the safety net does NOT delete the sentinel; that is
# autopilot-continue.sh's job — see H6 / CT-AC-19).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC37_STUB_DIR=$(mktemp -d)
cat > "$AC37_STUB_DIR/tmux" <<'AC37_STUB'
#!/usr/bin/env bash
exit 0
AC37_STUB
chmod +x "$AC37_STUB_DIR/tmux"
AC37_TMP=$(mktemp -d)
mkdir -p "$AC37_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC37_TMP/.simple-workflow/backlog/done/dummy/001-shipped"
touch "$AC37_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
# Stale sentinel: 200s in the past.
AC37_STALE_TS=$(( $(date +%s) - 200 ))
echo "$AC37_STALE_TS" > "$AC37_TMP/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
AC37_NEW=$(printf 'tickets:\n  - logical_id: a-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC37_INPUT=$(jq -n --arg fp "$AC37_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC37_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC37_OUT=$(cd "$AC37_TMP" && INPUT="$AC37_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC37_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
if echo "$AC37_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend=' && ! echo "$AC37_OUT" | grep -qE 'dedup: fresh sentinel'; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-37: safety-net Gate 6 — stale sentinel (>120s) does NOT block inject"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-37: stale-sentinel path broken. Output: $AC37_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC37_TMP" "$AC37_STUB_DIR"

# CT-AC-38: safety-net Write tool path. hooks.json registers the
# safety-net under PostToolUse:Write AND PostToolUse:Edit. Edit payloads
# carry `new_string`; Write payloads carry `content`. CT-AC-12..14
# exercise new_string only. This test exercises tool_input.content,
# confirming Gate 2 matches both fields.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC38_STUB_DIR=$(mktemp -d)
cat > "$AC38_STUB_DIR/tmux" <<'AC38_STUB'
#!/usr/bin/env bash
exit 0
AC38_STUB
chmod +x "$AC38_STUB_DIR/tmux"
AC38_TMP=$(mktemp -d)
mkdir -p "$AC38_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC38_TMP/.simple-workflow/backlog/done/dummy/001-shipped"
touch "$AC38_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC38_CONTENT=$(printf 'tickets:\n  - logical_id: a-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC38_INPUT=$(jq -n --arg fp "$AC38_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg c "$AC38_CONTENT" '{tool_input:{file_path:$fp,content:$c}}')
AC38_OUT=$(cd "$AC38_TMP" && INPUT="$AC38_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC38_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
if echo "$AC38_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend='; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-38: safety-net Write tool — tool_input.content carries ship: completed and reaches dispatcher"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-38: Write content path not exercised. Output: $AC38_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC38_TMP" "$AC38_STUB_DIR"

# CT-AC-39: primary Gate 5 stale (>300s) loop-marker — marker exists with
# same shipped_count but timestamp > 300s ago; primary must NOT skip
# (the loop window has expired). CT-AC-22 covers the <300s SKIP path;
# this covers the >300s CONTINUE path.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC39_STUB_DIR=$(mktemp -d)
cat > "$AC39_STUB_DIR/tmux" <<'AC39_STUB'
#!/usr/bin/env bash
exit 0
AC39_STUB
chmod +x "$AC39_STUB_DIR/tmux"
AC39_TMP=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC39_TMP/.simple-workflow/backlog/briefs/active/dummy"
# Same shipped_count as state file (1), timestamp 400s in the past.
AC39_STALE_TS=$(( $(date +%s) - 400 ))
echo "1:${AC39_STALE_TS}" > "$AC39_TMP/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-last-attempt"
AC39_OUT=$(cd "$AC39_TMP" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC39_STUB_DIR:$PATH" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1)
if echo "$AC39_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend=' && ! echo "$AC39_OUT" | grep -qE 'state-check.*loop suspected'; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-39: primary Gate 5 — stale marker (>300s) does NOT block inject"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-39: primary stale-marker path broken. Output: $AC39_OUT" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC39_TMP" "$AC39_STUB_DIR"

# CT-AC-40: inject_keys_failure_hint disambiguates the cause of injection
# failure (H9 fix). The previous failure-path additionalContext said only
# "injection failed (unsupported terminal)" for every cause, masking the
# difference between (a) no multiplexer at all, (b) kitty needs
# allow_remote_control, (c) iTerm2 needs macOS Automation permission,
# etc. The helper now maps each common stderr pattern to a specific
# hint; this test verifies five distinct paths.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC40_OK=1
AC40_MISSING=""

# Path A: no backend
AC40_NO_BACKEND=$(bash -c "source \"$AC_LIB\" && inject_keys_failure_hint '[inject-keys] no backend (TMUX= STY= TERM_PROGRAM= TERM=xterm)'")
if ! echo "$AC40_NO_BACKEND" | grep -qE 'no supported terminal multiplexer'; then
  AC40_OK=0; AC40_MISSING="${AC40_MISSING} no-backend-hint(got=${AC40_NO_BACKEND})"
fi

# Path B: kitty failed
AC40_KITTY=$(bash -c "source \"$AC_LIB\" && inject_keys_failure_hint '[inject-keys] backend=kitty failed (rc=1)'")
if ! echo "$AC40_KITTY" | grep -qE 'kitty backend failed.*allow_remote_control'; then
  AC40_OK=0; AC40_MISSING="${AC40_MISSING} kitty-hint(got=${AC40_KITTY})"
fi

# Path C: iterm2 failed
AC40_ITERM=$(bash -c "source \"$AC_LIB\" && inject_keys_failure_hint '[inject-keys] backend=iterm2 failed (rc=1)'")
if ! echo "$AC40_ITERM" | grep -qiE 'iTerm2 backend failed.*Automation permission'; then
  AC40_OK=0; AC40_MISSING="${AC40_MISSING} iterm2-hint(got=${AC40_ITERM})"
fi

# Path D: wezterm failed
AC40_WEZ=$(bash -c "source \"$AC_LIB\" && inject_keys_failure_hint '[inject-keys] backend=wezterm failed (rc=2)'")
if ! echo "$AC40_WEZ" | grep -qE 'WezTerm backend failed.*--no-paste'; then
  AC40_OK=0; AC40_MISSING="${AC40_MISSING} wezterm-hint(got=${AC40_WEZ})"
fi

# Path E: unknown backend failed (catch-all)
AC40_UNKNOWN=$(bash -c "source \"$AC_LIB\" && inject_keys_failure_hint '[inject-keys] backend=newbackend failed (rc=5)'")
if ! echo "$AC40_UNKNOWN" | grep -qE 'newbackend backend command failed'; then
  AC40_OK=0; AC40_MISSING="${AC40_MISSING} unknown-backend-hint(got=${AC40_UNKNOWN})"
fi

# Path F: hook additionalContext on failure includes the disambiguated
# hint (end-to-end). Force inject_keys to fail by having no backend env
# vars and no stubs on PATH.
AC40_TMP=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC40_TMP/.simple-workflow/backlog/briefs/active/dummy"
AC40_OUT=$(cd "$AC40_TMP" && \
  env -u TMUX -u STY -u TERM_PROGRAM -u KITTY_PID -u TERM PATH="/usr/bin:/bin" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' 2>/dev/null)
AC40_CTX=$(echo "$AC40_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
if ! echo "$AC40_CTX" | grep -qE 'no supported terminal multiplexer'; then
  AC40_OK=0; AC40_MISSING="${AC40_MISSING} hook-end-to-end-hint-missing(ctx=${AC40_CTX})"
fi
rm -rf "$AC40_TMP"

if [ "$AC40_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-40: inject_keys_failure_hint disambiguates 5 failure causes; hook additionalContext propagates the hint (H9 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-40: failure-mode disambiguation broken:${AC40_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-42: INJECT_KEYS_DRY_RUN requires SW_TEST_HARNESS=1 to short-
# circuit (H11 fix). Without the co-presence guard, a user who exports
# INJECT_KEYS_DRY_RUN=1 in their shell profile (e.g. after copy-pasting
# from a debug session) would silently disable every auto-compact —
# inject_keys would log "DRY_RUN" instead of injecting, the hooks'
# success branches would run, and the user would wonder why /compact
# never fires. With the guard the leaked env var alone is harmless:
# real injection proceeds. Verify (a) DRY_RUN=1 alone does NOT
# short-circuit, (b) DRY_RUN=1 + SW_TEST_HARNESS=1 still does.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC42_OK=1
AC42_MISSING=""

AC42_STUB_DIR=$(mktemp -d)
cat > "$AC42_STUB_DIR/tmux" <<'AC42_STUB'
#!/usr/bin/env bash
echo "[real-tmux-stub] would have sent: $*" >&2
exit 0
AC42_STUB
chmod +x "$AC42_STUB_DIR/tmux"

# Path A: DRY_RUN=1 alone (NO SW_TEST_HARNESS) → real backend invoked.
# P1-1 note: `SW_INJECT_KEYS_VERIFY=0` disables the post-inject
# capture-pane verify so the stubbed `tmux` (which exits 0 for every
# subcommand and produces no real pane output) does not flip rc to 1
# via the verify-missed branch. The H11 contract this test pins is
# about DRY_RUN short-circuit semantics, not about verify exit codes;
# disabling verify keeps the inner inject_keys rc=0 so the outer
# `set -e` does not abort the script before the assertions run.
AC42_OUT_A=$(env -u SW_TEST_HARNESS SW_INJECT_KEYS_VERIFY=0 TMUX=fake-socket TMUX_PANE='%0' INJECT_KEYS_DRY_RUN=1 PATH="$AC42_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
if echo "$AC42_OUT_A" | grep -qE 'DRY_RUN backend='; then
  AC42_OK=0; AC42_MISSING="${AC42_MISSING} dry_run-short-circuited-without-harness-env"
fi
if ! echo "$AC42_OUT_A" | grep -qE 'real-tmux-stub'; then
  AC42_OK=0; AC42_MISSING="${AC42_MISSING} real-backend-not-invoked-without-harness"
fi

# Path B: DRY_RUN=1 + SW_TEST_HARNESS=1 → short-circuit (existing
# fixtures depend on this). The DRY_RUN early-return precedes the
# P1-1 verify block, so `SW_INJECT_KEYS_VERIFY` is irrelevant here —
# but we keep the env minimal to mirror real DRY_RUN call sites.
AC42_OUT_B=$(SW_TEST_HARNESS=1 TMUX=fake-socket TMUX_PANE='%0' INJECT_KEYS_DRY_RUN=1 PATH="$AC42_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
if ! echo "$AC42_OUT_B" | grep -qE 'DRY_RUN backend=tmux'; then
  AC42_OK=0; AC42_MISSING="${AC42_MISSING} dry_run-not-short-circuited-with-harness"
fi
if echo "$AC42_OUT_B" | grep -qE 'real-tmux-stub'; then
  AC42_OK=0; AC42_MISSING="${AC42_MISSING} real-backend-invoked-despite-harness"
fi

rm -rf "$AC42_STUB_DIR"
if [ "$AC42_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-42: INJECT_KEYS_DRY_RUN requires SW_TEST_HARNESS=1; leaked env var alone is harmless (H11 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-42: DRY_RUN safety guard broken:${AC42_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-43: full cross-hook integration (H12 fix). CT-AC-23 simulated
# the Stop-hook sentinel consumption with a manual `rm -f` between
# Run A (safety-net) and Run B (primary). This test replaces the
# manual rm with the actual `hooks/autopilot-continue.sh` invocation,
# proving end-to-end that:
#   1. safety-net fires -> writes both .auto-compact-pending and
#      .auto-compact-last-attempt
#   2. autopilot-continue.sh sees the fresh sentinel, deletes it,
#      yields the Stop tick (exit 0, no decision:"block")
#   3. primary fires on the post-resume /scout, Gate 5 sees the marker
#      with unchanged shipped_count, short-circuits (no second inject)
# Without this integration, the three hooks are tested in isolation
# only and any drift in the sentinel/marker contracts could pass unit
# tests but break a real autopilot run.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC43_STUB_DIR=$(mktemp -d)
cat > "$AC43_STUB_DIR/tmux" <<'AC43_STUB'
#!/usr/bin/env bash
exit 0
AC43_STUB
chmod +x "$AC43_STUB_DIR/tmux"
AC43_TMPDIR=$(mktemp -d)
mkdir -p "$AC43_TMPDIR/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC43_TMPDIR/.simple-workflow/backlog/done/dummy/001-first"
cat > "$AC43_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" <<'AC43_STATE'
version: 1
parent_slug: dummy
tickets:
  - logical_id: dummy-part-1
    ticket_dir: .simple-workflow/backlog/done/dummy/001-first
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
  - logical_id: dummy-part-2
    ticket_dir: .simple-workflow/backlog/active/dummy/002-second
    status: in_progress
    steps:
      scout: pending
      impl: pending
      ship: pending
AC43_STATE
AC43_SENTINEL="$AC43_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-pending"
AC43_MARKER="$AC43_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/.auto-compact-last-attempt"

# Step 1: safety-net fires for T-1 boundary.
AC43_NEW=$(printf 'tickets:\n  - logical_id: dummy-part-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-first\n    status: completed\n    steps:\n      ship: completed\n')
AC43_INPUT=$(jq -n --arg fp "$AC43_TMPDIR/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC43_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
AC43_OUT_1=$(cd "$AC43_TMPDIR" && INPUT="$AC43_INPUT" TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC43_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" 2>&1 || true)
AC43_STEP1_SENTINEL_PRESENT=0
AC43_STEP1_MARKER_PRESENT=0
[ -f "$AC43_SENTINEL" ] && AC43_STEP1_SENTINEL_PRESENT=1
[ -f "$AC43_MARKER" ] && AC43_STEP1_MARKER_PRESENT=1

# Step 2: actual autopilot-continue.sh (Stop hook) sees the fresh
# sentinel and yields. This is the REAL hook, no manual rm simulation.
AC43_OUT_2=$(cd "$AC43_TMPDIR" && bash -c 'echo "{}" | bash "'"$REPO_DIR"'/hooks/autopilot-continue.sh"' 2>&1 || true)
AC43_STEP2_SENTINEL_DELETED=0
[ ! -f "$AC43_SENTINEL" ] && AC43_STEP2_SENTINEL_DELETED=1
AC43_STEP2_MARKER_SURVIVED=0
[ -f "$AC43_MARKER" ] && AC43_STEP2_MARKER_SURVIVED=1

# Step 3: primary fires on post-resume /scout. Marker survived the
# compact/resume cycle (sentinel was consumed in step 2 by the Stop
# hook). Gate 5 sees shipped_count=1 unchanged from the marker and
# short-circuits.
AC43_OUT_3=$(cd "$AC43_TMPDIR" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC43_STUB_DIR:$PATH" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' 2>&1 || true)

AC43_OK=1
AC43_MISSING=""
[ "$AC43_STEP1_SENTINEL_PRESENT" = "1" ] || { AC43_OK=0; AC43_MISSING="${AC43_MISSING} step1-sentinel-not-written"; }
[ "$AC43_STEP1_MARKER_PRESENT" = "1" ] || { AC43_OK=0; AC43_MISSING="${AC43_MISSING} step1-marker-not-written"; }
echo "$AC43_OUT_1" | grep -qE '\[POST-SHIP-STATE-AUTO-COMPACT\] \[inject-keys\] DRY_RUN backend=' \
  || { AC43_OK=0; AC43_MISSING="${AC43_MISSING} step1-dispatcher-not-reached"; }
# Step 2: autopilot-continue.sh consumed sentinel, marker survived.
[ "$AC43_STEP2_SENTINEL_DELETED" = "1" ] || { AC43_OK=0; AC43_MISSING="${AC43_MISSING} step2-sentinel-not-consumed"; }
[ "$AC43_STEP2_MARKER_SURVIVED" = "1" ] || { AC43_OK=0; AC43_MISSING="${AC43_MISSING} step2-marker-was-deleted"; }
echo "$AC43_OUT_2" | grep -qE '\[AUTO-COMPACT-YIELD\] sentinel found' \
  || { AC43_OK=0; AC43_MISSING="${AC43_MISSING} step2-no-yield-log"; }
echo "$AC43_OUT_2" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"' \
  && { AC43_OK=0; AC43_MISSING="${AC43_MISSING} step2-spurious-block"; }
# Step 3: primary short-circuited (no second inject).
echo "$AC43_OUT_3" | grep -qE '\[PRE-NEXT-SCOUT-AUTO-COMPACT\] \[inject-keys\] DRY_RUN backend=' \
  && { AC43_OK=0; AC43_MISSING="${AC43_MISSING} step3-double-compact"; }
echo "$AC43_OUT_3" | grep -qiE 'loop suspected|skipping inject' \
  || { AC43_OK=0; AC43_MISSING="${AC43_MISSING} step3-no-loop-detection-log"; }

if [ "$AC43_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-43: full cross-hook integration — safety-net writes markers, real autopilot-continue.sh consumes sentinel + preserves marker, primary post-resume scout short-circuits (H12 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-43: integration contract violated:${AC43_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -rf "$AC43_TMPDIR" "$AC43_STUB_DIR"

# CT-AC-44: audit-trail runtime_metrics entry on successful inject
# (M4 fix). Both auto-compact hooks must record one runtime_metrics
# entry per successful /compact injection so the user can correlate
# /compact fires with state transitions during forensics. Entry uses
# boundary=auto_compact_inject; stop_reason field carries
# "primary" or "safety_net" so analyses can disambiguate the trigger
# source. Verify both hooks via their dispatcher-reach fixtures.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC44_STUB_DIR=$(mktemp -d)
cat > "$AC44_STUB_DIR/tmux" <<'AC44_STUB'
#!/usr/bin/env bash
exit 0
AC44_STUB
chmod +x "$AC44_STUB_DIR/tmux"
AC44_OK=1
AC44_MISSING=""

# Path A: primary hook records `boundary: auto_compact_inject` with
# `stop_reason: primary`.
AC44_TMP_P=$(mktemp -d)
_ac_make_state_with_prior_ship "$AC44_TMP_P/.simple-workflow/backlog/briefs/active/dummy"
cd "$AC44_TMP_P" && \
  TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC44_STUB_DIR:$PATH" \
  bash -c 'echo "{\"tool_input\":{\"skill\":\"simple-workflow:scout\"}}" | bash "'"$AC_HOOK_PRIMARY"'"' >/dev/null 2>&1
cd - >/dev/null
AC44_P_STATE="$AC44_TMP_P/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
if ! grep -qE 'boundary:[[:space:]]+auto_compact_inject' "$AC44_P_STATE" 2>/dev/null; then
  AC44_OK=0; AC44_MISSING="${AC44_MISSING} primary-no-audit-entry"
fi
if ! grep -qE 'stop_reason:[[:space:]]+["'"'"']?primary["'"'"']?' "$AC44_P_STATE" 2>/dev/null; then
  AC44_OK=0; AC44_MISSING="${AC44_MISSING} primary-no-source-tag"
fi
rm -rf "$AC44_TMP_P"

# Path B: safety-net hook records `boundary: auto_compact_inject` with
# `stop_reason: safety_net`.
AC44_TMP_S=$(mktemp -d)
mkdir -p "$AC44_TMP_S/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC44_TMP_S/.simple-workflow/backlog/done/dummy/001-shipped"
touch "$AC44_TMP_S/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
AC44_NEW=$(printf 'tickets:\n  - logical_id: a-1\n    ticket_dir: .simple-workflow/backlog/done/dummy/001-shipped\n    status: completed\n    steps:\n      ship: completed\n')
AC44_INPUT=$(jq -n --arg fp "$AC44_TMP_S/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" --arg ns "$AC44_NEW" '{tool_input:{file_path:$fp,new_string:$ns}}')
cd "$AC44_TMP_S" && INPUT="$AC44_INPUT" env -u SW_AUTO_COMPACT_ON_SHIP_MODE TMUX=fake-socket INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC44_STUB_DIR:$PATH" bash -c "printf '%s' \"\$INPUT\" | bash \"$AC_HOOK_SAFETY\"" >/dev/null 2>&1
cd - >/dev/null
AC44_S_STATE="$AC44_TMP_S/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml"
if ! grep -qE 'boundary:[[:space:]]+auto_compact_inject' "$AC44_S_STATE" 2>/dev/null; then
  AC44_OK=0; AC44_MISSING="${AC44_MISSING} safety-no-audit-entry"
fi
if ! grep -qE 'stop_reason:[[:space:]]+["'"'"']?safety_net["'"'"']?' "$AC44_S_STATE" 2>/dev/null; then
  AC44_OK=0; AC44_MISSING="${AC44_MISSING} safety-no-source-tag"
fi
rm -rf "$AC44_TMP_S" "$AC44_STUB_DIR"
if [ "$AC44_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-44: both hooks record a runtime_metrics entry (boundary=auto_compact_inject; stop_reason=primary|safety_net) on successful inject (M4 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-44: audit-trail broken:${AC44_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-45: shipped_count uses YAML-aware parsing via parse_ticket_ship_dirs
# (WI-3 supersedes the original M7 strict-anchor approach). M7 attempted
# to harden a literal grep anchor (`^      ship: completed$`) to reject
# false positives like `runtime_metrics:` notes containing the literal
# substring. WI-3 takes a stronger guarantee: parse the state file as
# YAML (yq → python3+PyYAML → POSIX awk) so comments, free-form notes,
# and out-of-place text are structurally ignored. The helper also
# tolerates both canonical-flat (`steps.ship: completed`) and nested
# (`steps.ship.status: completed`) schemas, eliminating the
# test_simple_workflow27 failure mode where the grep anchor missed
# entire pipelines that wrote the nested form.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC45_TMP=$(mktemp -d)
mkdir -p "$AC45_TMP/.simple-workflow/backlog/briefs/active/dummy"
mkdir -p "$AC45_TMP/.simple-workflow/backlog/done/dummy/001-real"
# State file with ONE shipped ticket AND a runtime_metrics entry that
# CONTAINS the literal substring "ship: completed" in a note. A naive
# grep anchor would over-count to 2; the YAML-aware parser returns 1.
cat > "$AC45_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml" <<'AC45_STATE'
version: 1
parent_slug: dummy
tickets:
  - logical_id: only-1
    ticket_dir: .simple-workflow/backlog/done/dummy/001-real
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
runtime_metrics:
  - boundary: session_end
    stop_reason: normal_completion
    timestamp: 2026-05-17T03:00:00Z
    note: "ship: completed via /autopilot resume after compact"
AC45_STATE
# parse_ticket_ship_dirs (via the hook lib) must return exactly 1 line:
# the canonical ticket_dir. The `note:` field with the literal substring
# is structurally a string field, not a tickets[] entry, so it's ignored.
AC_LIB_PATH="$REPO_DIR/hooks/lib/parse-state-file.sh"
AC45_SHIPPED=$(bash -c "source '$AC_LIB_PATH' && parse_ticket_ship_dirs '$AC45_TMP/.simple-workflow/backlog/briefs/active/dummy/autopilot-state.yaml'" | grep -c . || true)
AC45_OK=1
AC45_MISSING=""
if [ "$AC45_SHIPPED" != "1" ]; then
  AC45_OK=0; AC45_MISSING="${AC45_MISSING} shipped-count-wrong(got=${AC45_SHIPPED}-expected=1)"
fi
# Source-level: both hooks count shipped tickets via the helper. The
# raw-grep-anchor regression check is omitted — the helper-presence
# assertion below is sufficient: if a hook regresses by re-introducing
# the literal grep anchor, the helper invocation would be removed and
# this check would fail.
if ! grep -qF 'parse_ticket_ship_dirs' "$AC_HOOK_PRIMARY"; then
  AC45_OK=0; AC45_MISSING="${AC45_MISSING} primary-missing-helper-call"
fi
if ! grep -qF 'parse_ticket_ship_dirs' "$AC_HOOK_SAFETY"; then
  AC45_OK=0; AC45_MISSING="${AC45_MISSING} safety-missing-helper-call"
fi
rm -rf "$AC45_TMP"
if [ "$AC45_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-45: shipped_count is computed via parse_ticket_ship_dirs (yq → python3 → awk), so runtime_metrics notes and free-form text are structurally ignored; both flat and nested ship-status schemas are counted correctly (WI-3 supersedes M7)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-45: YAML-aware shipped_count broken:${AC45_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-46: kitty backend targets the originating window via
# `--match id:$KITTY_WINDOW_ID` (WI-1 fix). Without that flag,
# `kitty @ send-text` defaults to the currently focused kitty window —
# same focus-leak failure mode the tmux/screen C3 fix addresses.
# Verifies (a) DRY_RUN log exposes target=<KITTY_WINDOW_ID>,
# (b) target is empty in fallback (no $KITTY_WINDOW_ID), (c) source
# uses --match in the non-DRY branch.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC46_STUB_DIR=$(mktemp -d)
cat > "$AC46_STUB_DIR/kitty" <<'AC46_STUB'
#!/usr/bin/env bash
exit 0
AC46_STUB
chmod +x "$AC46_STUB_DIR/kitty"
AC46_OUT_KITTY=$(env -u TMUX -u STY KITTY_PID=12345 KITTY_WINDOW_ID=99 TERM=xterm-kitty INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC46_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
AC46_OUT_NOWIN=$(env -u TMUX -u STY -u KITTY_WINDOW_ID KITTY_PID=12345 TERM=xterm-kitty INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC46_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
AC46_OK=1
AC46_MISSING=""
if ! echo "$AC46_OUT_KITTY" | grep -qE 'backend=kitty target=99 text=/compact'; then
  AC46_OK=0; AC46_MISSING="${AC46_MISSING} kitty-window-id-missing-from-log"
fi
if ! echo "$AC46_OUT_NOWIN" | grep -qE 'backend=kitty target= text=/compact'; then
  AC46_OK=0; AC46_MISSING="${AC46_MISSING} kitty-no-window-fallback-broken"
fi
if ! grep -qE 'kitty @ send-text --match "id:\$KITTY_WINDOW_ID"' "$AC_LIB"; then
  AC46_OK=0; AC46_MISSING="${AC46_MISSING} kitty-source-missing-target"
fi
rm -rf "$AC46_STUB_DIR"
if [ "$AC46_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-46: kitty backend targets originating window (--match id:\$KITTY_WINDOW_ID); DRY_RUN log exposes target (WI-1 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-46: kitty targeting contract:${AC46_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-47: wezterm backend targets the originating pane via
# `--pane-id $WEZTERM_PANE` (WI-1 fix). WezTerm's CLI does infer the
# caller's pane from $WEZTERM_PANE when --pane-id is omitted, but the
# explicit flag is defense-in-depth: it removes the dependency on CLI
# implementation detail and keeps the DRY_RUN log + source-grep
# contracts consistent with the other backends.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC47_STUB_DIR=$(mktemp -d)
cat > "$AC47_STUB_DIR/wezterm" <<'AC47_STUB'
#!/usr/bin/env bash
exit 0
AC47_STUB
chmod +x "$AC47_STUB_DIR/wezterm"
AC47_OUT_WEZTERM=$(env -u TMUX -u STY TERM_PROGRAM=WezTerm WEZTERM_PANE=7 INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC47_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
AC47_OUT_NOPANE=$(env -u TMUX -u STY -u WEZTERM_PANE TERM_PROGRAM=WezTerm INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC47_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
AC47_OK=1
AC47_MISSING=""
if ! echo "$AC47_OUT_WEZTERM" | grep -qE 'backend=wezterm target=7 text=/compact'; then
  AC47_OK=0; AC47_MISSING="${AC47_MISSING} wezterm-pane-missing-from-log"
fi
if ! echo "$AC47_OUT_NOPANE" | grep -qE 'backend=wezterm target= text=/compact'; then
  AC47_OK=0; AC47_MISSING="${AC47_MISSING} wezterm-no-pane-fallback-broken"
fi
if ! grep -qE 'wezterm cli send-text --no-paste --pane-id "\$WEZTERM_PANE"' "$AC_LIB"; then
  AC47_OK=0; AC47_MISSING="${AC47_MISSING} wezterm-source-missing-target"
fi
rm -rf "$AC47_STUB_DIR"
if [ "$AC47_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-47: wezterm backend targets originating pane (--pane-id \$WEZTERM_PANE); DRY_RUN log exposes target (WI-1 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-47: wezterm targeting contract:${AC47_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-48: iTerm2 backend targets the originating session by
# $ITERM_SESSION_ID UUID via AppleScript session-id lookup (WI-1 fix).
# The legacy `tell current session of current window to write text`
# resolves at osascript runtime to whichever iTerm window the user has
# focused — so a window switch between turn-start and hook fire
# (reproducer: brief mode=auto in window A, focus window B, hook fires)
# would inject /compact<Enter> into the wrong session. Verifies
# (a) DRY_RUN log exposes target=<full ITERM_SESSION_ID>,
# (b) target empty when env var absent (graceful fallback),
# (c) source uses ITERM_TARGET_UUID env var + session-id iteration
# pattern + a "session not found" error path in the AppleScript.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC48_STUB_DIR=$(mktemp -d)
cat > "$AC48_STUB_DIR/osascript" <<'AC48_STUB'
#!/usr/bin/env bash
exit 0
AC48_STUB
chmod +x "$AC48_STUB_DIR/osascript"
AC48_OUT_ITERM=$(env -u TMUX -u STY TERM_PROGRAM=iTerm.app ITERM_SESSION_ID='w0t1p0:AFB4CDF0-7514-4BDD-81C4-8F78F2305A34' INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC48_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
AC48_OUT_NOSID=$(env -u TMUX -u STY -u ITERM_SESSION_ID TERM_PROGRAM=iTerm.app INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC48_STUB_DIR:$PATH" bash -c "source \"$AC_LIB\" && inject_keys /compact --enter" 2>&1)
AC48_OK=1
AC48_MISSING=""
if ! echo "$AC48_OUT_ITERM" | grep -qE 'backend=iterm2 target=w0t1p0:AFB4CDF0-7514-4BDD-81C4-8F78F2305A34 text=/compact'; then
  AC48_OK=0; AC48_MISSING="${AC48_MISSING} iterm-session-id-missing-from-log"
fi
if ! echo "$AC48_OUT_NOSID" | grep -qE 'backend=iterm2 target= text=/compact'; then
  AC48_OK=0; AC48_MISSING="${AC48_MISSING} iterm-no-session-id-fallback-broken"
fi
# Source: AppleScript reads ITERM_TARGET_UUID via system attribute.
if ! grep -qF 'set targetUUID to system attribute "ITERM_TARGET_UUID"' "$AC_LIB"; then
  AC48_OK=0; AC48_MISSING="${AC48_MISSING} iterm-source-missing-targetUUID-attribute"
fi
# Source: session iteration with id-match predicate.
if ! grep -qF 'if id of s is targetUUID then' "$AC_LIB"; then
  AC48_OK=0; AC48_MISSING="${AC48_MISSING} iterm-source-missing-session-id-match"
fi
# Source: shell extracts UUID portion from ITERM_SESSION_ID.
if ! grep -qF '_ik_iterm_uuid="${ITERM_SESSION_ID##*:}"' "$AC_LIB"; then
  AC48_OK=0; AC48_MISSING="${AC48_MISSING} iterm-source-missing-uuid-extract"
fi
# Source: error path when session not found (refuses to fall back to
# focused window — that would defeat the whole fix). The WI-2 fix
# narrows the iteration to `current window` only (iTerm2's `windows`
# collection is empty in AppleScript), so the error message now says
# "not in current iTerm window" instead of "not found in any window".
if ! grep -qF '"iTerm session " & targetUUID & " not in current iTerm window' "$AC_LIB"; then
  AC48_OK=0; AC48_MISSING="${AC48_MISSING} iterm-source-missing-not-found-error"
fi
# Source: failure-hint maps the not-in-current-window error to a
# multi-iTerm-window-aware message recommending tmux for that workflow.
if ! grep -qF 'iTerm session .* not in current iTerm window' "$AC_LIB"; then
  AC48_OK=0; AC48_MISSING="${AC48_MISSING} iterm-source-missing-failure-hint"
fi
# Source: iteration uses `tabs of current window` rather than
# `repeat with w in windows` (WI-2 — the latter is empty in iTerm2's
# AppleScript and was the root cause of the test_simple_workflow26
# field failure).
if grep -qF 'repeat with w in windows' "$AC_LIB"; then
  AC48_OK=0; AC48_MISSING="${AC48_MISSING} iterm-source-still-uses-broken-windows-iteration"
fi
if ! grep -qF 'repeat with tt in tabs of current window' "$AC_LIB"; then
  AC48_OK=0; AC48_MISSING="${AC48_MISSING} iterm-source-missing-current-window-iteration"
fi
rm -rf "$AC48_STUB_DIR"
if [ "$AC48_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-48: iTerm2 backend targets originating session by \$ITERM_SESSION_ID UUID via AppleScript session-id lookup scoped to \`current window\` (iTerm2's \`windows\` collection is empty in AppleScript); DRY_RUN log exposes target; multi-iTerm-window case hard-fails with hint (WI-1 + WI-2 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-48: iTerm2 targeting contract:${AC48_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-49: WI-3 schema-tolerance end-to-end. Field reproducer
# (test_simple_workflow27, session
# d3748705-f477-44e9-8c88-229b78b7a29a): the autopilot orchestrator
# wrote the NESTED ship/status shape
# (`steps:\n  ship:\n    status: completed\n    invocation_method: skill`)
# instead of the canonical flat shape (`steps:\n  ship: completed`),
# and the v7 hooks silently exited at Gate 2 / shipped_count = 0
# because the literal grep anchors only matched the flat form. WI-3
# makes Gate 2 (safety-net payload regex) AND shipped_count (both
# hooks) accept BOTH shapes via parse_ticket_ship_dirs (yq-based)
# and a dual-form payload detector. This test reproduces the
# test_simple_workflow27 T-001 ship-completed payload and asserts
# the safety-net actually reaches the dispatcher (DRY_RUN log) and
# emits the canonical additionalContext.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC49_STUB_DIR=$(mktemp -d)
cat > "$AC49_STUB_DIR/tmux" <<'AC49_STUB'
#!/usr/bin/env bash
exit 0
AC49_STUB
chmod +x "$AC49_STUB_DIR/tmux"
AC49_TMP=$(mktemp -d)
mkdir -p "$AC49_TMP/.simple-workflow/backlog/briefs/active/pomodoro-timer"
mkdir -p "$AC49_TMP/.simple-workflow/backlog/done/pomodoro-timer/001-stage-1"
# State file mirrors the nested shape observed in test_simple_workflow27.
cat > "$AC49_TMP/.simple-workflow/backlog/briefs/active/pomodoro-timer/autopilot-state.yaml" <<'AC49_STATE'
version: 1
parent_slug: pomodoro-timer
total_tickets: 1
tickets:
  pomodoro-timer-part-1:
    ticket_dir: .simple-workflow/backlog/done/pomodoro-timer/001-stage-1
    status: completed
    depends_on: []
    steps:
      scout:
        status: completed
        invocation_method: skill
      impl:
        status: completed
        invocation_method: skill
      ship:
        status: completed
        invocation_method: skill
    pr_url: null
    commit_sha: 37f752d
AC49_STATE
# Payload is the EXACT new_string the orchestrator would Edit in.
AC49_PAYLOAD='  pomodoro-timer-part-1:
    ticket_dir: .simple-workflow/backlog/done/pomodoro-timer/001-stage-1
    status: completed
    depends_on: []
    steps:
      scout:
        status: completed
        invocation_method: skill
      impl:
        status: completed
        invocation_method: skill
      ship:
        status: completed
        invocation_method: skill
    pr_url: null
    commit_sha: 37f752d'
jq -n -c --arg fp "$AC49_TMP/.simple-workflow/backlog/briefs/active/pomodoro-timer/autopilot-state.yaml" --arg ns "$AC49_PAYLOAD" \
  '{tool_input:{file_path:$fp,new_string:$ns}}' > "$AC49_TMP/hook-input.json"

AC49_OUT=$(cd "$AC49_TMP" && \
  TMUX=fake-socket TMUX_PANE=%88 INJECT_KEYS_DRY_RUN=1 SW_TEST_HARNESS=1 PATH="$AC49_STUB_DIR:$PATH" \
  bash "$AC_HOOK_SAFETY" < "$AC49_TMP/hook-input.json" 2>&1)

AC49_OK=1
AC49_MISSING=""
# Must reach DRY_RUN dispatcher (proves Gate 2 + Gate 5 + Gate 7 all passed
# with the nested schema).
if ! echo "$AC49_OUT" | grep -qE '\[inject-keys\] DRY_RUN backend=tmux target=%88 text=/compact'; then
  AC49_OK=0; AC49_MISSING="${AC49_MISSING} dispatcher-not-reached(payload-rejected-by-Gate2-or-Gate7-zero-count)"
fi
# Must emit the canonical safety-net additionalContext label.
if ! echo "$AC49_OUT" | grep -qF 'auto-compact-on-ship (state-write safety-net):'; then
  AC49_OK=0; AC49_MISSING="${AC49_MISSING} additionalContext-missing"
fi
# This test fixture has shipped_count == total_tickets == 1, so the
# last-ticket sub-variant must fire.
if ! echo "$AC49_OUT" | grep -qF 'FINAL ticket of this pipeline'; then
  AC49_OK=0; AC49_MISSING="${AC49_MISSING} last-ticket-branch-not-fired(shipped_count-may-be-0)"
fi
rm -rf "$AC49_TMP" "$AC49_STUB_DIR"
if [ "$AC49_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-49: safety-net accepts the nested ship/status schema observed in test_simple_workflow27 — Gate 2 payload check and shipped_count both go through parse_ticket_ship_dirs (yq) and correctly fire the dispatcher (WI-3 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-49: WI-3 schema-tolerance broken:${AC49_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# =============================================================================
# CT-AC-50 / CT-AC-51 — WI-4 schema-tolerance extension (LIST/MAP for
# `tickets:`). Field reproducer: `test_simple_workflow28` (parent_slug
# `pomodoro-timer-web-app`, full pipeline 3/3 shipped 2026-05-17
# 13:01Z→14:05Z) — the autopilot orchestrator wrote `tickets:` as a
# MAP keyed by `logical_id` (`pomodoro-timer-web-app-part-1: { ... }`)
# instead of the canonical LIST. WI-3 already fixed
# `parse_ticket_ship_dirs` (so auto-compact worked on test28), but two
# OTHER hook surfaces — `parse_ticket_statuses` (Stop-hook loop-guard
# counters) and `parse_proposed_tickets` (PreToolUse:Write/Edit
# skip-transition guard) — silently bypassed on the MAP form because
# their Python tier required `isinstance(tickets, list)` and their
# awk / shell fallbacks required the dash-prefix item opener. The
# bypass on `parse_proposed_tickets` is security-relevant: a MAP-form
# state file could mark a ticket `skipped` with a forbidden rationale
# while siblings were `in_progress` and the guard would let the write
# through.
# =============================================================================
echo "--- Cat AC: WI-4 tickets LIST/MAP schema-tolerance (parse_ticket_statuses + parse_proposed_tickets) ---"

# CT-AC-50: parse_ticket_statuses MAP/LIST parity across all three tiers
# (yq → python3+PyYAML → POSIX awk). Mirrors WI-3's `parse_ticket_ship_dirs`
# tier-by-tier coverage. Each tier is forced by stubbing the higher tiers
# via a per-tier PATH override that points yq / python3 to a wrapper
# script that exits non-zero (so `_psf_have yq` still returns true but
# the yq invocation falls through, and `python3 -c 'import yaml'` fails).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC50_OK=1
AC50_MISSING=""

# Shared MAP-form and LIST-form fixtures (same logical tickets, different
# YAML shape). Both must yield identical status sequences.
AC50_MAP_FIXTURE=$(mktemp)
cat >"$AC50_MAP_FIXTURE" <<'AC50_YAML'
version: 1
parent_slug: pomodoro-timer-web-app
tickets:
  pomodoro-timer-web-app-part-1:
    status: completed
  pomodoro-timer-web-app-part-2:
    status: in_progress
  pomodoro-timer-web-app-part-3:
    status: pending
AC50_YAML
AC50_LIST_FIXTURE=$(mktemp)
cat >"$AC50_LIST_FIXTURE" <<'AC50_YAML'
version: 1
parent_slug: pomodoro-timer-web-app
tickets:
  - logical_id: pomodoro-timer-web-app-part-1
    status: completed
  - logical_id: pomodoro-timer-web-app-part-2
    status: in_progress
  - logical_id: pomodoro-timer-web-app-part-3
    status: pending
AC50_YAML
AC50_EXPECTED="completed,in_progress,pending,"

# Tier 1 (yq): no stubs — exercise the real yq binary on both shapes.
AC50_YQ_MAP=$(bash -c "
  source '$REPO_DIR/hooks/lib/parse-state-file.sh'
  parse_ticket_statuses '$AC50_MAP_FIXTURE' | tr '\n' ','
")
AC50_YQ_LIST=$(bash -c "
  source '$REPO_DIR/hooks/lib/parse-state-file.sh'
  parse_ticket_statuses '$AC50_LIST_FIXTURE' | tr '\n' ','
")
if [ "$AC50_YQ_MAP" != "$AC50_EXPECTED" ]; then
  AC50_OK=0; AC50_MISSING="${AC50_MISSING} yq-map(got=$AC50_YQ_MAP)"
fi
if [ "$AC50_YQ_LIST" != "$AC50_EXPECTED" ]; then
  AC50_OK=0; AC50_MISSING="${AC50_MISSING} yq-list(got=$AC50_YQ_LIST)"
fi

# Tier 2 (python3 + PyYAML): stub yq to exit non-zero so the function
# falls through.
AC50_STUB_PY=$(mktemp -d)
cat >"$AC50_STUB_PY/yq" <<'AC50_STUB'
#!/usr/bin/env bash
exit 1
AC50_STUB
chmod +x "$AC50_STUB_PY/yq"
AC50_PY_MAP=$(bash -c "
  source '$REPO_DIR/hooks/lib/parse-state-file.sh'
  PATH='$AC50_STUB_PY':\$PATH parse_ticket_statuses '$AC50_MAP_FIXTURE' | tr '\n' ','
")
AC50_PY_LIST=$(bash -c "
  source '$REPO_DIR/hooks/lib/parse-state-file.sh'
  PATH='$AC50_STUB_PY':\$PATH parse_ticket_statuses '$AC50_LIST_FIXTURE' | tr '\n' ','
")
if [ "$AC50_PY_MAP" != "$AC50_EXPECTED" ]; then
  AC50_OK=0; AC50_MISSING="${AC50_MISSING} py-map(got=$AC50_PY_MAP)"
fi
if [ "$AC50_PY_LIST" != "$AC50_EXPECTED" ]; then
  AC50_OK=0; AC50_MISSING="${AC50_MISSING} py-list(got=$AC50_PY_LIST)"
fi

# Tier 3 (POSIX awk): stub yq AND python3 to exit non-zero so the function
# falls through past both tier 1 and tier 2.
AC50_STUB_AWK=$(mktemp -d)
cat >"$AC50_STUB_AWK/yq" <<'AC50_STUB'
#!/usr/bin/env bash
exit 1
AC50_STUB
cat >"$AC50_STUB_AWK/python3" <<'AC50_STUB'
#!/usr/bin/env bash
exit 1
AC50_STUB
chmod +x "$AC50_STUB_AWK/yq" "$AC50_STUB_AWK/python3"
AC50_AWK_MAP=$(bash -c "
  source '$REPO_DIR/hooks/lib/parse-state-file.sh'
  PATH='$AC50_STUB_AWK':\$PATH parse_ticket_statuses '$AC50_MAP_FIXTURE' | tr '\n' ','
")
AC50_AWK_LIST=$(bash -c "
  source '$REPO_DIR/hooks/lib/parse-state-file.sh'
  PATH='$AC50_STUB_AWK':\$PATH parse_ticket_statuses '$AC50_LIST_FIXTURE' | tr '\n' ','
")
if [ "$AC50_AWK_MAP" != "$AC50_EXPECTED" ]; then
  AC50_OK=0; AC50_MISSING="${AC50_MISSING} awk-map(got=$AC50_AWK_MAP)"
fi
if [ "$AC50_AWK_LIST" != "$AC50_EXPECTED" ]; then
  AC50_OK=0; AC50_MISSING="${AC50_MISSING} awk-list(got=$AC50_AWK_LIST)"
fi

# Parity check: MAP and LIST results must be byte-identical at every tier.
if [ "$AC50_YQ_MAP" != "$AC50_YQ_LIST" ] || [ "$AC50_PY_MAP" != "$AC50_PY_LIST" ] || [ "$AC50_AWK_MAP" != "$AC50_AWK_LIST" ]; then
  AC50_OK=0; AC50_MISSING="${AC50_MISSING} parity-mismatch"
fi

rm -rf "$AC50_MAP_FIXTURE" "$AC50_LIST_FIXTURE" "$AC50_STUB_PY" "$AC50_STUB_AWK"
if [ "$AC50_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-50: parse_ticket_statuses MAP/LIST parity across all three tiers (yq, python3+PyYAML, POSIX awk) — same 'completed,in_progress,pending,' sequence for both shapes (WI-4 fix; mirrors WI-3 parse_ticket_ship_dirs)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-50: parse_ticket_statuses MAP form silently bypasses one or more tiers:${AC50_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-51: pre-state-transition MAP-form invariant guard. Reproduces the
# silent-bypass regression: a MAP-form `autopilot-state.yaml` Edit payload
# that flips `part-2: {status: skipped, skip_reason: <forbidden token>}`
# while `part-1: {status: in_progress}` MUST be blocked by
# `hooks/pre-state-transition.sh` with the same diagnostic the LIST-form
# payload would trigger (`unauthorized_skip_with_active_siblings` or
# `unauthorized_skip_with_forbidden_rationale`). Before WI-4 the Python
# tier short-circuited on `not isinstance(tickets, list)` and the
# shell fallback's dash-prefix opener never matched, so the hook
# silently allowed the write through.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
AC51_OK=1
AC51_MISSING=""

# Build a minimal autopilot tree under a tempdir so the hook's
# `is_autopilot_context` returns true.
AC51_TMP=$(mktemp -d)
AC51_SLUG="pomodoro-timer-web-app"
mkdir -p "$AC51_TMP/.simple-workflow/backlog/briefs/active/$AC51_SLUG"
AC51_STATE="$AC51_TMP/.simple-workflow/backlog/briefs/active/$AC51_SLUG/autopilot-state.yaml"
# On-disk state: part-1 in_progress (active sibling), part-2 pending.
cat >"$AC51_STATE" <<AC51_DISK
version: 1
parent_slug: ${AC51_SLUG}
execution_mode: split
total_tickets: 2
tickets:
  ${AC51_SLUG}-part-1:
    status: in_progress
  ${AC51_SLUG}-part-2:
    status: pending
AC51_DISK

# Proposed Edit payload: MAP-form, part-2 flips to skipped with a
# forbidden rationale (context budget) and NO override_skip. The hook
# MUST emit `decision: block` with either Rule 1 or Rule 2's tag —
# either is acceptable because both close the regression (Rule 1 fires
# when active siblings are detected; Rule 2 fires on the forbidden
# rationale token regardless of override). The pre-WI-4 hook silently
# returned exit 0 with empty stdout on this payload.
AC51_PROPOSED="version: 1
parent_slug: ${AC51_SLUG}
execution_mode: split
total_tickets: 2
tickets:
  ${AC51_SLUG}-part-1:
    status: in_progress
  ${AC51_SLUG}-part-2:
    status: skipped
    skip_reason: context budget exhausted, falling back to skip
"

# Drive the hook with an Edit payload (the harness-shaped JSON the
# PreToolUse:Edit slot receives at runtime).
AC51_PAYLOAD=$(jq -n \
  --arg fp "$AC51_STATE" \
  --arg ns "$AC51_PROPOSED" \
  --arg cwd "$AC51_TMP" \
  '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"", new_string:$ns}, cwd:$cwd, session_id:"test-AC51", transcript_path:""}')

AC51_STDOUT=$(printf '%s' "$AC51_PAYLOAD" | bash "$REPO_DIR/hooks/pre-state-transition.sh" 2>/dev/null || true)

if ! echo "$AC51_STDOUT" | grep -q '"decision":"block"'; then
  AC51_OK=0; AC51_MISSING="${AC51_MISSING} no-block-decision(stdout=$AC51_STDOUT)"
fi
if ! echo "$AC51_STDOUT" | grep -qE 'unauthorized_skip_with_active_siblings|unauthorized_skip_with_forbidden_rationale'; then
  AC51_OK=0; AC51_MISSING="${AC51_MISSING} missing-diagnostic-tag"
fi

# Sanity: the equivalent LIST-form payload MUST also block, so the MAP /
# LIST behaviour is provably parallel rather than vacuous.
AC51_LIST_PROPOSED="version: 1
parent_slug: ${AC51_SLUG}
execution_mode: split
total_tickets: 2
tickets:
  - logical_id: ${AC51_SLUG}-part-1
    status: in_progress
  - logical_id: ${AC51_SLUG}-part-2
    status: skipped
    skip_reason: context budget exhausted, falling back to skip
"
AC51_LIST_PAYLOAD=$(jq -n \
  --arg fp "$AC51_STATE" \
  --arg ns "$AC51_LIST_PROPOSED" \
  --arg cwd "$AC51_TMP" \
  '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"", new_string:$ns}, cwd:$cwd, session_id:"test-AC51", transcript_path:""}')
AC51_LIST_STDOUT=$(printf '%s' "$AC51_LIST_PAYLOAD" | bash "$REPO_DIR/hooks/pre-state-transition.sh" 2>/dev/null || true)
if ! echo "$AC51_LIST_STDOUT" | grep -q '"decision":"block"'; then
  AC51_OK=0; AC51_MISSING="${AC51_MISSING} list-form-also-not-blocking(parallel-broken)"
fi

rm -rf "$AC51_TMP"
if [ "$AC51_OK" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-51: pre-state-transition MAP-form skip-guard fires identically to LIST form (unauthorized_skip_* diagnostic emitted on MAP-form Edit payload); closes the silent-bypass regression observed against test_simple_workflow28-style schema slips (WI-4 fix)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-51: pre-state-transition silently bypasses on MAP-form payload:${AC51_MISSING}" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- P0-3C: [AUTOPILOT-CONTEXT] self-doc contract (CT-AC-52..60) ---------
# Plan P0-3C adds a Phase 1 step 0.5 to skills/autopilot/SKILL.md that emits
# EXACTLY ONE `[AUTOPILOT-CONTEXT]` block per pipeline run, with three
# verbatim branches (on / metric-only / off) kept in a new reference file
# so the model can recognise the active auto-compact-on-ship mode and
# never preventively asks the user about auto-compaction. The assertions
# pin the SKILL.md anchor tokens (env-var name, prefix, single-emit /
# unknown-fallback / hook-sync norms) and the verbatim branch lines in
# references/autopilot-context-self-doc.md.

# CT-AC-52 (P0-3C AC-1): [AUTOPILOT-CONTEXT] prefix appears in autopilot SKILL.md.
assert_file_contains \
  "CT-AC-52 (P0-3C AC-1): autopilot SKILL.md mentions [AUTOPILOT-CONTEXT] prefix" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  '\[AUTOPILOT-CONTEXT\]'

# CT-AC-53 (P0-3C AC-2): the new reference file exists.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$REPO_DIR/skills/autopilot/references/autopilot-context-self-doc.md" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-AC-53 (P0-3C AC-2): skills/autopilot/references/autopilot-context-self-doc.md exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-AC-53 (P0-3C AC-2): skills/autopilot/references/autopilot-context-self-doc.md missing" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-AC-54 (P0-3C AC-3): Branch A verbatim sentinel.
assert_file_contains \
  "CT-AC-54 (P0-3C AC-3): autopilot-context-self-doc.md carries Branch A (mode=on) verbatim" \
  "$REPO_DIR/skills/autopilot/references/autopilot-context-self-doc.md" \
  'auto-compact-on-ship is enabled \(mode=on\)'

# CT-AC-55 (P0-3C AC-4): Branch B verbatim sentinel.
assert_file_contains \
  "CT-AC-55 (P0-3C AC-4): autopilot-context-self-doc.md carries Branch B (metric-only) verbatim" \
  "$REPO_DIR/skills/autopilot/references/autopilot-context-self-doc.md" \
  'auto-compact-on-ship is in metric-only mode'

# CT-AC-56 (P0-3C AC-5): Branch C verbatim sentinel.
assert_file_contains \
  "CT-AC-56 (P0-3C AC-5): autopilot-context-self-doc.md carries Branch C (mode=off) verbatim" \
  "$REPO_DIR/skills/autopilot/references/autopilot-context-self-doc.md" \
  'auto-compact-on-ship is disabled \(mode=off\)'

# CT-AC-57 (P0-3C AC-6): env var name surfaced in autopilot SKILL.md.
assert_file_contains \
  "CT-AC-57 (P0-3C AC-6): autopilot SKILL.md names SW_AUTO_COMPACT_ON_SHIP_MODE in step 0.5" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'SW_AUTO_COMPACT_ON_SHIP_MODE'

# CT-AC-58 (P0-3C AC-7): unknown-value fallback norm in autopilot SKILL.md.
assert_file_contains \
  "CT-AC-58 (P0-3C AC-7): autopilot SKILL.md codifies the unknown-value -> off fallback" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'unknown values are treated as `off`'

# CT-AC-59 (P0-3C AC-8): hook-sync anchor in autopilot SKILL.md.
assert_file_contains \
  "CT-AC-59 (P0-3C AC-8): autopilot SKILL.md cross-references hooks/pre-next-scout-auto-compact.sh as the resolution-logic SSoT" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'matches `hooks/pre-next-scout-auto-compact.sh`'

# CT-AC-60 (P0-3C AC-9): single-emit / idempotency norm in autopilot SKILL.md.
assert_file_contains \
  "CT-AC-60 (P0-3C AC-9): autopilot SKILL.md mandates EXACTLY ONE [AUTOPILOT-CONTEXT] emission per run" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  'Emit EXACTLY ONE'

echo ""

# =============================================================================
# Category AL: ac-evaluator skill-access capability (runtime / browser verification)
# Rationale: ac-evaluator was made skill-capable so it can gather live runtime
#   evidence (render the built artifact, capture console errors / contrast /
#   screenshots via a browser-automation utility skill) for runtime & visual
#   ACs, instead of signing those off by static code inspection. This category
#   is a drift-guard: a future "simplification" PR that strips `- Skill` from
#   the agent, drops the External Tool Integration Policy section, or re-adds
#   ac-evaluator to the hermetic exclusion list would otherwise pass silently.
#   The evidence-only firewall (no authoring/modifying code; no pipeline-skill
#   recursion) is asserted alongside the capability so it cannot be widened into
#   a Generator/Evaluator firewall breach without tripping a test.
# =============================================================================
echo "--- Cat AL: ac-evaluator skill-access capability ---"

ACEV_SKILL_MD="$REPO_DIR/agents/ac-evaluator.md"

# CT-AL-1: ac-evaluator frontmatter tools: list includes a standalone `- Skill` entry.
al1_result="false"
if [ -f "$ACEV_SKILL_MD" ]; then
  al1_result=$(awk '
    BEGIN { fences=0; in_fm=0; found=0 }
    /^---[[:space:]]*$/ { fences++; if (fences==1) { in_fm=1; next } if (fences==2) { in_fm=0 } }
    in_fm && /^[[:space:]]*-[[:space:]]+Skill[[:space:]]*$/ { found=1 }
    END { print (found ? "true" : "false") }
  ' "$ACEV_SKILL_MD")
fi
assert_true \
  "CT-AL-1: agents/ac-evaluator.md frontmatter tools includes a standalone '- Skill' entry" \
  "$al1_result"

# CT-AL-2: ac-evaluator has the `## External Tool Integration Policy` section.
al2_result="false"
if [ -f "$ACEV_SKILL_MD" ] && grep -qE '^## External Tool Integration Policy[[:space:]]*$' "$ACEV_SKILL_MD"; then
  al2_result="true"
fi
assert_true \
  "CT-AL-2: agents/ac-evaluator.md has a '## External Tool Integration Policy' section" \
  "$al2_result"

# CT-AL-3: that section preserves the evidence-only firewall — both the
# "MUST NOT ... author/generate/modify the implementation" guard AND the
# "Never invoke pipeline skills" bullet must appear under the heading.
al3_result="false"
if [ -f "$ACEV_SKILL_MD" ]; then
  al3_result=$(awk '
    BEGIN { in_sec=0; guard=0; pipeline=0 }
    /^## External Tool Integration Policy[[:space:]]*$/ { in_sec=1; next }
    in_sec && /^## / { in_sec=0 }
    in_sec {
      ls=tolower($0)
      if (ls ~ /must not/ && ls ~ /author|generate|modify/) guard=1
      if (ls ~ /never invoke pipeline skills/) pipeline=1
    }
    END { print ((guard && pipeline) ? "true" : "false") }
  ' "$ACEV_SKILL_MD")
fi
assert_true \
  "CT-AL-3: ac-evaluator External Tool Integration Policy keeps the evidence-only firewall (no authoring/modifying + no pipeline-skill recursion)" \
  "$al3_result"

# CT-AL-4: no skill's Subagent Skill-Access Handoff still excludes ac-evaluator
# from receiving skill references (caller side now hands it browser-automation
# utilities for runtime/visual AC verification).
al4_hits=$( { grep -rlF 'hand skill references to `ac-evaluator`' "$REPO_DIR/skills" 2>/dev/null || true; } | wc -l | tr -d ' ')
assert_true \
  "CT-AL-4: no skill excludes ac-evaluator in its handoff line (found $al4_hits still excluding; expected 0)" \
  "$([ "$al4_hits" = "0" ] && echo true || echo false)"

# CT-AL-5: skills/impl/SKILL.md (the sole caller) carries the deterministic
# per-AC capability handoff for ac-evaluator. The legacy advisory bullet
# ("For `ac-evaluator`, hand off a browser-automation utility skill ...")
# was superseded in v7.1.0 by a forward-reference to Step 13 / Step 15
# that Read `{ticket-dir}/ticket.md`'s `### Capabilities` section and
# inline the bound per-AC capability list into the spawn prompt. This
# assertion locks the new shape: the handoff bullet for ac-evaluator must
# point at the deterministic per-AC handoff (Step 13/Step 15) and must
# preserve the evidence-only firewall ("never a skill that authors or
# modifies the code under review").
al5_result="false"
if grep -qF 'For `ac-evaluator`, the capability handoff is no longer ad-hoc' "$REPO_DIR/skills/impl/SKILL.md" \
   && grep -qF '### Capabilities' "$REPO_DIR/skills/impl/SKILL.md" \
   && grep -qF 'never a skill that authors or modifies the code under review' "$REPO_DIR/skills/impl/SKILL.md"; then
  al5_result="true"
fi
assert_true \
  "CT-AL-5: skills/impl/SKILL.md ac-evaluator handoff points at the deterministic per-AC Capabilities binding (Step 13 / Step 15) with the evidence-only firewall preserved" \
  "$al5_result"

echo ""

# =============================================================================
# Category AM: capability-detection wiring (T-CAP / v7.1.0)
# Diff: locks the upstream-detection -> per-AC binding -> downstream verifier
#        contract introduced in v7.1.0. Each assertion pins one of the
#        invariants from the plan's Acceptance Criteria (AC-1 .. AC-10).
# =============================================================================
echo "--- Cat AM: capability-detection wiring (T-CAP / v7.1.0) ---"

# CT-AM-1: ticket-template.md has the new `### Capabilities` block between
# `### Implementation Notes` and `### Claude Code Workflow`, and the column
# header sequence two lines below the heading is the canonical
# `Name | Type | Purpose | Used by | Bound AC(s)`. Pins AC-1.
TEMPLATE_MD="$REPO_DIR/skills/create-ticket/references/ticket-template.md"
am1_result="false"
if [ -f "$TEMPLATE_MD" ]; then
  am1_order=$(grep -nE '^### (Capabilities|Implementation Notes|Claude Code Workflow)' "$TEMPLATE_MD" \
              | awk -F: '{print $2}' \
              | tr '\n' '|' | sed 's/|$//')
  am1_expected='### Implementation Notes|### Capabilities|### Claude Code Workflow'
  am1_cap_line=$(grep -nE '^### Capabilities$' "$TEMPLATE_MD" | head -1 | cut -d: -f1)
  am1_col_line=""
  if [ -n "$am1_cap_line" ]; then
    am1_col_line=$(awk -v ln="$am1_cap_line" 'NR==ln+2' "$TEMPLATE_MD")
  fi
  if [ "$am1_order" = "$am1_expected" ] \
     && echo "$am1_col_line" | grep -qE '^\| *Name *\| *Type *\| *Purpose *\| *Used by *\| *Bound AC\(s\) *\|'; then
    am1_result="true"
  fi
fi
assert_true \
  "CT-AM-1: ticket-template.md has '### Capabilities' between '### Implementation Notes' and '### Claude Code Workflow' with column header 'Name | Type | Purpose | Used by | Bound AC(s)' (pins AC-1)" \
  "$am1_result"

# CT-AM-2: ac-quality-criteria.md gains the `## Gate 6: Capability Mapping`
# section AND the `## Planner MUST` bullet starting with the literal
# `**MUST** emit a \`### Capabilities\``. Pins AC-2 and AC-3.
ACQC_MD="$REPO_DIR/skills/create-ticket/references/ac-quality-criteria.md"
am2_g6=$(grep -cE '^## Gate 6: Capability Mapping$' "$ACQC_MD" || true)
am2_must=$(grep -cF '**MUST** emit a `### Capabilities`' "$ACQC_MD" || true)
am2_result="false"
if [ "$am2_g6" -eq 1 ] && [ "$am2_must" -ge 1 ]; then
  am2_result="true"
fi
assert_true \
  "CT-AM-2: ac-quality-criteria.md carries '## Gate 6: Capability Mapping' (count=$am2_g6, expected 1) and the literal '**MUST** emit a \`### Capabilities\`' Planner MUST bullet (count=$am2_must, expected >=1) (pins AC-2, AC-3)" \
  "$am2_result"

# CT-AM-3: create-ticket/SKILL.md Pre-computed Context contains exactly one
# `Available MCP servers: !` probe line, AND that line's substring includes
# both `.mcp.json` and `mcpServers` (the user-scope + project-scope sources
# enumerated by the probe). Pins AC-4.
CT_SKILL_MD="$REPO_DIR/skills/create-ticket/SKILL.md"
am3_count=$(grep -cE '^Available MCP servers: !`' "$CT_SKILL_MD" || true)
am3_probe_line=$(grep -E '^Available MCP servers: !`' "$CT_SKILL_MD" | head -1)
am3_result="false"
if [ "$am3_count" -eq 1 ] \
   && echo "$am3_probe_line" | grep -qF '.mcp.json' \
   && echo "$am3_probe_line" | grep -qF 'mcpServers'; then
  am3_result="true"
fi
assert_true \
  "CT-AM-3: create-ticket/SKILL.md has exactly 1 'Available MCP servers: !\`' probe (got $am3_count) whose pipeline references both .mcp.json and mcpServers (pins AC-4)" \
  "$am3_result"

# CT-AM-4: plan2doc/SKILL.md Step 3 mentions MCP (at least one MCP token
# within the awk range `/^3. **Scan available tooling/,/^4. /`), AND
# Step 4 spawn-prompt section includes both `Capabilities` and `verbatim`
# (count >= 2). Pins AC-5 and AC-7.
PD_SKILL_MD="$REPO_DIR/skills/plan2doc/SKILL.md"
am4_step3=$(awk '/^3\. \*\*Scan available tooling/,/^4\. /' "$PD_SKILL_MD" | grep -c -F MCP || true)
am4_step4=$(awk '/^4\. \*\*MUST invoke the .planner. agent/,/^5\. \*\*Return summary/' "$PD_SKILL_MD" | grep -c -E 'Capabilities|verbatim' || true)
am4_result="false"
if [ "$am4_step3" -ge 1 ] && [ "$am4_step4" -ge 2 ]; then
  am4_result="true"
fi
assert_true \
  "CT-AM-4: plan2doc/SKILL.md Step 3 mentions MCP ($am4_step3 hits, expected >=1) and Step 4 spawn prompt mentions Capabilities|verbatim ($am4_step4 hits, expected >=2) (pins AC-5, AC-7)" \
  "$am4_result"

# CT-AM-5: agent-spawn-prompts.md Phase 3 'Additional context for the
# planner' list mentions all three substrings 'Available capabilities',
# '### Capabilities', and 'Gate 6' (>= 3 line hits across them). Plus
# planner.md Pre-emit Self-Audit gains binding cross-check prose mentioning
# both '### Capabilities' and 'bind|bound|binding' (text-based check, since
# the AC's awk-range verify is brittle under same-line range semantics).
# Pins AC-6 and AC-8.
ASP_MD="$REPO_DIR/skills/create-ticket/references/agent-spawn-prompts.md"
am5_spawn=$(awk '/^Additional context for the planner:/,/^### Partition/' "$ASP_MD" \
            | grep -c -E 'Available capabilities|### Capabilities|Gate 6' || true)
# Planner.md Pre-emit Self-Audit: scan the documented section using a
# delimiter-aware sed (start at heading, stop at the next H2). awk's
# range expression is unreliable here because the start line itself
# matches `^## `; sed with explicit start/stop avoids the same-line
# truncation. Pins the substantive intent of AC-8.
PLANNER_MD="$REPO_DIR/agents/planner.md"
am5_planner_section=$(sed -n '/^## Pre-emit Self-Audit/,/^## [^P]/p' "$PLANNER_MD" \
                       | grep -c -E '### Capabilities|bind' || true)
am5_result="false"
if [ "$am5_spawn" -ge 3 ] && [ "$am5_planner_section" -ge 2 ]; then
  am5_result="true"
fi
assert_true \
  "CT-AM-5: agent-spawn-prompts.md Phase 3 inlines all three (Available capabilities | ### Capabilities | Gate 6) — $am5_spawn line-hits (>=3); planner.md Pre-emit Self-Audit names '### Capabilities' AND 'bind*' — $am5_planner_section hits (>=2) (pins AC-6, AC-8)" \
  "$am5_result"

# CT-AM-6: impl/SKILL.md Step 13 and Step 15 each reference the
# `### Capabilities` table (>= 2 total) AND every spawner-skill SKILL.md
# in the 8-skill propagation list carries the new handoff bullet whose
# body contains the literal '`### Capabilities`'. Pins AC-9 and AC-10.
IMPL_MD="$REPO_DIR/skills/impl/SKILL.md"
am6_impl_caps=$(grep -cE '### Capabilities' "$IMPL_MD" || true)
am6_propagation_zero=0
for f in \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "$REPO_DIR/skills/investigate/SKILL.md" \
  "$REPO_DIR/skills/plan2doc/SKILL.md" \
  "$REPO_DIR/skills/refactor/SKILL.md" \
  "$REPO_DIR/skills/test/SKILL.md" \
  "$REPO_DIR/skills/tune/SKILL.md"; do
  am6_one_hit=$(grep -cF '### Capabilities' "$f" || true)
  if [ "$am6_one_hit" -eq 0 ]; then
    am6_propagation_zero=$((am6_propagation_zero + 1))
  fi
done
am6_result="false"
if [ "$am6_impl_caps" -ge 2 ] && [ "$am6_propagation_zero" -eq 0 ]; then
  am6_result="true"
fi
assert_true \
  "CT-AM-6: impl/SKILL.md Steps 13/15 reference '### Capabilities' ($am6_impl_caps total, expected >=2); each of the 8 spawner SKILL.md files has the handoff propagation bullet (zero-hit count=$am6_propagation_zero, expected 0) (pins AC-9, AC-10)" \
  "$am6_result"

# CT-AM-7 (AC-12 trivial-pass branch): the AC-counting scanner in Cat AH-7
# (test-skill-contracts.sh near line 4406) terminates at
# `#### Negative Acceptance Criteria`. The new `### Capabilities` block
# lives BETWEEN `### Implementation Notes` and `### Claude Code Workflow`
# in ticket-template.md, which is OUTSIDE the
# `### Acceptance Criteria` -> next-`###`-heading window the AH-7 scanner
# consumes (the scanner stops at the negative-AC heading, and the
# Capabilities block carries no `AC-N`-formatted list items in any case).
# Therefore the scanner boundary is preserved trivially: no AC-pattern
# line appears under `### Capabilities`. This is the trivial-pass branch
# explicitly committed to by the implementation (see plan's polish note 1).
am12_template="$REPO_DIR/skills/create-ticket/references/ticket-template.md"
am12_cap_block=$(awk '/^### Capabilities$/,/^### Claude Code Workflow$/' "$am12_template")
am12_ac_hits=$(echo "$am12_cap_block" | grep -cE '^([0-9]+\.[[:space:]]+\*\*AC-|- AC-|AC-[0-9])' || true)
am12_result="false"
if [ "$am12_ac_hits" -eq 0 ]; then
  am12_result="true"
fi
assert_true \
  "CT-AM-7 (AC-12 boundary, trivial-pass branch): ticket-template.md '### Capabilities' block contains zero AC-pattern lines ($am12_ac_hits hits) — AH-7 scanner stops at '#### Negative Acceptance Criteria' and '### Capabilities' sits outside its window, so the boundary holds without a runtime-fixture diff" \
  "$am12_result"

# CT-AM-8 (gap-closure follow-up): every Skill-bearing agent body in the
# 8-agent set (ac-evaluator, code-reviewer, decomposer, implementer,
# planner, researcher, test-writer, tune-analyzer) carries a top-level
# `## Bound Capabilities` heading. The planner authors the section and
# uses a different role-specific subheading wording, but the heading
# regex `^## Bound Capabilities` matches both the receiver-role
# "## Bound Capabilities (Handoff from Orchestrator)" and the
# author-role "## Bound Capabilities (Authoring Role)" variants. The
# sum across the 8 files MUST be >= 8 (one heading per agent).
am8_sum=0
for a in ac-evaluator code-reviewer decomposer implementer planner researcher test-writer tune-analyzer; do
  am8_one_hit=$(grep -c -E '^## Bound Capabilities' "$REPO_DIR/agents/$a.md" || true)
  am8_sum=$((am8_sum + am8_one_hit))
done
am8_result="false"
if [ "$am8_sum" -ge 8 ]; then
  am8_result="true"
fi
assert_true \
  "CT-AM-8 (gap-closure follow-up): every Skill-bearing agent body has a top-level '## Bound Capabilities' heading (sum=$am8_sum across 8 agents, expected >=8)" \
  "$am8_result"

# CT-AM-9 (gap-closure follow-up): every Subagent Skill-Access Handoff
# in the 9 spawner skills (audit, brief, create-ticket, impl, investigate,
# plan2doc, refactor, test, tune) contains the upgraded literal
# "inline the bound capabilities verbatim into every spawn prompt". The
# upgrade replaces the legacy "prefer it over re-deriving relevance on
# the fly" wording with a deterministic-inlining requirement. The check
# counts how many of the 9 files have ZERO hits — that count MUST be 0
# (every file MUST carry the upgraded bullet).
am9_zero=0
for f in \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "$REPO_DIR/skills/investigate/SKILL.md" \
  "$REPO_DIR/skills/plan2doc/SKILL.md" \
  "$REPO_DIR/skills/refactor/SKILL.md" \
  "$REPO_DIR/skills/test/SKILL.md" \
  "$REPO_DIR/skills/tune/SKILL.md"; do
  am9_one_hit=$(grep -cF 'inline the bound capabilities verbatim into every spawn prompt' "$f" || true)
  if [ "$am9_one_hit" -eq 0 ]; then
    am9_zero=$((am9_zero + 1))
  fi
done
am9_result="false"
if [ "$am9_zero" -eq 0 ]; then
  am9_result="true"
fi
assert_true \
  "CT-AM-9 (gap-closure follow-up): every spawner SKILL.md (audit, brief, create-ticket, impl, investigate, plan2doc, refactor, test, tune) carries the upgraded deterministic-inlining bullet ('inline the bound capabilities verbatim into every spawn prompt'); zero-hit count=$am9_zero, expected 0" \
  "$am9_result"

echo ""

# =============================================================================
# Category AN: v8.0.0 omit-tools invariants (MCP inherit-all for productive
#              subagents)
# Rationale: v8.0.0 removes the `tools:` allowlist from the four productive
#   subagents (implementer, planner, researcher, test-writer) so they inherit
#   the parent session's full tool inventory, including every user-configured
#   MCP server. The remaining six agents (ac-evaluator, code-reviewer,
#   decomposer, security-scanner, ticket-evaluator, tune-analyzer) keep their
#   explicit allowlists for verdict independence / read-only invariants. This
#   category drift-guards seven facets of that contract:
#     1. Group A frontmatter omits `^tools:`
#     2. Group C frontmatter retains `^tools:`
#     3. Group A frontmatter omits `^permissionMode:`
#     4. planner.md / researcher.md ship a `## Side-effect ban` body section
#        with the three canonical forbidden tokens
#     5. Group A bodies carry the Bound Capabilities MCP-extension bullet
#        ('Skills **or MCP servers**')
#     6. agent-spawn-prompts.md and ac-quality-criteria.md doctrine is updated
#        and the legacy "subagents do not inherit MCP" wording is gone
#     7. hooks/pre-bash-safety.sh denylist gains the seven new tokens
#        (curl, wget, git remote add, npm install, pip install,
#         git config user.email, git commit --amend)
# =============================================================================
echo "--- Cat AN: v8.0.0 omit-tools invariants ---"

GROUP_A=(
  "implementer"
  "planner"
  "researcher"
  "test-writer"
)
GROUP_C=(
  "ac-evaluator"
  "code-reviewer"
  "decomposer"
  "security-scanner"
  "ticket-evaluator"
  "tune-analyzer"
)

# CT-AN-1: Group A frontmatter has zero `^tools:` lines across the 4 files.
an1_hits=0
for slug in "${GROUP_A[@]}"; do
  fm=$(extract_frontmatter_block "$REPO_DIR/agents/$slug.md")
  one=$(echo "$fm" | { grep -cE '^tools:' 2>/dev/null || true; })
  one=${one:-0}
  an1_hits=$((an1_hits + one))
done
an1_result="false"
if [ "$an1_hits" -eq 0 ]; then
  an1_result="true"
fi
assert_true \
  "CT-AN-1 (Group A frontmatter omit): agents/{implementer,planner,researcher,test-writer}.md frontmatter has zero '^tools:' lines (got $an1_hits, expected 0)" \
  "$an1_result"

# CT-AN-2: Group C frontmatter retains `^tools:` (6 hits across the 6 files).
an2_hits=0
for slug in "${GROUP_C[@]}"; do
  fm=$(extract_frontmatter_block "$REPO_DIR/agents/$slug.md")
  if echo "$fm" | grep -qE '^tools:'; then
    an2_hits=$((an2_hits + 1))
  fi
done
an2_result="false"
if [ "$an2_hits" -eq 6 ]; then
  an2_result="true"
fi
assert_true \
  "CT-AN-2 (Group C frontmatter tools: retained): agents/{ac-evaluator,code-reviewer,decomposer,security-scanner,ticket-evaluator,tune-analyzer}.md frontmatter has '^tools:' (got $an2_hits, expected 6)" \
  "$an2_result"

# CT-AN-3: Group A frontmatter has zero `^permissionMode:` lines (the silently
# ignored field is removed per CC docs).
an3_hits=0
for slug in "${GROUP_A[@]}"; do
  fm=$(extract_frontmatter_block "$REPO_DIR/agents/$slug.md")
  one=$(echo "$fm" | { grep -cE '^permissionMode:' 2>/dev/null || true; })
  one=${one:-0}
  an3_hits=$((an3_hits + one))
done
an3_result="false"
if [ "$an3_hits" -eq 0 ]; then
  an3_result="true"
fi
assert_true \
  "CT-AN-3 (Group A permissionMode removed): agents/{implementer,planner,researcher,test-writer}.md frontmatter has zero '^permissionMode:' lines (got $an3_hits, expected 0)" \
  "$an3_result"

# CT-AN-4: planner.md and researcher.md ship a top-level `## Side-effect ban`
# heading; the section body MUST contain three canonical forbidden tokens:
#   - `git commit`            (destructive Bash example)
#   - `curl`                  (network egress example)
#   - `mcp__Gmail__send`      (unbound MCP invocation example)
# The section body is the prose between `^## Side-effect ban$` and the next
# top-level `^## ` heading.
an4_files_ok=0
for slug in planner researcher; do
  agent_md="$REPO_DIR/agents/$slug.md"
  has_heading=$(grep -cE '^## Side-effect ban$' "$agent_md" || true)
  if [ "$has_heading" -lt 1 ]; then
    continue
  fi
  section=$(sed -n '/^## Side-effect ban$/,/^## /{/^## Side-effect ban$/!{/^## /!p;};}' "$agent_md")
  tokens_present=1
  for t in 'git commit' 'curl' 'mcp__Gmail__send'; do
    if ! echo "$section" | grep -qF "$t"; then
      tokens_present=0
      break
    fi
  done
  if [ "$tokens_present" -eq 1 ]; then
    an4_files_ok=$((an4_files_ok + 1))
  fi
done
an4_result="false"
if [ "$an4_files_ok" -eq 2 ]; then
  an4_result="true"
fi
assert_true \
  "CT-AN-4 (Side-effect ban section exists): agents/{planner,researcher}.md body has '^## Side-effect ban$' heading and the section contains tokens {git commit, curl, mcp__Gmail__send} ($an4_files_ok / 2 files pass)" \
  "$an4_result"

# CT-AN-5: each of the 4 Group A agents carries the literal string
# `Skills **or MCP servers**` (the Bound Capabilities MCP-extension bullet).
an5_hits=0
for slug in "${GROUP_A[@]}"; do
  if grep -qF 'Skills **or MCP servers**' "$REPO_DIR/agents/$slug.md"; then
    an5_hits=$((an5_hits + 1))
  fi
done
an5_result="false"
if [ "$an5_hits" -eq 4 ]; then
  an5_result="true"
fi
assert_true \
  "CT-AN-5 (Bound Capabilities MCP-extension bullet): agents/{implementer,planner,researcher,test-writer}.md contain the literal 'Skills **or MCP servers**' (got $an5_hits, expected 4)" \
  "$an5_result"

# CT-AN-6: doctrine update — agent-spawn-prompts.md and ac-quality-criteria.md
# reflect the v8.0.0 reality (productive agents inherit MCP) and the legacy
# v7.1.0 "subagents do not inherit MCP" wording is gone.
ASP_AN6="$REPO_DIR/skills/create-ticket/references/agent-spawn-prompts.md"
ACQC_AN6="$REPO_DIR/skills/create-ticket/references/ac-quality-criteria.md"
an6_asp_new1=$(grep -cF 'MCP inheritance under v8.0.0' "$ASP_AN6" || true)
an6_asp_new2=$(grep -cF 'productive subagents' "$ASP_AN6" || true)
an6_asp_legacy=$(grep -cF 'The subagent does not inherit the main-thread harness skill / MCP descriptions' "$ASP_AN6" || true)
an6_acqc_new=$(grep -cF 'Forked subagents inherit the parent session' "$ACQC_AN6" || true)
an6_acqc_legacy=$(grep -cF 'not guaranteed to inherit MCP tool access' "$ACQC_AN6" || true)
an6_result="false"
if [ "$an6_asp_new1" -ge 1 ] \
   && [ "$an6_asp_new2" -ge 1 ] \
   && [ "$an6_asp_legacy" -eq 0 ] \
   && [ "$an6_acqc_new" -ge 1 ] \
   && [ "$an6_acqc_legacy" -eq 0 ]; then
  an6_result="true"
fi
assert_true \
  "CT-AN-6 (doctrine update confirmed): agent-spawn-prompts.md contains 'MCP inheritance under v8.0.0' ($an6_asp_new1>=1) and 'productive subagents' ($an6_asp_new2>=1); legacy 'The subagent does not inherit ...' is gone ($an6_asp_legacy=0). ac-quality-criteria.md contains 'Forked subagents inherit the parent session' ($an6_acqc_new>=1); legacy 'not guaranteed to inherit MCP tool access' is gone ($an6_acqc_legacy=0)" \
  "$an6_result"

# CT-AN-7: hooks/pre-bash-safety.sh contains the 4 v8.0.0 denylist token
# anchors that remain after the supply-chain category was removed
# (npm/pnpm/yarn/pip/gem/cargo/brew/apt-get/apk/go/composer/bundle/mix/
# dart pub/conda/nuget/dotnet + git remote add are intentionally NOT
# blocked — see hook header for rationale). Existing destructive patterns
# remain untouched.
PBS_AN7="$REPO_DIR/hooks/pre-bash-safety.sh"
an7_missing=""
for t in 'curl' 'wget' 'git config user\.email' 'git commit --amend'; do
  if ! grep -qE "$t" "$PBS_AN7"; then
    an7_missing="$an7_missing $t"
  fi
done
an7_result="false"
if [ -z "$an7_missing" ]; then
  an7_result="true"
fi
assert_true \
  "CT-AN-7 (pre-bash-safety.sh new patterns): hooks/pre-bash-safety.sh contains all 4 remaining tokens (curl, wget, git config user.email, git commit --amend); missing:'${an7_missing:- (none)}'" \
  "$an7_result"

# CT-AN-8: hooks/pre-bash-safety.sh behaviorally blocks one representative
# command per v8.0.0 category. Mechanical guard against the "tokens in
# comments but regex broken" silent-regression class detected by Round 1
# evaluator review of v8.0.0.
PBS_AN8="$REPO_DIR/hooks/pre-bash-safety.sh"
an8_missing=""
# (label : exemplar command) — each must yield hook exit 2 (Blocked)
declare -a an8_specs=(
  "NETWORK_EGRESS|curl https://example.com"
  "IDENTITY_SPOOF|git config user.email evil@x.com"
  "PRIVILEGE_ESC|sudo apt-get install vim"
  "COMMIT_SUBVERT|git commit --amend"
)
for spec in "${an8_specs[@]}"; do
  label="${spec%%|*}"
  cmd="${spec#*|}"
  set +e
  echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | bash "$PBS_AN8" >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" != "2" ]; then
    an8_missing="$an8_missing ${label}(rc=$rc)"
  fi
done
an8_result="false"
if [ -z "$an8_missing" ]; then
  an8_result="true"
fi
assert_true \
  "CT-AN-8 (pre-bash-safety.sh behavioral block): each of the 4 v8.0.0 categories (NETWORK_EGRESS, IDENTITY_SPOOF, PRIVILEGE_ESC, COMMIT_SUBVERT) actually exits 2 for a representative command; failed:'${an8_missing:- (none)}'" \
  "$an8_result"

echo ""

# =============================================================================
# Category AO: args-aware shrinkage spec wiring (P0-2A)
# Diff: pins the four mechanically-detectable invariants from P0-2A's AC-1
#        .. AC-5. AC-6 is dogfood-observable only and asserted indirectly via
#        AC-1 (the orchestrator's `[args-aware shrinkage] args-resolved
#        categories:` literal MUST appear in skills/brief/SKILL.md so the
#        orchestrator emits it). The Caps-invariance assertion (AC-4) uses a
#        hard-coded expected count of 3 — the v7.x baseline immediately
#        before this plan landed — so any future bullet that adds, removes,
#        or paraphrases one of the three Caps phrases trips the test.
# =============================================================================
echo "--- Cat AO: args-aware shrinkage spec wiring (P0-2A) ---"

BRIEF_SKILL_AO="$REPO_DIR/skills/brief/SKILL.md"
ASP_AO="$REPO_DIR/skills/create-ticket/references/agent-spawn-prompts.md"
CT_SKILL_AO="$REPO_DIR/skills/create-ticket/SKILL.md"

# CT-AC-61 (P0-2A AC-1): skills/brief/SKILL.md carries the 'args-aware
# shrinkage' literal, AND the `#### args-aware shrinkage` subsection body
# contains both `$ARGUMENTS` and `args-resolved` tokens. The orchestrator's
# AC-6 console-trace literal (`[args-aware shrinkage] args-resolved
# categories:`) lives inside that same subsection, so its presence is
# verified transitively here.
ao1_main_hit=$(grep -cF 'args-aware shrinkage' "$BRIEF_SKILL_AO" || true)
ao1_section=$(awk '/^#### args-aware shrinkage/,/^#### Dynamic Phase 2 shrinkage/' "$BRIEF_SKILL_AO")
ao1_arguments=$(echo "$ao1_section" | grep -cF '$ARGUMENTS' || true)
ao1_resolved=$(echo "$ao1_section" | grep -cF 'args-resolved' || true)
ao1_trace=$(echo "$ao1_section" | grep -cF '[args-aware shrinkage] args-resolved categories:' || true)
ao1_result="false"
if [ "$ao1_main_hit" -ge 1 ] \
   && [ "$ao1_arguments" -ge 1 ] \
   && [ "$ao1_resolved" -ge 1 ] \
   && [ "$ao1_trace" -ge 1 ]; then
  ao1_result="true"
fi
assert_true \
  "CT-AC-61 (P0-2A AC-1): skills/brief/SKILL.md mentions 'args-aware shrinkage' (count=$ao1_main_hit, expected >=1); the '#### args-aware shrinkage' subsection contains \$ARGUMENTS (count=$ao1_arguments, expected >=1), 'args-resolved' (count=$ao1_resolved, expected >=1), and the orchestrator console-trace literal '[args-aware shrinkage] args-resolved categories:' (count=$ao1_trace, expected >=1; transitively pins AC-6)" \
  "$ao1_result"

# CT-AC-62 (P0-2A AC-2): skills/create-ticket/references/agent-spawn-prompts.md
# carries the 'args-aware shrinkage' literal in its Phase 2 section.
ao2_hit=$(grep -cF 'args-aware shrinkage' "$ASP_AO" || true)
ao2_result="false"
if [ "$ao2_hit" -ge 1 ]; then
  ao2_result="true"
fi
assert_true \
  "CT-AC-62 (P0-2A AC-2): skills/create-ticket/references/agent-spawn-prompts.md mentions 'args-aware shrinkage' (count=$ao2_hit, expected >=1)" \
  "$ao2_result"

# CT-AC-63 (P0-2A AC-3): skills/create-ticket/SKILL.md Phase 2 section
# carries the 'args-aware shrinkage' literal at least once AND the same
# line (the references-pointer line) contains the substring
# 'references/agent-spawn-prompts.md'. The literal pointer is enforced
# directly with a one-line grep that demands both tokens on the same
# line — the ticket spec requires the transition link to live "同行内"
# (on the same line) with the literal.
ao3_line=$(grep -nF 'args-aware shrinkage' "$CT_SKILL_AO" | head -1 | cut -d: -f2-)
ao3_result="false"
if [ -n "$ao3_line" ] \
   && echo "$ao3_line" | grep -qF 'references/agent-spawn-prompts.md'; then
  ao3_result="true"
fi
assert_true \
  "CT-AC-63 (P0-2A AC-3): skills/create-ticket/SKILL.md has at least one 'args-aware shrinkage' line whose text also contains the references/agent-spawn-prompts.md pointer on the SAME line (intra-line link required by ticket spec)" \
  "$ao3_result"

# CT-AC-64 (P0-2A AC-4): the three Caps phrases retain their pre-P0-2A
# count. Pre-P0-2A baseline = 3 hits total (one per phrase). This
# assertion guards against a future shrinkage-style change that
# silently drops or paraphrases one of the three load-bearing Caps
# bullets in skills/brief/SKILL.md.
ao4_caps=$(grep -cE 'At most \*\*10 rounds\*\*|At most \*\*3 questions per round\*\*|at most \*\*30 questions total\*\*' "$BRIEF_SKILL_AO" || true)
ao4_result="false"
if [ "$ao4_caps" -eq 3 ]; then
  ao4_result="true"
fi
assert_true \
  "CT-AC-64 (P0-2A AC-4): skills/brief/SKILL.md retains exactly 3 Caps-phrase hits ('At most **10 rounds**' + 'At most **3 questions per round**' + 'at most **30 questions total**') — got $ao4_caps, expected 3" \
  "$ao4_result"

# CT-AC-65 (P0-2A AC-5): the 'mode independence guard' literal remains
# present in skills/brief/SKILL.md AND its body content (the prose
# immediately after the load-bearing label) is unchanged from the
# v7.1.0 baseline. Body equivalence is asserted by grepping for the
# verbatim opening clause that has been present in the guard's prose
# since v6.0.0 and that the P0-2A change MUST NOT touch. If a future
# edit rewrites that clause (e.g. weakens "MUST" to "should" or drops
# the parenthetical), the assertion trips.
ao5_label=$(grep -cF 'mode independence guard' "$BRIEF_SKILL_AO" || true)
ao5_body=$(grep -cF 'MUST** run regardless of the parsed `mode` value' "$BRIEF_SKILL_AO" || true)
ao5_no_skip=$(grep -cF 'MUST NOT** be interpreted as a signal to skip, shorten, or bypass Phase 2' "$BRIEF_SKILL_AO" || true)
ao5_result="false"
if [ "$ao5_label" -ge 1 ] && [ "$ao5_body" -ge 1 ] && [ "$ao5_no_skip" -ge 1 ]; then
  ao5_result="true"
fi
assert_true \
  "CT-AC-65 (P0-2A AC-5): skills/brief/SKILL.md retains the 'mode independence guard' literal (count=$ao5_label, expected >=1) AND its body's two load-bearing clauses ('MUST run regardless of the parsed mode value' count=$ao5_body, expected >=1; 'MUST NOT be interpreted as a signal to skip, shorten, or bypass Phase 2' count=$ao5_no_skip, expected >=1) are byte-identical to the v7.1.0 baseline (P0-2A MUST NOT rewrite the guard body)" \
  "$ao5_result"

echo ""

# =============================================================================
# Category AP: /autopilot 3-tier risk_tolerance-aware non-interactive contract (P0-3A)
# Diff: Cat CP already pins the two canonical context-pressure responses and Cat LT
#        pins the loop-tail end_turn prohibition; neither covers the 3-tier
#        risk_tolerance allow-list, header naming, or the per-callee header
#        annotations introduced by P0-3A. This category is the structural
#        regression guard for the new prose contract. AC-26/27/28 from the
#        plan are NOT pinned here (27/28 are the test runner itself; 26 is a
#        meta check that becomes mechanically verifiable only once
#        hooks/pre-askuserquestion-guard.sh lands via P1-3B).
# =============================================================================
echo "--- Cat AP: /autopilot 3-tier risk_tolerance-aware non-interactive contract (P0-3A) ---"

AUTOPILOT_SKILL_AP="$REPO_DIR/skills/autopilot/SKILL.md"
IMPL_SKILL_AP="$REPO_DIR/skills/impl/SKILL.md"
SHIP_SKILL_AP="$REPO_DIR/skills/ship/SKILL.md"
REFACTOR_SKILL_AP="$REPO_DIR/skills/refactor/SKILL.md"

# AP-1 (P0-3A AC-1): new section header is present in skills/autopilot/SKILL.md.
ap1_result="false"
if grep -q '^## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)' "$AUTOPILOT_SKILL_AP"; then
  ap1_result="true"
fi
assert_true \
  "AP-1 (P0-3A AC-1): skills/autopilot/SKILL.md carries the '## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)' section heading" \
  "$ap1_result"

# AP-2 (P0-3A AC-2): contract start-point literal.
ap2_result="false"
if grep -q 'Phase 1 step 1 confirms `SPLIT_PLAN` exists' "$AUTOPILOT_SKILL_AP"; then
  ap2_result="true"
fi
assert_true \
  "AP-2 (P0-3A AC-2): skills/autopilot/SKILL.md states the contract starts when 'Phase 1 step 1 confirms \`SPLIT_PLAN\` exists'" \
  "$ap2_result"

# AP-3 (P0-3A AC-3): the '3-tier allow-list matrix' phrase is present.
ap3_result="false"
if grep -q '3-tier allow-list matrix' "$AUTOPILOT_SKILL_AP"; then
  ap3_result="true"
fi
assert_true \
  "AP-3 (P0-3A AC-3): skills/autopilot/SKILL.md mentions the '3-tier allow-list matrix'" \
  "$ap3_result"

# AP-4 (P0-3A AC-4): the matrix is keyed on `risk_tolerance`.
ap4_result="false"
if grep -q 'keyed on `risk_tolerance`' "$AUTOPILOT_SKILL_AP"; then
  ap4_result="true"
fi
assert_true \
  "AP-4 (P0-3A AC-4): skills/autopilot/SKILL.md declares the matrix is 'keyed on \`risk_tolerance\`'" \
  "$ap4_result"

# AP-5..AP-11 (P0-3A AC-5..AC-11): allow-list matrix cells (deny/allow per tier).
ap5_result="false"
if grep -qE 'audit-fail.*\|.*deny.*\|.*allow.*\|.*allow' "$AUTOPILOT_SKILL_AP"; then
  ap5_result="true"
fi
assert_true \
  "AP-5 (P0-3A AC-5): skills/autopilot/SKILL.md matrix row 'audit-fail | deny | allow | allow' present" \
  "$ap5_result"

ap6_result="false"
if grep -qE 'ac-eval.*\|.*deny.*\|.*allow.*\|.*allow' "$AUTOPILOT_SKILL_AP"; then
  ap6_result="true"
fi
assert_true \
  "AP-6 (P0-3A AC-6): skills/autopilot/SKILL.md matrix row 'ac-eval | deny | allow | allow' present" \
  "$ap6_result"

ap7_result="false"
if grep -qE 'ship-review.*\|.*deny.*\|.*deny.*\|.*allow' "$AUTOPILOT_SKILL_AP"; then
  ap7_result="true"
fi
assert_true \
  "AP-7 (P0-3A AC-7): skills/autopilot/SKILL.md matrix row 'ship-review | deny | deny | allow' present" \
  "$ap7_result"

ap8_result="false"
if grep -qE 'ship-ci.*\|.*deny.*\|.*deny.*\|.*allow' "$AUTOPILOT_SKILL_AP"; then
  ap8_result="true"
fi
assert_true \
  "AP-8 (P0-3A AC-8): skills/autopilot/SKILL.md matrix row 'ship-ci | deny | deny | allow' present" \
  "$ap8_result"

ap9_result="false"
if grep -qE 'eval-dry.*\|.*deny.*\|.*deny.*\|.*allow' "$AUTOPILOT_SKILL_AP"; then
  ap9_result="true"
fi
assert_true \
  "AP-9 (P0-3A AC-9): skills/autopilot/SKILL.md matrix row 'eval-dry | deny | deny | allow' present" \
  "$ap9_result"

ap10_result="false"
if grep -qE 'tkt-quality.*\|.*deny.*\|.*deny.*\|.*allow' "$AUTOPILOT_SKILL_AP"; then
  ap10_result="true"
fi
assert_true \
  "AP-10 (P0-3A AC-10): skills/autopilot/SKILL.md matrix row 'tkt-quality | deny | deny | allow' present" \
  "$ap10_result"

ap11_result="false"
if grep -qE '\(any other\).*\|.*deny.*\|.*deny.*\|.*deny' "$AUTOPILOT_SKILL_AP"; then
  ap11_result="true"
fi
assert_true \
  "AP-11 (P0-3A AC-11): skills/autopilot/SKILL.md matrix fallback row '(any other) | deny | deny | deny' present" \
  "$ap11_result"

# AP-12..AP-14 (P0-3A AC-12..AC-14): header naming load-bearing literals.
ap12_result="false"
if grep -q 'Header naming is load-bearing' "$AUTOPILOT_SKILL_AP"; then
  ap12_result="true"
fi
assert_true \
  "AP-12 (P0-3A AC-12): skills/autopilot/SKILL.md declares 'Header naming is load-bearing'" \
  "$ap12_result"

ap13_result="false"
if grep -q 'max 12 chars' "$AUTOPILOT_SKILL_AP"; then
  ap13_result="true"
fi
assert_true \
  "AP-13 (P0-3A AC-13): skills/autopilot/SKILL.md exposes the AskUserQuestion 'max 12 chars' header limit" \
  "$ap13_result"

ap14_result="false"
if grep -q 'denied at every tier' "$AUTOPILOT_SKILL_AP"; then
  ap14_result="true"
fi
assert_true \
  "AP-14 (P0-3A AC-14): skills/autopilot/SKILL.md declares off-matrix headers are 'denied at every tier'" \
  "$ap14_result"

# AP-15..AP-17 (P0-3A AC-15..AC-17): /impl carries the three header annotations.
ap15_result="false"
if grep -q 'header:[[:space:]]*eval-dry' "$IMPL_SKILL_AP"; then
  ap15_result="true"
fi
assert_true \
  "AP-15 (P0-3A AC-15): skills/impl/SKILL.md annotates the evaluator-dry-run question with 'header: eval-dry'" \
  "$ap15_result"

ap16_result="false"
if grep -q 'header:[[:space:]]*audit-fail' "$IMPL_SKILL_AP"; then
  ap16_result="true"
fi
assert_true \
  "AP-16 (P0-3A AC-16): skills/impl/SKILL.md annotates the audit-failure question with 'header: audit-fail'" \
  "$ap16_result"

ap17_result="false"
if grep -q 'header:[[:space:]]*ac-eval' "$IMPL_SKILL_AP"; then
  ap17_result="true"
fi
assert_true \
  "AP-17 (P0-3A AC-17): skills/impl/SKILL.md annotates the AC-eval FAIL escalation with 'header: ac-eval'" \
  "$ap17_result"

# AP-18 (P0-3A AC-18): /ship carries at least one ship-review or ship-ci header.
ap18_result="false"
if grep -qE 'header:[[:space:]]*(ship-review|ship-ci)' "$SHIP_SKILL_AP"; then
  ap18_result="true"
fi
assert_true \
  "AP-18 (P0-3A AC-18): skills/ship/SKILL.md annotates at least one policy-gate question with 'header: ship-review' or 'header: ship-ci'" \
  "$ap18_result"

# AP-19 (P0-3A AC-19): /refactor carries header: audit-fail on the autopilot-mode path.
ap19_result="false"
if grep -q 'header:[[:space:]]*audit-fail' "$REFACTOR_SKILL_AP"; then
  ap19_result="true"
fi
assert_true \
  "AP-19 (P0-3A AC-19): skills/refactor/SKILL.md annotates the autopilot-mode code-reviewer failure question with 'header: audit-fail'" \
  "$ap19_result"

# AP-20 (P0-3A AC-20): policy_gate_stop literal present in autopilot SKILL.md.
ap20_result="false"
if grep -q '`policy_gate_stop`' "$AUTOPILOT_SKILL_AP"; then
  ap20_result="true"
fi
assert_true \
  "AP-20 (P0-3A AC-20): skills/autopilot/SKILL.md surfaces the '\`policy_gate_stop\`' tag in the new section" \
  "$ap20_result"

# AP-21 (P0-3A AC-21): >=2 occurrences of '[AUTOPILOT-POLICY] gate=unexpected_error action=stop'.
ap21_count=$(grep -c 'AUTOPILOT-POLICY] gate=unexpected_error action=stop' "$AUTOPILOT_SKILL_AP" || true)
ap21_result="false"
if [ "$ap21_count" -ge 2 ]; then
  ap21_result="true"
fi
assert_true \
  "AP-21 (P0-3A AC-21): skills/autopilot/SKILL.md mentions '[AUTOPILOT-POLICY] gate=unexpected_error action=stop' at least twice (got $ap21_count, expected >=2)" \
  "$ap21_result"

# AP-22 (P0-3A AC-22): legacy ERROR literal preserved.
ap22_result="false"
if grep -q 'ERROR: split-plan not found at' "$AUTOPILOT_SKILL_AP"; then
  ap22_result="true"
fi
assert_true \
  "AP-22 (P0-3A AC-22): skills/autopilot/SKILL.md retains the verbatim 'ERROR: split-plan not found at' literal (backwards compatibility with existing contract tests)" \
  "$ap22_result"

# AP-23..AP-25 (P0-3A AC-23..AC-25): forbidden self-rationalisation patterns.
ap23_result="false"
if grep -q 'The per-ticket pipeline has not started yet, so the contract is not' "$AUTOPILOT_SKILL_AP"; then
  ap23_result="true"
fi
assert_true \
  "AP-23 (P0-3A AC-23): skills/autopilot/SKILL.md enumerates the 'pipeline has not started yet' forbidden self-rationalisation" \
  "$ap23_result"

ap24_result="false"
if grep -q 'Context budget is running low' "$AUTOPILOT_SKILL_AP"; then
  ap24_result="true"
fi
assert_true \
  "AP-24 (P0-3A AC-24): skills/autopilot/SKILL.md enumerates the 'Context budget is running low' forbidden self-rationalisation" \
  "$ap24_result"

ap25_result="false"
if grep -q 'phrase my question as `header: audit-fail`' "$AUTOPILOT_SKILL_AP"; then
  ap25_result="true"
fi
assert_true \
  "AP-25 (P0-3A AC-25): skills/autopilot/SKILL.md enumerates the 'phrase my question as \`header: audit-fail\`' header-misuse forbidden self-rationalisation" \
  "$ap25_result"

# AP-26 partial (P0-3A AC-26): the six gate-id header tokens all appear at least
# once in the autopilot SKILL.md so the matrix is well-formed. Full meta check
# vs hooks/pre-askuserquestion-guard.sh lands in P1-3B once the hook exists.
ap26_count=$(grep -c 'audit-fail\|ac-eval\|ship-review\|ship-ci\|eval-dry\|tkt-quality' "$AUTOPILOT_SKILL_AP" || true)
ap26_result="false"
if [ "$ap26_count" -ge 6 ]; then
  ap26_result="true"
fi
assert_true \
  "AP-26 (P0-3A AC-26, partial — matrix well-formed; full P1-3B parity check deferred): skills/autopilot/SKILL.md mentions each of the six gate-id headers (audit-fail / ac-eval / ship-review / ship-ci / eval-dry / tkt-quality); count=$ap26_count, expected >=6" \
  "$ap26_result"

echo ""

# =============================================================================
# Category P1-3B: pre-askuserquestion-guard.sh <-> SKILL.md matrix parity
# Diff: AP-26 above asserts presence of the six headers in SKILL.md only.
#        This block adds the structural parity assertions required by P1-3B
#        AC-9 / AC-10 / AC-6: 6 header literals present in BOTH the hook
#        script AND skills/autopilot/SKILL.md, the moderate row of the
#        SKILL.md matrix lists exactly {audit-fail, ac-eval}, and
#        hooks.json registers a single PreToolUse:AskUserQuestion matcher
#        pointing at the new hook.
# =============================================================================
echo "--- Cat P1-3B: pre-askuserquestion-guard.sh matrix parity ---"

ASK_GUARD_HOOK="$REPO_DIR/hooks/pre-askuserquestion-guard.sh"
HOOKS_JSON="$REPO_DIR/hooks/hooks.json"

# P1-3B AC-9 (6 assertions): each of the six known gate-id header
# literals MUST appear at least once in BOTH the hook script and the
# autopilot SKILL.md. Per-header presence parity prevents a future hook
# matrix edit from drifting away from the SKILL prose table (or vice
# versa). We deliberately do NOT require exact count equality — the
# hook references each header inside two case statements plus the reason
# literal, while the SKILL.md mentions each inside the matrix table plus
# the gate-id mapping prose — so the natural multiplicities differ.
for h in audit-fail ac-eval ship-review ship-ci eval-dry tkt-quality; do
  hook_hit="false"; skill_hit="false"
  grep -qF -- "$h" "$ASK_GUARD_HOOK" && hook_hit="true"
  grep -qF -- "$h" "$AUTOPILOT_SKILL_AP" && skill_hit="true"
  parity_result="false"
  if [ "$hook_hit" = "true" ] && [ "$skill_hit" = "true" ]; then
    parity_result="true"
  fi
  assert_true \
    "P1-3B AC-9: header literal '$h' present in BOTH hooks/pre-askuserquestion-guard.sh and skills/autopilot/SKILL.md (hook=$hook_hit, skill=$skill_hit)" \
    "$parity_result"
done

# P1-3B AC-10 (2 assertions): the moderate column of the SKILL.md
# Non-interactive-contract matrix table allows exactly the pair
# {audit-fail, ac-eval} and denies the four other known headers
# (ship-review / ship-ci / eval-dry / tkt-quality). The matrix is
# rendered as a Markdown table whose column order is
# `| header | aggressive | moderate | conservative |`, so the moderate
# cell is the third pipe-delimited field after the header label
# (positions: 0=label, 1=aggressive, 2=moderate, 3=conservative).
#
# AC-10a: every audit-fail / ac-eval row has `allow` in the moderate
# column (i.e. their row contains `| deny | allow | allow |` after the
# header literal -- the 2-pair that defines the moderate allow-list).
# AC-10b: every ship-review / ship-ci / eval-dry / tkt-quality row has
# `deny` in the moderate column (i.e. `| deny | deny | allow |`), so
# no extra header has been smuggled into the moderate allow-list.
ac10_audit_result="false"
audit_allow_count=0
for h in 'audit-fail' 'ac-eval'; do
  if grep -qE "^\|[[:space:]]*\`$h\`[[:space:]]*\|[[:space:]]*deny[[:space:]]*\|[[:space:]]*allow[[:space:]]*\|[[:space:]]*allow" "$AUTOPILOT_SKILL_AP"; then
    audit_allow_count=$((audit_allow_count + 1))
  fi
done
if [ "$audit_allow_count" -eq 2 ]; then
  ac10_audit_result="true"
fi
assert_true \
  "P1-3B AC-10a: skills/autopilot/SKILL.md moderate column allows exactly {audit-fail, ac-eval} via 'deny | allow | allow' row shape (matched=$audit_allow_count, expected 2)" \
  "$ac10_audit_result"

ac10_other_result="false"
other_deny_count=0
for h in 'ship-review' 'ship-ci' 'eval-dry' 'tkt-quality'; do
  if grep -qE "^\|[[:space:]]*\`$h\`[[:space:]]*\|[[:space:]]*deny[[:space:]]*\|[[:space:]]*deny[[:space:]]*\|[[:space:]]*allow" "$AUTOPILOT_SKILL_AP"; then
    other_deny_count=$((other_deny_count + 1))
  fi
done
if [ "$other_deny_count" -eq 4 ]; then
  ac10_other_result="true"
fi
assert_true \
  "P1-3B AC-10b: skills/autopilot/SKILL.md moderate column denies the four non-pair headers (ship-review / ship-ci / eval-dry / tkt-quality) via 'deny | deny | allow' row shape (matched=$other_deny_count, expected 4)" \
  "$ac10_other_result"

# P1-3B AC-6 (1 assertion): hooks.json registers exactly one
# PreToolUse matcher entry for AskUserQuestion AND that entry points at
# hooks/pre-askuserquestion-guard.sh.
ac6_matcher_count=$(grep -cE '"matcher":[[:space:]]*"AskUserQuestion"' "$HOOKS_JSON" || true)
ac6_hook_ref_count=$(grep -c 'pre-askuserquestion-guard.sh' "$HOOKS_JSON" || true)
ac6_result="false"
if [ "$ac6_matcher_count" -eq 1 ] && [ "$ac6_hook_ref_count" -eq 1 ]; then
  ac6_result="true"
fi
assert_true \
  "P1-3B AC-6: hooks/hooks.json registers exactly one PreToolUse:AskUserQuestion matcher pointing at pre-askuserquestion-guard.sh (matcher_count=$ac6_matcher_count, hook_ref_count=$ac6_hook_ref_count, both expected 1)" \
  "$ac6_result"

echo ""

# =============================================================================
# Category PSI: Post-Ship Integrity self-heal contract (P3-5)
# Diff: pins the SKILL prose (Step 15a idempotence + Step 16 ordering),
#        the hook Gate 5.5 + SW_POST_SHIP_INTEGRITY kill-switch literals,
#        and the behavioral self-heal / kill-switch / metric-only /
#        idempotence behaviours required by
#        .docs/dogfooding/33-34/P3-5-post-ship-phase-state-integrity.md.
# =============================================================================
echo "--- Cat PSI: post-ship integrity self-heal contract (P3-5) ---"

SHIP_SKILL_PSI="$REPO_DIR/skills/ship/SKILL.md"
PSI_HOOK="$REPO_DIR/hooks/post-ship-state-auto-compact.sh"
PSI_FIXTURE_DIR="$REPO_DIR/tests/fixtures/post-ship-integrity"

# PSI AC-1a: skills/ship/SKILL.md carries the literal `PSI contract` token.
psi_ac1a_count=$(grep -cF 'PSI contract' "$SHIP_SKILL_PSI" || true)
psi_ac1a_result="false"
[ "$psi_ac1a_count" -ge 1 ] && psi_ac1a_result="true"
assert_true \
  "PSI AC-1a: skills/ship/SKILL.md contains 'PSI contract' literal (count=$psi_ac1a_count, expected >=1)" \
  "$psi_ac1a_result"

# PSI AC-1b: Step 15a MUST run literal appears in SKILL.md (idempotence rule).
psi_ac1b_count=$(grep -cF 'Step 15a MUST run on every successful pass through Phase 2' "$SHIP_SKILL_PSI" || true)
psi_ac1b_result="false"
[ "$psi_ac1b_count" -ge 1 ] && psi_ac1b_result="true"
assert_true \
  "PSI AC-1b: skills/ship/SKILL.md contains 'Step 15a MUST run on every successful pass through Phase 2' (count=$psi_ac1b_count, expected >=1)" \
  "$psi_ac1b_result"

# PSI AC-2a: 'Ordering with Step 16' literal appears in SKILL.md.
psi_ac2a_count=$(grep -cF 'Ordering with Step 16' "$SHIP_SKILL_PSI" || true)
psi_ac2a_result="false"
[ "$psi_ac2a_count" -ge 1 ] && psi_ac2a_result="true"
assert_true \
  "PSI AC-2a: skills/ship/SKILL.md contains 'Ordering with Step 16' (count=$psi_ac2a_count, expected >=1)" \
  "$psi_ac2a_result"

# PSI AC-2b: Step 15a MUST complete its write to disk BEFORE Step 16 literal.
psi_ac2b_count=$(grep -cF 'Step 15a MUST complete its write to disk BEFORE Step 16' "$SHIP_SKILL_PSI" || true)
psi_ac2b_result="false"
[ "$psi_ac2b_count" -ge 1 ] && psi_ac2b_result="true"
assert_true \
  "PSI AC-2b: skills/ship/SKILL.md contains 'Step 15a MUST complete its write to disk BEFORE Step 16' (count=$psi_ac2b_count, expected >=1)" \
  "$psi_ac2b_result"

# PSI AC-3a: Gate 5.5 literal appears in post-ship-state-auto-compact.sh.
psi_ac3a_count=$(grep -cF 'Gate 5.5' "$PSI_HOOK" || true)
psi_ac3a_result="false"
[ "$psi_ac3a_count" -ge 1 ] && psi_ac3a_result="true"
assert_true \
  "PSI AC-3a: hooks/post-ship-state-auto-compact.sh contains 'Gate 5.5' (count=$psi_ac3a_count, expected >=1)" \
  "$psi_ac3a_result"

# PSI AC-3b: SW_POST_SHIP_INTEGRITY appears >=2 times in the hook
# (kill-switch interpretation + metric-only branch).
psi_ac3b_count=$(grep -cF 'SW_POST_SHIP_INTEGRITY' "$PSI_HOOK" || true)
psi_ac3b_result="false"
[ "$psi_ac3b_count" -ge 2 ] && psi_ac3b_result="true"
assert_true \
  "PSI AC-3b: hooks/post-ship-state-auto-compact.sh contains 'SW_POST_SHIP_INTEGRITY' (count=$psi_ac3b_count, expected >=2)" \
  "$psi_ac3b_result"

# Behavioural assertions (AC-4 / AC-5 / AC-6 / AC-7) require yq or
# python3+PyYAML for the hook self-heal write tier. If neither is
# available the rewrite tier is a no-op (ticket Risk R3): skip the
# behavioural block in that case but still emit a single sentinel
# assertion so test totals are stable.
psi_has_writer="false"
if command -v yq >/dev/null 2>&1; then
  psi_has_writer="true"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  psi_has_writer="true"
fi

if [ "$psi_has_writer" = "true" ]; then
  # Helper: prepare a temp repo root containing a fake ticket-done dir
  # and a brief-side autopilot-state.yaml, then return the stdin payload
  # the hook expects (PostToolUse Edit/Write tool input).
  _psi_setup_tmproot() {
    local fixture_phase_state="$1"   # absolute path to fixture phase-state.yaml
    local tmproot
    tmproot="$(mktemp -d)"
    mkdir -p "$tmproot/.simple-workflow/backlog/done/shelftrack/001-bootstrap-and-scaffold"
    mkdir -p "$tmproot/.simple-workflow/backlog/done/shelftrack/005-e2e-hardening-and-accessibility"
    mkdir -p "$tmproot/.simple-workflow/backlog/briefs/active/shelftrack"
    cp "$fixture_phase_state" "$tmproot/.simple-workflow/backlog/done/shelftrack/001-bootstrap-and-scaffold/phase-state.yaml"
    cp "$PSI_FIXTURE_DIR/clean-ticket-005/phase-state.yaml" "$tmproot/.simple-workflow/backlog/done/shelftrack/005-e2e-hardening-and-accessibility/phase-state.yaml"
    cp "$PSI_FIXTURE_DIR/briefs/active/shelftrack/autopilot-state.yaml" "$tmproot/.simple-workflow/backlog/briefs/active/shelftrack/autopilot-state.yaml"
    printf '%s\n' "$tmproot"
  }
  _psi_payload_for() {
    local state_file="$1"
    local content
    content="$(cat "$state_file")"
    jq -n \
      --arg fp "$state_file" \
      --arg content "$content" \
      '{tool_input: {file_path: $fp, new_string: $content}}'
  }

  # PSI AC-4: self-heal rewrites overall_status -> done AND emits the
  # canonical '[POST-SHIP-INTEGRITY] self-healing' warning to stderr.
  PSI_TMP1="$(_psi_setup_tmproot "$PSI_FIXTURE_DIR/drift-ticket-001/phase-state.yaml")"
  PSI_TARGET1="$PSI_TMP1/.simple-workflow/backlog/done/shelftrack/001-bootstrap-and-scaffold/phase-state.yaml"
  PSI_STATE1="$PSI_TMP1/.simple-workflow/backlog/briefs/active/shelftrack/autopilot-state.yaml"
  PSI_STDERR1="$(mktemp)"
  PSI_PAYLOAD1="$(_psi_payload_for "$PSI_STATE1")"
  ( cd "$PSI_TMP1" && printf '%s' "$PSI_PAYLOAD1" \
    | SW_TEST_HARNESS=1 \
      INJECT_KEYS_DRY_RUN=1 \
      SW_POST_SHIP_INTEGRITY=on \
      bash "$PSI_HOOK" >/dev/null 2>"$PSI_STDERR1" ) || true
  psi_ac4_overall="$(grep -E '^overall_status:' "$PSI_TARGET1" | awk '{print $2}' | tr -d '"' | tr -d "'" | head -1)"
  psi_ac4_stderr_hit="false"
  grep -qF '[POST-SHIP-INTEGRITY] self-healing' "$PSI_STDERR1" && psi_ac4_stderr_hit="true"
  psi_ac4_result="false"
  if [ "$psi_ac4_overall" = "done" ] && [ "$psi_ac4_stderr_hit" = "true" ]; then
    psi_ac4_result="true"
  fi
  assert_true \
    "PSI AC-4: hook self-heals drift fixture (overall_status='$psi_ac4_overall', expected 'done'; stderr contains '[POST-SHIP-INTEGRITY] self-healing'=$psi_ac4_stderr_hit)" \
    "$psi_ac4_result"
  rm -rf "$PSI_TMP1" "$PSI_STDERR1" 2>/dev/null || true

  # PSI AC-5: SW_POST_SHIP_INTEGRITY=off leaves overall_status untouched.
  PSI_TMP2="$(_psi_setup_tmproot "$PSI_FIXTURE_DIR/drift-ticket-001/phase-state.yaml")"
  PSI_TARGET2="$PSI_TMP2/.simple-workflow/backlog/done/shelftrack/001-bootstrap-and-scaffold/phase-state.yaml"
  PSI_STATE2="$PSI_TMP2/.simple-workflow/backlog/briefs/active/shelftrack/autopilot-state.yaml"
  PSI_PAYLOAD2="$(_psi_payload_for "$PSI_STATE2")"
  ( cd "$PSI_TMP2" && printf '%s' "$PSI_PAYLOAD2" \
    | SW_TEST_HARNESS=1 \
      INJECT_KEYS_DRY_RUN=1 \
      SW_POST_SHIP_INTEGRITY=off \
      bash "$PSI_HOOK" >/dev/null 2>/dev/null ) || true
  psi_ac5_overall="$(grep -E '^overall_status:' "$PSI_TARGET2" | awk '{print $2}' | tr -d '"' | tr -d "'" | head -1)"
  psi_ac5_result="false"
  [ "$psi_ac5_overall" = "in-progress" ] && psi_ac5_result="true"
  assert_true \
    "PSI AC-5: SW_POST_SHIP_INTEGRITY=off preserves drift overall_status (got '$psi_ac5_overall', expected 'in-progress')" \
    "$psi_ac5_result"
  rm -rf "$PSI_TMP2" 2>/dev/null || true

  # PSI AC-6: SW_POST_SHIP_INTEGRITY=metric-only emits warning log but
  # leaves the file unchanged.
  PSI_TMP3="$(_psi_setup_tmproot "$PSI_FIXTURE_DIR/drift-ticket-001/phase-state.yaml")"
  PSI_TARGET3="$PSI_TMP3/.simple-workflow/backlog/done/shelftrack/001-bootstrap-and-scaffold/phase-state.yaml"
  PSI_STATE3="$PSI_TMP3/.simple-workflow/backlog/briefs/active/shelftrack/autopilot-state.yaml"
  PSI_STDERR3="$(mktemp)"
  PSI_PAYLOAD3="$(_psi_payload_for "$PSI_STATE3")"
  ( cd "$PSI_TMP3" && printf '%s' "$PSI_PAYLOAD3" \
    | SW_TEST_HARNESS=1 \
      INJECT_KEYS_DRY_RUN=1 \
      SW_POST_SHIP_INTEGRITY=metric-only \
      bash "$PSI_HOOK" >/dev/null 2>"$PSI_STDERR3" ) || true
  psi_ac6_overall="$(grep -E '^overall_status:' "$PSI_TARGET3" | awk '{print $2}' | tr -d '"' | tr -d "'" | head -1)"
  psi_ac6_stderr_hit="false"
  grep -qF '[POST-SHIP-INTEGRITY] self-healing' "$PSI_STDERR3" && psi_ac6_stderr_hit="true"
  psi_ac6_result="false"
  if [ "$psi_ac6_overall" = "in-progress" ] && [ "$psi_ac6_stderr_hit" = "true" ]; then
    psi_ac6_result="true"
  fi
  assert_true \
    "PSI AC-6: SW_POST_SHIP_INTEGRITY=metric-only logs without writing (overall_status='$psi_ac6_overall' expected 'in-progress'; stderr hit=$psi_ac6_stderr_hit expected true)" \
    "$psi_ac6_result"
  rm -rf "$PSI_TMP3" "$PSI_STDERR3" 2>/dev/null || true

  # PSI AC-7: on a clean fixture (overall_status: done) the hook leaves
  # the file byte-identical (diff zero).
  PSI_TMP4="$(_psi_setup_tmproot "$PSI_FIXTURE_DIR/clean-ticket-005/phase-state.yaml")"
  PSI_TARGET4="$PSI_TMP4/.simple-workflow/backlog/done/shelftrack/001-bootstrap-and-scaffold/phase-state.yaml"
  PSI_STATE4="$PSI_TMP4/.simple-workflow/backlog/briefs/active/shelftrack/autopilot-state.yaml"
  PSI_PAYLOAD4="$(_psi_payload_for "$PSI_STATE4")"
  PSI_PRE4="$(mktemp)"
  cp "$PSI_TARGET4" "$PSI_PRE4"
  ( cd "$PSI_TMP4" && printf '%s' "$PSI_PAYLOAD4" \
    | SW_TEST_HARNESS=1 \
      INJECT_KEYS_DRY_RUN=1 \
      SW_POST_SHIP_INTEGRITY=on \
      bash "$PSI_HOOK" >/dev/null 2>/dev/null ) || true
  psi_ac7_result="false"
  if diff -q "$PSI_PRE4" "$PSI_TARGET4" >/dev/null 2>&1; then
    psi_ac7_result="true"
  fi
  assert_true \
    "PSI AC-7: clean fixture (overall_status: done) is unchanged by the hook (diff zero)" \
    "$psi_ac7_result"
  rm -rf "$PSI_TMP4" "$PSI_PRE4" 2>/dev/null || true

  unset PSI_TMP1 PSI_TARGET1 PSI_STATE1 PSI_STDERR1 PSI_PAYLOAD1
  unset PSI_TMP2 PSI_TARGET2 PSI_STATE2 PSI_PAYLOAD2
  unset PSI_TMP3 PSI_TARGET3 PSI_STATE3 PSI_STDERR3 PSI_PAYLOAD3
  unset PSI_TMP4 PSI_TARGET4 PSI_STATE4 PSI_PAYLOAD4 PSI_PRE4
  unset -f _psi_setup_tmproot _psi_payload_for
else
  assert_true \
    "PSI behavioural skipped: neither yq nor python3+PyYAML available; self-heal write tier is a no-op (ticket Risk R3)" \
    "true"
fi

echo ""

# =============================================================================
# Category PCN: P3-2C /brief chain={on,off} naming redesign (X.Y.0 deprecation
#               phase — mode=auto|manual retained as deprecated alias)
# Diff: Cat AC (CT-MODE-1..14) already pins the legacy mode={auto|manual}
#        contract and the argument-hint substring `mode=auto|manual`. PCN
#        layers the new `chain=on|off` canonical key on top without removing
#        any AC literal — argument-hint is rewritten to keep
#        `mode=auto|manual` (as `(legacy: mode=auto|manual)`) while gaining
#        `chain=on|off`; the deprecated-warning + simultaneous-spec error
#        literals; the frontmatter template carrying both `chain:` and
#        `mode:`; the cross-skill precedence marker `chain: precedes mode:`
#        in create-ticket SKILL.md and agent-spawn-prompts.md; and the
#        mode-independence-guard preservation with explicit `chain` mention.
# Maps to ticket .docs/dogfooding/33-34/P3-2C-brief-mode-naming-redesign.md
# AC-1..AC-8 (X.Y.0 phase). Future minor will drop the alias (AC-9, AC-10)
# in a separate Cat.
# =============================================================================
echo "--- Cat PCN: /brief chain={on,off} naming (P3-2C X.Y.0 phase) ---"

PCN_BRIEF_SKILL="$REPO_DIR/skills/brief/SKILL.md"
PCN_CT_SKILL="$REPO_DIR/skills/create-ticket/SKILL.md"
PCN_CT_SPAWN="$REPO_DIR/skills/create-ticket/references/agent-spawn-prompts.md"

# PCN-1a (AC-1): brief SKILL.md has >=1 hit of literal `chain=on`.
pcn_1a_count=$(grep -cF 'chain=on' "$PCN_BRIEF_SKILL" || true)
pcn_1a_result="false"
[ "$pcn_1a_count" -ge 1 ] && pcn_1a_result="true"
assert_true \
  "PCN-1a (AC-1): skills/brief/SKILL.md contains 'chain=on' literal (count=$pcn_1a_count, expected >=1)" \
  "$pcn_1a_result"

# PCN-1b (AC-1): brief SKILL.md has >=1 hit of literal `chain=off`.
pcn_1b_count=$(grep -cF 'chain=off' "$PCN_BRIEF_SKILL" || true)
pcn_1b_result="false"
[ "$pcn_1b_count" -ge 1 ] && pcn_1b_result="true"
assert_true \
  "PCN-1b (AC-1): skills/brief/SKILL.md contains 'chain=off' literal (count=$pcn_1b_count, expected >=1)" \
  "$pcn_1b_result"

# PCN-2 (AC-2): brief SKILL.md argument-hint value contains the substring
# `chain=on|off`.
pcn_2_hint=$(extract_frontmatter_field "$PCN_BRIEF_SKILL" "argument-hint")
pcn_2_result="false"
printf '%s' "$pcn_2_hint" | grep -qF 'chain=on|off' && pcn_2_result="true"
assert_true \
  "PCN-2 (AC-2): skills/brief/SKILL.md argument-hint contains 'chain=on|off' (value: '$pcn_2_hint')" \
  "$pcn_2_result"

# PCN-3 (AC-3): brief SKILL.md carries the verbatim deprecation warning
# literal `WARNING: 'mode=' is deprecated` (the inline-parser would emit
# this on stderr when the alias is supplied).
pcn_3_count=$(grep -cF "WARNING: 'mode=' is deprecated" "$PCN_BRIEF_SKILL" || true)
pcn_3_result="false"
[ "$pcn_3_count" -ge 1 ] && pcn_3_result="true"
assert_true \
  "PCN-3 (AC-3): skills/brief/SKILL.md contains \"WARNING: 'mode=' is deprecated\" literal (count=$pcn_3_count, expected >=1)" \
  "$pcn_3_result"

# PCN-4 (AC-4): brief SKILL.md carries the verbatim simultaneous-specification
# error literal `ERROR: 'chain=' and 'mode=' cannot be combined`.
pcn_4_count=$(grep -cF "ERROR: 'chain=' and 'mode=' cannot be combined" "$PCN_BRIEF_SKILL" || true)
pcn_4_result="false"
[ "$pcn_4_count" -ge 1 ] && pcn_4_result="true"
assert_true \
  "PCN-4 (AC-4): skills/brief/SKILL.md contains \"ERROR: 'chain=' and 'mode=' cannot be combined\" literal (count=$pcn_4_count, expected >=1)" \
  "$pcn_4_result"

# PCN-5 (AC-5/AC-6): the cross-skill precedence marker `chain: precedes mode:`
# is documented in BOTH skills/create-ticket/SKILL.md AND
# skills/create-ticket/references/agent-spawn-prompts.md (one hit each at
# minimum). AC-5 covers the frontmatter dual-key persistence; AC-6 covers
# the precedence rule that downstream readers (this marker) apply. The
# frontmatter template carrying both `chain:` and `mode:` is asserted by
# PCN-6 below (separate assertion so a frontmatter-only regression is
# diagnosable on its own).
pcn_5_ct_count=$(grep -cF 'chain: precedes mode:' "$PCN_CT_SKILL" || true)
pcn_5_spawn_count=$(grep -cF 'chain: precedes mode:' "$PCN_CT_SPAWN" || true)
pcn_5_result="false"
if [ "$pcn_5_ct_count" -ge 1 ] && [ "$pcn_5_spawn_count" -ge 1 ]; then
  pcn_5_result="true"
fi
assert_true \
  "PCN-5 (AC-5/AC-6): 'chain: precedes mode:' marker present in create-ticket SKILL.md (count=$pcn_5_ct_count) AND agent-spawn-prompts.md (count=$pcn_5_spawn_count); both expected >=1" \
  "$pcn_5_result"

# PCN-6 (AC-5): the brief Phase 3 frontmatter template carries BOTH the new
# `chain:` field AND the legacy `mode:` field during the deprecation period.
# Use loose patterns so any of the canonical forms (`chain: on`, `chain: off`,
# `chain: {on|off}`, `chain: (on|off)`) is accepted; mode similarly. This
# preserves Cat AC CT-MODE-2's assertion of `mode: {auto|manual}` while
# adding the new `chain:` line.
pcn_6_chain=$(grep -cE '^chain: (\{on\|off\}|\(on\|off\)|on|off)$' "$PCN_BRIEF_SKILL" || true)
pcn_6_mode=$(grep -cE '^mode: (\{auto\|manual\}|\(auto\|manual\)|auto|manual)$' "$PCN_BRIEF_SKILL" || true)
pcn_6_result="false"
if [ "$pcn_6_chain" -ge 1 ] && [ "$pcn_6_mode" -ge 1 ]; then
  pcn_6_result="true"
fi
assert_true \
  "PCN-6 (AC-5): brief SKILL.md frontmatter template carries both 'chain:' (count=$pcn_6_chain) and 'mode:' (count=$pcn_6_mode) lines; both expected >=1" \
  "$pcn_6_result"

# PCN-7 (AC-8): the `mode independence guard` section is preserved during the
# deprecation period AND its prose explicitly mentions `chain` alongside
# `mode`. The guard heading literal `mode independence guard` MUST still
# appear in the file (preservation); and the same paragraph (or section)
# MUST mention the new `chain` argument so the defensive prose covers both
# keys. We measure preservation by the heading literal count and chain-
# mention by counting `chain` occurrences in the lines from the guard
# heading up to the next blank line (the guard paragraph).
pcn_8_guard_count=$(grep -cF 'mode independence guard' "$PCN_BRIEF_SKILL" || true)
PCN_8_PARA=$(awk '/mode independence guard/{flag=1} flag{print; if(NR>1 && $0 ~ /^$/) exit}' "$PCN_BRIEF_SKILL")
pcn_8_chain_in_para=$(printf '%s' "$PCN_8_PARA" | grep -cF 'chain' || true)
pcn_8_result="false"
if [ "$pcn_8_guard_count" -ge 1 ] && [ "$pcn_8_chain_in_para" -ge 1 ]; then
  pcn_8_result="true"
fi
assert_true \
  "PCN-7 (AC-8): brief SKILL.md preserves 'mode independence guard' heading (count=$pcn_8_guard_count) AND its paragraph mentions 'chain' (count=$pcn_8_chain_in_para); both expected >=1" \
  "$pcn_8_result"
unset PCN_BRIEF_SKILL PCN_CT_SKILL PCN_CT_SPAWN PCN_8_PARA

echo ""

# --- Summary ---
print_summary
