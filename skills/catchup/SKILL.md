---
name: catchup
description: >-
  Analyze current branch state and recover working context. Use at session
  start, after context compaction, or when unsure what to do next. Detects
  current development phase and recommends the next action.
allowed-tools:
  # Claude Code
  - Agent
  - Read
  - Glob
  - Grep
  - "Bash(git:*)"
  - "Bash(ls:*)"
  # Copilot CLI
  - task
  - view
  - glob
  - grep
  - "shell(git:*)"
  - "shell(ls:*)"
argument-hint: "[phase: investigate|plan|implement|test|review|commit]"
---

Recover context and detect next action for the current working session.
User arguments: $ARGUMENTS

Current branch:
!`git branch --show-current`

Recent history:
!`git log --oneline -5`

Default branch:
!`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main`

Changes from default branch:
!`git diff --shortstat $(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main)`

Working tree:
!`git status --short`

## Instructions

**Note**: Throughout this skill, `<default-branch>` denotes the repository's default branch, taken from the `Default branch:` value in the pre-computed context above (which resolves `git symbolic-ref refs/remotes/origin/HEAD` and falls back to `main` when `origin/HEAD` is not set). Use this resolved value wherever the rules below mention `<default-branch>` — never hardcode `main`.

### 0. Argument Parsing

If `$ARGUMENTS` specifies a phase name (investigate, plan, implement, test, review, or commit), skip directly to **Step 4** and use the specified phase for guidance.

If `$ARGUMENTS` is empty, proceed with full recovery (Steps 1-pre and 1-4).

### 1-pre. phase-state.yaml primary state read

`phase-state.yaml` is the **primary** source of truth for ticket lifecycle state, read **before** the compact-state / session-log sources in Step 1. See `skills/create-ticket/references/phase-state-schema.md` for the canonical schema.

Use the `Glob` tool to enumerate state files across **both** ticket locations:
- `.backlog/active/*/phase-state.yaml`
- `.backlog/product_backlog/*/phase-state.yaml`

Product-backlog tickets sit at `last_completed_phase: create_ticket` with `overall_status: in-progress` — they are real in-progress records that Rule 0 must be able to recommend `/scout` for. Missing this location caused the pre-PR-E discovery gap (Reviewer B Findings 3, 4). For each match, use the `Read` tool to load the file, then use `Grep` on the in-memory content (via line-prefix matching — NOT shell pipelines; the allowed-tools of this skill do not include shell piping, consistent with AC 4.7) to extract per-ticket records:

- `current_phase` (top-level scalar: `create_ticket | scout | impl | ship | done`)
- `last_completed_phase` (top-level scalar: `create_ticket | scout | impl | ship | null`)
- `overall_status` (top-level scalar: `in-progress | blocked | done | failed`)
- `created` (top-level ISO-8601 scalar)
- For each phase section under `phases:` where present, its `started_at` scalar (used to resolve the "most recent" tie-break in Rule 0 — formerly Rule 0.5 before the precedence flip in Task 7)

Match only **top-level** scalars for `current_phase`, `last_completed_phase`, `overall_status` (lines whose content starts at column 0). Do not confuse them with identically-named nested keys under `phases:` which are indented.

Build an ordered per-ticket record list `phase_state_records = [{dir, location, current_phase, last_completed_phase, overall_status, created, latest_started_at}, ...]`. The `location` field is `active` when the file path matches `.backlog/active/` and `product_backlog` when it matches `.backlog/product_backlog/` — Rule 0's `{ticket-dir}` output includes the full prefix (e.g. `.backlog/product_backlog/001-foo`) so the recommended command resolves correctly without the user having to guess the location. The `latest_started_at` field is the maximum `phases.{phase}.started_at` across that ticket's phase sections; when no `started_at` is present, fall back to `created`. Carry this list forward to Steps 2, 4, and 5.

**Freshness flag**: If `phase_state_records` is non-empty (i.e. the `Glob` above found at least one valid `phase-state.yaml`), set `phase_state_fresh = true`; otherwise `phase_state_fresh = false`. The flag is consumed in Step 2 to decide whether to skip the researcher subagent — when the unified state file is present it already carries the per-phase records forward, so there is nothing a deep research pass would add. This simpler rule (presence, not mtime) replaces the prior 1-hour mtime check; it removes the need for the `Bash(stat:*)` permission without weakening the researcher-skip guarantee, because every state-file update is accompanied by a CHECKPOINT emission that is already the strongest "recently touched" signal available in the catchup flow.

