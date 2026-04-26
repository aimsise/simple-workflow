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

# L-4: create-ticket SKILL.md has Split Judgment structure (Split criteria / Split Rationale)
assert_file_contains \
  "create-ticket SKILL.md has Split criteria description" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "Split criteria"

assert_file_contains \
  "create-ticket SKILL.md has Split Rationale description" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "Split Rationale"

# L-5: create-ticket SKILL.md has Split guardrails (minimum size / AC count)
assert_file_contains \
  "create-ticket SKILL.md has split guardrail (at least Size S or 2+ AC)" \
  "$REPO_DIR/skills/create-ticket/SKILL.md" \
  "at least Size S|2 or more Acceptance Criteria"

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

# CT-MODE-14 (release guard): plugin.json version must match the latest CHANGELOG entry.
# Guards against shipping with a stale plugin.json version.
echo "--- CT-MODE-14 ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ct_mode_14_plugin_version=$(grep -E '^[[:space:]]*"version":' "$REPO_DIR/.claude-plugin/plugin.json" | head -1 | sed -E 's/.*"version":[[:space:]]*"([^"]+)".*/\1/')
if [ "$ct_mode_14_plugin_version" = "6.0.0" ]; then
  echo -e "  ${GREEN}PASS${NC} CT-MODE-14: plugin.json version is 6.0.0, aligned with CHANGELOG [6.0.0]"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-MODE-14: plugin.json version is '$ct_mode_14_plugin_version' but CHANGELOG advertises [6.0.0] — bump plugin.json"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Summary ---
print_summary
