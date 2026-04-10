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
  if grep -qE "$pattern" "$file"; then
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
  "branch.*slug"

assert_file_contains \
  "refactor/SKILL.md references ticket-dir or .backlog/active" \
  "$REPO_DIR/skills/refactor/SKILL.md" \
  "ticket-dir|\.backlog/active"

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

# --- Category 10: Agent Status contract ---
# Every agent must publish a `**Status**:` contract line in its return format
# so that orchestrator skills can parse a consistent structured return block.
# This catches drift between the agent prompt and the parser contract.
echo "--- Agent Status contract ---"

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
  if grep -qE '^\*\*Status\*\*:' "$agent_md"; then
    echo -e "  ${GREEN}PASS${NC} $agent_basename.md has '**Status**:' contract line"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $agent_basename.md is missing '**Status**:' contract line"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""

print_summary
