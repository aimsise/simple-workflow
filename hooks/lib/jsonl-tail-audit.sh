#!/usr/bin/env bash
# jsonl-tail-audit.sh — tail-bounded JSONL transcript helpers.
#
# Sourced by (current):
#   - hooks/pre-bash-contract-guard.sh (PreToolUse:Bash guard)
#   - tests/test-hooks-lib.sh (unit tests for these helpers)
#
# Planned consumers (foundation-2):
#   - hooks/pre-agent-contract-guard.sh (PreToolUse:Agent guard)
#   - hooks/pre-skill-contract-guard.sh (PreToolUse:Skill guard)
#   - hooks/post-autopilot-log-verify.sh (PostToolUse observer)
#
# Public contract (do not change without updating the consumers above):
#
#   jsonl_tail_skill_uses <transcript_path>
#     - Emits the .input.skill value for every Skill tool_use found within
#       the last 500 lines of the transcript, one per line, in document order.
#     - Returns empty stdout when the file is empty, absent, or has no Skill
#       tool_use entries in the tail window. Exits 0 always.
#
#   jsonl_tail_agent_uses <transcript_path>
#     - Emits the .input.subagent_type value for every Agent tool_use found
#       within the last 500 lines of the transcript, one per line, in document
#       order. Same empty-input and exit-0 contract as jsonl_tail_skill_uses.
#
#   jsonl_tail_tool_use_count <transcript_path> <tool_name>
#     - Counts occurrences of tool_use entries with .name == <tool_name> in
#       the last 500 lines of the transcript.
#     - Emits a single non-negative integer. Exits 0 always.
#
#   jsonl_tail_most_recent_skill <transcript_path>
#     - Emits the .input.skill of the LAST Skill tool_use in the tail-500
#       window (the most recent Skill invocation). Empty stdout when absent.
#       Exits 0 always.
#
#   transcript_contains_skill_invocation <skill_name> <transcript_path>
#     - Returns 0 when the last `_JTA_CROSS_SESSION_TAIL` lines of
#       <transcript_path> contain at least one Skill tool_use whose
#       .input.skill equals <skill_name>; returns 1 when no match (or when
#       the transcript is empty / missing / jq is unavailable). Used by
#       impl-checkpoint-guard.sh as the cross-session staleness guard
#       (5-AND condition (e)).
#     - Window size: this helper uses a LARGER window (5000 lines) than the
#       general-purpose helpers above (500 lines). The /impl Skill
#       invocation that triggered the /audit handoff can be hundreds or
#       thousands of records back when an autopilot run accumulates many
#       tool calls (read/edit/bash/grep) plus retry rounds before /audit
#       fires. Empirically a typical 1-3 round /impl session is ~1500
#       transcript lines; the 5000-line window gives ~3x headroom for
#       longer chains while keeping the scan O(1) wrt total session age
#       (`tail -n 5000 | jq` is ~50ms on a 6.6 MB transcript). Going below
#       5000 risked silent fail-OPEN on long autopilot runs.
#
# All reads go through a `tail -n` window so the scan is bounded.
# This file does not introduce any environment-variable knob that disables
# the helpers. If a downstream caller needs to bypass detection (e.g. for
# tests), it should call into the helper with a controlled fixture path.

# ---------------------------------------------------------------------------
# Internal constants.
# ---------------------------------------------------------------------------

# Tail-window size for transcript_contains_skill_invocation (cross-session
# staleness guard). Separate from the 500-line literal used in the other
# helpers — see the header for the rationale. Intentionally NOT `readonly`:
# this lib is sourced by hook scripts that may chain into other hooks which
# also source it, and `readonly X=...` would hard-error on the second source
# under `set -e`.
_JTA_CROSS_SESSION_TAIL=5000

# ---------------------------------------------------------------------------
# Internal helpers (not part of the public contract).
# ---------------------------------------------------------------------------

# _jta_have_jq -> emits error to stderr and returns 2 if jq is not on PATH.
_jta_have_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'jsonl-tail-audit: jq is required but not found\n' >&2
    return 2
  fi
}

