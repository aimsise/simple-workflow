#!/usr/bin/env bash
# scout-checkpoint-guard.sh — Stop hook: prevent premature end_turn after
# /plan2doc's ssot-line + summary emit, before /scout Step 8a/9/10 finalize.
#
# Failure mode: when /scout invokes /plan2doc via the Skill tool, the
# delegate emits the ssot-line `plan2doc: ac-source=ticket.md verbatim=true`
# plus a structured summary (Status: success / Output: <path> / Next Steps).
# /scout treats this as its own terminal response and ends the turn —
# skipping Step 8 (print summary), 8a (state update), 9 (final summary),
# and 10 (## [SW-CHECKPOINT] emit). This hook is the harness-side
# last-resort backstop; the prompt-side first-line defense lives in
# scout/SKILL.md ### Post-/plan2doc Checklist and the existing RE-ANCHOR
# blockquote ahead of Step 8.
#
# Structural mirror of impl-checkpoint-guard.sh (v6.4.6+). Differences:
#   - Primary transcript-tail signal is the plan2doc ssot-line rather than
#     the /audit structured-block Status/Reports literals.
#   - phase-state.yaml is OPTIONAL: the failure mode this hook addresses
#     occurs in legacy product_backlog/ tickets where phase-state.yaml is
#     not present, so the hook must fire on the 3-AND transcript-tail
#     signature alone. When phase-state.yaml exists AND
#     `phases.scout.status == completed`, the hook silently exits (the
#     state machine has already advanced past scout — nothing to enforce).
#   - Counter file is independent: /tmp/.scout-checkpoint-${SESSION_ID}.
#     The hook does NOT read or write the counter paths used by the other
#     two Stop hooks; per-hook counters are session-scoped and disjoint.
#
# Block when ALL of:
#   (a) transcript tail (50 lines) contains the ssot-line literal
#       `plan2doc: ac-source=ticket.md verbatim=true`
#   (b) `## [SW-CHECKPOINT]` is NOT present in the recent assistant turn
#       (anchored on `"text":"## [SW-CHECKPOINT]` or `\n## [SW-CHECKPOINT]`
#       to exclude backtick-quoted prose mentions)
#   (c) transcript contains a `Skill(name=simple-workflow:scout)` invocation
#       (cross-session staleness guard)
#   (d) optional: when phase-state.yaml exists AND
#       `phases.scout.status == completed`, silent-exit. Otherwise
#       (file missing OR status != completed), proceed with (a)(b)(c).
#   (e) optional (v8.0.1, Step 2a — autopilot-completion gate): when NO
#       active autopilot exists (briefs/active/ + product_backlog/ carry
#       no autopilot-state.yaml) AND a briefs/done/ autopilot-state.yaml
#       is fresh (mtime within SW_AUTOPILOT_DONE_GATE_TTL_SEC seconds,
#       default 86400) AND every tickets[].status is "completed",
#       silent-exit. Required because condition (d) cannot see the moved
#       phase-state.yaml after /ship migrates the brief to briefs/done/.
#
# Kill switch (default `block`):
#   SW_SCOUT_CHECKPOINT_MODE=block        — return decision:"block" up to 3x
#   SW_SCOUT_CHECKPOINT_MODE=metric-only  — record metric only, never block
#   SW_SCOUT_CHECKPOINT_MODE=off          — record `phasegate_disabled` and exit;
#                                            CI / debug only — never production.
#   SW_AUTOPILOT_DONE_GATE_TTL_SEC=<sec>  — TTL (seconds) for Step 2a's done
#                                           state freshness window. Default
#                                           86400 (24 h). Set 0 to disable
#                                           the TTL bound (gate fires on any
#                                           all-completed done state). Any
#                                           non-numeric value falls back to
#                                           86400 with a one-line stderr
#                                           warning.
#
# Loop guard: counter at /tmp/.scout-checkpoint-${SESSION_ID}; release at 3.
# Release stdout pattern: `[SCOUT-CHECKPOINT-RELEASE] ... Resume with: /scout
# <ticket-dir>` outside autopilot context, or `... Resume with: /autopilot
# <parent-slug>` inside autopilot context (mirrors impl-checkpoint-guard.sh).
#
# Stop chain order (hooks/hooks.json): scout-checkpoint-guard.sh runs
# AFTER the impl-handoff Stop hook and BEFORE the autopilot Stop hook.
# The three hooks evaluate INDEPENDENTLY in /autopilot context — each
# uses its own session-scoped counter prefix under /tmp; the prefixes
# are disjoint (one per hook). In a single Stop firing, at most ONE of
# the impl / scout hooks will match its transcript-tail signature
# (different Skill delegates), so double-block is structurally impossible.

