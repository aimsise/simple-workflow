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

### 1a. Resolve Category and Checklist Body

Before spawning agents, resolve the per-ticket Category and the matching
checklist body that will be propagated to each agent. The canonical
checklist source is `skills/audit/references/categories.md`; this path is
recorded verbatim in the dispatch log so the propagation is auditable.

When `ticket-dir` is set (Step 1 resolved a path under
`.simple-workflow/backlog/active/{dir-name}`), read `{ticket-dir}/ticket.md`
and locate the row whose first cell is exactly `Category` (the ticket
metadata table uses Markdown table rows of the form
`| Category | <value> |`).

Apply the following parsing rules:

- **Multiple Category rows** (Edge Case 1): if `ticket.md` contains more
  than one row whose first cell is `Category`, use the **first**
  occurrence's value verbatim AND emit the literal line
  `warn: multiple Category rows in ticket.md` to stderr. Do NOT abort.
- **Trailing whitespace** (Edge Case 3): strip leading and trailing
  whitespace from the extracted Category value before any further use
  (e.g., `Security ` becomes `Security`; the dispatch log MUST record
  the stripped form).
- **No Category row** (Negative AC 1): if no row matches, treat the
  Category as `unspecified` for dispatch-log purposes and skip checklist
  selection.
- **Unknown / lowercase Category** (Negative AC 4): the value is passed
  through verbatim. No rejection. No mapping. If the value does not
  match one of the six canonical `## Category: <name>` headers in
  `skills/audit/references/categories.md`, no checklist body is
  selected; the agents receive the file path and the verbatim Category
  value, and they fall back to their default review heuristics.

Selecting the checklist body (canonical six only):

- The canonical six values are `CodeQuality`, `Security`, `Performance`,
  `Reliability`, `Documentation`, `Testing`.
- When the resolved Category exactly matches one of the six, extract the
  body of `skills/audit/references/categories.md` between the line
  `## Category: <CategoryName>` and the next `## Category:` header (or
  end-of-file). This body — including its `- [ ] <item>` checklist
  items — is the **selected checklist body**.
- The selected checklist body MUST be passed verbatim to both
  `code-reviewer` and `security-scanner` as part of the agent prompt,
  with explicit instruction to evaluate each item and to emit a line of
  the form `- [ ] <item> (Category: <CategoryName>)` (or `- [x] ...`
  for items addressed by the changes) into its report file.

When `ticket-dir` is NOT set (no active ticket detected): skip the
ticket.md read, skip checklist selection, and skip the dispatch-log
write described in Step 1b. Audit proceeds without category
propagation.

### 1b. Write Dispatch Log

When `ticket-dir` is set, write the dispatch log to
`{ticket-dir}/audit-dispatch.log` BEFORE spawning the agents. The file
is a plain text key=value log used by tests and downstream tooling to
verify the propagation contract.

Content format (exact, no extra fields, one key per line):

```
category=<value>
checklist_source=skills/audit/references/categories.md
```

Rules:

- `<value>` is the verbatim Category value resolved in Step 1a (after
  trailing-whitespace stripping). If no Category row was present in
  `ticket.md`, write `category=unspecified`.
- The literal string `checklist_source=skills/audit/references/categories.md`
  MUST appear on its own line, even when the resolved category is
  `unspecified` or an unknown value. The log records that this is the
  source consulted, not that a body was selected.
- Use UTF-8, LF line endings, no surrounding quotes.
- The file is overwritten on every `/audit` invocation against the
  same ticket directory (one log per audit run; the round number is
  captured in `audit-round-{n}.md` instead).

When `ticket-dir` is NOT set, do NOT write a dispatch log.

### 2. Spawn Agents

**MUST invoke the `security-scanner` agent via the Agent tool** (sonnet) — **NEVER bypass security-scanner** even when changes appear security-irrelevant; the agent itself decides what is in scope. Fail this audit immediately if security-scanner cannot be invoked.
- Pass the changed files list and the security-scan output path determined in step 1.
- When a checklist body was selected in Step 1a, pass it verbatim as part
  of the agent prompt and instruct security-scanner to evaluate each
  `- [ ] <item>` line and emit `- [ ] <item> (Category: <CategoryName>)`
  (or `- [x] ...`) lines into its report.
- Receive Critical / Warnings / Suggestions counts and a summary.
- Note: security-scanner is always invoked regardless of whether sensitive files appear to be touched. The agent itself decides what is security-relevant.

**If** `only_security_scan` is `false` (default), you **MUST also invoke the `code-reviewer` agent via the Agent tool** (sonnet) **in parallel** with security-scanner. **NEVER bypass code-reviewer via direct file inspection** from within `/audit`. Fail this audit immediately if code-reviewer cannot be invoked (treat as Critical = 1 per the Error Handling section):
- Pass the changed files list and the quality-round output path determined in step 1.
- When a checklist body was selected in Step 1a, pass it verbatim as part
  of the agent prompt and instruct code-reviewer to evaluate each
  `- [ ] <item>` line and emit `- [ ] <item> (Category: <CategoryName>)`
  (or `- [x] ...`) lines into its report.
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
- The file content is the same 7-line `**Status**:...**Summary**:...` block printed in Step 4.
- **Category-tagged checklist transcription** (when a checklist body was
  selected in Step 1a): append, after the structured block, the
  evaluated checklist items reported by the spawned agents. Each
  transcribed item MUST appear on its own line, outside fenced code
  blocks and outside HTML comments, in the exact form
  `- [ ] <item> (Category: <CategoryName>)` for unaddressed items or
  `- [x] <item> (Category: <CategoryName>)` for items the changes
  addressed. At least one such line MUST be present whenever the
  ticket's Category matches one of the canonical six. When the
  Category is `unspecified` or an unknown value, no such lines are
  required.
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
