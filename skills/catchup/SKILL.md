---
name: catchup
description: >-
  Analyze current branch state and recover working context. Use at session
  start, after context compaction, or when unsure what to do next. Detects
  current development phase and recommends the next action.
allowed-tools:
  - Agent
  - Read
  - Glob
  - Grep
  - "Bash(git:*)"
  - "Bash(ls:*)"
argument-hint: "[phase: investigate|plan|implement|test|review|commit]"
---

Recover context and detect next action for the current working session.
User arguments: $ARGUMENTS

Current branch:
!`git branch --show-current`

Recent history:
!`git log --oneline -20`

Changes from main:
!`git diff --stat main`

Working tree:
!`git status --short`

## Instructions

### 0. Argument Parsing

If `$ARGUMENTS` specifies a phase name (investigate, plan, implement, test, review, or commit), skip directly to **Step 4** and use the specified phase for guidance.

If `$ARGUMENTS` is empty, proceed with full recovery (Steps 1-4).

### 1. Compact-State and Session-Log Recovery

Check for recent compact-state files in `.docs/compact-state/compact-state-*.md` (most recent first).

**If the latest file starts with a YAML frontmatter (`---`)**, parse the frontmatter and extract the following fields as variables (used in Step 4):
- `date` — when the compact happened
- `branch` — branch at compact time
- `active_tickets` — list of ticket directories that were active
- `active_plans` — list of plan files that were active
- `latest_eval_round` — highest round number among saved `eval-round-*.md` files
- `latest_quality_round` — highest round number among saved `quality-round-*.md` files
- `last_round_outcome` — `PASS` | `FAIL` | `PASS_WITH_CONCERNS` | `unknown`
- `in_progress_phase` — `impl-loop` | `impl-done` | `unknown`

Use simple grep/awk on the YAML lines (e.g., `grep '^in_progress_phase:' <file> | sed 's/^in_progress_phase: //'`) to extract scalars. For list fields (`active_tickets`, `active_plans`) collect lines matching `^  - ` until the next non-list line.

**If the latest file does not start with `---`**, treat it as a legacy compact-state file and ignore the structured fields (still keep its existence as a flag for Step 2).

**If no compact-state file is found** (or as a complement), check for the most recent session log at `.docs/session-log/session-log-*.md`. If the file starts with a YAML frontmatter (`---`), parse the metadata (`date`, `branch`, `last_commit`, `changed_files`) and the `## Final Status` / `## Recent Commits` sections to recover the last-known working state. Skip files without YAML frontmatter (legacy format).

### 2. Context Analysis (conditional)

Determine whether the **researcher** agent is needed:

- **Skip researcher** if ALL of the following are true:
  - Current branch is `main` or `master`
  - Working tree has 0 changed files
  - No compact-state file was found in Step 1
  (State is obvious — clean start, no prior work to recover.)

- **Skip researcher** if:
  - A compact-state file was found in Step 1 that is less than 1 hour old
  (State is already available from the file — no need for deep analysis.)

- **Otherwise**: Spawn the **researcher** agent to analyze:
  - What has changed on this branch vs main
  - What the changes are trying to accomplish
  - Current state of work (complete, in-progress, blocked)
  - Check `.backlog/active/` for any active tickets and their artifacts (investigation.md, plan.md, eval-round-*.md)

### 3. Artifact Discovery

Check for existing docs (regardless of whether researcher was spawned):
- `.docs/plans/` — implementation plans
- `.docs/research/` — research findings
- `.backlog/active/` — active tickets and their artifacts
- `.docs/session-log/session-log-*.md` — most recent session log (if any) for last-known branch state

### 4. Phase Auto-Detection and Guidance

Detect the current development phase by checking these conditions **in order**. Check both `.docs/` and `.backlog/active/` for artifacts. Use the **first matching** phase:

0. **Compact-state indicates an in-progress `/impl` loop** → suggest **resume `/impl`**
   - Check: a YAML-frontmatter compact-state file was parsed in Step 1 AND `in_progress_phase == impl-loop`
   - Check: no new git commit has been made since the compact-state's `date` (compare against `git log -1 --format=%cI` for the most recent commit). If a newer commit exists, the user has already moved on — skip Rule 0 and fall through to the rules below.
   - Guidance: "You were in the middle of `/impl` (round `{latest_eval_round}` evaluated, last outcome: `{last_round_outcome}`). The next expected step is round `{latest_eval_round + 1}`. Re-run `/impl` to resume the Generator-Evaluator loop."
   - If `active_tickets` from the compact-state is non-empty, name the ticket directory in the guidance.

1. **No research files for current topic** → suggest **investigate**
   - Check: `.docs/research/` is empty or has no files related to current branch
   - Also check: `.backlog/active/` has ticket directories but no `investigation.md` in any of them
   - Guidance: Use `/investigate <topic>`. If a ticket exists in `.backlog/active/`, mention its directory.

2. **Research exists, no plans** → suggest **plan**
   - Check: `.docs/research/` has files BUT `.docs/plans/` has no related files
   - Also check: `.backlog/active/*/investigation.md` exists BUT `.backlog/active/*/plan.md` does not
   - Guidance: Read the research first, then use `/plan2doc <feature>`. `/plan2doc` automatically uses sonnet for S-size and opus for M/L/XL.

3. **Plans exist, no code diff from main** → suggest **implement**
   - Check: `.docs/plans/` has files BUT `git diff main --name-only` shows no changes outside `.docs/` and `.backlog/`
   - Also check: `.backlog/active/*/plan.md` exists BUT no code changes outside `.backlog/`
   - Guidance: Read the plan first, then use `/impl`.

4. **Code diff exists, no test changes** → suggest **test**
   - Check: `git diff main --name-only` shows source changes BUT no test file changes
   - Guidance: Use `/test <changed files>`.

5. **Tests exist, no review files** → suggest **review**
   - Check: Both source and test changes exist BUT no recent review in `.docs/reviews/` or `.backlog/active/*/quality-round-*.md`
   - Guidance: Use `/audit` to check all changes (code quality + security).

6. **Review done, uncommitted changes** → suggest **commit**
   - Check: Review files exist AND `git status --porcelain` shows uncommitted changes
   - Guidance: Use `/commit` to create a conventional commit, or `/ship` to commit + create PR.

Present the detection result with reasoning, including any ticket directory information from `.backlog/active/`. If the user specified a phase via `$ARGUMENTS`, skip detection and go directly to the guidance for that phase.

### 5. Summary Output

Print a concise summary:
- Current situation (branch, what's been done)
- Active tickets in `.backlog/active/` (list slug and available artifacts)
- If a YAML-frontmatter compact-state was parsed in Step 1, also list the `active_tickets` recorded at compact time (these are the tickets the user was focused on at the moment of compaction — they may differ from the current `.backlog/active/` listing if filesystem state has drifted)
- Detected phase and recommended next action
- Exact command sequence, e.g.:
  ```
  /clear
  /catchup  (optional, to recover context after clearing)
  /<next-command>
  ```

## Error Handling

- **No artifacts found at all**: Phase detection still works — defaults to suggesting **investigate** as the first step.
- **Researcher agent failure**: Report error but still proceed with phase detection using pre-computed context.
- **Ambiguous state**: Present detection result with reasoning, ask user to confirm or choose differently.
