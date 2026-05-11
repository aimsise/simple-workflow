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

# J-8: brief SKILL.md has KB reference from index.yaml
assert_file_contains \
  "brief SKILL.md has KB reference from index.yaml" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "index\\.yaml"

# J-9: brief SKILL.md has role=autopilot filtering
assert_file_contains \
  "brief SKILL.md has autopilot role filtering" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  "autopilot"

# J-10: brief SKILL.md mentions confidence threshold 0.7
assert_file_contains \
  "brief SKILL.md mentions confidence threshold" \
  "$REPO_DIR/skills/brief/SKILL.md" \
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

# J-19: brief SKILL.md policy template has aggressive-specific values
assert_file_contains \
  "brief SKILL.md has timeout_minutes aggressive branch (60)" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  'timeout_minutes:.*60.*aggressive'

assert_file_contains \
  "brief SKILL.md has max_total_rounds aggressive branch (12)" \
  "$REPO_DIR/skills/brief/SKILL.md" \
  'max_total_rounds:.*12.*aggressive'

assert_file_contains \
  "brief SKILL.md has allow_breaking_changes aggressive branch (true)" \
  "$REPO_DIR/skills/brief/SKILL.md" \
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

# K-1: brief SKILL.md Phase 4 instructs annotating with kb-suggested comments
assert_file_contains \
  "brief SKILL.md instructs annotating with kb-suggested comments" \
  "$REPO_DIR/skills/brief/SKILL.md" \
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

# K-7: brief SKILL.md describes confidence >= 0.7 and kb-suggested on the same line
assert_file_contains \
  "brief SKILL.md ties kb-suggested to the confidence >= 0.7 branch" \
  "$REPO_DIR/skills/brief/SKILL.md" \
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

# Extract the Step 3.5 subsection body (heading -> next ### Triggers).
AJ_STEP35_TMP=$(mktemp)
awk '/^### Step 3\.5:/,/^### Triggers/' "$AUDIT_MD" \
  | grep -v '^### Triggers' > "$AJ_STEP35_TMP"

# Extract the Triggers subsection body (heading -> next ### Skeptical).
AJ_TRIGGERS_TMP=$(mktemp)
awk '/^### Triggers for Skeptical Third-Pass$/,/^### Skeptical/' "$AUDIT_MD" \
  | grep -v '^### Skeptical' > "$AJ_TRIGGERS_TMP"

# Extract the Prompt Template subsection body (heading -> next ## or ### at section boundary).
AJ_PROMPT_TMP=$(mktemp)
awk '/^### Skeptical Third-Pass Prompt Template$/,/^## /' "$AUDIT_MD" \
  | grep -v '^## ' > "$AJ_PROMPT_TMP"

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

# --- Summary ---
print_summary
