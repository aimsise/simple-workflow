---
name: impl
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Use after /scout or /plan2doc to execute the implementation plan.
  Implements the latest plan with independent AC verification and
  code quality review.
disable-model-invocation: false
allowed-tools:
  # Claude Code
  - Agent
  - AskUserQuestion
  - Skill
  - Read
  - Write
  - Edit
  - Glob
  - "Bash(git diff:*)"
  - "Bash(git status:*)"
  - "Bash(git log:*)"
  - "Bash(git branch:*)"
  - "Bash(git stash:*)"
  - "Bash(date:*)"
  - "Bash(rm:*)"
  # Copilot CLI
  - task
  - ask_user
  - skill
  - view
  - create
  - edit
  - glob
  - "shell(git diff:*)"
  - "shell(git status:*)"
  - "shell(git log:*)"
  - "shell(git branch:*)"
  - "shell(git stash:*)"
  - "shell(date:*)"
  - "shell(rm:*)"
argument-hint: "[plan file path or additional instructions]"
---

Implement the latest plan using Generator → AC Evaluator → Code Quality Reviewer architecture.
User arguments: $ARGUMENTS

## Mandatory Skill Invocations

The following agent/skill invocations are **contractual** — `/impl` MUST delegate to each of these via the prescribed tool. `/impl` itself writes no code and renders no AC verdict; its role is to orchestrate the Generator → AC Evaluator → /audit loop with strict information firewalls between stages. Any bypass collapses the firewall and produces a self-assessed PASS that the pipeline cannot trust. Bypasses are detected by the artifact presence gate and the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `implementer` agent (Agent tool, "Generator") | Phase 2 step 13 — once per round | No actual code changes produced by a dedicated Generator; `/impl` is tempted to self-write edits (breaks firewall). Detected by absence of implementer trace in skill invocation audit |
| `ac-evaluator` agent (Agent tool, "Evaluator", Dry Run) | Phase 1 step 8 — round 1 only, L/XL size only | No verification plan for the Generator; the Evaluator's later PASS/FAIL lacks a pre-committed rubric. Detected by absence of evaluator trace for L/XL tickets in round 1 |
| `ac-evaluator` agent (Agent tool, "Evaluator", main gate) | Phase 2 step 15 — once per round, always | No independent AC verdict; `/impl` would self-assess PASS based on Generator's return value (exactly the Ticket 002 failure mode). Missing `eval-round-{n}.md` — `/autopilot` artifact verification triggers `[PIPELINE] impl: ARTIFACT-MISSING`, ticket marked failed |
| `/audit` (Skill tool) | Phase 2 step 17 — once per round when AC gate returns PASS / PASS-WITH-CAVEATS | No code-reviewer + security-scanner review; `/impl` would return PASS without quality/security verification. Missing `audit-round-{n}.md` / `quality-round-{n}.md` / `security-scan-{n}.md` — `/autopilot` artifact verification triggers `[PIPELINE] impl: ARTIFACT-MISSING`, ticket marked failed |

**Binding rules**:
- `MUST invoke implementer via the Agent tool` — never substitute by having `/impl` write code directly via `Edit`/`Write`. The firewall between orchestrator and Generator is load-bearing for AC independence.
- `MUST invoke ac-evaluator via the Agent tool` — never self-assess AC compliance based on build/test results alone. The Evaluator must read the code independently via `git diff`.
- `MUST invoke /audit via the Skill tool` — never substitute by spawning `code-reviewer` / `security-scanner` agents directly from `/impl`. `/audit` aggregates both and enforces the "single agent failure = FAIL" invariant.
- `NEVER bypass any of these via direct file operations` — writing `eval-round-{n}.md`, `quality-round-{n}.md`, or `audit-round-{n}.md` by `/impl` itself is a contract violation (the evaluating agent is the only acceptable author).
- `Fail the task immediately if any mandatory invocation cannot be completed via the prescribed Agent/Skill tool` — print the failure reason, update `phase-state.yaml` (`phases.impl.status: failed`, `overall_status: failed`), and stop; do not fabricate a PASS.
- `MUST include the eval-report save path in the FIRST ac-evaluator invocation — NEVER call ac-evaluator a second time solely to persist the report` — re-invocation for persistence is a contract violation (detected by consecutive ac-evaluator calls with identical AC scope in the skill invocation audit).

## phase-state.yaml write ownership

This skill writes ONLY to `phases.impl` plus the top-level status fields
(`current_phase`, `last_completed_phase`, `overall_status`). It MUST NOT
modify any other phase's section (`phases.create_ticket`, `phases.scout`,
`phases.ship`). The legacy `impl-state.yaml` is retired; all intra-impl
loop state now lives under `phases.impl.*`.

`/impl` is also responsible for two one-shot migrations at start time:
- If a legacy `impl-state.yaml` exists and no `phase-state.yaml` exists,
  migrate it (see "Legacy migration" below).
- If neither file exists but a `plan.md` is given, bootstrap a fresh
  `phase-state.yaml` with prior phases backfilled as completed (see
  "Bootstrap" below).

Neither migration nor any other step in this skill ever deletes
`phase-state.yaml`. On final completion, `/impl` sets
`phases.impl.status: completed` and keeps the file in place so `/ship` and
downstream tools can read it.

Reference: `skills/create-ticket/references/phase-state-schema.md`.

## Pre-computed Context

Oldest non-autopilot plan in .backlog/active/ (FIFO, lowest ticket number):
!`for d in $(ls -d .backlog/active/*/ 2>/dev/null | sort); do [ ! -f "${d}autopilot-policy.yaml" ] && [ -f "${d}plan.md" ] && echo "${d}plan.md" && break; done || true`

Latest plan in .docs/plans/:
!`ls -t .docs/plans/*.md 2>/dev/null | head -1`

