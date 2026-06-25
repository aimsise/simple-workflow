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
argument-hint: "<what-to-build> [chain=on|off] [uc=on|off|metric-only] [parallel=on|off|metric-only] (legacy: mode=auto|manual)"
---

## Pre-computed Context

Interview templates:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/brief/references/interview-templates.md" 2>/dev/null || echo "[WARNING: interview-templates.md not found]"`

Existing briefs:
!`ls -t .simple-workflow/backlog/briefs/active/*/brief.md 2>/dev/null | head -5`

Knowledge base (autopilot patterns):
!`cat .simple-workflow/kb/index.yaml 2>/dev/null | grep -A2 "^autopilot:" || echo "[No autopilot patterns in knowledge base]"`

Available user skills: !`( ls -1 ~/.claude/skills 2>/dev/null ; ls -1 .claude/skills 2>/dev/null ) | sort -u | grep . | tr "\n" "," | sed "s/,$//" | grep . || echo "(none)"`

Available MCP servers: !`( jq -r '.mcpServers // {} | keys[]' .mcp.json 2>/dev/null ; jq -r '.mcpServers // {} | keys[]' ~/.claude.json 2>/dev/null ) | sort -u | grep . | tr "\n" "," | sed "s/,$//" | grep . || echo "(none)"`

# /brief

User input: $ARGUMENTS

## Scope boundary

`/brief` produces two artifacts and stops: `.simple-workflow/backlog/briefs/active/{slug}/brief.md` and `.simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml`. **`/brief` never writes `split-plan.md`** — ticket decomposition is owned by `/create-ticket`. Obsolete frontmatter fields `split:` and `ticket_count:` are **not emitted**.

## Argument Parsing

