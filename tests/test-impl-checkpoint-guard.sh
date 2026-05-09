#!/usr/bin/env bash
# tests/test-impl-checkpoint-guard.sh
#
# Fixture-driven regression suite for hooks/impl-checkpoint-guard.sh — the
# Stop hook that guards /audit's structured-block emit from prematurely
# ending the turn before /impl Step 18 + Phase 3 finalize.
#
# Eight cases exercise the 5-AND gate, the three short-circuit denylist
# values, the SW-CHECKPOINT lag-tolerance branch, the loop-counter release
# at 3, the cross-session staleness guard, and the autopilot-context
# Resume-command UX. Each fixture is built fresh in a tmpdir; mock state
# files and JSONL transcripts are constructed inline so the test is
# hermetic and self-documenting.
#
# See tests/fixtures/impl-checkpoint-guard/README.md for fixture construction
# rules; the per-case state files below are the canonical examples.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

HOOK="$HOOK_DIR/impl-checkpoint-guard.sh"

echo "=== impl-checkpoint-guard.sh Tests ==="
echo ""

# Helpers ---------------------------------------------------------------------

make_phase_state() {
  local repo_dir="$1"
  local ticket_dir="$2"
  local content="$3"
  mkdir -p "$repo_dir/.simple-workflow/backlog/active/$ticket_dir"
  printf '%s\n' "$content" > "$repo_dir/.simple-workflow/backlog/active/$ticket_dir/phase-state.yaml"
}

make_autopilot_state() {
  local repo_dir="$1"
  local parent_slug="$2"
  mkdir -p "$repo_dir/.simple-workflow/backlog/briefs/active/$parent_slug"
  cat > "$repo_dir/.simple-workflow/backlog/briefs/active/$parent_slug/autopilot-state.yaml" <<EOF
version: 1
slug: $parent_slug
started: 2026-05-09T00:00:00Z
execution_mode: single
total_tickets: 1
tickets:
  - logical_id: $parent_slug
    ticket_dir: 001-test
    status: in_progress
    steps:
      create-ticket: completed
      scout: completed
      impl: in_progress
      ship: pending
runtime_metrics: []
EOF
}

make_transcript() {
  local path="$1"
  local content="$2"
  printf '%s\n' "$content" > "$path"
}

run_guard_hook() {
  local input="$1"
  local cwd="${2:-.}"
  local stdout_file stderr_file
  stdout_file=$(mktemp); stderr_file=$(mktemp)
  set +e
  echo "$input" | (cd "$cwd" && bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  local exit_code=$?
  set -e
  LAST_EXIT_CODE=$exit_code
  # shellcheck disable=SC2034
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

cleanup_session() {
  rm -f "/tmp/.impl-checkpoint-$1" 2>/dev/null || true
}

# Shared transcript fixtures --------------------------------------------------

# /impl invocation, then /audit invocation, then audit's structured block as
# the last assistant text turn — no SW-CHECKPOINT emitted yet. This is the
# "premature end_turn" failure mode the hook is designed to catch.
TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT='{"type":"user","uuid":"u1","message":{"role":"user","content":[{"type":"text","text":"/impl"}]}}
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Skill","input":{"skill":"simple-workflow:impl","args":""}}]}}
{"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu2","name":"Skill","input":{"skill":"simple-workflow:audit","args":"round=1"}}]}}
{"type":"assistant","uuid":"a3","message":{"role":"assistant","content":[{"type":"text","text":"**Status**: PASS\n**Reports**:\n  - Code review: q.md\n  - Security scan: s.md\n**Summary**: ok"}]}}'

# Same /impl + /audit invocations, but the audit block is followed by a
# Phase 3 SW-CHECKPOINT emit — the prompt-side AuditTail is observed to
# have completed.
TRANSCRIPT_AUDIT_EMIT_WITH_CHECKPOINT='{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Skill","input":{"skill":"simple-workflow:impl","args":""}}]}}
{"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu2","name":"Skill","input":{"skill":"simple-workflow:audit","args":"round=1"}}]}}
{"type":"assistant","uuid":"a3","message":{"role":"assistant","content":[{"type":"text","text":"**Status**: PASS\n**Reports**:\n  - q\n  - s\n**Summary**: ok"}]}}
{"type":"assistant","uuid":"a4","message":{"role":"assistant","content":[{"type":"text","text":"## [SW-CHECKPOINT]\nphase: impl\nstatus: completed"}]}}'

