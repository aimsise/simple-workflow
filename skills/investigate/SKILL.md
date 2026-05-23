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
  - Agent
  - Read
  - Glob
  - Grep
  - "Bash(git:*)"
  - "Bash(ls:*)"
---

Investigate the following topic: $ARGUMENTS

Current repo state:
!`git status --short | head -20`

## Pre-computed Context

Available user skills: !`( ls -1 ~/.claude/skills 2>/dev/null ; ls -1 .claude/skills 2>/dev/null ) | sort -u | grep . | tr "\n" "," | sed "s/,$//" | grep . || echo "(none)"`

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

## Subagent Skill-Access Handoff

When you spawn a subagent via the Agent tool, consult the `Available user skills:` line in the Pre-computed Context above. If a listed utility skill is relevant to that subagent's task, name it in the Agent prompt and instruct the subagent to use it via the Skill tool when it materially helps.

- Do NOT hand skill references to `security-scanner` or `ticket-evaluator`. These subagents are intentionally hermetic and do not carry the Skill tool; referencing skills to them only adds noise.
- Never present a pipeline skill (`/scout`, `/impl`, `/audit`, `/ship`, `/autopilot`, `/brief`, `/catchup`, `/create-ticket`, `/investigate`, `/plan2doc`, `/refactor`, `/test`, `/tune`) as a utility for a subagent.
- When a ticket's `### Capabilities` section exists (resolve via `{ticket-dir}/ticket.md` or the autopilot state file's `paths.ticket`), `Read` it before constructing any subagent spawn prompt and inline the bound capabilities verbatim into every spawn prompt under the heading `## Bound capabilities (per AC)`. For per-AC spawns (one spawn per AC, e.g. `/impl` Steps 13/15), include only the rows whose `Bound AC(s)` column lists the active AC. For tip / whole-deliverable spawns (the rest), include the full table. The upstream binding is authoritative — do NOT re-derive relevance from the AC text or re-scan `Available user skills:` for plausible matches. When the ticket lacks `### Capabilities` (older ticket pre-dating Gate 6), emit `## Bound capabilities (per AC): (none recorded — ticket pre-dates Gate 6)` in the spawn prompt and let the subagent fall back to its in-house capability-selection path.
- If the `Available user skills:` probe reports `(none)`, hand off nothing and let the subagent proceed with its in-house capabilities.