**Dual-state precedence check (autopilot-state.yaml)**: After building `phase_state_records`, additionally `Glob` for `autopilot-state.yaml` under `.backlog/briefs/active/*/` and `.backlog/active/*/`. For each hit, apply the precedence rule documented in `skills/create-ticket/references/phase-state-schema.md` §5 ("Dual-state precedence"):

- During `/autopilot` execution, `autopilot-state.yaml` is authoritative for pipeline orchestration; `phase-state.yaml` is maintained in parallel.
- Outside autopilot, `phase-state.yaml` is authoritative.

Concretely, when both `autopilot-state.yaml` and `phase-state.yaml` exist for the same ticket, prefer `autopilot-state.yaml` when the ticket is under `.backlog/briefs/active/` (i.e. an autopilot-managed brief currently being orchestrated); otherwise prefer `phase-state.yaml`. This drops the prior mtime-based tiebreak (and the `Bash(stat:*)` permission that enabled it) but preserves the important rule: autopilot-driven tickets defer to `autopilot-state.yaml` because it is the orchestration source-of-truth while the pipeline is running.

When `autopilot-state.yaml` wins precedence, annotate the corresponding record (or add a new record when no `phase-state.yaml` exists for that ticket) with `source: autopilot-state` and prefer it for Rule 0 guidance. Emit a warning line `autopilot-state.yaml is authoritative for {ticket-dir} (autopilot-managed brief); deferring to autopilot-state per dual-state precedence.` The full fold-in of `autopilot-state.yaml` into `phase-state.yaml` is deferred — see `skills/create-ticket/references/autopilot-foldin.md`.

**If no `phase-state.yaml` file exists anywhere in `.backlog/active/` OR `.backlog/product_backlog/`**, set `phase_state_records = []` and fall through to Step 1 unchanged (AC 4.5 — existing compact-state + artifact-discovery behavior is preserved).

### 1. Compact-State and Session-Log Recovery

Check for recent compact-state files in `.docs/compact-state/compact-state-*.md` (most recent first).

**If the latest file starts with a YAML frontmatter (`---`)**, parse the frontmatter and extract the following fields as variables (used in Step 4):
- `date` — when the compact happened
- `branch` — branch at compact time
- `active_tickets` — list of ticket directories that were active
- `active_plans` — list of plan files that were active
- `latest_eval_round` — highest round number across all tickets (aggregate)
- `latest_audit_round` — highest round number across all tickets (aggregate)
- `last_round_outcome` — `PASS` | `FAIL` | `PASS_WITH_CONCERNS` | `unknown` (aggregate — from the most relevant impl-loop ticket)
- `in_progress_phase` — `impl-loop` | `impl-done` | `unknown` (aggregate — `impl-loop` if any ticket is looping)
- `tickets` — per-ticket array with `{dir, latest_eval_round, latest_audit_round, last_round_outcome, in_progress_phase}` for each active ticket

Use the `Read` tool to load the full compact-state file into context, then extract scalar fields by matching line prefixes (e.g., `latest_eval_round:`, `in_progress_phase:`). For list fields (`active_tickets`, `active_plans`) collect lines matching `^  - ` (2-space indent, dash, space) until the next non-list line. For the per-ticket `tickets:` array, each ticket entry begins with `  - dir: ` and its attributes are indented by 4 spaces (`    latest_eval_round:`, `    latest_audit_round:`, `    last_round_outcome:`, `    in_progress_phase:`). Parse them as an ordered list of maps; each map terminates when the next `  - dir: ` line appears or when the block ends. Do NOT use Bash for parsing — the allowed-tools of this skill do not include shell piping; `Read` and `Grep` are sufficient.

**If the latest file does not start with `---`**, treat it as a legacy compact-state file and ignore the structured fields (still keep its existence as a flag for Step 2).

**If no compact-state file is found** (or as a complement), check for the most recent session log at `.docs/session-log/session-log-*.md`. If the file starts with a YAML frontmatter (`---`), parse the metadata (`date`, `branch`, `last_commit`, `changed_files`) and the `## Final Status` / `## Recent Commits` sections to recover the last-known working state. Skip files without YAML frontmatter (legacy format).

### 2. Context Analysis (conditional)

