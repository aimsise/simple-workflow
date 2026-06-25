#!/usr/bin/env bash
# post-ship-state-auto-compact.sh — PostToolUse(Write|Edit) hook.
#
# **De-facto PRIMARY auto-compact trigger** (v7 redesign — Option A; labelled
# "safety-net" by original design intent, see note below). Fires when the
# autopilot orchestrator writes `steps.ship: completed` into the brief-level
# `autopilot-state.yaml` (PostToolUse Write|Edit). This is the canonical "ship
# + tune both done" marker, and because it PRECEDES the next /scout, it is the
# trigger that actually injects `/compact` at every normal ticket boundary —
# it emits an explicit "end the turn now" instruction so the queued /compact
# can drain. Field evidence (7-ticket run): 7/7 auto_compact_inject entries
# were stop_reason "safety_net" from this hook, 0/7 "primary". In addition to
# being the de-facto primary, it covers:
#
#   1. **Last-ticket transition**: when the just-shipped ticket was the
#      FINAL one, no `Skill(simple-workflow:scout)` follows and the
#      primary trigger never fires. Safety-net still kicks /compact so
#      the autopilot completion summary lands on a fresh context.
#   2. **Autopilot flow changes**: if a future autopilot redesign re-
#      orders or replaces `/scout` as the next-ticket entry skill, the
#      primary trigger goes dark but this state-write trigger still
#      catches the boundary.
#
# Why this ends up being the de-facto primary (despite the "safety-net" name):
# By the time the orchestrator writes `steps.ship: completed`, the full ticket
# loop (scout → impl → audit → ship → tune) is complete and the model is about
# to continue into the next ticket's preamble. This hook injects an explicit
# "end the turn now, do not proceed to the next preamble" instruction at that
# state-write moment, so the queued /compact drains here — it does NOT defer to
# the next /scout. The PreToolUse(Skill:scout) hook only fires AFTER
# compact/resume and by then dedups out, so in practice this state-write hook
# is the one that actually triggers each boundary /compact.
#
# **Coordination with the dedup-fallback trigger** (pre-next-scout-auto-compact.sh):
# When both hooks see the same ticket boundary, THIS state-write hook fires
# FIRST — the `steps.ship: completed` write happens before the next /scout
# invocation (which only occurs after the compact/resume cycle). This hook
# injects /compact, touches `.auto-compact-pending`, and (via Gate 7) writes
# the `.auto-compact-last-attempt` marker. The sentinel is consumed by
# autopilot-continue.sh during the Stop yield, but the last-attempt marker
# survives compact/resume, so when the next /scout finally fires, the
# pre-next-scout hook's Gate 5 sees shipped_count unchanged within 300s and
# short-circuits. Result: exactly one /compact per ticket boundary, injected by
# this hook.
#
# **Parallel wave re-key (T-006):** under `parallel_mode != off` (resolved
# via `resolve_parallel_mode` BEFORE the L126 ship-detector early-exit) the
# trigger re-keys from "a ship completed" to "the current wave just fully
# drained". The L126 `_detect_ship_completed_in_payload || exit 0`
# early-exit is SUPPLANTED by `_detect_wave_drained_in_payload` (greps the
# payload for a flat `wave_status: drained`), so a drained write that does
# NOT also carry `ship: completed` STILL proceeds and injects exactly once
# per wave — independent of how many ship writes preceded it. (Appending
# the wave detector AFTER L126 would silently kill auto-compaction under
# parallel — a drained-only write would exit at L126 first; the resolution
# MUST precede L126.) The Gate 7 dedup marker is re-keyed to
# `wave-{CURRENT_WAVE}:{ts}` (HYPHEN in the key, SINGLE colon) so the
# shared `%%:*`/`##*:` split is byte-UNTOUCHED (R-MARKER-SPLIT eliminated),
# and `IS_LAST_TICKET` generalizes to `IS_LAST_WAVE`
# (`current_wave + 1 >= wave_count && wave_status == drained`). Serial
# (`parallel_mode` absent/off) keeps the L126 ship-detector early-exit and
# the serial `{shipped_count}:{ts}` marker VERBATIM; `metric-only` parallel
# logs the would-be wave gate then takes the SERIAL path (serial marker +
# count-based last check). Every parallel-on behaviour change is inside a
# `$PARALLEL_MODE` guard (`= off` runs the original path untouched), so the
# off path is byte-identical (same decision, same exit, no new stderr).
#
# Kill-switch (DEFAULT ON within autopilot context, shared with the
# primary):
#   SW_AUTO_COMPACT_ON_SHIP_MODE unset (in autopilot) -> on (default)
#   SW_AUTO_COMPACT_ON_SHIP_MODE=on                   -> inject /compact
#   SW_AUTO_COMPACT_ON_SHIP_MODE=metric-only          -> log only, no injection
#   SW_AUTO_COMPACT_ON_SHIP_MODE=off                  -> disabled (opt-out)
#
# State-lie protection (test_simple_workflow23 T-001 ship #1 evidence):
# In `test_simple_workflow23`, on T-001 ship #1 the model wrote
# `ship: completed` to autopilot-state.yaml BEFORE actually running the
# ship body (no git commit, no PR, no ticket move). To avoid firing
# /compact on a bogus state, Gate 5 requires the just-shipped ticket's
# directory to exist under `.simple-workflow/backlog/done/` — that move
# only happens when the ship body genuinely ran.
#
# Failure modes (unsupported terminal, jq missing, injection error,
# state-lie detected, dedup short-circuit) are silent no-ops; this hook
# MUST never block Write/Edit regardless of internal failures. A hook
# that fails its host tool would break the autopilot orchestrator's
# state-update step entirely.

