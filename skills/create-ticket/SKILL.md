---
name: create-ticket
description: >-
  Do not auto-invoke. Only invoke when called by name. Use when (1) user
  types `/create-ticket`, (2) user provides description / `brief=<path>` /
  `findings=<path>` asking for a structured backlog ticket, or (3) sibling
  skill delegates ticket creation (single or N>=1 via decomposer). Triggers
  on "create a ticket", "/create-ticket", "draft a ticket".
disable-model-invocation: false
allowed-tools:
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
argument-hint: "<ticket description> | brief=<path> | findings=<path>"
---

# /create-ticket

Ticket description / findings path: $ARGUMENTS

UTC time: !`date -u +%Y-%m-%dT%H:%M:%SZ`

## Pre-computed Context

Available user skills: !`( ls -1 ~/.claude/skills 2>/dev/null ; ls -1 .claude/skills 2>/dev/null ) | sort -u | grep . | tr "\n" "," | sed "s/,$//" | grep . || echo "(none)"`

Available MCP servers: !`( jq -r '.mcpServers // {} | keys[]' .mcp.json 2>/dev/null ; jq -r '.mcpServers // {} | keys[]' ~/.claude.json 2>/dev/null ) | sort -u | grep . | tr "\n" "," | sed "s/,$//" | grep . || echo "(none)"`

## phase-state.yaml write ownership

Writes the **whole** `phase-state.yaml` template at creation, transitions `phases.create_ticket: in-progress -> completed` in the same invocation. Never writes other phase sections. Top-level `current_phase` / `last_completed_phase` / `overall_status` are owned on initial write; later writers update them. **Do NOT serialize a top-level `ticket_dir:` field** — path encodes location. Schema: [references/phase-state-schema.md](references/phase-state-schema.md).

## Mandatory Skill Invocations

`/create-ticket` MUST delegate to each agent below via the Agent tool. Direct model output bypasses the independent layers — contract violation detected by skill invocation audit.

| Invocation Target | When | Skip consequence |
|---|---|---|
| `researcher` agent (Agent tool) | Phase 1 — bare always; brief unless a freshness-validated `{ticket-dir}/investigation.md` is reused per [references/agent-spawn-prompts.md](references/agent-spawn-prompts.md); findings skips (findings doc IS the investigation) | No findings; planner falls back to model assumptions. Detected by missing researcher trace. Freshness-validated brief reuse OK; stale reuse forbidden |
| `decomposer` agent (Agent tool) | All modes — after Phase 1 (+Socratic), before planner. Caller picks `Input form: findings_doc` or `Input form: scope_context` per [references/spec-decomposer-input.md](references/spec-decomposer-input.md) | No dependency graph; cannot partition; run cannot proceed in any mode |
| `planner` agent (Agent tool) | Phase 3 — after Phase 1 (+optional Phase 2) | No structured draft; ticket-evaluator FAILs quality gate |
| `ticket-evaluator` agent (Agent tool) | Phase 4 per-ticket — after Phase 3 | No quality gate; ticket "NOT EVALUATED" with possibly untestable ACs. Detected by autopilot's check |

**Binding rules**: `MUST invoke` each agent above (researcher/decomposer/planner/ticket-evaluator) via the Agent tool. `NEVER bypass` via direct file ops or self-assessment. `Fail the task` if any mandatory invocation cannot complete. Each return capped under 500 tokens (Context Conservation Protocol in `agents/<agent>.md`).

## Argument Parsing

Parse `$ARGUMENTS` into one mode: `findings=<path>` (scan `findings=`); `brief=<path>` (scan `brief=`); else bare-description free-text.

**Mutual exclusion**: BOTH `brief=` AND `findings=` → print `ERROR: brief= and findings= are mutually exclusive. Pass exactly one.` and exit non-zero. Do NOT read either file. Do NOT touch `.ticket-counter`. Do NOT create directories. (Literal `mutually exclusive` is load-bearing.)

