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

# Fixture (iv): SW-CHECKPOINT in recent turn → exit 0 + emit
# `audit_handoff_via_prompt` (the SLO denominator metric, convergence §9).
# H4 (skeptical-review v6.4.1): asserts the metric IS appended to
# phase-state.yaml runtime_metrics so a future change to the conditional
# gating in the hook's SW-CHECKPOINT branch cannot regress the SLO
# silently.
echo "--- (iv): SW-CHECKPOINT visible in tail → silent exit 0 + audit_handoff_via_prompt metric ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_WITH_CHECKPOINT"
SID="impl-cp-iv-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ICG_IV_STATE="$TMP/.simple-workflow/backlog/active/001-test/phase-state.yaml"
ICG_IV_METRIC_HITS=$(grep -cF 'stop_reason: audit_handoff_via_prompt' "$ICG_IV_STATE" 2>/dev/null || true)
ICG_IV_METRIC_HITS="${ICG_IV_METRIC_HITS:-0}"
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ] && [ "$ICG_IV_METRIC_HITS" -ge 1 ]; then
  echo -e "  ${GREEN}PASS${NC} (iv): exit 0, empty stdout, audit_handoff_via_prompt recorded"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (iv): expected exit 0 + empty stdout + 1+ audit_handoff_via_prompt entries"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  echo -e "       Metric hits: $ICG_IV_METRIC_HITS"
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

# ============================================================
# Policy-gate-stop honour gate (SW_AUTOPILOT_POLICY_STOP_HONOR)
# ============================================================
echo ""
echo "--- Policy-gate-stop honour gate ---"

# env-capable runner (the default run_guard_hook above does not forward env).
run_guard_hook_env() {
  local input="$1"; local cwd="$2"; local env_kv="$3"
  local stdout_file stderr_file
  stdout_file=$(mktemp); stderr_file=$(mktemp)
  set +e
  if [ -n "$env_kv" ]; then
    echo "$input" | (cd "$cwd" && env "$env_kv" bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  else
    echo "$input" | (cd "$cwd" && bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
  fi
  LAST_EXIT_CODE=$?
  set -e
  LAST_STDOUT=$(cat "$stdout_file"); LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

# Transcript whose LAST assistant turn is the audit block (so the 5-AND
# would normally block) AND carries the policy_gate_stop marker in the same
# text block. This is the realistic shape: the orchestrator emits the audit
# block, then hard-stops with the [AUTOPILOT-POLICY] line in the same turn.
TRANSCRIPT_AUDIT_PLUS_POLICY_STOP='{"type":"user","uuid":"u1","message":{"role":"user","content":[{"type":"text","text":"/impl"}]}}
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Skill","input":{"skill":"simple-workflow:impl","args":""}}]}}
{"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu2","name":"Skill","input":{"skill":"simple-workflow:audit","args":"round=1"}}]}}
{"type":"assistant","uuid":"a3","message":{"role":"assistant","content":[{"type":"text","text":"**Status**: FAIL\n**Reports**:\n  - Code review: q.md\n**Summary**: audit infrastructure failure\n[AUTOPILOT-POLICY] gate=audit_infrastructure_fail action=stop reason=audit_infra_fail"}]}}'

# (P-i): honour on → 5-AND met but marker present → NO block, exit 0.
echo "--- (P-i): honour on → 5-AND met + marker → no block ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_PLUS_POLICY_STOP"
SID="impl-cp-pgs-i-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook_env "$INPUT" "$TMP" "SW_AUTOPILOT_POLICY_STOP_HONOR=on"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ "$DECISION" != "block" ] \
   && echo "$LAST_STDERR" | grep -qF '[POLICY-GATE-STOP]'; then
  echo -e "  ${GREEN}PASS${NC} (P-i): honour → exit 0, no block, [POLICY-GATE-STOP] stderr"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (P-i): expected exit 0 + no block"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'  Stderr: ${LAST_STDERR:0:160}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (P-ii): regression — same 5-AND but NO marker → still blocks (honour on).
