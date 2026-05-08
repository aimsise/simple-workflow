#!/usr/bin/env bash
# runtime-metrics.sh — shared runtime_metrics append helper for hook scripts.
#
# Sourced by:
#   - hooks/autopilot-continue.sh (session_end boundary writes)
#   - hooks/pre-compact-save.sh (session_compaction boundary writes)
#
# Public contract:
#
#   append_runtime_metrics_entry <state_file> <boundary> <stop_reason>
#       <timestamp> <cache_creation> <cache_read> <input_tokens> <consecutive>
#     - Appends a single entry to the `runtime_metrics:` list in the given
#       autopilot-state.yaml file.
#     - Is a NO-OP when the state file is missing or unreadable.
#     - Implementation strategy (in priority order):
#         1. yq (mikefarah/yq v4) when available — preferred, schema-aware.
#         2. python3 + PyYAML when available — schema-aware fallback.
#         3. Pure shell text append — last-resort, assumes runtime_metrics: is
#            the last top-level key (true for fresh state files written from
#            the SKILL.md template).
#     - Pass literal "null" (string) for stop_reason or consecutive when those
#       fields are not applicable to the boundary type.
#
# This file does not introduce any environment-variable knob that disables
# the helper. If a downstream caller needs to bypass detection (e.g. for
# tests), it should use a controlled fixture path.
#
# `set -euo pipefail` is intentionally NOT set here. This file is sourced
# by hook scripts that already declare their own shell flags; setting them
# again would override the caller's configuration. The other hooks/lib/*.sh
# files follow the same convention.

_rm_strip_unsafe() {
  # Strip `"`, `\`, `\n`, `\r` from a string using only bash builtins (no
  # external `tr` / `sed`) so the pure-shell tier remains usable when PATH
  # is restricted to a minimal toolset (see AC-4 fixture in
  # tests/test-hooks-lib.sh).
  local v="$1"
  v="${v//\"/}"
  v="${v//\\/}"
  v="${v//$'\n'/}"
  v="${v//$'\r'/}"
  printf '%s' "$v"
}

_rm_numeric_or_null() {
  # Returns the input unchanged when it is a non-negative integer or the
  # literal `null`; returns `null` otherwise. This closes the yq-expression
  # injection surface for the four numeric token fields, which flow from
  # `_runtime_metrics_payload_field` (jq -r against Claude-Code-supplied
  # JSON). Bash builtin regex; no external command.
  local v="$1"
  if [[ "$v" =~ ^([0-9]+|null)$ ]]; then
    printf '%s' "$v"
  else
    printf 'null'
  fi
}

append_runtime_metrics_entry() {
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

  # Strip characters that could break the yq expression (`"` / `\`) or the
  # pure-shell heredoc YAML structure (`\n` / `\r`). All callers pass
  # values from a small controlled enum (`session_end`, `normal_completion`,
  # ISO-8601 timestamps, integer or "null" literals) so this is a NO-OP on
  # legitimate input — it only fires as a defence-in-depth measure if a
  # future caller forwards an unsanitised payload field.
  boundary=$(_rm_strip_unsafe "$boundary")
  stop_reason=$(_rm_strip_unsafe "$stop_reason")
  timestamp=$(_rm_strip_unsafe "$timestamp")
  # Numeric fields are validated against `^([0-9]+|null)$` and any non-match
  # is coerced to the `null` literal. This closes the yq-expression
  # injection vector for these four positional arguments, which flow from
  # `_runtime_metrics_payload_field`'s jq output and are spliced raw into
  # the yq expression at line ~89.
  cache_creation=$(_rm_numeric_or_null "$cache_creation")
  cache_read=$(_rm_numeric_or_null "$cache_read")
  input_tokens=$(_rm_numeric_or_null "$input_tokens")
  consecutive=$(_rm_numeric_or_null "$consecutive")

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

export -f append_runtime_metrics_entry
