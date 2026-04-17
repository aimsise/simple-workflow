---
name: autopilot
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Execute the full development pipeline automatically from a brief document.
  Dispatches the ticket-pipeline agent per ticket for context-isolated execution.
disable-model-invocation: false
allowed-tools:
  # Claude Code
  - Agent
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - "Bash(git status:*)"
  - "Bash(git diff:*)"
  - "Bash(git log:*)"
  - "Bash(git branch:*)"
  - "Bash(gh:*)"
  - "Bash(mv:*)"
  - "Bash(ls:*)"
  - "Bash(mkdir:*)"
  - "Bash(date:*)"
  - "Bash(cp:*)"
  # Copilot CLI
  - task
  - view
  - create
  - edit
  - glob
  - grep
  - "shell(git status:*)"
  - "shell(git diff:*)"
  - "shell(git log:*)"
  - "shell(git branch:*)"
  - "shell(gh:*)"
  - "shell(mv:*)"
  - "shell(ls:*)"
  - "shell(mkdir:*)"
  - "shell(date:*)"
  - "shell(cp:*)"
argument-hint: "<slug>"
---

## Pre-computed Context

Brief files:
!`ls .backlog/briefs/active/*/brief.md 2>/dev/null`

Active tickets:
!`ls -d .backlog/active/*/ 2>/dev/null | head -10`

Current branch:
!`git branch --show-current`

Default branch:
!`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main`

## Mandatory Skill Invocations

The following invocation is **contractual** — `/autopilot` MUST dispatch the `ticket-pipeline` agent via the Agent tool for each ticket. Direct file operations, ad-hoc bash commands, or model self-judgment are **never acceptable substitutes**. The `ticket-pipeline` agent internally invokes `/create-ticket`, `/scout`, `/impl`, and `/ship` in its own isolated context and returns a minimal Result block.

| Invocation Target | When | Skip consequence |
|---|---|---|
| `ticket-pipeline` agent (Agent tool) | Phase 2 — once per ticket (single or split flow) | All per-ticket artifacts missing (ticket.md, investigation.md, plan.md, eval-round-*.md, audit-round-*.md, quality-round-*.md), ticket marked failed, no PR created |

**Binding rules**:
- `MUST invoke ticket-pipeline via the Agent tool for each ticket` — never call `/create-ticket`, `/scout`, `/impl`, `/ship` directly from `/autopilot`.
- `NEVER bypass ticket-pipeline via direct file operations or direct skill invocations` — ticket-pipeline handles all per-ticket state management, artifact verification (Artifact Presence Gate), and skill invocation auditing internally.
- `Fail this ticket immediately if ticket-pipeline cannot be dispatched via the Agent tool` — record the failure in `autopilot-state.yaml` and proceed to Phase 3 (single) or the next ticket (split). Do NOT fabricate artifacts to appear to satisfy the artifact presence gate.

# /autopilot

Target slug: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS`:
- Extract the slug (first argument).
- If empty, print "Usage: /autopilot <slug>" and stop.

## Phase 1: Pre-flight Checks

1. Verify `.backlog/briefs/active/{slug}/brief.md` exists. If not, print available briefs from Pre-computed Context and stop.
2. Verify `.backlog/briefs/active/{slug}/autopilot-policy.yaml` exists. If not, print "ERROR: No autopilot-policy.yaml found. Run /brief {slug} first." and stop.
3. Read brief.md. Verify frontmatter `status` is `confirmed`. If `draft`, print "ERROR: Brief status is 'draft'. Update to 'confirmed' or run /brief with auto=true." and stop.
4. Read autopilot-policy.yaml for use in decision logging.
5. **Human override detection**: Compare each gate's action in the policy against the expected defaults for the declared `risk_tolerance` level:
   - `conservative` defaults: `ticket_quality_fail.action: retry_with_feedback`, `evaluator_dry_run_fail.action: stop`, `ac_eval_fail.action: retry`, `audit_infrastructure_fail.action: stop`, `ship_review_gate.action: stop`, `ship_ci_pending.action: wait`, `ship_ci_pending.timeout_minutes: 30`, `constraints.max_total_rounds: 9`, `constraints.allow_breaking_changes: false`, `unexpected_error.action: stop`
   - `moderate` defaults: same as conservative except `evaluator_dry_run_fail.action: proceed_without`, `audit_infrastructure_fail.action: treat_as_fail`, `ship_review_gate.action: proceed_if_eval_passed`
   - `aggressive` defaults: same as moderate except `ship_ci_pending.timeout_minutes: 60`, `constraints.max_total_rounds: 12`, `constraints.allow_breaking_changes: true`
   - If any gate action differs from the expected default for the declared `risk_tolerance`:
     - Check whether the corresponding line in the policy YAML has a `# kb-suggested` comment.
     - If `# kb-suggested` is present → record it as a **kb_override** (not a human override).
     - If `# kb-suggested` is absent → record it as a **human_override**.
     - Store each override as (gate name, expected action, actual action, type: `human_override` | `kb_override`) for inclusion in the autopilot-log.
   - If no differences are found, record "No human overrides detected."
