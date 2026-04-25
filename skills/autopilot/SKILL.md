---
name: autopilot
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Consume a pre-built ticket list (split-plan.md under
  .backlog/product_backlog/{parent-slug}/) and drive the per-ticket
  /scout → /impl → /ship pipeline in topological order with policy-based
  autonomous decision making at each gate.
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
argument-hint: "<parent-slug>"
---

## Pre-computed Context

Brief files:
!`find .backlog/briefs/active -mindepth 2 -maxdepth 2 -name brief.md 2>/dev/null`

Split plans under product_backlog (source of truth for /autopilot):
!`find .backlog/product_backlog -mindepth 2 -maxdepth 2 -name split-plan.md 2>/dev/null`

Active tickets:
!`find .backlog/active -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -10`

Current branch:
!`git branch --show-current`

Default branch:
!`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main`

## Mandatory Skill Invocations

`/autopilot` MUST delegate to each target below via the Skill tool. Direct file ops, ad-hoc bash, or self-judgment are never acceptable substitutes. Bypasses are detected by the artifact presence gate and the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `/scout` (Skill) | Per ticket, Phase 2 step 3c (from split-plan consumption) | Missing `investigation.md` + `plan.md` triggers `[PIPELINE] scout: ARTIFACT-MISSING`; ticket marked failed |
| `/impl` (Skill) | Per ticket, Phase 2 step 3d, after scout | Missing `eval-round-*.md` (and `audit-round-*.md` / `quality-round-*.md` on PASS) triggers `[PIPELINE] impl: ARTIFACT-MISSING`; ticket marked failed |
| `/ship` (Skill) | Per ticket, Phase 2 step 3e, after impl | Ticket not moved to `.backlog/done/` triggers `[PIPELINE] ship: ARTIFACT-MISSING`; no PR created |

**Binding rules**:
- `MUST invoke /scout via the Skill tool` — never call `/investigate` or `/plan2doc` standalone; `/scout` is the sole entry point.
- `MUST invoke /impl via the Skill tool` — never spawn `implementer` / `ac-evaluator` directly.
- `MUST invoke /ship via the Skill tool` — never run `git commit` / `gh pr create` / `mv` directly.
- `NEVER bypass these skills via direct file operations` — pipeline correctness depends on each skill's internal state-management and artifact side effects.
- `Fail this ticket immediately if any mandatory invocation cannot be completed via the prescribed Skill tool` — record in `autopilot-state.yaml` and proceed to the next ticket. Do NOT fabricate artifacts.

**Ticket creation is NOT a responsibility of `/autopilot`.** As of Plan 4 of the v4.0.0 findings-mode refactor, `/create-ticket` is invoked upstream by the user and writes both the ticket directories under `.backlog/product_backlog/{parent-slug}/` AND (for N>1 runs) the `split-plan.md` that `/autopilot` consumes. `/autopilot` MUST NOT emit any line beginning with the literal string `/create-ticket` to its stdout — the skill never invokes `/create-ticket`, never writes `ticket.md`, never bumps `.backlog/.ticket-counter`. If a user reaches `/autopilot` without having run `/create-ticket` first, the skill exits with an `ERROR:` message (see Phase 1 below) and the error text is phrased so that no stdout line matches `^/create-ticket`.

# /autopilot