echo "--- (P-ii): no marker → still blocks ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-pgs-ii-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook_env "$INPUT" "$TMP" "SW_AUTOPILOT_POLICY_STOP_HONOR=on"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} (P-ii): no marker → decision=block (unchanged)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (P-ii): expected decision=block"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (P-iii): kill switch off → ignore marker → block.
echo "--- (P-iii): off → block despite marker ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_PLUS_POLICY_STOP"
SID="impl-cp-pgs-iii-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook_env "$INPUT" "$TMP" "SW_AUTOPILOT_POLICY_STOP_HONOR=off"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} (P-iii): off → decision=block (marker ignored)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (P-iii): expected decision=block"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (P-iv): metric-only → block + [POLICY-GATE-STOP] would-honour stderr.
echo "--- (P-iv): metric-only → block + stderr ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_PLUS_POLICY_STOP"
SID="impl-cp-pgs-iv-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook_env "$INPUT" "$TMP" "SW_AUTOPILOT_POLICY_STOP_HONOR=metric-only"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] && echo "$LAST_STDERR" | grep -qF '[POLICY-GATE-STOP]' \
   && echo "$LAST_STDERR" | grep -qiF 'would honour'; then
  echo -e "  ${GREEN}PASS${NC} (P-iv): metric-only → block + would-honour stderr"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (P-iv): expected block + would-honour stderr"
  echo -e "       Decision: '$DECISION'  Stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (P-v): unknown value → fail-closed to off → block.
echo "--- (P-v): unknown value → fail-closed (block) ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_PLUS_POLICY_STOP"
SID="impl-cp-pgs-v-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook_env "$INPUT" "$TMP" "SW_AUTOPILOT_POLICY_STOP_HONOR=garbage-value"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ]; then
  echo -e "  ${GREEN}PASS${NC} (P-v): unknown → decision=block (fail-closed)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (P-v): expected decision=block"
  echo -e "       Decision: '$DECISION'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# ===========================================================================
# T-005 — parallel-mode dual-event branch (Stop / SubagentStop)
# ===========================================================================
echo ""
echo "--- T-005 parallel-mode dual-event branch ---"

# Write an autopilot-state.yaml under briefs/active/<slug>/ carrying an
# optional parallel_mode: scalar (and optionally main_checkout_root). Used to
# drive resolve_parallel_mode + the main_checkout_root preference.
make_parallel_autopilot_state() {
  local repo_dir="$1"
  local parent_slug="$2"
  local parallel_mode="$3"
  local main_checkout_root="${4:-}"
  mkdir -p "$repo_dir/.simple-workflow/backlog/briefs/active/$parent_slug"
  {
    printf 'version: 1\n'
    printf 'slug: %s\n' "$parent_slug"
    printf 'parallel_mode: %s\n' "$parallel_mode"
    [ -n "$main_checkout_root" ] && printf 'main_checkout_root: %s\n' "$main_checkout_root"
    printf 'tickets:\n'
    printf '  - logical_id: t1\n'
    printf '    ticket_dir: 001-test\n'
    printf '    status: in_progress\n'
    printf '    steps:\n'
    printf '      impl: in_progress\n'
  } > "$repo_dir/.simple-workflow/backlog/briefs/active/$parent_slug/autopilot-state.yaml"
}

# Executor transcript: an ac-evaluator subagent that emits an /audit-style
# block but has NO Skill(simple-workflow:impl) invocation — the existing
# Step 7 cross-session signature gate must silent-exit on it.
TRANSCRIPT_AC_EVALUATOR='{"type":"user","uuid":"u1","message":{"role":"user","content":[{"type":"text","text":"evaluate ACs"}]}}
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"text","text":"**Status**: PASS\n**Reports**:\n  - eval: e.md\n**Summary**: all ACs pass"}]}}'

# (T-PAR-1): SubagentStop + parallel=on + executor transcript (5-AND) → block.
echo "--- (T-PAR-1): SubagentStop + parallel=on + 5-AND → block ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_parallel_autopilot_state "$TMP" "par-brief" "on"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-tpar1-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" \
  '{transcript_path: $t, session_id: $s, hook_event_name: "SubagentStop"}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] && [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-1): SubagentStop enforces on executor transcript → decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-1): expected decision=block, exit 0"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'  Stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (T-PAR-2): Stop + parallel=on → stand down (exit 0, [IMPL-CHECKPOINT] log).