6. Check if `.backlog/briefs/active/{slug}/split-plan.md` exists. If it does, read it and parse the ticket list and dependency graph. If it does not exist, proceed with single-ticket flow.

7. **Autopilot state recovery**: Check if `.backlog/briefs/active/{slug}/autopilot-state.yaml` exists.
   - If it does NOT exist: set `resume_mode = false` and proceed normally to Phase 2.
   - If it exists: set `resume_mode = true`. Read and parse the state file.
     - Print resume summary:
       ```
       [RESUME] 前回の /autopilot 実行が途中で停止しています。途中から再開します。
       [RESUME] Execution mode: {execution_mode}
       [RESUME] Progress: {completed_count}/{total_tickets} tickets completed
       ```
     - For each ticket, print: `[RESUME] {logical_id} → {ticket_dir}: {status} (last completed: {last_completed_step})`
     - If the `started` timestamp is older than 7 days, print: `[RESUME] WARNING: State file is from {started}. Codebase may have changed. Consider deleting autopilot-state.yaml and re-running.`
     - Carry forward `ticket_mapping` from the state file.
     - Resume logic per ticket:
       - `status: completed` → skip entirely, print `[RESUME] Skipping {logical_id}: already completed`
       - `status: failed` or `skipped` → re-attempt from the first non-completed step
       - `status: in_progress` → resume from the step marked `in_progress` (re-run it, since it may not have completed)
       - `status: pending` → execute normally
     - When skipping `create-ticket`: use `ticket_dir` from the state file
     - When skipping `scout`: ticket is already in `.backlog/active/{ticket-dir}/` with investigation.md and plan.md

## Phase 2: Pipeline Execution

### Execution Mode Detection

If split-plan.md was detected in Phase 1:
- Parse the `ticket_count` and each ticket's `depends_on` list
- Build a dependency graph and compute a topological sort for execution order
- Execute using the **Split Execution Flow** below

If no split-plan.md:
- Execute using the existing **Single Ticket Flow** (steps 9-13 below)

### State file initialization

Skip this block if `resume_mode = true` (state file already exists from the interrupted run).

Write `.backlog/briefs/active/{slug}/autopilot-state.yaml`:

```yaml
version: 1
slug: {slug}
started: {ISO-8601 timestamp via `date -u +%Y-%m-%dT%H:%M:%SZ`}
execution_mode: single | split
total_tickets: {N}
ticket_mapping: {}
tickets:
  - logical_id: {slug} (single) or {slug}-part-{N} (split, one entry per ticket)
    ticket_dir: null
    status: pending
    steps:
      create-ticket: pending
      scout: pending
      impl: pending
      ship: pending
```

### Single Ticket Flow

9. Update brief.md frontmatter status from `confirmed` to `in-progress`.

10. **Dispatch ticket-pipeline agent**:
    - **State update (before)**: Update autopilot-state.yaml: `tickets[0].status = "in_progress"`.
    - Copy `autopilot-policy.yaml` from `.backlog/briefs/active/{slug}/` to the brief directory if not already there (ticket-pipeline reads it from there).
    - **MUST invoke `ticket-pipeline` via the Agent tool** with the following inputs:
      - `brief_slug`: `{slug}`
      - `ticket_index`: `0`
      - `logical_id`: `{slug}`
      - `state_file`: `.backlog/briefs/active/{slug}/autopilot-state.yaml`
      - `policy_file`: `.backlog/briefs/active/{slug}/autopilot-policy.yaml`
      - `brief_path`: `.backlog/briefs/active/{slug}/brief.md`
    - If `resume_mode = true` and the ticket is `in_progress` or `failed`, ticket-pipeline will read `autopilot-state.yaml` and resume from the appropriate step internally.
    - **NEVER call `/create-ticket`, `/scout`, `/impl`, or `/ship` directly from `/autopilot`** — ticket-pipeline handles all four steps internally.
    - Fail this ticket immediately if `ticket-pipeline` cannot be dispatched via the Agent tool.

