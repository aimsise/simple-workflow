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

GitHub auth:
!`gh auth status 2>&1 | head -3`

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
4. Verify GitHub auth from Pre-computed Context. If not authenticated, print "ERROR: gh auth required. Run 'gh auth login'." and stop.
5. Read autopilot-policy.yaml for use in decision logging.
6. **Human override detection**: Compare each gate's action in the policy against the expected defaults for the declared `risk_tolerance` level:
   - `conservative` defaults: `ticket_quality_fail.action: retry_with_feedback`, `evaluator_dry_run_fail.action: stop`, `ac_eval_fail.action: retry`, `audit_infrastructure_fail.action: stop`, `ship_review_gate.action: stop`, `ship_ci_pending.action: wait`, `ship_ci_pending.timeout_minutes: 30`, `constraints.max_total_rounds: 9`, `constraints.allow_breaking_changes: false`, `unexpected_error.action: stop`
   - `moderate` defaults: same as conservative except `evaluator_dry_run_fail.action: proceed_without`, `audit_infrastructure_fail.action: treat_as_fail`, `ship_review_gate.action: proceed_if_eval_passed`
   - `aggressive` defaults: same as moderate except `ship_ci_pending.timeout_minutes: 60`, `constraints.max_total_rounds: 12`, `constraints.allow_breaking_changes: true`
   - If any gate action differs from the expected default for the declared `risk_tolerance`:
     - Check whether the corresponding line in the policy YAML has a `# kb-suggested` comment.
     - If `# kb-suggested` is present → record it as a **kb_override** (not a human override).
     - If `# kb-suggested` is absent → record it as a **human_override**.
     - Store each override as (gate name, expected action, actual action, type: `human_override` | `kb_override`) for inclusion in the autopilot-log.
   - If no differences are found, record "No human overrides detected."
7. Check if `.backlog/briefs/active/{slug}/split-plan.md` exists. If it does, read it and parse the ticket list and dependency graph. If it does not exist, proceed with single-ticket flow.

## Phase 2: Pipeline Execution

### Execution Mode Detection

If split-plan.md was detected in Phase 1:
- Parse the `ticket_count` and each ticket's `depends_on` list
- Build a dependency graph and compute a topological sort for execution order
- Execute using the **Split Execution Flow** below

If no split-plan.md:
- Execute using the existing **Single Ticket Flow** (steps 8-12 below)

### Single Ticket Flow

8. Update brief.md frontmatter status from `confirmed` to `in-progress`.

9. **Step: create-ticket**
   Invoke `/create-ticket` via the Skill tool with argument: `{brief-title} brief=.backlog/briefs/active/{slug}/brief.md`
   where {brief-title} is extracted from the brief's ## Vision section (first sentence).
   - Parse the response to extract the created ticket slug and path (from the summary output: "Ticket file path: .backlog/product_backlog/{ticket-dir}/ticket.md").
   - If `/create-ticket` fails, log the error to autopilot-log and go to Phase 3 (failure).
   - On success: copy `autopilot-policy.yaml` from `.backlog/briefs/active/{slug}/` to `.backlog/product_backlog/{ticket-dir}/autopilot-policy.yaml` (so that when `/scout` moves the ticket directory from product_backlog to active, the policy file moves with it).
   - Record: `[PIPELINE] create-ticket: success | ticket={ticket-dir}`

10. **Step: scout**
   - **Policy guard**: Verify that `autopilot-policy.yaml` exists in `.backlog/product_backlog/{ticket-dir}/` (copied in step 9). If not found, log `[PIPELINE] scout: ABORT — autopilot-policy.yaml missing in ticket dir` and go to Phase 3 (failure). Do NOT proceed without the policy file.
   - Invoke `/scout` via the Skill tool with argument: `{ticket-dir}`
   - Parse the response for success/failure status.
   - If `/scout` fails, log the error and go to Phase 3 (failure).
   - On success: Verify that `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/` (scout moved the ticket directory including the policy). If missing, copy it from `.backlog/briefs/active/{slug}/autopilot-policy.yaml` as a safety net.
   - Record: `[PIPELINE] scout: success`

