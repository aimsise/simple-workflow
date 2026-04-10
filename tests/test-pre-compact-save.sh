#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== pre-compact-save.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/pre-compact-save.sh"

# Trap to ensure cleanup on exit
trap 'cleanup_test_repo' EXIT

# --- Test group 1: empty repo (no tickets, no plans, no rounds) ---

setup_test_repo
run_hook "$HOOK" "" "$TEST_REPO"

# Test 1: compact-state-*.md file is created
TESTS_TOTAL=$((TESTS_TOTAL + 1))
COMPACT_FILE=$(ls "$TEST_REPO"/.docs/compact-state/compact-state-*.md 2>/dev/null | head -1)
if [ -n "$COMPACT_FILE" ] && [ -f "$COMPACT_FILE" ]; then
  echo -e "  ${GREEN}PASS${NC} compact-state-*.md file is created"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} compact-state-*.md file is created"
  echo -e "       No matching file found in $TEST_REPO/.docs/compact-state/"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: File begins with YAML frontmatter delimiter '---'
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && [ "$(head -1 "$COMPACT_FILE")" = "---" ]; then
  echo -e "  ${GREEN}PASS${NC} File begins with YAML frontmatter delimiter '---'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File begins with YAML frontmatter delimiter '---'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: YAML frontmatter contains 'date:' key
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^date:' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'date:' key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'date:' key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: YAML frontmatter contains 'branch:' key
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^branch:' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'branch:' key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'branch:' key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: YAML frontmatter contains 'active_tickets:' key
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^active_tickets:' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'active_tickets:' key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'active_tickets:' key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: YAML frontmatter contains 'active_plans:' key
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^active_plans:' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'active_plans:' key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'active_plans:' key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: YAML frontmatter contains 'latest_eval_round:' key (with value 0 in empty repo)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^latest_eval_round: 0$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'latest_eval_round: 0' (empty repo)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'latest_eval_round: 0' (empty repo)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: YAML frontmatter contains 'latest_audit_round:' key (with value 0 in empty repo)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^latest_audit_round: 0$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'latest_audit_round: 0' (empty repo)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'latest_audit_round: 0' (empty repo)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 9: YAML frontmatter contains 'last_round_outcome: unknown' (empty repo)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^last_round_outcome: unknown$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'last_round_outcome: unknown' (empty repo)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'last_round_outcome: unknown' (empty repo)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 10: YAML frontmatter contains 'in_progress_phase: unknown' (empty repo)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^in_progress_phase: unknown$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} YAML frontmatter contains 'in_progress_phase: unknown' (empty repo)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} YAML frontmatter contains 'in_progress_phase: unknown' (empty repo)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 11: File contains '## Changed Files' section
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qF "## Changed Files" "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains '## Changed Files'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains '## Changed Files'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 12: File contains '## Git Status' section
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qF "## Git Status" "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains '## Git Status'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains '## Git Status'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 13: File contains '## Active Tickets' section
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qF "## Active Tickets" "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} File content contains '## Active Tickets'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} File content contains '## Active Tickets'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 14: Exit code is 0
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} Exit code is 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Exit code is 0"
  echo -e "       Got: exit $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

cleanup_test_repo

echo ""

# --- Test group 2: repo with eval-round + audit-round files ---
# Verifies the in_progress_phase heuristic and latest_*_round detection.

setup_test_repo
mkdir -p "$TEST_REPO/.backlog/active/feature-x"
# Round 1: eval done, audit done with PASS
echo "round 1 eval" > "$TEST_REPO/.backlog/active/feature-x/eval-round-1.md"
echo "round 1 audit" > "$TEST_REPO/.backlog/active/feature-x/audit-round-1.md"
# Round 2: eval done, audit done with FAIL
echo "round 2 eval" > "$TEST_REPO/.backlog/active/feature-x/eval-round-2.md"
# Test 17 fake Status row is written to audit-round-2.md (Fix 3)
{
  echo "# Audit round 2"
  echo ""
  echo "**Status**: FAIL"
} > "$TEST_REPO/.backlog/active/feature-x/audit-round-2.md"

run_hook "$HOOK" "" "$TEST_REPO"
COMPACT_FILE=$(ls "$TEST_REPO"/.docs/compact-state/compact-state-*.md 2>/dev/null | head -1)

