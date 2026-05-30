---
name: scout
description: >-
  Investigates the codebase and produces an implementation plan by
  delegating to `/investigate` (researcher subagent) and `/plan2doc`
  (planner subagent), then emits a `## [SW-CHECKPOINT]` block at
  end-of-skill. Use when (1) the user runs `/scout` directly on a topic
  to research and plan it outside any ticket workflow, (2) the user runs
  `/scout` on an active or product-backlog ticket so the resulting
  `investigation.md` and `plan.md` land in
  `.simple-workflow/backlog/active/{ticket-dir}/` and the ticket's
  `phase-state.yaml` advances `phases.scout` from `pending` to
  `completed`, or (3) `/autopilot` chain-calls the scout phase of a
  ticket-driven pipeline via the Skill tool. Triggers on "/scout",
  "/scout <topic>", "scout the codebase", "investigate and plan",
  "research and plan", "kick off a ticket", "scout this feature".
disable-model-invocation: false
allowed-tools:
  - Skill
  - Read
  - Write
  - Edit
  - "Bash(date:*)"
  - "Bash(mv:*)"
  - "Bash(mkdir:*)"
argument-hint: "<topic or ticket to investigate and plan>"
---

Investigate and plan: $ARGUMENTS

Invocation policy: Do not auto-invoke. Only invoke when explicitly called by name by the user (e.g. `/scout <topic>` or `/scout` on an active ticket) or by another skill via the Skill tool. In practice, `/autopilot` Step 3b chain-calls `/scout` once per ticket as part of the per-ticket `scout` → `impl` → `ship` pipeline. `disable-model-invocation: false` is intentional because the `/autopilot` chain-call uses the Skill tool, which would not resolve if the flag were flipped to `true`; flipping it would break the chain-call surface for `/autopilot` while leaving direct user invocation (`/scout <topic>` or `/scout` on an active ticket) superficially intact.

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

## Observable Contract: SW-CHECKPOINT emission

Every successful `/scout` invocation MUST emit exactly one `## [SW-CHECKPOINT]` block as the FINAL section of its response. The block is the contractual end-of-skill artifact and is consumed by downstream tooling (notably `/autopilot` Step 3b artifact verification and `scout-checkpoint-guard.sh`).

The block carries four fields per `skills/create-ticket/references/sw-checkpoint-template.md`:

- `phase=scout` (always).
- `ticket=<ticket-dir>` — set to the repo-relative path `.simple-workflow/backlog/active/{ticket-dir}` when a ticket was resolved in Steps 1–2, otherwise the literal `none`.
- `artifacts=[<list>]` — repo-relative paths to `investigation.md`, `plan.md`, and `phase-state.yaml` (when present) on success, or `artifacts: []` on failure.
- `next_recommended=/impl <plan-path>` — set to `/impl .simple-workflow/backlog/active/{ticket-dir}/plan.md` on success, or the empty string on failure.

Failure paths (investigate failure in Step 4, plan2doc failure after Step 7) MUST still emit the block with `artifacts: []` and an empty `next_recommended` (matching Step 10 prose). The block is the only signal `/autopilot` uses to decide whether to advance `current_phase` from `scout` to `impl`; suppressing it on either success or failure breaks the pipeline.

See `skills/create-ticket/references/sw-checkpoint-template.md` for the canonical block format and the list of skills that emit it.

## Instructions

### Post-/plan2doc Checklist (mandatory)

When `/plan2doc` returns, its return value will contain `**Status**: success`,
`**Output**: <path>`, `**Summary**: ...`, and `**Next Steps**: ...`. **These
lines are the delegate's return value, NOT `/scout`'s final output to the
user.** A recurring failure mode is to treat the plan2doc summary as the
terminal response and end the turn before emitting `## [SW-CHECKPOINT]`.

Required after `/plan2doc` returns successfully:

- [ ] Step 8: print the plan summary
- [ ] Step 8a: update `phases.scout.status: completed` when `phase-state.yaml` exists
- [ ] Step 9: print the final summary (paths + size)
- [ ] Step 10: emit `## [SW-CHECKPOINT]` block

If you have not yet emitted `## [SW-CHECKPOINT]` literally in this turn,
the contract is unsatisfied — do NOT end your turn.

