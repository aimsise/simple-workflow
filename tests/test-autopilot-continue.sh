#!/usr/bin/env bash
# Tests for hooks/autopilot-continue.sh — autopilot pipeline Stop hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== autopilot-continue.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/autopilot-continue.sh"

# Trap to ensure cleanup on exit
trap 'cleanup_test_repo' EXIT

# Helper: create autopilot-state.yaml with given content
create_state_file() {
  local slug="$1"
  local content="$2"
  mkdir -p ".simple-workflow/backlog/briefs/active/${slug}"
  echo "$content" > ".simple-workflow/backlog/briefs/active/${slug}/autopilot-state.yaml"
}

# Helper: run the autopilot-continue hook with optional env vars
run_autopilot_hook() {
  local input="${1:-{}}"
  local cwd="${2:-.}"
  local env_count="${3:-}"

  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)

  set +e
  if [ -n "$env_count" ]; then
    echo "$input" | (cd "$cwd" && _AUTOPILOT_CONTINUE_COUNT="$env_count" bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  else
    echo "$input" | (cd "$cwd" && bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  fi
  local exit_code=$?
  set -e

  LAST_EXIT_CODE=$exit_code
  # shellcheck disable=SC2034
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

# ============================================================
# AC-1: No autopilot-state.yaml — allow stop
# ============================================================
echo "--- AC-1: No state file ---"

setup_test_repo
run_autopilot_hook '{}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} No state file: exit 0, no stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} No state file: exit 0, no stdout"
  echo -e "       Exit code: $LAST_EXIT_CODE, Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# AC-2: All tickets completed — allow stop
# ============================================================
echo "--- AC-2: All tickets completed ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: completed
    steps:
      create-ticket: completed
      scout: completed
      impl: completed
      ship: completed"

run_autopilot_hook '{}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} All completed: exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} All completed: exit 0"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# AC-3: All tickets failed/skipped — allow stop
# ============================================================
echo "--- AC-3: All tickets failed/skipped ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: split
total_tickets: 2
tickets:
  - logical_id: test-slug-part-1
    ticket_dir: 001-test
    status: failed
    steps:
      create-ticket: completed
      scout: failed
      impl: failed
      ship: failed
  - logical_id: test-slug-part-2
    ticket_dir: null
    status: skipped
    steps:
      create-ticket: skipped
      scout: skipped
      impl: skipped
      ship: skipped"

run_autopilot_hook '{}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} All failed/skipped: exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} All failed/skipped: exit 0"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# AC-4: scout in_progress — block stop
# ============================================================
echo "--- AC-4: scout in_progress ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: in_progress
      impl: pending
      ship: pending"

run_autopilot_hook '{"session_id":"test-ac4"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} scout in_progress: decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} scout in_progress: decision=block"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac4
cleanup_test_repo

# ============================================================
# AC-5: impl in_progress — block stop
# ============================================================
echo "--- AC-5: impl in_progress ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: completed
      impl: in_progress
      ship: pending"

run_autopilot_hook '{"session_id":"test-ac5"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} impl in_progress: decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} impl in_progress: decision=block"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac5
cleanup_test_repo

# ============================================================
# AC-6: ship in_progress — block stop
# ============================================================
echo "--- AC-6: ship in_progress ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: completed
      impl: completed
      ship: in_progress"

run_autopilot_hook '{"session_id":"test-ac6"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} ship in_progress: decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ship in_progress: decision=block"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac6
cleanup_test_repo

# ============================================================
# AC-7: reason contains required fields
# ============================================================
echo "--- AC-7: reason content ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: completed
      impl: in_progress
      ship: pending"

run_autopilot_hook '{"session_id":"test-ac7"}' "$TEST_REPO"
REASON=$(echo "$LAST_STDOUT" | jq -r '.reason // ""' 2>/dev/null || echo "")

# Check for autopilot-state.yaml mention
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -q "autopilot-state.yaml"; then
  echo -e "  ${GREEN}PASS${NC} reason mentions autopilot-state.yaml"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason mentions autopilot-state.yaml"
  echo -e "       Reason: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Check for autopilot mention
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -q "autopilot"; then
  echo -e "  ${GREEN}PASS${NC} reason mentions autopilot"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason mentions autopilot"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Check for next step name (impl in this case)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -q "impl"; then
  echo -e "  ${GREEN}PASS${NC} reason mentions next step (impl)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason mentions next step (impl)"
  echo -e "       Reason: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac7
cleanup_test_repo

# ============================================================
# AC-8: Loop guard — env var >= 5 allows stop
# ============================================================
echo "--- AC-8: Loop guard ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: in_progress
      impl: pending
      ship: pending"

# With _AUTOPILOT_CONTINUE_COUNT=5, should allow stop
run_autopilot_hook '{}' "$TEST_REPO" "5"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} Loop guard (count=5): exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Loop guard (count=5): exit 0"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# With _AUTOPILOT_CONTINUE_COUNT=10, should also allow stop
run_autopilot_hook '{}' "$TEST_REPO" "10"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} Loop guard (count=10): exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Loop guard (count=10): exit 0"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# With _AUTOPILOT_CONTINUE_COUNT=4, should still block
run_autopilot_hook '{"session_id":"test-ac8"}' "$TEST_REPO" "4"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} Loop guard (count=4): still blocks"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Loop guard (count=4): still blocks"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac8
cleanup_test_repo

