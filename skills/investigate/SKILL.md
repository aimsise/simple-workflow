---
name: investigate
description: >-
  Investigates codebase topics by spawning the researcher subagent and writing
  structured findings to disk. Use when (1) the user runs `/investigate <topic>`
  directly to research a question, (2) `/scout` delegates the research phase of
  a ticket workflow via the Skill tool, or (3) a ticket directory needs an
  `investigation.md` artifact at
  `.simple-workflow/backlog/active/{ticket-dir}/investigation.md`. Default
  output directory is `.simple-workflow/docs/research/` when no ticket is
  bound. Triggers on "/investigate", "research the code", "investigate <topic>",
  "find references", "explore the codebase".
context: fork
agent: researcher
model: sonnet
argument-hint: "<topic or question to investigate>"
allowed-tools:
  # Claude Code
  - Agent
  - Read
  - Glob
  - Grep
  - "Bash(git:*)"
  - "Bash(ls:*)"
  # Copilot CLI
  - task
  - view
  - glob
  - grep
  - "shell(git:*)"
  - "shell(ls:*)"
---

Investigate the following topic: $ARGUMENTS

Current repo state:
!`git status --short | head -20`

## Instructions

1. Parse `$ARGUMENTS` for `(ticket-dir: <path>)` to determine the output destination so downstream `/scout` and `/plan2doc` find the artifact at its canonical path:
   - If `ticket-dir` is specified: route findings to `{ticket-dir}/investigation.md`.
   - If `ticket-dir` is not specified: search `.simple-workflow/backlog/product_backlog/` and `.simple-workflow/backlog/active/` using Glob for directories matching `$ARGUMENTS` keywords. If a match is found in `product_backlog`, move it to `active` with `mv .simple-workflow/backlog/product_backlog/{ticket-dir} .simple-workflow/backlog/active/{ticket-dir}` and use `.simple-workflow/backlog/active/{ticket-dir}` as the ticket-dir. If already in `active`, use it as-is.
   - If no ticket-dir and no matching ticket: use the default `.simple-workflow/docs/research/` directory.
2. Investigate the topic thoroughly via the spawned researcher subagent (no direct Read/Grep loops at the orchestrator level — researcher owns the fork).
3. The researcher subagent uses Grep/Glob to locate relevant code, then Read to understand it.
4. When investigating a ticket, include the ticket's `Size (S/M/L/XL)` in the research-file header so downstream `/plan2doc` and `/scout` can size-route correctly (per `skills/create-ticket/references/workflow-patterns.md`).
5. Write ALL detailed findings to the determined output path (either `{ticket-dir}/investigation.md` or `.simple-workflow/docs/research/{topic}.md`). Tell the researcher agent the exact output file path so the artifact lands where cross-references expect it.
   - **Return value cap**: The spawned researcher's return value MUST stay under 500 tokens per the Context Conservation Protocol in `agents/researcher.md`. Full investigation content is written to the determined output path; the orchestrator reads it on demand.
6. Return a brief executive summary with the output file path so the caller can decide whether to read the full artifact.
