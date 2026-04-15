#!/usr/bin/env bash
# test-integration.sh — Integration tests using claude -p (Level 1)
#
# These tests exercise real skill invocations via claude CLI in headless mode.
# Post-condition verification only — we don't assert on CLI output, just
# check the filesystem/git state after the skill runs.
#
# Requires: claude CLI installed and authenticated.
# When claude CLI is not available, all tests are SKIPped (exit 0).
set -euo pipefail

# --- claude CLI detection ---
if ! command -v claude &>/dev/null; then
  echo "SKIP: claude CLI not found (test-integration.sh skipped)"
  exit 0
fi

# --- opt-in guard (avoids accidental API charges) ---
if [ "${RUN_LEVEL1_TESTS:-}" != "true" ]; then
  echo "SKIP: RUN_LEVEL1_TESTS is not set (run with RUN_LEVEL1_TESTS=true to execute)"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

# ============================================================
# Integration-specific assertion helpers
# ============================================================

assert_true() {
  local description="$1"
  local condition="$2"  # shell expression evaluated with eval
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if eval "$condition"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_false() {
  local description="$1"
  local condition="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if ! eval "$condition"; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Portable timeout wrapper (macOS lacks coreutils timeout)
# Usage: run_with_timeout <seconds> <command> [args...]
# Sets TIMEOUT_OUTPUT and TIMEOUT_EXIT_CODE
TIMEOUT_OUTPUT=""
TIMEOUT_EXIT_CODE=0

run_with_timeout() {
  local timeout_secs="$1"
  shift
  local outfile
  outfile=$(mktemp)

  # Determine which timeout command to use
  local timeout_cmd=""
  if command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout"
  elif command -v timeout &>/dev/null; then
    timeout_cmd="timeout"
  fi

  set +e
  if [ -n "$timeout_cmd" ]; then
    $timeout_cmd "$timeout_secs" "$@" 2>&1 | tee "$outfile" >/dev/null
    TIMEOUT_EXIT_CODE=${PIPESTATUS[0]}
  else
    # Fallback: run directly with --max-turns as the only safeguard
    "$@" 2>&1 | tee "$outfile" >/dev/null
    TIMEOUT_EXIT_CODE=${PIPESTATUS[0]}
  fi
  set -e

  TIMEOUT_OUTPUT=$(cat "$outfile")
  rm -f "$outfile"
}

# ============================================================
# Fixture: autopilot-policy.yaml (shared)
# ============================================================

create_autopilot_policy() {
  local dir="$1"
  cat > "$dir/autopilot-policy.yaml" <<'YAML'
version: 1
risk_tolerance: aggressive
gates:
  ticket_quality_fail:
    action: retry_with_feedback
    max_retries: 2
  evaluator_dry_run_fail:
    action: proceed_without
  ac_eval_fail:
    action: retry
    on_critical: stop
  audit_infrastructure_fail:
    action: treat_as_fail
  ship_review_gate:
    action: proceed_if_eval_passed
  ship_ci_pending:
    action: wait
    timeout_minutes: 60
    on_timeout: stop
  unexpected_error:
    action: stop
constraints:
  max_total_rounds: 12
  allow_breaking_changes: true
YAML
}

# ============================================================
# Fixture: setup_ship_fixture
# ============================================================

setup_ship_fixture() {
  local repo
  repo=$(mktemp -d)

  # Initialize git repo
  cd "$repo"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # .gitignore matching production
  cat > .gitignore <<'EOF'
.docs/
.backlog/
.simple-wf-knowledge/
EOF
  git add .gitignore
  git commit -q -m "initial: add .gitignore"

  # Create ticket fixture: .backlog/active/001-test-hello/
  local ticket_dir=".backlog/active/001-test-hello"
  mkdir -p "$ticket_dir"

  cat > "$ticket_dir/ticket.md" <<'MD'
## T-001: Test Hello

| Key | Value |
|-----|-------|
| Category | Feature |
| Size | S |

### Acceptance Criteria
- [ ] AC1: hello.txt exists with content "Hello"
MD

  create_autopilot_policy "$ticket_dir"

  cat > "$ticket_dir/plan.md" <<'MD'
# Implementation Plan — T-001: Test Hello

## Steps
1. Create hello.txt with content "Hello"

## Verification
- Check hello.txt exists and contains "Hello"
MD

  cat > "$ticket_dir/eval-round-1.md" <<'MD'
# Evaluation Round 1

## Status: PASS

### AC Results
- [x] AC1: hello.txt exists with content "Hello" — PASS
MD

  # Copy skills and agents into the test repo so claude can find them
  cp -r "$REPO_DIR/skills" "$repo/skills"
  cp -r "$REPO_DIR/agents" "$repo/agents"
  git add skills/ agents/
  git commit -q -m "chore: add skills and agents"

  # Create a code change and stage it (after skills commit, so it's a real change)
  echo "Hello" > hello.txt
  git add hello.txt

  echo "$repo"
}

# ============================================================
# Fixture: setup_audit_fixture
# ============================================================

setup_audit_fixture() {
  local repo
  repo=$(mktemp -d)

  # Initialize git repo
  cd "$repo"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # .gitignore matching production
  cat > .gitignore <<'EOF'
.docs/
.backlog/
.simple-wf-knowledge/
EOF
  git add .gitignore
  git commit -q -m "initial: add .gitignore"

  # Create ticket fixture: .backlog/active/002-test-world/
  local ticket_dir=".backlog/active/002-test-world"
  mkdir -p "$ticket_dir"

  cat > "$ticket_dir/ticket.md" <<'MD'
## T-002: Test World

| Key | Value |
|-----|-------|
| Category | Feature |
| Size | S |

### Acceptance Criteria
- [ ] AC1: world.txt exists with content "World"
MD

  create_autopilot_policy "$ticket_dir"

  # Copy skills and agents into the test repo so claude can find them
  cp -r "$REPO_DIR/skills" "$repo/skills"
  cp -r "$REPO_DIR/agents" "$repo/agents"
  git add skills/ agents/
  git commit -q -m "chore: add skills and agents"

  # Create a code change and stage it for audit
  echo "World" > world.txt
  git add world.txt

  echo "$repo"
}

# ============================================================
# Fixture: setup_integration_brief
# ============================================================

setup_integration_brief() {
  local repo="$1"  # Existing repo path (or creates new one if empty)

  if [ -z "$repo" ]; then
    repo=$(mktemp -d)
    cd "$repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > README.md
    git add README.md
    git commit -q -m "initial"
  fi

  local brief_dir=".backlog/briefs/active/test-slug"
  mkdir -p "$brief_dir"

  cat > "$brief_dir/brief.md" <<'MD'
---
title: "Test Utility Files"
status: confirmed
size: S
ticket_count: 2
---

# Brief: Test Utility Files

## Vision
Create two utility text files for testing.

## Scope
- Create hello.txt with content "Hello"
- Create world.txt with content "World"

## Tickets

### Ticket 1: Create hello.txt
- AC1: hello.txt exists with content "Hello"

### Ticket 2: Create world.txt
- AC1: world.txt exists with content "World"
MD

  cat > "$brief_dir/split-plan.md" <<'MD'
# Split Plan

## Tickets

### 001-create-hello
- Size: S
- Dependencies: none
- AC:
  - hello.txt exists with content "Hello"

### 002-create-world
- Size: S
- Dependencies: none
- AC:
  - world.txt exists with content "World"
MD

  create_autopilot_policy "$brief_dir"

  echo "$repo"
}

# ============================================================
# Test: /ship integration
# ============================================================

test_ship_integration() {
  echo "--- Integration: /ship ---"

  local test_repo
  test_repo=$(setup_ship_fixture)

  echo "  Test repo: $test_repo"
  echo "  Running: claude -p \"/ship main ticket-dir=001-test-hello\" ..."

  # Run from plugin repo root so skills are discoverable; use --add-dir for test project
  cd "$REPO_DIR"
  run_with_timeout 300 claude -p "Change to directory $test_repo and then run /ship main ticket-dir=001-test-hello" \
    --add-dir "$test_repo" --permission-mode bypassPermissions --allowed-tools=all --max-turns 15
  cd "$SCRIPT_DIR"

  if [ "$TIMEOUT_EXIT_CODE" -eq 124 ]; then
    echo -e "  ${YELLOW}WARN${NC} claude -p timed out (180s)"
  fi

  # Check if skill was recognized (plugin skills may not be available via claude -p)
  if echo "$TIMEOUT_OUTPUT" | grep -q "Unknown skill"; then
    echo -e "  ${YELLOW}SKIP${NC} /ship skill not available via claude -p (plugin skill resolution pending)"
    rm -rf "$test_repo"
    return 0
  fi

  # AC3: ticket moved from active to done (filesystem check)
  assert_true \
    "/ship: ticket moved to .backlog/done/001-test-hello/" \
    "[ -d '$test_repo/.backlog/done/001-test-hello' ]"

  # AC4: autopilot-state.yaml NOT in HEAD commit
  local head_files=""
  head_files=$(cd "$test_repo" && git show --name-only HEAD 2>/dev/null || echo "")
  assert_false \
    "/ship: autopilot-state.yaml not in HEAD commit" \
    "echo '$head_files' | grep -q 'autopilot-state.yaml'"

  # Cleanup
  rm -rf "$test_repo"
}

# ============================================================
# Test: /audit integration
# ============================================================

test_audit_integration() {
  echo "--- Integration: /audit ---"

  local test_repo
  test_repo=$(setup_audit_fixture)

  echo "  Test repo: $test_repo"
  echo "  Running: claude -p \"/audit round=1 ticket-dir=002-test-world\" ..."

  # Run from plugin repo root so skills are discoverable; use --add-dir for test project
  cd "$REPO_DIR"
  run_with_timeout 300 claude -p "Change to directory $test_repo and then run /audit round=1 ticket-dir=002-test-world" \
    --add-dir "$test_repo" --permission-mode bypassPermissions --allowed-tools=all --max-turns 15
  cd "$SCRIPT_DIR"

  if [ "$TIMEOUT_EXIT_CODE" -eq 124 ]; then
    echo -e "  ${YELLOW}WARN${NC} claude -p timed out (180s)"
  fi

  # Check if skill was recognized (plugin skills may not be available via claude -p)
  if echo "$TIMEOUT_OUTPUT" | grep -q "Unknown skill"; then
    echo -e "  ${YELLOW}SKIP${NC} /audit skill not available via claude -p (plugin skill resolution pending)"
    rm -rf "$test_repo"
    return 0
  fi

  # AC6: quality-round-1.md and security-scan-1.md exist
  assert_true \
    "/audit: quality-round-1.md created" \
    "[ -f '$test_repo/.backlog/active/002-test-world/quality-round-1.md' ]"

  assert_true \
    "/audit: security-scan-1.md created" \
    "[ -f '$test_repo/.backlog/active/002-test-world/security-scan-1.md' ]"

  # Cleanup
  rm -rf "$test_repo"
}

# ============================================================
# Test: brief fixture validation (unit-level, no claude needed)
# ============================================================

test_brief_fixture() {
  echo "--- Integration fixture: setup_integration_brief ---"

  local test_repo
  test_repo=$(mktemp -d)

  # Initialize git repo inside subshell to avoid cwd leaking
  (
    cd "$test_repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > README.md
    git add README.md
    git commit -q -m "initial"
  )

  # setup_integration_brief uses relative paths; run in subshell
  (cd "$test_repo" && setup_integration_brief "$test_repo") > /dev/null

  assert_true \
    "brief fixture: brief.md exists" \
    "[ -f '$test_repo/.backlog/briefs/active/test-slug/brief.md' ]"

  assert_true \
    "brief fixture: split-plan.md exists" \
    "[ -f '$test_repo/.backlog/briefs/active/test-slug/split-plan.md' ]"

  assert_true \
    "brief fixture: autopilot-policy.yaml exists" \
    "[ -f '$test_repo/.backlog/briefs/active/test-slug/autopilot-policy.yaml' ]"

  assert_true \
    "brief fixture: brief.md has confirmed status" \
    "grep -q 'status: confirmed' '$test_repo/.backlog/briefs/active/test-slug/brief.md'"

  assert_true \
    "brief fixture: brief.md has S size" \
    "grep -q 'size: S' '$test_repo/.backlog/briefs/active/test-slug/brief.md'"

  assert_true \
    "brief fixture: brief.md has 2 tickets" \
    "grep -q 'ticket_count: 2' '$test_repo/.backlog/briefs/active/test-slug/brief.md'"

  assert_true \
    "brief fixture: split-plan.md has 001-create-hello" \
    "grep -q '001-create-hello' '$test_repo/.backlog/briefs/active/test-slug/split-plan.md'"

  assert_true \
    "brief fixture: split-plan.md has 002-create-world" \
    "grep -q '002-create-world' '$test_repo/.backlog/briefs/active/test-slug/split-plan.md'"

  # Cleanup
  rm -rf "$test_repo"
}

# NOTE: /impl standalone test removed — covered by test_autopilot_integration
# which exercises the full Generator→Evaluator→Audit pipeline more reliably.

# ============================================================
# Test: /autopilot full pipeline integration
# ============================================================

test_autopilot_integration() {
  echo "--- Integration: /autopilot (full pipeline) ---"
  echo "  WARNING: This test may take 10-30 minutes."

  local test_repo
  test_repo=$(mktemp -d)

  # Initialize git repo
  (
    cd "$test_repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    cat > .gitignore <<'EOF'
.docs/
.simple-wf-knowledge/
EOF
    git add .gitignore
    git commit -q -m "initial"
  )

  # Create brief fixture (uses setup_integration_brief)
  (cd "$test_repo" && setup_integration_brief "$test_repo") > /dev/null

  echo "  Test repo: $test_repo"
  echo "  Running: claude -p \"/autopilot test-slug\" ..."

  cd "$REPO_DIR"
  run_with_timeout 1800 claude -p \
    "Change to directory $test_repo and then run /autopilot test-slug" \
    --add-dir "$test_repo" --permission-mode bypassPermissions --allowed-tools=all --max-turns 150
  cd "$SCRIPT_DIR"

  if [ "$TIMEOUT_EXIT_CODE" -eq 124 ]; then
    echo -e "  ${YELLOW}WARN${NC} claude -p timed out (1800s)"
  fi

  if echo "$TIMEOUT_OUTPUT" | grep -q "Unknown skill"; then
    echo -e "  ${YELLOW}SKIP${NC} /autopilot skill not available via claude -p"
    rm -rf "$test_repo"
    return 0
  fi

  # --- Verify ticket creation ---
  local done_dir="$test_repo/.backlog/done"
  local active_dir="$test_repo/.backlog/active"

  # Count completed tickets (in done/) + any still in active/
  local done_count=0
  local active_count=0
  [ -d "$done_dir" ] && done_count=$(find "$done_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  [ -d "$active_dir" ] && active_count=$(find "$active_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  local total_tickets=$((done_count + active_count))

  assert_true \
    "/autopilot: at least 2 ticket directories created" \
    "[ $total_tickets -ge 2 ]"

  assert_true \
    "/autopilot: at least 1 ticket moved to done/" \
    "[ $done_count -ge 1 ]"

  # --- Verify artifacts per completed ticket ---
  if [ -d "$done_dir" ]; then
    for ticket_path in "$done_dir"/*/; do
      [ -d "$ticket_path" ] || continue
      local tname
      tname=$(basename "$ticket_path")

      assert_true \
        "/autopilot: $tname has ticket.md" \
        "[ -f '$ticket_path/ticket.md' ]"

      assert_true \
        "/autopilot: $tname has investigation.md" \
        "[ -f '$ticket_path/investigation.md' ]"

      assert_true \
        "/autopilot: $tname has plan.md" \
        "[ -f '$ticket_path/plan.md' ]"

      assert_true \
        "/autopilot: $tname has eval-round-*.md" \
        "ls '$ticket_path'/eval-round-*.md >/dev/null 2>&1"
    done
  fi

  # --- Verify brief lifecycle ---
  assert_true \
    "/autopilot: brief moved to briefs/done/" \
    "[ -d '$test_repo/.backlog/briefs/done/test-slug' ]"

  assert_true \
    "/autopilot: autopilot-log.md exists in briefs/done/" \
    "[ -f '$test_repo/.backlog/briefs/done/test-slug/autopilot-log.md' ]"

  # --- Verify individual autopilot-log per ticket (split mode requirement) ---
  if [ -d "$done_dir" ]; then
    for ticket_path in "$done_dir"/*/; do
      [ -d "$ticket_path" ] || continue
      local tname
      tname=$(basename "$ticket_path")

      assert_true \
        "/autopilot: $tname has individual autopilot-log.md" \
        "[ -f '$ticket_path/autopilot-log.md' ]"
    done
  fi

  # --- Verify autopilot-state.yaml cleaned up ---
  assert_false \
    "/autopilot: autopilot-state.yaml cleaned up from briefs/" \
    "find '$test_repo/.backlog/briefs' -name 'autopilot-state.yaml' 2>/dev/null | grep -q ."

  # Cleanup
  rm -rf "$test_repo"
}

# ============================================================
# Run all integration tests
# ============================================================

echo "=== Integration Tests (claude -p) ==="
echo ""

test_brief_fixture
echo ""
test_ship_integration
echo ""
test_audit_integration
echo ""
test_autopilot_integration
echo ""

print_summary
