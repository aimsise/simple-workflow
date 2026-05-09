#!/usr/bin/env bash
# impl-checkpoint-guard.sh — Stop hook: prevent premature end_turn after
# /audit's structured block emit, before /impl Step 18 + Phase 3 finalize.
#
# Failure mode (recurring): when /impl invokes /audit via the Skill tool,
# the agent emits /audit's structured block (`**Status**: ... **Reports**:
# ...`) and immediately ends the turn — skipping /impl Step 18 (Combined
# Decision) and Phase 3 (`## [SW-CHECKPOINT]` emit, `phases.impl.status:
# completed`). This hook is the harness-side last-resort backstop; the
# prompt-side first-line defense lives in audit/SKILL.md Step 4-bis and
# impl/SKILL.md Step 17.
#
# Block when ALL of:
#   (a) transcript tail (50 lines) contains both `**Status**:` AND
#       `**Reports**:` literals (audit-block-pattern.sh)
#   (b) phases.impl.next_action ∉ {null, "", proceed-to-phase-3, stop-critical}
#       (denylist; fail-closed on unknown values)
#   (c) phases.impl.status != completed
#   (d) `## [SW-CHECKPOINT]` is NOT present in the recent assistant turn
#   (e) transcript contains a `Skill(name=simple-workflow:impl)` invocation
#       (cross-session staleness guard)
#
# Kill switch (default `block`):
#   SW_IMPL_CHECKPOINT_MODE=block        — return decision:"block" up to 3x
#   SW_IMPL_CHECKPOINT_MODE=metric-only  — record metric only, never block
#   SW_IMPL_CHECKPOINT_MODE=off          — record `phasegate_disabled` and exit;
#                                           CI / debug only — never production.
#
# Loop guard: counter at /tmp/.impl-checkpoint-${SESSION_ID}; release at 3.
# Release stdout pattern: `[IMPL-CHECKPOINT-RELEASE] ... Resume with: /impl
# <plan-path>` outside autopilot context, or `... Resume with: /autopilot
# <parent-slug>` inside autopilot context (mirrors autopilot-continue.sh:295).
#
# Stop chain order (registered in hooks/hooks.json): impl-checkpoint-guard.sh
# runs BEFORE autopilot-continue.sh. Both hooks evaluate INDEPENDENTLY in
# /autopilot context — this hook does NOT short-circuit on
# `is_autopilot_context()` for the block decision (only for the release UX
# branch). Counter file is independent of autopilot-continue.sh's
# `/tmp/.autopilot-continue-${SESSION_ID}`. The asymmetric release threshold
# (impl-checkpoint at 3, autopilot at 5+ FILE_COUNT) is intentional: the
# point-pinpoint detection here catches post-/audit handoff failures while
# autopilot-continue.sh preserves the broader phase-level loop guard.
# Cumulative max attempts before pipeline halt in autopilot context: ~8.
# (See addendum §13.A-3 for the design rationale.)

set -euo pipefail

INPUT=$(cat 2>/dev/null || echo '{}')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/audit-block-pattern.sh
source "$SCRIPT_DIR/lib/audit-block-pattern.sh"
# shellcheck source=hooks/lib/parse-state-file.sh
source "$SCRIPT_DIR/lib/parse-state-file.sh"
# shellcheck source=hooks/lib/jsonl-tail-audit.sh
source "$SCRIPT_DIR/lib/jsonl-tail-audit.sh"
# shellcheck source=hooks/lib/runtime-metrics.sh
source "$SCRIPT_DIR/lib/runtime-metrics.sh"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

