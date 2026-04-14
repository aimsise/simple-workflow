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
  - Glob
  - "Bash(git diff:*)"
  - "Bash(git status:*)"
  - "Bash(git log:*)"
  - "Bash(git branch:*)"
  - "Bash(git stash:*)"
  # Copilot CLI
  - task
  - ask_user
  - skill
  - view
  - glob
  - "shell(git diff:*)"
  - "shell(git status:*)"
  - "shell(git log:*)"
  - "shell(git branch:*)"
  - "shell(git stash:*)"
argument-hint: "[plan file path or additional instructions]"
---

Implement the latest plan using Generator → AC Evaluator → Code Quality Reviewer architecture.
User arguments: $ARGUMENTS

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

2. Read the plan file.

3. Size detection:
   - If plan is in `.backlog/active/{ticket-dir}/plan.md` -> read `.backlog/active/{ticket-dir}/ticket.md`, extract Size from `| Size |` row.
   - If plan is in `.docs/plans/` -> default to M.

4. **Worktree recommendation** (L/XL size only):
   If detected size is L or XL, print:
   "Tip: This is a Size {size} ticket. For safer isolation, consider using a git worktree:
   `git worktree add -b impl/{slug} ../impl-{slug} && cd ../impl-{slug}`
   Then re-run `/impl` in the new worktree."
   Where `{slug}` is the slug portion of the ticket directory name (strip the leading `NNN-` prefix, e.g., `001-add-search-feature` -> `add-search-feature`).
   This is a non-blocking suggestion — proceed regardless.

5. Identify Acceptance Criteria section in the plan (`### Acceptance Criteria` or equivalent).

6. If Acceptance Criteria section is NOT found in the plan, print "ERROR: Plan has no Acceptance Criteria. Add an '### Acceptance Criteria' section to the plan before running /impl." and stop.

7. **AC Sanity Check** (round 1 only, M/L/XL size only): Include in the Generator prompt: "Before implementing, review each AC. If any AC is ambiguous or technically infeasible, flag it in your **Next Steps** field." If Generator flags ambiguous AC, report to user and stop.

8. **Evaluator Dry Run** (round 1 only, **L/XL size only**):
   Spawn the **AC Evaluator** agent (`ac-evaluator`) with a verification planning prompt:
   - Prompt: "You are preparing a verification plan. For each Acceptance Criterion below, describe HOW you will verify it (what commands to run, what to check in the code, what edge cases to test). Do NOT evaluate any implementation — no code has been written yet. Return only the verification plan."
   - Include: Full plan content, Acceptance Criteria
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

9. If related investigation file exists (same directory `investigation.md` or latest in `.docs/research/`), read it.

10. If working tree has uncommitted changes unrelated to the plan, warn user.

11. **Resume check**: Check if `{ticket-dir}/impl-state.yaml` exists (where `{ticket-dir}` is the directory containing the plan file, e.g. `.backlog/active/{ticket-dir}/`).
    - If it does NOT exist: set `impl_resume_mode = false` and proceed normally to step 12.
    - If it exists: set `impl_resume_mode = true`. Read and parse the state file.
      - Print resume summary:
        ```
        [IMPL-RESUME] 前回の /impl 実行が途中で停止しています。途中から再開します。
        [IMPL-RESUME] Round: {current_round}/{max_rounds}
        [IMPL-RESUME] Phase: {phase}
        [IMPL-RESUME] Next action: {next_action}
        ```
      - Carry forward `feedback_files` from the state file.
      - Skip to the step corresponding to `next_action`:
        - `start-round-{N}-generator` → skip to Step 13 (Generator) with `current_round = N`. If `feedback_files.eval` and/or `feedback_files.quality` exist from a prior round, pass them to the Generator prompt (step 13e).
        - `start-evaluator` → skip to Step 15 (AC Evaluator) with the current round from the state file.
        - `start-audit` → skip to Step 17 (/audit) with the current round from the state file.
        - `proceed-to-phase-3` → skip directly to Phase 3 (Step 19).
        - `stop-critical` → print "Previous run stopped due to CRITICAL issues. Delete impl-state.yaml to re-run from scratch." and stop.

12. **Safety checkpoint**: Before starting implementation, create a rollback point:
   - Run `git stash push -m "impl-checkpoint" --include-untracked -- ':!.backlog' ':!.docs' ':!.simple-wf-knowledge'` to save current working state while preserving plugin artifacts
   - If stash succeeds, print: "Safety checkpoint created. To rollback: git stash pop"
   - If nothing to stash (clean working tree), skip silently

## Phase 2: Generator → AC Evaluator → Code Quality Reviewer Loop (max 3 rounds)

**Autopilot round limit**: If `{ticket-dir}/autopilot-policy.yaml` exists and `constraints.max_total_rounds` is defined, use that value as the maximum number of rounds for this loop (replacing the default of 3). If the policy does not exist or the field is not defined, use the default of 3 rounds.

### impl-state.yaml Management

If `impl_resume_mode = false` (no existing state file), initialize `{ticket-dir}/impl-state.yaml` before entering the loop:

```yaml
version: 1
plan_file: .backlog/active/{ticket-dir}/plan.md
ticket_dir: .backlog/active/{ticket-dir}
size: {S|M|L|XL}
started: {ISO-8601 timestamp via `date -u +%Y-%m-%dT%H:%M:%SZ`}
current_round: 1
max_rounds: {3 or autopilot policy value}
phase: generator-pending
last_ac_status: null
last_audit_status: null
last_audit_critical: 0
next_action: start-round-1-generator
feedback_files:
  eval: null
  quality: null
```

**phase** values: `generator-pending`, `generator-complete`, `evaluator-complete`, `audit-complete`, `round-complete`, `done`

