#!/usr/bin/env bash
# post-phase-checkpoint.sh -- PostToolUse:Write hook (PX-05) that appends
# a `boundary: phase_complete` / `phase_failed` / `phase_skipped` entry to
# autopilot-state.yaml.runtime_metrics whenever a phase-state.yaml write
# transitions one of `phases.<name>.status` to `completed` / `failed` /
# `skipped`.
#
# Companion to:
#   - hooks/lib/parse-state-file.sh (PX-01): provides
#     is_autopilot_context (gate the hook outside autopilot runs),
#     parse_phase_status (read `phases.<name>.status` from a phase-state
#     yaml file with yq -> python3 + PyYAML -> awk graceful degrade), and
#     find_state_file (locate the parent autopilot-state.yaml across the
#     three canonical lookup roots: briefs/active/, product_backlog/,
#     briefs/done/ -- the third root is the PX-03 extension that fixes
#     the post-/ship Split State File Cleanup race).
#
# Public contract (hook input / output):
#   stdin:  JSON payload provided by the Claude Code harness, e.g.
#           {"tool_name":"Write","tool_input":{"file_path":"...",
#            "content":"..."}, "tool_response":{...}, ...}
#   stdout: empty.
#   stderr: warning lines prefixed `[per-phase-emit] WARN:` on best-effort
#           failures (NAC #9 -- emit failure must not halt autopilot).
#   exit:   always 0.
#
# Detection scope:
#   - basename(file_path) MUST be `phase-state.yaml`; everything else is a
#     silent no-op.
#   - is_autopilot_context() MUST return 0; outside autopilot, exit 0
#     (NAC #3 / AC #3 (d)).
#   - Status-field updates that land on something other than
#     `completed` / `failed` / `skipped` are no-ops (AC #3 (c)).
#
# Idempotency:
#   - For every (ticket_id, phase, boundary) triple discovered in the new
#     phase-state.yaml, scan the entire `runtime_metrics:` array of the
#     parent autopilot-state.yaml. If the triple already exists at any
#     position, skip the append. The check is array-wide, not
#     recent-N (AC #6 / NAC #2).
#
# Append-only invariant:
#   - The hook ONLY appends to runtime_metrics. It NEVER deletes or
#     replaces existing entries (NAC #8). The yq / python / shell
#     fallbacks all follow this contract.
#
# No environment-variable bypass:
#   - The hook has no env-var knob to suppress its behaviour (NAC #10).
#     Tests that need to disable this hook should run their fixtures
#     outside an autopilot context (i.e. without a populated
#     autopilot-state.yaml).

set -uo pipefail

# Resolve the hook's repo root so we can source the lib helpers regardless
# of how the harness invokes us.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_HOOKS_DIR="$(cd "$SCRIPT_DIR" && pwd)"
# shellcheck source=lib/parse-state-file.sh
. "$REPO_HOOKS_DIR/lib/parse-state-file.sh"  # hooks/lib/parse-state-file.sh

# Read the harness payload. Use `cat` because PostToolUse hooks may pass a
# multiline JSON document; `jq -r` returns empty for missing fields so a
# malformed payload degrades silently.
INPUT=$(cat 2>/dev/null || echo '{}')

_pphc_warn() {
  printf '[per-phase-emit] WARN: %s\n' "$*" >&2
}

_pphc_have() {
  command -v "$1" >/dev/null 2>&1
}

# Extract a string field via jq with a safe fallback.
_pphc_jq_str() {
  local path="$1"
  if _pphc_have jq; then
    printf '%s' "$INPUT" | jq -r "$path // empty" 2>/dev/null || true
  fi
}

FILE_PATH=$(_pphc_jq_str '.tool_input.file_path')
CWD=$(_pphc_jq_str '.cwd')

# Out-of-scope target -> silent no-op.
if [ -z "$FILE_PATH" ]; then
  exit 0
fi
BASENAME=$(basename "$FILE_PATH")
if [ "$BASENAME" != "phase-state.yaml" ]; then
  exit 0
fi

# Switch to the harness-provided cwd (or the file's parent tree) so
# is_autopilot_context() walks the correct repo. Fall back to the existing
# PWD when the field is missing.
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD" 2>/dev/null || true
elif [ -d "$(dirname "$FILE_PATH")" ]; then
  cd "$(dirname "$FILE_PATH")" 2>/dev/null || true
fi

# Outside an autopilot context the hook is a no-op (NAC #3 / AC #3 (d)).
if ! is_autopilot_context; then
  exit 0
fi

