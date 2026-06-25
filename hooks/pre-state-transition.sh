#!/usr/bin/env bash
# pre-state-transition.sh -- PreToolUse:Write/Edit hook (PX-04) that blocks
# unauthorized `status: skipped` transitions in autopilot-state.yaml /
# phase-state.yaml writes.
#
# Companion to:
#   - hooks/lib/forbidden-rationale-patterns.sh (PX-01): single source of
#     truth for the FORBIDDEN_RATIONALE_PATTERNS array. This hook MUST NOT
#     redefine the patterns locally -- it iterates the imported array.
#   - hooks/lib/parse-state-file.sh (PX-01): provides is_autopilot_context
#     so the hook only activates when the caller is operating inside an
#     autopilot run.
#
# Public contract (hook input / output):
#   stdin:  JSON payload provided by the Claude Code harness, e.g.
#           Write: {"tool_name":"Write","tool_input":{"file_path":"...",
#                   "content":"..."}, "cwd":"...", ...}
#           Edit:  {"tool_name":"Edit","tool_input":{"file_path":"...",
#                   "old_string":"...","new_string":"..."}, "cwd":"...", ...}
#   stdout: empty when the write is allowed; otherwise a single JSON object
#           with shape {"decision":"block","reason":"<text>"}.
#   exit:   0 in both allow and block paths (block is conveyed via the JSON
#           decision field). Non-zero only on internal errors that prevent
#           the hook from making a decision.
#
# Detection scope (PX-04 Acceptance Criteria #2 / #3):
#   The hook activates only for Write / Edit calls whose target file
#   basename is `autopilot-state.yaml` or `phase-state.yaml`, and only
#   inside an autopilot context (see is_autopilot_context). Outside that
#   scope it is a silent no-op (NAC #1, NAC #7).
#
#   Inside scope, the hook parses the proposed write content for tickets
#   that carry `status: skipped` and applies two rules:
#
#   Rule 1 (`unauthorized_skip_with_active_siblings`):
#     If the new content marks any ticket as `status: skipped` AND at
#     least one OTHER ticket in the SAME write payload (or the existing
#     state file on disk) is `pending` / `in_progress` AND the skipped
#     ticket does NOT carry an inline `override_skip: true` flag and
#     does NOT carry a dependency-cascade `skip_reason` matching the
#     `dependency_` PREFIX form (`dependency_<dep-slug>_failed` /
#     `dependency_<dep-slug>_skipped`; the bare-token
#     `dependency_failed` / `dependency_skipped` still match) -> BLOCK.
#
#   Rule 2 (`unauthorized_skip_with_forbidden_rationale`):
#     If the new content marks any ticket as `status: skipped` and a
#     ticket-level `override_skip: true` IS present, but the same
#     ticket's `skip_reason` matches any FORBIDDEN_RATIONALE_PATTERNS
#     entry -> BLOCK. This closes the override-as-context-budget-bypass
#     escape route (NAC #10).
#
# Negative-AC posture:
#   - No environment-variable knob disables the guard (NAC #8).
#   - Override is structural: `override_skip: true` MUST sit at the same
#     indentation level as the ticket's `status:` line; a top-level or
#     comment-block placement does NOT count (NAC #3, AC #6 case (e)).
#   - Existing dependency-cascade skip logic is left intact -- a
#     `skip_reason` matching the `dependency_` PREFIX form
#     (`dependency_<dep-slug>_failed` / `dependency_<dep-slug>_skipped`,
#     with the bare `dependency_failed` / `dependency_skipped` tokens
#     still matching for back-compat) bypasses Rule 1 (NAC #4). The
#     autopilot orchestrator interpolates the dep slug between
#     `dependency_` and `_<status>` (skills/autopilot/SKILL.md Dependency
#     check), so the carve-out tolerates the slug. Rule 2 still applies
#     on top.
#   - No AskUserQuestion path; the hook either allows or emits
#     decision: block (NAC #6).
#   - ASCII only (no non-ASCII characters in this script).

set -uo pipefail

# Resolve the directory this script lives in so we can locate the helper
# library regardless of how the harness invokes it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/hooks"
# shellcheck source=lib/forbidden-rationale-patterns.sh
source "$REPO_HOOKS_DIR/lib/forbidden-rationale-patterns.sh"  # hooks/lib/forbidden-rationale-patterns.sh
# shellcheck source=lib/parse-state-file.sh
source "$REPO_HOOKS_DIR/lib/parse-state-file.sh"  # hooks/lib/parse-state-file.sh

