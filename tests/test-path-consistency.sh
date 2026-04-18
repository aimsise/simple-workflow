#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Local helpers ---

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

assert_file_not_contains() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if ! grep -qE "$pattern" "$file"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       File: $file"
    echo -e "       Unexpected pattern found: $pattern"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo "=== Path Consistency Tests ==="
echo ""

# --- Category 1: Agents support caller-specified output paths ---
echo "--- Agents support caller-specified output paths ---"

assert_file_contains \
  "security-scanner.md supports caller-specified path" \
  "$REPO_DIR/agents/security-scanner.md" \
  "specified by the caller"

assert_file_contains \
  "code-reviewer.md supports caller-specified path" \
  "$REPO_DIR/agents/code-reviewer.md" \
  "specified by the caller"

assert_file_contains \
  "ac-evaluator.md supports caller-specified path" \
  "$REPO_DIR/agents/ac-evaluator.md" \
  "specified by the caller"

echo ""

# --- Category 2: No stale hardcoded output paths ---
echo "--- No stale hardcoded output paths ---"

assert_file_not_contains \
  "security-scanner.md has no stale 'Write full audit report to'" \
  "$REPO_DIR/agents/security-scanner.md" \
  "Write full audit report to"

assert_file_not_contains \
  "code-reviewer.md has no stale 'more than 20' condition" \
  "$REPO_DIR/agents/code-reviewer.md" \
  "more than 20"

echo ""

# --- Category 3: Ticket-facing skills have ticket detection ---
echo "--- Ticket-facing skills have ticket detection ---"

assert_file_contains \
  "audit/SKILL.md references ticket-dir" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "ticket-dir"

assert_file_contains \
  "audit/SKILL.md references .backlog/active" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "\.backlog/active"

assert_file_contains \
  "plan2doc/SKILL.md searches .backlog for tickets" \
  "$REPO_DIR/skills/plan2doc/SKILL.md" \
  "search.*\.backlog"

assert_file_contains \
  "impl/SKILL.md uses branch matching for eval-round" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "slug.*portion|strip.*prefix|branch.*contains"

assert_file_contains \
  "refactor/SKILL.md references ticket-dir or .backlog/active" \
  "$REPO_DIR/skills/refactor/SKILL.md" \
  "ticket-dir|\.backlog/active"

assert_file_contains \
  "autopilot/SKILL.md references ticket-dir" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "ticket-dir"

assert_file_not_contains \
  "autopilot/SKILL.md has no stale ticket-slug" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  '\{ticket-slug\}'

echo ""

# --- Category 4: Cross-reference consistency ---
echo "--- Cross-reference consistency ---"

assert_file_contains \
  "audit/SKILL.md references quality-round" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "quality-round"

assert_file_contains \
  "audit/SKILL.md references security-scanner" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "security-scanner"

assert_file_contains \
  "audit/SKILL.md returns Status field" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "\*\*Status\*\*"

assert_file_contains \
  "refactor/SKILL.md references quality-refactor" \
  "$REPO_DIR/skills/refactor/SKILL.md" \
  "quality-refactor"

echo ""

# --- Category 5: Skill structural validity ---
echo "--- Skill structural validity ---"

# Helper: extract a YAML scalar field from a frontmatter block.
# Reads the first `--- ... ---` block of $1 and returns the value of field $2.
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

assert_skill_frontmatter_valid() {
  local skill_dir="$1"
  local skill_slug
  skill_slug=$(basename "$skill_dir")
  local skill_md="$skill_dir/SKILL.md"

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ ! -f "$skill_md" ]; then
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md exists"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  # Must start with YAML frontmatter
  if ! head -1 "$skill_md" | grep -qE '^---[[:space:]]*$'; then
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md starts with YAML frontmatter"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  local name
  name=$(extract_frontmatter_field "$skill_md" "name")
  if [ "$name" != "$skill_slug" ]; then
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md frontmatter 'name' matches dir"
    echo -e "       Expected: $skill_slug"
    echo -e "       Got: $name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  # description must be present (non-empty after extraction OR followed by a multi-line block)
  if ! grep -qE '^description:' "$skill_md"; then
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md frontmatter has 'description' field"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  echo -e "  ${GREEN}PASS${NC} skills/$skill_slug/SKILL.md frontmatter is valid (name=$name)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

