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

# Collect file lists depth-agnostically under .backlog/active/ so both the
# legacy flat layout (.backlog/active/{NNN}-{slug}/) and the new nested
# layouts (.backlog/active/{parent}/{NNN}-{slug}/ and deeper) are surfaced.
# `find` with no -maxdepth walks arbitrary depth; sort -u stabilises order
# and de-duplicates in case the same file is reachable via multiple paths.
#
# An "active ticket" is any directory under `.backlog/active/` that
# contains EITHER `ticket.md` OR `phase-state.yaml` (the latter covers
# tickets that have had their phase-state initialised before `ticket.md`
# is persisted, and guarantees that every ticket with a live lifecycle
# record shows up in the compact-state frontmatter). We represent each
# active ticket by a canonical `ticket.md` path: the real file when it
# exists, otherwise a synthetic path `{dir}/ticket.md` which downstream
# code reduces to `dir` via `dirname` — the active_tickets list only
# ever contains the directory, so no missing-file read is attempted.
ACTIVE_TICKET_FILES=()
ACTIVE_BACKLOG_PLAN_FILES=()
if [ -d .backlog/active ]; then
  while IFS= read -r _dir; do
    [ -n "$_dir" ] || continue
    # Deterministic canonical entry per ticket dir: always `{dir}/ticket.md`.
    # When the real file is absent, downstream code only uses `dirname` on
    # this path — the missing-file case is handled by `[ -f ... ]` guards
    # in per-ticket eval/audit loops.
    ACTIVE_TICKET_FILES+=("$_dir/ticket.md")
  done < <(
    {
      find .backlog/active -type f -name 'ticket.md' 2>/dev/null
      find .backlog/active -type f -name 'phase-state.yaml' 2>/dev/null
    } | while IFS= read -r _p; do
      [ -n "$_p" ] && dirname "$_p"
    done | sort -u
  )
  unset _dir

  while IFS= read -r _plan_md; do
    [ -n "$_plan_md" ] && ACTIVE_BACKLOG_PLAN_FILES+=("$_plan_md")
  done < <(find .backlog/active -type f -name 'plan.md' 2>/dev/null | sort -u)
fi
unset _plan_md

shopt -s nullglob
ACTIVE_DOCS_PLAN_FILES=(.docs/plans/*.md)
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
  # ticket layouts (.backlog/active/{parent}/{NNN}-{slug}/) are surfaced
  # alongside the legacy flat layout.
  ALL_EVAL_FILES=()
  ALL_AUDIT_FILES=()
  if [ -d .backlog/active ]; then
    while IFS= read -r _ef; do
      [ -n "$_ef" ] && ALL_EVAL_FILES+=("$_ef")
    done < <(find .backlog/active -type f -name 'eval-round-*.md' 2>/dev/null | sort -u)
    while IFS= read -r _af; do
      [ -n "$_af" ] && ALL_AUDIT_FILES+=("$_af")
    done < <(find .backlog/active -type f -name 'audit-round-*.md' 2>/dev/null | sort -u)
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

exit 0
