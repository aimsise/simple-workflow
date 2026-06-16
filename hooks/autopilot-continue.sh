#!/usr/bin/env bash
# autopilot-continue.sh — Stop hook: prevent premature end_turn during /autopilot pipeline
#
# When Claude issues end_turn while an autopilot pipeline has unfinished steps,
# this hook returns decision:"block" to force continuation.
#
# Allow stop (exit 0) when:
#   - No autopilot-state.yaml found (not in a pipeline)
#   - All tickets completed/failed/skipped (pipeline finished)
#   - Loop guard triggered (>= 5 consecutive blocks without state progress)
#
# Block stop (decision:"block") when:
#   - Active pipeline with in_progress or pending steps remaining
#
# On every session_end exit (any path that allows end_turn while a state file
# exists) the hook appends a runtime_metrics entry to that state file. The
# entry's `stop_reason` follows the discrimination heuristic documented in
# `skills/autopilot/references/stop-reason-taxonomy.md`. PreCompact-boundary
# entries are written by `hooks/pre-compact-save.sh`, never by this hook.

set -euo pipefail

# Read stdin JSON payload (may be empty)
INPUT=$(cat 2>/dev/null || echo '{}')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# `append_runtime_metrics_entry` is defined in hooks/lib/runtime-metrics.sh.
source "$SCRIPT_DIR/lib/runtime-metrics.sh"
# `last_turn_declares_policy_gate_stop` is defined in
# hooks/lib/detect-policy-gate-stop.sh (single source of truth for the
# model-declared policy-gate-stop marker — see AC-6 / the helper header).
source "$SCRIPT_DIR/lib/detect-policy-gate-stop.sh"
# `parse_active_steps` is defined in hooks/lib/parse-state-file.sh — the WI-3
# schema-tolerant (flat / inline-flow / nested) step parser the continuation
# driver below uses to count unfinished steps and pick the next one.
source "$SCRIPT_DIR/lib/parse-state-file.sh"

# `_runtime_metrics_payload_field` is currently duplicated in
# hooks/pre-compact-save.sh as `_pc_runtime_metrics_payload_field`. Both
# copies close over the hook-script-local `$INPUT` variable; sharing
# would require passing `$INPUT` as a function argument and lifting the
# helper into hooks/lib/. The duplication is kept inline as a
# trade-off — the helper is 14 lines and the consolidation would only
# remove one copy at the cost of an extra parameter on every call site.
# Any change to the jq invocation MUST be applied to both copies in
# lock-step until / unless the helper is consolidated.
_runtime_metrics_payload_field() {
  # $1 = field name, prints int or "null"
  local field="$1"
  local payload="${INPUT:-}"
  if [ -z "$payload" ]; then
    payload='{}'
  fi
  local value
  value=$(printf '%s' "$payload" | jq -r --arg f "$field" '.[$f] // "null"' 2>/dev/null) || value="null"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    printf 'null'
  else
    printf '%s' "$value"
  fi
}

_emit_session_end_metrics() {
  # $1 stop_reason, $2 consecutive_stop ("null" or int)
  local stop_reason="$1"
  local consecutive="${2:-null}"
  if [ -n "${STATE_FILE:-}" ] && [ -f "${STATE_FILE:-}" ]; then
    local timestamp cache_creation cache_read input_tokens
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
    cache_creation=$(_runtime_metrics_payload_field cache_creation_input_tokens)
    cache_read=$(_runtime_metrics_payload_field cache_read_input_tokens)
    input_tokens=$(_runtime_metrics_payload_field input_tokens)
    append_runtime_metrics_entry "$STATE_FILE" "session_end" "$stop_reason" "$timestamp" \
      "$cache_creation" "$cache_read" "$input_tokens" "$consecutive"
  fi
}

