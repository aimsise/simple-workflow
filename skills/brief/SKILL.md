---
name: brief
description: >-
  Conduct a structured interview to gather requirements and generate
  a brief document with autopilot policy for a new feature or task.
disable-model-invocation: true
allowed-tools:
  # Claude Code
  - Agent
  - Skill
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
  - "Bash(git log:*)"
  - "Bash(git status:*)"
  - "Bash(git diff:*)"
  - "Bash(git branch:*)"
  - "Bash(mkdir:*)"
  - "Bash(mv:*)"
  - "Bash(ls:*)"
  - "Bash(date:*)"
  # Copilot CLI
  - task
  - skill
  - view
  - create
  - glob
  - grep
  - ask_user
  - "shell(git log:*)"
  - "shell(git status:*)"
  - "shell(git diff:*)"
  - "shell(git branch:*)"
  - "shell(mkdir:*)"
  - "shell(mv:*)"
  - "shell(ls:*)"
  - "shell(date:*)"
argument-hint: "<what-to-build> [auto=true]"
---

## Pre-computed Context

Interview templates:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/brief/references/interview-templates.md" 2>/dev/null || echo "[WARNING: interview-templates.md not found]"`

Existing briefs:
!`ls -t .backlog/briefs/active/*/brief.md 2>/dev/null | head -5`

Knowledge base (autopilot patterns):
!`cat .simple-wf-knowledge/index.yaml 2>/dev/null | grep -A2 "^autopilot:" || echo "[No autopilot patterns in knowledge base]"`

# /brief

User input: $ARGUMENTS

## Scope boundary

`/brief` produces two artifacts and stops: `.backlog/briefs/active/{slug}/brief.md` and `.backlog/briefs/active/{slug}/autopilot-policy.yaml`. **`/brief` never writes `split-plan.md`** — ticket decomposition is owned by `/create-ticket` (bare, `brief=<path>`, or `findings=<path>` modes). The obsolete frontmatter fields `split:` and `ticket_count:` are **not emitted** by this skill.

## Argument Parsing

Parse `$ARGUMENTS`:
- Extract `auto=true` if present (case-insensitive). Remove it from the description.
- Remaining text is `<what-to-build>`.
- If `<what-to-build>` is empty, print "Usage: /brief <what-to-build> [auto=true]" and stop.
- Generate `{slug}` from `<what-to-build>` using kebab-case (e.g., "Add User Auth" -> `add-user-auth`). The brief `{slug}` also serves as the `{parent-slug}` downstream (see Finalization CHECKPOINT below).

## Phase 1: Initial Investigation

1. Spawn the **researcher** agent (sonnet) via the Agent tool:
   - description: "Investigate codebase for: <what-to-build>"
   - Prompt: "Investigate the codebase to understand existing patterns, dependencies, similar features, and technical constraints related to: <what-to-build>. Focus on: (1) existing code patterns and architecture, (2) related dependencies, (3) similar existing features, (4) potential technical constraints. Return a concise summary under 500 tokens."
   - model: sonnet
2. Save the researcher's summary for use in Phase 2 and Phase 3.

## Phase 2: Structured Interview (Socratic)

Conduct an iterative Q&A to gather comprehensive requirements.

**`auto=true` independence guard (load-bearing)**: Phase 2 Structured Interview (Socratic) **MUST** run regardless of whether `auto=true` was passed in `$ARGUMENTS`. `auto=true` **MUST NOT** be interpreted as a signal to skip, shorten, or bypass Phase 2 — it has **no effect whatsoever** on Phase 2's execution. Any non-interactive wording elsewhere in this skill (for example, in the Finalization Phase Step 2 chain-confirmation context) is scoped to that specific step and **MUST NOT** be generalized to Phase 2. The **ONLY** condition under which Phase 2 is skipped is the existing **"Non-interactive environment fallback"** defined below (triggered strictly by `AskUserQuestion` itself being unavailable or returning an error, e.g. `claude -p` / CI automation without a TTY) — **not** by the presence of `auto=true`.

**Caps (load-bearing for contract)**:
- At most **3 questions per round** (single `AskUserQuestion` call holds up to 3 items).
- At most **10 rounds** total.
- Therefore at most **30 questions total** across the entire interview before `brief.md` is written.
- Track a round counter starting at `0`. Increment **after** each user response is received (a round is counted only when the user actually responded — i.e., Phase 2 truly ran at least once).

**Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), skip Phase 2 entirely and proceed directly to Phase 3 with the researcher's findings only. In this case, set `interview_complete: false` for the frontmatter (Phase 3) and do NOT count any rounds. Note "Phase 2 skipped (non-interactive mode)" in the final summary. Do NOT hang waiting for input.

For each round (up to 10 rounds, at most 3 questions per round, at most 30 questions total):

1. Based on the researcher's findings and any previous answers, identify the most important unanswered questions from the interview templates (see Pre-computed Context above).
2. Select **up to 3** questions from the template categories that are most relevant and not yet answered. Adapt the questions based on the specific context — do not ask generic template questions verbatim. The `AskUserQuestion` call in a single round MUST carry at most 3 items.
3. Use `AskUserQuestion` to ask the selected questions.
4. After receiving answers, output a brief summary of "Current understanding" to the user:
   - What is known so far
   - What categories still need information
5. **Convergence check**: Stop the interview if ANY of these conditions are met:
   - The user responds with "sufficient", "enough", or similar.
   - All 7 categories (see `references/interview-templates.md`) have sufficient information.
   - **10 rounds have been completed** (hard ceiling; combined with the 3/round cap this also enforces the 30-questions-total ceiling).
6. Continue to next round if convergence is not reached and the round counter is below 10.

At the end of Phase 2, record `interview_complete = true` iff **at least one round produced a user response**; otherwise `interview_complete = false` (non-interactive fallback, or `AskUserQuestion` returned an error before any answer was received).

## Phase 3: Brief Document Generation

1. Create directory: `mkdir -p .backlog/briefs/active/{slug}`
2. Synthesize all gathered information into a structured brief document.
3. Estimate the ticket size (S/M/L/XL) based on:
   - S: 1-3 files, simple change
   - M: 4-8 files, moderate complexity
   - L: 9+ files, significant complexity
   - XL: Architecture-level changes
4. Estimate the category: Security / CodeQuality / Doc / DevOps / Community
5. Write to `.backlog/briefs/active/{slug}/brief.md`.

**Frontmatter contract** (brief.md):

```
---
slug: {slug}
created: {date}
status: draft
estimated_size: {S|M|L|XL}
estimated_category: {category}
interview_complete: {true|false}
---
```

