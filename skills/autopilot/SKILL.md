---
name: autopilot
description: >-
  Consume a pre-built ticket list (split-plan.md under
  .simple-workflow/backlog/product_backlog/{parent-slug}/) and drive the per-ticket
  /scout -> /impl -> /ship pipeline in topological order with policy-based
  autonomous decision making at each gate. Use when:
  (1) the user explicitly invokes /autopilot with a parent-slug;
  (2) another skill chains to /autopilot via the Skill tool after /brief
  and /create-ticket have populated a split-plan;
  (3) a resumable autopilot-state.yaml exists and the user re-runs
  /autopilot to continue from the last checkpoint.
  Triggers on "autopilot", "run the autopilot", "/autopilot <slug>",
  "continue the autopilot run", "drive scout impl ship pipeline".
disable-model-invocation: false
allowed-tools:
  - Skill
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - "Bash(git status:*)"
  - "Bash(git diff:*)"
  - "Bash(git log:*)"
  - "Bash(git branch:*)"
  - "Bash(gh:*)"
  - "Bash(mv:*)"
  - "Bash(ls:*)"
  - "Bash(mkdir:*)"
  - "Bash(date:*)"
  - "Bash(cp:*)"
argument-hint: "<parent-slug>"
---

## Pre-computed Context

Briefs: !`find .simple-workflow/backlog/briefs/active -mindepth 2 -maxdepth 2 -name brief.md 2>/dev/null`

Split plans (SSoT): !`find .simple-workflow/backlog/product_backlog -mindepth 2 -maxdepth 2 -name split-plan.md 2>/dev/null`

Active: !`find .simple-workflow/backlog/active -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -10`

Current branch: !`git branch --show-current`

Default branch: !`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main`

## Mandatory Skill Invocations

`/autopilot` MUST delegate to each target below via the Skill tool. Direct file ops / ad-hoc bash are not substitutes. Bypasses detected by Artifact Presence Gate + audit.

| Invocation Target | When | Skip consequence |
|---|---|---|
| `/scout` (Skill) | 3b | missing `investigation.md`+`plan.md` → `[PIPELINE] scout: ARTIFACT-MISSING`; ticket failed |
| `/impl` (Skill) | 3c | missing `eval-round-*.md` (+`audit-round-*.md`/`quality-round-*.md` on PASS) → `[PIPELINE] impl: ARTIFACT-MISSING`; ticket failed |
| `/ship` (Skill) | 3d | ticket not moved to `.simple-workflow/backlog/done/` → `[PIPELINE] ship: ARTIFACT-MISSING`; no PR |

**Binding rules**:
- `MUST invoke /scout via the Skill tool`; never call `/investigate`/`/plan2doc` standalone.
- `MUST invoke /impl via the Skill tool`; never spawn `implementer`/`ac-evaluator` directly.
- `MUST invoke /ship via the Skill tool`; never run `git commit`/`gh pr create`/`mv` directly.
- `NEVER bypass these skills via direct file operations`.
- `Fail this ticket immediately if any mandatory invocation cannot be completed via the prescribed Skill tool`; record in `autopilot-state.yaml`, next ticket. No fabricated artifacts.

**Ticket creation is NOT in scope.** Upstream `/create-ticket` writes ticket dirs under `.simple-workflow/backlog/product_backlog/{parent-slug}/` + `split-plan.md`. `/autopilot` never writes `ticket.md`, never bumps `.simple-workflow/.ticket-counter`, and MUST NOT emit stdout lines starting with `/create-ticket` — the upstream-missing ERROR keeps `/create-ticket` mid-line so no line matches `^/create-ticket`.

Invocation policy: Do not auto-invoke. `/autopilot` runs only via Skill chain call (explicit `/autopilot <parent-slug>` or chain from another skill). `disable-model-invocation: false` is intentional because callers reference this skill by name; flipping to `true` breaks the chain-call surface for `/brief`, `/create-ticket`, and resume workflows.

Target parent-slug: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS`: extract `{parent-slug}` (first arg). `{parent-slug}` is the dir basename under `.simple-workflow/backlog/product_backlog/` (or brief slug under `briefs/active/`); legacy `{slug}` is interchangeable. Empty → see `## Error Handling`.

## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)

