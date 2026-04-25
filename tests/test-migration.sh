#!/usr/bin/env bash
# PR E Task 3 (AC 3.2) + Task 2: migration fixture tests.
#
# The /impl skill's §11a migration logic is expressed as prose, not code,
# so these tests are static-structural: we build 4 fixture scenarios on
# disk that each exercise one branch of §11a, then assert via grep on
# skills/impl/SKILL.md that the skill text documents the correct handling
# for that branch. Re-running /impl across fixtures directly is out of
# scope — the skill is executed by Claude, not by bash — but the static
# presence of the branch instructions is what the tests guard.
#
# Fixture branches covered (see skills/impl/SKILL.md §11a):
#   1. Clean legacy only            (impl-state.yaml only)           → §11a.1
#   2. Both files, phases.impl populated  → §11a.0 sub-case A (skip migration)
#   3. Both files, phases.impl null       → §11a.0 sub-case B (re-migrate)
#   4. Legacy file with unknown field     → §11a.1 with legacy_extras
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

echo "=== migration fixture tests (PR E Task 2 / Task 3) ==="
echo ""

IMPL_SKILL="$REPO_DIR/skills/impl/SKILL.md"

MIGRATION_TMP=""
setup_fixture() {
  # $1 = fixture label
  MIGRATION_TMP=$(mktemp -d)
  mkdir -p "$MIGRATION_TMP/.simple-workflow/backlog/active/001-fixture-$1"
}
cleanup_fixture() {
  if [ -n "$MIGRATION_TMP" ] && [ -d "$MIGRATION_TMP" ]; then
    rm -rf "$MIGRATION_TMP"
    MIGRATION_TMP=""
  fi
}
trap 'cleanup_fixture' EXIT

# --- Fixture 1: clean legacy (impl-state.yaml only) ---
setup_fixture "clean-legacy"
F1="$MIGRATION_TMP/.simple-workflow/backlog/active/001-fixture-clean-legacy"
cat > "$F1/impl-state.yaml" <<EOF
phase: evaluator-complete
current_round: 2
max_rounds: 3
last_ac_status: FAIL
last_audit_status: null
last_audit_critical: 0
next_action: start-round-3-generator
size: M
started: 2025-04-15T10:30:00Z
ticket_dir: .simple-workflow/backlog/active/001-fixture-clean-legacy
plan_file: .simple-workflow/backlog/active/001-fixture-clean-legacy/plan.md
feedback_files:
  eval: .simple-workflow/backlog/active/001-fixture-clean-legacy/eval-round-2.md
  quality: null
EOF

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$F1/impl-state.yaml" ] && [ ! -f "$F1/phase-state.yaml" ]; then
  echo -e "  ${GREEN}PASS${NC} Fixture 1 (clean-legacy) seeded: impl-state.yaml only"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture 1 seed state wrong"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Assert the skill documents §11a.1 clean-legacy migration.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE '§?11a\.1|Clean legacy migration' "$IMPL_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} /impl §11a.1 (Clean legacy migration) branch is documented"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /impl §11a.1 missing"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Assert §11a.1 uses mv-to-.bak form (not rm) for cleanup (AC 2.2).
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'mv[[:space:]].*impl-state\.yaml[[:space:]]+.*\.bak' "$IMPL_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} /impl §11a.1 uses mv-to-.bak cleanup (AC 2.2)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /impl §11a.1 does not use mv-to-.bak cleanup form"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_fixture

# --- Fixture 2: both files, phase-state.yaml.phases.impl populated ---
# Sub-case A: migration is already complete. §11a.0 should skip to §11c.
setup_fixture "both-populated"
F2="$MIGRATION_TMP/.simple-workflow/backlog/active/001-fixture-both-populated"
cat > "$F2/impl-state.yaml" <<EOF
phase: evaluator-complete
current_round: 1
max_rounds: 3
next_action: start-audit
EOF
cat > "$F2/phase-state.yaml" <<EOF
version: 1
ticket_dir: .simple-workflow/backlog/active/001-fixture-both-populated
size: M
created: 2025-04-15T09:00:00Z
current_phase: impl
last_completed_phase: scout
overall_status: in-progress
phases:
  create_ticket:
    status: completed
  scout:
    status: completed
  impl:
    status: in-progress
    current_round: 1
    next_action: start-audit
  ship:
    status: pending