set -euo pipefail

INPUT=$(cat 2>/dev/null || echo '{}')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/parse-state-file.sh
source "$SCRIPT_DIR/lib/parse-state-file.sh"
# shellcheck source=hooks/lib/jsonl-tail-audit.sh
source "$SCRIPT_DIR/lib/jsonl-tail-audit.sh"
# shellcheck source=hooks/lib/runtime-metrics.sh
source "$SCRIPT_DIR/lib/runtime-metrics.sh"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

# --- Helpers ---------------------------------------------------------------

_runtime_metrics_payload_field() {
  local field="$1"
  local payload="$INPUT"
  [ -n "$payload" ] || payload='{}'
  local value
  value=$(printf '%s' "$payload" | jq -r --arg f "$field" '.[$f] // "null"' 2>/dev/null) || value="null"
  if [ -z "$value" ] || [ "$value" = "null" ]; then printf 'null'; else printf '%s' "$value"; fi
}

# Emit a runtime_metrics entry. NO-OP when no phase-state.yaml exists for
# the current ticket (legacy product_backlog flow). This is the principal
# observability difference from impl-checkpoint-guard.sh, which always has
# a STATE_FILE to write to because its (a)(b)(c)(d) preconditions include
# the file's presence.
_emit_metrics() {
  local stop_reason="$1"
  local consecutive="${2:-null}"
  [ -n "${STATE_FILE:-}" ] && [ -f "${STATE_FILE:-}" ] || return 0
  local timestamp cache_creation cache_read input_tokens
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  cache_creation=$(_runtime_metrics_payload_field cache_creation_input_tokens)
  cache_read=$(_runtime_metrics_payload_field cache_read_input_tokens)
  input_tokens=$(_runtime_metrics_payload_field input_tokens)
  append_runtime_metrics_entry "$STATE_FILE" "session_end" "$stop_reason" "$timestamp" \
    "$cache_creation" "$cache_read" "$input_tokens" "$consecutive"
}

# get_active_ticket_dir — repo-relative ticket-dir for the resume hint.
# Three-tier fallback (yq -> python3+PyYAML -> awk/find). The yq / python3
# tiers parse the discovered phase-state.yaml's *own path* to derive the
# ticket-dir (`.simple-workflow/backlog/active/<ticket-dir>`). The awk tier
# falls back to the same path computation directly from `find_phase_state_file`.
get_active_ticket_dir() {
  local state_file
  state_file=$(find_phase_state_file 2>/dev/null || true)
  if [ -n "${state_file:-}" ] && [ -f "$state_file" ]; then
    # phase-state.yaml lives at
    # <root>/.simple-workflow/backlog/active/<ticket-dir>/phase-state.yaml.
    # The repo-relative ticket-dir is the second-to-last path component.
    local dir
    dir=$(dirname "$state_file")
    # Resolve to repo-relative path
    local root
    root="$(cd "$dir" && cd ../../../../.. && pwd -P 2>/dev/null || echo "")"
    if [ -n "$root" ] && [ "${dir#"$root"/}" != "$dir" ]; then
      printf '%s\n' "${dir#"$root"/}"
      return 0
    fi
    # Fallback: emit the bare ticket-dir basename when path-relativisation fails.
    printf '.simple-workflow/backlog/active/%s\n' "$(basename "$dir")"
    return 0
  fi

  # No phase-state.yaml: walk the active ticket dir to pick the most-
  # recently-modified candidate. POSIX-portable; matches the
  # `find_phase_state_file` mtime-newest heuristic in parse-state-file.sh.
  local repo_root="$PWD"
  while [ "$repo_root" != "/" ] && [ -n "$repo_root" ]; do
    [ -d "$repo_root/.simple-workflow" ] && break
    repo_root="$(dirname "$repo_root")"
  done
  local active="$repo_root/.simple-workflow/backlog/active"
  [ -d "$active" ] || return 1

  local match=""
  while IFS= read -r _d; do
    [ -d "$_d" ] || continue
    if [ -z "$match" ] || [ "$_d" -nt "$match" ]; then
      match="$_d"
    fi
  done < <(find "$active" -mindepth 1 -maxdepth 2 -type d 2>/dev/null)
  unset _d

  if [ -n "$match" ]; then
    printf '.simple-workflow/backlog/active/%s\n' "$(basename "$match")"
    return 0
  fi
  return 1
}

