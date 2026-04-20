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

`/autopilot` MUST delegate to each target below via the Skill tool. Direct file ops, ad-hoc bash, or self-judgment are never acceptable substitutes. Bypasses are detected by the artifact presence gate and the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `/create-ticket` (Skill) | Phase 2 step 10 (single) / step 3a (split), once per ticket | No `ticket.md` with shared `.ticket-counter` slot; artifact presence gate fails; `steps.create-ticket: failed`; ticket marked failed |
| `/scout` (Skill) | Phase 2 step 11 (single) / 3c (split), after create-ticket | Missing `investigation.md` + `plan.md` triggers `[PIPELINE] scout: ARTIFACT-MISSING`; ticket marked failed |
| `/impl` (Skill) | Phase 2 step 12 (single) / 3d (split), after scout | Missing `eval-round-*.md` (and `audit-round-*.md` / `quality-round-*.md` on PASS) triggers `[PIPELINE] impl: ARTIFACT-MISSING`; ticket marked failed |
| `/ship` (Skill) | Phase 2 step 13 (single) / 3e (split), after impl | Ticket not moved to `.backlog/done/` triggers `[PIPELINE] ship: ARTIFACT-MISSING`; no PR created |

**Binding rules**:
- `MUST invoke /create-ticket via the Skill tool` — never write `ticket.md` or bump `.ticket-counter` manually.
- `MUST invoke /scout via the Skill tool` — never call `/investigate` or `/plan2doc` standalone; `/scout` is the sole entry point.
- `MUST invoke /impl via the Skill tool` — never spawn `implementer` / `ac-evaluator` directly.
- `MUST invoke /ship via the Skill tool` — never run `git commit` / `gh pr create` / `mv` directly.
- `NEVER bypass these skills via direct file operations` — pipeline correctness depends on each skill's internal state-management and artifact side effects.
- `Fail this ticket immediately if any mandatory invocation cannot be completed via the prescribed Skill tool` — record in `autopilot-state.yaml` and proceed to Phase 3 (single) or the next ticket (split). Do NOT fabricate artifacts.

# /autopilot

Target slug: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS`: extract slug (first arg); empty → "Usage: /autopilot <slug>" and stop.

## Phase 1: Pre-flight Checks

1. Verify `.backlog/briefs/active/{slug}/brief.md` exists; else list briefs and stop.
2. Verify `.backlog/briefs/active/{slug}/autopilot-policy.yaml` exists; else print "ERROR: No autopilot-policy.yaml found. Run /brief {slug} first." and stop.
3. Read brief.md; `status` must be `confirmed` (if `draft`, print "ERROR: Brief status is 'draft'. Update to 'confirmed' or run /brief with auto=true." and stop).
4. Read autopilot-policy.yaml for decision logging.
5. **Human override detection**: Compare each gate's action to the expected defaults for the declared `risk_tolerance`:
   - `conservative` defaults: `ticket_quality_fail.action: retry_with_feedback`, `evaluator_dry_run_fail.action: stop`, `ac_eval_fail.action: retry`, `audit_infrastructure_fail.action: stop`, `ship_review_gate.action: stop`, `ship_ci_pending.action: wait`, `ship_ci_pending.timeout_minutes: 30`, `constraints.max_total_rounds: 9`, `constraints.allow_breaking_changes: false`, `unexpected_error.action: stop`
   - `moderate` defaults: conservative except `evaluator_dry_run_fail.action: proceed_without`, `audit_infrastructure_fail.action: treat_as_fail`, `ship_review_gate.action: proceed_if_eval_passed`
   - `aggressive` defaults: moderate except `ship_ci_pending.timeout_minutes: 60`, `constraints.max_total_rounds: 12`, `constraints.allow_breaking_changes: true`
   - Gate differs from default: check for `# kb-suggested` comment. Present → `kb_override`; absent → `human_override`. Store (gate, expected, actual, type) for the log.
   - No differences → "No human overrides detected."
6. If `.backlog/briefs/active/{slug}/split-plan.md` exists, parse the ticket list and dependency graph. Else use single-ticket flow.