# --- Step 1: phase-state.yaml not found → silent exit ---
STATE_FILE=$(find_phase_state_file 2>/dev/null || true)
if [ -z "${STATE_FILE:-}" ] || [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# --- Helpers ---

_runtime_metrics_payload_field() {
  local field="$1"
  local payload="${INPUT:-}"
  [ -n "$payload" ] || payload='{}'
  local value
  value=$(printf '%s' "$payload" | jq -r --arg f "$field" '.[$f] // "null"' 2>/dev/null) || value="null"
  if [ -z "$value" ] || [ "$value" = "null" ]; then printf 'null'; else printf '%s' "$value"; fi
}

_emit_metrics() {
  local stop_reason="$1"
  local consecutive="${2:-null}"
  [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ] || return 0
  local timestamp cache_creation cache_read input_tokens
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  cache_creation=$(_runtime_metrics_payload_field cache_creation_input_tokens)
  cache_read=$(_runtime_metrics_payload_field cache_read_input_tokens)
  input_tokens=$(_runtime_metrics_payload_field input_tokens)
  append_runtime_metrics_entry "$STATE_FILE" "session_end" "$stop_reason" "$timestamp" \
    "$cache_creation" "$cache_read" "$input_tokens" "$consecutive"
}

# Patch 2: inline `get_plan_path` (3-tier fallback) — phases.scout.artifacts.plan.
# Kept local to this hook to avoid bloating parse-state-file.sh with a single-
# caller helper.
get_plan_path() {
  local file="$1"
  [ -n "$file" ] && [ -f "$file" ] || return 1

  if command -v yq >/dev/null 2>&1; then
    local out
    out="$(yq -r '.phases.scout.artifacts.plan // ""' "$file" 2>/dev/null || true)"
    [ "$out" = "null" ] && out=""
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    return 1
  fi

  if command -v python3 >/dev/null 2>&1; then
    local out
    out=$(python3 - "$file" <<'PY' 2>/dev/null
import sys
try:
    import yaml
except ImportError:
    sys.exit(1)
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
phases = doc.get("phases") or {}
scout = phases.get("scout") or {}
artifacts = scout.get("artifacts") or {}
val = artifacts.get("plan") or ""
print(val)
PY
)
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    return 1
  fi

  # awk fallback: walk phases -> scout -> artifacts -> plan.
  local out
  out=$(awk '
    BEGIN { in_phases = 0; in_scout = 0; in_artifacts = 0 }
    /^phases:[[:space:]]*$/ { in_phases = 1; next }
    in_phases && /^[^[:space:]]/ { in_phases = 0; in_scout = 0; in_artifacts = 0 }
    in_phases && match($0, /^[[:space:]]+([A-Za-z0-9_-]+):[[:space:]]*$/, m) {
      in_scout = (m[1] == "scout") ? 1 : 0
      in_artifacts = 0
      next
    }
    in_scout && match($0, /^[[:space:]]+artifacts:[[:space:]]*$/, _ignore) {
      in_artifacts = 1
      next
    }
    in_scout && in_artifacts && match($0, /^[[:space:]]+plan:[[:space:]]*(.*)$/, m) {
      val = m[1]
      gsub(/^"|"$/, "", val)
      gsub(/^'\''|'\''$/, "", val)
      sub(/[[:space:]]+#.*$/, "", val)
      if (val == "null" || val == "~") val = ""
      print val
      exit 0
    }
  ' "$file" 2>/dev/null || true)
  [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  return 1
}

# Patch 3: discover the autopilot parent-slug for the Resume command. The
# slug is the path between `briefs/active/` (or `product_backlog/`) and
# `/autopilot-state.yaml` — possibly nested for split runs.
get_autopilot_parent_slug() {
  local root
  root="$(_psf_repo_root "$PWD" 2>/dev/null || echo "$PWD")"
  local found=""
  for sub in "briefs/active" "product_backlog"; do
    [ -d "$root/.simple-workflow/backlog/$sub" ] || continue
    found=$(find "$root/.simple-workflow/backlog/$sub" -name 'autopilot-state.yaml' -type f 2>/dev/null | sort -u | head -1)
    if [ -n "$found" ]; then
      printf '%s\n' "$found" | sed -E "s|^.*/${sub}/||; s|/autopilot-state.yaml$||"
      return 0
    fi
  done
  return 1
}

# --- Step 2: kill switch ---
MODE="${SW_IMPL_CHECKPOINT_MODE:-block}"
case "$MODE" in
  off)
    _emit_metrics "phasegate_disabled"
    exit 0
    ;;
  metric-only|block)
    : # continue
    ;;
  *)
    # Unknown value: fail-closed to block (default behaviour).
    MODE=block
    ;;
esac

# --- Step 3: phases.impl.status == completed → silent exit ---
IMPL_STATUS=$(parse_phase_status "$STATE_FILE" "impl" 2>/dev/null || echo "")
if [ "$IMPL_STATUS" = "completed" ]; then
  exit 0
fi

# --- Step 4: ## [SW-CHECKPOINT] in recent assistant turn → silent exit ---
SW_CHECKPOINT_SEEN="false"
TAIL_50=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  TAIL_50=$(tail -n 50 "$TRANSCRIPT_PATH" 2>/dev/null || echo "")
  if printf '%s\n' "$TAIL_50" | grep -qF '## [SW-CHECKPOINT]'; then
    SW_CHECKPOINT_SEEN="true"
  fi
fi

if [ "$SW_CHECKPOINT_SEEN" = "true" ]; then
  # Positive observation: prompt-side AuditTail completed Phase 3. Record
  # `audit_handoff_via_prompt` only when an audit block AND a /impl Skill
  # invocation are also visible — otherwise a pre-existing SW-CHECKPOINT
  # in the tail would inflate the SLO denominator on unrelated turns.
  if [ -n "$TAIL_50" ] \
     && printf '%s\n' "$TAIL_50" | grep -qE -- "$AUDIT_BLOCK_PATTERN_STATUS" \
     && printf '%s\n' "$TAIL_50" | grep -qE -- "$AUDIT_BLOCK_PATTERN_REPORTS" \
     && transcript_contains_skill_invocation "simple-workflow:impl" "$TRANSCRIPT_PATH"; then
    _emit_metrics "audit_handoff_via_prompt"
  fi
  exit 0
fi

# --- Step 5: next_action denylist ---
NEXT_ACTION=$(parse_impl_next_action "$STATE_FILE" 2>/dev/null || echo "")
case "$NEXT_ACTION" in
  ""|"null"|"proceed-to-phase-3"|"stop-critical")
    exit 0
    ;;
