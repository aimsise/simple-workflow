---
name: commit
description: >-
  Stage changes and create a conventional commit following
  feat/fix/improve/chore/docs/test/perf prefixes. Use only when the user
  explicitly asks to commit or finalize changes.
disable-model-invocation: true
model: haiku
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(git log:*)
argument-hint: "[commit message hint (optional)]"
---

Create a conventional commit for the current changes.
Hint from user: $ARGUMENTS

Current state:
!`git status --short`

Staged diff:
!`git diff --cached`

Unstaged diff summary:
!`git diff --stat`

Recent commits for style reference:
!`git log --oneline -10`

## Instructions

1. Analyze the changes (staged and unstaged)
2. If there are unstaged changes, ask which files to stage
3. Create a commit message following conventional commits: feat/fix/improve/chore/docs/test/perf
4. Message must be concise and focus on the "why"
5. Use a HEREDOC for the commit message
6. Run `git status` after commit to verify success
