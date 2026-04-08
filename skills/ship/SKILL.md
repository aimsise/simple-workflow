---
name: ship
description: >-
  Commit current changes, create a PR, and optionally squash-merge.
  Combines commit + create-pr + merge into a single workflow.
  Use when the user wants to ship completed work.
disable-model-invocation: true
allowed-tools:
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
- First argument: target branch name (default: `main`). If the first argument is `true` or `merge=true`, treat it as the merge flag and use `main` as target.
- Second argument: `merge=true` or `true` to enable squash-merge after PR creation (default: no merge).

Examples:
- `/ship` -> commit + PR to main
- `/ship develop` -> commit + PR to develop
- `/ship merge=true` -> commit + PR to main + squash-merge
- `/ship main true` -> commit + PR to main + squash-merge
- `/ship develop merge=true` -> commit + PR to develop + squash-merge

## Pre-computed Context

Current branch:
!`git branch --show-current`

Current state:
!`git status --short`

Staged diff:
!`git diff --cached`

Unstaged diff summary:
!`git diff --stat`

Diff stats vs main:
!`git diff origin/main --stat`

Recent commits for style reference:
!`git log --oneline -10`

Commits ahead of main:
!`git log origin/main..HEAD --oneline`

## Phase 1: Commit

1. Analyze staged and unstaged changes.
2. If there are no changes at all (nothing staged, nothing unstaged, no untracked files), print "No changes to ship." and stop.
3. If there are unstaged or untracked changes, show the file list and ask the user which files to stage. Exclude files matching: `.env*`, `*credentials*`, `*secret*`, `*.key`, `*.pem` -- warn the user if such files are present.
4. Generate a conventional commit message (feat/fix/improve/chore/docs/test/perf). Focus on the "why", not the "what". Use a HEREDOC for the message.
5. Run `git status` to verify the commit succeeded.

## Phase 2: Create PR

6. Run `gh auth status`. If not authenticated, tell the user to run `gh auth login` and stop.

6b. **Review gate**: Check for recent code review:
    - If there is an active ticket (`.backlog/active/{slug}/`), run `ls -t .backlog/active/{slug}/quality-round-*.md 2>/dev/null | head -1` to find the most recent review file in that ticket directory
    - If there is no active ticket, skip the review gate (no check needed)
    - If a review file exists, compare its modification time with the last commit time
    - If NO review file exists, or the review predates the last code-changing commit:
      Print "No recent code review found. Recommended: run /review-diff before shipping."
      Ask the user: "Proceed without review? (yes/no)"
      - If "no" → stop
      - If "yes" → proceed, and append "[shipped without /review-diff]" to the PR body in step 11

7. Determine the target branch from arguments (default: main). If the target is not main, re-run `git log` and `git diff` against the actual target branch (the pre-computed context above is always against main).
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