set -euo pipefail

# jq is required for input parse + final hookSpecificOutput emit.
# Silent skip if missing — Write/Edit must never be blocked by this hook.
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/parse-state-file.sh"
source "$SCRIPT_DIR/lib/inject-keys.sh"
# M4 fix: source runtime-metrics so the inject-success branch can record
# an `auto_compact_inject` boundary for forensic audit trail.
source "$SCRIPT_DIR/lib/runtime-metrics.sh"

# Gate 1: file path match. The brief-level autopilot-state.yaml is the
# canonical location of `tickets[].steps.ship`. Ticket-level
# phase-state.yaml writes are handled by post-phase-checkpoint.sh and
# are NOT a ticket-boundary signal.
TOOL_FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
case "$TOOL_FILE_PATH" in
  */briefs/active/*/autopilot-state.yaml) ;;
  */briefs/done/*/autopilot-state.yaml) ;;
  */product_backlog/*/autopilot-state.yaml) ;;
  *) exit 0 ;;
esac

# Gate 2: `ship: completed` payload check. For Edit the relevant field is
# `tool_input.new_string`; for Write it is `tool_input.content`. The
# canonical schema (state-file.md) writes `      ship: completed` (flat,
# 6-space yq indent), but field evidence (test_simple_workflow27) shows
# autopilot also produces the nested form
# `      ship:\n        status: completed\n        invocation_method: skill`
# when the model merges the two parallel maps (`steps:` + `invocation_method:`)
# into a single nested map per step. WI-3 makes the gate accept BOTH
# shapes so a model schema slip cannot silently disable auto-compact;
# the SKILL layer enforces the canonical flat form for fresh writes.
# Authoritative ticket-level detection still happens at Gate 5 (yq-parsed
# via parse_ticket_ship_dirs, also schema-tolerant).
TOOL_PAYLOAD=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // ""' 2>/dev/null || echo "")
_detect_ship_completed_in_payload() {
  local payload="$1"
  # Flat form: same line "ship: completed". The trailing class also accepts the
  # inline-flow shape `steps: {…, ship: completed}` / `ship: completed,` (ST-11):
  # `}` and `,` are valid YAML flow-mapping terminators, so without them the gate
  # silently missed a template-seeded flow-form ship-completed write.
  if printf '%s' "$payload" | grep -qE '(^|[[:space:]])ship:[[:space:]]+completed([[:space:],}]|$)'; then
    return 0
  fi
  # Nested form: a line ending in `ship:` followed within 4 lines by
  # `status: completed` (POSIX awk; no PCRE / multi-line regex needed).
  printf '%s' "$payload" | awk '
    /^[[:space:]]*ship:[[:space:]]*$/ { in_ship = 1; ship_line = NR; next }
    in_ship && (NR - ship_line) <= 4 && /^[[:space:]]+status:[[:space:]]+completed[[:space:]]*$/ {
      found = 1; exit
    }
    in_ship && (NR - ship_line) > 4 { in_ship = 0 }
    END { exit !found }
  '
}

# T-006 wave-drained detector — a ~6-line sibling of
# _detect_ship_completed_in_payload. Greps the payload for a flat
# `wave_status: drained` transition (the single deterministic flip the
# single-writer orchestrator controls per wave). The same inline-flow
# terminators (`}` / `,`) are accepted as in the ship detector so a
# template-seeded flow-form `wave_status: drained` write is not missed.
_detect_wave_drained_in_payload() {
  local payload="$1"
  printf '%s' "$payload" | grep -qE '(^|[[:space:]])wave_status:[[:space:]]+drained([[:space:],}]|$)'
}

# T-006 M1 (make-or-break): resolve PARALLEL_MODE *before* the L126
# ship-detector early-exit so the parallel path NEVER hits the ship-only
# exit. Under `parallel_mode != off` the wave-drained detector SUPPLANTS
# the `_detect_ship_completed_in_payload || exit 0` gate — a
# `wave_status: drained` write that does NOT also carry `ship: completed`
# still proceeds (the N ship writes and the drained flip can be separate
# writes). Serial (parallel=off) keeps the L126 ship-detector early-exit
# VERBATIM: every parallel addition is inside `if [ "$PARALLEL_MODE" !=
# "off" ]`, so with `parallel_mode` absent/off this hook behaves exactly
# as before (same decision, same exit code, NO new stderr line).
#
# `resolve_parallel_mode` reads `parallel_mode:` from the just-written
# state file (Gate 1 guaranteed `$TOOL_FILE_PATH` is the autopilot-state.yaml
# the orchestrator wrote); a missing/unreadable file resolves `off`
# (fail-closed), preserving the serial path.
PARALLEL_MODE="$(resolve_parallel_mode "$TOOL_FILE_PATH")"
if [ "$PARALLEL_MODE" = "off" ]; then
  # Serial path — byte-identical L126 early-exit.
  _detect_ship_completed_in_payload "$TOOL_PAYLOAD" || exit 0
elif [ "$PARALLEL_MODE" = "metric-only" ]; then
  # metric-only parallel: log the would-be wave gate, then take the SERIAL
  # path (gate on ship-completed) so observation never changes behaviour.
  echo "[POST-SHIP-STATE-AUTO-COMPACT] metric-only parallel: would gate on wave_status: drained instead of ship: completed" >&2
  _detect_ship_completed_in_payload "$TOOL_PAYLOAD" || exit 0
else
  # parallel_mode=on: the L126 ship-detector early-exit is SUPPLANTED by
  # the wave-drained detector. A drained-only write (no ship: completed)
  # still proceeds; a mid-wave ship: completed write whose wave_status is
  # NOT drained exits here (defer to the wave barrier).
  _detect_wave_drained_in_payload "$TOOL_PAYLOAD" || exit 0
fi

# Gate 3: autopilot context (defence-in-depth; Gate 1 already implies it).
is_autopilot_context || exit 0

# Gate 4: kill-switch resolution. Default `on` inside autopilot.
MODE="${SW_AUTO_COMPACT_ON_SHIP_MODE:-on}"
case "$MODE" in
  on|metric-only) ;;
  off|*)          exit 0 ;;
esac

# Gate 5: state-lie protection (element-scoped — v7 CD-1 / CD-2 fix).
# Walk EVERY `tickets[]` element whose `steps.ship == "completed"` in the
# just-written payload and verify each one's `ticket_dir:` resolves to an
# existing `.simple-workflow/backlog/done/` directory. If ANY element
# fails, refuse to inject — the model is mid-state-lie.
#
# Why this is a list-walk and not a single-shot: the previous awk grepped
# globally for the first `ship: completed` and returned the most recent
# `ticket_dir:` seen so far, which silently passed Gate 5 when a multi-
# ticket payload had a genuine done/-dir T-001 followed by a lying
# active/-dir T-002 (CD-1). It also misfired when `steps:` appeared
# textually before `ticket_dir:` within an element (CD-2), inheriting
# the previous element's dir. The element-scoped helper
# `parse_ticket_ship_dirs` (hooks/lib/parse-state-file.sh) pairs each
# ship status with its OWN element's ticket_dir, so both bypasses are
# closed at the parser layer.
#
# Source-of-truth (test_simple_workflow35 fix): iterate `$TOOL_FILE_PATH`
# (the brief-side autopilot-state.yaml on disk after the PostToolUse
# write completed), NOT the Edit-tool `$TOOL_PAYLOAD` fragment. The
# fragment is a single ticket block lacking the top-level `tickets:`
# key, so `parse_ticket_ship_dirs` returns 0 entries and Gate 5 silently
# fails open. Reading the persisted state guarantees a well-formed YAML
# document with the canonical `tickets:` root key. The just-written
# change is already reflected on disk by the time PostToolUse fires.
#
# T-006 / parallel precondition (joint obligation with T-007): under
# `parallel_mode=on` the inject fires on the `wave_status: drained` write,
# and Gate 5 still walks every `ship: completed` element here. The
# orchestrator (T-007) MUST therefore complete all ticket-to-`done/` moves
# for a wave BEFORE it writes `wave_status: drained` — otherwise a drained
# write whose state still lists a just-shipped ticket under `active/` would
# be (correctly, from this gate's view) flagged as a state-lie and the
# inject skipped. Skipping is the SAFE degradation (no auto-compact at that
# boundary; the FILE_COUNT loop guard + the next drained write recover), so
# this gate is left UNCHANGED — the ordering obligation lives in the T-007
# wave-barrier write sequence, not here.
REPO_ROOT=""
if [ -n "$TOOL_FILE_PATH" ]; then
  REPO_ROOT="${TOOL_FILE_PATH%%/.simple-workflow/*}"
fi
[ -n "$REPO_ROOT" ] || REPO_ROOT="$PWD"

LIE_DETECTED=0
# Process substitution (`< <(...)`) keeps the loop in the parent shell so
# the LIE_DETECTED assignment is visible after the loop.
while IFS= read -r TICKET_DIR; do
  [ -n "$TICKET_DIR" ] || continue
  case "$TICKET_DIR" in
    /*) RESOLVED_TICKET_DIR="$TICKET_DIR" ;;
    *)  RESOLVED_TICKET_DIR="$REPO_ROOT/$TICKET_DIR" ;;
  esac
  # The ticket_dir written into autopilot-state.yaml may point at either
  # backlog/active/<slug>/<ticket>/ (mid-ship, before move) or
  # backlog/done/<slug>/<ticket>/ (post-move). Only done/ form qualifies
  # as genuine ship completion; rewrite active/ → done/ before checking
  # so a still-in-active path with a real done/ counterpart passes.
  case "$RESOLVED_TICKET_DIR" in
    */backlog/done/*) ;;
    */backlog/active/*)
      RESOLVED_TICKET_DIR="${RESOLVED_TICKET_DIR//\/backlog\/active\//\/backlog\/done\/}"
      ;;
    */backlog/product_backlog/*)
      # ST-02: a never-scouted ticket whose ticket_dir still holds the initial
      # product_backlog form would otherwise pass the -d check (the dir exists in
      # product_backlog/) and let a fabricated ship: completed inject. Rewrite to
      # the done/ form so the existence check catches the state-lie.
      RESOLVED_TICKET_DIR="${RESOLVED_TICKET_DIR//\/backlog\/product_backlog\//\/backlog\/done\/}"
      ;;
  esac
  if [ ! -d "$RESOLVED_TICKET_DIR" ]; then
    echo "[POST-SHIP-STATE-AUTO-COMPACT] state-lie protection: ticket dir not in done/ ($RESOLVED_TICKET_DIR). Skipping inject — model wrote ship: completed without actually completing ship body." >&2
    LIE_DETECTED=1
    break
  fi
done < <(parse_ticket_ship_dirs "$TOOL_FILE_PATH" 2>/dev/null)

[ "$LIE_DETECTED" = "1" ] && exit 0

# Gate 5.5 (post-ship integrity self-heal — P3-5):
#
# After Gate 5 has confirmed every `tickets[].steps.ship == completed`
# element resolves to a genuine `.simple-workflow/backlog/done/` directory,
# walk those same elements again and check each ticket's per-ticket
# `phase-state.yaml` for an `overall_status: in-progress` left over by a
# `/ship` Step 15a that was skipped or interrupted (test_simple_workflow34
# evidence: 4/5 tickets shipped with `overall_status: in-progress`
# residue). When detected, rewrite the four canonical scalars
# (`overall_status: done`, `current_phase: done`, `last_completed_phase:
# ship`, `phases.ship.status: completed`) so the per-ticket record
# matches the autopilot-state.yaml ground truth.
#
# Kill-switch: SW_POST_SHIP_INTEGRITY
#   on (default)   -> self-heal: rewrite phase-state.yaml + warn to stderr.
#   metric-only    -> warn to stderr only, NO write.
#   off / unknown  -> silent skip.
#
# Failure-mode policy (ticket Risk R3): yq -i is atomic, python3+PyYAML
# uses tempfile + rename, awk-tier rewriting is NOT attempted (silent
# skip on awk fallback to preserve the original file rather than risk
# corrupting it). If both yq and python3+PyYAML are unavailable the
# self-heal is a no-op for that file.
PSI_MODE_RAW="${SW_POST_SHIP_INTEGRITY:-on}"
case "$PSI_MODE_RAW" in
  on|metric-only|off) PSI_MODE="$PSI_MODE_RAW" ;;
  *)                  PSI_MODE="off" ;;
esac

if [ "$PSI_MODE" != "off" ]; then
  # REPO_ROOT was set by Gate 5 above. Recompute defensively for the
  # rare case where Gate 5's REPO_ROOT derivation could not run (e.g.,
  # a future refactor reorders the gates).
  PSI_REPO_ROOT="${REPO_ROOT:-}"
  if [ -z "$PSI_REPO_ROOT" ]; then
    if [ -n "$TOOL_FILE_PATH" ]; then
      PSI_REPO_ROOT="${TOOL_FILE_PATH%%/.simple-workflow/*}"
    fi
    [ -n "$PSI_REPO_ROOT" ] || PSI_REPO_ROOT="$PWD"
  fi
  # Source-of-truth (test_simple_workflow35 fix): iterate
  # `$TOOL_FILE_PATH` (the brief-side autopilot-state.yaml on disk
  # after the PostToolUse write completed), NOT the Edit-tool
  # `$TOOL_PAYLOAD` fragment. The fragment is a single ticket block
  # lacking the top-level `tickets:` key, so `parse_ticket_ship_dirs`
  # returns 0 entries and the self-heal loop silently never runs
  # (root cause of the test_simple_workflow35 ticket-001 drift residue
  # despite the hook firing 5 times). Reading the persisted state
  # guarantees a well-formed YAML document with the canonical
  # `tickets:` root key. The just-written change is already on disk
  # by the time PostToolUse fires, so the iteration includes the
  # newly-completed ticket plus every prior completed ticket — the
  # loop is idempotent on clean phase-state.yaml files (PSI AC-7), so
  # repeated sweeps cost only a parse + scalar read per clean entry.
  while IFS= read -r PSI_TICKET_DIR; do
    [ -n "$PSI_TICKET_DIR" ] || continue
    case "$PSI_TICKET_DIR" in
      /*) PSI_RESOLVED="$PSI_TICKET_DIR" ;;
      *)  PSI_RESOLVED="$PSI_REPO_ROOT/$PSI_TICKET_DIR" ;;
    esac
    # Same active/-to-done rewrite as Gate 5 — the autopilot writer
    # may still record `backlog/active/...` mid-move; the canonical
    # destination is always `backlog/done/...`.
    case "$PSI_RESOLVED" in
      */backlog/done/*) ;;
      */backlog/active/*)
        PSI_RESOLVED="${PSI_RESOLVED//\/backlog\/active\//\/backlog\/done\/}"
        ;;
      */backlog/product_backlog/*)
        # ST-02: same product_backlog-form rewrite as Gate 5 so the per-ticket
        # phase-state.yaml lookup resolves to the done/ location.
        PSI_RESOLVED="${PSI_RESOLVED//\/backlog\/product_backlog\//\/backlog\/done\/}"
        ;;
    esac
    # Strip any trailing slash so we can append /phase-state.yaml uniformly.
    PSI_RESOLVED="${PSI_RESOLVED%/}"
    PSI_PHASE_STATE="$PSI_RESOLVED/phase-state.yaml"
    [ -f "$PSI_PHASE_STATE" ] || continue
    PSI_OVERALL=$(parse_yaml_scalar "$PSI_PHASE_STATE" overall_status 2>/dev/null || true)
    if [ "$PSI_OVERALL" = "in-progress" ]; then
      echo "[POST-SHIP-INTEGRITY] self-healing $PSI_RESOLVED (overall_status was 'in-progress'; /ship Step 15a was skipped or interrupted)" >&2
      if [ "$PSI_MODE" = "metric-only" ]; then
        # SW_POST_SHIP_INTEGRITY=metric-only — log only, no write.
        continue
      fi
      if command -v yq >/dev/null 2>&1; then
        # yq -i is atomic; on failure the original file is preserved.
        yq -i '
          .overall_status = "done" |
          .current_phase = "done" |
          .last_completed_phase = "ship" |
          .phases.ship.status = "completed"
        ' "$PSI_PHASE_STATE" 2>/dev/null || \
          echo "[POST-SHIP-INTEGRITY] yq self-heal failed for $PSI_PHASE_STATE (original preserved)" >&2
      elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
        PSI_PY_TMP=$(mktemp 2>/dev/null) || PSI_PY_TMP=""
        if [ -n "$PSI_PY_TMP" ]; then
          if python3 - "$PSI_PHASE_STATE" "$PSI_PY_TMP" <<'PY' 2>/dev/null
import sys
import yaml
src, dst = sys.argv[1], sys.argv[2]
with open(src, "r", encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
doc["overall_status"] = "done"
doc["current_phase"] = "done"
doc["last_completed_phase"] = "ship"
phases = doc.setdefault("phases", {})
ship = phases.setdefault("ship", {})
ship["status"] = "completed"
with open(dst, "w", encoding="utf-8") as fh:
    yaml.safe_dump(doc, fh, sort_keys=False, default_flow_style=False)
PY
          then
            mv "$PSI_PY_TMP" "$PSI_PHASE_STATE" 2>/dev/null || \
              echo "[POST-SHIP-INTEGRITY] python3 self-heal mv failed for $PSI_PHASE_STATE (original preserved)" >&2
          else
            rm -f "$PSI_PY_TMP" 2>/dev/null || true
            echo "[POST-SHIP-INTEGRITY] python3 self-heal failed for $PSI_PHASE_STATE (original preserved)" >&2
          fi
        fi
      else
        # awk-tier rewriting deliberately not attempted (ticket Risk R3):
        # complex YAML mutation in pure awk risks corrupting the file.
        echo "[POST-SHIP-INTEGRITY] yq and python3+PyYAML both unavailable; skipping self-heal for $PSI_PHASE_STATE (original preserved)" >&2
      fi
    fi
  done < <(parse_ticket_ship_dirs "$TOOL_FILE_PATH" 2>/dev/null)
fi
unset PSI_MODE PSI_MODE_RAW PSI_TICKET_DIR PSI_RESOLVED PSI_PHASE_STATE PSI_OVERALL PSI_PY_TMP PSI_REPO_ROOT

# State file path (H5 fix): derive deterministically from $TOOL_FILE_PATH
# rather than the most-recently-modified heuristic
# `find_any_autopilot_state_file` would return. Gate 1 already guaranteed
# `$TOOL_FILE_PATH` matches `*/autopilot-state.yaml`, so it is the exact
# file the orchestrator just wrote — using it ensures the sentinel and
# loop-guard markers land in the SAME brief directory as the write, even
# when multiple briefs are concurrently active under
# `.simple-workflow/backlog/briefs/active/`. The most-recently-modified
# heuristic could otherwise pick a different brief whose autopilot-state.yaml
# happened to have a newer mtime (e.g. due to a stale touch), causing
# dedup against the wrong brief's `.auto-compact-pending` and writing
# Gate 7's marker in the wrong dir. Fallback to the slug-free finder is
# kept for defence in depth (Gate 1 broadening hypothesis).
if [ -n "$TOOL_FILE_PATH" ] && [ -f "$TOOL_FILE_PATH" ]; then
  STATE_FILE_PATH="$TOOL_FILE_PATH"
else
  STATE_FILE_PATH="$(find_any_autopilot_state_file 2>/dev/null || true)"
fi

# Gate 6: deduplicate with the primary trigger
# (pre-next-scout-auto-compact.sh). If a fresh sentinel is already in
# place for this boundary, the primary already injected /compact and we
# must NOT fire a second one.
if [ -n "$STATE_FILE_PATH" ]; then
  EXISTING_SENTINEL="$(dirname "$STATE_FILE_PATH")/.auto-compact-pending"
  if [ -f "$EXISTING_SENTINEL" ]; then
    EXISTING_TS=$(cat "$EXISTING_SENTINEL" 2>/dev/null || echo 0)
    EXISTING_NOW=$(date +%s)
    EXISTING_AGE=$((EXISTING_NOW - EXISTING_TS))
    if [ "$EXISTING_AGE" -ge 0 ] && [ "$EXISTING_AGE" -le 120 ]; then
      echo "[POST-SHIP-STATE-AUTO-COMPACT] dedup: fresh sentinel present (age=${EXISTING_AGE}s), primary trigger already injected. Skipping." >&2
      exit 0
    fi
  fi
fi

# Gate 7: shared loop-guard marker — coordinate with the primary trigger
# (pre-next-scout-auto-compact.sh) across the compact/resume cycle.
#
# Field evidence (test_simple_workflow24, session
# `48c15d9e-cfa2-4148-9268-1cfdcf9c9cbb`): 1 ticket boundary fired
# /compact TWICE because Gate 6 (sentinel dedup) does not survive the
# compact/resume cycle — `hooks/autopilot-continue.sh` consumes
# `.auto-compact-pending` when yielding the Stop tick, so by the time
# the post-compact-resumed orchestrator invokes the next `/scout`, the
# sentinel is gone and the primary trigger fires a second time. The
# primary's own Gate 5 also cannot detect this because the
# `.auto-compact-last-attempt` marker is only written by the primary
# itself — when the safety-net fires first, the marker doesn't exist.
#
# This Gate 7 makes the safety-net write the SAME marker the primary
# reads in its Gate 5: `{shipped_count}:{unix_timestamp}` at
# `<state_dir>/.auto-compact-last-attempt`. The marker file is NOT
# consumed by `autopilot-continue.sh` (only `.auto-compact-pending`
# is), so it survives the compact/resume cycle and the primary's Gate
# 5 then sees `shipped_count` unchanged within 300s and short-circuits.
# Result: exactly one /compact per ticket boundary regardless of which
# hook fires first.
#
# In addition, Gate 7 itself short-circuits when the safety-net is
# invoked twice for the same boundary (e.g. the orchestrator splits the
# `ship: completed` write across two consecutive Edit calls — the
# second Edit's `new_string` still matches Gate 2 and would otherwise
# fire a second time).
if [ -n "$STATE_FILE_PATH" ] && [ -f "$STATE_FILE_PATH" ]; then
  # WI-3 schema-tolerance: count BOTH `ship: completed` (flat) and
  # `ship:\n  status: completed` (nested) — see parse_ticket_ship_dirs
  # docstring. parse_ticket_ship_dirs walks the canonical structure via
  # yq → python3+PyYAML → POSIX awk, so a model schema slip cannot
  # silently produce shipped_count=0 (which would defeat both Gate 7
  # loop-detection and the primary's mirror Gate 4). The line count of
  # its output is the shipped ticket count.
  G7_SHIPPED_COUNT=$(parse_ticket_ship_dirs "$STATE_FILE_PATH" 2>/dev/null | grep -c . || true)
  G7_SHIPPED_COUNT="${G7_SHIPPED_COUNT:-0}"
  # T-006 dedup re-key. Serial keeps the `{shipped_count}:{ts}` marker
  # VERBATIM. ONLY under `parallel_mode = on` does the dedup key become
  # `wave-{CURRENT_WAVE}:{ts}` — a HYPHEN in the key, a SINGLE colon — so
  # the shared `%%:*` (key) / `##*:` (ts) split below is byte-UNTOUCHED
  # and works identically for both forms (R-MARKER-SPLIT eliminated, not
  # mitigated). `metric-only` parallel deliberately takes the SERIAL marker
  # (it logged the would-be wave gate above and then ran the serial gate),
  # so the re-key gates on `= on`, not `!= off`. `current_wave:` is a
  # top-level scalar in the wave cursor (T-003); a missing/blank value
  # resolves to `0` so the marker is still well-formed. The whole re-key
  # lives inside the `= on` gate, so the serial marker is byte-identical.
  G7_MARKER_KEY="$G7_SHIPPED_COUNT"
  if [ "$PARALLEL_MODE" = "on" ]; then
    G7_CURRENT_WAVE="$(parse_yaml_scalar "$STATE_FILE_PATH" current_wave 2>/dev/null || true)"
    [ -n "$G7_CURRENT_WAVE" ] || G7_CURRENT_WAVE=0
    G7_MARKER_KEY="wave-${G7_CURRENT_WAVE}"
  fi
  G7_ATTEMPT_FILE="$(dirname "$STATE_FILE_PATH")/.auto-compact-last-attempt"
  if [ -f "$G7_ATTEMPT_FILE" ]; then
    G7_PREV_LINE=$(cat "$G7_ATTEMPT_FILE" 2>/dev/null || echo "")
    G7_PREV_COUNT="${G7_PREV_LINE%%:*}"
    G7_PREV_TS="${G7_PREV_LINE##*:}"
    G7_NOW_TS=$(date +%s)
    if [ -n "$G7_PREV_COUNT" ] && [ -n "$G7_PREV_TS" ] \
       && [ "$G7_PREV_TS" -gt 0 ] 2>/dev/null \
       && [ "$G7_PREV_COUNT" = "$G7_MARKER_KEY" ]; then
      G7_AGE=$((G7_NOW_TS - G7_PREV_TS))
      if [ "$G7_AGE" -ge 0 ] && [ "$G7_AGE" -le 300 ]; then
        echo "[POST-SHIP-STATE-AUTO-COMPACT] loop-guard: marker key=${G7_MARKER_KEY} unchanged since previous attempt ${G7_AGE}s ago. Skipping inject (test_simple_workflow24 double-compact fix)." >&2
        jq -n --arg cnt "$G7_MARKER_KEY" --arg age "$G7_AGE" \
          '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("auto-compact-on-ship: loop suspected — marker key (" + $cnt + ") unchanged since previous compact " + $age + "s ago. Skipping inject (shared loop-guard marker).")}}'
        exit 0
      fi
    fi
  fi
  # Marker write must happen even when we proceed to inject so the
  # primary trigger can detect this boundary as already-handled on its
  # post-compact-resume PreToolUse(scout) fire.
  echo "${G7_MARKER_KEY}:$(date +%s)" > "$G7_ATTEMPT_FILE" 2>/dev/null || true
  # H7 fix: last-ticket detection. shipped_count == total_tickets means
  # this just-flipped `ship: completed` was for the FINAL ticket; the
  # orchestrator must run the post-loop completion phase (Split Autopilot
  # Log -> Completion Report -> Brief Lifecycle -> State File Cleanup)
  # BEFORE end_turn, otherwise those writes are skipped. For non-last
  # tickets the next-ticket preamble follows, so end_turn-now is correct.
  # The primary trigger never fires on the last ticket (no next /scout),
  # so this branch is safety-net-only.
  #
  # T-006 IS_LAST_TICKET → IS_LAST_WAVE generalization (positive
  # correctness gain). Under parallel the count-based check
  # (shipped_count == total_tickets) is WRONG: a failed/skipped ticket
  # makes shipped_count < total_tickets on the last drained wave, so the
  # post-loop instruction would never fire. The wave-cursor key keys off
  # `current_wave + 1 >= wave_count && wave_status == drained` instead.
  # Serial keeps the count-based IS_LAST_TICKET verbatim (inside `else`);
  # `metric-only` parallel runs the serial count-based check too (it took
  # the serial path above), so this gates on `= on`, not `!= off`.
  IS_LAST_TICKET=0
  if [ "$PARALLEL_MODE" = "on" ]; then
    G7_WAVE_COUNT="$(parse_yaml_scalar "$STATE_FILE_PATH" wave_count 2>/dev/null || true)"
    [ -n "$G7_WAVE_COUNT" ] || G7_WAVE_COUNT=0
    G7_WAVE_STATUS="$(parse_yaml_scalar "$STATE_FILE_PATH" wave_status 2>/dev/null || true)"
    G7_CURRENT_WAVE_LW="${G7_CURRENT_WAVE:-0}"
    [ -n "$G7_CURRENT_WAVE_LW" ] || G7_CURRENT_WAVE_LW=0
    if [ "$G7_CURRENT_WAVE_LW" -ge 0 ] 2>/dev/null \
       && [ "$G7_WAVE_COUNT" -ge 1 ] 2>/dev/null \
       && [ "$((G7_CURRENT_WAVE_LW + 1))" -ge "$G7_WAVE_COUNT" ] \
       && [ "$G7_WAVE_STATUS" = "drained" ]; then
      IS_LAST_TICKET=1
    fi
  else
    G7_TOTAL_TICKETS=$(parse_ticket_statuses "$STATE_FILE_PATH" 2>/dev/null | wc -l | tr -d ' ')
    G7_TOTAL_TICKETS="${G7_TOTAL_TICKETS:-0}"
    if [ "$G7_SHIPPED_COUNT" -ge 1 ] 2>/dev/null \
       && [ "$G7_TOTAL_TICKETS" -ge 1 ] 2>/dev/null \
       && [ "$G7_SHIPPED_COUNT" = "$G7_TOTAL_TICKETS" ]; then
      IS_LAST_TICKET=1
    fi
  fi
  # M4: preserve the shipped count for the audit-trail metrics write
  # below. The G7_* vars get unset on the next line; copy into a more
  # specific name so the inject branch can reference it.
  SHIPPED_COUNT_FOR_AUDIT="$G7_SHIPPED_COUNT"
