---
name: catchup
description: >-
  Recovers branch state and recommends the next development action after a
  context reset. Activates when (1) starting a fresh session on an existing
  branch with unknown progress, (2) resuming after `/compact` or `/clear`
  drops in-flight state, or (3) the operator is unsure which phase
  (investigate / plan / implement / test / review / commit) to run next.
  Reads `phase-state.yaml`, compact-state snapshots, session logs, and
  artifact directories to detect the current phase and print an exact
  command sequence. Triggers on "catchup", "what's next", "resume work",
  "recover context", "next recommended action", "phase detection".
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

`phase-state.yaml` is the **primary** lifecycle source, read before compact-state / session-log in Step 1. Glob both `.simple-workflow/backlog/active/**/phase-state.yaml` and `.simple-workflow/backlog/product_backlog/**/phase-state.yaml` (depth-agnostic), deduplicate by path, then Read each match and Grep top-level scalars (`current_phase`, `last_completed_phase`, `overall_status`, `created`) plus nested `phases.*.started_at`.

Build `phase_state_records = [{dir, location, current_phase, last_completed_phase, overall_status, created, latest_started_at}, ...]` and carry it forward to Steps 2, 4, 5. Set `phase_state_fresh = true` iff the list is non-empty. Then apply dual-state precedence vs any `autopilot-state.yaml` hits.

See [references/phase-state-discovery.md](references/phase-state-discovery.md) for the full Glob patterns, the top-level vs nested scalar matching rule, the dual-state precedence prose, and the freshness-flag derivation rules.

### 1. Compact-State and Session-Log Recovery

Check `.simple-workflow/docs/compact-state/compact-state-*.md` (most recent first). If the latest file starts with `---`, Read it and extract YAML-frontmatter scalars including `date`, `branch`, `active_tickets`, `active_plans`, `latest_eval_round`, `latest_audit_round`, `last_round_outcome`, `in_progress_phase`, plus the per-ticket `tickets` array (each entry keyed by `dir`, with the same four scalars at 4-space indent).

If the latest file lacks `---`, treat as legacy and only retain its existence as a flag for Step 2. If no compact-state exists, fall back to the most recent `.simple-workflow/docs/session-log/session-log-*.md` with YAML frontmatter.

See [references/compact-state-schema.md](references/compact-state-schema.md) for the full field schema and the per-ticket `tickets:` parsing recipe.

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

- **Otherwise**: Spawn the **researcher** agent (pass `simple-workflow:researcher` as the Agent tool `subagent_type`) to analyze:
  - What has changed on this branch vs `<default-branch>`
  - What the changes are trying to accomplish
  - Current state of work (complete, in-progress, blocked)
  - Check `.simple-workflow/backlog/active/` for any active tickets and their artifacts (investigation.md, plan.md, eval-round-*.md)

### 2.5 Advisory Consultation Pre-Check (conditional, only when researcher was spawned)

If the researcher was spawned in Step 2 (Otherwise branch), the return value MUST contain a `**Advisory consultation**:` field per the format in `agents/researcher.md` `## Advisory Capabilities` → `### Consultation reporting format`. Match by regex `^\*\*Advisory consultation\*\*:` on the return value (case-sensitive, line-anchored). Two outcomes:

- **Field present** → emit `[ADVISORY-CONSULT] catchup researcher present` to stderr and proceed to Step 3.
- **Field absent** → emit `[PIPELINE] catchup: ADVISORY-MISSING (agent=researcher)` to stderr; surface the violation in the final session-snapshot summary returned to the user (`/catchup` is read-only and has no phase-state to FAIL, so surfacing is the canonical degradation path); proceed to Step 3 with the partial researcher findings. Do NOT silently re-spawn the researcher — silent omission is a contract violation and re-rolling would mask it.

If the researcher was skipped (any of the three Skip conditions in Step 2 held), §2.5 is a no-op; emit `[ADVISORY-CONSULT] catchup researcher skipped (researcher not spawned)` to stderr for trace symmetry with the gated path and proceed to Step 3.

### 3. Artifact Discovery

Check for existing docs (regardless of whether researcher was spawned):
- `.simple-workflow/docs/plans/` — implementation plans
- `.simple-workflow/docs/research/` — research findings
- `.simple-workflow/backlog/active/` — active tickets and their artifacts
- `.simple-workflow/docs/session-log/session-log-*.md` — most recent session log (if any) for last-known branch state

### 4. Phase Auto-Detection and Guidance

Evaluate the rules below **in order** and use the **first match**. Rule 0 (`phase-state.yaml`) is authoritative and runs strictly before Rule 0-legacy. See [references/phase-detection-rules.md](references/phase-detection-rules.md) for the full mapping tables, precedence prose, per-ticket guidance variants, and the inconsistency-warning contract.

0. **`phase-state.yaml` indicates an in-progress ticket with a completed phase** → map `last_completed_phase` to `/scout {ticket-dir}` | `/impl {plan-path}` | `/ship`.
0-legacy. **Compact-state shows an in-progress `/impl` loop** (no Rule 0 match) → recommend resuming `/impl` for the named ticket(s).
1. **No research files for current topic** → suggest `/investigate <topic>`.
2. **Research exists, no plans** → suggest `/plan2doc <feature>`.
3. **Plans exist, no code diff from default branch** → suggest `/impl`.
4. **Code diff exists, no test changes** → suggest `/test <changed files>`.
5. **Tests exist, no review files** → suggest `/audit`.
6. **Review done, uncommitted changes** → suggest `/ship`.

Present the detection result with reasoning, including any ticket directory information from `.simple-workflow/backlog/active/`. If the user specified a phase via `$ARGUMENTS`, skip detection and go directly to the guidance for that phase.

### 5. Summary Output

Print a concise summary:
- Current situation (branch, what's been done)
- Active tickets in `.simple-workflow/backlog/active/` (list ticket-dir name and available artifacts)
- If `phase_state_records` (from Step 1-pre) is non-empty, also list each record's `{dir} phase={current_phase} last_completed={last_completed_phase} status={overall_status}` — this is the authoritative lifecycle state and takes precedence over compact-state-derived information
- If a YAML-frontmatter compact-state was parsed in Step 1, also list the `active_tickets` recorded at compact time (these are the tickets the user was focused on at the moment of compaction — they may differ from the current `.simple-workflow/backlog/active/` listing if filesystem state has drifted)
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
