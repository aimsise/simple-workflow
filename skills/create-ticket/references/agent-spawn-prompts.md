# `/create-ticket` Agent Spawn Prompts

Verbose Phase 1 / 2 / 3 / 4 spawn-prompt construction details, the retry-with-feedback loop, the autopilot-policy gate lookup, and the retry-planner filesystem-search ban. `skills/create-ticket/SKILL.md` retains the headings, binding rules, AC marker pair, and pinned literals; this reference file expands each phase so SKILL.md can stay within the BP token budget.

## Phase 1: Investigation (researcher agent)

The orchestrator MUST invoke the `researcher` via the Agent tool. NEVER bypass via direct `Grep`/`Read`/`Glob` — independent findings are required for Phase 3. Fail the task immediately if the researcher cannot be invoked.

**Return value cap**: per the Context Conservation Protocol in `agents/researcher.md`, the researcher's return value MUST stay under 500 tokens (status, executive summary, output path). The full investigation content lives at the canonical artifact path; the orchestrator reads it only when the planner needs it.

Researcher scope:

1. Source code related to the ticket description.
2. Affected files and line ranges.
3. Existing test coverage.
4. Related documentation.
5. Dependencies (relationships with other tickets).

In **findings mode**, Phase 1 is already satisfied by the findings document itself — the decomposer consumes the prior investigation directly. The researcher is only invoked again if the decomposer's Rationale flags missing context.

In **brief mode**, Phase 1 is reused (researcher invocation skipped) when a `{ticket-dir}/investigation.md` already exists in the same ticket directory the brief is bound to **AND** that file satisfies the freshness criterion defined below. The reuse is strictly scoped to `{ticket-dir}/investigation.md` inside the resolved ticket directory; an `investigation.md` from any other directory MUST NOT be reused (no remote-directory borrowing).

**Freshness criterion** (mechanically checkable; presence alone is NOT sufficient). An existing `{ticket-dir}/investigation.md` is considered fresh and reusable iff at least ONE of the following signals holds, and the chosen signal is recorded in the Phase 1 trace:

1. **`phase-state.yaml` provenance (preferred)** — `{ticket-dir}/phase-state.yaml` exists and `phases.scout.artifacts.investigation` resolves to the same `{ticket-dir}/investigation.md` path with `phases.scout.status` ∈ {`in-progress`, `completed`} and a `started_at` (or `completed_at`) timestamp not earlier than the file's `mtime`. This is the canonical signal because `/scout` (and `/investigate` via `/scout`) is the only legitimate writer of that artifact slot per `references/phase-state-schema.md` §2.
2. **mtime freshness threshold** — when `phase-state.yaml` has no `phases.scout.artifacts.investigation` entry, the file's `mtime` MUST be within the last 24 hours (≤ 86400 s before the current `/create-ticket` invocation start time). Files older than this threshold are treated as stale.
3. **Content-hash signature** — when the brief's YAML frontmatter records an `investigation_sha256:` field, the SHA-256 of `{ticket-dir}/investigation.md` MUST match that value byte-for-byte. A mismatch is treated as stale.

When `{ticket-dir}/investigation.md` is absent, OR is present but fails ALL of the freshness signals above (e.g., a leftover file from an aborted earlier run with no matching `phase-state.yaml` provenance, an mtime older than 24 h, and no matching `investigation_sha256:`), the reuse path MUST NOT fire: brief mode falls through to the default behavior and the researcher is invoked exactly as in the no-file case. Phase 1 is mandatory whenever the reuse condition is not met — there is no third path that drafts a ticket without either a researcher invocation or a freshness-validated reused file.

When the reuse path fires, Phase 1 still emits the same downstream contract as a researcher invocation: an executive summary plus the output file path. The schema of this Phase 1 output is identical to the researcher-invoked schema. **Bare-description mode does NOT participate in this reuse path** — bare mode always runs the researcher.

For fresh bare and brief runs (no reuse), the orchestrator passes a transient output path under `.simple-workflow/.tmp/create-ticket-{parent-slug}/investigation.md` to the researcher. The transient location keeps Common Write Path atomicity intact (the canonical product_backlog ticket directories are created only at Step W-4 after every evaluation passes); the orchestrator reads the transient file when constructing the `scope_context` decomposer prompt in Step B-5 / D-4.

## Phase 2: Socratic Refinement

**Brief mode with `interview_complete: true`**: SKIP Phase 2 entirely — the brief already contains structured-interview context. Proceed to Phase 3 immediately. When `brief=<path>` is provided and the brief's YAML frontmatter contains the literal line `interview_complete: true`, the skill MUST NOT invoke `AskUserQuestion` and MUST NOT block on stdin; a ticket file is expected to appear under `.simple-workflow/backlog/` within 10 seconds even with closed stdin.

**Brief mode with `interview_complete: false` or absent**: run the capped Socratic interview below. Absence of the `interview_complete` key is treated as `false` (safe default — run the interview when capability is available).

