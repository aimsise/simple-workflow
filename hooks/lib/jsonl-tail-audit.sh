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
# All reads go through `tail -n 500` (literal) so the scan window is bounded.
# This file does not introduce any environment-variable knob that disables
# the helpers. If a downstream caller needs to bypass detection (e.g. for
# tests), it should call into the helper with a controlled fixture path.

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

# Export the four public functions so children that re-enter bash via `bash -c`
# can pick them up without re-sourcing. (Bash only — POSIX `sh` ignores
# `export -f`. Hooks already require Bash, so this is safe.)
export -f jsonl_tail_skill_uses jsonl_tail_agent_uses jsonl_tail_tool_use_count jsonl_tail_most_recent_skill 2>/dev/null || true
