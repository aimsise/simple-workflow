#!/usr/bin/env bash
# detect-policy-gate-stop.sh — single source of truth for detecting a
# model-declared autopilot policy-gate hard-stop in a transcript's LAST
# assistant turn.
#
# Background: the /autopilot orchestrator, when it legitimately hard-stops,
# emits the marker line
#   [AUTOPILOT-POLICY] gate=<gatename> action=stop reason=<...>
# in its assistant text (mandated by skills/autopilot/SKILL.md — see the
# `policy_gate_stop` exit path described at ## Non-interactive orchestrator
# contract and Phase 1 steps 1 / 3 / 5). The three autopilot Stop hooks
# (autopilot-continue.sh, impl-checkpoint-guard.sh, scout-checkpoint-guard.sh)
# would otherwise keep re-injecting "Do NOT stop" because they only look at
# pending steps in the state file and ignore the model's declared stop. This
# helper lets all three honour the declaration via ONE detection definition
# (DRY) rather than three inlined regexes.
#
# Sourced by:
#   - hooks/autopilot-continue.sh        (Stop hook — honour gate)
#   - hooks/impl-checkpoint-guard.sh     (Stop hook — honour gate)
#   - hooks/scout-checkpoint-guard.sh    (Stop hook — honour gate)
#   - tests/test-detect-policy-gate-stop.sh (unit tests for this helper)
#
# Public contract:
#
#   last_turn_declares_policy_gate_stop <transcript_path>
#     - Returns 0 iff the LAST assistant turn in the JSONL transcript at
#       <transcript_path> contains, inside a `text`-type content block, the
#       marker matching `[AUTOPILOT-POLICY] ... action=stop` on one logical
#       line.
#     - Returns 1 (non-zero) for any of:
#         * no marker anywhere;
#         * the marker only in an EARLIER (non-last) assistant turn;
#         * the marker only inside a tool_use input (not a text block);
#         * missing / empty / unreadable / malformed transcript;
#         * jq unavailable.
#     - NEVER crashes. A clean non-zero return is the failure mode — the
#       caller treats "no honour" as the safe default (the existing loop
#       guards remain the backstop).
#
# "LAST assistant turn" = the last JSONL record with `.type == "assistant"`
# (matching the convention `autopilot-continue.sh` already uses for its
# NOTOOL detection: `grep '"role":"assistant"' | tail -1`). Detection is
# scoped to that single record's `text` content blocks so that a marker the
# model quoted in an earlier turn, or one embedded in a tool_use input, does
# NOT trigger a false honour.
#
# `set -euo pipefail` is intentionally NOT set here. This file is sourced by
# hook scripts and tests that already declare their own shell flags; setting
# them again would override the caller's configuration. The other
# hooks/lib/*.sh files follow the same convention.

# Canonical marker pattern (ERE). The SINGLE definition of the detection
# regex (AC-6): the three Stop hooks obtain detection only by calling
# `last_turn_declares_policy_gate_stop`, never by re-inlining this pattern.
# Matches `[AUTOPILOT-POLICY]` ... `action=stop` on one logical line, with
# any `gate=`/`reason=` text in between. The `[[:space:]]` between the
# literal pieces tolerates the canonical `gate=<name> action=stop` ordering
# (the only ordering SKILL.md mandates). Intentionally NOT `readonly`: this
# lib may be sourced more than once when several hooks chain in the same
# process, and `readonly X=...` would hard-error on the second source under
# `set -e`.
_DPGS_MARKER_RE='\[AUTOPILOT-POLICY\][^"]*action=stop'

# last_turn_declares_policy_gate_stop <transcript_path>
last_turn_declares_policy_gate_stop() {
  local transcript="${1:-}"
  [ -n "$transcript" ] || return 1
  [ -f "$transcript" ] || return 1
  # Empty file → no declaration.
  [ -s "$transcript" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  # Extract the LAST assistant record from the tail window. The window is
  # bounded so the scan is O(1) wrt total session age; 200 lines comfortably
  # covers the trailing assistant turn plus its surrounding tool_result /
  # user records even on a busy turn. `grep '"type":"assistant"'` mirrors the
  # tail-based selection autopilot-continue.sh already relies on; the
  # subsequent `jq` re-parses the single JSON line so a literal that merely
  # appears inside a tool_use input (not a text block) is excluded.
  local last_turn
  last_turn=$(tail -n 200 -- "$transcript" 2>/dev/null \
    | grep -E '"type":"assistant"' \
    | tail -n 1 || true)
  [ -n "$last_turn" ] || return 1

  # Concatenate every `text`-type content block in the last assistant turn
  # into a single string, then test it against the marker pattern. A marker
  # inside a `tool_use` input never reaches `texts` because the filter keeps
  # only `select(.type=="text") | .text`. jq parse errors (malformed line)
  # are swallowed and yield empty output → non-zero return.
  local texts
  texts=$(printf '%s\n' "$last_turn" | jq -r '
      ((.message.content // .content) // [])
      | (if type == "array" then . else [] end)
      | map(select(.type == "text") | (.text // ""))
      | join("\n")
    ' 2>/dev/null || true)
  [ -n "$texts" ] || return 1

  if printf '%s\n' "$texts" | grep -qE "$_DPGS_MARKER_RE"; then
    return 0
  fi
  return 1
}

# Export the public function so children that re-enter bash via `bash -c`
# can pick it up without re-sourcing. (Bash only — POSIX `sh` ignores
# `export -f`. Hooks already require Bash, so this is safe.)
export -f last_turn_declares_policy_gate_stop 2>/dev/null || true
