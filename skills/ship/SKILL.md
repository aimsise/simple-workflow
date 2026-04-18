---
name: ship
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Commit current changes, create a PR, and optionally squash-merge.
  Combines commit + create-pr + merge into a single workflow.
  Use when the user wants to ship completed work.
disable-model-invocation: false
allowed-tools:
  # Claude Code
  - Skill
  - AskUserQuestion
  - Read
  - Write
  - Edit
  - "Bash(git add:*)"
  - "Bash(git commit:*)"
  - "Bash(git status:*)"
  - "Bash(git diff:*)"
  - "Bash(git log:*)"
  - "Bash(git push:*)"
  - "Bash(git checkout:*)"
  - "Bash(git pull:*)"
  - "Bash(git branch:*)"
  - "Bash(gh:*)"
  - "Bash(mv:*)"
  - "Bash(ls:*)"
  - "Bash(mkdir:*)"
  - "Bash(rmdir:*)"
  - "Bash(date:*)"
  # Copilot CLI
  - skill
  - view
  - create
  - edit
  - "shell(git add:*)"
  - "shell(git commit:*)"
  - "shell(git status:*)"
  - "shell(git diff:*)"
  - "shell(git log:*)"
  - "shell(git push:*)"
  - "shell(git checkout:*)"
  - "shell(git pull:*)"
  - "shell(git branch:*)"
  - "shell(gh:*)"
  - "shell(mv:*)"
  - "shell(ls:*)"
  - "shell(mkdir:*)"
  - "shell(rmdir:*)"
  - "shell(date:*)"
argument-hint: "[target-branch] [merge=true] [ticket-dir=<dir-name>]"
---

Ship the current changes: commit, create PR, and optionally merge.
User arguments: $ARGUMENTS

## Mandatory Skill Invocations

The following skill invocation is **contractual** — `/ship` MUST delegate to `/tune` via the Skill tool once a ticket has been moved to `.backlog/done/`. The rest of `/ship` (commit, push, PR creation) is performed directly via `git`/`gh` commands and is not a skill delegation contract; those are the skill's own implementation, not mandatory sub-skill calls. Any bypass of `/tune` is a contract violation and will be detected by the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `/tune` (Skill) | Phase 1 step 6 — only after a ticket was moved to `.backlog/done/` in step 5 | No knowledge-base pattern extraction from the completed ticket's `eval-round-*.md` / `quality-round-*.md`. The `/impl` Generator for the next ticket runs without updated `.simple-wf-knowledge/index.yaml` — degraded learning over time. Detected by absence of `/tune` invocation trace after a ticket-move in the skill invocation audit |

**Binding rules**:
- `MUST invoke /tune via the Skill tool` whenever a ticket was moved in step 5. Pass the ticket-dir name as the argument.
- `NEVER bypass /tune via direct manipulation` of `.simple-wf-knowledge/candidates.yaml` or `entries.yaml` from within `/ship`.
- If `/tune` itself fails, **do NOT stop the ship workflow** (the commit is already made and the ticket is already moved) — but the invocation MUST have been attempted. `Fail the /tune invocation attempt only if the Skill tool is unreachable; log the failure and continue.`

## phase-state.yaml write ownership

This skill writes ONLY to `phases.ship` plus the top-level status fields
(`current_phase`, `last_completed_phase`, `overall_status`). It MUST NOT
modify any other phase's section (`phases.create_ticket`, `phases.scout`,
`phases.impl`).

`phase-state.yaml` lives inside the ticket directory. When `/ship` moves
`.backlog/active/{ticket-dir}` to `.backlog/done/{ticket-dir}` via `mv`, the
state file moves with it. `/ship` MUST NOT delete `phase-state.yaml` at any
point — it is the permanent historical record that stays in
`.backlog/done/{ticket-dir}/` forever.

Reference: `skills/create-ticket/references/phase-state-schema.md`.

## Argument Parsing

Parse `$ARGUMENTS` for positional arguments:
- First argument: target branch name (default: `<default-branch>` — see pre-computed context above). If the first argument is `true` or `merge=true`, treat it as the merge flag and use `<default-branch>` as target.
- Second argument: `merge=true` or `true` to enable squash-merge after PR creation (default: no merge).
- `ticket-dir=<dir-name>`: Optional key=value argument specifying the ticket directory name (directory name only, not a full path — e.g., `003-fix-login`). Because this uses key=value syntax, it is position-independent and does not affect parsing of the positional arguments (target-branch, merge).