# ============================================================
# AC-9: Split execution — multiple tickets
# ============================================================
echo "--- AC-9: Split execution ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: split
total_tickets: 4
tickets:
  - logical_id: test-slug-part-1
    ticket_dir: 001-done
    status: completed
    steps:
      create-ticket: completed
      scout: completed
      impl: completed
      ship: completed
  - logical_id: test-slug-part-2
    ticket_dir: 002-active
    status: in_progress
    steps:
      create-ticket: completed
      scout: in_progress
      impl: pending
      ship: pending
  - logical_id: test-slug-part-3
    ticket_dir: null
    status: pending
    steps:
      create-ticket: pending
      scout: pending
      impl: pending
      ship: pending
  - logical_id: test-slug-part-4
    ticket_dir: null
    status: pending
    steps:
      create-ticket: pending
      scout: pending
      impl: pending
      ship: pending"

run_autopilot_hook '{"session_id":"test-ac9"}' "$TEST_REPO"
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
REASON=$(echo "$LAST_STDOUT" | jq -r '.reason // ""' 2>/dev/null || echo "")

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} Split: decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Split: decision=block"
  echo -e "       Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Check reason mentions ticket 2's ticket_dir
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -q "002-active"; then
  echo -e "  ${GREEN}PASS${NC} Split: reason mentions ticket 2 dir (002-active)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Split: reason mentions ticket 2 dir (002-active)"
  echo -e "       Reason: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-ac9
cleanup_test_repo

# ============================================================
# AC-12: Empty stdin — no crash
# ============================================================
echo "--- AC-12: Empty stdin ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: in_progress
      impl: pending
      ship: pending"

# Run with completely empty stdin
AC12_STDOUT=$(mktemp)
AC12_STDERR=$(mktemp)
set +e
echo -n "" | (cd "$TEST_REPO" && bash "$HOOK") >"$AC12_STDOUT" 2>"$AC12_STDERR"
LAST_EXIT_CODE=$?
LAST_STDOUT=$(cat "$AC12_STDOUT")
LAST_STDERR=$(cat "$AC12_STDERR")
rm -f "$AC12_STDOUT" "$AC12_STDERR"
set -e

TESTS_TOTAL=$((TESTS_TOTAL + 1))
# Should not crash — either exit 0 or output valid JSON
if [ "$LAST_EXIT_CODE" -eq 0 ] || echo "$LAST_STDOUT" | jq -e '.decision' >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} Empty stdin: no crash"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Empty stdin: no crash"
  echo -e "       Exit code: $LAST_EXIT_CODE"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# Auto-kick tests (brief → create-ticket → autopilot chain guard)
# ============================================================

# Helper: create brief.md + auto-kick.yaml under .simple-workflow/backlog/briefs/active/{slug}
create_autokick_fixture() {
  local slug="$1"
  mkdir -p ".simple-workflow/backlog/briefs/active/${slug}"
  cat > ".simple-workflow/backlog/briefs/active/${slug}/brief.md" <<EOF
---
slug: ${slug}
created: 2026-04-20
status: confirmed
estimated_size: M
estimated_category: CodeQuality
interview_complete: true
---
# Brief
EOF
  cat > ".simple-workflow/backlog/briefs/active/${slug}/auto-kick.yaml" <<EOF
version: 1
slug: ${slug}
started: 2026-04-20T00:00:00Z
EOF
}

# Helper: create split-plan.md under .simple-workflow/backlog/product_backlog/{slug}
create_split_plan() {
  local slug="$1"
  mkdir -p ".simple-workflow/backlog/product_backlog/${slug}"
  cat > ".simple-workflow/backlog/product_backlog/${slug}/split-plan.md" <<EOF
---
parent_slug: ${slug}
findings_source: ""
ticket_count: 1
created: 2026-04-20T00:00:00Z
version: 1
---
# Split Plan: ${slug}
EOF
}

# Global cleanup for autokick counter files
rm -f /tmp/.autokick-continue-test-autokick-* 2>/dev/null || true

# ============================================================
# AC-AUTOKICK-2: brief confirmed + auto-kick.yaml → decision=block, exit 0
# ============================================================
echo "--- AC-AUTOKICK-2: brief + auto-kick.yaml → block ---"

setup_test_repo
create_autokick_fixture "feat-x"

run_autopilot_hook '{"session_id":"test-autokick-2"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] && [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} auto-kick only: decision=block, exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} auto-kick only: decision=block, exit 0"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autokick-continue-test-autokick-2
cleanup_test_repo

