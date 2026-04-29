#!/usr/bin/env bash
# PreCompact hook: snapshot work state with YAML frontmatter so /catchup
# can recover the in-progress phase after context compaction.
#
# Plan 01: this hook also appends a `boundary: session_compaction` entry to
# any autopilot-state.yaml that exists, so /tune and post-mortem analysis
# can correlate compaction events with pipeline progress. The append is
# best-effort — missing yq + python3 simply skips the metric write.
set -euo pipefail
INPUT=$(cat 2>/dev/null || echo '{}')

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_ISO=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
SAVE_FILE=".simple-workflow/docs/compact-state/compact-state-${TIMESTAMP}.md"

mkdir -p .simple-workflow/docs/compact-state

# Collect file lists depth-agnostically under .simple-workflow/backlog/active/
# so both the flat layout (.simple-workflow/backlog/active/{NNN}-{slug}/) and
# nested layouts (.simple-workflow/backlog/active/{parent}/{NNN}-{slug}/ and
# deeper) are surfaced.
# `find` with no -maxdepth walks arbitrary depth; sort -u stabilises order
# and de-duplicates in case the same file is reachable via multiple paths.
#
# An "active ticket" is any directory under `.simple-workflow/backlog/active/`
# that contains EITHER `ticket.md` OR `phase-state.yaml` (the latter covers
# tickets that have had their phase-state initialised before `ticket.md`
# is persisted, and guarantees that every ticket with a live lifecycle
# record shows up in the compact-state frontmatter). We represent each
# active ticket by a canonical `ticket.md` path: the real file when it
# exists, otherwise a synthetic path `{dir}/ticket.md` which downstream
# code reduces to `dir` via `dirname` — the active_tickets list only
# ever contains the directory, so no missing-file read is attempted.
ACTIVE_TICKET_FILES=()
ACTIVE_BACKLOG_PLAN_FILES=()
if [ -d .simple-workflow/backlog/active ]; then
  while IFS= read -r _dir; do
    [ -n "$_dir" ] || continue
    # Deterministic canonical entry per ticket dir: always `{dir}/ticket.md`.
    # When the real file is absent, downstream code only uses `dirname` on
    # this path — the missing-file case is handled by `[ -f ... ]` guards
    # in per-ticket eval/audit loops.
    ACTIVE_TICKET_FILES+=("$_dir/ticket.md")
  done < <(
    {
      find .simple-workflow/backlog/active -type f -name 'ticket.md' 2>/dev/null
      find .simple-workflow/backlog/active -type f -name 'phase-state.yaml' 2>/dev/null
    } | while IFS= read -r _p; do
      [ -n "$_p" ] && dirname "$_p"
    done | sort -u
  )
  unset _dir

  while IFS= read -r _plan_md; do
    [ -n "$_plan_md" ] && ACTIVE_BACKLOG_PLAN_FILES+=("$_plan_md")
  done < <(find .simple-workflow/backlog/active -type f -name 'plan.md' 2>/dev/null | sort -u)
fi
unset _plan_md