Examples:
- `/ship` -> commit + PR to `<default-branch>` (e.g. main, master, develop)
- `/ship develop` -> commit + PR to develop
- `/ship merge=true` -> commit + PR to `<default-branch>` + squash-merge
- `/ship <default-branch> true` -> commit + PR to `<default-branch>` + squash-merge
- `/ship develop merge=true` -> commit + PR to develop + squash-merge
- `/ship main ticket-dir=003-fix-login` -> commit + PR to main, using ticket directory `003-fix-login`

## Pre-compute Resilience Contract

All pre-compute bash commands below return fallback values on failure and never
halt `/ship` execution. The orchestrating agent is responsible for reading each
pre-compute result and deciding commit/push strategy from the reported state
(e.g., `(detached HEAD)`, `[no commits yet]`, `[no remote — skipped]`). A
failing pre-compute must never be treated as a reason to abandon `/ship` and
fall back to ad-hoc git commands; instead, the agent interprets the fallback
marker and routes the workflow accordingly (skip push when remote is absent,
skip diff vs default branch when there is no commit history, etc.).

## Pre-computed Context

Current branch:
!`git branch --show-current 2>/dev/null | grep . || echo "(detached HEAD or no commits)"`

Default branch:
!`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main`

Current state:
!`git status --short 2>/dev/null || echo "[git status unavailable]"`

Staged diff:
!`git diff --cached 2>/dev/null || echo "[no commits yet — nothing staged]"`

Unstaged diff summary:
!`git diff --stat 2>/dev/null || echo "[no commits yet — cannot diff against HEAD]"`

Remote configured:
!`git remote get-url origin >/dev/null 2>&1 && echo "yes" || echo "no"`

Diff stats vs default branch:
!`git diff origin/$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main) --stat 2>/dev/null || echo "[no remote — skipped]"`

Recent commits for style reference:
!`git log --oneline -10 2>/dev/null || echo "[no commit history]"`

Commits ahead of default branch:
!`git log origin/$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main)..HEAD --oneline 2>/dev/null || echo "[no remote — skipped]"`

## Instructions

**Note**: Throughout this skill, `<default-branch>` denotes the repository's default branch, taken from the `Default branch:` value in the pre-computed context above (which resolves `git symbolic-ref refs/remotes/origin/HEAD` and falls back to `main` when `origin/HEAD` is not set). Use this resolved value wherever the rules below mention `<default-branch>` — never hardcode `main`.

## Phase 1: Commit

1. **Pre-flight check**: Run `git status --short` to detect any changes. If there are no changes at all (nothing staged, nothing unstaged, no untracked files), print "No changes to ship." and stop immediately.

2. **Sensitive file warning**: Inspect the working tree for files matching `.env*`, `*credentials*`, `*secret*`, `*.key`, `*.pem`. If any such files are present (staged, unstaged, or untracked), warn the user explicitly before proceeding. The user may then decide whether to abort or continue.

3. **Create commit**: Handle staging and conventional commit creation directly:
   a. Run `git diff --stat` and `git diff --cached --stat` to understand the changes.
   b. If there are unstaged changes, determine which files to stage based on the implementation context. In autopilot mode (autopilot-policy.yaml exists), stage all modified/new files relevant to the ticket, **except** files under `.backlog/briefs/` (e.g., `autopilot-state.yaml`, `brief.md`, `split-plan.md`) — these are pipeline management files, not ticket artifacts and must not be committed as part of ticket work. This exclusion is defense-in-depth: normally `.gitignore` prevents these files from being tracked, but if `.gitignore` is missing or misconfigured, they should still never be staged. In interactive mode, use `AskUserQuestion` to ask which files to stage. **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error, stage all modified/new files (same as autopilot mode, including the same `.backlog/briefs/` exclusion).
   c. Stage the selected files with `git add`.
   d. Generate a conventional commit message (feat/fix/improve/chore/docs/test/perf) focused on the "why", using `git log --oneline -5` for style reference.
   e. Create the commit using a HEREDOC.
   f. Run `git status` to verify the commit succeeded.

