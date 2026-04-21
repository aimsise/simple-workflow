---
name: create-ticket
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Create one or more structured tickets with scope analysis, acceptance
  criteria, and Claude Code workflow recommendations. Supports bare-description
  (N=1), brief-mode, and findings-mode (N>=1 via decomposer agent) entrypoints.
disable-model-invocation: false
allowed-tools:
  # Claude Code
  - Agent
  - Skill
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - AskUserQuestion
  - "Bash(sha256sum:*)"
  - "Bash(shasum:*)"
  - "Bash(cp:*)"
  - "Bash(mkdir:*)"
  - "Bash(date:*)"
  - "Bash(ls:*)"
  # Copilot CLI
  - task
  - skill
  - view
  - glob
  - grep
  - create
  - edit
  - ask_user
  - "shell(sha256sum:*)"
  - "shell(shasum:*)"
  - "shell(cp:*)"
  - "shell(mkdir:*)"
  - "shell(date:*)"
  - "shell(ls:*)"
argument-hint: "<ticket description> | brief=<path> | findings=<path>"
---

## Pre-computed Context

Workflow patterns:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/workflow-patterns.md" 2>/dev/null || echo "[WARNING: workflow-patterns.md not found]"`

Ticket template:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/ticket-template.md" 2>/dev/null || echo "[WARNING: ticket-template.md not found]"`

`phase-state.yaml` schema (canonical reference for all writers):
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/phase-state-schema.md" 2>/dev/null || echo "[WARNING: phase-state-schema.md not found]"`

split-plan.md schema (canonical reference for N>1 writes):
!`cat "$CLAUDE_PLUGIN_ROOT/.docs/fix_structure/spec-split-plan-schema.md" 2>/dev/null || echo "[WARNING: spec-split-plan-schema.md not found]"`

AC Quality Criteria (canonical contract — planner and ticket-evaluator are both bound by this file):
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/ac-quality-criteria.md" 2>/dev/null || echo "[WARNING: ac-quality-criteria.md not found]"`

## phase-state.yaml write ownership

Writes the **whole** `phase-state.yaml` template at creation and transitions `phases.create_ticket` through `in-progress` → `completed` in the same invocation. Never writes other phase sections beyond the initial pending template. Top-level `current_phase` / `last_completed_phase` / `overall_status` are owned on initial write; subsequent writers update them per their own phase.

**Do NOT serialize a top-level `ticket_dir:` field** — the file path encodes location (see `phase-state-schema.md` §1).

Reference: `skills/create-ticket/references/phase-state-schema.md`.

## Mandatory Skill Invocations

`/create-ticket` MUST delegate to each agent below via the Agent tool. Direct model output without delegation bypasses the independent research/planning/evaluation layers and is a contract violation detected by the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `researcher` agent (Agent tool) | Phase 1 Investigation — before drafting (bare/brief modes only; findings mode skips because the findings doc IS the investigation) | No investigation findings; planner operates on model-internal assumptions rather than codebase evidence. Detected by missing researcher trace in skill invocation audit |
| `decomposer` agent (Agent tool) | Findings mode — immediately after findings-file validation, before planner | No dependency graph; skill cannot partition N work units into N ticket skeletons; findings mode cannot proceed |
| `planner` agent (Agent tool) | Phase 3 Ticket Draft — after Phase 1 (+ optional Phase 2) | No structured draft; skill falls back to ad-hoc output with no category/size/AC separation — ticket-evaluator will FAIL the quality gate |
| `ticket-evaluator` agent (Agent tool) | Phase 4 per-ticket evaluation — after Phase 3 | No quality gate; ticket marked "NOT EVALUATED" and may contain untestable/ambiguous ACs. Detected by autopilot's post-create-ticket quality check |

**Binding rules**:
- `MUST invoke researcher via the Agent tool` — the researcher's independent findings are load-bearing for ticket scope definition (bare/brief modes).
- `MUST invoke decomposer via the Agent tool` — in findings mode, the decomposer's dependency graph is load-bearing for ticket partitioning and `split-plan.md` synthesis.
- `MUST invoke planner via the Agent tool` — never draft ticket content inline; the planner's output is the canonical draft.
- `MUST invoke ticket-evaluator via the Agent tool` — never self-assess ticket quality; the ticket-evaluator is the independent quality gate.
- `NEVER bypass any of these agents via direct file operations` — writing `ticket.md` without going through all three phases is a contract violation.
- `Fail the task immediately if any mandatory agent invocation cannot be completed` — print the reason and stop; do not fabricate a ticket.

# /create-ticket