Target parent-slug: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS`: extract `{parent-slug}` (first arg); empty → "Usage: /autopilot <parent-slug>" and stop. Throughout this document, `{parent-slug}` is used; legacy docs called it `{slug}` (the names are interchangeable — the input is the directory basename under `.backlog/product_backlog/` for consuming a split-plan, and the brief slug under `.backlog/briefs/active/` when a brief is present).

## Phase 1: Pre-flight Checks

The pre-flight gate decides whether `/autopilot` has a runnable input. The single source of truth for the ticket list is `.backlog/product_backlog/{parent-slug}/split-plan.md` (new path, Plan 4). Legacy path `.backlog/briefs/active/{parent-slug}/split-plan.md` is explicitly NOT read (Plan 4 Negative AC).

0. **Auto-kick cleanup**: If `.backlog/briefs/active/{parent-slug}/auto-kick.yaml` exists, delete it. This signals to the Stop hook that the auto-chain has entered `/autopilot` and the pre-autopilot guard is no longer needed. Deletion is idempotent — missing file is not an error. Do NOT touch `brief.md`, `autopilot-policy.yaml`, or `autopilot-state.yaml` in this step — only `auto-kick.yaml` is removed.

1. **Split-plan discovery (single source of truth)**:
   - Let `SPLIT_PLAN = .backlog/product_backlog/{parent-slug}/split-plan.md`.
   - Legacy path `.backlog/briefs/active/{parent-slug}/split-plan.md` MUST NOT be read. Even if such a file exists on disk, `/autopilot` does not fall back to it. This is enforced by the Plan 4 Negative AC: "A `split-plan.md` located at the legacy path is not read by `/autopilot` as the authoritative ticket source — the skill's execution transcript for `/autopilot <slug>` against such a fixture emits stdout containing `ERROR:` or `not found` referencing the new path."
   - If `SPLIT_PLAN` exists → parsed in Phase 2 (Split Execution Flow).
   - If `SPLIT_PLAN` is missing:
     a. If `.backlog/briefs/active/{parent-slug}/brief.md` exists → print exactly:
        ```
        ERROR: split-plan not found at .backlog/product_backlog/{parent-slug}/split-plan.md. Run /create-ticket brief=.backlog/briefs/active/{parent-slug}/brief.md first to produce the ticket set, then re-run /autopilot {parent-slug}.
        ```
        Exit non-zero. Do NOT create or modify any file under `.backlog/active/`. (No stdout line matches `^/create-ticket` — the `/create-ticket` token sits mid-line after `Run `.)
     b. If no brief either (AC #8) → print exactly:
        ```
        ERROR: no split-plan at .backlog/product_backlog/{parent-slug}/split-plan.md and no brief at .backlog/briefs/active/{parent-slug}/brief.md. Nothing to autopilot.
        ```
        Exit non-zero. Do NOT create or modify any file under `.backlog/active/`.

2. **Brief optionality (Plan 4)**: A brief is no longer required for `/autopilot` to proceed. When `SPLIT_PLAN` exists, `/autopilot` runs even if `.backlog/briefs/active/{parent-slug}/brief.md` is absent. Policy propagation is upstream (`/create-ticket brief=<path>` copied `autopilot-policy.yaml` into each ticket dir, Plan 1). If a ticket dir has no policy, the Policy guard below aborts that ticket — explicit "not autopilot-eligible" signal.

3. If the brief does exist, read it for decision logging and status verification:
   - `status` must be `confirmed` (if `draft`, print "ERROR: Brief status is 'draft'. Update to 'confirmed' or run /brief with auto=true." and stop). If the brief is absent (split-plan-only runs), skip this step — there is no brief status to check.

4. If `.backlog/briefs/active/{parent-slug}/autopilot-policy.yaml` exists, read it for decision logging; otherwise per-ticket policy files (copied in by `/create-ticket`) serve the same role.

5. **Human override detection**: Compare each gate's action in the per-ticket or brief-level `autopilot-policy.yaml` to the expected defaults for the declared `risk_tolerance`:
   - `conservative` defaults: `ticket_quality_fail.action: retry_with_feedback`, `evaluator_dry_run_fail.action: stop`, `ac_eval_fail.action: retry`, `audit_infrastructure_fail.action: stop`, `ship_review_gate.action: stop`, `ship_ci_pending.action: wait`, `ship_ci_pending.timeout_minutes: 30`, `constraints.max_total_rounds: 9`, `constraints.allow_breaking_changes: false`, `unexpected_error.action: stop`
   - `moderate` defaults: conservative except `evaluator_dry_run_fail.action: proceed_without`, `audit_infrastructure_fail.action: treat_as_fail`, `ship_review_gate.action: proceed_if_eval_passed`
   - `aggressive` defaults: moderate except `ship_ci_pending.timeout_minutes: 60`, `constraints.max_total_rounds: 12`, `constraints.allow_breaking_changes: true`
   - Gate differs from default: check for `# kb-suggested` comment. Present → `kb_override`; absent → `human_override`. Store (gate, expected, actual, type) for the log.
   - No differences → "No human overrides detected."

6. **State recovery**: `autopilot-state.yaml` absent at `.backlog/briefs/active/{parent-slug}/autopilot-state.yaml` (or any previously-chosen location) → `resume_mode = false`. Else `resume_mode = true`, parse:
   - Print:
     ```
     [RESUME] 前回の /autopilot 実行が途中で停止しています。途中から再開します。
     [RESUME] Execution mode: {execution_mode}
     [RESUME] Progress: {completed_count}/{total_tickets} tickets completed
     ```
   - Per ticket: `[RESUME] {logical_id} → {ticket_dir}: {status} (last completed: {last_completed_step})`.
   - `started` older than 7 days: `[RESUME] WARNING: State file is from {started}. Codebase may have changed. Consider deleting autopilot-state.yaml and re-running.`
   - Carry `ticket_mapping`. Per-ticket resume: `completed` → skip (`[RESUME] Skipping {logical_id}: already completed`); `failed` / `skipped` → retry from first non-completed step; `in_progress` → re-run that step; `pending` → normal. Skip `scout` → ticket already in `.backlog/active/{parent-slug}/{ticket-dir}/`.