Parse `$ARGUMENTS`:
- **Preferred new key — `chain=<value>`**: extract `chain=<value>` if present. **Value normalization**: trim whitespace and lowercase the value (`chain=ON`, `chain=Off`, `chain= on ` normalize to `on`/`off`). Token `chain=` is matched case-insensitively. Accepted: `on` (default if neither `chain=` nor `mode=` is supplied), `off`. Any other value → stop and emit `ERROR: invalid chain=<value>. Use chain=on or chain=off` (substituting the offending value); do NOT create the brief directory, do NOT write `brief.md`, do NOT write `autopilot-policy.yaml`, and do NOT write `auto-kick.yaml`; exit non-zero. Mapping for downstream / legacy reasoning: `chain=on` ≡ `mode=auto`, `chain=off` ≡ `mode=manual`.
- **Deprecated alias — `mode=<value>`**: extract `mode=<value>` if present. **Value normalization**: trim whitespace and lowercase the value (`mode=AUTO`, `mode=Manual`, `mode= auto ` normalize to `auto`/`manual`). Token `mode=` is matched case-insensitively. Accepted: `auto` (treated as `chain=on`), `manual` (treated as `chain=off`). Any other value → stop and emit the invalid-mode error (see ## Error Handling for exact message + side-effect contract). **When `mode=` is supplied, also emit to stderr the single line `WARNING: 'mode=' is deprecated and will be removed in a future major version. Use 'chain=on' instead of 'mode=auto', 'chain=off' instead of 'mode=manual'.`** (verbatim literal, including the leading `WARNING:` and the surrounding single quotes). The warning is informational; processing continues with the `mode=` value mapped to the equivalent `chain=` value.
- **Simultaneous specification — `chain=` and `mode=` both present**: stop and emit `ERROR: 'chain=' and 'mode=' cannot be combined. Use 'chain=' (preferred).` Do NOT silent-rewrite; do NOT pick one and ignore the other. Do NOT create the brief directory, do NOT write `brief.md`, do NOT write `autopilot-policy.yaml`, and do NOT write `auto-kick.yaml`. Exit non-zero. (This mirrors the v6.0.0 `auto=true` defensive stance — no silent rewrites of ambiguous argument intent.)
- **Default when both keys are omitted**: `chain=on` (equivalent to legacy `mode=auto`). The default preserves the prior `mode=auto`-default behavior so existing user-typed `/brief "<X>"` invocations continue to chain into `/create-ticket` and `/autopilot`.
- **`auto=true` removal (v6.0.0)**: if `auto=true` (case-insensitive) appears in `$ARGUMENTS`, stop and emit the v6.0.0 removal error (see ## Error Handling). The removal is intentional and `auto=true` is NOT silently rewritten.
- **ultracode orchestration — `uc=<value>` (additive, run-scoped opt-in)**: extract `uc=<value>` if present, using the SAME case-insensitive `key=value` convention as `chain=` above (token `uc=` matched case-insensitively; trim whitespace and lowercase the value, so `uc=ON`, `uc=Off`, `uc= metric-only ` normalize to `on`/`off`/`metric-only`). Accepted values: `on`, `off`, `metric-only`. **Default when `uc=` is omitted: `on` under `chain=on` (the `/brief` default), `off` under `chain=off`.** Resolve the effective `uc` value (`resolved_uc`) as follows, AFTER the `chain` value has been resolved above:
  - When `chain` resolves to `on` (≡ legacy `mode=auto`, the `/brief` default) → `resolved_uc` = the explicitly parsed `uc=` value (`on`, `off`, or `metric-only`) if one was supplied, ELSE `on` (the default — ultracode orchestration is on by default). The value is carried into the Finalization Step 2 chained handoff (it is forwarded to the chained `/autopilot`, which records it as run-scoped state and propagates it to each per-ticket `/impl`; `/brief` itself does not act on `uc` beyond forwarding it).
  - When `chain` resolves to `off` (≡ legacy `mode=manual`) AND the parsed `uc=` value is `on` or `metric-only` → emit to stderr the single line `WARNING: uc=on ignored when chain=off (no chained /autopilot to receive it)` (verbatim literal, including the leading `WARNING:`) and set `resolved_uc = off`. This is a **WARNING, not an error**: there is no chained `/autopilot` in `chain=off` mode to receive the value, so `uc` is ignored; processing continues normally (the brief is still written, Step 3 manual guidance still runs). Do NOT stop, do NOT exit non-zero, do NOT suppress any artifact.
  - When `chain` resolves to `off` AND the parsed `uc=` value is `off` (or `uc=` is omitted) → `resolved_uc = off` silently (no warning — nothing to ignore).
  - Any value other than `on`/`off`/`metric-only` → treat as `off` (this argument is an observe-only opt-in; an unrecognized value never blocks brief creation). `resolved_uc` is carried forward to Finalization Step 2.
- **parallel execution — `parallel=<value>` (additive, run-scoped opt-in)**: extract `parallel=<value>` if present, using the SAME case-insensitive `key=value` convention as `uc=` above (token `parallel=` matched case-insensitively; trim whitespace and lowercase the value, so `parallel=ON`, `parallel=Off`, `parallel= metric-only ` normalize to `on`/`off`/`metric-only`). Accepted values: `on`, `off`, `metric-only`. **Default when `parallel=` is omitted: `on` under `chain=on` (the `/brief` default), `off` under `chain=off`.** Resolve the effective `parallel` value (`resolved_parallel`) AFTER the `chain` value has been resolved above, exactly mirroring `resolved_uc`:
  - When `chain` resolves to `on` (the `/brief` default) → `resolved_parallel` = the explicitly parsed `parallel=` value (`on`, `off`, or `metric-only`) if one was supplied, ELSE `on` (the v9.0.0 default — wave-parallel ticket execution is on by default). The value is carried into the Finalization Step 2 chained handoff (forwarded to the chained `/autopilot`, which records it as run-scoped state and selects each ticket's execution path; `/brief` itself does not act on `parallel` beyond forwarding it).
  - When `chain` resolves to `off` AND the parsed `parallel=` value is `on` or `metric-only` → emit to stderr the single line `WARNING: parallel=on ignored when chain=off (no chained /autopilot to receive it)` (verbatim literal, including the leading `WARNING:`) and set `resolved_parallel = off`. This is a **WARNING, not an error**: there is no chained `/autopilot` in `chain=off` mode to receive the value; processing continues normally (the brief is still written). Do NOT stop, do NOT exit non-zero, do NOT suppress any artifact.
  - When `chain` resolves to `off` AND the parsed `parallel=` value is `off` (or `parallel=` is omitted) → `resolved_parallel = off` silently (no warning — nothing to ignore).
  - Any value other than `on`/`off`/`metric-only` → treat as `off` (fail-safe; an unrecognized value never blocks brief creation). `resolved_parallel` is carried forward to Finalization Step 2.
- Remove the parsed `chain=` AND `mode=` AND `uc=` AND `parallel=` tokens from the description; remaining text is `<what-to-build>`.
- If `<what-to-build>` is empty, print `Usage: /brief <what-to-build> [chain=on|off]` (legacy alias accepted: `mode=auto|manual`) and stop.
- Generate `{slug}` from `<what-to-build>` using kebab-case (e.g., "Add User Auth" -> `add-user-auth`). The brief `{slug}` also serves as the `{parent-slug}` downstream.

## Phase 1: Initial Investigation

1. Spawn the **simple-workflow:researcher** agent (sonnet) via the Agent tool:
   - description: "Investigate codebase for: <what-to-build>"
   - Prompt: "Investigate the codebase to understand existing patterns, dependencies, similar features, and technical constraints related to: <what-to-build>. Focus on: (1) existing code patterns and architecture, (2) related dependencies, (3) similar existing features, (4) potential technical constraints. Return a concise summary under 500 tokens."
   - model: sonnet
2. Save the researcher's summary for use in Phase 2 and Phase 3.

3. **§1.5 — Advisory Consultation Pre-Check** (gating, v8.0.0+ Phase 6 enforcement; mirrors `/impl` Step 14b): the researcher return value received at Step 1 MUST contain a `**Advisory consultation**:` field per the format in `agents/researcher.md` `## Advisory Capabilities` → `### Consultation reporting format`. Match by regex `^\*\*Advisory consultation\*\*:` on the return value (case-sensitive, line-anchored). Two outcomes:
   - **Field present** (the value is either `(none)` or a bullet list of `- <Name>: invoked/not invoked (...)` entries) → emit `[ADVISORY-CONSULT] brief researcher present` to stderr and proceed to Phase 2.
   - **Field absent** → contract violation. Emit `[PIPELINE] brief: ADVISORY-MISSING (agent=researcher)` to stderr; record the violation in the final summary surfaced to the user (note the missing Phase 6 audit trail and degrade gracefully); do NOT silently re-spawn the researcher. Re-rolling the same Generator without surfacing the contract violation would mask the regression. Since `/brief` has no `phase-state.yaml` of its own, the violation is surfaced in-band via the executive summary rather than via a state-file FAIL write.

## Phase 2: Structured Interview (Socratic)

Conduct an iterative Q&A to gather comprehensive requirements.

**mode independence guard (load-bearing — preserved during the `chain=` / `mode=` deprecation period; defensive prose now covers BOTH the new `chain` argument AND the legacy `mode` alias)**: Phase 2 Structured Interview (Socratic) **MUST** run regardless of the parsed `mode` value (`auto` or `manual`, including when `mode=` is omitted and defaults to `auto`). The same independence rule applies to the new canonical `chain` argument introduced in vX.Y.0 — Phase 2 MUST run regardless of the parsed `chain` value (`on` or `off`, including when `chain=` is omitted and defaults to `on` ≡ legacy `mode=auto`). The `mode` argument **MUST NOT** be interpreted as a signal to skip, shorten, or bypass Phase 2 — it has **no effect whatsoever** on Phase 2's execution. The same MUST-NOT applies to the new `chain` argument: it is independence-protected from Phase 2 alongside `mode`, and has no effect whatsoever on Phase 2's execution. Any non-interactive wording elsewhere in this skill (e.g. the Finalization Phase Step 2 chain-confirmation context gated on `mode=auto` ≡ `chain=on`) is scoped to that specific step and **MUST NOT** be generalized to Phase 2. The **ONLY** condition under which Phase 2 is skipped is the existing **"Non-interactive environment fallback"** below (triggered strictly by `AskUserQuestion` itself being unavailable or returning an error, e.g. `claude -p` / CI automation without a TTY) — **not** by the value of `mode` or `chain`. This guard is scheduled for removal in a future major (deferred from v9.0.0) alongside the `mode=` alias: `chain={on,off}` does not lexically suggest interview-policy, so the defensive prose becomes unnecessary once the alias is gone and Phase 2 independence can be left implicit.

**Caps (load-bearing for contract)**:
- At most **3 questions per round** (single `AskUserQuestion` call holds up to 3 items).
- At most **10 rounds** total.
- Therefore at most **30 questions total** across the entire interview before `brief.md` is written.
- Track a round counter starting at `0`. Increment **after** each user response is received (a round is counted only when the user actually responded — i.e., Phase 2 truly ran at least once).

#### args-aware shrinkage (suppress re-asking what `$ARGUMENTS` already answers)

Before issuing any `AskUserQuestion` call in Phase 2, perform a one-shot scan of `$ARGUMENTS` (the original `<what-to-build>` description, with the parsed `chain=` and `mode=` tokens already removed) against the seven interview categories listed in `references/interview-templates.md`. For each candidate question, classify it as either:

- `args-resolved` — the answer is already stated or unambiguously implied by `$ARGUMENTS`. Examples: `$ARGUMENTS` contains "Next.js 14 App Router" → "Which framework?" is `args-resolved`. `$ARGUMENTS` contains "must support 10k req/s" → "What throughput target?" is `args-resolved`. `$ARGUMENTS` contains "rollback via feature flag, no DB migration" → "How critical is this feature — can it be rolled back easily?" is `args-resolved`.
- `needs-question` — the answer is not stated in `$ARGUMENTS` AND not derivable from the researcher's findings.

Construction rule for every `AskUserQuestion` call in Phase 2:

1. A single call MUST carry at most 3 items (existing cap; unchanged).
2. Items MUST be drawn only from the `needs-question` set. `args-resolved` candidates MUST NOT appear in any `AskUserQuestion` payload, including paraphrased or "to confirm" variants.
3. If fewer than 3 `needs-question` items remain in the highest-priority category, fill the remaining slots from the next-highest-priority category that still has `needs-question` items. Do NOT pad with `args-resolved` items.
4. If zero `needs-question` items remain across all seven categories, end Phase 2 (convergence — record `interview_complete: true` and the actual round count). This is an additional convergence trigger on top of the existing five (user says "sufficient", all 7 categories covered, 10 rounds reached, etc.).
5. The shrinkage decision MUST be applied on every round, not only on round 1 — newly arrived user answers can convert `needs-question` items to `args-resolved` mid-interview.

Output a single line at the top of the round-1 console trace listing the `args-resolved` categories so the user can audit the suppression decision: `[args-aware shrinkage] args-resolved categories: <list>; needs-question categories: <list>`. The line is informational; do NOT block on it. The shrinkage decision MUST NOT widen the round / question caps stated above (it can only shorten the interview, never lengthen it).

Confidence rule: when classification is ambiguous (the description partially answers a question), default to `needs-question`. This bias keeps Phase 2's quality-first design intact: when in doubt, ask.

#### Dynamic Phase 2 shrinkage (one-shot read of `runtime_metrics:`)

At Phase 2 start, perform a **single one-shot read** of `.simple-workflow/backlog/briefs/active/{slug}/autopilot-state.yaml` and tier-classify on `remaining_pct = 1 - ((input_tokens + cache_read_input_tokens) / context_window_size)`. The tier table maps the four bands (`≥ 70%`, `50-70%`, `30-50%`, `< 30%`) to round/question caps and the **standalone fallback (state-file-absent)** restores the 10 rounds × 3 questions ceiling. Full formula, table, and caveats: see [phase2-dynamic-shrinkage](references/phase2-dynamic-shrinkage.md).

Once the tier is selected at Phase 2 start, the round counter and questions/round caps are fixed for the remainder of the interview. The Caps stated above remain the **upper bound** — the dynamic table never raises them, only lowers them inside an autopilot run.

**Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), skip Phase 2 entirely and proceed directly to Phase 3 with the researcher's findings only. In this case, set `interview_complete: false` for the frontmatter (Phase 3) and do NOT count any rounds. Note "Phase 2 skipped (non-interactive mode)" in the final summary. Do NOT hang waiting for input.

For each round (up to the active tier cap, at most 3 questions per round, at most 30 questions total):

1. From the researcher's findings and prior answers, pick the most important unanswered questions from the interview templates (see Pre-computed Context).
2. Select **up to 3** questions from the template categories most relevant and not yet answered. Adapt to the specific context; do not ask generic template questions verbatim. A single `AskUserQuestion` call MUST carry at most 3 items.
3. Use `AskUserQuestion` to ask the selected questions.
4. After receiving answers, output a brief "Current understanding" summary (what is known, what categories still need information).
5. **Convergence check** — stop if ANY: user responds "sufficient"/"enough"/similar; all 7 categories (`references/interview-templates.md`) covered; **10 rounds have been completed** (hard ceiling; with the 3/round cap, enforces the 30-questions ceiling); all `needs-question` items exhausted (see `#### args-aware shrinkage` above — zero `needs-question` items remaining across all seven categories triggers convergence even before the round cap).
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
chain: {on|off}
mode: {auto|manual}
estimated_size: {S|M|L|XL}
estimated_category: {category}
interview_complete: {true|false}
---
```

- `chain` (canonical, vX.Y.0+) is the literal scalar (`on` or `off`) derived from the parsed argument in the Argument Parsing step (`chain=on|off` if supplied; otherwise mapped from the deprecated `mode=auto|manual` alias as `auto → on`, `manual → off`; otherwise the default `on`). Sample frontmatter MUST include this `chain: (on|off)` line.
- `mode` (legacy, retained through the deprecation period — slated for removal in a future major, deferred from v9.0.0) is the literal scalar (`auto` or `manual`) parsed from `$ARGUMENTS` in the Argument Parsing step (defaulting to `auto` when both `chain=` and `mode=` are omitted; equivalent to the derived `chain` value via `on ↔ auto` / `off ↔ manual`). During this deprecation window both keys are written to every new brief so legacy `/create-ticket` consumers that have not yet adopted the `chain:` reader keep working unchanged. It is REQUIRED in v6.0.0+ (carried forward as `mode: {auto|manual}` per the deprecation alias contract). Super-legacy briefs written before v6.0.0 may lack this key entirely; downstream readers (notably `/create-ticket brief=<path>`) follow the precedence rule **`chain:` precedes `mode:`** — `chain:` is read first if present, otherwise `mode:` is read for backward compatibility, otherwise the reader defaults to `chain=on` (≡ `mode: auto`).
- `interview_complete` is the literal scalar recorded at the end of Phase 2 (`true` if at least one round ran to a user response; `false` if Phase 2 was skipped via the non-interactive fallback or no round produced a response).
- **Do NOT emit `split:`** (obsolete — decomposition is `/create-ticket`'s job).
- **Do NOT emit `ticket_count:`** (obsolete — decomposition is `/create-ticket`'s job).

**Body schema**: render the canonical sections (Vision / Business Context / Technical Requirements / Scope with In Scope / Out of Scope / Edge Cases / Constraints / Quality Expectations / researcher summary) per [brief-body-template](references/brief-body-template.md). Synthesize the Phase 1 researcher's findings into the final body section so the brief stands alone for downstream skills.

## Phase 4: Policy Generation

1. Read `.simple-workflow/kb/index.yaml`, filter the `autopilot` section (historical decision patterns produced by `/tune` analysis), and apply confidence-based 3-tier judgment per gate (`>= 0.7` → annotate with `# kb-suggested`; `0.5-0.7` → `# [low confidence]`; `< 0.5` → conservative default). Apply size-scoped pattern priority before falling back to `scope=general`. Full integration logic: see [kb-policy-integration](references/kb-policy-integration.md).
2. Determine default policy values based on the user's risk tolerance answers from Phase 2 (maps to conservative/moderate/aggressive). If Phase 2 was skipped (`interview_complete: false`), default to **conservative** and emit default gates.
3. Write to `.simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml` regardless of Phase 2 outcome **and regardless of the parsed `chain` value** (or the legacy `mode` value, while the alias is accepted; the top-level `gates:` line MUST be present). Even in `chain=off` (legacy `mode=manual`), the brief-level `autopilot-policy.yaml` is written as a **rescue path**: per-ticket propagation is suppressed by `/create-ticket` (so manual-mode tickets work like bare-mode tickets via `/impl`'s FIFO selector), but the brief-level policy file remains so a user can later opt into autopilot by **first re-running `/create-ticket` with the brief set to `chain: on`** (which propagates `autopilot-policy.yaml` to each ticket dir) and then running `/autopilot {slug}`, exactly as Step 3 instructs. Running `/autopilot {slug}` directly on a manual (`chain: off`) brief stops with a re-propagation directive — the autopilot brief-level policy fallback was retired (`skills/autopilot/SKILL.md` Phase 1).

The emitted YAML follows the template in [policy-template](references/policy-template.md) (version 1 / risk_tolerance / gates / constraints, with conservative/moderate/aggressive branches inlined as comments).

Split judgement has been removed: `/brief` no longer analyzes `estimated_size` to produce `split-plan.md`, and the legacy `planner` Split Judgment was retired in v6.2.0. `/create-ticket brief=<path>` receives the brief and decomposes the scope via `findings=<path>` mode + `decomposer`.

## Finalization: Output, `chain=on` handoff, and SW-CHECKPOINT

Final phase of `/brief`: summary print, `chain=on` chained skill invocations (Step 2 — also reached via the deprecated `mode=auto` alias), `chain=off` no-chain guidance (Step 3 — also reached via the deprecated `mode=manual` alias), mandatory SW-CHECKPOINT (Step 4). **No further file writes occur after this phase**.

### Step 1 — Summary

Print:
- Brief file path: `.simple-workflow/backlog/briefs/active/{slug}/brief.md`
- Policy file path: `.simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml`
- Estimated size and category
- Interview outcome (`interview_complete: true|false`); if true, number of rounds actually completed

### Step 2 — `chain=on` handoff

Only runs when chain=on (equivalent to the deprecated `mode=auto`). (`chain=on` was passed explicitly, OR the legacy alias `mode=auto` was passed and mapped to `chain=on`, OR both `chain=` and `mode=` were omitted so the default `chain=on` was applied. When the parsed `chain` is `off` — equivalent to the deprecated `mode=manual` — this entire Step 2 is skipped and execution proceeds directly to Step 3. The earlier convention "Only runs when mode=auto" remains semantically true during the deprecation window because `mode=auto` is just an alias for `chain=on`.) Within **Step 2's chain-confirmation context**, the flow is strictly linear (display → status update → auto-kick write → `/create-ticket` → `/autopilot`): Step 2 **MUST NOT** call `AskUserQuestion`, nor otherwise prompt the user for a yes/no confirmation, to gate the chain between these sub-steps. The brief + policy display in (a) is passive — it does not gate the chain.

**Scope disclaimer (Step 2-only)**: The non-interactive restriction above is **scoped exclusively to Step 2's chain confirmation** (only reachable when `chain=on` / legacy `mode=auto`) and **MUST NOT** be generalized to the rest of `/brief`. In particular, **Phase 2 Structured Interview (Socratic) is independent of this restriction and MUST run regardless of the parsed `chain` value (or the legacy `mode` value)** — neither `chain` nor `mode` has any effect on Phase 2's behavior (see `## Phase 2` above).

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

   **MUST invoke `/autopilot` via the Skill tool** with argument `{slug}` (the brief's slug, which is also the `parent-slug` that `/create-ticket` wrote under `.simple-workflow/backlog/product_backlog/{slug}/`). **ultracode forwarding (additive)**: if `resolved_uc` (from Argument Parsing) is not `off`, append the resolved `uc` token to this invocation — i.e. invoke `/autopilot {slug} uc={resolved_uc}` (where `{resolved_uc}` is `on` or `metric-only`). When `resolved_uc` is `off` (the default, or downgraded by the `chain=off` warning above), the invocation stays exactly `/autopilot {slug}` with no `uc` token — so the default chained run is byte-identical to prior behavior. The chained `/autopilot` records `uc` as run-scoped state and propagates it to each per-ticket `/impl`; do NOT add `uc` to the `/create-ticket` invocation in sub-step (d) (`/create-ticket` does not start autopilot, so it is out of scope for `uc`). **parallel forwarding (additive, composes with `uc`)**: independently, if `resolved_parallel` (from Argument Parsing) is not `off`, append `parallel={resolved_parallel}` to the SAME invocation — so a run with both set invokes `/autopilot {slug} uc={resolved_uc} parallel={resolved_parallel}`. When `resolved_parallel` is `off` (the default, or downgraded by the `chain=off` warning), no `parallel=` token is appended, so the default chained run stays byte-identical. Exactly like `uc`, `parallel` is NOT added to the `/create-ticket` invocation in sub-step (d) (`/create-ticket` does not start autopilot).

### Step 3 — `chain=off` (≡ legacy `mode=manual`; no chained handoff)

> Legacy-alias heading kept inline for backward search compatibility: this section is also reachable as **Step 3 — `mode=manual`** while the `mode=` alias remains accepted (slated for removal in a future major, deferred from v9.0.0, alongside the alias).



Only runs when the parsed `chain` is `off` (equivalently, the deprecated alias `mode=manual` was supplied). No `auto-kick.yaml` is written, no `/create-ticket` invocation, no `/autopilot` invocation — `/brief` produces the two artifacts (`brief.md` with both `chain: off` and `mode: manual` in frontmatter during the deprecation window, plus `autopilot-policy.yaml` as the rescue path file from Phase 4) and stops. Print the manual-flow guidance below verbatim:

```
Brief generated in manual mode. To proceed:
1. Review and edit the brief if needed
2. Update status to 'confirmed' in brief.md frontmatter
3. Run /create-ticket brief=.simple-workflow/backlog/briefs/active/{slug}/brief.md to produce the ticket(s).
   Tickets will NOT receive autopilot-policy.yaml (manual mode).
4. Per ticket: /scout → /impl → /ship (standard manual flow)

If you later decide to switch to autopilot, first re-run /create-ticket with the brief
set to chain: on so each ticket dir receives autopilot-policy.yaml, then run:
  /autopilot {slug}
Running /autopilot directly on a manual (chain: off) brief stops with a re-propagation
directive — per-ticket autopilot-policy.yaml is only propagated when the brief is chain: on.
The brief-level autopilot-policy.yaml is preserved at .simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml.
```

### Step 4 — Emit the final `## [SW-CHECKPOINT]` block

The block MUST be the LAST section of the skill's output. Format + the literal `context_advice` sentence are defined **once** in `skills/create-ticket/references/sw-checkpoint-template.md`; emit the block verbatim per that template (do NOT retype the `context_advice:` sentence).

Fields:
- `phase: brief`
- `ticket: none`
- **Success path** (`brief.md` + `autopilot-policy.yaml` both written) — branch on the parsed `chain` (equivalently on the legacy `mode` alias while it is accepted):
  - `artifacts:` — list containing the two repo-relative paths: `.simple-workflow/backlog/briefs/active/{slug}/brief.md` and `.simple-workflow/backlog/briefs/active/{slug}/autopilot-policy.yaml`.
  - **`chain=on`** (≡ legacy `mode=auto`):
    - Emit EXACTLY ONE line matching `^next_recommended_auto:[[:space:]]+/autopilot[[:space:]]+\S+$` with value `/autopilot {slug}`.
    - Emit EXACTLY ONE line matching `^next_recommended_manual:[[:space:]]+/create-ticket[[:space:]]+brief=\S+$` with value `/create-ticket brief=.simple-workflow/backlog/briefs/active/{slug}/brief.md`.
  - **`chain=off`** (≡ legacy `mode=manual`):
    - Emit `next_recommended_auto: ""` (literal empty string). This empty value does NOT match the AC #11 regex `^next_recommended_auto:[[:space:]]+/autopilot[[:space:]]+\S+$`, so the Stop hook's auto-`/autopilot` firing path does NOT trigger — load-bearing safety guarantee of `chain=off` (legacy `mode=manual`).
    - Emit EXACTLY ONE line matching `^next_recommended_manual:[[:space:]]+/create-ticket[[:space:]]+brief=\S+$` with value `/create-ticket brief=.simple-workflow/backlog/briefs/active/{slug}/brief.md`.
  - Do NOT emit a bare `next_recommended:` line alongside these two.
  - `{slug}` is the brief's `{slug}` (= `parent-slug` downstream; aliases here).
- **Failure path** (any write failure — `mkdir`, `brief.md`, `autopilot-policy.yaml`, or `chain=on` / legacy `mode=auto` chained `/create-ticket` failed):
  - `artifacts: []` on a single line.
  - Emit BOTH recommendation lines with empty-string values: `next_recommended_auto: ""` AND `next_recommended_manual: ""`. AC #11's regex does not match empty-string values, so downstream automation does not misfire. Both keys remain present (shape-preserving).

In all three shapes (`chain=on` success ≡ legacy `mode=auto` success, `chain=off` success ≡ legacy `mode=manual` success, failure), both `next_recommended_auto:` and `next_recommended_manual:` keys are present; only their values differ.

## Error Handling

- **Empty arguments**: Print `Usage: /brief <what-to-build> [chain=on|off]` (legacy alias also accepted during the deprecation window: `mode=auto|manual`) and stop.
- **`auto=true` argument (v6.0.0 removal)**: Print `ERROR: 'auto=true' has been removed in v6.0.0; use 'mode=auto' or 'mode=manual'` (legacy literal preserved verbatim; the equivalent vX.Y.0+ form is `chain=on` or `chain=off`) and stop. Do NOT create the brief directory, do NOT write `brief.md`, do NOT write `autopilot-policy.yaml`, and do NOT write `auto-kick.yaml`. Exit non-zero.
- **Invalid `chain=<value>` (vX.Y.0+ canonical form)**: Print `ERROR: invalid chain=<value>. Use chain=on or chain=off` (substituting the offending value) and stop. Do NOT create the brief directory, do NOT write `brief.md`, do NOT write `autopilot-policy.yaml`, and do NOT write `auto-kick.yaml`. Exit non-zero.
- **Invalid `mode=<value>` (legacy alias path)**: Print `ERROR: invalid mode=<value>. Use mode=auto or mode=manual` (substituting the offending value) and stop. Do NOT create the brief directory, do NOT write `brief.md`, do NOT write `autopilot-policy.yaml`, and do NOT write `auto-kick.yaml`. Exit non-zero. (The deprecation warning for `mode=` itself is emitted only when the alias is *valid*; invalid `mode=` values short-circuit to this error without the warning.)
- **Deprecated `mode=` alias supplied (warning, not an error)**: When `mode=` is parsed with a valid value (`auto` or `manual`) and `chain=` is NOT also supplied, emit to stderr the single line `WARNING: 'mode=' is deprecated and will be removed in a future major version. Use 'chain=on' instead of 'mode=auto', 'chain=off' instead of 'mode=manual'.` (verbatim literal). Processing continues — the alias is mapped to the equivalent `chain=` value and the brief is written normally.
- **Simultaneous `chain=` and `mode=` specification (ERROR, exit non-zero)**: Print `ERROR: 'chain=' and 'mode=' cannot be combined. Use 'chain=' (preferred).` and stop. Do NOT silent-rewrite to either key. Do NOT create the brief directory, do NOT write `brief.md`, do NOT write `autopilot-policy.yaml`, and do NOT write `auto-kick.yaml`. Exit non-zero.
- **Researcher failure**: Report error. Continue to Phase 2 without investigation summary.
- **AskUserQuestion failure in Phase 2**: Skip Phase 2, proceed with researcher findings only; set `interview_complete: false`.
- **Write failure** (brief.md or autopilot-policy.yaml): Report the error and emit the failure-path SW-CHECKPOINT from Step 4 (empty-string recommendations, `artifacts: []`).
- **`chain=on` path (≡ legacy `mode=auto`) — `/create-ticket` chained invocation fails**: stdout MUST contain `ERROR:` AND `create-ticket failed`. Do NOT invoke `/autopilot`. Emit the failure-path SW-CHECKPOINT from Step 4.

## Subagent Skill-Access Handoff

When you spawn a subagent via the Agent tool, consult the `Available user skills:` line in the Pre-computed Context above. If a listed utility skill is relevant to that subagent's task, name it in the Agent prompt and instruct the subagent to use it via the Skill tool when it materially helps.

- **Truly hermetic agents** (`security-scanner`, `ticket-evaluator`) carry no Skill tool, no MCP, no `Bash(*)`. If you spawn one, hand off nothing — speculative references only add noise.
- **Skill-bearing verdict / read-only agents** (`ac-evaluator`, `code-reviewer`, `decomposer`, `tune-analyzer`) retain explicit `tools:` allowlists and do NOT inherit MCP / `Bash(*)`. They DO carry the Skill tool and receive capability handoffs, but only via **deterministic per-AC binding** (the `## Bound capabilities (per AC)` block extracted from `{ticket-dir}/ticket.md`'s `### Capabilities` section) — never via ad-hoc speculation from the `Available user skills:` probe.
- **Productive agents** (`implementer`, `planner`, `researcher`, `test-writer`) inherit-all under v8.0.0 — every parent-session MCP server and `Bash(*)` is in their tool inventory. Only `mcp__*` and Skills bound to an active AC via `## Bound capabilities (per AC)` may be invoked (per the agent body's `## Bound Capabilities (Handoff from Orchestrator)` section).
- Never present a pipeline skill (`/scout`, `/impl`, `/audit`, `/ship`, `/autopilot`, `/brief`, `/catchup`, `/create-ticket`, `/investigate`, `/plan2doc`, `/refactor`, `/test`, `/tune`) as a utility for a subagent.
- When a ticket's `### Capabilities` section exists (resolve via `{ticket-dir}/ticket.md` or the autopilot state file's `paths.ticket`), `Read` it before constructing any subagent spawn prompt and inline the bound capabilities verbatim into every spawn prompt under the heading `## Bound capabilities (per AC)`. For per-AC spawns (one spawn per AC, e.g. `/impl` Steps 13/15), include only the rows whose `Bound AC(s)` column lists the active AC. For tip / whole-deliverable spawns (the rest), include the full table. The upstream binding is authoritative — do NOT re-derive relevance from the AC text or re-scan `Available user skills:` for plausible matches. When the ticket lacks `### Capabilities` (older ticket pre-dating Gate 6), emit `## Bound capabilities (per AC): (none recorded — ticket pre-dates Gate 6)` in the spawn prompt and let the subagent fall back to its in-house capability-selection path.
- If the `Available user skills:` probe reports `(none)`, hand off nothing and let the subagent proceed with its in-house capabilities.