**Findings mode**: SKIP Phase 2 if the upstream brief (if any) had `interview_complete: true`. Otherwise run the capped interview.

**Bare description mode**: always run the capped interview (unless non-interactive fallback fires).

**Interview caps** (load-bearing for contract):
- At most **3 questions per round** (a single `AskUserQuestion` call carries at most 3 items).
- At most **10 rounds** total across the interview.
- Therefore at most **30 questions total** before a ticket file appears under `.simple-workflow/backlog/`.

These caps apply uniformly. Implementations MUST NOT exceed 3 items per `AskUserQuestion` call and MUST NOT issue more than 10 rounds.

Refine scope through targeted questions:

1. Analyze the researcher's findings (or the findings / brief document in the respective modes).
2. Identify unclear points across scope boundaries, priority, edge cases, constraints.
3. Use `AskUserQuestion` for up to 3 targeted questions per round (single call; at most 10 rounds → at most 30 questions total). **Non-interactive fallback**: If `AskUserQuestion` is unavailable / errors (typical in `claude -p` / CI where stdin is not a TTY), skip Phase 2 and proceed to Phase 3 with researcher findings only. Note "Phase 2 skipped (non-interactive mode)" in the final summary. Do NOT hang.
4. Save the answers for the Phase 3 planner prompt.
5. **Convergence**: stop the interview once the user indicates sufficiency, scope is clear, or 10 rounds have been reached.

If investigation yields sufficient clarity (e.g., simple S-size with obvious scope), skip questioning and proceed to Phase 3.

## Phase 3: Ticket Draft (planner agent)

The orchestrator MUST invoke the `planner` via the Agent tool. NEVER draft inline — the planner's structured output (Background / Scope / Acceptance Criteria / Implementation Notes + category/size/workflow) is the canonical draft for Phase 4. Fail the task immediately if the planner cannot be invoked.

**Return value cap**: per the Context Conservation Protocol in `agents/planner.md`, the planner's return value MUST stay under 500 tokens (status, output path, 1-2 line summary). The full draft is persisted to the artifact; the orchestrator and the Phase 4 evaluator read it from disk.

Planner scope:

1. Ticket structure (Background, Scope, Acceptance Criteria, Implementation Notes).
2. Category (Security / CodeQuality / Doc / DevOps / Community) and size (S/M/L/XL).
3. Workflow recommendations based on category × size, using workflow patterns in `references/workflow-patterns.md`.

Additional context for the planner:
- Phase 2 answers (scope, priority, edge cases, constraints).
- If brief was provided: full brief content (replaces Phase 2 answers).
- If findings mode: decomposer-returned skeleton (title, scope_summary, size, depends_on) plus the findings file content, so the planner can lift affected files and observable outcomes verbatim.
- The literal instruction: "Each AC will be evaluated by an independent evaluator against the canonical AC Quality Criteria at `skills/create-ticket/references/ac-quality-criteria.md`. The planner MUST follow that file as the sole source of truth for Gates 1-5, including the Gate 4 observation-point carve-out and the Gate 5 size-mismatch rationale rule. ACs that fail any gate will be rejected."

Planner behaviour: draft every AC to satisfy Gates 1-5 on first pass; when the file-count axis and AC-count axis of Gate 5 disagree, include a short rationale in the ticket so the evaluator can apply the single-axis tiebreak rule.

### Partition is owned by the decomposer (all modes)

Partition (the decision of how many ticket skeletons to produce) is performed by the `decomposer` agent in every mode (bare / brief / findings). The planner receives N skeletons one at a time from the decomposer and never re-partitions its own draft. The legacy planner-side partition mechanisms (the per-mode partition heuristic, the per-tier dynamic shrinkage tied to `runtime_metrics:`, and the confidence-based loop skip) were removed in v6.2.0 when bare and brief modes were unified onto the decomposer-led partition path. See `references/spec-decomposer-input.md` for the input forms the orchestrator constructs.

## Phase 4: Ticket Evaluation

The orchestrator MUST invoke the `ticket-evaluator` via the Agent tool. NEVER self-assess — the ticket-evaluator is the independent gate verifying AC Testability/Unambiguity. Fail immediately if it cannot be invoked.

**Return value cap**: per the Context Conservation Protocol in `agents/ticket-evaluator.md`, the evaluator's return value MUST stay under 500 tokens (PASS/FAIL verdict + per-AC findings). The full Feedback transcript is consumed by Phase 4's retry-with-feedback loop on FAIL; the orchestrator does not re-echo it.

### Canonical AC Quality Criteria injection

For every `ticket-evaluator` spawn (both the initial evaluation and any retry re-spawn), the orchestrator MUST `Read` the file `skills/create-ticket/references/ac-quality-criteria.md` and inline-inject its full content between the literal marker pair `<canonical_ac_criteria>` and `</canonical_ac_criteria>`. The evaluator does NOT read the canonical file itself — it consumes only the marker block in its spawn prompt, so failure to inject is a contract violation that will cause the evaluator to fail-fast with ERROR. If the `Read` cannot resolve the canonical file, stop with an ERROR rather than spawning the evaluator without the rubric.

