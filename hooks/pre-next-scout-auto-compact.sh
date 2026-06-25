#!/usr/bin/env bash
# pre-next-scout-auto-compact.sh — PreToolUse(Skill) hook.
#
# **De-facto DEDUP FALLBACK at the ticket boundary** (v7 redesign — Option B;
# original design intent was "primary", see note below). Fires at PreToolUse
# when the autopilot orchestrator is about to invoke `/scout` for the NEXT
# ticket (i.e. at least one prior ticket already has `steps.ship: completed`).
# In practice this hook almost always SKIPS: the post-ship state-write trigger
# (post-ship-state-auto-compact.sh) fires earlier in the same boundary, injects
# the `/compact`, and writes `.auto-compact-last-attempt` BEFORE the next
# `/scout` is ever invoked — so this hook's Gate 5 (shipped_count unchanged
# within 300s) finds the boundary already handled and short-circuits. Field
# evidence (7-ticket run): 7/7 auto_compact_inject entries were stop_reason
# "safety_net", 0/7 were "primary". Together the two hooks still yield exactly
# one /compact at the end of each ticket loop — exactly the cadence the user
# asked for — but the state-write hook is the one that injects it.
#
# Why this replaces the v6 `PostToolUse(Skill:simple-workflow:ship)` design:
# `PostToolUse(Skill)` fires when the Skill tool is **invoked** (the
# launching tool_result comes back ~50ms later), NOT when the skill body
# completes its work. Field evidence from test_simple_workflow23:
#   - T-001 ship #1 (10:03:33): model state-LIED (wrote ship: completed
#     before any git commit), end_turned, /compact fired but on bogus state
#   - T-002 ship (10:22:56): model recognised the trap and DEFIED the
#     hook's additionalContext — executed full ship body inline, never
#     end_turned for /compact → no auto-compact between tickets
#   - T-003 ship (10:40:25): same defiance pattern
# Root cause / design caveat: there is no "skill completed" hook event in
# Claude Code's model, so this hook hangs the boundary signal on the NEXT
# `Skill(simple-workflow:scout)` invocation. But the brief-level state write
# (`steps.ship: completed`) UNAMBIGUOUSLY PRECEDES that next /scout — which is
# exactly why the post-ship-state PostToolUse(Write|Edit) hook fires first and
# becomes the de-facto primary injection point. By the time this PreToolUse
# next-scout signal arrives (after the compact/resume cycle), the boundary is
# already handled and Gate 5 short-circuits. PreToolUse on next-scout is
# retained as a dedup-coordinated FALLBACK that also covers any future
# autopilot reorder, not as the primary trigger.
#
# Kill-switch (DEFAULT ON within autopilot context, shared with
# post-ship-state-auto-compact.sh):
#   SW_AUTO_COMPACT_ON_SHIP_MODE unset (in autopilot) -> on (default)
#   SW_AUTO_COMPACT_ON_SHIP_MODE=on                   -> inject /compact
#   SW_AUTO_COMPACT_ON_SHIP_MODE=metric-only          -> log only, no injection
#   SW_AUTO_COMPACT_ON_SHIP_MODE=off                  -> disabled (opt-out)
# The env-var name is retained from v6 to preserve user opt-out muscle
# memory; the underlying trigger semantics are different but the user-
# facing knob is the same.
#
# **Parallel stand-down (T-006):** under `parallel_mode != off` (resolved
# via `resolve_parallel_mode`, Gate 2.5) this hook STANDS DOWN — a whole
# wave drains together and `/scout` runs inside the executor, so
# `post-ship-state-auto-compact.sh` (which re-keys to the `wave_status:
# drained` transition) is the SOLE wave-trigger. `parallel_mode=on` exits
# 0 immediately; `metric-only` logs "would stand down" and falls through;
# `off` (default) keeps the existing serial path byte-identical.
#
# Queue-drain coordination (Sentinel + Stop hook yield + SessionStart resume):
# Identical to the v6 design — only the trigger event moves. On successful
# inject: touch `<state_dir>/.auto-compact-pending` (UNIX timestamp).
# `hooks/autopilot-continue.sh` (Stop hook) sees the fresh sentinel, deletes
# it, exits 0 to release the Stop tick so Claude Code's input loop can
# consume the queued `/compact`. After compaction `hooks/session-start.sh`
# PTY-injects `/autopilot {parent_slug}` on the rehydrated session and the
# resume contract (skills/autopilot/SKILL.md:180) picks up from
# autopilot-state.yaml. Stale sentinels (>120s) are deleted and ignored so a
# never-arrived inject cannot freeze the pipeline.
#
# Failure modes (unsupported terminal, jq missing, injection error,
# missing autopilot-state.yaml) are silent no-ops; this hook MUST never
# block /scout regardless of internal failures. PreToolUse hooks that
# return non-zero would prevent the underlying tool call from running,
# breaking autopilot's pipeline progression.