**next_action** values: `start-round-{N}-generator`, `start-evaluator`, `start-audit`, `proceed-to-phase-3`, `stop-critical`

State updates occur at these 4 points within each round:
- **Before Generator (step 13)**: Update `phase: generator-pending`, `next_action: start-round-{N}-generator`, `current_round: {N}`
- **After Generator (step 14)**: Update `phase: generator-complete`, `next_action: start-evaluator`
- **After Evaluator (step 16)**: Update `phase: evaluator-complete`, `last_ac_status: {PASS|FAIL|FAIL-CRITICAL}`, `next_action: start-audit` (if PASS) or `next_action: start-round-{N+1}-generator` (if FAIL and rounds remain) or `next_action: stop-critical` (if FAIL-CRITICAL)
- **After /audit (step 18)**: Update `phase: audit-complete`, `last_audit_status: {PASS|PASS_WITH_CONCERNS|FAIL}`, `last_audit_critical: {count}`, `next_action` based on decision (e.g. `proceed-to-phase-3` if PASS, `start-round-{N+1}-generator` if FAIL), `feedback_files.eval: {eval-round-{N}.md path}`, `feedback_files.quality: {quality-round-{N}.md path}`

13. Spawn **Generator** agent via the Agent tool:
    - subagent_type: `implementer` (always; no -light variant)
    - model: `sonnet` if Size == S, otherwise `opus` (M/L/XL/unknown)
    - description: "Implement plan for <feature>"
    - Prompt must include:
      a. Full plan content
      b. Acceptance Criteria (highlighted: "You will be evaluated by an independent evaluator against these criteria")
      c. Investigation file content (if exists)
      d. User's additional instructions (if any)
      e. Round 2+: Pass the previous round's feedback file paths to the Generator:
         "Read the following feedback files from the previous evaluation round before implementing:
         - AC Evaluator feedback: {eval-round-{n-1}.md path} (or 'All AC passed' if none)
         - Code Quality feedback: {quality-round-{n-1}.md path} (or 'Not run' / 'No issues' if none)"
      f. "Refer to CLAUDE.md or project conventions for lint/test commands and coding standards."
      g. Round 1 with Dry Run: AC Evaluator's verification plan ("The AC evaluator will verify your implementation against the acceptance criteria using this plan:")
      h. Knowledge-base injection: Read `.simple-wf-knowledge/index.yaml`. If the file exists, filter entries where the role is `implementer` and `confidence >= 0.8`. Collect up to 20 lines of summaries and include them in the prompt under a heading "## Known Project Patterns". If `.simple-wf-knowledge/index.yaml` does not exist, skip this injection silently. **Note: Acceptance Criteria always take precedence over KB patterns. If a KB pattern conflicts with an AC, the AC wins.**
      i. Autopilot constraints: If `{ticket-dir}/autopilot-policy.yaml` exists, read `constraints.allow_breaking_changes`. If `false`, include in the Generator prompt: "CONSTRAINT: Do not introduce breaking changes to existing public APIs, interfaces, or exported functions. Maintain backward compatibility." If `true` or if the policy file does not exist, omit this constraint.
    - Receive Generator's return value (changed files list + lint/test status)

14. Run `git diff --stat` to capture change summary.

15. Spawn **AC Evaluator** agent (`ac-evaluator`, always sonnet):
   - Prompt must include:
     a. Full plan content
     b. Acceptance Criteria
     c. Output of `git diff --stat` from step 14
     d. "The following files have been changed. Run `git diff` to inspect changes, run lint/test independently, and verify each AC."
     e. Report save path:
        - If plan is in `.backlog/active/{ticket-dir}/` -> "Save your evaluation report to `.backlog/active/{ticket-dir}/eval-round-{n}.md`"
        - Otherwise -> Match the current branch name against active ticket directories. For each directory in `.backlog/active/`, extract the slug portion by stripping the leading `NNN-` prefix (the initial sequence of digits followed by a hyphen, e.g., `001-add-search-feature` → `add-search-feature`). Check if the branch name contains this slug portion. If a match is found, set `ticket-dir` to `.backlog/active/{full-directory-name}` (including the numeric prefix) and use `{ticket-dir}/eval-round-{n}.md`. If no match, use `.docs/eval-round/{topic}-eval-round-{n}.md` where {topic} is derived from the plan filename (e.g., `.docs/plans/add-search.md` -> `add-search`).
        Where {n} is the current round number (1, 2, or 3).
   - Prompt must NOT include: Generator's return value (bias elimination)
   - Receive AC Evaluator's return value (PASS/FAIL/FAIL-CRITICAL + feedback)

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

17. **Invoke `/audit` via the Skill tool** (replaces direct code-reviewer spawning):
    - Call `/audit` with explicit `round={n}` matching the current Generator round counter (same `{n}` used for `eval-round-{n}.md` in Step 15). Do NOT pass `only_security_scan` so both code-reviewer and security-scanner run.
    - `/audit` writes its reports to `{ticket-dir}/quality-round-{n}.md`, `{ticket-dir}/security-scan-{n}.md`, and `{ticket-dir}/audit-round-{n}.md` using the round number passed via `round={n}`. This guarantees `eval-round-{n}` and `quality-round-{n}` / `audit-round-{n}` stay aligned across retries and resumed sessions.
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
    > 1. Read `{ticket-dir}/impl-state.yaml`
    > 2. The state file shows `next_action`. Execute it immediately.
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

21. **impl-state.yaml cleanup**: Delete `{ticket-dir}/impl-state.yaml`. The `eval-round-*.md` and `quality-round-*.md` files serve as the permanent record of each round's results.

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