**When split (N > 1, any mode)**: Run the evaluation process below **independently per sub-ticket**. If any sub-ticket FAILs after exhausting retry/escalation, the entire create-ticket stops (all sub-tickets affected; no directories created; counter untouched).

**When not split (N = 1)**: Run the evaluation for the single ticket.

### Per-ticket evaluation process

1. Read the ticket content from Phase 3.
2. Spawn the **ticket-evaluator** with the ticket content. Include the canonical AC Quality Criteria inline in the spawn prompt, delimited by `<canonical_ac_criteria>` ... `</canonical_ac_criteria>` (using the rubric text just `Read` from `references/ac-quality-criteria.md`).
3. Output envelope: the evaluator returns a `Status: PASS|FAIL` line plus a per-AC findings list. Treat any other shape as ERROR.
4. Decision:
   - **PASS** → proceed to Common Write Path.
   - **FAIL** → enter the retry-with-feedback loop below.

### Retry-with-feedback loop (FAIL path)

a. Save the evaluator's Feedback transcript.

b. Re-spawn the **planner** with: original ticket content (inlined verbatim into the spawn prompt); evaluator Feedback (all FAIL items + improvement suggestions); instruction "For each FAIL item you revise, prepend a 'Change rationale: [why this addresses the feedback]' comment above the revised section. The evaluator reviews the rationale to verify intent."

#### Retry planner FS-search ban (token-efficiency contract)

The retry spawn prompt MUST include the following literal constraint, and the planner MUST honor it even though its `tools:` allowlist (see `agents/planner.md`) still permits Read/Grep/Glob/Bash. The allowlist itself is NOT modified — this is a prompt-level suppression only.

- The retry planner works **solely from the inlined prior draft** and the inlined evaluator Feedback supplied in this spawn prompt.
- The retry planner MUST NOT search the filesystem for the prior `ticket.md` (no `Bash(find:*)`, no `Bash(grep:*)`, no `Bash(ls:*)`, no `Read` of any `ticket.md` path on disk, no `Grep`/`Glob` over the repository looking for ticket files). The prior draft is already inline; re-discovering it from disk is forbidden and wastes cache.
- The retry planner MUST NOT shell out to look for ticket directories, `.simple-workflow/backlog/...`, or any `ticket.md` artifact under any path; the canonical input is the inlined draft text only.
- These suppressions are **intentional** even when the underlying tool permission would allow the call. Treat the constraint as a hard contract: if the inlined draft is malformed or missing, fail-fast with `ERROR: retry spawn missing inlined prior draft` rather than reaching for the filesystem.

c. Re-spawn the **ticket-evaluator** on the revised ticket. Again include the canonical AC Quality Criteria inline in this retry spawn prompt, delimited by the same `<canonical_ac_criteria>` ... `</canonical_ac_criteria>` marker pair. Missing the marker block causes the evaluator to fail-fast with ERROR.

d. Max 2 rounds (initial + 1 revision). If still FAIL, run the autopilot-policy escalation below.

### Autopilot-policy escalation (gates.ticket_quality_fail)

After 2 rounds of FAIL, check `{ticket-dir}/autopilot-policy.yaml` at `.simple-workflow/backlog/product_backlog/{parent-slug}/{ticket-dir}/`. If missing **and** `brief=<path>` was given **AND** `brief_mode == auto` (parsed in Step B-2; legacy briefs without `mode:` are treated as `auto`), also check `{brief-parent-dir}/autopilot-policy.yaml` (e.g. `.simple-workflow/backlog/briefs/active/{slug}/`). When `brief_mode == manual`, the brief-parent `autopilot-policy.yaml` fallback is **skipped** — manual-mode runs do not pull retry-strategy from autopilot policy and proceed directly to the interactive flow below.

- If a policy file is present, read `gates.ticket_quality_fail`:
  - `retry_with_feedback` + retry count < `max_retries` → continue retrying. Print `[AUTOPILOT-POLICY] gate=ticket_quality_fail action=retry_with_feedback round={n}`.
  - else → stop. Print `[AUTOPILOT-POLICY] gate=ticket_quality_fail action=stop`.
- Else interactive flow:
  - `AskUserQuestion`: "The ticket has unresolved quality issues: [list]. Proceed anyway or stop to revise manually?"
  - Proceed → Common Write Path with issues noted.
  - Stop → print ticket path + issues.
- **Non-interactive fallback**: If `AskUserQuestion` unavailable / errors, default to **stop**. Print "Stopped: /create-ticket cannot resolve FAIL gates non-interactively. Ticket saved at <path>. Re-run interactively." and exit. Do NOT hang.
