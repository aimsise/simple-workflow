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
  local at="${3:-}"   # optional agent_type (FIX-2/FIX-3): merged ONLY when non-empty
  local payload
  payload=$(jq -n \
    --arg cmd "$command" \
    --arg cwd "$cwd" \
    --arg at "$at" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd, session_id:"test", transcript_path:""}
       + (if $at=="" then {} else {agent_type:$at} end)')

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
  local at="${4:-}"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_guard "$command" "$cwd" "$at"
  if [ "$LAST_EXIT_CODE" -eq 0 ] && ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
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
  local at="${5:-}"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_guard "$command" "$cwd" "$at"
  local blocked="false"
  if [ "$LAST_EXIT_CODE" -ne 0 ]; then
    blocked="true"
  elif grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
    blocked="true"
  fi
  local tag_ok="true"
  if [ -n "$expected_tag" ]; then
    if ! grep -q -- "$expected_tag" <<<"$LAST_STDOUT"; then
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
# Scenario (b): inside autopilot, /ship nonce present -> commit allowed.
# FIX-2 (v9.0.1): the authorization signal is a `.ship-commit-nonce` file
# (written by /ship step 2.5 BEFORE the Step-3 commit), not the forgeable
# `phases.ship.status: in-progress` proxy.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (b): inside autopilot, .ship-commit-nonce present, git commit allowed ---"
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
# /ship step 2.5 nonce sink (ticket-dir scope).
: > "$TMP_B/.simple-workflow/backlog/active/$SLUG_B/$TICKET_B/.ship-commit-nonce"
assert_guard_allow \
  "(b) inside autopilot tree, .ship-commit-nonce present, git commit allowed" \
  "git commit -m 'release(vX.Y.Z): feature'" \
  "$TMP_B"

# ---------------------------------------------------------------------------
# Scenario (c): inside autopilot, no nonce -> commit blocked.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (c): inside autopilot, no .ship-commit-nonce, git commit blocked ---"
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
# No .ship-commit-nonce written -> the Step-3 commit is unauthorized.
assert_guard_block \
  "(c) inside autopilot tree, no .ship-commit-nonce, git commit blocked" \
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
if grep -q -- '"decision":"block"' <<<"$LAST_STDOUT" \
   && grep -q -- 'unauthorized_state_mutate_bash' <<<"$LAST_STDOUT" \
   && grep -q -- 'docs/state-schema.md' <<<"$LAST_STDOUT"; then
  echo -e "  ${GREEN}PASS${NC} (f1) knob=on: Bash status mutation blocked (unauthorized_state_mutate_bash + docs/state-schema.md ref)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (f1) knob=on: expected decision:block. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# (f2) metric-only (the shipped default) -> NOT blocked; stderr logs would-deny.
run_guard_mode metric-only "$CMD_F_MUTATE" "$TMP_F"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT" \
   && grep -q -- 'metric-only: would deny unauthorized_state_mutate_bash' <<<"$LAST_STDERR"; then
  echo -e "  ${GREEN}PASS${NC} (f2) metric-only (default): not blocked, logs would-deny to stderr"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (f2) metric-only: expected allow + stderr would-deny. stdout: $LAST_STDOUT stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# (f3) knob=on + legitimate read-only command on a state file -> allowed (no mutation).
run_guard_mode on "grep skipped autopilot-state.yaml" "$TMP_F"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
  echo -e "  ${GREEN}PASS${NC} (f3) knob=on: read-only 'grep skipped' on state file allowed (no mutation)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (f3) knob=on: read-only command should be allowed. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# FIX-2 (v9.0.1) scenarios: review-agent git firewall + nonce gate + carve-out.
# These share the run_guard agent_type 5th argument (assert_guard_*) so the
# orchestrator-allow path depends on agent_type being ABSENT.
# ---------------------------------------------------------------------------
echo ""
echo "--- FIX-2: review-agent git firewall (SW_REVIEW_FIREWALL_MODE) ---"
TMP_FW="$(mktemp -d)"; register_cleanup "$TMP_FW"
SLUG_FW="firewall-slug"
TICKET_FW="001-fw-feature"
mkdir -p \
  "$TMP_FW/.simple-workflow/backlog/briefs/active/$SLUG_FW" \
  "$TMP_FW/.simple-workflow/backlog/active/$SLUG_FW/$TICKET_FW"
write_autopilot_state \
  "$TMP_FW/.simple-workflow/backlog/briefs/active/$SLUG_FW/autopilot-state.yaml" \
  "$SLUG_FW"
# A nonce IS present so the unconditional Detection 2 (A) nonce gate does NOT
# fire -- this isolates the NEW review-deny (B) under test.
: > "$TMP_FW/.simple-workflow/backlog/active/$SLUG_FW/$TICKET_FW/.ship-commit-nonce"