# ===========================================================================
# Function definitions
#
# All helpers are defined before the main body so a `source` of this file
# (e.g. from tests/test-skill-contracts.sh CT-AC-51 or the WI-4 verify-
# blocks for parse_proposed_tickets) can use them without driving the
# full hook pipeline. The sourcing-detection guard below the function
# definitions short-circuits the main body when this script is sourced.
# ===========================================================================

# Emit a `decision: block` JSON object on stdout. The harness reads this
# and rejects the Write/Edit invocation; the textual reason is surfaced to
# the model so it can recover by removing the offending skip transition.
emit_block() {
  local kind="$1"
  local detail="$2"
  jq -nc \
    --arg reason "$kind: $detail" \
    '{decision:"block", reason:$reason}'
  exit 0
}

# ---------------------------------------------------------------------------
# YAML structural parser. The hook needs three signals per ticket:
# `status`, `override_skip`, `skip_reason`. Implementation strategy: prefer
# Python + PyYAML (rich + reliable), fall back to a pure-shell line parser
# that uses the indentation of each ticket's `-` marker (list form) or
# bare `<key>:` marker (WI-4 map form) as the column anchor for "this
# field belongs to this ticket".
#
# Output format (one line per ticket in the proposed CONTENT):
#   <status>|<override_skip>|<skip_reason>
# Empty fields are emitted as the literal string `(none)`.
#
# WI-4 schema-tolerance: `tickets:` may be EITHER a YAML list
# (`- logical_id: ...`) OR a YAML map (`pomodoro-timer-part-1: { ... }`).
# Both shapes are tolerated at the hook layer so a model schema slip in
# the autopilot orchestrator does not silently bypass the
# `unauthorized_skip_with_active_siblings` /
# `unauthorized_skip_with_forbidden_rationale` guards. Canonical schema
# remains the list form; map tolerance is a safety net only — SKILL
# prose enforces the canonical schema for fresh writes. Field evidence:
# `test_simple_workflow28` produced the map form and broke the LIST-only
# Python `isinstance(tickets, list)` and shell `^[[:space:]]*-` opener.
# ---------------------------------------------------------------------------
_pst_have() { command -v "$1" >/dev/null 2>&1; }