Oldest non-autopilot research in .backlog/active/:
!`for d in $(ls -d .backlog/active/*/ 2>/dev/null | sort); do [ ! -f "${d}autopilot-policy.yaml" ] && [ -f "${d}investigation.md" ] && echo "${d}investigation.md" && break; done || true`

Latest research in .docs/research/:
!`ls -t .docs/research/*.md 2>/dev/null | head -1`

Current state:
!`git status --short`

## Phase 1: Plan Loading & Size Detection

1. Parse `$ARGUMENTS`:
   - If it starts with `.backlog/active/` or `.docs/plans/` -> use it as the plan file path. Remaining text is additional instructions.
   - Otherwise -> entire argument is additional instructions. Auto-select from `.backlog/active/`:
     1. List all directories in `.backlog/active/` that contain `plan.md`
     2. **Exclude** directories that contain `autopilot-policy.yaml` (these are managed by `/autopilot` and must not be processed by manual `/impl`)
     3. Sort by directory name ascending to select the lowest ticket number first (FIFO order)
     4. Select the first match
     5. If no match in `.backlog/active/`, fall back to the latest plan in `.docs/plans/*.md`
   - If no plan file exists in either location, print "No plan found in .backlog/active/ or .docs/plans/. Run /scout or /plan2doc first." and stop.
   - If `.backlog/active/` contains only autopilot-managed tickets (all have `autopilot-policy.yaml`), print "All active tickets are managed by /autopilot. To implement manually, specify the plan path explicitly: /impl .backlog/active/{ticket-dir}/plan.md" and fall back to `.docs/plans/*.md`.

2. Confirm the plan file exists (via Glob or a minimal `Read(limit=5)`). Do NOT read the plan content in full — the implementer agent receives the path and reads it itself in Phase 2.

3. Size detection:
   - If plan is in `.backlog/active/{ticket-dir}/plan.md` -> `Read(.backlog/active/{ticket-dir}/ticket.md, limit=30)` and extract Size from `| Size |` row. If the `| Size |` row is not found in the first 30 lines, fall back to `Read(.backlog/active/{ticket-dir}/ticket.md, limit=80)` once. If still not found, default to `M`.
   - If plan is in `.docs/plans/` -> default to M.

4. **Worktree recommendation** (L/XL size only):
   If detected size is L or XL, print:
   "Tip: This is a Size {size} ticket. For safer isolation, consider using a git worktree:
   `git worktree add -b impl/{slug} ../impl-{slug} && cd ../impl-{slug}`
   Then re-run `/impl` in the new worktree."
   Where `{slug}` is the slug portion of the ticket directory name (strip the leading `NNN-` prefix, e.g., `001-add-search-feature` -> `add-search-feature`).
   This is a non-blocking suggestion — proceed regardless.

5. **Locate and extract the Acceptance Criteria section** — bounded read only, do NOT read the plan in full:
   a. Use `Grep -n "^### Acceptance Criteria" <plan-path>` (or the equivalent heading `^## Acceptance Criteria` / `^#### Acceptance Criteria` as a fallback) to locate the header line number.
   b. If a match is found at line `L`, **read from line `L` onward with a 200-line hard cap**: `Read(<plan-path>, offset=L, limit=200)`. The 200-line cap is an upper bound — the AC section is almost always far shorter.
   c. **Terminate at the next header or EOF**: after the Read, scan the returned content for the first line matching `^#{1,6} ` (any markdown header at any depth) **AFTER** the initial `### Acceptance Criteria` header line. Keep only the content from line `L` up to (but not including) that terminator line. If no subsequent header is found within the returned window, the terminator is end-of-content (whichever comes first — subsequent header OR end of the 200-line window OR EOF).
   d. **200-line cap warning**: If the 200-line window was fully consumed AND no subsequent header was found AND the returned window did not reach EOF of the plan file (i.e. the cap truncated a larger AC section), emit the warning `"AC section exceeds 200 lines; using the first 200 lines"` and proceed with the full 200-line window as the AC body. Plans with >200 lines of AC are pathological and should be redesigned, but the skill must not silently truncate them.
   e. Extract the AC bullet list from the bounded window. Keep the extracted text in a variable for use in the Generator prompt (§13 field b) and Evaluator prompts (§8, §15 field b).

6. If step 5 Grep returns no header line, print "ERROR: Plan has no Acceptance Criteria. Add an '### Acceptance Criteria' section to the plan before running /impl." and stop.

7. **AC Sanity Check** (round 1 only, M/L/XL size only): Include in the Generator prompt: "Before implementing, review each AC. If any AC is ambiguous or technically infeasible, flag it in your **Next Steps** field." If Generator flags ambiguous AC, report to user and stop.

8. **Evaluator Dry Run** (round 1 only, **L/XL size only**):
   **MUST invoke the `ac-evaluator` agent via the Agent tool** with a verification planning prompt. **NEVER bypass the Evaluator** by having `/impl` self-draft the verification plan. Fail the task immediately if the Evaluator agent cannot be invoked.
   - Prompt: "You are preparing a verification plan. For each Acceptance Criterion below, describe HOW you will verify it (what commands to run, what to check in the code, what edge cases to test). Do NOT evaluate any implementation — no code has been written yet. Return only the verification plan."
   - Include: Plan path: `<path>`. Acceptance Criteria: <text>. Append to the prompt body: "Read the plan file at the given path before drafting the verification plan. The Acceptance Criteria text above is the fixed rubric — do not re-derive it from the plan."
   - Receive: Evaluator's verification plan
   - **If Evaluator fails or returns partial**:
     - **Autopilot policy check**: Before asking the user, check if `{ticket-dir}/autopilot-policy.yaml` exists (where ticket-dir is the directory containing the plan file, e.g. `.backlog/active/{ticket-dir}/`).
       - If it exists, read `gates.evaluator_dry_run_fail.action`:
         - If `proceed_without`: proceed without the verification plan. Print `[AUTOPILOT-POLICY] gate=evaluator_dry_run_fail action=proceed_without`.
         - If `stop`: stop the skill. Print `[AUTOPILOT-POLICY] gate=evaluator_dry_run_fail action=stop`.
       - If it does not exist, proceed with the existing interactive flow below.
     Use `AskUserQuestion` to ask the user "Evaluator が検証プランに合意できませんでした。続行しますか？" with options "yes" (proceed without verification plan) and "no" (stop the skill).
     - If user answers "no" → stop the skill immediately. Print "Stopped by user after Evaluator Dry Run failure." and exit.
     - If user answers "yes" → proceed without the verification plan. The Generator prompt will not include the dry run output for this round.
   - **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), default to "no" (stop the skill). Print "Stopped: /impl requires interactive mode to recover from Evaluator Dry Run failure. Re-run in interactive mode." and exit. Do NOT hang waiting for input.
   - **If Evaluator succeeds**: Save the verification plan for inclusion in Generator prompt (step 13g).

