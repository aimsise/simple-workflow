# phase-state.yaml primary state discovery

This reference documents the full discovery logic for the `phase-state.yaml` primary read performed in `### 1-pre.` of `skills/catchup/SKILL.md`. It is the source of truth for the Glob patterns, top-level vs nested scalar rules, dual-state precedence prose, and freshness-flag derivation rules. The SKILL.md body summarises the contract and links here for the mechanical detail.

## Why `phase-state.yaml` is read first

`phase-state.yaml` is the **primary** source of truth for ticket lifecycle state, read **before** the compact-state / session-log sources in Step 1. See `skills/create-ticket/references/phase-state-schema.md` for the canonical schema.

## Glob patterns (depth-agnostic across both ticket locations)

Use the `Glob` tool to enumerate state files across **both** ticket locations. Patterns are **depth-agnostic** so both the legacy flat layout (`.simple-workflow/backlog/active/{NNN}-{slug}/`) and the nested layouts (`.simple-workflow/backlog/active/{parent-slug}/{NNN}-{slug}/`, or deeper) are discovered with a single Glob call per location:

- `.simple-workflow/backlog/active/**/phase-state.yaml`
- `.simple-workflow/backlog/product_backlog/**/phase-state.yaml`

After collecting matches, **deduplicate** by the resolved file path — if the same `phase-state.yaml` is returned by two Glob patterns (e.g. because a fallback pattern also fires), render it exactly once. Depth-agnostic globs plus the dedup step together guarantee that a triple-nested ticket (`.simple-workflow/backlog/active/alpha/beta/003-deep/phase-state.yaml`) is listed once, not three times.

Product-backlog tickets sit at `last_completed_phase: create_ticket` with `overall_status: in-progress` — they are real in-progress records that Rule 0 must be able to recommend `/scout` for. Missing this location caused the pre-PR-E discovery gap (Reviewer B Findings 3, 4).

## Top-level vs nested scalar matching rule

For each match, use the `Read` tool to load the file, then use `Grep` on the in-memory content (via line-prefix matching — NOT shell pipelines; the allowed-tools of this skill do not include shell piping, consistent with AC 4.7) to extract per-ticket records:

- `current_phase` (top-level scalar: `create_ticket | scout | impl | ship | done`)
- `last_completed_phase` (top-level scalar: `create_ticket | scout | impl | ship | null`)
- `overall_status` (top-level scalar: `in-progress | blocked | done | failed`)
- `created` (top-level ISO-8601 scalar)
- For each phase section under `phases:` where present, its `started_at` scalar (used to resolve the "most recent" tie-break in Rule 0 — formerly Rule 0.5 before the precedence flip in Task 7)

Match only **top-level** scalars for `current_phase`, `last_completed_phase`, `overall_status` (lines whose content starts at column 0). Do not confuse them with identically-named nested keys under `phases:` which are indented.

## Per-ticket record list

Build an ordered per-ticket record list `phase_state_records = [{dir, location, current_phase, last_completed_phase, overall_status, created, latest_started_at}, ...]`. The `location` field is `active` when the file path matches `.simple-workflow/backlog/active/` and `product_backlog` when it matches `.simple-workflow/backlog/product_backlog/` — Rule 0's `{ticket-dir}` output includes the full prefix (e.g. `.simple-workflow/backlog/product_backlog/001-foo`) so the recommended command resolves correctly without the user having to guess the location. The `latest_started_at` field is the maximum `phases.{phase}.started_at` across that ticket's phase sections; when no `started_at` is present, fall back to `created`. Carry this list forward to Steps 2, 4, and 5.

## Freshness flag derivation rule (`phase_state_fresh`)

**Freshness flag**: If `phase_state_records` is non-empty (i.e. the `Glob` above found at least one valid `phase-state.yaml`), set `phase_state_fresh = true`; otherwise `phase_state_fresh = false`. The flag is consumed in Step 2 to decide whether to skip the researcher subagent — when the unified state file is present it already carries the per-phase records forward, so there is nothing a deep research pass would add. This simpler rule (presence, not mtime) replaces the prior 1-hour mtime check; it removes the need for the `Bash(stat:*)` permission without weakening the researcher-skip guarantee, because every state-file update is accompanied by a CHECKPOINT emission that is already the strongest "recently touched" signal available in the catchup flow.

## Dual-state precedence (autopilot-state.yaml)

**Dual-state precedence check (autopilot-state.yaml)**: After building `phase_state_records`, additionally `Glob` for `autopilot-state.yaml` under `.simple-workflow/backlog/briefs/active/**/` and `.simple-workflow/backlog/active/**/` (depth-agnostic — nested parent-slug layouts are common). For each hit, apply the precedence rule documented in `skills/create-ticket/references/phase-state-schema.md` §5 ("Dual-state precedence"):

- During `/autopilot` execution, `autopilot-state.yaml` is authoritative for pipeline orchestration; `phase-state.yaml` is maintained in parallel.
- Outside autopilot, `phase-state.yaml` is authoritative.

Concretely, when both `autopilot-state.yaml` and `phase-state.yaml` exist for the same ticket, prefer `autopilot-state.yaml` when the ticket is under `.simple-workflow/backlog/briefs/active/` (i.e. an autopilot-managed brief currently being orchestrated); otherwise prefer `phase-state.yaml`. This drops the prior mtime-based tiebreak (and the `Bash(stat:*)` permission that enabled it) but preserves the important rule: autopilot-driven tickets defer to `autopilot-state.yaml` because it is the orchestration source-of-truth while the pipeline is running.

When `autopilot-state.yaml` wins precedence, annotate the corresponding record (or add a new record when no `phase-state.yaml` exists for that ticket) with `source: autopilot-state` and prefer it for Rule 0 guidance. Emit a warning line `autopilot-state.yaml is authoritative for {ticket-dir} (autopilot-managed brief); deferring to autopilot-state per dual-state precedence.` The full fold-in of `autopilot-state.yaml` into `phase-state.yaml` is deferred — see `skills/create-ticket/references/autopilot-foldin.md`.

## Empty-result fallthrough

**If no `phase-state.yaml` file exists anywhere in `.simple-workflow/backlog/active/` OR `.simple-workflow/backlog/product_backlog/`**, set `phase_state_records = []` and fall through to Step 1 unchanged (AC 4.5 — existing compact-state + artifact-discovery behavior is preserved).
