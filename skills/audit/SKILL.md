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
argument-hint: "[only_security_scan=true|false] [round=N] [ticket-dir=<dir-name>] [branch or commit range (optional)]"
---

Audit current code changes. Args: $ARGUMENTS

## Mandatory Skill Invocations

The following agent invocations are **contractual** — `/audit` MUST delegate to each of these via the Agent tool (in parallel when both are requested). `/audit` itself performs no review work; its entire role is to spawn the review agents, aggregate their counts, and return a structured result block. Any bypass is a contract violation and will be detected by the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `security-scanner` agent (Agent tool) | Step 2 — **always**, regardless of `only_security_scan` flag | No security review; hardcoded secrets / injection vulnerabilities may reach `done/` undetected. Detected by absence of `security-scan-{n}.md` in ticket dir and absence of security-scanner trace in skill invocation audit |
| `code-reviewer` agent (Agent tool) | Step 2 — in parallel with security-scanner when `only_security_scan=false` (default) | No code quality review; `/impl`'s retry loop has no feedback on style/maintainability/correctness concerns. Detected by absence of `quality-round-{n}.md` in ticket dir |

**Binding rules**:
- `MUST invoke security-scanner via the Agent tool` every time `/audit` runs — never skip security review even when changes look "obviously safe".
- `MUST invoke code-reviewer via the Agent tool` unless `only_security_scan=true` was explicitly passed. Never substitute by having `/audit` itself read files and render a verdict.
- `NEVER bypass these agents via direct file operations` — `/audit` must NOT read the changed files itself (Step 2 explicitly states: "Do NOT read files directly — delegate ALL review work to the agents").
- `Fail this audit immediately if any required agent cannot be invoked via the Agent tool` — the Error Handling section treats agent failure as Critical = 1; **never silently treat a failed agent as PASS or PASS_WITH_CONCERNS**.

Current branch:
!`git branch --show-current`

Active tickets:
!`ls -d .simple-workflow/backlog/active/*/ 2>/dev/null || echo "(none)"`

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
- `ticket-dir=<dir-name>` (case-insensitive key): ticket directory name (directory name only, not a full path — e.g., `003-fix-login`). When provided, this value is used in Step 1 to construct the full path `.simple-workflow/backlog/active/{dir-name}` instead of inferring the ticket directory from the branch name. This token is consumed by argument parsing and is NOT passed through as a commit/branch range hint.
- Any other tokens are treated as an optional commit/branch range hint, passed through to the agents as additional context.

### 1. Determine Output Destinations

- Get the current branch name from the pre-computed context above.
- List directories in `.simple-workflow/backlog/active/` from the pre-computed context above.

**If `ticket-dir=<dir-name>` was provided in Step 0:**
- Construct the full path: `.simple-workflow/backlog/active/{dir-name}`
- Check whether `.simple-workflow/backlog/active/{dir-name}` exists as a directory.
  - If the directory exists: set `ticket-dir` to `.simple-workflow/backlog/active/{dir-name}` and skip branch name matching entirely.
  - If the directory does NOT exist: print `WARNING: ticket-dir '.simple-workflow/backlog/active/{dir-name}' does not exist; falling back to branch name matching.` and proceed to the branch name matching below as if `ticket-dir=` was not provided.

**If `ticket-dir=` was not provided (or directory does not exist):**
- Match the current branch name against active ticket directories. For each directory in `.simple-workflow/backlog/active/`, extract the slug portion by stripping the leading `NNN-` prefix (the initial sequence of digits followed by a hyphen, e.g., `001-add-search-feature` → `add-search-feature`). Check if the branch name contains this slug portion.
- If a match is found: set `ticket-dir` to `.simple-workflow/backlog/active/{full-directory-name}` (including the numeric prefix).

**Once `ticket-dir` is resolved (by either method above):**
- If `ticket-dir` is set:
  - If `round=N` was parsed in Step 0, use `{N}` as the round number for all output files.
  - Otherwise, auto-increment: check existing `quality-round-*.md` files in `ticket-dir`, take max + 1, or 1 if none.
  - Code-reviewer output (when invoked): `{ticket-dir}/quality-round-{n}.md`
  - Security-scanner output (always invoked): `{ticket-dir}/security-scan-{n}.md`
- If no match: use defaults (code-reviewer: `.simple-workflow/docs/reviews/{topic}.md`, security-scanner: `.simple-workflow/docs/reviews/security-{topic}.md`) where `{topic}` is derived from the current branch name.

### 2. Spawn Agents

**MUST invoke the `security-scanner` agent via the Agent tool** (sonnet) — **NEVER bypass security-scanner** even when changes appear security-irrelevant; the agent itself decides what is in scope. Fail this audit immediately if security-scanner cannot be invoked.
- Pass the changed files list and the security-scan output path determined in step 1.
- Receive Critical / Warnings / Suggestions counts and a summary.
- Note: security-scanner is always invoked regardless of whether sensitive files appear to be touched. The agent itself decides what is security-relevant.

**If** `only_security_scan` is `false` (default), you **MUST also invoke the `code-reviewer` agent via the Agent tool** (sonnet) **in parallel** with security-scanner. **NEVER bypass code-reviewer via direct file inspection** from within `/audit`. Fail this audit immediately if code-reviewer cannot be invoked (treat as Critical = 1 per the Error Handling section):
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