From the moment `/autopilot` resolves `{parent-slug}` and Phase 1 step 1 confirms `SPLIT_PLAN` exists, until ALL of the following are complete -- every ticket is terminal (`completed`/`failed`/`skipped`), Split Autopilot Log is written, Completion Report is printed, Brief Lifecycle runs, State File Cleanup runs, and the final `## [SW-CHECKPOINT]` is emitted -- `AskUserQuestion` invocations are governed by the 3-tier allow-list matrix below, keyed on `risk_tolerance` from `<state-dir>/autopilot-policy.yaml` (already read by Phase 1 step 4 during Human override detection, so no additional I/O is required):

| header (AskUserQuestion `header` field, max 12 chars) | aggressive | moderate | conservative |
|---|---|---|---|
| `audit-fail`   | deny | allow | allow |
| `ac-eval`      | deny | allow | allow |
| `ship-review`  | deny | deny  | allow |
| `ship-ci`      | deny | deny  | allow |
| `eval-dry`     | deny | deny  | allow |
| `tkt-quality`  | deny | deny  | allow |
| (any other)    | deny | deny  | deny  |

The six headers above correspond 1:1 to the autopilot policy gates: `audit-fail` -> `audit_infrastructure_fail`, `ac-eval` -> `ac_eval_fail`, `ship-review` -> `ship_review_gate`, `ship-ci` -> `ship_ci_pending`, `eval-dry` -> `evaluator_dry_run_fail`, `tkt-quality` -> `ticket_quality_fail`. The `unexpected_error` gate is NEVER a user prompt -- it MUST surface as `policy_gate_stop` (see below).

Header naming is load-bearing -- every `AskUserQuestion` emitted inside the autopilot pipeline MUST use one of the six gate IDs above as its `header` field (max 12 chars). Headers outside this set are treated as phase-gate or ad-hoc and **denied at every tier**, including conservative. This includes (non-exhaustive): `phase-gate`, `backend?`, empty header, free-form prose headers, and any prefix-matched bypass attempts. The naming rule is what makes the matrix structurally enforceable; it removes the "reason-wording bypass" attack surface observed in field-test Q6 (where a phase-gate question was disguised as a context-budget concern).

When `risk_tolerance` is absent or unreadable from `autopilot-policy.yaml`, fall through to the Phase 1 step 4 defaults logic and assume `conservative` -- this is the most-conservative tier on the policy-gate axis but still rejects every off-matrix header, so a malformed policy file cannot widen the allow-list.

Hard-stop conditions discovered during Phase 1 (hostile working tree, absent ticket dir, malformed split-plan, brief status `draft`, etc.) MUST surface as `policy_gate_stop` (the state-file mechanism), NOT as user prompts. Concretely: emit `[AUTOPILOT-POLICY] gate=unexpected_error action=stop reason=<...>`, write `## Stop Reason` with `tag: policy_gate_stop`, and append a one-line resume hint of the form `Resume after fixing X with: /autopilot {parent-slug}`. The autopilot session then ends gracefully so the user can resume after fixing the upstream issue. The existing verbatim `ERROR: ...` literals from Phase 1 step 1 / step 3 / step 5 continue to be emitted (downstream contract tests depend on them), alongside the new `policy_gate_stop` exit path.

**A missing git remote is explicitly NOT a hard-stop, and MUST NOT be treated as one.** A remote is not required to build, verify, and locally land a ticket. Proceed with the full pipeline: `/ship` detects the absent remote, commits locally, and skips push + PR creation (see `/ship` Phase 2 step 7 and Error Handling "No remote"), reaching `steps.ship: completed` exactly as a remote-backed ship would — the ticket lands as `completed-with-warnings`, not `failed`. This is load-bearing for context management: a completed `/ship` is precisely what fires the per-ticket auto-compact (`hooks/post-ship-state-auto-compact.sh` keys on `steps.ship: completed`), so hard-stopping before ship over an absent remote would starve auto-compaction and pressure the context window across the remaining tickets. Do NOT emit `policy_gate_stop`, do NOT raise an `AskUserQuestion`, and do NOT defer a "remote blocker" to ship time for an absent remote — there is no blocker; push is simply skipped.

The ONLY legitimate exits, in any tier, are:

1. A policy gate evaluating to `action: stop` (incl. the Phase 1 hard-stop path above, tagged `policy_gate_stop`).
2. The auto-compact exception documented in Phase 2 step e, which is `end_turn` (NOT an interactive prompt) and is the ONE documented place mid-pipeline `end_turn` is permitted.
3. An `AskUserQuestion` whose `header` is on the matrix above AND whose row resolves to **allow** for the current `risk_tolerance`. This third exit replaces the unconditional ban of the prior two-valued contract.