**Empty arguments**: print `Usage: /create-ticket <ticket description> | brief=<path> | findings=<path>` and stop.

## Mode dispatch

`findings=<path>` → Findings (**F-0..F-9**). `brief=<path>` → Brief (**B-0..B-8**). Else Bare (**D-0..D-7**). All converge on Common Write Path. Step prose: [references/mode-dispatch-flows.md](references/mode-dispatch-flows.md).

**Step 0 capability guard (every mode)** — first step reads the env-var kill-switch:

- F-0 reads `SIMPLE_WORKFLOW_DISABLE_DECOMPOSER`.
- B-0 reads `SIMPLE_WORKFLOW_DISABLE_DECOMPOSER` (same).
- D-0 reads `SIMPLE_WORKFLOW_DISABLE_DECOMPOSER` (same).

If `=1`: print `ERROR: decomposer capability disabled (SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1)`, exit non-zero, read no input, touch no `.ticket-counter`, invoke no agent. v6.2.0+ unifies bare/brief/findings.

Per-mode deltas:

| Step | F (findings) | B (brief) | D (bare) |
|---|---|---|---|
| 1 Input | findings file exists | brief file exists | derive `{parent-slug}` |
| 2 Frontmatter | `findings_version`, `title`, `slug_hint` | `slug`, `chain` (canonical, vX.Y.0+) **and** `mode` (legacy alias, retained one minor for backward read compatibility), `interview_complete`; `brief_mode == auto` gates W-8 + `gates.ticket_quality_fail` brief-parent fallback. **Precedence rule (marker literal: chain: precedes mode:)**: `chain:` is read first if present (`on` → `brief_mode == auto`, `off` → `brief_mode == manual`); when `chain:` is absent, `mode:` is read for backward compatibility; super-legacy briefs lacking both keys default to `brief_mode == auto` (≡ `chain=on`). | (n/a) |
| 3 Phase 1 | enumerates `## Required Work Units` | researcher (reuse path) | researcher (no reuse) |
| 4 Phase 2 | skip on upstream `interview_complete: true` | skip on `interview_complete: true`, else capped | always capped |
| 5 Decomposer | F-5 `findings_doc` | B-5 `scope_context` | D-4 `scope_context` |
| 6 Validation | F-6 cycle / unknown-id | (re-used in W-3) | (re-used in W-3) |
| 7 Planner+Eval | F-7/F-8 per-ticket | B-6/B-7 per-ticket | D-5/D-6 per-ticket |
| 8 Dispatch | F-9 → CWP | B-8 → CWP | D-7 → CWP |

### Step D-4: Synthesize `scope_context` and invoke `decomposer` (Bare Description Mode)

`MUST invoke the decomposer via the Agent tool` with an inline `scope_context` spawn prompt per [references/spec-decomposer-input.md](references/spec-decomposer-input.md) Form B. Body: `Input form: scope_context`; `Parent slug: {parent-slug}` (kebab-case of description); `## Context` = description verbatim; `## Investigation Summary` = Phase 1 transient `investigation.md`; `## Socratic Answers` (if any) = one bullet per answer.

Receive `## Result` (Status / Parent slug / Tickets / Topological order / Rationale). Failures: `Status: failed` → `ERROR: decomposer failed — <Rationale>`; unavailable → `ERROR: decomposer agent unavailable`; empty Tickets → `ERROR: decomposer returned zero tickets`; cycle → `ERROR: circular dependency detected among tickets: <list>`. All exit non-zero, atomic.

### Step B-5: Synthesize `scope_context` and invoke `decomposer` (Brief Mode)

`MUST invoke the decomposer via the Agent tool` with an inline `scope_context` spawn prompt per [references/spec-decomposer-input.md](references/spec-decomposer-input.md) Form B. Body: `Input form: scope_context`; `Parent slug: {parent-slug}` (`{brief_slug}`); `## Context` = brief.md `## Vision` + `## Business Context` verbatim; `## Investigation Summary` = Phase 1 `investigation.md` (reused when fresh); `## Socratic Answers` (if any) = one bullet per answer.