# get_autopilot_parent_slug — discover the autopilot parent-slug for the
# Resume command. Reused logic from impl-checkpoint-guard.sh:180 (two-pass
# search: $PWD ancestor walk-up, then mtime-newest across briefs/active +
# product_backlog).
get_autopilot_parent_slug() {
  local root
  root="$(_psf_repo_root "$PWD" 2>/dev/null || echo "$PWD")"

  # Pass 1: $PWD ancestor walk-up.
  local dir="$PWD"
  local active_root_briefs="$root/.simple-workflow/backlog/briefs/active"
  local active_root_pb="$root/.simple-workflow/backlog/product_backlog"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    local parent
    parent="$(dirname "$dir")"
    if [ "$parent" = "$active_root_briefs" ] || [ "$parent" = "$active_root_pb" ]; then
      if [ -f "$dir/autopilot-state.yaml" ]; then
        basename "$dir"
        return 0
      fi
    fi
    [ "$dir" = "$root" ] && break
    dir="$parent"
  done

  # Pass 2: mtime-newest across both roots.
  local newest=""
  for sub in "briefs/active" "product_backlog"; do
    [ -d "$root/.simple-workflow/backlog/$sub" ] || continue
    while IFS= read -r _f; do
      [ -f "$_f" ] || continue
      if [ -z "$newest" ] || [ "$_f" -nt "$newest" ]; then
        newest="$_f"
      fi
    done < <(find "$root/.simple-workflow/backlog/$sub" -name 'autopilot-state.yaml' -type f 2>/dev/null)
    unset _f
  done

  if [ -n "$newest" ]; then
    printf '%s\n' "$newest" | sed -E 's|^.*/(briefs/active\|product_backlog)/||; s|/autopilot-state.yaml$||'
    return 0
  fi
  return 1
}

# --- Step 1: discover state file (optional — may not exist) ----------------
STATE_FILE=$(find_phase_state_file 2>/dev/null || true)

# --- Step 2: kill switch ---------------------------------------------------
MODE="${SW_SCOUT_CHECKPOINT_MODE:-block}"
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