4. **Post-commit verification**: Run `git status` to confirm a commit was actually created. If the working tree is still dirty or no new commit exists (`git log -1 --format=%H` is unchanged from before), report the failure and stop.

5. **Ticket completion**: If `.backlog/active/` exists, list its contents. Determine `ticket-dir` using the following priority:
   - **Explicit `ticket-dir=` argument**: If `ticket-dir=<dir-name>` was provided in the arguments, check whether `.backlog/active/{dir-name}` exists. If it exists, set `ticket-dir` to that value and skip branch name matching. If it does **not** exist, print a WARNING: "ticket-dir '{dir-name}' not found in .backlog/active/ — falling back to branch name matching." and proceed to the fallback below.
   - **Fallback — branch name matching**: For each directory in `.backlog/active/`, extract the slug portion by stripping the leading `NNN-` prefix (the initial sequence of digits followed by a hyphen, e.g., `001-add-search-feature` → `add-search-feature`). Check if the branch name contains this slug portion. If a match is found, set `ticket-dir` to the full directory name (including the numeric prefix).
   - If neither method finds a match, skip silently.

   Once `ticket-dir` is determined:

   a. **Begin ship phase (state update — only when `.backlog/active/{ticket-dir}/phase-state.yaml` exists)**: Read the state file and update ONLY the following fields (read-modify-write; leave every other section untouched):
      - `phases.ship.status: in-progress`
      - `phases.ship.started_at: {now}` (ISO-8601 UTC, via `date -u +%Y-%m-%dT%H:%M:%SZ`)
      - `current_phase: ship`
   b. **Write destination-anchored phase-state.yaml FIRST, then move remaining contents** — this ordering closes the race window where an interruption between the `mv` and the `ticket_dir:` rewrite would strand the state file at the wrong self-reference (Reviewer B Finding 7). Concretely:
      1. Compute the new `ticket_dir: .backlog/done/{ticket-dir}` value in memory from the state file loaded in 5a.
      2. Ensure the destination directory exists: `mkdir -p .backlog/done/{ticket-dir}`.
      3. Write the updated phase-state.yaml directly to `.backlog/done/{ticket-dir}/phase-state.yaml` with the new `ticket_dir:` value already serialized inside. All other fields from step 5a remain as they were in the source file. **At the end of this sub-step the destination-path state file exists and is self-consistent, even if the process is interrupted before sub-step 5.**
      4. Move the remaining contents of the source directory: for each file in `.backlog/active/{ticket-dir}/` other than `phase-state.yaml`, `mv` it to `.backlog/done/{ticket-dir}/`. Do NOT copy or re-write `phase-state.yaml` here — it was already written in sub-step 3 above.
      5. Remove the now-empty source directory: `rmdir .backlog/active/{ticket-dir}` (or `mv`-then-`rmdir` equivalent). If `rmdir` fails because the directory is not empty, list the unexpected remaining files and stop — the state is recoverable but needs manual attention.
   c. Because phase-state.yaml was serialized to its destination path in sub-step 5.b.3 before any other file move, the skill does NOT need a separate post-move `ticket_dir:` rewrite step. The ordering in 5b is the mitigation for the pre-PR-E race where `mv`-then-rewrite left a half-migrated state file on interruption.

6. **Knowledge base tuning** (only after a ticket was moved in step 5): **MUST invoke `/tune` via the Skill tool**, passing the completed ticket-dir name as the argument. This extracts reusable patterns from the ticket's evaluation logs into the project knowledge base. **NEVER bypass /tune** via direct writes to `.simple-wf-knowledge/*.yaml` from within `/ship`. If `/tune` itself fails during execution, log the failure but do **not** stop the ship workflow — the commit is already created and the ticket is already moved. Fail the ship workflow only if the Skill tool itself is unreachable (contract-level bypass).

Proceed to Phase 2.

## Phase 2: Create PR

7. **Remote availability check**: Check the `Remote configured:` value from pre-computed context. If it is `no` (no remote origin configured), print "Commit complete. No remote configured — skipping push and PR creation." and stop. Do NOT attempt push, PR creation, or merge.

8. Run `gh auth status`. If not authenticated, tell the user to run `gh auth login` and stop.