echo "--- (T-PAR-2): main Stop + parallel=on → stand down ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_parallel_autopilot_state "$TMP" "par-brief" "on"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-tpar2-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" \
  '{transcript_path: $t, session_id: $s, hook_event_name: "Stop"}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ "$DECISION" != "block" ] \
   && echo "$LAST_STDERR" | grep -qF '[IMPL-CHECKPOINT] parallel stand-down'; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-2): main Stop stands down → exit 0, no block, stand-down log"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-2): expected exit 0 + no block + stand-down log"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'  Stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (T-PAR-3): serial (parallel=off) SubagentStop + unrelated ac-evaluator
# transcript → silent-exit at the existing Step 7 signature gate.
echo "--- (T-PAR-3): serial SubagentStop + unrelated ac-evaluator → silent exit ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
# parallel=off explicitly (serial). The ac-evaluator transcript has the audit
# block but no Skill(simple-workflow:impl), so Step 7 silent-exits.
make_parallel_autopilot_state "$TMP" "par-brief" "off"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AC_EVALUATOR"
SID="impl-cp-tpar3-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" \
  '{transcript_path: $t, session_id: $s, hook_event_name: "SubagentStop"}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ] \
   && ! echo "$LAST_STDERR" | grep -qF '[IMPL-CHECKPOINT] parallel stand-down'; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-3): serial SubagentStop → exit 0, empty stdout, no parallel log"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-3): expected exit 0 + empty stdout + no parallel log"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'  Stdout: '$LAST_STDOUT'  Stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (T-PAR-4): non-autopilot SubagentStop → early exit 0, no transcript scan.
echo "--- (T-PAR-4): non-autopilot SubagentStop → exit 0 ---"
TMP=$(mktemp -d)
# NO autopilot-state.yaml at all → resolve_parallel_mode → off; impl Step 1
# finds no phase-state.yaml → silent-exit before any transcript I/O.
mkdir -p "$TMP/.simple-workflow/backlog/active"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-tpar4-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" \
  '{transcript_path: $t, session_id: $s, hook_event_name: "SubagentStop"}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-4): non-autopilot SubagentStop → exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-4): expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'  Stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (T-PAR-5): missing hook_event_name + parallel=on → treated as Stop → stand down.
echo "--- (T-PAR-5): missing hook_event_name + parallel=on → treated as Stop (stand down) ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_parallel_autopilot_state "$TMP" "par-brief" "on"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-tpar5-$$"
cleanup_session "$SID"
# No hook_event_name field in the payload.
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" \
  '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ "$DECISION" != "block" ] \
   && echo "$LAST_STDERR" | grep -qF '[IMPL-CHECKPOINT] parallel stand-down'; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-5): missing event treated as Stop → stand down"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-5): expected exit 0 + no block + stand-down log"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'  Stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (T-PAR-6): parallel=off main Stop → existing behaviour unchanged (block).
echo "--- (T-PAR-6): parallel=off main Stop → existing behaviour (block) ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_parallel_autopilot_state "$TMP" "par-brief" "off"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-tpar6-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" \
  '{transcript_path: $t, session_id: $s, hook_event_name: "Stop"}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] && [ "$LAST_EXIT_CODE" -eq 0 ] \
   && ! echo "$LAST_STDERR" | grep -qF '[IMPL-CHECKPOINT] parallel'; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-6): parallel=off main Stop → decision=block, no parallel log"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-6): expected decision=block, no parallel stderr"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'  Stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (T-PAR-7): metric-only main Stop → log "would stand down" + fall through (block).
echo "--- (T-PAR-7): metric-only main Stop → log + fall through (block) ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
make_parallel_autopilot_state "$TMP" "par-brief" "metric-only"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-tpar7-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" \
  '{transcript_path: $t, session_id: $s, hook_event_name: "Stop"}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] && [ "$LAST_EXIT_CODE" -eq 0 ] \
   && echo "$LAST_STDERR" | grep -qF '[IMPL-CHECKPOINT] parallel stand-down (metric-only)'; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-7): metric-only logs would-stand-down + falls through → block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-7): expected block + metric-only stand-down log"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'  Stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# (T-PAR-8): worktree phase-state resolution via main_checkout_root (AC-6).