- `interview_complete` is the literal scalar recorded at the end of Phase 2 (`true` if at least one round ran to a user response; `false` if Phase 2 was skipped via the non-interactive fallback or no round produced a response).
- **Do NOT emit `split:`** (obsolete — decomposition is `/create-ticket`'s job).
- **Do NOT emit `ticket_count:`** (obsolete — decomposition is `/create-ticket`'s job).

**Body** (after frontmatter):

```
## Vision
[Refined expression of the user's goal]

## Business Context
[Motivation, stakeholders, timeline — from interview or "Not specified"]

## Technical Requirements
[Specific technical requirements gathered from investigation + interview]

## Scope
### In Scope
- [items]
### Out of Scope
- [items, or "Not explicitly defined"]
### Edge Cases
- [case]: [expected behavior]

## Constraints
[Technical constraints, compatibility requirements]

## Quality Expectations
[Test coverage expectations, review requirements]

## Investigation Summary
[Key findings from Phase 1 researcher]
```

## Phase 4: Policy Generation

1. Read `.simple-wf-knowledge/index.yaml` if it exists.
   - Filter entries under the `autopilot` section. These are historical decision patterns (from `/tune` analysis of autopilot-log.md) that inform default policy values.
   - For each gate in the policy template, search the `autopilot` section for patterns whose `summary` matches the gate name (e.g., `ac_eval_fail`, `ship_review_gate`).
2. Determine default policy values based on:
   - User's risk tolerance answers from Phase 2 (maps to conservative/moderate/aggressive). If Phase 2 was skipped (`interview_complete: false`), default to **conservative** and emit default gates.
   - KB autopilot patterns (if any), applying confidence-based 3-tier judgment per gate:
     - confidence >= 0.7 → use the pattern's action as recommended default; append `# kb-suggested` comment to the gate line
     - confidence 0.5-0.7 → use the pattern's action but append `# [low confidence]` comment
     - confidence < 0.5 → use conservative default (stop)
   - **Size-scoped pattern priority**: If the `autopilot` section contains patterns with a `scope` matching the current brief's `estimated_size` (S/M/L/XL), prefer those over patterns with `scope=general`. Fall back to `scope=general` only when no size-specific pattern exists for a gate.
   - If `.simple-wf-knowledge/index.yaml` does not exist or has no `autopilot` section (first run), use conservative defaults for all gates and add `# KB patterns: none` comment to the generated policy file.
3. Write to `.backlog/briefs/active/{slug}/autopilot-policy.yaml` regardless of Phase 2 outcome (policy generation is preserved even when Phase 2 was skipped — the top-level `gates:` line MUST be present):

```yaml
version: 1
risk_tolerance: {conservative|moderate|aggressive}

gates:
  ticket_quality_fail:
    action: retry_with_feedback
    max_retries: 3
    allow_partial_split_commit: false  # opt-in: when true, successful sub-tickets in an N>1 split are committed even if one sub-ticket exhausts retries. Default false preserves the atomic all-or-nothing contract.
  evaluator_dry_run_fail:
    action: {proceed_without|stop}  # conservative=stop, moderate/aggressive=proceed_without
  ac_eval_fail:
    action: retry
    on_critical: stop
  audit_infrastructure_fail:
    action: {treat_as_fail|stop}  # conservative=stop, moderate/aggressive=treat_as_fail
  ship_review_gate:
    action: {proceed_if_eval_passed|stop}  # conservative=stop, moderate/aggressive=proceed_if_eval_passed
  ship_ci_pending:
    action: wait
    timeout_minutes: {30|60}  # conservative/moderate=30, aggressive=60
    on_timeout: stop
  unexpected_error:
    action: stop

constraints:
  max_total_rounds: {9|12}  # conservative/moderate=9, aggressive=12
  allow_breaking_changes: {false|true}  # conservative/moderate=false, aggressive=true
```

The split judgement that used to live here has been removed: `/brief` no longer analyzes `estimated_size` L / XL to produce `split-plan.md`. `/create-ticket brief=<path>` receives the brief and is responsible for decomposing the scope (via its `planner` Split Judgment or via `findings=<path>` mode + `decomposer`). See `.docs/fix_structure/spec-migration-policy.md` for the updated ownership boundary.

## Finalization: Output, `auto=true` handoff, and SW-CHECKPOINT

This is the final phase of `/brief`. It handles the summary print, the optional `auto=true` confirmation + chained skill invocations, and the mandatory SW-CHECKPOINT emission. **No further file writes occur after this phase**.

### Step 1 — Summary

Print:
- Brief file path: `.backlog/briefs/active/{slug}/brief.md`
- Policy file path: `.backlog/briefs/active/{slug}/autopilot-policy.yaml`
- Estimated size and category
- Interview outcome (`interview_complete: true|false`); if true, number of rounds actually completed

### Step 2 — `auto=true` handoff

Only runs when `auto=true` was parsed from arguments. Within **Step 2's chain-confirmation context**, the flow is strictly linear (display → status update → auto-kick write → `/create-ticket` → `/autopilot`): Step 2 **MUST NOT** call `AskUserQuestion`, nor otherwise prompt the user for a yes/no confirmation, to gate the chain between these sub-steps. The brief + policy display in (a) is the only user-facing surface in this branch and is a passive display — it does not gate the chain.

**Scope disclaimer (Step 2-only)**: The non-interactive restriction described above is **scoped exclusively to Step 2's chain confirmation**. It **MUST NOT** be generalized to the rest of `/brief`. In particular, **Phase 2 Structured Interview (Socratic) is independent of this restriction and MUST run regardless of whether `auto=true` was passed** — `auto=true` has no effect on Phase 2's behavior. Phase 2 is the requirements-gathering interview and is governed solely by its own rules (see `## Phase 2` above).

a. Display the brief content and policy content to the user. This display is passive — it informs the user of what will be chained but does not pause for acknowledgement.
b. Update `brief.md` `status:` from `draft` to `confirmed`.
c. **Before invoking `/create-ticket` via the Skill tool**, write the auto-kick state file at `.backlog/briefs/active/{slug}/auto-kick.yaml` with the following sample shape (use `date -u +%Y-%m-%dT%H:%M:%SZ` for `started`):

   ```yaml
   version: 1
   slug: {slug}
   started: {ISO-8601 UTC from `date -u +%Y-%m-%dT%H:%M:%SZ`}
   ```

   This file signals the Stop hook that the auto-chain is mid-flight between `/brief` → `/create-ticket` → `/autopilot`; it is deleted by `/autopilot` Phase 1 on startup.
d. **MUST invoke `/create-ticket` via the Skill tool** with argument `brief=.backlog/briefs/active/{slug}/brief.md`.
e. If `/create-ticket` exits non-zero (or its SW-CHECKPOINT block indicates a failure path), **stdout MUST contain the literal string `ERROR:` AND the literal string `create-ticket failed`**; `/autopilot` MUST NOT be invoked. **Before emitting the failure-path SW-CHECKPOINT, delete `.backlog/briefs/active/{slug}/auto-kick.yaml`** (idempotent — missing file is not an error). This prevents a stale auto-kick flag from looping the Stop hook indefinitely after a brief-side abort. Skip directly to Step 4 (SW-CHECKPOINT) with the failure recommendation shape.
f. Otherwise (`/create-ticket` succeeded), proceed to the final invocation:

   > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: `auto-kick.yaml` is present at `.backlog/briefs/active/{slug}/auto-kick.yaml`. Invoke `/autopilot {slug}` via the Skill tool now. Do NOT end your turn or summarize.

   **MUST invoke `/autopilot` via the Skill tool** with argument `{slug}` (the brief's slug, which is also the `parent-slug` that `/create-ticket` wrote under `.backlog/product_backlog/{slug}/`).

### Step 3 — `auto=true` NOT specified

Print:

```
Brief generated. To proceed:
1. Review and edit the brief if needed
2. Update status to 'confirmed' in brief.md frontmatter
3. Run /create-ticket brief=.backlog/briefs/active/{slug}/brief.md to produce the ticket set
4. Run /autopilot {slug} to drive the full pipeline
```

### Step 4 — Emit the final `## [SW-CHECKPOINT]` block

The block MUST be the LAST section of the skill's output. Format + the literal `context_advice` sentence are defined **once** in `skills/create-ticket/references/sw-checkpoint-template.md`; emit the block verbatim per that template (including the literal `context_advice:` sentence shown there — do NOT retype it here).

Fields:
- `phase: brief`
- `ticket: none`
- **Success path** (`brief.md` + `autopilot-policy.yaml` both written successfully):
  - `artifacts:` — list containing the two repo-relative paths: `.backlog/briefs/active/{slug}/brief.md` and `.backlog/briefs/active/{slug}/autopilot-policy.yaml`.
  - Emit EXACTLY ONE line matching `^next_recommended_auto:[[:space:]]+/autopilot[[:space:]]+\S+$` with value `/autopilot {slug}`.
  - Emit EXACTLY ONE line matching `^next_recommended_manual:[[:space:]]+/create-ticket[[:space:]]+brief=\S+$` with value `/create-ticket brief=.backlog/briefs/active/{slug}/brief.md`.
  - Do NOT emit a bare `next_recommended:` line alongside these two.
  - The `{slug}` attached to `/autopilot` is the brief's `{slug}` (= `parent-slug` downstream; they are aliases in this skill).
- **Failure path** (any write failure — `mkdir` failed, `brief.md` write failed, `autopilot-policy.yaml` write failed, or `auto=true` chained `/create-ticket` failed):
  - `artifacts: []` on a single line.
  - Emit BOTH recommendation lines with empty-string values: `next_recommended_auto: ""` AND `next_recommended_manual: ""`.
  - AC #11's regex does not match empty-string values, so downstream automation does not misfire after a `/brief` error. Both keys are still present (shape-preserving) so parsers can distinguish "brief emitted a failure block" from "no block at all".

In both shapes both recommendation keys are present; only their values differ.

## Error Handling

- **Empty arguments**: Print "Usage: /brief <what-to-build> [auto=true]" and stop.
- **Researcher failure**: Report error. Continue to Phase 2 without investigation summary.
- **AskUserQuestion failure in Phase 2**: Skip Phase 2, proceed with researcher findings only; set `interview_complete: false`.
- **Write failure** (brief.md or autopilot-policy.yaml): Report the error and emit the failure-path SW-CHECKPOINT from Step 4 (empty-string recommendations, `artifacts: []`).
- **`auto=true` path — `/create-ticket` chained invocation fails**: stdout MUST contain `ERROR:` AND `create-ticket failed`. Do NOT invoke `/autopilot`. Emit the failure-path SW-CHECKPOINT from Step 4.