Ticket description / findings path: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS` into exactly one of three modes:

1. **`findings=<path>`** — scan for the token `findings=`; extract the path (rest of the token up to whitespace).
2. **`brief=<path>`** — scan for the token `brief=`; extract the path similarly.
3. **Bare description** — everything else is treated as a free-text ticket description.

**Mutual exclusion**: If BOTH `brief=<path>` AND `findings=<path>` are present, print:

```
ERROR: brief= and findings= are mutually exclusive. Pass exactly one.
```

Exit non-zero. Do NOT read either file. Do NOT touch `.ticket-counter`. Do NOT create any directories. (The literal phrase `mutually exclusive` is load-bearing for the skill's edge-case contract.)

**Empty arguments** (no description, no `brief=`, no `findings=`): print `Usage: /create-ticket <ticket description> | brief=<path> | findings=<path>` and stop.

After parsing, dispatch to the matching mode section below.

## Mode dispatch

- `findings=<path>` present → jump to **Findings Mode** section.
- `brief=<path>` present → jump to **Brief Mode** section.
- Otherwise → jump to **Bare Description Mode** section.

All three modes converge on the **Common Write Path** (counter atomicity, directory creation, `phase-state.yaml` init, `autopilot-policy.yaml` propagation, summary printing, SW-CHECKPOINT emission).

---

## Findings Mode

Entry condition: `findings=<path>` was parsed from `$ARGUMENTS`.

### Step F-0: Capability guard (environment variable)

Check the environment variable `SIMPLE_WORKFLOW_DISABLE_DECOMPOSER`. If it is set to `1`, print exactly:

```
ERROR: decomposer capability disabled (SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1)
```

Exit non-zero. Do NOT read the findings file. Do NOT touch `.ticket-counter`. Do NOT invoke the `decomposer` agent. (AC #12 requires this external kill-switch to be honored before any other work.)

### Step F-1: Findings file existence check

If the findings path does not exist on disk, print exactly:

```
ERROR: Findings file not found at <path>
```

Substitute `<path>` with the literal path argument. Exit non-zero. Do NOT touch `.ticket-counter`. Do NOT create any directories. (AC #2, AC #3 and edge case require this exact `ERROR: Findings file not found at` prefix on missing paths.)

### Step F-2: Findings frontmatter validation

Read the findings file. Parse its YAML frontmatter. Required keys per `.docs/fix_structure/spec-findings-fixture.md`:

- `title` (required)
- `findings_version` (required; MUST equal `1` for this skill version)
- `slug_hint` (optional)

On any validation failure, print `ERROR: findings_version missing or unsupported (expected 1)` (or the appropriate `ERROR:` message naming the missing field) and exit non-zero. No directories created, counter untouched.

Derive `{parent-slug}`:
- If frontmatter `slug_hint` is present, use it verbatim (after trim).
- Else, kebab-case `title` (lowercase ASCII, whitespace → `-`, strip non-`[a-z0-9-]`, truncate at 40 chars).

### Step F-3: Parse Required Work Units

Locate the `## Required Work Units` section. Enumerate child headings matching regex `^###\s+[0-9]+\.\s+.+`. If **zero** such headings exist, print `ERROR: findings file contains zero Required Work Units` and exit non-zero. (Edge case: empty findings → non-zero, no dirs, counter unchanged.)

### Step F-4: Brief-backed short-circuit (Socratic skip)

If the findings file was supplied alongside (or was derived from) a brief with frontmatter `interview_complete: true`, skip Phase 2 Socratic Refinement entirely (do NOT invoke `AskUserQuestion`). Otherwise run the capped Socratic Refinement (max 3 questions per round, max 10 rounds, max 30 questions total — see Phase 2 below) before invoking the decomposer.

### Step F-5: Invoke `decomposer` agent

**MUST invoke the `decomposer` via the Agent tool.** Pass the findings document full content + any Socratic Refinement answers as context. Receive the structured `## Result` block with fields:

- `Status`: `success | partial | failed`
- `Parent slug`: should match `{parent-slug}` derived above (reconcile if decomposer disagrees; decomposer wins if `slug_hint` was absent).
- `Tickets`: list of `{id, title, size, scope_summary, depends_on}` entries.
- `Topological order`: ordered list of IDs.
- `Rationale`: 1-3 sentence explanation.

On `Status: failed` → print `ERROR: decomposer failed — <Rationale>` and exit non-zero.

If the agent cannot be invoked (e.g., `agents/decomposer.md` unreadable) → print `ERROR: decomposer agent unavailable` and exit non-zero.

If `Tickets` is empty → print `ERROR: decomposer returned zero tickets` and exit non-zero.

### Step F-6: Cycle detection

Build a directed graph from each ticket's `depends_on` list. Run Kahn's algorithm (or DFS-based cycle detection) to produce a topological order. If any cycle is detected, print:

```
ERROR: circular dependency detected among tickets: <list cycle members>
```

The literal word `circular` MUST appear in stdout. Exit non-zero. Do NOT touch `.ticket-counter`. Do NOT create directories.

Validate: every `depends_on` element must be the `id` of another ticket in the same output — unknown IDs → non-zero exit with `ERROR: split-plan validation failed — unknown depends_on id <id>`.

### Step F-7: Per-ticket planner expansion

For each ticket skeleton returned by the decomposer, in topological order:

1. **MUST invoke the `planner` via the Agent tool** with the skeleton (title, scope_summary, size, findings context). Receive the full `ticket.md` draft (Background / Scope / Acceptance Criteria / Implementation Notes / Claude Code Workflow).
2. Follow the same AC Quality Criteria as bare/brief modes — the canonical rubric at `skills/create-ticket/references/ac-quality-criteria.md` (see Phase 3 below).

### Step F-8: Per-ticket evaluation

