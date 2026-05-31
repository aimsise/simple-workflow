---
name: impl
description: >-
  Do not auto-invoke. Only invoke when called by name. Implements the latest plan via Generator -> AC Evaluator -> Code Quality Reviewer loop. Use when (1) /scout or /plan2doc produced a plan and user calls `/impl`, (2) /autopilot delegates the per-ticket impl step, or (3) an explicit plan path is passed. Triggers on "/impl", "implement the plan", "generator-evaluator loop".
disable-model-invocation: false
allowed-tools:
  - Agent
  - AskUserQuestion
  - Skill
  - Read
  - Write
  - Edit
  - Glob
  - "Bash(git diff:*)"
  - "Bash(git status:*)"
  - "Bash(git log:*)"
  - "Bash(git branch:*)"
  - "Bash(git stash:*)"
  - "Bash(date:*)"
  - "Bash(rm:*)"
argument-hint: "[rounds=N] [plan file path or additional instructions]"
---

Implement the latest plan via Generator → AC Evaluator → Code Quality Reviewer.
User arguments: $ARGUMENTS

## Mandatory Skill Invocations

`/impl` orchestrates Generator → Evaluator → /audit with strict firewalls; writes no code, renders no AC verdict.

| Invocation Target | When | Skip consequence |
|---|---|---|
| `implementer` agent (Agent tool, "Generator") | step 13 | missing trace |
| `ac-evaluator` agent (Agent tool, Dry Run) | step 8 (round 1, L/XL) | no rubric |
| `ac-evaluator` agent (Agent tool, main gate) | step 15 | missing `eval-round-{n}.md` → `[PIPELINE] impl: ARTIFACT-MISSING` |
| `/audit` (Skill tool) | step 17 (PASS/PASS-WITH-CAVEATS) | missing report → `[PIPELINE] impl: ARTIFACT-MISSING` |

**Binding rules**:
- `MUST invoke simple-workflow:implementer via the Agent tool`; `MUST invoke simple-workflow:ac-evaluator via the Agent tool`; `MUST invoke /audit via the Skill tool`.
- `NEVER bypass via direct file operations` — writing `eval-round-{n}.md` / `quality-round-{n}.md` / `audit-round-{n}.md` from `/impl` violates the contract.
- `Fail the task immediately on any missing invocation` — set `phases.impl.status: failed` + `overall_status: failed`.
- `ac-evaluator is contractually idempotent on persistence` (`agents/ac-evaluator.md`); first call writes and returns non-empty Output. NEVER re-invoke to persist.

## phase-state.yaml write ownership

Writes ONLY `phases.impl` + top-level `current_phase` / `last_completed_phase` / `overall_status`. Legacy `impl-state.yaml` retired. Start-time: legacy → migrate; neither + plan.md → bootstrap. See [state-file-resolution.md](references/state-file-resolution.md). Never deleted. Schema: `skills/create-ticket/references/phase-state-schema.md`.

## Pre-computed Context

Current state:
!`git status --short`

Available user skills: !`( ls -1 ~/.claude/skills 2>/dev/null ; ls -1 .claude/skills 2>/dev/null ) | sort -u | grep . | tr "\n" "," | sed "s/,$//" | grep . || echo "(none)"`

Available MCP servers: !`( jq -r '.mcpServers // {} | keys[]' .mcp.json 2>/dev/null ; jq -r '.mcpServers // {} | keys[]' ~/.claude.json 2>/dev/null ) | sort -u | grep . | tr "\n" "," | sed "s/,$//" | grep . || echo "(none)"`

## Phase 1: Plan Loading & Size Detection

