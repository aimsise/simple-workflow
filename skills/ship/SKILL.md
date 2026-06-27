---
name: ship
description: >-
  Ships completed work by committing staged changes, moving any
  bound ticket to `.simple-workflow/backlog/done/`, delegating
  knowledge-base extraction to `/tune` via the Skill tool,
  pushing the branch, creating a GitHub PR, and optionally
  squash-merging it. Use when (1) the user runs `/ship` directly
  to commit-and-PR the current branch outside any ticket workflow,
  (2) the user runs `/ship` on an active ticket so the ticket
  directory moves from `.simple-workflow/backlog/active/` to
  `.simple-workflow/backlog/done/`, the ticket's `phase-state.yaml`
  advances `phases.ship` from `pending` to `completed`, and the
  PR body carries the canonical `Audit Summary:` line plus every
  `### Warning:` heading from the latest `audit-round-N.md`, or
  (3) `/autopilot` chain-calls the ship phase of a ticket-driven
  pipeline via the Skill tool. Triggers on "/ship", "/ship merge=true",
  "/ship [target-branch]", "ship the changes", "commit and PR",
  "create pull request", "squash merge", "complete ticket".
disable-model-invocation: false
allowed-tools:
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
argument-hint: "[target-branch] [merge=true] [ticket-dir=<dir-name>]"
---

Ship the current changes: commit, create PR, and optionally merge.
User arguments: $ARGUMENTS

Invocation policy: Do not auto-invoke. `disable-model-invocation: false` is intentional because `/ship` is chain-called by name from the /autopilot skill via the Skill tool during the ship phase of the split-per-ticket flow, and is also invoked directly by users (`/ship`, `/ship merge=true`, `/ship <target-branch>`). Only invoke when the user names it directly or when another skill explicitly chain-calls it.

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

## Observable Contract: Audit Summary embedding

When a ticket was moved to `.simple-workflow/backlog/done/{ticket-dir}/` in Phase 1 step 5, `/ship` MUST embed a structured audit summary into BOTH the commit message body (Phase 1 step 3.e) AND the PR body (Phase 2 step 14) so reviewers without access to gitignored `.simple-workflow/` artifacts can see the audit verdict from GitHub alone. Reference helper: `tests/helpers/audit-summary.sh` mirrors the parsing rules below and is the canonical contract test fixture.

### Selecting the latest audit-round-N.md

Search `.simple-workflow/backlog/done/{ticket-dir}/audit-round-*.md`. The latest file is selected by **numeric** ordering of `N`, NOT lexicographic: `audit-round-10.md` is later than `audit-round-2.md`. Implementation hint: extract `N` from each filename, sort numerically descending, pick the head. A pure-bash reference is in `tests/helpers/audit-summary.sh` (the `--dir` mode).

### Parsing the audit-round file

From the latest `audit-round-N.md`, parse four fields by line:
- `Status:` value — one of `PASS`, `PASS_WITH_CONCERNS`, `FAIL`. Optional surrounding `**` markdown bold markers around the field name are tolerated (`**Status**: PASS` and `Status: PASS` parse identically; `/audit` writes the bold form, see `skills/audit/SKILL.md` Step 4a).
- `Critical:` integer count.
- `Warnings:` integer count.
- `Suggestions:` integer count.