For each planner draft, **MUST invoke the `ticket-evaluator` via the Agent tool**. **MUST inline-inject the canonical AC Quality Criteria content into the evaluator's spawn prompt**, delimited by the exact marker pair `<canonical_ac_criteria>` ... `</canonical_ac_criteria>`. The canonical content is the one already loaded into this skill's Pre-computed Context above (the `AC Quality Criteria` backtick-bang loader near the top of this file) — reuse that loaded text verbatim; do NOT have the evaluator open the file itself and do NOT compute an absolute path. If the Pre-computed Context loader produced the `[WARNING: ac-quality-criteria.md not found]` sentinel, stop with an ERROR rather than spawning the evaluator without the rubric. Apply the same retry/escalation policy as the bare/brief modes (max 2 rounds, gate check on `gates.ticket_quality_fail` for autopilot-policy when `brief=` is present). See Phase 4 below.

If ANY sub-ticket FAILs after exhausting retry/escalation, the entire `/create-ticket` stops with **no** directories created and **no** counter change. This is the atomicity guarantee of findings mode. (Edge case: partial ticket creation failure → no ticket dirs remain.)

### Step F-9: Dispatch to Common Write Path

- If exactly **1** ticket was produced → route to the **N=1 Common Write Path** (no `split-plan.md` written). See Common Write Path below.
- If **N>1** tickets were produced → route to the **N>1 Common Write Path** (`split-plan.md` is written at `.backlog/product_backlog/{parent-slug}/split-plan.md`). See Common Write Path below.

---

## Brief Mode

Entry condition: `brief=<path>` was parsed from `$ARGUMENTS`.

### Step B-1: Brief file existence check

If the brief path does not exist, print `ERROR: Brief file not found at <path>` and exit non-zero.

### Step B-2: Read brief frontmatter

Read the brief's YAML frontmatter. Extract:
- `slug` → `{brief_slug}` (used as `{parent-slug}` unless overridden)
- `interview_complete` (if `true`, Phase 2 Socratic Refinement is SKIPPED entirely — no `AskUserQuestion` call, no stdin read; if `false` or absent, run the capped Socratic interview per Phase 2 below).

The `{parent-slug}` for brief mode defaults to `{brief_slug}`.

**Stdin independence (`interview_complete: true`)**: when the brief frontmatter contains `interview_complete: true`, `/create-ticket` MUST be able to produce a ticket file under `.backlog/` within 10 seconds even if stdin is a closed file descriptor. This is verified by AC #7 of the findings-mode Plan 2. When `interview_complete: false` (or absent), the skill blocks on `AskUserQuestion` / stdin until at least one answer arrives (AC #8).

### Step B-3: Run Phase 1 + 2 + 3 + 4

Execute the standard single-ticket pipeline (researcher → optional Socratic → planner → ticket-evaluator). Brief content supplies the context in lieu of a findings file.

### Step B-4: Dispatch to Common Write Path (N=1)

Brief mode produces exactly 1 ticket by default. If a split occurs mid-planner (per the Split Judgment section below), route to N>1 Common Write Path instead.

---

## Bare Description Mode

Entry condition: neither `brief=` nor `findings=` was present in `$ARGUMENTS`.

### Step D-1: Derive parent_slug

`{parent-slug}` = kebab-case of the ticket description (lowercase ASCII, whitespace → `-`, strip non-`[a-z0-9-]`, truncate at 40 chars).

### Step D-2: Run Phase 1 + 2 + 3 + 4

Same as Brief Mode (researcher → Socratic → planner → ticket-evaluator), but the description is the sole context.

### Step D-3: Dispatch to Common Write Path (N=1)

