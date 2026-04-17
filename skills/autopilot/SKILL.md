---
name: autopilot
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Execute the full development pipeline automatically from a brief document.
  Chains create-ticket, scout, impl, and ship with policy-based autonomous
  decision making at each gate.
disable-model-invocation: false
allowed-tools:
  # Claude Code
  - Skill
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
  - skill
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

The following skill invocations are **contractual** — `/autopilot` MUST delegate to each of these via the Skill tool. Direct file operations, ad-hoc bash commands, or model self-judgment are **never acceptable substitutes**. Any bypass is a pipeline defect and will be detected by the artifact presence gate and the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `/create-ticket` (Skill) | Phase 2 step 10 (single flow) and step 3a (split flow), once per ticket | No `ticket.md` written with the shared `.ticket-counter` slot — artifact presence gate fails; autopilot-state.yaml records `steps.create-ticket: failed` and the ticket is marked failed |
| `/scout` (Skill) | Phase 2 step 11 (single) / step 3c (split), after create-ticket succeeds | Missing `investigation.md` + `plan.md` in `.backlog/active/{ticket-dir}/` — Phase 2 artifact verification triggers `[PIPELINE] scout: ARTIFACT-MISSING`, ticket marked failed |
| `/impl` (Skill) | Phase 2 step 12 (single) / step 3d (split), after scout succeeds | Missing `eval-round-*.md` (and `audit-round-*.md` / `quality-round-*.md` on PASS) — artifact verification triggers `[PIPELINE] impl: ARTIFACT-MISSING`, ticket marked failed |
| `/ship` (Skill) | Phase 2 step 13 (single) / step 3e (split), after impl succeeds | Ticket not moved from `.backlog/active/` to `.backlog/done/` — artifact verification triggers `[PIPELINE] ship: ARTIFACT-MISSING`; no PR is created |

**Binding rules**:
- `MUST invoke /create-ticket via the Skill tool` — never substitute by writing `ticket.md` directly or by bumping `.ticket-counter` manually.
- `MUST invoke /scout via the Skill tool` — never substitute by calling `/investigate` or `/plan2doc` standalone; `/scout` is the only contract-compliant entry point.
- `MUST invoke /impl via the Skill tool` — never substitute by spawning `implementer` or `ac-evaluator` agents directly from `/autopilot`.
- `MUST invoke /ship via the Skill tool` — never substitute by running `git commit`, `gh pr create`, or `mv` commands directly.
- `NEVER bypass these skills via direct file operations` — even if a step appears trivial, the pipeline's correctness depends on each skill's internal state-management and artifact-writing side effects.
- `Fail this ticket immediately if any mandatory invocation cannot be completed via the prescribed Skill tool` — record the failure in `autopilot-state.yaml` and proceed to Phase 3 (single) or the next ticket (split). Do NOT fabricate artifacts to appear to satisfy the artifact presence gate.

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
    invocation_method:
      create-ticket: unknown
      scout: unknown
      impl: unknown
      ship: unknown