fi
unset G7_SHIPPED_COUNT G7_ATTEMPT_FILE G7_PREV_LINE G7_PREV_COUNT G7_PREV_TS G7_NOW_TS G7_AGE G7_TOTAL_TICKETS G7_MARKER_KEY G7_CURRENT_WAVE G7_WAVE_COUNT G7_WAVE_STATUS G7_CURRENT_WAVE_LW

# metric-only branch.
if [ "$MODE" = "metric-only" ]; then
  echo "[POST-SHIP-STATE-AUTO-COMPACT] metric-only: would inject /compact (safety-net path)" >&2
  jq -n '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"auto-compact-on-ship: metric-only mode (state-write safety-net path, no injection)"}}'
  exit 0
fi

# Inject /compact via dispatcher (best-effort, never block Edit/Write).
# H9: capture inject_keys stderr so the failure path can render a
# disambiguating hint instead of the misleading "unsupported terminal"
# blanket message.
#
# P2-1: create `<state_dir>/.next-compact-pending` sentinel BEFORE the
# inject call so `hooks/session-start.sh` can detect a likely-silent
# failure on the next session boot and retry the `/compact` injection.
# Mirrors the lifecycle in pre-next-scout-auto-compact.sh — sentinel is
# deleted only on confirmed success (INJECT_RC == 0 after P1-1 verify);
# on rc=1 the sentinel is RETAINED so session-start can replay the
# inject from a fresh context.
NEXT_COMPACT_SENTINEL=""
if [ -n "$STATE_FILE_PATH" ]; then
  NEXT_COMPACT_SENTINEL="$(dirname "$STATE_FILE_PATH")/.next-compact-pending"
  date +%s > "$NEXT_COMPACT_SENTINEL" 2>/dev/null || true