1. Parse `$ARGUMENTS`:

   **1a. Round-cap argument extraction** (before plan-path detection): find `rounds=N` (case-insensitive, first wins); validate `N` as positive integer (6-digit hard cap). **Soft cap 24** — `arg_rounds > 24` emits `[ARG-WARN]` without clamping (soft cap 24 is advisory). Strip first recognized token. **Precedence** (→ `phases.impl.max_rounds`): `rounds=N` argument > `{ticket-dir}/autopilot-policy.yaml` `constraints.max_total_rounds` > **Else default 9**; then add the verification-depth bonus (`+0`/`+3`/`+6` for tier `standard`/`thorough`/`exhaustive`) UNLESS a valid `rounds=N` was supplied OR `constraints.verification_depth: off`. This argument-extraction step only parses/strips `rounds=N`; the bonus is **applied later**, when `max_rounds` is materialised at the Phase 2 init block (after the Step 3a tier is known) — see [verification-depth.md](references/verification-depth.md). See [round-cap-parser.md](references/round-cap-parser.md) for regex/validation/hard-cap/strip/precedence/stderr/quoted-strings.

   **1b. Plan-path detection** (operates on the post-strip `$ARGUMENTS`):
   - Starts with `.simple-workflow/backlog/active/` or `.simple-workflow/docs/plans/` → use as plan path.
   - Else auto-select from `.simple-workflow/backlog/active/`: list dirs with `plan.md`; **Exclude** dirs containing `autopilot-policy.yaml`; sort ascending by directory name (FIFO, lowest ticket number first); pick first. Fallback: latest `.simple-workflow/docs/plans/*.md`.
   - No plan → "No plan found in .simple-workflow/backlog/active/ or .simple-workflow/docs/plans/. Run /scout or /plan2doc first." and stop.
   - Only autopilot-managed tickets → "All active tickets are managed by /autopilot. To implement manually, specify the plan path explicitly: /impl .simple-workflow/backlog/active/{ticket-dir}/plan.md" and fall back to `.simple-workflow/docs/plans/*.md`.

2. Confirm plan exists (Glob or `Read(limit=5)`); do NOT read in full.

3. Size detection: ticket → `Read(ticket.md, limit=30)` for `| Size |` (fallback `limit=80`; default `M`). `.simple-workflow/docs/plans/` → default `M`.

3a. **Verification depth tier** (v8.1.0+): read `constraints.verification_depth` from `{ticket-dir}/autopilot-policy.yaml` (absent file or field → `auto`). Resolve `VERIFICATION_DEPTH`: `off` → feature disabled (no round-cap bonus, single evaluator at Step 15, no `depth=` to `/audit` at Step 17); `standard`/`thorough`/`exhaustive` → forced literal; `auto` → derive from `Size` (Step 3) × `risk_tolerance` (from the same policy; absent/unreadable → `conservative`) per the matrix in [verification-depth.md](references/verification-depth.md). Carry `VERIFICATION_DEPTH` to the Phase 2 init round-cap computation (where the `+0`/`+3`/`+6` bonus is applied to the Step 1a base), Step 15 (evaluator-mode dispatch), and Step 17 (`/audit` `depth=` handoff). Emit `[VERIFICATION-DEPTH] tier={VERIFICATION_DEPTH} source={auto|policy|off} size={S|M|L|XL} risk={conservative|moderate|aggressive}` to stderr. For S/M at conservative/moderate this resolves to `standard` and the whole feature is a no-op (byte-identical to pre-v8.1.0).

4. **Worktree recommendation** (L/XL): non-blocking tip `git worktree add -b impl/{slug} ../impl-{slug}` (`{slug}` = dir minus `NNN-`).

5. **Locate AC section** — bounded: `Grep -n "^### Acceptance Criteria" <plan-path>` (fallbacks `^## Acceptance Criteria` / `^#### Acceptance Criteria`). At line `L`, `Read(<plan-path>, offset=L, limit=200)` (200-line cap); terminate at first `^#{1,6} ` AFTER header (or EOF). If window exhausted without terminator, emit `"AC section exceeds 200 lines; using the first 200 lines"`. Keep for Generator (§13 b) and Evaluator (§8, §15 b).

6. No header → "ERROR: Plan has no Acceptance Criteria. Add an '### Acceptance Criteria' section to the plan before running /impl." and stop.

7. **AC Sanity Check** (round 1, M/L/XL only): Generator prompt "Before implementing, review each AC. If any is ambiguous or infeasible, flag it in your **Next Steps** field." If flagged, stop.