9. **Review gate**: Check for recent code review:
    - If there is a completed ticket (`{ticket-dir}` — now in `.backlog/done/` after step 5), run `ls -t .backlog/done/{ticket-dir}/quality-round-*.md 2>/dev/null | head -1` to find the most recent review file
    - If there is no ticket, skip the review gate (no check needed)
    - If a review file exists, compare its modification time with the last commit time
    - If NO review file exists, or the review predates the last code-changing commit:
      - **Autopilot policy check**: Check if `.backlog/done/{ticket-dir}/autopilot-policy.yaml` exists.
        - If it exists, read `gates.ship_review_gate.action`:
          - If `proceed_if_eval_passed`: Check the latest `eval-round-*.md` in the ticket directory. Read its Status line.
            - If Status is PASS or PASS-WITH-CAVEATS: proceed automatically. Print `[AUTOPILOT-POLICY] gate=ship_review_gate action=proceed_if_eval_passed eval_status={status}`. Append "[shipped without /audit, autopilot policy applied]" to the PR body.
            - If Status is FAIL or no eval-round exists: stop (safety valve — do not ship code that failed AC evaluation). Print `[AUTOPILOT-POLICY] gate=ship_review_gate action=stop reason=eval_status_not_pass`.
          - If `stop`: stop. Print `[AUTOPILOT-POLICY] gate=ship_review_gate action=stop`.
        - If it does not exist, proceed with the existing interactive flow below.
      Print "No recent code review found. Recommended: run /audit before shipping."
      Ask the user: "Proceed without review? (yes/no)"
      - If "no" → stop
      - If "yes" → proceed, and append "[shipped without /audit]" to the PR body in step 14

10. Determine the target branch from arguments (default: `<default-branch>` — obtained from the `Default branch:` pre-computed context above). If the target is not `<default-branch>`, re-run `git log` and `git diff` against the actual target branch (the pre-computed context above is always against `<default-branch>`).
11. Check commits ahead of target: `git log origin/<target>..HEAD --oneline`. If there are no commits ahead, print "No commits ahead of target branch." and stop.
12. Run `gh pr list --head <current-branch> --state open` to check for an existing PR. If one exists, capture the PR URL, print it, and skip to Phase 3 (if merge is enabled) or stop.
13. Push with `git push origin HEAD`. On failure, show the error and stop.
14. Generate PR title (conventional commit style, single line) and body (summarize changes and scope) from the commit log and diff.
15. Create the PR with `gh pr create --base <target-branch> --head <current-branch> --title "<title>" --body "<body>"`.
15a. **Complete ship phase (state update — only when a ticket was moved in step 5 AND `.backlog/done/{ticket-dir}/phase-state.yaml` exists)**: Read the state file at `.backlog/done/{ticket-dir}/phase-state.yaml` and update ONLY the following fields (read-modify-write; leave every other section untouched):
     - `phases.ship.status: completed`
     - `phases.ship.completed_at: {now}` (ISO-8601 UTC, recomputed at this step)
     - `phases.ship.artifacts.pr_url: <pr-url>` (the URL returned by `gh pr create` in step 15, or the URL of the existing PR captured in step 12 if one was found)
     - `last_completed_phase: ship`
     - `current_phase: done`
     - `overall_status: done`

     Do NOT modify `phases.create_ticket`, `phases.scout`, or `phases.impl`. The state file remains in place inside `.backlog/done/{ticket-dir}/phase-state.yaml` as the permanent record — NEVER delete it.

     If an existing PR was captured in step 12 (Phase 2 gate), run this state update at that point too, so the ticket is correctly finalized even on re-runs.
16. Print the PR URL. If merge is not enabled, stop here. Note: when squash-merged, the PR title becomes the commit message on the target branch.

## Phase 3: Merge (only when merge=true)