7. **State recovery**: `autopilot-state.yaml` absent → `resume_mode = false`. Else `resume_mode = true`, parse:
   - Print:
     ```
     [RESUME] 前回の /autopilot 実行が途中で停止しています。途中から再開します。
     [RESUME] Execution mode: {execution_mode}
     [RESUME] Progress: {completed_count}/{total_tickets} tickets completed
     ```
   - Per ticket: `[RESUME] {logical_id} → {ticket_dir}: {status} (last completed: {last_completed_step})`.
   - `started` older than 7 days: `[RESUME] WARNING: State file is from {started}. Codebase may have changed. Consider deleting autopilot-state.yaml and re-running.`
   - Carry `ticket_mapping`. Per-ticket resume: `completed` → skip (`[RESUME] Skipping {logical_id}: already completed`); `failed` / `skipped` → retry from first non-completed step; `in_progress` → re-run that step; `pending` → normal. Skip `create-ticket` → use state's `ticket_dir`; skip `scout` → ticket already in `.backlog/active/{ticket-dir}/`.

## Phase 2: Pipeline Execution

### Execution Mode Detection

- `split-plan.md` present → parse `ticket_count` + each `depends_on`; build dependency graph; topological sort; use **Split Execution Flow**.
- No `split-plan.md` → use **Single Ticket Flow** (steps 9-13).

### State file initialization

Skip if `resume_mode = true` (state exists). This brief-level `autopilot-state.yaml` is distinct from each ticket's `phase-state.yaml` (owned by `/scout`, `/impl`, `/ship`).

Write `.backlog/briefs/active/{slug}/autopilot-state.yaml`:

```yaml
version: 1
slug: {slug}
started: {ISO-8601 via `date -u +%Y-%m-%dT%H:%M:%SZ`}
execution_mode: single | split
total_tickets: {N}
ticket_mapping: {}
tickets:
  - logical_id: {slug}  # single; or {slug}-part-{N} per ticket (split)
    ticket_dir: null
    status: pending
    steps: {create-ticket: pending, scout: pending, impl: pending, ship: pending}
    invocation_method: {create-ticket: unknown, scout: unknown, impl: unknown, ship: unknown}
```

### Single Ticket Flow

9. Update brief.md frontmatter status from `confirmed` to `in-progress`.