Stop hooks cannot intercept `AskUserQuestion`; this SKILL-level prose is the sole prose-layer enforcement. A structural-layer enforcement (`hooks/pre-askuserquestion-guard.sh`) is provided by plan P1-3B and applies the same matrix at the PreToolUse hook face. The two layers MUST stay synchronized -- changing the matrix here REQUIRES the same change in the hook (and vice versa). The structural enforcement carries its own kill-switch (`SW_AUTOPILOT_ASK_GUARD`) documented under P1-3B; the prose layer has no kill-switch by design.

Forbidden self-rationalisations (each has been observed in the field and produced a contract breach; enumeration is normative, not exhaustive):

- "The per-ticket pipeline has not started yet, so the contract is not yet in effect." -- WRONG. The contract starts at Phase 1 step 1 confirmation of `SPLIT_PLAN`, not at the first `/scout` call.
- "Context budget is running low, so I should ask whether to continue." -- WRONG. Context pressure is handled by `hooks/pre-compact-save.sh` and the auto-compact-on-ship mechanism; this is a phase-gate question, denied at every tier.
- "A precondition is unmet (untracked files, etc.), so I should ask the user to confirm before proceeding." -- WRONG. Treat the unmet precondition as `unexpected_error.action: stop`, emit the policy line + `## Stop Reason`, and exit. (Note: an absent git remote is NOT such a precondition -- it is handled by a local-only `/ship`; see the hard-stop carve-out above.)
- "I am between two phases (Phase 1 just ended, Phase 2 about to begin), so the prohibition does not apply at this seam." -- WRONG. Seams are inside the prohibition window, not at its edges.
- "I will phrase my question as `header: audit-fail` even though it is actually a phase-gate concern, so it slips through the matrix." -- WRONG. The header MUST correspond truthfully to the policy gate whose failure path is currently being evaluated. Mis-labelling is a contract breach equivalent to bypassing the matrix.

## Phase 1: Pre-flight Checks

Pre-flight gate decides whether `/autopilot` has a runnable input. SSoT is `.simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md`; the legacy `briefs/active/.../split-plan.md` path is NOT read.

0. **Auto-kick cleanup**: delete `.simple-workflow/backlog/briefs/active/{parent-slug}/auto-kick.yaml` if present (idempotent). Do NOT touch `brief.md`, `autopilot-policy.yaml`, `autopilot-state.yaml`. `hooks/post-skill-cleanup.sh` (PostToolUse) removes stale `auto-kick.yaml` as defense-in-depth.

0.5. **Emit `[AUTOPILOT-CONTEXT]` self-doc**: Read
`SW_AUTO_COMPACT_ON_SHIP_MODE` from the environment (default `on` in
autopilot context; matches `hooks/pre-next-scout-auto-compact.sh` L81).
Emit EXACTLY ONE `[AUTOPILOT-CONTEXT]` block to stdout per the
branch matching the resolved mode (`on` / `metric-only` / `off`;
unknown values are treated as `off`). The verbatim text of each
branch is fixed and lives in `references/autopilot-context-self-doc.md`.
This step is read-only and idempotent: re-runs after `/compact`
re-emit the same block.

1. **Split-plan discovery**: `SPLIT_PLAN = .simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md`. Exists → parse Phase 2. Missing + brief exists → print exactly `ERROR: split-plan not found at .simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md. Run /create-ticket brief=.simple-workflow/backlog/briefs/active/{parent-slug}/brief.md first to produce the ticket set, then re-run /autopilot {parent-slug}.` and exit non-zero (no stdout matches `^/create-ticket`). Neither → print exactly `ERROR: no split-plan at .simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md and no brief at .simple-workflow/backlog/briefs/active/{parent-slug}/brief.md. Nothing to autopilot.` and exit non-zero. Never create/modify `active/`. Additionally, emit `[AUTOPILOT-POLICY] gate=unexpected_error action=stop reason=missing_split_plan` and write `## Stop Reason` with `tag: policy_gate_stop` plus a resume hint of the form `Resume after fixing X with: /autopilot {parent-slug}`; the verbatim `ERROR: ...` literals above are retained for downstream contract tests and surface alongside the new `policy_gate_stop` exit path — never escalate to `AskUserQuestion`.

