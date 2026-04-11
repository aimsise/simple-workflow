---
name: impl
description: >-
  Use after /scout or /plan2doc to execute the implementation plan.
  Implements the latest plan with independent AC verification and
  code quality review.
disable-model-invocation: true
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

Latest plan in .backlog/active/:
!`ls -t .backlog/active/*/plan.md 2>/dev/null | head -1`

Latest plan in .docs/plans/:
!`ls -t .docs/plans/*.md 2>/dev/null | head -1`

Latest research in .backlog/active/:
!`ls -t .backlog/active/*/investigation.md 2>/dev/null | head -1`

Latest research in .docs/research/:
!`ls -t .docs/research/*.md 2>/dev/null | head -1`

Current state:
!`git status --short`

## Phase 1: Plan Loading & Size Detection

1. Parse `$ARGUMENTS`:
   - If it starts with `.backlog/active/` or `.docs/plans/` -> use it as the plan file path. Remaining text is additional instructions.
   - Otherwise -> entire argument is additional instructions. Use the latest plan from pre-computed context above, preferring `.backlog/active/*/plan.md` (most recent) over `.docs/plans/*.md`.
   - If no plan file exists in either location, print "No plan found in .backlog/active/ or .docs/plans/. Run /scout or /plan2doc first." and stop.

2. Read the plan file.

3. Size detection:
   - If plan is in `.backlog/active/{slug}/plan.md` -> read `.backlog/active/{slug}/ticket.md`, extract Size from `| Size |` row.
   - If plan is in `.docs/plans/` -> default to M.

4. **Worktree recommendation** (L/XL size only):
   If detected size is L or XL, print:
   "Tip: This is a Size {size} ticket. For safer isolation, consider using a git worktree:
   `git worktree add -b impl/{slug} ../impl-{slug} && cd ../impl-{slug}`
   Then re-run `/impl` in the new worktree."
   Where `{slug}` is derived from the plan path (`.backlog/active/{slug}/plan.md`) or the plan filename.
   This is a non-blocking suggestion — proceed regardless.

5. Identify Acceptance Criteria section in the plan (`### Acceptance Criteria` or equivalent).

6. If Acceptance Criteria section is NOT found in the plan, print "ERROR: Plan has no Acceptance Criteria. Add an '### Acceptance Criteria' section to the plan before running /impl." and stop.

7. **AC Sanity Check** (round 1 only, M/L/XL size only): Include in the Generator prompt: "Before implementing, review each AC. If any AC is ambiguous or technically infeasible, flag it in your **Next Steps** field." If Generator flags ambiguous AC, report to user and stop.

8. **Evaluator Dry Run** (round 1 only, **L/XL size only**):
   Spawn the **AC Evaluator** agent (`ac-evaluator`) with a verification planning prompt:
   - Prompt: "You are preparing a verification plan. For each Acceptance Criterion below, describe HOW you will verify it (what commands to run, what to check in the code, what edge cases to test). Do NOT evaluate any implementation — no code has been written yet. Return only the verification plan."
   - Include: Full plan content, Acceptance Criteria
   - Receive: Evaluator's verification plan
   - **If Evaluator fails or returns partial**: Use `AskUserQuestion` to ask the user "Evaluator が検証プランに合意できませんでした。続行しますか？" with options "yes" (proceed without verification plan) and "no" (stop the skill).
     - If user answers "no" → stop the skill immediately. Print "Stopped by user after Evaluator Dry Run failure." and exit.
     - If user answers "yes" → proceed without the verification plan. The Generator prompt will not include the dry run output for this round.
   - **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), default to "no" (stop the skill). Print "Stopped: /impl requires interactive mode to recover from Evaluator Dry Run failure. Re-run in interactive mode." and exit. Do NOT hang waiting for input.
   - **If Evaluator succeeds**: Save the verification plan for inclusion in Generator prompt (step 12g).

9. If related investigation file exists (same directory `investigation.md` or latest in `.docs/research/`), read it.

10. If working tree has uncommitted changes unrelated to the plan, warn user.

11. **Safety checkpoint**: Before starting implementation, create a rollback point:
   - Run `git stash push -m "impl-checkpoint" --include-untracked` to save current working state
   - If stash succeeds, print: "Safety checkpoint created. To rollback: git stash pop"
   - If nothing to stash (clean working tree), skip silently

## Phase 2: Generator → AC Evaluator → Code Quality Reviewer Loop (max 3 rounds)

12. Spawn **Generator** agent via the Agent tool:
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
    - Receive Generator's return value (changed files list + lint/test status)

13. Run `git diff --stat` to capture change summary.

14. Spawn **AC Evaluator** agent (`ac-evaluator`, always sonnet):
   - Prompt must include:
     a. Full plan content
     b. Acceptance Criteria
     c. Output of `git diff --stat` from step 13
     d. "The following files have been changed. Run `git diff` to inspect changes, run lint/test independently, and verify each AC."
     e. Report save path:
        - If plan is in `.backlog/active/{slug}/` -> "Save your evaluation report to `.backlog/active/{slug}/eval-round-{n}.md`"
        - Otherwise -> check if any directory in `.backlog/active/` matches the current branch name (branch name contains the slug). If a match is found, use `.backlog/active/{slug}/eval-round-{n}.md`. If no match, use `.docs/eval-round/{topic}-eval-round-{n}.md` where {topic} is derived from the plan filename (e.g., `.docs/plans/add-search.md` -> `add-search`).
        Where {n} is the current round number (1, 2, or 3).
   - Prompt must NOT include: Generator's return value (bias elimination)
   - Receive AC Evaluator's return value (PASS/FAIL/FAIL-CRITICAL + feedback)

