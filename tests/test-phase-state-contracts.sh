#!/usr/bin/env bash
# PR E Task 3: phase-state.yaml contract tests.
#
# These are static checks — they do not run /scout, /impl, or /ship. The
# point is to prove by grep / file inspection that:
#   1. The canonical schema document exists and names the required sections.
#   2. Each skill respects write-ownership for phase-state.yaml (only its
#      own section plus the top-level status fields).
#   3. No skill or hook ever deletes phase-state.yaml (the permanent record
#      invariant from the schema doc's §6 "Contractual invariants").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

echo "=== phase-state.yaml contract tests (PR E Task 3) ==="
echo ""

SCHEMA_DOC="$REPO_DIR/skills/create-ticket/references/phase-state-schema.md"

# --- 1. Schema document exists ---
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$SCHEMA_DOC" ]; then
  echo -e "  ${GREEN}PASS${NC} phase-state-schema.md exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} phase-state-schema.md is missing at $SCHEMA_DOC"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- 2. Schema document has the required section headings ---
# The canonical schema doc is organized around these section titles; any
# missing heading indicates a structural regression.
for heading in \
  "## 1. Canonical schema" \
  "## 2. Write ownership" \
  "## 3. Lifecycle rules" \
  "## 4. Legacy migration path" \
  "## 5. Field renames from legacy" \
  "## 6. Contractual invariants" \
  "## 7. Readers"; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qF "$heading" "$SCHEMA_DOC" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} schema doc has heading: $heading"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} schema doc missing heading: $heading"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# --- 3. Write-ownership: /scout body does not WRITE to phases.impl ---
# /scout may mention phases.impl in prose (e.g. "do not touch phases.impl"
# or "only /impl writes phases.impl"), but it must NEVER have a write
# instruction that sets phases.impl.* — the rule is "one section per
# writer". We detect writes by requiring an assignment-shaped line such as
# "phases.impl.status: completed". A pure read/guard mention is
# permitted (lines without a colon-value assignment).
SCOUT_SKILL="$REPO_DIR/skills/scout/SKILL.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
# Match "phases.impl" on the same line as an assignment-like pattern.
# Negative control: a guard-only line like "phases.scout.status ==
# completed AND current_phase in {impl, ship, done}" should NOT match
# because "phases.impl" itself does not appear there.
SCOUT_IMPL_WRITES=$(grep -nE 'phases\.impl\.[a-z_]+:[[:space:]]*(completed|in-progress|failed|pending|true|false|[a-zA-Z0-9])' "$SCOUT_SKILL" 2>/dev/null || true)
if [ -z "$SCOUT_IMPL_WRITES" ]; then
  echo -e "  ${GREEN}PASS${NC} /scout SKILL.md does not assign phases.impl.* fields"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /scout SKILL.md writes to phases.impl (write-ownership violation):"
  echo "$SCOUT_IMPL_WRITES" | sed 's/^/       /'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- 4. Write-ownership: /impl body does not WRITE to phases.scout ---
# Reads and path-lookups for phases.scout.artifacts.* are fine (e.g.
# resolving the plan path); assignments are not. Migration and bootstrap
# (§11a, §11b) legitimately backfill phases.scout.status as part of the
# one-shot legacy migration / fresh-state bootstrap — those sections are
# explicitly part of /impl's write ownership per the schema doc §4.
# We detect unsafe writes by computing for each matching line whether the
# nearest preceding section heading is one of the migration/bootstrap
# sections. If any match falls OUTSIDE those sections, fail.
IMPL_SKILL="$REPO_DIR/skills/impl/SKILL.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
IMPL_SCOUT_UNSAFE=""
while IFS= read -r match_line; do
  [ -z "$match_line" ] && continue
  line_no="${match_line%%:*}"
  # Find the nearest preceding line matching a top-level numbered step or
  # sub-step marker. Migration / bootstrap sections are 11a, 11a.0,
  # 11a.1, 11b. Any other enclosing step is suspect.
  enclosing=$(awk -v target="$line_no" '
    /^§?11a\.0|^§?11a\.1|^§11a|^11a\.|^11b\.|Sub-case|Legacy migration|Bootstrap/ {sect=$0}
    /^[0-9]+\./ {sect=$0}
    NR==target {print sect; exit}
  ' "$IMPL_SKILL")
  # Accept lines enclosed by migration/bootstrap prose.
  if echo "$enclosing" | grep -qE '11a|11b|Legacy migration|Bootstrap|Sub-case'; then
    continue
  fi
  IMPL_SCOUT_UNSAFE+="$match_line"$'\n'
done < <(grep -nE 'phases\.scout\.[a-z_]+:[[:space:]]*(completed|in-progress|failed|pending|true|false)' "$IMPL_SKILL" 2>/dev/null || true)
if [ -z "${IMPL_SCOUT_UNSAFE//[[:space:]]/}" ]; then
  echo -e "  ${GREEN}PASS${NC} /impl SKILL.md does not assign phases.scout.* outside migration/bootstrap"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /impl SKILL.md writes to phases.scout outside migration (write-ownership violation):"
  echo "$IMPL_SCOUT_UNSAFE" | sed 's/^/       /'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- 5. No skill or hook ever deletes phase-state.yaml ---
# The contractual invariant in schema doc §6 is "Skills MUST NOT delete
# phase-state.yaml at any point". An `rm` in a SKILL.md or hook body is
# a direct violation.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
PHASE_STATE_DELETES=$(grep -rnE 'rm[[:space:]].*phase-state\.yaml' \
  "$REPO_DIR/skills/" \
  "$REPO_DIR/hooks/" 2>/dev/null || true)
if [ -z "$PHASE_STATE_DELETES" ]; then
  echo -e "  ${GREEN}PASS${NC} no rm on phase-state.yaml anywhere in skills/ or hooks/"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} rm on phase-state.yaml detected (schema §6 invariant violation):"
  echo "$PHASE_STATE_DELETES" | sed 's/^/       /'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- 6. No skill uses `rm` on legacy impl-state.yaml ---
# Per PR E Task 2 / AC 2.2: cleanup of the legacy file must use the
# `mv ... .bak` form, never `rm`. This preserves auditability.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
IMPL_STATE_DELETES=$(grep -rnE 'rm[[:space:]].*impl-state\.yaml' \
  "$REPO_DIR/skills/" 2>/dev/null || true)
if [ -z "$IMPL_STATE_DELETES" ]; then
  echo -e "  ${GREEN}PASS${NC} no rm on legacy impl-state.yaml in skills/"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} rm on impl-state.yaml detected (Task 2 AC 2.2 violation):"
  echo "$IMPL_STATE_DELETES" | sed 's/^/       /'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- 7. §11a documents the both-files-exist partial-migration branch ---
# AC 2.1 requirement: §11a.0 must explicitly call out the "both files
# exist" branch with both sub-cases (populated vs null phases.impl).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE '§?11a\.0|Both files exist|both files exist' "$IMPL_SKILL" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} /impl §11a documents the both-files-exist branch"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /impl §11a missing both-files-exist branch (AC 2.1)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- 8. legacy_extras preservation is documented ---
# AC 2.3 requirement.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'legacy_extras' "$IMPL_SKILL" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} /impl §11a documents legacy_extras preservation (AC 2.3)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /impl §11a missing legacy_extras preservation (AC 2.3)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_summary