2. **Brief optionality**: brief not required; runs whenever `SPLIT_PLAN` exists. Policy propagation is upstream (`/create-ticket brief=<path>` copies `autopilot-policy.yaml` into each ticket dir). No policy → Policy guard aborts. Brief-level `autopilot-policy.yaml` at `briefs/active/{parent-slug}/` is read for decision logging; else per-ticket policy serves the same role.

3. Brief `status`: `confirmed` proceeds; `draft` → print `ERROR: Brief status is 'draft'. Update to 'confirmed' or run /brief with mode=auto.` and stop. Read brief `mode` (default `auto`); if `mode: manual` (equivalently `chain: off`) + `/autopilot` invoked, print `ERROR: Brief is in manual mode (chain: off); per-ticket autopilot-policy.yaml was never propagated (Step W-8 skips it for manual briefs) and the per-ticket Policy guard would abort every ticket. Re-run /create-ticket brief=.simple-workflow/backlog/briefs/active/{parent-slug}/brief.md with the brief set to chain: on (legacy mode=auto) so the policy propagates into each ticket dir, then re-run /autopilot {parent-slug}.` and stop; additionally emit `[AUTOPILOT-POLICY] gate=unexpected_error action=stop reason=brief_mode_manual` and write `## Stop Reason` with `tag: policy_gate_stop` plus a resume hint of the form `Resume after fixing X with: /autopilot {parent-slug}`; never escalate to `AskUserQuestion`. The earlier brief-level fallback wording is retired: the three per-ticket Policy guards (Phase 2 Pre-scout / Pre-impl / Pre-ship) read **only** `product_backlog/{ticket-dir}/autopilot-policy.yaml` with no brief-level substitution, so continuing past a manual brief would strand every ticket — the hard-stop surfaces that one actionable directive at the entry instead. On the `draft` hard-stop path, additionally emit `[AUTOPILOT-POLICY] gate=unexpected_error action=stop reason=brief_status_draft` and write `## Stop Reason` with `tag: policy_gate_stop` plus a resume hint of the form `Resume after fixing X with: /autopilot {parent-slug}`; the verbatim `ERROR:` literal above is retained for downstream contract tests and surfaces alongside the new `policy_gate_stop` exit path — never escalate to `AskUserQuestion`.

4. **Human override detection**: compare each gate in `autopilot-policy.yaml` to defaults for `risk_tolerance`. `conservative` defaults + `moderate` defaults: in [references/state-file.md](references/state-file.md). `aggressive` defaults: moderate + `aggressive ship_ci_pending.timeout_minutes: 60`, `aggressive constraints.max_total_rounds: 12`, `aggressive constraints.allow_breaking_changes: true`. Gate differs + `# kb-suggested` → `kb_override` else `human_override`. Render to `## Human Overrides` / `## KB Overrides`; `## Decisions Made` distinguishes `human_override` from `kb_override`. **Exclude `kb_override`** from `## Human Overrides`. No diff → "No human overrides detected."

5. **State recovery**: absent `autopilot-state.yaml` → `resume_mode = false`. Else `resume_mode = true`; emit `[RESUME] ...` summary (resume msg, execution mode, progress N/total, per-ticket status). If `started` is older than 7 days, emit `[RESUME] WARNING` to delete `autopilot-state.yaml` and re-run. Carry `ticket_mapping`. Per-ticket: `completed` → skip (`[RESUME] Skipping {logical_id}: already completed`); `failed`/`skipped` → retry first non-completed; `in_progress` → re-run; `pending` → normal. If state recovery cannot continue (e.g. unparseable `autopilot-state.yaml`, hostile working tree detected during this step, or any other Phase 1 precondition that newly fails here), emit `[AUTOPILOT-POLICY] gate=unexpected_error action=stop reason=state_recovery_hard_stop` and write `## Stop Reason` with `tag: policy_gate_stop` plus a resume hint of the form `Resume after fixing X with: /autopilot {parent-slug}`; never escalate to `AskUserQuestion`. Any existing verbatim `ERROR:` / `[RESUME] WARNING` literal continues to be emitted alongside the new `policy_gate_stop` exit path.

## Phase 2: Pipeline Execution

### State file initialization