# Test 15: latest_eval_round is 2
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^latest_eval_round: 2$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} latest_eval_round detected as 2 (after creating round-1 + round-2)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} latest_eval_round detected as 2"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 16: latest_audit_round is 2
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^latest_audit_round: 2$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} latest_audit_round detected as 2"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} latest_audit_round detected as 2"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 17: last_round_outcome is FAIL (parsed from audit-round-2.md)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^last_round_outcome: FAIL$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} last_round_outcome parsed as FAIL"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} last_round_outcome parsed as FAIL"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 18: in_progress_phase is impl-loop (FAIL outcome means more rounds expected)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^in_progress_phase: impl-loop$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} in_progress_phase derived as impl-loop (FAIL at round 2)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} in_progress_phase derived as impl-loop"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

cleanup_test_repo

echo ""

# --- Test group 3: repo with completed round (PASS_WITH_CONCERNS) ---

setup_test_repo
mkdir -p "$TEST_REPO/.backlog/active/feature-y"
echo "round 1 eval" > "$TEST_REPO/.backlog/active/feature-y/eval-round-1.md"
# Test 19 fake Status row is written to audit-round-1.md (Fix 3)
{
  echo "# Audit round 1"
  echo ""
  echo "**Status**: PASS_WITH_CONCERNS"
} > "$TEST_REPO/.backlog/active/feature-y/audit-round-1.md"

run_hook "$HOOK" "" "$TEST_REPO"
COMPACT_FILE=$(ls "$TEST_REPO"/.docs/compact-state/compact-state-*.md 2>/dev/null | head -1)

# Test 19: in_progress_phase is impl-done (PASS_WITH_CONCERNS at completed round)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^in_progress_phase: impl-done$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} in_progress_phase derived as impl-done (PASS_WITH_CONCERNS)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} in_progress_phase derived as impl-done"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

cleanup_test_repo

echo ""

# --- Test group 4: contract-drift regression tests (Fix 3) ---
# These tests guard against the HIGH-A class bug where pre-compact-save
# was parsing the code-reviewer's raw quality-round-*.md (vocabulary:
# success/partial/failed) instead of /audit's aggregated audit-round-*.md
# (vocabulary: PASS/FAIL/PASS_WITH_CONCERNS).

# Test 20: code-reviewer's raw "**Status**: success" output misplaced in
# quality-round-1.md (no audit-round file) must yield last_round_outcome=unknown.
# This verifies pre-compact-save does NOT fall back to parsing quality-round files.
setup_test_repo
mkdir -p "$TEST_REPO/.backlog/active/feature-z"
echo "round 1 eval" > "$TEST_REPO/.backlog/active/feature-z/eval-round-1.md"
{
  echo "# Code review round 1 (raw code-reviewer output)"
  echo ""
  echo "**Status**: success"
} > "$TEST_REPO/.backlog/active/feature-z/quality-round-1.md"
# NOTE: no audit-round-1.md — simulates code-reviewer ran but /audit did not persist
run_hook "$HOOK" "" "$TEST_REPO"
COMPACT_FILE=$(ls "$TEST_REPO"/.docs/compact-state/compact-state-*.md 2>/dev/null | head -1)

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^last_round_outcome: unknown$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} code-reviewer '**Status**: success' in quality-round-1.md yields last_round_outcome=unknown (contract isolation)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} code-reviewer '**Status**: success' should not be parsed by pre-compact-save"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

echo ""

# Test 21: even if code-reviewer's raw "**Status**: success" is misplaced into
# audit-round-1.md, the case statement only matches PASS/FAIL/PASS_WITH_CONCERNS,
# so last_round_outcome must remain "unknown" — this detects accidental future
# loosening of the case filter.
setup_test_repo
mkdir -p "$TEST_REPO/.backlog/active/feature-w"
echo "round 1 eval" > "$TEST_REPO/.backlog/active/feature-w/eval-round-1.md"
{
  echo "# Misplaced raw code-reviewer output in audit-round file"
  echo ""
  echo "**Status**: success"
} > "$TEST_REPO/.backlog/active/feature-w/audit-round-1.md"
run_hook "$HOOK" "" "$TEST_REPO"
COMPACT_FILE=$(ls "$TEST_REPO"/.docs/compact-state/compact-state-*.md 2>/dev/null | head -1)

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -n "$COMPACT_FILE" ] && grep -qE '^last_round_outcome: unknown$' "$COMPACT_FILE"; then
  echo -e "  ${GREEN}PASS${NC} '**Status**: success' in audit-round-1.md yields last_round_outcome=unknown (case filter)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} case filter should reject 'success' vocabulary in audit-round files"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

echo ""

print_summary
