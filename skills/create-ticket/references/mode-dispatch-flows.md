# `/create-ticket` Mode-Dispatch Flows

Verbose narrative for each entrypoint mode. `skills/create-ticket/SKILL.md` carries the unified Step-0..Step-7 outline plus a per-mode delta table; this reference file expands each step so the SKILL body can stay within the BP token budget. SKILL.md still retains the pinned step headings `### Step D-4: Synthesize ...` and `### Step B-5: Synthesize ...` inline because those exact heading literals anchor static test contracts.

All three modes converge on the Common Write Path documented in SKILL.md. The capability guard `SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1` is honored uniformly: in every mode, when the env var is set to `1` the skill prints `ERROR: decomposer capability disabled (SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1)`, exits non-zero, touches no input file, leaves `.ticket-counter` untouched, and invokes no agent.

## Findings Mode (F-0 … F-9)

Entry condition: `findings=<path>` was parsed from `$ARGUMENTS`.

### Step F-0: Capability guard (environment variable)

Check `SIMPLE_WORKFLOW_DISABLE_DECOMPOSER`. If `1`, print `ERROR: decomposer capability disabled (SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1)` and exit non-zero. Do NOT read the findings file. Do NOT touch `.ticket-counter`. Do NOT invoke the decomposer.

### Step F-1: Findings file existence check

If the findings path does not exist on disk, print:

```
ERROR: Findings file not found at <path>
```

Substitute `<path>` with the literal path argument. Exit non-zero. Do NOT touch `.ticket-counter`. Do NOT create any directories.

### Step F-2: Findings frontmatter validation

Read the findings file. Parse its YAML frontmatter. Required keys per `.simple-workflow/docs/fix_structure/spec-findings-fixture.md`:

- `title` (required)
- `findings_version` (required; MUST equal `1` for this skill version)
- `slug_hint` (optional)

On any validation failure, print `ERROR: findings_version missing or unsupported (expected 1)` (or the appropriate `ERROR:` message naming the missing field) and exit non-zero. No directories created, counter untouched.

Derive `{parent-slug}`:
- If frontmatter `slug_hint` is present, use it verbatim (after trim).
- Else, kebab-case `title` (lowercase ASCII, whitespace → `-`, strip non-`[a-z0-9-]`, truncate at 40 chars).

### Step F-3: Parse Required Work Units

Locate the `## Required Work Units` section. Enumerate child headings matching regex `^###\s+[0-9]+\.\s+.+`. If **zero** such headings exist, print `ERROR: findings file contains zero Required Work Units` and exit non-zero.

### Step F-4: Brief-backed short-circuit (Socratic skip)

If the findings file was supplied alongside (or was derived from) a brief with frontmatter `interview_complete: true`, skip Phase 2 Socratic Refinement entirely (do NOT invoke `AskUserQuestion`). Otherwise run the capped Socratic Refinement (max 3 questions per round, max 10 rounds, max 30 questions total — see SKILL.md Phase 2) before invoking the decomposer.

### Step F-5: Invoke `decomposer` agent

The orchestrator MUST invoke the `simple-workflow:decomposer` via the Agent tool with `Input form: findings_doc` per `references/spec-decomposer-input.md` Form A. Pass the findings document's full content (frontmatter included) plus any Socratic Refinement answers appended as `## Socratic Answers`.

Receive the structured `## Result` block (Status / Parent slug / Tickets / Topological order / Rationale). The decomposer's return value is bounded by the Context Conservation Protocol in `agents/decomposer.md` (under 500 tokens) — no file content is echoed back. Reconcile parent slug if decomposer disagrees with the derived value; decomposer wins if `slug_hint` was absent.

Failure paths:
- `Status: failed` → print `ERROR: decomposer failed — <Rationale>` and exit non-zero.
- Agent unavailable → print `ERROR: decomposer agent unavailable` and exit non-zero.
- Empty `Tickets` → print `ERROR: decomposer returned zero tickets` and exit non-zero.

### Step F-6: Cycle detection

Build a directed graph from each ticket's `depends_on` list. Run Kahn's algorithm (or DFS-based cycle detection) to produce a topological order. If any cycle is detected, print:

```
ERROR: circular dependency detected among tickets: <list cycle members>
```

The literal word `circular` MUST appear in stdout. Exit non-zero. Do NOT touch `.ticket-counter`. Do NOT create directories. Unknown ID in `depends_on` → non-zero exit with `ERROR: split-plan validation failed — unknown depends_on id <id>`.

### Step F-7: Per-ticket planner expansion

For each ticket skeleton returned by the decomposer, in topological order, invoke the `simple-workflow:planner` via the Agent tool with the skeleton (title, scope_summary, size, findings context). Receive the full `ticket.md` draft (Background / Scope / Acceptance Criteria / Implementation Notes / Claude Code Workflow). Bind the planner to the canonical AC Quality Criteria at `skills/create-ticket/references/ac-quality-criteria.md` (see SKILL.md Phase 3).

### Step F-8: Per-ticket evaluation

