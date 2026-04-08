---
name: refactor
description: >-
  Plan and execute a refactoring with safety checks. Uses planner agent, then
  implements incrementally with test/lint verification and code review loop.
  Use only when the user explicitly asks to refactor code.
disable-model-invocation: true
allowed-tools:
  - Agent
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - "Bash(git:*)"
  - "Bash(npm:*)"
  - "Bash(npx:*)"
  - "Bash(yarn:*)"
  - "Bash(pnpm:*)"
  - "Bash(bun:*)"
  - "Bash(pytest:*)"
  - "Bash(cargo:*)"
  - "Bash(go :*)"
  - "Bash(make:*)"
argument-hint: "<refactoring target and goal>"
---

Plan and execute refactoring: $ARGUMENTS

Current state:
!`git status --short`
!`git diff --stat`

## Instructions

### Phase 1: Planning
1. Spawn the **planner** agent to create a refactoring plan
2. Present the plan summary to the user

### Phase 2: Approval
3. Ask the user to approve before proceeding. If rejected, gather feedback and re-plan (return to Phase 1).

3b. **Safety checkpoint**: After user approval, create a backup branch:
    - Run `git branch backup/pre-refactor-$(date +%Y%m%d-%H%M%S)` to save current state
    - Print: "Backup branch created: backup/pre-refactor-{timestamp}. To rollback: git checkout backup/pre-refactor-{timestamp}"

### Phase 3: Implementation + Review Loop (max 3 iterations)
4. Implement changes according to the plan
5. Run verification:
   - Run the project's test command (as defined in CLAUDE.md or project conventions)
   - Run the project's lint command (as defined in CLAUDE.md or project conventions)
6. Spawn the **code-reviewer** agent to review all changes
7. Evaluate review results:
   - **Critical = 0 AND Warning = 0** -> exit loop, proceed to Phase 4
   - **Issues found** -> fix the reported issues, then return to step 5
   - **Iteration 3 reached** -> exit loop with remaining issues noted

### Phase 4: Final Report
8. Report summary:
   - Changes made (files modified, lines changed)
   - Review iterations completed
   - Remaining issues (if loop exited at max iterations)
   - Test and lint final status
