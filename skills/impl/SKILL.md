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

`/impl` MUST delegate to each target below via the prescribed tool. `/impl` writes no code and renders no AC verdict — its role is to orchestrate the Generator → Evaluator → /audit loop with strict information firewalls. Bypasses are detected by the artifact presence gate and the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `implementer` agent (Agent tool, "Generator") | Phase 2 step 13 — once per round | No code produced by a dedicated Generator; `/impl` is tempted to self-write edits (firewall broken). Detected by missing implementer trace in skill invocation audit |
| `ac-evaluator` agent (Agent tool, Dry Run) | Phase 1 step 8 — round 1, L/XL only | No pre-committed verification rubric. Detected by missing evaluator trace for L/XL round 1 |
| `ac-evaluator` agent (Agent tool, main gate) | Phase 2 step 15 — once per round | No independent AC verdict (Ticket 002 failure mode). Missing `eval-round-{n}.md` triggers `[PIPELINE] impl: ARTIFACT-MISSING`; ticket marked failed |
| `/audit` (Skill tool) | Phase 2 step 17 — when AC gate is PASS / PASS-WITH-CAVEATS | No code-reviewer + security-scanner review. Missing `audit-round-{n}.md` / `quality-round-{n}.md` / `security-scan-{n}.md` triggers `[PIPELINE] impl: ARTIFACT-MISSING`; ticket marked failed |

**Binding rules**:
- `MUST invoke implementer via the Agent tool` — the orchestrator / Generator firewall is load-bearing for AC independence.
- `MUST invoke ac-evaluator via the Agent tool` — never self-assess AC compliance from build/test output; the Evaluator reads the code via `git diff`.
- `MUST invoke /audit via the Skill tool` — never spawn `code-reviewer` / `security-scanner` directly; `/audit` enforces the "single agent failure = FAIL" invariant.
- `NEVER bypass these via direct file operations` — writing `eval-round-{n}.md` / `quality-round-{n}.md` / `audit-round-{n}.md` from `/impl` itself is a contract violation.
- `Fail the task immediately if any mandatory invocation cannot be completed` — print the reason, set `phases.impl.status: failed` and `overall_status: failed` in `phase-state.yaml`, and stop; do not fabricate a PASS.
- `ac-evaluator is contractually idempotent on persistence (see agents/ac-evaluator.md Report Persistence Contract): it always writes the report on the first call and returns a non-empty Output path. NEVER re-invoke ac-evaluator solely to persist a report — an empty Output is an agent failure, not a retryable state.`

## phase-state.yaml write ownership

Writes ONLY `phases.impl` plus top-level `current_phase` / `last_completed_phase` / `overall_status`. Never modify `phases.create_ticket` / `phases.scout` / `phases.ship`. Legacy `impl-state.yaml` retired; intra-impl state lives under `phases.impl.*`.

Start-time one-shot migrations:
- Legacy `impl-state.yaml` + no `phase-state.yaml` → migrate (§11a).
- Neither file exists + plan.md given → bootstrap with prior phases backfilled completed (§11b).

`phase-state.yaml` is never deleted. On completion, set `phases.impl.status: completed` and leave the file for `/ship` / downstream tools.

Reference: `skills/create-ticket/references/phase-state-schema.md`.

## Pre-computed Context

Oldest non-autopilot plan:
!`for d in $(ls -d .backlog/active/*/ 2>/dev/null | sort); do [ ! -f "${d}autopilot-policy.yaml" ] && [ -f "${d}plan.md" ] && echo "${d}plan.md" && break; done || true`

Latest plan in .docs/plans/:
!`ls -t .docs/plans/*.md 2>/dev/null | head -1`

Oldest non-autopilot research:
!`for d in $(ls -d .backlog/active/*/ 2>/dev/null | sort); do [ ! -f "${d}autopilot-policy.yaml" ] && [ -f "${d}investigation.md" ] && echo "${d}investigation.md" && break; done || true`