1. Before calling /investigate, attempt to read the ticket file directly:
   - Search `.simple-workflow/backlog/product_backlog/` and `.simple-workflow/backlog/active/` for ticket files matching `$ARGUMENTS` keyword using Glob. Patterns are **depth-agnostic** so nested layouts (`.simple-workflow/backlog/active/{parent-slug}/{NNN}-{slug}/`) as well as the legacy flat layout are covered: `.simple-workflow/backlog/product_backlog/**/*<keyword>*/ticket.md` and `.simple-workflow/backlog/active/**/*<keyword>*/ticket.md`.
   - If multiple matches, use the first. If zero matches or the directories do not exist, skip to step 3 (Size stays unset, non-ticket flow).
   - If found, read the `| Size |` table row to extract the Size value (S/M/L/XL).
2. If the matched ticket is in `.simple-workflow/backlog/product_backlog/{ticket-dir}`, move it to active: `mv .simple-workflow/backlog/product_backlog/{ticket-dir} .simple-workflow/backlog/active/{ticket-dir}`. If already in `.simple-workflow/backlog/active/{ticket-dir}`, use it as-is. Record the ticket directory as `ticket-dir` (`.simple-workflow/backlog/active/{ticket-dir}`). Because `phase-state.yaml` (if present) lives inside the ticket directory, the `mv` moves it along with `ticket.md`.
2a. **Idempotency guard + begin scout phase (state update — only when `ticket-dir` is set and `phase-state.yaml` exists in the ticket dir)**:

    **Idempotency guard (runs first)**: Before beginning the scout phase, read `.simple-workflow/backlog/active/{ticket-dir}/phase-state.yaml` and check whether scout has already completed with downstream work started:
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
   - If `ticket-dir` is set, append `(ticket-dir: .simple-workflow/backlog/active/{ticket-dir})` to the arguments.
   - `/investigate` MUST NOT write to `phase-state.yaml`; only `/scout` updates `phases.scout`.
   - **Return value cap**: Return per the Context Conservation Protocol in the researcher agent definition — the spawned agent's return value MUST stay under 500 tokens (status, output path, executive summary). Full investigation content goes to the artifact path; the orchestrator reads it on demand.
4. Check the investigate response for failure conditions:
   - If the response contains `**Status**: failed` or `**Status**: partial`, print the error and stop. **Before stopping**, if `phase-state.yaml` exists, read-modify-write `phases.scout.status: failed` and `overall_status: failed`. Leave all other sections untouched.
   - If the response does not contain a research file path (e.g., no `.simple-workflow/docs/research/` or `.simple-workflow/backlog/active/` path), print an error and stop (same failure-state update as above).
   - Only proceed if `**Status**: success` and a research file path is present.
4a. **Advisory Consultation Pre-Check** (Phase 6 enforcement, v8.0.0+): `/scout` is the gate-able caller of the otherwise-declarative `/investigate` — it resumes after `/investigate` returns via the Skill tool, so it verifies the researcher's Advisory audit trail that the `context: fork` path cannot gate inline. The `/investigate` return value (the spawned researcher's `## Result` envelope) MUST contain a `**Advisory consultation**:` field per `agents/researcher.md` `### Consultation reporting format`. Match by regex `^\*\*Advisory consultation\*\*:` on the return value (case-sensitive, line-anchored). Two outcomes:
   - **Field present** → emit `[ADVISORY-CONSULT] scout researcher present` to stderr and proceed to Step 5.
   - **Field absent** → emit `[PIPELINE] scout: ADVISORY-MISSING (agent=researcher)` to stderr and append a one-line Phase 6 audit-trail-gap note to the research summary printed in Step 5; then proceed to Step 5. Do NOT set `phases.scout.status: failed`, do NOT set `overall_status: failed`, and do NOT re-invoke `/investigate` — `investigation.md` is already written to disk and `/plan2doc` consumes that file (not the return summary), so a missing Advisory field is an audit-trail gap, not a pipeline-breaking failure. This surface-don't-fail degradation matches `/catchup` Step 2.5 (artifact-preserving paths surface the violation rather than FAIL); it is distinct from the Step 4 failure path, which fails scout only when `/investigate` itself returned `failed`/`partial` or produced no research file.