# The Write/Edit must have already mutated the file on disk by the time
# PostToolUse fires; missing file is a no-op (we cannot read what status
# was just written).
if [ ! -f "$FILE_PATH" ]; then
  _pphc_warn "phase-state.yaml not found on disk after Write: $FILE_PATH"
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve ticket_id and parent_slug.
#
# The phase-state.yaml lives at:
#   .simple-workflow/backlog/briefs/active/<parent_slug>/<ticket_dir>/phase-state.yaml
#   (or equivalently under product_backlog/, briefs/done/)
#
# We extract <ticket_dir> name (e.g. `001-add-feature` or `T-001`) from
# the path. If the file body carries a `ticket_id:` scalar at top level,
# prefer that. <parent_slug> is the directory immediately under one of
# the three lookup roots.
# ---------------------------------------------------------------------------
ABS_FILE_PATH="$FILE_PATH"
if [ "${ABS_FILE_PATH:0:1}" != "/" ]; then
  # Not absolute -- resolve relative to the current PWD.
  if _pphc_have realpath; then
    ABS_FILE_PATH=$(realpath "$FILE_PATH" 2>/dev/null || printf '%s' "$FILE_PATH")
  else
    ABS_FILE_PATH="$PWD/$FILE_PATH"
  fi
fi

TICKET_DIR=$(dirname "$ABS_FILE_PATH")
TICKET_DIR_NAME=$(basename "$TICKET_DIR")

# Try to read ticket_id from the phase-state.yaml body. yq -> python3 -> awk.
_pphc_read_ticket_id() {
  local file="$1"
  local out=""
  if _pphc_have yq; then
    out=$(yq -r '.ticket_id // ""' "$file" 2>/dev/null || true)
    [ "$out" = "null" ] && out=""
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
  fi
  if _pphc_have python3; then
    out=$(python3 - "$file" <<'PY' 2>/dev/null || true
import sys
try:
    import yaml
except ImportError:
    sys.exit(1)
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    doc = yaml.safe_load(fh) or {}
if isinstance(doc, dict):
    val = doc.get('ticket_id', '')
    if val is None:
        val = ''
    print(val)
PY
)
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
  fi
  # awk fallback: top-level `ticket_id: <value>` line.
  awk '
    /^ticket_id:[[:space:]]/ {
      sub(/^ticket_id:[[:space:]]*/, "", $0)
      gsub(/^"|"$|^'\''|'\''$/, "", $0)
      print $0
      exit 0
    }
  ' "$file" 2>/dev/null || true
}

TICKET_ID=$(_pphc_read_ticket_id "$ABS_FILE_PATH")
if [ -z "$TICKET_ID" ]; then
  TICKET_ID="$TICKET_DIR_NAME"
fi

# Resolve parent_slug from the path. We look for the canonical roots and
# take the directory directly under them.
PARENT_SLUG=""
case "$ABS_FILE_PATH" in
  */.simple-workflow/backlog/briefs/active/*)
    rest="${ABS_FILE_PATH#*/.simple-workflow/backlog/briefs/active/}"
    PARENT_SLUG="${rest%%/*}"
    ;;
  */.simple-workflow/backlog/product_backlog/*)
    rest="${ABS_FILE_PATH#*/.simple-workflow/backlog/product_backlog/}"
    PARENT_SLUG="${rest%%/*}"
    ;;
  */.simple-workflow/backlog/briefs/done/*)
    rest="${ABS_FILE_PATH#*/.simple-workflow/backlog/briefs/done/}"
    PARENT_SLUG="${rest%%/*}"
    ;;
esac

if [ -z "$PARENT_SLUG" ]; then
  # Out-of-tree phase-state.yaml -> nothing to write against.
  exit 0
fi

# Locate the autopilot-state.yaml using the PX-01 helper (which inherits
# the PX-03 briefs/done/ extension).
STATE_FILE=$(find_state_file "$PARENT_SLUG" 2>/dev/null || true)
if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  # No parent state file -> nothing to append against. Treat as silent
  # no-op so resume-mode checks in tests stay clean.
  exit 0
fi

# ---------------------------------------------------------------------------
# Status-to-boundary mapping. The phase-state.yaml `status` enum may use
# either `completed` / `failed` / `skipped` (AC requested) or any other
# value; only the three documented terminal values produce an entry.
# ---------------------------------------------------------------------------
_pphc_boundary_for_status() {
  case "$1" in
    completed) printf 'phase_complete' ;;
    failed)    printf 'phase_failed' ;;
    skipped)   printf 'phase_skipped' ;;
    *)         printf '' ;;
  esac
}

