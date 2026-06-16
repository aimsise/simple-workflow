#!/usr/bin/env bash
# test-state-parsers.sh — cross-version regression tests for
# `hooks/lib/parse-state-file.sh` against the v7 and v8 fixtures under
# `tests/fixtures/state-schema/`.
#
# Coverage matrix (P2-4 §Design):
#
#   | function                          | v7 fixture | v8 fixture |
#   |---                                |---         |---         |
#   | parse_ticket_ship_dirs            | 7 lines    | 5 lines    |
#   | parse_ticket_statuses             | completed x7 | completed x5 |
#   | is_autopilot_context (scaffolded) | exit 0     | exit 0     |
#   | find_any_autopilot_state_file     | exit 0     | exit 0     |
#
# Plus migration-tool checks (Phase 2):
#   - tools/migrate-state-schema.sh --help exits 0 with --in / --out usage
#   - migration produces a canonical v8-shaped output
#   - migration is idempotent on already-migrated input

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$REPO_DIR/hooks/lib"
TOOLS_DIR="$REPO_DIR/tools"
FIX_DIR="$REPO_DIR/tests/fixtures/state-schema"

# Color output (kept aligned with tests/test-helper.sh's conventions).
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       expected: $expected"
    echo -e "       actual:   $actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_exit_zero() {
  local description="$1" actual_exit="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ "$actual_exit" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description (exit=$actual_exit)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_contains() {
  local description="$1" needle="$2" haystack="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       expected to find: $needle"
    echo -e "       in: $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo "=== state-schema cross-version parser tests ==="
echo ""

V7_FIX="$FIX_DIR/v7-shelftrack/autopilot-state.yaml"
V8_FIX="$FIX_DIR/v8-shelftrack/autopilot-state.yaml"

# AC-1: fixtures exist.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$V7_FIX" ] && [ -f "$V8_FIX" ]; then
  echo -e "  ${GREEN}PASS${NC} AC-1: both v7 and v8 fixtures exist"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-1: missing fixture (v7=$V7_FIX v8=$V8_FIX)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Source the parser helpers.
# shellcheck disable=SC1091
source "$LIB_DIR/parse-state-file.sh"

# AC-2: parse_ticket_ship_dirs line counts.
v7_ship_count="$(parse_ticket_ship_dirs "$V7_FIX" | wc -l | tr -d ' ')"
assert_eq "AC-2a: parse_ticket_ship_dirs v7 -> 7 lines" "7" "$v7_ship_count"

v8_ship_count="$(parse_ticket_ship_dirs "$V8_FIX" | wc -l | tr -d ' ')"
assert_eq "AC-2b: parse_ticket_ship_dirs v8 -> 5 lines" "5" "$v8_ship_count"

# AC-3: parse_ticket_statuses values.
v7_statuses_uniq="$(parse_ticket_statuses "$V7_FIX" | sort -u | tr '\n' ',' | sed 's/,$//')"
assert_eq "AC-3a: parse_ticket_statuses v7 -> only 'completed'" "completed" "$v7_statuses_uniq"
v7_statuses_count="$(parse_ticket_statuses "$V7_FIX" | wc -l | tr -d ' ')"
assert_eq "AC-3a: parse_ticket_statuses v7 -> 7 entries" "7" "$v7_statuses_count"

v8_statuses_uniq="$(parse_ticket_statuses "$V8_FIX" | sort -u | tr '\n' ',' | sed 's/,$//')"
assert_eq "AC-3b: parse_ticket_statuses v8 -> only 'completed'" "completed" "$v8_statuses_uniq"
v8_statuses_count="$(parse_ticket_statuses "$V8_FIX" | wc -l | tr -d ' ')"
assert_eq "AC-3b: parse_ticket_statuses v8 -> 5 entries" "5" "$v8_statuses_count"

# AC-4: is_autopilot_context against scaffolded tempdir layouts that mirror
# the fixture into a canonical brief location. The parser walks upward to a
# `.simple-workflow/backlog/` anchor, so we must build that scaffold for
# the function to recognise the context.
SCAFFOLD_TMP="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$SCAFFOLD_TMP'" EXIT

