#!/usr/bin/env bash
# test-brief-lightening.sh — Plan 07 dynamic Phase 2 shrinkage doc-consistency tests
#
# Static document-consistency check: for each of three mock autopilot-state.yaml
# fixtures (remaining_pct = 80% / 40% / 10%), assert that skills/brief/SKILL.md's
# Phase 2 shrinkage table covers the matching tier.
#
# The test does NOT execute the Skill (Skills are model-driven). It validates
# that the documented thresholds in SKILL.md are consistent with the fixture
# values that downstream consumers would feed into the formula.
#
# v6.2.0: the create-ticket-side assertions (runtime_metrics signal pair, one-shot
# read for split, lazy re-evaluation) were removed when the planner Split Judgment /
# Dynamic split-loop / Lazy re-evaluation sections were retired in favour of the
# decomposer-led partition path. The brief-side Phase 2 shrinkage rule remains
# in scope and is still validated below.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BRIEF_SKILL="$REPO_DIR/skills/brief/SKILL.md"
BRIEF_SHRINKAGE_REF="$REPO_DIR/skills/brief/references/phase2-dynamic-shrinkage.md"
FIXTURES_DIR="$REPO_DIR/tests/fixtures/autopilot-state-samples"

assert_grep() {
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

assert_fixture_exists() {
  local description="$1"
  local file="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ -f "$file" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       File: $file"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo "=== Plan 07 Dynamic Phase 2 Shrinkage Tests ==="
echo ""

# --- Fixture presence ---
echo "--- Fixtures present ---"
assert_fixture_exists "mock_state_80pct.yaml present" "$FIXTURES_DIR/mock_state_80pct.yaml"
assert_fixture_exists "mock_state_40pct.yaml present" "$FIXTURES_DIR/mock_state_40pct.yaml"
assert_fixture_exists "mock_state_10pct.yaml present" "$FIXTURES_DIR/mock_state_10pct.yaml"
echo ""

# --- Case 1: 80pct fixture should map to >=70 tier in SKILL.md ---
echo "--- Case 80pct selects >=70 tier ---"
# Fixture's input_tokens + cache_read_input_tokens = 200000 -> remaining 80% -> tier >=70%.
# SKILL.md must document the >=70% tier with a 30-question ceiling that matches the
# legacy upper bound.
assert_grep "SKILL.md contains the >=70% tier row" \
  "$BRIEF_SKILL" \
  '≥ 70%|>= 70%'
assert_grep "phase2-dynamic-shrinkage.md >=70% tier mentions 30 questions" \
  "$BRIEF_SHRINKAGE_REF" \
  'up to 30 questions'
echo ""

# --- Case 2: 40pct fixture should map to 30-50 tier ---
echo "--- Case 40pct selects 30-50 tier ---"
# Fixture's signal sum = 600000 -> remaining 40% -> tier 30-50%.
assert_grep "SKILL.md contains the 30-50% tier row" \
  "$BRIEF_SKILL" \
  '30-50%'
assert_grep "phase2-dynamic-shrinkage.md 30-50% tier mentions 6 questions" \
  "$BRIEF_SHRINKAGE_REF" \
  'up to 6 questions'
echo ""

# --- Case 3: 10pct fixture should map to <30 tier ---
echo "--- Case 10pct selects <30 tier ---"
# Fixture's signal sum = 900000 -> remaining 10% -> tier <30%.
assert_grep "SKILL.md contains the <30% tier row" \
  "$BRIEF_SKILL" \
  '< 30%'
assert_grep "phase2-dynamic-shrinkage.md <30% tier mentions 1 question" \
  "$BRIEF_SHRINKAGE_REF" \
  'up to 1 question'
echo ""

# --- Cross-cutting consistency checks ---
echo "--- Plan 07 cross-cutting consistency ---"
assert_grep "brief/SKILL.md cites runtime_metrics signal pair" \
  "$BRIEF_SKILL" \
  'input_tokens.*cache_read_input_tokens'
assert_grep "brief/SKILL.md states one-shot read at Phase 2 start" \
  "$BRIEF_SKILL" \
  'one-shot read'
assert_grep "brief/SKILL.md documents standalone fallback" \
  "$BRIEF_SKILL" \
  'standalone|state-file-absent'
echo ""

echo "==============================="
echo "Total: $TESTS_TOTAL | ${GREEN}Passed: $TESTS_PASSED${NC} | ${RED}Failed: $TESTS_FAILED${NC}"
echo "==============================="

[ "$TESTS_FAILED" -eq 0 ]