9. If related investigation file exists (same directory `investigation.md` or latest in `.docs/research/`), locate its path via Glob. Pass the path to the Generator prompt as field c — the implementer will read it if needed.

10. If working tree has uncommitted changes unrelated to the plan, warn user.

11. **State file resolution, legacy migration, and bootstrap**. Let `{ticket-dir}` be the directory containing the plan file (e.g. `.backlog/active/{ticket-dir}/`). Determine which state file is present and set `impl_resume_mode` accordingly.

    **§11-completed — Already-completed ticket**: If `{ticket-dir}/phase-state.yaml` exists and `phases.impl.status == completed`, print:

    ```
    Ticket already completed: phases.impl.completed_at = {timestamp}. Run /ship next, or specify a different plan path to /impl.
    ```

    and stop immediately. Do NOT re-run the Generator / Evaluator / Audit loop on a completed ticket — doing so would silently re-open a closed state file and invalidate downstream `/ship` assumptions.

    **§11-failed — Previously-failed run**: If `{ticket-dir}/phase-state.yaml` exists and `phases.impl.status == failed`, print:

    ```
    Previous /impl run marked phases.impl.status: failed. To retry: manually reset phases.impl.status to 'pending' and next_action to null in phase-state.yaml, then re-run /impl. Alternatively, specify a different plan path.
    ```

    and stop immediately. The user must explicitly acknowledge the failure by editing the state file before re-entering the loop; automatic retry would mask recurring infrastructure issues.

    **11a. Legacy migration**: Before applying the migration, **read `skills/create-ticket/references/phase-state-migration.md`** — it is the authoritative source for the field rename table, the `legacy_extras` preservation rule, the `.bak` cleanup convention, and the sunset timeline. The three branches below summarize how `/impl` dispatches over every legacy / partial-migration state combination; the rename table and preservation rule are defined in the migration doc, not repeated here.

    **§11a.0 — Both files exist (partial-migration or test state)**: If `{ticket-dir}/impl-state.yaml` AND `{ticket-dir}/phase-state.yaml` both exist:
    - Read `{ticket-dir}/phase-state.yaml`.
    - **Sub-case A (migration already complete)**: If `phases.impl.status != null` OR `phases.impl.current_round != null`, treat migration as already complete — the presence of `impl-state.yaml` is a stale leftover. Skip to §11c (Resume dispatch). Do NOT re-migrate and do NOT touch the legacy file (a later run can rename it once it is confirmed untouched for a full release).
    - **Sub-case B (empty / pending phase-state skeleton)**: Otherwise (phase-state.yaml exists but `phases.impl.status == null` AND `phases.impl.current_round == null` — e.g. a just-bootstrapped empty skeleton left by a crashed earlier migration attempt), treat as partial migration. Proceed to §11a.1 with the following modification: instead of creating a new `phase-state.yaml`, re-populate the existing file's `phases.impl.*` section from the legacy `impl-state.yaml` (other sections of the existing phase-state.yaml remain intact). The cleanup step (§11a.1 step 4) still runs.

    **§11a.1 — Clean legacy migration**: If ONLY `{ticket-dir}/impl-state.yaml` exists (no `phase-state.yaml`):
    1. Read `{ticket-dir}/impl-state.yaml`.
    2. **Before rename**: identify any top-level keys in `impl-state.yaml` that are NOT listed in the rename table (see `skills/create-ticket/references/phase-state-migration.md` §2). The known legacy fields are: `phase`, `current_round`, `max_rounds`, `last_ac_status`, `last_audit_status`, `last_audit_critical`, `next_action`, `feedback_files.*`, `plan_file`, `ticket_dir`, `size`, `started`. Any other top-level key is **unknown** and preserved per the `legacy_extras` rule (migration doc §3).
    3. Write `{ticket-dir}/phase-state.yaml` with the canonical schema (see `skills/create-ticket/references/phase-state-schema.md`). Populate fields as follows:
       - Top-level: `version: 1`; `size:` = legacy `size`; `created:` = legacy `started` (fallback to `{now}` if missing); `current_phase: impl`; `last_completed_phase: scout`; `overall_status: in-progress`. (No top-level `ticket_dir:` is written — the file path itself encodes location.)
       - `phases.create_ticket.status: completed`, `completed_at: {now}`, `artifacts.ticket: .backlog/active/{ticket-dir}/ticket.md` (if the file exists; otherwise `null`).
       - `phases.scout.status: completed`, `completed_at: {now}`, `artifacts.investigation: .backlog/active/{ticket-dir}/investigation.md` (only if the file exists; otherwise `null`), `artifacts.plan: .backlog/active/{ticket-dir}/plan.md` (only if the file exists; otherwise `null`).
       - `phases.impl.status: in-progress`, `started_at:` = legacy `started`. Copy every legacy field 1:1 under `phases.impl.*` using the rename table documented in `phase-state-migration.md` §2 (summary: legacy `phase → phase_sub`; `current_round`, `max_rounds`, `last_ac_status`, `last_audit_status`, `last_audit_critical`, `next_action`, `feedback_files.*` keep the same name under `phases.impl.*`; `plan_file` and `ticket_dir` are dropped; `started → started_at`).
       - `phases.impl.legacy_extras:` — preserve every unknown legacy top-level key (identified in step 2) as a YAML map under this field (e.g. `legacy_extras: {custom_flag: true}`). If no unknown keys exist, omit the `legacy_extras` field entirely rather than writing an empty map. (See migration doc §3.)
       - `phases.ship.status: pending` with all fields `null`.
    4. **After the write succeeds**, rename the legacy file out of the way rather than deleting it: `mv {ticket-dir}/impl-state.yaml {ticket-dir}/impl-state.yaml.migrated-{YYYYMMDD}.bak` (see migration doc §4). NEVER use `rm` here — the `.bak` file is preserved for audit / rollback. If the `phase-state.yaml` write in step 3 failed, do NOT rename the legacy file — the migration is all-or-nothing.
    5. Print `[PHASE-STATE-MIGRATION] impl-state.yaml → phase-state.yaml migrated for {ticket-dir}; legacy file preserved at impl-state.yaml.migrated-{YYYYMMDD}.bak`.
    6. Set `impl_resume_mode = true` and proceed to step 11c (Resume dispatch) with the newly-written state.

    **11b. Bootstrap (one-shot)**: If NEITHER `{ticket-dir}/impl-state.yaml` NOR `{ticket-dir}/phase-state.yaml` exists, but a `plan.md` is present in `{ticket-dir}` (or the plan path is `.docs/plans/...`):
    - If the plan path is under `.backlog/active/{ticket-dir}/`:
      1. Create `{ticket-dir}/phase-state.yaml` with the canonical schema:
         - Top-level: `version: 1`; `size:` = detected Size (S/M/L/XL from Step 3); `created: {now}`; `current_phase: impl`; `last_completed_phase: scout`; `overall_status: in-progress`. (No top-level `ticket_dir:` is written.)
         - `phases.create_ticket.status: completed`, `completed_at: {now}`, `artifacts.ticket: .backlog/active/{ticket-dir}/ticket.md` if the file exists (else `null`).
         - `phases.scout.status: completed`, `completed_at: {now}`, `artifacts.investigation: .backlog/active/{ticket-dir}/investigation.md` if the file exists (else `null`), `artifacts.plan: .backlog/active/{ticket-dir}/plan.md` if the file exists (else `null`).
         - `phases.impl.status: in-progress`, `started_at: {now}`, all other `phases.impl.*` fields at their pending defaults.
         - `phases.ship.status: pending` with all fields `null`.
      2. Print `[PHASE-STATE-BOOTSTRAP] phase-state.yaml bootstrapped for {ticket-dir} (no prior state found)`.
      3. Set `impl_resume_mode = false` and proceed to Step 12.
    - If the plan is in `.docs/plans/` (non-ticket flow), skip state-file creation entirely and proceed to Step 12 without any state tracking. The state-update steps (before/after Generator, Evaluator, Audit; Step 21 cleanup) become no-ops for non-ticket flows.

    **11c. Resume dispatch**: If `{ticket-dir}/phase-state.yaml` exists (either pre-existing or just migrated) AND `phases.impl.status` is `in-progress` AND `phases.impl.next_action` is non-null:
    - Set `impl_resume_mode = true`. Read `phases.impl.*` from the file.
    - Print resume summary:
      ```
      [IMPL-RESUME] 前回の /impl 実行が途中で停止しています。途中から再開します。
      [IMPL-RESUME] Round: {phases.impl.current_round}/{phases.impl.max_rounds}
      [IMPL-RESUME] Phase: {phases.impl.phase_sub}
      [IMPL-RESUME] Next action: {phases.impl.next_action}
      ```
    - Carry forward `phases.impl.feedback_files` from the state file.
    - Skip to the step corresponding to `phases.impl.next_action`:
      - `start-round-{N}-generator` → skip to Step 13 (Generator) with `current_round = N`. If `phases.impl.feedback_files.eval` and/or `phases.impl.feedback_files.quality` exist from a prior round, pass them to the Generator prompt (step 13e).
      - `start-evaluator` → skip to Step 15 (AC Evaluator) with the current round from the state file.
      - `start-audit` → skip to Step 17 (/audit) with the current round from the state file.
      - `proceed-to-phase-3` → skip directly to Phase 3 (Step 19).
      - `stop-critical` → print "Previous run stopped due to CRITICAL issues. Reset `phases.impl` in phase-state.yaml (status: pending, next_action: null) to re-run from scratch." and stop.

    **11d. Fresh-start (create phase-state.yaml if missing, else just begin)**: If `{ticket-dir}/phase-state.yaml` exists but `phases.impl.status` is `pending` (the typical post-`/scout` case): set `impl_resume_mode = false` and proceed to Step 12. The state file is already correct; `/impl` will update `phases.impl` at Step 13+ as described in the "phase-state.yaml phases.impl state management" section below.

    If the plan file path lies outside any active ticket directory (e.g. `.docs/plans/...`), skip all state-file resolution and proceed to Step 12 with `impl_resume_mode = false`.