```

### Single Ticket Flow

9. Update brief.md frontmatter status from `confirmed` to `in-progress`.

10. **Step: create-ticket**
    If `resume_mode = true` and this step is already `completed` in the state file, skip to step 11 using `ticket_dir` from the state file.
    - **State update (before)**: Update autopilot-state.yaml: `tickets[0].steps.create-ticket = "in_progress"`, `tickets[0].status = "in_progress"`, `tickets[0].invocation_method.create-ticket = "skill"`.
    - **MUST invoke `/create-ticket` via the Skill tool** with argument: `{brief-title} brief=.backlog/briefs/active/{slug}/brief.md`
      where {brief-title} is extracted from the brief's ## Vision section (first sentence).
      **NEVER bypass /create-ticket by writing `ticket.md` directly or mutating `.ticket-counter` from within `/autopilot`.** Fail this ticket immediately if `/create-ticket` cannot be invoked via the Skill tool.
    - If Skill tool invocation fails and a Bash fallback is used, update: `tickets[0].invocation_method.create-ticket = "manual-bash"`.
    - Parse the response to extract the created ticket slug and path (from the summary output: "Ticket file path: .backlog/product_backlog/{ticket-dir}/ticket.md").
    - If `/create-ticket` fails: Update autopilot-state.yaml: `tickets[0].steps.create-ticket = "failed"`, `tickets[0].status = "failed"`. Log the error to autopilot-log and go to Phase 3 (failure).
    - On success: copy `autopilot-policy.yaml` from `.backlog/briefs/active/{slug}/` to `.backlog/product_backlog/{ticket-dir}/autopilot-policy.yaml` (so that when `/scout` moves the ticket directory from product_backlog to active, the policy file moves with it).
    - **State update (after)**: Update autopilot-state.yaml: `tickets[0].steps.create-ticket = "completed"`, `tickets[0].ticket_dir = {ticket-dir}`, `ticket_mapping.{slug} = {ticket-dir}`.
    - Record: `[PIPELINE] create-ticket: success | ticket={ticket-dir}`

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
    > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
    > 2. The state file shows the next pending step. Execute it immediately.
    > 3. Do NOT end your turn. Do NOT summarize. Proceed directly to the next step.

11. **Step: scout**
    If `resume_mode = true` and this step is already `completed` in the state file, skip to step 12. The ticket is already in `.backlog/active/{ticket-dir}/` with investigation.md and plan.md.
    - **State update (before)**: Update autopilot-state.yaml: `tickets[0].steps.scout = "in_progress"`, `tickets[0].invocation_method.scout = "skill"`.
    - **Policy guard**: Verify that `autopilot-policy.yaml` exists in `.backlog/product_backlog/{ticket-dir}/` (copied in step 10). If not found, log `[PIPELINE] scout: ABORT — autopilot-policy.yaml missing in ticket dir` and go to Phase 3 (failure). Do NOT proceed without the policy file.
    - **MUST invoke `/scout` via the Skill tool** with argument: `{ticket-dir}`. **NEVER bypass /scout via direct `/investigate` or `/plan2doc` calls** — the contract requires /scout as the single entry point. Fail this ticket immediately if `/scout` cannot be invoked.
    - If Skill tool invocation fails and a Bash fallback is used, update: `tickets[0].invocation_method.scout = "manual-bash"`.
    - Parse the response for success/failure status.
    - If `/scout` fails: Update autopilot-state.yaml: `tickets[0].steps.scout = "failed"`, `tickets[0].status = "failed"`. Log the error and go to Phase 3 (failure).
    - On success: Verify that `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/` (scout moved the ticket directory including the policy). If missing, copy it from `.backlog/briefs/active/{slug}/autopilot-policy.yaml` as a safety net.
    - **Artifact verification**: Verify that both `.backlog/active/{ticket-dir}/investigation.md` and `.backlog/active/{ticket-dir}/plan.md` exist. If either file is missing, record `[PIPELINE] scout: ARTIFACT-MISSING — investigation.md or plan.md not found in .backlog/active/{ticket-dir}/`, update autopilot-state.yaml: `tickets[0].steps.scout = "failed"`, `tickets[0].status = "failed"`, and go to Phase 3 (failure).
    - **State update (after)**: Update autopilot-state.yaml: `tickets[0].steps.scout = "completed"`.
    - Record: `[PIPELINE] scout: success`

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
    > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
    > 2. The state file shows the next pending step. Execute it immediately.
    > 3. Do NOT end your turn. Do NOT summarize. Proceed directly to the next step.

12. **Step: impl**
    If `resume_mode = true` and this step is already `completed` in the state file, skip to step 13.
    - **State update (before)**: Update autopilot-state.yaml: `tickets[0].steps.impl = "in_progress"`, `tickets[0].invocation_method.impl = "skill"`.
    - **Policy guard**: Verify that `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If not found, log `[PIPELINE] impl: ABORT — autopilot-policy.yaml missing in ticket dir` and go to Phase 3 (failure). Do NOT proceed without the policy file.
    - **MUST invoke `/impl` via the Skill tool** with argument: `.backlog/active/{ticket-dir}/plan.md`. **NEVER bypass /impl by spawning `implementer` or `ac-evaluator` agents directly** — /impl enforces the Generator → AC Evaluator → /audit loop and must be the single orchestrator. Fail this ticket immediately if `/impl` cannot be invoked.
    - If Skill tool invocation fails and a Bash fallback is used, update: `tickets[0].invocation_method.impl = "manual-bash"`.
    - Parse the response for the final status (PASS/FAIL/STOP).
    - If FAIL-CRITICAL or stopped: Update autopilot-state.yaml: `tickets[0].steps.impl = "failed"`, `tickets[0].status = "failed"`. Log the error and go to Phase 3 (failure).
    - **Artifact verification**: Verify the following artifacts exist in `.backlog/active/{ticket-dir}/`:
      1. At least one `eval-round-*.md` file (AC evaluation result).
      2. If the final `/impl` status is PASS (AC evaluation passed and `/audit` was invoked): at least one `audit-round-*.md` file AND at least one `quality-round-*.md` file. If `/impl` ended with FAIL at the AC evaluator stage (all rounds failed AC), audit artifacts are not expected — skip this check.
      If any expected artifact is missing, record `[PIPELINE] impl: ARTIFACT-MISSING — {missing-file-pattern} not found in .backlog/active/{ticket-dir}/`, update autopilot-state.yaml: `tickets[0].steps.impl = "failed"`, `tickets[0].status = "failed"`, and go to Phase 3 (failure).
    - **State update (after)**: Update autopilot-state.yaml: `tickets[0].steps.impl = "completed"`.
    - Record: `[PIPELINE] impl: {status} | rounds={n}`
    - Note: Decision points within `/impl` (evaluator_dry_run_fail, audit_infrastructure_fail) are handled by the autopilot-policy.yaml already copied to the ticket dir.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
    > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
    > 2. The state file shows the next pending step. Execute it immediately.
    > 3. Do NOT end your turn. Do NOT summarize. Proceed directly to the next step.

