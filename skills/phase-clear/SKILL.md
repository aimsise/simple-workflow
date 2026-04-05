---
name: phase-clear
description: >-
  Switch work phase with context preservation guidance. Auto-detects current
  phase from git state and .docs/ contents when no argument provided.
  Supports investigate/plan/implement/test/review/commit phases.
allowed-tools:
  - "Bash(git:*)"
  - "Bash(ls:*)"
  - Read
  - Glob
argument-hint: "<next phase: investigate|plan|implement|test|review|commit>"
---

Switching to phase: $ARGUMENTS

Current state:
!`git status --short`
!`git branch --show-current`
!`git log --oneline -5`

## Instructions

### 0. Auto-Detection (when $ARGUMENTS is empty)

If $ARGUMENTS is empty, auto-detect the current phase by checking these conditions in order.
Check both `.docs/` and `.backlog/active/` for artifacts. Recommend the first matching phase:

1. **No research files for current topic** -> suggest **investigate**
   - Check: `ls .docs/research/ 2>/dev/null` is empty or has no files related to current branch
   - Also check: `.backlog/active/` has ticket directories but no `investigation.md` in any of them
2. **Research exists, no plans** -> suggest **plan**
   - Check: `.docs/research/` has files BUT `.docs/plans/` has no related files
   - Also check: `.backlog/active/*/investigation.md` exists BUT `.backlog/active/*/plan.md` does not
3. **Plans exist, no code diff from main** -> suggest **implement**
   - Check: `.docs/plans/` has files BUT `git diff main --name-only` shows no changes outside `.docs/` and `.backlog/`
   - Also check: `.backlog/active/*/plan.md` exists BUT no code changes outside `.backlog/`
4. **Code diff exists, no test changes** -> suggest **test**
   - Check: `git diff main --name-only` shows source changes BUT no test changes
5. **Tests exist, no review files** -> suggest **review**
   - Check: Both source and test changes BUT `.docs/reviews/` has no recent review
6. **Review done, uncommitted changes** -> suggest **commit**
   - Check: `.docs/reviews/` has recent review AND `git status --porcelain` shows uncommitted changes

Present the detection result with reasoning, including any ticket directory information from `.backlog/active/`. Ask user to confirm or choose differently.

### 1. Summarize current work state briefly
2. Guide the user based on next phase:
   - **investigate** -> Use `/investigate <topic>` to start fresh exploration. If a ticket exists in `.backlog/active/`, mention its directory.
   - **plan** -> Read `.docs/research/` or `.backlog/active/{slug}/investigation.md` first, then use `/plan2doc <feature>`
   - **implement** -> Read `.docs/plans/` or `.backlog/active/{slug}/plan.md` first, implement directly
   - **test** -> Use `/test <changed files>` on modified code
   - **review** -> Use `/review-diff` to check all changes
   - **commit** -> Use `/commit` to create a conventional commit
3. Recommend running `/clear` then the next command
4. Print the exact command sequence, e.g.:
   ```
   /clear
   /catchup  (optional, to recover context)
   /<next-command>
   ```