12. **Safety checkpoint**: Before starting implementation, create a rollback point:
   - Run `git stash push -m "impl-checkpoint" --include-untracked -- ':!.backlog' ':!.docs' ':!.simple-wf-knowledge'` to save current working state while preserving plugin artifacts
   - If stash succeeds, print: "Safety checkpoint created. To rollback: git stash pop"
   - If nothing to stash (clean working tree), skip silently

## Phase 2: Generator → AC Evaluator → Code Quality Reviewer Loop (max 3 rounds)

**Autopilot round limit**: If `{ticket-dir}/autopilot-policy.yaml` exists and `constraints.max_total_rounds` is defined, use that value as the maximum number of rounds for this loop (replacing the default of 3). If the policy does not exist or the field is not defined, use the default of 3 rounds.

### phase-state.yaml phases.impl state management

All intra-impl loop state lives under `phases.impl.*` in the unified
`{ticket-dir}/phase-state.yaml` file. The legacy `{ticket-dir}/impl-state.yaml`
is retired; step 11a migrates it on first encounter. See
`skills/create-ticket/references/phase-state-schema.md` for the canonical
schema.

If `impl_resume_mode = false` and `phase-state.yaml` exists (the typical
post-`/scout` case, or a just-bootstrapped file from step 11b), initialize
`phases.impl` to the in-progress state **before entering the loop** via a
read-modify-write. Update ONLY the fields listed below (all other sections
and top-level fields stay untouched unless explicitly listed):