# ============================================================
# AC-AUTOKICK-3: auto-kick.yaml + split-plan.md present →
#   reason contains /autopilot, {slug}, Skill tool, and NOT /create-ticket
# ============================================================
echo "--- AC-AUTOKICK-3: auto-kick + split-plan → reason shape (autopilot only) ---"

setup_test_repo
create_autokick_fixture "feat-x"
create_split_plan "feat-x"

run_autopilot_hook '{"session_id":"test-autokick-3"}' "$TEST_REPO"
REASON=$(echo "$LAST_STDOUT" | jq -r '.reason // ""' 2>/dev/null || echo "")

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -qF "/autopilot"; then
  echo -e "  ${GREEN}PASS${NC} reason contains /autopilot"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason contains /autopilot — got: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -qF "feat-x"; then
  echo -e "  ${GREEN}PASS${NC} reason contains slug feat-x"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason contains slug feat-x — got: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -qF "Skill tool"; then
  echo -e "  ${GREEN}PASS${NC} reason contains 'Skill tool'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason contains 'Skill tool' — got: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# NegAC5: reason does NOT contain /create-ticket
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! echo "$REASON" | grep -qF "/create-ticket"; then
  echo -e "  ${GREEN}PASS${NC} [NegAC5] reason does NOT contain /create-ticket (split-plan present)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} [NegAC5] reason does NOT contain /create-ticket"
  echo -e "       Reason: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autokick-continue-test-autokick-3
cleanup_test_repo

# ============================================================
# AC-AUTOKICK-4: auto-kick.yaml present + split-plan.md ABSENT →
#   reason contains /create-ticket, /autopilot, {slug}, Skill tool
#   AND no stdout line starts with /create-ticket (NegAC6)
# ============================================================
echo "--- AC-AUTOKICK-4: auto-kick + NO split-plan → reason shape (create-ticket + autopilot) ---"

setup_test_repo
create_autokick_fixture "feat-y"

run_autopilot_hook '{"session_id":"test-autokick-4"}' "$TEST_REPO"
REASON=$(echo "$LAST_STDOUT" | jq -r '.reason // ""' 2>/dev/null || echo "")

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -qF "/create-ticket"; then
  echo -e "  ${GREEN}PASS${NC} reason contains /create-ticket"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason contains /create-ticket — got: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -qF "/autopilot"; then
  echo -e "  ${GREEN}PASS${NC} reason contains /autopilot"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason contains /autopilot"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -qF "feat-y"; then
  echo -e "  ${GREEN}PASS${NC} reason contains slug feat-y"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason contains slug feat-y"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -qF "Skill tool"; then
  echo -e "  ${GREEN}PASS${NC} reason contains 'Skill tool'"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason contains 'Skill tool'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# NegAC6: /create-ticket MUST NOT appear at line start of stdout
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! echo "$LAST_STDOUT" | grep -qE '^/create-ticket'; then
  echo -e "  ${GREEN}PASS${NC} [NegAC6] no stdout line starts with /create-ticket"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} [NegAC6] stdout has line starting with /create-ticket"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autokick-continue-test-autokick-4
cleanup_test_repo

# ============================================================
# AC-AUTOKICK-5: BOTH autopilot-state.yaml AND auto-kick.yaml present →
#   reason uses autopilot-state content, NOT auto-kick message
# ============================================================
echo "--- AC-AUTOKICK-5: both state + auto-kick → state file wins ---"

setup_test_repo
create_autokick_fixture "feat-z"
# Overwrite brief.md with state file addition
create_state_file "feat-z" "version: 1
slug: feat-z
started: 2026-04-20T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: feat-z
    ticket_dir: 001-test
    status: in_progress
    steps:
      scout: in_progress
      impl: pending
      ship: pending"

run_autopilot_hook '{"session_id":"test-autokick-5"}' "$TEST_REPO"
REASON=$(echo "$LAST_STDOUT" | jq -r '.reason // ""' 2>/dev/null || echo "")

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -qF "autopilot-state.yaml"; then
  echo -e "  ${GREEN}PASS${NC} reason contains autopilot-state.yaml"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason contains autopilot-state.yaml — got: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$REASON" | grep -qF "steps:"; then
  echo -e "  ${GREEN}PASS${NC} reason contains steps: block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason contains steps: block — got: $REASON"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! echo "$REASON" | grep -qF "auto-kick.yaml"; then
  echo -e "  ${GREEN}PASS${NC} reason does NOT contain auto-kick.yaml (state file wins)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} reason does NOT contain auto-kick.yaml"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-autokick-5 /tmp/.autokick-continue-test-autokick-5
cleanup_test_repo

# ============================================================
# AC-AUTOKICK-6: 5 consecutive auto-kick invocations → 6th returns exit 0 empty stdout
# ============================================================
echo "--- AC-AUTOKICK-6: auto-kick loop guard (5→allow stop on 6th) ---"

setup_test_repo
create_autokick_fixture "feat-loop"

