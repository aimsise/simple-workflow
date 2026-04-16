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

## Mandatory Skill Invocations

The following skill invocations are **contractual** — `/scout` MUST delegate to each of these via the Skill tool. `/scout` is a thin orchestrator and performs no research/planning work itself; its entire purpose is to chain /investigate and /plan2doc with ticket-aware arguments. Any bypass is a contract violation and will be detected by the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `/investigate` (Skill) | Step 3 — always, after ticket resolution | No `investigation.md` written to the ticket dir; downstream `/plan2doc` has no research context, producing a weaker plan. `/autopilot`'s post-scout artifact verification triggers `[PIPELINE] scout: ARTIFACT-MISSING — investigation.md` |
| `/plan2doc` (Skill) | Step 7 — always, after /investigate succeeds | No `plan.md` written to the ticket dir; `/impl` has nothing to execute. `/autopilot`'s post-scout artifact verification triggers `[PIPELINE] scout: ARTIFACT-MISSING — plan.md`, ticket marked failed |

**Binding rules**:
- `MUST invoke /investigate via the Skill tool` — never substitute by running `Grep`/`Glob`/`Read` directly from within `/scout`.
- `MUST invoke /plan2doc via the Skill tool` — never write `plan.md` by model output; `/plan2doc` is the only contract-compliant author of plan files because it spawns the `planner` agent with size-aware model selection.
- `NEVER bypass these skills via direct file operations` — `/scout` must not write to `investigation.md` or `plan.md` itself.
- `Fail the task immediately if /investigate or /plan2doc cannot be invoked via the Skill tool` — print the failure reason and stop.

## Instructions

1. Before calling /investigate, attempt to read the ticket file directly:
   - Search `.backlog/product_backlog/` and `.backlog/active/` for ticket files matching `$ARGUMENTS` keyword using Glob (e.g., `.backlog/product_backlog/*<keyword>*/ticket.md` and `.backlog/active/*<keyword>*/ticket.md`).
   - If multiple matches, use the first. If zero matches or the directories do not exist, skip to step 3 (Size stays unset, non-ticket flow).
   - If found, read the `| Size |` table row to extract the Size value (S/M/L/XL).
2. If the matched ticket is in `.backlog/product_backlog/{ticket-dir}`, move it to active: `mv .backlog/product_backlog/{ticket-dir} .backlog/active/{ticket-dir}`. If already in `.backlog/active/{ticket-dir}`, use it as-is. Record the ticket directory as `ticket-dir` (`.backlog/active/{ticket-dir}`).
3. **MUST invoke `/investigate` via the Skill tool** with the topic to run codebase research via the researcher agent (sonnet). **NEVER bypass /investigate** with direct `Grep`/`Glob`/`Read` from within `/scout`. Fail the task immediately if `/investigate` cannot be invoked.
   - If `ticket-dir` is set, append `(ticket-dir: .backlog/active/{ticket-dir})` to the arguments.
4. Check the investigate response for failure conditions:
   - If the response contains `**Status**: failed` or `**Status**: partial`, print the error and stop.
   - If the response does not contain a research file path (e.g., no `.docs/research/` or `.backlog/active/` path), print an error and stop.
   - Only proceed if `**Status**: success` and a research file path is present.
5. Print the research summary and file path returned by investigate.
6. Determine the final Size (informational only — `/plan2doc` will re-detect):
   - If Size was read from the ticket file in step 1, use that value.
   - Otherwise, read the research file for a Size field (S/M/L/XL). Default to M if absent.
7. **MUST invoke `/plan2doc` via the Skill tool** with `<topic>` and the following arguments. **NEVER bypass /plan2doc** by writing `plan.md` directly — /plan2doc is the only contract-compliant author (it spawns the `planner` agent with size-aware model selection). Fail the task immediately if `/plan2doc` cannot be invoked.
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