# --- Find autopilot-state.yaml (moved up so loop-guard exits can write metrics) ---
# Depth-agnostic scan: the flat layout is
# `.simple-workflow/backlog/briefs/active/{slug}/autopilot-state.yaml` (one
# level under briefs/active/), but nested layouts such as
# `.simple-workflow/backlog/briefs/active/{parent-slug}/{slug}/autopilot-state.yaml`
# are also valid. Use `find` with no -maxdepth so all depths are discovered.
# sort -u guarantees deterministic ordering and dedupes on any rare case
# where the same file is reachable through two paths.
STATE_FILE=""
if [ -d .simple-workflow/backlog/briefs/active ]; then
  while IFS= read -r _f; do
    if [ -f "$_f" ]; then
      STATE_FILE="$_f"
      break
    fi
  done < <(find .simple-workflow/backlog/briefs/active -type f -name 'autopilot-state.yaml' 2>/dev/null | sort -u)
  unset _f
fi
if [ -z "$STATE_FILE" ] && [ -d .simple-workflow/backlog/product_backlog ]; then
  while IFS= read -r _f; do
    if [ -f "$_f" ]; then
      STATE_FILE="$_f"
      break
    fi
  done < <(find .simple-workflow/backlog/product_backlog -type f -name 'autopilot-state.yaml' 2>/dev/null | sort -u)
  unset _f
fi
# PX-03: terminal Stop hook fallback. After /ship's Split State File Cleanup
# moves the brief to briefs/done/, the same-turn Stop hook would otherwise
# fail to discover the state file and skip the runtime_metrics emit. Adding
# briefs/done/ as the third lookup root closes that race window. The order
# is intentional — briefs/active/ and product_backlog/ MUST be checked first
# so that an unrelated parent_slug already moved to briefs/done/ never
# shadows an active run. NAC #7 protection: when the candidate state file
# lives in briefs/done/, refuse to adopt it unless every step has reached
# `completed`; this prevents a premature partial_completion emit against a
# half-finished run that was prematurely moved.
if [ -z "$STATE_FILE" ] && [ -d .simple-workflow/backlog/briefs/done ]; then
  while IFS= read -r _f; do
    if [ -f "$_f" ]; then
      # All step-level entries must be `completed`. Any in_progress or
      # pending step disqualifies the file (NAC #7 / AC #3 (d)).
      if grep -qE '(create-ticket|scout|impl|ship): (in_progress|pending)' "$_f" 2>/dev/null; then
        continue
      fi
      STATE_FILE="$_f"
      break
    fi
  done < <(find .simple-workflow/backlog/briefs/done -type f -name 'autopilot-state.yaml' 2>/dev/null | sort -u)
  unset _f
fi

