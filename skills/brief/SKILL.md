---
name: brief
description: >-
  Conducts a structured Socratic interview that gathers requirements, then
  writes a brief and an autopilot policy file for a new feature or task.
  Use when (1) a user starts /brief with a feature description, (2) requirements
  are unclear and need iterative Q&A, or (3) downstream skills (/create-ticket,
  /autopilot) need a structured brief artifact. Triggers on "/brief", "draft a
  brief", "start a new feature brief", "feature scoping interview".
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
argument-hint: "<what-to-build> [mode=auto|manual]"
---

## Pre-computed Context

Interview templates:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/brief/references/interview-templates.md" 2>/dev/null || echo "[WARNING: interview-templates.md not found]"`

Existing briefs:
!`ls -t .simple-workflow/backlog/briefs/active/*/brief.md 2>/dev/null | head -5`

Knowledge base (autopilot patterns):
!`cat .simple-workflow/kb/index.yaml 2>/dev/null | grep -A2 "^autopilot:" || echo "[No autopilot patterns in knowledge base]"`

# /brief

User input: $ARGUMENTS

## Scope boundary

`/brief` produces two artifacts and stops: `.simple-workflow/backlog/briefs/active/{slug}/brief.md` and `.simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml`. **`/brief` never writes `split-plan.md`** — ticket decomposition is owned by `/create-ticket`. Obsolete frontmatter fields `split:` and `ticket_count:` are **not emitted**.

## Argument Parsing