Determine whether the **researcher** agent is needed:

- **Skip researcher** if ALL of the following are true:
  - Current branch equals `<default-branch>` (the value resolved at the top of the Instructions section)
  - Working tree has 0 changed files
  - No compact-state file was found in Step 1
  (State is obvious — clean start, no prior work to recover.)

- **Skip researcher** if:
  - A compact-state file was found in Step 1 that is less than 1 hour old
  (State is already available from the file — no need for deep analysis.)

- **Skip researcher** if `phase_state_fresh = true` (set in Step 1-pre — at least one valid `phase-state.yaml` record exists). The unified state file already carries the per-phase records forward, so there is nothing a deep research pass would add (AC 4.6).

- **Otherwise**: Spawn the **researcher** agent to analyze:
  - What has changed on this branch vs `<default-branch>`
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

Detect the current development phase by checking these conditions **in order**. Check both `.docs/` and `.backlog/active/` for artifacts. Use the **first matching** phase.

**Rule precedence note**: `phase-state.yaml` is the authoritative lifecycle state source. Rule 0 below therefore evaluates `phase_state_records` (from Step 1-pre) **strictly before** the legacy compact-state rule (now Rule 0-legacy). The legacy rule only fires when Rule 0 did not match (typically on repositories that have no `phase-state.yaml` yet, or where every record has `overall_status != in-progress`).

