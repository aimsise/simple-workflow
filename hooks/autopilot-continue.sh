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
# Depth-agnostic scan: the legacy layout is
# `.backlog/briefs/active/{slug}/autopilot-state.yaml` (one level under
# briefs/active/), but nested layouts such as
# `.backlog/briefs/active/{parent-slug}/{slug}/autopilot-state.yaml` are
# also valid. Use `find` with no -maxdepth so all depths are discovered.
# sort -u guarantees deterministic ordering and dedupes on any rare case
# where the same file is reachable through two paths.
STATE_FILE=""
if [ -d .backlog/briefs/active ]; then
  while IFS= read -r _f; do
    if [ -f "$_f" ]; then
      STATE_FILE="$_f"
      break
    fi
  done < <(find .backlog/briefs/active -type f -name 'autopilot-state.yaml' 2>/dev/null | sort -u)
  unset _f
fi

if [ -z "$STATE_FILE" ]; then
  # --- No autopilot-state.yaml: check for auto-kick.yaml (brief → create-ticket → autopilot chain) ---
  # auto-kick.yaml is written by /brief on "yes" confirmation and deleted by /autopilot Phase 1.
  # Its presence means the auto-chain is between /brief and /autopilot, so we must block end_turn
  # until /autopilot starts and removes the file.
  AUTOKICK_FILE=""
  if [ -d .backlog/briefs/active ]; then
    while IFS= read -r _f; do
      if [ -f "$_f" ]; then
        AUTOKICK_FILE="$_f"
        break
      fi
    done < <(find .backlog/briefs/active -type f -name 'auto-kick.yaml' 2>/dev/null | sort -u)
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
  AUTOKICK_SPLIT_PLAN=".backlog/product_backlog/${AUTOKICK_SLUG}/split-plan.md"

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
        reason: ("auto-kick.yaml detected at " + $autokick_path + " (slug: " + $slug + "). The auto-chain requires you to run /create-ticket first to produce .backlog/product_backlog/" + $slug + "/split-plan.md, and then run /autopilot " + $slug + " via the Skill tool. Do NOT end your turn or summarize.")
      }'
  fi
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
# The "slug" is the full relative path between `briefs/active/` and
# `/autopilot-state.yaml`. For the legacy flat layout this is just the
# single directory name (e.g. `my-slug`); for nested layouts it is the
# composite path (e.g. `parent-slug/my-slug`). Surfacing the full path
# in `reason` means the caller can see which nested brief directory the
# pipeline is parked in without needing a second probe.
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