set -euo pipefail

# jq is required for input parse + final hookSpecificOutput emit.
# Silent skip if missing — /scout must never be blocked by this hook.
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/parse-state-file.sh"
source "$SCRIPT_DIR/lib/inject-keys.sh"
# M4 fix: source runtime-metrics so the inject-success branch can record
# an `auto_compact_inject` boundary in autopilot-state.yaml — provides
# the user a forensic audit trail of when /compact actually fired.
source "$SCRIPT_DIR/lib/runtime-metrics.sh"

# Gate 1: skill name match (cheap, no I/O beyond jq).
SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")
[ "$SKILL_NAME" = "simple-workflow:scout" ] || exit 0

# Gate 2: autopilot context. Outside an autopilot pipeline, /scout
# invocations are ad-hoc and must not trigger auto-compact.
is_autopilot_context || exit 0

# Gate 2.5 (T-006 parallel stand-down — Peer-Set Uniformity / Gate 10):
# Under parallel execution a whole wave of N tickets drains together and
# `/scout` runs INSIDE the executor, so this PreToolUse(Skill:scout) hook
# never fires on the main transcript at all. To make `post-ship` the SOLE
# wave-trigger (the 2-peer auto-compact set adopts one consistent posture),
# this hook STANDS DOWN under `parallel_mode != off`. Every parallel
# addition is gated behind `!= off` so the serial path is byte-identical:
# with `parallel_mode` absent/off NO new stderr line is emitted and the
# existing Gate 3 → Gate 5 path runs verbatim.
#
# The state file is resolved here only to read `parallel_mode:`; the
# existing Gate 4 re-resolves it for the serial path, so this lookup does
# not perturb the off path. `resolve_parallel_mode` returns `off` for a
# missing/unreadable state file (fail-closed), preserving byte-identity.
PNS_PARALLEL_STATE_FILE="$(find_any_autopilot_state_file 2>/dev/null || true)"
PARALLEL_MODE="$(resolve_parallel_mode "$PNS_PARALLEL_STATE_FILE")"
if [ "$PARALLEL_MODE" != "off" ]; then
  if [ "$PARALLEL_MODE" = "metric-only" ]; then
    echo "[PRE-NEXT-SCOUT-AUTO-COMPACT] metric-only parallel: would stand down (post-ship is the sole wave-trigger); falling through to serial path" >&2
  else
    echo "[PRE-NEXT-SCOUT-AUTO-COMPACT] parallel stand-down: post-ship-state-auto-compact.sh is the sole wave-trigger under parallel_mode=on. Skipping." >&2
    exit 0
  fi
fi
unset PNS_PARALLEL_STATE_FILE

# Gate 3: kill-switch resolution. Default `on` inside autopilot context.
MODE="${SW_AUTO_COMPACT_ON_SHIP_MODE:-on}"
case "$MODE" in
  on|metric-only) ;;
  off|*)          exit 0 ;;
esac

# Gate 4: ticket-boundary detection. Fire only when this `/scout` is the
# START of a NON-FIRST ticket — i.e. at least one earlier ticket already
# has `steps.ship: completed` in autopilot-state.yaml. For the very first
# ticket of a pipeline the previous-ship marker is absent by definition,
# so we MUST NOT fire (there is no context to compact).
#
# Detection: count tickets where ship has reached completed status via
# `parse_ticket_ship_dirs` (yq → python3+PyYAML → POSIX awk; tolerates
# both the canonical-flat `steps.ship: completed` and the nested
# `steps.ship.status: completed` forms — see WI-3 / parse-state-file.sh
# docstring). Pre-WI-3 this hook used a literal grep anchor that ONLY
# matched the flat form, so when the autopilot orchestrator wrote the
# nested form (test_simple_workflow27 evidence) the counter stayed at 0
# and the hook silently exited even though tickets had genuinely
# shipped.
STATE_FILE_PATH="$(find_any_autopilot_state_file 2>/dev/null || true)"
if [ -z "$STATE_FILE_PATH" ] || [ ! -f "$STATE_FILE_PATH" ]; then
  exit 0