V7_SLUG="v7-shelftrack"
V8_SLUG="v8-shelftrack"
V7_SCAFFOLD="$SCAFFOLD_TMP/v7/.simple-workflow/backlog/briefs/active/$V7_SLUG"
V8_SCAFFOLD="$SCAFFOLD_TMP/v8/.simple-workflow/backlog/briefs/active/$V8_SLUG"
mkdir -p "$V7_SCAFFOLD" "$V8_SCAFFOLD"
cp "$V7_FIX" "$V7_SCAFFOLD/autopilot-state.yaml"
cp "$V8_FIX" "$V8_SCAFFOLD/autopilot-state.yaml"

set +e
is_autopilot_context "$V7_SCAFFOLD/"
v7_ctx_exit=$?
is_autopilot_context "$V8_SCAFFOLD/"
v8_ctx_exit=$?
set -e
assert_exit_zero "AC-4a: is_autopilot_context returns 0 for v7 fixture in canonical scaffold" "$v7_ctx_exit"
assert_exit_zero "AC-4b: is_autopilot_context returns 0 for v8 fixture in canonical scaffold" "$v8_ctx_exit"

# Find_any_autopilot_state_file should locate the same scaffolded files.
set +e
v7_found="$(find_any_autopilot_state_file "$V7_SCAFFOLD/")"
v7_find_exit=$?
v8_found="$(find_any_autopilot_state_file "$V8_SCAFFOLD/")"
v8_find_exit=$?
set -e
assert_exit_zero "AC-4c: find_any_autopilot_state_file resolves v7 scaffold" "$v7_find_exit"
assert_exit_zero "AC-4d: find_any_autopilot_state_file resolves v8 scaffold" "$v8_find_exit"
assert_contains "AC-4c: v7 scaffold path resolves under expected slug dir" "$V7_SLUG/autopilot-state.yaml" "$v7_found"
assert_contains "AC-4d: v8 scaffold path resolves under expected slug dir" "$V8_SLUG/autopilot-state.yaml" "$v8_found"

# AC-5: docs/state-schema.md contains the three required invariants.
DOC="$REPO_DIR/docs/state-schema.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$DOC" ] \
    && grep -qF 'processing_order' "$DOC" \
    && grep -qF 'ticket_dir' "$DOC" \
    && grep -qF 'fullpath' "$DOC"; then
  echo -e "  ${GREEN}PASS${NC} AC-5: docs/state-schema.md contains processing_order / ticket_dir / fullpath"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-5: docs/state-schema.md missing one of processing_order / ticket_dir / fullpath"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- Phase 2: migration tool checks ----------------------------------------

MIG_TOOL="$TOOLS_DIR/migrate-state-schema.sh"

# AC-7: tool exists and is executable.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -x "$MIG_TOOL" ]; then
  echo -e "  ${GREEN}PASS${NC} AC-7a: tools/migrate-state-schema.sh exists and is executable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-7a: tools/migrate-state-schema.sh missing or not executable"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# AC-7b: --help exits 0 and contains --in / --out.
set +e
help_out="$(bash "$MIG_TOOL" --help 2>&1)"
help_exit=$?
set -e
assert_exit_zero "AC-7b: --help exits 0" "$help_exit"
assert_contains "AC-7b: --help mentions --in" "--in" "$help_out"
assert_contains "AC-7b: --help mentions --out" "--out" "$help_out"

# AC-8: migrate v7 -> v8 and validate canonical shape.
MIG_OUT="$SCAFFOLD_TMP/v7-migrated.yaml"
set +e
bash "$MIG_TOOL" --in "$V7_FIX" --out "$MIG_OUT"
mig_exit=$?
set -e
assert_exit_zero "AC-8a: migration completes with exit 0" "$mig_exit"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$MIG_OUT" ]; then
  echo -e "  ${GREEN}PASS${NC} AC-8b: migrated output file produced"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC-8b: migrated output file not produced"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Verify shape with yq when available; fall back to grep when not.
if command -v yq >/dev/null 2>&1; then
  po_len="$(yq -r '.processing_order | length' "$MIG_OUT")"
  assert_eq "AC-8c: processing_order has 7 entries" "7" "$po_len"

  ho_len="$(yq -r '.human_overrides | length' "$MIG_OUT")"
  assert_eq "AC-8d: human_overrides = []" "0" "$ho_len"

  ko_len="$(yq -r '.kb_overrides | length' "$MIG_OUT")"
  assert_eq "AC-8e: kb_overrides = []" "0" "$ko_len"

  dm_len="$(yq -r '.decisions_made | length' "$MIG_OUT")"
  assert_eq "AC-8f: decisions_made = []" "0" "$dm_len"

  tt_present="$(yq -r 'has("total_tickets")' "$MIG_OUT")"
  assert_eq "AC-8g: total_tickets removed" "false" "$tt_present"

  bd_present="$(yq -r 'has("boundary")' "$MIG_OUT")"
  assert_eq "AC-8h: boundary removed" "false" "$bd_present"

  pr_url_first="$(yq -r '.tickets[0].pr_url' "$MIG_OUT")"
  assert_eq "AC-8i: tickets[0].pr_url = null" "null" "$pr_url_first"

  fr_first="$(yq -r '.tickets[0].failure_reason' "$MIG_OUT")"
  assert_eq "AC-8j: tickets[0].failure_reason = null" "null" "$fr_first"
