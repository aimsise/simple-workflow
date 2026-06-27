#!/usr/bin/env bash
# test-state-transition-guard.sh -- exercises hooks/pre-state-transition.sh
# (PX-04). The hook intercepts PreToolUse:Write/Edit calls targeting
# autopilot-state.yaml or phase-state.yaml inside an autopilot tree, and
# blocks unauthorized `status: skipped` transitions.
#
# Scenarios (PX-04 Acceptance Criteria #6):
#   (a) all siblings completed, skipped without override         -> ALLOW
#       Resume-mode normal: a write that re-emits every ticket as
#       completed except one explicit skip is the canonical resume
#       behaviour and must not trip the guard.
#   (b) one sibling pending, skipped without override            -> BLOCK
#       (unauthorized_skip_with_active_siblings)
#   (c) one sibling pending, override_skip: true at ticket level,
#       non-forbidden skip_reason                                -> ALLOW
#   (d) pending -> completed normal transition                   -> ALLOW
#       (skip guard inapplicable)
#   (e) override_skip: true placed at irrelevant location
#       (top-level / comment) without an in-ticket override      -> BLOCK
#   (f) one sibling pending, override_skip: true at ticket level,
#       skip_reason matches forbidden pattern                    -> BLOCK
#       (unauthorized_skip_with_forbidden_rationale)
#
# Each scenario builds a self-contained tempdir holding the minimum
# `.simple-workflow/` skeleton needed for is_autopilot_context() to
# return true (a stub autopilot-state.yaml under
# briefs/active/<slug>/), then drives the hook with a Claude Code-shaped
# Write payload via stdin.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_DIR/hooks/pre-state-transition.sh"