# --- Auto-compact sentinel: yield Stop tick so queued /compact can run ---
# `hooks/post-ship-auto-compact.sh` touches <state_dir>/.auto-compact-pending
# with a UNIX timestamp on every successful PTY injection of `/compact`.
# Without this check, the continuation prompt below would re-arm the
# conversation immediately and the queued `/compact` would sit unprocessed
# forever (observed in test_simple_workflow19: two enqueues, zero
# pre-compact-save snapshots). When the sentinel is fresh (<=120s old),
# delete it and exit 0 — Claude Code's idle loop will then consume the
# queued `/compact`. PreCompact fires → `pre-compact-save.sh` writes the
# `boundary: session_compaction` snapshot → on the rehydrated session the
# resume contract (`skills/autopilot/SKILL.md:180`) picks up via
# autopilot-state.yaml. Stale sentinels (>120s) are deleted and ignored
# so a never-arrived `/compact` cannot freeze the pipeline.
if [ -n "$STATE_FILE" ]; then
  SENTINEL_DIR="$(dirname "$STATE_FILE")"
  SENTINEL_FILE="$SENTINEL_DIR/.auto-compact-pending"
  if [ -f "$SENTINEL_FILE" ]; then
    SENTINEL_TS=$(cat "$SENTINEL_FILE" 2>/dev/null || echo 0)
    NOW_TS=$(date +%s)
    SENTINEL_AGE=$((NOW_TS - SENTINEL_TS))
    # H6 fix: defer the rm until after the freshness decision is made
    # AND about to be acted on. The previous order rm'd unconditionally
    # before the age check, which (a) discarded observability if a
    # never-arrived /compact left a stale sentinel that we'd otherwise
    # want to log + investigate, and (b) left a brief race window where
    # a `cat` failure (e.g. permission flap mid-read) would coerce
    # SENTINEL_TS to 0, mark the sentinel stale, and then delete it —
    # discarding a real fresh sentinel.
    if [ "$SENTINEL_AGE" -ge 0 ] && [ "$SENTINEL_AGE" -le 120 ]; then
      rm -f "$SENTINEL_FILE"
      # P2-1: yield = `/compact` is about to drain. The session-start
      # retry sentinel (`.next-compact-pending`) was placed by the
      # upstream auto-compact hook before the inject_keys call and
      # would normally be deleted only on verify success. Yield via
      # `.auto-compact-pending` is proof that the inject did fire and
      # the TUI is about to consume it, so the retry role is also
      # discharged here — co-delete to prevent a duplicate `/compact`
      # being injected by session-start.sh after the rehydrated
      # session boots.
      rm -f "$SENTINEL_DIR/.next-compact-pending" 2>/dev/null || true
      echo "[AUTO-COMPACT-YIELD] sentinel found (age=${SENTINEL_AGE}s); yielding Stop tick so queued /compact can drain. autopilot will resume after compaction via state file." >&2
      _emit_session_end_metrics "auto_compact_yield" "null"
      exit 0
    else
      rm -f "$SENTINEL_FILE"
      echo "[AUTO-COMPACT-YIELD] stale sentinel (age=${SENTINEL_AGE}s, >120s); treating as orphaned and continuing autopilot normally." >&2
    fi
  fi
fi

# --- Loop guard: environment variable override (for tests / manual override) ---
CONTINUE_COUNT="${_AUTOPILOT_CONTINUE_COUNT:-0}"
if [ "$CONTINUE_COUNT" -ge 5 ] 2>/dev/null; then
  echo "[AUTOPILOT-STALL] env-var loop guard released after $CONTINUE_COUNT consecutive blocks" >&2
  echo "[AUTOPILOT-STALL] env-var loop guard released after $CONTINUE_COUNT consecutive blocks. Resume with: /autopilot {parent-slug}"
  _emit_session_end_metrics "loop_guard_release" "$CONTINUE_COUNT"
  exit 0
fi

