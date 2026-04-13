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
  - "Bash(date:*)"
  # Copilot CLI
  - skill
  - view
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
  - "shell(date:*)"
argument-hint: "[target-branch] [merge=true]"
---

Ship the current changes: commit, create PR, and optionally merge.
User arguments: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS` for positional arguments:
- First argument: target branch name (default: `<default-branch>` — see pre-computed context above). If the first argument is `true` or `merge=true`, treat it as the merge flag and use `<default-branch>` as target.
- Second argument: `merge=true` or `true` to enable squash-merge after PR creation (default: no merge).

Examples:
- `/ship` -> commit + PR to `<default-branch>` (e.g. main, master, develop)
- `/ship develop` -> commit + PR to develop
- `/ship merge=true` -> commit + PR to `<default-branch>` + squash-merge
- `/ship <default-branch> true` -> commit + PR to `<default-branch>` + squash-merge
- `/ship develop merge=true` -> commit + PR to develop + squash-merge

## Pre-computed Context

Current branch:
!`git branch --show-current`

Default branch:
!`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main`

Current state:
!`git status --short`

Staged diff:
!`git diff --cached`

Unstaged diff summary:
!`git diff --stat`

Diff stats vs default branch:
!`git diff origin/$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main) --stat`

Recent commits for style reference:
!`git log --oneline -10`

Commits ahead of default branch:
!`git log origin/$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main)..HEAD --oneline`

## Instructions

**Note**: Throughout this skill, `<default-branch>` denotes the repository's default branch, taken from the `Default branch:` value in the pre-computed context above (which resolves `git symbolic-ref refs/remotes/origin/HEAD` and falls back to `main` when `origin/HEAD` is not set). Use this resolved value wherever the rules below mention `<default-branch>` — never hardcode `main`.

## Phase 1: Commit

1. **Pre-flight check**: Run `git status --short` to detect any changes. If there are no changes at all (nothing staged, nothing unstaged, no untracked files), print "No changes to ship." and stop immediately.

2. **Sensitive file warning**: Inspect the working tree for files matching `.env*`, `*credentials*`, `*secret*`, `*.key`, `*.pem`. If any such files are present (staged, unstaged, or untracked), warn the user explicitly before proceeding. The user may then decide whether to abort or continue.

3. **Create commit**: Handle staging and conventional commit creation directly:
   a. Run `git diff --stat` and `git diff --cached --stat` to understand the changes.
   b. If there are unstaged changes, determine which files to stage based on the implementation context. In autopilot mode (autopilot-policy.yaml exists), stage all modified/new files relevant to the ticket. In interactive mode, use `AskUserQuestion` to ask which files to stage. **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error, stage all modified/new files (same as autopilot mode).
   c. Stage the selected files with `git add`.
   d. Generate a conventional commit message (feat/fix/improve/chore/docs/test/perf) focused on the "why", using `git log --oneline -5` for style reference.
   e. Create the commit using a HEREDOC.
   f. Run `git status` to verify the commit succeeded.

4. **Post-commit verification**: Run `git status` to confirm a commit was actually created. If the working tree is still dirty or no new commit exists (`git log -1 --format=%H` is unchanged from before), report the failure and stop.

5. **Ticket completion**: If `.backlog/active/` exists, list its contents. Match the current branch name against active ticket directories. For each directory in `.backlog/active/`, extract the slug portion by stripping the leading `NNN-` prefix (the initial sequence of digits followed by a hyphen, e.g., `001-add-search-feature` → `add-search-feature`). Check if the branch name contains this slug portion. If a match is found, set `ticket-dir` to the full directory name (including the numeric prefix), then run `mkdir -p .backlog/done && mv .backlog/active/{ticket-dir} .backlog/done/{ticket-dir}`. If no match, skip silently.

6. **Knowledge base tuning** (only after a ticket was moved in step 5): Invoke `/tune` via the Skill tool, passing the completed ticket-dir name as the argument. This extracts reusable patterns from the ticket's evaluation logs into the project knowledge base. If `/tune` fails, log the failure but do **not** stop the ship workflow — the commit is already created and the ticket is already moved.

Proceed to Phase 2.

## Phase 2: Create PR

7. Run `gh auth status`. If not authenticated, tell the user to run `gh auth login` and stop.

8. **Review gate**: Check for recent code review:
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
      - If "yes" → proceed, and append "[shipped without /audit]" to the PR body in step 13

9. Determine the target branch from arguments (default: `<default-branch>` — obtained from the `Default branch:` pre-computed context above). If the target is not `<default-branch>`, re-run `git log` and `git diff` against the actual target branch (the pre-computed context above is always against `<default-branch>`).
10. Check commits ahead of target: `git log origin/<target>..HEAD --oneline`. If there are no commits ahead, print "No commits ahead of target branch." and stop.
11. Run `gh pr list --head <current-branch> --state open` to check for an existing PR. If one exists, capture the PR URL, print it, and skip to Phase 3 (if merge is enabled) or stop.
12. Push with `git push origin HEAD`. On failure, show the error and stop.
13. Generate PR title (conventional commit style, single line) and body (summarize changes and scope) from the commit log and diff.
14. Create the PR with `gh pr create --base <target-branch> --head <current-branch> --title "<title>" --body "<body>"`.
15. Print the PR URL. If merge is not enabled, stop here. Note: when squash-merged, the PR title becomes the commit message on the target branch.

## Phase 3: Merge (only when merge=true)

16. Attempt `gh pr merge <pr-url> --squash --delete-branch`.
17. If merge fails due to pending CI checks,
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
18. After successful merge, sync local: `git checkout <target-branch> && git pull origin <target-branch>`.
19. Print summary: merged PR URL, deleted branch name, current local state. If a ticket was moved in step 5, also include "Ticket moved to .backlog/done/{ticket-dir}".

## Error Handling

- **No changes**: Print "No changes to ship." and stop.
- **No commits ahead**: Print "No commits ahead of target branch." and stop.
- **gh auth failure**: Print `gh auth login` instructions and stop.
- **Push failure**: Show the error and stop.
- **Existing PR (merge disabled)**: Show the PR URL and stop.
- **Existing PR (merge enabled)**: Capture the PR URL and proceed to Phase 3.
- **CI checks pending**: Ask user to choose Wait / Force / Skip (Phase 3 step 17).
- **Force merge failure (no admin)**: Inform user, keep PR open, print URL.
- **Merge conflict**: Print details, keep PR open, stop.
- **Merge failure (any reason)**: Keep PR open, print PR URL for manual follow-up.