Parse `$ARGUMENTS`:
- Extract `mode=<value>` if present. **Value normalization**: trim whitespace and lowercase the value (`mode=AUTO`, `mode=Manual`, `mode= auto ` normalize to `auto`/`manual`). Token `mode=` is matched case-insensitively. Accepted: `auto` (default if `mode=` is omitted), `manual`. Any other value → stop and emit the invalid-mode error (see ## Error Handling for exact message + side-effect contract).
- **`auto=true` removal (v6.0.0)**: if `auto=true` (case-insensitive) appears in `$ARGUMENTS`, stop and emit the v6.0.0 removal error (see ## Error Handling). The removal is intentional and `auto=true` is NOT silently rewritten.
- Remove the parsed `mode=` token from the description; remaining text is `<what-to-build>`.
- If `<what-to-build>` is empty, print `Usage: /brief <what-to-build> [mode=auto|manual]` and stop.
- Generate `{slug}` from `<what-to-build>` using kebab-case (e.g., "Add User Auth" -> `add-user-auth`). The brief `{slug}` also serves as the `{parent-slug}` downstream.

## Phase 1: Initial Investigation

1. Spawn the **researcher** agent (sonnet) via the Agent tool:
   - description: "Investigate codebase for: <what-to-build>"
   - Prompt: "Investigate the codebase to understand existing patterns, dependencies, similar features, and technical constraints related to: <what-to-build>. Focus on: (1) existing code patterns and architecture, (2) related dependencies, (3) similar existing features, (4) potential technical constraints. Return a concise summary under 500 tokens."
   - model: sonnet
2. Save the researcher's summary for use in Phase 2 and Phase 3.

## Phase 2: Structured Interview (Socratic)

Conduct an iterative Q&A to gather comprehensive requirements.

**`mode` independence guard (load-bearing)**: Phase 2 Structured Interview (Socratic) **MUST** run regardless of the parsed `mode` value (`auto` or `manual`, including when `mode=` is omitted and defaults to `auto`). The `mode` argument **MUST NOT** be interpreted as a signal to skip, shorten, or bypass Phase 2 — it has **no effect whatsoever** on Phase 2's execution. Any non-interactive wording elsewhere in this skill (e.g. the Finalization Phase Step 2 chain-confirmation context gated on `mode=auto`) is scoped to that specific step and **MUST NOT** be generalized to Phase 2. The **ONLY** condition under which Phase 2 is skipped is the existing **"Non-interactive environment fallback"** below (triggered strictly by `AskUserQuestion` itself being unavailable or returning an error, e.g. `claude -p` / CI automation without a TTY) — **not** by the value of `mode`.

**Caps (load-bearing for contract)**:
- At most **3 questions per round** (single `AskUserQuestion` call holds up to 3 items).
- At most **10 rounds** total.
- Therefore at most **30 questions total** across the entire interview before `brief.md` is written.
- Track a round counter starting at `0`. Increment **after** each user response is received (a round is counted only when the user actually responded — i.e., Phase 2 truly ran at least once).

#### Dynamic Phase 2 shrinkage (one-shot read of `runtime_metrics:`)

At Phase 2 start, perform a **single one-shot read** of `.simple-workflow/backlog/briefs/active/{slug}/autopilot-state.yaml` and tier-classify on `remaining_pct = 1 - ((input_tokens + cache_read_input_tokens) / context_window_size)`. The tier table maps the four bands (`≥ 70%`, `50-70%`, `30-50%`, `< 30%`) to round/question caps and the **standalone fallback (state-file-absent)** restores the 10 rounds × 3 questions ceiling. Full formula, table, and caveats: see [phase2-dynamic-shrinkage](references/phase2-dynamic-shrinkage.md).

Once the tier is selected at Phase 2 start, the round counter and questions/round caps are fixed for the remainder of the interview. The Caps stated above remain the **upper bound** — the dynamic table never raises them, only lowers them inside an autopilot run.

**Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), skip Phase 2 entirely and proceed directly to Phase 3 with the researcher's findings only. In this case, set `interview_complete: false` for the frontmatter (Phase 3) and do NOT count any rounds. Note "Phase 2 skipped (non-interactive mode)" in the final summary. Do NOT hang waiting for input.

For each round (up to the active tier cap, at most 3 questions per round, at most 30 questions total):

1. From the researcher's findings and prior answers, pick the most important unanswered questions from the interview templates (see Pre-computed Context).
2. Select **up to 3** questions from the template categories most relevant and not yet answered. Adapt to the specific context; do not ask generic template questions verbatim. A single `AskUserQuestion` call MUST carry at most 3 items.
3. Use `AskUserQuestion` to ask the selected questions.
4. After receiving answers, output a brief "Current understanding" summary (what is known, what categories still need information).
5. **Convergence check** — stop if ANY: user responds "sufficient"/"enough"/similar; all 7 categories (`references/interview-templates.md`) covered; **10 rounds have been completed** (hard ceiling; with the 3/round cap, enforces the 30-questions ceiling).
6. Otherwise continue to next round while the counter is below the tier cap.

At end of Phase 2, record `interview_complete = true` iff **at least one round produced a user response**; otherwise `interview_complete = false`.

## Phase 3: Brief Document Generation

1. Create directory: `mkdir -p .simple-workflow/backlog/briefs/active/{slug}`
2. Synthesize all gathered information into a structured brief document.
3. Estimate the ticket size (S/M/L/XL) based on:
   - S: 1-3 files, simple change
   - M: 4-8 files, moderate complexity
   - L: 9+ files, significant complexity
   - XL: Architecture-level changes
4. Estimate the category: Security / CodeQuality / Doc / DevOps / Community
5. Write to `.simple-workflow/backlog/briefs/active/{slug}/brief.md`.

**Frontmatter contract** (brief.md):

```
---
slug: {slug}
created: {date}
status: draft
mode: {auto|manual}
estimated_size: {S|M|L|XL}
estimated_category: {category}
interview_complete: {true|false}
---
```

- `mode` is the literal scalar (`auto` or `manual`) parsed from `$ARGUMENTS` in the Argument Parsing step (defaulting to `auto` when `mode=` is omitted). It is REQUIRED in v6.0.0+. Legacy briefs written before v6.0.0 may lack this key entirely; downstream readers (notably `/create-ticket brief=<path>`) treat the absence of `mode:` as `mode: auto` for backward compatibility.
- `interview_complete` is the literal scalar recorded at the end of Phase 2 (`true` if at least one round ran to a user response; `false` if Phase 2 was skipped via the non-interactive fallback or no round produced a response).
- **Do NOT emit `split:`** (obsolete — decomposition is `/create-ticket`'s job).
- **Do NOT emit `ticket_count:`** (obsolete — decomposition is `/create-ticket`'s job).

**Body schema**: render the canonical sections (Vision / Business Context / Technical Requirements / Scope with In Scope / Out of Scope / Edge Cases / Constraints / Quality Expectations / researcher summary) per [brief-body-template](references/brief-body-template.md). Synthesize the Phase 1 researcher's findings into the final body section so the brief stands alone for downstream skills.

## Phase 4: Policy Generation

1. Read `.simple-workflow/kb/index.yaml`, filter the `autopilot` section (historical decision patterns produced by `/tune` analysis), and apply confidence-based 3-tier judgment per gate (`>= 0.7` → annotate with `# kb-suggested`; `0.5-0.7` → `# [low confidence]`; `< 0.5` → conservative default). Apply size-scoped pattern priority before falling back to `scope=general`. Full integration logic: see [kb-policy-integration](references/kb-policy-integration.md).
2. Determine default policy values based on the user's risk tolerance answers from Phase 2 (maps to conservative/moderate/aggressive). If Phase 2 was skipped (`interview_complete: false`), default to **conservative** and emit default gates.
3. Write to `.simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml` regardless of Phase 2 outcome **and regardless of the parsed `mode` value** (the top-level `gates:` line MUST be present). Even in `mode=manual`, the brief-level `autopilot-policy.yaml` is written as a **rescue path**: per-ticket propagation is suppressed by `/create-ticket` (so manual-mode tickets work like bare-mode tickets via `/impl`'s FIFO selector), but the brief-level policy file remains so a user can later opt into autopilot by running `/autopilot {slug}` directly — the autopilot's brief-level policy fallback (see `skills/autopilot/SKILL.md` Phase 1 step 2, "Brief optionality") consumes this file.

The emitted YAML follows the template in [policy-template](references/policy-template.md) (version 1 / risk_tolerance / gates / constraints, with conservative/moderate/aggressive branches inlined as comments).

Split judgement has been removed: `/brief` no longer analyzes `estimated_size` to produce `split-plan.md`, and the legacy `planner` Split Judgment was retired in v6.2.0. `/create-ticket brief=<path>` receives the brief and decomposes the scope via `findings=<path>` mode + `decomposer`.

## Finalization: Output, `mode=auto` handoff, and SW-CHECKPOINT

Final phase of `/brief`: summary print, `mode=auto` chained skill invocations (Step 2), `mode=manual` no-chain guidance (Step 3), mandatory SW-CHECKPOINT (Step 4). **No further file writes occur after this phase**.

### Step 1 — Summary

Print:
- Brief file path: `.simple-workflow/backlog/briefs/active/{slug}/brief.md`
- Policy file path: `.simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml`
- Estimated size and category
- Interview outcome (`interview_complete: true|false`); if true, number of rounds actually completed

### Step 2 — `mode=auto` handoff

Only runs when mode=auto. (`mode=auto` was passed explicitly, or `mode=` was omitted so the default `auto` was applied. When the parsed `mode` is `manual`, this entire Step 2 is skipped and execution proceeds directly to Step 3.) Within **Step 2's chain-confirmation context**, the flow is strictly linear (display → status update → auto-kick write → `/create-ticket` → `/autopilot`): Step 2 **MUST NOT** call `AskUserQuestion`, nor otherwise prompt the user for a yes/no confirmation, to gate the chain between these sub-steps. The brief + policy display in (a) is passive — it does not gate the chain.

**Scope disclaimer (Step 2-only)**: The non-interactive restriction above is **scoped exclusively to Step 2's chain confirmation** (only reachable when `mode=auto`) and **MUST NOT** be generalized to the rest of `/brief`. In particular, **Phase 2 Structured Interview (Socratic) is independent of this restriction and MUST run regardless of the parsed `mode` value** — `mode` has no effect on Phase 2's behavior (see `## Phase 2` above).

a. Display the brief content and policy content to the user. This display is passive — it informs the user of what will be chained but does not pause for acknowledgement.
b. Update `brief.md` `status:` from `draft` to `confirmed`.
c. **Before invoking `/create-ticket` via the Skill tool**, write the auto-kick state file at `.simple-workflow/backlog/briefs/active/{slug}/auto-kick.yaml` with the following sample shape (use `date -u +%Y-%m-%dT%H:%M:%SZ` for `started`):

   ```yaml
   version: 1
   slug: {slug}
   started: {ISO-8601 UTC from `date -u +%Y-%m-%dT%H:%M:%SZ`}
   ```

   This file signals the Stop hook that the auto-chain is mid-flight between `/brief` → `/create-ticket` → `/autopilot`; it is deleted by `/autopilot` Phase 1 on startup.
d. **MUST invoke `/create-ticket` via the Skill tool** with argument `brief=.simple-workflow/backlog/briefs/active/{slug}/brief.md`.
e. If `/create-ticket` exits non-zero (or its SW-CHECKPOINT block indicates a failure path), **stdout MUST contain the literal string `ERROR:` AND the literal string `create-ticket failed`**; `/autopilot` MUST NOT be invoked. **Before emitting the failure-path SW-CHECKPOINT, delete `.simple-workflow/backlog/briefs/active/{slug}/auto-kick.yaml`** (idempotent — missing file is not an error). This prevents a stale auto-kick flag from looping the Stop hook indefinitely after a brief-side abort. Skip directly to Step 4 (SW-CHECKPOINT) with the failure recommendation shape.
f. Otherwise (`/create-ticket` succeeded), proceed to the final invocation:

   > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: `auto-kick.yaml` is present at `.simple-workflow/backlog/briefs/active/{slug}/auto-kick.yaml`. Invoke `/autopilot {slug}` via the Skill tool now. Do NOT end your turn or summarize.

   **MUST invoke `/autopilot` via the Skill tool** with argument `{slug}` (the brief's slug, which is also the `parent-slug` that `/create-ticket` wrote under `.simple-workflow/backlog/product_backlog/{slug}/`).

### Step 3 — `mode=manual` (no chained handoff)

Only runs when the parsed `mode` is `manual`. No `auto-kick.yaml` is written, no `/create-ticket` invocation, no `/autopilot` invocation — `/brief` produces the two artifacts (`brief.md` with `mode: manual` in frontmatter, plus `autopilot-policy.yaml` as the rescue path file from Phase 4) and stops. Print the manual-flow guidance below verbatim:

```
Brief generated in manual mode. To proceed:
1. Review and edit the brief if needed
2. Update status to 'confirmed' in brief.md frontmatter
3. Run /create-ticket brief=.simple-workflow/backlog/briefs/active/{slug}/brief.md to produce the ticket(s).
   Tickets will NOT receive autopilot-policy.yaml (manual mode).
4. Per ticket: /scout → /impl → /ship (standard manual flow)

If you later decide to switch to autopilot, run:
  /autopilot {slug}
The brief-level autopilot-policy.yaml is preserved at .simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml.
```

### Step 4 — Emit the final `## [SW-CHECKPOINT]` block

The block MUST be the LAST section of the skill's output. Format + the literal `context_advice` sentence are defined **once** in `skills/create-ticket/references/sw-checkpoint-template.md`; emit the block verbatim per that template (do NOT retype the `context_advice:` sentence).

Fields:
- `phase: brief`
- `ticket: none`
- **Success path** (`brief.md` + `autopilot-policy.yaml` both written) — branch on the parsed `mode`:
  - `artifacts:` — list containing the two repo-relative paths: `.simple-workflow/backlog/briefs/active/{slug}/brief.md` and `.simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml`.
  - **`mode=auto`**:
    - Emit EXACTLY ONE line matching `^next_recommended_auto:[[:space:]]+/autopilot[[:space:]]+\S+$` with value `/autopilot {slug}`.
    - Emit EXACTLY ONE line matching `^next_recommended_manual:[[:space:]]+/create-ticket[[:space:]]+brief=\S+$` with value `/create-ticket brief=.simple-workflow/backlog/briefs/active/{slug}/brief.md`.
  - **`mode=manual`**:
    - Emit `next_recommended_auto: ""` (literal empty string). This empty value does NOT match the AC #11 regex `^next_recommended_auto:[[:space:]]+/autopilot[[:space:]]+\S+$`, so the Stop hook's auto-`/autopilot` firing path does NOT trigger — load-bearing safety guarantee of `mode=manual`.
    - Emit EXACTLY ONE line matching `^next_recommended_manual:[[:space:]]+/create-ticket[[:space:]]+brief=\S+$` with value `/create-ticket brief=.simple-workflow/backlog/briefs/active/{slug}/brief.md`.
  - Do NOT emit a bare `next_recommended:` line alongside these two.
  - `{slug}` is the brief's `{slug}` (= `parent-slug` downstream; aliases here).
- **Failure path** (any write failure — `mkdir`, `brief.md`, `autopilot-policy.yaml`, or `mode=auto` chained `/create-ticket` failed):
  - `artifacts: []` on a single line.
  - Emit BOTH recommendation lines with empty-string values: `next_recommended_auto: ""` AND `next_recommended_manual: ""`. AC #11's regex does not match empty-string values, so downstream automation does not misfire. Both keys remain present (shape-preserving).

In all three shapes (mode=auto success, mode=manual success, failure), both `next_recommended_auto:` and `next_recommended_manual:` keys are present; only their values differ.

## Error Handling

- **Empty arguments**: Print `Usage: /brief <what-to-build> [mode=auto|manual]` and stop.
- **`auto=true` argument (v6.0.0 removal)**: Print `ERROR: 'auto=true' has been removed in v6.0.0; use 'mode=auto' or 'mode=manual'` and stop. Do NOT create the brief directory, do NOT write `brief.md`, do NOT write `autopilot-policy.yaml`, and do NOT write `auto-kick.yaml`. Exit non-zero.
- **Invalid `mode=<value>`**: Print `ERROR: invalid mode=<value>. Use mode=auto or mode=manual` (substituting the offending value) and stop. Do NOT create the brief directory, do NOT write `brief.md`, do NOT write `autopilot-policy.yaml`, and do NOT write `auto-kick.yaml`. Exit non-zero.
- **Researcher failure**: Report error. Continue to Phase 2 without investigation summary.
- **AskUserQuestion failure in Phase 2**: Skip Phase 2, proceed with researcher findings only; set `interview_complete: false`.
- **Write failure** (brief.md or autopilot-policy.yaml): Report the error and emit the failure-path SW-CHECKPOINT from Step 4 (empty-string recommendations, `artifacts: []`).
- **`mode=auto` path — `/create-ticket` chained invocation fails**: stdout MUST contain `ERROR:` AND `create-ticket failed`. Do NOT invoke `/autopilot`. Emit the failure-path SW-CHECKPOINT from Step 4.