```yaml
# (under phases.impl — read-modify-write, preserve all other sections)
phases:
  impl:
    status: in-progress
    started_at: {ISO-8601 timestamp via `date -u +%Y-%m-%dT%H:%M:%SZ`}
    current_round: 1
    max_rounds: {3 or autopilot policy value}
    phase_sub: generator-pending
    last_ac_status: null
    last_audit_status: null
    last_audit_critical: 0
    next_action: start-round-1-generator
    feedback_files:
      eval: null
      quality: null
# plus top-level:
current_phase: impl
```

**`phases.impl.phase_sub`** values: `generator-pending`, `generator-complete`, `evaluator-complete`, `audit-complete`, `round-complete`, `done`

**`phases.impl.next_action`** values: `start-round-{N}-generator`, `start-evaluator`, `start-audit`, `proceed-to-phase-3`, `stop-critical`

State updates occur at these 4 points within each round. Each update is a
read-modify-write on `phase-state.yaml` that touches ONLY the listed fields
under `phases.impl.*`; never touch `phases.create_ticket`, `phases.scout`, or
`phases.ship`:
- **Before Generator (step 13)**: Update `phases.impl.phase_sub: generator-pending`, `phases.impl.next_action: start-round-{N}-generator`, `phases.impl.current_round: {N}`.
- **At start of step 14 — before `git diff --shortstat`**: Update `phases.impl.phase_sub: generator-complete`, `phases.impl.next_action: start-evaluator`.
- **After Evaluator (step 16)**: Update `phases.impl.phase_sub: evaluator-complete`, `phases.impl.last_ac_status: {PASS|FAIL|FAIL-CRITICAL}`, `phases.impl.next_action: start-audit` (if PASS) or `phases.impl.next_action: start-round-{N+1}-generator` (if FAIL and rounds remain) or `phases.impl.next_action: stop-critical` (if FAIL-CRITICAL).
- **After /audit (step 18)**: Update `phases.impl.phase_sub: audit-complete`, `phases.impl.last_audit_status: {PASS|PASS_WITH_CONCERNS|FAIL}`, `phases.impl.last_audit_critical: {count}`, `phases.impl.next_action` based on decision (e.g. `proceed-to-phase-3` if PASS, `start-round-{N+1}-generator` if FAIL), `phases.impl.feedback_files.eval: {eval-round-{N}.md path}`, `phases.impl.feedback_files.quality: {quality-round-{N}.md path}`. (Per-round artifact filenames are NOT appended to the state file — they are discoverable by Glob under the ticket directory.)

**Non-ticket flow note**: When the plan is in `.docs/plans/` (not under a ticket directory), there is no `phase-state.yaml` and all state updates in this section are no-ops. The Generator → Evaluator → Audit loop still runs normally; resume/migration do not apply.

13. **MUST invoke the Generator (`implementer`) agent via the Agent tool**. **NEVER bypass the Generator** by writing code directly via `Edit`/`Write` from within `/impl` — the Generator → Evaluator information firewall depends on the orchestrator producing no code changes itself. Fail the task immediately if the Generator agent cannot be invoked.
    - subagent_type: `implementer` (always; no -light variant)
    - model: determined by the Size → model routing rule below. Read `constraints.sonnet_size_threshold` from `{ticket-dir}/autopilot-policy.yaml` if the file is present (where `{ticket-dir}` is the directory containing the plan file, e.g. `.backlog/active/{ticket-dir}/`). Accepted values: `S`, `M`, `L`, `off`. The default — applied when the policy file is absent OR the field is absent — is `M`, which preserves the current shipped behavior (Size S and M use sonnet; L/XL/unknown use opus). Mapping:
      - threshold `S` → sonnet only when detected Size is S; otherwise opus.
      - threshold `M` (default) → sonnet when Size is S or M; otherwise opus.
      - threshold `L` → sonnet when Size is S, M, or L; otherwise opus (Size XL or unknown).
      - threshold `off` → always opus (never sonnet).
      See `skills/create-ticket/references/autopilot-policy-reference.md` for the knob reference.
    - description: "Implement plan for <feature>"
    - Prompt must include:
      a. Plan path: `<path>`. The implementer MUST read the full plan file at this path before implementing.
      b. Acceptance Criteria (highlighted: "You will be evaluated by an independent evaluator against these criteria")
      c. Investigation path (if exists): `<path>`. The implementer SHOULD read it for background context if the plan references it.
      d. User's additional instructions (if any)
      e. Round 2+: Pass the previous round's feedback file paths to the Generator:
         "Read the following feedback files from the previous evaluation round before implementing:
         - AC Evaluator feedback: {eval-round-{n-1}.md path} (or 'All AC passed' if none)
         - Code Quality feedback: {quality-round-{n-1}.md path} (or 'Not run' / 'No issues' if none)"
      f. "Refer to CLAUDE.md or project conventions for lint/test commands and coding standards."
      g. Round 1 with Dry Run: AC Evaluator's verification plan ("The AC evaluator will verify your implementation against the acceptance criteria using this plan:")
      h. Knowledge-base injection: Read `.simple-wf-knowledge/index.yaml`. If the file exists, filter entries where the role is `implementer` and `confidence >= 0.8`. Collect up to 20 lines of summaries and include them in the prompt under a heading "## Known Project Patterns". If `.simple-wf-knowledge/index.yaml` does not exist, skip this injection silently. **Note: Acceptance Criteria always take precedence over KB patterns. If a KB pattern conflicts with an AC, the AC wins.**
      i. Autopilot constraints: If `{ticket-dir}/autopilot-policy.yaml` exists, read `constraints.allow_breaking_changes`. If `false`, include in the Generator prompt: "CONSTRAINT: Do not introduce breaking changes to existing public APIs, interfaces, or exported functions. Maintain backward compatibility." If `true` or if the policy file does not exist, omit this constraint.
      j. **CONSTRAINT — Input immutability**: Include verbatim in the Generator prompt: "Do NOT modify `plan.md`, `ticket.md`, or `investigation.md` at any point. These are read-only inputs. Source code changes and new files (test files, eval reports are produced separately) are fine. If you believe the plan needs revision, flag it in your Next Steps field — the orchestrator will invoke `/plan2doc` separately." This firewall constraint prevents Generator / Evaluator contamination via input-artifact mutation.
    - Receive Generator's return value (changed files list + lint/test status)