if [ -z "$STATE_FILE" ]; then
  # --- No autopilot-state.yaml: check for auto-kick.yaml (brief → create-ticket → autopilot chain) ---
  # auto-kick.yaml is written by /brief on "yes" confirmation and deleted by /autopilot Phase 1.
  # Its presence means the auto-chain is between /brief and /autopilot, so we must block end_turn
  # until /autopilot starts and removes the file.
  AUTOKICK_FILE=""
  if [ -d .simple-workflow/backlog/briefs/active ]; then
    while IFS= read -r _f; do
      if [ -f "$_f" ]; then
        AUTOKICK_FILE="$_f"
        break
      fi
    done < <(find .simple-workflow/backlog/briefs/active -type f -name 'auto-kick.yaml' 2>/dev/null | sort -u)
    unset _f
  fi

  if [ -z "$AUTOKICK_FILE" ]; then
    # Neither autopilot-state.yaml nor auto-kick.yaml → not in any pipeline
    exit 0
  fi

  # Extract slug from auto-kick.yaml (top-level `slug:` key)
  AUTOKICK_SLUG=$({ grep -E '^slug:' "$AUTOKICK_FILE" 2>/dev/null || true; } | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
  AUTOKICK_SLUG="${AUTOKICK_SLUG:-unknown}"

  # Independent file-based loop guard (separate from the autopilot-state counter)
  AUTOKICK_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
  AUTOKICK_COUNTER_FILE="/tmp/.autokick-continue-${AUTOKICK_SESSION_ID}"
  AUTOKICK_COUNT=0

  if [ "$AUTOKICK_SESSION_ID" != "unknown" ] && [ -f "$AUTOKICK_COUNTER_FILE" ]; then
    AUTOKICK_COUNT=$(cat "$AUTOKICK_COUNTER_FILE" 2>/dev/null || echo "0")
    # Reset counter if auto-kick.yaml is newer than the counter (progress / fresh write)
    if [ "$AUTOKICK_FILE" -nt "$AUTOKICK_COUNTER_FILE" ]; then
      AUTOKICK_COUNT=0
    fi
  fi

  if [ "$AUTOKICK_COUNT" -ge 5 ]; then
    exit 0
  fi

  # Determine whether the upstream /create-ticket already produced split-plan.md
  AUTOKICK_SPLIT_PLAN=".simple-workflow/backlog/product_backlog/${AUTOKICK_SLUG}/split-plan.md"

  # Increment counter
  AUTOKICK_COUNT=$((AUTOKICK_COUNT + 1))
  if [ "$AUTOKICK_SESSION_ID" != "unknown" ]; then
    echo "$AUTOKICK_COUNT" > "$AUTOKICK_COUNTER_FILE"
  fi

  if [ -f "$AUTOKICK_SPLIT_PLAN" ]; then
    # split-plan exists → /create-ticket already ran. Next step is /autopilot.
    # reason MUST contain: /autopilot, {slug}, Skill tool
    # reason MUST NOT contain: /create-ticket
    jq -n \
      --arg slug "$AUTOKICK_SLUG" \
      --arg autokick_path "$AUTOKICK_FILE" \
      '{
        decision: "block",
        reason: ("auto-kick.yaml detected at " + $autokick_path + " (slug: " + $slug + ") and the upstream split-plan.md is already in place. Invoke /autopilot " + $slug + " via the Skill tool now to continue the auto-chain. Do NOT end your turn or summarize.")
      }'
  else
    # split-plan absent → /create-ticket has not yet produced the ticket set.
    # reason MUST contain: /create-ticket, /autopilot, {slug}, Skill tool
    # /create-ticket MUST NOT appear at the start of any line in reason.
    jq -n \
      --arg slug "$AUTOKICK_SLUG" \
      --arg autokick_path "$AUTOKICK_FILE" \
      '{
        decision: "block",
        reason: ("auto-kick.yaml detected at " + $autokick_path + " (slug: " + $slug + "). The auto-chain requires you to run /create-ticket first to produce .simple-workflow/backlog/product_backlog/" + $slug + "/split-plan.md, and then run /autopilot " + $slug + " via the Skill tool. Do NOT end your turn or summarize.")
      }'
  fi
  exit 0
fi

# --- File-based loop guard (keyed to session) ---
# `FILE_COUNT` (a.k.a. `MTIME_COUNT` in Plan 02 terminology) tracks consecutive
# Stop-hook block decisions in which `STATE_FILE` mtime did NOT advance. The
# pre-Plan-02 release rule was `FILE_COUNT >= 5` — that threshold is unchanged.
# Reset condition is also unchanged: `STATE_FILE -nt COUNTER_FILE`. Plan 02
# layers a SECOND counter (`NOTOOL_COUNT`) on top and AND-combines the two,
# so a release fires only when BOTH the state file is stuck AND the model has
# made N consecutive turns without invoking a real tool.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
COUNTER_FILE="/tmp/.autopilot-continue-${SESSION_ID}"
FILE_COUNT=0

# Extract TRANSCRIPT_PATH up-front (used by both the NOTOOL block below and
# the policy-gate-stop honour gate). Hoisted out of the legacy-conditional
# `else` branch so the honour gate works regardless of
# AUTOPILOT_LEGACY_LOOPGUARD.
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

