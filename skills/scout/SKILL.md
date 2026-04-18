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
  - Write
  - Edit
  - "Bash(date:*)"
  - "Bash(mv:*)"
  - "Bash(mkdir:*)"
  # Copilot CLI
  - skill
  - view
  - create
  - edit
  - "shell(date:*)"
  - "shell(mv:*)"
  - "shell(mkdir:*)"
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

## phase-state.yaml write ownership

This skill writes ONLY to `phases.scout` plus the top-level status fields
(`current_phase`, `last_completed_phase`, `overall_status`). It MUST NOT
modify any other phase's section (`phases.create_ticket`, `phases.impl`,
`phases.ship`). The internal delegates (`/investigate`, `/plan2doc`) MUST
NOT write to `phase-state.yaml` at all — only `/scout` writes, so the
"only one section per writer" rule holds.

**Idempotency guard (see Step 2a)**: Before advancing scout state on a
ticket that already has a `phase-state.yaml`, `/scout` MUST check whether
`phases.scout.status == completed` AND `current_phase in {impl, ship, done}`.
If so, re-running scout would regenerate `plan.md` / `investigation.md`
and invalidate any `/impl` progress already accumulated. Step 2a aborts
(or, in interactive mode, prompts) in that situation. The guard does NOT
fire when `current_phase == scout` / `create_ticket` or when
`phases.scout.status != completed` — a fresh retry of a failed / in-progress
scout is always safe and skips the guard.

**Failure recovery**: When `phase-state.yaml` exists with
`overall_status: failed` (from a prior /scout failure), Step 2a
additionally resets `overall_status: in-progress` and
`phases.scout.status: pending` before proceeding, so the skill can
re-enter from a failed state without manual file editing.

Reference: `skills/create-ticket/references/phase-state-schema.md`.

## Instructions

1. Before calling /investigate, attempt to read the ticket file directly:
   - Search `.backlog/product_backlog/` and `.backlog/active/` for ticket files matching `$ARGUMENTS` keyword using Glob (e.g., `.backlog/product_backlog/*<keyword>*/ticket.md` and `.backlog/active/*<keyword>*/ticket.md`).
   - If multiple matches, use the first. If zero matches or the directories do not exist, skip to step 3 (Size stays unset, non-ticket flow).
   - If found, read the `| Size |` table row to extract the Size value (S/M/L/XL).