Same failures as D-4 — atomic.

## Instructions (shared phases)

Prose: [references/agent-spawn-prompts.md](references/agent-spawn-prompts.md). Each agent's return is capped under 500 tokens per its own Context Conservation Protocol.

### Phase 1: Investigation (researcher agent)

`MUST invoke the researcher via the Agent tool`. `NEVER bypass` via direct `Grep`/`Read`/`Glob`. `Fail the task` if researcher cannot be invoked. Researcher return MUST stay under 500 tokens per the Context Conservation Protocol in `agents/researcher.md`.

Modes: findings — satisfied by findings doc. Brief — reuse `{ticket-dir}/investigation.md` only when freshness-valid (`phase-state.yaml` provenance, mtime ≤ 24 h, or matching `investigation_sha256:`; see [references/agent-spawn-prompts.md](references/agent-spawn-prompts.md)). Bare — always invoked. Fresh runs write `.simple-workflow/.tmp/create-ticket-{parent-slug}/investigation.md`.

### Phase 2: Socratic Refinement

Brief with `interview_complete: true` skips Phase 2 (no `AskUserQuestion`, no stdin block; ticket file under `.simple-workflow/backlog/` within 10 s on closed stdin). Findings mirrors upstream brief's `interview_complete`. Bare always runs the capped interview unless non-interactive fallback fires.

Caps (load-bearing): max **3 questions/round**, **10 rounds**, **30 total**. Non-interactive fallback: skip Phase 2 if `AskUserQuestion` errors. Do NOT hang.

**args-aware shrinkage**: Phase 2 MUST suppress questions whose answers are already in `$ARGUMENTS` (bare) or brief body (brief mode, `interview_complete: false`). Full rule: [references/agent-spawn-prompts.md](references/agent-spawn-prompts.md) Phase 2.

### Phase 3: Ticket Draft (planner agent)

`MUST invoke the planner via the Agent tool`. `NEVER bypass` by drafting inline — planner output (Background / Scope / ACs / Implementation Notes + category/size/workflow) is the canonical draft. `Fail the task` if planner cannot be invoked. Planner return MUST stay under 500 tokens per the Context Conservation Protocol in `agents/planner.md`.

Scope: ticket structure; category (Security / CodeQuality / Doc / DevOps / Community); size (S/M/L/XL); workflow chain from [references/workflow-patterns.md](references/workflow-patterns.md). Context: Phase 2 answers, brief content (replaces Phase 2 in brief mode), or findings + decomposer skeleton.

**Partition owned by decomposer (all modes)**; planner never re-partitions. See [references/spec-decomposer-input.md](references/spec-decomposer-input.md).

**AC Quality Criteria binding**: planner MUST follow [references/ac-quality-criteria.md](references/ac-quality-criteria.md) for Gates 1-5 (Gate 4 observation-point carve-out, Gate 5 size-mismatch rationale). ACs failing any gate are rejected by Phase 4.

#### Workflow selection (planner output)

By category: Security wraps with security-only audits, spec-first; CodeQuality uses `/refactor` (no behavior change); Doc — doc-focused plan; DevOps — `/plan2doc`; Community — industry templates. By size: S — `/plan2doc` optional; M — recommended; L/XL — required. Chained skills (scan `.claude/skills/`, `.claude/agents/`): `/investigate`, `/plan2doc`, `/scout`, `/refactor`. Full chains: [references/workflow-patterns.md](references/workflow-patterns.md).

### Phase 4: Ticket Evaluation

`MUST invoke the ticket-evaluator via the Agent tool`. `NEVER bypass` by self-assessing. `Fail this ticket` if evaluator cannot be invoked. Evaluator return MUST stay under 500 tokens per the Context Conservation Protocol in `agents/ticket-evaluator.md`.