if [ "$SESSION_ID" != "unknown" ] && [ -f "$COUNTER_FILE" ]; then
  FILE_COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  # Reset counter if state file was modified since last block (progress was made)
  if [ "$STATE_FILE" -nt "$COUNTER_FILE" ]; then
    FILE_COUNT=0
  fi
fi

# --- NOTOOL_COUNT: tool-use absence counter (Plan 02) ---
# A second counter tracks consecutive end_turn attempts in which the most
# recent assistant turn produced ZERO real tool_use blocks. "Real" tools are
# {Skill, Agent, Bash, Edit, Write, NotebookEdit}. `Read` is intentionally
# excluded — pure investigation turns are not progress. The hook reads the
# tail of the JSONL transcript pointed at by `transcript_path` in the stdin
# payload. The kill switch `AUTOPILOT_LEGACY_LOOPGUARD=1` short-circuits this
# logic and forces NOTOOL_COUNT to threshold so FILE_COUNT alone drives the
# release decision (the pre-Plan-02 behaviour).
LEGACY_LOOPGUARD="${AUTOPILOT_LEGACY_LOOPGUARD:-0}"
NOTOOL_THRESHOLD=5
NOTOOL_COUNTER_FILE="/tmp/.autopilot-notool-${SESSION_ID}"
NOTOOL_COUNT=0

if [ "$LEGACY_LOOPGUARD" = "1" ]; then
  # Legacy / pre-Plan-02 mode: bypass tool-use detection and let FILE_COUNT
  # alone gate the release decision.
  NOTOOL_COUNT="$NOTOOL_THRESHOLD"