2. If the matched ticket is in `.backlog/product_backlog/{ticket-dir}`, move it to active: `mv .backlog/product_backlog/{ticket-dir} .backlog/active/{ticket-dir}`. If already in `.backlog/active/{ticket-dir}`, use it as-is. Record the ticket directory as `ticket-dir` (`.backlog/active/{ticket-dir}`). Because `phase-state.yaml` (if present) lives inside the ticket directory, the `mv` moves it along with `ticket.md`.
2a. **Idempotency guard + begin scout phase (state update — only when `ticket-dir` is set and `phase-state.yaml` exists in the ticket dir)**:

    **Idempotency guard (runs first)**: Before beginning the scout phase, read `.backlog/active/{ticket-dir}/phase-state.yaml` and check whether scout has already completed with downstream work started:
    - If `phases.scout.status == completed` AND `current_phase` is in `{impl, ship, done}`:
      - **Interactive path** (AskUserQuestion available): ask the user `"Scout phase already completed and /impl or later phase has begun. Re-running scout will regenerate plan.md and can invalidate /impl progress. Continue? (yes/no)"`. On `no`, abort with `"Stopped by user after scout idempotency guard."` and exit. On `yes`, fall through to the state update below (the user has accepted that `/impl` progress may be invalidated).
      - **Non-interactive path** (AskUserQuestion unavailable, typical in `claude -p` or CI): abort with `"Scout phase already completed. To regenerate, delete plan.md and investigation.md manually, then rerun /scout in interactive mode."` and exit. Do NOT hang waiting for input.
    - Otherwise (scout `pending` / `in-progress` / `failed`, OR `current_phase` is still `scout` / `create_ticket`), the guard does NOT fire — proceed to the state update below. Fresh scout retries and first-time runs are always safe.

    **Begin scout phase (state update)**: Update ONLY the following fields (read-modify-write; leave every other field untouched):
    - `phases.scout.status: in-progress`
    - `phases.scout.started_at: {now}` (ISO-8601 UTC, e.g. via `date -u +%Y-%m-%dT%H:%M:%SZ`)
    - `current_phase: scout`
    - (No `ticket_dir:` field is rewritten — the schema no longer stores a top-level `ticket_dir:`; the file's own path encodes its location and `mv` in step 2 already put it at the correct path.)
    - **Failure recovery (only when pre-state `overall_status == failed`)**: additionally set `overall_status: in-progress` (reset from `failed`). When pre-state `overall_status` is already `in-progress` or any other non-`failed` value, do NOT rewrite this field. This lets `/scout` recover cleanly from a prior `/scout` failure without the user editing the state file by hand.
    If `phase-state.yaml` does NOT exist (e.g. the ticket was created outside `/create-ticket` or in a pre-schema legacy state), skip this step silently — `/impl` will bootstrap the state file later.
3. **MUST invoke `/investigate` via the Skill tool** with the topic to run codebase research via the researcher agent (sonnet). **NEVER bypass /investigate** with direct `Grep`/`Glob`/`Read` from within `/scout`. Fail the task immediately if `/investigate` cannot be invoked.
   - If `ticket-dir` is set, append `(ticket-dir: .backlog/active/{ticket-dir})` to the arguments.
   - `/investigate` MUST NOT write to `phase-state.yaml`; only `/scout` updates `phases.scout`.
4. Check the investigate response for failure conditions:
   - If the response contains `**Status**: failed` or `**Status**: partial`, print the error and stop. **Before stopping**, if `phase-state.yaml` exists, read-modify-write `phases.scout.status: failed` and `overall_status: failed`. Leave all other sections untouched.
   - If the response does not contain a research file path (e.g., no `.docs/research/` or `.backlog/active/` path), print an error and stop (same failure-state update as above).
   - Only proceed if `**Status**: success` and a research file path is present.
5. Print the research summary and file path returned by investigate.
6. Determine the final Size (informational only — `/plan2doc` will re-detect):
   - If Size was read from the ticket file in step 1, use that value.
   - Otherwise, read the research file for a Size field (S/M/L/XL). Default to M if absent.
7. **MUST invoke `/plan2doc` via the Skill tool** with `<topic>` and the following arguments. **NEVER bypass /plan2doc** by writing `plan.md` directly — /plan2doc is the only contract-compliant author (it spawns the `planner` agent with size-aware model selection). Fail the task immediately if `/plan2doc` cannot be invoked.
   - If `ticket-dir` is set, append `(ticket-dir: .backlog/active/{ticket-dir})` and `(research: .backlog/active/{ticket-dir}/investigation.md)` to the arguments.
   - If `ticket-dir` is not set, use `(research: <research-file-path>)` as before.
   - `/plan2doc` will internally select the planner model based on the Size in `ticket.md` (sonnet for S, opus for M/L/XL).
   - `/plan2doc` MUST NOT write to `phase-state.yaml`; only `/scout` updates `phases.scout`.
8. Print the plan summary and file path returned by plan2doc.
8a. **Complete scout phase (state update — only when `ticket-dir` is set and `phase-state.yaml` exists)**: After both `investigation.md` and `plan.md` are successfully written, read `.backlog/active/{ticket-dir}/phase-state.yaml` and update ONLY the following fields (read-modify-write):
    - `phases.scout.status: completed`
    - `phases.scout.completed_at: {now}` (ISO-8601 UTC, recomputed at this step)
    - `phases.scout.artifacts.investigation: .backlog/active/{ticket-dir}/investigation.md`
    - `phases.scout.artifacts.plan: .backlog/active/{ticket-dir}/plan.md`
    - `last_completed_phase: scout`
    - `current_phase: impl`
    Do NOT modify `phases.create_ticket`, `phases.impl`, or `phases.ship`. Do NOT modify `overall_status` (it remains `in-progress`).
9. Print a final summary with both file paths and the detected size.

10. **Emit SW-CHECKPOINT block**. Emit the `## [SW-CHECKPOINT]` block per `skills/create-ticket/references/sw-checkpoint-template.md` as the FINAL section of the skill's response, after the final summary in step 9 and after any error output. Fill: `phase=scout`, `ticket=.backlog/active/{ticket-dir}` when a ticket was resolved in steps 1–2 (otherwise `none`), `artifacts=[<repo-relative paths to investigation.md and plan.md, plus phase-state.yaml if present>]`, `next_recommended=/impl .backlog/active/{ticket-dir}/plan.md` on success (or `""` if no `plan.md` was produced). Emit on failure paths with `artifacts: []`.

## Error Handling

- **Empty arguments**: Print "Usage: /scout <topic or ticket>" and stop.
- **investigate failure**: If `**Status**: failed` or `**Status**: partial` is present, or no research file path (`.docs/research/` or `.backlog/active/` path) is found in the response, print the error and stop. Do NOT proceed to plan2doc.
- **plan2doc failure**: Print the error and the research file path (research is still valid).
- **Ticket not found**: If no ticket matches in `.backlog/product_backlog/` or `.backlog/active/`, continue without ticket-dir (non-ticket flow, Size stays unset).