Bare description mode ALWAYS nests the single ticket under `{parent-slug}/` — never at bare `.backlog/product_backlog/NNN-*/`. This uniform-nesting rule (AC #7) holds for N=1 just as for N>1.

---

## Instructions (shared phases)

The following phases are referenced by all three modes above.

### Phase 1: Investigation (researcher agent)

**MUST invoke the `researcher` via the Agent tool.** **NEVER bypass** via direct `Grep`/`Read`/`Glob` — independent findings are required for Phase 3. Fail the task immediately if the researcher cannot be invoked.

Researcher scope:

1. Source code related to the ticket description
2. Affected files and line ranges
3. Existing test coverage
4. Related documentation
5. Dependencies (relationships with other tickets)

In **findings mode**, Phase 1 is already satisfied by the findings document itself — the decomposer consumes the prior investigation directly. The researcher is only invoked again if the decomposer's Rationale flags missing context.

### Phase 2: Socratic Refinement

**Brief mode with `interview_complete: true`**: SKIP Phase 2 entirely — the brief already contains structured-interview context. Proceed to Phase 3 immediately. When `brief=<path>` is provided and the brief's YAML frontmatter contains the literal line `interview_complete: true`, the skill MUST NOT invoke `AskUserQuestion` and MUST NOT block on stdin; a ticket file is expected to appear under `.backlog/` within 10 seconds even with closed stdin (AC #7 from the findings-mode plan).

**Brief mode with `interview_complete: false` or absent**: run the capped Socratic interview below. Absence of the `interview_complete` key in the brief frontmatter is treated as `false` (safe default — run the interview when capability is available).

**Findings mode**: SKIP Phase 2 if the upstream brief (if any) had `interview_complete: true`. Otherwise run the capped Socratic interview below.

**Bare description mode**: always run the capped Socratic interview below (unless non-interactive fallback fires).

**Interview caps (load-bearing for contract)**:
- At most **3 questions per round** (a single `AskUserQuestion` call carries at most 3 items).
- At most **10 rounds** total across the interview.
- Therefore at most **30 questions total** before a ticket file appears under `.backlog/`.

These caps apply uniformly to bare-description Socratic, brief-mode-without-`interview_complete` Socratic, and findings-mode Socratic. Implementations MUST NOT exceed 3 items per `AskUserQuestion` call and MUST NOT issue more than 10 rounds.

Refine scope through targeted questions:

1. Analyze the researcher's findings (or the findings / brief document in the respective modes).
2. Identify unclear points across:
   - **Scope boundaries**: Related functionality that may or may not be included
   - **Priority**: Which concern takes precedence when multiple exist
   - **Edge cases**: Boundary / error cases from investigation
   - **Constraints**: Performance, security, backward-compat requirements
3. Use `AskUserQuestion` for **up to 3** targeted questions per round (single call; at most 10 rounds → at most 30 questions total).
   - **Non-interactive fallback**: If `AskUserQuestion` is unavailable / errors (typical in `claude -p` / CI where stdin is not a TTY), skip Phase 2 and proceed to Phase 3 with researcher findings only. Note "Phase 2 skipped (non-interactive mode)" in the final summary. Do NOT hang.
4. Save the answers for the Phase 3 planner prompt.
5. **Convergence**: stop the interview once the user indicates sufficiency, scope is clear, or 10 rounds have been reached. The 10-round ceiling (combined with the 3-per-round cap) also enforces the 30-question total ceiling.

If investigation yields sufficient clarity (e.g., simple S-size with obvious scope), skip questioning and proceed to Phase 3.

### Phase 3: Ticket Draft (planner agent)

**MUST invoke the `planner` via the Agent tool.** **NEVER draft inline** — the planner's structured output (Background / Scope / Acceptance Criteria / Implementation Notes + category/size/workflow) is the canonical draft for Phase 4. Fail the task immediately if the planner cannot be invoked.

Planner scope:

1. Ticket structure (Background, Scope, Acceptance Criteria, Implementation Notes)
2. Category (Security / CodeQuality / Doc / DevOps / Community) and size (S/M/L/XL)
3. Workflow recommendations based on category × size, using workflow patterns from Pre-computed Context above

Additional context for the planner:
- Phase 2 answers (scope, priority, edge cases, constraints)
- If brief was provided: full brief content (replaces Phase 2 answers)
- If findings mode: decomposer-returned skeleton (title, scope_summary, size, depends_on) plus the findings file content, so the planner can lift affected files and observable outcomes verbatim.
- "Each AC will be evaluated by an independent evaluator against the canonical AC Quality Criteria at `skills/create-ticket/references/ac-quality-criteria.md` (injected via Pre-computed Context above). The planner MUST follow that file as the sole source of truth for Gates 1-5, including the Gate 4 observation-point carve-out and the Gate 5 size-mismatch rationale rule. ACs that fail any gate will be rejected."

#### AC Quality Criteria

The full rubric (Gates 1-5, BAD/GOOD examples, size thresholds, HOW/observation-point carve-out, Evaluator MUST NOT list) lives in the canonical contract `skills/create-ticket/references/ac-quality-criteria.md`, which is injected into this skill via Pre-computed Context above. Both the planner and the ticket-evaluator are bound by that file. Do NOT restate the rubric here.

Planner behaviour: draft every AC to satisfy Gates 1-5 on first pass; when the file-count axis and AC-count axis of Gate 5 disagree, include a short rationale in the ticket so the evaluator can apply the single-axis tiebreak rule.

#### Split Judgment (bare / brief modes only)

Instruct the planner to evaluate whether the ticket should be split:

- **Split criteria**: Size ≥ M **and** ACs group into 2+ independent work units (no inter-AC deps within a group).
- **Split quality guardrails**:
  - Each sub-ticket must be at least Size S with 2 or more Acceptance Criteria. Never create a ticket with only 1 AC.
  - Splits must produce **independently deployable and verifiable work units**, not mechanical AC distribution — each sub-ticket represents coherent functionality.
  - The planner must emit a **Split Rationale** justifying the split (e.g., "These ACs form an independent feature boundary" or "This group can be deployed/tested in isolation").
  - If no candidate satisfies all guardrails, fall back to **N = 1** (invalid split is worse than one larger ticket).
- **N > 1**: Planner outputs each sub-ticket individually with its own title, category, size, scope, ACs. Each must be self-contained and independently implementable.
- **N = 1**: Planner outputs a single ticket draft (existing behavior).

(In findings mode, split judgment is already performed by the `decomposer` — the planner receives N skeletons one at a time and does NOT re-split.)

### Phase 4: Ticket Evaluation

**MUST invoke the `ticket-evaluator` via the Agent tool.** **NEVER self-assess** — the ticket-evaluator is the independent gate verifying AC Testability/Unambiguity. Fail immediately if it cannot be invoked.

**MUST inline-inject the canonical AC Quality Criteria into every `ticket-evaluator` spawn prompt** (both the initial evaluation and any retry re-spawn), delimited by the exact marker pair `<canonical_ac_criteria>` ... `</canonical_ac_criteria>`. The injected content is the canonical rubric text already loaded into this skill's Pre-computed Context above (via the `AC Quality Criteria` backtick-bang loader near the top of this file); reuse that loaded text verbatim. The evaluator does NOT read the canonical file itself — it reads only the marker block in its spawn prompt, so failure to inject is a contract violation that will cause the evaluator to fail-fast with ERROR. If the Pre-computed Context loader produced the `[WARNING: ac-quality-criteria.md not found]` sentinel, stop with an ERROR rather than spawning the evaluator without the rubric.

**When split (N > 1, any mode)**: Run the evaluation process below **independently per sub-ticket**. If any sub-ticket FAILs after exhausting retry/escalation, the entire create-ticket stops (all sub-tickets affected; no directories created; counter untouched).

**When not split (N = 1)**: Run the evaluation for the single ticket (existing behavior).

#### Per-ticket evaluation process

1. Read the ticket content from Phase 3.
2. Spawn the **ticket-evaluator** with the ticket content. **MUST** include the canonical AC Quality Criteria inline in the spawn prompt, delimited by the exact marker pair `<canonical_ac_criteria>` ... `</canonical_ac_criteria>`, using the rubric text already loaded in the Pre-computed Context above (do NOT have the evaluator resolve or open the canonical file).
3. Decision:
   - **PASS** → proceed to Common Write Path.
   - **FAIL** →
     a. Save the evaluator's Feedback.
     b. Re-spawn the **planner** with: original ticket content; evaluator Feedback (all FAIL items + improvement suggestions); instruction "For each FAIL item you revise, prepend a 'Change rationale: [why this addresses the feedback]' comment above the revised section. The evaluator reviews the rationale to verify intent."
     c. Re-spawn the **ticket-evaluator** on the revised ticket. **MUST** again include the canonical AC Quality Criteria inline in this retry spawn prompt, delimited by the same `<canonical_ac_criteria>` ... `</canonical_ac_criteria>` marker pair, sourced from the Pre-computed Context above. Missing the marker block causes the evaluator to fail-fast with ERROR.
     d. Max 2 rounds (initial + 1 revision). If still FAIL:
        - **Autopilot policy check**: Check `{ticket-dir}/autopilot-policy.yaml` at `.backlog/product_backlog/{parent-slug}/{ticket-dir}/`. If missing **and** `brief=<path>` was given, also check `{brief-parent-dir}/autopilot-policy.yaml` (e.g. `.backlog/briefs/active/{slug}/`).
          - If present, read `gates.ticket_quality_fail`: `retry_with_feedback` + retry count < `max_retries` → continue retrying (print `[AUTOPILOT-POLICY] gate=ticket_quality_fail action=retry_with_feedback round={n}`); else stop (print `[AUTOPILOT-POLICY] gate=ticket_quality_fail action=stop`).
          - Else interactive flow below.
        - `AskUserQuestion`: "The ticket has unresolved quality issues: [list]. Proceed anyway or stop to revise manually?"
        - Proceed → Common Write Path with issues noted; Stop → print ticket path + issues.
        - **Non-interactive fallback**: If `AskUserQuestion` unavailable / errors, default to **stop**. Print "Stopped: /create-ticket cannot resolve FAIL gates non-interactively. Ticket saved at <path>. Re-run interactively." and exit. Do NOT hang.

---

## Common Write Path

Use the ticket template from Pre-computed Context for the output format.

All three modes converge here. This section enforces the atomic counter/directory/`split-plan.md`/`phase-state.yaml`/`autopilot-policy.yaml` contract.

### Step W-1: Counter read & validate

1. Read `.backlog/.ticket-counter`. If missing, initialize counter to `1` (write happens in Step W-5, after all validations pass).
2. If the file's content is **non-numeric**, print exactly:
   ```
   ERROR: .backlog/.ticket-counter contains non-numeric value '<content>'. Fix or delete the file and retry.
   ```
   Exit non-zero. Do NOT write any ticket directories. Do NOT update the counter. (Edge case: counter invalid → non-zero exit, no dirs.)
3. Let `counter` = current value; let `N` = 1 (bare / brief / findings-N=1) or `N` > 1 (findings-N>1 / brief-with-split).

### Step W-2: Derive ticket-dir paths

For each ticket `i` (0-indexed, `i = 0 … N-1`):
- `number_i` = `counter + i`.
- Zero-pad `number_i` to 3 digits → `{NNN}` (e.g., `1` → `001`).
- Derive `{slug_i}` from the ticket's title in kebab-case.
- **Uniform nesting (AC #7)**: `{ticket_dir_path_i}` = `.backlog/product_backlog/{parent-slug}/{NNN}-{slug_i}/` — always nested under `{parent-slug}`, even for N=1 bare description mode. NEVER write directly to `.backlog/product_backlog/{NNN}-{slug_i}/` (a bare `NNN-slug` directly under `product_backlog/`, without an intervening parent_slug, is forbidden).

### Step W-3: Dependency graph validation (N>1 only)

Re-verify the `depends_on` graph (the `decomposer` already did this in findings mode, but we re-check before commit):

1. Every `depends_on` entry must reference another ticket's logical ID (`{parent-slug}-part-{M}` for `1 ≤ M ≤ N`).
2. The graph must be acyclic (topological sort returns exactly N nodes).

On violation, print `ERROR: split-plan validation failed — <reason>` (or `ERROR: circular dependency detected ...` for cycles) and exit non-zero. NO directories created. NO counter change.

### Step W-4: Atomic directory creation + writes

Once all validations above have passed:

1. **Create the parent directory**: `mkdir -p .backlog/product_backlog/{parent-slug}/`.
2. For each ticket `i`, create `.backlog/product_backlog/{parent-slug}/{NNN}-{slug_i}/` (absent).
3. For each ticket `i`, write `ticket.md` at `{ticket_dir_path_i}/ticket.md`. Replace `{NNN}` in the `## T-{NNN}:` placeholder with the actual number (e.g. `## T-005: Add User Auth`).
4. For each ticket `i`, write `phase-state.yaml` at `{ticket_dir_path_i}/phase-state.yaml` per Step W-6 below.
5. For **N>1 only**: write `split-plan.md` at `.backlog/product_backlog/{parent-slug}/split-plan.md` per Step W-7 below. **For N=1, NO `split-plan.md` is written** (AC #13).
6. **Autopilot policy propagation** (Step W-8): if `brief=<path>` was passed AND `.backlog/briefs/active/{brief_slug}/autopilot-policy.yaml` exists on disk, copy it into each ticket directory.

**Atomicity rule**: if ANY write fails during Step W-4, attempt best-effort cleanup of already-created dirs (`rm -rf`) before reporting the error. Counter increment in Step W-5 happens ONLY after every file in the above list has been successfully written.

### Step W-5: Atomic counter write

Write `counter + N` to `.backlog/.ticket-counter` (`counter` was the pre-run value read in Step W-1; `N` is the ticket count). Bump is single-shot: the file is written **once** after all N dirs + artifacts have been committed. This guarantees AC #10 (counter increments by exactly 3 after a 3-ticket run).

### Step W-6: phase-state.yaml template (per ticket)

For each ticket `i`:

1. `now` = ISO-8601 UTC (`date -u +%Y-%m-%dT%H:%M:%SZ`).
2. `size_i` = Size from planner/decomposer (S/M/L/XL).
3. Write `{ticket_dir_path_i}/phase-state.yaml` with the pending template below. **Do NOT include a top-level `ticket_dir:` field** — the file path encodes location (Plan 3 schema-slim). Canonical schema: `skills/create-ticket/references/phase-state-schema.md`:

   ```yaml
   version: 1
   size: {size_i}
   created: {now}

   current_phase: create_ticket
   last_completed_phase: null
   overall_status: in-progress

   phases:
     create_ticket:
       status: in-progress
       started_at: {now}
       completed_at: null
       artifacts:
         ticket: null

     scout:
       status: pending
       started_at: null
       completed_at: null
       artifacts:
         investigation: null
         plan: null

     impl:
       status: pending
       started_at: null
       completed_at: null
       current_round: null
       max_rounds: null
       phase_sub: null
       last_ac_status: null
       last_audit_status: null
       last_audit_critical: 0
       last_round: null
       next_action: null
       feedback_files:
         eval: null
         quality: null

     ship:
       status: pending
       started_at: null
       completed_at: null
       artifacts:
         pr_url: null
   ```

4. **Immediately** transition `phases.create_ticket` to `completed` in the same invocation (before returning) via read-modify-write. The post-transition top-level fields MUST match AC #6:
   - `phases.create_ticket.status: completed`
   - `phases.create_ticket.completed_at: {now}` (recomputed immediately before write)
   - `phases.create_ticket.artifacts.ticket: {ticket_dir_path_i}/ticket.md`
   - `last_completed_phase: create_ticket`  ← AC #6 asserts this exact scalar
   - `current_phase: scout`                  ← AC #6 asserts this exact scalar

5. Do NOT modify other `phases.*` sections. The `scout`, `impl`, `ship` sections remain in the pending template for their owning skills.

6. Do NOT emit a top-level `ticket_dir:` line. AC #9 asserts this absence via regex `^ticket_dir:`.

**Atomicity**: On write failure, report the error but do NOT delete already-created `ticket.md` files — retry is idempotent on the state file.

### Step W-7: split-plan.md template (N>1 only)

Write `.backlog/product_backlog/{parent-slug}/split-plan.md` following `.docs/fix_structure/spec-split-plan-schema.md`. Exact schema:

```markdown
---
parent_slug: {parent-slug}
findings_source: {findings-path-or-""}
ticket_count: {N}
created: {ISO-8601 UTC}
version: 1
---

# Split Plan: {parent-slug}

## Context

{1-3 sentence summary lifted from findings.md Context section, or brief.md Vision if brief mode.}

## Tickets

### 1. {parent-slug}-part-1: {Unit Title}

- ticket_dir: `.backlog/product_backlog/{parent-slug}/{NNN-1}-{slug-1}`
- size: {S|M|L|XL}
- depends_on: []

{scope summary, 1-3 sentences}

### 2. {parent-slug}-part-2: {Unit Title}

- ticket_dir: `.backlog/product_backlog/{parent-slug}/{NNN-2}-{slug-2}`
- size: {S|M|L|XL}
- depends_on: [{parent-slug}-part-1]

{scope summary}

### 3. {parent-slug}-part-3: {Unit Title}

- ticket_dir: `.backlog/product_backlog/{parent-slug}/{NNN-3}-{slug-3}`
- size: {S|M|L|XL}
- depends_on: [{parent-slug}-part-1]

{scope summary}
```

Validation contract:
- Frontmatter `parent_slug` equals the parent directory basename (AC #5).
- Frontmatter `ticket_count` equals the number of `### N.` entries in `## Tickets` (AC #5, AC #8 — exactly N entries).
- Each entry's heading matches regex `^###[[:space:]]+[0-9]+\.[[:space:]]+{parent-slug}-part-[0-9]+:` (AC #8).
- Every entry has a `- depends_on:` line (AC #11).
- The `depends_on` graph is a DAG (topological sort returns N nodes, AC #11).

On validation failure, print `ERROR: split-plan validation failed — <reason>` and exit non-zero. No directories or artifacts persist (they were created during Step W-4 and must be rolled back — see atomicity rule).

### Step W-8: autopilot-policy.yaml propagation (AC #14, #15)

This step replaces the legacy `/autopilot` responsibility of copying the policy into each ticket dir.

Only runs if `brief=<path>` was passed AND the file `.backlog/briefs/active/{brief_slug}/autopilot-policy.yaml` exists on disk.

```bash
for ticket_dir_path_i in {ticket_dir_path_0} {ticket_dir_path_1} ...; do
  cp -p .backlog/briefs/active/{brief_slug}/autopilot-policy.yaml \
        "${ticket_dir_path_i}/autopilot-policy.yaml"
done
```

Byte-identical copy (use `cp -p` to preserve timestamps and permissions; SHA-256 of source == SHA-256 of copy — AC #14 asserts this).

**Do NOT copy if `brief=<path>` was not passed** — findings-only and bare-description modes MUST NOT emit `autopilot-policy.yaml` in any ticket dir (AC #15). The absence is an explicit signal to `/autopilot`'s downstream Policy guard: those tickets are "not autopilot-eligible".

**Do NOT copy if the source policy file is absent**, even when `brief=<path>` was passed. Missing source → tickets still created, no `autopilot-policy.yaml` placed. This matches the edge case: "`brief=<path>` where policy file is absent: tickets still created, no `autopilot-policy.yaml` in them (not an error)".

### Step W-9: Brief metadata injection

If `brief=<path>` was provided:

a. Read the brief's YAML frontmatter; extract `slug` → `{brief_slug}`.
b. If the creation context includes a part indicator (e.g., "This is part {N} of {total}" from `/autopilot` for split briefs), extract → `{brief_part}`.
c. In each ticket.md, add to the metadata table:
   - `| Brief Slug | {brief_slug} |` (uses literal key `brief_slug`)
   - `| Brief Part | {brief_part} |` (uses literal key `brief_part`; only if extracted; omit otherwise)

### Step W-10: Summary printing

After writing, print a summary:

**Non-split (N = 1)**:
- Ticket file path (e.g. `Ticket file path: .backlog/product_backlog/{parent-slug}/{NNN}-{slug}/ticket.md`)
- Category, Size
- Number of ACs
- Quality evaluation result (PASS / FAIL + remaining issues)
- Recommended workflow: `/scout → /impl → /ship`

**Split (N > 1)**: Print a ticket list table followed by per-ticket details:

```
### Created Tickets (N tickets)

| # | Path | Category | Size | ACs | Quality |
|---|------|----------|------|-----|---------|
| T-005 | .backlog/product_backlog/{parent-slug}/005-foo/ticket.md | CodeQuality | M | 3 | PASS |
| T-006 | .backlog/product_backlog/{parent-slug}/006-bar/ticket.md | CodeQuality | S | 2 | PASS |
| ... | ... | ... | ... | ... | ... |

Split plan: .backlog/product_backlog/{parent-slug}/split-plan.md
Recommended workflow per ticket: `/scout → /impl → /ship`
```

### Step W-11: Emit SW-CHECKPOINT block

Emit the `## [SW-CHECKPOINT]` block per `skills/create-ticket/references/sw-checkpoint-template.md` as the FINAL section of the skill's output, after `### Created Tickets` and any other summary content.

Common fields (all modes):

- `phase: create_ticket`
- `ticket: <first created ticket-dir or "none">` (for N>1 use the first in topological order).
- `artifacts:` list repo-relative paths to every `ticket.md` written, plus `split-plan.md` when N>1. On failure paths use `artifacts: []` on a single line.
- `context_advice:` the literal sentence from the template (verbatim).

**Recommendation line — choose exactly ONE shape per run**:

- **Success path, N = 1** (bare description, brief mode without split, findings mode with 1 Required Work Unit):
  - Emit a single line: `next_recommended: /scout <ticket-dir>`.
  - Do NOT emit `next_recommended_auto:` or `next_recommended_manual:`.
  - The block MUST NOT contain the substring `next_recommended_auto` anywhere (negative AC).

- **Success path, N > 1** (findings mode with 2+ Required Work Units, or brief mode where split judgment chose split):
  - Emit BOTH of the following, on separate lines, in this order:
    - `next_recommended_auto: /autopilot {parent-slug}`
    - `next_recommended_manual: /scout {first-unblocked-ticket-dir}`
  - Do NOT emit a plain `next_recommended:` line in this block.
  - `{first-unblocked-ticket-dir}` is computed thus (per `spec-split-plan-schema.md` § first-unblocked rule):
    1. Enumerate every ticket whose `depends_on: []` (empty list).
    2. Sort candidates by `ticket_dir` in ascending **lexicographic** order (this is the physical path string, e.g. `.backlog/product_backlog/<parent-slug>/005-foo`).
    3. Pick the first (lexicographically smallest). This is deterministic even when every ticket is independent — exactly one line matches `^next_recommended_manual:` (negative AC: N=3 all-independent run still emits a single `next_recommended_manual:`).
  - Regex invariant: the block contains exactly one line matching `^next_recommended_auto:[[:space:]]+/autopilot[[:space:]]+\S+$` AND exactly one line matching `^next_recommended_manual:[[:space:]]+/scout[[:space:]]+\.backlog/product_backlog/\S+$`.

- **Failure path (any N — counter-invalid, decomposer failed, split-plan validation failed, planner/evaluator exhausted retries, write failure during Step W-4, etc.)**:
  - Emit a single line: `next_recommended: ""` (literal empty string).
  - Do NOT emit `next_recommended_auto:` or `next_recommended_manual:` (even if N>1 was attempted — no ticket dirs exist, no downstream command is sensible).
  - `artifacts: []` on a single line.

**Uniqueness**: per emitted block, exactly one shape is present. Emitting all three recommendation-line variants, or none, is a contract violation.

The rationale for the dual-recommendation form and the first-unblocked rule lives in `skills/create-ticket/references/sw-checkpoint-template.md` § "Why the dual-recommendation for N>1" — do not restate it here.

### Workflow selection guide

Identify available skills/agents by scanning `.claude/skills/` and `.claude/agents/`, listing installed plugin skills/agents, and using the workflow patterns from Pre-computed Context.

**Category guidelines**:
- **Security**: Wrap with `/audit only_security_scan=true` before and after. Spec-first; documentation leads.
- **CodeQuality**: Use `/refactor`. Guarantee no behavior changes.
- **Doc**: Use `/impl` with a doc-focused plan.
- **DevOps**: CI/CD configs are hard to test; design with `/plan2doc`.
- **Community**: Reference industry-standard templates.

**Size guidelines**:
- **S**: `/plan2doc` optional. Direct implementation.
- **M**: `/plan2doc` recommended.
- **L/XL**: `/plan2doc` required. Incremental implementation recommended.

## Error Handling

All `ERROR:` paths below share the same invariants: **no ticket directories created**, **`.ticket-counter` unchanged** (atomicity), non-zero exit.

- **Counter file invalid**: Non-numeric `.backlog/.ticket-counter` → print `ERROR: .backlog/.ticket-counter contains non-numeric value '<content>'. Fix or delete the file and retry.` and stop; create no ticket.
- **Empty arguments**: Print "Usage: /create-ticket <ticket description> | brief=<path> | findings=<path>" and stop.
- **Both `brief=` and `findings=`**: Print `ERROR: brief= and findings= are mutually exclusive. Pass exactly one.` and stop.
- **`findings=<path>` points to non-existent file**: Print `ERROR: Findings file not found at <path>` and stop.
- **`findings_version` missing or ≠ 1**: Print `ERROR: findings_version missing or unsupported (expected 1)` and stop.
- **Findings has zero Required Work Units**: Print `ERROR: findings file contains zero Required Work Units` and stop.
- **`SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1`**: Print `ERROR: decomposer capability disabled (SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1)` and stop, BEFORE reading findings or invoking any agent.
- **Decomposer `Status: failed`**: Print `ERROR: decomposer failed — <Rationale>` and stop.
- **Decomposer returns empty Tickets list**: Print `ERROR: decomposer returned zero tickets` and stop.
- **Decomposer agent unavailable** (`agents/decomposer.md` unreadable, etc.): Print `ERROR: decomposer agent unavailable` and stop.
- **Cyclic `depends_on` graph** (either from decomposer output or from a hand-rolled findings input): Print `ERROR: circular dependency detected among tickets: <cycle members>` and stop. The literal word `circular` MUST appear in stdout.
- **split-plan validation fails** (unknown id / ticket_count mismatch): Print `ERROR: split-plan validation failed — <reason>` and stop. Rollback any directories created in Step W-4.
- **Researcher failure**: Report error and stop.
- **Planner failure**: Report error and stop.
- **Ticket-evaluator failure**: Output ticket without evaluation; display "Quality: NOT EVALUATED" in summary.
- **2 rounds FAIL (per ticket)**: Present remaining issues via `AskUserQuestion`. Proceed only with user confirmation. Decline → stop + print ticket path. **Non-interactive fallback**: default to stop + print ticket path with issues. Do NOT hang.
- **Split ticket partial failure**: If any sub-ticket FAILs evaluation and stops, no tickets are written and the counter is not updated (atomic — counter + N is a single write in Step W-5 that only runs after all N evaluations PASS).
- **Brief mode — brief file not found**: Print `ERROR: Brief file not found at <path>` and stop.
