---
name: catchup
description: >-
  Analyze current branch state and recover working context. Summarizes what
  has been done and what to do next. Use at session start to resume work.
allowed-tools:
  - Agent
  - Read
  - Glob
  - Grep
  - "Bash(git:*)"
---

Recover context for the current working session.

Current branch:
!`git branch --show-current`

Recent history:
!`git log --oneline -20`

Changes from main:
!`git diff --stat main`

Working tree:
!`git status --short`

## Instructions

1. Check for recent compact-state files in `.docs/compact-state/compact-state-*.md` (most recent first). If found, read the latest one to recover pre-compaction context (active tickets, plans, evaluation state).
2. Spawn the **researcher** agent to analyze:
   - What has changed on this branch vs main
   - What the changes are trying to accomplish
   - Current state of work (complete, in-progress, blocked)
   - Check `.backlog/active/` for any active tickets and their artifacts (investigation.md, plan.md)
3. Check for existing docs in `.docs/plans/`, `.docs/research/`, and `.backlog/active/`
4. Report a concise summary:
   - Current situation (branch, what's been done)
   - Active tickets in `.backlog/active/` (list slug and available artifacts)
   - Relevant .docs/plans files to read
   - What to do next