13. **Step: ship**
    If `resume_mode = true` and this step is already `completed` in the state file, skip to Phase 3.
    - **State update (before)**: Update autopilot-state.yaml: `tickets[0].steps.ship = "in_progress"`, `tickets[0].invocation_method.ship = "skill"`.
    - **Policy guard**: Verify that `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If not found, log `[PIPELINE] ship: ABORT — autopilot-policy.yaml missing in ticket dir` and go to Phase 3 (failure). Do NOT proceed without the policy file.
    - Determine the target branch from Pre-computed Context (Default branch).
    - **MUST invoke `/ship` via the Skill tool** with argument: `{target-branch} ticket-dir={ticket-dir}` (do NOT pass merge=true). **NEVER bypass /ship with direct `git commit` / `gh pr create` / `mv` commands** — /ship is responsible for moving the ticket to `done/`, invoking `/tune`, and creating the PR in a single atomic sequence. Fail this ticket immediately if `/ship` cannot be invoked. The `ticket-dir` parameter ensures `/ship` moves the correct ticket to `done/` regardless of the current branch name.
    - If Skill tool invocation fails and a Bash fallback is used, update: `tickets[0].invocation_method.ship = "manual-bash"`.
    - Parse the response to extract the PR URL.
    - If `/ship` fails: Update autopilot-state.yaml: `tickets[0].steps.ship = "failed"`, `tickets[0].status = "failed"`. Log the error and go to Phase 3 (failure).
    - **Artifact verification**: Verify that `.backlog/done/{ticket-dir}/` exists (ticket was moved from `active/` to `done/` by `/ship`). If this directory does not exist, record `[PIPELINE] ship: ARTIFACT-MISSING — .backlog/done/{ticket-dir}/ not found after ship`, update autopilot-state.yaml: `tickets[0].steps.ship = "failed"`, `tickets[0].status = "failed"`, and go to Phase 3 (failure).
    - **Artifact Presence Gate**: After `/ship` completes successfully, verify that the following 7 artifact patterns exist in the ticket directory (check `.backlog/done/{ticket-dir}/` first, then `.backlog/active/{ticket-dir}/`):
      - `ticket.md`, `investigation.md`, `plan.md`, `eval-round-*.md`, `audit-round-*.md`, `quality-round-*.md`, `security-scan-*.md`
      - If any artifact is missing: record `[PIPELINE] {step}: ARTIFACT-MISSING: {patterns}` and mark the ticket as failed.
      - **Exception**: If the last `eval-round-*.md` status is FAIL or FAIL-CRITICAL (AC評価の全ラウンドでFAIL), the absence of `audit-round-*.md`, `quality-round-*.md`, and `security-scan-*.md` is expected — skip checking those 3 patterns.
    - **State update (after)**: Update autopilot-state.yaml: `tickets[0].steps.ship = "completed"`, `tickets[0].status = "completed"`.
    - Record: `[PIPELINE] ship: success | pr={pr-url}`
    - Note: Decision points within `/ship` (ship_review_gate, ship_ci_pending) are handled by the autopilot-policy.yaml in the ticket dir.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
    > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
    > 2. The state file shows the next pending step. Execute it immediately.
    > 3. Do NOT end your turn. Do NOT summarize. Proceed directly to the next step.

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
- ## Warnings section: Present when `final_status` is `completed-with-warnings` (at least one `invocation_method` is `manual-bash`). List each manual-bash fallback step with the step name and fallback method used. If no warnings, omit this section entirely.
- ## Human Overrides section: List only `human_override` type entries from step 5 as `| {gate} | {expected_action} | {actual_action} | human_override |`. Exclude `kb_override` entries from this section. If no human overrides, write "No human overrides detected."
- ## KB Overrides section: List only `kb_override` type entries from step 5 as `| {gate} | {expected_action} | {actual_action} | kb_override |`. If no KB overrides, write "No KB overrides detected."
- ## Decisions Made table (parse [AUTOPILOT-POLICY] prefixed output from skill invocations if available, or note "No policy decisions were triggered" if pipeline ran without hitting any gates). Include overrides from step 5 as entries, distinguishing type `human_override` from `kb_override` in the type column.
- ## Stop Reason section (only if stopped/failed)

**`completed-with-warnings` determination**: Set `final_status = completed-with-warnings` when all tickets completed successfully AND at least one `invocation_method` across any ticket's steps is `manual-bash`. This indicates the pipeline completed but used a Bash fallback instead of the Skill tool for at least one step. Log the manual-bash fallback steps in the `## Warnings` section of autopilot-log.md.

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
   - If `tickets[i].status` is `failed` or `in_progress` → resume from the first non-completed step within this ticket.