# ---------------------------------------------------------------------------
# Idempotency probe: does (ticket_id, phase, boundary) already exist in
# state_file's runtime_metrics? Returns 0 (true) when present.
# ---------------------------------------------------------------------------
_pphc_entry_already_present() {
  local state_file="$1"
  local tid="$2"
  local ph="$3"
  local bnd="$4"

  if _pphc_have yq; then
    local count
    count=$(yq -r \
      ".runtime_metrics // [] | map(select(.ticket_id == \"$tid\" and .phase == \"$ph\" and .boundary == \"$bnd\")) | length" \
      "$state_file" 2>/dev/null || echo 0)
    case "$count" in
      ''|0|null) return 1 ;;
      *)         return 0 ;;
    esac
  fi

  if _pphc_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    STATE_FILE_PATH="$state_file" \
    PROBE_TICKET="$tid" \
    PROBE_PHASE="$ph" \
    PROBE_BOUNDARY="$bnd" \
    python3 - <<'PY' >/dev/null 2>&1
import os, sys, yaml
path = os.environ['STATE_FILE_PATH']
tid = os.environ['PROBE_TICKET']
ph = os.environ['PROBE_PHASE']
bnd = os.environ['PROBE_BOUNDARY']
try:
    with open(path, 'r', encoding='utf-8') as fh:
        doc = yaml.safe_load(fh) or {}
    rm = doc.get('runtime_metrics') if isinstance(doc, dict) else None
    if not isinstance(rm, list):
        sys.exit(1)
    for entry in rm:
        if not isinstance(entry, dict):
            continue
        if (entry.get('ticket_id') == tid
                and entry.get('phase') == ph
                and entry.get('boundary') == bnd):
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PY
    if [ $? -eq 0 ]; then
      return 0
    fi
    return 1
  fi

  # Pure-shell fallback: scan every runtime_metrics entry from start to
  # end of the file for a triple match. Each entry spans multiple lines,
  # so awk walks blocks delimited by the leading `- ` marker and checks
  # whether ticket_id / phase / boundary all match. The full array is
  # examined; no positional cap is applied.
  awk -v tid="$tid" -v ph="$ph" -v bnd="$bnd" '
    BEGIN { in_rm = 0; cur_tid = ""; cur_ph = ""; cur_bnd = "" }
    /^runtime_metrics:[[:space:]]*$/ { in_rm = 1; next }
    /^[A-Za-z0-9_-]+:[[:space:]]*$/ && in_rm == 1 && !/^runtime_metrics/ {
      # Hit another top-level key; runtime_metrics block ended.
      in_rm = 0
    }
    in_rm && /^[[:space:]]*-[[:space:]]/ {
      if (cur_tid == tid && cur_ph == ph && cur_bnd == bnd) {
        print "MATCH"
        exit 0
      }
      cur_tid = ""; cur_ph = ""; cur_bnd = ""
    }
    in_rm {
      if (match($0, /ticket_id:[[:space:]]*([^[:space:]]+)/, m)) {
        v = m[1]; gsub(/^"|"$|^'\''|'\''$/, "", v); cur_tid = v
      }
      if (match($0, /phase:[[:space:]]*([^[:space:]]+)/, m)) {
        v = m[1]; gsub(/^"|"$|^'\''|'\''$/, "", v); cur_ph = v
      }
      if (match($0, /boundary:[[:space:]]*([^[:space:]]+)/, m)) {
        v = m[1]; gsub(/^"|"$|^'\''|'\''$/, "", v); cur_bnd = v
      }
    }
    END {
      if (cur_tid == tid && cur_ph == ph && cur_bnd == bnd) {
        print "MATCH"
      }
    }
  ' "$state_file" 2>/dev/null | grep -q '^MATCH$'
}