LOOP_BLOCKED=0
for _ in 1 2 3 4 5; do
  run_autopilot_hook '{"session_id":"test-autokick-6"}' "$TEST_REPO"
  DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
  if [ "$DECISION" = "block" ]; then
    LOOP_BLOCKED=$((LOOP_BLOCKED + 1))
  fi
done

# 6th invocation
run_autopilot_hook '{"session_id":"test-autokick-6"}' "$TEST_REPO"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LOOP_BLOCKED" -eq 5 ]; then
  echo -e "  ${GREEN}PASS${NC} first 5 invocations all blocked"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} first 5 invocations all blocked (got $LOOP_BLOCKED/5 blocks)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} 6th invocation: exit 0 + empty stdout (loop guard fires)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} 6th invocation: exit 0 + empty stdout"
  echo -e "       Exit code: $LAST_EXIT_CODE, Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autokick-continue-test-autokick-6
cleanup_test_repo

# ============================================================
# AC-AUTOKICK-7: auto-kick.yaml mtime newer than counter → counter resets
# ============================================================
echo "--- AC-AUTOKICK-7: auto-kick.yaml mtime bump resets counter ---"

setup_test_repo
create_autokick_fixture "feat-bump"

# Run 5 times to trigger loop guard
for _ in 1 2 3 4 5; do
  run_autopilot_hook '{"session_id":"test-autokick-7"}' "$TEST_REPO"
done
# At this point, 6th would allow stop. Touch auto-kick.yaml so it's newer than counter.
sleep 1
touch "$TEST_REPO/.simple-workflow/backlog/briefs/active/feat-bump/auto-kick.yaml"

run_autopilot_hook '{"session_id":"test-autokick-7"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} counter reset after mtime bump: decision=block again"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} counter reset after mtime bump"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autokick-continue-test-autokick-7
cleanup_test_repo

# ============================================================
# AC-AUTOKICK-8 (indirect): /autopilot SKILL.md documents auto-kick.yaml cleanup
# ============================================================
echo "--- AC-AUTOKICK-8: /autopilot SKILL.md documents auto-kick cleanup ---"

AUTOPILOT_SKILL="$SCRIPT_DIR/../skills/autopilot/SKILL.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qF "auto-kick.yaml" "$AUTOPILOT_SKILL" && grep -qF "delete" "$AUTOPILOT_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} autopilot SKILL.md mentions auto-kick.yaml deletion"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} autopilot SKILL.md mentions auto-kick.yaml deletion"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# NegAC7: the auto-kick cleanup step must NOT instruct deletion of
# brief.md / autopilot-policy.yaml / autopilot-state.yaml
TESTS_TOTAL=$((TESTS_TOTAL + 1))
# Extract the auto-kick cleanup paragraph (heuristic: the sentence block mentioning auto-kick.yaml)
# and verify it contains a "do NOT touch" style guard for the other files
if grep -qE "Do NOT touch .*brief\.md.*autopilot-policy\.yaml.*autopilot-state\.yaml" "$AUTOPILOT_SKILL"; then
  echo -e "  ${GREEN}PASS${NC} [NegAC7] SKILL.md explicitly forbids touching brief/policy/state"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} [NegAC7] SKILL.md missing 'Do NOT touch brief.md...policy...state' guard"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ============================================================
# NegAC-AUTOKICK-3: neither autopilot-state.yaml nor auto-kick.yaml → exit 0, empty stdout
# ============================================================
echo "--- NegAC-AUTOKICK-3: neither state nor auto-kick → exit 0, empty stdout ---"

setup_test_repo
# Deliberately do NOT create any files under .simple-workflow/backlog/briefs/active/

run_autopilot_hook '{"session_id":"test-autokick-neg3"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} [NegAC3] no state + no auto-kick: exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} [NegAC3] no state + no auto-kick: exit 0, empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE, Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# Plan 02: NOTOOL_COUNT (tool-use absence) counter + AND-release rule
# ============================================================
echo ""
echo "=== Plan 02: NOTOOL_COUNT counter ==="
echo ""

P02_FIXTURES_DIR="$(cd "$SCRIPT_DIR/fixtures/transcripts" 2>/dev/null && pwd)"

