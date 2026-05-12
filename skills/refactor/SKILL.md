---
name: refactor
description: >-
  Plans and executes a refactoring with safety checks by delegating to the
  planner and code-reviewer agents, then iterating implementation + review up
  to three rounds. Use when (1) the user runs `/refactor {target}` directly to
  refactor a specific function, file, or pattern, (2) refactoring is invoked
  inside a ticket workflow with `ticket-dir={dir-name}` so the review artifact
  lands at `{ticket-dir}/quality-refactor-{n}.md`, or (3) the user wants the
  refactor protected by a `backup/pre-refactor-{timestamp}` branch and a
  bounded review loop. Use only when the user explicitly asks to refactor
  code. Triggers on "/refactor", "refactor code", "restructure",
  "extract method", "rename", "clean up".
disable-model-invocation: true
allowed-tools:
  # Claude Code
  - Agent
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - "Bash(git:*)"
  - "Bash(npm:*)"
  - "Bash(npx:*)"
  - "Bash(yarn:*)"
  - "Bash(pnpm:*)"
  - "Bash(bun:*)"
  - "Bash(pytest:*)"
  - "Bash(cargo:*)"
  - "Bash(go :*)"
  - "Bash(make:*)"
  - "Bash(gradle:*)"
  - "Bash(./gradlew:*)"
  - "Bash(mvn:*)"
  - "Bash(./mvnw:*)"
  - "Bash(sbt:*)"
  - "Bash(dotnet test:*)"
  - "Bash(dotnet build:*)"
  - "Bash(bundle exec:*)"
  - "Bash(rake:*)"
  - "Bash(mix:*)"
  - "Bash(swift test:*)"
  - "Bash(swift build:*)"
  - "Bash(flutter test:*)"
  - "Bash(dart test:*)"
  - "Bash(composer:*)"
  - "Bash(./vendor/bin/phpunit:*)"
  # Copilot CLI
  - task
  - view
  - glob
  - grep
  - create
  - edit
  - "shell(git:*)"
  - "shell(npm:*)"
  - "shell(npx:*)"
  - "shell(yarn:*)"
  - "shell(pnpm:*)"
  - "shell(bun:*)"
  - "shell(pytest:*)"
  - "shell(cargo:*)"
  - "shell(go :*)"
  - "shell(make:*)"
  - "shell(gradle:*)"
  - "shell(./gradlew:*)"
  - "shell(mvn:*)"
  - "shell(./mvnw:*)"
  - "shell(sbt:*)"
  - "shell(dotnet test:*)"
  - "shell(dotnet build:*)"
  - "shell(bundle exec:*)"
  - "shell(rake:*)"
  - "shell(mix:*)"
  - "shell(swift test:*)"
  - "shell(swift build:*)"
  - "shell(flutter test:*)"
  - "shell(dart test:*)"
  - "shell(composer:*)"
  - "shell(./vendor/bin/phpunit:*)"
argument-hint: "<refactoring target and goal> [ticket-dir=<dir-name>]"
---