11. **Step: impl**
    - **Policy guard**: Verify that `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If not found, log `[PIPELINE] impl: ABORT — autopilot-policy.yaml missing in ticket dir` and go to Phase 3 (failure). Do NOT proceed without the policy file.
    - Invoke `/impl` via the Skill tool with argument: `.backlog/active/{ticket-dir}/plan.md`
    - Parse the response for the final status (PASS/FAIL/STOP).
    - If FAIL-CRITICAL or stopped, log the error and go to Phase 3 (failure).
    - Record: `[PIPELINE] impl: {status} | rounds={n}`
    - Note: Decision points within `/impl` (evaluator_dry_run_fail, audit_infrastructure_fail) are handled by the autopilot-policy.yaml already copied to the ticket dir.

12. **Step: ship**
    - **Policy guard**: Verify that `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If not found, log `[PIPELINE] ship: ABORT — autopilot-policy.yaml missing in ticket dir` and go to Phase 3 (failure). Do NOT proceed without the policy file.
    - Determine the target branch from Pre-computed Context (Default branch).
    - Invoke `/ship` via the Skill tool with argument: `{target-branch}` (do NOT pass merge=true).
    - Parse the response to extract the PR URL.
    - If `/ship` fails, log the error and go to Phase 3 (failure).
    - Record: `[PIPELINE] ship: success | pr={pr-url}`
    - Note: Decision points within `/ship` (ship_review_gate, ship_ci_pending) are handled by the autopilot-policy.yaml in the ticket dir.

## Phase 3: Completion

13. **Generate autopilot-log.md**: Write to the ticket directory's `autopilot-log.md`. Determine the actual ticket location by checking the filesystem in this order:
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
final_status: completed | stopped | failed
---
```

Followed by:
- ## Pipeline Execution section with each step's status
- ## Human Overrides section: List only `human_override` type entries from step 6 as `| {gate} | {expected_action} | {actual_action} | human_override |`. Exclude `kb_override` entries from this section. If no human overrides, write "No human overrides detected."
- ## KB Overrides section: List only `kb_override` type entries from step 6 as `| {gate} | {expected_action} | {actual_action} | kb_override |`. If no KB overrides, write "No KB overrides detected."
- ## Decisions Made table (parse [AUTOPILOT-POLICY] prefixed output from skill invocations if available, or note "No policy decisions were triggered" if pipeline ran without hitting any gates). Include overrides from step 6 as entries, distinguishing type `human_override` from `kb_override` in the type column.
- ## Stop Reason section (only if stopped/failed)

14. **Update brief lifecycle**:
    - If all steps succeeded (final_status = completed):
      - Update brief.md status to `completed`
      - Move: `mv .backlog/briefs/active/{slug} .backlog/briefs/done/{slug}` (create .backlog/briefs/done/ if needed)
    - If any step failed (final_status = stopped or failed):
      - Update brief.md status to `stopped`
      - Brief stays in .backlog/briefs/active/

15. **Print Completion Report** (under 500 tokens):
    - Final status
    - Each pipeline step result
    - PR URL (if created)
    - Files changed count (from `git diff --stat`)
    - Impl rounds count
    - autopilot-log.md path
    - If stopped: "To resume manually, check the autopilot-log and run the failed step individually."

### Split Execution Flow

**Mapping table initialization**: Before iterating, initialize an empty mapping table `ticket_mapping` that will store `{slug}-part-{N}` → `{ticket-dir}` entries. This table maps logical ticket identifiers (from split-plan.md) to physical directory names (assigned by `/create-ticket`).

For each ticket in topological order:

1. **Dependency check**: Verify all tickets in `depends_on` have status `completed` (PR created successfully).
   - If any dependency has status `failed` or `skipped` → mark this ticket as `skipped` with reason "dependency {dep-slug} {status}". Record `[PIPELINE] {ticket-part}: skipped | reason=dependency_{dep-slug}_{status} | ticket-dir={ticket-dir-if-known}` and continue to the next ticket. Use the `ticket_mapping` table to resolve `{ticket-dir-if-known}` for the dependency (or `unknown` if not yet mapped).
   - If all dependencies are `completed` → proceed.

2. **Execute pipeline for this ticket**:
   a. Invoke `/create-ticket` with the brief content + the relevant scope section from split-plan.md. Use argument: `{ticket-title} brief=.backlog/briefs/active/{slug}/brief.md`
      - Include in the brief argument context: "This is part {N} of {total}. Scope for this ticket: {scope from split-plan}. Overall vision and constraints from the brief apply."
      - Parse the `/create-ticket` response to extract `{ticket-dir}` (from the summary output: "Ticket file path: .backlog/product_backlog/{ticket-dir}/ticket.md").
      - **Register mapping**: Add entry `{slug}-part-{N}` → `{ticket-dir}` to `ticket_mapping`.
   b. Copy `autopilot-policy.yaml` from `.backlog/briefs/active/{slug}/` to `.backlog/product_backlog/{ticket-dir}/autopilot-policy.yaml` (so `/scout` moves it to active with the ticket).
   c. **Policy guard**: Verify `autopilot-policy.yaml` exists in `.backlog/product_backlog/{ticket-dir}/`. If not found, log `[PIPELINE] scout: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as `failed`, and continue to the next ticket.
      Invoke `/scout {ticket-dir}`. On success, verify `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If missing, copy from `.backlog/briefs/active/{slug}/autopilot-policy.yaml` as a safety net.
   d. **Policy guard**: Verify `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If not found, log `[PIPELINE] impl: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as `failed`, and continue to the next ticket.
      Invoke `/impl .backlog/active/{ticket-dir}/plan.md`
   e. **Policy guard**: Verify `autopilot-policy.yaml` exists in `.backlog/active/{ticket-dir}/`. If not found, log `[PIPELINE] ship: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as `failed`, and continue to the next ticket.
      Invoke `/ship {target-branch}` (no merge)
   f. Record PR URL and status.