fi
SHIPPED_COUNT=$(parse_ticket_ship_dirs "$STATE_FILE_PATH" 2>/dev/null | grep -c . || true)
SHIPPED_COUNT="${SHIPPED_COUNT:-0}"
if ! [ "$SHIPPED_COUNT" -ge 1 ] 2>/dev/null; then
  # First-ticket scout — do nothing.
  exit 0
fi

# metric-only branch: log + emit additionalContext, no injection.
if [ "$MODE" = "metric-only" ]; then
  echo "[PRE-NEXT-SCOUT-AUTO-COMPACT] metric-only: would inject /compact (shipped_count=$SHIPPED_COUNT)" >&2
  jq -n --arg cnt "$SHIPPED_COUNT" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("auto-compact-on-ship: metric-only mode (no injection). shipped_count=" + $cnt)}}'
  exit 0
fi

# Gate 5: state-consistency check (compact-loop prevention). Same shape as
# the v6 Gate 4 — if a previous compact attempt left the shipped-ticket
# count unchanged within the last 300s, refuse to inject again. Marker
# file `.auto-compact-last-attempt` lives next to autopilot-state.yaml in
# the format `{shipped_count}:{unix_timestamp}`.
LOOP_GATE_ATTEMPT_FILE="$(dirname "$STATE_FILE_PATH")/.auto-compact-last-attempt"
if [ -f "$LOOP_GATE_ATTEMPT_FILE" ]; then
  LOOP_GATE_PREV_LINE=$(cat "$LOOP_GATE_ATTEMPT_FILE" 2>/dev/null || echo "")
  LOOP_GATE_PREV_COUNT="${LOOP_GATE_PREV_LINE%%:*}"
  LOOP_GATE_PREV_TS="${LOOP_GATE_PREV_LINE##*:}"
  LOOP_GATE_NOW_TS=$(date +%s)
  if [ -n "$LOOP_GATE_PREV_COUNT" ] && [ -n "$LOOP_GATE_PREV_TS" ] \
     && [ "$LOOP_GATE_PREV_TS" -gt 0 ] 2>/dev/null \
     && [ "$LOOP_GATE_PREV_COUNT" = "$SHIPPED_COUNT" ]; then
    LOOP_GATE_AGE=$((LOOP_GATE_NOW_TS - LOOP_GATE_PREV_TS))
    if [ "$LOOP_GATE_AGE" -ge 0 ] && [ "$LOOP_GATE_AGE" -le 300 ]; then
      echo "[PRE-NEXT-SCOUT-AUTO-COMPACT] state-check: compact-loop suspected — shipped_count=${SHIPPED_COUNT} unchanged since previous attempt ${LOOP_GATE_AGE}s ago. Skipping inject." >&2
      jq -n --arg cnt "$SHIPPED_COUNT" --arg age "$LOOP_GATE_AGE" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("auto-compact-on-ship: loop suspected — shipped_count (" + $cnt + ") unchanged since previous compact " + $age + "s ago. Skipping inject. The pipeline can still proceed; user may run /compact manually if context pressure is high.")}}'
      exit 0
    fi
  fi
fi
echo "${SHIPPED_COUNT}:$(date +%s)" > "$LOOP_GATE_ATTEMPT_FILE" 2>/dev/null || true

# Inject /compact via dispatcher (best-effort, never block /scout).
# H9: capture inject_keys stderr so the failure path can render a
# disambiguating hint instead of the misleading "unsupported terminal"
# blanket message.
#
# P2-1: create `<state_dir>/.next-compact-pending` sentinel BEFORE the
# inject call so `hooks/session-start.sh` can detect a likely-silent
# failure on the next session boot and retry the `/compact` injection.
# The sentinel is deleted only on confirmed success (INJECT_RC == 0
# after the P1-1 verify); on rc=1 the sentinel is RETAINED so session-
# start can replay the inject from a fresh context. The sentinel is
# distinct from `.auto-compact-pending` (Stop hook yield signal): both
# can coexist on different code paths but not simultaneously on the
# success path (verify success deletes the next-compact sentinel and
# keeps only `.auto-compact-pending`).
NEXT_COMPACT_SENTINEL="$(dirname "$STATE_FILE_PATH")/.next-compact-pending"
date +%s > "$NEXT_COMPACT_SENTINEL" 2>/dev/null || true

