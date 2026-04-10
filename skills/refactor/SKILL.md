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

Current branch:
!`git branch --show-current`

Active tickets:
!`ls -d .backlog/active/*/ 2>/dev/null || echo "(none)"`

## Instructions

### Phase 1: Planning
1. Spawn the **planner** agent to create a refactoring plan
1b. **Ticket detection**: Get the current branch name and active ticket list from the pre-computed context above. Match the current branch name against active ticket directory slugs (branch name contains the slug). If a match is found, set `ticket-dir` to `.backlog/active/{slug}`.
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
6. Spawn the **code-reviewer** agent to review all changes:
   - If `ticket-dir` is set: specify output path as `{ticket-dir}/quality-refactor-{n}.md` where {n} is the iteration number
   - If `ticket-dir` is not set: let the code-reviewer use its default (`.docs/reviews/{topic}.md`)
7. Evaluate review results:
   - **code-reviewer Status: failed or partial** (review infrastructure failure):
     Use `AskUserQuestion` to ask "code-reviewerが失敗しました。どうしますか？" with options:
     - "stop": stop the skill immediately. Print "Stopped by user after code-reviewer failure. Refactoring changes remain in working tree." and exit.
     - "continue without review": proceed to Phase 4 without quality verification, noting "Quality review SKIPPED (code-reviewer failed)" in the final summary.
     - **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), default to **stop**. Print "Stopped: /refactor cannot proceed without code-reviewer in non-interactive mode. Refactoring changes remain in working tree. Re-run in interactive mode." and exit. Do NOT hang waiting for input.
     - **Never** silently treat code-reviewer failure as "no issues" — that would let Critical bugs slip through unverified.
   - **Critical = 0 AND Warning = 0** -> exit loop, proceed to Phase 4
   - **Issues found** -> fix the reported issues, then return to step 5
   - **Iteration 3 reached** -> exit loop with remaining issues noted

### Phase 4: Final Report
8. Report summary:
   - Changes made (files modified, lines changed)
   - Review iterations completed
   - Remaining issues (if loop exited at max iterations)
   - Test and lint final status