shopt -s nullglob
ACTIVE_DOCS_PLAN_FILES=(.simple-workflow/docs/plans/*.md)
shopt -u nullglob

# --- Per-ticket processing ---
# Compute eval/audit round, outcome, and phase for each ticket individually.
# This fixes the prior bug where a single global max was used, causing
# incorrect aggregate values when multiple tickets are active.
TICKET_DIRS=()
TICKET_EVAL=()
TICKET_AUDIT=()
TICKET_OUTCOME=()
TICKET_PHASE=()

for tf in "${ACTIVE_TICKET_FILES[@]:-}"; do
  [ -n "$tf" ] || continue
  d=$(dirname "$tf")

  shopt -s nullglob
  t_eval_files=("${d}"/eval-round-*.md)
  t_audit_files=("${d}"/audit-round-*.md)
  shopt -u nullglob

  t_eval_max=0
  for f in "${t_eval_files[@]}"; do
    n=$(echo "$f" | sed -E 's/.*-([0-9]+)\.md$/\1/')
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt "$t_eval_max" ]; then
      t_eval_max="$n"
    fi
  done

  t_audit_max=0
  for f in "${t_audit_files[@]}"; do
    n=$(echo "$f" | sed -E 's/.*-([0-9]+)\.md$/\1/')
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt "$t_audit_max" ]; then
      t_audit_max="$n"
    fi
  done

  # Determine outcome from the most recent audit-round file for THIS ticket.
  # Only PASS/FAIL/PASS_WITH_CONCERNS are accepted; code-reviewer vocabulary
  # (success/partial/failed) is intentionally rejected.
  t_outcome="unknown"
  if [ "$t_audit_max" -gt 0 ]; then
    t_a_file="${d}/audit-round-${t_audit_max}.md"
    if [ -f "$t_a_file" ]; then
      STATUS_LINE=$(grep -m 1 -E '^\*\*Status\*\*:' "$t_a_file" 2>/dev/null || true)
      if [ -n "$STATUS_LINE" ]; then
        STATUS_VAL=$(echo "$STATUS_LINE" | sed -E 's/^\*\*Status\*\*:[[:space:]]*([A-Z_]+).*/\1/')
        case "$STATUS_VAL" in
          PASS|FAIL|PASS_WITH_CONCERNS) t_outcome="$STATUS_VAL" ;;
        esac
      fi
    fi
  fi

  # Heuristic for per-ticket in_progress_phase:
  #   - Eval done but audit not yet for the same round -> impl-loop
  #   - Eval and audit both done at same round, FAIL    -> impl-loop
  #   - Eval and audit both done at same round, PASS(*) -> impl-done
  #   - Otherwise                                       -> unknown
  t_phase="unknown"
  if [ "$t_eval_max" -gt 0 ]; then
    if [ "$t_audit_max" -lt "$t_eval_max" ]; then
      t_phase="impl-loop"
    elif [ "$t_audit_max" -eq "$t_eval_max" ]; then
      case "$t_outcome" in
        FAIL) t_phase="impl-loop" ;;
        PASS|PASS_WITH_CONCERNS) t_phase="impl-done" ;;
      esac
    fi
  fi

  TICKET_DIRS+=("$d")
  TICKET_EVAL+=("$t_eval_max")
  TICKET_AUDIT+=("$t_audit_max")
  TICKET_OUTCOME+=("$t_outcome")
  TICKET_PHASE+=("$t_phase")
done

# --- Aggregate values from per-ticket data ---
# These scalar fields are kept for backward compatibility with older /catchup
# implementations that only read top-level scalars.
LATEST_EVAL_ROUND=0
LATEST_AUDIT_ROUND=0
LAST_ROUND_OUTCOME="unknown"
IN_PROGRESS_PHASE="unknown"
_best_idx=-1

for i in "${!TICKET_DIRS[@]}"; do
  [ "${TICKET_EVAL[i]}" -gt "$LATEST_EVAL_ROUND" ] && LATEST_EVAL_ROUND="${TICKET_EVAL[i]}"
  [ "${TICKET_AUDIT[i]}" -gt "$LATEST_AUDIT_ROUND" ] && LATEST_AUDIT_ROUND="${TICKET_AUDIT[i]}"
  if [ "${TICKET_PHASE[i]}" = "impl-loop" ]; then
    IN_PROGRESS_PHASE="impl-loop"
    if [ "$_best_idx" -eq -1 ] || [ "${TICKET_AUDIT[i]}" -gt "${TICKET_AUDIT[$_best_idx]}" ]; then
      _best_idx=$i
    fi
  fi
done

if [ "$IN_PROGRESS_PHASE" = "unknown" ]; then
  for i in "${!TICKET_DIRS[@]}"; do
    if [ "${TICKET_PHASE[i]}" = "impl-done" ]; then
      IN_PROGRESS_PHASE="impl-done"
      [ "$_best_idx" -eq -1 ] && _best_idx=$i
    fi
  done
fi

[ "$_best_idx" -ge 0 ] && LAST_ROUND_OUTCOME="${TICKET_OUTCOME[$_best_idx]}"