Skip if `resume_mode = true`. Brief-level `autopilot-state.yaml` ≠ per-ticket `phase-state.yaml`. Write at `briefs/active/{parent-slug}/` (else `product_backlog/{parent-slug}/`); hooks also accept `briefs/done/{parent-slug}/`. Fields: `ticket_mapping`, per-ticket `ticket_dir:` + `status` + `steps` + `invocation_method` ∈ `skill`/`manual-bash`/`unknown`, append-only `runtime_metrics: []` (`hooks/autopilot-continue.sh` + `hooks/pre-compact-save.sh` only; skills MUST NOT write). **MUST emit `tickets:` as a YAML list** of dash-prefixed `- logical_id: …` mappings — NOT a map keyed by `logical_id`. The map form silently bypasses the hook-layer skip-transition guard (`parse_proposed_tickets`) and the Stop-hook loop-guard counters (`parse_ticket_statuses`); field evidence `test_simple_workflow28`. Hook tolerance was added in WI-4 as a safety net only; SKILL prose remains the enforcement. Loop-guard emits `[AUTOPILOT-STALL] ...`. Schema invariants (including `tickets:` list-vs-map) + precedence + counters + kill switch + `boundary`/`stop_reason` domains in [references/state-file.md](references/state-file.md) + [references/stop-reason-taxonomy.md](references/stop-reason-taxonomy.md).

### Split Execution Flow

Parse `SPLIT_PLAN` frontmatter + tickets, build dependency graph, run topological sort (lex tiebreak), emit `Processing order: {NNN-slug}` per ticket. Parsing/algorithm in [references/split-plan-parsing.md](references/split-plan-parsing.md). Edge-case ERROR literals (zero entries, cyclic `depends_on`) in `## Error Handling`. Single-ticket plans flow through the same path.

#### Per-ticket pipeline

> **Non-interactive orchestrator contract**: see `## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)` above. Per-ticket pipeline inherits the same 3-tier matrix; the only mid-pipeline `end_turn` is the auto-compact exception in step e.

For each ticket in `PROCESSING_ORDER` (`i` = 0-based):

1. **Resume skip check** (`resume_mode = true` only): `completed` → skip with `[RESUME] Skipping ticket {logical_id}: already completed`; `skipped` → re-evaluate dependencies; `failed`/`in_progress` → resume from first non-completed step.

2. **Dependency check**: all `depends_on` must be `completed`. Any dep `failed`/`skipped` → this ticket `skipped` (reason `dependency_{dep-slug}_{status}`), record `[PIPELINE] {ticket-part}: skipped | reason=dependency_... | ticket-dir={ticket-dir}`, next ticket. Skip-transition invariant + `hooks/pre-state-transition.sh` enforcement in [references/state-file.md](references/state-file.md).