0. **`phase-state.yaml` indicates an in-progress ticket with a completed phase** → suggest `next_recommended` command based on `last_completed_phase` mapping

   - **Precedence**: this rule is evaluated **strictly before Rule 0-legacy** and before Rule 1. `phase-state.yaml` is the authoritative state source; only when it yields no match do the legacy compact-state / artifact-discovery rules apply.
   - **Fire condition**: at least one record in `phase_state_records` (from Step 1-pre) has `overall_status: in-progress` AND `last_completed_phase != ship` AND `last_completed_phase != null`. If none match, fall through to Rule 0-legacy.
   - **Mapping from `last_completed_phase` to next recommended command**:

     | `last_completed_phase` | ticket location | next command |
     |---|---|---|
     | `create_ticket` | `.backlog/active/` or `.backlog/product_backlog/` | `/scout {ticket-dir}` |
     | `scout` | `.backlog/active/` | `/impl {plan-path}` |
     | `impl` | `.backlog/active/` | `/ship` |

     (`last_completed_phase == ship` means the ticket should have moved to `.backlog/done/`; skip.)

     The `{ticket-dir}` carries its full location prefix — for a product_backlog ticket use the full path (e.g. `.backlog/product_backlog/001-foo`), not just the bare directory name. Step 1-pre records the `location` field per record specifically so this mapping can emit the correct prefix.

   - **Single in-progress ticket**: recommend the mapped command using that ticket's `{ticket-dir}` (and `plan.md` path for the `scout → /impl` case).
   - **Multiple in-progress tickets** (AC 4.3): list ALL matching tickets in the guidance, then recommend resuming the one with the **most recent `latest_started_at`** (computed in Step 1-pre as the max `phases.{phase}.started_at` across that ticket's phase sections, with `created` as fallback). Ties are broken by lexicographic `{ticket-dir}` order. Name the selected ticket in the recommendation line so the user can see which one was chosen.

   - **Inconsistency warning (Rule 0 vs Rule 0-legacy)**: If Rule 0 fires AND a YAML-frontmatter compact-state was also parsed in Step 1 AND the compact-state's aggregate suggestion (from Rule 0-legacy below) would recommend a different action than Rule 0 AND `phase-state.yaml` mtime (from Step 1-pre) is newer than the compact-state's `date` field, emit a single warning line **before** the Rule 0 guidance:

     ```
     Inconsistency detected between phase-state.yaml and older compact-state. Preferring phase-state.yaml (newer).
     ```

     Then proceed with the Rule 0 recommendation. This surfaces — rather than silently hides — state drift between the two files, so users can investigate whether the compact-state snapshot is stale.

0-legacy. **Compact-state indicates an in-progress `/impl` loop** → suggest **resume `/impl`** *(only when Rule 0 did not fire)*
   - Check: a YAML-frontmatter compact-state file was parsed in Step 1 AND `in_progress_phase == impl-loop` (aggregate field)
   - Check: no new git commit has been made since the compact-state's `date` (compare against `git log -1 --format=%cI` for the most recent commit). If a newer commit exists, the user has already moved on — skip Rule 0-legacy and fall through to the rules below.
   - **Per-ticket guidance** (when `tickets:` array is present): identify ticket(s) with `in_progress_phase == impl-loop` from the per-ticket array. For each such ticket, include its directory, round number, and outcome in the guidance.
     - Single impl-loop ticket: "You were in the middle of `/impl` for `{dir}` (round `{latest_eval_round}` evaluated, last outcome: `{last_round_outcome}`). Re-run `/impl` to resume."
     - Multiple impl-loop tickets: List all looping tickets with their round/outcome, then recommend resuming the one with the highest `latest_eval_round`.
   - **Fallback** (when `tickets:` array is absent — legacy compact-state): use the aggregate `latest_eval_round` and `last_round_outcome` as before. If `active_tickets` is non-empty, name the ticket directory in the guidance.

1. **No research files for current topic** → suggest **investigate**
   - Check: `.docs/research/` is empty or has no files related to current branch
   - Also check: `.backlog/active/` has ticket directories but no `investigation.md` in any of them
   - Guidance: Use `/investigate <topic>`. If a ticket exists in `.backlog/active/`, mention its directory.

2. **Research exists, no plans** → suggest **plan**
   - Check: `.docs/research/` has files BUT `.docs/plans/` has no related files
   - Also check: `.backlog/active/*/investigation.md` exists BUT `.backlog/active/*/plan.md` does not
   - Guidance: Read the research first, then use `/plan2doc <feature>`. `/plan2doc` automatically uses sonnet for S-size and opus for M/L/XL.

3. **Plans exist, no code diff from default branch** → suggest **implement**
   - Check: `.docs/plans/` has files BUT `git diff <default-branch> --name-only` shows no changes outside `.docs/` and `.backlog/`
   - Also check: `.backlog/active/*/plan.md` exists BUT no code changes outside `.backlog/`
   - Guidance: Read the plan first, then use `/impl`.

4. **Code diff exists, no test changes** → suggest **test**
   - Check: `git diff <default-branch> --name-only` shows source changes BUT no test file changes
   - Guidance: Use `/test <changed files>`.

5. **Tests exist, no review files** → suggest **review**
   - Check: Both source and test changes exist BUT no recent review in `.docs/reviews/` or `.backlog/active/*/quality-round-*.md`
   - Guidance: Use `/audit` to check all changes (code quality + security).

6. **Review done, uncommitted changes** → suggest **commit**
   - Check: Review files exist AND `git status --porcelain` shows uncommitted changes
   - Guidance: Use `/ship` to commit and create PR.

Present the detection result with reasoning, including any ticket directory information from `.backlog/active/`. If the user specified a phase via `$ARGUMENTS`, skip detection and go directly to the guidance for that phase.

### 5. Summary Output

Print a concise summary:
- Current situation (branch, what's been done)
- Active tickets in `.backlog/active/` (list ticket-dir name and available artifacts)
- If `phase_state_records` (from Step 1-pre) is non-empty, also list each record's `{dir} phase={current_phase} last_completed={last_completed_phase} status={overall_status}` — this is the authoritative lifecycle state and takes precedence over compact-state-derived information
- If a YAML-frontmatter compact-state was parsed in Step 1, also list the `active_tickets` recorded at compact time (these are the tickets the user was focused on at the moment of compaction — they may differ from the current `.backlog/active/` listing if filesystem state has drifted)
- Detected phase and recommended next action
- Exact command sequence, e.g.:
  ```
  /clear
  /catchup  (optional, to recover context after clearing)
  /<next-command>
  ```

`/catchup` does NOT emit a `[SW-RESUME]` or `[SW-CHECKPOINT]` block. It is recovery tooling, not a phase terminator — the Summary Output above already states the recommended next command plainly, and `/catchup`-specific tooling should read the "Exact command sequence" line rather than a structured marker. See `skills/create-ticket/references/sw-checkpoint-template.md` for the CHECKPOINT contract and the list of skills that DO emit it.

## Error Handling

- **No artifacts found at all**: Phase detection still works — defaults to suggesting **investigate** as the first step.
- **Researcher agent failure**: Report error but still proceed with phase detection using pre-computed context.
- **Ambiguous state**: Present detection result with reasoning, ask user to confirm or choose differently.