5. Print the research summary and file path returned by investigate.
6. Determine the final Size (informational only — `/plan2doc` will re-detect):
   - If Size was read from the ticket file in step 1, use that value.
   - Otherwise, read the research file for a Size field (S/M/L/XL). Default to M if absent.
7. **MUST invoke `/plan2doc` via the Skill tool** with `<topic>` and the following arguments. **NEVER bypass /plan2doc** by writing `plan.md` directly — /plan2doc is the only contract-compliant author (it spawns the `planner` agent with size-aware model selection). Fail the task immediately if `/plan2doc` cannot be invoked.
   - If `ticket-dir` is set, append `(ticket-dir: .simple-workflow/backlog/active/{ticket-dir})` and `(research: .simple-workflow/backlog/active/{ticket-dir}/investigation.md)` to the arguments.
   - If `ticket-dir` is not set, use `(research: <research-file-path>)` as before.
   - `/plan2doc` will internally select the planner model based on the Size in `ticket.md` (sonnet for S, opus for M/L/XL).
   - `/plan2doc` MUST NOT write to `phase-state.yaml`; only `/scout` updates `phases.scout`.
   - **Return value cap**: Return per the Context Conservation Protocol in the planner agent definition — the spawned agent's return value MUST stay under 500 tokens (status, plan.md output path, 1-2 line summary). The full plan content lives in `plan.md`; the orchestrator reads it on demand.

   > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: `/plan2doc` has just returned (`plan2doc: ac-source=ticket.md verbatim=true` ssot-line + plan summary). That return value is `/scout`'s input, not your output. You are NOT done — Steps 8, 8a, 9, and 10 remain in this turn. Do NOT end your turn. Do NOT treat the plan2doc summary as the final response. Required next emit: `## [SW-CHECKPOINT]` in Step 10.

8. Print the plan summary and file path returned by plan2doc.
8a. **Complete scout phase (state update — only when `ticket-dir` is set and `phase-state.yaml` exists)**: After both `investigation.md` and `plan.md` are successfully written, read `.simple-workflow/backlog/active/{ticket-dir}/phase-state.yaml` and update ONLY the following fields (read-modify-write):
    - `phases.scout.status: completed`
    - `phases.scout.completed_at: {now}` (ISO-8601 UTC, recomputed at this step)
    - `phases.scout.artifacts.investigation: .simple-workflow/backlog/active/{ticket-dir}/investigation.md`
    - `phases.scout.artifacts.plan: .simple-workflow/backlog/active/{ticket-dir}/plan.md`
    - `last_completed_phase: scout`
    - `current_phase: impl`
    Do NOT modify `phases.create_ticket`, `phases.impl`, or `phases.ship`. Do NOT modify `overall_status` (it remains `in-progress`).
9. Print a final summary with both file paths and the detected size.

10. **Emit SW-CHECKPOINT block**. Emit the `## [SW-CHECKPOINT]` block per `skills/create-ticket/references/sw-checkpoint-template.md` as the FINAL section of the skill's response, after the final summary in step 9 and after any error output. Fill: `phase=scout`, `ticket=.simple-workflow/backlog/active/{ticket-dir}` when a ticket was resolved in steps 1–2 (otherwise `none`), `artifacts=[<repo-relative paths to investigation.md and plan.md, plus phase-state.yaml if present>]`, `next_recommended=/impl .simple-workflow/backlog/active/{ticket-dir}/plan.md` on success (or `""` if no `plan.md` was produced). Emit on failure paths with `artifacts: []`.

## Error Handling

- **Empty arguments**: Print "Usage: /scout <topic or ticket>" and stop.
- **investigate failure**: If `**Status**: failed` or `**Status**: partial` is present, or no research file path (`.simple-workflow/docs/research/` or `.simple-workflow/backlog/active/` path) is found in the response, print the error and stop. Do NOT proceed to plan2doc.
- **plan2doc failure**: Print the error and the research file path (research is still valid).
- **Ticket not found**: If no ticket matches in `.simple-workflow/backlog/product_backlog/` or `.simple-workflow/backlog/active/`, continue without ticket-dir (non-ticket flow, Size stays unset).