## Phase 2: Pipeline Execution

### Execution Mode Detection

- `SPLIT_PLAN` present (the only success path — see Phase 1 step 1) → parse the file, extract each ticket's logical id + `ticket_dir` + `depends_on`, build the dependency graph, run topological sort, use **Split Execution Flow** (below). Even if the split-plan lists exactly 1 ticket, the Split Execution Flow handles it uniformly.

There is no longer a "no split-plan.md → Single Ticket Flow" branch. `/autopilot` is a pure consumer of `split-plan.md` produced by `/create-ticket`. If you have a brief but no split-plan, the Phase 1 error message directs you to run `/create-ticket` first.

### State file initialization

Skip if `resume_mode = true` (state exists). This brief-level / parent-level `autopilot-state.yaml` is distinct from each ticket's `phase-state.yaml` (owned by `/scout`, `/impl`, `/ship`).

Write `.backlog/briefs/active/{parent-slug}/autopilot-state.yaml` (or, when no brief dir exists, `.backlog/product_backlog/{parent-slug}/autopilot-state.yaml` — `/autopilot` chooses whichever parent directory is present on disk; both locations are valid for state):

```yaml
version: 1
parent_slug: {parent-slug}
started: {ISO-8601 via `date -u +%Y-%m-%dT%H:%M:%SZ`}
execution_mode: split
total_tickets: {N}
ticket_mapping: {}
tickets:
  - logical_id: {parent-slug}-part-{N}   # one entry per split-plan ticket, in topological order
    ticket_dir: {ticket-dir from split-plan}
    status: pending
    steps: {scout: pending, impl: pending, ship: pending}
    invocation_method: {scout: unknown, impl: unknown, ship: unknown}
```

Note: the `steps:` / `invocation_method:` maps no longer contain a `create-ticket` key — ticket creation is no longer an `/autopilot` step (Plan 4). Existing state files from pre-Plan-4 runs that still carry a `create-ticket` key are tolerated on resume but not written fresh.

### Split Execution Flow

**Input**: `SPLIT_PLAN = .backlog/product_backlog/{parent-slug}/split-plan.md` (parsed in Phase 1 discovery). This is the **single source of truth** for the ticket set. Legacy path `.backlog/briefs/active/{parent-slug}/split-plan.md` is ignored.

#### Parse `split-plan.md`

Per `.docs/fix_structure/spec-split-plan-schema.md`:

1. Read frontmatter: `parent_slug`, `ticket_count`, `version`. If any is missing, print `ERROR: split-plan.md at .backlog/product_backlog/{parent-slug}/split-plan.md has invalid frontmatter` and exit non-zero.
2. Verify `parent_slug` in frontmatter equals the `{parent-slug}` argument. Mismatch → `ERROR: split-plan.md parent_slug mismatch (file=<frontmatter-value>, argument=<parent-slug>)` and exit non-zero.
3. Enumerate ticket entries under `## Tickets`: each `### N. {parent-slug}-part-N: <Title>` heading with its meta lines (`- ticket_dir: \`...\``, `- size: ...`, `- depends_on: [...]`).

#### Edge: zero ticket entries

If the `## Tickets` section contains **zero** `### N.` entries (equivalently, `ticket_count: 0` or no entries found), print exactly:

```
ERROR: split-plan.md at .backlog/product_backlog/{parent-slug}/split-plan.md is empty (zero ticket entries).
```

Exit non-zero. Do NOT create or modify any file under `.backlog/active/`. (The literal word `empty` is load-bearing — Plan 4 Edge Case asserts `stdout containing 'ERROR:' and the literal 'empty'`.)

#### Edge: cyclic `depends_on` graph

Build a directed graph over ticket logical IDs (`{parent-slug}-part-N`) using each entry's `depends_on` list. Run **Kahn's algorithm** (or DFS with colored nodes) to detect cycles.

If a cycle is detected (e.g., A depends on B AND B depends on A), print exactly:

```
ERROR: circular dependency detected in split-plan.md at .backlog/product_backlog/{parent-slug}/split-plan.md among tickets: <list cycle members>
```

Exit non-zero **before any ticket work begins**. Do NOT create or modify any file under `.backlog/active/{parent-slug}/` (Plan 4 Edge Case asserts "no `.backlog/active/{parent-slug}/` subdirectories are created during this failed invocation"). The literal word `circular` MUST appear in stdout; the word `cycle` is also acceptable (Plan 4 Edge Case allows either).

#### Topological sort with lexicographic tiebreak

Run Kahn's algorithm with a **FIFO queue ordered by lexicographic ticket_dir**:

1. Compute in-degree per node (number of `depends_on` entries).
2. Initial ready queue = all nodes with in-degree 0 (roots, i.e. `depends_on: []`), sorted in **ascending lexicographic order of `ticket_dir`** (the physical directory path string).
3. Pop the lexicographically smallest ready node, emit it to the processing order, and decrement in-degrees of its dependents. When a dependent's in-degree reaches 0, insert it into the ready queue maintaining lexicographic order.
4. Continue until all nodes emitted or queue is empty (empty + unprocessed nodes means a cycle — already caught above).

The resulting `PROCESSING_ORDER` is a list of tickets. For each ticket in `PROCESSING_ORDER` (in that exact order), emit a single stdout line:

```
Processing order: {NNN-slug}
```

where `{NNN-slug}` is the basename of `ticket_dir` (e.g. `005-add-user-auth`). All `Processing order:` lines appear at the top of Phase 2 output — one per ticket — in topological order. AC #10: when every ticket has `depends_on: []`, the `Processing order:` lines appear in ascending lexicographic order of `NNN-slug`.

#### Mapping table

If `resume_mode`, use `ticket_mapping` from state; else seed empty and add each ticket from the split-plan as `{parent-slug}-part-{N}` → `{ticket-dir}` immediately (we already know all ticket_dir paths from the split-plan; no `/create-ticket` invocation needed to resolve them).

#### Per-ticket pipeline

> **MUST NOT directive — Non-interactive orchestrator contract**: `/autopilot` is a fully non-interactive orchestrator. From the moment the per-ticket pipeline begins until every ticket in `PROCESSING_ORDER` has reached a terminal status (`completed`, `failed`, or `skipped`), the skill **MUST NOT** call `AskUserQuestion` under any circumstance. This prohibition applies **uniformly** to every boundary inside the pipeline — mid-step, between steps (after `/scout`, after `/impl`, after `/ship`), at the loop tail between tickets, and on resume from a prior `autopilot-state.yaml`. The skill **MUST NOT** ask the user to confirm continuation, choose the next ticket, approve the next step, or otherwise gate progress on an interactive prompt. The **only legitimate stop** inside the pipeline is a gate evaluation in each ticket's `autopilot-policy.yaml` whose `action` resolves to `stop` — that is the contracted stop path and it is decided by reading YAML, **not** by prompting the user. Interactive prompts (`AskUserQuestion` or equivalent) are explicitly out of contract and MUST NOT be used as a substitute for the policy-gate stop path. Stop hooks cannot intercept `AskUserQuestion`, so this SKILL-level prohibition is the sole enforcement mechanism.

For each ticket in `PROCESSING_ORDER` (let `i` = 0-based index in `PROCESSING_ORDER`):

1. **Resume skip check** (`resume_mode = true` only):
   - `tickets[i].status == completed` → skip; print `[RESUME] Skipping ticket {logical_id}: already completed`; next ticket.
   - `skipped` → re-evaluate dependencies (may now be satisfied).
   - `failed` or `in_progress` → resume from first non-completed step.

2. **Dependency check**: All `depends_on` tickets must have `status == completed`.
   - Any dep `failed` / `skipped` → mark this ticket `skipped` reason "dependency {dep-slug} {status}". state `tickets[i].status = skipped`; record `[PIPELINE] {ticket-part}: skipped | reason=dependency_{dep-slug}_{status} | ticket-dir={ticket-dir}`; next ticket. `ticket-dir` is always known (from split-plan).
   - All deps `completed` → proceed.

