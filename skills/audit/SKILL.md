---
name: audit
description: >-
  Comprehensive multi-agent code audit using code-reviewer and
  security-scanner. Always runs security-scanner. Set only_security_scan=true
  to skip code-reviewer (security-only mode). Use to verify changes before
  shipping or as part of /impl review loop.
disable-model-invocation: true
allowed-tools:
  - Agent
  - Read
  - Glob
  - Grep
argument-hint: "[only_security_scan=true|false] [branch or commit range (optional)]"
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
- Any other tokens are treated as an optional commit/branch range hint, passed through to the agents as additional context.

### 1. Determine Output Destinations

- Get the current branch name from the pre-computed context above.
- List directories in `.backlog/active/` from the pre-computed context above.
- Match the current branch name against active ticket directory slugs (branch name contains the slug).
- If a match is found: set `ticket-dir` to `.backlog/active/{slug}`.
  - Code-reviewer output (when invoked): `{ticket-dir}/quality-round-{n}.md` where `{n}` is the next available number — check existing `quality-round-*.md` files in `ticket-dir`, take max + 1, or 1 if none.
  - Security-scanner output (always invoked): `{ticket-dir}/security-scan-{n}.md` where `{n}` is the next available number — check existing `security-scan-*.md` files in `ticket-dir`, take max + 1, or 1 if none.
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

## Error Handling

- **No changes at all**: Print "No changes to audit." and return Status: PASS with all counts at 0.
- **code-reviewer agent failure**: Treat code-reviewer counts as 0, set Status based on security-scanner only. Note the failure in the Summary.
- **security-scanner agent failure**: Treat security-scanner counts as 0, set Status based on code-reviewer only (or PASS if also skipped). Note the failure in the Summary.
- **Both agents fail**: Status: FAIL. Summary: "All review agents failed."
- **Invalid only_security_scan value** (e.g., `only_security_scan=yes`): Print warning and treat as `false` (default behavior).
