---
name: review-diff
description: >-
  Review current changes with multi-agent analysis using code-reviewer and
  security-scanner agents. Reports findings by severity. Use only when the
  user explicitly asks to review changes.
disable-model-invocation: true
allowed-tools:
  - Agent
  - Read
  - Glob
  - Grep
argument-hint: "[branch or commit range (optional)]"
---

Review the current code changes. Target: $ARGUMENTS

Current branch:
!`git branch --show-current`

Active tickets:
!`ls -d .backlog/active/*/ 2>/dev/null || echo "(none)"`

Staged changes:
!`git diff --cached --stat`

Unstaged changes:
!`git diff --stat`

Changed files:
!`git diff --cached --name-only && git diff --name-only`

## Instructions

0. Determine output destination:
   - Get the current branch name from the pre-computed context above.
   - List directories in `.backlog/active/` from the pre-computed context above.
   - Match the current branch name against active ticket directory slugs (branch name contains the slug).
   - If a match is found: set `ticket-dir` to `.backlog/active/{slug}`.
     - Code-reviewer output: `{ticket-dir}/quality-round-{n}.md` where {n} is the next available number (check existing `quality-round-*.md` files in ticket-dir)
     - Security-scanner output: `{ticket-dir}/security-scan.md`
   - If no match: use defaults (code-reviewer: `.docs/reviews/{topic}.md`, security-scanner: `.docs/reviews/security-{topic}.md`)
1. Spawn the **code-reviewer** agent to review all changes, specifying the output path from step 0
2. If security-sensitive files are changed, also spawn the **security-scanner** agent in parallel, specifying the output path from step 0
3. Do NOT read files directly - delegate ALL review to agents
4. Aggregate results by severity: Critical > Warning > Suggestion
5. Report structured review summary to the user