else
  # TRANSCRIPT_PATH was extracted up-front (above) so the policy-gate-stop
  # honour gate can also use it under AUTOPILOT_LEGACY_LOOPGUARD=1.
  if [ "$SESSION_ID" != "unknown" ] && [ -f "$NOTOOL_COUNTER_FILE" ]; then
    NOTOOL_COUNT=$(cat "$NOTOOL_COUNTER_FILE" 2>/dev/null || echo "0")
    case "$NOTOOL_COUNT" in *[!0-9]*|"") NOTOOL_COUNT=0 ;; esac
  fi

  HAS_TOOL_USE="false"
  TRANSCRIPT_READABLE="false"
  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    TRANSCRIPT_READABLE="true"
    LAST_ASSISTANT_TURN=$(tail -n 50 "$TRANSCRIPT_PATH" 2>/dev/null \
      | grep -E '"role":"assistant"' \
      | tail -1 || true)
    if [ -n "$LAST_ASSISTANT_TURN" ]; then
      if echo "$LAST_ASSISTANT_TURN" | jq -e '
        ((.message.content // .content) // [])
        | (if type=="array" then . else [] end)
        | map(select(
            .type == "tool_use"
            and ((.name // "") | IN("Skill","Agent","Bash","Edit","Write","NotebookEdit"))
          ))
        | length > 0
      ' >/dev/null 2>&1; then
        HAS_TOOL_USE="true"
      fi
    fi
  fi

  if [ "$TRANSCRIPT_READABLE" = "true" ]; then
    if [ "$HAS_TOOL_USE" = "true" ]; then
      NOTOOL_COUNT=0
    else
      NOTOOL_COUNT=$((NOTOOL_COUNT + 1))
    fi
    if [ "$SESSION_ID" != "unknown" ]; then
      echo "$NOTOOL_COUNT" > "$NOTOOL_COUNTER_FILE"
    fi
  else
    # Crash-safety: transcript empty / missing / malformed. Fall back to the
    # pre-Plan-02 behaviour by treating NOTOOL as already-met. Do not persist
    # this synthetic value to the counter file — a future invocation with a
    # readable transcript should start clean.
    NOTOOL_COUNT="$NOTOOL_THRESHOLD"
  fi
fi

# --- Policy-gate-stop honour gate (SW_AUTOPILOT_POLICY_STOP_HONOR) ---
# When the orchestrator model legitimately hard-stops it emits the marker
# `[AUTOPILOT-POLICY] gate=<name> action=stop reason=<...>` in its last
# assistant turn (mandated by skills/autopilot/SKILL.md). Without this gate
# the hook ignores that declaration and keeps re-injecting "Do NOT stop"
# even though the model has correctly stopped (the v6.x dogfood thrash:
# 11 consecutive re-injections). Honour the declaration by allowing the
# stop and recording a session_end / policy_gate_stop runtime_metrics entry.
#
# This gate is PURELY ADDITIVE and sits BEFORE the existing FILE_COUNT /
# NOTOOL_COUNT loop guard and the ACTIVE_STEPS continuation below: with the
# kill switch off OR no marker present, every downstream branch behaves
# exactly as before (the loop guard remains the backstop). The gate calls
# the shared detector directly with $TRANSCRIPT_PATH so it is independent
# of AUTOPILOT_LEGACY_LOOPGUARD.
#
# Kill switch (tri-value; mirrors SW_AUTOPILOT_ASK_GUARD):
#   on (default)  — honour: allow stop, emit policy_gate_stop metric.
#   metric-only   — detect + log `[POLICY-GATE-STOP]` to stderr (would
#                   honour) but STILL fall through to block.
#   off           — ignore entirely.
#   unknown value — fail-closed to `off` semantics (a typo never widens
#                   honour behaviour).
POLICY_STOP_HONOR="${SW_AUTOPILOT_POLICY_STOP_HONOR:-on}"
case "$POLICY_STOP_HONOR" in
  on)
    if last_turn_declares_policy_gate_stop "$TRANSCRIPT_PATH"; then
      echo "[POLICY-GATE-STOP] honouring model-declared policy_gate_stop (last assistant turn emitted [AUTOPILOT-POLICY] ... action=stop); allowing end_turn instead of re-injecting continuation." >&2
      _emit_session_end_metrics "policy_gate_stop" "$FILE_COUNT"
      rm -f "$COUNTER_FILE" 2>/dev/null || true
      rm -f "$NOTOOL_COUNTER_FILE" 2>/dev/null || true
      exit 0
    fi
    ;;
  metric-only)
    if last_turn_declares_policy_gate_stop "$TRANSCRIPT_PATH"; then
      echo "[POLICY-GATE-STOP] metric-only: would honour model-declared policy_gate_stop (last assistant turn emitted [AUTOPILOT-POLICY] ... action=stop); still blocking per SW_AUTOPILOT_POLICY_STOP_HONOR=metric-only." >&2
    fi
    ;;
  off)
    : # honour disabled — fall through to existing logic.
    ;;
  *)
    # Unknown value: fail-closed to `off` semantics (a typo must not widen
    # the honour behaviour).
    :
    ;;
esac

if [ "$FILE_COUNT" -ge 5 ] && [ "$NOTOOL_COUNT" -ge "$NOTOOL_THRESHOLD" ]; then
  echo "[AUTOPILOT-STALL] file-based loop guard released after $FILE_COUNT consecutive blocks" >&2
  echo "[AUTOPILOT-STALL] Pipeline halted: model emitted $NOTOOL_COUNT consecutive end_turn attempts without tool calls or state progress. Resume with: /autopilot {parent-slug}"
  _emit_session_end_metrics "loop_guard_release" "$FILE_COUNT"
  rm -f "$NOTOOL_COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- Check for unfinished steps (WI-3 schema-tolerant) ---
# parse_active_steps (hooks/lib/parse-state-file.sh) emits one `<step>:<status>`
# line per in_progress/pending step across all tickets, tolerating the flat
# (`scout: in_progress`), inline-flow (`steps: {scout: in_progress, …}`), and
# nested (`scout:\n  status: in_progress`) shapes. The prior inline grep matched
# only the flat/flow shapes and silently stranded a nested-form pipeline.
ACTIVE_STEP_LINES=$(parse_active_steps "$STATE_FILE" 2>/dev/null || true)
# grep -c exits 1 (and prints 0) when there are no active steps; guard it.
ACTIVE_STEPS=$(printf '%s' "$ACTIVE_STEP_LINES" | grep -c ':') || ACTIVE_STEPS=0

