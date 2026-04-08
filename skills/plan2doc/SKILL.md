---
name: plan2doc
description: >-
  Create an implementation plan via planner agent and save to .docs/plans/.
  Use when planning a feature, refactoring, or significant change.
context: fork
agent: planner
argument-hint: "<feature or change to plan>"
---

Create an implementation plan for: $ARGUMENTS

Current changes:
!`git diff --stat`

Existing research (if any):
!`ls -t .docs/research/*.md 2>/dev/null | head -5`

## Instructions

0. Parse `$ARGUMENTS` for `(ticket-dir: <path>)` to determine the output destination:
   - If `ticket-dir` is specified: output the plan to `{ticket-dir}/plan.md`
   - If `ticket-dir` is not specified: search `.backlog/product_backlog/` and `.backlog/active/` using Glob for directories matching `$ARGUMENTS` keywords. If a match is found in `product_backlog`, move it to `active` (`mv .backlog/product_backlog/{slug} .backlog/active/{slug}`) and use `.backlog/active/{slug}/plan.md`. If already in `active`, use `.backlog/active/{slug}/plan.md`.
   - If no ticket-dir and no matching ticket found: output to `.docs/plans/{feature}.md` (default)
1. If arguments contain `(research: <path>)`, read that specific file first. If `ticket-dir` is set and `{ticket-dir}/investigation.md` exists, also read it for additional context. Otherwise, if research files are listed above, read them to build on prior findings
2. Identify dependencies, affected files, risks, and implementation order
3. Identify available skills and agents by scanning `.claude/skills/` and `.claude/agents/` (if present), and listing installed plugin skills/agents. Read frontmatter only (not full file contents)
4. Write the full plan to the determined output path (`{ticket-dir}/plan.md` or `.docs/plans/{feature}.md`) including:
   - Overview and goals
   - Affected files and components
   - Step-by-step implementation plan (numbered)
   - Risk assessment and testing strategy
   - `### Claude Code Workflow` section with phase/command/agent table
5. Return a summary with the plan file path

## Error Handling

- **Empty arguments**: Print "Usage: /plan2doc <feature or change to plan>" and stop.
- **Missing .docs/ directories**: Create `.docs/plans/` automatically.
- **Missing .backlog/ directories**: Create `.backlog/active/{slug}/` automatically when ticket-dir is specified.