14. **Immediately** update `{ticket-dir}/phase-state.yaml` (read-modify-write; touch only the listed fields under `phases.impl.*`):
      phases.impl.phase_sub: generator-complete
      phases.impl.next_action: start-evaluator
    Then run `git diff --shortstat` to capture a single-line change summary (e.g., `N files changed, +M -K`). Do NOT run `git diff --stat` in the main session — the ac-evaluator can invoke it independently via its `Bash(git diff:*)` permission if per-file detail is needed.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
    > 1. Read `{ticket-dir}/phase-state.yaml`
    > 2. Confirm `phases.impl.next_action: start-evaluator`.
    > 3. Proceed to Step 15 — spawn the AC Evaluator now. Do NOT end your turn.

15. **MUST invoke the AC Evaluator (`ac-evaluator`) agent via the Agent tool** (always sonnet). **NEVER self-assess AC compliance** based on the Generator's return value, build status, or test output alone — the Evaluator must read the code independently via `git diff` and render its own PASS/FAIL. This is the exact failure mode observed in JSONL Ticket 002 (L554-L559): the orchestrator self-judged PASS without invoking the Evaluator, bypassing the firewall. Fail the task immediately if the Evaluator agent cannot be invoked.
   - Prompt must include:
     a. Plan path: `<path>`. Read it in full before evaluating.
     b. Acceptance Criteria
     c. Output of `git diff --shortstat` from step 14
     d. "The following files have been changed. Run `git diff` to inspect changes, run lint/test independently, and verify each AC."
     e. Report save path — **`{eval-report-path}` MUST be resolved by the orchestrator before invoking the agent and substituted into the template below**. Resolution logic:
        - If plan is in `.backlog/active/{ticket-dir}/` -> `{eval-report-path}` = `.backlog/active/{ticket-dir}/eval-round-{n}.md`.
        - Otherwise -> Match the current branch name against active ticket directories. For each directory in `.backlog/active/`, extract the slug portion by stripping the leading `NNN-` prefix (the initial sequence of digits followed by a hyphen, e.g., `001-add-search-feature` → `add-search-feature`). Check if the branch name contains this slug portion. If a match is found, set `ticket-dir` to `.backlog/active/{full-directory-name}` (including the numeric prefix) and `{eval-report-path}` = `{ticket-dir}/eval-round-{n}.md`. If no match, `{eval-report-path}` = `.docs/eval-round/{topic}-eval-round-{n}.md` where {topic} is derived from the plan filename (e.g., `.docs/plans/add-search.md` -> `add-search`).
        Where {n} is the current round number (1, 2, or 3).
     f. Append the following clarifying line to the Evaluator prompt body (verbatim): "The Acceptance Criteria text above is the fixed rubric — do NOT re-derive it from the plan. The plan path is provided as context; if the plan's current AC text differs from the rubric above, trust the rubric (it was extracted by the orchestrator before the Generator ran)." This mirrors the §8 Dry Run wording and is required to keep Evaluator verdicts anchored to a rubric that predates any Generator edits.
   - Prompt must NOT include: Generator's return value (bias elimination); a second invocation whose sole purpose is to persist the report (the save path is always included in THIS first call — see Binding rules).
   - Receive AC Evaluator's return value (PASS/FAIL/FAIL-CRITICAL + feedback)

   **Copy-pasteable Evaluator prompt template** (orchestrator MUST substitute `{plan-path}`, `{acceptance-criteria}`, `{git-diff-shortstat}`, `{eval-report-path}`, and `{n}` before invoking the agent; `{eval-report-path}` is resolved by the orchestrator per the logic in 15.e above):

   ```
   Plan path: {plan-path}. Read it in full before evaluating.
   Acceptance Criteria:
   {acceptance-criteria}
   git diff --shortstat: {git-diff-shortstat}
   The following files have been changed. Run `git diff` to inspect changes, run lint/test independently, and verify each AC.
   Save your evaluation report to: {eval-report-path}
   The Acceptance Criteria text above is the fixed rubric — do NOT re-derive it from the plan. The plan path is provided as context; if the plan's current AC text differs from the rubric above, trust the rubric (it was extracted by the orchestrator before the Generator ran).
   ```