# Helper: run hook with explicit session id, transcript path, and pre-populated counters.
# Args: $1=session_id, $2=transcript_path (relative to fixtures dir, or empty),
#       $3=mtime_count_initial (number, blank to leave counter file absent),
#       $4=notool_count_initial (number, blank to leave absent),
#       $5=cwd (test repo root), $6=extra_env_var ("AUTOPILOT_LEGACY_LOOPGUARD=1" or empty)
run_p02_hook() {
  local sid="$1"
  local transcript="$2"
  local mtime_init="$3"
  local notool_init="$4"
  local cwd="${5:-.}"
  local extra_env="${6:-}"

  local mtime_file="/tmp/.autopilot-continue-${sid}"
  local notool_file="/tmp/.autopilot-notool-${sid}"
  rm -f "$mtime_file" "$notool_file"

  if [ -n "$mtime_init" ]; then echo "$mtime_init" > "$mtime_file"; fi
  if [ -n "$notool_init" ]; then echo "$notool_init" > "$notool_file"; fi

  local input
  if [ -n "$transcript" ]; then
    input=$(jq -n --arg sid "$sid" --arg tp "$P02_FIXTURES_DIR/$transcript" \
      '{session_id:$sid, transcript_path:$tp}')
  else
    input=$(jq -n --arg sid "$sid" '{session_id:$sid}')
  fi

  local stdout_file stderr_file
  stdout_file=$(mktemp); stderr_file=$(mktemp)
  set +e
  if [ -n "$extra_env" ]; then
    echo "$input" | (cd "$cwd" && env "$extra_env" bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  else
    echo "$input" | (cd "$cwd" && bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  fi
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$stdout_file"); LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
  P02_NOTOOL_AFTER=$(cat "$notool_file" 2>/dev/null || echo "")
  rm -f "$mtime_file" "$notool_file"
}

# Helper: write a minimal in-progress autopilot-state.yaml so the hook treats
# the pipeline as active. The yaml uses literal newlines so we keep it inline
# rather than using an HEREDOC (the existing tests use the same pattern).
p02_create_state() {
  local slug="$1"
  mkdir -p ".simple-workflow/backlog/briefs/active/${slug}"
  cat > ".simple-workflow/backlog/briefs/active/${slug}/autopilot-state.yaml" <<EOF
version: 1
parent_slug: ${slug}
started: 2026-04-29T00:00:00Z
execution_mode: split
total_tickets: 1
ticket_mapping: {}
tickets:
  - logical_id: ${slug}-part-1
    ticket_dir: 001-test
    status: in_progress
    steps:
      scout: in_progress
      impl: pending
      ship: pending
manual_bash_fallbacks: []
runtime_metrics: []
EOF
  # Backdate state file so the file-based counter (created later) is "newer"
  # than the state file — i.e. STATE_FILE -nt COUNTER_FILE is FALSE so the
  # mtime guard does NOT reset FILE_COUNT in these synthetic scenarios.
  if [ "$(uname -s)" = "Darwin" ]; then
    touch -A -010000 ".simple-workflow/backlog/briefs/active/${slug}/autopilot-state.yaml" 2>/dev/null || true
  else
    touch -d "1 hour ago" ".simple-workflow/backlog/briefs/active/${slug}/autopilot-state.yaml" 2>/dev/null || true
  fi
}

# ------------------------------------------------------------
# AC #2: mtime stuck but tool_use present → block (no release)
# ------------------------------------------------------------
echo "--- Plan 02 / AC #2: mtime stuck but tool_use present ---"
setup_test_repo
p02_create_state "p02-ac2"
run_p02_hook "p02-ac2" "tool_use_present.jsonl" "5" "0" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DEC" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} mtime stuck but tool_use present: decision=block (no release)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} mtime stuck but tool_use present"
  echo -e "       Got decision='$DEC', exit=$LAST_EXIT_CODE, stdout snippet: ${LAST_STDOUT:0:120}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC #3: tool_use unblocks counter (NOTOOL counter file → 0)
# ------------------------------------------------------------
echo "--- Plan 02 / AC #3: tool_use unblocks counter ---"
setup_test_repo
p02_create_state "p02-ac3"
run_p02_hook "p02-ac3" "tool_use_present.jsonl" "" "4" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$P02_NOTOOL_AFTER" = "0" ]; then
  echo -e "  ${GREEN}PASS${NC} tool_use unblocks counter: NOTOOL counter reset to 0 (was 4)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tool_use unblocks counter"
  echo -e "       Expected NOTOOL=0, got '$P02_NOTOOL_AFTER'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC #4: double stuck releases (FILE>=5 AND NOTOOL>=5) → exit 0 + [AUTOPILOT-STALL] on stdout
# ------------------------------------------------------------
echo "--- Plan 02 / AC #4: double stuck releases ---"
setup_test_repo
p02_create_state "p02-ac4"
run_p02_hook "p02-ac4" "text_only_5_consecutive.jsonl" "5" "4" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && echo "$LAST_STDOUT" | grep -qE '\[AUTOPILOT-STALL\]'; then
  echo -e "  ${GREEN}PASS${NC} double stuck releases: exit 0 + [AUTOPILOT-STALL] on stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} double stuck releases"
  echo -e "       exit=$LAST_EXIT_CODE, stdout: ${LAST_STDOUT:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC #5: realistic full turn parsing (complex content array)
#         The fixture's last assistant turn carries Read AND Edit tool_use blocks;
#         Edit is in the real-tool set so NOTOOL must reset to 0.
# ------------------------------------------------------------
echo "--- Plan 02 / AC #5: realistic full turn parsing ---"
setup_test_repo
p02_create_state "p02-ac5"
run_p02_hook "p02-ac5" "realistic_full_turn.jsonl" "" "3" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$P02_NOTOOL_AFTER" = "0" ]; then
  echo -e "  ${GREEN}PASS${NC} realistic full turn parsing: NOTOOL reset to 0 (Edit tool_use detected)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} realistic full turn parsing"
  echo -e "       Expected NOTOOL=0, got '$P02_NOTOOL_AFTER'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC #6: Read alone does NOT reset NOTOOL (Read excluded from real-tool set)
# ------------------------------------------------------------
echo "--- Plan 02 / AC #6: Read alone does not reset ---"
setup_test_repo
p02_create_state "p02-ac6"
run_p02_hook "p02-ac6" "read_only_turns.jsonl" "" "2" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$P02_NOTOOL_AFTER" = "3" ]; then
  echo -e "  ${GREEN}PASS${NC} Read alone does not reset: NOTOOL incremented 2→3"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} Read alone does not reset"
  echo -e "       Expected NOTOOL=3, got '$P02_NOTOOL_AFTER'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC #7: malformed transcript → hook does not crash; emits valid JSON or exit 0
# ------------------------------------------------------------
echo "--- Plan 02 / AC #7: malformed transcript ---"
setup_test_repo
p02_create_state "p02-ac7"
run_p02_hook "p02-ac7" "malformed.jsonl" "" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -n "$DEC" ]; then
  echo -e "  ${GREEN}PASS${NC} malformed transcript: exit 0 + decision='$DEC' (no crash)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} malformed transcript"
  echo -e "       exit=$LAST_EXIT_CODE decision='$DEC' stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC #9 part 1: legacy loop guard env var skips NOTOOL — FILE=4 still blocks