For each planner draft, invoke the `simple-workflow:ticket-evaluator` via the Agent tool with the canonical AC Quality Criteria inline-injected between the marker pair `<canonical_ac_criteria>` and `</canonical_ac_criteria>` (Read the rubric file at spawn time). Apply the retry/escalation policy described in SKILL.md Phase 4 (max 2 rounds, gate check on `gates.ticket_quality_fail` when `brief=` is present).

If ANY sub-ticket FAILs after exhausting retry/escalation, the entire `/create-ticket` stops with **no** directories created and **no** counter change. This is the atomicity guarantee of findings mode.

### Step F-9: Dispatch to Common Write Path

Route to the Common Write Path regardless of N. `split-plan.md` is written at `.simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md` for every run (N ≥ 1), so `/autopilot` can consume the ticket set uniformly.

## Brief Mode (B-0 … B-8)

Entry condition: `brief=<path>` was parsed from `$ARGUMENTS`.

### Step B-0: Capability guard (environment variable)

Same as F-0 (`SIMPLE_WORKFLOW_DISABLE_DECOMPOSER`). v6.2.0+ unifies bare / brief / findings modes on this single external kill-switch.

### Step B-1: Brief file existence check

If the brief path does not exist, print `ERROR: Brief file not found at <path>` and exit non-zero.

### Step B-2: Read brief frontmatter

Read the brief's YAML frontmatter. Extract:
- `slug` → `{brief_slug}` (used as `{parent-slug}` unless overridden).
- `mode` → `{brief_mode}`. Required field as of v6.0.0 (`auto` or `manual`). Read the raw scalar after the `mode:` key, strip surrounding double or single quotes if present, trim leading/trailing whitespace, and lowercase the result before comparison (`AUTO`, `Manual`, ` auto ` all normalize). After normalization, only the literal strings `auto` and `manual` are accepted. If the key is **absent** (legacy brief written before v6.0.0), default to `brief_mode = auto` for backward compatibility. Any value that does not normalize to `auto` or `manual` → print `ERROR: brief frontmatter has invalid mode=<value>. Expected 'auto' or 'manual'` and exit non-zero.
- `interview_complete` (if `true`, Phase 2 Socratic Refinement is SKIPPED entirely; if `false` or absent, run the capped Socratic interview).

The `{parent-slug}` for brief mode defaults to `{brief_slug}`.

The `{brief_mode}` value gates two downstream behaviors:
- **Step W-8 autopilot-policy propagation**: only runs when `brief_mode == auto`. When `brief_mode == manual`, propagation is skipped — SKILL.md Step W-8 emits the audit-trace line `[POLICY-PROPAGATION] skipped: brief mode=manual`.
- **Phase 4 ticket-evaluator's `gates.ticket_quality_fail` brief-parent fallback**: only consulted when `brief_mode == auto`. When `brief_mode == manual`, the brief-parent `autopilot-policy.yaml` lookup is skipped.

**Stdin independence (`interview_complete: true`)**: when the brief frontmatter contains `interview_complete: true`, `/create-ticket` MUST be able to produce a ticket file under `.simple-workflow/backlog/` within 10 seconds even if stdin is a closed file descriptor. When `interview_complete: false` (or absent), the skill blocks on `AskUserQuestion` / stdin until at least one answer arrives.

### Step B-3: Phase 1 — Researcher (with reuse condition)

Run SKILL.md Phase 1. For brief mode, the researcher writes `investigation.md` to a transient location at `.simple-workflow/.tmp/create-ticket-{brief_slug}/investigation.md` (parent dir created by the orchestrator if absent — `.simple-workflow/` is gitignored).

**Reuse path**: if the brief is bound to a pre-existing ticket directory and a fresh `{ticket-dir}/investigation.md` already exists per the freshness criterion in SKILL.md Phase 1, skip the researcher invocation and use the existing file as the Phase 1 output. The reuse is strictly scoped to `{ticket-dir}/investigation.md` inside the resolved ticket directory; an `investigation.md` from any other directory MUST NOT be reused.

### Step B-4: Phase 2 — Socratic Refinement

If the brief's frontmatter contains `interview_complete: true`, **skip Phase 2 entirely**. Otherwise run the capped Socratic Refinement (max 3 questions per round, max 10 rounds, max 30 questions total). Non-interactive fallback: skip Phase 2 and proceed.

### Step B-5: Synthesize `scope_context` and invoke `decomposer`

Construct an inline `scope_context` spawn prompt per `references/spec-decomposer-input.md` Form B:

- Header: `Input form: scope_context`
- Header: `Parent slug: {parent-slug}` (i.e. `{brief_slug}`)
- Body section `## Context`: the brief.md `## Vision` + `## Business Context` sections concatenated verbatim
- Body section `## Investigation Summary`: full content of `investigation.md` from B-3
- Body section `## Socratic Answers` (only if B-4 collected at least one answer): one bullet per answer

Invoke the `simple-workflow:decomposer` via the Agent tool with this spawn prompt. Receive the structured `## Result` block (Status / Parent slug / Tickets / Topological order / Rationale).