Latest research in .docs/research/:
!`ls -t .docs/research/*.md 2>/dev/null | head -1`

Current state:
!`git status --short`

## Phase 1: Plan Loading & Size Detection

1. Parse `$ARGUMENTS`:
   - If it starts with `.backlog/active/` or `.docs/plans/` → use as plan path; remaining text is additional instructions.
   - Otherwise → entire argument is additional instructions. Auto-select from `.backlog/active/`: list dirs containing `plan.md`; **Exclude** dirs containing `autopilot-policy.yaml` (autopilot-managed); sort by directory name ascending to select the lowest ticket number first (FIFO); pick first. Fallback: latest `.docs/plans/*.md`.
   - No plan anywhere → print "No plan found in .backlog/active/ or .docs/plans/. Run /scout or /plan2doc first." and stop.
   - If `.backlog/active/` contains only autopilot-managed tickets, print "All active tickets are managed by /autopilot. To implement manually, specify the plan path explicitly: /impl .backlog/active/{ticket-dir}/plan.md" and fall back to `.docs/plans/*.md`.

2. Confirm the plan file exists (Glob or minimal `Read(limit=5)`). Do NOT read the plan in full — the implementer agent reads it in Phase 2.

3. Size detection:
   - Plan in `.backlog/active/{ticket-dir}/plan.md` → `Read(ticket.md, limit=30)` and extract Size from `| Size |`. Fallback `limit=80` once. Default `M` if still missing.
   - Plan in `.docs/plans/` → default `M`.

4. **Worktree recommendation** (L/XL only): Print "Tip: Size {size} ticket. Consider a worktree: `git worktree add -b impl/{slug} ../impl-{slug} && cd ../impl-{slug}`. Then re-run /impl." `{slug}` = ticket dir with `NNN-` prefix stripped. Non-blocking.

5. **Locate and extract the Acceptance Criteria section** — bounded read, do NOT read the plan in full:
   a. `Grep -n "^### Acceptance Criteria" <plan-path>` (fallbacks: `^## Acceptance Criteria` / `^#### Acceptance Criteria`).
   b. If found at line `L`: `Read(<plan-path>, offset=L, limit=200)` (200-line hard cap).
   c. Terminate at the first `^#{1,6} ` line AFTER the AC header, or at EOF / end of window.
   d. If the 200-line window is fully consumed without a terminator and does not reach EOF, emit `"AC section exceeds 200 lines; using the first 200 lines"` and proceed with the 200-line window.
   e. Extract the AC bullet list. Keep the text for Generator (§13 field b) and Evaluator (§8, §15 field b) prompts.

6. If step 5 Grep returns no header line, print "ERROR: Plan has no Acceptance Criteria. Add an '### Acceptance Criteria' section to the plan before running /impl." and stop.

7. **AC Sanity Check** (round 1, M/L/XL only): In Generator prompt: "Before implementing, review each AC. If any is ambiguous or infeasible, flag it in your **Next Steps** field." If Generator flags ambiguous AC, report and stop.

8. **Evaluator Dry Run** (round 1 only, **L/XL size only**):
   **MUST invoke the `ac-evaluator` agent via the Agent tool** with a verification planning prompt. **NEVER bypass the Evaluator** by self-drafting the plan. Fail the task immediately if the Evaluator cannot be invoked.
   - Prompt: "You are preparing a verification plan. For each Acceptance Criterion below, describe HOW you will verify it (commands, code checks, edge cases). Do NOT evaluate any implementation — no code exists yet. Return only the verification plan."
   - Include: Plan path: `<path>`. Acceptance Criteria: <text>. Append: "Read the plan at the given path before drafting. The AC text above is the fixed rubric — do not re-derive it from the plan."
   - **If Evaluator fails or returns partial**:
     - **Autopilot policy check**: If `{ticket-dir}/autopilot-policy.yaml` exists, read `gates.evaluator_dry_run_fail.action`: `proceed_without` → proceed without the plan (print `[AUTOPILOT-POLICY] gate=evaluator_dry_run_fail action=proceed_without`); `stop` → stop (print `[AUTOPILOT-POLICY] gate=evaluator_dry_run_fail action=stop`).
     - Else use `AskUserQuestion` "Evaluator が検証プランに合意できませんでした。続行しますか？" with yes (proceed without plan) / no (stop).
     - **Non-interactive fallback**: If `AskUserQuestion` is unavailable / errors, default to "no". Print "Stopped: /impl requires interactive mode to recover from Evaluator Dry Run failure." and exit. Do NOT hang.
   - **On success**: Save the plan for Generator prompt (step 13g).

