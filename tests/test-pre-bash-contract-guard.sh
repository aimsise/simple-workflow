#!/usr/bin/env bash
# test-pre-bash-contract-guard.sh -- exercises hooks/pre-bash-contract-guard.sh
# (PX-02a). The hook only activates when the caller sits inside an autopilot
# tree (a directory whose ancestor contains
# .simple-workflow/backlog/{briefs/active,product_backlog}/<slug>/autopilot-state.yaml),
# so each scenario builds the matching fixture under a tempdir and feeds the
# Claude Code harness payload via stdin.
#
# Scenarios (PX-02a Acceptance Criteria #4):
#   (a) outside autopilot   + git commit                   -> allow
#   (b) inside autopilot    + git commit + ship in-progress -> allow
#   (c) inside autopilot    + git commit + ship pending     -> block
#   (d) inside autopilot    + manual_bash_fallbacks append
#       with reason "Context budget"                         -> block
#   (e) inside autopilot    + manual_bash_fallbacks append
#       with reason "subagent could not handle"              -> allow

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_DIR/hooks/pre-bash-contract-guard.sh"

echo "=== pre-bash-contract-guard.sh Tests ==="
echo ""

# Each scenario gets its own tempdir so we can compose distinct
# .simple-workflow/ trees and trap them all on EXIT.
declare -a CLEANUP_DIRS=()
register_cleanup() {
  CLEANUP_DIRS+=("$1")
}
cleanup_all() {
  for d in "${CLEANUP_DIRS[@]+"${CLEANUP_DIRS[@]}"}"; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup_all EXIT

# Drive the hook with a synthetic harness payload and capture exit code,
# stdout, and stderr. The hook returns 0 in both allow and block paths;
# the block signal is the presence of `"decision":"block"` in stdout.
run_guard() {
  local command="$1"
  local cwd="$2"
  local payload
  payload=$(jq -n \
    --arg cmd "$command" \
    --arg cwd "$cwd" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd, session_id:"test", transcript_path:""}')

  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)

  set +e
  printf '%s' "$payload" | bash "$HOOK_PATH" >"$stdout_file" 2>"$stderr_file"
  local exit_code=$?
  set -e

  LAST_EXIT_CODE=$exit_code
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

# Allow assertion: exit 0 AND stdout does not request a block.
assert_guard_allow() {
  local description="$1"
  local command="$2"
  local cwd="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_guard "$command" "$cwd"
  if [ "$LAST_EXIT_CODE" -eq 0 ] && ! printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"'; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       exit:   $LAST_EXIT_CODE"
    echo -e "       stdout: $LAST_STDOUT"
    echo -e "       stderr: $LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Block assertion: exit non-zero OR stdout contains a decision:block JSON
# object whose reason field carries the expected violation tag.
assert_guard_block() {
  local description="$1"
  local command="$2"
  local cwd="$3"
  local expected_tag="$4"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_guard "$command" "$cwd"
  local blocked="false"
  if [ "$LAST_EXIT_CODE" -ne 0 ]; then
    blocked="true"
  elif printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"'; then
    blocked="true"
  fi
  local tag_ok="true"
  if [ -n "$expected_tag" ]; then
    if ! printf '%s' "$LAST_STDOUT" | grep -q "$expected_tag"; then
      tag_ok="false"
    fi
  fi
  if [ "$blocked" = "true" ] && [ "$tag_ok" = "true" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    echo -e "       exit:        $LAST_EXIT_CODE"
    echo -e "       stdout:      $LAST_STDOUT"
    echo -e "       stderr:      $LAST_STDERR"
    echo -e "       expected tag: $expected_tag"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Helper: write a phase-state.yaml under the active ticket dir, recording
# the requested ship status. The file shape mirrors the canonical schema
# used by parse_phase_status (yq path: .phases.ship.status).
write_phase_state() {
  local target="$1"
  local ship_status="$2"
  cat >"$target" <<YAML
version: 1
phases:
  scout:
    status: completed
  impl:
    status: completed
  ship:
    status: ${ship_status}
YAML
}

# Helper: write a minimal autopilot-state.yaml under
# briefs/active/<slug>/. is_autopilot_context only checks for the file's
# existence so the body content is illustrative.
write_autopilot_state() {
  local target="$1"
  local slug="$2"
  cat >"$target" <<YAML
version: 1
parent_slug: ${slug}
execution_mode: split
total_tickets: 1
tickets:
  - logical_id: ${slug}-part-1
    status: in-progress
manual_bash_fallbacks: []
YAML
}

# ---------------------------------------------------------------------------
# Scenario (a): outside any autopilot tree -- the hook is a no-op.
# ---------------------------------------------------------------------------
echo "--- Scenario (a): outside autopilot context, git commit allowed ---"
TMP_A="$(mktemp -d)"
register_cleanup "$TMP_A"
# Note: NO .simple-workflow/ ancestor exists here.
assert_guard_allow \
  "(a) outside autopilot tree, git commit passes through" \
  "git commit -m 'unrelated'" \
  "$TMP_A"

# ---------------------------------------------------------------------------
# Scenario (b): inside autopilot, /ship Skill in progress -> commit allowed.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (b): inside autopilot, ship in-progress, git commit allowed ---"
TMP_B="$(mktemp -d)"
register_cleanup "$TMP_B"
SLUG_B="example-slug"
TICKET_B="001-impl-feature"
mkdir -p \
  "$TMP_B/.simple-workflow/backlog/briefs/active/$SLUG_B" \
  "$TMP_B/.simple-workflow/backlog/active/$SLUG_B/$TICKET_B"
write_autopilot_state \
  "$TMP_B/.simple-workflow/backlog/briefs/active/$SLUG_B/autopilot-state.yaml" \
  "$SLUG_B"
write_phase_state \
  "$TMP_B/.simple-workflow/backlog/active/$SLUG_B/$TICKET_B/phase-state.yaml" \
  "in-progress"
assert_guard_allow \
  "(b) inside autopilot tree, phases.ship.status=in-progress, git commit allowed" \
  "git commit -m 'release(vX.Y.Z): feature'" \
  "$TMP_B"

# ---------------------------------------------------------------------------
# Scenario (c): inside autopilot, ship pending -> commit blocked.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (c): inside autopilot, ship pending, git commit blocked ---"
TMP_C="$(mktemp -d)"
register_cleanup "$TMP_C"
SLUG_C="bypass-slug"
TICKET_C="001-bypass-feature"
mkdir -p \
  "$TMP_C/.simple-workflow/backlog/briefs/active/$SLUG_C" \
  "$TMP_C/.simple-workflow/backlog/active/$SLUG_C/$TICKET_C"
write_autopilot_state \
  "$TMP_C/.simple-workflow/backlog/briefs/active/$SLUG_C/autopilot-state.yaml" \
  "$SLUG_C"
write_phase_state \
  "$TMP_C/.simple-workflow/backlog/active/$SLUG_C/$TICKET_C/phase-state.yaml" \
  "pending"
assert_guard_block \
  "(c) inside autopilot tree, phases.ship.status!=in-progress, git commit blocked" \
  "git commit -m 'inline shortcut'" \
  "$TMP_C" \
  "unauthorized_ship_inline"

# ---------------------------------------------------------------------------
# Scenario (d): manual_bash_fallbacks[] append with forbidden rationale.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (d): manual_bash_fallbacks append with 'Context budget' blocked ---"
TMP_D="$(mktemp -d)"
register_cleanup "$TMP_D"
SLUG_D="rationale-slug"
mkdir -p "$TMP_D/.simple-workflow/backlog/briefs/active/$SLUG_D"
write_autopilot_state \
  "$TMP_D/.simple-workflow/backlog/briefs/active/$SLUG_D/autopilot-state.yaml" \
  "$SLUG_D"
# Synthetic command shape: a yq -i append targeting manual_bash_fallbacks
# with a reason text containing "Context budget".
CMD_D='yq -i ".manual_bash_fallbacks += [{\"timestamp\":\"2026-05-02T00:00:00Z\",\"command\":\"git commit\",\"reason\":\"Context budget exhausted, falling back\",\"exit_code\":0,\"destructive\":false}]" autopilot-state.yaml'
assert_guard_block \
  "(d) manual_bash_fallbacks append with 'Context budget' rationale blocked" \
  "$CMD_D" \
  "$TMP_D" \
  "context_budget_fallback"

# ---------------------------------------------------------------------------
# Scenario (e): manual_bash_fallbacks[] append with allowed rationale.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (e): manual_bash_fallbacks append with 'subagent could not handle' allowed ---"
TMP_E="$(mktemp -d)"
register_cleanup "$TMP_E"
SLUG_E="legit-slug"
mkdir -p "$TMP_E/.simple-workflow/backlog/briefs/active/$SLUG_E"
write_autopilot_state \
  "$TMP_E/.simple-workflow/backlog/briefs/active/$SLUG_E/autopilot-state.yaml" \
  "$SLUG_E"
CMD_E='yq -i ".manual_bash_fallbacks += [{\"timestamp\":\"2026-05-02T00:00:00Z\",\"command\":\"mv ticket dir\",\"reason\":\"subagent could not handle interactive prompt\",\"exit_code\":0,\"destructive\":false}]" autopilot-state.yaml'
assert_guard_allow \
  "(e) manual_bash_fallbacks append with 'subagent could not handle' rationale allowed" \
  "$CMD_E" \
  "$TMP_E"

# ---------------------------------------------------------------------------
# Scenario (f): Detection 3 (proposal 4 / ST-04) -- Bash-mediated state-file
# status mutation, gated by SW_BASH_STATE_GUARD_MODE (default metric-only).
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (f): Bash state-file status mutation (SW_BASH_STATE_GUARD_MODE) ---"
TMP_F="$(mktemp -d)"
register_cleanup "$TMP_F"
SLUG_F="state-mutate-slug"
mkdir -p "$TMP_F/.simple-workflow/backlog/briefs/active/$SLUG_F"
write_autopilot_state \
  "$TMP_F/.simple-workflow/backlog/briefs/active/$SLUG_F/autopilot-state.yaml" \
  "$SLUG_F"

# run_guard variant that sets SW_BASH_STATE_GUARD_MODE for the hook process.
run_guard_mode() {
  local mode="$1" command="$2" cwd="$3" payload so se
  payload=$(jq -n --arg cmd "$command" --arg cwd "$cwd" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd, session_id:"test", transcript_path:""}')
  so=$(mktemp); se=$(mktemp)
  set +e
  printf '%s' "$payload" | env SW_BASH_STATE_GUARD_MODE="$mode" bash "$HOOK_PATH" >"$so" 2>"$se"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$so"); LAST_STDERR=$(cat "$se"); rm -f "$so" "$se"
}

CMD_F_MUTATE='yq -i ".tickets[].status = \"skipped\"" autopilot-state.yaml'

# (f1) knob=on -> decision:block with unauthorized_state_mutate_bash + schema ref.
run_guard_mode on "$CMD_F_MUTATE" "$TMP_F"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"' \
   && printf '%s' "$LAST_STDOUT" | grep -q 'unauthorized_state_mutate_bash' \
   && printf '%s' "$LAST_STDOUT" | grep -q 'docs/state-schema.md'; then
  echo -e "  ${GREEN}PASS${NC} (f1) knob=on: Bash status mutation blocked (unauthorized_state_mutate_bash + docs/state-schema.md ref)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (f1) knob=on: expected decision:block. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# (f2) metric-only (the shipped default) -> NOT blocked; stderr logs would-deny.
run_guard_mode metric-only "$CMD_F_MUTATE" "$TMP_F"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"' \
   && printf '%s' "$LAST_STDERR" | grep -q 'metric-only: would deny unauthorized_state_mutate_bash'; then
  echo -e "  ${GREEN}PASS${NC} (f2) metric-only (default): not blocked, logs would-deny to stderr"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (f2) metric-only: expected allow + stderr would-deny. stdout: $LAST_STDOUT stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# (f3) knob=on + legitimate read-only command on a state file -> allowed (no mutation).
run_guard_mode on "grep skipped autopilot-state.yaml" "$TMP_F"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"'; then
  echo -e "  ${GREEN}PASS${NC} (f3) knob=on: read-only 'grep skipped' on state file allowed (no mutation)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (f3) knob=on: read-only command should be allowed. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_summary