esac

# --- Step 6: transcript tail must contain Status AND Reports literals ---
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] || [ -z "$TAIL_50" ]; then
  exit 0
fi
if ! printf '%s\n' "$TAIL_50" | grep -qE -- "$AUDIT_BLOCK_PATTERN_STATUS"; then
  exit 0
fi
if ! printf '%s\n' "$TAIL_50" | grep -qE -- "$AUDIT_BLOCK_PATTERN_REPORTS"; then
  exit 0
fi

# --- Step 7: cross-session guard ---
if ! transcript_contains_skill_invocation "simple-workflow:impl" "$TRANSCRIPT_PATH"; then
  exit 0
fi

# --- 5-AND met. Counter management. ---
COUNTER_FILE="/tmp/.impl-checkpoint-${SESSION_ID}"
BLOCK_COUNT=0
if [ "$SESSION_ID" != "unknown" ] && [ -f "$COUNTER_FILE" ]; then
  BLOCK_COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  case "$BLOCK_COUNT" in *[!0-9]*|"") BLOCK_COUNT=0 ;; esac
  # Reset on state-file progress (mirrors autopilot-continue.sh).
  if [ "$STATE_FILE" -nt "$COUNTER_FILE" ]; then
    BLOCK_COUNT=0
  fi
fi

# --- metric-only mode: record observation, never block ---
if [ "$MODE" = "metric-only" ]; then
  _emit_metrics "premature_audit_handoff_blocked" "$BLOCK_COUNT"
  exit 0
fi

# --- block mode: release at 3 ---
if [ "$BLOCK_COUNT" -ge 3 ] 2>/dev/null; then
  if is_autopilot_context; then
    PARENT_SLUG=$(get_autopilot_parent_slug 2>/dev/null || echo "")
    if [ -z "$PARENT_SLUG" ]; then
      PARENT_SLUG="<parent-slug>"
    fi
    echo "[IMPL-CHECKPOINT-RELEASE] Pipeline halted: 3 consecutive end_turn attempts after /audit. Resume with: /autopilot ${PARENT_SLUG}"
  else
    PLAN_PATH=$(get_plan_path "$STATE_FILE" 2>/dev/null || true)
    if [ -n "${PLAN_PATH:-}" ]; then
      echo "[IMPL-CHECKPOINT-RELEASE] Pipeline halted: 3 consecutive end_turn attempts after /audit. Resume with: /impl ${PLAN_PATH}"
    else
      echo "[IMPL-CHECKPOINT-RELEASE] Pipeline halted: 3 consecutive end_turn attempts after /audit. Resume with: /impl <path-to-plan.md> (auto-detect failed; specify manually)"
    fi
  fi
  echo "[IMPL-CHECKPOINT-RELEASE] release after $BLOCK_COUNT blocks" >&2
  _emit_metrics "phasegate_released_after_N_blocks" "$BLOCK_COUNT"
  rm -f "$COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- block: increment counter, emit decision:block, record metric ---
BLOCK_COUNT=$((BLOCK_COUNT + 1))
if [ "$SESSION_ID" != "unknown" ]; then
  echo "$BLOCK_COUNT" > "$COUNTER_FILE"
fi

_emit_metrics "premature_audit_handoff_blocked" "$BLOCK_COUNT"

jq -n \
  --arg path "$STATE_FILE" \
  --arg next_action "$NEXT_ACTION" \
  '{
    decision: "block",
    reason: ("/audit emitted its structured block (Status / Reports), but /impl Phase 3 has not finalized. Read " + $path + ", execute phases.impl.next_action (" + $next_action + ") immediately to continue through Step 18 → Phase 3 → ## [SW-CHECKPOINT]. Do NOT end your turn or summarize the audit.")
  }'
exit 0
