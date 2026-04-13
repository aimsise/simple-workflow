---
name: scout
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Use after creating a ticket or when starting work on a new feature.
  Investigates the codebase and creates an implementation plan for the
  specified topic or active ticket.
disable-model-invocation: false
allowed-tools:
  # Claude Code
  - Skill
  - Read
  # Copilot CLI
  - skill
  - view
argument-hint: "<topic or ticket to investigate and plan>"
---

Investigate and plan: $ARGUMENTS

## Instructions

1. Before calling /investigate, attempt to read the ticket file directly:
   - Search `.backlog/product_backlog/` and `.backlog/active/` for ticket files matching `$ARGUMENTS` keyword using Glob (e.g., `.backlog/product_backlog/*<keyword>*/ticket.md` and `.backlog/active/*<keyword>*/ticket.md`).
   - If multiple matches, use the first. If zero matches or the directories do not exist, skip to step 3 (Size stays unset, non-ticket flow).
   - If found, read the `| Size |` table row to extract the Size value (S/M/L/XL).
2. If the matched ticket is in `.backlog/product_backlog/{ticket-dir}`, move it to active: `mv .backlog/product_backlog/{ticket-dir} .backlog/active/{ticket-dir}`. If already in `.backlog/active/{ticket-dir}`, use it as-is. Record the ticket directory as `ticket-dir` (`.backlog/active/{ticket-dir}`).
3. Call `/investigate` with the topic to run codebase research via the researcher agent (sonnet).
   - If `ticket-dir` is set, append `(ticket-dir: .backlog/active/{ticket-dir})` to the arguments.
4. Check the investigate response for failure conditions:
   - If the response contains `**Status**: failed` or `**Status**: partial`, print the error and stop.
   - If the response does not contain a research file path (e.g., no `.docs/research/` or `.backlog/active/` path), print an error and stop.
   - Only proceed if `**Status**: success` and a research file path is present.
5. Print the research summary and file path returned by investigate.
6. Determine the final Size (informational only — `/plan2doc` will re-detect):
   - If Size was read from the ticket file in step 1, use that value.
   - Otherwise, read the research file for a Size field (S/M/L/XL). Default to M if absent.
7. Call `/plan2doc` with `<topic>` and the following arguments:
   - If `ticket-dir` is set, append `(ticket-dir: .backlog/active/{ticket-dir})` and `(research: .backlog/active/{ticket-dir}/investigation.md)` to the arguments.
   - If `ticket-dir` is not set, use `(research: <research-file-path>)` as before.
   - `/plan2doc` will internally select the planner model based on the Size in `ticket.md` (sonnet for S, opus for M/L/XL).
8. Print the plan summary and file path returned by plan2doc.
9. Print a final summary with both file paths and the detected size.

## Error Handling

- **Empty arguments**: Print "Usage: /scout <topic or ticket>" and stop.
- **investigate failure**: If `**Status**: failed` or `**Status**: partial` is present, or no research file path (`.docs/research/` or `.backlog/active/` path) is found in the response, print the error and stop. Do NOT proceed to plan2doc.
- **plan2doc failure**: Print the error and the research file path (research is still valid).
- **Ticket not found**: If no ticket matches in `.backlog/product_backlog/` or `.backlog/active/`, continue without ticket-dir (non-ticket flow, Size stays unset).
