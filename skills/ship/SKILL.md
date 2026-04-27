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

`/ship` MUST delegate to `/tune` via the Skill tool once a ticket has been moved to `.simple-workflow/backlog/done/`. The rest of `/ship` (commit, push, PR creation) is direct `git`/`gh` work, not a sub-skill contract. Any `/tune` bypass is a contract violation detected by the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `/tune` (Skill) | Phase 1 step 6 — only after a ticket was moved to `.simple-workflow/backlog/done/` in step 5 | No knowledge-base pattern extraction from the ticket's `eval-round-*.md` / `quality-round-*.md`. Next `/impl` Generator runs without updated `.simple-workflow/kb/index.yaml` — learning degrades. Detected by missing `/tune` trace after a ticket-move in the skill invocation audit |

**Binding rules**:
- `MUST invoke /tune via the Skill tool` whenever a ticket was moved in step 5. Pass the ticket-dir name as argument.
- `NEVER bypass /tune` via direct manipulation of `.simple-workflow/kb/candidates.yaml` or `entries.yaml` from within `/ship`.
- If `/tune` itself fails, **do NOT stop the ship workflow** (commit made, ticket moved) — but the invocation MUST have been attempted. `Fail the /tune invocation attempt only if the Skill tool is unreachable; log and continue.`

## phase-state.yaml write ownership

Writes ONLY `phases.ship` plus top-level `current_phase` / `last_completed_phase` / `overall_status`. Never modify `phases.create_ticket` / `phases.scout` / `phases.impl`.

`phase-state.yaml` lives inside the ticket directory. When `/ship` moves `.simple-workflow/backlog/active/{ticket-dir}` → `.simple-workflow/backlog/done/{ticket-dir}` via `mv`, the state file moves with it. NEVER delete `phase-state.yaml` — it is the permanent historical record that stays in `.simple-workflow/backlog/done/{ticket-dir}/` forever.

Reference: `skills/create-ticket/references/phase-state-schema.md`.

## Argument Parsing

Parse `$ARGUMENTS` for positional arguments:
- First: target branch (default `<default-branch>` — see pre-computed context). If `true` or `merge=true`, treat as merge flag with `<default-branch>` target.
- Second: `merge=true` or `true` to enable squash-merge after PR (default: no merge).
- `ticket-dir=<dir-name>`: Optional key=value; directory name only (e.g. `003-fix-login`), not a full path. Position-independent; does not affect the positional arguments.

Examples:
- `/ship` → commit + PR to `<default-branch>`
- `/ship develop` → commit + PR to develop
- `/ship merge=true` → commit + PR to `<default-branch>` + squash-merge
- `/ship <default-branch> true` → commit + PR to `<default-branch>` + squash-merge
- `/ship develop merge=true` → commit + PR to develop + squash-merge
- `/ship main ticket-dir=003-fix-login` → commit + PR to main, using ticket-dir `003-fix-login`

## Pre-compute Resilience Contract

All pre-compute bash commands return fallback values on failure and never halt `/ship`. The agent reads each pre-compute result and routes commit/push strategy from the reported state (e.g., `(detached HEAD)`, `[no commits yet]`, `[no remote — skipped]`). A failing pre-compute never justifies abandoning `/ship` for ad-hoc git commands; interpret the fallback marker and skip push when no remote, skip default-branch diff when no history, etc.

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

**Note**: `<default-branch>` denotes the repo default branch from `Default branch:` in the pre-computed context (resolves `git symbolic-ref refs/remotes/origin/HEAD`; falls back to `main` if unset). Use this value wherever `<default-branch>` appears — never hardcode `main`.

## Phase 1: Commit

**Destructive shortcut prohibition**: If a git command fails with an error message suggesting a non-destructive remediation (e.g. `use -f to force removal`, `use --allow-empty-message`), apply that suggestion first. NEVER use `rm -f .git/index`, `git reset --hard`, `git clean -f` as an error-recovery shortcut.

1. **Pre-flight check**: `git status --short`. If nothing staged/unstaged/untracked, print "No changes to ship." and stop.

2. **Sensitive file warning**: Inspect the working tree for `.env*`, `*credentials*`, `*secret*`, `*.key`, `*.pem`. If any are present (staged/unstaged/untracked), warn the user explicitly before proceeding; the user decides whether to abort or continue.