8. **Evaluator Dry Run** (round 1, **L/XL only**): **MUST invoke `simple-workflow:ac-evaluator` via the Agent tool** with a planning prompt (HOW each AC verified; no code yet). **NEVER bypass** by self-drafting. Include plan path + AC + "AC above is the fixed rubric — do not re-derive". Failure: read `gates.evaluator_dry_run_fail.action` — `proceed_without` → proceed (`[AUTOPILOT-POLICY] gate=evaluator_dry_run_fail action=proceed_without`); `stop` → stop. Else `AskUserQuestion` yes/no with `header: eval-dry` (Non-interactive default `no`); the `header` value is load-bearing under the autopilot 3-tier `risk_tolerance` matrix (see `skills/autopilot/SKILL.md` `## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)`), so any other header (or an empty one) is denied at every tier when invoked under `/autopilot`. Success → save plan for Generator (step 13g).

9. If related investigation exists (same-dir `investigation.md` or latest `.simple-workflow/docs/research/`), pass path to Generator field c.

10. If working tree has uncommitted changes unrelated to the plan, warn.

11. **State file resolution, migration, bootstrap**. Dispatch on state-file presence + `phases.impl.status`. Sets `impl_resume_mode`.
    - §11-completed/§11-failed: early-exit gates.
    - §11a.0 Both files exist — Sub-case A (already complete, skip to §11c) / Sub-case B (partial, re-populate).
    - §11a.1 Clean legacy migration: **Read `impl-state.yaml`**, write `phase-state.yaml`; `mv impl-state.yaml impl-state.yaml.migrated-{YYYYMMDD}.bak` (NEVER `rm`); preserve unknown keys via `legacy_extras`.
    - §11b Bootstrap. §11c Resume dispatch. §11d Fresh-start (post-`/scout`).
    See [state-file-resolution.md](references/state-file-resolution.md) for all dispatch sub-cases.

12. **Safety checkpoint**: `git stash push -m "impl-checkpoint" --include-untracked -- ':!.simple-workflow'`. Print "Safety checkpoint created. To rollback: git stash pop". Skip if empty.

## Phase 2: Generator → AC Evaluator → Code Quality Reviewer Loop (max N rounds, default 9)

