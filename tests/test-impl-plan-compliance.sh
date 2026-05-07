#!/usr/bin/env bash
# tests/test-impl-plan-compliance.sh
#
# Reference implementation + verification for §14a of skills/impl/SKILL.md
# (Plan-Compliance Pre-Check, v6.3.0). The orchestrator (Claude in /impl)
# performs the same logic inline using its Read/Grep/Bash tools; this test
# script is the executable specification — keep its parsing rules in lock-step
# with the §14a prose.
#
# Behaviour mirrored from §14a:
#   1. Grep plan.md for `^## Affected [Ff]iles$|^## Critical files to modify$`.
#   2. If absent → emit `[PLAN-COMPLIANCE] no Affected-files section in plan; skipped`.
#   3. If present → parse the first markdown table that follows; extract paths
#      from the first column; strip backticks; cap at 80 lines / 50 paths.
#   4. Diff against the union of `git diff --name-only HEAD` and
#      `git ls-files --others --exclude-standard`.
#   5. Emit `[PLAN-COMPLIANCE-WARN]` per missing path, or
#      `[PLAN-COMPLIANCE] OK (N files matched)` when none are missing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/impl-plan-compliance"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=tests/test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

# ---------------------------------------------------------------------------
# Reference implementation of §14a Plan-Compliance Pre-Check.
# ---------------------------------------------------------------------------
# plan_compliance_check PLAN_PATH ACTUAL_FILES_LIST [ROUND_N]
#   PLAN_PATH         path to the plan markdown file
#   ACTUAL_FILES_LIST path to a newline-separated list of files in git diff
#                     (the union of `git diff --name-only HEAD` and
#                     `git ls-files --others --exclude-standard`)
#   ROUND_N           round number for [PLAN-COMPLIANCE-WARN] lines (default 1)
#
# Emits §14a's verdict lines on stdout. Always exits 0 (warn-only contract).
plan_compliance_check() {
  local plan_path="$1"
  local actual_files_list="$2"
  local round_n="${3:-1}"

  local header_lineno
  header_lineno=$(grep -nE '^## Affected [Ff]iles$|^## Critical files to modify$' "$plan_path" | head -1 | cut -d: -f1)

  if [ -z "$header_lineno" ]; then
    echo "[PLAN-COMPLIANCE] no Affected-files section in plan; skipped"
    return 0
  fi

  # Read up to 80 lines after the header and extract first-column paths from
  # the first contiguous markdown table. Skip header and separator rows.
  local expected_files
  expected_files=$(awk -v start="$header_lineno" '
    NR <= start { next }
    NR > start + 80 { exit }
    {
      if ($0 ~ /^\|/) {
        seen_table = 1
        if ($0 ~ /\|[[:space:]]*-+[[:space:]]*\|/) next   # separator row
        if ($0 ~ /^\|[[:space:]]*(File|ファイル)[[:space:]]*\|/) next  # header row
        line = $0
        sub(/^\|[[:space:]]*/, "", line)
        sub(/[[:space:]]*\|.*/, "", line)
        gsub(/^`/, "", line)
        gsub(/`$/, "", line)
        if (length(line) > 0) print line
      } else if (seen_table) {
        exit
      }
    }
  ' "$plan_path" | sort -u | head -50)

  if [ -z "$expected_files" ]; then
    # Header matched but no parseable table rows — treat as skipped to avoid
    # false positives on degenerate plans.
    echo "[PLAN-COMPLIANCE] no Affected-files section in plan; skipped"
    return 0
  fi

  local actual_sorted
  actual_sorted=$(sort -u "$actual_files_list")

  local missing
  missing=$(comm -23 <(printf '%s\n' "$expected_files") <(printf '%s\n' "$actual_sorted"))

  if [ -z "$missing" ]; then
    local matched_count
    matched_count=$(printf '%s\n' "$expected_files" | wc -l | tr -d ' ')
    echo "[PLAN-COMPLIANCE] OK ($matched_count files matched)"
    return 0
  fi

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    echo "[PLAN-COMPLIANCE-WARN] plan declares \"$path\" in Affected files but it is not in git diff (round=$round_n)"
  done <<< "$missing"
  return 0
}

# ---------------------------------------------------------------------------
# Test cases.
# ---------------------------------------------------------------------------
run_case() {
  local name="$1" plan="$2" actual="$3" expected_pattern="$4"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  local actual_tmp
  actual_tmp=$(mktemp)
  printf '%s\n' "$actual" > "$actual_tmp"

  local out
  out=$(plan_compliance_check "$plan" "$actual_tmp" 1)
  rm -f "$actual_tmp"

  if printf '%s\n' "$out" | grep -qE "$expected_pattern"; then
    echo -e "  ${GREEN}PASS${NC} $name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name"
    echo -e "       Expected pattern: $expected_pattern"
    echo -e "       Actual stdout:    $out"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_no_match() {
  local name="$1" plan="$2" actual="$3" forbidden_pattern="$4"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  local actual_tmp
  actual_tmp=$(mktemp)
  printf '%s\n' "$actual" > "$actual_tmp"

  local out
  out=$(plan_compliance_check "$plan" "$actual_tmp" 1)
  rm -f "$actual_tmp"

  if printf '%s\n' "$out" | grep -qE "$forbidden_pattern"; then
    echo -e "  ${RED}FAIL${NC} $name"
    echo -e "       Forbidden pattern matched: $forbidden_pattern"
    echo -e "       Actual stdout:             $out"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo -e "  ${GREEN}PASS${NC} $name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
}

echo "=== /impl §14a Plan-Compliance Pre-Check tests ==="
echo ""

echo "--- Case 1: plan-ok.md (table matches diff exactly) ---"
ALL_FILES_OK=$(printf 'src/foo.ts\nsrc/bar.ts\ntests/foo.test.ts\nother/unrelated.md')
run_case \
  "plan-ok: emits [PLAN-COMPLIANCE] OK with file count" \
  "$FIXTURE_DIR/plan-ok.md" \
  "$ALL_FILES_OK" \
  '^\[PLAN-COMPLIANCE\] OK \(3 files matched\)$'
assert_no_match \
  "plan-ok: does not emit any [PLAN-COMPLIANCE-WARN]" \
  "$FIXTURE_DIR/plan-ok.md" \
  "$ALL_FILES_OK" \
  'PLAN-COMPLIANCE-WARN'

echo ""
echo "--- Case 2: plan-missing.md (one declared file omitted from diff) ---"
ACTUAL_MISSING=$(printf 'src/foo.ts\nsrc/bar.ts')
run_case \
  "plan-missing: emits [PLAN-COMPLIANCE-WARN] for tests/foo.test.ts" \
  "$FIXTURE_DIR/plan-missing.md" \
  "$ACTUAL_MISSING" \
  '^\[PLAN-COMPLIANCE-WARN\] plan declares "tests/foo\.test\.ts" in Affected files but it is not in git diff \(round=1\)$'
assert_no_match \
  "plan-missing: does not emit OK verdict" \
  "$FIXTURE_DIR/plan-missing.md" \
  "$ACTUAL_MISSING" \
  '\[PLAN-COMPLIANCE\] OK'

echo ""
echo "--- Case 3: plan-no-section.md (no Affected-files heading) ---"
ACTUAL_ANYTHING=$(printf 'src/foo.ts')
run_case \
  "plan-no-section: emits the skipped verdict" \
  "$FIXTURE_DIR/plan-no-section.md" \
  "$ACTUAL_ANYTHING" \
  '^\[PLAN-COMPLIANCE\] no Affected-files section in plan; skipped$'

echo ""
echo "--- Case 4: plan-critical-files.md (alternate header, all matched) ---"
ALL_FILES_CRIT=$(printf 'src/foo.ts\nsrc/bar.ts')
run_case \
  "plan-critical-files: alternate header is recognised; emits OK with count" \
  "$FIXTURE_DIR/plan-critical-files.md" \
  "$ALL_FILES_CRIT" \
  '^\[PLAN-COMPLIANCE\] OK \(2 files matched\)$'

echo ""
echo "--- Case 5: round number propagation ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ROUND2_TMP=$(mktemp)
printf 'src/foo.ts\n' > "$ROUND2_TMP"
ROUND2_OUT=$(plan_compliance_check "$FIXTURE_DIR/plan-missing.md" "$ROUND2_TMP" 2)
rm -f "$ROUND2_TMP"
if printf '%s\n' "$ROUND2_OUT" | grep -qE 'round=2\)$'; then
  echo -e "  ${GREEN}PASS${NC} round=N propagates into [PLAN-COMPLIANCE-WARN] lines"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} round=N propagation"
  echo -e "       Actual stdout: $ROUND2_OUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "--- Case 6: SKILL.md prose contract ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE '^[[:space:]]+\*\*§14a — Plan-Compliance Pre-Check\*\*' "$REPO_DIR/skills/impl/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} skills/impl/SKILL.md retains §14a header"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} skills/impl/SKILL.md is missing the §14a Plan-Compliance Pre-Check section"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE '^[[:space:]]+h\. \*\*Plan-Compliance hint\*\*' "$REPO_DIR/skills/impl/SKILL.md"; then
  echo -e "  ${GREEN}PASS${NC} skills/impl/SKILL.md Step 15 carries the conditional Plan-Compliance hint field"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} skills/impl/SKILL.md is missing Step 15.h Plan-Compliance hint"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_summary