17. Attempt `gh pr merge <pr-url> --squash --delete-branch`.
18. If merge fails due to pending CI checks,
    - **Autopilot policy check**: Check if `.backlog/done/{ticket-dir}/autopilot-policy.yaml` exists.
      - If it exists, read `gates.ship_ci_pending`:
        - If `action` is `wait`: Run `gh pr checks <pr-number> --watch` with a timeout of `timeout_minutes` minutes. Print `[AUTOPILOT-POLICY] gate=ship_ci_pending action=wait timeout={timeout_minutes}m`.
          - If checks pass within timeout: retry the merge.
          - If timeout expires: follow `on_timeout` action (`stop` by default). Print `[AUTOPILOT-POLICY] gate=ship_ci_pending action=on_timeout`.
        - If `action` is `stop`: stop. Print `[AUTOPILOT-POLICY] gate=ship_ci_pending action=stop`.
      - If it does not exist, proceed with the existing interactive flow below.
    ask the user to choose one of:
    - **Wait**: Run `gh pr checks <pr-number> --watch`, then retry the merge.
    - **Force**: Run `gh pr merge <pr-url> --squash --delete-branch --admin` to bypass checks. **WARNING: This bypasses CI checks and risks merging untested code. Confirm with the user before proceeding.** Note: requires admin permissions on the repository.
    - **Skip**: Stop without merging. Print the PR URL for manual follow-up.
19. After successful merge, sync local: `git checkout <target-branch> && git pull origin <target-branch>`.
20. Print summary: merged PR URL, deleted branch name, current local state. If a ticket was moved in step 5, also include "Ticket moved to .backlog/done/{ticket-dir}".

21. **Emit SW-CHECKPOINT block**. After the final summary in step 20 (Phase 3), or after step 16 (Phase 2 completion when `merge=true` is not set), or after any early-stop point (Phase 1 `No changes to ship.`, Phase 2 `No remote configured`, `gh auth` failure, push failure, `No commits ahead`, `Existing PR`, etc.), append the following `## [SW-CHECKPOINT]` block as the **final** section of the `/ship` response.

    Output ordering requirements:

    - The block MUST be the last thing shown to the user. It MUST come AFTER the PR URL print, the merge summary, and any error / stop messages.
    - Emit this block exactly once per `/ship` invocation, at the very end — regardless of which stop point was reached.
    - Do NOT omit it on failure paths. On `No changes to ship.`, push failure, `gh auth` failure, etc., still emit the block with `artifacts: []` on a single line and `next_recommended: ""`.

    Rendering rules:

    - Use the literal fenced block below. Replace only the placeholders inside `{...}`.
    - `phase:` is always the literal string `ship`.
    - `ticket:` is `.backlog/done/{ticket-dir}` when a ticket was moved in step 5 (and is now in `done/`); otherwise `.backlog/active/{ticket-dir}` when a ticket was detected but not yet moved (early failure before step 5); otherwise the bare string `none` (no quotes) when no ticket was matched.
    - `artifacts:` lists repo-relative paths to files `/ship` caused to be created/updated in this invocation. On the success path this is typically the PR URL (recorded under `phases.ship.artifacts.pr_url`) plus the `phase-state.yaml` (now at `.backlog/done/{ticket-dir}/phase-state.yaml`). The commit SHA / PR URL may appear as an entry (e.g., `- {pr-url}`). On a failure path with no artifacts, emit `artifacts: []` on a single line.
    - `next_recommended:` is always the empty string `""` for `/ship` because the ticket is complete (there is no next phase).
    - `context_advice:` is the literal English sentence shown below, verbatim. Never translate, never paraphrase, never omit — include it even on failure paths.

    ```
    ## [SW-CHECKPOINT]
    phase: ship
    ticket: {ticket-dir or "none"}
    artifacts:
      - {relative path to phase-state.yaml}
      - {PR URL or commit SHA}
    next_recommended: ""
    context_advice: "Intermediate tool outputs from this phase remain in the main session context. If you plan to run the next phase manually, run `/clear` first and then `/catchup` to recover position with minimal token spend."
    ```

## Error Handling

- **No changes**: Print "No changes to ship." and stop.
- **No remote**: Print "Commit complete. No remote configured — skipping push and PR creation." and stop after Phase 1.
- **No commits ahead**: Print "No commits ahead of target branch." and stop.
- **gh auth failure**: Print `gh auth login` instructions and stop.
- **Push failure**: Show the error and stop.
- **Existing PR (merge disabled)**: Show the PR URL and stop.
- **Existing PR (merge enabled)**: Capture the PR URL and proceed to Phase 3.
- **CI checks pending**: Ask user to choose Wait / Force / Skip (Phase 3 step 18).
- **Force merge failure (no admin)**: Inform user, keep PR open, print URL.
- **Merge conflict**: Print details, keep PR open, stop.
- **Merge failure (any reason)**: Keep PR open, print PR URL for manual follow-up.