parse_proposed_tickets() {
  local content="$1"

  if _pst_have python3; then
    local out rc
    out=$(printf '%s' "$content" | python3 -c '
import sys
try:
    import yaml
except ImportError:
    sys.exit(2)
data = yaml.safe_load(sys.stdin.read()) or {}
tickets = data.get("tickets") if isinstance(data, dict) else None
# WI-4: accept both list form (canonical) and map form (tolerated).
# Map form iterates values in insertion order, matching the orchestrator
# write order; list form iterates as-is. Mirrors parse_ticket_ship_dirs.
if isinstance(tickets, dict):
    entries = list(tickets.values())
elif isinstance(tickets, list):
    entries = tickets
else:
    sys.exit(0)
for entry in entries:
    if not isinstance(entry, dict):
        continue
    status = entry.get("status", "")
    override = entry.get("override_skip", None)
    if isinstance(override, bool):
        override = "true" if override else "false"
    elif override is None:
        override = "(none)"
    else:
        override = str(override).lower()
    reason = entry.get("skip_reason", None)
    if reason is None or (isinstance(reason, str) and reason.strip() == ""):
        reason = "(none)"
    else:
        reason = str(reason).replace("\n", " ").replace("\r", " ")
    head = status if status else "(none)"
    print(head + "|" + override + "|" + reason)
' 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then
      printf '%s\n' "$out"
      return 0
    fi
    # rc == 2 means PyYAML missing -> fall through to shell parser.
  fi

  # Pure-shell fallback. Walks the content line-by-line. A ticket item
  # begins with `<spaces>-<space>...` (list form, canonical) or
  # `^  <key>:[[:space:]]*$` (map form, WI-4 tolerance); subsequent lines
  # whose indentation is strictly greater than the opener's column belong
  # to that ticket.
  printf '%s' "$content" | _pst_shell_parse
}

# Pure-shell helper used when PyYAML is unavailable. WI-4 added the
# map-form opener branch alongside the original dash-form opener; both
# pin `dash_indent` (the column anchor used for "field belongs to this
# ticket" containment) to the opener's leading-space count so the field
# parser below works identically for both shapes.
_pst_shell_parse() {
  local in_tickets=0
  local have_item=0
  local dash_indent=-1
  local status="(none)" override="(none)" reason="(none)"

  flush_item() {
    if [ "$have_item" -eq 1 ]; then
      printf '%s|%s|%s\n' "$status" "$override" "$reason"
    fi
    status="(none)"; override="(none)"; reason="(none)"
    have_item=0
  }

  local raw line stripped indent
  while IFS= read -r raw || [ -n "$raw" ]; do
    line="$raw"
    # Compute leading-space count.
    stripped="${line#"${line%%[! ]*}"}"
    indent=$(( ${#line} - ${#stripped} ))

    # Top-level key (column 0, ends with `:`)
    if printf '%s' "$line" | grep -qE '^[A-Za-z0-9_-]+:[[:space:]]*$'; then
      flush_item
      if [ "$line" = "tickets:" ] || printf '%s' "$line" | grep -qE '^tickets:[[:space:]]*$'; then
        in_tickets=1
      else
        in_tickets=0
      fi
      dash_indent=-1
      continue
    fi

    [ "$in_tickets" -eq 1 ] || continue

    # Skip blank lines.
    if [ -z "$stripped" ]; then
      continue
    fi

    # A non-indented, non-blank line outside the ticket section ends it.
    if [ "$indent" -eq 0 ]; then
      flush_item
      in_tickets=0
      continue
    fi

    # Dash-prefixed item start (list form, canonical).
    if printf '%s' "$line" | grep -qE '^[[:space:]]*-[[:space:]]'; then
      flush_item
      dash_indent=$indent
      have_item=1
      # Capture inline status (e.g. `- status: skipped`).
      local rest
      rest=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*-[[:space:]]+//')
      if printf '%s' "$rest" | grep -qE '^status:[[:space:]]'; then
        status=$(printf '%s' "$rest" | sed -E 's/^status:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
      fi
      continue
    fi

    # WI-4: map-form item opener — `^  <key>:[[:space:]]*$` (a bare
    # 2-space-indented key under `tickets:` with no inline value). Treat
    # it like a dash: flush the previous item, set dash_indent to the
    # KEY's own column (so 4-space-indented sibling status: lines clear
    # the `indent > dash_indent` check), have_item=1. The key line
    # carries no inline status / override / reason — those land on the
    # 4-space-indented sibling lines below, which the existing field
    # parser handles unchanged.
    if [ "$indent" -eq 2 ] && printf '%s' "$line" | grep -qE '^  [A-Za-z0-9._-]+:[[:space:]]*$'; then
      flush_item
      dash_indent=$indent
      have_item=1
      continue
    fi

    if [ "$have_item" -ne 1 ]; then
      continue
    fi

    # Field lines belong to the current ticket only when their indent is
    # strictly greater than the dash indent.
    if [ "$indent" -le "$dash_indent" ]; then
      continue
    fi

    if printf '%s' "$line" | grep -qE '^[[:space:]]+status:[[:space:]]'; then
      status=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+status:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
      continue
    fi
    if printf '%s' "$line" | grep -qE '^[[:space:]]+override_skip:[[:space:]]'; then
      local val
      val=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+override_skip:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
      override=$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')
      continue
    fi
    if printf '%s' "$line" | grep -qE '^[[:space:]]+skip_reason:[[:space:]]'; then
      local val
      val=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+skip_reason:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
      # Strip surrounding quotes.
      val=$(printf '%s' "$val" | sed -E 's/^"(.*)"$/\1/' | sed -E "s/^'(.*)'$/\\1/")
      if [ -z "$val" ]; then
        reason="(none)"
      else
        reason="$val"
      fi
      continue
    fi
  done
  flush_item
}

# Top-level (non-ticket) override_skip detector. Used to detect malformed
# override placement: `override_skip: true` at column 0 (or in a comment
# line) MUST NOT count toward Rule 1 acceptance.
#
# Returns 0 (true) when a malformed top-level / comment override is found.
has_top_level_override_true() {
  if printf '%s' "$1" | grep -qE '^override_skip:[[:space:]]*true[[:space:]]*$'; then
    return 0
  fi
  if printf '%s' "$1" | grep -qE '^[[:space:]]*#.*override_skip[[:space:]]*:[[:space:]]*true'; then
    return 0
  fi
  return 1
}

# ===========================================================================
# Sourcing guard. When this script is sourced (e.g. by a unit test that
# wants to invoke parse_proposed_tickets in isolation), skip the main
# body so an empty stdin / unset FILE_PATH does not propagate `exit 0`
# back into the sourcing shell. The function definitions above remain
# available to the caller.
# ===========================================================================
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
  return 0 2>/dev/null || true
fi

# Read and parse the harness payload. `jq -r` returns an empty string when
# the field is absent.
INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)

# Pull the candidate content depending on tool. Write provides .content;
# Edit provides .new_string. We only inspect what the model is about to
# write -- the existing file on disk is read separately for sibling state.
CONTENT=""
if [ "$TOOL_NAME" = "Write" ]; then
  CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)
elif [ "$TOOL_NAME" = "Edit" ]; then
  CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || true)
fi

# Out-of-scope target -> silent no-op.
if [ -z "$FILE_PATH" ]; then
  exit 0
fi
BASENAME=$(basename "$FILE_PATH")
if [ "$BASENAME" != "autopilot-state.yaml" ] && [ "$BASENAME" != "phase-state.yaml" ]; then
  exit 0
fi

# Empty content -> nothing to evaluate.
if [ -z "$CONTENT" ]; then
  exit 0
fi

# Switch to the harness-provided cwd so is_autopilot_context walks the
# correct tree. Fall back to the existing PWD when the field is missing.
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD" || true
fi

# Outside an autopilot context the hook is a no-op (NAC #1).
if ! is_autopilot_context; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Detect whether the proposed CONTENT introduces a `status: skipped`
# transition for at least one ticket.
# ---------------------------------------------------------------------------
HAS_SKIPPED="false"
HAS_OVERRIDE_AT_TICKET="false"
SKIPPED_OVERRIDE_REASONS=()  # reasons for skipped tickets that DO carry override
SKIPPED_PLAIN_REASONS=()     # reasons for skipped tickets that do NOT carry override

# `parse_proposed_tickets` emits one line per ticket; we read into arrays.
PROPOSED_TICKETS_LIST=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  PROPOSED_TICKETS_LIST+=("$line")
done < <(parse_proposed_tickets "$CONTENT")

# Count statuses for sibling detection inside the same payload.
PROP_PENDING=0
PROP_IN_PROGRESS=0
PROP_TOTAL=${#PROPOSED_TICKETS_LIST[@]}

if [ "$PROP_TOTAL" -gt 0 ]; then
  for entry in "${PROPOSED_TICKETS_LIST[@]}"; do
    status=${entry%%|*}
    rest=${entry#*|}
    override=${rest%%|*}
    reason=${rest#*|}
    case "$status" in
      skipped)
        HAS_SKIPPED="true"
        if [ "$override" = "true" ]; then
          HAS_OVERRIDE_AT_TICKET="true"
          SKIPPED_OVERRIDE_REASONS+=("$reason")
        else
          SKIPPED_PLAIN_REASONS+=("$reason")
        fi
        ;;
      pending) PROP_PENDING=$((PROP_PENDING + 1)) ;;
      in_progress|in-progress) PROP_IN_PROGRESS=$((PROP_IN_PROGRESS + 1)) ;;
    esac
  done
fi

# Nothing skipped in the proposed content -> nothing for this hook to do.
if [ "$HAS_SKIPPED" != "true" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Rule 2 (forbidden-rationale override). Evaluated FIRST so that a
# legitimate-looking `override_skip: true` never wins when the rationale
# itself is forbidden. NAC #10 / AC #6 case (f).
# ---------------------------------------------------------------------------
if [ "${#SKIPPED_OVERRIDE_REASONS[@]}" -gt 0 ]; then
  for reason in "${SKIPPED_OVERRIDE_REASONS[@]}"; do
    [ "$reason" = "(none)" ] && continue
    for pat in "${FORBIDDEN_RATIONALE_PATTERNS[@]}"; do
      if printf '%s' "$reason" | grep -iE -q "$pat"; then
        emit_block "unauthorized_skip_with_forbidden_rationale" \
          "skip_reason '$reason' matches forbidden rationale pattern '$pat'. override_skip: true does not authorize a skip whose rationale matches a context-budget pattern; route through auto-compaction or unexpected_error.action: stop instead."
      fi
    done
  done
fi

# ---------------------------------------------------------------------------
# Rule 1 (unauthorized skip while siblings active). We need to know
# whether ANY sibling is `pending` or `in_progress`. Two lookup paths:
#   1. inside the same proposed payload (top-of-payload knowledge);
#   2. on disk in the existing autopilot-state.yaml (in case the payload
#      only re-emits the skipped ticket).
# ---------------------------------------------------------------------------

ACTIVE_SIBLINGS="false"
if [ "$PROP_PENDING" -gt 0 ] || [ "$PROP_IN_PROGRESS" -gt 0 ]; then
  ACTIVE_SIBLINGS="true"
fi

# When the proposed payload looks like a partial / single-ticket update
# (e.g. an Edit that only re-renders one item) we cannot tell which
# siblings are active without consulting the on-disk file. The "partial"
# heuristic: PROP_TOTAL <= 1 OR the proposed payload has fewer ticket
# entries than the on-disk file. In a full snapshot write where the
# proposal already enumerates every ticket with its terminal status, the
# proposal is the authoritative source and disk state is ignored.
if [ "$ACTIVE_SIBLINGS" != "true" ] && [ -f "$FILE_PATH" ]; then
  DISK_TICKET_COUNT=0
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    DISK_TICKET_COUNT=$((DISK_TICKET_COUNT + 1))
  done < <(parse_ticket_statuses "$FILE_PATH" 2>/dev/null || true)

  if [ "$PROP_TOTAL" -le 1 ] || [ "$PROP_TOTAL" -lt "$DISK_TICKET_COUNT" ]; then
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      case "$s" in
        pending|in_progress|in-progress)
          ACTIVE_SIBLINGS="true"
          ;;
      esac
    done < <(parse_ticket_statuses "$FILE_PATH" 2>/dev/null || true)
  fi
fi

# When no sibling is active, Rule 1 is trivially satisfied.
if [ "$ACTIVE_SIBLINGS" != "true" ]; then
  exit 0
fi

# A dependency-cascade skip is always allowed even with active siblings.
# Filter SKIPPED_PLAIN_REASONS (no override) by the dep markers; if every
# plain-skipped ticket has a dep-cascade reason, the hook lets the write
# through.
remaining_plain=0
if [ "${#SKIPPED_PLAIN_REASONS[@]}" -gt 0 ]; then
  for reason in "${SKIPPED_PLAIN_REASONS[@]}"; do
    if printf '%s' "$reason" | grep -qE 'dependency_([^[:space:]]*_)?(failed|skipped)'; then
      continue
    fi
    remaining_plain=$((remaining_plain + 1))
  done
fi

if [ "$remaining_plain" -gt 0 ]; then
  emit_block "unauthorized_skip_with_active_siblings" \
    "Cannot transition a ticket to status: skipped while a sibling is pending/in_progress without an explicit override_skip: true placed at the ticket level (and a non-forbidden skip_reason). Dependency-cascade skips (skip_reason matching the dependency_ prefix form dependency_<dep-slug>_failed / dependency_<dep-slug>_skipped, bare dependency_failed / dependency_skipped still matching) are exempt. See skills/autopilot/SKILL.md Per-ticket pipeline / Dependency check."
fi

# ---------------------------------------------------------------------------
# Structural override placement check (AC #6 case (e), NAC #3): if the
# proposal carries no in-ticket override but DOES carry a top-level (or
# commented) `override_skip: true`, the write is rejected so authors
# cannot fake a structural override by sprinkling the token at the wrong
# indentation. (`has_top_level_override_true` is defined above the
# sourcing guard alongside the other helpers.)
# ---------------------------------------------------------------------------
if [ "$HAS_OVERRIDE_AT_TICKET" != "true" ]; then
  if has_top_level_override_true "$CONTENT"; then
    emit_block "malformed_override_placement" \
      "override_skip: true must appear at the ticket level (same indentation as the ticket's status: line). Top-level or comment placement is ignored. See skills/create-ticket/references/phase-state-schema.md."
  fi
fi

# All checks passed -> allow.
exit 0
