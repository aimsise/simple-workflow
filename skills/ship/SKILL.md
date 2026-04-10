---
name: ship
description: >-
  Commit current changes, create a PR, and optionally squash-merge.
  Combines commit + create-pr + merge into a single workflow.
  Use when the user wants to ship completed work.
disable-model-invocation: true
allowed-tools:
  - Skill
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
!`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main`

Current state:
!`git status --short`

Staged diff:
!`git diff --cached`

Unstaged diff summary:
!`git diff --stat`

Diff stats vs default branch:
!`git diff origin/$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main) --stat`

Recent commits for style reference:
!`git log --oneline -10`

Commits ahead of default branch:
!`git log origin/$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)..HEAD --oneline`

## Instructions

**Note**: Throughout this skill, `<default-branch>` denotes the repository's default branch, taken from the `Default branch:` value in the pre-computed context above (which resolves `git symbolic-ref refs/remotes/origin/HEAD` and falls back to `main` when `origin/HEAD` is not set). Use this resolved value wherever the rules below mention `<default-branch>` — never hardcode `main`.

## Phase 1: Commit

1. **Pre-flight check**: Run `git status --short` to detect any changes. If there are no changes at all (nothing staged, nothing unstaged, no untracked files), print "No changes to ship." and stop immediately.

2. **Sensitive file warning**: Inspect the working tree for files matching `.env*`, `*credentials*`, `*secret*`, `*.key`, `*.pem`. If any such files are present (staged, unstaged, or untracked), warn the user explicitly before proceeding. The user may then decide whether to abort or continue.

3. **Delegate to /commit**: Invoke the `/commit` skill via the Skill tool to handle staging and conventional commit creation. Pass any user-provided commit message hint as the argument. The `/commit` skill will:
   - Show the user the changes
   - Ask which files to stage (if there are unstaged changes)
   - Generate a conventional commit message (feat/fix/improve/chore/docs/test/perf) focused on the "why"
   - Create the commit using a HEREDOC
   - Verify the commit succeeded with `git status`

4. **Post-commit verification**: After the Skill call returns, run `git status` to confirm a commit was actually created. If the working tree is still dirty or no new commit exists (`git log -1 --format=%H` is unchanged from before), report the failure and stop. Otherwise, proceed to Phase 2.

## Phase 2: Create PR

6. Run `gh auth status`. If not authenticated, tell the user to run `gh auth login` and stop.

6b. **Review gate**: Check for recent code review:
    - If there is an active ticket (`.backlog/active/{slug}/`), run `ls -t .backlog/active/{slug}/quality-round-*.md 2>/dev/null | head -1` to find the most recent review file in that ticket directory
    - If there is no active ticket, skip the review gate (no check needed)
    - If a review file exists, compare its modification time with the last commit time
    - If NO review file exists, or the review predates the last code-changing commit:
      Print "No recent code review found. Recommended: run /audit before shipping."
      Ask the user: "Proceed without review? (yes/no)"
      - If "no" → stop
      - If "yes" → proceed, and append "[shipped without /audit]" to the PR body in step 11

7. Determine the target branch from arguments (default: `<default-branch>` — obtained from the `Default branch:` pre-computed context above). If the target is not `<default-branch>`, re-run `git log` and `git diff` against the actual target branch (the pre-computed context above is always against `<default-branch>`).
8. Check commits ahead of target: `git log origin/<target>..HEAD --oneline`. If there are no commits ahead, print "No commits ahead of target branch." and stop.
9. Run `gh pr list --head <current-branch> --state open` to check for an existing PR. If one exists, capture the PR URL, print it, and skip to Phase 3 (if merge is enabled) or stop.
10. Push with `git push origin HEAD`. On failure, show the error and stop.
11. Generate PR title (conventional commit style, single line) and body (summarize changes and scope) from the commit log and diff.
12. Create the PR with `gh pr create --base <target-branch> --head <current-branch> --title "<title>" --body "<body>"`.
13. Print the PR URL. If merge is not enabled, stop here. Note: when squash-merged, the PR title becomes the commit message on the target branch.

## Phase 3: Merge (only when merge=true)

14. Attempt `gh pr merge <pr-url> --squash --delete-branch`.
15. If merge fails due to pending CI checks, ask the user to choose one of:
    - **Wait**: Run `gh pr checks <pr-number> --watch`, then retry the merge.
    - **Force**: Run `gh pr merge <pr-url> --squash --delete-branch --admin` to bypass checks. **WARNING: This bypasses CI checks and risks merging untested code. Confirm with the user before proceeding.** Note: requires admin permissions on the repository.
    - **Skip**: Stop without merging. Print the PR URL for manual follow-up.
16. After successful merge, sync local: `git checkout <target-branch> && git pull origin <target-branch>`.
17. **Ticket completion**: If `.backlog/active/` exists, list its contents. Match the current branch name against the ticket directory slugs (branch name contains the slug). If a match is found, run `mkdir -p .backlog/done && mv .backlog/active/{slug} .backlog/done/{slug}`. If no match, skip silently.
18. Print summary: merged PR URL, deleted branch name, current local state. If a ticket was moved in step 17, also include "Ticket moved to .backlog/done/{slug}".

## Error Handling

- **No changes**: Print "No changes to ship." and stop.
- **No commits ahead**: Print "No commits ahead of target branch." and stop.
- **gh auth failure**: Print `gh auth login` instructions and stop.
- **Push failure**: Show the error and stop.
- **Existing PR (merge disabled)**: Show the PR URL and stop.
- **Existing PR (merge enabled)**: Capture the PR URL and proceed to Phase 3.
- **CI checks pending**: Ask user to choose Wait / Force / Skip (Phase 3 step 15).
- **Force merge failure (no admin)**: Inform user, keep PR open, print URL.
- **Merge conflict**: Print details, keep PR open, stop.
- **Merge failure (any reason)**: Keep PR open, print PR URL for manual follow-up.
