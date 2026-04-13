---
name: audit
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Comprehensive multi-agent code audit using code-reviewer and
  security-scanner. Always runs security-scanner. Set only_security_scan=true
  to skip code-reviewer (security-only mode). Use to verify changes before
  shipping or as part of /impl review loop.
disable-model-invocation: false
allowed-tools:
  # Claude Code
  - Agent
  - Read
  - Glob
  - Grep
  # Copilot CLI
  - task
  - view
  - glob
  - grep
argument-hint: "[only_security_scan=true|false] [round=N] [branch or commit range (optional)]"
---

Audit current code changes. Args: $ARGUMENTS

Current branch:
!`git branch --show-current`

Active tickets:
!`ls -d .backlog/active/*/ 2>/dev/null || echo "(none)"`

Staged changes:
!`git diff --cached --stat`

Unstaged changes:
!`git diff --stat`

Changed files:
!`git diff --cached --name-only && git diff --name-only`

## Instructions

### 0. Argument Parsing

Parse `$ARGUMENTS` for the following:
- `only_security_scan=true` (case-insensitive): set the flag to skip code-reviewer.
- `only_security_scan=false`: explicit default (run both agents).
- If neither token is present, default `only_security_scan=false`.
- `round=N` (case-insensitive, N is a positive integer): explicit round number for output filenames. When provided, the skill MUST write to `quality-round-{N}.md`, `security-scan-{N}.md`, and `audit-round-{N}.md` using this number instead of auto-incrementing. This lets the calling skill (e.g. `/impl`) synchronize audit round numbers with its own Generator-Evaluator loop counter. If N is ≤ 0 or not an integer, print a warning and fall back to auto-increment.
- If `round=` is absent, use the current behavior (auto-increment: max existing round + 1).
- Any other tokens are treated as an optional commit/branch range hint, passed through to the agents as additional context.

### 1. Determine Output Destinations

- Get the current branch name from the pre-computed context above.
- List directories in `.backlog/active/` from the pre-computed context above.
- Match the current branch name against active ticket directories. For each directory in `.backlog/active/`, extract the slug portion by stripping the leading `NNN-` prefix (the initial sequence of digits followed by a hyphen, e.g., `001-add-search-feature` → `add-search-feature`). Check if the branch name contains this slug portion.
- If a match is found: set `ticket-dir` to `.backlog/active/{full-directory-name}` (including the numeric prefix).
  - If `round=N` was parsed in Step 0, use `{N}` as the round number for all output files.
  - Otherwise, auto-increment: check existing `quality-round-*.md` files in `ticket-dir`, take max + 1, or 1 if none.
  - Code-reviewer output (when invoked): `{ticket-dir}/quality-round-{n}.md`
  - Security-scanner output (always invoked): `{ticket-dir}/security-scan-{n}.md`
- If no match: use defaults (code-reviewer: `.docs/reviews/{topic}.md`, security-scanner: `.docs/reviews/security-{topic}.md`) where `{topic}` is derived from the current branch name.

### 2. Spawn Agents

**Always** spawn the **security-scanner** agent (`security-scanner`, sonnet):
- Pass the changed files list and the security-scan output path determined in step 1.
- Receive Critical / Warnings / Suggestions counts and a summary.
- Note: security-scanner is always invoked regardless of whether sensitive files appear to be touched. The agent itself decides what is security-relevant.

**If** `only_security_scan` is `false` (default), **also** spawn the **code-reviewer** agent (`code-reviewer`, sonnet) **in parallel** with security-scanner:
- Pass the changed files list and the quality-round output path determined in step 1.
- Receive Critical / Warnings / Suggestions counts and a summary.

If `only_security_scan` is `true`, the code-reviewer is **skipped** (security-only mode).

Do NOT read files directly — delegate ALL review work to the agents.

### 3. Aggregate Results

Combine the results from the spawned agents into a single aggregated report:

- `Critical` = sum of Critical counts from all spawned agents (security-scanner always; code-reviewer when not skipped).
- `Warnings` = sum of Warnings counts from all spawned agents.
- `Suggestions` = sum of Suggestions counts from all spawned agents.
- Determine `Status`:
  - If `Critical > 0` → `FAIL`
  - Else if `Warnings > 0` or `Suggestions > 0` → `PASS_WITH_CONCERNS`
  - Else → `PASS`

The aggregated counts MUST be calculated across both agents (or just security-scanner when code-reviewer is skipped).

### 4. Return Structured Result

First, print a human-readable summary of the most important findings (Critical issues first, then Warnings, then Suggestions) with file:line references where available.

Then, print exactly the following structured block at the end of your output (this is parseable by the calling skill):

```
**Status**: <PASS | PASS_WITH_CONCERNS | FAIL>
**Critical**: <N>
**Warnings**: <N>
**Suggestions**: <N>
**Reports**:
  - Code review: <path or "skipped (only_security_scan=true)">
  - Security scan: <path>
**Summary**: <one-line aggregated summary across all spawned agents>
```

### 4a. Persist Aggregated Result (when ticket-dir is set)

If an active ticket directory was detected in Step 1 (`ticket-dir`):
- Write the structured result block below to `{ticket-dir}/audit-round-{n}.md`, where `{n}` is the same round number used for `quality-round-{n}.md` / `security-scan-{n}.md` in Step 1 (the explicit `round=N` value if provided, else the auto-incremented value).
- The file content is exactly the same 7-line `**Status**:...**Summary**:...` block printed in Step 4 (no extra header, no extra text).
- This file is consumed by `hooks/pre-compact-save.sh` to compute `last_round_outcome` in the compact-state snapshot, which in turn drives `/catchup` Rule 0 (impl-loop resume detection).

If no ticket directory was detected, skip this persistence step (no audit-round file is written for non-ticket flows).

## Error Handling

- **No changes at all**: Print "No changes to audit." and return Status: PASS with all counts at 0.
- **Single agent failure (the other succeeded)**: Return Status: FAIL with Critical = 1 (counting "review infrastructure failure" as a Critical finding).
  The Summary MUST explicitly name the failed agent and the failure reason.
  Do NOT silently set counts to 0 — a partial review is not enough evidence to return PASS or PASS_WITH_CONCERNS.
  **Never silently treat a failed agent as PASS or PASS_WITH_CONCERNS.**
  Example: "**Status**: FAIL | **Summary**: security-scanner failed (timeout) — review incomplete; retry required"
- **Both agents fail (or the only requested agent failed)**:
  Do NOT return the structured result block at all. Instead, print the failure details to stderr and exit abnormally.
  This forces the calling skill's fallback (e.g. `/impl` Step 16) to detect "no structured block" and escalate via `AskUserQuestion`.
  Example stderr output:
  "/audit: all spawned agents failed. code-reviewer: <error>. security-scanner: <error>."
- **Invalid only_security_scan value** (e.g., `only_security_scan=yes`): Print warning and treat as `false` (default behavior).