Additionally, parse every `### Warning: <title>` heading line — each is one warning title. Backticks inside the title (e.g. `` ### Warning: `SECRET_TOKEN` exposed in logs ``) MUST be propagated verbatim to the PR body; do not strip them.

**Masking rules** (before parsing, remove these regions):
- Lines inside triple-backtick fenced code blocks (` ``` ... ``` `) — illustrative example outputs MUST NOT be parsed as the active verdict.
- Lines (or inline segments) inside `<!-- ... -->` HTML comments — multi-line HTML comments mask every line until their closing marker.

### Embedding the canonical line

After parsing, embed exactly one line of the form:

```
Audit Summary: <Status> (Critical=<N>, Warnings=<N>, Suggestions=<N>)
```

Embed this line into:
- The commit message body produced in Phase 1 step 3.e (verifiable via `git log -1 --format=%B HEAD`).
- The PR body produced in Phase 2 step 14 (verifiable via `gh pr view --json body --jq .body`).

In addition, append every `### Warning: <title>` heading verbatim into the PR body so warning titles propagate to GitHub. The commit message MAY include warning titles for context but is only required to carry the canonical `Audit Summary:` line.

### Error contracts (non-zero exit, message to stderr)

`/ship` MUST stop with a non-zero exit when:
- The latest `audit-round-N.md` lacks a `Status:` line. Stderr contains the literal substring:
  ```
  audit-summary: missing Status line in audit-round-
  ```
- The declared `Warnings:` count differs from the number of `### Warning:` headings actually present (after masking). Stderr contains the literal substring:
  ```
  audit-summary: count-mismatch (Warnings declared=<X>, headings=<Y>)
  ```

### No-audit fallback

If no `audit-round-*.md` file exists under `.simple-workflow/backlog/done/{ticket-dir}/`, /ship MUST NOT fabricate an `Audit Summary:` line. Instead the PR body MUST contain the literal substring `[shipped without /audit]` (already produced by Phase 2 step 9's review gate — autopilot policy or interactive flow appends it) and MUST contain zero occurrences of the substring `Audit Summary:`. The commit message body in this no-audit path likewise carries no `Audit Summary:` line.

### Static contract literals

The literal strings below are verified by `tests/test-skill-contracts.sh` Category 25 ("Audit Summary embedding contract") to guard against silent drift:

- `Audit Summary: <Status> (Critical=<N>, Warnings=<N>, Suggestions=<N>)`
- `audit-summary: missing Status line in audit-round-`
- `audit-summary: count-mismatch (Warnings declared=<X>, headings=<Y>)`
- `[shipped without /audit]`

## Observable Contract: SW-CHECKPOINT emission

Every `/ship` invocation MUST emit exactly one `## [SW-CHECKPOINT]` block as the FINAL section of its output, per `skills/create-ticket/references/sw-checkpoint-template.md`. The block carries four required fields:

- `phase=ship` (literal — the underscore-form canonical name of this skill).
- `ticket=<ticket-dir or "none">` — `.simple-workflow/backlog/done/{ticket-dir}` when a ticket was moved in step 5, `.simple-workflow/backlog/active/{ticket-dir}` when a ticket was detected but not moved (e.g. early-stop before step 5.b), or the bare string `none` for non-ticket flows.
- `artifacts=[<paths>]` — non-empty list of repo-relative paths on success (e.g. `phase-state.yaml`, PR URL or commit SHA). Failure paths emit `artifacts: []` (empty inline list) instead.
- `next_recommended=""` — empty string, because the ticket lifecycle terminates here; downstream tooling reads this as "no further command".

Failure paths (no-changes, no-remote, push failure, gh-auth failure, merge conflict, etc.) still MUST emit the block, with `artifacts: []` and `next_recommended=""`. The block is emitted exactly once per invocation, at the very end of output. See `skills/create-ticket/references/sw-checkpoint-template.md` for the canonical block format and the list of skills that emit it.

## Phase 1: Commit

**Destructive shortcut prohibition**: If a git command fails with an error message suggesting a non-destructive remediation (e.g. `use -f to force removal`, `use --allow-empty-message`), apply that suggestion first. NEVER use `rm -f .git/index`, `git reset --hard`, `git clean -f` as an error-recovery shortcut.

1. **Pre-flight check**: `git status --short`. If nothing staged/unstaged/untracked, print "No changes to ship." and stop.

2. **Sensitive file warning**: Inspect the working tree for `.env*`, `*credentials*`, `*secret*`, `*.key`, `*.pem`. If any are present (staged/unstaged/untracked), warn the user explicitly before proceeding; the user decides whether to abort or continue.

2a. **Write /ship-commit nonce (Step 2.5)** (authorizes the Step-3 commit under autopilot): When a ticket-dir is in scope (an explicit `ticket-dir=` argument OR a branch-name match — prefetch the Step 5 `ticket-dir` lookup logic here), write a sentinel file BEFORE the Step 3 commit so the `pre-bash-contract-guard.sh` Detection 2 nonce gate authorizes the `git commit`. Path: `.simple-workflow/backlog/active/{ticket-dir}/.ship-commit-nonce`. Behavior — write it via a **Bash sink** (NOT Write/Edit), because the basename is neither `autopilot-state.yaml` nor `phase-state.yaml`, so `pre-state-transition.sh` early-exits and the PII / state-field guards do not inspect a Bash sink:
   - `mkdir -p .simple-workflow/backlog/active/{ticket-dir}` (idempotent).
   - `: > .simple-workflow/backlog/active/{ticket-dir}/.ship-commit-nonce` (truncate-create; empty file).

   The nonce MUST be written BEFORE (or in the SAME `&&` chain as) Step 3's `git commit` — the nonce gate (`pre-bash-contract-guard.sh` Detection 2) authorizes the commit when the nonce is EITHER already on disk (written by a separate prior Bash call) OR written by a co-located `: > .../.ship-commit-nonce` redirect in the SAME command (the gate scans the command string for the queued active-tree nonce write, so the combined `: > nonce && git commit` form is NOT false-blocked — dogfood63 hardening). A nonce written AFTER the commit, or in a later command, does not authorize it. The nonce gate is UNCONDITIONAL (not gated by `SW_REVIEW_FIREWALL_MODE`). The file is gitignored and untracked (it lives under `.simple-workflow/`), so it never appears in `git status` or a diff. **No-ticket (free-form `/ship`)**: silent skip — no ticket scope means no nonce, and a free-form `/ship` commit outside an autopilot tree is not gated by Detection 2 anyway.

3. **Create commit** (the nonce was written for the ticket in step 2.5):
   a. `git diff --stat` and `git diff --cached --stat`.
   b. For unstaged changes, select files by context. Autopilot mode (autopilot-policy.yaml exists) → stage all modified/new user-code files. `.simple-workflow/` is expected to be gitignored via the `hooks/session-start.sh` setup; do NOT attempt to force-add it with `-f`. If it appears in `git status`, the setup hook failed — warn the user rather than paper over. Interactive mode: `AskUserQuestion`. **Non-interactive fallback**: stage all modified/new files (gitignore handles exclusion).
   c. `git add` selected files.
   d. Conventional commit message (feat/fix/improve/chore/docs/test/perf) focused on the "why"; `git log --oneline -5` for style.
   e. Commit via HEREDOC. **Audit Summary embedding**: when a ticket-dir is detected in step 5 and a `.simple-workflow/backlog/done/{ticket-dir}/audit-round-*.md` exists, the canonical `Audit Summary: <Status> (Critical=<N>, Warnings=<N>, Suggestions=<N>)` line MUST appear in the commit message body per the "Audit Summary embedding" section above. Note: this commit is created in step 3 BEFORE the ticket move in step 5.b — to satisfy the contract, resolve `ticket-dir` first (step 5 lookup logic), then read the audit-round file from `.simple-workflow/backlog/active/{ticket-dir}/` (its pre-move location) when building the commit message body. The contract is on the final committed message text, not on filesystem ordering.
   f. `git status` to verify.

4. **Post-commit verification**: `git status`. If tree still dirty or `git log -1 --format=%H` unchanged, report and stop.

5. **Ticket completion** (moves the ticket to `.simple-workflow/backlog/done/`): If `.simple-workflow/backlog/active/` exists, list it. Determine `ticket-dir`:

   > **Worktree path-resolution (W-3, autopilot `PARALLEL_MODE == on`).** Under the parallel wave scheduler, `/ship` runs inside a per-ticket executor worktree (cwd = `<MAIN_REPO>/.claude/worktrees/agent-<id>`, the platform-created `isolation:"worktree"` worktree). The gitignored `.simple-workflow/` state tree is ABSENT in a fresh worktree, but the executor self-created a `.simple-workflow` → `<MAIN_REPO>/.simple-workflow` **symlink** inside the worktree as its first step (autopilot wave-loop step 2a), so EVERY bare relative `.simple-workflow/...` path in Step 5 — the 5.b ticket-move (`active/` → `done/`, the `mkdir -p` / `mv` / `rmdir` targets) AND the 5.d post-move rewrite surfaces (5.d.1 audit-round files, 5.d.2 the brief-side `autopilot-state.yaml`, 5.d.3 the autopilot-log) AND the no-remote local-ship path below — **transparently follows the symlink to the shared main checkout**. Step 5 therefore needs NO change and NO `ARTIFACT_ROOT` argument: the SAME bare relative paths resolve to `<MAIN_REPO>` via the symlink under a worktree, and to the cwd (= the main checkout) on the serial `/autopilot` / manual `/ship` path — behaviour is byte-identical in both. The per-ticket PR (`/ship <default-branch> ticket-dir=<NNN-slug>`, NO `merge=true`) and the no-remote `steps.ship: completed` carve-out are untouched.

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

   **Nonce cleanup** (step 2.5 sentinel removal on EVERY exit path): The `.ship-commit-nonce` written in step 2.5 MUST be removed on every `/ship` exit — both success (Step 15a / 16 / 21) AND every failure path (`No changes` / `No remote` / `gh auth` failure / `Push` failure / `Merge conflict` / `Existing PR`). Run `rm -f .simple-workflow/backlog/active/{ticket-dir}/.ship-commit-nonce` (the `-f` makes it idempotent — absent on the no-ticket path or if the ticket already moved to `done/`). The nonce is gitignored + untracked, so neither its creation nor removal appears in `git status` or a diff. A subsequent `/ship` invocation writes a fresh nonce in step 2.5, so cleanup never blocks a legitimate re-ship.

6. **Knowledge base tuning** (only after a ticket was moved in step 5): **MUST invoke `/tune` via the Skill tool**, passing the ticket-dir name as argument. Extracts reusable patterns from the ticket's evaluation logs into the project KB. **NEVER bypass /tune** via direct writes to `.simple-workflow/kb/*.yaml`. If `/tune` execution fails, log but do **not** stop the ship workflow — commit made, ticket moved. Fail only if the Skill tool itself is unreachable (contract bypass).

Proceed to Phase 2.

## Phase 2: Create PR

7. **Remote availability check**: Check `Remote configured:` in pre-computed context. If `no`, print "Commit complete. No remote configured — skipping push and PR creation." and stop. Do NOT push, create PR, or merge.

8. `gh auth status`. If not authenticated, tell the user to run `gh auth login` and stop.

9. **Review gate**: Verify the latest code review covers the committed content.
    - If no ticket completed in step 5, skip this gate (proceed to step 10).
    - Locate latest review: `ls -t .simple-workflow/backlog/done/{ticket-dir}/quality-round-*.md 2>/dev/null | head -1`. No file → treat as "no review", jump to **Gate-failure flow** below.
    - **Content-identity check**: source `hooks/lib/audit-coverage.sh` and call `audit_coverage_check "{quality-round-path}"`. Interpret stdout/exit:
      - `OK <N>` (exit 0): print `[REVIEW-GATE] audit-coverage match (<N> files) — gate passed`, proceed to step 10. **No interactive prompt, no autopilot-policy lookup.**
      - `STALE <reason>` (exit 1): print `[REVIEW-GATE] audit-coverage stale: <reason>`, jump to **Gate-failure flow**.
      - `LEGACY` (exit 2): fall back to the legacy mtime comparison. Compare quality-round mtime against `git log -1 --format=%ct HEAD`. If review predates commit, jump to **Gate-failure flow**; otherwise proceed to step 10 with `[REVIEW-GATE] legacy mtime ok`.
    - **Gate-failure flow** (no review file, STALE, or LEGACY-predates):
      - **Autopilot policy check**: If `.simple-workflow/backlog/done/{ticket-dir}/autopilot-policy.yaml` exists, read `gates.ship_review_gate.action`:
        - `proceed_if_eval_passed`: Check latest `eval-round-*.md` Status:
          - PASS / PASS-WITH-CAVEATS → proceed. Print `[AUTOPILOT-POLICY] gate=ship_review_gate action=proceed_if_eval_passed eval_status={status}`. Append "[shipped without /audit, autopilot policy applied]" to PR body.
          - FAIL or no eval-round → stop (safety valve; never ship code that failed AC). Print `[AUTOPILOT-POLICY] gate=ship_review_gate action=stop reason=eval_status_not_pass`.
        - `stop`: stop. Print `[AUTOPILOT-POLICY] gate=ship_review_gate action=stop`.
      - Else interactive flow: Print "No recent code review found. Recommended: run /audit before shipping." Ask "Proceed without review? (yes/no)" via `AskUserQuestion` with `header: ship-review`; the `header` value is load-bearing under the autopilot 3-tier `risk_tolerance` matrix (see `skills/autopilot/SKILL.md` `## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)`) — any other header (or an empty one) is denied at every tier when invoked under `/autopilot`. "no" → stop; "yes" → proceed and append "[shipped without /audit]" to the PR body in step 14.

10. Determine target branch from arguments (default `<default-branch>` from pre-computed context). If target ≠ `<default-branch>`, re-run `git log` / `git diff` against the actual target (pre-computed context is always vs `<default-branch>`).
11. `git log origin/<target>..HEAD --oneline`. If no commits ahead, print "No commits ahead of target branch." and stop.
12. `gh pr list --head <current-branch> --state open`. If a PR exists, capture URL, print it, and skip to Phase 3 (if merge enabled) or stop.
13. `git push origin HEAD`. On failure, show the error and stop.
14. Generate PR title (conventional commit, single line) and body (summary of changes + scope) from commit log and diff. **Audit Summary embedding**: when a ticket was moved in step 5, embed the canonical `Audit Summary: <Status> (Critical=<N>, Warnings=<N>, Suggestions=<N>)` line plus every `### Warning: <title>` heading from `.simple-workflow/backlog/done/{ticket-dir}/audit-round-{latest-N}.md` into the PR body per the "Audit Summary embedding" section above. If no `audit-round-*.md` exists, the PR body carries `[shipped without /audit]` (from Step 9) and zero occurrences of `Audit Summary:`.
15. `gh pr create --base <target-branch> --head <current-branch> --title "<title>" --body "<body>"`.
15a. **Complete ship phase (state update — only when a ticket was moved in step 5 AND `.simple-workflow/backlog/done/{ticket-dir}/phase-state.yaml` exists)**: Read `.simple-workflow/backlog/done/{ticket-dir}/phase-state.yaml` and update ONLY (read-modify-write):
     - `phases.ship.status: completed`
     - `phases.ship.completed_at: {now}` (ISO-8601 UTC, recomputed; preserve the existing value when already non-null)
     - `phases.ship.artifacts.pr_url: <pr-url>` (URL from step 15, or existing PR URL captured in step 12; pass through `null` when neither is available, e.g. no-remote / push-failure paths)
     - `last_completed_phase: ship`
     - `current_phase: done`
     - `overall_status: done`

     Do NOT modify `phases.create_ticket` / `phases.scout` / `phases.impl`. The state file stays at `.simple-workflow/backlog/done/{ticket-dir}/phase-state.yaml` as the permanent record — NEVER delete.

     **Idempotence (PSI contract)**: Step 15a MUST run on every successful pass through Phase 2, regardless of whether the PR was newly created in Step 15 OR pre-existing (captured in Step 12) OR the no-remote / no-commits-ahead early-stop branch was taken. If `phases.ship.status` is already `completed` on read, still recompute and write the three top-level scalars (`last_completed_phase`, `current_phase`, `overall_status`) to ensure they match — a prior interrupted run may have left `phases.ship.status: completed` paired with stale top-level scalars (`current_phase: ship`, `overall_status: in-progress`). The post-ship integrity hook (`hooks/post-ship-state-auto-compact.sh`) reads this invariant as ground truth and self-heals when it fails; Step 15a is the primary writer, the hook is the safety net.

     **Ordering with Step 16**: Step 15a MUST complete its write to disk BEFORE Step 16's "print PR URL and stop" early-exit. The "stop" in Step 16 refers to ending the `/ship` skill's body, not to ending the turn; Step 15a's `Write`/`Edit` Tool call still counts as part of `/ship`'s body even when no merge is requested.

     If an existing PR was captured in step 12, run this state update there too, so re-runs finalize correctly.
16. Print the PR URL. If merge is not enabled, stop. Note: on squash-merge the PR title becomes the commit message on the target branch.

## Phase 3: Merge (only when merge=true)

17. `gh pr merge <pr-url> --squash --delete-branch`.
18. If merge fails due to pending CI:
    - **Autopilot policy check**: If `.simple-workflow/backlog/done/{ticket-dir}/autopilot-policy.yaml` exists, read `gates.ship_ci_pending`:
      - `wait`: `gh pr checks <pr-number> --watch` with `timeout_minutes`. Print `[AUTOPILOT-POLICY] gate=ship_ci_pending action=wait timeout={timeout_minutes}m`.
        - Pass within timeout → retry merge. Timeout → `on_timeout` (`stop` by default). Print `[AUTOPILOT-POLICY] gate=ship_ci_pending action=on_timeout`.
      - `stop`: stop. Print `[AUTOPILOT-POLICY] gate=ship_ci_pending action=stop`.
    - Else interactive, ask the user via `AskUserQuestion` with `header: ship-ci`; the `header` value is load-bearing under the autopilot 3-tier `risk_tolerance` matrix (see `skills/autopilot/SKILL.md` `## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)`) — any other header (or an empty one) is denied at every tier when invoked under `/autopilot`. Options:
      - **Wait**: `gh pr checks <pr-number> --watch`, then retry merge.
      - **Force**: `gh pr merge <pr-url> --squash --delete-branch --admin`. **WARNING: bypasses CI; risks merging untested code. Confirm before proceeding.** Requires admin permissions.
      - **Skip**: Stop without merging. Print PR URL for manual follow-up.
19. After successful merge, sync local: `git checkout <target-branch> && git pull origin <target-branch>`.
20. Print summary: merged PR URL, deleted branch, local state. If a ticket moved in step 5, include "Ticket moved to .simple-workflow/backlog/done/{ticket-dir}".

21. **Emit SW-CHECKPOINT block**. Emit `## [SW-CHECKPOINT]` per `skills/create-ticket/references/sw-checkpoint-template.md` as the FINAL section — after step 20 (Phase 3), or step 16 (Phase 2 when `merge=true` unset), or any early-stop (`No changes`, `No remote`, auth / push failure, `No commits ahead`, `Existing PR`, etc.). Emit exactly once at the very end, after PR URL / summary / errors. Fill: `phase=ship`, `ticket=.simple-workflow/backlog/done/{ticket-dir}` if moved in step 5 (else `.simple-workflow/backlog/active/{ticket-dir}` if detected-not-moved, else `none`), `artifacts=[<repo-relative paths to phase-state.yaml and PR URL / commit SHA>]`, `next_recommended=""` (the ticket is complete). Failure paths use `artifacts: []`.

## Error Handling

On EVERY path below (and on success), run the **Nonce cleanup** from Phase 1 step 5 — `rm -f .simple-workflow/backlog/active/{ticket-dir}/.ship-commit-nonce` — so the step-2.5 `.ship-commit-nonce` never survives a failed or interrupted `/ship` (a stale nonce would wrongly authorize a later inline commit). The `-f` flag makes it a no-op when no ticket was in scope.

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