else
  echo -e "  ${RED}FAIL${NC} AC-8c..j: yq unavailable, cannot verify migrated shape"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
fi

# AC-9: idempotence — second migration produces zero diff.
MIG_OUT2="$SCAFFOLD_TMP/v7-migrated-twice.yaml"
set +e
bash "$MIG_TOOL" --in "$MIG_OUT" --out "$MIG_OUT2"
mig2_exit=$?
set -e
assert_exit_zero "AC-9a: second migration completes with exit 0" "$mig2_exit"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if command -v yq >/dev/null 2>&1; then
  if diff <(yq -P . "$MIG_OUT") <(yq -P . "$MIG_OUT2") >/dev/null 2>&1; then
    echo -e "  ${GREEN}PASS${NC} AC-9b: second migration is idempotent (diff zero, yq-normalised)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AC-9b: second migration is NOT idempotent"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  if diff "$MIG_OUT" "$MIG_OUT2" >/dev/null 2>&1; then
    echo -e "  ${GREEN}PASS${NC} AC-9b: second migration is idempotent (byte-exact, yq unavailable)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AC-9b: second migration is NOT idempotent"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
fi

# AC-10 (proposal 3 / ST-01,ST-11): parse_active_steps is WI-3 schema-tolerant —
# it returns the SAME active (in_progress|pending) step set for the canonical-flat,
# inline-flow, and nested step shapes. The continuation driver
# (hooks/autopilot-continue.sh) relies on this to count unfinished steps and pick
# the next step across all three forms. Reverting proposal 3 removes the helper, so
# every assertion below fails (empty output).
PAS_FLAT="$SCAFFOLD_TMP/pas-flat.yaml"
PAS_FLOW="$SCAFFOLD_TMP/pas-flow.yaml"
PAS_NESTED="$SCAFFOLD_TMP/pas-nested.yaml"
cat > "$PAS_FLAT" <<'EOF'
tickets:
  - logical_id: t1
    ticket_dir: 001-a
    status: in_progress
    steps:
      create-ticket: completed
      scout: in_progress
      impl: pending
      ship: pending
EOF
cat > "$PAS_FLOW" <<'EOF'
tickets:
  - logical_id: t1
    ticket_dir: 001-a
    status: in_progress
    steps: {create-ticket: completed, scout: in_progress, impl: pending, ship: pending}
EOF
cat > "$PAS_NESTED" <<'EOF'
tickets:
  - logical_id: t1
    ticket_dir: 001-a
    status: in_progress
    steps:
      create-ticket:
        status: completed
      scout:
        status: in_progress
      impl:
        status: pending
      ship:
        status: pending
EOF
PAS_EXPECT="scout:in_progress,impl:pending,ship:pending"
pas_flat="$(parse_active_steps "$PAS_FLAT" 2>/dev/null | tr '\n' ',' | sed 's/,$//')" || pas_flat=""
pas_flow="$(parse_active_steps "$PAS_FLOW" 2>/dev/null | tr '\n' ',' | sed 's/,$//')" || pas_flow=""
pas_nested="$(parse_active_steps "$PAS_NESTED" 2>/dev/null | tr '\n' ',' | sed 's/,$//')" || pas_nested=""
assert_eq "AC-10a: parse_active_steps flat form -> active steps" "$PAS_EXPECT" "$pas_flat"
assert_eq "AC-10b: parse_active_steps inline-flow form -> active steps" "$PAS_EXPECT" "$pas_flow"
assert_eq "AC-10c: parse_active_steps nested form -> active steps" "$PAS_EXPECT" "$pas_nested"

echo ""
echo "==============================="
echo -e "Total: $TESTS_TOTAL | ${GREEN}Passed: $TESTS_PASSED${NC} | ${RED}Failed: $TESTS_FAILED${NC}"
echo "==============================="

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
