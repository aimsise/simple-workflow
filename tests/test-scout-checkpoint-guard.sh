#!/usr/bin/env bash
# tests/test-scout-checkpoint-guard.sh
#
# Fixture-driven regression suite for hooks/scout-checkpoint-guard.sh — the
# Stop hook that guards /plan2doc's ssot-line emit from prematurely ending
# the turn before /scout Step 8 / 8a / 9 / 10 finalize (including the
# ## [SW-CHECKPOINT] emit).
#
# Mirrors the structural prior in tests/test-impl-checkpoint-guard.sh; the
# differences are signal selection (plan2doc ssot-line vs audit
# Status/Reports literals) and the phase-state.yaml absent branch — the
# /scout failure mode is canonically observed on legacy product_backlog
# tickets that have no phase-state.yaml, so C5 explicitly exercises that
# path (NAC-2).
#
# Fourteen cases exercise:
#   C1  — short-circuit on missing transcript_path
#   C2  — short-circuit on missing ssot-line in tail
#   C3  — short-circuit on ## [SW-CHECKPOINT] present (counter cleared)
#   C4  — short-circuit on no /scout Skill invocation (cross-session guard)
#   C5  — block on 3-AND match WITHOUT phase-state.yaml (NAC-2)
#   C6  — block on 3-AND match WITH phase-state.yaml in-progress
#   C7  — short-circuit when phase-state.yaml has scout.status == completed
#   C8  — release at counter == 3 with [SCOUT-CHECKPOINT-RELEASE] stdout
#   C9  — Step 2a gate fires after fresh briefs/done/ autopilot completion (v8.0.1, AC-1)
#   C10 — Step 2a gate yields to active autopilot when both states coexist (v8.0.1, AC-3)
#   C11 — Step 2a gate ignores stale briefs/done/ state past default TTL (v8.0.1, AC-4)
#   C12 — Step 2 kill switch precedes Step 2a; SW_SCOUT_CHECKPOINT_MODE=off skips both (v8.0.1, AC-2)
#   C13 — Step 2a gate fails closed when any tickets[].status != completed (v8.0.1, AC-1 negative)
#   C14 — Step 2a gate respects custom SW_AUTOPILOT_DONE_GATE_TTL_SEC (v8.0.1, AC-4 variant)
#
# Each fixture is built fresh in a tmpdir; mock state files and JSONL
# transcripts are constructed inline so the test is hermetic and
# self-documenting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

HOOK="$HOOK_DIR/scout-checkpoint-guard.sh"

echo "=== scout-checkpoint-guard.sh Tests ==="
echo ""

# Helpers --------------------------------------------------------------------

make_phase_state() {
  local repo_dir="$1"
  local ticket_dir="$2"
  local content="$3"
  mkdir -p "$repo_dir/.simple-workflow/backlog/active/$ticket_dir"
  printf '%s\n' "$content" > "$repo_dir/.simple-workflow/backlog/active/$ticket_dir/phase-state.yaml"
}

# Step 2a (v8.0.1) fixture helpers: write a briefs/done/<parent>/ or
# briefs/active/<parent>/ autopilot-state.yaml. The content is canonical
# tickets[] list form; parse_ticket_statuses already tolerates list and
# map forms (WI-4).
make_done_autopilot_state() {
  local repo_dir="$1"
  local parent_slug="$2"
  local content="$3"
  mkdir -p "$repo_dir/.simple-workflow/backlog/briefs/done/$parent_slug"
  printf '%s\n' "$content" > "$repo_dir/.simple-workflow/backlog/briefs/done/$parent_slug/autopilot-state.yaml"
}

make_active_autopilot_state() {
  local repo_dir="$1"
  local parent_slug="$2"
  local content="$3"
  mkdir -p "$repo_dir/.simple-workflow/backlog/briefs/active/$parent_slug"
  printf '%s\n' "$content" > "$repo_dir/.simple-workflow/backlog/briefs/active/$parent_slug/autopilot-state.yaml"
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
  rm -f "/tmp/.scout-checkpoint-$1" 2>/dev/null || true
}

# Shared transcript fixtures -------------------------------------------------