**Canonical AC Quality Criteria inline-injection (every spawn — initial AND retry)**: orchestrator MUST `Read` [references/ac-quality-criteria.md](references/ac-quality-criteria.md) at spawn time and inline-inject the content between the markers `<canonical_ac_criteria>` and `</canonical_ac_criteria>`. Evaluator reads only the marker block (not the file). Missing markers fail-fast with ERROR.

Envelope: `Status: PASS|FAIL` + per-AC findings. `PASS` → CWP. `FAIL` → retry-with-feedback (max 2 rounds). Retry planner FS-search ban: works **solely from the inlined prior draft** + inlined Feedback (no filesystem search for `ticket.md`). Exhausted retries consult `autopilot-policy.yaml` `gates.ticket_quality_fail`; honor `retry_with_feedback` / `stop`; emit `[AUTOPILOT-POLICY] gate=ticket_quality_fail action=<retry_with_feedback|stop> round={n}`. `brief_mode == manual` skips brief-parent fallback. Non-interactive: stop. Full: [references/agent-spawn-prompts.md](references/agent-spawn-prompts.md).

**Split (N>1)**: independent per sub-ticket. Any FAIL after retry/escalation → `/create-ticket` stops atomically (no directories, no counter change).

#### Canonical Gate 1 / Gate 2 examples

The rubric [references/ac-quality-criteria.md](references/ac-quality-criteria.md) anchors these BAD/GOOD strings; duplicated here verbatim (no cross-file interpolation). The AC-example drift guard keeps both copies in sync.

- BAD: "Improve performance" (no threshold)
- GOOD: "Response time under 200ms for 95th percentile"
- BAD: "Support large files" ("large" undefined)
- GOOD: "Stream files over 100MB without loading into memory"

## Common Write Path

All three modes converge here. `ticket.md` per [references/ticket-template.md](references/ticket-template.md); W-6/W-7/W-10 in [references/write-path-templates.md](references/write-path-templates.md). Every `ERROR:` here is atomic — no directories, `.ticket-counter` unchanged, non-zero exit.

### Step W-1: Counter read & validate

Read `.simple-workflow/.ticket-counter`; missing → initialize to `1` (write at W-5). Non-numeric → `ERROR: .simple-workflow/.ticket-counter contains non-numeric value '<content>'. Fix or delete the file and retry.`. `counter` = current value, `N` = decomposer ticket count.

### Step W-2: Derive ticket-dir paths

For each ticket `i` (`0..N-1`): `number_i = counter + i`, zero-pad to 3 digits → `{NNN}`; `{slug_i}` = title kebab-case; **uniform nesting** `{ticket_dir_path_i} = .simple-workflow/backlog/product_backlog/{parent-slug}/{NNN}-{slug_i}/` — always under `{parent-slug}` for N=1.

### Step W-3: Dependency graph validation (N>1 only)

Re-verify the `depends_on` graph: every `depends_on` references another ticket's ID (`{parent-slug}-part-{M}` for `1 ≤ M ≤ N`); acyclic (topological sort returns N nodes). Violation → `ERROR: split-plan validation failed — <reason>` or `ERROR: circular dependency detected ...` for cycles.

### Step W-4: Atomic directory creation + writes

After validations: (1) `mkdir -p .simple-workflow/backlog/product_backlog/{parent-slug}/`; (2) create each `{ticket_dir_path_i}`; (3) write `{ticket_dir_path_i}/ticket.md` from [references/ticket-template.md](references/ticket-template.md), replacing `{NNN}` in `## T-{NNN}:`; (4) `{ticket_dir_path_i}/phase-state.yaml` (W-6); (5) `.simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md` (W-7) — unconditional (N≥1); (6) policy propagation (W-8). Write failure → best-effort cleanup (`rm -rf`); W-5 counter increment ONLY after every file written.

### Step W-5: Atomic counter write

Write `counter + N` to `.simple-workflow/.ticket-counter` — single-shot, **once** after all N dirs + artifacts have committed.