# --- Step 2a: autopilot-completion gate (v8.0.1) ---------------------------
# After /autopilot finishes a brief (every tickets[].status == "completed",
# brief moved to briefs/done/), the transcript can still carry the
# /scout Skill invocation and /plan2doc ssot-line emitted earlier in the
# pipeline. Without this gate, the existing 3-AND (Steps 5-7) would
# false-block on the autopilot-completed Stop tick because find_phase_state_file
# only scans active/ — the moved phase-state.yaml is invisible to Step 3.
#
# Silent-exit when ALL of:
#   - is_autopilot_context() is false (no active autopilot under
#     briefs/active/ or product_backlog/)
#   - find_done_autopilot_state_file returns an autopilot-state.yaml whose
#     mtime is within SW_AUTOPILOT_DONE_GATE_TTL_SEC seconds (default 86400 s
#     = 24 h)
#   - every tickets[].status in that file equals "completed"
#
# Env knob:
#   SW_AUTOPILOT_DONE_GATE_TTL_SEC=<seconds>  default 86400. Set to 0 to
#     disable the TTL check (gate fires on any all-completed done state).
#     Non-numeric values fall back to 86400 with a one-line stderr warning.
#
# The kill switch (`SW_SCOUT_CHECKPOINT_MODE=off`) in Step 2 above already
# bypasses this entire block; no further escape hatch is wired here.
if ! is_autopilot_context; then
  DONE_TTL="${SW_AUTOPILOT_DONE_GATE_TTL_SEC:-86400}"
  case "$DONE_TTL" in
    ''|*[!0-9]*)
      echo "[SCOUT-AUTOPILOT-DONE-GATE] non-numeric SW_AUTOPILOT_DONE_GATE_TTL_SEC='$DONE_TTL'; using default 86400" >&2
      DONE_TTL=86400
      ;;
  esac
  DONE_STATE_FILE=$(find_done_autopilot_state_file "$DONE_TTL" 2>/dev/null || true)
  if [ -n "${DONE_STATE_FILE:-}" ] && [ -f "$DONE_STATE_FILE" ]; then
    # Collect every tickets[].status. Fail-closed on empty list OR any
    # non-"completed" entry — both shapes signal "autopilot not finished"
    # and the gate falls through to the existing logic.
    DONE_STATUSES=$(parse_ticket_statuses "$DONE_STATE_FILE" 2>/dev/null || true)
    ALL_COMPLETED=0
    if [ -n "$DONE_STATUSES" ]; then
      ALL_COMPLETED=1
      while IFS= read -r _status; do
        [ -n "$_status" ] || continue
        if [ "$_status" != "completed" ]; then
          ALL_COMPLETED=0
          break
        fi
      done <<< "$DONE_STATUSES"
      unset _status
    fi
    if [ "$ALL_COMPLETED" = "1" ]; then
      DONE_MTIME=""
      if _m=$(stat -f %m "$DONE_STATE_FILE" 2>/dev/null) && [ -n "$_m" ]; then
        DONE_MTIME="$_m"
      elif _m=$(stat -c %Y "$DONE_STATE_FILE" 2>/dev/null) && [ -n "$_m" ]; then
        DONE_MTIME="$_m"
      fi
      unset _m
      DONE_AGE="unknown"
      if [ -n "$DONE_MTIME" ]; then
        DONE_AGE=$(( $(date +%s) - DONE_MTIME ))
      fi
      echo "[SCOUT-AUTOPILOT-DONE-GATE] silent exit (state=$DONE_STATE_FILE, age=${DONE_AGE}s)" >&2
      exit 0
    fi
  fi
fi

# --- Step 3: if phase-state.yaml exists AND scout completed, silent exit ---
# This is the only branch that consults phase-state.yaml. The hook MUST
# also fire when the file is absent (legacy product_backlog ticket flow,
# the failure mode the hook is designed to address).
if [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ]; then
  SCOUT_STATUS=$(parse_phase_status "$STATE_FILE" "scout" 2>/dev/null || echo "")
  if [ "$SCOUT_STATUS" = "completed" ]; then
    exit 0
  fi
fi

# Compute COUNTER_FILE up-front so the SW-CHECKPOINT-seen branch (below)
# can clean it on the prompt-side success path. Without this cleanup, a
# session that emitted SW-CHECKPOINT after N false-blocks would carry the
# stale counter into a subsequent re-entry of the same SESSION_ID and
# release on the next match (instead of giving a fresh 3-attempt budget).
COUNTER_FILE="/tmp/.scout-checkpoint-${SESSION_ID}"

# --- Step 4: transcript availability ---------------------------------------
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi
TAIL_50=$(tail -n 50 "$TRANSCRIPT_PATH" 2>/dev/null || echo "")
if [ -z "$TAIL_50" ]; then
  exit 0
fi

# --- Step 5: ## [SW-CHECKPOINT] in recent assistant turn -> silent exit ----
# The grep is anchored on either `"text":"## [SW-CHECKPOINT]` (start of a
# JSON-encoded text block) or `\n## [SW-CHECKPOINT]` (mid-text after a
# JSON-escaped newline). This excludes backtick-quoted prose mentions
# (e.g. instructions in scout/SKILL.md or plan2doc Summary text saying
# "emit `## [SW-CHECKPOINT]` next") which would otherwise trigger a
# false positive lag-tolerance exit.
if printf '%s\n' "$TAIL_50" | grep -qE '("text":"|\\n)## \[SW-CHECKPOINT\]'; then
  # H6: clean the counter on the prompt-side success path so a stale
  # value cannot leak into a future re-entry under the same SESSION_ID.
  rm -f "$COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- Step 6: transcript tail must contain the ssot-line literal -----------