# cwd is a worktree path with its OWN autopilot-state.yaml (carrying
# main_checkout_root pointing at the main checkout) but NO phase-state.yaml;
# the main checkout holds the phase-state.yaml. The impl guard must resolve
# phase-state from main_checkout_root, pass Step 1, and enforce on SubagentStop.
echo "--- (T-PAR-8): SubagentStop in worktree resolves phase-state via main_checkout_root → block ---"
MAIN=$(mktemp -d)
WT=$(mktemp -d)
# Main checkout: phase-state.yaml lives here (NOT in the worktree).
make_phase_state "$MAIN" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
# Worktree: autopilot-state.yaml carrying main_checkout_root -> $MAIN; NO
# phase-state.yaml under the worktree's active/ dir.
mkdir -p "$WT/.simple-workflow/backlog/active"
make_parallel_autopilot_state "$WT" "par-brief" "on" "$MAIN"
make_transcript "$WT/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID="impl-cp-tpar8-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$WT/transcript.jsonl" --arg s "$SID" \
  '{transcript_path: $t, session_id: $s, hook_event_name: "SubagentStop"}')
run_guard_hook "$INPUT" "$WT"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] && [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-8): worktree SubagentStop resolves phase-state via main_checkout_root → block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-8): expected decision=block (phase-state resolved from main_checkout_root)"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'  Stderr: ${LAST_STDERR:0:200}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$MAIN" "$WT"

# (T-PAR-9, dogfood63 AC-8 owed): assert the impl main_checkout_root resolution emits its
# observability marker (the resolution is invisible in subagent transcripts, so the marker is the
# only way to verify it ran). Positive: marker fires + names the main checkout root. Control: no
# main_checkout_root in the state -> the resolution block is skipped and the marker is absent.
echo "--- (T-PAR-9): impl main_checkout_root resolution marker fires (AC-8 owed observability) ---"
MAIN9=$(mktemp -d); WT9=$(mktemp -d)
make_phase_state "$MAIN9" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
mkdir -p "$WT9/.simple-workflow/backlog/active"
make_parallel_autopilot_state "$WT9" "par9-brief" "on" "$MAIN9"
make_transcript "$WT9/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SID9="impl-cp-tpar9-$$"; cleanup_session "$SID9"
INPUT=$(jq -n --arg t "$WT9/transcript.jsonl" --arg s "$SID9" \
  '{transcript_path: $t, session_id: $s, hook_event_name: "SubagentStop"}')
run_guard_hook "$INPUT" "$WT9"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if echo "$LAST_STDERR" | grep -q "main_checkout_root resolution: root=$MAIN9"; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-9): impl main_checkout_root resolution marker fired (root=$MAIN9)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-9): expected marker 'root=$MAIN9' in stderr"
  echo -e "       Stderr: ${LAST_STDERR:0:300}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
MAINC=$(mktemp -d); WTC=$(mktemp -d)
make_phase_state "$MAINC" "001-test" "$PHASE_STATE_NEEDS_AUDIT"
mkdir -p "$WTC/.simple-workflow/backlog/active"
make_parallel_autopilot_state "$WTC" "par9c-brief" "on" ""
make_transcript "$WTC/transcript.jsonl" "$TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT"
SIDC="impl-cp-tpar9c-$$"; cleanup_session "$SIDC"
INPUTC=$(jq -n --arg t "$WTC/transcript.jsonl" --arg s "$SIDC" \
  '{transcript_path: $t, session_id: $s, hook_event_name: "SubagentStop"}')
run_guard_hook "$INPUTC" "$WTC"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! echo "$LAST_STDERR" | grep -q 'main_checkout_root resolution'; then
  echo -e "  ${GREEN}PASS${NC} (T-PAR-9 control): no main_checkout_root -> marker absent (non-vacuous)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} (T-PAR-9 control): marker fired despite empty main_checkout_root"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID9"; cleanup_session "$SIDC"
rm -rf "$MAIN9" "$WT9" "$MAINC" "$WTC"

echo ""
print_summary