### Step W-6: phase-state.yaml template (per ticket)

Write per-ticket pending template + immediate `phases.create_ticket: in-progress -> completed` transition per [references/write-path-templates.md](references/write-path-templates.md) (schema: [references/phase-state-schema.md](references/phase-state-schema.md)). Post-transition top-level: `last_completed_phase: create_ticket`, `current_phase: scout`. Do NOT emit `ticket_dir:`.

### Step W-7: split-plan.md template

Write per [references/write-path-templates.md](references/write-path-templates.md) (schema: `.simple-workflow/docs/fix_structure/spec-split-plan-schema.md`). Validation: parent_slug = parent basename; ticket_count = `### N.` count; every entry has `- depends_on:`; graph DAG. Failure → `ERROR: split-plan validation failed — <reason>`; roll back W-4 dirs.

### Step W-8: autopilot-policy.yaml propagation

Runs only when ALL hold: `brief=<path>` passed; `brief_mode == auto` (per B-2; resolved via the precedence rule **chain: precedes mode:** — `chain: on` → `brief_mode == auto`, `chain: off` → `brief_mode == manual`; when `chain:` is absent the legacy `mode:` is read; super-legacy briefs lacking both keys are treated as `auto` ≡ `chain=on`); `.simple-workflow/backlog/briefs/active/{brief_slug}/autopilot-policy.yaml` exists.

`brief_mode == manual` (v6.0.0+) **skips** even if source exists; emit one audit line: `[POLICY-PROPAGATION] skipped: brief mode=manual`. Per-ticket dirs receive no policy — indistinguishable from bare tickets to `/impl`'s FIFO selector.

When conditions hold: byte-identical `cp -p` (SHA-256 source == SHA-256 copy) into each `{ticket_dir_path_i}/autopilot-policy.yaml` from `.simple-workflow/backlog/briefs/active/{brief_slug}/autopilot-policy.yaml`.