3. **Create commit**:
   a. `git diff --stat` and `git diff --cached --stat`.
   b. For unstaged changes, select files by context. Autopilot mode (autopilot-policy.yaml exists) → stage all modified/new user-code files. `.simple-workflow/` is expected to be gitignored via the `hooks/session-start.sh` setup; do NOT attempt to force-add it with `-f`. If it appears in `git status`, the setup hook failed — warn the user rather than paper over. Interactive mode: `AskUserQuestion`. **Non-interactive fallback**: stage all modified/new files (gitignore handles exclusion).
   c. `git add` selected files.
   d. Conventional commit message (feat/fix/improve/chore/docs/test/perf) focused on the "why"; `git log --oneline -5` for style.
   e. Commit via HEREDOC.
   f. `git status` to verify.

4. **Post-commit verification**: `git status`. If tree still dirty or `git log -1 --format=%H` unchanged, report and stop.

5. **Ticket completion** (moves the ticket to `.simple-workflow/backlog/done/`): If `.simple-workflow/backlog/active/` exists, list it. Determine `ticket-dir`:
   - **Explicit `ticket-dir=`**: If provided, check `.simple-workflow/backlog/active/{dir-name}`. Exists → use it (skip branch matching). Else print WARNING "ticket-dir '{dir-name}' not found in .simple-workflow/backlog/active/ — falling back to branch name matching." and fall through.
   - **Fallback — branch matching**: For each dir in `.simple-workflow/backlog/active/`, strip the leading `NNN-` (e.g. `001-add-search-feature` → `add-search-feature`). If branch contains this slug, set `ticket-dir` to the full dir name.
   - No match → skip silently.

   Once determined:

   a. **Begin ship phase (only if `.simple-workflow/backlog/active/{ticket-dir}/phase-state.yaml` exists)**: read-modify-write ONLY these fields:
      - `phases.ship.status: in-progress`
      - `phases.ship.started_at: {now}` (ISO-8601 UTC via `date -u +%Y-%m-%dT%H:%M:%SZ`)
      - `current_phase: ship`
   b. **Write destination-anchored phase-state.yaml FIRST, then move remaining contents** — ordering closes the race where an interruption after `mv` strands state mid-move (Reviewer B Finding 7). The schema has no top-level `ticket_dir:`, so ordering is the entire mitigation.
      1. `mkdir -p .simple-workflow/backlog/done/{ticket-dir}`.
      2. Write the updated phase-state.yaml (with the 5a `in-progress` update) directly to `.simple-workflow/backlog/done/{ticket-dir}/phase-state.yaml`. **After this sub-step the destination state file is self-consistent even if interrupted.**
      3. For each file in `.simple-workflow/backlog/active/{ticket-dir}/` other than `phase-state.yaml`, `mv` to `.simple-workflow/backlog/done/{ticket-dir}/`. Do NOT re-write `phase-state.yaml` — already written in sub-step 2.
      4. `rmdir .simple-workflow/backlog/active/{ticket-dir}`. If non-empty, list remaining files and stop (recoverable; needs manual attention).
   c. No post-move rewrite needed for `phase-state.yaml` — 5.b.2 serialized it to its destination before any other move.

   d. **Post-move path rewrite (audit reports, brief-side autopilot state, autopilot log)** — three other surfaces still embed the OLD source-path string after `mv`. Rewrite each in place so no residual `.simple-workflow/backlog/active/{ticket-dir}/` or `.simple-workflow/backlog/product_backlog/{ticket-dir}/` substring survives outside fenced code blocks and HTML comments.

      **Surfaces** (rewrite ONLY these, ONLY for the moved ticket):
      1. `.simple-workflow/backlog/done/{ticket-dir}/audit-round-*.md` — every match, prose only.
      2. The brief-side `autopilot-state.yaml` under the parent-slug's done directory (`<briefs-done>/{parent-slug}/autopilot-state.yaml` per the autopilot Split Brief Lifecycle) — set the moved ticket's `tickets[].ticket_dir` value to `.simple-workflow/backlog/done/{ticket-dir}/` (trailing slash inclusive). Other ticket entries in the same file MUST NOT be touched.
      3. `.simple-workflow/backlog/done/{ticket-dir}/autopilot-log.md` — every match, prose only.

      **Rewrite rules**:
      - Replace every literal occurrence of the OLD path (active or product_backlog form) with the NEW done path.
      - **OUTSIDE fenced code blocks** (delimited by triple-backtick lines) AND **OUTSIDE HTML comments** (delimited by `<!--` / `-->`). Substrings inside these zones are intentionally left alone — they are documentation, regex examples, or historical narrative.
      - **Moved-ticket scope only**: do NOT rewrite paths that reference a different `{slug}` or different `{ticket-id}` (cross-ticket references stay verbatim).
      - **Idempotent**: a second invocation against the same already-moved ticket produces zero further edits (the OLD-path substring is already absent in prose).
      - If a target file does not exist (e.g., no audit reports were produced), skip silently — absent files are not drift.

      The regression guard `tests/test-path-consistency.sh` (Category 25) verifies these contracts on synthetic fixtures.

   **Post-move commit policy**: After the `mv` in step 5.b.3, `git status --short` should be clean (the moved files are gitignored). If status is still dirty, investigate — do NOT create a `chore: move ticket artifacts` follow-up commit. The ticket lifecycle produces exactly ONE commit per ticket (step 3's `feat:` / `fix:` commit).

6. **Knowledge base tuning** (only after a ticket was moved in step 5): **MUST invoke `/tune` via the Skill tool**, passing the ticket-dir name as argument. Extracts reusable patterns from the ticket's evaluation logs into the project KB. **NEVER bypass /tune** via direct writes to `.simple-workflow/kb/*.yaml`. If `/tune` execution fails, log but do **not** stop the ship workflow — commit made, ticket moved. Fail only if the Skill tool itself is unreachable (contract bypass).

Proceed to Phase 2.

## Phase 2: Create PR

7. **Remote availability check**: Check `Remote configured:` in pre-computed context. If `no`, print "Commit complete. No remote configured — skipping push and PR creation." and stop. Do NOT push, create PR, or merge.

8. `gh auth status`. If not authenticated, tell the user to run `gh auth login` and stop.

9. **Review gate**: Check for recent code review:
    - If a ticket completed (`{ticket-dir}` now in `.simple-workflow/backlog/done/` after step 5), run `ls -t .simple-workflow/backlog/done/{ticket-dir}/quality-round-*.md 2>/dev/null | head -1` for the latest review.
    - No ticket → skip the review gate.
    - Review file exists → compare its mtime with the last commit time.
    - NO review file, or review predates last code-changing commit:
      - **Autopilot policy check**: If `.simple-workflow/backlog/done/{ticket-dir}/autopilot-policy.yaml` exists, read `gates.ship_review_gate.action`:
        - `proceed_if_eval_passed`: Check latest `eval-round-*.md` Status:
          - PASS / PASS-WITH-CAVEATS → proceed. Print `[AUTOPILOT-POLICY] gate=ship_review_gate action=proceed_if_eval_passed eval_status={status}`. Append "[shipped without /audit, autopilot policy applied]" to PR body.
          - FAIL or no eval-round → stop (safety valve; never ship code that failed AC). Print `[AUTOPILOT-POLICY] gate=ship_review_gate action=stop reason=eval_status_not_pass`.
        - `stop`: stop. Print `[AUTOPILOT-POLICY] gate=ship_review_gate action=stop`.
      - Else interactive flow: Print "No recent code review found. Recommended: run /audit before shipping." Ask "Proceed without review? (yes/no)". "no" → stop; "yes" → proceed and append "[shipped without /audit]" to the PR body in step 14.

10. Determine target branch from arguments (default `<default-branch>` from pre-computed context). If target ≠ `<default-branch>`, re-run `git log` / `git diff` against the actual target (pre-computed context is always vs `<default-branch>`).
11. `git log origin/<target>..HEAD --oneline`. If no commits ahead, print "No commits ahead of target branch." and stop.
12. `gh pr list --head <current-branch> --state open`. If a PR exists, capture URL, print it, and skip to Phase 3 (if merge enabled) or stop.
13. `git push origin HEAD`. On failure, show the error and stop.
14. Generate PR title (conventional commit, single line) and body (summary of changes + scope) from commit log and diff.
15. `gh pr create --base <target-branch> --head <current-branch> --title "<title>" --body "<body>"`.
15a. **Complete ship phase (state update — only when a ticket was moved in step 5 AND `.simple-workflow/backlog/done/{ticket-dir}/phase-state.yaml` exists)**: Read `.simple-workflow/backlog/done/{ticket-dir}/phase-state.yaml` and update ONLY (read-modify-write):
     - `phases.ship.status: completed`
     - `phases.ship.completed_at: {now}` (ISO-8601 UTC, recomputed)
     - `phases.ship.artifacts.pr_url: <pr-url>` (URL from step 15, or existing PR URL captured in step 12)
     - `last_completed_phase: ship`
     - `current_phase: done`
     - `overall_status: done`

     Do NOT modify `phases.create_ticket` / `phases.scout` / `phases.impl`. The state file stays at `.simple-workflow/backlog/done/{ticket-dir}/phase-state.yaml` as the permanent record — NEVER delete.

     If an existing PR was captured in step 12, run this state update there too, so re-runs finalize correctly.
16. Print the PR URL. If merge is not enabled, stop. Note: on squash-merge the PR title becomes the commit message on the target branch.

## Phase 3: Merge (only when merge=true)

17. `gh pr merge <pr-url> --squash --delete-branch`.
18. If merge fails due to pending CI:
    - **Autopilot policy check**: If `.simple-workflow/backlog/done/{ticket-dir}/autopilot-policy.yaml` exists, read `gates.ship_ci_pending`:
      - `wait`: `gh pr checks <pr-number> --watch` with `timeout_minutes`. Print `[AUTOPILOT-POLICY] gate=ship_ci_pending action=wait timeout={timeout_minutes}m`.
        - Pass within timeout → retry merge. Timeout → `on_timeout` (`stop` by default). Print `[AUTOPILOT-POLICY] gate=ship_ci_pending action=on_timeout`.
      - `stop`: stop. Print `[AUTOPILOT-POLICY] gate=ship_ci_pending action=stop`.
    - Else interactive, ask the user:
      - **Wait**: `gh pr checks <pr-number> --watch`, then retry merge.
      - **Force**: `gh pr merge <pr-url> --squash --delete-branch --admin`. **WARNING: bypasses CI; risks merging untested code. Confirm before proceeding.** Requires admin permissions.
      - **Skip**: Stop without merging. Print PR URL for manual follow-up.
19. After successful merge, sync local: `git checkout <target-branch> && git pull origin <target-branch>`.
20. Print summary: merged PR URL, deleted branch, local state. If a ticket moved in step 5, include "Ticket moved to .simple-workflow/backlog/done/{ticket-dir}".

21. **Emit SW-CHECKPOINT block**. Emit `## [SW-CHECKPOINT]` per `skills/create-ticket/references/sw-checkpoint-template.md` as the FINAL section — after step 20 (Phase 3), or step 16 (Phase 2 when `merge=true` unset), or any early-stop (`No changes`, `No remote`, auth / push failure, `No commits ahead`, `Existing PR`, etc.). Emit exactly once at the very end, after PR URL / summary / errors. Fill: `phase=ship`, `ticket=.simple-workflow/backlog/done/{ticket-dir}` if moved in step 5 (else `.simple-workflow/backlog/active/{ticket-dir}` if detected-not-moved, else `none`), `artifacts=[<repo-relative paths to phase-state.yaml and PR URL / commit SHA>]`, `next_recommended=""` (the ticket is complete). Failure paths use `artifacts: []`.

## Error Handling

- **No changes**: Print "No changes to ship." and stop.
- **No remote**: Print "Commit complete. No remote configured — skipping push and PR creation." and stop after Phase 1.
- **No commits ahead**: Print "No commits ahead of target branch." and stop.
- **gh auth failure**: Print `gh auth login` instructions and stop.
- **Push failure**: Show the error and stop.
- **Existing PR (merge disabled)**: Show the PR URL and stop.
- **Existing PR (merge enabled)**: Capture PR URL and proceed to Phase 3.
- **CI checks pending**: Wait / Force / Skip (Phase 3 step 18).
- **Force merge failure (no admin)**: Inform user, keep PR open, print URL.
- **Merge conflict**: Print details, keep PR open, stop.
- **Merge failure (any reason)**: Keep PR open, print PR URL for manual follow-up.
