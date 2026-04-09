#!/usr/bin/env bash
# PreCompact hook: snapshot work state with YAML frontmatter so /catchup
# can recover the in-progress phase after context compaction.
set -euo pipefail
cat > /dev/null  # consume stdin

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_ISO=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
SAVE_FILE=".docs/compact-state/compact-state-${TIMESTAMP}.md"

mkdir -p .docs/compact-state

# Collect file lists with nullglob so empty matches yield zero-length arrays.
shopt -s nullglob
ACTIVE_TICKET_FILES=(.backlog/active/*/ticket.md)
ACTIVE_BACKLOG_PLAN_FILES=(.backlog/active/*/plan.md)
ACTIVE_DOCS_PLAN_FILES=(.docs/plans/*.md)
EVAL_ROUND_FILES=(.backlog/active/*/eval-round-*.md)
QUALITY_ROUND_FILES=(.backlog/active/*/quality-round-*.md)
shopt -u nullglob

# Compute the maximum round number from a list of files matching *-N.md.
LATEST_EVAL_ROUND=0
if [ "${#EVAL_ROUND_FILES[@]}" -gt 0 ]; then
  for f in "${EVAL_ROUND_FILES[@]}"; do
    n=$(echo "$f" | sed -E 's/.*-([0-9]+)\.md$/\1/')
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt "$LATEST_EVAL_ROUND" ]; then
      LATEST_EVAL_ROUND="$n"
    fi
  done
fi

LATEST_QUALITY_ROUND=0
if [ "${#QUALITY_ROUND_FILES[@]}" -gt 0 ]; then
  for f in "${QUALITY_ROUND_FILES[@]}"; do
    n=$(echo "$f" | sed -E 's/.*-([0-9]+)\.md$/\1/')
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt "$LATEST_QUALITY_ROUND" ]; then
      LATEST_QUALITY_ROUND="$n"
    fi
  done
fi

# Determine the outcome of the most recent quality round by parsing its
# Status field. Defaults to "unknown" when no file or no parseable line.
LAST_ROUND_OUTCOME="unknown"
if [ "$LATEST_QUALITY_ROUND" -gt 0 ]; then
  shopt -s nullglob
  LATEST_Q_FILES=(.backlog/active/*/quality-round-"${LATEST_QUALITY_ROUND}".md)
  shopt -u nullglob
  if [ "${#LATEST_Q_FILES[@]}" -gt 0 ]; then
    LATEST_Q_FILE="${LATEST_Q_FILES[0]}"
    STATUS_LINE=$(grep -m 1 -E '^\*\*Status\*\*:' "$LATEST_Q_FILE" 2>/dev/null || true)
    if [ -n "$STATUS_LINE" ]; then
      STATUS_VAL=$(echo "$STATUS_LINE" | sed -E 's/^\*\*Status\*\*:[[:space:]]*([A-Z_]+).*/\1/')
      case "$STATUS_VAL" in
        PASS|FAIL|PASS_WITH_CONCERNS) LAST_ROUND_OUTCOME="$STATUS_VAL" ;;
      esac
    fi
  fi
fi

# Heuristic for in_progress_phase:
#   - Eval done but quality not yet for the same round -> impl-loop
#   - Eval and quality both done at same round, FAIL    -> impl-loop (next round expected)
#   - Eval and quality both done at same round, PASS(*) -> impl-done (loop completed)
#   - Otherwise                                         -> unknown
IN_PROGRESS_PHASE="unknown"
if [ "$LATEST_EVAL_ROUND" -gt 0 ]; then
  if [ "$LATEST_QUALITY_ROUND" -lt "$LATEST_EVAL_ROUND" ]; then
    IN_PROGRESS_PHASE="impl-loop"
  elif [ "$LATEST_QUALITY_ROUND" -eq "$LATEST_EVAL_ROUND" ]; then
    case "$LAST_ROUND_OUTCOME" in
      FAIL) IN_PROGRESS_PHASE="impl-loop" ;;
      PASS|PASS_WITH_CONCERNS) IN_PROGRESS_PHASE="impl-done" ;;
    esac
  fi
fi

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
  echo "latest_quality_round: ${LATEST_QUALITY_ROUND}"
  echo "last_round_outcome: ${LAST_ROUND_OUTCOME}"
  echo "in_progress_phase: ${IN_PROGRESS_PHASE}"
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
  if [ "${#EVAL_ROUND_FILES[@]}" -eq 0 ] && [ "${#QUALITY_ROUND_FILES[@]}" -eq 0 ]; then
    echo "(none)"
  else
    if [ "${#EVAL_ROUND_FILES[@]}" -gt 0 ]; then
      printf '%s\n' "${EVAL_ROUND_FILES[@]}"
    fi
    if [ "${#QUALITY_ROUND_FILES[@]}" -gt 0 ]; then
      printf '%s\n' "${QUALITY_ROUND_FILES[@]}"
    fi
  fi
} > "$SAVE_FILE"

exit 0