3. **Execute pipeline** (ticket dir starts in `product_backlog/{parent-slug}/`; `/scout` moves it to `active/{parent-slug}/`):

   a. **Pre-scout Policy guard** — `autopilot-policy.yaml` in `product_backlog/{ticket-dir}/` (copied by `/create-ticket`). Missing → `[PIPELINE] scout: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket failed, next ticket.

   b. **Step: scout**.
      - State update (before): `steps.scout = in_progress`, `invocation_method.scout = skill`.
      - Invoke `/scout .simple-workflow/backlog/product_backlog/{parent-slug}/{NNN}-{slug}` via Skill.
      - Artifacts: `investigation.md` + `plan.md`. Missing → `[PIPELINE] scout: ARTIFACT-MISSING`, state failed, next ticket.
      - State update (after): `steps.scout = completed`.

      **CHECKPOINT — RE-ANCHOR**: Read `autopilot-state.yaml`; execute next pending step. Do NOT end turn or summarize.

   c. **Step: impl**.
      - State update (before): `steps.impl = in_progress`, `invocation_method.impl = skill`. Policy guard missing → `[PIPELINE] impl: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket failed, next ticket.
      - Invoke `/impl .simple-workflow/backlog/active/{parent-slug}/{NNN}-{slug}/plan.md` via Skill.
      - Artifacts: ≥1 `eval-round-*.md`; on PASS also ≥1 `audit-round-*.md` AND `quality-round-*.md` (skip when all AC evaluation rounds FAILED). Missing → `[PIPELINE] impl: ARTIFACT-MISSING`, state failed, next ticket.
      - State update (after): `steps.impl = completed`.

      **CHECKPOINT — RE-ANCHOR**: Read `autopilot-state.yaml`; execute next pending step. Do NOT end turn or summarize.

   d. **Step: ship**.
      - State update (before): `steps.ship = in_progress`, `invocation_method.ship = skill`. Policy guard missing → `[PIPELINE] ship: ABORT — autopilot-policy.yaml missing in ticket dir`, mark this ticket failed, next ticket.
      - Invoke `/ship {target-branch} ticket-dir={ticket-dir}` via Skill (no `merge=true`). `/ship` atomically commits + moves ticket + runs `/tune` + opens PR.
      - Artifacts: `.simple-workflow/backlog/done/{parent-slug}/{NNN}-{slug}/` must exist. Missing → `[PIPELINE] ship: ARTIFACT-MISSING`, state failed, next ticket.
      - **Artifact Presence Gate** (7 patterns, `done/` first else `active/`): `ticket.md`, `investigation.md`, `plan.md`, `eval-round-*.md`, `audit-round-*.md`, `quality-round-*.md`, `security-scan-*.md`. Missing → `[PIPELINE] {step}: ARTIFACT-MISSING: {patterns}`, ticket failed. Exception: last `eval-round-*.md` FAIL or FAIL-CRITICAL (all AC evaluation rounds FAILED) → skip last 3.
      - State update (after): `steps.ship = completed`, `status = completed`. Record PR URL. **MUST emit the canonical FLAT schema** — `steps.ship` is a STRING value on a single line (`      ship: completed`), NOT a nested map (`      ship:\n        status: completed`). The auto-compact safety-net hook gates on `steps.ship == "completed"`; the nested form silently bypasses ticket-boundary detection (field evidence: `test_simple_workflow27`). Full schema invariant in [references/state-file.md §"Schema invariants"](references/state-file.md).

      **CHECKPOINT — RE-ANCHOR**: Read `autopilot-state.yaml`; execute next pending step (typically loop-tail step e for the next ticket). Do NOT end turn or summarize. The auto-compact exception is handled at step e below — it is the ONLY documented place a mid-pipeline `end_turn` is permitted.

   e. **Loop-tail CHECKPOINT — iterate or exit**: terminal status (`completed`/`failed`/`skipped`). Re-enter step 1 for `i+1`. **MUST NOT** `end_turn`, **MUST NOT** summarize. **Exit** when all terminal → post-loop phase (Split Autopilot Log → Completion Report → Brief Lifecycle → State File Cleanup → final `## [SW-CHECKPOINT]`).

      **AUTO-COMPACT EXCEPTION (overrides the MUST NOT end_turn rule above)**: If EITHER of the following two additionalContext payloads was injected by the harness during this ticket loop, end the turn immediately or — for the last-ticket variant of (a) — first complete the post-loop phase then end the turn. In ALL cases: do NOT invoke the next `/scout`. The match substrings below are written with the SAME literal backtick characters the hooks emit at runtime, so substring comparison is byte-for-byte:
      - **(a) Safety-net path** — the PostToolUse hook output for an `Edit/Write` that wrote `steps.ship: completed` into `autopilot-state.yaml` contained the label `auto-compact-on-ship (state-write safety-net):` immediately followed by `` `/compact` has been queued `` (from `hooks/post-ship-state-auto-compact.sh`). **last-ticket sub-variant**: if the body also contains the substring `FINAL ticket of this pipeline`, the just-shipped ticket was the FINAL one and the post-loop phase (Split Autopilot Log → Completion Report → Brief Lifecycle → State File Cleanup → final `## [SW-CHECKPOINT]`) MUST run FIRST — only then end the turn. Skipping the post-loop phase would lose `autopilot-log.md`, the `briefs/done/` move, and the runtime_metrics finalize. **non-last sub-variant**: body lacks `FINAL ticket of this pipeline`; end the turn immediately, do NOT print a summary, do NOT issue any further tool call.
      - **(b) Primary ticket-boundary path** — the PreToolUse hook output for the NEXT ticket's `Skill(simple-workflow:scout)` invocation contained the label `auto-compact-on-ship (ticket-boundary):` immediately followed by `` `/compact` has been queued `` (from `hooks/pre-next-scout-auto-compact.sh`). End the turn immediately; the primary trigger never fires on the last ticket by construction (it only fires before a next `/scout` that, by definition, has remaining work).

      This is the ONE documented exception to the otherwise-strict "Do NOT end turn" rule in this pipeline. Reason: the queued `/compact` only drains while Claude Code's input loop is idle; without an end_turn it sits for 18-30+ minutes (field evidence: `test_simple_workflow19/20`), defeating the auto-compaction it was meant to perform. After end_turn the `/compact` runs, PreCompact saves the snapshot, `hooks/session-start.sh` PTY-injects `/autopilot {parent-slug}` on the post-compact session, and the resume contract (`hooks/autopilot-continue.sh` + `[RESUME] Skipping {logical_id}: already completed`) picks the NEXT ticket up from `autopilot-state.yaml` (the just-completed ticket is already `steps.ship = completed`, so resume skips it). When BOTH additionalContext payloads are absent (auto-compact disabled, terminal unsupported, or `SW_AUTO_COMPACT_ON_SHIP_MODE=off`), the MUST NOT end_turn rule stands and iteration continues normally. Field evidence for this redesign: `test_simple_workflow23` showed that the v6 `PostToolUse(Skill:simple-workflow:ship)` trigger fires when `/ship` is **invoked**, not when its body completes — the model either state-LIED (wrote `ship: completed` before the actual git commit) or DEFIED the additionalContext (executed `/ship` body inline and never end_turned). The v7 ticket-boundary trigger sidesteps both failure modes by waiting until `steps.ship: completed` is genuinely on disk (state-write path) or until the next ticket's `/scout` is about to launch (ticket-boundary path).

