---
name: impl
description: >-
  Implement the latest plan using Generator-Evaluator architecture.
  Routes S-size to sonnet implementer, M+ to opus implementer.
  Independent evaluator verifies plan adherence and code quality.
  Use after /scout or /plan2doc to execute the plan.
disable-model-invocation: true
allowed-tools:
  - Agent
  - Read
  - Glob
  - "Bash(git diff:*)"
  - "Bash(git status:*)"
  - "Bash(git log:*)"
  - "Bash(git branch:*)"
argument-hint: "[plan file path or additional instructions]"
---

Implement the latest plan using Generator-Evaluator architecture.
User arguments: $ARGUMENTS

## Pre-computed Context

Latest plan in .backlog/active/:
!`ls -t .backlog/active/*/plan.md 2>/dev/null | head -1`

Latest plan in .docs/plans/:
!`ls -t .docs/plans/*.md 2>/dev/null | head -1`

Latest research in .backlog/active/:
!`ls -t .backlog/active/*/investigation.md 2>/dev/null | head -1`

Latest research in .docs/research/:
!`ls -t .docs/research/*.md 2>/dev/null | head -1`

Current state:
!`git status --short`

## Phase 1: Plan Loading & Size Detection

1. Parse `$ARGUMENTS`:
   - If it starts with `.backlog/active/` or `.docs/plans/` -> use it as the plan file path. Remaining text is additional instructions.
   - Otherwise -> entire argument is additional instructions. Use the latest plan from pre-computed context above, preferring `.backlog/active/*/plan.md` (most recent) over `.docs/plans/*.md`.
   - If no plan file exists in either location, print "No plan found in .backlog/active/ or .docs/plans/. Run /scout or /plan2doc first." and stop.

2. Read the plan file.

3. Size detection:
   - If plan is in `.backlog/active/{slug}/plan.md` -> read `.backlog/active/{slug}/ticket.md`, extract Size from `| Size |` row.
   - If plan is in `.docs/plans/` -> default to M.

4. Identify Acceptance Criteria section in the plan (`### Acceptance Criteria` or equivalent).

5. If Acceptance Criteria section is NOT found in the plan, print "ERROR: Plan has no Acceptance Criteria. Add an '### Acceptance Criteria' section to the plan before running /impl." and stop.

6. **AC Sanity Check** (round 1 only, M/L/XL size only): Include in the Generator prompt: "Before implementing, review each AC. If any AC is ambiguous or technically infeasible, flag it in your **Next Steps** field." If Generator flags ambiguous AC, report to user and stop.

7. If related investigation file exists (same directory `investigation.md` or latest in `.docs/research/`), read it.

8. If working tree has uncommitted changes unrelated to the plan, warn user.

## Phase 2: Generator-Evaluator Loop (max 3 rounds)

9. Spawn **Generator** agent:
   - Size S -> `implementer-light` (sonnet)
   - Size M/L/XL -> `implementer` (opus)
   - Prompt must include:
     a. Full plan content
     b. Acceptance Criteria (highlighted: "You will be evaluated by an independent evaluator against these criteria")
     c. Investigation file content (if exists)
     d. User's additional instructions (if any)
     e. Round 2+: previous evaluator's **Feedback** field
     f. "Refer to CLAUDE.md or project conventions for lint/test commands and coding standards."
   - Receive Generator's return value (changed files list + lint/test status)

10. Run `git diff --stat` to capture change summary.

11. Spawn **Evaluator** agent (always sonnet):
   - Prompt must include:
     a. Full plan content
     b. Acceptance Criteria
     c. Output of `git diff --stat` from step 10
     d. "The following files have been changed. Run `git diff` to inspect changes, run lint/test independently, and verify each AC."
   - Prompt must NOT include: Generator's return value (bias elimination)
   - Receive Evaluator's return value (PASS/FAIL/FAIL-CRITICAL + feedback)

12. Decision:
    - **Status: PASS** → proceed to Phase 3
    - **Status: FAIL-CRITICAL** → stop immediately. Report CRITICAL issues to the user. Do NOT continue to further rounds.
    - **Status: FAIL** → save evaluator's **Feedback**, continue to next round
    - **Round 3 and Status: FAIL** → proceed to Phase 3 with remaining issues noted

## Phase 3: Summary

13. Run `git status -s` and display.

14. Print summary:
    - Plan file executed
    - Files changed or created
    - Generator-Evaluator rounds completed
    - Final evaluator status (PASS or remaining issues from last evaluation)
    - "Review the changes above, then run `/ship` to commit and create PR"

## Error Handling

- **No plan**: Print "No plan found in .backlog/active/ or .docs/plans/. Run /scout or /plan2doc first." and stop.
- **Dirty working tree**: Warn user about unrelated changes, ask whether to continue.
- **Generator failure** (Status: failed): Report error and stop.
- **Evaluator failure** (Status: failed or partial): Report error. Generator's changes remain in place.
- **3 rounds FAIL**: Report remaining issues. Code remains changed.
