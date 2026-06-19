#!/usr/bin/env bash
# Tests for the tautological-assertion static detector used by ac-evaluator.
#
# AC #4 / AC #5 (PX-07): the detector must FAIL on R1/R2/R3 fixtures and
# PASS on the hint-exempt, non-constant-bound, and clean fixtures.
#
# AC #3(ii): the FAIL output for fixtures (a)/(b)/(c) must each contain
# the literal rule id `R1`/`R2`/`R3` so that ac-evaluator can surface the
# rule id in its Feedback field.
#
# AC #1: the canonical rules file `skills/impl/references/tautological-
# assertion-rules.md` exists, defines R1/R2/R3 with BAD/GOOD pairs, and
# carries a `## Limitations` (or `## Known Limitations`) heading whose body
# mentions AST or variable resolution.
#
# AC #2: `agents/ac-evaluator.md` references the rules file by name.
#
# AC #6: the latest unreleased CHANGELOG section carries an `### Added`
# entry mentioning "tautological assertion".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

DETECTOR="$REPO_DIR/skills/impl/lib/detect-tautological-assertions.sh"
FIXTURE_DIR="$REPO_DIR/tests/fixtures/tautological-assertions"
RULES_FILE="$REPO_DIR/skills/impl/references/tautological-assertion-rules.md"
EVALUATOR_FILE="$REPO_DIR/agents/ac-evaluator.md"
CHANGELOG="$REPO_DIR/CHANGELOG.md"

echo "=== ac-evaluator tautological-assertion static rules (PX-07) ==="
echo ""

# --- AC #1: rules file exists and is well-formed ---
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$RULES_FILE" ]; then
  echo -e "  ${GREEN}PASS${NC} AC #1: rules file exists at $RULES_FILE"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC #1: rules file missing at $RULES_FILE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
RULE_HITS=$(grep -cE '^### R[1-3]:|R1:|R2:|R3:' "$RULES_FILE" 2>/dev/null || true)
RULE_HITS=${RULE_HITS:-0}
if [ "$RULE_HITS" -ge 3 ]; then
  echo -e "  ${GREEN}PASS${NC} AC #1: rules file has 3+ R1/R2/R3 references ($RULE_HITS hits)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC #1: rules file has only $RULE_HITS R1/R2/R3 hits (need 3+)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

for rule in R1 R2 R3; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  # Each rule section must carry both BAD: and GOOD: labels.
  if awk -v r="### $rule:" '
        $0 ~ r {inside=1; next}
        /^### R[0-9]+:/ {inside=0}
        inside {print}
      ' "$RULES_FILE" | grep -q 'BAD:' \
     && awk -v r="### $rule:" '
        $0 ~ r {inside=1; next}
        /^### R[0-9]+:/ {inside=0}
        inside {print}
      ' "$RULES_FILE" | grep -q 'GOOD:'; then
    echo -e "  ${GREEN}PASS${NC} AC #1: $rule section has BAD: and GOOD: example labels"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AC #1: $rule section missing BAD: or GOOD: label"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE '^##+[[:space:]]+(Known )?Limitations' "$RULES_FILE"; then
  echo -e "  ${GREEN}PASS${NC} AC #1: Limitations heading present"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC #1: Limitations heading missing"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if awk '
      /^##+[[:space:]]+(Known )?Limitations/ {inside=1; next}
      /^##+[[:space:]]/ && inside {inside=0}
      inside {print}
    ' "$RULES_FILE" | grep -qE 'AST|variable resolution'; then
  echo -e "  ${GREEN}PASS${NC} AC #1: Limitations body mentions AST / variable resolution"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC #1: Limitations body does not mention AST / variable resolution"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# NAC #4: language/framework names must not appear in PROSE (outside fenced
