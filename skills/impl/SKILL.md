---
name: impl
description: >-
  Use after /scout or /plan2doc to execute the implementation plan.
  Implements the latest plan with independent AC verification and
  code quality review.
disable-model-invocation: true
allowed-tools:
  - Agent
  - Read
  - Glob
  - "Bash(git diff:*)"
  - "Bash(git status:*)"
  - "Bash(git log:*)"
  - "Bash(git branch:*)"
  - "Bash(git stash:*)"
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

8. **Evaluator Dry Run** (round 1 only, M/L/XL size only):
   Spawn the **AC Evaluator** agent (`ac-evaluator`) with a verification planning prompt:
   - Prompt: "You are preparing a verification plan. For each Acceptance Criterion below, describe HOW you will verify it (what commands to run, what to check in the code, what edge cases to test). Do NOT evaluate any implementation — no code has been written yet. Return only the verification plan."
   - Include: Full plan content, Acceptance Criteria
   - Receive: Evaluator's verification plan
   - If Evaluator fails or returns partial: warn user "Evaluator Dry Run failed. Verification plan unavailable. Proceeding without bilateral agreement." Continue with implementation.
   - Save the verification plan for inclusion in Generator prompt

9. If related investigation file exists (same directory `investigation.md` or latest in `.docs/research/`), read it.

10. If working tree has uncommitted changes unrelated to the plan, warn user.

11. **Safety checkpoint**: Before starting implementation, create a rollback point:
   - Run `git stash push -m "impl-checkpoint" --include-untracked` to save current working state
   - If stash succeeds, print: "Safety checkpoint created. To rollback: git stash pop"
   - If nothing to stash (clean working tree), skip silently

## Phase 2: Generator → AC Evaluator → Code Quality Reviewer Loop (max 3 rounds)

12. Spawn **Generator** agent:
   - Size S -> `implementer-light` (sonnet)
   - Size M/L/XL -> `implementer` (opus)
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

16. Spawn **Code Quality Reviewer** agent (`code-reviewer`, always sonnet):
   - Prompt must include:
     a. Output of `git diff --stat` from step 13
     b. List of changed files (from `git diff --name-only`)
     c. "Review the code changes for quality, security, performance, and convention compliance. AC compliance has already been verified by a separate evaluator. Refer to CLAUDE.md or project conventions for coding standards."
     d. Report save path:
        - If plan is in `.backlog/active/{slug}/` -> "Save your review report to `.backlog/active/{slug}/quality-round-{n}.md`"
        - Otherwise -> check if any directory in `.backlog/active/` matches the current branch name (branch name contains the slug). If a match is found, use `.backlog/active/{slug}/quality-round-{n}.md`. If no match, use `.docs/quality-round/{topic}-quality-round-{n}.md` where {topic} is derived from the plan filename (e.g., `.docs/plans/add-search.md` -> `add-search`).
   - Prompt must NOT include: Generator's return value or AC Evaluator's return value
   - Receive code-reviewer's return value (Critical/Warnings/Suggestions)

17. Combined Decision:
    - **Code-reviewer Critical > 0** → Status: FAIL. Combine ac-evaluator's pass confirmation and code-reviewer's Critical issues as feedback for next Generator round. Continue to next round.
    - **Code-reviewer Warnings or Suggestions only (no Critical)** → Status: PASS_WITH_CONCERNS. Proceed to Phase 3. Include quality concerns in the summary.
    - **Code-reviewer no issues** → Status: PASS. Proceed to Phase 3.
    - **Round 3 and Status: FAIL** → proceed to Phase 3 with remaining issues noted (both AC and quality).

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
- **Code Quality Reviewer failure** (Status: failed or partial): Treat as no quality issues. Proceed with AC Evaluator result only.
- **3 rounds FAIL**: Report remaining issues. Code remains changed.

## Evaluator Tuning

After completing multiple /impl cycles, review evaluator performance:
1. Read saved evaluation reports (`eval-round-*.md`, `quality-round-*.md`) across recent tickets
2. Identify patterns: Does the evaluator consistently miss certain issue types? Over-flag certain patterns?
3. If patterns are found, update the evaluator agent prompt (`agents/ac-evaluator.md` or `agents/code-reviewer.md`) to address them
4. Track prompt changes in git commit messages for auditability