10. **Step: create-ticket**
    Resume: if this step is `completed` in state, skip to step 11 using `ticket_dir` from state.
    - **State update (before)**: `tickets[0].steps.create-ticket = in_progress`, `status = in_progress`, `invocation_method.create-ticket = skill`.
    - **MUST invoke `/create-ticket` via the Skill tool** with `{brief-title} brief=.backlog/briefs/active/{slug}/brief.md` (brief-title = first sentence of `## Vision`). **NEVER bypass /create-ticket by writing `ticket.md` directly or mutating `.ticket-counter`.** Fail immediately if not invokable.
    - On Bash fallback: `invocation_method.create-ticket = manual-bash`.
    - Parse response to extract ticket slug and path ("Ticket file path: .backlog/product_backlog/{ticket-dir}/ticket.md").
    - On failure: state `steps.create-ticket = failed`, `status = failed`; log and go to Phase 3.
    - Note: `autopilot-policy.yaml` is propagated to each ticket directory by `/create-ticket` itself (Plan 1 AC #14 — policy-copy responsibility moved out of `/autopilot`). `/autopilot` no longer performs this copy. The downstream Policy guard in Step 11 verifies the file is present; if absent, `/scout` is aborted.
    - **State update (after)**: `steps.create-ticket = completed`, `ticket_dir = {ticket-dir}`, `ticket_mapping.{slug} = {ticket-dir}`.
    - Record: `[PIPELINE] create-ticket: success | ticket={ticket-dir}`.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

11. **Step: scout**
    Resume: if `completed`, skip to step 12 (ticket already in `.backlog/active/{ticket-dir}/`).
    - **State update (before)**: `steps.scout = in_progress`, `invocation_method.scout = skill`.
    - **Policy guard**: Verify `autopilot-policy.yaml` exists in `.backlog/product_backlog/{ticket-dir}/`. Missing → log `[PIPELINE] scout: ABORT — autopilot-policy.yaml missing in ticket dir`, Phase 3 (failure). Do NOT proceed without policy.
    - **MUST invoke `/scout {ticket-dir}` via the Skill tool**. **NEVER bypass /scout** via `/investigate` / `/plan2doc`. Fail immediately if not invokable.
    - On Bash fallback: `invocation_method.scout = manual-bash`.
    - On failure: state `steps.scout = failed`, `status = failed`; log and go to Phase 3.
    - On success: verify `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/` (moved by `/scout`). If missing, log `[PIPELINE] scout: WARN — autopilot-policy.yaml missing in active dir after /scout` — do NOT copy from briefs (Plan 1 moved the copy responsibility to `/create-ticket`). Subsequent `/impl` Policy guard will abort.
    - **Artifact verification**: Both `investigation.md` and `plan.md` must exist in `.backlog/active/{ticket-dir}/`; missing → record `[PIPELINE] scout: ARTIFACT-MISSING — investigation.md or plan.md not found in .backlog/active/{ticket-dir}/`, state `steps.scout = failed`, `status = failed`, go to Phase 3.
    - **State update (after)**: `steps.scout = completed`.
    - Record: `[PIPELINE] scout: success`.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

12. **Step: impl**
    Resume: if `completed`, skip to step 13.
    - **State update (before)**: `steps.impl = in_progress`, `invocation_method.impl = skill`.
    - **Policy guard**: `autopilot-policy.yaml` must exist in `.backlog/active/{ticket-dir}/`. Missing → `[PIPELINE] impl: ABORT — autopilot-policy.yaml missing in ticket dir`, Phase 3 (failure).
    - **MUST invoke `/impl .backlog/active/{ticket-dir}/plan.md` via the Skill tool**. **NEVER bypass /impl** by spawning `implementer` / `ac-evaluator` directly — /impl is the sole orchestrator of the Generator → Evaluator → /audit loop. Fail immediately if not invokable.
    - On Bash fallback: `invocation_method.impl = manual-bash`.
    - Parse response for final status (PASS/FAIL/STOP). On FAIL-CRITICAL or stop: state `steps.impl = failed`, `status = failed`; log and go to Phase 3.
    - **Artifact verification** in `.backlog/active/{ticket-dir}/`:
      1. At least one `eval-round-*.md` file.
      2. If PASS (AC passed and `/audit` ran): at least one `audit-round-*.md` AND `quality-round-*.md`. If `/impl` ended FAIL at AC stage (all rounds FAIL), skip this check.
      Missing → record `[PIPELINE] impl: ARTIFACT-MISSING — {missing-file-pattern} not found in .backlog/active/{ticket-dir}/`, state `steps.impl = failed`, `status = failed`, Phase 3.
    - **State update (after)**: `steps.impl = completed`.
    - Record: `[PIPELINE] impl: {status} | rounds={n}`. Note: `/impl`'s internal decision points (evaluator_dry_run_fail, audit_infrastructure_fail) are handled by the policy already in the ticket dir.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

13. **Step: ship**
    Resume: if `completed`, skip to Phase 3.
    - **State update (before)**: `steps.ship = in_progress`, `invocation_method.ship = skill`.
    - **Policy guard**: `autopilot-policy.yaml` must exist in `.backlog/active/{ticket-dir}/`. Missing → `[PIPELINE] ship: ABORT — autopilot-policy.yaml missing in ticket dir`, Phase 3 (failure).
    - Determine target branch from Pre-computed Context.
    - **MUST invoke `/ship {target-branch} ticket-dir={ticket-dir}` via the Skill tool** (no `merge=true`). **NEVER bypass /ship** with direct `git commit` / `gh pr create` / `mv` — /ship atomically commits + moves ticket + invokes `/tune` + creates PR. Fail immediately if not invokable. `ticket-dir` ensures the correct ticket moves to `done/` regardless of branch name.
    - On Bash fallback: `invocation_method.ship = manual-bash`.
    - Parse response to extract PR URL. On failure: state `steps.ship = failed`, `status = failed`; log, Phase 3.
    - **Artifact verification**: `.backlog/done/{ticket-dir}/` must exist. Missing → `[PIPELINE] ship: ARTIFACT-MISSING — .backlog/done/{ticket-dir}/ not found after ship`, state `steps.ship = failed`, `status = failed`, Phase 3.
    - **Artifact Presence Gate**: After successful `/ship`, verify 7 patterns in the ticket dir (check `.backlog/done/{ticket-dir}/` first, then `.backlog/active/{ticket-dir}/`): `ticket.md`, `investigation.md`, `plan.md`, `eval-round-*.md`, `audit-round-*.md`, `quality-round-*.md`, `security-scan-*.md`. Missing → record `[PIPELINE] {step}: ARTIFACT-MISSING: {patterns}` and mark failed. **Exception**: Last `eval-round-*.md` status FAIL or FAIL-CRITICAL (AC評価の全ラウンドでFAIL) → skip checking `audit-round-*.md` / `quality-round-*.md` / `security-scan-*.md`.
    - **State update (after)**: `steps.ship = completed`, `status = completed`.
    - Record: `[PIPELINE] ship: success | pr={pr-url}`. Note: `/ship`'s internal decision points (ship_review_gate, ship_ci_pending) are handled by the ticket-dir policy.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

## Phase 3: Completion

14. **Generate autopilot-log.md** at the ticket dir. Location priority:
    1. `.backlog/done/{ticket-dir}/` (if `/ship` reached Step 5 before failure — ticket moves to `done/` at Step 5).
    2. `.backlog/active/{ticket-dir}/` (if `/ship` not invoked or did not reach Step 5).
    3. Fallback `.backlog/briefs/active/{slug}/autopilot-log.md` (if `{ticket-dir}` never determined).

```yaml
---
brief_slug: {slug}
ticket_dir: {ticket-dir}
started: {start-timestamp}
completed: {end-timestamp}
final_status: completed | completed-with-warnings | stopped | failed
---
```

Sections:
- `## Pipeline Execution` per-step status.
- `## Warnings` (only on `completed-with-warnings`): list each manual-bash fallback step + method.
- `## Human Overrides`: step-5 `human_override` rows `| {gate} | {expected_action} | {actual_action} | human_override |`. Exclude `kb_override`. None → "No human overrides detected."
- `## KB Overrides`: step-5 `kb_override` rows. None → "No KB overrides detected."
- `## Decisions Made` table: parse `[AUTOPILOT-POLICY]` lines; "No policy decisions were triggered" if none. Include step-5 overrides (distinguish type).
- `## Stop Reason` (only on stopped/failed).

**`completed-with-warnings`**: all tickets completed AND some `invocation_method == manual-bash`. Log fallbacks in `## Warnings`.

15. **Update brief lifecycle**:
    - `final_status = completed` → brief.md status = `completed`; `mv .backlog/briefs/active/{slug} .backlog/briefs/done/{slug}` (create `done/` if needed).
    - `stopped` / `failed` → brief.md status = `stopped`; stays in `briefs/active/`.

16. **Completion Report** (<500 tokens): final status; each step's result; PR URL; files-changed count (`git diff --stat`); impl rounds; autopilot-log.md path. On stopped/failed add: "To resume, re-run `/autopilot {slug}`. The pipeline will automatically continue from the last checkpoint. To start fresh, delete `.backlog/briefs/active/{slug}/autopilot-state.yaml` first."

17. **State file cleanup**: Delete `.backlog/briefs/active/{slug}/autopilot-state.yaml` (or the one in `briefs/done/{slug}/` if the brief was moved). `autopilot-log.md` is the permanent record.

### Split Execution Flow

**Mapping table**: If `resume_mode`, use `ticket_mapping` from state; else initialize empty. Maps `{slug}-part-{N}` → `{ticket-dir}` (logical → physical dir assigned by `/create-ticket`).

For each ticket in topological order (let `i` = 0-based index):

1. **Resume skip check** (`resume_mode = true` only):
   - `tickets[i].status == completed` → skip; print `[RESUME] Skipping ticket {logical_id}: already completed`; next ticket.
   - `skipped` → re-evaluate dependencies (may now be satisfied).
   - `failed` or `in_progress` → resume from first non-completed step.

2. **Dependency check**: All `depends_on` tickets must have `status == completed`.
   - Any dep `failed` / `skipped` → mark this ticket `skipped` reason "dependency {dep-slug} {status}". state `tickets[i].status = skipped`; record `[PIPELINE] {ticket-part}: skipped | reason=dependency_{dep-slug}_{status} | ticket-dir={ticket-dir-if-known}`; next ticket. Resolve `ticket-dir-if-known` via `ticket_mapping` (or `unknown`).
   - All deps `completed` → proceed.

3. **Execute pipeline for this ticket**:
   a. **Step: create-ticket**
      Resume: if `tickets[i].steps.create-ticket = completed`, skip to 3b using state's `ticket_dir`.
      - **State update (before)**: `tickets[i].steps.create-ticket = in_progress`, `status = in_progress`, `invocation_method.create-ticket = skill`.
      - **MUST invoke `/create-ticket` via the Skill tool** with brief + scope. Argument: `{ticket-title} brief=.backlog/briefs/active/{slug}/brief.md`. Include context: "This is part {N} of {total}. Scope: {scope from split-plan}. Overall vision and constraints from the brief apply." **NEVER bypass /create-ticket** by writing `ticket.md` or `.ticket-counter`. Fail immediately if not invokable.
      - Bash fallback → `invocation_method.create-ticket = manual-bash`.
      - Parse response for `{ticket-dir}` ("Ticket file path: .backlog/product_backlog/{ticket-dir}/ticket.md").
      - **State update (after)**: `steps.create-ticket = completed`, `ticket_dir = {ticket-dir}`, `ticket_mapping.{slug}-part-{N} = {ticket-dir}`. Register mapping.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

   b. Note: `autopilot-policy.yaml` is propagated into each ticket directory by `/create-ticket` in Phase 1 Plan AC #14 (split-brief mode passes `brief=` to each sub-ticket invocation, which drives the copy). `/autopilot` no longer performs this copy. The Policy guard in step 3c verifies presence; absence aborts `/scout`.

   c. **Step: scout**
      Resume: if `scout = completed`, skip to 3d (ticket already in `.backlog/active/{ticket-dir}/`).
      - **State update (before)**: `steps.scout = in_progress`, `invocation_method.scout = skill`.
      - **Policy guard**: `autopilot-policy.yaml` must exist in `.backlog/product_backlog/{ticket-dir}/`. Missing → log `[PIPELINE] scout: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as failed, state `steps.scout = failed`, `status = failed`, next ticket.
      - **MUST invoke `/scout {ticket-dir}` via the Skill tool**. **NEVER bypass /scout** via `/investigate` / `/plan2doc`. Fail immediately if not invokable.
      - On Bash fallback: `invocation_method.scout = manual-bash`. On success verify policy in active dir; if missing, log `[PIPELINE] scout: WARN — autopilot-policy.yaml missing in active dir after /scout` — do NOT copy from briefs (Plan 1 moved the copy responsibility to `/create-ticket`).
      - **Artifact verification**: `investigation.md` and `plan.md` must exist. Missing → `[PIPELINE] scout: ARTIFACT-MISSING — investigation.md or plan.md not found in .backlog/active/{ticket-dir}/`, state failed, next ticket.
      - On `/scout` failure: state `steps.scout = failed`, `status = failed`, next ticket.
      - **State update (after)**: `steps.scout = completed`.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

   d. **Step: impl**
      Resume: if `impl = completed`, skip to 3e.
      - **State update (before)**: `steps.impl = in_progress`, `invocation_method.impl = skill`.
      - **Policy guard**: `autopilot-policy.yaml` must exist in `.backlog/active/{ticket-dir}/`. Missing → log `[PIPELINE] impl: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as failed, state `steps.impl = failed`, `status = failed`, next ticket.
      - **MUST invoke `/impl .backlog/active/{ticket-dir}/plan.md` via the Skill tool**. **NEVER bypass /impl** by spawning `implementer` / `ac-evaluator` directly. Fail immediately if not invokable.
      - On Bash fallback: `invocation_method.impl = manual-bash`. On failure: state `steps.impl = failed`, `status = failed`, next ticket.
      - **Artifact verification** in `.backlog/active/{ticket-dir}/`: at least one `eval-round-*.md`; if PASS (AC passed + `/audit` ran) at least one `audit-round-*.md` AND `quality-round-*.md` (skip when `/impl` ended FAIL at AC stage). Missing → `[PIPELINE] impl: ARTIFACT-MISSING — {missing-file-pattern} not found in .backlog/active/{ticket-dir}/`, state failed, next ticket.
      - **State update (after)**: `steps.impl = completed`.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

   e. **Step: ship**
      Resume: if `ship = completed`, skip to 3f.
      - **State update (before)**: `steps.ship = in_progress`, `invocation_method.ship = skill`.
      - **Policy guard**: `autopilot-policy.yaml` must exist in `.backlog/active/{ticket-dir}/`. Missing → log `[PIPELINE] ship: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as failed, state `steps.ship = failed`, `status = failed`, next ticket.
      - **MUST invoke `/ship {target-branch} ticket-dir={ticket-dir}` via the Skill tool** (no `merge=true`). **NEVER bypass /ship** with direct `git commit` / `gh pr create` / `mv` — /ship is the atomic orchestrator for commit + ticket move + `/tune` + PR. Fail immediately if not invokable.
      - On Bash fallback: `invocation_method.ship = manual-bash`. On failure: state `steps.ship = failed`, `status = failed`, next ticket.
      - **Artifact verification**: `.backlog/done/{ticket-dir}/` must exist. Missing → `[PIPELINE] ship: ARTIFACT-MISSING — .backlog/done/{ticket-dir}/ not found after ship`, state failed, next ticket.
      - **Artifact Presence Gate**: Verify 7 patterns (check `done/{ticket-dir}/` first, else `active/{ticket-dir}/`): `ticket.md`, `investigation.md`, `plan.md`, `eval-round-*.md`, `audit-round-*.md`, `quality-round-*.md`, `security-scan-*.md`. Missing → `[PIPELINE] {step}: ARTIFACT-MISSING: {patterns}`, ticket failed. **Exception**: Last `eval-round-*.md` FAIL or FAIL-CRITICAL (AC評価の全ラウンドでFAIL) → skip checking the last 3 patterns.
      - **State update (after)**: `steps.ship = completed`, `status = completed`.

   f. Record PR URL and status.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read `.backlog/briefs/active/{slug}/autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

4. **Error handling per ticket**: Any step failure → ticket `failed` (state already updated), log error. Continue to next ticket (do NOT stop the pipeline). Tickets with a failed dependency are skipped (step 2). Independent tickets still run.

### Split Autopilot Log

Write both the overall and per-ticket logs:

1. **Overall log**: `.backlog/briefs/active/{slug}/autopilot-log.md` (or `briefs/done/{slug}/autopilot-log.md` if brief was moved).
2. **Per-ticket logs**: Each processed ticket (completed / failed / skipped) MUST have its own `autopilot-log.md` at its ticket dir. Location priority: `.backlog/done/{ticket-dir}/` first (if `/ship` reached Step 5), else `.backlog/active/{ticket-dir}/`.

IMPORTANT: Per-ticket logs are required — no skipping.

Overall autopilot-log.md includes additional fields:

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

Include `## Warnings` when any ticket has `invocation_method = manual-bash`: list ticket IDs and fallback steps. Omit if none.

### Split Completion Report

Print: overall status (completed / partial / failed); per-ticket table (status + PR URL); counts `{completed}/{failed}/{skipped} of {total}`. On partial / failed: "To resume, re-run `/autopilot {slug}`. The pipeline will automatically continue from the last checkpoint. To start fresh, delete `.backlog/briefs/active/{slug}/autopilot-state.yaml` first."

### Split Brief Lifecycle

- All tickets completed → brief `completed`, move to `briefs/done/`.
- Any ticket failed / skipped → brief `stopped`, stays in `briefs/active/`.
- `final_status`: all completed (no manual-bash) → `completed`; all completed but some manual-bash → `completed-with-warnings`; mixed completed + failed/skipped → `partial`; first ticket failed → `failed`.

### Split State File Cleanup

After Split Brief Lifecycle, delete `.backlog/briefs/active/{slug}/autopilot-state.yaml` (or `briefs/done/{slug}/autopilot-state.yaml` if moved). Logs are the permanent record.

## Error Handling

- **Empty arguments**: "Usage: /autopilot <slug>" and stop.
- **Brief not found**: list briefs and stop.
- **Policy not found**: instruct user to run `/brief` first.
- **Brief not confirmed**: instruct user to update status.
- **Any pipeline step failure (single flow)**: check `gates.unexpected_error.action`: `stop` (default) → log, brief = stopped, partial report, do NOT continue. Any other value → treat as `stop` (safety fallback); print `[AUTOPILOT-POLICY] gate=unexpected_error action=stop (fallback from unsupported action={original_action})`. Policy absent / field undefined → default `stop`. Always print `[AUTOPILOT-POLICY] gate=unexpected_error action={actual_action}` on invocation.
- **Any pipeline step failure (split flow)**: log for that ticket, mark failed, next ticket. Dependents skipped.
- **Artifact preservation**: On failure, artifacts (ticket, plan, eval-round, etc.) remain in the ticket dir — `.backlog/done/{ticket-dir}/` if `/ship` Step 5 completed, else `.backlog/active/{ticket-dir}/`. The `autopilot-state.yaml` in `briefs/active/{slug}/` records exact progress for `/autopilot {slug}` resume.