Failure paths (identical to Findings Mode F-5 / F-6): `Status: failed` → `ERROR: decomposer failed — <Rationale>`; agent unavailable → `ERROR: decomposer agent unavailable`; empty `Tickets` → `ERROR: decomposer returned zero tickets`; cycle in `depends_on` → `ERROR: circular dependency detected among tickets: <list>`. All failures exit non-zero with no directory writes and no counter change.

### Step B-6: Per-ticket planner expansion

For each ticket skeleton returned by the decomposer, in topological order, invoke the `simple-workflow:planner` via the Agent tool with the skeleton (title, scope_summary, size) plus the brief content and Phase 1 investigation as supporting context. Bind the planner to `references/ac-quality-criteria.md` (see SKILL.md Phase 3). The planner does NOT re-partition — the decomposer already decided the ticket count in Step B-5.

### Step B-7: Per-ticket evaluation

For each planner draft, invoke the `simple-workflow:ticket-evaluator` via the Agent tool with the canonical AC Quality Criteria inline-injected per SKILL.md Phase 4. Apply the retry/escalation policy (max 2 rounds, `autopilot-policy.yaml` `gates.ticket_quality_fail` consulted when `brief_mode == auto`, non-interactive fallback to stop). If ANY sub-ticket FAILs after exhausting retry/escalation, the entire `/create-ticket` stops with no directories created and no counter change (atomicity).

### Step B-8: Dispatch to Common Write Path

Route to the Common Write Path regardless of N. `split-plan.md` is written for every run (N ≥ 1). The Common Write Path's autopilot-policy propagation in Step W-8 honors `brief_mode == auto` exactly as before.

## Bare Description Mode (D-0 … D-7)

Entry condition: neither `brief=` nor `findings=` was present in `$ARGUMENTS`.

### Step D-0: Capability guard (environment variable)

Same as F-0 (`SIMPLE_WORKFLOW_DISABLE_DECOMPOSER`).

### Step D-1: Derive parent_slug

`{parent-slug}` = kebab-case of the ticket description (lowercase ASCII, whitespace → `-`, strip non-`[a-z0-9-]`, truncate at 40 chars).

### Step D-2: Phase 1 — Researcher

Run SKILL.md Phase 1. Researcher writes `investigation.md` to `.simple-workflow/.tmp/create-ticket-{parent-slug}/investigation.md` (parent dir created by the orchestrator if absent). Bare-description mode does NOT participate in the brief-mode reuse path; the researcher is invoked unconditionally because no ticket directory exists yet at Phase 1 time.

### Step D-3: Phase 2 — Socratic Refinement

Run the capped Socratic Refinement (max 3 questions per round, max 10 rounds, max 30 questions total). Non-interactive fallback: skip Phase 2 and proceed with the researcher's findings only.

### Step D-4: Synthesize `scope_context` and invoke `decomposer`

Construct an inline `scope_context` spawn prompt per `references/spec-decomposer-input.md` Form B:

- Header: `Input form: scope_context`
- Header: `Parent slug: {parent-slug}`
- Body section `## Context`: the bare description text verbatim
- Body section `## Investigation Summary`: full content of `investigation.md` from D-2
- Body section `## Socratic Answers` (only if D-3 collected at least one answer): one bullet per answer

Invoke the `simple-workflow:decomposer` via the Agent tool with this spawn prompt. Receive the structured `## Result` block (Status / Parent slug / Tickets / Topological order / Rationale).

Failure paths (identical to Findings Mode F-5 / F-6): `Status: failed` → `ERROR: decomposer failed — <Rationale>`; agent unavailable → `ERROR: decomposer agent unavailable`; empty `Tickets` → `ERROR: decomposer returned zero tickets`; cycle in `depends_on` → `ERROR: circular dependency detected among tickets: <list>`. All failures exit non-zero with no directory writes and no counter change.

### Step D-5: Per-ticket planner expansion

For each ticket skeleton returned by the decomposer, in topological order, invoke the `simple-workflow:planner` via the Agent tool with the skeleton (title, scope_summary, size) plus the bare description and Phase 1 investigation as supporting context. Bind the planner to `references/ac-quality-criteria.md`. The planner does NOT re-partition — the decomposer already decided the ticket count in Step D-4.

### Step D-6: Per-ticket evaluation

For each planner draft, invoke the `simple-workflow:ticket-evaluator` via the Agent tool with the canonical AC Quality Criteria inline-injected per SKILL.md Phase 4. Apply the retry/escalation policy (max 2 rounds, non-interactive fallback to stop). Bare description mode does NOT have an `autopilot-policy.yaml` brief-parent fallback (no brief is present). If ANY sub-ticket FAILs after exhausting retry/escalation, the entire `/create-ticket` stops with no directories created and no counter change (atomicity).

### Step D-7: Dispatch to Common Write Path

Route to the Common Write Path regardless of N. `split-plan.md` is written for every run (N ≥ 1). Bare description mode ALWAYS nests every ticket under `{parent-slug}/` — never at bare `.simple-workflow/backlog/product_backlog/NNN-*/`. This uniform-nesting rule holds for N=1 just as for N>1.