Plan and execute refactoring: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS` for the following:
- `ticket-dir=<dir-name>` (case-insensitive key): Optional ticket directory name (directory name only, not a full path — e.g., `003-fix-login`). When provided, this value is used in Step 1b to construct the full path `.simple-workflow/backlog/active/{dir-name}` instead of inferring the ticket directory from the branch name.
- All other tokens are treated as the refactoring target and goal description.

Current state:
!`git status --short`
!`git diff --stat`

Current branch:
!`git branch --show-current`

Active tickets:
!`ls -d .simple-workflow/backlog/active/*/ 2>/dev/null || echo "(none)"`

Invocation policy: Do not auto-invoke. `disable-model-invocation: true` is intentional because `/refactor` performs destructive changes (file edits, possible structural moves) and creates a `backup/pre-refactor-{timestamp}` branch as the only rollback point. The safety design assumes the user has made an explicit decision to refactor; chain-call from another skill is not supported without re-evaluating that assumption. Manual `/refactor <target>` invocation is the sole supported entry point. Flipping `disable-model-invocation` to `false` is not appropriate without re-evaluating the safety checkpoint design (in particular the backup-branch contract in Phase 2 Step 3b and the bounded review loop in Phase 3).

## Mandatory Skill Invocations

`/refactor` is a two-agent orchestrator: it MUST delegate planning to the `planner` agent and quality review to the `code-reviewer` agent. The orchestrator itself writes no plan content and produces no review report; its role is argument parsing, ticket detection, backup-branch creation, implementation orchestration, and loop control.

| Invocation Target | When | Skip consequence |
|---|---|---|
| `planner` agent (Agent tool) | Phase 1 Step 1 — always, before user approval is sought | No refactoring plan exists; Phase 2 has nothing to seek approval for; Phase 3 has no scope to implement against. Detected by the absence of a planner agent return value in the conversation transcript. |
| `code-reviewer` agent (Agent tool) | Phase 3 Step 6 — each iteration of the implement → verify → review loop, up to 3 iterations | Quality review SKIPPED; Critical and Warning findings cannot be detected; loop exit condition `Critical = 0 AND Warning = 0` cannot be evaluated, so Critical bugs may slip through unverified. Detected by absence of the configured output file (`{ticket-dir}/quality-refactor-{n}.md` or the default `.simple-workflow/docs/reviews/{topic}.md`). |

**Binding rules**:
- `MUST invoke the planner agent` in Phase 1 Step 1 before presenting any plan summary to the user. The orchestrator MUST NOT fabricate a plan in lieu of the planner return value.
- `MUST invoke the code-reviewer agent` in every iteration of Phase 3 Step 6 (up to the 3-iteration ceiling). The orchestrator MUST NOT skip review by self-judging "no issues".
- `NEVER bypass the code-reviewer` by treating an Agent-tool infrastructure failure as a clean review — Phase 3 Step 7 defines the explicit `AskUserQuestion` fallback (`stop` / `continue without review`) and the non-interactive default-to-stop; bypass is allowed only via that documented path.
- `Fail the task immediately` when the planner agent cannot be invoked at all (no fallback exists — Phase 2 backup branch creation cannot proceed without a plan). Print the failure reason and stop.

## Instructions

### Phase 1: Planning
1. Spawn the **planner** agent to create a refactoring plan
1b. **Ticket detection**: Get the current branch name and active ticket list from the pre-computed context above. Determine `ticket-dir` using the following priority:
   - **Explicit `ticket-dir=` argument**: If `ticket-dir=<dir-name>` was provided in the arguments, check whether `.simple-workflow/backlog/active/{dir-name}` exists. If it exists, set `ticket-dir` to `.simple-workflow/backlog/active/{dir-name}` and skip branch name matching. If it does **not** exist, print a WARNING: "ticket-dir '{dir-name}' not found in .simple-workflow/backlog/active/ — falling back to branch name matching." and proceed to the fallback below.
   - **Fallback — branch name matching**: For each directory in `.simple-workflow/backlog/active/`, extract the slug portion by stripping the leading `NNN-` prefix (the initial sequence of digits followed by a hyphen, e.g., `001-add-search-feature` → `add-search-feature`). Check if the branch name contains this slug portion. If a match is found, set `ticket-dir` to `.simple-workflow/backlog/active/{full-directory-name}` (including the numeric prefix).
2. Present the plan summary to the user

### Phase 2: Approval
3. Ask the user to approve before proceeding. If rejected, gather feedback and re-plan (return to Phase 1).

3b. **Safety checkpoint**: After user approval, create a backup branch:
    - Run `git branch backup/pre-refactor-$(date +%Y%m%d-%H%M%S)` to save current state
    - Print: "Backup branch created: backup/pre-refactor-{timestamp}. To rollback: git checkout backup/pre-refactor-{timestamp}"

### Phase 3: Implementation + Review Loop (max 3 iterations)
4. Implement changes according to the plan
5. Run verification:
   - Run the project's test command (as defined in CLAUDE.md or project conventions)
   - Run the project's lint command (as defined in CLAUDE.md or project conventions)
6. Spawn the **code-reviewer** agent to review all changes:
   - If `ticket-dir` is set: specify output path as `{ticket-dir}/quality-refactor-{n}.md` where {n} is the iteration number
   - If `ticket-dir` is not set: let the code-reviewer use its default (`.simple-workflow/docs/reviews/{topic}.md`)
7. Evaluate review results:
   - **code-reviewer Status: failed or partial** (review infrastructure failure):
     Use `AskUserQuestion` to ask "code-reviewer failed. How do you want to proceed?" with options:
     - "stop": stop the skill immediately. Print "Stopped by user after code-reviewer failure. Refactoring changes remain in working tree." and exit.
     - "continue without review": proceed to Phase 4 without quality verification, noting "Quality review SKIPPED (code-reviewer failed)" in the final summary.
     - **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), default to **stop**. Print "Stopped: /refactor cannot proceed without code-reviewer in non-interactive mode. Refactoring changes remain in working tree. Re-run in interactive mode." and exit. Do NOT hang waiting for input.
     - **Never** silently treat code-reviewer failure as "no issues" — that would let Critical bugs slip through unverified.
   - **Critical = 0 AND Warning = 0** -> exit loop, proceed to Phase 4
   - **Issues found** -> fix the reported issues, then return to step 5
   - **Iteration 3 reached** -> exit loop with remaining issues noted

### Phase 4: Final Report
8. Report summary:
   - Changes made (files modified, lines changed)
   - Review iterations completed
   - Remaining issues (if loop exited at max iterations)
   - Test and lint final status

`/refactor` does NOT emit a `[SW-CHECKPOINT]` block. The Final Report above is the canonical end-of-skill artifact; downstream tooling that watches for checkpoint markers should ignore `/refactor` invocations. See `skills/create-ticket/references/sw-checkpoint-template.md` for the canonical block contract and the list of skills that DO emit it.

## Error Handling

- **Empty arguments**: Print `Usage: /refactor <refactoring target and goal> [ticket-dir=<dir-name>]` and stop.
- **planner agent failure** (Phase 1 Step 1): Print the failure reason and stop before Phase 2. Do not create a backup branch when there is no plan to back up against.
- **Backup branch failure** (Phase 2 Step 3b): If `git branch backup/pre-refactor-$(date +%Y%m%d-%H%M%S)` fails (e.g. duplicate timestamp under rapid re-runs, working-tree conflict), print the error and stop before Phase 3. Do not proceed with destructive implementation without a successful safety branch.
- **code-reviewer agent failure** (Phase 3 Step 6): Handled inline by Phase 3 Step 7 — `AskUserQuestion` prompts the user with `stop` / `continue without review`. In non-interactive environments (`claude -p` / CI), the default is `stop`. Never silently treat the failure as "no issues found".
- **Loop exit at max iterations** (Phase 3 Step 7): If iteration 3 is reached with remaining Critical or Warning findings, exit the loop and report the remaining findings in Phase 4 Final Report. Do not silently retry beyond the 3-iteration ceiling.