15. AC Gate:
    - **Status: FAIL-CRITICAL** → stop immediately. Report CRITICAL issues to the user. Do NOT continue to further rounds.
    - **Status: FAIL** → save ac-evaluator's **Feedback**, continue to next round (skip quality review for this round)
    - **Status: PASS** → continue to step 16

16. **Invoke `/audit` via the Skill tool** (replaces direct code-reviewer spawning):
    - Call `/audit` with explicit `round={n}` matching the current Generator round counter (same `{n}` used for `eval-round-{n}.md` in Step 14). Do NOT pass `only_security_scan` so both code-reviewer and security-scanner run.
    - `/audit` writes its reports to `{ticket-dir}/quality-round-{n}.md`, `{ticket-dir}/security-scan-{n}.md`, and `{ticket-dir}/audit-round-{n}.md` using the round number passed via `round={n}`. This guarantees `eval-round-{n}` and `quality-round-{n}` / `audit-round-{n}` stay aligned across retries and resumed sessions.
    - The `/audit` skill must NOT receive Generator's return value or AC Evaluator's return value (information firewall is preserved because `/audit` independently inspects `git diff` via its own pre-computed context).
    - Parse `/audit`'s structured return block:
      - `**Status**`: PASS | PASS_WITH_CONCERNS | FAIL
      - `**Critical**`: aggregated count across code-reviewer + security-scanner
      - `**Warnings**`: aggregated count
      - `**Suggestions**`: aggregated count
      - `**Reports**`: paths to the saved review files
      - `**Summary**`: one-line aggregated summary
    - **If `/audit` itself fails** (no structured block returned, or the block is malformed): print the failure details (`/audit`'s raw output if available) and use `AskUserQuestion` to ask "/auditが失敗しました。どうしますか？" with options:
      - "stop": stop the skill immediately. Print "Stopped by user after /audit failure." and exit. Do NOT proceed to Phase 3.
      - "fail": treat the audit as **Status: FAIL** with `Critical = 1` (audit infrastructure failure). Combine the audit failure note with ac-evaluator's pass confirmation as feedback for the next Generator round, and follow the same flow as a normal FAIL in step 17. If this is round 3, proceed to Phase 3 with the audit failure noted in the summary.
      - **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), default to "stop" (do NOT default to "fail" — a silent FAIL retry would mask the infrastructure failure). Print "Stopped: /impl requires interactive mode to recover from /audit failure. Re-run in interactive mode." and exit. Do NOT hang waiting for input.
      - **Never** silently treat audit failure as PASS or PASS_WITH_CONCERNS — that would let Critical/security issues slip through unverified.

17. Combined Decision (based on `/audit` structured return):
    - **`/audit` Status: FAIL** (Critical > 0) → Combine ac-evaluator's pass confirmation and the audit's Critical findings (from the report files in `**Reports**`) as feedback for the next Generator round. Continue to next round.
    - **`/audit` Status: PASS_WITH_CONCERNS** (Warnings or Suggestions, no Critical) → Proceed to Phase 3. Include the audit's concerns in the summary.
    - **`/audit` Status: PASS** (all counts at 0) → Proceed to Phase 3.
    - **Round 3 and Status: FAIL** → proceed to Phase 3 with remaining issues noted (both AC and quality/security).

## Phase 3: Summary

18. Run `git status -s` and display.

19. Print summary:
    - Plan file executed
    - Files changed or created
    - Generator → AC Evaluator → Code Quality Reviewer rounds completed
    - Final status (PASS, PASS_WITH_CONCERNS with listed quality concerns, or remaining issues from AC/quality evaluation)
    - Evaluation reports: [list of saved eval-round-*.md and quality-round-*.md file paths]
    - "Review the changes above, then run `/ship` to commit and create PR"

## Error Handling

- **No plan**: Print "No plan found in .backlog/active/ or .docs/plans/. Run /scout or /plan2doc first." and stop.
- **Dirty working tree**: Warn user about unrelated changes, ask whether to continue.
- **Generator failure** (Status: failed): Report error and stop.
- **AC Evaluator failure** (Status: failed or partial): Report error. Generator's changes remain in place.
- **/audit failure** (no structured block returned, or malformed): See Step 16 — ask the user via `AskUserQuestion` whether to STOP or treat the audit as FAIL. Never silently treat audit failure as PASS / PASS_WITH_CONCERNS.
- **3 rounds FAIL**: Report remaining issues. Code remains changed.

## Evaluator Tuning

Evaluator tuning is now automated via the `/tune` skill:
1. After `/ship` completes a ticket, `/tune` is invoked automatically (Step 18 in `/ship`) to extract patterns from evaluation logs
2. Extracted patterns are stored in `.simple-wf-knowledge/candidates.yaml` and promoted to `entries.yaml` when confidence reaches 0.8
3. Promoted patterns are injected into the Generator prompt (Step 12h above) via `index.yaml`
4. To run tuning manually: `/tune {ticket-slug}` or `/tune all`
5. To review the current knowledge base: read `.simple-wf-knowledge/entries.yaml` and `.simple-wf-knowledge/index.yaml`