4. **Per-ticket error handling**: any step failure → ticket `failed`, log error, next ticket (do NOT stop pipeline). Dependents skipped (step 2). Independent tickets still run.

### Split Autopilot Log

Write overall `autopilot-log.md` at `briefs/active/{parent-slug}/` (or `briefs/done/` post-move; no brief dir → `product_backlog/{parent-slug}/`) AND per-ticket logs in each ticket dir (`done/...` if `/ship` Step 5 reached, else `active/...`). Per-ticket logs required. Frontmatter + per-ticket subsection + six common sections (`## Pipeline Execution`, `## Warnings`, `## Human Overrides`, `## KB Overrides`, `## Decisions Made`, `## Unreached Gates`) + Manual Bash Fallback rendering (`manual_bash_fallbacks[]` SSoT in `autopilot-state.yaml`; per-step `invocation_method == manual-bash` derived) live in [references/autopilot-log.md](references/autopilot-log.md).

### Split Completion Report

Print: overall status (completed/partial/failed); per-ticket table (status + PR URL); counts `{completed}/{failed}/{skipped} of {total}`. On partial/failed: tell user to re-run `/autopilot {parent-slug}` (resumes from checkpoint) or remove `autopilot-state.yaml` to start fresh.

### Split Brief Lifecycle

All completed + brief exists → brief `completed`, move to `briefs/done/`. Any failed/skipped + brief exists → brief `stopped`, stays in `briefs/active/`. No brief → skip. `final_status` (`completed`/`completed-with-warnings`/`partial`/`failed`) discrimination in [references/autopilot-log.md](references/autopilot-log.md).

### Split State File Cleanup

**Move** `autopilot-state.yaml` to `briefs/done/{parent-slug}/autopilot-state.yaml` (create dir if missing). NEVER delete — Manual Bash Fallback history must be preserved. ("State file cleanup" step.) Stop + PreCompact hooks treat `briefs/done/` as a third lookup root after `briefs/active/` → `product_backlog/`, adopted ONLY when every step has `completed`.

### Gate decisions and Unreached gates

Canonical gates: `scout`, `plan`, `build`, `verify`, `retro`. Each emits `[AUTOPILOT-POLICY] gate=<name> action=<allow|deny|skip> reason=<reason>` + a `## Decisions Made` row. Canonical reasons: `evaluated`, `not_reached`, `condition_unmet`, `dependency_skipped` — `evaluated` pairs any action; rest pair `action=skip` only. Terminate before considering gates → `autopilot-log.md` MUST contain `## Unreached Gates` listing each as `- <gate>: not_reached`. Every gate has a row → heading MUST NOT appear. Edge: empty decisions → enumerate all five. Regexes + reason-semantics + enumeration regex + edge in [references/gate-decisions.md](references/gate-decisions.md).

**`completed-with-warnings`**: all tickets completed + ≥1 ticket has non-empty `manual_bash_fallbacks[]`. Replay every entry in `## Warnings`; per-step `invocation_method == manual-bash` is derived.

### Manual Bash Fallback Discipline

A Manual Bash Fallback is a last-resort orchestrator-level `Bash` call to recover from a subagent anomaly. Log every fallback to `autopilot-state.yaml` `manual_bash_fallbacks[]`; replay verbatim in `autopilot-log.md`. Per-step `invocation_method == manual-bash` is derived.