2. **Dependency check**: Verify all tickets in `depends_on` have status `completed` (PR created successfully).
   - If any dependency has status `failed` or `skipped` → mark this ticket as `skipped` with reason "dependency {dep-slug} {status}". Update autopilot-state.yaml: `tickets[i].status = "skipped"`. Record `[PIPELINE] {ticket-part}: skipped | reason=dependency_{dep-slug}_{status} | ticket-dir={ticket-dir-if-known}` and continue to the next ticket. Use the `ticket_mapping` table to resolve `{ticket-dir-if-known}` for the dependency (or `unknown` if not yet mapped).
   - If all dependencies are `completed` → proceed.

3. **Execute pipeline for this ticket**:
   a. **Step: create-ticket**
      If `resume_mode = true` and `tickets[i].steps.create-ticket` is `completed`, skip to step 3b using `ticket_dir` from the state file.
      - **State update (before)**: Update autopilot-state.yaml: `tickets[i].steps.create-ticket = "in_progress"`, `tickets[i].status = "in_progress"`, `tickets[i].invocation_method.create-ticket = "skill"`.
      - **MUST invoke `/create-ticket` via the Skill tool** with the brief content + the relevant scope section from split-plan.md. Use argument: `{ticket-title} brief=.backlog/briefs/active/{slug}/brief.md`. **NEVER bypass /create-ticket** by writing `ticket.md` or updating `.ticket-counter` directly. Fail this ticket immediately if /create-ticket cannot be invoked.
      - If Skill tool invocation fails and a Bash fallback is used, update: `tickets[i].invocation_method.create-ticket = "manual-bash"`.
        - Include in the brief argument context: "This is part {N} of {total}. Scope for this ticket: {scope from split-plan}. Overall vision and constraints from the brief apply."
        - Parse the `/create-ticket` response to extract `{ticket-dir}` (from the summary output: "Ticket file path: .backlog/product_backlog/{ticket-dir}/ticket.md").
      - **State update (after)**: Update autopilot-state.yaml: `tickets[i].steps.create-ticket = "completed"`, `tickets[i].ticket_dir = {ticket-dir}`, `ticket_mapping.{slug}-part-{N} = {ticket-dir}`.
      - **Register mapping**: Add entry `{slug}-part-{N}` → `{ticket-dir}` to `ticket_mapping`.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
      > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
      > 2. The state file shows the next pending step. Execute it immediately.
      > 3. Do NOT end your turn. Do NOT summarize. Proceed directly to the next step.

   b. Copy `autopilot-policy.yaml` from `.backlog/briefs/active/{slug}/` to `.backlog/product_backlog/{ticket-dir}/autopilot-policy.yaml` (so `/scout` moves it to active with the ticket).

   c. **Step: scout**
      If `resume_mode = true` and `tickets[i].steps.scout` is `completed`, skip to step 3d. The ticket is already in `.backlog/active/{ticket-dir}/`.
      - **State update (before)**: Update autopilot-state.yaml: `tickets[i].steps.scout = "in_progress"`, `tickets[i].invocation_method.scout = "skill"`.
      - **Policy guard**: Verify `autopilot-policy.yaml` exists in `.backlog/product_backlog/{ticket-dir}/`. If not found, log `[PIPELINE] scout: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as `failed`, update state: `tickets[i].steps.scout = "failed"`, `tickets[i].status = "failed"`, and continue to the next ticket.
      - **MUST invoke `/scout {ticket-dir}` via the Skill tool**. **NEVER bypass /scout** by calling `/investigate` or `/plan2doc` directly. Fail this ticket immediately if /scout cannot be invoked.
      - If Skill tool invocation fails and a Bash fallback is used, update: `tickets[i].invocation_method.scout = "manual-bash"`. On success, verify `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If missing, copy from `.backlog/briefs/active/{slug}/autopilot-policy.yaml` as a safety net.
      - **Artifact verification**: Verify that both `.backlog/active/{ticket-dir}/investigation.md` and `.backlog/active/{ticket-dir}/plan.md` exist. If either file is missing, record `[PIPELINE] scout: ARTIFACT-MISSING — investigation.md or plan.md not found in .backlog/active/{ticket-dir}/`, update state: `tickets[i].steps.scout = "failed"`, `tickets[i].status = "failed"`, and continue to the next ticket.
      - If `/scout` fails: Update state: `tickets[i].steps.scout = "failed"`, `tickets[i].status = "failed"`. Continue to the next ticket.
      - **State update (after)**: Update autopilot-state.yaml: `tickets[i].steps.scout = "completed"`.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
      > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
      > 2. The state file shows the next pending step. Execute it immediately.
      > 3. Do NOT end your turn. Do NOT summarize. Proceed directly to the next step.

   d. **Step: impl**
      If `resume_mode = true` and `tickets[i].steps.impl` is `completed`, skip to step 3e.
      - **State update (before)**: Update autopilot-state.yaml: `tickets[i].steps.impl = "in_progress"`, `tickets[i].invocation_method.impl = "skill"`.
      - **Policy guard**: Verify `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If not found, log `[PIPELINE] impl: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as `failed`, update state: `tickets[i].steps.impl = "failed"`, `tickets[i].status = "failed"`, and continue to the next ticket.
      - **MUST invoke `/impl .backlog/active/{ticket-dir}/plan.md` via the Skill tool**. **NEVER bypass /impl** by spawning `implementer` or `ac-evaluator` agents directly. Fail this ticket immediately if /impl cannot be invoked.
      - If Skill tool invocation fails and a Bash fallback is used, update: `tickets[i].invocation_method.impl = "manual-bash"`.
      - If `/impl` fails: Update state: `tickets[i].steps.impl = "failed"`, `tickets[i].status = "failed"`. Continue to the next ticket.
      - **Artifact verification**: Verify the following artifacts exist in `.backlog/active/{ticket-dir}/`:
        1. At least one `eval-round-*.md` file (AC evaluation result).
        2. If the final `/impl` status is PASS (AC evaluation passed and `/audit` was invoked): at least one `audit-round-*.md` file AND at least one `quality-round-*.md` file. If `/impl` ended with FAIL at the AC evaluator stage (all rounds failed AC), audit artifacts are not expected — skip this check.
        If any expected artifact is missing, record `[PIPELINE] impl: ARTIFACT-MISSING — {missing-file-pattern} not found in .backlog/active/{ticket-dir}/`, update state: `tickets[i].steps.impl = "failed"`, `tickets[i].status = "failed"`, and continue to the next ticket.
      - **State update (after)**: Update autopilot-state.yaml: `tickets[i].steps.impl = "completed"`.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
      > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
      > 2. The state file shows the next pending step. Execute it immediately.
      > 3. Do NOT end your turn. Do NOT summarize. Proceed directly to the next step.

   e. **Step: ship**
      If `resume_mode = true` and `tickets[i].steps.ship` is `completed`, skip to step 3f.
      - **State update (before)**: Update autopilot-state.yaml: `tickets[i].steps.ship = "in_progress"`, `tickets[i].invocation_method.ship = "skill"`.
      - **Policy guard**: Verify `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If not found, log `[PIPELINE] ship: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as `failed`, update state: `tickets[i].steps.ship = "failed"`, `tickets[i].status = "failed"`, and continue to the next ticket.
      - **MUST invoke `/ship {target-branch} ticket-dir={ticket-dir}` via the Skill tool** (no merge). **NEVER bypass /ship** with direct `git commit` / `gh pr create` / `mv` — /ship is the single atomic orchestrator for commit + ticket move + /tune + PR. Fail this ticket immediately if /ship cannot be invoked. The `ticket-dir` parameter ensures `/ship` moves the correct ticket to `done/` regardless of the current branch name.
      - If Skill tool invocation fails and a Bash fallback is used, update: `tickets[i].invocation_method.ship = "manual-bash"`.
      - If `/ship` fails: Update state: `tickets[i].steps.ship = "failed"`, `tickets[i].status = "failed"`. Continue to the next ticket.
      - **Artifact verification**: Verify that `.backlog/done/{ticket-dir}/` exists (ticket was moved from `active/` to `done/` by `/ship`). If this directory does not exist, record `[PIPELINE] ship: ARTIFACT-MISSING — .backlog/done/{ticket-dir}/ not found after ship`, update state: `tickets[i].steps.ship = "failed"`, `tickets[i].status = "failed"`, and continue to the next ticket.
      - **Artifact Presence Gate**: After `/ship` completes successfully, verify that the following 7 artifact patterns exist in the ticket directory (check `.backlog/done/{ticket-dir}/` first, then `.backlog/active/{ticket-dir}/`):
        - `ticket.md`, `investigation.md`, `plan.md`, `eval-round-*.md`, `audit-round-*.md`, `quality-round-*.md`, `security-scan-*.md`
        - If any artifact is missing: record `[PIPELINE] {step}: ARTIFACT-MISSING: {patterns}` and mark the ticket as failed.
        - **Exception**: If the last `eval-round-*.md` status is FAIL or FAIL-CRITICAL (AC評価の全ラウンドでFAIL), the absence of `audit-round-*.md`, `quality-round-*.md`, and `security-scan-*.md` is expected — skip checking those 3 patterns.
      - **State update (after)**: Update autopilot-state.yaml: `tickets[i].steps.ship = "completed"`, `tickets[i].status = "completed"`.

   f. Record PR URL and status.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
      > 1. Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`
      > 2. The state file shows the next pending step. Execute it immediately.
      > 3. Do NOT end your turn. Do NOT summarize. Proceed directly to the next step.

4. **Error handling per ticket**:
   - If any step fails → mark this ticket as `failed` (state file already updated above), log the error.
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
- create-ticket: {status}
- scout: {status}
- impl: {status} ({rounds} rounds)
- ship: {status} → PR: {url}
- Manual Bash Fallbacks: {list of steps with manual-bash invocation_method, or "none"}
```

Include a ## Warnings section when any ticket has at least one `invocation_method` of `manual-bash`. List each warning with the ticket identifier and the fallback steps. If no warnings, omit this section.

### Split Completion Report

Print:
- Overall status (completed / partial / failed)
- Per-ticket results table with status + PR URL
- Counts: {completed}/{failed}/{skipped} of {total}
- If partial/failed: "To resume, re-run `/autopilot {slug}`. The pipeline will automatically continue from the last checkpoint. To start fresh, delete `.backlog/briefs/active/{slug}/autopilot-state.yaml` first."

### Split Brief Lifecycle

- All tickets completed → brief status = `completed`, move to briefs/done/
- Any ticket failed or skipped → brief status = `stopped`, stay in briefs/active/
- final_status determination:
  - All completed (no manual-bash fallbacks) → `completed`
  - All completed but some had manual-bash invocation_method → `completed-with-warnings`
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