SSOT_RE='plan2doc: ac-source=ticket\.md verbatim=true'
if ! printf '%s\n' "$TAIL_50" | grep -qE "$SSOT_RE"; then
  exit 0
fi

# --- Step 7: cross-session guard ------------------------------------------
if ! transcript_contains_skill_invocation "simple-workflow:scout" "$TRANSCRIPT_PATH"; then
  exit 0
fi

# --- 3-AND met (plus optional state guard above). Counter management ------
BLOCK_COUNT=0
if [ "$SESSION_ID" != "unknown" ] && [ -f "$COUNTER_FILE" ]; then
  BLOCK_COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  case "$BLOCK_COUNT" in *[!0-9]*|"") BLOCK_COUNT=0 ;; esac
  # Reset on state-file progress (mirrors impl-checkpoint-guard.sh /
  # autopilot-continue.sh). When STATE_FILE is absent this branch never
  # fires — fine, because the only way state mtime can advance is when
  # phase-state.yaml exists.
  if [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ] && [ "$STATE_FILE" -nt "$COUNTER_FILE" ]; then
    BLOCK_COUNT=0
  fi
fi

# --- metric-only mode: record observation, never block --------------------
if [ "$MODE" = "metric-only" ]; then
  _emit_metrics "premature_plan2doc_handoff_blocked" "$BLOCK_COUNT"
  exit 0
fi

# --- block mode: release at 3 ---------------------------------------------
if [ "$BLOCK_COUNT" -ge 3 ] 2>/dev/null; then
  if is_autopilot_context; then
    PARENT_SLUG=$(get_autopilot_parent_slug 2>/dev/null || echo "")
    if [ -z "$PARENT_SLUG" ]; then
      PARENT_SLUG="<parent-slug>"
    fi
    echo "[SCOUT-CHECKPOINT-RELEASE] Pipeline halted: 3 consecutive end_turn attempts after /plan2doc. Resume with: /autopilot ${PARENT_SLUG}"
  else
    TICKET_DIR=$(get_active_ticket_dir 2>/dev/null || true)
    if [ -n "${TICKET_DIR:-}" ]; then
      echo "[SCOUT-CHECKPOINT-RELEASE] Pipeline halted: 3 consecutive end_turn attempts after /plan2doc. Resume with: /scout ${TICKET_DIR}"
    else
      echo "[SCOUT-CHECKPOINT-RELEASE] Pipeline halted: 3 consecutive end_turn attempts after /plan2doc. Resume with: /scout <ticket-dir> (auto-detect failed; specify manually)"
    fi
  fi
  echo "[SCOUT-CHECKPOINT-RELEASE] release after $BLOCK_COUNT blocks" >&2
  _emit_metrics "phasegate_released_after_N_blocks" "$BLOCK_COUNT"
  rm -f "$COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- block: increment counter, emit decision:block, record metric ---------
BLOCK_COUNT=$((BLOCK_COUNT + 1))
if [ "$SESSION_ID" != "unknown" ]; then
  echo "$BLOCK_COUNT" > "$COUNTER_FILE"
fi

_emit_metrics "premature_plan2doc_handoff_blocked" "$BLOCK_COUNT"

jq -n '{
  decision: "block",
  reason: "/plan2doc emitted its ssot-line (plan2doc: ac-source=ticket.md verbatim=true), but /scout Step 10 (## [SW-CHECKPOINT]) is missing. Execute Steps 8/8a/9/10 immediately: print the plan summary (Step 8), update phase-state.yaml phases.scout.status=completed if the file exists (Step 8a), print the final summary with paths and size (Step 9), and emit the ## [SW-CHECKPOINT] block (Step 10). ALL of Steps 8/8a/9/10 must be executed in this turn. Do NOT end your turn or treat the plan2doc summary as your final response."
}'
exit 0