INJECT_TMP=$(mktemp 2>/dev/null) || INJECT_TMP=""
INJECT_RC=0
INJECT_LOG=""
if [ -n "$INJECT_TMP" ]; then
  # `|| INJECT_RC=$?` keeps set -e from tripping when the dispatcher
  # returns non-zero (no backend / backend failed); the failure-path
  # branch below needs to observe rc != 0, not abort the hook.
  inject_keys '/compact' --enter 2>"$INJECT_TMP" || INJECT_RC=$?
  INJECT_LOG=$(cat "$INJECT_TMP" 2>/dev/null || echo "")
  rm -f "$INJECT_TMP" 2>/dev/null
  printf '%s\n' "$INJECT_LOG" | sed 's/^/[PRE-NEXT-SCOUT-AUTO-COMPACT] /' >&2
else
  # mktemp fallback path — pipe through sed so we still get the log line
  # in hook stderr, accept that INJECT_LOG stays empty so the hint helper
  # falls back to the unknown-cause branch.
  inject_keys '/compact' --enter 2>&1 | sed 's/^/[PRE-NEXT-SCOUT-AUTO-COMPACT] /' >&2 || true
  INJECT_RC=${PIPESTATUS[0]}
fi

if [ "$INJECT_RC" = "0" ]; then
  # P2-1: P1-1 verify succeeded -> sentinel role discharged, delete it.
  rm -f "$NEXT_COMPACT_SENTINEL" 2>/dev/null || true
  SENTINEL="$(dirname "$STATE_FILE_PATH")/.auto-compact-pending"
  date +%s > "$SENTINEL" 2>/dev/null || true
  # M4: audit trail. Record one runtime_metrics entry per successful
  # injection so the user can correlate /compact fires with state
  # transitions (e.g. forensics after an unexpected context loss).
  # Uses the shared append helper from hooks/lib/runtime-metrics.sh.
  _AC_ISO_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  # shipped_count goes to arg9 (the dedicated field), NOT arg8
  # (consecutive_stop_blocks, which is meaningful only for session_end) — the
  # latter is passed "null" here so this auto_compact_inject entry no longer
  # pollutes consecutive_stop_blocks. stop_reason stays "primary" so a rare
  # real fire from this hook is still distinguishable from the safety-net path.
  append_runtime_metrics_entry "$STATE_FILE_PATH" "auto_compact_inject" "primary" "$_AC_ISO_TS" "null" "null" "null" "null" "$SHIPPED_COUNT" 2>/dev/null || true
  unset _AC_ISO_TS
  # additionalContext: tell the model to end the turn NOW so Claude Code's
  # input loop consumes the queued `/compact`. The autopilot orchestrator
  # is about to invoke `/scout` for the next ticket; we want it to defer
  # that invocation until after compaction. After compact the session-start
  # PTY-injects `/autopilot {parent_slug}`, which re-enters the orchestrator
  # and re-issues `/scout` for the same next ticket from a fresh context.
  #
  # No `state update first` two-step is needed here (unlike the v6
  # PostToolUse(Skill:ship) design) — by the time this hook fires, the
  # autopilot orchestrator has ALREADY written `steps.ship = completed`
  # for the just-finished ticket (the ticket-boundary precondition).
  # Skipping the scout invocation is the single instruction the model
  # needs to honour.
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"auto-compact-on-ship (ticket-boundary): `/compact` has been queued. The previous ticket'"'"'s full pipeline (scout → impl → audit → ship → tune) has completed and its `steps.ship = completed` is already in autopilot-state.yaml. To let the queued /compact drain, end this turn now WITHOUT invoking the next /scout. Do NOT print a summary, do NOT issue any further tool call. After compaction, hooks/session-start.sh will PTY-inject `/autopilot {parent-slug}` on the rehydrated session and the resume contract (skills/autopilot/SKILL.md:180) will re-issue this same /scout from a fresh context."}}'
else
  # P2-1: inject verify failed (rc=1) -> RETAIN .next-compact-pending so
  # hooks/session-start.sh can replay the `/compact` injection on the
  # next session boot. This closes the "verify window false-negative"
  # gap from test 33 (P1-1 verify can miss true silent failures where
  # capture-pane sees the echo but the TUI input loop discards the
  # keystroke at turn-end).
  echo "[PRE-NEXT-SCOUT-AUTO-COMPACT] retaining .next-compact-pending for session-start retry (INJECT_RC=$INJECT_RC)" >&2
  INJECT_HINT=$(inject_keys_failure_hint "$INJECT_LOG")
  jq -n --arg hint "$INJECT_HINT" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("auto-compact-on-ship: injection failed — " + $hint + ". A retry will be attempted on the next session start (sentinel `.next-compact-pending` retained). /scout will proceed without compaction for now. User may run /compact manually.")}}'
fi
exit 0
