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

assert_file_not_contains \
  "security-scan/SKILL.md has no stale 'Full report will be saved to'" \
  "$REPO_DIR/skills/security-scan/SKILL.md" \
  "Full report will be saved to"

echo ""

# --- Category 3: Ticket-facing skills have ticket detection ---
echo "--- Ticket-facing skills have ticket detection ---"

assert_file_contains \
  "security-scan/SKILL.md references ticket-dir" \
  "$REPO_DIR/skills/security-scan/SKILL.md" \
  "ticket-dir"

assert_file_contains \
  "review-diff/SKILL.md references .backlog/active" \
  "$REPO_DIR/skills/review-diff/SKILL.md" \
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
  "review-diff/SKILL.md references quality-round" \
  "$REPO_DIR/skills/review-diff/SKILL.md" \
  "quality-round"

assert_file_contains \
  "review-diff/SKILL.md references security-scan" \
  "$REPO_DIR/skills/review-diff/SKILL.md" \
  "security-scan"

assert_file_contains \
  "security-scan/SKILL.md references output path" \
  "$REPO_DIR/skills/security-scan/SKILL.md" \
  "output path"

assert_file_contains \
  "refactor/SKILL.md references quality-refactor" \
  "$REPO_DIR/skills/refactor/SKILL.md" \
  "quality-refactor"

echo ""

print_summary