# /scout invocation, then /plan2doc invocation, then plan2doc's ssot-line as
# the last assistant text turn — no SW-CHECKPOINT emitted yet. This is the
# "premature end_turn" failure mode the hook is designed to catch.
TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT='{"type":"user","uuid":"u1","message":{"role":"user","content":[{"type":"text","text":"/scout 001-test"}]}}
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Skill","input":{"skill":"simple-workflow:scout","args":""}}]}}
{"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu2","name":"Skill","input":{"skill":"simple-workflow:plan2doc","args":"(ticket-dir: .simple-workflow/backlog/active/001-test)"}}]}}
{"type":"assistant","uuid":"a3","message":{"role":"assistant","content":[{"type":"text","text":"plan2doc: ac-source=ticket.md verbatim=true\n\n**Status**: success\n**Output**: .simple-workflow/backlog/active/001-test/plan.md\n**Summary**: plan written\n**Next Steps**: Run /impl"}]}}'

# Same /scout + /plan2doc invocations, but plan2doc emit is followed by a
# Phase 3 SW-CHECKPOINT — the prompt-side completed the contract.
TRANSCRIPT_PLAN2DOC_EMIT_WITH_CHECKPOINT='{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Skill","input":{"skill":"simple-workflow:scout","args":""}}]}}
{"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu2","name":"Skill","input":{"skill":"simple-workflow:plan2doc","args":""}}]}}
{"type":"assistant","uuid":"a3","message":{"role":"assistant","content":[{"type":"text","text":"plan2doc: ac-source=ticket.md verbatim=true\n\n**Status**: success"}]}}
{"type":"assistant","uuid":"a4","message":{"role":"assistant","content":[{"type":"text","text":"## [SW-CHECKPOINT]\nphase: scout\nstatus: completed"}]}}'

