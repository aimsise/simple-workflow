#!/usr/bin/env bash
# PR E Task 3 (AC 3.3) + Task 4: SessionStart hook fixture tests.
#
# Each test builds a temp git repo, seeds a specific .simple-workflow/backlog/ / filesystem
# state, runs hooks/session-start.sh against it, and asserts on the
# additionalContext JSON output. We cover:
#
#   A. Valid seeded phase-state.yaml (active/)            → Active tickets: line present
#   B. Valid seeded phase-state.yaml (product_backlog/)   → Active tickets: line present with (product_backlog)
#   C. Malformed YAML                                     → exit 0, ticket silently skipped
#   D. chmod 000 phase-state.yaml                         → exit 0, ticket silently skipped
#   E. Missing .simple-workflow/backlog/ directory        → no Active tickets line
#
# (Task 4 AC 4.1 requires the product_backlog location marker, so scenario
# B is added alongside the 4 required scenarios.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

echo "=== session-start hook fixture tests (PR E Task 3 / Task 4) ==="
echo ""

HOOK="$HOOK_DIR/session-start.sh"

# Trap cleanup in case of early exit mid-fixture
trap 'cleanup_test_repo' EXIT

# Helper: write a minimal valid phase-state.yaml
write_valid_phase_state() {
  local dir="$1"
  local phase="${2:-scout}"
  local last_completed="${3:-create_ticket}"
  local status="${4:-in-progress}"
  cat > "$dir/phase-state.yaml" <<EOF
version: 1
ticket_dir: $dir
size: M
created: 2025-04-15T09:00:00Z
current_phase: $phase
last_completed_phase: $last_completed
overall_status: $status
phases:
  create_ticket:
    status: completed
  scout:
    status: pending
  impl:
    status: pending
  ship:
    status: pending
EOF
}

# --- Fixture A: valid seeded phase-state.yaml in .simple-workflow/backlog/active/ ---
setup_test_repo
mkdir -p "$TEST_REPO/.simple-workflow/backlog/active/001-foo"
write_valid_phase_state "$TEST_REPO/.simple-workflow/backlog/active/001-foo" "scout" "create_ticket" "in-progress"
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if [ "$LAST_EXIT_CODE" -eq 0 ] && \
   echo "$CONTEXT" | grep -qF "Active tickets:" && \
   echo "$CONTEXT" | grep -qF "001-foo"; then
  echo -e "  ${GREEN}PASS${NC} Fixture A: valid .simple-workflow/backlog/active ticket appears under 'Active tickets:'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture A: expected 'Active tickets:' + '001-foo' in output"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  echo -e "       Context:   $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
# Scenario-specific additional marker: active tickets get an (active) marker.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$CONTEXT" | grep -qF "(active)"; then
  echo -e "  ${GREEN}PASS${NC} Fixture A: active ticket line carries '(active)' location marker"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture A: (active) marker missing"
  echo -e "       Context: $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# --- Fixture B: product_backlog ticket emits (product_backlog) marker (Task 4 AC 4.1) ---
setup_test_repo
mkdir -p "$TEST_REPO/.simple-workflow/backlog/product_backlog/001-bar"
write_valid_phase_state "$TEST_REPO/.simple-workflow/backlog/product_backlog/001-bar" "create_ticket" "create_ticket" "in-progress"
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if [ "$LAST_EXIT_CODE" -eq 0 ] && \
   echo "$CONTEXT" | grep -qF "Active tickets:" && \
   echo "$CONTEXT" | grep -qF "001-bar" && \
   echo "$CONTEXT" | grep -qF "(product_backlog)"; then
  echo -e "  ${GREEN}PASS${NC} Fixture B: product_backlog ticket appears with '(product_backlog)' marker (AC 4.1)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture B: product_backlog ticket / marker missing"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  echo -e "       Context:   $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# --- Fixture C: malformed YAML → exit 0, silent skip ---