echo "=== pre-state-transition.sh Tests ==="
echo ""

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
  local file_path="$1"
  local content="$2"
  local cwd="$3"
  local tool_name="${4:-Write}"
  local at="${5:-}"   # optional agent_type (FIX-3): merged ONLY when non-empty

  local payload
  if [ "$tool_name" = "Edit" ]; then
    payload=$(jq -n \
      --arg fp "$file_path" \
      --arg ns "$content" \
      --arg cwd "$cwd" \
      --arg at "$at" \
      '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"", new_string:$ns}, cwd:$cwd, session_id:"test", transcript_path:""}
         + (if $at=="" then {} else {agent_type:$at} end)')
  else
    payload=$(jq -n \
      --arg fp "$file_path" \
      --arg c "$content" \
      --arg cwd "$cwd" \
      --arg at "$at" \
      '{tool_name:"Write", tool_input:{file_path:$fp, content:$c}, cwd:$cwd, session_id:"test", transcript_path:""}
         + (if $at=="" then {} else {agent_type:$at} end)')
  fi

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
  local description="$1"; shift
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_guard "$@"
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

# Block assertion: stdout contains a decision:block JSON object whose
# reason field carries the expected violation tag.
assert_guard_block() {
  local description="$1"
  local expected_tag="$2"
  shift 2
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_guard "$@"
  local blocked="false"
  if printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"'; then
    blocked="true"
  fi
  local tag_ok="true"
  if [ -n "$expected_tag" ]; then
    if ! printf '%s' "$LAST_STDOUT" | grep -q "$expected_tag"; then
      tag_ok="false"
    fi
  fi
  if [ "$blocked" = "true" ] && [ "$tag_ok" = "true" ] && [ "$LAST_EXIT_CODE" -eq 0 ]; then
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

# Helper: build a tempdir with a minimal autopilot tree. Initial state
# has every ticket marked `pending` so the disk-fallback sibling lookup
# would always say "active siblings exist" -- which means the proposal
# itself must be the source of truth for full snapshots, while partial
# (single-ticket) writes inherit the disk siblings.
prepare_autopilot_tree() {
  local tmp="$1"
  local slug="$2"
  local n="${3:-2}"  # number of tickets in the on-disk file
  mkdir -p "$tmp/.simple-workflow/backlog/briefs/active/$slug"
  local state_file="$tmp/.simple-workflow/backlog/briefs/active/$slug/autopilot-state.yaml"
  {
    printf 'version: 1\n'
    printf 'parent_slug: %s\n' "$slug"
    printf 'execution_mode: split\n'
    printf 'total_tickets: %d\n' "$n"
    printf 'tickets:\n'
    local i
    for ((i = 1; i <= n; i++)); do
      printf '  - logical_id: %s-part-%d\n' "$slug" "$i"
      printf '    status: pending\n'
    done
  } >"$state_file"
  printf '%s\n' "$state_file"
}

# ---------------------------------------------------------------------------
# Scenario (a): all siblings completed in proposal -> allow even without
# an `override_skip` flag (this is the canonical resume_mode pattern: a
# completed run re-emits every ticket as completed and the last one as
# skipped because the user signalled "drop this ticket from the run").
# ---------------------------------------------------------------------------
echo "--- Scenario (a): all siblings completed, skip without override -> allow ---"
TMP_A="$(mktemp -d)"; register_cleanup "$TMP_A"
SLUG_A="resume-slug"
STATE_A="$(prepare_autopilot_tree "$TMP_A" "$SLUG_A" 2)"
# Mutate the on-disk file so part-1 is already completed (the resume
# precondition described in [RESUME] Skipping {logical_id}: already
# completed). The proposal then re-emits part-1 as completed and marks
# part-2 as skipped without an override.
cat >"$STATE_A" <<YAML
version: 1
parent_slug: ${SLUG_A}
execution_mode: split
total_tickets: 2
tickets:
  - logical_id: ${SLUG_A}-part-1
    status: completed
  - logical_id: ${SLUG_A}-part-2
    status: completed
YAML
CONTENT_A="version: 1
parent_slug: ${SLUG_A}
execution_mode: split
total_tickets: 2
tickets:
  - logical_id: ${SLUG_A}-part-1
    status: completed
  - logical_id: ${SLUG_A}-part-2
    status: skipped
    skip_reason: prerequisite invalidated by external change
"
assert_guard_allow \
  "(a) resume_mode: every sibling completed, skip without override allowed" \
  "$STATE_A" "$CONTENT_A" "$TMP_A"
# NAC #2 reinforcement: the same content string carries the [RESUME]-style
# narrative shape (status: completed for siblings) so the resume pathway
# is exercised explicitly by this fixture.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if printf '%s' "$CONTENT_A" | grep -qE 'status:[[:space:]]*completed' \
   && printf '%s' "$CONTENT_A" | grep -qE 'status:[[:space:]]*skipped'; then
  echo -e "  ${GREEN}PASS${NC} (a/NAC#2) resume-mode shape preserved (completed siblings + lone skip)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (a/NAC#2) resume-mode shape missing"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Scenario (b): pending sibling + skip without override -> block.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (b): one sibling pending + skip without override -> block ---"
TMP_B="$(mktemp -d)"; register_cleanup "$TMP_B"
SLUG_B="active-slug"
STATE_B="$(prepare_autopilot_tree "$TMP_B" "$SLUG_B" 2)"
CONTENT_B="version: 1
parent_slug: ${SLUG_B}
tickets:
  - logical_id: ${SLUG_B}-part-1
    status: pending
  - logical_id: ${SLUG_B}-part-2
    status: skipped
    skip_reason: deferred-to-resume context budget exhausted
"
assert_guard_block \
  "(b) pending sibling + skip without override blocked" \
  "unauthorized_skip_with_active_siblings" \
  "$STATE_B" "$CONTENT_B" "$TMP_B"

# ---------------------------------------------------------------------------
# Scenario (c): pending sibling + override at ticket level + non-forbidden
# rationale -> allow.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (c): pending sibling + override + non-forbidden reason -> allow ---"
TMP_C="$(mktemp -d)"; register_cleanup "$TMP_C"
SLUG_C="override-slug"
STATE_C="$(prepare_autopilot_tree "$TMP_C" "$SLUG_C" 2)"
CONTENT_C="version: 1
parent_slug: ${SLUG_C}
tickets:
  - logical_id: ${SLUG_C}-part-1
    status: pending
  - logical_id: ${SLUG_C}-part-2
    status: skipped
    override_skip: true
    skip_reason: prerequisite invalidated by external change
"
assert_guard_allow \
  "(c) pending sibling + ticket-level override + non-forbidden reason allowed" \
  "$STATE_C" "$CONTENT_C" "$TMP_C"

# ---------------------------------------------------------------------------
# Scenario (d): normal pending -> completed transition. The guard MUST
# remain a no-op for every state-file write that does not introduce any
# `status: skipped` transition.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (d): pending -> completed normal transition -> allow ---"
TMP_D="$(mktemp -d)"; register_cleanup "$TMP_D"
SLUG_D="normal-slug"
STATE_D="$(prepare_autopilot_tree "$TMP_D" "$SLUG_D" 2)"
CONTENT_D="version: 1
parent_slug: ${SLUG_D}
tickets:
  - logical_id: ${SLUG_D}-part-1
    status: completed
  - logical_id: ${SLUG_D}-part-2
    status: in_progress
"
assert_guard_allow \
  "(d) pending->completed/in_progress normal transition allowed" \
  "$STATE_D" "$CONTENT_D" "$TMP_D"

# ---------------------------------------------------------------------------
# Scenario (e) / fixture (e): override_skip placed at irrelevant location
# (top-level) does NOT validate the skip transition. This fixture exercises
# Rule 1 (`unauthorized_skip_with_active_siblings`) — a pending sibling is
# present and the lone skipped ticket has no dep-cascade marker, so Rule 1
# fires before the structural override check (Rule 2) is even reached.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (e): top-level override_skip without ticket override -> block ---"
TMP_E="$(mktemp -d)"; register_cleanup "$TMP_E"
SLUG_E="misplaced-slug"
STATE_E="$(prepare_autopilot_tree "$TMP_E" "$SLUG_E" 2)"
CONTENT_E="version: 1
parent_slug: ${SLUG_E}
override_skip: true
tickets:
  - logical_id: ${SLUG_E}-part-1
    status: pending
  - logical_id: ${SLUG_E}-part-2
    status: skipped
    skip_reason: prerequisite invalidated by external change
"
# fixture (e) expectation: Rule 1's tag, narrowed from the prior substring
# match so a regression in Rule 2 cannot mask itself behind Rule 1.
assert_guard_block \
  "(e) override_skip at top-level (not at ticket level) does not authorize skip; blocked" \
  "unauthorized_skip_with_active_siblings" \
  "$STATE_E" "$CONTENT_E" "$TMP_E"

# Comment-form override_skip: also rejected.
TMP_E2="$(mktemp -d)"; register_cleanup "$TMP_E2"
SLUG_E2="commented-slug"
STATE_E2="$(prepare_autopilot_tree "$TMP_E2" "$SLUG_E2" 2)"
CONTENT_E2="version: 1
parent_slug: ${SLUG_E2}
# override_skip: true   (planted in a comment, must not count)
tickets:
  - logical_id: ${SLUG_E2}-part-1
    status: pending
  - logical_id: ${SLUG_E2}-part-2
    status: skipped
    skip_reason: prerequisite invalidated by external change
"
assert_guard_block \
  "(e2) commented override_skip line does not authorize skip; blocked" \
  "unauthorized_skip_with_active_siblings" \
  "$STATE_E2" "$CONTENT_E2" "$TMP_E2"

# ---------------------------------------------------------------------------
# Scenario (e3) / fixture (e3): structural override placement check
# (Rule 2) reached only when Rule 1 does NOT fire. To bypass Rule 1,
# every plain-skipped ticket must carry a `dependency_failed` cascade
# marker; then a misplaced top-level `override_skip: true` becomes the
# sole structural defect, and the hook must emit the distinct
# `malformed_override_placement` tag (not Rule 1's
# `unauthorized_skip_with_active_siblings`).
#
# Fixture (e3) covers Rule 2's structural override placement check,
# distinct from fixture (e) which trips Rule 1's active-sibling rule.
# Fixture (e) exercises Rule 1 (active sibling without dep-cascade),
# whereas fixture (e3) exercises Rule 2 (every skip has a dep-cascade
# exemption, but a misplaced top-level override_skip is still present).
# The two trip different rules and emit different tags.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (e3): top-level override + dep-cascade siblings -> Rule 2 block ---"
TMP_E3="$(mktemp -d)"; register_cleanup "$TMP_E3"
SLUG_E3="malformed-override-slug"
STATE_E3="$(prepare_autopilot_tree "$TMP_E3" "$SLUG_E3" 3)"
# Mutate disk state so a sibling is in_progress (active sibling on disk),
# forcing the hook past the no-active-sibling early exit and into the
# structural-placement check after the dep-cascade filter clears Rule 1.
cat >"$STATE_E3" <<YAML
version: 1
parent_slug: ${SLUG_E3}
execution_mode: split
total_tickets: 3
tickets:
  - logical_id: ${SLUG_E3}-part-1
    status: in_progress
  - logical_id: ${SLUG_E3}-part-2
    status: pending
  - logical_id: ${SLUG_E3}-part-3
    status: pending
YAML
# fixture (e3) Proposal: every skipped ticket carries `dependency_failed`
# (so Rule 1's `remaining_plain` count stays at 0), but a top-level
# `override_skip: true` is planted at column 0 -- structural defect that
# Rule 2 must catch and tag as `malformed_override_placement`.
CONTENT_E3="version: 1
parent_slug: ${SLUG_E3}
override_skip: true
tickets:
  - logical_id: ${SLUG_E3}-part-2
    status: skipped
    skip_reason: dependency_failed
  - logical_id: ${SLUG_E3}-part-3
    status: skipped
    skip_reason: dependency_failed
"
assert_guard_block \
  "(e3) all-dep-cascade skips with misplaced top-level override blocked as malformed_override_placement" \
  "malformed_override_placement" \
  "$STATE_E3" "$CONTENT_E3" "$TMP_E3"

# ---------------------------------------------------------------------------
# Scenario (f): override at correct level + forbidden rationale -> block.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario (f): override + forbidden rationale -> block ---"
TMP_F="$(mktemp -d)"; register_cleanup "$TMP_F"
SLUG_F="forbidden-slug"
STATE_F="$(prepare_autopilot_tree "$TMP_F" "$SLUG_F" 2)"
CONTENT_F="version: 1
parent_slug: ${SLUG_F}
tickets:
  - logical_id: ${SLUG_F}-part-1
    status: pending
  - logical_id: ${SLUG_F}-part-2
    status: skipped
    override_skip: true
    skip_reason: Context budget exhausted, falling back to skip
"
assert_guard_block \
  "(f) override + 'Context budget' rationale blocked as forbidden_rationale" \
  "unauthorized_skip_with_forbidden_rationale" \
  "$STATE_F" "$CONTENT_F" "$TMP_F"

# Bonus (f2): release valve rationale (different forbidden pattern) under
# override -- still blocked.
TMP_F2="$(mktemp -d)"; register_cleanup "$TMP_F2"
SLUG_F2="release-valve-slug"
STATE_F2="$(prepare_autopilot_tree "$TMP_F2" "$SLUG_F2" 2)"
CONTENT_F2="version: 1
parent_slug: ${SLUG_F2}
tickets:
  - logical_id: ${SLUG_F2}-part-1
    status: pending
  - logical_id: ${SLUG_F2}-part-2
    status: skipped
    override_skip: true
    skip_reason: release valve engaged to free context window
"
assert_guard_block \
  "(f2) override + 'release valve' rationale blocked as forbidden_rationale" \
  "unauthorized_skip_with_forbidden_rationale" \
  "$STATE_F2" "$CONTENT_F2" "$TMP_F2"

# ---------------------------------------------------------------------------
# Out-of-scope checks: target file basename is NOT autopilot-state.yaml
# / phase-state.yaml -> always pass through silently. NAC #1.
# ---------------------------------------------------------------------------
echo ""
echo "--- Out-of-scope target -> always allow ---"
TMP_X="$(mktemp -d)"; register_cleanup "$TMP_X"
SLUG_X="oob-slug"
prepare_autopilot_tree "$TMP_X" "$SLUG_X" 2 >/dev/null
assert_guard_allow \
  "(x) Write to README.md inside an autopilot tree is silently allowed" \
  "$TMP_X/README.md" \
  "anything goes here, status: skipped is harmless prose" \
  "$TMP_X"

# ---------------------------------------------------------------------------
# Outside autopilot context -> always allow. NAC #1.
# ---------------------------------------------------------------------------
echo ""
echo "--- Outside autopilot tree -> always allow ---"
TMP_O="$(mktemp -d)"; register_cleanup "$TMP_O"
# No .simple-workflow/ ancestor exists.
mkdir -p "$TMP_O/somedir"
assert_guard_allow \
  "(o) Write to autopilot-state.yaml outside any autopilot tree allowed" \
  "$TMP_O/somedir/autopilot-state.yaml" \
  "tickets:
  - logical_id: anything-part-1
    status: skipped
    skip_reason: even forbidden 'Context budget' rationale is allowed off-context
" \
  "$TMP_O"

# ---------------------------------------------------------------------------
# Edit (PreToolUse:Edit) form: same payload but delivered via .new_string.
# Repeats scenario (b) to confirm the Edit branch is wired correctly.
# ---------------------------------------------------------------------------
echo ""
echo "--- Edit branch coverage (scenario b via Edit) ---"
TMP_BE="$(mktemp -d)"; register_cleanup "$TMP_BE"
SLUG_BE="edit-slug"
STATE_BE="$(prepare_autopilot_tree "$TMP_BE" "$SLUG_BE" 2)"
CONTENT_BE="version: 1
parent_slug: ${SLUG_BE}
tickets:
  - logical_id: ${SLUG_BE}-part-1
    status: pending
  - logical_id: ${SLUG_BE}-part-2
    status: skipped
    skip_reason: deferred-to-resume context budget exhausted
"
assert_guard_block \
  "(b/Edit) Edit-shaped payload with same skip violation also blocks" \
  "unauthorized_skip_with_active_siblings" \
  "$STATE_BE" "$CONTENT_BE" "$TMP_BE" "Edit"

# ---------------------------------------------------------------------------
# NAC #5: pending-state initial write (every ticket pending, no skip)
# must NOT trip the guard.
# ---------------------------------------------------------------------------
echo ""
echo "--- NAC #5: initial all-pending write -> allow ---"
TMP_P="$(mktemp -d)"; register_cleanup "$TMP_P"
SLUG_P="initial-slug"
mkdir -p "$TMP_P/.simple-workflow/backlog/briefs/active/$SLUG_P"
INIT_FILE="$TMP_P/.simple-workflow/backlog/briefs/active/$SLUG_P/autopilot-state.yaml"
# Seed an existing autopilot-state.yaml so is_autopilot_context() returns
# true even though the proposal is the very first multi-ticket snapshot.
cat >"$INIT_FILE" <<YAML
version: 1
parent_slug: ${SLUG_P}
tickets: []
YAML
INIT_CONTENT="version: 1
parent_slug: ${SLUG_P}
tickets:
  - logical_id: ${SLUG_P}-part-1
    status: pending
  - logical_id: ${SLUG_P}-part-2
    status: pending
  - logical_id: ${SLUG_P}-part-3
    status: pending
"
assert_guard_allow \
  "(NAC#5) initial all-pending snapshot allowed (no skip in proposal)" \
  "$INIT_FILE" "$INIT_CONTENT" "$TMP_P"

# ---------------------------------------------------------------------------
# Dependency-cascade exception: skip_reason contains dependency_failed /
# dependency_skipped -> allow even with active siblings (NAC #4).
# ---------------------------------------------------------------------------
echo ""
echo "--- NAC #4: dependency-cascade skip allowed ---"
TMP_DC="$(mktemp -d)"; register_cleanup "$TMP_DC"
SLUG_DC="depcascade-slug"
STATE_DC="$(prepare_autopilot_tree "$TMP_DC" "$SLUG_DC" 3)"
CONTENT_DC="version: 1
parent_slug: ${SLUG_DC}
tickets:
  - logical_id: ${SLUG_DC}-part-1
    status: pending
  - logical_id: ${SLUG_DC}-part-2
    status: failed
  - logical_id: ${SLUG_DC}-part-3
    status: skipped
    skip_reason: dependency_failed
"
assert_guard_allow \
  "(NAC#4) dependency_failed cascade skip allowed even with pending sibling" \
  "$STATE_DC" "$CONTENT_DC" "$TMP_DC"

# ---------------------------------------------------------------------------
# NAC #8 / static checks: hook source has no env-var escape-hatch tokens.
# The check looks for upper-case identifiers shaped like SKIP_X / BYPASS_X
# / FORCE_X used in a $VAR / ${VAR} expansion, which is the canonical
# Bash env-var bypass shape. Lower-case feature names like `skip_reason`
# and tag literals like `unauthorized_skip_with_forbidden_rationale`
# are intentionally out of scope -- they are domain vocabulary, not
# escape hatches.
# ---------------------------------------------------------------------------
echo ""
echo "--- NAC #8: no env-var bypass tokens in hook source ---"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if grep -qE '\$\{?(SKIP|BYPASS|FORCE)_[A-Z_]+' "$HOOK_PATH"; then
  echo -e "  ${RED}FAIL${NC} (NAC#8) hook contains an env-var escape-hatch (\$SKIP_*/\$BYPASS_*/\$FORCE_*)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo -e "  ${GREEN}PASS${NC} (NAC#8) hook source has no \$SKIP_*/\$BYPASS_*/\$FORCE_* env-var bypass"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# ---------------------------------------------------------------------------
# FIX-3 (v9.0.1): phase-advancement guard (PART A detection + PART B Detection 4).
# A run_guard variant that sets SW_STATE_ADVANCE_GUARD_MODE for the hook proc.
# ---------------------------------------------------------------------------
run_guard_adv() {
  local mode="$1" file_path="$2" content="$3" cwd="$4" at="$5" payload so se
  payload=$(jq -n --arg fp "$file_path" --arg c "$content" --arg cwd "$cwd" --arg at "$at" \
    '{tool_name:"Write", tool_input:{file_path:$fp, content:$c}, cwd:$cwd, session_id:"test", transcript_path:""}
       + (if $at=="" then {} else {agent_type:$at} end)')
  so=$(mktemp); se=$(mktemp)
  set +e
  printf '%s' "$payload" | env SW_STATE_ADVANCE_GUARD_MODE="$mode" bash "$HOOK_PATH" >"$so" 2>"$se"
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$so"); LAST_STDERR=$(cat "$se"); rm -f "$so" "$se"
}

echo ""
echo "--- FIX-3 PART A / PART B: phase-advancement guard ---"
TMP_ADV="$(mktemp -d)"; register_cleanup "$TMP_ADV"
SLUG_ADV="advance-slug"
# prepare the autopilot tree for the fixture (the returned state path is unused here).
prepare_autopilot_tree "$TMP_ADV" "$SLUG_ADV" 2 >/dev/null
PS_ADV="$TMP_ADV/.simple-workflow/backlog/active/$SLUG_ADV/001-feat/phase-state.yaml"
mkdir -p "$(dirname "$PS_ADV")"

# A phase-state.yaml advancement content (current_phase + overall_status + ship.status).
ADV_CONTENT="version: 1
current_phase: ship
overall_status: in-progress
phases:
  ship:
    status: completed
"

# CT-FIX3-REVIEW-AGENT-ADVANCE-DENIED (bare agent_type, on -> block).
run_guard_adv on "$PS_ADV" "$ADV_CONTENT" "$TMP_ADV" "ticket-evaluator"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"' \
   && printf '%s' "$LAST_STDOUT" | grep -q 'unauthorized_phase_advance_by_review_agent'; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX3-REVIEW-AGENT-ADVANCE-DENIED (bare ticket-evaluator, on): advancement blocked"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX3-REVIEW-AGENT-ADVANCE-DENIED (bare): expected block. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-FIX3-REVIEW-AGENT-ADVANCE-DENIED (namespaced agent_type -> identical block).
run_guard_adv on "$PS_ADV" "$ADV_CONTENT" "$TMP_ADV" "simple-workflow:doc-verifier"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"' \
   && printf '%s' "$LAST_STDOUT" | grep -q 'unauthorized_phase_advance_by_review_agent'; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX3-REVIEW-AGENT-ADVANCE-DENIED (namespaced simple-workflow:doc-verifier, on): blocked"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX3-REVIEW-AGENT-ADVANCE-DENIED (namespaced): expected block. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# metric-only -> fail-open (no block), stderr logs would-deny (PART A still detects).
run_guard_adv metric-only "$PS_ADV" "$ADV_CONTENT" "$TMP_ADV" "doc-verifier"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"' \
   && printf '%s' "$LAST_STDERR" | grep -q 'metric-only: would deny unauthorized_phase_advance_by_review_agent'; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX3-PART-A/PART-B (metric-only): detect+log, fail-open allow"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX3 (metric-only): expected allow+stderr. stdout: $LAST_STDOUT stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-FIX3-LEGIT-ORCHESTRATOR-ALLOWED: empty agent_type (orchestrator) advancement
# -> ALLOW even under on (fail-open-on-empty). PART A detects the advancement but
# the empty identity is not in the denylist.
run_guard_adv on "$PS_ADV" "$ADV_CONTENT" "$TMP_ADV" ""
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"'; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX3-LEGIT-ORCHESTRATOR-ALLOWED (empty agent_type, on): advancement allowed (fail-open-on-empty)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX3-LEGIT-ORCHESTRATOR-ALLOWED: empty agent_type must fail-open. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# CT-FIX3-PART-A: a generator (implementer) doing the SAME advancement -> ALLOW
# (not in the denylist), confirming PART A detection is identity-free but the
# deny only fires for review/evaluator roles.
run_guard_adv on "$PS_ADV" "$ADV_CONTENT" "$TMP_ADV" "implementer"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! printf '%s' "$LAST_STDOUT" | grep -q '"decision":"block"'; then
  echo -e "  ${GREEN}PASS${NC} CT-FIX3-PART-A (implementer advancement, on): generator allowed (role not denylisted)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CT-FIX3-PART-A: generator advancement must be allowed. stdout: $LAST_STDOUT"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_summary