fi

INJECT_TMP=$(mktemp 2>/dev/null) || INJECT_TMP=""
INJECT_RC=0
INJECT_LOG=""
if [ -n "$INJECT_TMP" ]; then
  # `|| INJECT_RC=$?` keeps set -e from tripping when the dispatcher
  # returns non-zero; the failure-path branch below needs to observe
  # rc != 0, not abort the hook.
  inject_keys '/compact' --enter 2>"$INJECT_TMP" || INJECT_RC=$?
  INJECT_LOG=$(cat "$INJECT_TMP" 2>/dev/null || echo "")
  rm -f "$INJECT_TMP" 2>/dev/null
  printf '%s\n' "$INJECT_LOG" | sed 's/^/[POST-SHIP-STATE-AUTO-COMPACT] /' >&2
else
  inject_keys '/compact' --enter 2>&1 | sed 's/^/[POST-SHIP-STATE-AUTO-COMPACT] /' >&2 || true
  INJECT_RC=${PIPESTATUS[0]}
fi

if [ "$INJECT_RC" = "0" ]; then
  if [ -n "$STATE_FILE_PATH" ]; then
    # P2-1: P1-1 verify succeeded -> sentinel role discharged, delete it.
    [ -n "$NEXT_COMPACT_SENTINEL" ] && rm -f "$NEXT_COMPACT_SENTINEL" 2>/dev/null || true
    SENTINEL="$(dirname "$STATE_FILE_PATH")/.auto-compact-pending"
    date +%s > "$SENTINEL" 2>/dev/null || true
    # M4: audit trail — one runtime_metrics entry per successful inject
    # so the user can correlate /compact fires with state transitions.
    _AC_ISO_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
    # shipped_count goes to arg9 (the dedicated field), NOT arg8
    # (consecutive_stop_blocks, which is meaningful only for session_end) — the
    # latter is passed "null" so this auto_compact_inject entry no longer
    # pollutes consecutive_stop_blocks. ${SHIPPED_COUNT_FOR_AUDIT:-null} may be
    # the literal "null" (no count resolved); runtime-metrics.sh treats "null"
    # arg9 as "omit the field", so no shipped_count: null is emitted.
    append_runtime_metrics_entry "$STATE_FILE_PATH" "auto_compact_inject" "safety_net" "$_AC_ISO_TS" "null" "null" "null" "null" "${SHIPPED_COUNT_FOR_AUDIT:-null}" 2>/dev/null || true
    unset _AC_ISO_TS
  fi
  # Safety-net additionalContext. This fires INSIDE the autopilot
  # orchestrator's same turn (state write → this hook → orchestrator
  # continues to next-ticket preamble). To stop the orchestrator from
  # immediately invoking the next scout, we ask the model to end the
  # turn now. If the primary trigger (pre-next-scout-auto-compact.sh)
  # already fired, Gate 6 above short-circuits this branch so the
  # model only sees ONE such instruction per ticket boundary.
  #
  # H7 fix: branch on last-ticket. The label
  # `auto-compact-on-ship (state-write safety-net):` is constant across
  # both branches (CT-AC-27 byte-equality + CT-AC-20 substring contract).
  # The body diverges so a literally-compliant model knows whether to
  # end_turn immediately (non-last) or first complete the post-loop
  # phase (last).
  if [ "${IS_LAST_TICKET:-0}" = "1" ]; then
    jq -n '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"auto-compact-on-ship (state-write safety-net): `/compact` has been queued. The just-shipped ticket'"'"'s `steps.ship = completed` was the FINAL ticket of this pipeline — no more tickets remain. Complete the post-loop phase FIRST (Split Autopilot Log → Completion Report → Brief Lifecycle → State File Cleanup → final `## [SW-CHECKPOINT]` per `skills/autopilot/SKILL.md` step e), THEN end the turn. Do NOT skip the post-loop writes — they finalize the brief, the runtime_metrics, and the [SW-CHECKPOINT] handoff. After end_turn the queued /compact drains; `hooks/session-start.sh` re-injects `/autopilot {parent-slug}` but the resume contract finds all tickets terminal and exits cleanly."}}'
  else
    jq -n '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"auto-compact-on-ship (state-write safety-net): `/compact` has been queued. The just-shipped ticket'"'"'s `steps.ship = completed` was just written to autopilot-state.yaml — the full ticket loop (scout → impl → audit → ship → tune) is complete. To let the queued /compact drain, end this turn now without proceeding to the next ticket'"'"'s preamble. Do NOT print a summary, do NOT issue any further tool call. After compaction, hooks/session-start.sh PTY-injects `/autopilot {parent-slug}` and the resume contract (skills/autopilot/SKILL.md:180) picks up from autopilot-state.yaml."}}'
  fi
else
  # P2-1: inject verify failed (rc=1) -> RETAIN .next-compact-pending so
  # hooks/session-start.sh can replay the `/compact` injection on the
  # next session boot. Mirrors the pre-next-scout-auto-compact.sh failure
  # path so both auto-compact triggers participate in the session-start
  # retry contract.
  echo "[POST-SHIP-STATE-AUTO-COMPACT] retaining .next-compact-pending for session-start retry (INJECT_RC=$INJECT_RC)" >&2
  INJECT_HINT=$(inject_keys_failure_hint "$INJECT_LOG")
  jq -n --arg hint "$INJECT_HINT" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("auto-compact-on-ship: injection failed — " + $hint + ". A retry will be attempted on the next session start (sentinel `.next-compact-pending` retained). User may run /compact manually.")}}'
fi
exit 0