**MUST NOT treat as Manual Bash Fallback**:
- Subagent response truncation/failure — re-spawn via the configured retry gate.
- Context window / context budget / context pressure rationales — context pressure is not an anomaly; canonical responses are auto-compaction (`hooks/pre-compact-save.sh`) and `unexpected_error.action: stop`. Such rationales in `manual_bash_fallbacks[].reason` are rejected by `hooks/lib/forbidden-rationale-patterns.sh`.

**MUST NOT use destructive operations as error shortcuts**: `rm -rf`, `rm -f .git/index`, `git reset --hard`, `git clean -f`, `git checkout .`, `git branch -D`.

Runtime enforcement: `hooks/pre-bash-contract-guard.sh` (`PreToolUse:Bash`) blocks forbidden-rationale appends and `/ship` bypasses. Full forbidden-rationale list, `manual_bash_fallbacks:` schema, and `hooks/lib/forbidden-rationale-patterns.sh` link in [references/manual-bash-fallback.md](references/manual-bash-fallback.md).

## Context-Pressure Response Paths

Two canonical responses; a third (`AskUserQuestion` escalation, inline Bash fallback, skipping a Skill invocation) violates the contract. **(a) Accept auto-compaction**: `hooks/pre-compact-save.sh` writes `boundary: session_compaction`; on rehydrate, resume prints `[RESUME] Skipping {logical_id}: already completed` and continues. **(b) Stop via `unexpected_error.action: stop`**: gate `unexpected_error` emits `[AUTOPILOT-POLICY] gate=unexpected_error action=stop` and writes `## Stop Reason` with `tag: policy_gate_stop`; resume via `/autopilot {parent-slug}`. Forbidden third paths in [references/manual-bash-fallback.md](references/manual-bash-fallback.md).

## Stop Reason

An `autopilot-log.md` for a stopped/failed run MUST include `## Stop Reason`. Tag values, heuristic, per-tag conditions in [references/stop-reason-taxonomy.md](references/stop-reason-taxonomy.md); `stop_reason` namespace also written by Stop hook into `autopilot-state.yaml` `runtime_metrics:` entries (SSoT across log + state). Section format:

```markdown
## Stop Reason
- **tag**: `<one of: self_abort | loop_guard_release | policy_gate_stop | partial_completion | normal_completion | harness_terminated>`
- **timestamp**: 2026-04-29T19:39:10Z
- **last_completed_ticket**: <logical_id or `null`>
- **next_pending_ticket**: <logical_id or `null`>
- **note**: <free-form, 1-2 lines>
```

## Error Handling

- **Empty arguments**: `Usage: /autopilot <parent-slug>` and stop.
- **No split-plan / split-plan missing but brief exists**: see Phase 1 step 1 for the verbatim `ERROR:` literals (both include `not found`).
- **Empty split-plan** (zero ticket entries): print exactly `ERROR: split-plan.md at .simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md is empty (zero ticket entries).` and exit non-zero. Literal `empty` is load-bearing.
- **Cyclic `depends_on` graph**: print exactly `ERROR: circular dependency detected in split-plan.md at .simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md among tickets: <list cycle members>` and exit non-zero **before any ticket work begins**. Literal `circular` (or `cycle`) MUST appear in stdout.
- **Brief not confirmed** (brief `status: draft`): see Phase 1 step 3 for exact message.
- **Manual-mode brief invoked under `/autopilot`** (brief `mode: manual` / `chain: off`): see Phase 1 step 3 — hard-stops with `reason=brief_mode_manual` and a directive to re-run `/create-ticket` with the brief set to `chain: on` so per-ticket `autopilot-policy.yaml` propagates, since the per-ticket Policy guards have no brief-level fallback.
- **Pipeline step failure**: check `gates.unexpected_error.action`. `stop` (default) → log, mark failed, partial report. Other value → treat as `stop`; print `[AUTOPILOT-POLICY] gate=unexpected_error action=stop (fallback from unsupported action={original_action})`. Policy absent → default `stop`. Always print `[AUTOPILOT-POLICY] gate=unexpected_error action={actual_action}`. Mark failed, next ticket; dependents skipped.
- **Artifact preservation**: artifacts remain in the ticket dir — `done/...` if `/ship` Step 5 completed, else `active/...`. `autopilot-state.yaml` records progress for resume.