# even when transcript shows no tool_use (in non-legacy mode this would also
# block because FILE<5; the non-trivial assertion is that the FILE-only path
# is the only gate).
# ------------------------------------------------------------
echo "--- Plan 02 / AC #9: legacy loop guard env var (mtime gate alone) ---"
setup_test_repo
p02_create_state "p02-ac9a"
run_p02_hook "p02-ac9a" "text_only_5_consecutive.jsonl" "4" "10" "$TEST_REPO" "AUTOPILOT_LEGACY_LOOPGUARD=1"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
# Even though NOTOOL initial was 10 (above threshold), legacy mode bypasses it
# and FILE=4 alone is below threshold → block.
if [ "$DEC" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} legacy loop guard (FILE=4): decision=block (NOTOOL bypassed)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} legacy loop guard (FILE=4)"
  echo -e "       Got decision='$DEC' stdout: ${LAST_STDOUT:0:120}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# AC #9 part 2: legacy + FILE=5 still releases (mtime alone, regardless of tool_use)
echo "--- Plan 02 / AC #9: legacy loop guard env var (FILE=5 releases) ---"
setup_test_repo
p02_create_state "p02-ac9b"
# tool_use_present transcript: in non-legacy mode this would force NOTOOL=0
# and PREVENT release; in legacy mode NOTOOL is bypassed so FILE>=5 alone
# triggers release. This is the precise AC #9 sub-assertion.
run_p02_hook "p02-ac9b" "tool_use_present.jsonl" "5" "0" "$TEST_REPO" "AUTOPILOT_LEGACY_LOOPGUARD=1"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && echo "$LAST_STDOUT" | grep -qE '\[AUTOPILOT-STALL\]'; then
  echo -e "  ${GREEN}PASS${NC} legacy loop guard (FILE=5): release fires regardless of tool_use"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} legacy loop guard (FILE=5)"
  echo -e "       exit=$LAST_EXIT_CODE stdout: ${LAST_STDOUT:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# NAC #2 regression: auto-kick branch unchanged
# ------------------------------------------------------------
echo "--- Plan 02 / NAC #2 regression: autokick branch unchanged ---"
setup_test_repo
mkdir -p .simple-workflow/backlog/briefs/active/test-autokick-p02
cat > .simple-workflow/backlog/briefs/active/test-autokick-p02/auto-kick.yaml <<'EOF'
slug: test-autokick-p02
EOF

run_p02_hook "p02-autokick" "" "" "" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
REASON=$(echo "$LAST_STDOUT" | jq -r '.reason // ""' 2>/dev/null || echo "")
if [ "$DEC" = "block" ] && echo "$REASON" | grep -q 'auto-kick.yaml'; then
  echo -e "  ${GREEN}PASS${NC} autokick branch unchanged: decision=block + reason mentions auto-kick.yaml"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} autokick branch unchanged"
  echo -e "       decision='$DEC' reason: ${REASON:0:120}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# Policy-gate-stop honour gate (SW_AUTOPILOT_POLICY_STOP_HONOR)
# ============================================================
echo ""
echo "=== Policy-gate-stop honour gate ==="
echo ""