setup_test_repo
mkdir -p "$TEST_REPO/.simple-workflow/backlog/active/001-foo"
# Write garbage that will make every scalar extraction return empty.
cat > "$TEST_REPO/.simple-workflow/backlog/active/001-foo/phase-state.yaml" <<EOF
!!this is not YAML at all
:::
<unclosed brace {
EOF
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if [ "$LAST_EXIT_CODE" -eq 0 ] && \
   echo "$LAST_STDOUT" | jq . >/dev/null 2>&1 && \
   ! echo "$CONTEXT" | grep -qF "001-foo"; then
  # We want: hook exited 0, output is valid JSON, malformed ticket was
  # silently skipped (not mentioned in Active tickets).
  echo -e "  ${GREEN}PASS${NC} Fixture C: malformed YAML silently skipped, hook exits 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture C: malformed YAML was not handled gracefully"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  echo -e "       Context:   $CONTEXT"
  echo -e "       Stderr:    $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# --- Fixture D: chmod 000 phase-state.yaml → exit 0, silent skip ---
# Root rarely runs tests; if the current user can still read chmod-000
# files (unusual, but possible), this test would give a false pass. We
# detect that case by attempting to read the file ourselves after the
# chmod; if we CAN read it the test is inconclusive and we mark it as
# skipped rather than failing, because the point is to exercise the
# hook's [ -r "$f" ] guard — which only triggers when the file is truly
# unreadable.
setup_test_repo
mkdir -p "$TEST_REPO/.simple-workflow/backlog/active/001-foo"
write_valid_phase_state "$TEST_REPO/.simple-workflow/backlog/active/001-foo" "scout" "create_ticket" "in-progress"
chmod 000 "$TEST_REPO/.simple-workflow/backlog/active/001-foo/phase-state.yaml" 2>/dev/null || true

if [ ! -r "$TEST_REPO/.simple-workflow/backlog/active/001-foo/phase-state.yaml" ]; then
  run_hook "$HOOK" "" "$TEST_REPO"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
  if [ "$LAST_EXIT_CODE" -eq 0 ] && \
     echo "$LAST_STDOUT" | jq . >/dev/null 2>&1 && \
     ! echo "$CONTEXT" | grep -qF "001-foo"; then
    echo -e "  ${GREEN}PASS${NC} Fixture D: chmod 000 ticket silently skipped, hook exits 0"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} Fixture D: chmod 000 was not handled gracefully"
    echo -e "       Exit code: $LAST_EXIT_CODE"
    echo -e "       Context:   $CONTEXT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  echo -e "  ${YELLOW}SKIP${NC} Fixture D: current user can still read chmod-000 file (test inconclusive)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi
# Restore permissions before cleanup so rm -rf doesn't choke.
chmod 600 "$TEST_REPO/.simple-workflow/backlog/active/001-foo/phase-state.yaml" 2>/dev/null || true
cleanup_test_repo

# --- Fixture E: missing .simple-workflow/backlog/ → no Active tickets line ---
setup_test_repo
# No .simple-workflow/backlog directory at all.
run_hook "$HOOK" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if [ "$LAST_EXIT_CODE" -eq 0 ] && \
   echo "$CONTEXT" | grep -qF "Branch:" && \
   echo "$CONTEXT" | grep -qF "Changed files:" && \
   ! echo "$CONTEXT" | grep -qF "Active tickets:"; then
  echo -e "  ${GREEN}PASS${NC} Fixture E: missing .simple-workflow/backlog → original Branch + Changed files only, no 'Active tickets:' line"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture E: missing .simple-workflow/backlog behaviour regressed"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  echo -e "       Context:   $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# --- Fixture F: subdirectory cwd (AC 15.4) ---
# Hook must work when invoked from a subdirectory of the repo. Prior
# behavior broke because `.simple-workflow/backlog/active/*/phase-state.yaml` was resolved
# relative to $PWD rather than the repo root. After the cwd anchor, the
# hook must still surface the ticket even when pwd sits deep in the tree.
setup_test_repo
mkdir -p "$TEST_REPO/.simple-workflow/backlog/active/001-foo"
write_valid_phase_state "$TEST_REPO/.simple-workflow/backlog/active/001-foo" "scout" "create_ticket" "in-progress"
# Create a nested subdirectory and invoke the hook from there.
mkdir -p "$TEST_REPO/src/foo"
run_hook "$HOOK" "" "$TEST_REPO/src/foo"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CONTEXT=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""')
if [ "$LAST_EXIT_CODE" -eq 0 ] && \
   echo "$CONTEXT" | grep -qF "Active tickets:" && \
   echo "$CONTEXT" | grep -qF "001-foo" && \
   echo "$CONTEXT" | grep -qF ".simple-workflow/backlog/active/001-foo" && \
   ! echo "$CONTEXT" | grep -qE "/(tmp|private)/"; then
  # The ticket must appear, and its path must be rendered relative to the
  # repo root (not as an absolute path leaking the tmpdir prefix).
  echo -e "  ${GREEN}PASS${NC} Fixture F: hook invoked from src/foo/ still sees .simple-workflow/backlog/active/ (AC 15.4)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Fixture F: subdirectory cwd regressed"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  echo -e "       Context:   $CONTEXT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

echo ""
print_summary