# _jta_iter_tool_uses <transcript_path> <tool_name> <output_field>
#   Reads the last 500 lines of <transcript_path> via `tail -n 500`,
#   finds every assistant line whose content array contains a tool_use
#   entry with .name == <tool_name>, and emits .input.<output_field>
#   for each match, one value per line, in document order.
#   Returns empty stdout on any mismatch or jq error. Exits 0 always.
#
#   NOTE: <output_field> must be a trusted, internal-only string — it
#   is used as a dynamic object key (.input[$field]) in the jq filter
#   and must never be derived from untrusted / user-supplied input.
#
#   NOTE: `2>/dev/null` on the jq call is intentional fail-open
#   behaviour: corrupt or truncated JSONL lines are silently skipped
#   so the library never aborts a hook on a malformed transcript.
#   Downstream guard hooks must treat "no output" as "no matches found"
#   rather than as a confirmed clean state when transcript integrity
#   cannot be assumed.
_jta_iter_tool_uses() {
  local transcript="$1"
  local tool_name="$2"
  local output_field="$3"
  _jta_have_jq || return 2
  [ -f "$transcript" ] || return 0
  tail -n 500 -- "$transcript" \
    | jq -r --arg name "$tool_name" --arg field "$output_field" '
        select(.type=="assistant")
        | ((.message.content // .content) // [])
        | .[]?
        | select(.type=="tool_use" and .name==$name)
        | select(.input[$field] != null and .input[$field] != "")
        | .input[$field]
      ' 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# Public function: jsonl_tail_skill_uses
# Usage: jsonl_tail_skill_uses <transcript_path>
# ---------------------------------------------------------------------------
jsonl_tail_skill_uses() {
  _jta_iter_tool_uses "$1" "Skill" "skill"
}

# ---------------------------------------------------------------------------
# Public function: jsonl_tail_agent_uses
# Usage: jsonl_tail_agent_uses <transcript_path>
# ---------------------------------------------------------------------------
jsonl_tail_agent_uses() {
  _jta_iter_tool_uses "$1" "Agent" "subagent_type"
}

# ---------------------------------------------------------------------------
# Public function: jsonl_tail_tool_use_count
# Usage: jsonl_tail_tool_use_count <transcript_path> <tool_name>
# ---------------------------------------------------------------------------
jsonl_tail_tool_use_count() {
  local transcript="$1"
  local tool_name="$2"
  _jta_have_jq || { printf '0\n'; return 0; }
  [ -f "$transcript" ] || { printf '0\n'; return 0; }
  # Count matching tool_use entries directly (no output-field projection) to
  # avoid the degenerate-record overcounting that `.input[$field] // ""` causes.
  tail -n 500 -- "$transcript" \
    | jq --arg name "$tool_name" '
        select(.type=="assistant")
        | ((.message.content // .content) // [])
        | .[]?
        | select(.type=="tool_use" and .name==$name)
        | 1
      ' 2>/dev/null \
    | wc -l | tr -d ' '
  return 0
}

# ---------------------------------------------------------------------------
# Public function: jsonl_tail_most_recent_skill
# Usage: jsonl_tail_most_recent_skill <transcript_path>
# ---------------------------------------------------------------------------
jsonl_tail_most_recent_skill() {
  _jta_iter_tool_uses "$1" "Skill" "skill" | tail -n 1
}

# ---------------------------------------------------------------------------
# Public function: transcript_contains_skill_invocation
# Usage: transcript_contains_skill_invocation <skill_name> <transcript_path>
# ---------------------------------------------------------------------------
transcript_contains_skill_invocation() {
  local skill_name="$1"
  local transcript="$2"
  [ -n "$skill_name" ] || return 1
  [ -n "$transcript" ] || return 1
  [ -f "$transcript" ] || return 1

  # Tier 1: jq (preferred; same engine as the rest of this file).
  if command -v jq >/dev/null 2>&1; then
    local found
    found=$(tail -n "$_JTA_CROSS_SESSION_TAIL" -- "$transcript" 2>/dev/null \
      | jq -r --arg name "$skill_name" '
          select(.type=="assistant")
          | ((.message.content // .content) // [])
          | .[]?
          | select(.type=="tool_use" and .name=="Skill" and (.input.skill // "")==$name)
          | "1"
        ' 2>/dev/null \
      | head -n 1)
    if [ "$found" = "1" ]; then
      return 0
    fi
    return 1
  fi

  # Tier 2: python3 + json (no PyYAML required; transcripts are JSONL).
  if command -v python3 >/dev/null 2>&1; then
    if tail -n "$_JTA_CROSS_SESSION_TAIL" -- "$transcript" 2>/dev/null | python3 - "$skill_name" <<'PY'
import json, sys
target = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        rec = json.loads(line)
    except Exception:
        continue
    if rec.get("type") != "assistant":
        continue
    msg = rec.get("message") or {}
    content = msg.get("content") if isinstance(msg, dict) else None
    if content is None:
        content = rec.get("content") or []
    if not isinstance(content, list):
        continue
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") != "tool_use":
            continue
        if block.get("name") != "Skill":
            continue
        inp = block.get("input") or {}
        if isinstance(inp, dict) and inp.get("skill") == target:
            sys.exit(0)
sys.exit(1)
PY
    then
      return 0
    fi
    return 1
  fi

  # Tier 3: pure grep on the tail window. The transcript is JSONL, so each
  # tool_use record is a single line containing `"name":"Skill"` and
  # `"skill":"<name>"` literals. False positives from prose are negligible
  # because the assistant content is JSON-encoded in the transcript itself.
  if tail -n "$_JTA_CROSS_SESSION_TAIL" -- "$transcript" 2>/dev/null \
        | grep -F '"name":"Skill"' \
        | grep -qF "\"skill\":\"$skill_name\""; then
    return 0
  fi
  return 1
}

# Export the public functions so children that re-enter bash via `bash -c`
# can pick them up without re-sourcing. (Bash only — POSIX `sh` ignores
# `export -f`. Hooks already require Bash, so this is safe.)
export -f jsonl_tail_skill_uses jsonl_tail_agent_uses jsonl_tail_tool_use_count jsonl_tail_most_recent_skill transcript_contains_skill_invocation 2>/dev/null || true
