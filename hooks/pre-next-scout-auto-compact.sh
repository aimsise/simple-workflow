#!/usr/bin/env bash
# pre-next-scout-auto-compact.sh — PreToolUse(Skill) hook.
#
# **Primary auto-compact trigger** (v7 redesign — Option B). Fires at the
# **ticket boundary**: when the autopilot orchestrator is about to invoke
# `/scout` for the NEXT ticket (i.e. at least one prior ticket already has
# `steps.ship: completed`). At that moment the previous ticket's full
# pipeline (scout → impl → audit → ship → tune) has finished and the model
# is about to start a fresh ticket — exactly the cadence the user asked
# for ("one /compact at the end of each ticket loop").
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
# Root cause: there is no "skill completed" hook event in Claude Code's
# model. The skill body runs as subsequent model turns invoking Bash/Edit/
# Read/etc. By contrast, by the time the orchestrator emits the NEXT
# `Skill(simple-workflow:scout)` call, every prior step (commit, move to
# done/, tune body, brief-level state write) has unambiguously completed.
# PreToolUse on that next-scout invocation is the cleanest ticket-boundary
# signal the hook surface provides.
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

# Gate 1: skill name match (cheap, no I/O beyond jq).
SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")
[ "$SKILL_NAME" = "simple-workflow:scout" ] || exit 0

# Gate 2: autopilot context. Outside an autopilot pipeline, /scout
# invocations are ad-hoc and must not trigger auto-compact.
is_autopilot_context || exit 0

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
# Detection uses a simple grep over the brief-level state file. The
# `steps:` block lives at 4-space indent inside each `tickets[]` element,
# and the canonical autopilot orchestrator writes `      ship: completed`
# (6-space indent) when it advances the just-shipped ticket. Counting
# those lines tells us how many tickets have already shipped; anything
# >= 1 means this `/scout` is for ticket 2+.
STATE_FILE_PATH="$(find_any_autopilot_state_file 2>/dev/null || true)"
if [ -z "$STATE_FILE_PATH" ] || [ ! -f "$STATE_FILE_PATH" ]; then
  exit 0
fi
# `grep -c` returns 1 on zero matches; guard with `|| true` under set -e
# and never chain `|| echo 0` (would double-emit "0\n0").
SHIPPED_COUNT=$(grep -cE '^[[:space:]]+ship:[[:space:]]+completed' "$STATE_FILE_PATH" 2>/dev/null || true)
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
if inject_keys '/compact' --enter 2>&1 | sed 's/^/[PRE-NEXT-SCOUT-AUTO-COMPACT] /' >&2; then
  SENTINEL="$(dirname "$STATE_FILE_PATH")/.auto-compact-pending"
  date +%s > "$SENTINEL" 2>/dev/null || true
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
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"auto-compact-on-ship: injection failed (unsupported terminal); /scout will proceed without compaction. User may run /compact manually."}}'
fi
exit 0
