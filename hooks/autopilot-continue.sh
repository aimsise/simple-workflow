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

set -euo pipefail

# Read stdin JSON payload (may be empty)
INPUT=$(cat 2>/dev/null || echo '{}')

# --- Loop guard: environment variable override (for tests / manual override) ---
CONTINUE_COUNT="${_AUTOPILOT_CONTINUE_COUNT:-0}"
if [ "$CONTINUE_COUNT" -ge 5 ] 2>/dev/null; then
  exit 0
fi

# --- Find autopilot-state.yaml ---
STATE_FILE=""
for f in .backlog/briefs/active/*/autopilot-state.yaml; do
  if [ -f "$f" ]; then
    STATE_FILE="$f"
    break
  fi
done

if [ -z "$STATE_FILE" ]; then
  exit 0
fi

# --- File-based loop guard (keyed to session) ---
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
COUNTER_FILE="/tmp/.autopilot-continue-${SESSION_ID}"
FILE_COUNT=0

if [ "$SESSION_ID" != "unknown" ] && [ -f "$COUNTER_FILE" ]; then
  FILE_COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  # Reset counter if state file was modified since last block (progress was made)
  if [ "$STATE_FILE" -nt "$COUNTER_FILE" ]; then
    FILE_COUNT=0
  fi
fi

if [ "$FILE_COUNT" -ge 5 ]; then
  exit 0
fi

# --- Check for unfinished steps ---
# Count step-level entries that are in_progress or pending
# Note: grep -c exits 1 when no matches; capture separately to avoid double output
ACTIVE_STEPS=$(grep -cE '(create-ticket|scout|impl|ship): (in_progress|pending)' "$STATE_FILE" 2>/dev/null) || ACTIVE_STEPS=0

if [ "$ACTIVE_STEPS" -eq 0 ]; then
  # All steps done — pipeline is finished, allow stop
  rm -f "$COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- Determine next step to execute ---
# Priority: first in_progress step, then first pending step
NEXT_STEP=$(grep -E '(create-ticket|scout|impl|ship): in_progress' "$STATE_FILE" | head -1 | sed 's/^ *//; s/: in_progress//') || true
if [ -z "$NEXT_STEP" ]; then
  NEXT_STEP=$(grep -E '(create-ticket|scout|impl|ship): pending' "$STATE_FILE" | head -1 | sed 's/^ *//; s/: pending//') || true
fi
NEXT_STEP="${NEXT_STEP:-unknown}"

# --- Determine ticket_dir for the active ticket ---
TICKET_DIR=$(awk '
  /ticket_dir:/ { dir=$NF }
  /(create-ticket|scout|impl|ship): (in_progress|pending)/ { if (dir != "null") print dir; exit }
' "$STATE_FILE") || true
TICKET_DIR="${TICKET_DIR:-unknown}"

# --- Extract slug from state file path ---
SLUG=$(echo "$STATE_FILE" | sed 's|.*/briefs/active/||; s|/autopilot-state.yaml||')

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