# run_guard variant that sets SW_REVIEW_FIREWALL_MODE for the hook process.
run_guard_fw() {
  local mode="$1" command="$2" cwd="$3" at="$4" payload so se
  payload=$(jq -n --arg cmd "$command" --arg cwd "$cwd" --arg at "$at" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd, session_id:"test", transcript_path:""}
       + (if $at=="" then {} else {agent_type:$at} end)')
  so=$(mktemp); se=$(mktemp)
  set +e
  printf '%s' "$payload" | env SW_REVIEW_FIREWALL_MODE="$mode" bash "$HOOK_PATH" >"$so" 2>"$se"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$so"); LAST_STDERR=$(cat "$se"); rm -f "$so" "$se"
}

# CT-FIX2-REVIEW-AGENT-COMMIT-DENIED (bare agent_type).
run_guard_fw on "git commit -m 'review tries to commit'" "$TMP_FW" "doc-verifier"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -q -- '"decision":"block"' <<<"$LAST_STDOUT" \
   && grep -q -- 'unauthorized_commit_by_review_agent' <<<"$LAST_STDOUT"; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX2-REVIEW-AGENT-COMMIT-DENIED (bare doc-verifier, on): git commit blocked"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX2-REVIEW-AGENT-COMMIT-DENIED (bare): expected block. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-FIX2-REVIEW-AGENT-COMMIT-DENIED (namespaced agent_type -> identical block).
run_guard_fw on "git add ." "$TMP_FW" "simple-workflow:doc-verifier"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -q -- '"decision":"block"' <<<"$LAST_STDOUT" \
   && grep -q -- 'unauthorized_commit_by_review_agent' <<<"$LAST_STDOUT"; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX2-REVIEW-AGENT-COMMIT-DENIED (namespaced simple-workflow:doc-verifier, on): git add blocked"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX2-REVIEW-AGENT-COMMIT-DENIED (namespaced): expected block. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# metric-only -> fail-open (no block), stderr logs would-deny.
run_guard_fw metric-only "git commit -m x" "$TMP_FW" "doc-verifier"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT" \
   && grep -q -- 'metric-only: would deny unauthorized_commit_by_review_agent' <<<"$LAST_STDERR"; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX2-REVIEW-AGENT-COMMIT (metric-only): fail-open + stderr would-deny"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX2-REVIEW-AGENT-COMMIT (metric-only): expected allow+stderr. stdout: $LAST_STDOUT stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# off -> fully disabled (no block, no stderr deny line).
run_guard_fw off "git push origin HEAD" "$TMP_FW" "code-reviewer"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX2-REVIEW-AGENT-COMMIT (off): disabled, no block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX2-REVIEW-AGENT-COMMIT (off): expected allow. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-FIX2-GIT-WORKTREE-EXEMPT: a review agent's `git worktree add` is NOT blocked.
run_guard_fw on "git worktree add ../scratch HEAD" "$TMP_FW" "ac-evaluator"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX2-GIT-WORKTREE-EXEMPT (ac-evaluator git worktree add, on): not blocked (carve-out)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX2-GIT-WORKTREE-EXEMPT: git worktree must be exempt. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Orchestrator-allow: ABSENT agent_type + git commit + nonce present -> allowed.
run_guard_fw on "git commit -m 'orchestrator'" "$TMP_FW" ""
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX2-ORCH-ALLOWED (empty agent_type + nonce present): git commit allowed"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX2-ORCH-ALLOWED: empty agent_type must fail-open. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# CT-FIX2-NONCE-ORDERING: with a nonce present the commit ALLOWs (default env,
# no SW_REVIEW_FIREWALL_MODE override); without it the commit BLOCKs. This locks
# the unconditional Detection 2 (A) nonce gate (NOT gated by the firewall knob).
# ---------------------------------------------------------------------------
echo ""
echo "--- CT-FIX2-NONCE-ORDERING: nonce present -> allow, absent -> block (default env) ---"
TMP_NO="$(mktemp -d)"; register_cleanup "$TMP_NO"
SLUG_NO="nonce-slug"; TICKET_NO="001-nonce"
mkdir -p \
  "$TMP_NO/.simple-workflow/backlog/briefs/active/$SLUG_NO" \
  "$TMP_NO/.simple-workflow/backlog/active/$SLUG_NO/$TICKET_NO"
write_autopilot_state \
  "$TMP_NO/.simple-workflow/backlog/briefs/active/$SLUG_NO/autopilot-state.yaml" \
  "$SLUG_NO"
# Absent nonce -> block (unconditional, default env).
assert_guard_block \
  "CT-FIX2-NONCE-ORDERING (no nonce, default env): git commit blocked" \
  "git commit -m 'before nonce'" \
  "$TMP_NO" \
  "unauthorized_ship_inline"
# Now write the nonce (the /ship step-2.5 sink ran before the commit) -> allow.
: > "$TMP_NO/.simple-workflow/backlog/active/$SLUG_NO/$TICKET_NO/.ship-commit-nonce"
assert_guard_allow \
  "CT-FIX2-NONCE-ORDERING (nonce written before commit, default env): git commit allowed" \
  "git commit -m 'after nonce'" \
  "$TMP_NO"