9. If a related investigation file exists (same-dir `investigation.md` or latest `.docs/research/`), locate via Glob and pass the path to Generator field c.

10. If working tree has uncommitted changes unrelated to the plan, warn user.

11. **State file resolution, legacy migration, and bootstrap**. Let `{ticket-dir}` be the directory containing the plan file. Set `impl_resume_mode` based on which state file is present.

    **§11-completed**: If `phase-state.yaml` exists and `phases.impl.status == completed`, print `Ticket already completed: phases.impl.completed_at = {timestamp}. Run /ship next, or specify a different plan path.` and stop. Do NOT re-run the loop on a completed ticket.

    **§11-failed**: If `phase-state.yaml` exists and `phases.impl.status == failed`, print `Previous /impl run marked phases.impl.status: failed. To retry: reset phases.impl.status to 'pending' and next_action to null, then re-run.` and stop. Automatic retry would mask recurring infrastructure issues.

    **11a. Legacy migration**: Before migrating, **read `skills/create-ticket/references/phase-state-migration.md`** — authoritative for the rename table, `legacy_extras` preservation rule, `.bak` cleanup convention, and sunset timeline. Three dispatch branches:

    **§11a.0 — Both files exist**: If `impl-state.yaml` AND `phase-state.yaml` both exist, read phase-state.yaml:
    - Sub-case A: `phases.impl.status != null` OR `current_round != null` → migration already complete; legacy file is stale leftover. Skip to §11c. Do NOT re-migrate or touch the legacy file.
    - Sub-case B: Empty skeleton (both fields null) → partial migration. Proceed to §11a.1 but re-populate the existing file's `phases.impl.*` section rather than creating a new file (other sections remain intact); impl-state.yaml cleanup (step 4) still runs.

    **§11a.1 — Clean legacy migration**: If ONLY `impl-state.yaml` exists:
    1. Read `impl-state.yaml`.
    2. Identify unknown top-level keys (not in the migration doc's rename table). Known legacy fields: `phase`, `current_round`, `max_rounds`, `last_ac_status`, `last_audit_status`, `last_audit_critical`, `next_action`, `feedback_files.*`, `plan_file`, `ticket_dir`, `size`, `started`. Unknown keys are preserved per `legacy_extras` rule (migration doc §3).
    3. Write `phase-state.yaml` with the canonical schema (see `phase-state-schema.md`):
       - Top-level: `version: 1`; `size:` = legacy `size`; `created:` = legacy `started` (fallback `{now}`); `current_phase: impl`; `last_completed_phase: scout`; `overall_status: in-progress`. No top-level `ticket_dir:`.
       - `phases.create_ticket.status: completed`, `completed_at: {now}`, `artifacts.ticket: .backlog/active/{ticket-dir}/ticket.md` if exists else `null`.
       - `phases.scout.status: completed`, `completed_at: {now}`, `artifacts.investigation` / `artifacts.plan` if the files exist else `null`.
       - `phases.impl.status: in-progress`, `started_at:` = legacy `started`. Copy legacy fields 1:1 under `phases.impl.*` per rename table (legacy `phase → phase_sub`; `started → started_at`; `plan_file` / `ticket_dir` dropped; other fields keep name).
       - `phases.impl.legacy_extras:` preserves unknown keys (omit field if none).
       - `phases.ship.status: pending`, all fields `null`.
    4. On successful write, rename legacy: `mv impl-state.yaml impl-state.yaml.migrated-{YYYYMMDD}.bak`. NEVER `rm`. If the write failed, do NOT rename — migration is all-or-nothing.
    5. Print `[PHASE-STATE-MIGRATION] impl-state.yaml → phase-state.yaml migrated for {ticket-dir}; legacy preserved at impl-state.yaml.migrated-{YYYYMMDD}.bak`.
    6. Set `impl_resume_mode = true` and proceed to §11c.

    **11b. Bootstrap**: If NEITHER file exists but a plan.md is present:
    - Under `.backlog/active/{ticket-dir}/`:
      1. Create `phase-state.yaml` with the canonical schema: top-level `version: 1`, `size:` = detected Size, `created: {now}`, `current_phase: impl`, `last_completed_phase: scout`, `overall_status: in-progress`; `phases.create_ticket` and `phases.scout` marked completed with artifact fields pointing to existing files (else null); `phases.impl.status: in-progress`, `started_at: {now}`, other fields at pending defaults; `phases.ship.status: pending`.
      2. Print `[PHASE-STATE-BOOTSTRAP] phase-state.yaml bootstrapped for {ticket-dir} (no prior state found)`.
      3. Set `impl_resume_mode = false` and proceed to Step 12.
    - Under `.docs/plans/` (non-ticket flow): skip state creation; all state-update steps (incl. Step 21 cleanup) become no-ops.

    **11c. Resume dispatch**: If `phase-state.yaml` exists, `phases.impl.status == in-progress`, and `next_action` is non-null:
    - Set `impl_resume_mode = true`. Read `phases.impl.*`.
    - Print resume summary:
      ```
      [IMPL-RESUME] 前回の /impl 実行が途中で停止しています。途中から再開します。
      [IMPL-RESUME] Round: {current_round}/{max_rounds}
      [IMPL-RESUME] Phase: {phase_sub}
      [IMPL-RESUME] Next action: {next_action}
      ```
    - Carry forward `feedback_files`. Skip to the step matching `next_action`:
      - `start-round-{N}-generator` → Step 13 with `current_round = N` (pass `feedback_files.eval` / `quality` to Generator if present).
      - `start-evaluator` → Step 15. `start-audit` → Step 17. `proceed-to-phase-3` → Phase 3 (Step 19).
      - `stop-critical` → print "Previous run stopped due to CRITICAL. Reset `phases.impl` (status: pending, next_action: null) to re-run." and stop.

    **11d. Fresh-start**: If `phase-state.yaml` exists but `phases.impl.status == pending` (typical post-`/scout`): set `impl_resume_mode = false` and proceed to Step 12. State updates happen at Step 13+ per the state-management section below.

    If the plan lies outside any active ticket dir (e.g. `.docs/plans/...`), skip all state resolution and proceed with `impl_resume_mode = false`.

12. **Safety checkpoint**: Create a rollback point with `git stash push -m "impl-checkpoint" --include-untracked -- ':!.backlog' ':!.docs' ':!.simple-wf-knowledge'` (preserves plugin artifacts). On success print "Safety checkpoint created. To rollback: git stash pop". If nothing to stash, skip silently.

## Phase 2: Generator → AC Evaluator → Code Quality Reviewer Loop (max 3 rounds)

**Autopilot round limit**: If `{ticket-dir}/autopilot-policy.yaml` defines `constraints.max_total_rounds`, use that value; else default 3.

### phase-state.yaml phases.impl state management

All intra-impl loop state lives under `phases.impl.*` in `{ticket-dir}/phase-state.yaml`. See `phase-state-schema.md` for the canonical schema.

If `impl_resume_mode = false` and `phase-state.yaml` exists, initialize `phases.impl` to the in-progress state **before entering the loop** via read-modify-write; touch only the fields listed:

```yaml
phases:
  impl:
    status: in-progress
    started_at: {ISO-8601 via `date -u +%Y-%m-%dT%H:%M:%SZ`}
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

`phase_sub` values: `generator-pending`, `generator-complete`, `evaluator-complete`, `audit-complete`, `round-complete`, `done`. `next_action` values: `start-round-{N}-generator`, `start-evaluator`, `start-audit`, `proceed-to-phase-3`, `stop-critical`.

State updates (read-modify-write, touch ONLY fields under `phases.impl.*`; never touch `phases.create_ticket` / `phases.scout` / `phases.ship`):
- **Before Generator (step 13)**: `phase_sub: generator-pending`, `next_action: start-round-{N}-generator`, `current_round: {N}`.
- **Start of step 14 (pre `git diff --shortstat`)**: `phase_sub: generator-complete`, `next_action: start-evaluator`.
- **After Evaluator (step 16)**: `phase_sub: evaluator-complete`, `last_ac_status: {PASS|FAIL|FAIL-CRITICAL}`, `next_action: start-audit` (PASS) / `start-round-{N+1}-generator` (FAIL, rounds remain) / `stop-critical` (FAIL-CRITICAL).
- **After /audit (step 18)**: `phase_sub: audit-complete`, `last_audit_status: {PASS|PASS_WITH_CONCERNS|FAIL}`, `last_audit_critical: {count}`, `next_action` per decision, `feedback_files.eval`/`feedback_files.quality` = round-N report paths.

**Non-ticket flow**: When the plan is under `.docs/plans/` there is no `phase-state.yaml` and all state updates are no-ops.

13. **MUST invoke the Generator (`implementer`) agent via the Agent tool**. **NEVER bypass the Generator** by writing code directly via `Edit`/`Write` from `/impl` — the Generator → Evaluator firewall requires the orchestrator to produce no code changes. Fail the task immediately if the Generator cannot be invoked.
    - subagent_type: `implementer` (always; no -light variant).
    - model: per Size → model routing. Read `constraints.sonnet_size_threshold` from `{ticket-dir}/autopilot-policy.yaml` if present. Values `S`, `M`, `L`, `off`; default `M` when policy/field absent. Mapping: `S` → sonnet only on Size S; `M` (default) → sonnet on S or M; `L` → sonnet on S, M, or L; `off` → always opus. Otherwise opus. See `skills/create-ticket/references/autopilot-policy-reference.md`.
    - description: "Implement plan for <feature>"
    - Prompt must include:
      a. Plan path: `<path>`. Implementer MUST read the full plan before implementing.
      b. Acceptance Criteria (highlighted: "You will be evaluated by an independent evaluator against these criteria")
      c. Investigation path (if exists) as background context.
      d. User's additional instructions (if any)
      e. Round 2+: Pass previous round's feedback file paths: "Read feedback before implementing — AC Evaluator: {eval-round-{n-1}.md} (or 'All AC passed'); Code Quality: {quality-round-{n-1}.md} (or 'Not run' / 'No issues')."
      f. "Refer to CLAUDE.md for lint/test commands and coding standards."
      g. Round 1 with Dry Run: AC Evaluator's verification plan prefixed with "The AC evaluator will verify your implementation against the acceptance criteria using this plan:"
      h. Knowledge-base injection: Read `.simple-wf-knowledge/index.yaml`; filter `role=implementer` and `confidence >= 0.8`; include up to 20 summary lines under "## Known Project Patterns". If `.simple-wf-knowledge/index.yaml` does not exist, skip this injection silently. **AC always wins over KB patterns on conflict.**
      i. Autopilot constraints: If `autopilot-policy.yaml` exists and `constraints.allow_breaking_changes: false`, include: "CONSTRAINT: Do not introduce breaking changes to existing public APIs, interfaces, or exported functions. Maintain backward compatibility." Omit otherwise.
      j. **CONSTRAINT — Input immutability** (verbatim): "Do NOT modify `plan.md`, `ticket.md`, or `investigation.md` at any point. These are read-only inputs. Source code changes and new files (test files, eval reports are produced separately) are fine. If you believe the plan needs revision, flag it in your Next Steps field — the orchestrator will invoke `/plan2doc` separately." Prevents Generator / Evaluator contamination via input-artifact mutation.
    - Receive Generator's return value (changed files list + lint/test status).

14. **Immediately** update `phase-state.yaml` (touch only `phases.impl.*`):
      phases.impl.phase_sub: generator-complete
      phases.impl.next_action: start-evaluator
    Then `git diff --shortstat` for a one-line summary. Do NOT run `git diff --stat` in the main session — the ac-evaluator invokes it via its own `Bash(git diff:*)` permission.

    > **CHECKPOINT**: Read `phase-state.yaml`, confirm `next_action: start-evaluator`, proceed to Step 15. Do NOT end your turn.

15. **MUST invoke the AC Evaluator (`ac-evaluator`) agent via the Agent tool** (always sonnet). **NEVER self-assess AC compliance** from Generator return / build / test output alone — the Evaluator reads the code via `git diff` and renders its own PASS/FAIL. This is the Ticket 002 failure mode (L554-L559). Fail the task immediately if the Evaluator cannot be invoked.
   - Prompt must include:
     a. Plan path: `<path>`. Read it in full before evaluating.
     b. Acceptance Criteria
     c. Output of `git diff --shortstat` from step 14
     d. "The following files have been changed. Run `git diff` to inspect changes, run lint/test independently, and verify each AC."
     e. Report save path — **`{eval-report-path}` MUST be resolved by the orchestrator and substituted into the template below**. Resolution:
        - Plan under `.backlog/active/{ticket-dir}/` → `{eval-report-path}` = `.backlog/active/{ticket-dir}/eval-round-{n}.md`.
        - Else match current branch against active ticket dirs: strip leading `NNN-` prefix from each dir (e.g. `001-add-search-feature` → `add-search-feature`), check if branch contains the slug; if match, `{eval-report-path}` = `.backlog/active/{full-directory-name}/eval-round-{n}.md`. Else `{eval-report-path}` = `.docs/eval-round/{topic}-eval-round-{n}.md` where `{topic}` is derived from plan filename.
        `{n}` = current round (1, 2, or 3).
     f. Append verbatim: "The Acceptance Criteria text above is the fixed rubric — do NOT re-derive it from the plan. The plan path is provided as context; if the plan's current AC text differs from the rubric above, trust the rubric (it was extracted by the orchestrator before the Generator ran)." Keeps Evaluator verdicts anchored to a pre-Generator rubric.
   - Prompt must NOT include: Generator's return value (bias elimination); a second invocation whose sole purpose is to persist the report (the save path is always in THIS first call — see Binding rules).
   - Receive AC Evaluator's return value (PASS/FAIL/FAIL-CRITICAL + feedback).

   **Copy-pasteable Evaluator prompt template** (substitute `{plan-path}`, `{acceptance-criteria}`, `{git-diff-shortstat}`, `{eval-report-path}`, `{n}` per 15.e):

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
    - **FAIL-CRITICAL** → stop immediately. Report CRITICAL issues. Do NOT continue rounds.
    - **Autopilot policy check for ac_eval_fail**: If `autopilot-policy.yaml` exists, read `gates.ac_eval_fail`: `on_critical: stop` is always enforced (FAIL-CRITICAL safety invariant); `action: retry` → continue (print `[AUTOPILOT-POLICY] gate=ac_eval_fail action=retry round={n}`); `action: stop` → stop (print `[AUTOPILOT-POLICY] gate=ac_eval_fail action=stop`). Else proceed with behavior below.
    - **FAIL** → save ac-evaluator's Feedback; continue to next round (skip quality review this round).
    - **PASS-WITH-CAVEATS** → treat as PASS; record Caveats for Phase 3 summary ("AC passed with caveats: {caveats}"). Continue to step 17.
    - **PASS** → continue to step 17.

    Update `phase-state.yaml` (touch only `phases.impl.*`):
      phases.impl.phase_sub: evaluator-complete
      phases.impl.last_ac_status: {PASS|FAIL|FAIL-CRITICAL}
      phases.impl.next_action: start-audit                    ← PASS / PASS-WITH-CAVEATS
                           or: start-round-{N+1}-generator   ← FAIL
                           or: stop-critical                  ← FAIL-CRITICAL (already stopped)

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING** (skip if FAIL-CRITICAL): Read `phase-state.yaml`; execute `phases.impl.next_action` immediately (`start-audit` → Step 17; `start-round-{N+1}-generator` → Step 13). Do NOT end your turn.

17. **MUST invoke `/audit` via the Skill tool** (replaces direct code-reviewer spawning). **NEVER bypass /audit** by spawning `code-reviewer` / `security-scanner` directly or skipping review after AC PASS. Fail the task immediately if `/audit` cannot be invoked — do not proceed to Phase 3 without a valid structured return block.
    - Call `/audit` with `round={n}` (matches `eval-round-{n}.md`). If plan is under `.backlog/active/{ticket-dir}/plan.md`, also pass `ticket-dir={ticket-dir}` (bare directory name, e.g. `003-fix-login`) to `/audit`. Do NOT pass `only_security_scan` — both code-reviewer and security-scanner must run.
    - `/audit` writes reports to `.backlog/active/{ticket-dir}/quality-round-{n}.md`, `security-scan-{n}.md`, `audit-round-{n}.md`. `round={n}` keeps round files aligned across retries / resumes.
    - `/audit` must NOT receive Generator's or AC Evaluator's return value — firewall is preserved because `/audit` inspects `git diff` independently.
    - Parse `/audit`'s structured return block: `**Status**` (PASS | PASS_WITH_CONCERNS | FAIL), `**Critical**`, `**Warnings**`, `**Suggestions**`, `**Reports**`, `**Summary**`.
    - **If `/audit` itself fails** (no structured block / malformed):
     - **Autopilot policy check**: If `autopilot-policy.yaml` exists, read `gates.audit_infrastructure_fail.action`: `treat_as_fail` → **Status: FAIL**, `Critical = 1`, print `[AUTOPILOT-POLICY] gate=audit_infrastructure_fail action=treat_as_fail`, continue with audit failure in feedback; `stop` → stop, print `[AUTOPILOT-POLICY] gate=audit_infrastructure_fail action=stop`.
     - Else use `AskUserQuestion` "/auditが失敗しました。どうしますか？" with: `stop` (exit, do NOT proceed to Phase 3); `fail` (treat as FAIL+Critical=1; combine with ac-evaluator PASS as feedback for next round; on round 3 proceed to Phase 3 with audit failure noted).
      - **Non-interactive fallback**: If `AskUserQuestion` unavailable / errors, default to `stop` (NOT `fail` — a silent FAIL retry would mask infrastructure failure). Print "Stopped: /impl requires interactive mode to recover from /audit failure." and exit. Do NOT hang.
      - **Never** silently treat audit failure as PASS / PASS_WITH_CONCERNS — Critical / security issues must not slip through.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: Read `phase-state.yaml`; execute `phases.impl.next_action` immediately. Do NOT end your turn. Do NOT summarize the audit to the user.

18. Combined Decision (from `/audit` structured return):
    - **FAIL** (Critical > 0) → combine ac-evaluator PASS + audit Critical findings (from the `**Reports**` paths) as feedback for next Generator round. Continue.
    - **PASS_WITH_CONCERNS** (Warnings/Suggestions only) → Phase 3, include concerns in summary.
    - **PASS** (all counts 0) → Phase 3.
    - **Round 3 + FAIL** → Phase 3 with remaining AC and quality/security issues noted.

## Phase 3: Summary

19. Run `git status -s` and display.

20. Print summary: plan file, files changed/created, rounds completed, final status (PASS / PASS_WITH_CONCERNS with listed concerns / remaining AC+quality issues), evaluation report paths, and "Review the changes above, then run `/ship` to commit and create PR".

21. **phase-state.yaml finalization**: When Phase 3 is reached via `proceed-to-phase-3` (success / PASS_WITH_CONCERNS), update `phase-state.yaml` (touch only listed fields):
    - `phases.impl.status: completed`
    - `phases.impl.completed_at: {now}` (ISO-8601 UTC)
    - `phases.impl.phase_sub: done`
    - `phases.impl.last_round: {final round N}`
    - `phases.impl.next_action: null` (volatile resume state cleared)
    - `last_completed_phase: impl`
    - `current_phase: ship`

    Do NOT delete `phase-state.yaml` — it is the permanent record consumed by `/ship` and `/catchup`. `eval-round-*.md`, `quality-round-*.md`, `audit-round-*.md`, `security-scan-*.md` remain in the ticket directory (Glob-discoverable). `current_round`, `max_rounds`, `last_ac_status`, `last_audit_status`, `last_audit_critical`, `feedback_files.*` remain as historical trace.

    **Non-ticket flow**: No `phase-state.yaml`, step is a no-op.

    **Failure case**: If `/impl` exits with remaining AC/quality issues after the max-rounds cap, set `phases.impl.status: completed` but leave `overall_status: in-progress` — user decides whether to re-run. Only set `phases.impl.status: failed` and `overall_status: failed` when the skill itself cannot complete (Generator/Evaluator invocation failure, FAIL-CRITICAL early stop).

22. **Emit SW-CHECKPOINT block (Phase 3 final output only)**. Emit `## [SW-CHECKPOINT]` per `skills/create-ticket/references/sw-checkpoint-template.md` as the FINAL section, after step 20 summary and step 21 finalization. **Only once per invocation** — never after each round / inside the loop. Fill: `phase=impl`; `ticket=.backlog/active/{ticket-dir}` when under a ticket dir, else `none`; `artifacts=[<repo-relative paths to every eval-round-*.md / quality-round-*.md / audit-round-*.md / security-scan-*.md across all rounds + changed source files from `git diff --name-only`>]`; `next_recommended=/ship` on `proceed-to-phase-3`, else `""` (FAIL-CRITICAL / infra failure). Emit on failure paths with `artifacts: []`.

## Error Handling

- **No plan**: Print the no-plan message and stop.
- **Dirty working tree**: Warn and ask whether to continue.
- **Generator failure**: Report and stop.
- **AC Evaluator failure**: Report; Generator's changes remain.
- **/audit failure**: Step 17 handles — ask `AskUserQuestion` STOP vs FAIL. Never treat audit failure as PASS / PASS_WITH_CONCERNS.
- **3 rounds FAIL**: Report remaining issues; code remains changed.

## Evaluator Tuning

Automated via the `/tune` skill:
1. `/ship` invokes `/tune` automatically (Step 6) to extract patterns from evaluation logs.
2. Patterns land in `.simple-wf-knowledge/candidates.yaml`, promoted to `entries.yaml` at confidence 0.8.
3. Promoted patterns are injected into the Generator prompt (Step 13h) via `index.yaml`.
4. Manual: `/tune {ticket-dir}` or `/tune all`.
5. Review: `.simple-wf-knowledge/entries.yaml` and `.simple-wf-knowledge/index.yaml`.