assert_skill_has_body_sections() {
  # A skill must have at least one '##' heading in its body (i.e. structural
  # content beyond the frontmatter). Delegator skills typically have just
  # '## Instructions'; orchestrator skills (/impl, /ship) use '## Phase N'.
  # Either is fine — we only catch frontmatter-only / empty-body files.
  local skill_dir="$1"
  local skill_slug
  skill_slug=$(basename "$skill_dir")
  local skill_md="$skill_dir/SKILL.md"

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local heading_count
  heading_count=$(grep -cE '^## ' "$skill_md")
  if [ "$heading_count" -ge 1 ]; then
    echo -e "  ${GREEN}PASS${NC} skills/$skill_slug/SKILL.md has body sections (${heading_count} '##' headings)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md has body sections (need >= 1 '##' heading, got 0)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

for skill_dir in "$REPO_DIR"/skills/*/; do
  assert_skill_frontmatter_valid "$skill_dir"
  assert_skill_has_body_sections "$skill_dir"
done

echo ""

# --- Category 6: Agent structural validity ---
echo "--- Agent structural validity ---"

assert_agent_frontmatter_valid() {
  local agent_md="$1"
  local agent_basename
  agent_basename=$(basename "$agent_md" .md)

  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  if ! head -1 "$agent_md" | grep -qE '^---[[:space:]]*$'; then
    echo -e "  ${RED}FAIL${NC} agents/$agent_basename.md starts with YAML frontmatter"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  local name
  name=$(extract_frontmatter_field "$agent_md" "name")
  if [ "$name" != "$agent_basename" ]; then
    echo -e "  ${RED}FAIL${NC} agents/$agent_basename.md frontmatter 'name' matches filename"
    echo -e "       Expected: $agent_basename"
    echo -e "       Got: $name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  if ! grep -qE '^description:' "$agent_md"; then
    echo -e "  ${RED}FAIL${NC} agents/$agent_basename.md frontmatter has 'description'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  if ! grep -qE '^tools:' "$agent_md"; then
    echo -e "  ${RED}FAIL${NC} agents/$agent_basename.md frontmatter has 'tools'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return
  fi

  echo -e "  ${GREEN}PASS${NC} agents/$agent_basename.md frontmatter is valid (name=$name)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

for agent_md in "$REPO_DIR"/agents/*.md; do
  assert_agent_frontmatter_valid "$agent_md"
done

echo ""

# --- Category 7: Agent reference reachability ---
# Every agent in agents/ must be referenced by at least one skill (or another agent)
# so we catch dead agents and renames that lose all callers.
echo "--- Agent reference reachability ---"

for agent_md in "$REPO_DIR"/agents/*.md; do
  agent_basename=$(basename "$agent_md" .md)
  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  # Search for agent name in any skill or other agent file (excluding self)
  hits=$(grep -RIl --include="*.md" -F "$agent_basename" "$REPO_DIR/skills" "$REPO_DIR/agents" 2>/dev/null \
         | grep -vF "$agent_md" || true)
  if [ -n "$hits" ]; then
    echo -e "  ${GREEN}PASS${NC} agent '$agent_basename' is referenced from at least one skill/agent"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} agent '$agent_basename' is not referenced anywhere — dead agent?"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""

# --- Category 8: Inline bash interpolation syntax ---
# Skill markdown can include `!`<bash command>`` blocks that Claude Code executes.
# Validate each interpolation parses with `bash -n` so a typo cannot ship undetected.
echo "--- Inline bash interpolation syntax ---"

for skill_md in "$REPO_DIR"/skills/*/SKILL.md; do
  skill_slug=$(basename "$(dirname "$skill_md")")

  # Extract every `!`...`` interpolation. Lines look like:  !`some bash`
  # Use perl-compatible regex to capture everything between !` and `.
  mapfile -t interpolations < <(grep -oE '!`[^`]+`' "$skill_md" | sed -E 's/^!`//; s/`$//')

  if [ ${#interpolations[@]} -eq 0 ]; then
    continue
  fi

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  syntax_ok=1
  bad_cmd=""
  for cmd in "${interpolations[@]}"; do
    if ! bash -n -c "$cmd" 2>/dev/null; then
      syntax_ok=0
      bad_cmd="$cmd"
      break
    fi
  done

  if [ $syntax_ok -eq 1 ]; then
    echo -e "  ${GREEN}PASS${NC} skills/$skill_slug/SKILL.md inline bash interpolations parse (${#interpolations[@]} block(s))"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md has a bash interpolation that fails 'bash -n'"
    echo -e "       Bad command: $bad_cmd"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""

# --- Category 9: Default-branch hardcode guard ---
# Any literal reference to `origin/main` in skills/ (excluding the fallback
# `|| echo main`, which uses `echo main` without the `origin/` prefix)
# indicates a hardcoded default branch that will fatal on master/develop
# repos. This catches the same class of bug as the /catchup + /ship fixes.
echo "--- Default-branch hardcode guard ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
# Allow: `|| echo main` (fallback), `fallback to main when origin/HEAD is not set` (doc prose)
# Disallow: any literal `origin/main`
HARDCODED=$(grep -RIn --include='*.md' 'origin/main' "$REPO_DIR/skills" 2>/dev/null || true)
if [ -z "$HARDCODED" ]; then
  echo -e "  ${GREEN}PASS${NC} skills/ has no literal 'origin/main' references"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} skills/ has literal 'origin/main' references:"
  echo "$HARDCODED" | sed 's/^/       /'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Category 10: Agent Status contract (vocabulary verification) ---
# Every agent must publish a `**Status**:` contract line in its return format
# so that orchestrator skills can parse a consistent structured return block.
# This catches drift between the agent prompt and the parser contract.
# In addition, verify the Status line is non-empty AND contains a recognizable
# token from the known vocabulary set, to catch empty or garbage values.
echo "--- Agent Status contract (vocabulary verification) ---"

KNOWN_TOKENS='success|partial|failed|PASS|PASS-WITH-CAVEATS|FAIL|FAIL-CRITICAL|PASS_WITH_CONCERNS'

for agent_md in \
  "$REPO_DIR/agents/code-reviewer.md" \
  "$REPO_DIR/agents/security-scanner.md" \
  "$REPO_DIR/agents/ac-evaluator.md" \
  "$REPO_DIR/agents/implementer.md" \
  "$REPO_DIR/agents/researcher.md" \
  "$REPO_DIR/agents/ticket-evaluator.md" \
  "$REPO_DIR/agents/test-writer.md" \
  "$REPO_DIR/agents/planner.md"; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  agent_basename=$(basename "$agent_md" .md)
  if [ ! -f "$agent_md" ]; then
    echo -e "  ${RED}FAIL${NC} $agent_basename.md does not exist"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    continue
  fi
  STATUS_LINE=$(grep -m1 -E '^\*\*Status\*\*:' "$agent_md" || true)
  if [ -z "$STATUS_LINE" ]; then
    echo -e "  ${RED}FAIL${NC} $agent_basename.md is missing '**Status**:' contract line"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    continue
  fi
  # Extract the value portion after "**Status**:"
  STATUS_VALUES=$(echo "$STATUS_LINE" | sed -E 's/^\*\*Status\*\*:[[:space:]]*//')
  if [ -z "$STATUS_VALUES" ] || [ "$STATUS_VALUES" = "$STATUS_LINE" ]; then
    echo -e "  ${RED}FAIL${NC} $agent_basename.md has empty Status value"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    continue
  fi
  # Verify at least one known token appears
  if echo "$STATUS_VALUES" | grep -qE "($KNOWN_TOKENS)"; then
    echo -e "  ${GREEN}PASS${NC} $agent_basename.md Status vocabulary is recognized"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $agent_basename.md Status value '$STATUS_VALUES' contains no known token ($KNOWN_TOKENS)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""

# --- Category 11: Bash(*) scope restricted to generator agents ---
echo "--- Bash(*) scope guard ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
bstar_files=$(grep -rl '"Bash(\*)"' "$REPO_DIR"/agents/*.md 2>/dev/null | sort)
bstar_count=$(echo "$bstar_files" | grep -c . 2>/dev/null || echo 0)
expected_files=$(printf '%s\n' "$REPO_DIR/agents/implementer.md" "$REPO_DIR/agents/test-writer.md")
if [ "$bstar_count" -eq 2 ] && [ "$bstar_files" = "$expected_files" ]; then
  echo -e "  ${GREEN}PASS${NC} Bash(*) restricted to implementer + test-writer"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Unexpected Bash(*) agents (expected implementer + test-writer only): $(echo "$bstar_files" | tr '\n' ' ')"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Category 12: /audit round=N contract ---
echo "--- /audit round=N contract ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'round=N' "$REPO_DIR/skills/audit/SKILL.md" && grep -qF 'round={n}' "$REPO_DIR/skills/impl/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} /audit supports round=N and /impl passes round={n}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /audit round=N contract is missing or /impl does not pass round={n}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Category 13: Bash permission whitespace consistency ---
echo "--- Bash permission whitespace consistency ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
inconsistent=$( (grep -rE 'Bash\([a-z]+ :\*\)' "$REPO_DIR"/agents/ 2>/dev/null || true) | wc -l | tr -d ' ')
if [ "$inconsistent" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} No whitespace inconsistency in Bash(<cmd> :*) permissions"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Found $inconsistent Bash(<cmd> :*) whitespace-mixed entries in agents/"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Category 14: catchup allowed-tools compliance ---
echo "--- catchup allowed-tools compliance ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -qE "grep.*\|.*sed" "$REPO_DIR/skills/catchup/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} catchup does not suggest grep|sed piping outside allowed-tools"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} catchup still contains grep|sed pipe example"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Category 15: CHANGELOG / plugin.json version consistency ---
echo "--- CHANGELOG / plugin.json version consistency ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
PLUGIN_VER=$(jq -r '.version' "$REPO_DIR/.claude-plugin/plugin.json")
CHANGELOG_LATEST=$(grep -m1 -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$REPO_DIR/CHANGELOG.md" | sed -E 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/')
if [ "$PLUGIN_VER" = "$CHANGELOG_LATEST" ]; then
  echo -e "  ${GREEN}PASS${NC} plugin.json version ($PLUGIN_VER) matches latest CHANGELOG release ($CHANGELOG_LATEST)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} version mismatch: plugin.json=$PLUGIN_VER CHANGELOG=$CHANGELOG_LATEST"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Category 16: Default-branch pipe correctness ---
echo "--- Default-branch pipe correctness ---"

for skill_md in "$REPO_DIR"/skills/*/SKILL.md; do
  skill_slug=$(basename "$(dirname "$skill_md")")

  mapfile -t pipes < <(grep -oE '!`[^`]*git symbolic-ref[^`]*`' "$skill_md" | sed -E 's/^!`//; s/`$//')

  if [ ${#pipes[@]} -eq 0 ]; then
    continue
  fi

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  all_ok=1
  bad_pipe=""
  for pipe in "${pipes[@]}"; do
    if ! echo "$pipe" | grep -qF '| grep .'; then
      all_ok=0
      bad_pipe="$pipe"
      break
    fi
  done

  if [ $all_ok -eq 1 ]; then
    echo -e "  ${GREEN}PASS${NC} skills/$skill_slug/SKILL.md git symbolic-ref pipes include '| grep .'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md git symbolic-ref pipe missing '| grep .'"
    echo -e "       Bad pipe: $bad_pipe"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""

# --- Category 17: Step number continuity ---
# NOTE (PR E Task 3): NNa/NNb branch steps are accepted as valid
# continuations of step NN. /ship and /impl use them to insert inline
# sub-steps (e.g. 15a "Complete ship phase state update") without shifting
# every subsequent step's number. Only the primary numbered sequence
# (1, 2, 3, ...) must remain sequential with no gaps; branch steps are
# skipped during the gap scan.
echo "--- Step number continuity ---"

for skill_md in \
  "$REPO_DIR/skills/ship/SKILL.md" \
  "$REPO_DIR/skills/impl/SKILL.md"; do
  skill_slug=$(basename "$(dirname "$skill_md")")
  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  mapfile -t steps < <(grep -nE '^[0-9]+[a-z]?\.' "$skill_md" | sed -E 's/:([0-9]+[a-z]?)\..*/:\1/')

  if [ ${#steps[@]} -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} skills/$skill_slug/SKILL.md has no top-level steps (skipped)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    continue
  fi

  has_gap=0
  bad_detail=""
  prev_num=0
  for entry in "${steps[@]}"; do
    line_no="${entry%%:*}"
    step_id="${entry##*:}"
    # Branch steps (e.g. 15a, 15b) annotate step 15 inline; accept them and
    # skip the gap scan for that entry. They do not advance prev_num.
    if echo "$step_id" | grep -qE '[a-z]$'; then
      continue
    fi
    num="$step_id"
    if [ "$prev_num" -gt 0 ] && [ "$num" -ne $((prev_num + 1)) ] && [ "$num" -ne 1 ]; then
      has_gap=1
      bad_detail="gap: step $prev_num -> $num at line $line_no"
      break
    fi
    prev_num=$num
  done

  if [ "$has_gap" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} skills/$skill_slug/SKILL.md steps are sequential (1..$prev_num; NNa/NNb branch steps accepted)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md step numbering issue: $bad_detail"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""

# --- Category 18: Phase-step alignment ---
echo "--- Phase-step alignment ---"

for skill_md in \
  "$REPO_DIR/skills/ship/SKILL.md" \
  "$REPO_DIR/skills/impl/SKILL.md"; do
  skill_slug=$(basename "$(dirname "$skill_md")")
  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  phase_ok=1
  bad_detail=""
  prev_last_step=0

  while IFS= read -r line; do
    line_no=$(echo "$line" | cut -d: -f1)
    first_step=$(awk -v start="$line_no" 'NR > start && /^[0-9]+\./ { sub(/\..*/, ""); print; exit }' "$skill_md")
    if [ -z "$first_step" ]; then
      continue
    fi

    if [ "$prev_last_step" -gt 0 ] && [ "$first_step" -ne $((prev_last_step + 1)) ]; then
      phase_ok=0
      bad_detail="Phase at line $line_no starts at step $first_step, expected $((prev_last_step + 1))"
      break
    fi

    next_phase_line=$(awk -v start="$line_no" 'NR > start && /^## Phase/ { print NR; exit }' "$skill_md")
    if [ -n "$next_phase_line" ]; then
      prev_last_step=$(awk -v start="$line_no" -v end="$next_phase_line" 'NR > start && NR < end && /^[0-9]+\./ { sub(/\..*/, ""); last=$0 } END { print last+0 }' "$skill_md")
    else
      prev_last_step=$(awk -v start="$line_no" 'NR > start && /^[0-9]+\./ { sub(/\..*/, ""); last=$0 } END { print last+0 }' "$skill_md")
    fi
  done < <(grep -nE '^## Phase' "$skill_md")

  if [ "$phase_ok" -eq 1 ]; then
    echo -e "  ${GREEN}PASS${NC} skills/$skill_slug/SKILL.md phase-step alignment is correct"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md phase-step misalignment: $bad_detail"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""

# --- Category 19: allowed-tools vs body Bash usage consistency ---
echo "--- allowed-tools vs body Bash usage consistency ---"

for skill_md in "$REPO_DIR"/skills/*/SKILL.md; do
  skill_slug=$(basename "$(dirname "$skill_md")")

  # Skip delegator skills with agent: field (they delegate to an agent that has Bash)
  if grep -qE '^agent:' "$skill_md"; then
    continue
  fi

  has_bash_in_tools=$(awk '
    BEGIN{in_fm=0;depth=0;found=0}
    /^---/{depth++;if(depth==1){in_fm=1;next};if(depth==2){exit}}
    in_fm && /Bash/{found=1}
    END{print found}
  ' "$skill_md")

  # Check body (after frontmatter) for shell command invocation patterns
  # Exclude !` interpolations (pre-computed context, handled by platform)
  # shellcheck disable=SC2034
  body_bash=$( awk 'BEGIN{depth=0} /^---/{depth++;next} depth>=2{print}' "$skill_md" \
    | { grep -cvE '^!' || true; } \
    | head -1 )
  # More targeted: look for "Run `git/gh/ls/mkdir" patterns in body
  # Exclude !` interpolation lines (pre-computed context, not agent shell instructions)
  body_shell_refs=$( awk 'BEGIN{depth=0} /^---/{depth++;next} depth>=2{print}' "$skill_md" \
    | grep -vE '^!' \
    | { grep -cE '`(git |gh |npm |npx |cargo |go |make |pytest |bash )' || true; } )

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$has_bash_in_tools" -eq 0 ] && [ "$body_shell_refs" -gt 3 ]; then
    echo -e "  ${RED}FAIL${NC} skills/$skill_slug/SKILL.md body has $body_shell_refs shell refs but allowed-tools has no Bash"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo -e "  ${GREEN}PASS${NC} skills/$skill_slug/SKILL.md allowed-tools vs body Bash usage is consistent"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
done

echo ""

# --- Category 20: catchup tickets field documentation ---
echo "--- catchup tickets field documentation ---"

assert_file_contains \
  "catchup/SKILL.md documents tickets: field" \
  "$REPO_DIR/skills/catchup/SKILL.md" \
  'tickets'

assert_file_contains \
  "catchup/SKILL.md documents per-ticket dir field" \
  "$REPO_DIR/skills/catchup/SKILL.md" \
  '- dir:'

assert_file_contains \
  "catchup/SKILL.md documents per-ticket in_progress_phase" \
  "$REPO_DIR/skills/catchup/SKILL.md" \
  'in_progress_phase'

echo ""

# --- Category 21: ticket-slug regression guard (cross-skill) ---
echo "--- ticket-slug regression guard (cross-skill) ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
TICKET_SLUG_HITS=$(grep -rE '\{ticket-slug\}' "$REPO_DIR/skills/" --include='*.md' 2>/dev/null || true)
if [ -z "$TICKET_SLUG_HITS" ]; then
  echo -e "  ${GREEN}PASS${NC} skills/ has no stale {ticket-slug} references"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} skills/ has stale {ticket-slug} references:"
  echo "$TICKET_SLUG_HITS" | sed 's/^/       /'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Category 22: ticket-dir= propagation contract ---
echo "--- ticket-dir= propagation contract ---"

assert_file_contains \
  "audit/SKILL.md argument-hint includes ticket-dir=" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  "argument-hint:.*ticket-dir="

assert_file_contains \
  "ship/SKILL.md argument-hint includes ticket-dir=" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  "argument-hint:.*ticket-dir="

assert_file_contains \
  "impl/SKILL.md Step 17 passes ticket-dir= to /audit" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  "pass.*ticket-dir=.*\/audit"

assert_file_contains \
  "refactor/SKILL.md argument-hint includes ticket-dir=" \
  "$REPO_DIR/skills/refactor/SKILL.md" \
  "argument-hint:.*ticket-dir="

assert_file_contains \
  "autopilot/SKILL.md passes ticket-dir={ticket-dir} to /ship" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "ticket-dir=\{ticket-dir\}"

assert_file_contains \
  "autopilot/SKILL.md contains ARTIFACT-MISSING handling" \
  "$REPO_DIR/skills/autopilot/SKILL.md" \
  "ARTIFACT-MISSING"

echo ""

# --- Category 23: ticket-dir= semantic verification ---
echo "--- ticket-dir= semantic verification ---"

# AC1: Both /audit and /ship argument-hint lines use <dir-name> format (not <path>)
assert_file_contains \
  "audit/SKILL.md argument-hint uses ticket-dir=<dir-name> format" \
  "$REPO_DIR/skills/audit/SKILL.md" \
  'argument-hint:.*ticket-dir=<dir-name>'

assert_file_contains \
  "ship/SKILL.md argument-hint uses ticket-dir=<dir-name> format" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  'argument-hint:.*ticket-dir=<dir-name>'

assert_file_contains \
  "refactor/SKILL.md argument-hint uses ticket-dir=<dir-name> format" \
  "$REPO_DIR/skills/refactor/SKILL.md" \
  'argument-hint:.*ticket-dir=<dir-name>'

# AC2: /impl's ticket-dir= pass to /audit uses bare name format (not full path)
assert_file_not_contains \
  "impl/SKILL.md does NOT pass ticket-dir=.backlog (no full path leak)" \
  "$REPO_DIR/skills/impl/SKILL.md" \
  'ticket-dir=\.backlog'

# AC3: Artifact verification ordering — phase-guarded for Phase E
# AC3: Artifact verification ordering — ARTIFACT-MISSING appears before State update (after)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
autopilot_file="$REPO_DIR/skills/autopilot/SKILL.md"
ordering_ok=1
bad_ordering=""
while IFS=: read -r artifact_lineno _rest; do
  next_state_after=$(awk -v start="$artifact_lineno" 'NR > start && /State update \(after\)/ { print NR; exit }' "$autopilot_file")
  if [ -z "$next_state_after" ]; then
    ordering_ok=0
    bad_ordering="ARTIFACT-MISSING at line $artifact_lineno has no subsequent State update (after)"
    break
  fi
done < <(grep -n 'ARTIFACT-MISSING' "$autopilot_file")

if [ "$ordering_ok" -eq 1 ]; then
  artifact_count=$(grep -c 'ARTIFACT-MISSING' "$autopilot_file")
  echo -e "  ${GREEN}PASS${NC} autopilot/SKILL.md all $artifact_count ARTIFACT-MISSING blocks appear before their State update (after)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} autopilot/SKILL.md ARTIFACT-MISSING ordering violation: $bad_ordering"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- Category 24: /ship staging exclusion for .backlog/briefs/ ---
echo "--- /ship staging exclusion for .backlog/briefs/ ---"

assert_file_contains \
  "ship/SKILL.md Step 3b excludes .backlog/briefs/ from staging" \
  "$REPO_DIR/skills/ship/SKILL.md" \
  '\.backlog/briefs/'

echo ""

print_summary
