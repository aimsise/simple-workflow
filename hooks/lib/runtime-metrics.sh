#!/usr/bin/env bash
# runtime-metrics.sh — shared runtime_metrics append helper for hook scripts.
#
# Sourced by:
#   - hooks/autopilot-continue.sh (session_end boundary writes)
#   - hooks/pre-compact-save.sh (session_compaction boundary writes)
#   - hooks/impl-checkpoint-guard.sh (session_end boundary writes for the
#     /audit-handoff guard; emits the four stop_reason values listed below)
#   - hooks/scout-checkpoint-guard.sh (session_end boundary writes)
#   - hooks/pre-next-scout-auto-compact.sh (auto_compact_inject boundary;
#     passes the cumulative shipped-ticket count via the optional 9th arg)
#   - hooks/post-ship-state-auto-compact.sh (auto_compact_inject boundary;
#     passes the cumulative shipped-ticket count via the optional 9th arg)
#
# Public contract:
#
#   append_runtime_metrics_entry <state_file> <boundary> <stop_reason>
#       <timestamp> <cache_creation> <cache_read> <input_tokens> <consecutive>
#       [<shipped_count>]
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
#     - <shipped_count> (arg9) is OPTIONAL ("only-when-provided" semantics).
#       Omitted, empty, or the literal "null" -> NO `shipped_count:` field is
#       emitted and the entry is byte-identical to the historical 8-arg form
#       (so every session_end / session_compaction caller is unchanged). A
#       non-negative integer -> a `shipped_count:` field is appended AFTER
#       `consecutive_stop_blocks` in ALL THREE write tiers. This field carries
#       the cumulative count of shipped tickets at an `auto_compact_inject`
#       boundary and is semantically DISTINCT from `consecutive_stop_blocks`
#       (which is meaningful only for `boundary: session_end`). The two
#       auto_compact_inject callers pass it so they no longer pollute
#       consecutive_stop_blocks. The per-boundary variable key set mirrors
#       post-phase-checkpoint.sh, which already adds ticket_id/phase only to
#       phase_* entries.
#
# stop_reason taxonomy (informative; the helper itself does no validation):
#
#   Existing (autopilot-continue.sh, pre-compact-save.sh, session-stop-log.sh):
#     normal_completion, partial_completion, loop_guard_release,
#     session_compaction, ...
#
#   Added by impl-checkpoint-guard.sh (Stop hook, session_end boundary):
#     premature_audit_handoff_blocked     — 5-AND condition met; block emitted
#     audit_handoff_via_prompt            — recorded by the same Stop hook
#                                            when the prompt-side AuditTail
#                                            is observed to have completed
#                                            Phase 3 (`## [SW-CHECKPOINT]`
#                                            present); used to compute the
#                                            primary SLO ratio.
#     phasegate_released_after_N_blocks   — 3-loop release path
#     phasegate_disabled                  — kill switch SW_IMPL_CHECKPOINT_MODE
#                                            in {metric-only, off}; kept so
#                                            disabled sessions are not invisible
#                                            to monitoring.
#
# Boundary orthogonality (per addendum §13.C-2): runtime_metrics entries are
# partitioned by `boundary` field. `boundary: phase_complete | phase_failed |
# phase_skipped` (PX-05 / post-phase-checkpoint.sh) tracks phase-level
# transitions; `boundary: session_end` (Stop hooks above) tracks turn-
# termination events. Tune-skill aggregations treat the two partitions
# independently — no double-counting between boundaries. Cross-boundary
# correlation is reserved for ad-hoc analysis, not standard SLO computation.
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
  # $8 consecutive_stop ("null" or int),
  # $9 shipped_count (OPTIONAL; "", "null", or omitted -> field NOT emitted;
  #    a non-negative int -> a `shipped_count:` field is appended after
  #    consecutive_stop_blocks). Used by the two auto_compact_inject callers
  #    (pre-next-scout-auto-compact.sh / post-ship-state-auto-compact.sh) to
  #    record the cumulative shipped count WITHOUT polluting
  #    consecutive_stop_blocks.
  local state_file="$1"
  local boundary="$2"
  local stop_reason="$3"
  local timestamp="$4"
  local cache_creation="$5"
  local cache_read="$6"
  local input_tokens="$7"
  local consecutive="$8"
  local shipped_count="${9:-}"

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
  # injection vector for these positional arguments, which flow from
  # `_runtime_metrics_payload_field`'s jq output and are spliced raw into
  # the yq expression below.
  cache_creation=$(_rm_numeric_or_null "$cache_creation")
  cache_read=$(_rm_numeric_or_null "$cache_read")
  input_tokens=$(_rm_numeric_or_null "$input_tokens")
  consecutive=$(_rm_numeric_or_null "$consecutive")

  # arg9 (shipped_count): OPTIONAL, only-when-provided semantics. Empty,
  # "null", or a value that does not survive the numeric guard -> emit no
  # field (emit_shipped=0), keeping the 8-arg callers byte-identical (T3).
  # A non-negative integer -> emit `shipped_count:` after consecutive_stop_blocks
  # in every tier. Runs through the SAME numeric guard as the count fields so
  # the yq-expression injection surface is closed identically (it flows from
  # SHIPPED_COUNT). post-ship-state passes `${SHIPPED_COUNT_FOR_AUDIT:-null}`,
  # so the literal "null" must also map to "omit" — handled here.
  local emit_shipped=0
  if [ -n "$shipped_count" ] && [ "$shipped_count" != "null" ]; then
    shipped_count=$(_rm_numeric_or_null "$shipped_count")
    [ "$shipped_count" != "null" ] && emit_shipped=1
  fi

  [ -n "$state_file" ] && [ -f "$state_file" ] || return 0

  if command -v yq >/dev/null 2>&1; then
    local stop_value
    if [ "$stop_reason" = "null" ]; then stop_value="null"; else stop_value="\"$stop_reason\""; fi
    # T1/T2: append shipped_count LAST (immediately after consecutive_stop_blocks)
    # and ONLY when arg9 was provided, so all three tiers emit a parse-identical
    # key order and the 8-arg form stays byte-identical.
    local sc_frag=""
    if [ "$emit_shipped" = "1" ]; then sc_frag=",\"shipped_count\":$shipped_count"; fi
    if yq eval -i ".runtime_metrics = ((.runtime_metrics // []) + [{\"boundary\":\"$boundary\",\"stop_reason\":$stop_value,\"timestamp\":\"$timestamp\",\"cache_creation_input_tokens\":$cache_creation,\"cache_read_input_tokens\":$cache_read,\"input_tokens\":$input_tokens,\"consecutive_stop_blocks\":$consecutive$sc_frag}])" "$state_file" 2>/dev/null; then
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
    METRIC_SHIPPED="$shipped_count" \
    METRIC_EMIT_SHIPPED="$emit_shipped" \
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
    # T1/T2: shipped_count appended LAST, only when arg9 was provided.
    # yaml.safe_dump(sort_keys=False) preserves insertion order, matching the
    # yq object literal and the pure-shell heredoc.
    if os.environ.get('METRIC_EMIT_SHIPPED') == '1':
        entry['shipped_count'] = numeric_or_null(os.environ['METRIC_SHIPPED'])
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
  # T1: emit shipped_count INSIDE the just-written element (immediately after
  # consecutive_stop_blocks, same 4-space indent) — NOT as a separate
  # top-level write — so the pure-shell tier's "runtime_metrics is the last
  # top-level key" invariant is preserved and the field lands within the array
  # element. Only when arg9 was provided.
  if [ "$emit_shipped" = "1" ]; then
    printf '    shipped_count: %s\n' "$shipped_count" >> "$state_file"
  fi
  return 0
}

export -f append_runtime_metrics_entry