16. AC Gate:
    - **Status: FAIL-CRITICAL** → stop immediately. Report CRITICAL issues to the user. Do NOT continue to further rounds.
    - **Autopilot policy check for ac_eval_fail**: If `{ticket-dir}/autopilot-policy.yaml` exists, read `gates.ac_eval_fail`:
      - `on_critical: stop` is always enforced (FAIL-CRITICAL always stops regardless of policy — this is a safety invariant).
      - If `action` is `retry`: continue to next round (default behavior). Print `[AUTOPILOT-POLICY] gate=ac_eval_fail action=retry round={n}`.
      - If `action` is `stop`: stop the skill immediately. Print `[AUTOPILOT-POLICY] gate=ac_eval_fail action=stop`.
    - If autopilot-policy.yaml does not exist, proceed with the existing behavior below.
    - **Status: FAIL** → save ac-evaluator's **Feedback**, continue to next round (skip quality review for this round)
    - **Status: PASS-WITH-CAVEATS** → treat as PASS (continue to step 17), but record the Caveats field for inclusion in Phase 3 summary: "AC passed with caveats: {caveats}"
    - **Status: PASS** → continue to step 17

    Update `{ticket-dir}/phase-state.yaml` (read-modify-write; touch only the listed fields under `phases.impl.*`):
      phases.impl.phase_sub: evaluator-complete
      phases.impl.last_ac_status: {PASS|FAIL|FAIL-CRITICAL}
      phases.impl.next_action: start-audit                    ← PASS / PASS-WITH-CAVEATS の場合
                           or: start-round-{N+1}-generator   ← FAIL の場合
                           or: stop-critical                  ← FAIL-CRITICAL の場合（この後停止済み）

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING** (skip if FAIL-CRITICAL — already stopped):
    > 1. Read `{ticket-dir}/phase-state.yaml`
    > 2. Execute `phases.impl.next_action` immediately:
    >    - `start-audit` → invoke `/audit` now (Step 17). Do NOT end your turn.
    >    - `start-round-{N+1}-generator` → proceed to next round (Step 13). Do NOT end your turn.

17. **MUST invoke `/audit` via the Skill tool** (replaces direct code-reviewer spawning). **NEVER bypass /audit** by spawning `code-reviewer` / `security-scanner` agents directly from `/impl`, or by skipping review entirely after an AC PASS. Fail the task immediately if `/audit` cannot be invoked — do not proceed to Phase 3 without a valid `/audit` structured return block.
    - Call `/audit` with explicit `round={n}` matching the current Generator round counter (same `{n}` used for `eval-round-{n}.md` in Step 15). Additionally, if the plan is in `.backlog/active/{ticket-dir}/plan.md` (i.e., `ticket-dir` is known), pass `ticket-dir={ticket-dir}` (bare directory name, e.g., `003-fix-login`) to `/audit`. Do NOT pass `only_security_scan` so both code-reviewer and security-scanner run.
    - `/audit` constructs the full path `.backlog/active/{ticket-dir}` internally and writes its reports to `.backlog/active/{ticket-dir}/quality-round-{n}.md`, `.backlog/active/{ticket-dir}/security-scan-{n}.md`, and `.backlog/active/{ticket-dir}/audit-round-{n}.md`. The `ticket-dir=` argument explicitly tells `/audit` which ticket directory to write to (as a bare name; `/audit` resolves the full path). The `round={n}` parameter ensures `eval-round-{n}` and `quality-round-{n}` / `audit-round-{n}` stay aligned across retries and resumed sessions.
    - The `/audit` skill must NOT receive Generator's return value or AC Evaluator's return value (information firewall is preserved because `/audit` independently inspects `git diff` via its own pre-computed context).
    - Parse `/audit`'s structured return block:
      - `**Status**`: PASS | PASS_WITH_CONCERNS | FAIL
      - `**Critical**`: aggregated count across code-reviewer + security-scanner
      - `**Warnings**`: aggregated count
      - `**Suggestions**`: aggregated count
      - `**Reports**`: paths to the saved review files
      - `**Summary**`: one-line aggregated summary
    - **If `/audit` itself fails** (no structured block returned, or the block is malformed):
     - **Autopilot policy check**: Before asking the user, check if `{ticket-dir}/autopilot-policy.yaml` exists.
       - If it exists, read `gates.audit_infrastructure_fail.action`:
         - If `treat_as_fail`: treat the audit as **Status: FAIL** with `Critical = 1`. Print `[AUTOPILOT-POLICY] gate=audit_infrastructure_fail action=treat_as_fail`. Continue to next round with audit failure noted in feedback.
         - If `stop`: stop the skill. Print `[AUTOPILOT-POLICY] gate=audit_infrastructure_fail action=stop`.
       - If it does not exist, proceed with the existing interactive flow below.
     print the failure details (`/audit`'s raw output if available) and use `AskUserQuestion` to ask "/auditが失敗しました。どうしますか？" with options:
      - "stop": stop the skill immediately. Print "Stopped by user after /audit failure." and exit. Do NOT proceed to Phase 3.
      - "fail": treat the audit as **Status: FAIL** with `Critical = 1` (audit infrastructure failure). Combine the audit failure note with ac-evaluator's pass confirmation as feedback for the next Generator round, and follow the same flow as a normal FAIL in step 18. If this is round 3, proceed to Phase 3 with the audit failure noted in the summary.
      - **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), default to "stop" (do NOT default to "fail" — a silent FAIL retry would mask the infrastructure failure). Print "Stopped: /impl requires interactive mode to recover from /audit failure. Re-run in interactive mode." and exit. Do NOT hang waiting for input.
      - **Never** silently treat audit failure as PASS or PASS_WITH_CONCERNS — that would let Critical/security issues slip through unverified.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**:
    > 1. Read `{ticket-dir}/phase-state.yaml`
    > 2. The state file shows `phases.impl.next_action`. Execute it immediately.
    > 3. Do NOT end your turn. Do NOT summarize the audit results to the user. Proceed directly to the next action.