# Standalone /audit run (no /scout invocation) — the cross-session staleness
# guard MUST exit 0 here so unrelated reviews and stale phase-state.yaml
# from a prior session do not produce false blocks.
TRANSCRIPT_NO_SCOUT='{"type":"user","uuid":"u1","message":{"role":"user","content":[{"type":"text","text":"/audit"}]}}
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Skill","input":{"skill":"simple-workflow:audit","args":""}}]}}
{"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"text","text":"plan2doc: ac-source=ticket.md verbatim=true (referenced in audit summary, not a fresh emit)"}]}}'

# Same as above but with NO ssot-line in the tail at all.
TRANSCRIPT_NO_SSOT='{"type":"user","uuid":"u1","message":{"role":"user","content":[{"type":"text","text":"/scout"}]}}
{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Skill","input":{"skill":"simple-workflow:scout","args":""}}]}}
{"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"text","text":"Investigating the codebase..."}]}}'

# Canonical phase-state.yaml shapes -----------------------------------------

PHASE_STATE_SCOUT_IN_PROGRESS='version: 1
size: M
created: 2026-05-09T00:00:00Z
current_phase: scout
last_completed_phase: create_ticket
overall_status: in-progress
phases:
  create_ticket:
    status: completed
  scout:
    status: in-progress
    started_at: 2026-05-09T00:00:00Z
    artifacts:
      investigation: null
      plan: null
  impl:
    status: pending
  ship:
    status: pending
runtime_metrics: []'

PHASE_STATE_SCOUT_COMPLETED='version: 1
current_phase: impl
last_completed_phase: scout
phases:
  create_ticket:
    status: completed
  scout:
    status: completed
    completed_at: 2026-05-09T00:00:00Z
    artifacts:
      investigation: .simple-workflow/backlog/active/001-test/investigation.md
      plan: .simple-workflow/backlog/active/001-test/plan.md
  impl:
    status: pending
  ship:
    status: pending
runtime_metrics: []'

# Step 2a autopilot-state.yaml fixtures (v8.0.1) ----------------------------

# Canonical "all tickets completed" autopilot-state.yaml — matches the
# shape /ship writes after the final ticket is shipped.
AUTOPILOT_STATE_ALL_COMPLETED='version: 1
slug: test-brief
created_at: 2026-05-26T00:00:00Z
tickets:
  - logical_id: t1
    ticket_dir: .simple-workflow/backlog/done/test-brief/001-one
    status: completed
    steps:
      create-ticket: completed
      scout: completed
      impl: completed
      ship: completed
  - logical_id: t2
    ticket_dir: .simple-workflow/backlog/done/test-brief/002-two
    status: completed
    steps:
      create-ticket: completed
      scout: completed
      impl: completed
      ship: completed'

# Mixed-status autopilot-state.yaml — one completed, one failed. The gate
# must NOT silent-exit on this shape because the brief is genuinely
# incomplete (even though /ship moved the dir to briefs/done/).
AUTOPILOT_STATE_ONE_FAILED='version: 1
slug: test-brief
created_at: 2026-05-26T00:00:00Z
tickets:
  - logical_id: t1
    ticket_dir: .simple-workflow/backlog/done/test-brief/001-one
    status: completed
    steps:
      ship: completed
  - logical_id: t2
    ticket_dir: .simple-workflow/backlog/done/test-brief/002-two
    status: failed
    steps:
      ship: failed'

# Active autopilot-state.yaml (one ticket still in progress) — used by
# C10 to assert is_autopilot_context() blocks Step 2a even when a fresh
# all-completed briefs/done/ state also exists.
AUTOPILOT_STATE_ACTIVE_IN_PROGRESS='version: 1
slug: active-brief
created_at: 2026-05-27T00:00:00Z
tickets:
  - logical_id: t1
    ticket_dir: .simple-workflow/backlog/active/active-brief/001-one
    status: in-progress
    steps:
      scout: in-progress'

# Fixture (C1): missing transcript_path -> exit 0 ---------------------------
echo "--- C1: short-circuit on missing transcript_path ---"
TMP=$(mktemp -d)
SID="scout-cp-c1-$$"
cleanup_session "$SID"
# transcript_path empty AND points to nonexistent file
INPUT=$(jq -n --arg t "" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} C1: exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C1: expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C2): tail does not contain ssot-line -> exit 0 -------------------
echo "--- C2: short-circuit on missing ssot-line ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/.simple-workflow/backlog/active"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_NO_SSOT"
SID="scout-cp-c2-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} C2: exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C2: expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C3): ## [SW-CHECKPOINT] visible in tail -> exit 0 + counter cleared
echo "--- C3: short-circuit on SW-CHECKPOINT present (counter cleared) ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/.simple-workflow/backlog/active"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_WITH_CHECKPOINT"
SID="scout-cp-c3-$$"
# Seed a counter file so we can assert it gets cleaned up.
echo "2" > "/tmp/.scout-checkpoint-$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ] && [ ! -f "/tmp/.scout-checkpoint-$SID" ]; then
  echo -e "  ${GREEN}PASS${NC} C3: exit 0, empty stdout, counter cleared"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C3: expected exit 0 + empty stdout + counter removed"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  echo -e "       Counter still present: $([ -f "/tmp/.scout-checkpoint-$SID" ] && echo yes || echo no)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C4): no /scout Skill invocation in transcript -> exit 0 ----------
echo "--- C4: short-circuit on no /scout Skill invocation ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/.simple-workflow/backlog/active"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_NO_SCOUT"
SID="scout-cp-c4-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} C4: exit 0, empty stdout"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C4: expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C5): 3-AND met, NO phase-state.yaml -> decision:block (NAC-2) ---
echo "--- C5: block on 3-AND match without phase-state.yaml (legacy ticket flow) ---"
TMP=$(mktemp -d)
# Deliberately do NOT create phase-state.yaml; this is the legacy
# product_backlog flow that triggered the original failure mode.
mkdir -p "$TMP/.simple-workflow/backlog/active"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c5-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] && [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} C5: emits decision=block, exit 0 (no phase-state.yaml needed)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C5: expected decision=block, exit 0"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C6): 3-AND met WITH phase-state.yaml in-progress -> decision:block
echo "--- C6: block on 3-AND match with phase-state.yaml in-progress ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_SCOUT_IN_PROGRESS"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c6-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] && [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} C6: emits decision=block, exit 0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C6: expected decision=block, exit 0"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C7): phase-state.yaml has scout.status=completed -> exit 0 -------
echo "--- C7: short-circuit when phase-state.yaml has scout.status=completed ---"
TMP=$(mktemp -d)
make_phase_state "$TMP" "001-test" "$PHASE_STATE_SCOUT_COMPLETED"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c7-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  echo -e "  ${GREEN}PASS${NC} C7: exit 0, empty stdout (state machine already advanced)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C7: expected exit 0 + empty stdout"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C8): counter == 3 -> release with [SCOUT-CHECKPOINT-RELEASE] -----
echo "--- C8: release at counter=3 with [SCOUT-CHECKPOINT-RELEASE] stdout ---"
TMP=$(mktemp -d)
# phase-state.yaml in-progress so the counter mtime comparison branch
# can be exercised. Counter set to 3 to trigger release.
make_phase_state "$TMP" "001-test" "$PHASE_STATE_SCOUT_IN_PROGRESS"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c8-$$"
cleanup_session "$SID"
echo "3" > "/tmp/.scout-checkpoint-$SID"
# Force counter mtime to be strictly NEWER than state file mtime so the
# hook's `STATE_FILE -nt COUNTER_FILE` reset branch does NOT fire and
# BLOCK_COUNT stays at the preset value (3). Mirrors the technique used
# in test-impl-checkpoint-guard.sh fixture (v).
touch -r "$TMP/.simple-workflow/backlog/active/001-test/phase-state.yaml" "/tmp/.scout-checkpoint-$SID"
sleep 1
touch "/tmp/.scout-checkpoint-$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] \
   && echo "$LAST_STDOUT" | grep -qF '[SCOUT-CHECKPOINT-RELEASE]' \
   && echo "$LAST_STDOUT" | grep -qF 'Resume with: /scout' \
   && [ ! -f "/tmp/.scout-checkpoint-$SID" ]; then
  echo -e "  ${GREEN}PASS${NC} C8: release stdout contains [SCOUT-CHECKPOINT-RELEASE] + counter removed"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C8: release stdout missing required tokens"
  echo -e "       Exit: $LAST_EXIT_CODE"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  echo -e "       Counter file present: $([ -f "/tmp/.scout-checkpoint-$SID" ] && echo yes || echo no)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# ===========================================================================