# ---------------------------------------------------------------------------
# CT-FIX2-NONCE-COLOCATED (dogfood63 hardening): the nonce gate tolerates a
# co-located nonce-write in the SAME command. /ship may chain
# `: > .../.ship-commit-nonce` with the Step-3 `git commit` via `&&`; PreToolUse
# inspects the command string BEFORE the `: >` runs, so the file is not yet on
# disk -- the gate scans $COMMAND for the queued active-tree nonce write and
# ALLOWs. A bare commit (no such co-located write) is still BLOCKed.
# ---------------------------------------------------------------------------
echo ""
echo "--- CT-FIX2-NONCE-COLOCATED: combined ': > nonce && git commit' allowed; bare commit blocked ---"
TMP_CO="$(mktemp -d)"; register_cleanup "$TMP_CO"
SLUG_CO="colocated-slug"; TICKET_CO="001-co"
mkdir -p \
  "$TMP_CO/.simple-workflow/backlog/briefs/active/$SLUG_CO" \
  "$TMP_CO/.simple-workflow/backlog/active/$SLUG_CO/$TICKET_CO"
write_autopilot_state \
  "$TMP_CO/.simple-workflow/backlog/briefs/active/$SLUG_CO/autopilot-state.yaml" \
  "$SLUG_CO"
# No nonce on disk -> a bare commit is still blocked (the co-located scan finds no nonce write).
assert_guard_block \
  "CT-FIX2-NONCE-COLOCATED (no nonce on disk, bare git commit): blocked" \
  "git commit -m 'bare'" \
  "$TMP_CO" \
  "unauthorized_ship_inline"
# Combined `: > nonce && git commit` in ONE command (nonce not yet on disk) -> allowed via the co-located scan.
assert_guard_allow \
  "CT-FIX2-NONCE-COLOCATED (co-located ': > nonce && git commit' in one command): allowed" \
  ": > .simple-workflow/backlog/active/$SLUG_CO/$TICKET_CO/.ship-commit-nonce && git commit -m 'combined'" \
  "$TMP_CO"

# ---------------------------------------------------------------------------
# CT-FIX2-NONCE-BASH-SINK: the nonce write/cleanup commands themselves
# (`: > ....ship-commit-nonce` and `rm -f ....ship-commit-nonce`) must NOT be
# blocked under any SW_REVIEW_FIREWALL_MODE value (the firewall never blocks
# its own authorization-sentinel write).
# ---------------------------------------------------------------------------
echo ""
echo "--- CT-FIX2-NONCE-BASH-SINK: nonce write/cleanup never blocked ---"
NONCE_REL=".simple-workflow/backlog/active/$SLUG_NO/$TICKET_NO/.ship-commit-nonce"
for _m in on metric-only off; do
  run_guard_fw "$_m" ": > $NONCE_REL" "$TMP_NO" ""
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
    echo -e "  ${GREEN}PASS${NC} CT-FIX2-NONCE-BASH-SINK (mode=$_m, write): not blocked"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} CT-FIX2-NONCE-BASH-SINK (mode=$_m, write): unexpected block. stdout: $LAST_STDOUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  run_guard_fw "$_m" "rm -f $NONCE_REL" "$TMP_NO" ""
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
    echo -e "  ${GREEN}PASS${NC} CT-FIX2-NONCE-BASH-SINK (mode=$_m, cleanup): not blocked"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} CT-FIX2-NONCE-BASH-SINK (mode=$_m, cleanup): unexpected block. stdout: $LAST_STDOUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# ---------------------------------------------------------------------------
# CT-FIX3-BASHMIRROR: the Detection 3 advancement-set extension catches a
# `current_phase: ship` Bash mutation (yq -i), while a read-only `grep ship`
# is NOT flagged (no _sg_mutation). SW_BASH_STATE_GUARD_MODE=on isolates the
# block.
# ---------------------------------------------------------------------------
echo ""
echo "--- CT-FIX3-BASHMIRROR: current_phase:ship mutation detected, read-only grep not ---"
TMP_BM="$(mktemp -d)"; register_cleanup "$TMP_BM"
SLUG_BM="bashmirror-slug"
mkdir -p "$TMP_BM/.simple-workflow/backlog/briefs/active/$SLUG_BM"
write_autopilot_state \
  "$TMP_BM/.simple-workflow/backlog/briefs/active/$SLUG_BM/autopilot-state.yaml" \
  "$SLUG_BM"
# (1) yq -i current_phase=ship on phase-state.yaml -> blocked under knob=on.
run_guard_mode on 'yq -i ".current_phase = \"ship\"" phase-state.yaml' "$TMP_BM"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -q -- '"decision":"block"' <<<"$LAST_STDOUT" \
   && grep -q -- 'unauthorized_state_mutate_bash' <<<"$LAST_STDOUT"; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX3-BASHMIRROR (yq -i current_phase=ship): blocked (advancement-set extension)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX3-BASHMIRROR: expected block on current_phase:ship. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
# (2) read-only grep ship on phase-state.yaml -> NOT blocked (no mutation).
run_guard_mode on "grep ship phase-state.yaml" "$TMP_BM"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! grep -q -- '"decision":"block"' <<<"$LAST_STDOUT"; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX3-BASHMIRROR (grep ship): read-only not blocked (no _sg_mutation)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX3-BASHMIRROR: read-only grep must be allowed. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_summary