# Helper: run the hook with an in-tree autopilot-state.yaml, a transcript
# path, and an explicit SW_AUTOPILOT_POLICY_STOP_HONOR value. Captures the
# state-file content AFTER the run so the runtime_metrics emit can be
# asserted. The state file carries an in_progress step so that, ABSENT the
# honour gate, the hook would block (the regression baseline).
# Args: $1=session_id, $2=transcript (rel to fixtures dir), $3=honor_value
#       ("" leaves the var unset), $4=cwd (test repo root)
PGS_STATE_AFTER=""
run_pgs_hook() {
  local sid="$1"; local transcript="$2"; local honor="$3"; local cwd="${4:-.}"
  local mtime_file="/tmp/.autopilot-continue-${sid}"
  local notool_file="/tmp/.autopilot-notool-${sid}"
  rm -f "$mtime_file" "$notool_file"

  local input
  input=$(jq -n --arg sid "$sid" --arg tp "$P02_FIXTURES_DIR/$transcript" \
    '{session_id:$sid, transcript_path:$tp}')

  local stdout_file stderr_file
  stdout_file=$(mktemp); stderr_file=$(mktemp)
  set +e
  if [ -n "$honor" ]; then
    echo "$input" | (cd "$cwd" && env SW_AUTOPILOT_POLICY_STOP_HONOR="$honor" bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  else
    echo "$input" | (cd "$cwd" && bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  fi
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$stdout_file"); LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
  PGS_STATE_AFTER=$(cat "$cwd/.simple-workflow/backlog/briefs/active/${sid}/autopilot-state.yaml" 2>/dev/null || echo "")
  rm -f "$mtime_file" "$notool_file"
}

# ------------------------------------------------------------
# AC-2: honour on declaration → allow stop (no block) + session_end /
#       policy_gate_stop runtime_metrics entry.
# ------------------------------------------------------------
echo "--- AC-2: honour on declaration (allow stop + metric) ---"
setup_test_repo
p02_create_state "pgs-honor"
run_pgs_hook "pgs-honor" "policy_gate_stop_last_turn.jsonl" "on" "$TEST_REPO"
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ "$DEC" != "block" ]; then
  echo -e "  ${GREEN}PASS${NC} honour: exit 0, no decision=block (allows stop)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} honour: expected exit 0 + no block"
  echo -e "       exit=$LAST_EXIT_CODE decision='$DEC' stdout: ${LAST_STDOUT:0:160}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$PGS_STATE_AFTER" | grep -qF 'stop_reason: policy_gate_stop' \
   && echo "$PGS_STATE_AFTER" | grep -qF 'boundary: session_end'; then
  echo -e "  ${GREEN}PASS${NC} honour: runtime_metrics session_end / policy_gate_stop appended"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} honour: expected session_end / policy_gate_stop metric entry"
  echo -e "       state tail: $(printf '%s' "$PGS_STATE_AFTER" | tail -8)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC-2 regression: same state file but transcript WITHOUT the marker →
#       the hook still blocks.
# ------------------------------------------------------------
echo "--- AC-2 regression: no marker → still blocks ---"
setup_test_repo
p02_create_state "pgs-nomarker"
# read_only_turns.jsonl: last assistant turn has no [AUTOPILOT-POLICY] marker.
run_pgs_hook "pgs-nomarker" "read_only_turns.jsonl" "on" "$TEST_REPO"
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DEC" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} no marker: decision=block (loop guard backstop intact)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} no marker: expected decision=block"
  echo -e "       exit=$LAST_EXIT_CODE decision='$DEC'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC-5: kill switch off → ignore the declaration (block as before).
# ------------------------------------------------------------
echo "--- AC-5: kill switch off → block despite marker ---"
setup_test_repo
p02_create_state "pgs-off"
run_pgs_hook "pgs-off" "policy_gate_stop_last_turn.jsonl" "off" "$TEST_REPO"
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DEC" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} off: decision=block (declaration ignored)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} off: expected decision=block"
  echo -e "       exit=$LAST_EXIT_CODE decision='$DEC'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC-5: unknown value → fail-closed to off semantics (block).
# ------------------------------------------------------------
echo "--- AC-5: unknown value → fail-closed (block) ---"
setup_test_repo
p02_create_state "pgs-unknown"
run_pgs_hook "pgs-unknown" "policy_gate_stop_last_turn.jsonl" "garbage-value" "$TEST_REPO"
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DEC" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} unknown: decision=block (fail-closed to off)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} unknown: expected decision=block"
  echo -e "       exit=$LAST_EXIT_CODE decision='$DEC'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# AC-5: metric-only → still blocks AND emits a [POLICY-GATE-STOP] "would
#       honour" stderr line.
# ------------------------------------------------------------
echo "--- AC-5: metric-only → block + [POLICY-GATE-STOP] stderr ---"
setup_test_repo
p02_create_state "pgs-metric"
run_pgs_hook "pgs-metric" "policy_gate_stop_last_turn.jsonl" "metric-only" "$TEST_REPO"
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DEC" = "block" ] && echo "$LAST_STDERR" | grep -qF '[POLICY-GATE-STOP]' \
   && echo "$LAST_STDERR" | grep -qiF 'would honour'; then
  echo -e "  ${GREEN}PASS${NC} metric-only: decision=block + [POLICY-GATE-STOP] would-honour stderr"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} metric-only: expected block + would-honour stderr line"
  echo -e "       decision='$DEC' stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# No false stop: marker only in an EARLIER assistant turn → still blocks