# Emit the YAML frontmatter + Markdown body.
{
  echo "---"
  echo "date: ${DATE_ISO}"
  echo "branch: ${BRANCH}"
  echo "active_tickets:"
  if [ "${#ACTIVE_TICKET_FILES[@]}" -eq 0 ]; then
    echo "  []"
  else
    for f in "${ACTIVE_TICKET_FILES[@]}"; do
      d=$(dirname "$f")
      echo "  - ${d}"
    done
  fi
  echo "active_plans:"
  if [ "${#ACTIVE_BACKLOG_PLAN_FILES[@]}" -eq 0 ] && [ "${#ACTIVE_DOCS_PLAN_FILES[@]}" -eq 0 ]; then
    echo "  []"
  else
    if [ "${#ACTIVE_BACKLOG_PLAN_FILES[@]}" -gt 0 ]; then
      for p in "${ACTIVE_BACKLOG_PLAN_FILES[@]}"; do
        echo "  - ${p}"
      done
    fi
    if [ "${#ACTIVE_DOCS_PLAN_FILES[@]}" -gt 0 ]; then
      for p in "${ACTIVE_DOCS_PLAN_FILES[@]}"; do
        echo "  - ${p}"
      done
    fi
  fi
  echo "latest_eval_round: ${LATEST_EVAL_ROUND}"
  echo "latest_audit_round: ${LATEST_AUDIT_ROUND}"
  echo "last_round_outcome: ${LAST_ROUND_OUTCOME}"
  echo "in_progress_phase: ${IN_PROGRESS_PHASE}"
  echo "tickets:"
  if [ "${#TICKET_DIRS[@]}" -eq 0 ]; then
    echo "  []"
  else
    for i in "${!TICKET_DIRS[@]}"; do
      echo "  - dir: ${TICKET_DIRS[i]}"
      echo "    latest_eval_round: ${TICKET_EVAL[i]}"
      echo "    latest_audit_round: ${TICKET_AUDIT[i]}"
      echo "    last_round_outcome: ${TICKET_OUTCOME[i]}"
      echo "    in_progress_phase: ${TICKET_PHASE[i]}"
    done
  fi
  echo "---"
  echo ""
  echo "# Work State Before Compact"
  echo ""
  echo "## Changed Files"
  git diff --name-only 2>/dev/null || true
  echo ""
  echo "## Git Status"
  git status --short 2>/dev/null || true
  echo ""
  echo "## Active Tickets"
  if [ "${#ACTIVE_TICKET_FILES[@]}" -eq 0 ]; then
    echo "(none)"
  else
    printf '%s\n' "${ACTIVE_TICKET_FILES[@]}"
  fi
  echo ""
  echo "## Active Plans"
  if [ "${#ACTIVE_BACKLOG_PLAN_FILES[@]}" -eq 0 ] && [ "${#ACTIVE_DOCS_PLAN_FILES[@]}" -eq 0 ]; then
    echo "(none)"
  else
    if [ "${#ACTIVE_BACKLOG_PLAN_FILES[@]}" -gt 0 ]; then
      printf '%s\n' "${ACTIVE_BACKLOG_PLAN_FILES[@]}"
    fi
    if [ "${#ACTIVE_DOCS_PLAN_FILES[@]}" -gt 0 ]; then
      printf '%s\n' "${ACTIVE_DOCS_PLAN_FILES[@]}"
    fi
  fi
  echo ""
  echo "## Evaluation State"
  # Depth-agnostic scan for eval-round-*.md / audit-round-*.md so nested
  # ticket layouts (.simple-workflow/backlog/active/{parent}/{NNN}-{slug}/) are
  # surfaced alongside the flat layout.
  ALL_EVAL_FILES=()
  ALL_AUDIT_FILES=()
  if [ -d .simple-workflow/backlog/active ]; then
    while IFS= read -r _ef; do
      [ -n "$_ef" ] && ALL_EVAL_FILES+=("$_ef")
    done < <(find .simple-workflow/backlog/active -type f -name 'eval-round-*.md' 2>/dev/null | sort -u)
    while IFS= read -r _af; do
      [ -n "$_af" ] && ALL_AUDIT_FILES+=("$_af")
    done < <(find .simple-workflow/backlog/active -type f -name 'audit-round-*.md' 2>/dev/null | sort -u)
  fi
  unset _ef _af
  if [ "${#ALL_EVAL_FILES[@]}" -eq 0 ] && [ "${#ALL_AUDIT_FILES[@]}" -eq 0 ]; then
    echo "(none)"
  else
    if [ "${#ALL_EVAL_FILES[@]}" -gt 0 ]; then
      printf '%s\n' "${ALL_EVAL_FILES[@]}"
    fi
    if [ "${#ALL_AUDIT_FILES[@]}" -gt 0 ]; then
      printf '%s\n' "${ALL_AUDIT_FILES[@]}"
    fi
  fi
} > "$SAVE_FILE"