# v8.0.1 — Step 2a (autopilot-completion gate) regression cases C9..C14
# ===========================================================================

# Fixture (C9): fresh done state, all completed -> Step 2a silent exit ------
echo "--- C9: Step 2a silent-exits on fresh briefs/done/ all-completed state ---"
TMP=$(mktemp -d)
make_done_autopilot_state "$TMP" "test-brief" "$AUTOPILOT_STATE_ALL_COMPLETED"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c9-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] \
   && [ -z "$LAST_STDOUT" ] \
   && echo "$LAST_STDERR" | grep -qF '[SCOUT-AUTOPILOT-DONE-GATE] silent exit'; then
  echo -e "  ${GREEN}PASS${NC} C9: exit 0, empty stdout, gate stderr token visible"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C9: expected exit 0 + empty stdout + gate stderr token"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C10): active autopilot present -> Step 2a yields, 3-AND blocks --
echo "--- C10: Step 2a yields when an active autopilot exists; 3-AND blocks ---"
TMP=$(mktemp -d)
# Done state is all-completed AND fresh, BUT an active autopilot is in
# progress under briefs/active/ — is_autopilot_context() returns true,
# so Step 2a does NOT silent-exit. With no phase-state.yaml under
# .simple-workflow/backlog/active/, Step 3 also passes through and the
# 3-AND on the transcript tail produces decision=block.
make_done_autopilot_state "$TMP" "done-brief" "$AUTOPILOT_STATE_ALL_COMPLETED"
make_active_autopilot_state "$TMP" "active-brief" "$AUTOPILOT_STATE_ACTIVE_IN_PROGRESS"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c10-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] \
   && [ "$LAST_EXIT_CODE" -eq 0 ] \
   && ! echo "$LAST_STDERR" | grep -qF '[SCOUT-AUTOPILOT-DONE-GATE] silent exit'; then
  echo -e "  ${GREEN}PASS${NC} C10: gate yields to active; decision=block; no gate token"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C10: expected decision=block, no gate stderr token"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C11): stale done state (year-2020 mtime) -> gate falls through --
echo "--- C11: stale briefs/done/ state past default TTL falls through to block ---"
TMP=$(mktemp -d)
make_done_autopilot_state "$TMP" "test-brief" "$AUTOPILOT_STATE_ALL_COMPLETED"
# Age the file far past the default 86400s TTL.
touch -t 202001010000 "$TMP/.simple-workflow/backlog/briefs/done/test-brief/autopilot-state.yaml"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c11-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] \
   && [ "$LAST_EXIT_CODE" -eq 0 ] \
   && ! echo "$LAST_STDERR" | grep -qF '[SCOUT-AUTOPILOT-DONE-GATE] silent exit'; then
  echo -e "  ${GREEN}PASS${NC} C11: stale done state -> gate falls through; decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C11: expected decision=block, no gate stderr token"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C12): SW_SCOUT_CHECKPOINT_MODE=off precedes Step 2a -------------