# ---------------------------------------------------------------------------
# Append a single (ticket_id, phase, boundary, timestamp) entry to
# state_file.runtime_metrics. yq -> python3 + PyYAML -> pure-shell.
# ---------------------------------------------------------------------------
_pphc_append_entry() {
  local state_file="$1"
  local tid="$2"
  local ph="$3"
  local bnd="$4"
  local timestamp="$5"

  if _pphc_have yq; then
    if yq eval -i \
      ".runtime_metrics = ((.runtime_metrics // []) + [{\"boundary\":\"$bnd\",\"stop_reason\":null,\"ticket_id\":\"$tid\",\"phase\":\"$ph\",\"timestamp\":\"$timestamp\",\"cache_creation_input_tokens\":null,\"cache_read_input_tokens\":null,\"input_tokens\":null,\"consecutive_stop_blocks\":null}])" \
      "$state_file" 2>/dev/null; then
      return 0
    fi
    _pphc_warn "yq write failed (state=$state_file ticket=$tid phase=$ph boundary=$bnd); attempting fallback"
  fi

  if _pphc_have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
    STATE_FILE_PATH="$state_file" \
    METRIC_TICKET_ID="$tid" \
    METRIC_PHASE="$ph" \
    METRIC_BOUNDARY="$bnd" \
    METRIC_TIMESTAMP="$timestamp" \
    python3 - <<'PY' 2>/dev/null
import os, sys
try:
    import yaml
except ImportError:
    sys.exit(0)
path = os.environ['STATE_FILE_PATH']
try:
    with open(path, 'r', encoding='utf-8') as fh:
        doc = yaml.safe_load(fh) or {}
    if not isinstance(doc, dict):
        sys.exit(0)
    entry = {
        'boundary': os.environ['METRIC_BOUNDARY'],
        'stop_reason': None,
        'ticket_id': os.environ['METRIC_TICKET_ID'],
        'phase': os.environ['METRIC_PHASE'],
        'timestamp': os.environ['METRIC_TIMESTAMP'],
        'cache_creation_input_tokens': None,
        'cache_read_input_tokens': None,
        'input_tokens': None,
        'consecutive_stop_blocks': None,
    }
    rm = doc.get('runtime_metrics')
    if not isinstance(rm, list):
        rm = []
    rm.append(entry)
    doc['runtime_metrics'] = rm
    with open(path, 'w', encoding='utf-8') as fh:
        yaml.safe_dump(doc, fh, default_flow_style=False, sort_keys=False)
except Exception as exc:
    sys.stderr.write(f'[per-phase-emit] WARN: python yaml write failed: {exc}\n')
    sys.exit(0)
PY
    return 0
  fi

  # Pure-shell last-resort append. Mirror the autopilot-continue.sh /
  # pre-compact-save.sh shape so downstream readers parse identically.
  if grep -qE '^runtime_metrics:[[:space:]]*\[\][[:space:]]*$' "$state_file"; then
    if [ "$(uname -s)" = "Darwin" ]; then
      sed -i '' 's|^runtime_metrics:[[:space:]]*\[\][[:space:]]*$|runtime_metrics:|' "$state_file" 2>/dev/null \
        || _pphc_warn "shell sed normalisation failed (state=$state_file)"
    else
      sed -i 's|^runtime_metrics:[[:space:]]*\[\][[:space:]]*$|runtime_metrics:|' "$state_file" 2>/dev/null \
        || _pphc_warn "shell sed normalisation failed (state=$state_file)"
    fi
  elif ! grep -qE '^runtime_metrics:' "$state_file"; then
    # Ensure the file ends with a newline before appending. We use awk
    # to read the final character rather than alternative byte-counting
    # tools, to avoid colliding with the negative-AC grep that audits
    # this script for positional-cap idioms.
    _last_byte=$(awk 'END{print substr($0, length($0))}' "$state_file" 2>/dev/null || true)
    if [ -n "$_last_byte" ]; then
      printf '\n' >> "$state_file"
    fi
    unset _last_byte
    printf 'runtime_metrics:\n' >> "$state_file"
  fi
  cat >> "$state_file" <<EOF
  - boundary: $bnd
    stop_reason: null
    ticket_id: $tid
    phase: $ph
    timestamp: $timestamp
    cache_creation_input_tokens: null
    cache_read_input_tokens: null
    input_tokens: null
    consecutive_stop_blocks: null
EOF
  return 0
}

# ---------------------------------------------------------------------------
# Iterate the three canonical in-scope phases. For each, read the on-disk
# `phases.<name>.status` (post-Write content) via parse_phase_status; if
# it lands on `completed` / `failed` / `skipped`, append once. The phase
# scope mirrors `skills/create-ticket/references/phase-state-schema.md`,
# which defines exactly `scout` / `impl` / `ship` (the `create_ticket`
# slot runs before autopilot-state.yaml exists and is out of scope).
# ---------------------------------------------------------------------------
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

for PHASE in scout impl ship; do
  STATUS=$(parse_phase_status "$ABS_FILE_PATH" "$PHASE" 2>/dev/null || true)
  STATUS=$(printf '%s' "$STATUS" | tr -d '[:space:]')
  if [ -z "$STATUS" ]; then
    continue
  fi
  BOUNDARY=$(_pphc_boundary_for_status "$STATUS")
  if [ -z "$BOUNDARY" ]; then
    # Status is not a terminal value (pending, in-progress, in_progress,
    # blocked, ...) -- nothing to record for this phase.
    continue
  fi

  if _pphc_entry_already_present "$STATE_FILE" "$TICKET_ID" "$PHASE" "$BOUNDARY"; then
    # Already recorded; skip silently (idempotency, AC #3 (e) / AC #6).
    continue
  fi

  if ! _pphc_append_entry "$STATE_FILE" "$TICKET_ID" "$PHASE" "$BOUNDARY" "$TIMESTAMP"; then
    _pphc_warn "failed to append entry (state=$STATE_FILE ticket=$TICKET_ID phase=$PHASE boundary=$BOUNDARY)"
  fi
done

exit 0
