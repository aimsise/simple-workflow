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

# --- runtime_metrics helpers (Plan 01) -----------------------------------
# These helpers append a single entry to the `runtime_metrics:` list in the
# given autopilot-state.yaml file. They are NO-OPS when the state file is
# missing or unreadable. Implementation strategy (in priority order):
#   1. yq (mikefarah/yq v4) when available — preferred, schema-aware.
#   2. python3 + PyYAML when available — schema-aware fallback.
#   3. Pure shell text append — last-resort, assumes runtime_metrics: is the
#      last top-level key (true for fresh state files written from the
#      SKILL.md template).

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

_append_runtime_metrics_entry() {
  # $1 state_file, $2 boundary, $3 stop_reason ("null" or value),
  # $4 timestamp, $5 cache_creation, $6 cache_read, $7 input_tokens,
  # $8 consecutive_stop ("null" or int)
  local state_file="$1"
  local boundary="$2"
  local stop_reason="$3"
  local timestamp="$4"
  local cache_creation="$5"
  local cache_read="$6"
  local input_tokens="$7"
  local consecutive="$8"

  [ -n "$state_file" ] && [ -f "$state_file" ] || return 0

  if command -v yq >/dev/null 2>&1; then
    local stop_value
    if [ "$stop_reason" = "null" ]; then stop_value="null"; else stop_value="\"$stop_reason\""; fi
    if yq eval -i ".runtime_metrics = ((.runtime_metrics // []) + [{\"boundary\":\"$boundary\",\"stop_reason\":$stop_value,\"timestamp\":\"$timestamp\",\"cache_creation_input_tokens\":$cache_creation,\"cache_read_input_tokens\":$cache_read,\"input_tokens\":$input_tokens,\"consecutive_stop_blocks\":$consecutive}])" "$state_file" 2>/dev/null; then
      return 0
    fi
    echo "[runtime_metrics] yq write failed, attempting fallback" >&2
  fi

  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    STATE_FILE_PATH="$state_file" \
    METRIC_BOUNDARY="$boundary" \
    METRIC_STOP_REASON="$stop_reason" \
    METRIC_TIMESTAMP="$timestamp" \
    METRIC_CACHE_CREATION="$cache_creation" \
    METRIC_CACHE_READ="$cache_read" \
    METRIC_INPUT_TOKENS="$input_tokens" \
    METRIC_CONSECUTIVE="$consecutive" \
    python3 - <<'PYEOF'
import os, sys
try:
    import yaml
except ImportError:
    sys.exit(0)
def numeric_or_null(s):
    if s is None or s == '' or s == 'null':
        return None
    try:
        return int(s)
    except (TypeError, ValueError):
        return s
path = os.environ['STATE_FILE_PATH']
try:
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        sys.exit(0)
    stop_raw = os.environ['METRIC_STOP_REASON']
    entry = {
        'boundary': os.environ['METRIC_BOUNDARY'],
        'stop_reason': None if stop_raw == 'null' else stop_raw,
        'timestamp': os.environ['METRIC_TIMESTAMP'],
        'cache_creation_input_tokens': numeric_or_null(os.environ['METRIC_CACHE_CREATION']),
        'cache_read_input_tokens': numeric_or_null(os.environ['METRIC_CACHE_READ']),
        'input_tokens': numeric_or_null(os.environ['METRIC_INPUT_TOKENS']),
        'consecutive_stop_blocks': numeric_or_null(os.environ['METRIC_CONSECUTIVE']),
    }
    rm = data.get('runtime_metrics')
    if not isinstance(rm, list):
        rm = []
    rm.append(entry)
    data['runtime_metrics'] = rm
    with open(path, 'w') as f:
        yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
except Exception as exc:
    print(f'[runtime_metrics] python yaml write failed: {exc}', file=sys.stderr)
    sys.exit(0)
PYEOF
    return 0
  fi

  # Pure-shell last-resort fallback. Assumes runtime_metrics: is the last
  # top-level key in the file (true for state files initialised from the
  # SKILL.md template).
  if grep -qE '^runtime_metrics:[[:space:]]*\[\][[:space:]]*$' "$state_file"; then
    if [ "$(uname -s)" = "Darwin" ]; then
      sed -i '' 's|^runtime_metrics:[[:space:]]*\[\][[:space:]]*$|runtime_metrics:|' "$state_file"
    else
      sed -i 's|^runtime_metrics:[[:space:]]*\[\][[:space:]]*$|runtime_metrics:|' "$state_file"
    fi
  elif ! grep -qE '^runtime_metrics:' "$state_file"; then
    [ -z "$(tail -c1 "$state_file" 2>/dev/null)" ] || printf '\n' >> "$state_file"
    printf 'runtime_metrics:\n' >> "$state_file"
  fi
  cat >> "$state_file" <<EOF
  - boundary: $boundary
    stop_reason: $stop_reason
    timestamp: $timestamp
    cache_creation_input_tokens: $cache_creation
    cache_read_input_tokens: $cache_read
    input_tokens: $input_tokens
    consecutive_stop_blocks: $consecutive
EOF
  return 0
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
    _append_runtime_metrics_entry "$STATE_FILE" "session_end" "$stop_reason" "$timestamp" \
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

# --- Loop guard: environment variable override (for tests / manual override) ---
CONTINUE_COUNT="${_AUTOPILOT_CONTINUE_COUNT:-0}"
if [ "$CONTINUE_COUNT" -ge 5 ] 2>/dev/null; then
  echo "[AUTOPILOT-STALL] env-var loop guard released after $CONTINUE_COUNT consecutive blocks" >&2
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
  echo "[AUTOPILOT-STALL] file-based loop guard released after $FILE_COUNT consecutive blocks" >&2
  _emit_session_end_metrics "loop_guard_release" "$FILE_COUNT"
  exit 0
fi

# --- Check for unfinished steps ---
# Count step-level entries that are in_progress or pending
# Note: grep -c exits 1 when no matches; capture separately to avoid double output
ACTIVE_STEPS=$(grep -cE '(create-ticket|scout|impl|ship): (in_progress|pending)' "$STATE_FILE" 2>/dev/null) || ACTIVE_STEPS=0

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