# --- Plan 01: append boundary: session_compaction entry to every discovered
# autopilot-state.yaml. Best-effort — missing yq AND missing python3+yaml
# simply skips the write. ---

_pc_runtime_metrics_payload_field() {
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

_pc_append_session_compaction() {
  local state_file="$1"
  [ -n "$state_file" ] && [ -f "$state_file" ] || return 0

  local timestamp cache_creation cache_read input_tokens
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  cache_creation=$(_pc_runtime_metrics_payload_field cache_creation_input_tokens)
  cache_read=$(_pc_runtime_metrics_payload_field cache_read_input_tokens)
  input_tokens=$(_pc_runtime_metrics_payload_field input_tokens)

  if command -v yq >/dev/null 2>&1; then
    if yq eval -i ".runtime_metrics = ((.runtime_metrics // []) + [{\"boundary\":\"session_compaction\",\"stop_reason\":null,\"timestamp\":\"$timestamp\",\"cache_creation_input_tokens\":$cache_creation,\"cache_read_input_tokens\":$cache_read,\"input_tokens\":$input_tokens,\"consecutive_stop_blocks\":null}])" "$state_file" 2>/dev/null; then
      return 0
    fi
    echo "[runtime_metrics] yq write failed, attempting fallback" >&2
  fi

  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    STATE_FILE_PATH="$state_file" \
    METRIC_TIMESTAMP="$timestamp" \
    METRIC_CACHE_CREATION="$cache_creation" \
    METRIC_CACHE_READ="$cache_read" \
    METRIC_INPUT_TOKENS="$input_tokens" \
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
    entry = {
        'boundary': 'session_compaction',
        'stop_reason': None,
        'timestamp': os.environ['METRIC_TIMESTAMP'],
        'cache_creation_input_tokens': numeric_or_null(os.environ['METRIC_CACHE_CREATION']),
        'cache_read_input_tokens': numeric_or_null(os.environ['METRIC_CACHE_READ']),
        'input_tokens': numeric_or_null(os.environ['METRIC_INPUT_TOKENS']),
        'consecutive_stop_blocks': None,
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

  # Pure-shell last-resort append (assumes runtime_metrics: is the last top-level key).
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
  - boundary: session_compaction
    stop_reason: null
    timestamp: $timestamp
    cache_creation_input_tokens: $cache_creation
    cache_read_input_tokens: $cache_read
    input_tokens: $input_tokens
    consecutive_stop_blocks: null
EOF
  return 0
}

# Discover all autopilot-state.yaml files and write a session_compaction
# entry to each. Both legacy briefs/active and product_backlog locations
# are scanned (matches autopilot-continue.sh discovery semantics).
PC_STATE_FILES=()
for _root in .simple-workflow/backlog/briefs/active .simple-workflow/backlog/product_backlog; do
  [ -d "$_root" ] || continue
  while IFS= read -r _sf; do
    [ -n "$_sf" ] && [ -f "$_sf" ] && PC_STATE_FILES+=("$_sf")
  done < <(find "$_root" -type f -name 'autopilot-state.yaml' 2>/dev/null | sort -u)
done
unset _root _sf

for _state_file in "${PC_STATE_FILES[@]:-}"; do
  [ -n "$_state_file" ] && _pc_append_session_compaction "$_state_file"
done
unset _state_file

exit 0