# (honour on).
# ------------------------------------------------------------
echo "--- no false stop: marker in earlier turn only → block ---"
setup_test_repo
p02_create_state "pgs-earlier"
run_pgs_hook "pgs-earlier" "policy_gate_stop_earlier_turn_only.jsonl" "on" "$TEST_REPO"
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DEC" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} earlier-turn marker: decision=block (last turn governs)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} earlier-turn marker: expected decision=block"
  echo -e "       exit=$LAST_EXIT_CODE decision='$DEC'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# No false stop: marker only inside a tool_use input → still blocks.
# ------------------------------------------------------------
echo "--- no false stop: marker in tool_use input only → block ---"
setup_test_repo
p02_create_state "pgs-tooluse"
run_pgs_hook "pgs-tooluse" "policy_gate_stop_tool_use_only.jsonl" "on" "$TEST_REPO"
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$DEC" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} tool_use-only marker: decision=block (text blocks only)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} tool_use-only marker: expected decision=block"
  echo -e "       exit=$LAST_EXIT_CODE decision='$DEC'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ------------------------------------------------------------
# Honour works under AUTOPILOT_LEGACY_LOOPGUARD=1 (TRANSCRIPT_PATH hoist).
# ------------------------------------------------------------
echo "--- honour under AUTOPILOT_LEGACY_LOOPGUARD=1 ---"
setup_test_repo
p02_create_state "pgs-legacy"
LEGACY_SID="pgs-legacy"
rm -f "/tmp/.autopilot-continue-${LEGACY_SID}" "/tmp/.autopilot-notool-${LEGACY_SID}"
LEGACY_INPUT=$(jq -n --arg sid "$LEGACY_SID" --arg tp "$P02_FIXTURES_DIR/policy_gate_stop_last_turn.jsonl" \
  '{session_id:$sid, transcript_path:$tp}')
LEGACY_STDOUT=$(mktemp); LEGACY_STDERR=$(mktemp)
set +e
echo "$LEGACY_INPUT" | (cd "$TEST_REPO" && env AUTOPILOT_LEGACY_LOOPGUARD=1 SW_AUTOPILOT_POLICY_STOP_HONOR=on bash "$HOOK") >"$LEGACY_STDOUT" 2>"$LEGACY_STDERR"
LAST_EXIT_CODE=$?
set -e
LAST_STDOUT=$(cat "$LEGACY_STDOUT"); LAST_STDERR=$(cat "$LEGACY_STDERR")
rm -f "$LEGACY_STDOUT" "$LEGACY_STDERR" "/tmp/.autopilot-continue-${LEGACY_SID}" "/tmp/.autopilot-notool-${LEGACY_SID}"
DEC=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ "$DEC" != "block" ] \
   && echo "$LAST_STDERR" | grep -qF '[POLICY-GATE-STOP]'; then
  echo -e "  ${GREEN}PASS${NC} legacy loopguard: honour still fires (exit 0, no block)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} legacy loopguard: expected honour (exit 0, no block)"
  echo -e "       exit=$LAST_EXIT_CODE decision='$DEC' stderr: ${LAST_STDERR:0:160}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# ============================================================
# AC-NESTED (proposal 3 / ST-01): nested-form scout in_progress — block stop.
# WI-3 schema-tolerance regression guard. The prior flat-only grep in the
# continuation driver matched `scout: in_progress` but NOT the nested
# `scout:\n  status: in_progress` shape, so a purely nested state yielded
# ACTIVE_STEPS=0 and allowed a premature stop. Routing ACTIVE_STEPS/NEXT_STEP
# through parse_active_steps must now block. Reverting that refactor makes this
# case FAIL (decision != block).
# ============================================================
echo "--- AC-NESTED: nested-form scout in_progress (WI-3) ---"

setup_test_repo
create_state_file "test-slug" "version: 1
slug: test-slug
started: 2026-04-15T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: test-slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket:
        status: completed
      scout:
        status: in_progress
      impl:
        status: pending
      ship:
        status: pending"

run_autopilot_hook '{"session_id":"test-nested"}' "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
REASON_NEXT=$(echo "$LAST_STDOUT" | jq -r '.reason // ""' 2>/dev/null | grep -c 'scout' || true)
if [ "$DECISION" = "block" ] && [ "$REASON_NEXT" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} nested-form scout in_progress: decision=block, next step 'scout' resolved (WI-3 nested tolerance)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} nested-form scout in_progress: expected decision=block with next step 'scout'"
  echo -e "       Exit code: $LAST_EXIT_CODE, Decision: '$DECISION', scout-in-reason: '$REASON_NEXT'"
  echo -e "       Stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rm -f /tmp/.autopilot-continue-test-nested
cleanup_test_repo

echo ""
print_summary