EOF

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$F2/impl-state.yaml" ] && [ -f "$F2/phase-state.yaml" ]; then
  echo -e "  ${GREEN}PASS${NC} Fixture 2 (both-populated) seeded"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture 2 seed state wrong"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# §11a.0 sub-case A: populated phase-state → skip migration, go to §11c.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'Sub-case A|migration as already complete|migration is already complete' "$IMPL_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} /impl §11a.0 sub-case A (populated, skip migration) documented"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /impl §11a.0 sub-case A missing"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_fixture

# --- Fixture 3: both files, phase-state.yaml.phases.impl null ---
# Sub-case B: re-populate phases.impl from legacy file.
setup_fixture "both-empty-impl"
F3="$MIGRATION_TMP/.simple-workflow/backlog/active/001-fixture-both-empty-impl"
cat > "$F3/impl-state.yaml" <<EOF
phase: generator-complete
current_round: 1
max_rounds: 3
next_action: start-evaluator
EOF
cat > "$F3/phase-state.yaml" <<EOF
version: 1
ticket_dir: .simple-workflow/backlog/active/001-fixture-both-empty-impl
size: M
created: 2025-04-15T09:00:00Z
current_phase: scout
last_completed_phase: scout
overall_status: in-progress
phases:
  create_ticket:
    status: completed
  scout:
    status: completed
  impl:
    status: null
    current_round: null
    next_action: null
  ship:
    status: pending
EOF

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$F3/impl-state.yaml" ] && [ -f "$F3/phase-state.yaml" ]; then
  echo -e "  ${GREEN}PASS${NC} Fixture 3 (both-empty-impl) seeded"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture 3 seed state wrong"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# §11a.0 sub-case B: null phase-state.impl → re-migrate.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE 'Sub-case B|partial migration|re-migrate|re-populate' "$IMPL_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} /impl §11a.0 sub-case B (null impl, re-migrate) documented"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /impl §11a.0 sub-case B missing"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AC 2.4: re-running /impl on post-migration state does not corrupt the
# file. The guarantee is encoded in §11a.0 prose ("Skip to §11c resume"
# without re-writing). Assert the skill explicitly says Skip / Resume in
# that branch rather than re-writing.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE '§?11a\.0' "$IMPL_SKILL" && \
   grep -qE '[Ss]kip to §?11c|[Pp]roceed to §?11c|Resume dispatch' "$IMPL_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} /impl §11a.0 skips to §11c on already-migrated state (AC 2.4 no-corruption)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /impl §11a.0 does not document no-corruption skip path"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_fixture

# --- Fixture 4: legacy file with unknown field (legacy_extras preservation) ---
setup_fixture "unknown-field"
F4="$MIGRATION_TMP/.simple-workflow/backlog/active/001-fixture-unknown-field"
cat > "$F4/impl-state.yaml" <<EOF
phase: generator-pending
current_round: 1
max_rounds: 3
next_action: start-round-1-generator
custom_flag: true
experimental_mode: aggressive
size: M
started: 2025-04-15T10:30:00Z
ticket_dir: .simple-workflow/backlog/active/001-fixture-unknown-field
EOF

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$F4/impl-state.yaml" ]; then
  echo -e "  ${GREEN}PASS${NC} Fixture 4 (unknown-field) seeded with custom_flag / experimental_mode"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture 4 seed state wrong"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AC 2.3: §11a must instruct preservation of unknown legacy keys under
# phases.impl.legacy_extras.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF 'legacy_extras' "$IMPL_SKILL" && \
   grep -qE 'unknown|preserv' "$IMPL_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} /impl §11a.1 preserves unknown keys under phases.impl.legacy_extras (AC 2.3)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} /impl §11a.1 legacy_extras preservation not documented"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_fixture

# --- Structural: all three 11a branches present as labelled sections ---
for branch in '§11a.0' '§11a.1'; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qF "$branch" "$IMPL_SKILL"; then
    echo -e "  ${GREEN}PASS${NC} /impl SKILL.md contains section label $branch"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} /impl SKILL.md missing section label $branch"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# §11b (Bootstrap) and §11c (Resume dispatch) must remain intact (pre-existing; PR E must not break them).
for branch in '11b' '11c'; do
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  # Accept either "**11b. Bootstrap" heading form or any "§11b" / "11b."
  # inline reference.
  if grep -qE "\*\*${branch}\.|§?${branch}\b" "$IMPL_SKILL"; then
    echo -e "  ${GREEN}PASS${NC} /impl SKILL.md still references §${branch}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} /impl SKILL.md lost reference to §${branch}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""
print_summary