# example blocks). Fenced code blocks are exempt — a worked example may legitimately
# carry a runner token — mirroring the fence-aware scan in hooks/pre-write-safety.sh.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
NAC4_HITS=$(awk '/^[[:space:]]*```/{f=1-f;next} !f{print}' "$RULES_FILE" | grep -ciE 'vitest|jest|pytest|junit' || true)
if [ "$NAC4_HITS" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} NAC #4: rules file is framework-agnostic"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} NAC #4: rules file mentions a specific framework ($NAC4_HITS hit(s))"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- AC #2: ac-evaluator.md references the rules file ---
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'tautological-assertion-rules' "$EVALUATOR_FILE"; then
  echo -e "  ${GREEN}PASS${NC} AC #2: ac-evaluator.md references the rules file"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC #2: ac-evaluator.md does not reference the rules file"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- AC #3(i): ac-evaluator prompt mentions R1/R2/R3 with `:` or `/` separator ---
TESTS_TOTAL=$((TESTS_TOTAL + 1))
PROMPT_RID_HITS=$(grep -cE 'R1[/:]|R2[/:]|R3[/:]' "$EVALUATOR_FILE" || true)
if [ "$PROMPT_RID_HITS" -ge 3 ]; then
  echo -e "  ${GREEN}PASS${NC} AC #3(i): ac-evaluator.md surfaces rule IDs ($PROMPT_RID_HITS hits)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC #3(i): ac-evaluator.md only has $PROMPT_RID_HITS R<N>[/:] hits (need 3+)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# NAC #6: no environment-variable bypass mechanism.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -qiE 'SKIP_|BYPASS_TAUTOLOGICAL' "$EVALUATOR_FILE" \
   && ! grep -qiE 'SKIP_|BYPASS_TAUTOLOGICAL' "$RULES_FILE"; then
  echo -e "  ${GREEN}PASS${NC} NAC #6: no env-var bypass in evaluator or rules file"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} NAC #6: env-var bypass detected"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- AC #4: detector verdicts on each fixture ---
declare -a VIOLATING=("a-r1-violation.test.js:R1" "b-r2-violation.test.js:R2" "c-r3-violation.test.js:R3")
declare -a CLEAN=("d-hint-exempt.test.js" "e-non-constant-bound.test.js" "f-clean.test.js")

for entry in "${VIOLATING[@]}"; do
  fixture="${entry%%:*}"
  rule="${entry##*:}"
  fixture_path="$FIXTURE_DIR/$fixture"

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  set +e
  output=$(bash "$DETECTOR" "$fixture_path" 2>&1)
  exit_code=$?
  set -e

  if [ "$exit_code" -eq 1 ] && printf '%s' "$output" | grep -qF "$rule"; then
    echo -e "  ${GREEN}PASS${NC} AC #4: $fixture FAILs with $rule"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AC #4: $fixture expected FAIL+$rule, got exit=$exit_code"
    printf '       output: %s\n' "$output"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

for fixture in "${CLEAN[@]}"; do
  fixture_path="$FIXTURE_DIR/$fixture"

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  set +e
  output=$(bash "$DETECTOR" "$fixture_path" 2>&1)
  exit_code=$?
  set -e

  if [ "$exit_code" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} AC #4: $fixture PASSes"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AC #4: $fixture expected PASS, got exit=$exit_code"
    printf '       output: %s\n' "$output"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# --- AC #3(ii): FAIL output for fixtures (a)/(b)/(c) contains R1/R2/R3 ---
for entry in "a:R1" "b:R2" "c:R3"; do
  prefix="${entry%%:*}"
  rule="${entry##*:}"
  fixture_path=$(ls "$FIXTURE_DIR/$prefix-"*.test.js 2>/dev/null | head -1)

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  set +e
  output=$(bash "$DETECTOR" "$fixture_path" 2>&1)
  exit_code=$?
  set -e

  if printf '%s' "$output" | grep -qF "$rule"; then
    echo -e "  ${GREEN}PASS${NC} AC #3(ii): $prefix fixture feedback contains '$rule'"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AC #3(ii): $prefix fixture feedback missing '$rule'"
    printf '       output: %s\n' "$output"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# --- AC #6: CHANGELOG entry exists under the latest unreleased / version section ---
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'tautological assertion' "$CHANGELOG"; then
  echo -e "  ${GREEN}PASS${NC} AC #6: CHANGELOG mentions 'tautological assertion'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC #6: CHANGELOG does not mention 'tautological assertion'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_summary