3. **Error handling per ticket**:
   - If any step fails → mark this ticket as `failed`, log the error.
   - Continue to the next ticket (do NOT stop the entire pipeline).
   - Tickets that depend on a failed ticket will be skipped (step 1 above).
   - Tickets with no dependency on the failed ticket will still execute.

### Split Autopilot Log

For split execution, write the overall autopilot-log to `.backlog/briefs/active/{slug}/autopilot-log.md`. Additionally, each ticket's individual log is written to its ticket directory (`autopilot-log.md`). Determine each ticket's actual location by checking the filesystem in this order:
1. Check `.backlog/done/{ticket-dir}/` first — the ticket is here if `/ship` completed or partially completed (ticket moves to `done/` at `/ship` Step 5, before PR creation).
2. Check `.backlog/active/{ticket-dir}/` — the ticket is here if `/ship` was never invoked or did not reach Step 5.
Write each ticket's individual `autopilot-log.md` to whichever path is found.

The overall autopilot-log.md includes additional fields:

```yaml
---
brief_slug: {slug}
started: {timestamp}
completed: {timestamp}
final_status: completed | partial | failed
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
```

### Split Completion Report

Print:
- Overall status (completed / partial / failed)
- Per-ticket results table with status + PR URL
- Counts: {completed}/{failed}/{skipped} of {total}
- If partial/failed: "Failed tickets can be re-run manually. Check autopilot-log.md for details."

### Split Brief Lifecycle

- All tickets completed → brief status = `completed`, move to briefs/done/
- Any ticket failed or skipped → brief status = `stopped`, stay in briefs/active/
- final_status determination:
  - All completed → `completed`
  - Some completed + some failed/skipped → `partial`
  - First ticket failed → `failed`

## Error Handling

- **Empty arguments**: Print "Usage: /autopilot <slug>" and stop.
- **Brief not found**: List available briefs and stop.
- **Policy not found**: Print instructions to run `/brief` first.
- **Brief not confirmed**: Print instructions to update status.
- **gh auth failure**: Print login instructions.
- **Any pipeline step failure (single ticket flow)**: Check `autopilot-policy.yaml` `gates.unexpected_error.action`:
  - If `stop` (default): Log to autopilot-log.md, update brief status to stopped, print partial completion report. Do NOT attempt to continue to the next step.
  - If `action` is any value other than `stop` (e.g., user edited to an unsupported action): treat as `stop` (safety fallback). Print `[AUTOPILOT-POLICY] gate=unexpected_error action=stop (fallback from unsupported action={original_action})`.
  - If the policy does not exist or `unexpected_error` is not defined, default to `stop`.
  Print `[AUTOPILOT-POLICY] gate=unexpected_error action={actual_action}` when this gate is invoked (where `{actual_action}` is the resolved action: `stop` in all cases, including fallback).
- **Any pipeline step failure (split flow)**: Log to autopilot-log.md for that ticket, mark as failed, continue to next ticket. Dependent tickets are skipped.
- **Artifact preservation**: On failure, all artifacts created so far (ticket, plan, eval-round, etc.) are preserved in the ticket directory. This may be `.backlog/done/{ticket-dir}/` (if `/ship` Step 5 completed before the failure) or `.backlog/active/{ticket-dir}/` (if `/ship` was never invoked or did not reach Step 5). Check both locations to find the artifacts. The user can resume manually.