echo "--- C12: SW_SCOUT_CHECKPOINT_MODE=off short-circuits before Step 2a ---"
TMP=$(mktemp -d)
make_done_autopilot_state "$TMP" "test-brief" "$AUTOPILOT_STATE_ALL_COMPLETED"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c12-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
# Run the hook with the kill switch active. The gate's stderr token must
# NOT appear (Step 2 wins). Wrapped inline because run_guard_hook does
# not have an env-passthrough surface.
stdout_file=$(mktemp); stderr_file=$(mktemp)
set +e
echo "$INPUT" | (cd "$TMP" && SW_SCOUT_CHECKPOINT_MODE=off bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
LAST_EXIT_CODE=$?
set -e
LAST_STDOUT=$(cat "$stdout_file"); LAST_STDERR=$(cat "$stderr_file")
rm -f "$stdout_file" "$stderr_file"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ] \
   && [ -z "$LAST_STDOUT" ] \
   && ! echo "$LAST_STDERR" | grep -qF '[SCOUT-AUTOPILOT-DONE-GATE]'; then
  echo -e "  ${GREEN}PASS${NC} C12: kill-switch wins, no Step 2a stderr token"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C12: expected exit 0 + empty stdout + no gate token"
  echo -e "       Exit: $LAST_EXIT_CODE  Stdout: '$LAST_STDOUT'"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C13): one ticket failed -> gate fails closed -------------------
echo "--- C13: one tickets[].status=failed -> gate falls through to block ---"
TMP=$(mktemp -d)
make_done_autopilot_state "$TMP" "test-brief" "$AUTOPILOT_STATE_ONE_FAILED"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c13-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
run_guard_hook "$INPUT" "$TMP"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] \
   && [ "$LAST_EXIT_CODE" -eq 0 ] \
   && ! echo "$LAST_STDERR" | grep -qF '[SCOUT-AUTOPILOT-DONE-GATE] silent exit'; then
  echo -e "  ${GREEN}PASS${NC} C13: failed ticket -> gate yields; decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C13: expected decision=block, no gate stderr token"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

# Fixture (C14): SW_AUTOPILOT_DONE_GATE_TTL_SEC=60 + state aged 120s ------
echo "--- C14: custom SW_AUTOPILOT_DONE_GATE_TTL_SEC=60 with 120s-old state ---"
TMP=$(mktemp -d)
make_done_autopilot_state "$TMP" "test-brief" "$AUTOPILOT_STATE_ALL_COMPLETED"
# Age the file by 120 seconds. Cross-platform: try GNU date first, BSD
# date next; both forms yield a stable yyyymmddHHMM[.SS] stamp for touch.
TS_PAST=""
if TS_PAST="$(date -u -d "120 seconds ago" "+%Y%m%d%H%M.%S" 2>/dev/null)" && [ -n "$TS_PAST" ]; then
  :
elif TS_PAST="$(date -u -v-120S "+%Y%m%d%H%M.%S" 2>/dev/null)" && [ -n "$TS_PAST" ]; then
  :
else
  TS_PAST="202001010000"  # fall back to far-past so the test still rejects
fi
touch -t "$TS_PAST" "$TMP/.simple-workflow/backlog/briefs/done/test-brief/autopilot-state.yaml"
make_transcript "$TMP/transcript.jsonl" "$TRANSCRIPT_PLAN2DOC_EMIT_NO_CHECKPOINT"
SID="scout-cp-c14-$$"
cleanup_session "$SID"
INPUT=$(jq -n --arg t "$TMP/transcript.jsonl" --arg s "$SID" '{transcript_path: $t, session_id: $s}')
stdout_file=$(mktemp); stderr_file=$(mktemp)
set +e
echo "$INPUT" | (cd "$TMP" && SW_AUTOPILOT_DONE_GATE_TTL_SEC=60 bash "$HOOK") >"$stdout_file" 2>"$stderr_file"
LAST_EXIT_CODE=$?
set -e
LAST_STDOUT=$(cat "$stdout_file"); LAST_STDERR=$(cat "$stderr_file")
rm -f "$stdout_file" "$stderr_file"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.decision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "block" ] \
   && [ "$LAST_EXIT_CODE" -eq 0 ] \
   && ! echo "$LAST_STDERR" | grep -qF '[SCOUT-AUTOPILOT-DONE-GATE] silent exit'; then
  echo -e "  ${GREEN}PASS${NC} C14: custom TTL=60 + 120s-old state -> gate yields; decision=block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} C14: expected decision=block, no gate stderr token"
  echo -e "       Exit: $LAST_EXIT_CODE  Decision: '$DECISION'"
  echo -e "       Stdout: $LAST_STDOUT"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_session "$SID"
rm -rf "$TMP"

echo ""
print_summary