3. **Execute pipeline for this ticket** (no ticket-creation step — the ticket dir already exists under `.backlog/product_backlog/{parent-slug}/` when the pipeline starts, and `/scout` moves it into `.backlog/active/{parent-slug}/`):

   a. **Pre-scout: Policy guard**
      - Verify `autopilot-policy.yaml` exists at `.backlog/product_backlog/{ticket-dir}/autopilot-policy.yaml` (it was copied there by `/create-ticket` when `brief=<path>` was passed upstream; see Plan 1 AC #14).
      - If missing → log `[PIPELINE] scout: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as failed, state `steps.scout = failed`, `status = failed`, next ticket. Do NOT proceed. This is the explicit "not autopilot-eligible" signal for tickets created without a brief (findings-only or bare-description — Plan 1 AC #15).

   b. *(Former step `create-ticket` removed in Plan 4. `/autopilot` does not invoke `/create-ticket` and does not write `ticket.md` or mutate `.backlog/.ticket-counter`. The ticket dir and `ticket.md` are produced upstream by `/create-ticket` before `/autopilot` runs.)*

   c. **Step: scout**
      Resume: if `scout = completed`, skip to 3d (ticket already in `.backlog/active/{parent-slug}/{NNN}-{slug}/`).
      - Emit stdout line: `scout: {NNN-slug} start` (where `{NNN-slug}` is the ticket_dir basename).
      - **State update (before)**: `steps.scout = in_progress`, `invocation_method.scout = skill`.
      - **MUST invoke `/scout {ticket-dir}` via the Skill tool**, passing the full path `.backlog/product_backlog/{parent-slug}/{NNN}-{slug}` (the source location in product_backlog; `/scout` moves it to `.backlog/active/{parent-slug}/{NNN}-{slug}/`). **NEVER bypass /scout** via `/investigate` / `/plan2doc`. Fail immediately if not invokable.
      - On Bash fallback: `invocation_method.scout = manual-bash`. On success verify policy in active dir; if missing, log `[PIPELINE] scout: WARN — autopilot-policy.yaml missing in active dir after /scout` — do NOT copy from briefs (Plan 1 moved the copy responsibility to `/create-ticket`).
      - **Artifact verification**: `investigation.md` and `plan.md` must exist in `.backlog/active/{parent-slug}/{NNN}-{slug}/`. Missing → `[PIPELINE] scout: ARTIFACT-MISSING — investigation.md or plan.md not found in .backlog/active/{parent-slug}/{NNN}-{slug}/`, state failed, next ticket.
      - On `/scout` failure: state `steps.scout = failed`, `status = failed`, next ticket.
      - **State update (after)**: `steps.scout = completed`.
      - Emit stdout line: `scout: {NNN-slug} complete`.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read the `autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

   d. **Step: impl**
      Resume: if `impl = completed`, skip to 3e.
      - **State update (before)**: `steps.impl = in_progress`, `invocation_method.impl = skill`.
      - **Policy guard**: `autopilot-policy.yaml` must exist in `.backlog/active/{parent-slug}/{NNN}-{slug}/`. Missing → log `[PIPELINE] impl: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as failed, state `steps.impl = failed`, `status = failed`, next ticket.
      - **MUST invoke `/impl .backlog/active/{parent-slug}/{NNN}-{slug}/plan.md` via the Skill tool**. **NEVER bypass /impl** by spawning `implementer` / `ac-evaluator` directly. Fail immediately if not invokable.
      - On Bash fallback: `invocation_method.impl = manual-bash`. On failure: state `steps.impl = failed`, `status = failed`, next ticket.
      - **Artifact verification** in `.backlog/active/{parent-slug}/{NNN}-{slug}/`: at least one `eval-round-*.md`; if PASS (AC passed + `/audit` ran) at least one `audit-round-*.md` AND `quality-round-*.md` (skip when `/impl` ended FAIL at AC stage, i.e. AC評価の全ラウンドでFAIL). Missing → `[PIPELINE] impl: ARTIFACT-MISSING — {missing-file-pattern} not found in .backlog/active/{parent-slug}/{NNN}-{slug}/`, state failed, next ticket.
      - **State update (after)**: `steps.impl = completed`.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read the `autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

   e. **Step: ship**
      Resume: if `ship = completed`, skip to 3f.
      - **State update (before)**: `steps.ship = in_progress`, `invocation_method.ship = skill`.
      - **Policy guard**: `autopilot-policy.yaml` must exist in `.backlog/active/{parent-slug}/{NNN}-{slug}/`. Missing → log `[PIPELINE] ship: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket as failed, state `steps.ship = failed`, `status = failed`, next ticket.
      - Determine target branch from Pre-computed Context.
      - **MUST invoke `/ship {target-branch} ticket-dir={ticket-dir}` via the Skill tool** (no `merge=true`). **NEVER bypass /ship** with direct `git commit` / `gh pr create` / `mv` — /ship is the atomic orchestrator for commit + ticket move + `/tune` + PR. Fail immediately if not invokable.
      - On Bash fallback: `invocation_method.ship = manual-bash`. On failure: state `steps.ship = failed`, `status = failed`, next ticket.
      - **Artifact verification**: `.backlog/done/{parent-slug}/{NNN}-{slug}/` must exist (nested layout) — or `.backlog/done/{NNN}-{slug}/` for any legacy flat-layout tickets. Missing → `[PIPELINE] ship: ARTIFACT-MISSING — done ticket-dir not found after ship`, state failed, next ticket.
      - **Artifact Presence Gate**: Verify 7 patterns (check `done/{...}/` first, else `active/{...}/`): `ticket.md`, `investigation.md`, `plan.md`, `eval-round-*.md`, `audit-round-*.md`, `quality-round-*.md`, `security-scan-*.md`. Missing → `[PIPELINE] {step}: ARTIFACT-MISSING: {patterns}`, ticket failed. **Exception**: Last `eval-round-*.md` FAIL or FAIL-CRITICAL (AC評価の全ラウンドでFAIL) → skip checking the last 3 patterns.
      - **State update (after)**: `steps.ship = completed`, `status = completed`.

   f. Record PR URL and status.

      > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read the `autopilot-state.yaml`; execute the next pending step. Do NOT end your turn or summarize.

   g. **Loop-tail CHECKPOINT — iterate or exit**:

      > **CHECKPOINT — LOOP TAIL (this ticket complete → iterate to next ticket in PROCESSING_ORDER)**: This ticket is complete (every step of this ticket's pipeline has reached a terminal status — `completed`, `failed`, or `skipped`). The next action is to **iterate to the next ticket in `PROCESSING_ORDER`** by re-entering the per-ticket pipeline at step 1 (Resume skip check) for index `i+1`. You **MUST NOT** call `AskUserQuestion` at this loop-tail boundary. You **MUST NOT** `end_turn` at this loop-tail boundary. You **MUST NOT** summarize progress, print a "Part N complete" status, or otherwise pause for acknowledgement at this loop-tail boundary. **Exit condition**: when every ticket in `PROCESSING_ORDER` has reached a terminal status (`completed` / `failed` / `skipped`) — i.e., there is no next index to iterate to — exit the per-ticket loop and proceed to the post-loop phase (Split Autopilot Log → Split Completion Report → Split Brief Lifecycle → Split State File Cleanup → final `## [SW-CHECKPOINT]` emission).

4. **Error handling per ticket**: Any step failure → ticket `failed` (state already updated), log error. Continue to next ticket (do NOT stop the pipeline). Tickets with a failed dependency are skipped (step 2). Independent tickets still run.

### Split Autopilot Log

Write both the overall and per-ticket logs:

1. **Overall log**: `.backlog/briefs/active/{parent-slug}/autopilot-log.md` (or `briefs/done/{parent-slug}/autopilot-log.md` if the brief was moved; if no brief dir exists, write at `.backlog/product_backlog/{parent-slug}/autopilot-log.md`).
2. **Per-ticket logs**: Each processed ticket (completed / failed / skipped) MUST have its own `autopilot-log.md` at its ticket dir. Location priority: `.backlog/done/{parent-slug}/{NNN}-{slug}/` first (if `/ship` reached Step 5), else `.backlog/active/{parent-slug}/{NNN}-{slug}/`.

IMPORTANT: Per-ticket logs are required — no skipping.

Overall autopilot-log.md includes additional fields:

```yaml
---
parent_slug: {parent-slug}
started: {timestamp}
completed: {timestamp}
final_status: completed | completed-with-warnings | partial | failed
ticket_count: {N}
tickets_completed: {N}
tickets_failed: {N}
tickets_skipped: {N}
ticket_mapping:
  {parent-slug}-part-1: {ticket-dir-1}
  {parent-slug}-part-2: {ticket-dir-2}
---
```

Each ticket gets its own subsection in ## Pipeline Execution:

```markdown
### Ticket: {parent-slug}-part-{N} → {ticket-dir} ({status})
- scout: {status}
- impl: {status} ({rounds} rounds)
- ship: {status} → PR: {url}
- Manual Bash Fallbacks: {rendered from manual_bash_fallbacks[] — see below}
```

**Single source of truth for Manual Bash Fallbacks**: the authoritative log is the structured `manual_bash_fallbacks[]` list recorded in this ticket's `autopilot-state.yaml` (schema defined in the Manual Bash Fallback Discipline section below). Every entry in the structured list MUST be rendered verbatim in the per-ticket subsection as `{timestamp} | {command} | {reason} (exit={exit_code}, destructive={destructive})`. When the list is empty or absent, print `none`. The per-step `invocation_method == manual-bash` flag (used elsewhere in this document) is a derived indicator — it MUST be set if and only if a matching `manual_bash_fallbacks[]` entry exists for that step, never independently.

Include `## Warnings` when any ticket's `manual_bash_fallbacks[]` is non-empty (equivalently: any step with `invocation_method == manual-bash`, which is derived from the list): list ticket IDs and replay each fallback entry with its `reason` and `destructive` flag. Omit if every ticket's `manual_bash_fallbacks[]` is empty.

### Split Completion Report

Print: overall status (completed / partial / failed); per-ticket table (status + PR URL); counts `{completed}/{failed}/{skipped} of {total}`. On partial / failed: "To resume, re-run `/autopilot {parent-slug}`. The pipeline will automatically continue from the last checkpoint. To start fresh, remove the `autopilot-state.yaml` (or rename it aside) before re-running."

### Split Brief Lifecycle

- All tickets completed AND brief exists → brief `completed`, move to `briefs/done/`.
- Any ticket failed / skipped AND brief exists → brief `stopped`, stays in `briefs/active/`.
- No brief (split-plan-only run) → skip brief lifecycle; the `split-plan.md` and per-ticket `autopilot-log.md` artefacts are the permanent record.
- `final_status`: all completed AND every ticket's `manual_bash_fallbacks[]` empty → `completed`; all completed but at least one ticket has a non-empty `manual_bash_fallbacks[]` → `completed-with-warnings`; mixed completed + failed/skipped → `partial`; first ticket failed → `failed`.

### Split State File Cleanup

After Split Brief Lifecycle, **move** the `autopilot-state.yaml` from its active location (`.backlog/briefs/active/{parent-slug}/` or `.backlog/product_backlog/{parent-slug}/`) to `.backlog/briefs/done/{parent-slug}/autopilot-state.yaml` (creating the dir if missing). NEVER delete — post-mortem and Manual Bash Fallback history must be preserved. Logs and state together form the permanent record of the run. (This is the "State file cleanup" step — absence of this text is a contract violation.)

### Autopilot Log Sections (common to overall + per-ticket)

Every `autopilot-log.md` (overall or per-ticket) includes the following sections derived from Phase 1 step 5 (Human override detection) and runtime `[AUTOPILOT-POLICY]` lines:

- `## Pipeline Execution` — per-step status per ticket.
- `## Warnings` (only on `completed-with-warnings`): replay every ticket's `manual_bash_fallbacks[]` entries verbatim (`timestamp | command | reason | exit_code | destructive`). Each entry MUST appear; silent drops are a contract violation. The structured list is the single source of truth — do NOT derive the Warnings section from `invocation_method` flags alone.
- `## Human Overrides`: step-5 `human_override` rows `| {gate} | {expected_action} | {actual_action} | human_override |`. **Exclude `kb_override` rows** from this section — they go to `## KB Overrides` instead. None → "No human overrides detected."
- `## KB Overrides`: step-5 `kb_override` rows `| {gate} | {expected_action} | {actual_action} | kb_override |` (gates where the value differs from the risk_tolerance default AND a `# kb-suggested` comment is attached in the policy file). None → "No KB overrides detected."
- `## Decisions Made` table: parse `[AUTOPILOT-POLICY]` lines; "No policy decisions were triggered" if none. Include step-5 overrides — **distinguish `human_override` and `kb_override` type** via the final column so a reviewer can tell which differences came from the user and which came from the KB suggestion layer.
- `## Stop Reason` (only on stopped/failed).

**`completed-with-warnings`**: all tickets completed AND at least one ticket has a non-empty `manual_bash_fallbacks[]` in its state (equivalently: at least one step with `invocation_method == manual-bash`, which is derived from the structured list). Log fallbacks in `## Warnings` by replaying every `manual_bash_fallbacks[]` entry — the structured list is authoritative, the per-step flag is derived.

### Manual Bash Fallback Discipline

A Manual Bash Fallback is an orchestrator-level `Bash` call used to recover from an anomaly that a subagent could not handle. It is a last resort.

**MUST NOT treat as Manual Bash Fallback**:
- Generator / Evaluator / any subagent response truncation (timeout / token limit). These MUST trigger the configured retry gate (`ac_eval_fail`, `evaluator_dry_run_fail`, etc.) and re-spawn the subagent, NOT be covered by an orchestrator-run shadow execution.
- Cases where a subagent was the intended executor but failed. Re-spawn the subagent with the failure context in its prompt.

**MUST NOT use destructive operations as error shortcuts**:
- Prohibited without explicit justification: `rm -rf`, `rm -f .git/index`, `git reset --hard`, `git clean -f`, `git checkout .`, `git branch -D` of an active branch.
- If a tool's error output names a non-destructive flag (e.g. `use -f to force removal`, `use --allow-empty-message`), apply that flag first. Do not jump to destructive alternatives.
- Before any destructive call, write the reasoning into `autopilot-state.yaml` `manual_bash_fallbacks[]` and prefer an interactive confirmation when the autopilot is in a resumable state.

**MUST log every Manual Bash Fallback immediately**:
Append to `autopilot-state.yaml` at the active parent dir:

```yaml
manual_bash_fallbacks:
  - timestamp: "<ISO-8601 UTC>"
    command: "<command verbatim>"
    reason: "<why this fell outside the subagent contract>"
    exit_code: <int>
    destructive: <true|false>
```

On finalization (when writing `autopilot-log.md`), the `Manual Bash Fallbacks` section MUST replay this list verbatim. "No manual bash fallbacks" is valid ONLY when `manual_bash_fallbacks` is empty or absent. When the state file recorded fallbacks, the log MUST NOT emit an empty `Manual Bash Fallbacks: none` line — silent drops are a contract violation.

## Error Handling

- **Empty arguments**: "Usage: /autopilot <parent-slug>" and stop.
- **No split-plan.md AND no brief**: print `ERROR: no split-plan at .backlog/product_backlog/{parent-slug}/split-plan.md and no brief at .backlog/briefs/active/{parent-slug}/brief.md. Nothing to autopilot.` and stop. Do NOT create or modify any file under `.backlog/active/`. (AC #8)
- **No split-plan.md but brief exists**: print `ERROR: split-plan not found at .backlog/product_backlog/{parent-slug}/split-plan.md. Run /create-ticket brief=.backlog/briefs/active/{parent-slug}/brief.md first to produce the ticket set, then re-run /autopilot {parent-slug}.` and stop. (AC #1: stdout does NOT contain a line matching `^/create-ticket`.)
- **Legacy split-plan at `.backlog/briefs/active/{parent-slug}/split-plan.md`**: ignored. `/autopilot` does NOT fall back to it. The usual "No split-plan.md" error fires and mentions the new path (the literal substrings `ERROR:` and `not found` both appear in stdout — Plan 4 Negative AC).
- **split-plan.md has zero ticket entries**: print `ERROR: split-plan.md at .backlog/product_backlog/{parent-slug}/split-plan.md is empty (zero ticket entries).` and stop. (Edge case — literal `empty` is load-bearing.)
- **Cyclic `depends_on` graph**: print `ERROR: circular dependency detected in split-plan.md at .backlog/product_backlog/{parent-slug}/split-plan.md among tickets: <cycle members>` and stop BEFORE any pipeline work. Do NOT create `.backlog/active/{parent-slug}/` subdirectories. The literal word `circular` (or `cycle`) MUST appear in stdout.
- **Brief not confirmed** (brief exists but status is `draft`): instruct user to update status.
- **Any pipeline step failure (per ticket)**: check `gates.unexpected_error.action`: `stop` (default) → log, mark ticket failed, partial report. Any other value → treat as `stop` (safety fallback); print `[AUTOPILOT-POLICY] gate=unexpected_error action=stop (fallback from unsupported action={original_action})`. Policy absent / field undefined → default `stop`. Always print `[AUTOPILOT-POLICY] gate=unexpected_error action={actual_action}` on invocation.
- **Any pipeline step failure (per ticket, continued)**: log for that ticket, mark failed, next ticket. Dependents skipped.
- **Artifact preservation**: On failure, artifacts (ticket, plan, eval-round, etc.) remain in the ticket dir — `.backlog/done/{parent-slug}/{NNN}-{slug}/` if `/ship` Step 5 completed, else `.backlog/active/{parent-slug}/{NNN}-{slug}/`. The `autopilot-state.yaml` records exact progress for `/autopilot {parent-slug}` resume.
