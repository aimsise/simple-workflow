---
name: impl
description: >-
  Implement the latest plan with optional additional instructions.
  Runs implementation, lint, test loop.
  Use after /scout or /plan2doc to execute the plan.
  Optionally accepts a plan file path as the first argument.
disable-model-invocation: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - "Bash(*)"
  - Skill
argument-hint: "[plan file path or additional instructions]"
---

Implement the latest plan.
User arguments: $ARGUMENTS

## Pre-computed Context

Latest plan (backlog):
!`ls -t .backlog/active/*/plan.md 2>/dev/null | head -1`

Latest plan (docs):
!`ls -t .docs/plans/*.md 2>/dev/null | head -1`

Latest research (backlog):
!`ls -t .backlog/active/*/investigation.md 2>/dev/null | head -1`

Latest research (docs):
!`ls -t .docs/research/*.md 2>/dev/null | head -1`

Current state:
!`git status --short`

## Phase 1: Plan Loading

1. Determine the plan file (check in priority order):
   - If `$ARGUMENTS` starts with `.backlog/active/` or `.docs/plans/` -> use it as the plan file path. Remaining text is additional instructions.
   - Otherwise, use the latest plan file from the pre-computed context above, preferring `.backlog/active/*/plan.md` (most recent) over `.docs/plans/*.md`.
   - If no plan file exists in either location, print "No plan found in .backlog/active/ or .docs/plans/. Run /scout or /plan2doc first." and stop.
2. Read the plan file content.
3. If the plan is in `.backlog/active/{slug}/`, check for `investigation.md` in the same directory first. Otherwise, if a related research file exists in `.docs/research/`, read it for additional context.
4. If additional instructions are provided, integrate them with the plan (additional instructions take priority on conflicts).
5. If the working tree has uncommitted changes unrelated to the plan, warn the user before proceeding.

## Phase 2: Implementation

6. Follow the plan's steps to implement code changes, including test code.
7. Adhere to project constraints defined in CLAUDE.md or project conventions.
8. If the plan involves format or behavior changes, update relevant documentation first (spec-first policy, if applicable).

## Phase 3: Lint (max 3 attempts)

9. Run the project's lint command (as defined in CLAUDE.md or project conventions).
10. If lint fails, fix the issues and re-run. Repeat up to 3 attempts.
11. If lint still fails after 3 attempts, report failures and stop.

## Phase 4: Test (max 3 attempts)

12. Run the project's test command (as defined in CLAUDE.md or project conventions).
13. If tests fail, fix the issues and re-run. Repeat up to 3 attempts.
14. If tests still fail after 3 attempts, report failures and stop.

## Phase 5: Summary

15. Run `git status -s` and display the output.
16. Print a summary including:
    - Plan file executed
    - Files changed or created
    - Test results (pass/fail count)
    - "Review the changes above, then run `/ship` to commit and create PR"

## Error Handling

- **No plan**: Print "No plan found in .backlog/active/ or .docs/plans/. Run /scout or /plan2doc first." and stop.
- **Dirty working tree**: Warn user about unrelated changes, ask whether to continue.
- **Lint 3x failure**: Print failures and stop. Code remains in place.
- **Test 3x failure**: Print failures and stop. Code remains in place.