if [ "$ACTIVE_STEPS" -eq 0 ]; then
  # All step-level work done — pipeline is finished, allow stop.
  # Determine ticket-level pending state for stop_reason discrimination.
  PENDING_TICKETS=$(grep -cE '^[[:space:]]+status:[[:space:]]+(pending|in_progress)' "$STATE_FILE" 2>/dev/null) || PENDING_TICKETS=0
  if [ "$PENDING_TICKETS" -gt 0 ]; then
    _emit_session_end_metrics "partial_completion" "$FILE_COUNT"
  else
    _emit_session_end_metrics "normal_completion" "$FILE_COUNT"
  fi
  rm -f "$COUNTER_FILE" 2>/dev/null || true
  rm -f "$NOTOOL_COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- Determine next step to execute ---
# Priority: first in_progress step, then first pending step. Derived from the
# same WI-3-tolerant parse_active_steps output (`<step>:<status>` lines).
NEXT_STEP=$(printf '%s\n' "$ACTIVE_STEP_LINES" | grep ':in_progress$' | head -1 | sed 's/:in_progress$//') || true
if [ -z "$NEXT_STEP" ]; then
  NEXT_STEP=$(printf '%s\n' "$ACTIVE_STEP_LINES" | grep ':pending$' | head -1 | sed 's/:pending$//') || true
fi
NEXT_STEP="${NEXT_STEP:-unknown}"

# --- Determine ticket_dir for the active ticket ---
TICKET_DIR=$(awk '
  /ticket_dir:/ { dir=$NF }
  /(create-ticket|scout|impl|ship): (in_progress|pending)/ { if (dir != "null") print dir; exit }
' "$STATE_FILE") || true
TICKET_DIR="${TICKET_DIR:-unknown}"

# --- Extract slug from state file path ---
# The "slug" is the full relative path between `briefs/active/` and
# `/autopilot-state.yaml`. For the legacy flat layout this is just the
# single directory name (e.g. `my-slug`); for nested layouts it is the
# composite path (e.g. `parent-slug/my-slug`). Surfacing the full path
# in `reason` means the caller can see which nested brief directory the
# pipeline is parked in without needing a second probe.
SLUG=$(echo "$STATE_FILE" | sed 's|.*/briefs/active/||; s|.*/product_backlog/||; s|/autopilot-state.yaml||')

# --- Increment file-based counter ---
FILE_COUNT=$((FILE_COUNT + 1))
if [ "$SESSION_ID" != "unknown" ]; then
  echo "$FILE_COUNT" > "$COUNTER_FILE"
fi

# --- Read state file for inclusion in reason ---
STATE_CONTENT=$(cat "$STATE_FILE")

# --- Block the stop and inject continuation instruction ---
jq -n \
  --arg next_step "$NEXT_STEP" \
  --arg ticket_dir "$TICKET_DIR" \
  --arg slug "$SLUG" \
  --arg state_path "$STATE_FILE" \
  --arg state_content "$STATE_CONTENT" \
  '{
    decision: "block",
    reason: ("You are in the middle of a /autopilot pipeline (slug: " + $slug + "). Do NOT stop.\n\nThe " + $state_path + " shows unfinished work. The next step to execute is: " + $next_step + " (ticket-dir: " + $ticket_dir + ").\n\nIMPORTANT: Read the autopilot-state.yaml file and continue executing the /autopilot pipeline from where you left off. Update the state file as you complete each step. Follow the CHECKPOINT — RE-ANCHOR instructions from the /autopilot skill.\n\nCurrent pipeline state:\n" + $state_content)
  }'
