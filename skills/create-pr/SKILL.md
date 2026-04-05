---
name: create-pr
description: >-
  Create a PR to merge current branch into target branch. Requires gh command.
  Use only when the user explicitly asks to create a pull request.
disable-model-invocation: true
allowed-tools:
  - "Bash(gh:*)"
  - "Bash(git:*)"
argument-hint: "[target-branch]"
---

Create a pull request from the current branch to the target branch.
Target branch is $ARGUMENTS if provided, otherwise default to main.

## Context

- Current branch: !`git branch --show-current`
- Target branch: $ARGUMENTS (default: main)
- Commits ahead of target (vs main): !`git log origin/main..HEAD --oneline`
- Diff stats (vs main): !`git diff origin/main --stat`

## Steps

1. Run `gh auth status` to verify authentication. If not authenticated, tell the user to run `gh auth login` and stop immediately.

2. Determine the target branch. If $ARGUMENTS is provided, use it. Otherwise use main. If the target is not main, re-run `git log` and `git diff` against the actual target branch (the pre-computed context above is always against main).

3. If there are no commits ahead of the target branch, print "No changes to create PR for." and stop.

4. Run `gh pr list --head <current-branch> --state open` to check for an existing PR. If one exists, print its URL and stop.

5. Push unpushed commits by running `git push origin HEAD`. If push fails, show the error and stop.

6. Generate the PR title and body from the commit log and diff stat. Title should be conventional commit style, single line. Body should summarize changes and scope.

7. Run `gh pr create --base <target-branch> --head <current-branch> --title "<title>" --body "<body>"` and print the created PR URL.

## Error Handling

- **Existing PR**: Show the PR URL and stop (not an error).
- **No diff**: Inform the user there are no changes and stop.
- **Push failure**: Show the error message and stop.
- **gh auth failure**: Print `gh auth login` instructions and stop.