Round-limit precedence per Step 1a. Stop hook (`hooks/impl-checkpoint-guard.sh`) guards the post-`/audit` handoff — Stop (not PreToolUse) because the failure mode is *omission* (turn ending after `/audit`'s structured block but before Step 18 → Phase 3 → `## [SW-CHECKPOINT]`); only a turn-termination hook detects a tool call that never happens.

### phase-state.yaml phases.impl state management

Intra-impl state lives under `phases.impl.*` in `{ticket-dir}/phase-state.yaml`. Initialise before the loop (`status: in-progress`, `phase_sub: generator-pending`, `next_action: start-round-1-generator`, `current_round: 1`, `max_rounds` (materialise here as the Step 1a base + the Step 3a depth bonus, unless `rounds=N` was supplied or `verification_depth: off`), `verification_depth: {VERIFICATION_DEPTH resolved in Step 3a}`). Per-step updates touch only `phases.impl.*`. Non-ticket flow: no-op. See [phase-state-impl-management.md](references/phase-state-impl-management.md) for init YAML, value lists, per-Step rules.

13. **MUST invoke the Generator (`simple-workflow:implementer`) agent via the Agent tool**. **NEVER bypass the Generator** via `Edit`/`Write` from `/impl` — firewall requires zero orchestrator code changes. Fail immediately if not invocable.
    - **Deterministic capability handoff (per-AC)**: Before constructing the prompt, `Read` `{ticket-dir}/ticket.md` (or the resolved ticket path; skip when no ticket pairs the plan, e.g. `.simple-workflow/docs/plans/`). Extract the `### Capabilities` table. For each AC in the rubric, look up the rows whose `Bound AC(s)` column lists that AC; the union of `Name` values across those rows is the **bound capability list** for that AC. Inline the per-AC bound capabilities into the spawn prompt under a heading such as `## Bound capabilities (per AC)` — this serialises the upstream-recorded mapping verbatim so the implementer does not re-derive relevance and the downstream `ac-evaluator` (Step 15) sees the same list. When the ticket has no `### Capabilities` section (older ticket), fall back to the present ad-hoc path: do NOT fabricate bindings; emit `## Bound capabilities (per AC): (none recorded — ticket pre-dates Gate 6)` and proceed.
    - **Advisory capability handoff (per-ticket, v8.0.0+)**: Also extract the `### Advisory Capabilities` table from the same `ticket.md` (if present per the Gate 6.5 contract in `skills/create-ticket/references/ac-quality-criteria.md`). The Advisory table lists capabilities — utility skills (e.g. `ui-ux-pro-max` for UI/UX heuristics), MCP servers (e.g. `mcp__context7__query-docs` for library docs) — that are NOT bound to any AC but that the planner has classified as useful authoring references for the productive subagent. Inline the Advisory table into the spawn prompt under the heading `## Advisory capabilities (per ticket)` **with an additional `How to load` column appended at the right of each row**. The `How to load` value is generated mechanically from the row's `Type` column (no skill-name or server-name branching — see `agents/implementer.md` `### How to invoke each Advisory entry`):
      - `Type = skill` → `` `Skill` tool with `skill=<Name>` `` (the `<Name>` is substituted verbatim from the row's `Name` column).
      - `Type = MCP` → `` `ToolSearch query="select:<Name>" max_results=1`, then invoke `<Name>` directly `` (the `<Name>` is the full `mcp__<server>__<tool>` slug, substituted verbatim from the row's `Name` column).

      The column exists because plugin subagents see `mcp__*` (and some Skills) as **deferred tools** — names visible, schemas unloaded — so direct invocation raises `InputValidationError` until `ToolSearch` fetches the schema. By generating `How to load` from the `Type` column at orchestrator time, user-added MCP servers (mounted via the user's `.mcp.json` or `~/.claude.json`) and user-installed Skills (under `~/.claude/skills/` or `.claude/skills/`) are handled identically to anything shipped by the plugin without any per-skill code change. The implementer's `## Side-effect ban` carries an explicit advisory-invocation exception for entries on this list. When the ticket has no `### Advisory Capabilities` section (older ticket or empty by Gate 6.5 design), emit `## Advisory capabilities (per ticket): (none)` and proceed. The Advisory table is for productive subagents only — do NOT inline it into `ac-evaluator` spawn prompts at Step 15 (Advisory ≠ verification).
    - `subagent_type: simple-workflow:implementer`; description "Implement plan for <feature>". Model per `constraints.sonnet_size_threshold` in `{ticket-dir}/autopilot-policy.yaml` (`S`/`M`/`L`/`off`; default `M`; `off` → opus); see `skills/create-ticket/references/autopilot-policy-reference.md`.
    - Prompt fields a-g: plan path (read full), AC list ("You will be evaluated by an independent evaluator"), investigation, user instructions, round 2+ feedback (`eval-round-{n-1}.md` / `quality-round-{n-1}.md`), CLAUDE.md lint/test ref, round-1 Dry-Run plan.
      h. KB injection: Read `.simple-workflow/kb/index.yaml`; filter `role=implementer` and `confidence >= 0.8`; include up to 20 summary lines under "## Known Project Patterns". If `.simple-workflow/kb/index.yaml` does not exist, skip silently. **AC always wins over KB patterns on conflict.**
      i. Autopilot: if `autopilot-policy.yaml` has `constraints.allow_breaking_changes: false`, include "CONSTRAINT: Do not introduce breaking changes to existing public APIs, interfaces, or exported functions."
      j. **CONSTRAINT — Input immutability** (verbatim): "Do NOT modify `plan.md`, `ticket.md`, or `investigation.md` at any point. These are read-only inputs. Source code changes and new files are fine. If you believe the plan needs revision, flag it in your Next Steps field — the orchestrator will invoke `/plan2doc` separately."
      k. **Return value cap**: Return per the Context Conservation Protocol in `agents/implementer.md` — under 500 tokens (status, changed-files, lint/test summary).

14. **Immediately** update `phase-state.yaml`: `phase_sub: generator-complete`, `next_action: start-evaluator`. Then `git diff --shortstat`. Do NOT run `git diff --stat`.
    **§14a — Plan-Compliance Pre-Check** (warn-only): `Grep -nE "^## Affected [Ff]iles$|^## Critical files to modify$"`. No match → `[PLAN-COMPLIANCE] no Affected-files section in plan; skipped`. Else parse col-1 paths (80 lines / 50 cap), diff against `git diff --name-only HEAD` ∪ `git ls-files --others --exclude-standard`. Missing → `[PLAN-COMPLIANCE-WARN] plan declares "<path>" in Affected files but it is not in git diff (round={n})` per path; field `h` to Step 15. Else `[PLAN-COMPLIANCE] OK`. Read-only.

    **§14b — Advisory Consultation Pre-Check** (gating, v8.0.0+ Phase 6 enforcement): the Generator return value received at Step 13/14 MUST contain a `**Advisory consultation**:` field per the format in `agents/implementer.md` `## Advisory Capabilities` → `### Consultation reporting format`. Match by regex `^\*\*Advisory consultation\*\*:` on the return value. Two outcomes:
    - **Field present** → emit `[ADVISORY-CONSULT] round={n} present` to stderr and proceed to Step 15. Do NOT further parse the field's bullets here — the field is an audit trail, not an AC verdict; downstream verifiers (and the next round's Generator on FAIL) consume it as-is.
    - **Field absent** → contract violation. Emit `[PIPELINE] impl: ADVISORY-MISSING (round={n}, agent=implementer)` to stderr. Update `phase-state.yaml`: `phases.impl.status: failed`, `phases.impl.phase_sub: advisory-missing`, top-level `overall_status: failed`. Stop the round (do NOT advance to Step 15). The orchestrator MUST NOT silently re-prompt the Generator — the missing field is a contract issue, not a content issue, and re-rolling the same Generator without surfacing the failure would mask the regression.

    The §14b check is skipped only when the Step 13 Advisory handoff emitted `## Advisory capabilities (per ticket): (none)` for this round (older ticket, no Advisory block, or empty by Gate 6.5 design); in that path the field's presence is still preferred (Generator should write `**Advisory consultation**: (none)` verbatim) but its absence does not FAIL the round — emit `[ADVISORY-CONSULT] round={n} skipped (no Advisory block)` instead.

    > **CHECKPOINT**: Read `phase-state.yaml`, confirm `next_action: start-evaluator`, proceed to Step 15. Do NOT end your turn.

15. **MUST invoke the AC Evaluator (`simple-workflow:ac-evaluator`) agent via the Agent tool** (always sonnet). **NEVER self-assess AC compliance** — Evaluator reads code via `git diff` and renders PASS/FAIL (Ticket 002 failure mode L554-L559). Fail immediately if not invocable.

   **Deterministic capability handoff (per-AC)**: Before constructing the prompt, `Read` `{ticket-dir}/ticket.md` (or the resolved ticket path) and reuse the per-AC bound-capability list extracted from the `### Capabilities` section in Step 13. Inline that mapping verbatim into the spawn prompt under `## Bound capabilities (per AC)` so the Evaluator picks its evidence-gathering capability from the recorded binding instead of re-deriving relevance from the AC text. When the ticket lacks `### Capabilities` (older ticket), fall back to the present ad-hoc path: emit `## Bound capabilities (per AC): (none recorded — ticket pre-dates Gate 6)` and let `ac-evaluator` proceed on its in-house verification methods. The Evaluator MUST treat the recorded binding as authoritative — when an AC carries a bound capability, code inspection alone is not sufficient evidence to PASS that AC; the Evaluator MUST gather live evidence via the bound Skill (or rewrite the AC as static via the planner's `#### Capability Gaps` rule, which is upstream).

   Count positive ACs (`AC_COUNT`); compute `EVALUATOR_MAX_TURNS = max(60, AC_COUNT * 4)` (field `j`; hard `maxTurns: 200` in frontmatter; e.g. `AC_COUNT = 22` → 88).

   **Evaluator-mode dispatch** (precedence: partition > multi-verifier > single):
   - `AC_COUNT >= 30` → **partition** (takes precedence over multi-verifier even when `VERIFICATION_DEPTH == exhaustive`): split by AC-ID order, invoke twice with `--- partition: <i>/2 ---` headers (field `k`), persist `eval-round-{n}-part-1.md` / `eval-round-{n}-part-2.md`, merge worst-of-2.
   - Else `VERIFICATION_DEPTH == exhaustive` (Step 3a) → **high-assurance multi-verifier**: invoke `simple-workflow:ac-evaluator` three times independently over the SAME rubric and `git diff`, each with a distinct lens directive (field `l`: V1 correctness, V2 adversarial-refute, V3 reproduction-edge), persist `eval-round-{n}-v1.md` / `eval-round-{n}-v2.md` / `eval-round-{n}-v3.md`, and majority-merge per AC (any one CRITICAL → CRITICAL; a non-critical FAIL needs ≥2 verifiers; quorum < 2 valid envelopes → FAIL-CRITICAL). Apply the Step 16 four-way envelope check (incl. single-shot IN_PROGRESS recovery) independently to EACH `-v{i}.md` return; see [ac-gate-decision.md](references/ac-gate-decision.md).
   - Else → single invocation with `eval-round-{n}.md`.
   See [ac-evaluator-orchestration.md](references/ac-evaluator-orchestration.md) for counting, partition, the multi-verifier lenses + majority merge + quorum rule, fields `j`/`k`/`l`, template.

   - Prompt fields (a-d): plan path (read full), AC, `git diff --shortstat` from step 14, "Run `git diff` to inspect changes, run lint/test independently, and verify each AC."
     e. Save path — emit `Save your evaluation report to: {eval-report-path}`. **Orchestrator MUST substitute `{eval-report-path}` (and every `{brace}` placeholder) BEFORE sending; a raw placeholder reintroduces the FU-1 bug.** Resolution: ticket → `.simple-workflow/backlog/active/{ticket-dir}/eval-round-{n}.md`; else strip `NNN-` prefix from active dirs and check if branch contains slug → `.simple-workflow/backlog/active/{full-directory-name}/eval-round-{n}.md`; else `.simple-workflow/docs/eval-round/{topic}-eval-round-{n}.md`. `{n}` = current round.
     f. Append: "The Acceptance Criteria text above is the fixed rubric — do NOT re-derive from the plan. If the plan's AC differs, trust the rubric."
     g. **Return value cap**: Return per the Context Conservation Protocol in `agents/ac-evaluator.md` — under 500 tokens (Status / Output / 3-5 bullets). Full evaluation in `eval-round-{n}.md`.
     h. **Plan-Compliance hint** (only when §14a emitted `[PLAN-COMPLIANCE-WARN]`): name missing paths so Evaluator can mark related AC FAIL if load-bearing.
   - Prompt must NOT include Generator's return value (bias) or a second invocation to persist.
   - Receive return value (PASS / FAIL / FAIL-CRITICAL + feedback).

16. AC Gate:
    - **Output envelope check (precedence over Status parsing) — 4-way** over `(empty / file + IN_PROGRESS / ERROR- / non-empty)`:
      (i) **Empty + no file** → `[CONTRACT-VIOLATION]`, FAIL-CRITICAL, stop. Do NOT re-invoke.
      (ii) **Empty + file with first `## Status: IN_PROGRESS`** → exactly one single-shot recovery invocation per file per round. Recovery prompt MUST tell agent to **Read the IN_PROGRESS file** at `{eval-report-path}` first and **resume from** the first `[ ]` (unchecked) AC; preserve `[x]` verdicts. If recovery yields no terminal verdict → `[CONTRACT-VIOLATION]`, FAIL-CRITICAL, stop.
      (iii) **Output begins with `ERROR-`** → `[CONTRACT-VIOLATION]`, FAIL-CRITICAL, stop.
      (iv) **Non-empty AND not `ERROR-`** → Status parsing.

      See [ac-gate-decision.md](references/ac-gate-decision.md) for IN_PROGRESS recovery prompt, `[CONTRACT-VIOLATION]` strings, Partition × IN_PROGRESS rules, and Multi-verifier × IN_PROGRESS recovery (the four-way check + single-shot recovery applies independently to each `-v{i}.md` return).

    - **FAIL-CRITICAL** → stop. Report CRITICAL.
    - **ac_eval_fail policy**: if `autopilot-policy.yaml` exists, read `gates.ac_eval_fail`: `on_critical: stop` always enforced; `action: retry` → continue (`[AUTOPILOT-POLICY] gate=ac_eval_fail action=retry round={n}`); `action: stop` → stop. If the gate falls through to an `AskUserQuestion` escalation (e.g. unknown action value with a documented interactive fallback), the question MUST set `header: ac-eval` — the `header` value is load-bearing under the autopilot 3-tier `risk_tolerance` matrix (see `skills/autopilot/SKILL.md` `## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)`), so any other header (or an empty one) is denied at every tier when invoked under `/autopilot`.
    - **FAIL** → save Feedback; next round (skip quality review).
    - **PASS-WITH-CAVEATS** → treat as PASS; record Caveats for Phase 3. Continue to step 17.
    - **PASS** (distinct from `/audit`'s `PASS_WITH_CONCERNS`) → step 17.

    Update `phase-state.yaml`: `phase_sub: evaluator-complete`, `last_ac_status: {PASS|FAIL|FAIL-CRITICAL}`, `next_action`: `start-audit` (PASS/PASS-WITH-CAVEATS) / `start-round-{N+1}-generator` (FAIL) / `stop-critical` (FAIL-CRITICAL).

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING** (skip if FAIL-CRITICAL): Read `phase-state.yaml`; execute `phases.impl.next_action` (`start-audit` → Step 17; `start-round-{N+1}-generator` → Step 13). Do NOT end your turn.

17. **MUST invoke `/audit` via the Skill tool**. **NEVER bypass /audit** by spawning `code-reviewer` / `security-scanner` directly. Fail immediately if not invocable. Call with `round={n}` (matches `eval-round-{n}.md`); ticket plan → also pass `ticket-dir={ticket-dir}` (bare name); when `VERIFICATION_DEPTH ∈ {thorough, exhaustive}` (Step 3a) also pass `depth={VERIFICATION_DEPTH}` so `/audit` forces its skeptical third-pass (trigger T-F); omit `depth=` for `standard`/`off` (T-F does not fire — the conditional T-A..T-E behaviour is unchanged). Do NOT pass `only_security_scan`. `/audit` writes `quality-round-{n}.md`, `security-scan-{n}.md`, `audit-round-{n}.md` under `.simple-workflow/backlog/active/{ticket-dir}/`; firewall preserved — `/audit` reads `git diff` independently and must NOT receive Generator's or AC Evaluator's return value. **Return value cap**: per Context Conservation Protocol — under 500 tokens per spawned return.
    - Parse `/audit`'s structured return: `**Status**` (PASS | PASS_WITH_CONCERNS | FAIL), `**Critical**`, `**Warnings**`, `**Suggestions**`, `**Reports**`, `**Summary**`.
    - **If `/audit` itself fails**: read `gates.audit_infrastructure_fail.action` — `treat_as_fail` → Status: FAIL, Critical=1, `[AUTOPILOT-POLICY] gate=audit_infrastructure_fail action=treat_as_fail`; `stop` → stop. Else `AskUserQuestion` `stop`/`fail` with `header: audit-fail` (non-interactive default `stop`); the `header` value is load-bearing under the autopilot 3-tier `risk_tolerance` matrix (see `skills/autopilot/SKILL.md` `## Non-interactive orchestrator contract (3-tier, risk_tolerance-aware)`), so any other header (or an empty one) is denied at every tier when invoked under `/autopilot`. **Never** silently treat audit failure as PASS / PASS_WITH_CONCERNS.

    > **CHECKPOINT — RE-ANCHOR BEFORE CONTINUING**: `/audit`'s structured block is `/impl`'s input, not your output. Read `phase-state.yaml`; execute `phases.impl.next_action` (you are AT Step 18). Do NOT end your turn. Required next emit: `## [SW-CHECKPOINT]` in Phase 3.

18. Combined Decision: **FAIL** (Critical>0) → combine ac-evaluator PASS + audit Critical as feedback for next round. **PASS_WITH_CONCERNS** → Phase 3 with concerns. **PASS** (all 0) → Phase 3. **Final round + FAIL** → Phase 3 noting remaining issues.

## Phase 3: Summary

19. `git status -s` and display.

20. Print summary: plan, files changed/created, rounds, final status, evaluation report paths, "Review the changes above, then run `/ship` to commit and create PR".

21. **phase-state.yaml finalization** (`proceed-to-phase-3`): set `phases.impl.status: completed` + `completed_at: {now}` (ISO-8601 UTC) + `phase_sub: done` + `last_round: {N}` + `next_action: null`; top-level `last_completed_phase: impl`, `current_phase: ship`. Do NOT delete (consumed by `/ship`, `/catchup`). Non-ticket flow: no-op. Max-rounds FAIL → `status: completed` but `overall_status: in-progress`. `status: failed` + `overall_status: failed` only on invocation failure / FAIL-CRITICAL.

22. **Emit `## [SW-CHECKPOINT]`** (Phase 3 final, once per invocation) per `skills/create-ticket/references/sw-checkpoint-template.md` as FINAL section. Fill: `phase=impl`; `ticket=.simple-workflow/backlog/active/{ticket-dir}` else `none`; `artifacts=` repo-relative paths to every round's eval/quality/audit/security report + changed sources (`git diff --name-only`); `next_recommended=/ship` on `proceed-to-phase-3` else `""`. Failure: `artifacts: []`.

## Error Handling

- **No plan / Generator failure / AC Evaluator failure / Max-rounds FAIL**: report and stop (changes remain).
- **Dirty working tree**: warn; ask to continue.
- **/audit failure**: Step 17 handles via `AskUserQuestion` STOP vs FAIL; never PASS / PASS_WITH_CONCERNS.

## Evaluator Tuning

`/ship` invokes `/tune` (Step 6) to extract patterns into `.simple-workflow/kb/candidates.yaml`, promoted at confidence 0.8 to `entries.yaml`, injected via `index.yaml` into Generator prompt (Step 13h). Manual: `/tune {ticket-dir}` or `/tune all`.

## Subagent Skill-Access Handoff

When you spawn a subagent via the Agent tool, consult the `Available user skills:` line in the Pre-computed Context above. If a listed utility skill is relevant to that subagent's task, name it in the Agent prompt and instruct the subagent to use it via the Skill tool when it materially helps.

- **Truly hermetic agents** (`security-scanner`, `ticket-evaluator`) carry no Skill tool, no MCP, no `Bash(*)`. If you spawn one, hand off nothing — speculative references only add noise.
- **Skill-bearing verdict / read-only agents** (`ac-evaluator`, `code-reviewer`, `decomposer`, `tune-analyzer`) retain explicit `tools:` allowlists and do NOT inherit MCP / `Bash(*)`. They DO carry the Skill tool and receive capability handoffs, but only via **deterministic per-AC binding** (the `## Bound capabilities (per AC)` block extracted from `{ticket-dir}/ticket.md`'s `### Capabilities` section) — never via ad-hoc speculation from the `Available user skills:` probe.
- **Productive agents** (`implementer`, `planner`, `researcher`, `test-writer`) inherit-all under v8.0.0 — every parent-session MCP server and `Bash(*)` is in their tool inventory. Only `mcp__*` and Skills bound to an active AC via `## Bound capabilities (per AC)` may be invoked (per the agent body's `## Bound Capabilities (Handoff from Orchestrator)` section).
- For `ac-evaluator`, the capability handoff is no longer ad-hoc: Step 13 and Step 15 each `Read` `{ticket-dir}/ticket.md`'s `### Capabilities` section and inline the per-AC bound-capability list into the spawn prompt verbatim, so the Evaluator picks its evidence-gathering Skill from the upstream-recorded binding instead of re-deriving relevance. When the ticket has no `### Capabilities` section (e.g. pre-Gate-6 ticket), the orchestrator falls back to the prior advisory path and lets the Evaluator proceed on its in-house verification methods. Hand off evidence-gathering utilities only; never a skill that authors or modifies the code under review.
- Never present a pipeline skill (`/scout`, `/impl`, `/audit`, `/ship`, `/autopilot`, `/brief`, `/catchup`, `/create-ticket`, `/investigate`, `/plan2doc`, `/refactor`, `/test`, `/tune`) as a utility for a subagent.
- When a ticket's `### Capabilities` section exists (resolve via `{ticket-dir}/ticket.md` or the autopilot state file's `paths.ticket`), `Read` it before constructing any subagent spawn prompt and inline the bound capabilities verbatim into every spawn prompt under the heading `## Bound capabilities (per AC)`. For per-AC spawns (one spawn per AC, e.g. `/impl` Steps 13/15), include only the rows whose `Bound AC(s)` column lists the active AC. For tip / whole-deliverable spawns (the rest), include the full table. The upstream binding is authoritative — do NOT re-derive relevance from the AC text or re-scan `Available user skills:` for plausible matches. When the ticket lacks `### Capabilities` (older ticket pre-dating Gate 6), emit `## Bound capabilities (per AC): (none recorded — ticket pre-dates Gate 6)` in the spawn prompt and let the subagent fall back to its in-house capability-selection path.
- If the `Available user skills:` probe reports `(none)`, hand off nothing and let the subagent proceed with its in-house capabilities.