11. **Process ticket-pipeline result**:
    - Parse the Result block returned by ticket-pipeline:
      - `Status`: `completed` | `completed-with-warnings` | `failed` | `stopped`
      - `Ticket Dir`: the ticket directory path
      - `PR URL`: the PR URL or `null`
      - `Manual Bash Fallbacks`: list of steps that fell back to manual bash, or `none`
      - `Failure Reason`: present only when Status is `failed` or `stopped`
    - Re-read `.backlog/briefs/active/{slug}/autopilot-state.yaml` to get the final ticket state (ticket-pipeline writes step completion status internally).
    - **Result handling**:
      - `Status: completed` → record `[PIPELINE] ticket-pipeline: completed | ticket={ticket-dir} | pr={pr-url}`, proceed to Phase 3.
      - `Status: completed-with-warnings` → record `[PIPELINE] ticket-pipeline: completed-with-warnings | ticket={ticket-dir} | pr={pr-url} | fallbacks={Manual Bash Fallbacks}`, store warnings for Phase 3 autopilot-log.
      - `Status: failed` → record `[PIPELINE] ticket-pipeline: failed | ticket={ticket-dir} | reason={Failure Reason}`, go to Phase 3 (failure).
      - `Status: stopped` → record `[PIPELINE] ticket-pipeline: stopped | ticket={ticket-dir} | reason={Failure Reason}`, go to Phase 3 (failure).

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
    > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
    > 2. Proceed directly to Phase 3. Do NOT end your turn. Do NOT summarize.

## Phase 3: Completion

14. **Generate autopilot-log.md**: Write to the ticket directory's `autopilot-log.md`. Determine the actual ticket location by checking the filesystem in this order:
    1. Check `.backlog/done/{ticket-dir}/` first — the ticket is here if `/ship` completed or partially completed (ticket moves to `done/` at `/ship` Step 5, before PR creation).
    2. Check `.backlog/active/{ticket-dir}/` — the ticket is here if `/ship` was never invoked or did not reach Step 5.
    3. If `{ticket-dir}` is not yet determined (e.g., create-ticket failed before producing a slug), fall back to `.backlog/briefs/active/{slug}/autopilot-log.md`.
    Write `autopilot-log.md` to whichever path is found.

```yaml
---
brief_slug: {slug}
ticket_dir: {ticket-dir}
started: {start-timestamp}
completed: {end-timestamp}
final_status: completed | completed-with-warnings | stopped | failed
---
```

Followed by:
- ## Pipeline Execution section with each step's status
- ## Warnings section: Present when any ticket returned `completed-with-warnings` or had non-empty `Manual Bash Fallbacks`. List each warning with the step name and fallback method used. If no warnings, omit this section entirely.
- ## Human Overrides section: List only `human_override` type entries from step 5 as `| {gate} | {expected_action} | {actual_action} | human_override |`. Exclude `kb_override` entries from this section. If no human overrides, write "No human overrides detected."
- ## KB Overrides section: List only `kb_override` type entries from step 5 as `| {gate} | {expected_action} | {actual_action} | kb_override |`. If no KB overrides, write "No KB overrides detected."
- ## Decisions Made table (parse [AUTOPILOT-POLICY] prefixed output from skill invocations if available, or note "No policy decisions were triggered" if pipeline ran without hitting any gates). Include overrides from step 5 as entries, distinguishing type `human_override` from `kb_override` in the type column.
- ## Stop Reason section (only if stopped/failed)

15. **Update brief lifecycle**:
    - If all steps succeeded (final_status = completed):
      - Update brief.md status to `completed`
      - Move: `mv .backlog/briefs/active/{slug} .backlog/briefs/done/{slug}` (create .backlog/briefs/done/ if needed)
    - If any step failed (final_status = stopped or failed):
      - Update brief.md status to `stopped`
      - Brief stays in .backlog/briefs/active/

16. **Print Completion Report** (under 500 tokens):
    - Final status
    - Each pipeline step result
    - PR URL (if created)
    - Files changed count (from `git diff --stat`)
    - Impl rounds count
    - autopilot-log.md path
    - If stopped/failed: "To resume, re-run `/autopilot {slug}`. The pipeline will automatically continue from the last checkpoint. To start fresh, delete `.backlog/briefs/active/{slug}/autopilot-state.yaml` first."

17. **State file cleanup**: Delete `.backlog/briefs/active/{slug}/autopilot-state.yaml`.
    - If brief was moved to `.backlog/briefs/done/{slug}/` (step 15), delete from there instead.
    - The `autopilot-log.md` serves as the permanent execution record.

### Split Execution Flow