**Do NOT copy** without `brief=<path>` (findings/bare MUST NOT emit `autopilot-policy.yaml` — signal to `/autopilot`'s Policy guard). **Do NOT copy** if source absent (tickets created, no policy, not an error). Phase 4 retry also consults `autopilot-policy.yaml` `gates.ticket_quality_fail`.

### Step W-9: Brief metadata injection

If `brief=<path>` provided: read brief `slug` → `{brief_slug}`; extract `{brief_part}` from any "This is part {N} of {total}" indicator (from `/autopilot` split briefs). Add `| Brief Slug | {brief_slug} |` (key `brief_slug`) and (if extracted) `| Brief Part | {brief_part} |` (key `brief_part`) to each ticket.md.

### Step W-10: Summary printing

Print per [references/write-path-templates.md](references/write-path-templates.md). N=1: ticket file path, category, size, AC count, quality, workflow `/scout → /impl → /ship`. N>1: per-ticket table + `split-plan.md` path.

### Step W-11: Emit SW-CHECKPOINT block

Emit `## [SW-CHECKPOINT]` per [references/sw-checkpoint-template.md](references/sw-checkpoint-template.md) as the FINAL section. Fields: `phase: create_ticket`; `ticket: <first ticket-dir or "none">` (N>1: first in topological order); `artifacts:` repo-relative paths to every `ticket.md` + `split-plan.md` (or `artifacts: []` for failure); `context_advice:` literal template sentence verbatim.

**Recommendation line — exactly ONE shape per run**:

- Success N = 1: `next_recommended: /scout <ticket-dir>`; block MUST NOT contain `next_recommended_auto`.
- Success N > 1: BOTH `next_recommended_auto: /autopilot {parent-slug}` AND `next_recommended_manual: /scout {first-unblocked-ticket-dir}` (separate lines, in order); no plain `next_recommended:`. `{first-unblocked-ticket-dir}` = lexicographically smallest `ticket_dir` with `depends_on: []` (per `spec-split-plan-schema.md` first-unblocked rule).
- Failure (any N): `next_recommended: ""`; no `next_recommended_auto:` / `next_recommended_manual:`; `artifacts: []` on a single line.

Dual-recommendation rationale: [references/sw-checkpoint-template.md](references/sw-checkpoint-template.md).

## Error Handling

Every `ERROR:` path is atomic: no directories created, `.ticket-counter` unchanged, non-zero exit.

| Trigger | Output |
|---|---|
| Counter non-numeric | `ERROR: .simple-workflow/.ticket-counter contains non-numeric value '<content>'. Fix or delete the file and retry.` |
| Empty arguments | Print Usage line, stop |
| Both `brief=` and `findings=` | `ERROR: brief= and findings= are mutually exclusive. Pass exactly one.` |
| `findings=<path>` not on disk | `ERROR: Findings file not found at <path>` |
| Brief file not on disk | `ERROR: Brief file not found at <path>` |
| `findings_version` missing or != 1 | `ERROR: findings_version missing or unsupported (expected 1)` |
| Findings zero `## Required Work Units` | `ERROR: findings file contains zero Required Work Units` |
| `SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1` | `ERROR: decomposer capability disabled (SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1)` — stop BEFORE reading input or invoking any agent |
| Decomposer `Status: failed` | `ERROR: decomposer failed — <Rationale>` |
| Decomposer empty Tickets | `ERROR: decomposer returned zero tickets` |
| Decomposer agent unavailable | `ERROR: decomposer agent unavailable` |
| Cyclic `depends_on` | `ERROR: circular dependency detected among tickets: <cycle members>`; literal `circular` MUST appear |
| split-plan validation fails | `ERROR: split-plan validation failed — <reason>` — rollback W-4 dirs |
| Researcher / planner failure | Report error, stop |
| Ticket-evaluator failure | Output ticket with "Quality: NOT EVALUATED" |
| 2 rounds FAIL | Present issues via `AskUserQuestion`. User-confirm to proceed; decline → stop + print ticket path. Non-interactive: stop. Do NOT hang. |
| Split partial failure | Any sub-ticket FAIL → no tickets written, counter not updated (atomic — `counter + N` is the single write in W-5 after all N PASS) |

## Subagent Skill-Access Handoff

When you spawn a subagent via the Agent tool, consult the `Available user skills:` line in the Pre-computed Context above. If a listed utility skill is relevant to that subagent's task, name it in the Agent prompt and instruct the subagent to use it via the Skill tool when it materially helps.

- Do NOT hand skill references to `security-scanner` or `ticket-evaluator`. These subagents are intentionally hermetic and do not carry the Skill tool; referencing skills to them only adds noise.
- Never present a pipeline skill (`/scout`, `/impl`, `/audit`, `/ship`, `/autopilot`, `/brief`, `/catchup`, `/create-ticket`, `/investigate`, `/plan2doc`, `/refactor`, `/test`, `/tune`) as a utility for a subagent.
- When a ticket's `### Capabilities` section exists (resolve via `{ticket-dir}/ticket.md` or the autopilot state file's `paths.ticket`), `Read` it before constructing any subagent spawn prompt and inline the bound capabilities verbatim into every spawn prompt under the heading `## Bound capabilities (per AC)`. For per-AC spawns (one spawn per AC, e.g. `/impl` Steps 13/15), include only the rows whose `Bound AC(s)` column lists the active AC. For tip / whole-deliverable spawns (the rest), include the full table. The upstream binding is authoritative — do NOT re-derive relevance from the AC text or re-scan `Available user skills:` for plausible matches. When the ticket lacks `### Capabilities` (older ticket pre-dating Gate 6), emit `## Bound capabilities (per AC): (none recorded — ticket pre-dates Gate 6)` in the spawn prompt and let the subagent fall back to its in-house capability-selection path.
- If the `Available user skills:` probe reports `(none)`, hand off nothing and let the subagent proceed with its in-house capabilities.