18. Combined Decision (based on `/audit` structured return):
    - **`/audit` Status: FAIL** (Critical > 0) → Combine ac-evaluator's pass confirmation and the audit's Critical findings (from the report files in `**Reports**`) as feedback for the next Generator round. Continue to next round.
    - **`/audit` Status: PASS_WITH_CONCERNS** (Warnings or Suggestions, no Critical) → Proceed to Phase 3. Include the audit's concerns in the summary.
    - **`/audit` Status: PASS** (all counts at 0) → Proceed to Phase 3.
    - **Round 3 and Status: FAIL** → proceed to Phase 3 with remaining issues noted (both AC and quality/security).

## Phase 3: Summary

19. Run `git status -s` and display.

20. Print summary:
    - Plan file executed
    - Files changed or created
    - Generator → AC Evaluator → Code Quality Reviewer rounds completed
    - Final status (PASS, PASS_WITH_CONCERNS with listed quality concerns, or remaining issues from AC/quality evaluation)
    - Evaluation reports: [list of saved eval-round-*.md and quality-round-*.md file paths]
    - "Review the changes above, then run `/ship` to commit and create PR"

21. **phase-state.yaml finalization (impl phase completion)**: When `/impl` reaches Phase 3 with `phases.impl.next_action` resolved to `proceed-to-phase-3` (i.e. the loop finished successfully, possibly with PASS_WITH_CONCERNS), update `{ticket-dir}/phase-state.yaml` via read-modify-write, touching ONLY the following fields:
    - `phases.impl.status: completed`
    - `phases.impl.completed_at: {now}` (ISO-8601 UTC)
    - `phases.impl.phase_sub: done`
    - `phases.impl.last_round: {final round number N}`
    - `phases.impl.next_action: null` (cleared — volatile resume state is no longer needed)
    - `last_completed_phase: impl`
    - `current_phase: ship`

    Do NOT delete `phase-state.yaml` — it is the permanent record for the ticket and is consumed by `/ship` and by `/catchup`. The `eval-round-*.md`, `quality-round-*.md`, `audit-round-*.md`, and `security-scan-*.md` files remain in the ticket directory and are discoverable by Glob. Also set `phases.impl.last_round: {final round number}` as a scalar terminal marker. `current_round`, `max_rounds`, `last_ac_status`, `last_audit_status`, `last_audit_critical`, `feedback_files.*` remain in place as a historical trace of the final round.

    **Non-ticket flow**: When the plan is in `.docs/plans/` with no ticket dir, there is no `phase-state.yaml` and this step is a no-op.

    **Failure case**: If `/impl` exits with remaining AC/quality issues after the max-rounds cap (typically 3 rounds), set `phases.impl.status: completed` (the loop terminated normally) but leave `overall_status: in-progress` — the user must decide whether to re-run or abandon; do NOT set `overall_status: failed` based on Round-N FAIL alone. Only set `phases.impl.status: failed` and `overall_status: failed` when the skill itself cannot complete (e.g. Generator or Evaluator invocation failure, or FAIL-CRITICAL early stop).

22. **Emit SW-CHECKPOINT block (Phase 3 final output only)**. Emit the `## [SW-CHECKPOINT]` block per `skills/create-ticket/references/sw-checkpoint-template.md` as the FINAL section of the `/impl` response, after the Phase 3 summary (step 20) and the state-file finalization (step 21). Emit the block **only once per `/impl` invocation**, at the very end — NOT after each Generator/Evaluator/audit round and NOT inside the Phase 2 loop. Fill: `phase=impl`, `ticket=.backlog/active/{ticket-dir}` when the plan is under a ticket directory (otherwise `none`), `artifacts=[<repo-relative paths to every eval-round-*.md, quality-round-*.md, audit-round-*.md, security-scan-*.md produced across all rounds, plus changed source files from `git diff --name-only`>]`, `next_recommended=/ship` when Phase 3 was reached with `proceed-to-phase-3` (success / PASS_WITH_CONCERNS) or `""` when the skill stopped without producing a shippable state (FAIL-CRITICAL early stop, infrastructure failure). Emit on failure paths with `artifacts: []`.

## Error Handling

- **No plan**: Print "No plan found in .backlog/active/ or .docs/plans/. Run /scout or /plan2doc first." and stop.
- **Dirty working tree**: Warn user about unrelated changes, ask whether to continue.
- **Generator failure** (Status: failed): Report error and stop.
- **AC Evaluator failure** (Status: failed or partial): Report error. Generator's changes remain in place.
- **/audit failure** (no structured block returned, or malformed): See Step 17 — ask the user via `AskUserQuestion` whether to STOP or treat the audit as FAIL. Never silently treat audit failure as PASS / PASS_WITH_CONCERNS.
- **3 rounds FAIL**: Report remaining issues. Code remains changed.

## Evaluator Tuning

Evaluator tuning is now automated via the `/tune` skill:
1. After `/ship` commits and completes a ticket, `/tune` is invoked automatically (Step 6 in `/ship`) to extract patterns from evaluation logs
2. Extracted patterns are stored in `.simple-wf-knowledge/candidates.yaml` and promoted to `entries.yaml` when confidence reaches 0.8
3. Promoted patterns are injected into the Generator prompt (Step 13h above) via `index.yaml`
4. To run tuning manually: `/tune {ticket-dir}` or `/tune all`
5. To review the current knowledge base: read `.simple-wf-knowledge/entries.yaml` and `.simple-wf-knowledge/index.yaml`