**Mapping table initialization**: If `resume_mode = true`, use `ticket_mapping` from the state file. Otherwise, initialize an empty mapping table `ticket_mapping` that will store `{slug}-part-{N}` → `{ticket-dir}` entries. This table maps logical ticket identifiers (from split-plan.md) to physical directory names (assigned by `/create-ticket`).

For each ticket in topological order (let `i` be the 0-based index of the current ticket):

1. **Resume skip check** (only when `resume_mode = true`):
   - If `tickets[i].status` is `completed` in the state file → skip entirely. Print `[RESUME] Skipping ticket {logical_id}: already completed`. Continue to the next ticket.
   - If `tickets[i].status` is `skipped` → re-evaluate dependencies (they may now be satisfied in a resumed run).
   - If `tickets[i].status` is `failed` or `in_progress` → ticket-pipeline will resume from the appropriate step internally.

2. **Dependency check**: Verify all tickets in `depends_on` have status `completed` (PR created successfully).
   - If any dependency has status `failed` or `skipped` → mark this ticket as `skipped` with reason "dependency {dep-slug} {status}". Update autopilot-state.yaml: `tickets[i].status = "skipped"`. Record `[PIPELINE] {ticket-part}: skipped | reason=dependency_{dep-slug}_{status} | ticket-dir={ticket-dir-if-known}` and continue to the next ticket. Use the `ticket_mapping` table to resolve `{ticket-dir-if-known}` for the dependency (or `unknown` if not yet mapped).
   - If all dependencies are `completed` → proceed.

3. **Dispatch ticket-pipeline agent**:
   - **State update (before)**: Update autopilot-state.yaml: `tickets[i].status = "in_progress"`.
   - **MUST invoke `ticket-pipeline` via the Agent tool** with the following inputs:
     - `brief_slug`: `{slug}`
     - `ticket_index`: `{i}`
     - `logical_id`: `{slug}-part-{N}`
     - `state_file`: `.backlog/briefs/active/{slug}/autopilot-state.yaml`
     - `policy_file`: `.backlog/briefs/active/{slug}/autopilot-policy.yaml`
     - `brief_path`: `.backlog/briefs/active/{slug}/brief.md`
     - `split_plan_path`: `.backlog/briefs/active/{slug}/split-plan.md`
   - **NEVER call `/create-ticket`, `/scout`, `/impl`, or `/ship` directly from `/autopilot`** — ticket-pipeline handles all four steps internally.
   - Fail this ticket immediately if `ticket-pipeline` cannot be dispatched via the Agent tool.

4. **Process ticket-pipeline result**:
   - Parse the Result block returned by ticket-pipeline (same format as Single Ticket Flow step 11).
   - Re-read `.backlog/briefs/active/{slug}/autopilot-state.yaml` to get the final ticket state.
   - Update `ticket_mapping` from the state file (ticket-pipeline writes `ticket_mapping.{logical_id} = {ticket_dir}` internally).
   - **Result handling**:
     - `Status: completed` → record `[PIPELINE] {logical_id}: completed | ticket={ticket-dir} | pr={pr-url}`, continue to the next ticket.
     - `Status: completed-with-warnings` → record `[PIPELINE] {logical_id}: completed-with-warnings | ticket={ticket-dir} | pr={pr-url} | fallbacks={Manual Bash Fallbacks}`, store warnings for autopilot-log, continue to the next ticket.
     - `Status: failed` → record `[PIPELINE] {logical_id}: failed | ticket={ticket-dir} | reason={Failure Reason}`, continue to the next ticket. Dependent tickets will be skipped at step 2.
     - `Status: stopped` → record `[PIPELINE] {logical_id}: stopped | ticket={ticket-dir} | reason={Failure Reason}`, continue to the next ticket.

   > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
   > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
   > 2. The state file shows the next pending ticket. Execute it immediately.
   > 3. Do NOT end your turn. Do NOT summarize. Proceed directly to the next ticket.

5. **Error handling per ticket**:
   - If ticket-pipeline returns `failed` or `stopped` → the ticket is already marked in the state file, log the error.
   - Continue to the next ticket (do NOT stop the entire pipeline).
   - Tickets that depend on a failed ticket will be skipped (step 2 above).
   - Tickets with no dependency on the failed ticket will still execute.

### Split Autopilot Log

For split execution, you MUST write both the overall autopilot-log and per-ticket individual logs. Follow these steps in order:

1. **Overall log**: Write the overall `autopilot-log.md` to `.backlog/briefs/active/{slug}/autopilot-log.md` (or `.backlog/briefs/done/{slug}/autopilot-log.md` if the brief has already been moved).
2. **Per-ticket logs**: For each ticket, you MUST write an individual `autopilot-log.md` to its ticket directory. To determine each ticket's actual directory location, search in this order:
   1. Check `.backlog/done/{ticket-dir}/` first — the ticket is here if `/ship` completed or partially completed (ticket moves to `done/` at `/ship` Step 5, before PR creation).
   2. Check `.backlog/active/{ticket-dir}/` — the ticket is here if `/ship` was never invoked or did not reach Step 5.
   Write each ticket's individual `autopilot-log.md` to whichever path is found.

IMPORTANT: Skipping per-ticket individual logs is not allowed. Every ticket that was processed (completed, failed, or skipped) MUST have its own `autopilot-log.md` written to its ticket directory.

The overall autopilot-log.md includes additional fields:

```yaml
---
brief_slug: {slug}
started: {timestamp}
completed: {timestamp}
final_status: completed | completed-with-warnings | partial | failed
ticket_count: {N}
tickets_completed: {N}
tickets_failed: {N}
tickets_skipped: {N}
ticket_mapping:
  {slug}-part-1: {ticket-dir-1}
  {slug}-part-2: {ticket-dir-2}
---
```

Each ticket gets its own subsection in ## Pipeline Execution:

```markdown
### Ticket: {slug}-part-{N} → {ticket-dir} ({status})
- ticket-pipeline: {status}
- PR: {url}
- Manual Bash Fallbacks: {fallbacks or "none"}
```

Include a ## Warnings section when any ticket returned `completed-with-warnings` or had non-empty `Manual Bash Fallbacks`. List each warning with the ticket identifier and the fallback steps. If no warnings, omit this section.

### Split Completion Report

Print:
- Overall status (completed / partial / failed)
- Per-ticket results table with status + PR URL
- Counts: {completed}/{failed}/{skipped} of {total}
- If partial/failed: "To resume, re-run `/autopilot {slug}`. The pipeline will automatically continue from the last checkpoint. To start fresh, delete `.backlog/briefs/active/{slug}/autopilot-state.yaml` first."

### Split Brief Lifecycle

- All tickets completed (or completed-with-warnings) → brief status = `completed`, move to briefs/done/
- Any ticket failed or skipped → brief status = `stopped`, stay in briefs/active/
- final_status determination:
  - All completed (no warnings) → `completed`
  - All completed but some had warnings → `completed-with-warnings`
  - Some completed + some failed/skipped → `partial`
  - First ticket failed → `failed`

### Split State File Cleanup

After the Split Brief Lifecycle step, delete `.backlog/briefs/active/{slug}/autopilot-state.yaml` (or `.backlog/briefs/done/{slug}/autopilot-state.yaml` if the brief was moved). The overall `autopilot-log.md` and per-ticket logs serve as the permanent record.

## Error Handling

- **Empty arguments**: Print "Usage: /autopilot <slug>" and stop.
- **Brief not found**: List available briefs and stop.
- **Policy not found**: Print instructions to run `/brief` first.
- **Brief not confirmed**: Print instructions to update status.
- **Any pipeline step failure (single ticket flow)**: Check `autopilot-policy.yaml` `gates.unexpected_error.action`:
  - If `stop` (default): Log to autopilot-log.md, update brief status to stopped, print partial completion report. Do NOT attempt to continue to the next step.
  - If `action` is any value other than `stop` (e.g., user edited to an unsupported action): treat as `stop` (safety fallback). Print `[AUTOPILOT-POLICY] gate=unexpected_error action=stop (fallback from unsupported action={original_action})`.
  - If the policy does not exist or `unexpected_error` is not defined, default to `stop`.
  Print `[AUTOPILOT-POLICY] gate=unexpected_error action={actual_action}` when this gate is invoked (where `{actual_action}` is the resolved action: `stop` in all cases, including fallback).
- **Any pipeline step failure (split flow)**: Log to autopilot-log.md for that ticket, mark as failed, continue to next ticket. Dependent tickets are skipped.
- **Artifact preservation**: On failure, all artifacts created so far (ticket, plan, eval-round, etc.) are preserved in the ticket directory. This may be `.backlog/done/{ticket-dir}/` (if `/ship` Step 5 completed before the failure) or `.backlog/active/{ticket-dir}/` (if `/ship` was never invoked or did not reach Step 5). Check both locations to find the artifacts. The `autopilot-state.yaml` in `.backlog/briefs/active/{slug}/` records the exact progress for automatic resume via `/autopilot {slug}`.