# Standalone /audit (no /impl invocation in transcript) — the cross-session
# staleness guard MUST exit 0 here so manual /audit reviews and stale
# phase-state.yaml left over from a prior session do not produce false
# blocks.
TRANSCRIPT_NO_IMPL='{"type":"user","uuid":"u1","message":{"role":"user","content":[{"type":"text","text":"/audit only_security_scan=true"}]}}
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Skill","input":{"skill":"simple-workflow:audit","args":"only_security_scan=true"}}]}}
{"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"text","text":"**Status**: PASS\n**Reports**:\n  - Code review: skipped\n  - Security scan: s.md\n**Summary**: ok"}]}}'

# Canonical phase-state.yaml shapes ------------------------------------------

PHASE_STATE_NEEDS_AUDIT='version: 1
size: M
created: 2026-05-09T00:00:00Z
current_phase: impl
last_completed_phase: scout
overall_status: in-progress
phases:
  create_ticket:
    status: completed
    completed_at: 2026-05-09T00:00:00Z
    artifacts:
      ticket: .simple-workflow/backlog/active/001-test/ticket.md
  scout:
    status: completed
    completed_at: 2026-05-09T00:00:00Z
    artifacts:
      plan: .simple-workflow/backlog/active/001-test/plan.md
      investigation: null
  impl:
    status: in-progress
    started_at: 2026-05-09T00:00:00Z
    current_round: 1
    max_rounds: 3
    phase_sub: audit-pending
    last_ac_status: PASS
    next_action: start-audit
    feedback_files:
      eval: null
      quality: null
  ship:
    status: pending
runtime_metrics: []'

PHASE_STATE_NULL_NEXT_ACTION='version: 1
current_phase: impl
phases:
  scout:
    status: completed
    artifacts:
      plan: .simple-workflow/backlog/active/001-test/plan.md
  impl:
    status: in-progress
    next_action: null
runtime_metrics: []'

PHASE_STATE_COMPLETED='version: 1
current_phase: impl
phases:
  scout:
    status: completed
    artifacts:
      plan: .simple-workflow/backlog/active/001-test/plan.md
  impl:
    status: completed
    completed_at: 2026-05-09T01:00:00Z
    next_action: null
runtime_metrics: []'

# Fixture (i): 5-AND met → decision:"block" ----------------------------------
echo "--- (i): 5-AND met → decision:block ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-i-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] && [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} (i): emits decision=block, exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (i): expected decision=block, exit 0"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (ii): next_action=null → exit 0 ------------------------------------
echo "--- (ii): next_action=null → silent exit 0 ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NULL_NEXT_ACTION"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-ii-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} (ii): exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (ii): expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (iii): phases.impl.status=completed → exit 0 -----------------------
echo "--- (iii): phases.impl.status=completed → silent exit 0 ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_COMPLETED"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-iii-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} (iii): exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (iii): expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (iv): SW-CHECKPOINT in recent turn → exit 0 ------------------------
echo "--- (iv): SW-CHECKPOINT visible in tail → silent exit 0 ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_WITH_CHECKPOINT"
SID="impl-cp-iv-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} (iv): exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (iv): expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (v): counter == 3 → release with /impl Resume command --------------
echo "--- (v): counter=3 → release with /impl Resume command ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-v-$$"
cleanup_session "$SID"
echo "3" > "/tmp/.impl-checkpoint-$SID"
# Force counter mtime to be strictly NEWER than state file mtime so the
# hook's `STATE_FILE -nt COUNTER_FILE` reset branch does NOT fire and
# BLOCK_COUNT stays at the preset value (3). Using -r to anchor to the
# state file's mtime then bumping by `sleep 1; touch` keeps the test
# deterministic across FS mtime granularities (1-second on many fs).
touch -r "$TMP/.simple-workflow/backlog/active/001-test/phase-state.yaml" "/tmp/.impl-checkpoint-$SID"
sleep 1
touch "/tmp/.impl-checkpoint-$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] \
   && echo "$LAST_STDOUT" | grep -qF '[IMPL-CHECKPOINT-RELEASE]' \
   && echo "$LAST_STDOUT" | grep -qF 'Resume with: /impl'; then
  echo -e "  ${GREEN}PASS${NC} (v): release stdout contains [IMPL-CHECKPOINT-RELEASE] + Resume with: /impl"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (v): release stdout missing required tokens"
  echo -e "       Exit: $LAST_EXIT_CODE"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (vi): phase-state.yaml absent → exit 0 -----------------------------
echo "--- (vi): phase-state.yaml absent → silent exit 0 ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/.simple-workflow/backlog/active"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-vi-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} (vi): exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (vi): expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (vii): Skill(impl) absent in transcript → exit 0 -------------------
echo "--- (vii): Skill(impl) absent in transcript → silent exit 0 ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_NO_IMPL"
SID="impl-cp-vii-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} (vii): exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (vii): expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (viii): /autopilot context + counter=3 → autopilot Resume command --
echo "--- (viii): /autopilot context + counter=3 → /autopilot Resume command ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_autopilot_state "$TMP" "feature-x"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-viii-$$"
cleanup_session "$SID"
echo "3" > "/tmp/.impl-checkpoint-$SID"
# Force counter mtime to be strictly NEWER than state file mtime — see
# fixture (v) for the rationale.
touch -r "$TMP/.simple-workflow/backlog/active/001-test/phase-state.yaml" "/tmp/.impl-checkpoint-$SID"
sleep 1
touch "/tmp/.impl-checkpoint-$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] \
   && echo "$LAST_STDOUT" | grep -qF '[IMPL-CHECKPOINT-RELEASE]' \
   && echo "$LAST_STDOUT" | grep -qF 'Resume with: /autopilot' \
   && echo "$LAST_STDOUT" | grep -qF 'feature-x'; then
  echo -e "  ${GREEN}PASS${NC} (viii): release stdout names autopilot parent slug"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (viii): release stdout missing autopilot Resume tokens"
  echo -e "       Exit: $LAST_EXIT_CODE"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

echo ""
print_summary
