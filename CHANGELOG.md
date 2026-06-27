# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [9.0.1] — 2026-06-27

**TL;DR.** Fixes the three criticals the v9.0.0 first real wave-parallel dogfood surfaced. **(FIX-1)** wave-parallel now actually runs: the worktree mechanism is redesigned around the platform's native `isolation:"worktree"` Task parameter (the prior manual `git worktree add` + cwd-at-spawn path was unreachable — the Task tool has no `cwd` parameter), with the orchestrator advancing the cross-wave base by checking out the local-only `ap-integration/<parent>` branch **in its own main checkout** (no dedicated integration worktree). **(FIX-2 + FIX-3)** a generator→evaluator→audit firewall stops a review/evaluator subagent from committing the code it grades or advancing its own phase-state: a PreToolUse `.agent_type` identity gate denies review agents the git `add`/`commit`/`mv`/`push` + pipeline-skill + phase-advancement vectors, and the inline-`git commit` authorization is re-keyed from a forgeable `phases.ship.status` flag to a non-forgeable `/ship`-issued `.ship-commit-nonce`. The firewall ships **metric-only** (observe + log, no deny) behind `SW_REVIEW_FIREWALL_MODE` / `SW_STATE_ADVANCE_GUARD_MODE`; FIX-1 ships **on** behind `SW_PARALLEL_WORKTREE_PREFLIGHT_MODE` (a host without git-worktree support falls back to byte-identical serial). Non-breaking: every new default is kill-switched and the `parallel=off` lane stays byte-identical to v9.0.0.

### Fixed

- **FIX-1 — wave-parallel executes (isolation:"worktree" redesign).** The v9.0.0 wave-parallel path fell back to serial on the first real dogfood — each `ticket-executor` was spawned at the orchestrator's repo-root cwd, so its `EnterWorktree(path=…)` was rejected and `parallel_mode` collapsed to off. Phase-0 spikes (headless `claude -p`) settled the mechanism: the Task/Agent tool has **no `cwd` parameter**, but `isolation:"worktree"` is a native Task parameter that places the subagent in `.claude/worktrees/agent-<id>` on branch `worktree-agent-<id>`, **based on the orchestrator's current HEAD**. The scheduler now spawns each executor with `isolation:"worktree"` + `MAIN_REPO=<abs>` (the executor self-creates the `.simple-workflow` → main-checkout symlink as its first step); the orchestrator `git checkout`s the local-only `ap-integration/<parent>` branch **in its own main checkout** and merges each completed `worktree-agent-<id>` branch there, so the next wave's isolation worktrees branch from the integrated tip (the spike-validated cross-wave base). The dedicated integration worktree is removed (a branch cannot be checked out in two worktrees). A worktree-capability **pre-flight** runs before the integration-branch checkout; on an isolation-unsupported host it deletes the `parallel_mode:` line (persisting the downgrade so a resume does not re-thrash) and falls back to byte-identical serial. **Migration:** none for a working host; `SW_PARALLEL_WORKTREE_PREFLIGHT_MODE=off` skips the probe, `parallel=off` / `SW_PARALLEL_TICKETS_MODE=off` restore the serial loop unchanged.
- **FIX-2 — generator→evaluator firewall (Bash + Skill vectors).** A review/evaluator subagent could land a `git commit` and chain-call pipeline skills, breaching the generator→evaluator separation (dogfood62 observed a `doc-verifier` committing + running `/ship`). The PreToolUse:Bash guard now (a) re-keys the inline-`git commit` authorization from the forgeable `phases.ship.status: in-progress` proxy to a non-forgeable `.ship-commit-nonce` file that `/ship` writes immediately **before** its Step-3 commit (and removes on every exit path) — an **unconditionally enforced** signal swap — and (b) denies `git add/commit/mv/push` issued by a review agent (the four Bash-bearing review agents; `git worktree` exempt). A new PreToolUse:Skill guard denies a review agent invoking the namespaced pipeline skills (`simple-workflow:impl|audit|ship|autopilot|refactor`). The per-agent `tools:` allowlist cannot close these (Phase-0 S3: Bash-subcommand granularity is not enforced), so the hook is the sole mechanism. **Migration:** the review-deny ships `metric-only` (log only); `SW_REVIEW_FIREWALL_MODE=on` enforces, `=off` disables. The nonce gate is independent of the knob.
- **FIX-3 — phase-state write-authority + advancement coverage (Write/Edit + Bash vectors).** `pre-state-transition.sh` previously guarded only `status: skipped`; it now detects **every** advancement (`status` / `current_phase` / `overall_status` / `phases.<phase>.status` → `in_progress` / `completed` / `failed` / `ship`) identity-free, and a new Detection 4 denies a review/evaluator agent (all six, bare and `simple-workflow:`-namespaced) writing such an advancement. The Bash mirror (`pre-bash-contract-guard.sh` Detection 3) gains the same `current_phase` / `overall_status` + bare-`ship` coverage. **Migration:** ships `metric-only` behind `SW_STATE_ADVANCE_GUARD_MODE`; `=on` enforces. The orchestrator and generators (empty `.agent_type`) are always allowed (fail-open-on-empty).
- **dogfood63 hardening (re-dogfood findings — all low/medium, self-recovered in the run).** Four refinements surfaced by the v9.0.1 re-dogfood (a 3-ticket wave-parallel run): **(a)** the nonce gate now tolerates a **co-located** nonce-write — `/ship` may chain `: > .../.ship-commit-nonce` with the Step-3 commit in one `&&` (PreToolUse inspects the command string before the write runs), so the combined form is no longer false-blocked (it false-tripped 1 of 3 ship paths in dogfood63; the bare-commit breach is still blocked); **(b)** the post-loop **no-remote landing** is codified — with no remote (no per-ticket PRs) the orchestrator fast-forwards (`--ff-only`, with a divergence fallback) the start ref to the integrated tip so the assembled work lands on the branch the user launched on instead of a local-only orchestration branch; **(c)** the SubagentStop checkpoint guards emit a behaviour-neutral `main_checkout_root resolution` marker so the worktree-symlink phase-state resolution (the AC-8 owed item) is unit-testable and forensically visible; **(d)** the implementer MUST isolate build/test tooling installs to the workspace (a project-local virtual environment / container) and never mutate a shared/global/system toolchain that persists outside the workspace (an eval-sandbox-boundary principle; a wave-0 executor's `--break-system-packages` system install motivated it).

### Verification

- `bash tests/test-skill-contracts.sh` **912/912** (CT-WORKTREE-1/2/3/8/9 rewritten for the isolation:"worktree" redesign + CT-FIX1-SPAWN-ISOLATION/SYMLINK/PREFLIGHT; CT-FIX2-NONCE-ORDERING / REVIEW-AGENT-COMMIT-DENIED / GIT-WORKTREE-EXEMPT / SKILL-NAMESPACED / HOOKS-JSON-SPLIT; CT-FIX3-PART-A / REVIEW-AGENT-ADVANCE-DENIED / BASHMIRROR / SYNC1 — SYNC1 is a property check that enumerates every review/evaluator `agents/*.md` by role and goes RED if one is missing from the Detection-4 denylist, with token-boundary membership); `bash tests/test-pre-bash-contract-guard.sh` **24/24**; `bash tests/test-state-transition-guard.sh` **21/21** (scenarios (a)-(f) green; the pending→completed canary still ALLOW via fail-open-on-empty); `bash tests/test-pre-skill-contract-guard.sh` **9/9** (new); `bash tests/test-path-consistency.sh` **145/145**; `bash tests/run-all.sh` reports **ALL TEST SUITES PASSED**; `shellcheck -S error` clean on the three edited hooks; `hooks.json` valid. `plugin.json` `9.0.1` == newest CHANGELOG `[9.0.1]` (CT-MODE-14).
- **Phase-0 spikes (headless `claude -p`, CC 2.1.191).** S1: the Task tool has no `cwd` parameter (cwd-at-spawn unexpressible). S2: the PreToolUse payload natively carries `.agent_type` (subagent → name, possibly namespaced; orchestrator → absent), so the firewall identity gate is a two-line extraction + unconditional `simple-workflow:` strip. S3: per-agent `tools:` Bash-subcommand allowlists are not enforced (a `Bash(git diff:*)`-only agent still committed). S4/S5: `isolation:"worktree"` works and bases the worktree on the orchestrator's current HEAD, so advancing the orchestrator's HEAD to the integrated tip propagates the cross-wave base (S5 Run B confirmed empirically).
- **Adversarial verification.** FIX-1: an independent read-only review found all five mechanism claims survive refutation (cross-wave coherence, `parallel=off` byte-identity, CT non-vacuity, no stale-mechanism stragglers, governance) and surfaced one ordering edge (pre-flight after the integration checkout), fixed before release. FIX-2/FIX-3: a 4-lens adversarial panel (firewall-correctness, byte-identity, CT-non-vacuity, governance + folded-blockers) all returned SURVIVES with zero blockers; the two minor findings (a substring blind spot in the property CT, a stale header comment) were fixed.
- **Metric-only / byte-identity.** The firewall defaults are `metric-only` (stderr only; no state-file write, no `.runtime_metrics` leak); all guards are autopilot-context-gated (a normal `git commit` outside an autopilot run is never touched), fail-open (exit 0; a block is decision JSON), and silent-exit when `jq` is absent. `SW_REVIEW_FIREWALL_MODE=off` / `SW_STATE_ADVANCE_GUARD_MODE=off` / `SW_PARALLEL_WORKTREE_PREFLIGHT_MODE=off` plus the existing `parallel=off` / `SW_PARALLEL_TICKETS_MODE=off` kill switches revert. **Re-dogfood (dogfood63 — a 3-ticket wave-parallel run with the firewall knobs `on`):** AC-8 PASSED decisively (truly-concurrent wave-0 spawn verified by shared message/requestId + out-of-order completion, distinct isolation worktrees, git-proven cross-wave integration, 61 product tests, normal completion) and AC-6 ran with **zero firewall false-trips** on legitimate review activity (all review-agent transcripts read-only git, no out-of-role commit or phase-advance); the four findings it surfaced are hardened in the `dogfood63 hardening` entry above. **Still owed (a follow-up):** a LIVE review-agent deny (`unauthorized_commit_by_review_agent` / `unauthorized_phase_advance_by_review_agent`) — the clean run produced no breach to deny — gates the `SW_REVIEW_FIREWALL_MODE` / `SW_STATE_ADVANCE_GUARD_MODE` metric-only→on promotion.

## [9.0.0] — 2026-06-25

**TL;DR.** **BREAKING (default flips).** Two run-defaults flip from opt-in to **on** for a bare invocation: **ultracode orchestration** (`uc`) and **wave-parallel ticket execution** (`parallel`). A bare `/autopilot <slug>` (and `/brief <idea>` under the `chain=on` default) now writes `ultracode_mode: on` + `parallel_mode: on`, routes M+ tickets through the parallel multi-verifier eval panel, and executes a multi-ticket run wave-by-wave through one `ticket-executor` subagent per topologically-ready ticket (each in an isolated git worktree, merged at wave boundaries) instead of the inline serial loop. The safety guarantee inverts to the **opt-out** path: `uc=off` restores the v8.7.0 single-evaluator Agent path; `parallel=off` (or the `SW_PARALLEL_TICKETS_MODE=off` / `SW_PARALLEL_HOOKS_MODE=off` env kill switches) restores the v8.7.0 inline serial loop — **byte-identical** in artifacts, state, and verdict. The `parallel` flip rides on the full Phase 2 hook rework (T-004/5/6 wave-aware Stop / checkpoint / auto-compact), the wave scheduler (T-007), and worktree isolation + cross-wave integration (T-008), all landed in this release, AND on the **T-005 R-SUBSTOP spike resolving to RELOCATE** (the checkpoint guards relocate to `SubagentStop`, fire on the executor transcript, and enforce there). A fat-fingered `parallel=<garbage>` value fails **safe to `off`** (the proven serial path, uniform with `uc=` unknown→off), surfaced via `[PARALLEL-MODE] mode=off active=n reason=invocation-unknown-value-failsafe`.

### Changed

- **BREAKING — `uc` (ultracode orchestration) default flips off→on.** With no `uc=` token, `/autopilot` / `/impl` / (`chain=on`) `/brief` now resolve `UC_ORCH = on`: M+ tickets run their AC evaluation as a parallel multi-verifier panel via the Workflow tool. **Migration:** pass `uc=off` to restore the v8.7.0 single-evaluator Agent path (byte-identical — no Workflow dispatch, no UC-FLOOR raise). Token cost rises for every M+ ticket on a bare run because of the added panel lenses (see the README "Sub-agents consume API tokens" note); `uc=off` is the cost-revert. The `uc` flip has no hook dependency and is independent of the spike; it rides v9.0.0 for the "breaking when in doubt" bundling.
- **BREAKING — `parallel` (wave-parallel ticket execution) default flips off→on.** With no `parallel=` token, `/autopilot` (and `/brief chain=on`) now resolve `PARALLEL_MODE = on` and execute a multi-ticket run wave-parallel through `ticket-executor` subagents in isolated worktrees. **Migration:** pass `parallel=off` (per-invocation) or set `SW_PARALLEL_TICKETS_MODE=off` / `SW_PARALLEL_HOOKS_MODE=off` (the env panic button for a `/brief`-chained invocation you cannot edit) to restore the v8.7.0 inline serial loop — byte-identical: no `ticket-executor` spawn, no wave cursor, no worktree machinery, the `parallel_mode:` state field omitted, every hook firing exactly as in v8.7.0. This flip is gated on the full Phase 2 rework + the T-005 spike verdict being RELOCATE (both satisfied in this release); defaulting parallel on before the rework — or with the checkpoint guards blind — would silently kill auto-compaction across long runs and/or blind the guards on every run, the precise failures Phase 2 prevents.
- **Unknown-value posture is uniform fail-safe → off (L3 / R4).** An unknown `parallel=<garbage>` (and `uc=<garbage>`) invocation value coerces to **off** (the proven serial / Agent path), reconciling the argument-side parser with the hook-side `resolve_parallel_mode` (both fail closed to off). For `parallel`, the coercion is observable: `[PARALLEL-MODE] mode=off active=n reason=invocation-unknown-value-failsafe`. **Migration:** none — this only hardens the opt-out guarantee so a typo never silently opts INTO the less-proven parallel machinery; the prior "coerce unknown to the on default" posture is rejected as inverting the conservative direction.

### Removed

- **`mode=` alias removal — DEFERRED, NOT executed in v9.0.0.** The deprecated `/brief mode=auto|manual` alias (superseded by `chain=on|off`) was slated for removal in v9.0.0, but its removal is **out of scope for this release** (T-009 changes default *values*, not the alias surface). The alias and its `WARNING: 'mode=' is deprecated and will be removed in a future major version …` deprecation line still ship and remain functional. The removal is carried forward to a future major; every shipped reference to it (the runtime `/brief` WARNING, the README `/brief` signature, the `mode independence guard` note, and the `agent-spawn-prompts.md` precedence note) was corrected this release to name **"a future major"** rather than v9.0.0, so no v9.0.0 artifact claims its own removal in the version that is shipping. (Recorded honestly here rather than claiming a removal that did not happen — an R4 doc-truthfulness obligation.)

### Verification

- `bash tests/test-skill-contracts.sh` **900/900** (+ **CT-PARALLEL-7..12**: the parallel default off→on flip, the explicit `parallel=off` byte-identity opt-out, the bare-default-on-routes-to-wave-parallel anchor, the unknown→off fail-safe, the **`SW_PARALLEL_TICKETS_MODE` env-override** wiring [CT-PARALLEL-11], and the **metric-only → inline-serial-with-wave-log routing** [CT-PARALLEL-12]; the existing **CT-PARALLEL-1..6** / **CT-PARALLEL-CURSOR-*** / **CT-PARALLEL-SUBSTOP-*** / **CT-WAVE-*** / **CT-WORKTREE-1..12** greens carry; **CT-UC-ORCH-5** reaffirms the `uc=off` byte-identity); `bash tests/test-path-consistency.sh` **145/145**; `bash tests/test-accept-set-verify.sh` **32/32**; `bash tests/run-all.sh` reports **ALL TEST SUITES PASSED** (incl `test-phase-state-contracts.sh` **14/14** + `test-autopilot-continue.sh` **65/65**). `plugin.json` `9.0.0` == newest CHANGELOG `[9.0.0]` (CT-MODE-14, which reads the newest entry dynamically); the real ISO date is verified by the manual pre-flight (CT-MODE-13 is hardcoded to the `[6.0.0]` header and does NOT guard the `[9.0.0]` date).
- **Opt-out byte-identity.** `/autopilot {slug} uc=off parallel=off` is byte-identical to v8.7.0 (inline serial loop + Agent-path evaluator): the `parallel=off` lane omits the `parallel_mode:` state field and adds no code path (the serial-fork literals `parallel=off … adds NO code path` / `the serial loop is untouched` survive verbatim); `uc=off` preserves the `byte-identical to v8.5.0` literal. The two args are a uniform 2-peer set (one `[*-MODE] mode=… active=… reason=…` emit shape, one opt-out-byte-identical contract, one `chain=off`-silent rule, one unknown→off fail-safe rule).
- **Phase 2 rework + scheduler + worktree evidence (landed this release).** T-004/5/6 wave-aware hooks (autopilot-continue wave-aware continuation; checkpoint guards relocated to `SubagentStop` with the parallel main-`Stop` stand-down; per-wave-drained auto-compact re-key) ship green; T-007 wave scheduler + `parallel_max` cap + the H2 cascade-skip carve-out fix; T-008 worktree isolation + cross-wave integration via the shared-tree `.simple-workflow` symlink.
- **R-SUBSTOP spike verdict = RELOCATE.** The T-005 spike resolved to RELOCATE (confirmed empirically: `SubagentStop` fires with the executor transcript and the checkpoint guards enforce on it), which is the first-class release input that gates the `parallel` default flip. Under RELOCATE the flip ships; had it resolved to STAND-DOWN, the parallel default would have stayed opt-in for v9.0.0 with a barrier-not-guards caveat.
- **Documented limitation (T-008).** Under concurrency > 1 the `/ship` Step 6 `/tune` step read-modify-writes the shared `.simple-workflow/kb/` accumulator, racing to a bounded **KB-learning lost-update** — a tolerated best-effort-learning fidelity drop, NOT a correctness bug (ticket execution + status + `autopilot-state.yaml` are unaffected). Serializing `/tune` is the documented follow-up.
- **Pre-release multi-angle branch review (4 cross-cutting criticals found + fixed).** A 25-agent / 6-dimension adversarial review of the whole branch (each finding independently re-verified) caught 4 critical bugs the per-ticket reviews missed; all fixed + re-verified clean before release. **(C1)** an empty-wave cursor stall — under parallel default-on, cascading dependency failures that empty later waves left `current_wave` un-advanced, so `hooks/autopilot-continue.sh` blocked "spawn next wave" until the loop guard fired; fixed with an all-terminal guard (the serial path already handled it; fixture `T-004-4b`, negative-control proven). **(C2)** the `SW_PARALLEL_TICKETS_MODE` kill switch was unwired — the resolver reads `SW_PARALLEL_HOOKS_MODE` and `/autopilot` never checked `SW_PARALLEL_TICKETS_MODE`, so the documented panic button did nothing; fixed by wiring an env-override (`env > arg > default`, unknown→off) into Argument Parsing + correcting the false "applied by the resolver helper" claim in `skills/autopilot/SKILL.md` + `CLAUDE.md`. **(C3)** `test-phase-state-contracts.sh` false-positive-FAILed on a dense prose line (`platfo`**`rm`** … `phase-state.yaml`) — the suite was RED on the branch; fixed by anchoring the `rm` grep to a shell-command boundary (genuine `rm phase-state.yaml` still caught; positive/negative controls verified). **(C4)** a metric-only routing contradiction (T-001 "`!= off` → executor" vs T-007 "metric-only = serial"); resolved by splitting the routing gate into three explicit cases (`off` / `metric-only` serial-with-wave-log / `on` executor-routed) + aligning `agents/ticket-executor.md` to `== on`. Guarded by `CT-PARALLEL-11`/`12` + `T-004-4b` + the tightened `test-phase-state-contracts.sh`.

## [8.7.0] — 2026-06-24

**TL;DR.** Adds **forward-direction lossless verification (MR-ROUNDTRIP)** — the write-side counterpart to the parse-side MR-CANONICAL in the executed accept-set sweep. When a ticket pairs a reader (parse / decode) with a **canonical writer** (format / serialize / encode) that advertises a **round-trip / lossless / exact / canonical** guarantee, the `ac-evaluator` now drives exactly-representable values **through the real writer** and verifies `parse(format(x)) === x` over a grammar-derived **inter-anchor intermediate band** (including the just-below-promotion extremes where significant-figure rounding would fire), with an independent `parse∘format` oracle built from first principles — catching a writer that silently rounds an exactly-representable value to a lossy canonical string at `rc=0`, a class invisible to every parse-side relation. A deterministic **W-axis writer-pairing trigger** (`/impl` Step 3a) recognizes the paired reader+writer even when the only lexical cue sits on the reader, and a recognition-independent hook backstop (`P5` forward-depth, `P6` round-trip-mislabel) makes a shallow or mislabeled forward sweep un-shippable. Strictly **meet-or-beat**: the W-axis relation only ADDS coverage; absent a paired canonical-writer boundary it never triggers, and the same kill switches (`SW_ACCEPT_SET_CONFORMANCE_MODE=off` / `constraints.accept_set_conformance: off`) revert byte-for-byte. Validated dogfood58 → dogfood59: a paired `parse` + `format` subject drove `boundary=W roundtrip=y intermediate-sampled=y` end-to-end across three tickets (corpus 9190 IEC + 9004 SI, 0 divergences), shipped a correct + doc-truthful writer (the silent-loss regression class foreclosed in both code and README), and locked the round-trip + Unicode-digit complement RED in the committed test suite.

### Added

- **MR-ROUNDTRIP — forward-direction writer losslessness (W axis).** The executed accept-set sweep gains a fifth metamorphic relation: for an AC whose boundary is a canonical writer advertising round-trip / lossless / exact / canonical, the evaluator builds a value corpus from the writer's **own** grammar (first-principles multiplier / anchor tables, never the unit-under-test's data), samples the **inter-anchor intermediate band** plus the just-below-next-anchor extremes, drives each through the real writer, and checks the independent `parse∘format` round-trip identity. The persisted `## Accept-set sweep` line gains `roundtrip=` and `intermediate-sampled=` fields; a triggered W boundary with `intermediate-sampled=n` self-incriminates as a shallow forward sweep. A worked copyable shape (`make_value_corpus` / `run_writer_roundtrip`) lives in `skills/impl/references/accept-set-conformance-harness.md`, mirrored byte-identically across the `ac-evaluator` / `ac-evaluator-hi` twins. Guarded by **CT-AASC-15..22**.
- **Deterministic W-axis writer-pairing trigger (`/impl` Step 3a).** When the ticket scope pairs a reader (parse / decode / deserialize) with a canonical writer (format / serialize / encode) that advertises a round-trip / lossless guarantee, the AC is included in `triggered-on=` for the **W** axis even when the only lexical cue sits on the reader — the paired-writer round-trip boundary is itself the trigger (parallel to the existing keyed-structure K-axis clause) — and the evaluator MUST encode the sweep as `boundary=W roundtrip=y` (never an improvised non-canonical label). Removes the run-to-run recognition variance that let the writer's forward sweep be recorded under an off-grammar label.
- **Hook forward-depth backstops (`P5`, `P6`).** `hooks/accept-set-verify.sh` gains two recognition-independent `PostToolUse` predicates: **P5** blocks a triggered `boundary=W` with `roundtrip=y intermediate-sampled=n` (a shallow forward sweep), and **P6** blocks a round-trip-bearing sweep (`roundtrip=y` or `intermediate-sampled=y`) persisted under any non-`W` boundary label (a mislabeled forward sweep) — so a writer's forward sweep recorded under an off-grammar label is un-shippable regardless of model recognition. Fail-OPEN (exit code always 0). Guarded by **CT-AASC-23**.
- **Gate 4 representation-foreclosure + Gate 9 R1 forward-losslessness (AC authoring).** `skills/create-ticket/references/ac-quality-criteria.md` gains a Gate 9 R1 "forward-direction writer losslessness" rule (the inter-anchor band) and a Gate 4 "representation foreclosure" sub-section, so a paired-writer ticket authors the round-trip AC up front. The planner runs a Gate-4 self-audit, and the brief body template carries an Out-of-Scope **ENDS-not-MEANS** note so an exclusion cannot silently foreclose the writer's exact representation.
- **Producer generative property-test lock-in (P0-3).** On a found accept-set leak the producer (`test-writer` / `implementer`, per `test-authoring-guidance.md`) writes a **generative property test** unconditionally, so the regression is locked RED in the **committed** suite — closing the durable-layer generation gap at the producer side.

### Verification

- `bash tests/test-skill-contracts.sh` **865/865** (+ **CT-AASC-15..23**; twin byte-identity **CT-EV-MODEL-1**; **CT-DECONTAM-1** 0 hits); `bash tests/test-accept-set-verify.sh` **32/32**; `bash tests/test-path-consistency.sh` **144/144**; `shellcheck --severity=warning hooks/accept-set-verify.sh` clean; `ac-evaluator` / `ac-evaluator-hi` bodies byte-identical sans `name:` / `model:`. `plugin.json` `8.7.0` == newest CHANGELOG `[8.7.0]` (CT-MODE-14), real ISO date (CT-MODE-13). The hook `P5` / `P6` paths are covered by **CT-AASC-23** + functional hook probes; dedicated cases in `test-accept-set-verify.sh` are a tracked follow-up.
- **Dogfood evidence.** dogfood58 (a paired byte-size converter) was a SPLIT — the product was correct and the forward sweep was authored, but the W-axis runtime gate did not engage (the writer's round-trip was recorded under an off-grammar label), which motivated the deterministic W-trigger + hook `P6`. dogfood59 (a paired `parse` + `format` subject, `chain=on` / `uc=off`) confirmed the fix end-to-end: the orchestrator recognized the paired parse/format as the W axis (`[ACCEPT-SET-TRIGGER] … basis=both`), the evaluator encoded canonical `boundary=W roundtrip=y intermediate-sampled=y` across three tickets, a 9190 IEC + 9004 SI corpus MR-ROUNDTRIP ran with 0 divergences, the shipped `format` was correct + doc-truthful (a dedicated README "Round-trip fidelity (caveat)" section documents the lossy-display contract + the representation-foreclosure remedy), and the committed suite (208/208) locks the round-trip property + the Unicode-digit complement RED. Zero product defects shipped.
- **Additive + kill-switched.** The W-axis (forward) relation only ADDS coverage to the existing accept-set sweep — absent a paired canonical-writer boundary it never triggers, and the parse-side relations (MR-FINITE / MR-ALPHABET / MR-CANONICAL / MR-KEYFAITH) and the A/U/K axes are byte-unchanged. The hook `P5` / `P6` predicates are fail-OPEN (exit code always 0) and strictly additive to `P1`–`P4`. `SW_ACCEPT_SET_CONFORMANCE_MODE=off` / `constraints.accept_set_conformance: off` reverts byte-for-byte to v8.6.0 behaviour.

## [8.6.0] — 2026-06-21

**TL;DR.** Adds an opt-in **ultracode orchestration** mode (`uc=on`) that routes a ticket's AC evaluation through Claude Code's **Workflow tool** instead of sequential Agent-tool spawns. When `uc=on`, every non-trivial (M+) ticket runs its evaluation as a **parallel 3-lens multi-verifier panel** (a committed Workflow script, `skills/impl/workflows/eval-panel.mjs`) that returns **schema-validated typed verdicts** (closing the prose-envelope-parsing gap) and merges them with the existing refute-then-synthesize rule — at a **tier-appropriate model** (Sonnet at `thorough`, Opus at `exhaustive`). The opt-in is a single invocation argument that propagates `/brief` → `/autopilot` → each `/impl` and is **preserved across auto-`/compact` and autopilot resume** via run-scoped state (`ultracode_mode` in `autopilot-state.yaml`), never a persisted policy flag. Strictly **meet-or-beat**: `uc=on` only ADDS verification (3 evidence-mode-diverse lenses where the prior path ran 1) and can never lower the catch-rate; **`uc=off` / no `uc` argument is byte-identical to v8.5.0**. Validated across dogfood54→55 (a leak-inviting strict subject; M tickets correctly routed to the parallel panel at Sonnet, the exhaustive ticket at Opus, run-scoped continuity held across 3 auto-compacts, zero product defects).

### Added

- **Ultracode orchestration opt-in (`uc=on`).** A new invocation argument accepted on `/brief <idea> chain=on uc=on`, `/autopilot <slug> uc=on`, and `/impl … uc=on` (case-insensitive `key=value`, like `rounds=`/`chain=`; default `off`). When `on`, `/impl` Step 15 dispatches the AC evaluation through the **Workflow tool** (the committed `skills/impl/workflows/eval-panel.mjs`) — 3 lens-diverse evaluators (V1 EC-RUNTIME / V2 EC-DIFFERENTIAL-or-EC-PROPERTY / V3 EC-ORACLE) in parallel, returning a forced **`EVAL_SCHEMA`** StructuredOutput object that Step 16 consumes directly (no prose-envelope grep parse), merged by the identical refute-then-synthesize rule. `metric-only` logs intent and falls through to the Agent path; `off` is the existing Agent path. `Workflow` is added to `/impl` allowed-tools.
- **Coverage = every non-trivial (M+) ticket (Step 3a `UC-FLOOR`).** When `uc=on` and the ticket Size is not `S`, `VERIFICATION_DEPTH` is floored to at least `thorough` (applied before evaluator-model / evidence-floor / round-cap so they all reflect the floored tier), routing M/L/XL through the parallel panel at a **tier-appropriate model** — Sonnet at `thorough`, Opus at `exhaustive`. `S` tickets stay `standard` (Agent path). Emits `[UC-ORCH-FLOOR]` + `[UC-ORCH-MODE]` observability lines. The Workflow dispatch is gated `AC_COUNT < 30` so a large-AC ticket defers to the Agent **partition** branch (which takes precedence per `ac-evaluator-orchestration.md`).
- **Run-scoped continuity across auto-`/compact` / resume.** `/autopilot` records the resolved mode as a top-level `ultracode_mode:` field in `autopilot-state.yaml` (documented in `references/state-file.md`), re-reads it on resume (Phase 1 Step 5, via `parse_yaml_scalar`), and forwards `uc=` to each per-ticket `/impl` — so the mode survives compaction and resume until the run completes, then is gone (it is run-state, **not** a permanent `autopilot-policy.yaml` flag). The `session-start.sh` / `autopilot-continue.sh` hooks are unchanged (they read state wholesale). On `/brief chain=off`, a supplied `uc=on` is ignored with a `WARNING` (there is no chained `/autopilot` to receive it). Guarded by **CT-UC-ORCH-1..4**; the committed merge pure-function is unit-tested (`tests/test-eval-panel-merge.mjs`, **23/23**, mirrored byte-identically in the script).

### Verification

- `bash tests/test-skill-contracts.sh` **856/856** (+ **CT-UC-ORCH-1..4**; twin byte-identity **CT-EV-MODEL-1**; **CT-DECONTAM-1** 0 hits incl. the new `eval-panel.mjs`); `bash tests/test-accept-set-verify.sh` **32/32**; `bash tests/test-path-consistency.sh` **144/144**; `node --check skills/impl/workflows/eval-panel.mjs`; `node tests/test-eval-panel-merge.mjs` **23/23** (merge fn src↔test mirror byte-identical); `shellcheck --severity=warning` clean; `ac-evaluator` / `ac-evaluator-hi` bodies byte-identical sans `name:` / `model:`. `plugin.json` `8.6.0` == newest CHANGELOG `[8.6.0]` (CT-MODE-14), real ISO date (CT-MODE-13).
- **Dogfood evidence.** dogfood54 (byte-size codec) surfaced + fixed two Workflow-path bugs (args marshalled as a JSON string → silent Opus→Sonnet downgrade on exhaustive; the partition case not deferred). dogfood55 (strict rational-number library, 4 tickets) confirmed the fixes + the M-widening live: the L/exhaustive ticket ran 3× Opus (`ac-evaluator-hi`), the three M tickets ran 3× Sonnet (`ac-evaluator`) via the Workflow panel, `[UC-ORCH-FLOOR] raised=y` fired, run-scoped continuity held across 3 auto-compacts, the executed accept-set sweep ran (corpus 1542, astral, 0 divergences), and zero product defects shipped (audit `PASS_WITH_CONCERNS`, 0 Critical).
- **Additive + opt-in.** Absent `uc` / `uc=off` is byte-identical to v8.5.0 (no Workflow invocation, no marker lines, the existing Agent path). The Workflow path only ever ADDS verification (3 evidence-mode lenses where the Agent path ran 1) — it cannot lower the catch-rate.

## [8.5.0] — 2026-06-20

**TL;DR.** Adds **Advertised-Accept-Set Conformance (AASC)** — a product-/language-/domain-agnostic meet-or-beat upgrade to verification. When a boundary advertises **strict / canonical / lossless / limit** (or shares an input class with a sibling), the `ac-evaluator` now **EXECUTES** a generative grammar-complement sweep in scratch and diffs the unit's accept-set against an **independent hand-coded oracle** — catching parse-accepted overflow, input-alphabet leaks (incl. astral Unicode digits), non-canonical accepts, and structural-key / prototype-pollution injection **by construction for all inputs**, instead of by recalling a product-specific keyword cue. A new recognition-independent PostToolUse hook (`hooks/accept-set-verify.sh`) deterministically gates the persisted sweep and **enforces by default**. This release also codifies the product/language/domain-**agnosticism** rules (the (A)/(B) substrate line + the meet-or-beat principle + the `CT-DECONTAM-1` product-instance recidivism guard) and lands the P0 safety / state-machinery hardening batch. Validated across dogfood43→53: a deliberately leak-inviting strict subject produced correct strict artifacts on every historically-failing trap, and a live `decision:block` de-risk confirmed the enforce path. Additive + kill-switched: `constraints.accept_set_conformance: off` or `SW_ACCEPT_SET_CONFORMANCE_MODE=off` reverts byte-for-byte to the pre-v8.5.0 read-only strictness reasoning.

### Added

- **Advertised-Accept-Set Conformance — the executed accept-set sweep.** For an AC whose boundary advertises strict / canonical / lossless / limit OR belongs to a `shared_input_boundary` sibling family, the `ac-evaluator` derives a per-boundary **Grammar Card** (`A` alphabet / `U` unicode-transform / `W` canonical-writer / `K` keyed-structure) and EXECUTES four machine-generated metamorphic relations black-box in `.simple-workflow/scratch/` against an independent hand-coded spec oracle: **MR-FINITE** (parse-accepted overflow), **MR-ALPHABET** (the Unicode decimal-digit-property complement across the BMP **and** astral planes — generator names no script/codepoint), **MR-CANONICAL** (non-canonical accept), **MR-KEYFAITH** (a reserved/accessor/private-slot key derived by reflection over the type/prototype — generator names no key literal). A divergence is force-FAILed only under a two-tier oracle-authoritative gate (otherwise advisory `[MEDIUM]`, fail-open where no runnable artifact exists). One unconditional `## Accept-set sweep` line per inspected boundary is persisted to `eval-round-{n}.md` (`boundary= triggered= ran= astral= corpus-size= divergences= authoritative= caveat=`). A worked copyable shape lives in `skills/impl/references/accept-set-conformance-harness.md`; committed proof prototypes in `design-oracles/aasc-accept-set/` and `design-oracles/aasc-keyfaith/` (verified `node` + `python3`). Guarded by **CT-AASC-1..14**.
- **Per-AC deterministic AASC trigger + `constraints.accept_set_conformance` kill switch.** `/impl` Step 15 computes, per AC, whether the boundary advertises strict/canonical/lossless/limit (lexical) OR is a shared-input sibling (a keyed-structure-from-untrusted-input always triggers the K axis), inlines `Accept-set conformance: {auto|off} triggered-on={ids}` into the evaluator spawn, and emits `[ACCEPT-SET-TRIGGER]` — so the evaluator never re-decides whether to run the sweep (removing the run-to-run recognition variance). The per-brief `constraints.accept_set_conformance` field is documented symmetrically across all three spawner surfaces (`policy-template.md`, `autopilot-policy-reference.md`, `ac-evaluator-orchestration.md`); **CT-AASC-14**.
- **AASC determinism hook (`hooks/accept-set-verify.sh`).** A recognition-independent `PostToolUse(Write|Edit)` gate that reads the persisted `## Accept-set sweep` line and applies the lens's own self-incrimination rule with zero model recall: a triggered boundary not run (P1), an A/U-axis sweep that skipped the astral complement (P2), or an authoritative divergence not driven to FAIL (P4) emits a `decision:block`; a thin A/U corpus (P3) is advisory-only. Fail-OPEN (exit code always 0; jq-missing / non-eval path / skeleton / `n/a` all pass). Env knobs `SW_ACCEPT_SET_CONFORMANCE_MODE` + `SW_AASC_CORPUS_FLOOR`. Verified by `tests/test-accept-set-verify.sh` (**32/32**) and registered via **CT-AASC-13**.
- **Product/language/domain agnosticism codification.** `CLAUDE.md` gains the **(A) user-product / (B) harness-own substrate line**, the *agnosticism must never lower quality* (meet-or-beat) rule, and the HARD-LINE-vs-JUDGMENT enforcement boundary. **CT-DECONTAM-1** is a product-instance recidivism guard over the 14-file normative set (denylist = product instances only; abstract failure-class names + bare domain vocabulary are deliberately kept), and the normative content was de-contaminated of product-specific cues.
- **Cross-ticket `shared_input_boundary` sibling-guard (P-A).** The planner / ticket-evaluator forward a shared-input-class signal so a delegating sibling's boundary is recognized (it triggers the accept-set sweep even with no lexical strict/canonical word present).
- **Safety / state-machinery hardening (P0 batch).** New `hooks/pre-bash-contract-guard.sh` (Bash-mediated state-mutation guard, `SW_BASH_STATE_GUARD_MODE`); jq-missing (`SW_SAFETY_JQ_MISSING_MODE`) and HOOK_OWNED_FIELDS (`SW_STATE_FIELD_GUARD_MODE`) guards across `pre-bash`/`pre-write`/`pre-edit-safety`; `hooks/lib/parse-state-file.sh` element-scoped state parsers; `autopilot-continue` loop-guard de-pollution + `post-ship-state-auto-compact` Gate 5.5 integrity self-heal (`SW_POST_SHIP_INTEGRITY`). New suites `tests/test-pre-bash-contract-guard.sh`, `tests/test-state-parsers.sh`, `tests/test-autopilot-continue.sh` + safety-guard additions.

### Changed

- **AASC determinism hook promoted to enforce (`on`) by default.** After dogfood51/52 (14 real conformant eval reports → 0 false-trips) + a live `decision:block` de-risk (dogfood53: the block surfaced cleanly, the model handled it gracefully without thrash and was not pressured into fabricating a conformant line), the `SW_ACCEPT_SET_CONFORMANCE_MODE` default flipped `metric-only` → `on`. Set `metric-only` to observe-only or `off` to disable. Non-breaking: this is the initial default of a new feature with a kill switch, not a change to any prior released behaviour.

### Fixed

- **AASC hook robustness (dogfood51/52 confirmation + pre-release audit).** The `## Accept-set sweep` header is now matched at any hash depth (`#{1,6}`) and case-insensitively (was `## `-only / case-sensitive, which let a mis-leveled / mis-cased header skip a whole report); fields parse whitespace-bounded (tab-separated lines no longer dodge); the line selector is order-independent; an off-grammar boundary label emits a stderr WARN (not a block). The **P3 corpus floor was demoted from blocking to advisory** — corpus-size is a weak depth proxy and flooring it false-tripped legitimately-thin-but-conformant sweeps; the astral check (P2) is the real A/U depth gate.
- **EC-taxonomy uniformity.** `evidence-channels.md` no longer carries the stale "MR-KEYFAITH is ASSUMED / advisory-only" posture (folded into the same two-tier oracle-authoritative FAIL gate as the other relations, matching the `ac-evaluator` twins + harness doc); **CT-AASC-10** now also scans `evidence-channels.md` so the sibling-artifact uniformity rule is mechanized.

### Verification

- `bash tests/test-skill-contracts.sh` **852/852** (+ **CT-AASC-1..14**, **CT-DECONTAM-1**, **CT-EV-PANEL-ROBUST**, twin byte-identity **CT-EV-MODEL-1**); `bash tests/test-accept-set-verify.sh` **32/32**; `bash tests/test-path-consistency.sh` **144/144**; `shellcheck --severity=warning` clean on the new hook + tests; `ac-evaluator` / `ac-evaluator-hi` bodies byte-identical sans `name:` / `model:`. `plugin.json` `8.5.0` == newest CHANGELOG `[8.5.0]` (CT-MODE-14), real ISO date (CT-MODE-13).
- **Dogfood evidence.** dogfood52 (a leak-inviting strict-numeric + keyed + canonical/delegating subject built on the exact historically-failing traps) → the harness produced correct strict artifacts on every trap (impl explicitly avoided the `\d`-without-`re.ASCII` Unicode-digit trap), the AASC chain fired on all 3 tickets with genuinely-executed astral-inclusive sweeps and zero stand-downs, and an independent re-probe found 0 leaks; dogfood53 → a live `decision:block` on a fault-injected non-conformant report, handled gracefully.
- **Additive + kill-switched.** `constraints.accept_set_conformance: off` (or `SW_ACCEPT_SET_CONFORMANCE_MODE=off`) reverts byte-for-byte to the pre-v8.5.0 read-only strictness reasoning; the determinism hook is fail-OPEN (exit code always 0) and structurally cannot remove a catch the prior harness had. The safety/state hardening guards ship at their documented defaults with `SW_*_MODE` kill switches.

## [8.4.2] — 2026-06-11

**TL;DR.** Fixes a manual-mode dead-end on the `/autopilot` path. A brief created with `chain: off` (manual mode) intentionally never receives a per-ticket `autopilot-policy.yaml` (Step W-8 skips propagation), yet `/autopilot` Phase 1 step 3 used to `[WARN] ... only brief-level policy is in effect` and continue — after which the three per-ticket Policy guards (which have no brief-level fallback) aborted every ticket. `/autopilot` on a manual brief now hard-stops once at the entry with an actionable re-propagation directive, and `/brief`'s manual-flow guidance names the prerequisite before advertising the autopilot switch. Surfaced by the follow-up #2 live `/autopilot` validation; the original "`/create-ticket` policy-copy is broken" framing was a non-bug (W-8's manual skip is spec-correct and `[POLICY-PROPAGATION] skipped: brief mode=manual`-pinned) — the real defect was the downstream WARN-and-continue that stranded the run.

### Fixed

- **`/autopilot` on a manual-mode (`chain: off` / `mode: manual`) brief now hard-stops with an actionable directive instead of stranding every ticket.** `skills/autopilot/SKILL.md` Phase 1 step 3 previously emitted `[WARN] brief mode=manual but /autopilot was invoked; per-ticket autopilot-policy.yaml is absent (only brief-level policy is in effect).` and continued — but the per-ticket Pre-scout / Pre-impl / Pre-ship Policy guards read **only** `product_backlog/{ticket-dir}/autopilot-policy.yaml` with no brief-level fallback, so a manual brief (whose per-ticket policy is deliberately never propagated by Step W-8) aborted at the first guard on every ticket. It now prints `ERROR: Brief is in manual mode (chain: off); …` and stops once with `[AUTOPILOT-POLICY] gate=unexpected_error action=stop reason=brief_mode_manual` + `## Stop Reason` `tag: policy_gate_stop` (honored by the existing generic policy-gate-stop detector — no hook change), directing the user to re-run `/create-ticket` with the brief set to `chain: on` so the policy propagates, then re-run `/autopilot`. A parallel `## Error Handling` entry points to the same step.
- **`/brief` manual-flow guidance now names the re-propagation prerequisite.** `skills/brief/SKILL.md` Step 3 (`chain=off`) guidance previously advertised `/autopilot {slug}` as a switch-to-autopilot off-ramp the engine could not deliver natively; it now tells the user to first re-run `/create-ticket` with the brief set to `chain: on` (so each ticket dir receives `autopilot-policy.yaml`) before running `/autopilot`.

### Verification

- `bash tests/test-skill-contracts.sh` **826/826** (+**CT-MODE-15** autopilot manual-brief hard-stop: asserts `reason=brief_mode_manual` + `Re-run /create-ticket` present and the stranding `only brief-level policy is in effect` WARN removed; +**CT-MODE-16** brief Step 3 names the `re-run /create-ticket` prerequisite). `bash tests/test-path-consistency.sh` **144/144** (unchanged). `plugin.json` `8.4.2` == newest CHANGELOG `[8.4.2]` (CT-MODE-14), real ISO date (CT-MODE-13). No behavioral change to the supported `chain: on` auto path, to Step W-8's spec-correct manual skip (CT-MODE-12), to the per-ticket Policy guards (the early hard-stop makes them unreachable on the manual path — they stay byte-identical), or to the legacy `mode=auto` / `mode=manual` aliases (CT-MODE-1/3/8). Smaller-surface fix chosen over auto-re-propagating the policy inside `/autopilot` on a manual→auto switch, which would relax the manual/auto contract and is deferred as a separate feature.

## [8.4.1] — 2026-06-10

**TL;DR.** Activates the `doc-verifier` agent that v8.4.0 shipped but never spawned: `/audit` (Step 2) and `/refactor` (Phase 3 Step 6) now spawn `simple-workflow:doc-verifier` in parallel with their other read-only reviewers, so the EC-SELFDOC doc/interface-truthfulness check runs as an independent agent at review time — not only as the inline `ac-evaluator` duty. The cross-agent EC-SELFDOC handoff is now demonstrated at runtime.

### Added

- **`doc-verifier` spawn-wiring in `/audit` + `/refactor`** — both review orchestrators now invoke `simple-workflow:doc-verifier` (sonnet, read-only, scratch-only exec) in parallel with `code-reviewer` (and `security-scanner` for `/audit`) when `constraints.selfdoc_verification` is active AND the change touches a documentation / advertised-interface surface (a `README` / `*.md` / `--help` / man-page, or a Gate 9 R3 `DESCRIPTION-MATCHES-BEHAVIOR` / R4 `DOC/INTERFACE TRUTHFULNESS` AC). doc-verifier RUNs the unit's advertised examples / boundary claims against the real build under the `.simple-workflow/scratch/` carve-out and reports EC-SELFDOC drift (class A) or advertised-vs-enforced boundary mismatch (class E); a non-reproducing example or advertised≠enforced boundary is a Critical that feeds the `/audit` Step 3 aggregation and the `/refactor` Step 7 loop-exit tally, while an unrunnable build is a fail-open `PASS-WITH-CAVEATS`. `agents/doc-verifier.md` gains a `## When spawned (input contract)` section (the spawner inlines the changed files, the build location, the report path, and the ticket's Gate 9 R3 / R4 rows). Both the `/audit` reviewer table + Binding-rules and the `/refactor` agent table + Binding-rules name doc-verifier. Guarded by **CT-EV-SELFDOC-6**.

### Changed

- **`constraints.selfdoc_verification: off` now also skips the spawn** — `autopilot-policy-reference.md` documents that `off` skips the `/audit` + `/refactor` doc-verifier spawn in addition to standing down the inline `ac-evaluator` EC-SELFDOC duty. No new kill switch; the existing one gates the spawn. doc-verifier is intentionally wired into the two review skills only (`/audit`, `/refactor`) — the other Skill-bearing spawners (`/impl` Step 15 grades EC-SELFDOC inline via the `ac-evaluator` duty; `/create-ticket` is authoring-side) do not spawn it.

### Verification

- `bash tests/test-skill-contracts.sh` (prior + **CT-EV-SELFDOC-6**), `bash tests/test-path-consistency.sh` unchanged (`doc-verifier` was already registered); full `run-all.sh` ALL SUITES PASSED. `plugin.json` `8.4.1` == newest CHANGELOG `[8.4.1]` (CT-MODE-14), real ISO date (CT-MODE-13). Additive + kill-switched: with `constraints.selfdoc_verification: off`, or no documentation / advertised-interface surface touched, neither review skill spawns doc-verifier — byte-for-byte the pre-v8.4.1 review flow.

## [8.4.0] — 2026-06-09

**TL;DR.** Phase A + B + C of the *failure-class-coverage by default* line. **Phase A** splits the verification machinery's **evidence-independence floor** off the Size×risk depth axis (**M3**) so the independence that beat a max-effort human build in the 2026-06-02 / 06-09 A/B is no longer gated behind blast-radius, and adds per-AC `[ORACLE-AUDIT]` observability (**M8**, partial). Concretely: `evidence_floor = max(tier floor, AC-shape floor)` — ANY behavioral AC now floors at `+1-independent` regardless of Size, so a routine `standard`-tier ticket with a behavioral AC has its single evaluator establish one independent channel beyond the natural one; Gate 7's adversarial-input requirement broadens from computational-only to **every external-input boundary (computational or behavioral)**; and a tier-independent **strongest-derivation oracle** preference (first-principles over sibling library, recorded as `oracle-kind`) applies at every tier. Depth is untouched — Size still gates rounds / `/audit` third-pass / the 3-spawn fan-out — so routine S/M spawn count and wall-clock are unchanged; only the evidence bar rises, by one channel, in-agent. **Phase B** turns two more defaults on. The *failure-class eval panel*: the evaluator now grades through a fixed five-lens set (`L-CORRECTNESS` / `L-ROBUSTNESS` / `L-CONTRACT-CONFORMANCE` / `L-UNIFORMITY` / `L-SIMPLICITY`) instead of a single all-purpose pass — at `standard` one evaluator runs `>=2` lenses sequentially with NO added spawn, at `exhaustive` the existing 3-spawn fan-out carries them — emitting a per-ticket `[EVAL-PANEL]` line; and **Gate 9: Failure-Class Coverage**, an authoring-side gate making AC derivation coverage-driven by forcing, per Scope-touched external boundary, a four-row failure-class matrix (full-domain invariant / hostile + bounded termination / description-matches-behavior / doc-interface truthfulness) each resolved to `>=1` AC or a justified `n/a`. Both carry kill switches (`constraints.eval_panel`, `constraints.failure_class_coverage`) and do not fire on trivial single-unit / internal-helper-only tickets. **Phase C** completes the failure-class surface: a new `EC-SELFDOC` evidence channel + a read-only `doc-verifier` agent (classes A/E — the unit's own docstring / `--help` / advertised boundary RUN against the real build and diffed), a canonical **Gate 10: Peer-Set Uniformity** forcing one error-convention / envelope / vocabulary / wrapper AC across a `>=2`-peer set (class D), a **refute-then-synthesize merge** replacing the majority-merge so a lone non-critical FAIL survives unless a sibling refutes it (no more silent demotion), and a **Gate 9 R1 round-trip-losslessness cue** that closes the persistence-format strength axis a 2-subject dogfood A/B found a max-effort build still led on. Every Phase-C mechanism is kill-switched (`constraints.peer_uniformity` / `constraints.selfdoc_verification` / `constraints.refute_merge`).

**Migration (non-byte-identical default change).** Unlike v8.3.1, a routine `standard`-tier ticket that carries a behavioral AC is **no longer byte-identical to pre-v8.3.0**: its `evidence_floor` rises `EC-STATIC+natural → +1-independent`, and a behavioral AC on external/untrusted input now requires adversarial / non-finite / malformed coverage. To restore the prior behaviour per brief, set `constraints.independent_evidence: off` in `{ticket-dir}/autopilot-policy.yaml` (drops the AC-shape floor and the Gate 8 requirement) and/or `constraints.oracle_verification: off` (drops Gate 7 including the broadened adversarial trigger). Both default to `auto` (active). Structural-only tickets, and `thorough` / `exhaustive` tickets, are unchanged (the `max()` is monotone — it only ever RAISES the floor).

Phase B additionally turns the **failure-class eval panel** and **Gate 9 failure-class coverage** on by default. A non-trivial ticket (`>=2` source units or `>=1` behavioral AC) is now graded through `>=2` sequential evaluator lenses and emits a per-ticket `[EVAL-PANEL]` stderr line; a ticket touching an external boundary must carry a `#### Failure-Class Coverage (Gate 9)` matrix. Set `constraints.eval_panel: off` to restore the single all-purpose evaluator pass (drops the panel + the `[EVAL-PANEL]` line; `[ORACLE-AUDIT]` still emits) and `constraints.failure_class_coverage: off` to restore feature-driven AC derivation (Gate 9 graded `n/a` ticket-wide). Both default to `auto`; a trivial single-unit structural-only ticket and an internal-helper-only ticket are unaffected (panel OFF / Gate 9 `n/a` by the auto trigger).

Phase C adds three more kill-switched defaults. The **refute-then-synthesize merge** flips a merge DEFAULT on `exhaustive` (3-verifier) tickets: a lone non-critical FAIL one verifier raises now SURVIVES unless a sibling refutes it, instead of being silently demoted to PASS for lack of a second independent FAIL — so an `exhaustive` ticket may now surface more FAIL rounds / Generator iterations. Set `constraints.refute_merge: off` to restore the exact prior majority-merge (and its `[AC-EVAL-MAJORITY]` stderr line). `constraints.peer_uniformity: off` drops Gate 10 (no unified-convention AC required); `constraints.selfdoc_verification: off` stands down the `EC-SELFDOC` channel + `doc-verifier` (Gate 9 R3/R4 fall back to prose). All three default to `auto`. A single-unit ticket (no peer set), a structural-only ticket, and any non-`exhaustive` ticket are unaffected by the respective mechanism. v8.5.0 stays reserved for the separately-tracked red-team pre-ship phase.

### Added

- **AC-shape evidence-independence floor (M3)** — `skills/impl/references/verification-depth.md` gains a `### AC-shape evidence-independence floor` subsection defining a second, Size-independent floor axis: `evidence_floor = max(tier floor, AC-shape floor)`, where any behavioral AC floors at `+1-independent` and a structural-only ticket stays `EC-STATIC+natural`. `/impl` Step 3a resolves the `max()` and emits the extended `[EVIDENCE-FLOOR] tier= shape= floor= source=` stderr line. Mirrored into Gate 8 (`ac-quality-criteria.md`), the `ac-evaluator` / `ac-evaluator-hi` evidence-floor handoff (byte-identical), the `planner` Gate 8 self-audit floor note, and the `constraints.independent_evidence` policy doc.
- **Strongest-derivation oracle + `oracle-kind` recording (M3)** — at every tier (not only `thorough` / `exhaustive`), a computational AC whose contract is derivable from a published spec SHOULD take its expected value from a first-principles oracle in preference to a sibling library; the evaluator records the `oracle-kind` (`first-principles | sibling | hand | none`) used. Wired into `verification-depth.md` and `agents/ac-evaluator.md` (+ `-hi`).
- **Per-AC `[ORACLE-AUDIT]` observability (M8, partial)** — `agents/ac-evaluator.md` (+ `-hi`) emits one `[ORACLE-AUDIT] ac= oracle-kind= channels= boundary-quantified=` line per computational / behavioral AC to stderr, unconditionally (even under each `off` kill switch); documented at `/impl` Step 15. This makes the otherwise-invisible per-AC evidence strength auditable in a dogfood run.
- **Default failure-class eval panel + `constraints.eval_panel` kill switch (M8)** — `skills/impl/references/ac-evaluator-orchestration.md` gains a `## Default failure-class panel` section promoting a fixed five-lens failure-class set (`L-CORRECTNESS`, `L-ROBUSTNESS`, `L-CONTRACT-CONFORMANCE`, `L-UNIFORMITY`, `L-SIMPLICITY`) to the DEFAULT eval shape, and `agents/ac-evaluator.md` (+ `-hi`, byte-identical) gains a `## Failure-class panel (default lenses)` body section. At `standard` a SINGLE `ac-evaluator` runs `>=2` lenses sequentially in one spawn (no added invocation); at `exhaustive` the existing 3-spawn fan-out carries the lens emphasis (the per-AC merge is the refute-then-synthesize merge that replaces the prior majority-merge — see `### Changed`). For the panel lenses the out-of-scope restriction is lifted so a lens MAY surface a failure-class coverage gap the planner dropped, reported as advisory `[MEDIUM]` coverage-gap Feedback (matching carve-outs in `ac-quality-criteria.md` `## Evaluator MUST NOT` and `ticket-evaluator.md`). Resolved at `/impl` Step 3a (auto = ON for `>=2` source units OR `>=1` behavioral AC; `on` forces; `off` reverts byte-for-byte to the single all-purpose pass), inlined as field `m` (`--- panel: ... ---`), with a per-ticket `[EVAL-PANEL]` emit (M8, conditional on the panel being active, beside the unconditional `[ORACLE-AUDIT]`) and an orchestrator `[EVAL-PANEL-MODE]` resolver emit. Mirrored into `autopilot-policy-reference.md` and `policy-template.md`. The `L-ROBUSTNESS` lens and Gate 9 R2 additionally require probing hostile KEYS — prototype-pollution / accessor keys (`__proto__`, `constructor`, `prototype`), colliding / empty keys — where a unit builds a structure from untrusted input; this adversarial-key vector was added after a 2026-06-09 dogfood A/B (a `csvjson` CSV↔JSON library) found the default panel missed a `__proto__` header-column silent-data-loss its value-only vectors never reached (guarded by `CT-EV-PANEL-ROBUST-1`).
- **Gate 9: Failure-Class Coverage + `constraints.failure_class_coverage` kill switch** — `skills/create-ticket/references/ac-quality-criteria.md` gains `## Gate 9: Failure-Class Coverage`, an authoring-side gate that makes AC derivation coverage-driven: for each Scope-touched external boundary (public/exported function, CLI subcommand, endpoint, exported API symbol, file-format/wire-format, parser, or `>=2`-peer set) the planner emits a `#### Failure-Class Coverage (Gate 9)` matrix whose four rows (R1 full-domain invariant, R2 hostile + bounded termination + resource-cap, R3 description-matches-behavior, R4 doc/interface truthfulness) each resolve to `>=1` AC or a justified `n/a`. Gate 9 ENUMERATES which boundaries need an AC; Gate 7/8 GRADE it. A ticket touching no external boundary (internal-helper-only) is graded `n/a` (routine-ticket flood prevention), as is any ticket under `constraints.failure_class_coverage: off` (byte-for-byte revert to feature-driven AC derivation). Wired into `planner.md` (Pre-emit Self-Audit step 10), `ticket-evaluator.md` (Gate-Results row), the permanent `ticket-template.md` scaffold, and `autopilot-policy-reference.md` + `policy-template.md`. The gate-count carriers (`create-ticket/SKILL.md`, `agent-spawn-prompts.md`, `ticket-evaluator.md` L15) are bumped `Gates 1-8` → `Gates 1-9`.
- **Cat EV CT-EV-M3-1..3 + CT-EV-M8-1 + CT-EV-PANEL-1 + CT-EV-EVALPANEL-1/2 + CT-EV-PANEL-KS-1 + CT-EV-GATE9-1..3 + CT-EV-LENSSYNC-1 + CT-EV-PANEL-ROBUST-1** in `tests/test-skill-contracts.sh` — symmetry guards for the AC-shape floor (`AC-shape evidence-independence floor` + `max(tier floor, AC-shape floor)` across `verification-depth.md` + `/impl`; CT-EV-M3-1), the broadened Gate 7 trigger (a 7-file `computational or behavioral` guard across the gate + verifier + grader + author + both producers + producer rubric, mirroring the v8.3.1 CT-EV-10/11/12 cross-agent pattern; CT-EV-M3-2), the `oracle-kind` recording (canonical reference + verifier; CT-EV-M3-3), and the `[ORACLE-AUDIT]` emit (verifier + `/impl`; CT-EV-M8-1). Every new grep token is HEAD=0 (a `git stash` flips the assert to FAIL).
- **Phase C — `EC-SELFDOC` channel + `doc-verifier` agent, Gate 10 peer-uniformity, refute-then-synthesize merge, Gate 9 R1 round-trip cue** — a new evidence channel **`EC-SELFDOC`** (`skills/impl/references/evidence-channels.md`; a specialization layered on `EC-RUNTIME` — the unit's OWN docstring / `--help` / advertised boundary RUN against the real build and diffed, failing on description-vs-behavior drift (class A) or advertised≠enforced boundary (class E)) plus a new read-only **`agents/doc-verifier.md`** (scratch-only build/run Bash under the `.simple-workflow/scratch/` carve-out, fail-open with a Caveat) concretize Gate 9 R3/R4. A new canonical **`## Gate 10: Peer-Set Uniformity`** (`constraints.peer_uniformity`) forces a single error-convention / envelope / vocabulary / wrapper AC across any `>=2`-peer set (class D), wired through the `decomposer` `peer_set:` / `shared_conventions:` return hint, the `planner` Pre-emit Self-Audit step 11, `ticket-evaluator`, and the `ticket-template` scaffold (gate-count carriers bumped `Gates 1-9` → `Gates 1-10`). The **Gate 9 R1** row gains a **round-trip-losslessness cue** (`parse(serialize(x)) == x` across the value domain incl. empty-key / delimiter-in-value / unicode / `__proto__`-key) that closes the persistence-format strength gap the 2-subject dogfood A/B surfaced (the lone residual where a max-effort build still beat the default tier). New CTs **CT-EV-GATE10-1..3 + CT-EV-SELFDOC-1/2/4/5 + CT-EV-REFUTE-1..3 + CT-EV-GATE9-R1RT-1** (11), and `CT-EV-2` updated to the 6-party `binding_parties`; `doc-verifier` registered in `test-path-consistency.sh` (Group-C structural-validity + the `tools:` roster). `EC-SELFDOC` is exercised via the inline `ac-evaluator` / `-hi` `## Independent Evidence` duty, with `agents/doc-verifier.md` as the channel's dedicated verifier-side consumer under the `.simple-workflow/scratch/` exec carve-out.

### Changed

- **Gate 7 adversarial-input trigger broadened (M3)** — `skills/create-ticket/references/ac-quality-criteria.md` Gate 7 (and its mirrors in `agents/ac-evaluator.md` + `-hi` point 5, `agents/planner.md`, `agents/ticket-evaluator.md`, `agents/test-writer.md`, `agents/implementer.md`, and `skills/impl/references/test-authoring-guidance.md` rule 4) extends the adversarial / non-finite / out-of-range coverage requirement from *computational ACs on external input* to **every external-input boundary (computational or behavioral)**: a behavioral AC on external/untrusted input with zero hostile-input coverage is now a Gate 7 FAIL on that sub-requirement (the oracle + raw-value requirements stay computational-only). The `ticket-evaluator` Gate-7 drift-prevention bullet is amended to admit the behavioral-AC adversarial sub-requirement while keeping the oracle FAIL computational-only.
- **Gate 8 `standard`-floor carve-out removed for behavioral ACs (M3)** — the `standard`-tier "natural channel is sufficient" carve-out in Gate 8 (and its `autopilot-policy-reference.md` mirror) is removed for behavioral ACs: at `standard`, a behavioral AC's resolved `evidence_floor` is now `+1-independent` via the AC-shape floor. The authoring-time naming requirement (name ≥1 independent channel) is unchanged; this is a runtime evaluator obligation, adds no spawn, and is reverted by `constraints.independent_evidence: off`.
- **Gate 10: Peer-Set Uniformity (authoring-side, failure class D)** — when a ticket's `### Scope` creates a `>=2`-peer set (a family of analogous sibling tools / endpoints / subcommands / functions sharing one output surface), the planner now MUST assert `>=1` UNIFIED-convention AC over the set (single error convention / single success-envelope shape / single vocabulary per concept / single wrapper for repeated boilerplate, mechanically grep/AST-verifiable across every peer) or a one-line `n/a` justification under a new `#### Peer-Set Uniformity (Gate 10)` scaffold, and the `ticket-evaluator` FAILs an unresolved peer set. The `decomposer` surfaces a `peer_set:` / `shared_conventions:` hint forwarded to the planner. Kill switch: `constraints.peer_uniformity: off` grades Gate 10 `n/a` ticket-wide (byte-for-byte revert; absent / unknown → `auto`).
- **EC-SELFDOC evidence channel + `doc-verifier` agent + Gate 9 R3/R4 concretization** — a new EC-SELFDOC channel compares a unit's OWN declared contract (docstring / declared invariant / `--help` line / README worked-example / advertised size-or-range boundary) against observed runtime behaviour, RUN against the real build: advertised examples are reproduced and diffed, and advertised boundaries are probed with a FORBIDDEN value (must reject) + an ALLOWED value (must accept). Gate 9 rows R3 (description-vs-behavior) / R4 (doc/interface truthfulness) are concretized with this RUN-and-diff recipe; a new read-only `doc-verifier` agent (scratch-only build/run exec, fail-open with a Caveat) and the `ac-evaluator` / `ac-evaluator-hi` `## Independent Evidence` duty consume it. Kill switch: `constraints.selfdoc_verification: off` stands the channel + agent down (other behavioral channels unaffected; R3/R4 fall back to pre-v8.4.0 prose — byte-for-byte revert; absent / unknown → `auto`).
- **Refute-then-synthesize merge replaces the silently-demoting majority-merge** (`exhaustive` multi-verifier branch): a non-critical `FAIL` raised by any one valid verifier now survives as `FAIL` unless every other valid verifier refutes it (independently rendered `PASS` / `PASS-WITH-CAVEATS` on the same AC — computed from the already-rendered verdicts, no re-spawn, no firewall break). A lone reproducing non-critical FAIL is no longer demoted to `PASS`, closing the Phase-B gap where a real defect one verifier caught was silently dropped. CRITICAL-not-voted-away, the `valid < 2` quorum, and the severity ladder are unchanged. Migration / kill switch: `constraints.refute_merge: off` restores the prior majority-merge byte-for-byte (a non-critical FAIL then needs `>=2` verifiers); absent / unknown → `auto` (active).

### Verification

- `bash tests/test-skill-contracts.sh` 821/821 (801 baseline + 9 Phase-B + the dogfood-hardening `CT-EV-PANEL-ROBUST-1` + 11 Phase-C CTs = 821), `bash tests/test-path-consistency.sh` 144/144 (+2 `doc-verifier` Group-C / `tools:`-roster assertions); both exit 0; full `run-all.sh` ALL SUITES PASSED. `plugin.json` `8.4.0` == newest CHANGELOG `[8.4.0]` (CT-MODE-14), real ISO date (CT-MODE-13). The `ac-evaluator` ↔ `ac-evaluator-hi` byte-identical-body invariant (CT-EV-MODEL-1) holds across all Phase-C paired edits (EC-SELFDOC duty + refute cue + the `### Refute-then-synthesize merge` rename). **Dogfood A/B**: 2 subjects (`csvjson` converter library + `kv` stateful CLI) generated through the default tier vs a spec-only max-effort build — the default failure-class panel fired always-on, the adversarial-key hardening generalized (kind #1 shipped a `__proto__` bug, kind #2 did not), and Phase C's R1 round-trip cue closed the persistence-format strength axis (the default tier round-trips an `=`-bearing / newline / unicode value losslessly through its export path).
- New **CT-EV-M3-1..3 + CT-EV-M8-1 + CT-EV-PANEL-1 + CT-EV-EVALPANEL-1/2 + CT-EV-PANEL-KS-1 + CT-EV-GATE9-1..3 + CT-EV-LENSSYNC-1 + CT-EV-PANEL-ROBUST-1** pass; each new grep token (`AC-shape evidence-independence floor`, `max(tier floor, AC-shape floor)`, `external-input boundary (computational or behavioral)`, `computational or behavioral`, `oracle-kind`, `[ORACLE-AUDIT]`, plus Phase B's `L-CORRECTNESS`, `L-ROBUSTNESS`, `L-CONTRACT-CONFORMANCE`, `L-UNIFORMITY`, `L-SIMPLICITY`, `[EVAL-PANEL]`, `[EVAL-PANEL-MODE]`, `--- panel:`, `constraints.eval_panel`, `eval_panel`, `coverage-gap finder`, `Gate 9: Failure-Class Coverage`, `constraints.failure_class_coverage`, `#### Failure-Class Coverage (Gate 9)`, `R1 FULL-DOMAIN INVARIANT`, `prototype-pollution`) is net-new vs the working tree (a revert flips its assert to FAIL) — EXCEPT `CT-EV-LENSSYNC-1`, whose matched lens token pre-exists and whose assertion value is the impl↔orchestration field-l SYMMETRY (not a net-new token), and the `Gates 1-8`→`Gates 1-9` carrier bumps guarded by the existing CT-EV-9. The `ac-evaluator` ↔ `ac-evaluator-hi` byte-identical-body invariant (CT-EV-MODEL-1) holds — every body edit was mirrored verbatim. Every v8.3.x contract is intact (CT-EV-1..14, CT-EV-MODEL-1..4, CT-AR-11 `adversarial`, CT-EV-4/5/7 floor + kill-switch wiring). The feature is additive and kill-switched: a structural-only routine ticket resolves `evidence_floor=EC-STATIC+natural` (no change), and each `constraints.<x>: off` restores the pre-v8.4.0 path.

## [8.3.1] — 2026-06-04

**TL;DR.** A fail-open, criticality-gated refinement of v8.3.0's M1 (Gate 8 + the `evidence_floor` ladder) and M5 (criticality floor) — the "Wave A" verification-assurance pass that closes the main residual lead a 2026-06-02 A/B found a human-directed max-effort build still held over the harness. It does NOT add a gate; it sharpens what the EXISTING `thorough` / `exhaustive` floor demands for a **standard-backed computational** AC: **(H1)** the oracle evidence must be ≥2 mutually-validated oracles with ≥1 derived from first principles (the spec formula, no library); **(H2)** un-defers committed seeded fuzz — a fixed-seed property-fuzz loop becomes a depth-gated MUST, not an encouragement; **(H3)** `EC-DIFFERENTIAL` is re-specced to algorithm-vs-algorithm where a second independent algorithm exists (membership is necessary-not-sufficient). **(H13)** ships `skills/impl/references/independent-oracle-harness.md`, the copyable gold-standard four-part oracle module (first-principles block + independent-library block + seeded PRNG + second-algorithm differential helper), wired into the producer rubric, the taxonomy, and the verifier. **(H12)** tightens the M5 criticality cue set (color-science cues + a shared-core / shared-input-boundary trigger) so the class of ACs this rigor targets reliably escalates — the catch only fires if classification fires. Every requirement engages ONLY at the `thorough` / `exhaustive` evidence_floor (already M5-criticality-gated) and ONLY where a published spec / second oracle / second algorithm exists; otherwise it degrades to the single natural channel + a Caveat (never a block). A routine S/M-conservative ticket stays byte-identical to v8.3.0; the `standard` floor and every `constraints.<x>: off` path are unchanged. `v8.4.0` remains reserved for M3 + M4.

### Added

- **`skills/impl/references/independent-oracle-harness.md`** (H13) — a new reference encoding the gold-standard four-part independent-oracle module: (a) a from-first-principles formula block (the published spec, no library), (b) an independent-library oracle block (a library that does not share the implementation's core), (c) a seeded `mulberry32` PRNG for reproducible fuzz, and (d) a second-algorithm differential helper — with a worked color/WCAG example transcribed from the A/B reference build. It is read at authoring time and is never a runtime gate. Linked from `test-authoring-guidance.md`, `evidence-channels.md`, `agents/ac-evaluator.md` (+ `ac-evaluator-hi.md`), `agents/test-writer.md`, and `agents/implementer.md`.
- **Multi-oracle mutual validation (H1)** — Gate 7 in `skills/create-ticket/references/ac-quality-criteria.md` gains a depth-gated multi-oracle clause: at the `thorough` / `exhaustive` `evidence_floor`, a standard-backed computational AC's expected value must come from ≥2 oracles independent of the implementation's core, mutually-validated (they agree within an explicit tolerance before either is trusted), with ≥1 derived from first principles. A single oracle still suffices at `standard`. Mirrored into the `EC-ORACLE` definition (`evidence-channels.md`), the producer rubric rule 1 (`test-authoring-guidance.md`) + both producer agents (`implementer`, `test-writer`), the verifier (`ac-evaluator` `## Oracle Independence` point 1 + the V3 lens), and the planner step-8 / ticket-evaluator Gate-7-row authoring guidance.
- **Committed seeded fuzz un-deferred (H2)** — `test-authoring-guidance.md` rule 7 is promoted from "encouraged" to a depth-gated **MUST**: at `thorough` / `exhaustive` a computational AC must ship a committed, fixed-seed property-fuzz loop (reproducible PRNG, tier-scaled case count) over the input distribution, not only deterministic grids. Mirrored into the `EC-PROPERTY` definition, both producer agents, the verifier (`## Oracle Independence` point 5 + the V2/V3 lenses), and the planner/ticket-evaluator Gate-8 authoring guidance. (Closes the v8.2.1 seeded-fuzz deferral, now justified by the 2026-06-02 dogfood.)
- **Algorithm-vs-algorithm differential (H3)** — `EC-DIFFERENTIAL` is re-specced (in `evidence-channels.md`, Gate 7 of `ac-quality-criteria.md`, `test-authoring-guidance.md` rule 3, `agents/ac-evaluator.md` + the V2 lens, and `ac-evaluator-orchestration.md`): when a second INDEPENDENT algorithm for the same contract exists (e.g. CSS-MINDE vs chroma-clamping gamut mapping), the verification compares algorithm-vs-algorithm within tolerance — a membership / invariant check alone is necessary-not-sufficient because a wrong result can still be in-range.
- **`### Standard-backed computational evidence floor` subsection** in `skills/impl/references/verification-depth.md` — the single authoritative statement tying H1/H2/H3 to the `thorough` / `exhaustive` floor, with the fail-open degradation rule, placed without disturbing the pinned effects-ladder cells.
- **Cat EV CT-EV-10..14** in `tests/test-skill-contracts.sh` — H1 multi-oracle symmetry guard (`mutually-validated` across the full 9-file author→verify surface — canonical gate + taxonomy + producer rubric + both producers + planner author + ticket-evaluator grader + verifier + floor doc — plus `first-principles` at the two ends; CT-EV-10), H2 committed-seeded-fuzz symmetry guard (`fixed-seed` across 8 files; CT-EV-11), H3 algorithm-vs-algorithm symmetry guard (`algorithm-vs-algorithm` across 9 files; CT-EV-12), H13 harness file-exists + reference-wired (CT-EV-13), and the H12 criticality cue (`shared-core`; CT-EV-14). Every token is HEAD=0 (a `git stash` of the change flips the assert to FAIL). The symmetry guards include the `planner` author and `ticket-evaluator` grader cells so a future silent revert of either authoring surface cannot ship green.

### Changed

- **M5 criticality cue set widened (H12)** — the `## Criticality floor` cue list in `verification-depth.md` adds color-science cues (color-space / gamut / OKLab / luminance / chroma conversion) and a domain-independent **shared-core input-boundary** trigger: a computational AC that reads or must hold an invariant across a parser / validation / constant (e.g. an epsilon / range / gamut guard) shared with sibling tools floors `criticality=critical` even when its surface domain is otherwise routine. This is the exact wrong-but-self-consistent shared-core defect class the floor targets; the trigger only RAISES the tier, never lowers it.

### Verification

- `bash tests/test-skill-contracts.sh` 797/797, `bash tests/test-path-consistency.sh` 142/142; full sweep 34/34 suites.
- New **CT-EV-10..14** all pass; each new grep token (`mutually-validated`, `first-principles`, `fixed-seed`, `algorithm-vs-algorithm`, `independent-oracle-harness.md`, `shared-core`) is HEAD=0 — a `git stash` flips the corresponding assert to FAIL, `git stash pop` restores PASS. Every v8.3.0 contract is intact: Gate 7's `## Gate 7: Oracle Independence` section (CT-AR-1/4/8), the `## Verification Lens (high-assurance handoff)` / `multi-verifier` DEPTH-8 anchors, the CT-EV-1..9 + CT-EV-MODEL-1..4 family, the `parse-accepted` / `sibling-guard` / `outputSchema` CT-AR-12/13/14 tokens, the `Gates 1-8` carriers, and the `ac-evaluator` ↔ `ac-evaluator-hi` byte-identical-body invariant (every body edit was mirrored). The feature is additive and fail-open: a routine S/M-conservative ticket resolves `evidence_floor=EC-STATIC+natural` (no multi-oracle, no fuzz mandate, no differential), each `constraints.<x>: off` makes its mechanism a no-op, and the requirements degrade to the natural channel + a Caveat where no published spec / second oracle / second algorithm exists.

## [8.3.0] — 2026-06-02

**TL;DR.** First of three additive, fail-open minor releases bringing the autonomous Generator-Evaluator harness toward parity with a human-directed max-effort session, after an A/B on a color-math MCP server lost on correctness/safety axes. This release ships the shared scaffolding (**Phase 0**) plus the first two measures. **Phase 0**: a new canonical **Evidence-Channel Taxonomy** (`skills/impl/references/evidence-channels.md`) — five evidence channels `EC-ORACLE` / `EC-DIFFERENTIAL` / `EC-PROPERTY` / `EC-RUNTIME` / `EC-STATIC`, five reserved red-team attack classes `RT-FUZZ` / `RT-ABUSE` / `RT-MALFORMED` / `RT-EXHAUST` / `RT-CONCURRENCY` (M2, v8.5.0), and the irreversibility-axis cue list (M5) — cited by ID, never paraphrased; and a `/impl` Step 3a resolved struct `{depth_tier, criticality, evidence_floor, evaluator_model, redteam_budget, domain_set}` that for a routine S/M-conservative ticket resolves to today's values (a byte-identical no-op). **M5 (effort/model allocation by criticality)**: a single `criticality = blast_radius(Size) × irreversibility` scalar, a new **irreversibility axis** (an AC verifying writes / network / money / destructive / external-system side-effects floors `criticality=critical` even at Size S), and an evaluator-model bump (sonnet→opus at `critical`/`exhaustive`) realized via the byte-identical sibling agent `agents/ac-evaluator-hi.md` (the Agent JSONSchema rejects a per-spawn `model:` override). **M1 (evidence-channel independence)**: a new **Gate 8 "Independent Evidence"** generalizing Gate 7's oracle requirement to every *behavioral* AC (Gate 7 stays a literal, intact section as the strongest `EC-ORACLE` sub-case), the three multi-verifier lenses re-specced from attitude-diverse to **evidence-mode-diverse**, and an `evidence_floor` ladder (standard = the AC's natural channel; thorough = +1 independent channel; exhaustive = ≥2). Default `auto` keeps a routine ticket byte-identical; the per-brief kill switches `constraints.independent_evidence: off`, `constraints.irreversibility_floor: off`, and the master `constraints.verification_depth: off` each restore prior behaviour. Red-team budget is recorded into the struct but has no consumer until M2 (v8.5.0).

### Added

- **Evidence-Channel Taxonomy** — new canonical reference `skills/impl/references/evidence-channels.md` (`binding_parties: [planner, ticket-evaluator, implementer, test-writer, ac-evaluator]`): the five `EC-*` evidence channels (each with a one-line "what makes this independent of the SUT"), the five reserved `RT-*` red-team attack classes (consumed by M2 in v8.5.0), the M5 irreversibility-axis cue list, and the channel-independence + natural-channel-sufficiency rule. The `RT-` prefix is deliberate — attack classes never share the acceptance-criterion `AC-` namespace (a sonnet evaluator would otherwise conflate the two in one prompt).
- **Gate 8: Independent Evidence (behavioral ACs)** in `skills/create-ticket/references/ac-quality-criteria.md` — every behavioral AC (PASS/FAIL hinges on observable runtime behaviour) must name ≥1 evidence channel independent of the implementation's internals (`EC-ORACLE` / `EC-DIFFERENTIAL` / `EC-PROPERTY` / `EC-RUNTIME`) or be rewritten as a structural AC (`EC-STATIC`). Gate 7 (oracle independence for computational ACs) is the strongest `EC-ORACLE` sub-case and is UNCHANGED — its section, prose, and CT-AR tests are intact. A natural-channel-sufficiency clause and an Evaluator-MUST-NOT anti-over-fire bullet keep a routine ticket byte-identical (a black-box CLI assertion is already `EC-RUNTIME`). Wired into the `planner` Pre-emit Self-Audit (new step 9), the `ticket-evaluator` Result template (new "Independent Evidence" gate row) and its L15 gate enumeration, and the `Planner MUST` / `Evaluator MUST NOT` lists. Kill switch `constraints.independent_evidence: off`.
- **`## Independent Evidence (behavioral ACs)`** section in `agents/ac-evaluator.md` — the verifier-side counterpart, defining the five channels, the `evidence_floor` handoff, the over-fire guard, and the `independent_evidence: off` fallback; wired symmetrically into `/impl` Step 15 and `skills/impl/references/ac-evaluator-orchestration.md` (the `## Independent-evidence channels` section).
- **Evidence-mode multi-verifier lenses** — the three exhaustive-tier `ac-evaluator` lenses are re-specced from attitude-diverse (correctness / adversarial-refute / reproduction-edge) to **evidence-mode-diverse**: V1 `EC-RUNTIME` (real public/protocol boundary), V2 `EC-DIFFERENTIAL`-or-`EC-PROPERTY` (reference cross-check or seeded property sweep), V3 `EC-ORACLE` + a parse-accepted-then-overflows fuzz vector — so the three verifiers no longer share the single-source blind spot of reading the same diff and tests. Renamed across all five non-CHANGELOG sites (orchestration directives + field-`l` template, `verification-depth.md` ladder + prose, `autopilot-policy-reference.md` summary table, the canonical `ac-evaluator.md` lens definitions, `/impl` Step 15 dispatch).
- **`evidence_floor` ladder** in `skills/impl/references/verification-depth.md` (new column) and resolved at `/impl` Step 3a: standard = `EC-STATIC` + the AC's natural channel (no extra channel — byte-identical to pre-v8.3.0), thorough = +1 independent channel, exhaustive = ≥2. Emits `[EVIDENCE-FLOOR] …` to stderr and inlines `Evidence floor: {…}` into every `ac-evaluator` spawn prompt (parallel to `Oracle verification:`). The floor only RAISES channels, never lowers.
- **Criticality scalar + irreversibility axis (M5)** in `skills/impl/references/verification-depth.md` — `criticality = blast_radius(Size) × irreversibility ∈ {routine, critical}`, resolved once at `/impl` Step 3a (`[CRITICALITY] …` stderr). The new irreversibility axis floors `criticality=critical` when an AC verifies an irreversible side-effect (writes / network / money / destructive / external-system) even on a Size-S ticket; dedicated kill switch `constraints.irreversibility_floor: off` (removes only the new axis).
- **Evaluator-model allocation (M5)** — the resolved `evaluator_model` goes sonnet→opus at `criticality=critical` OR the `exhaustive` tier, symmetric with the generator-side `constraints.sonnet_size_threshold`. Because the Agent tool's JSONSchema rejects a per-invocation `model:` override (the Strategy-B limitation that already forces the soft turn budget), the opus path is realized by a dedicated agent file **`agents/ac-evaluator-hi.md`** (`model: opus`), spawned by `/impl` Step 15 when `EVALUATOR_MODEL == opus`. Its body is byte-identical to `agents/ac-evaluator.md` except its `name:` and `model:` frontmatter lines (the `name:` necessarily differs so the agent is independently resolvable as `simple-workflow:ac-evaluator-hi`), guarded mechanically by CT-EV-MODEL-1. Emits `[EVALUATOR-MODEL] …`. Per graft #10 this two-file workaround should be empirically pre-verified in a v8.3 dogfood; if a per-spawn `model:` override turns out to be accepted, it can later collapse to one file.
- **Red-team budget (M5, forward-declared)** — `redteam_budget` (`full` at `criticality=critical`/`exhaustive`, else `0`) is recorded into the Step 3a struct and emitted as `[REDTEAM-BUDGET] …`, but has no consumer until the M2 red-team phase (v8.5.0); it is a pure no-op in v8.3.0.
- **Inert `constraints.*` knobs** — `constraints.independent_evidence` and `constraints.irreversibility_floor` documented in `skills/create-ticket/references/autopilot-policy-reference.md` and emitted in `skills/brief/references/policy-template.md`, both `auto` (active) by default with 3-layer fail-open (field absent / policy absent / unknown value → `auto`).
- **Cat EV** (CT-EV-1..9) and **Cat EV-MODEL** (CT-EV-MODEL-1..4) contract tests in `tests/test-skill-contracts.sh` — a fresh drift-guard category (NOT an extension of the doubly-overloaded Cat AR): Gate 8 section + Gate 7 intact (CT-EV-1), the taxonomy file + channel IDs + binding_parties (CT-EV-2), the evidence-mode lens tokens in both orchestration and the agent (CT-EV-3), the `evidence_floor` wiring (CT-EV-4), the Gate 8 caller↔callee symmetry guard (CT-EV-5, mirroring CT-AR-8), the authoring-side planner-step-9 + ticket-evaluator-row symmetry (CT-EV-6), the `independent_evidence` kill-switch surfaces (CT-EV-7), the `RT-*` namespace guard with zero AC-prefixed attack tokens (CT-EV-8), the `Gates 1-8` carriers (CT-EV-9), the `ac-evaluator-hi` byte-identical-body guard (CT-EV-MODEL-1), the evaluator-model wiring (CT-EV-MODEL-2), the irreversibility-axis three-file symmetry (CT-EV-MODEL-3), and the criticality scalar (CT-EV-MODEL-4). `tests/test-path-consistency.sh` registers `ac-evaluator-hi` in the Group-C structural-validity and `tools:`-allowlist enumerations.

### Changed

- Loose "Gates 1-7" planner-facing pointers now read "Gates 1-8" so Gate 8 reaches the authoring path (`skills/create-ticket/SKILL.md`, `skills/create-ticket/references/agent-spawn-prompts.md` — both occurrences, `agents/ticket-evaluator.md` L15). The planner's "All four self-audits …" recap line is rewritten count-free (a gate-name list, no English numeral) so later releases append a gate name without re-incrementing a hand-counted number.
- `/impl` Step 3a now also resolves the criticality scalar, `evaluator_model`, `evidence_floor`, and (forward-declared) `redteam_budget` into the `phases.impl.*` struct; Step 15 selects `simple-workflow:ac-evaluator-hi` when `EVALUATOR_MODEL == opus` and carries the `Evidence floor:` directive to the `ac-evaluator`. The `verification-depth.md` Effects-ladder lead-in is rewritten count-free and names the resolved struct.

### Verification

- `bash tests/test-skill-contracts.sh` 792/792, `bash tests/test-path-consistency.sh` 142/142; full sweep 34/34 suites.
- New **Cat EV** (CT-EV-1..9) and **Cat EV-MODEL** (CT-EV-MODEL-1..4) all pass; each new grep token is HEAD=0 (a `git stash` of the change flips the corresponding assert to FAIL). Existing **Cat AR** (Gate 7), **Cat AQ**, and **DEPTH-1..11** are unaffected — Gate 7's `## Gate 7: Oracle Independence` section and the `## Verification Lens (high-assurance handoff)` / `multi-verifier` DEPTH-8 anchors are untouched. The feature is additive and fail-open: a routine S/M-conservative ticket resolves `criticality=routine`, `evidence_floor=EC-STATIC+natural`, `evaluator_model=sonnet`, `redteam_budget=0` — byte-identical to pre-v8.3.0 — and each `constraints.<x>: off` makes its mechanism a no-op.

## [8.2.0] — 2026-06-01

**TL;DR.** A new verification feature line that closes the oracle-circularity defect class — a generated test that re-measures with the implementation's own rounded value, so it passes even when the code is wrong (the defect that let a dogfood WCAG contrast solver falsely report a target as met past a green 93-test suite). Five composable, additive, fail-open pieces: (1) **Gate 7 "Oracle Independence"** requires every *computational* AC (one whose PASS/FAIL hinges on a computed numeric/algorithmic value) to name an oracle independent of the implementation and be checked on the raw, pre-rounding value with an explicit tolerance; (2) the `ac-evaluator` now derives that oracle value itself (a green project suite is necessary-but-not-sufficient for a computational AC) with a carve-out to write throwaway probes under the gitignored `.simple-workflow/scratch/`; (3) a positive `test-authoring-guidance.md` rubric wired into the `implementer` and `test-writer`; (4) tautological rule **R4 (oracle circularity)**; and (5) a **criticality floor** that raises the verification-depth tier to `thorough` for a critical-domain computational AC even on a small/conservative ticket. Per-brief kill switch `constraints.oracle_verification: off` restores pre-v8.2.0 behaviour; for a non-computational ticket the whole feature is a no-op. The adversarial-input requirement additionally demands at least one *parse-accepted-then-overflows* vector (a value the parser ACCEPTS that yields a non-finite / out-of-range intermediate, e.g. `oklch(0.5 1e400 30)` → Infinity chroma — not just parse-rejected `NaN` / `Infinity` keyword tokens) and a **sibling-guard requirement** that forces an input-validation guard across every tool sharing an input boundary; together they close a dogfood residual where an unguarded `gamut_map` sibling still hung on `oklch(0.5 1e400 30)` while the suite passed green on rejected-token cases.

### Added

- **Gate 7: Oracle Independence (computational ACs)** in `skills/create-ticket/references/ac-quality-criteria.md` — defines the computational-AC classifier, the independent-oracle + raw-value-tolerance requirement, the no-oracle fallback (raw-value + property/invariant + adversarial coverage), an adversarial / non-finite / out-of-range coverage requirement for computational ACs on externally-fed functions (catching DoS hangs and bad-input contract violations, not just wrong values on good input), and the `constraints.oracle_verification: off` kill switch. Wired into the `planner` Pre-emit Self-Audit (new step 8), the `ticket-evaluator` Result template (new "Oracle Independence" gate row), and the `Planner MUST` / `Evaluator MUST NOT` lists.
- **`## Oracle Independence (computational ACs)`** section in `agents/ac-evaluator.md` — the evaluator independently derives ≥1 expected value from an oracle that does not share the implementation's core and compares the raw, pre-rounding output with an explicit tolerance; "project tests green" is necessary-but-not-sufficient for a computational AC. Applies in single, partition, and multi-verifier modes; wired symmetrically into `/impl` Step 15 and `skills/impl/references/ac-evaluator-orchestration.md`.
- **Oracle-probe carve-out** in `agents/ac-evaluator.md` — the otherwise-blanket "no scratch scripts" ban now permits a throwaway independent-oracle probe under the gitignored `.simple-workflow/scratch/` (never the project tree), since catching oracle circularity requires the evaluator to derive an expected value itself.
- **Tautological rule R4 (Oracle Circularity)** in `skills/impl/references/tautological-assertion-rules.md` — flags a numeric assertion whose expected value is produced by the system under test or by re-applying the implementation's own rounding/formatting (e.g. re-thresholding a rounded result field). The `ac-evaluator` now loads four canonical rules (R1-R4).
- **`skills/impl/references/test-authoring-guidance.md`** (new) — a positive test-authoring rubric (independent oracle; raw-before-rounded + tolerance; property/invariant; adversarial/non-finite/out-of-range inputs by default; spec-completeness; black-box > white-box; seeded fuzz), referenced from `agents/implementer.md` and `agents/test-writer.md`.
- **Criticality floor** in `skills/impl/references/verification-depth.md` — a computational AC in a critical domain (accessibility / security / money / data-integrity / standard-compliance) floors the resolved depth tier at `thorough` regardless of Size × `risk_tolerance`, forcing `/audit`'s skeptical third-pass even on an S/conservative ticket.
- **`constraints.oracle_verification`** policy field (`auto` default / `off`) documented in `skills/create-ticket/references/autopilot-policy-reference.md` and `skills/brief/references/policy-template.md`, consumed at `/impl` Step 3a.
- **Cat AR** contract tests (CT-AR-1..CT-AR-9) in `tests/test-skill-contracts.sh` drift-guarding the whole feature line, including a CT-AR-8 symmetry guard (oracle independence wired across `/impl` + orchestration + `ac-evaluator`, mirroring DEPTH-8).
- **Parse-accepted-overflow vector + sibling-guard hardening (Gate 7).** The adversarial-input requirement now demands at least one *parse-accepted-then-overflows* vector (a value the parser ACCEPTS that yields a non-finite / out-of-range intermediate, e.g. `oklch(0.5 1e400 30)` → Infinity chroma), NOT only parse-rejected `NaN` / `Infinity` keyword tokens that the parser rejects in ~0 ms at the door. A new **sibling-guard requirement** makes an input-validation guard (finiteness / range / gamut) required either in the SHARED input boundary or in EVERY sibling tool that accepts the same input class — a guard in one tool but absent from its analogous siblings is a Gate 7 FAIL (the `CLAUDE.md ## Modifications` sibling-artifact rule enforced at the AC level). Both requirements are wired symmetrically across the full author-and-verify path: Gate 7 in `ac-quality-criteria.md` (canonical), the producer rubric `test-authoring-guidance.md` (rule 4, "test BOTH classes" + a "Sibling-guard symmetry" paragraph), the two producer agents `agents/implementer.md` / `agents/test-writer.md` (inline rubric echo, so an author who does not open the full file still authors the class-(b) vector and the sibling guard), `agents/planner.md` (step 8d self-audit), `agents/ac-evaluator.md` (point 5, with a time-bounded watchdog probe under `.simple-workflow/scratch/` and a sibling-probe), `agents/ticket-evaluator.md` (Gate 7 grade row), and `verification-depth.md`'s criticality-floor section. Closes a v8.2.0 dogfood residual: the generated suite used `oklch(NaN ..)` tokens rejected in ~0 ms while `oklch(0.5 1e400 30)` parsed and hung an unbounded clamp loop in the unguarded `gamut_map` / `parse_color` siblings.
- **MCP `outputSchema` advisory** (`ac-quality-criteria.md` `Planner MUST`) — an MCP-server ticket's registered tools SHOULD declare an `outputSchema` (zod shape) so the SDK validates `structuredContent` server-side and the calling LLM sees a typed return contract; advisory MCP-protocol hygiene, explicitly NOT a Gate 7 FAIL trigger (orthogonal to oracle independence).
- **Cat AR** contract tests CT-AR-12 (parse-accepted-overflow vector enumerated across Gate 7 + `test-authoring-guidance` + `ac-evaluator` + `planner` + `implementer` + `test-writer`), CT-AR-13 (sibling-guard enumerated across Gate 7 + `test-authoring-guidance` + `ac-evaluator` + `planner` + `verification-depth` + `implementer` + `test-writer`, with revert-detecting tokens), and CT-AR-14 (the `outputSchema` advisory bullet) in `tests/test-skill-contracts.sh`.

### Changed

- Loose "Gates 1-5" references that instruct the planner now read "Gates 1-7" (`skills/create-ticket/SKILL.md`, `skills/create-ticket/references/agent-spawn-prompts.md`, `agents/ticket-evaluator.md`) so Gate 7 reaches the authoring path; this also widens the numeric span to nominally cover Gate 6 / 6.5 in those loose pointers.
- `/impl` Step 3a now also reads `constraints.oracle_verification` and applies the criticality floor; Step 15 carries the oracle-independence directive to the `ac-evaluator`.

### Verification

- `bash tests/test-skill-contracts.sh` 778/778, `bash tests/test-path-consistency.sh` 140/140.
- New **Cat AR** (CT-AR-1..14) all pass; existing **Cat AQ** (Gate 6.5) and **DEPTH-1..11** unaffected. The feature is additive and fail-open: a ticket with no computational AC is a no-op, and `constraints.oracle_verification: off` restores the pre-v8.2.0 RUNTIME oracle path (semantic Gate 7 + criticality floor + `ac-evaluator` oracle enforcement disabled). The always-on tautological rule R4 and the positive test-authoring rubric carry no kill switch — like R1-R3 they remain active under `off` and still reject a freshly authored / modified circular test.

## [8.1.1] — 2026-05-31

**TL;DR.** Three backward-compatible correctness/clarity fixes surfaced by a dogfood `/brief chain=on` run. (1) The two auto-compact hooks no longer overload `consecutive_stop_blocks` with the cumulative shipped-ticket count — it moves to a dedicated OPTIONAL `shipped_count` field on `auto_compact_inject` entries. (2) Every skill's in-body subagent spawn instruction and `subagent_type:` literal is now plugin-qualified (`simple-workflow:<agent>`) so a resumed orchestrator cannot pass a bare name that fails with "Agent type not found". (3) The two auto-compact hook header comments are corrected to match observed runtime (the post-ship state-write hook is the de-facto primary; the pre-next-scout hook is a dedup fallback). No migration needed — every existing `runtime_metrics` writer and the `agent:` frontmatter / Mandatory-table contracts are byte-identical.

### Fixed

- **`runtime_metrics` field pollution**: `hooks/pre-next-scout-auto-compact.sh` and `hooks/post-ship-state-auto-compact.sh` passed the shipped-ticket count into `append_runtime_metrics_entry`'s 8th argument, writing it to `consecutive_stop_blocks` — a field documented as meaningful only for `boundary: session_end`. The count now flows to a new OPTIONAL 9th argument and is emitted as a dedicated `shipped_count` field on `auto_compact_inject` entries (with `consecutive_stop_blocks: null`). The field is emitted only when provided, so the five unchanged 8-arg callers (`autopilot-continue.sh`, `pre-compact-save.sh`, the two checkpoint guards) produce byte-identical entries. The numeric guard `_rm_numeric_or_null` is applied to the 9th arg in all three write tiers (yq / python+PyYAML / pure-shell).
- **Bare subagent spawn names**: every skill's in-body "MUST invoke X via the Agent tool" instruction and `subagent_type:` literal now uses the plugin-qualified `simple-workflow:<agent>` form (notably `skills/plan2doc/SKILL.md` `subagent_type: simple-workflow:planner` and `skills/impl/SKILL.md` `subagent_type: simple-workflow:implementer` — the literals a resumed orchestrator copies verbatim). A bare name could otherwise raise "Agent type 'planner' not found". Mandatory-table cells (`| \`X\` agent (Agent tool) |`) and the YAML `agent:` frontmatter stay bare — they are agents/ file-name references and Cat D / Cat X contract identifiers that Claude Code resolves in plugin scope.

### Changed

- **auto-compact hook header comments corrected**: `pre-next-scout-auto-compact.sh` is now documented as the de-facto DEDUP FALLBACK and `post-ship-state-auto-compact.sh` as the de-facto PRIMARY trigger, matching observed runtime (a 7-ticket autopilot run produced 7/7 `auto_compact_inject` entries with `stop_reason: safety_net`, 0/7 `primary`): the state-write hook fires first and injects `/compact`; the next-scout hook dedup-skips on resume via its Gate 5. No runtime logic changed — only the header/coordination comments.
- **`auto_compact_inject` boundary documented**: added to the boundary table in `skills/autopilot/references/stop-reason-taxonomy.md` (previously omitted despite both hooks writing it), and the new `shipped_count` field documented there and in `references/state-file.md` (8th optional key).

### Verification

- `tests/test-skill-contracts.sh` 764/764, `tests/test-path-consistency.sh` 140/140, `tests/test-hooks-lib.sh` 159/159 — the last includes new **AC-5**: the 9th-arg `shipped_count` is emitted only when provided, the 8-arg form stays byte-identical, and a literal `null` arg9 omits the field (verified in both the yq and pure-shell tiers).
- runtime / checkpoint suites green: test-autopilot-runtime-metrics 16/16, test-runtime-metrics-write-window 23/23, test-per-phase-metrics 38/38, test-precompact-end-to-end 9/9, test-impl-checkpoint-guard 13/13, test-autopilot-continue 52/52, test-scout-checkpoint-guard 19/19. A python-tier live check confirmed `shipped_count: 9` emission with `consecutive_stop_blocks: null`, and zero `shipped_count` leakage on the 8-arg path.

## [8.1.0] — 2026-05-31

**TL;DR.** Two composable verification-depth features, both gated by the existing ticket Size × `risk_tolerance` signals and a no-op for the common case. (1) **Size/risk-aware depth scaling**: a new `constraints.verification_depth` policy knob (`auto` default) derives a depth tier (`standard` / `thorough` / `exhaustive`) that scales the Generator→Evaluator round cap (`+0` / `+3` / `+6`) and forces `/audit`'s skeptical third-pass at `thorough`+. (2) **High-assurance multi-verifier majority**: at the `exhaustive` tier, `/impl` Step 15 spawns three independent `ac-evaluator`s with diverse lenses (correctness / adversarial-refute / reproduction-edge) and majority-merges their verdicts (a CRITICAL finding survives a minority; a non-critical FAIL needs ≥2). For the common S/M conservative/moderate ticket the resolved tier is `standard`, so behaviour is byte-identical to `v8.0.0`.

**Migration / kill switch (non-breaking).** Default `constraints.verification_depth: auto` only deepens L/XL or `aggressive` tickets; S/M conservative/moderate tickets are unchanged. Set `constraints.verification_depth: off` in a brief's `autopilot-policy.yaml` to restore the exact pre-`v8.1.0` contract (base `max_total_rounds`, single evaluator, conditional-only third-pass). An explicit `rounds=N` argument to `/impl` remains authoritative and suppresses the depth bonus.

### Added

- `constraints.verification_depth` policy knob (`auto` / `standard` / `thorough` / `exhaustive` / `off`) with a Size × `risk_tolerance` derivation matrix, documented in `skills/impl/references/verification-depth.md` and consumed by `/impl` (round-cap Step 1a, evaluator-mode dispatch Step 15, `/audit` handoff Step 17). Default `auto` at every tier; the `auto` derivation folds `risk_tolerance` into the matrix rather than carrying a per-tier literal.
- High-assurance multi-verifier majority at `/impl` Step 15 (`exhaustive` tier, `AC_COUNT < 30`): three diverse-lens `ac-evaluator` spawns (`eval-round-{n}-v1.md` … `-v3.md`) merged by per-AC majority with a 2-of-3 quorum, documented in `skills/impl/references/ac-evaluator-orchestration.md` (`## High-assurance multi-verifier branch`) and `agents/ac-evaluator.md` (`## Verification Lens (high-assurance handoff)`). The `AC_COUNT >= 30` partition branch takes precedence, capping per-round evaluator spawns at 3.
- `/audit` `depth=<tier>` argument and skeptical-pass trigger **T-F**: `depth=thorough|exhaustive` forces the existing Step 3.5 third-pass regardless of the diff heuristics `T-A`..`T-E`.

### Changed

- `/impl` Phase 1 adds Step 3a (verification-depth tier resolution after Size detection) and records the resolved tier in `phases.impl.verification_depth`. The round-cap precedence (`skills/impl/references/round-cap-parser.md`) folds the tier bonus in after the base resolves, unless a valid `rounds=N` was supplied or `verification_depth: off`.
- The per-tier policy defaults (`skills/autopilot/references/state-file.md`) and the emitted policy template (`skills/brief/references/policy-template.md`) now document `verification_depth: auto`.

### Verification

- `bash tests/test-skill-contracts.sh` and `bash tests/test-path-consistency.sh` exit 0, including the new `CT-DEPTH-*` assertions and the CHANGELOG ↔ `plugin.json` version-equality check.
- Scoping confirmed: S/M conservative/moderate tickets resolve to tier `standard` (no-op vs `v8.0.0`); `verification_depth: off` restores the pre-`v8.1.0` path verbatim; an explicit `rounds=N` suppresses the depth bonus.

## [8.0.0] — 2026-05-30

**TL;DR.** First `8.x` major release. It consolidates the entire capability-detection feature line developed since `v7.0.4` (the prior `v7.1.0` / `v8.0.0` / `v8.0.1` milestones were never tagged and are merged here): per-AC capability binding (`### Capabilities` table in `ticket.md` / `plan.md`, Gate 6), the Advisory-capability tier (Gate 6.5, "Recommending, not Permitting"), MCP-server inheritance for the four productive subagents, **Phase 6 machine-enforcement** of Advisory consultation as an audit trail across `/impl`, `/brief`, `/catchup`, `/create-ticket`, `/scout`, `/investigate`, and `/test`, the autopilot 3-tier non-interactive contract, and the `brief` mode rename. Everything is **capability-name-agnostic**: any Skill or MCP server the user mounts into their harness flows through the same detection → binding → invocation → audit path with no plugin-file change.

**Migration (breaking).**
- **MCP inheritance / `tools:` removal** — `agents/{implementer,planner,researcher,test-writer}.md` no longer ship a `tools:` allowlist; they inherit the parent session's full inventory (including any `mcp__*`), and `planner` / `researcher` `Bash` widens to `Bash(*)`, fenced by each agent's `## Side-effect ban` and the extended `hooks/pre-bash-safety.sh` denylist. An `mcp__*` tool is invocable only when bound to an AC via the planner-authored `### Capabilities` table. Rollback: `git checkout v7.0.4` plus reinstall.
- **`brief` mode rename** — the legacy brief mode value is renamed to `chain`, with a deprecation alias retained for one release. Update any `autopilot-policy.yaml` / scripted invocations that pass the old mode literal.
- **Autopilot 3-tier non-interactive contract** — `/autopilot` now resolves an explicit `risk_tolerance` (conservative / moderate / aggressive) and a deterministic `AskUserQuestion` allow-list; absent or unknown `risk_tolerance` fails closed to `conservative`. Review `autopilot-policy.yaml` against the new tiers before running non-interactively.
- Pre-Gate-6 tickets (no `### Capabilities` section) continue to drive `/impl` / `/audit` / `/ship` unchanged.

### BREAKING CHANGES

- **`agents/{implementer,planner,researcher,test-writer}.md` no longer ship
  a `tools:` allowlist**; they now inherit the parent session's full tool
  inventory. `planner` and `researcher` Bash permission expands from
  `Bash(git log|diff|status|branch:*)` to `Bash(*)`. Mitigation: each
  agent's new `## Side-effect ban` (or expanded body prose) forbids
  destructive Bash, unbound MCP invocation, identity spoofing, and
  outbound network calls; `hooks/pre-bash-safety.sh` adds defense-in-
  depth at the shell level for `curl`, `wget`,
  `git config user.email`, `git commit --amend`, `sudo`, `chmod 777`,
  and related destructive / identity-spoofing patterns. Package-manager
  installs (`npm install`, `pnpm install`, `yarn add`, `pip install`,
  `gem install`, `cargo install`, `brew install`, `apt-get install`,
  `apk add`, `go install`, `composer require`, `bundle install`,
  `mix deps.get`, `dart pub get`, `conda install`, `nuget restore`,
  `dotnet add package`, etc., across every language) and `git remote
  add` are intentionally NOT blocked so autopilot can install declared
  dependencies and add remotes without manual interruption; the
  prompt-injection-driven-install mitigation lives at the prompt level
  via the `## Bound capabilities (per AC)` discipline and the planner
  Pre-emit Self-Audit step 6(d).
- **`tests/test-path-consistency.sh` Cat 6 + Cat 11 invariants redesigned**:
  Cat 6 (`^tools:` required) now allows Group A omission while still
  enforcing `^tools:` presence for the six Group C agents; Cat 11 is
  redesigned as a positive enumeration of (a) zero agents declaring the
  unrestricted `"Bash(*)"` allowlist entry and (b) exactly the six Group C
  agents carrying `^tools:` in their frontmatter.
- **v7.1.0 doctrine retracted**: `skills/create-ticket/references/agent-
  spawn-prompts.md` and `skills/create-ticket/references/ac-quality-
  criteria.md` no longer say "subagents do not inherit MCP". The new
  wording reflects the v8.0.0 reality: productive agents inherit, verdict
  / read-only agents do not. Tickets created on v7.x continue to drive
  `/impl` / `/audit` / `/ship` without parse failure.

- **`/autopilot` non-interactive contract is now 3-tier and
  `risk_tolerance`-aware**. The prior unconditional ban on
  `AskUserQuestion` between per-ticket pipeline start and the final
  `## [SW-CHECKPOINT]` is replaced by an allow-list matrix keyed on
  `risk_tolerance` from `autopilot-policy.yaml`: `aggressive` denies
  every header (zero questions); `moderate` allows only the safety-
  critical `audit-fail` / `ac-eval` headers; `conservative` allows
  the six gate-id headers (`audit-fail`, `ac-eval`, `ship-review`,
  `ship-ci`, `eval-dry`, `tkt-quality`) and denies every other
  (phase-gate / ad-hoc) header. The contract activation point is
  shifted earlier — from per-ticket pipeline start to the moment
  Phase 1 step 1 confirms `SPLIT_PLAN` exists — and now spans the
  full Phase 1 / Phase 2 / post-loop window. Header naming on every
  `AskUserQuestion` issued under `/autopilot` is load-bearing (gate
  ID, max 12 chars); the issuing skills (`/impl`, `/ship`,
  `/refactor`) now record the required `header:` value in prose so
  off-matrix headers are denied at every tier. Phase 1 hard-stop
  conditions (missing split-plan, brief `status: draft`, hostile
  state) emit `[AUTOPILOT-POLICY] gate=unexpected_error action=stop`
  alongside the verbatim legacy `ERROR:` literals and write
  `## Stop Reason` with `tag: policy_gate_stop` plus a one-line
  `Resume after fixing X with: /autopilot {parent-slug}` hint instead
  of escalating to `AskUserQuestion`. Migration: users who relied on
  the prior two-valued contract should set
  `risk_tolerance: aggressive` in `autopilot-policy.yaml` to preserve
  the zero-question behaviour. New mechanical assertions AP-1..AP-26
  in `tests/test-skill-contracts.sh` pin the new section, matrix
  cells, header naming, per-callee header annotations, hard-stop
  path, and forbidden self-rationalisation enumeration. Structural
  enforcement (`hooks/pre-askuserquestion-guard.sh`) ships in a
  separate plan; the prose layer here is the sole orchestrator-side
  enforcement until that hook lands.

### Added

- **MCP inheritance for 4 productive subagents** via `tools:` omission:
  `agents/{implementer,planner,researcher,test-writer}.md` now inherit
  every MCP server configured in `.mcp.json` (project) and
  `~/.claude.json` (user), including custom user-authored servers.
- **`## Side-effect ban` section** in `agents/planner.md` and
  `agents/researcher.md`. Forbids destructive Bash, unbound MCP
  invocation, identity spoofing, and outbound network calls. Three
  canonical forbidden tokens (`git commit`, `curl`, `mcp__Gmail__send`)
  appear in each section as concrete examples. Note that package-
  manager installs ARE allowed by the hook (see BREAKING CHANGES
  bullet) — Side-effect ban discourages planner / researcher from
  introducing new dependencies as part of their authoring / read-mostly
  role, but the hook lets implementer / test-writer install declared
  dependencies as part of their productive role. Intentionally NOT
  applied to `agents/implementer.md` / `agents/test-writer.md` because
  productive code-mutation and test-execution work legitimately
  requires `Write` / `Edit` and `Bash(*)` beyond read-only inspection
  (a build script may run `rm` on build artifacts, an integration
  test may invoke `npm run test:e2e`). Defense-in-depth at the hook
  level (`hooks/pre-bash-safety.sh`) backstops these productive agents
  for the destructive / identity-spoof patterns even without an agent-
  body Side-effect ban.
- **Bound Capabilities MCP-extension bullet** in
  `agents/{implementer,planner,researcher,test-writer}.md`. Extends the
  v7.1.0 "Do NOT scan installed Skills independently" guidance to also
  cover MCP servers — only `mcp__*` bound to an active AC may be invoked
  (`Skills **or MCP servers**`).
- **`hooks/pre-bash-safety.sh` denylist extension** covering 4 new
  categories: network egress (`curl`, `wget`, `scp`, `rsync ... ssh`),
  identity spoofing (`git config user.email`, `git config user.name`),
  privilege escalation (`sudo`, `chmod 777`, `chown root`), and
  branch / commit subversion (`git commit --amend`, `git stash drop`,
  `git reflog expire`, `git push --no-verify`). Defense-in-depth
  against the Group A `Bash(*)` expansion. A supply-chain mutation
  category was prototyped in earlier drafts and intentionally dropped
  before release — package-manager installs (`npm install` and
  equivalents across every language) and `git remote add` are
  allowed by the hook so autopilot does not stall on routine
  dependency setup. See the BREAKING CHANGES bullet for the prompt-
  level mitigation. Patterns
  accept a permissive prefix that blocks the common obfuscations —
  full-path invocation (`/usr/bin/curl ...`), relative-path invocation
  (`./curl`, `../curl`, `bin/curl`, `node_modules/.bin/curl`,
  `~/bin/curl`, `$HOME/bin/curl`), arbitrary env-var assignment
  (`FOO=bar curl ...`), command wrappers (`env`, `command`, `exec`,
  `time`, `nice`, `ionice`, `nohup`), and flags between `git push` and
  `--no-verify` at any argument position (including quoted args
  containing pipe / semicolon / ampersand). Out-of-scope
  obfuscations (covered by the agent-body `## Side-effect ban` and the
  per-AC binding discipline instead): the quoted argument inside
  `bash -c '...'` / `sh -c '...'`, parenthesised subshell token-start
  `(cmd)`, and brace-group token-start `{ cmd; }`.
- **Cat AN drift-guard tests (CT-AN-1..CT-AN-8)** in
  `tests/test-skill-contracts.sh`. Pin the Group A omit, Group C
  retention, `permissionMode` removal, Side-effect ban presence,
  Bound Capabilities MCP bullet, doctrine update, `pre-bash-safety.sh`
  new pattern tokens (CT-AN-7), and behavioral block per category
  (CT-AN-8 — pipes a representative command per category into the hook
  and asserts exit 2, guarding against the "tokens in comments but
  regex broken" silent-regression class).

- **Gate 6.5 (Probe Completeness) + Advisory Capabilities pathway**
  closes the v8.0.0 probe-visible-but-silently-dropped failure mode.
  Dogfood (TW33 / TW34, 12 tickets) showed `ui-ux-pro-max` was probe-
  visible in both directories but classified in zero tickets, and
  `mcp__context7__query-docs` was classified as `(advisory; no AC
  binding)` in 4 of 5 TW34 tickets but never reached the implementer
  because the orchestrator did not propagate that advisory annotation
  into spawn prompts. v8.0.0 ships the structural fix:
  - **`skills/create-ticket/references/ac-quality-criteria.md`**
    gains `## Gate 6.5: Probe Completeness` between Gate 6 and the
    Evaluator-MUST-NOT list. The new gate defines a three-bucket
    classification (Bound / Advisory / Skipped with rationale) and
    REQUIRES the planner to classify every probe-visible entry into
    exactly one bucket. Silent omission is FAIL. `(none)` probes are
    vacuously PASS. Pipeline orchestrator skill names (`/scout`,
    `/impl`, etc.) qualify for an automatic Skipped path with a fixed
    rationale. The Evaluator MUST NOT list gains two new entries
    (bucket-choice debatability is not FAIL; `(none)` probe is PASS).
    The Planner MUST list gains a corresponding entry requiring
    classification of every probe entry on every emit / re-emit.
  - **`agents/planner.md`** gains Pre-emit Self-Audit step 7 (Gate 6.5
    probe completeness cross-check) with the three-bucket vocabulary,
    the self-skip exception for pipeline orchestrators, the `(none)`
    exception, and the Advisory authoring discipline (`Used by`
    column MUST list productive subagents only; verdict / Group C
    agents in an Advisory row's `Used by` is a Gate 6.5 FAIL). The
    Capabilities Authoring (Authoring Role) body section is updated
    to enumerate the three sections the planner authors
    (`### Capabilities`, `### Advisory Capabilities`,
    `#### Capability Skip Rationale`) and confirm their union covers
    every probe entry.
  - **`agents/ticket-evaluator.md`** Result template gains a Probe
    Completeness (Gate 6.5) Gate Result row; `n/a` is permitted when
    both probes are `(none)` or the ticket pre-dates Gate 6.5.
  - **`skills/create-ticket/references/ticket-template.md`** ships the
    `### Advisory Capabilities` table block (with `Name | Type |
    Purpose | Used by` columns; no `Bound AC(s)` column) and the
    `#### Capability Skip Rationale` bullet block, both emitted by
    the planner between `### Capabilities` and `### Claude Code
    Workflow`.
  - **`agents/implementer.md`, `agents/researcher.md`,
    `agents/test-writer.md`** each gain a `## Advisory Capabilities`
    body section that lifts the speculative-invocation ban
    exclusively for entries the orchestrator listed under
    `## Advisory capabilities (per ticket)` in the spawn prompt. The
    ban remains in force for any Skill or `mcp__*` tool not listed in
    Bound or Advisory. The four productive subagents (`planner`,
    `implementer`, `researcher`, `test-writer`) split into one author
    (planner) and three consumers (implementer / researcher /
    test-writer); only consumers gain the section because the
    planner authors the Advisory table rather than reading it.
  - **MCP probe coverage extended** to four previously probe-light
    skills (`skills/{impl,brief,plan2doc,investigate}/SKILL.md`).
    Each `## Pre-computed Context` block now emits both
    `Available user skills:` and `Available MCP servers:` so
    downstream planner / researcher invocations see the full probe
    set and Gate 6.5 cross-check has authoritative input.
  - **Advisory propagation pathway** in `skills/impl/SKILL.md` Step 13
    (implementer spawn) and `skills/refactor/SKILL.md` Phase 1 Step 1
    (planner spawn). The orchestrator now extracts the
    `### Advisory Capabilities` table from `{ticket-dir}/ticket.md`
    in addition to `### Capabilities`, and inlines the full table
    into the productive-subagent spawn prompt under
    `## Advisory capabilities (per ticket)`. The block is NOT inlined
    into `ac-evaluator` (Step 15) spawn prompts — Advisory is for
    authoring, not verification.
- **Cat AQ drift-guard tests (CT-AQ-1..CT-AQ-9)** in
  `tests/test-skill-contracts.sh`. Pin Gate 6.5 canonical section
  presence (CT-AQ-1), planner step 7 wiring (CT-AQ-2), ticket-
  evaluator Gate Results row (CT-AQ-3), ticket template Advisory +
  Skip Rationale blocks (CT-AQ-4), productive-consumer Advisory body
  section across `{implementer,researcher,test-writer}.md` (CT-AQ-5),
  MCP probe coverage across the four newly-probe-emitting skills
  (CT-AQ-6), Advisory handoff in `impl` / `refactor` orchestrators
  (CT-AQ-7), the `(none)` probe vacuous-pass documentation in
  both authoring sites (CT-AQ-8), and the Recommending-semantics
  consultation discipline that elevates Advisory from
  permitting-only to invoke-or-record-rationale (CT-AQ-9).

- **Advisory Capabilities Recommending semantics (v8.0.0+
  consumer-side consultation discipline)**: TW35 dogfood
  (`/Users/kytk/workspace/repos/test_simple_workflow35`) confirmed
  the planner-side Gate 6.5 + orchestrator-side Advisory propagation
  pathway both worked end-to-end (`ui-ux-pro-max` was Advisory-bound
  in 4/5 tickets and inlined into every implementer spawn prompt),
  but the consumer side silently skipped the entry — `ui-ux-pro-max`
  was invoked 0 times across the entire session with no recorded
  skip rationale anywhere in the audit trail. The collapse of
  permitting-only Advisory into "silent inaction" hides the
  implementer's design decision from downstream review. This release
  promotes Advisory from permitting to Recommending:
  - **`agents/{implementer,researcher,test-writer}.md`** each gain a
    `### Consultation discipline (v8.0.0+ — Recommending, not just
    Permitting)` subsection under their `## Advisory Capabilities`
    body section. For every Advisory entry whose `Used by` column
    lists the consumer, the consumer MUST either (a) invoke the
    listed Skill / `mcp__*` tool at least once during work, OR
    (b) record a one-line skip rationale under `### Limitations`
    (or `Next Steps` when no `### Limitations` heading exists in the
    consumer's return envelope) explaining why the entry was not
    consulted. Silent omission — neither invoking nor recording a
    rationale — is a contract violation.
  - **`skills/create-ticket/references/ac-quality-criteria.md`**
    Gate 6.5 section gains a `Consumer-side consultation discipline`
    paragraph documenting the Recommending semantics and the TW35
    dogfood evidence that motivated it.
  - The discipline mirrors Gate 6.5's probe-completeness principle
    at the consumer side: a probe-visible capability bound for a
    consumer must result in either an invocation OR a documented
    skip, never invisible inaction.
- **Category J in `tests/test-pre-bash-safety.sh`** — full behavioral
  block / allow coverage of the v8.0.0 denylist, including the bypass
  cases listed in the previous bullet. Total grows from 126 to 195
  assertions (+69) including J.7 (7 BLOCK assertions for relative-path
  and quoted-arg bypasses: `./curl`, `../curl`, `bin/curl`,
  `node_modules/.bin/curl`, `git push 'arg|piped' --no-verify`, etc.)
  and 36 ALLOW assertions: 24 covering legitimate package-manager
  installs across npm / pnpm / yarn / pip / pip3 / gem / cargo /
  brew / apt-get / apk / go / composer / bundle / mix / dart pub /
  conda / nuget / dotnet plus `git remote add`, and 12 false-positive
  sanity cases (`git remote -v`, `git push`, `git commit -m`,
  `ls bin/curl`, `git push origin some--no-verify-branch`, etc.).

- **`hooks/lib/inject-keys.sh` gains a post-inject capture-pane verify
  for the tmux backend (P1-1)**. After `tmux send-keys` returns rc=0,
  the library now sleeps `SW_INJECT_KEYS_VERIFY_SLEEP_MS` ms (default
  `150`) and runs `tmux capture-pane -p -S -3 -E -` against
  `$TMUX_PANE`; if the injected text is not visible, `inject_keys`
  downgrades rc to 1 and emits `[INJECT-VERIFY] missed: ...` to
  stderr. The upstream auto-compact hooks
  (`hooks/pre-next-scout-auto-compact.sh` L169,
  `hooks/post-ship-state-auto-compact.sh` L328) already gate the
  `.auto-compact-pending` sentinel and the `runtime_metrics`
  `auto_compact_inject` write on `INJECT_RC = 0`, so the verify miss
  flips them to the failure branch without further changes —
  `additionalContext` now begins `auto-compact-on-ship: injection
  failed — ` and includes the new verify-missed hint (greppable by
  the substring `verify window`) emitted by `inject_keys_failure_hint`.
  Kill-switches: `SW_INJECT_KEYS_VERIFY=0` disables the verify block
  entirely (rc reflects `tmux send-keys` exit code only, restoring
  pre-P1-1 behaviour); `SW_INJECT_KEYS_VERIFY_SLEEP_MS` overrides the
  sleep window. The DRY_RUN early-return (`INJECT_KEYS_DRY_RUN=1 +
  SW_TEST_HARNESS=1`) runs before the verify block so the existing
  `[inject-keys] DRY_RUN backend=tmux target=... text=... enter=...`
  stderr contract is unchanged. New hermetic test
  `tests/test-inject-keys.sh` (PATH-stubbed `tmux` via
  `tests/fixtures/tmux-stub.sh`) covers DRY_RUN unchanged, opt-out,
  verify success, verify failure, sleep-ms override, and the
  `inject_keys_failure_hint` `verify window` substring contract.

- **`/autopilot` Phase 1 emits a 1-line `[AUTOPILOT-CONTEXT]` self-doc**
  describing the resolved `SW_AUTO_COMPACT_ON_SHIP_MODE` so the
  orchestrator never asks about auto-compaction. New step 0.5 in
  `skills/autopilot/SKILL.md` (between auto-kick cleanup and split-plan
  discovery) reads the env var, defaults to `on` in autopilot context,
  treats unknown values as `off`, and emits EXACTLY ONE block whose
  three verbatim branches (on / metric-only / off) live in the new
  `skills/autopilot/references/autopilot-context-self-doc.md`. The
  resolution mirrors `hooks/pre-next-scout-auto-compact.sh` L81 so the
  self-doc never lies about the active mode. Drift-guarded by
  `tests/test-skill-contracts.sh` CT-AC-52..60.
- **`hooks/pre-askuserquestion-guard.sh`** — new
  `PreToolUse:AskUserQuestion` hook that structurally enforces the
  autopilot non-interactive contract via a 3-tier `risk_tolerance` x
  6-header allow-list matrix (single source of truth shared verbatim
  with `skills/autopilot/SKILL.md`). The hook resolves the kill-switch
  (`SW_AUTOPILOT_ASK_GUARD`), walks the canonical
  `is_autopilot_context` / `find_any_autopilot_state_file` /
  `parse_ticket_statuses` detection chain, and emits
  `hookSpecificOutput.permissionDecision: "deny"` with a reason
  enumerating the matched tier, the offending header, the
  `policy_gate_stop` resume path, and the
  `autopilot-policy.yaml` tuning knob. New helper
  `hooks/lib/parse-state-file.sh::get_risk_tolerance` reads
  `risk_tolerance` from `<state_dir>/autopilot-policy.yaml` using the
  standard `yq -> python3+PyYAML -> awk` three-tier fallback; file
  absence, missing key, or unknown value normalises to `conservative`
  so a malformed policy does not silently widen / collapse the
  allow-list. Kill-switch: `SW_AUTOPILOT_ASK_GUARD=on` (default) /
  `metric-only` (compute matrix + log `[ASK-GUARD] metric-only: would
  deny ...` without denying) / `off` (silent allow; unknown values
  collapse here). Companion to the SKILL prose work above; matrix
  parity is enforced by 9 new mechanical assertions (P1-3B AC-6 /
  AC-9 / AC-10) appended to `tests/test-skill-contracts.sh` and by
  the new `tests/test-ask-guard.sh` (56 scenarios covering all 21
  matrix cells, metric-only / off / policy-absent kill-switches, the
  unknown-header stderr signal, the unknown-tier fail-open, and the
  outside-autopilot / all-terminal negative paths).
- **Sentinel-based session-start `/compact` retry (P2-1)** —
  `hooks/pre-next-scout-auto-compact.sh` and
  `hooks/post-ship-state-auto-compact.sh` now drop
  `<state_dir>/.next-compact-pending` (UNIX timestamp) BEFORE every
  `inject_keys '/compact'` call and delete it only on confirmed
  success (`INJECT_RC == 0` after P1-1 verify). On rc=1 the sentinel
  is RETAINED and stderr carries
  `retaining .next-compact-pending for session-start retry`, so
  `hooks/session-start.sh` can replay the injection on the next
  `source=startup` / `source=resume` boot (the timestamp is refreshed
  before each replay attempt); `source=compact` deletes the sentinel
  without re-injecting (logs `sentinel cleared on source=compact`).
  Sentinels older than `SW_NEXT_COMPACT_PENDING_TTL_SEC` (default
  21600 = 6h) are deleted without retry (`stale sentinel ... removed
  without retry`). `hooks/autopilot-continue.sh` co-deletes
  `.next-compact-pending` whenever it yields on
  `.auto-compact-pending`, so a same-session yield never triggers a
  duplicate session-start retry. Kill-switch:
  `SW_AUTO_COMPACT_ON_SHIP_MODE=off` short-circuits the entire P2-1
  block in both writers and reader (full backward compat). New
  hermetic tests `tests/test-session-start-next-compact.sh` (AC-5 /
  AC-6 / AC-7 / AC-8 via `INJECT_KEYS_DRY_RUN=1 + SW_TEST_HARNESS=1`)
  and `tests/test-pre-next-scout-auto-compact.sh` (AC-2 / AC-3 via
  PATH-stubbed `tmux` from `tests/fixtures/tmux-stub.sh`) pin the
  sentinel lifecycle end-to-end.
- **`SW_POST_SHIP_INTEGRITY` runtime env knob (P3-5)** — controls the
  new post-ship integrity Gate 5.5 inside
  `hooks/post-ship-state-auto-compact.sh`. Values: `on` (default —
  self-heal each ticket's `phase-state.yaml` when
  `overall_status:` is still `in-progress` after `steps.ship: completed`
  was written to the brief-side `autopilot-state.yaml`), `metric-only`
  (emit the `[POST-SHIP-INTEGRITY] self-healing <dir>` warning to
  stderr but skip the write — forensic mode), `off` (silent skip;
  unknown values collapse here so a typo fails closed for the rewrite
  path). The rewrite uses `yq -i` first then a `python3 + PyYAML`
  tempfile + rename fallback; awk-tier rewriting is intentionally not
  attempted (ticket Risk R3) so the original file is preserved on
  failure. Companion helper `parse_yaml_scalar <file> <key>` lands in
  `hooks/lib/parse-state-file.sh` with the canonical
  `yq -> python3+PyYAML -> awk` three-tier fallback. New
  mechanical assertions PSI AC-1..AC-7 in
  `tests/test-skill-contracts.sh` pin the SKILL prose (Step 15a
  idempotence + Step 16 ordering), the hook Gate 5.5 + kill-switch
  literals, and the behavioural self-heal / kill-switch / metric-only /
  idempotence behaviours against the
  `tests/fixtures/post-ship-integrity/` fixtures.
- **State-schema cross-version tests + canonical invariant doc + migration tool
  (P2-4)** — new fixtures `tests/fixtures/state-schema/v7-shelftrack/` and
  `tests/fixtures/state-schema/v8-shelftrack/` capture the v7 (legacy
  `total_tickets:` + basename `ticket_mapping:`) and v8 (canonical
  `processing_order:` + fullpath `ticket_mapping:` + `human_overrides: []` /
  `kb_overrides: []` / `decisions_made: []`) shapes of `autopilot-state.yaml`
  sanitised from test_simple_workflow33 / 34. New `tests/test-state-parsers.sh`
  asserts the four `hooks/lib/parse-state-file.sh` helpers (`is_autopilot_context`,
  `find_any_autopilot_state_file`, `parse_ticket_ship_dirs`,
  `parse_ticket_statuses`) return semantically identical results across both
  fixtures (≥8 PASS, run via the existing `tests/run-all.sh` glob). New
  `docs/state-schema.md` documents the canonical v8 shape, the read-only v7
  legacy fields, the three load-bearing invariants (`processing_order:` is
  the SSoT for ticket count; `ticket_dir:` is always a fullpath; `tickets[]`
  is list-canonical; forward-compatible additions only), and the migration
  workflow. New `tools/migrate-state-schema.sh` performs a non-destructive
  v7 -> v8 rewrite (`--in` / `--out` only; in-place edits unsupported by
  design) using the project's standard `yq` -> `python3 + PyYAML` ->
  fail-with-warning three-tier fallback, and is idempotent on already-v8
  input.

- `## Gate 6: Capability Mapping` in
  `skills/create-ticket/references/ac-quality-criteria.md`. Defines when
  an AC is runtime/visual (live rendering, console-error count, keyboard
  focus/hover, WCAG contrast, network I/O, FS-state-dependent) and the
  binding rule (every such AC MUST appear in the `Bound AC(s)` column of
  at least one `### Capabilities` row OR be rewritten as a static AC).
  Gate 6 evaluation activates only after this update ships;
  pre-ship evaluations of this plan (including
  `.docs/update_ticket/eval-report.md`) deliberately applied Gates 1-5
  only and their PASS verdicts do not imply Gate 6 conformance.
- `### Capabilities` section in
  `skills/create-ticket/references/ticket-template.md`, placed between
  `### Implementation Notes` and `### Claude Code Workflow`. Column
  header sequence is `Name | Type | Purpose | Used by | Bound AC(s)`.
  Optional `#### Capability Gaps` subsection records runtime/visual ACs
  that could not be bound and the reason.
- `Available MCP servers:` Pre-computed Context probe in
  `skills/create-ticket/SKILL.md`. The `!`-prefixed bash pipeline reads
  the `mcpServers` keys of `.mcp.json` (project-scope) and
  `~/.claude.json` (user-scope), unions and de-duplicates them, and
  serialises the result into the planner spawn prompt verbatim. Empty
  probes return `(none)`.
- MCP-server enumeration step in `skills/plan2doc/SKILL.md` Step 3 and a
  `## Capabilities` section requirement in Step 4 — the planner copies
  the ticket's `### Capabilities` table verbatim into the plan when
  `ticket.md` exists, mirroring the existing AC SSoT verbatim-copy
  discipline.
- Planner Pre-emit Self-Audit step 6 in `agents/planner.md`. Cross-
  checks every drafted AC against the Gate 6 runtime/visual classifier
  and verifies each runtime/visual AC appears in at least one row's
  `Bound AC(s)` column, OR is rewritten as a static AC, OR is recorded
  under `#### Capability Gaps`.
- `Capability Mapping` row in the `agents/ticket-evaluator.md` return
  envelope `**Gate Results**` block (canonical criteria are inline-
  injected; no rubric change inside the evaluator agent itself).
- `tests/test-skill-contracts.sh` Category AM (CT-AM-1..7). Drift guards
  lock the new template heading + column header, the canonical Gate 6
  + Planner MUST bullet, the create-ticket MCP probe shape, the
  plan2doc Step 3 / Step 4 wording, the spawn-prompt + planner self-
  audit substrings, the impl-side per-AC handoff, the 8-skill handoff
  propagation, and the AC-12 trivial-pass boundary against the
  pre-existing Cat AH-7 AC-counting scanner.
- Each Skill-bearing subagent body (`ac-evaluator`, `code-reviewer`,
  `decomposer`, `implementer`, `researcher`, `test-writer`,
  `tune-analyzer`) now carries a `## Bound Capabilities (Handoff from
  Orchestrator)` section instructing the agent to treat the spawn
  prompt's `## Bound capabilities (per AC)` block as upstream-
  authoritative — no re-derivation of capability relevance from the AC
  text, no independent scan of installed Skills for "plausible matches",
  and explicit gap-reporting when a bound Skill is unavailable at
  runtime. `agents/planner.md` carries the matching authoring-role
  variant (`## Bound Capabilities (Authoring Role)`) clarifying that the
  planner emits — rather than consumes — the binding, sourced from the
  orchestrator's `Available capabilities` probe under Gate 6.
- `tests/test-skill-contracts.sh` Category AM gains CT-AM-8 and
  CT-AM-9. CT-AM-8 asserts every Skill-bearing agent body carries a
  top-level `## Bound Capabilities` heading (sum across 8 agents `>= 8`).
  CT-AM-9 asserts every Subagent Skill-Access Handoff in the 9 spawner
  skills (audit, brief, create-ticket, impl, investigate, plan2doc,
  refactor, test, tune) carries the upgraded deterministic-inlining
  bullet (`inline the bound capabilities verbatim into every spawn
  prompt`).

- **Phase 6 — machine-enforced Advisory consultation (audit trail across the pipeline).** Building on the v8.0.0 Gate 6.5 "Recommending, not Permitting" semantics, every productive subagent now emits a REQUIRED `**Advisory consultation**:` field in its Result envelope, and the orchestrators gate on it. The field is `(none)` when no Advisory entry targets the agent, otherwise one `- <Name>: invoked (<evidence>)` / `- <Name>: not invoked (<rationale>)` bullet per applicable entry — so a probe-visible capability bound for the agent's use must result in either an invocation OR a documented skip, never silent inaction.
  - **`agents/{implementer,researcher,test-writer}.md`**: REQUIRED `**Advisory consultation**:` field + `### How to invoke each Advisory entry` (deferred-tool resolution: `Type=skill` → `Skill` tool; `Type=MCP` → `ToolSearch query:"select:<Name>"` then invoke) + `### Consultation reporting format`. The procedure is **capability-name-agnostic by design** — a user-mounted Skill or MCP server flows through the identical path with no agent-file change. `agents/planner.md` is intentionally excluded (it AUTHORS the Advisory table, it does not consume it).
  - **Orchestrator gates**: `/impl` Step 14b (FAIL the round on a missing field), `/brief` §1.5, `/catchup` Step 2.5, `/create-ticket` Phase 1.5 (explicit-Agent-tool researcher spawners; FAIL or surface), and `/scout` Step 4a (the gate-able caller of the declarative `/investigate`; surface-don't-fail since `investigation.md` is already on disk).
  - **Declarative-spawner enforcement**: `/investigate` Step 6 and `/test` Step 7 return contracts now require the Advisory field, because a `context: fork` spawn runs the SKILL.md body AS the agent's task prompt with no post-fork orchestrator turn to gate inline. Dogfood (TW41) measured `/investigate`-spawned researchers emitting the field in 9/9 returns, up from 0/7 before the return-contract fix.

### Changed

- **`/brief` and `/create-ticket` Phase 2 enforce args-aware shrinkage**:
  before issuing any `AskUserQuestion`, both skills now scan the active
  input (`$ARGUMENTS` in bare mode; brief body in brief mode with
  `interview_complete: false`) against the seven interview-template
  categories and classify each candidate question as `args-resolved`
  or `needs-question`. `args-resolved` items MUST NOT appear in any
  payload (including paraphrased / "to confirm" variants); a fully
  exhausted `needs-question` set is a new convergence trigger. Round /
  question caps (10 rounds × 3/round × 30 total) are unchanged; the
  `mode independence guard` body is unchanged. The orchestrator emits
  `[args-aware shrinkage] args-resolved categories: <list>; needs-question
  categories: <list>` once on round 1 so users can audit the
  suppression decision. New mechanical assertions CT-AC-61..65 in
  `tests/test-skill-contracts.sh` pin the contract grep, caps
  invariance, and guard-body invariance.
- **`/brief` introduces `chain={on,off}` as the canonical finalization
  control argument (P3-2C, X.Y.0 deprecation phase)**. The new key
  expresses what the argument actually controls — whether `/brief`
  chains into `/create-ticket` + `/autopilot` at Finalization — instead
  of the misleading `mode=auto|manual` framing that was repeatedly
  read as "skip the Socratic interview" (it never did, per the
  `mode independence guard`). Mapping: `chain=on` ≡ legacy
  `mode=auto`; `chain=off` ≡ legacy `mode=manual`; default when
  neither is supplied stays `chain=on` to preserve pre-vX.Y.0 user
  habits. `skills/brief/SKILL.md` `argument-hint` is now
  `<what-to-build> [chain=on|off] (legacy: mode=auto|manual)`; the
  `## Argument Parsing` section parses `chain=` first and treats
  `mode=` as a deprecated alias; the Phase 3 frontmatter writes
  BOTH `chain:` and `mode:` during the deprecation window so legacy
  readers continue to work; the Finalization section title is
  `## Finalization: Output, \`chain=on\` handoff, and SW-CHECKPOINT`
  with `### Step 2 — \`chain=on\` handoff` and `### Step 3 — \`chain=off\``;
  the `mode independence guard` is preserved and explicitly extended
  to mention `chain` alongside `mode` (independence-protection covers
  both arguments during the deprecation window; the guard is slated
  for removal in vX.(Y+1).0 once the alias is gone). `skills/create-ticket/SKILL.md`
  Step W-8 + B-2 frontmatter row and
  `skills/create-ticket/references/agent-spawn-prompts.md` Phase 4
  `gates.ticket_quality_fail` fallback both document the precedence
  rule `chain: precedes mode:` (chain takes precedence; mode read
  as fallback; super-legacy briefs lacking both keys default to
  `chain=on` / `mode: auto`). New mechanical assertions PCN-1..PCN-7
  in `tests/test-skill-contracts.sh` Category PCN pin the literals
  (`chain=on` / `chain=off` count, `argument-hint` substring,
  deprecation warning + simultaneous-spec error, frontmatter dual-key
  presence, cross-skill precedence marker, guard preservation +
  `chain` mention). The `mode=` argument continues to work unchanged
  for one minor and emits a stderr deprecation warning when supplied;
  combining `chain=` and `mode=` simultaneously errors out (no silent
  rewrite, mirroring the v6.0.0 `auto=true` defensive stance). The
  removal of `mode=` is a future-minor BREAKING change — flagged here
  via the `feat(P3-2C)!` commit subject so consumers can prepare.

- `skills/create-ticket/references/agent-spawn-prompts.md` — v7.1.0
  paragraph "The subagent does not inherit the main-thread harness skill
  / MCP descriptions" replaced by "MCP inheritance under v8.0.0" with
  the Group A / Group C split documented explicitly and the
  `productive subagents` term introduced.
- `skills/create-ticket/references/ac-quality-criteria.md` — v7.1.0
  wording "Forked subagents are not guaranteed to inherit MCP tool
  access" replaced by "Forked subagents inherit the parent session's
  MCP tool access when their `tools:` field is omitted".
- `skills/{impl,audit,test,tune,create-ticket}/SKILL.md` and
  `skills/{brief,investigate,plan2doc,refactor}/SKILL.md` — the
  `## Subagent Skill-Access Handoff` opening bullet is rewritten as a
  three-bullet structure that distinguishes (a) truly hermetic agents
  (`security-scanner`, `ticket-evaluator`) which carry no Skill tool,
  (b) Skill-bearing verdict / read-only agents (`ac-evaluator`,
  `code-reviewer`, `decomposer`, `tune-analyzer`) which receive
  capability handoffs via deterministic per-AC binding only, and
  (c) productive agents (`implementer`, `planner`, `researcher`,
  `test-writer`) which inherit-all under v8.0.0 but are still bound to
  the active-AC `## Bound capabilities (per AC)` block. The same
  three-bullet structure is applied uniformly across all 9 spawner
  SKILL.md so the v7.1.0 sibling-audit asymmetry that produced the
  Round 1 finding does not recur.
- `agents/planner.md` — body paragraph "Note on the `tools:` allowlist
  above" rewritten as "Note on subagent permission model" reflecting
  omit + prompt-level FS-search ban. Pre-emit Self-Audit step 6 also
  gains a new sub-step (d) that rejects MCP-typed `### Capabilities`
  rows whose `Used by` column lists a Group C agent — MCP servers are
  unexecutable for those agents under v8.0.0, so the binding must
  either split (productive agent invokes the MCP; verdict agent
  verifies via a plain Skill) or move under `#### Capability Gaps`.
- `skills/refactor/SKILL.md` — Phase 1 Step 1 (planner spawn) and
  Phase 3 Step 6 (code-reviewer spawn) now inline the per-AC
  `## Bound capabilities (per AC)` block from `{ticket-dir}/ticket.md`'s
  `### Capabilities` section into each spawn prompt (parity with
  `/impl` Steps 13/15). Pre-Gate-6 / `ticket-dir`-absent invocations
  fall back to the prior advisory path. The `## Pre-computed Context`
  block gains the `Available MCP servers:` probe (mirroring
  `/create-ticket`) so the planner authoring a brand-new
  `### Capabilities` table can see MCP servers from `.mcp.json` /
  `~/.claude.json`. **Known gap, v8.0.x candidate**: explicit in-step
  capability pre-load instructions (analogous to `/impl` Steps 13/15
  and `/refactor` Phase 1 Step 1 / Phase 3 Step 6) are NOT yet present
  in the remaining 7 spawner SKILL.md (`audit`, `brief`,
  `create-ticket`, `investigate`, `plan2doc`, `test`, `tune`). Those
  7 spawners received the v8.0.0 three-bullet `## Subagent
  Skill-Access Handoff` doctrine update so the contract is stated
  ("inline the bound capabilities verbatim into every spawn prompt"),
  but the in-step pre-load wording is advisory only. Existing
  consumers fall back to the agent body's in-house capability-
  selection path when the orchestrator omits the explicit pre-load.
  Tracked as a known gap for a future v8.0.x release; no backlog
  ticket has been filed yet.
- `tests/test-path-consistency.sh` Cat 6 + Cat 11 redesigned for v8.0.0.

- `skills/impl/SKILL.md` Step 13 (`implementer`) and Step 15
  (`ac-evaluator`) now `Read` `{ticket-dir}/ticket.md`'s
  `### Capabilities` section and inline the per-AC bound-capability list
  into the spawn prompt under `## Bound capabilities (per AC)`. The
  v7.0.4 advisory bullet for `ac-evaluator` is replaced by a forward-
  reference to this deterministic handoff. Pre-Gate-6 tickets fall back
  to the prior ad-hoc path (`(none recorded — ticket pre-dates Gate 6)`)
  so backwards compatibility is preserved.
- Subagent Skill-Access Handoff in `skills/{audit,brief,create-ticket,
  investigate,plan2doc,refactor,test,tune}/SKILL.md` gains a bullet
  pointing spawners at the ticket's `### Capabilities` section as the
  authoritative per-AC binding; spawners stop re-deriving relevance from
  the raw `Available user skills:` probe when a ticket records the
  binding upstream.
- Subagent Skill-Access Handoff bullet in the 9 spawner skills
  (`audit`, `brief`, `create-ticket`, `impl`, `investigate`, `plan2doc`,
  `refactor`, `test`, `tune`) is upgraded from "prefer the section" to
  **deterministic inlining**: orchestrators MUST `Read` the ticket's
  `### Capabilities` section (resolved via `{ticket-dir}/ticket.md` or
  the autopilot state file's `paths.ticket`) and inline the bound
  capabilities verbatim under `## Bound capabilities (per AC)` in every
  spawn prompt. Per-AC spawns include only the rows whose
  `Bound AC(s)` column lists the active AC; tip / whole-deliverable
  spawns include the full table. Older tickets without the section
  trigger a `(none recorded — ticket pre-dates Gate 6)` placeholder.
  `/impl` Steps 13/15 retain their in-step per-AC deterministic
  handoff; the Subagent Skill-Access Handoff upgrade is cross-skill
  uniformity at the file's guardrails footer — both surfaces coexist.
- `skills/create-ticket/references/agent-spawn-prompts.md` Phase 3
  "Additional context for the planner" list now serialises the
  `Available user skills:` and `Available MCP servers:` probes
  verbatim into the planner spawn prompt and carries explicit
  Gate 6 / `### Capabilities` emission instructions, because subagents
  do not inherit the main-thread harness skill / MCP descriptions.
- `tests/test-skill-contracts.sh` CT-AL-5 updated to assert the new
  deterministic-handoff prose ("the capability handoff is no longer
  ad-hoc"); the legacy "browser-automation utility skill" advisory
  bullet is no longer checked because v7.1.0 supersedes it.
- `agents/planner.md` Pre-emit Self-Audit is split into two `## `-level
  sections — one for the numeric scope/AC cross-check (steps 1-5) and
  one for the Gate 6 capability-binding cross-check (step 6). The
  substantive procedure is unchanged; the split makes the documented
  binding cross-check visible to the rubric's awk-range verifier whose
  start/end patterns both match `## `, which would otherwise truncate
  the range to the heading line alone.

- **`agents/implementer.md` turn budget raised `maxTurns: 30 → 45`** and a new `## Turn-budget self-governance (envelope-priority)` section added to `implementer` / `researcher` / `test-writer`: the closing `## Result` envelope (with the Advisory field) is the highest-priority deliverable, so an agent stuck on the same failure across 3+ distinct fix attempts bails to `**Status**: partial` rather than risk a `maxTurns` truncation that returns no envelope (and loses the audit trail for capabilities it did invoke). Dogfood (TW38→TW41) reduced implementer truncation 30% → 25%.

### Deprecated

- **`/brief mode=auto|manual` argument alias (P3-2C, X.Y.0 deprecation
  phase)**. The legacy `mode=auto|manual` argument is now a deprecated
  alias for the canonical `chain=on|off` introduced in the
  `### Changed` entry above (`mode=auto` ≡ `chain=on`,
  `mode=manual` ≡ `chain=off`). Supplying `mode=` continues to work
  for one minor (vX.Y.0) and emits a one-line stderr warning
  `WARNING: 'mode=' is deprecated and will be removed in vX.(Y+1).0.
  Use 'chain=on' instead of 'mode=auto', 'chain=off' instead of
  'mode=manual'.` (verbatim). The Phase 3 frontmatter continues to
  write the `mode:` field alongside the new `chain:` field during
  this window so legacy `/create-ticket brief=<path>` readers keep
  working; downstream readers (notably `/create-ticket`) implement
  the precedence rule `chain: precedes mode:` (read `chain:` first
  if present, fall back to `mode:`, default to `chain=on` when both
  keys are absent). The `mode=` argument, the `mode:` frontmatter
  field, and the `mode independence guard` defensive prose are
  scheduled for removal in vX.(Y+1).0. Migration: replace
  `/brief "X" mode=auto` with `/brief "X" chain=on` (or drop the
  argument entirely — `chain=on` remains the default) and
  `/brief "X" mode=manual` with `/brief "X" chain=off`. Combining
  both keys (`/brief "X" chain=on mode=auto`) is rejected with
  `ERROR: 'chain=' and 'mode=' cannot be combined. Use 'chain='
  (preferred).` and exits non-zero without writing any artifacts.

### Removed

- `permissionMode: acceptEdits` line from
  `agents/{implementer,planner,researcher,test-writer}.md` and from
  `agents/decomposer.md`. Per CC docs and the 2026-05-24 spike this
  field is silently ignored for plugin subagents — removal is a no-op
  cleanup that aligns all five agents to omit the field. Behaviorally
  equivalent settings can be set per-user via
  `~/.claude/settings.local.json` if needed.

### Fixed

- **`/ship` Step 15a is now idempotent and the post-ship integrity hook
  self-heals stale `phase-state.yaml` (P3-5)**. Field evidence
  (`test_simple_workflow34`) showed 4/5 tickets shipped with
  `overall_status: in-progress` paired with `phases.ship.status:
  in-progress` while the brief-side `autopilot-state.yaml` recorded
  every ticket as `steps.ship: completed` — the per-ticket `/ship`
  Step 15a write was systematically dropped under autopilot chaining.
  `skills/ship/SKILL.md` Step 15a now carries an explicit **PSI
  contract** paragraph (`Step 15a MUST run on every successful pass
  through Phase 2`, including the no-remote / no-commits-ahead /
  pre-existing-PR branches) and an **Ordering with Step 16** paragraph
  (`Step 15a MUST complete its write to disk BEFORE Step 16`'s
  `print PR URL and stop` early-exit). The companion safety net lives
  in `hooks/post-ship-state-auto-compact.sh` as new Gate 5.5
  (post-ship integrity self-heal), gated by
  `SW_POST_SHIP_INTEGRITY` (see `### Added` above for kill-switch
  semantics): for every ticket whose `steps.ship` just flipped to
  `completed`, the hook reads
  `.simple-workflow/backlog/done/{ticket-dir}/phase-state.yaml` and,
  when `overall_status: in-progress`, rewrites the four canonical
  scalars (`overall_status: done`, `current_phase: done`,
  `last_completed_phase: ship`, `phases.ship.status: completed`).
- **`hooks/post-ship-state-auto-compact.sh` Gate 5 + Gate 5.5 now read
  the on-disk brief-side `autopilot-state.yaml` instead of the
  Edit-tool payload fragment**. Field evidence
  (`test_simple_workflow35`) showed P3-5's Gate 5.5 self-heal never
  fired for the 5 ticket boundaries it was meant to cover, leaving
  ticket 001 with `overall_status: in-progress` despite the hook
  running 5 times — the exact `test_simple_workflow34` regression
  P3-5 was supposed to prevent. Root cause: both gates piped the
  Edit's `new_string` (a single-ticket YAML fragment lacking the
  top-level `tickets:` key) through `parse_ticket_ship_dirs`, whose
  yq query `.tickets | .[]` returns zero entries from such a
  fragment; the loops silently never iterated any ticket. The fix
  is a one-line source swap in each gate
  (`parse_ticket_ship_dirs "$TOOL_FILE_PATH"`) plus removal of the
  now-unneeded `mktemp + printf` payload-to-tempfile plumbing. The
  brief-side state file on disk already reflects the PostToolUse
  write at the time the hook fires, so the parse is always
  well-formed regardless of payload shape. Side effect: Gate 5
  (state-lie protection) now actually detects state-lies for the
  fragment-payload code path that has been the production norm
  since v6 (previously fail-open). Regression-guarded by new
  `tests/test-skill-contracts.sh` PSI AC-8 (fragment payload still
  triggers self-heal) and by hardening the existing CT-AC-12 /
  CT-AC-24 / CT-AC-25 fixtures to write the YAML into the state
  file instead of relying on the now-discarded payload-fragment
  parse path.

- **`hooks/scout-checkpoint-guard.sh` Step 2a (autopilot-completion gate)**: a new gate inserted between the kill switch (Step 2) and the phase-state.yaml short-circuit (Step 3) silent-exits the hook when no active autopilot is running, a fresh `briefs/done/<parent>/autopilot-state.yaml` exists (mtime within `SW_AUTOPILOT_DONE_GATE_TTL_SEC` seconds), and every `tickets[].status` is `completed`. The 3-AND (a)(b)(c) signature on the transcript tail (`plan2doc: ac-source=ticket.md verbatim=true` ssot-line + no `## [SW-CHECKPOINT]` + a `Skill(simple-workflow:scout)` invocation in the 5000-line window) is no longer evaluated under that condition, so post-autopilot Stop ticks stop emitting `decision: block` on stale transcript artifacts. Observability: the gate writes a one-line `[SCOUT-AUTOPILOT-DONE-GATE] silent exit (state=<path>, age=<seconds>)` diagnostic to stderr. Kill switch and TTL override:
  - `SW_AUTOPILOT_DONE_GATE_TTL_SEC` (new, default `86400`): TTL window in seconds; set `0` to disable the bound (gate fires on any all-completed done state); non-numeric values fall back to `86400` with a one-line stderr warning.
  - `SW_SCOUT_CHECKPOINT_MODE=off` (existing, unchanged): short-circuits Step 2 before Step 2a runs, preserving the v8.0.0 disable behaviour.

- **`hooks/lib/parse-state-file.sh` `find_done_autopilot_state_file [ttl_seconds] [start_dir]`**: new public helper that scans `briefs/done/**/autopilot-state.yaml`, returns the mtime-newest match whose mtime is within `ttl_seconds` (strict `<` comparison), and exits 1 on empty / aged-out / no-done-dir. Symlink resolution mirrors `find_state_file` (canonical absolute path via `cd ... && pwd -P`). Used by `scout-checkpoint-guard.sh` Step 2a. Exported alongside the existing public helpers so children that re-enter via `bash -c` pick it up without re-sourcing.

- **`hooks/autopilot-continue.sh` + post-ship hooks: missing git remote is a local-only ship, not a Phase 1 hard-stop.** Autopilot on a repository with no configured git remote (`origin` absent) now completes the ship phase locally (commit only, no push/PR) instead of hard-stopping at Phase 1. Greenfield local dogfoods (e.g. a fresh `colorforge` brief with no remote) run end-to-end.
- **The three autopilot Stop hooks now honour a model-declared `policy_gate_stop`.** When the orchestrator records a policy-gate stop in `autopilot-state.yaml`, the Stop hooks respect it instead of re-deriving continuation from transcript heuristics, so an intentional policy halt is not overridden by the loop guard.

### Verification

- **Release pre-flight (v8.0.0 consolidation, 2026-05-30)**: `bash tests/test-skill-contracts.sh` → 753 / 753 PASS and `bash tests/test-path-consistency.sh` → 140 / 140 PASS at the consolidated HEAD. The skill-contract Total includes the Phase 6 Advisory category (Cat AR: AR-1..10 implementer, AR-RES-1..9 researcher, AR-TW-1..6 test-writer, AR-PLN-1 negative, plus AR-INV-1/2, AR-TST-1, AR-SCT-1, AR-TRN-1/2/3 for the declarative-spawner gates and truncation mitigation). The full `tests/run-all.sh` suite runs green under ShellCheck (`--severity=warning` on `hooks/*.sh` and `tests/*.sh`) per `.github/workflows/ci.yml`.
- `bash tests/test-skill-contracts.sh` exit 0 with Total >= 598 (baseline
  580 + 8 new for Cat AN CT-AN-1..CT-AN-8 + 9 new for Cat AQ
  CT-AQ-1..CT-AQ-9 + 1 new for PSI AC-8 TW35 regression guard);
  current run reports 719 / 719 PASS. The Total above the 598 floor
  reflects Cat D's dynamic per-skill agent-name assertions growing as
  the v8.0.0 doctrine update referenced more agent names in the
  spawner SKILL.md bodies (Cat AL v7.0.4, Cat AM v7.1.0, Cat AQ
  Gate 6.5, and PSI Gate 5.5 fragment-payload invariants all intact).
- `bash tests/test-path-consistency.sh` exit 0 with the redesigned Cat 6
  (Group A omit + Group C retention) and Cat 11 (positive enumeration —
  zero `Bash(*)` declarations and exactly the 6 Group C agents carrying
  `^tools:`).
- `bash tests/test-pre-bash-safety.sh` exit 0 with Total 195 / 195 PASS.
  Every existing destructive / sensitive-staging / bulk-staging case
  still blocks; the new Category J adds 69 v8.0.0 assertions split
  into BLOCK (4 categories: network egress / identity spoofing /
  privilege escalation / branch-commit subversion) including bypass
  coverage (full-path and relative-path invocation, env-var prefix,
  `exec`/`time`/`nice`/`nohup` wrappers, `git push --no-verify` at any
  argument position with quoted-arg variants) and ALLOW (24 package-
  manager installs across all common languages plus `git remote add`,
  plus 12 false-positive sanity negatives for legitimate operations).
- Spike basis: 2026-05-24 CC 2.1.149 four-probe spike (user scope) plus
  `--plugin-dir` invocation (plugin scope) confirmed (a) omit-`tools:`
  inherits all including MCP, (b) exact-name `disallowedTools` blocks
  tools, (c) `mcp__*` glob in `disallowedTools` is NOT honored, and
  (d) `permissionMode` is a silent no-op for plugin subagents.
- Pre-flight: spawning 5 parallel general-purpose evaluator subagents on
  2026-05-24 found 9 unique problems in the original 7-agent transition
  plan; this release addresses all 9 (decomposer / code-reviewer /
  tune-analyzer moved to Group C, side-effect ban added, doctrine
  updated, `pre-bash-safety.sh` extended, Cat 6 + Cat 11 redesigned).

- `bash tests/test-hooks-lib.sh` → exit 0 (153/153 cases pass). New section `find_done_autopilot_state_file (v8.0.1)` adds 11 assertions across cases (a)–(f) covering: no `briefs/done/` (a), empty `briefs/done/` (b), single fresh match (c), multi-match newest-wins (d), aged-out TTL=60 (e), TTL=0 disables bound (e-bis), and non-numeric TTL coerces to 0 (f).
- `bash tests/test-scout-checkpoint-guard.sh` → exit 0 (14/14 cases pass). New fixtures **C9** (fresh done all-completed → gate silent-exits, stderr token visible), **C10** (active + done both fresh → `is_autopilot_context()` blocks the gate, 3-AND blocks decision), **C11** (year-2020 done state → stale, gate yields, decision=block), **C12** (`SW_SCOUT_CHECKPOINT_MODE=off` → kill switch wins before Step 2a, no gate token), **C13** (one `tickets[].status: failed` → gate fails closed, decision=block), **C14** (custom `SW_AUTOPILOT_DONE_GATE_TTL_SEC=60` + 120-second-old state → gate yields, decision=block). Existing C1–C8 continue to pass without modification. Case count 8 → 14.
- `bash tests/test-skill-contracts.sh` baseline → exit 0 (no skill contract surface touched).
- `bash tests/test-path-consistency.sh` baseline → exit 0 (no path invariant surface touched).

- `bash tests/test-skill-contracts.sh` exit 0 with Total 580
  (baseline 570 + 8 new for Cat AM CT-AM-1..7 plus the AC-12 trivial-
  pass assertion, + 2 more for the gap-closure follow-up:
  CT-AM-8 / CT-AM-9).
- `bash tests/test-path-consistency.sh` exit 0 with Total 139 unchanged
  (no path-consistency surface was touched).
- AC-13 backwards compatibility: existing pre-Gate-6 tickets in
  `.simple-workflow/backlog/done/` continue to drive `/impl`, `/audit`,
  `/ship` without parse failure — the deterministic handoff falls back
  to the prior ad-hoc path when `### Capabilities` is absent.

## [7.0.4] — 2026-05-23

Extend `ac-evaluator` with scoped Skill access so the verdict agent can
gather live runtime evidence (render the built artifact, capture console
output, measure WCAG contrast, take screenshots) for runtime and visual
acceptance criteria, instead of signing those off by static code
inspection. The agent's verdict-independence firewall is preserved by a
new `## External Tool Integration Policy` block that limits skill use to
evidence gathering — code authoring, AC-fixing, and letting a skill's own
output stand in for the verdict are all forbidden, and pipeline-skill
recursion remains banned. `security-scanner` and `ticket-evaluator` stay
hermetic by design. Drift-guards in `tests/test-skill-contracts.sh`
Category AL (CT-AL-1..5) lock the new shape in place.

### Added

- `Skill` tool granted to `agents/ac-evaluator.md`. Its new
  `## External Tool Integration Policy` section scopes use to
  evidence-only: skills are invoked solely to gather independent evidence
  about the *already-built* artifact under review (render it, exercise
  it, measure it, screenshot it). The agent MUST NOT use any skill to
  author, generate, or modify the implementation, to fix a failing AC,
  or to let a skill's own output substitute for its independent verdict.
  Pipeline-skill recursion (`/scout`, `/impl`, `/audit`, ...) is
  explicitly banned.
- New AC verification method 6 in `agents/ac-evaluator.md`: "Drive the
  rendered artifact with a browser-automation utility skill" — for
  runtime or visual ACs (live rendering, "no console errors", keyboard
  hover/focus states, WCAG contrast), when such a skill is offered the
  agent MUST gather live evidence; code inspection alone is not
  sufficient evidence to PASS such an AC.
- `skills/impl/SKILL.md` positive handoff bullet: when the plan carries
  runtime or visual ACs, the orchestrator hands `ac-evaluator` a
  browser-automation utility skill in its spawn prompt. The handoff is
  scoped to evidence-gathering utilities — never to a skill that authors
  or modifies the code under review.
- `tests/test-skill-contracts.sh` Category AL with CT-AL-1..5: drift
  guards that lock in (1) `- Skill` standalone entry in ac-evaluator's
  `tools:`, (2) `## External Tool Integration Policy` heading presence,
  (3) the evidence-only firewall prose (`MUST NOT ... author/generate/
  modify` plus `Never invoke pipeline skills`), (4) no spawner skill
  still excludes ac-evaluator from skill handoff, and (5)
  `skills/impl/SKILL.md` carries the positive browser-automation handoff
  bullet for ac-evaluator.

### Changed

- `agents/ac-evaluator.md` Status Decision: **PASS-WITH-CAVEATS is no
  longer available** for a runtime or visual AC when a browser-automation
  utility skill was offered in the spawn prompt or otherwise available.
  In that case the agent MUST gather live evidence (verification
  method 6) and render PASS or FAIL on what it observes, never
  PASS-WITH-CAVEATS on code inspection alone.
- `skills/{audit,brief,create-ticket,impl,investigate,plan2doc,refactor,test,tune}/SKILL.md`
  Subagent Skill-Access Handoff: `ac-evaluator` removed from the hermetic
  exclusion list (it now carries the Skill tool). `security-scanner` and
  `ticket-evaluator` remain excluded.
- `skills/impl/references/tautological-assertion-rules.md`:
  "ac-evaluator's available tools (Read, Grep, Glob)" narrowed to
  "ac-evaluator's text-inspection tools (Read, Grep, Glob)" in the
  Limitations section. The grep-based tautological-assertion rules
  continue to use only Read/Grep/Glob regardless of the new Skill tool's
  availability — the wording change documents that fact without altering
  rule scope.

### Verification

- `bash tests/test-skill-contracts.sh` exit 0 with new Category AL pass
  (CT-AL-1 through CT-AL-5).
- `bash tests/test-path-consistency.sh` exit 0 — Category 11 (`Bash(*)`
  restricted to `implementer` + `test-writer`) remains green; ac-evaluator
  gained Skill, not Bash(*).
- The evidence-only firewall in the new `## External Tool Integration
  Policy` is asserted by CT-AL-3 — a future drift PR that removes the
  `MUST NOT ... author/generate/modify` guard or the `Never invoke
  pipeline skills` bullet would fail the contract test.
- v7.0.3 Subagent Skill-Access Handoff exclusions for `security-scanner`
  and `ticket-evaluator` remain intact across all 9 spawner skills.

## [7.0.3] — 2026-05-21

Let the research-and-build subagents use the user's installed Skills.
Previously every subagent `tools:` allowlist omitted `Skill`, so an agent
could never invoke a user utility skill (e.g. a UI/UX or browser-automation
skill) even when the task plainly called for one. This release grants
`Skill` to the seven generator/investigator subagents and threads skill
discovery from the spawning skills into the Agent prompt, so a relevant
skill is used automatically when present and silently ignored when absent.
The three verdict/security subagents (`ac-evaluator`, `security-scanner`,
`ticket-evaluator`) stay hermetic by design. No behaviour change for users
who have no extra Skills installed.

### Added

- `Skill` tool granted to the 7 generator/investigator subagents
  (`researcher`, `planner`, `implementer`, `test-writer`, `code-reviewer`,
  `decomposer`, `tune-analyzer`). The 3 hermetic subagents (`ac-evaluator`,
  `security-scanner`, `ticket-evaluator`) intentionally omit it so their
  verdicts and security audits stay deterministic.
- "External Tool Integration Policy" block in each of the 7 Skill-enabled
  agent bodies: prefer a relevant utility skill when it materially helps,
  never recurse into the 13 pipeline skills, and degrade gracefully when
  none is available.
- "Subagent Skill-Access Handoff" block plus an `Available user skills:`
  pre-computed-context probe in the 9 skills that spawn those subagents
  (`/investigate`, `/plan2doc`, `/impl`, `/test`, `/audit`,
  `/create-ticket`, `/refactor`, `/brief`, `/tune`). The spawner enumerates
  installed skills at load time and passes any relevant one into the Agent
  prompt; the 3 hermetic subagents are explicitly excluded from the handoff.

### Verification

- `tests/test-path-consistency.sh` 139/139, `tests/test-skill-contracts.sh`
  572/572, `tests/run-all.sh` exit 0.
- Dogfood (`/brief mode=auto` in a sibling test repo, 2026-05-21): 4 subagent
  invocations of an installed `ui-ux-pro-max` skill (researcher ×2, planner,
  implementer), with the full probe → handoff → use chain confirmed in the
  JSONL transcripts; the main thread never invoked the skill directly; the 3
  hermetic subagents made zero skill calls; no permission denials.

## [7.0.2] — 2026-05-19

Fix the auto-`/compact` resume path that silently no-op'd when a hook
fired with a cwd under `.simple-workflow/<subdir>/` (e.g. a `/tune`
skill body that left cwd at `.simple-workflow/kb/`). Field evidence
`test_simple_workflow29` (session
`8f7dff21-c491-4fc2-ada0-20f2bb814fd4`): after a clean post-ship
`/compact`, `SessionStart(source=compact)` Axis 3 resume injection
silently skipped because cwd-relative writes from prior hooks had
materialised a decoy nested `.simple-workflow/kb/.simple-workflow/`,
which `_psf_repo_root` accepted as a valid autopilot root. The
pipeline then idled in user-input-wait state until the user typed
manually. Two-layer defence: T-01 tightens the `_psf_repo_root`
anchor so the symptom cannot recur, T-02/T-03 prevent the upstream
hooks from writing the nested directory in the first place.

### Fixed

- `hooks/lib/parse-state-file.sh` `_psf_repo_root` (T-01) — anchor
  condition tightened from `[ -d "$dir/.simple-workflow" ]` to
  `[ -d "$dir/.simple-workflow" ] && [ -d "$dir/.simple-workflow/backlog" ]`.
  A nested decoy `.simple-workflow/<subdir>/.simple-workflow/`
  created by a cwd-relative write can no longer be mistaken for the
  autopilot root. Zero false-negative risk: `backlog/` is created at
  the very first `/brief` step and is present throughout the
  lifetime of any autopilot context. The companion
  `_sa_repo_root` in `hooks/lib/state-authority.sh` is intentionally
  untouched (separate contract; F-RR docstring already documents the
  divergence).
- `hooks/session-start.sh` opening setup block (T-02) — every bare
  `.simple-workflow/...` literal at lines 14-115 (compact-state
  cleanup, session-log cleanup, `.setup-done` existence check,
  `mkdir`/`touch` that materialises the flag) now resolves against
  the absolute `$_sw_repo_root` prefix. `_sw_repo_root` is resolved
  once at the top of the file via `git rev-parse --show-toplevel ||
  pwd` (net-zero line count — the redundant resolution that previously
  lived at line 156 is removed). The Axis 3 resume injection block
  (lines 233-281) is byte-identical to the prior version.
- `hooks/session-stop-log.sh` `LOG_DIR` (T-03) — `LOG_DIR` now
  resolves to `"$_sw_repo_root/.simple-workflow/docs/session-log"`.
  `_sw_repo_root` is resolved at the top of the file via the
  shared `_psf_repo_root` helper (sourced from
  `hooks/lib/parse-state-file.sh`). When invoked from a cwd of
  `.simple-workflow/<subdir>/` the Stop hook write now lands in the
  real `.simple-workflow/docs/session-log/`, not in a nested
  `.simple-workflow/<subdir>/.simple-workflow/docs/session-log/`.

### Verification

- `bash tests/test-hooks-lib.sh` — 138 / 138 pass (baseline 132;
  +6 new tests under the `--- _psf_repo_root strict anchor (T-01) ---`
  section: positive walk-up, decoy skip, `is_autopilot_context`
  regression under nested cwd, `find_any_autopilot_state_file`
  regression under nested cwd, empty-`.simple-workflow/` skip).
- `bash tests/test-session-start.sh` — 36 / 36 pass (baseline 30;
  +6 new assertions across cases C8/C9/C10: nested-cwd no-op for
  setup block, 30-day session-log cleanup under absolute path,
  `additionalContext` `Branch:` substring still emitted).
- `bash tests/test-session-stop-log.sh` — 12 / 12 pass (baseline
  10; +2 new assertions in Test 11: nested-cwd produces no decoy,
  log file lands in the real root).
- `bash tests/test-skill-contracts.sh` — 501 / 501 pass (unchanged
  baseline; this patch does not touch the contract surface).
- `bash tests/test-path-consistency.sh` — 139 / 139 pass (unchanged
  baseline).
- `bash tests/run-all.sh` — ALL TEST SUITES PASSED.

## [7.0.1] — 2026-05-18

Docs-only patch. The v7.0.0 release introduced the auto-`/compact`
ticket boundary but did not document what the host terminal needs to
expose for keystroke injection to actually fire. README now lays out
the support matrix, the iTerm2 multi-window limitation
(AppleScript's `windows` collection is empty, so only `current
window` is reachable — multi-iTerm-window cases hard-fail with a
diagnostic), and the explicit non-support for Apple Terminal, Warp,
Ghostty, and Windows terminals. The recommendation is unchanged: run
`claude` inside tmux for any unattended autopilot run.

### Changed

- `README.md` — replaced the single "Supported terminals" bullet in
  the **Auto-`/compact` between autopilot tickets** section with a
  new `#### Terminal requirements for keystroke injection`
  sub-section. The sub-section documents (1) the five supported
  backends and their extra setup (kitty `allow_remote_control yes`,
  iTerm2 macOS Automation permission), (2) the iTerm2
  single-iTerm-window limitation, (3) the explicit non-support set
  (Apple Terminal — deliberately excluded for focus-leak risk; Warp,
  Ghostty, Windows — no pane-targeted send-text CLI exists), and
  (4) the tmux recommendation for unattended runs. No behaviour
  change — `hooks/lib/inject-keys.sh` is unchanged.

### Fixed

- `tests/test-skill-contracts.sh` CT-AC-17 — dropped the `head -40`
  window when locating the `## [7.0.0]` header; it now greps the
  full file. The original window assumed v7.0.0 stayed the topmost
  CHANGELOG entry forever and broke as soon as v7.0.1 pushed the
  header past line 40, blocking pre-flight for every subsequent
  patch. Test intent (verify the v7.0.0 entry exists with the right
  format + group headers + opt-out env-var sentence) is preserved.

### Verification

- `bash tests/test-skill-contracts.sh` — 501 / 501 pass (unchanged
  baseline; docs-only patch does not exercise the contract suite).
- `bash tests/test-path-consistency.sh` — 139 / 139 pass (unchanged
  baseline).

## [7.0.0] — 2026-05-17

Major release that fires `/compact` at the **ticket boundary** of every
multi-ticket `/autopilot` run by default, so long-running pipelines no
longer hit the conversation-context ceiling between tickets. Compact is
injected via PTY keystroke from two new hooks that work together:
`hooks/pre-next-scout-auto-compact.sh` (primary, PreToolUse on the next
ticket's `Skill(simple-workflow:scout)`) catches the canonical boundary;
`hooks/post-ship-state-auto-compact.sh` (safety net, PostToolUse on
`Edit/Write` that writes `steps.ship: completed` to autopilot-state.yaml)
catches the last-ticket case and any flow change that bypasses the next
`/scout`. Both share `hooks/lib/inject-keys.sh` for terminal-aware
injection and `.auto-compact-pending` for queue-drain coordination with
`hooks/autopilot-continue.sh` (Stop yield) and `hooks/session-start.sh`
(post-compaction `/autopilot {parent-slug}` resume kick). State-lie
protection (safety net Gate 5) and a 300s loop-detection marker
(primary Gate 5) close the failure modes observed in
`test_simple_workflow22` (compact-loop) and `test_simple_workflow23`
(model state-LIED at PostToolUse(Skill:ship) trigger time, then DEFIED
the additionalContext on subsequent ships).

Pre-merge skeptical review (five-axis: hook concurrency, model
defection, PTY injection, test coverage, architecture) caught and
fixed four critical pre-release defects: **CD-1/CD-2** — the safety
net's Gate 5 awk parser exited at the first `ship: completed` and
returned whatever `ticket_dir:` was last seen, silently bypassing
state-lie protection on multi-ticket payloads and on shuffled
within-element key orders (verified reproducer); now element-scoped
via the new `parse_ticket_ship_dirs` helper in
`hooks/lib/parse-state-file.sh`. **C3** — `tmux send-keys` and
`screen -X stuff` had no target-pane/window argument, so a user pane
switch between turn-start and hook fire would inject `/compact<Enter>`
into vim / ssh / log-tail; now targeted via `-t "$TMUX_PANE"` and
`-p "$WINDOW"` with graceful fallbacks. **C4** — `skills/autopilot/SKILL.md`
step e named the `` `/compact` has been queued`` label with
`` \`/compact\``` backslash escapes while the hooks emit the literal
backtick form, so substring-match between SKILL.md and runtime
additionalContext drifted; now byte-for-byte aligned and locked
under CT-AC-27.

A field-reported window-focus reproducer surfaced one more
critical defect that the C3 fix only partially closed: **WI-1**
— `hooks/lib/inject-keys.sh` shipped C3 protections only for
tmux and screen. The other three backends had the same
focus-leak class: iTerm2's AppleScript used `tell current session
of current window`, which resolves at osascript runtime to the
currently focused iTerm window — so the user's reproducer
(`brief mode=auto` in iTerm window A, focus iTerm window B, hook
fires) caused `/compact<Enter>` to be typed into window B's
shell. kitty's `kitty @ send-text` defaults to the focused kitty
window with the same outcome. WezTerm's CLI happens to infer the
caller's pane from `$WEZTERM_PANE` implicitly, but the explicit
flag was missing. All three are now fixed: iTerm2 targets the
originating session by `$ITERM_SESSION_ID` UUID via an
AppleScript session-id lookup (refuses to fall back to the
focused window — that would defeat the fix); kitty targets the
originating window via `--match id:$KITTY_WINDOW_ID`; WezTerm
explicitly passes `--pane-id $WEZTERM_PANE`. Each backend falls
back to its pre-WI-1 untargeted call when the relevant env var
is absent, so degraded execution still attempts injection rather
than silently no-op. CT-AC-46/47/48 lock in the source + DRY_RUN
contracts.

A `test_simple_workflow26` dogfood run revealed a follow-on
defect in the WI-1 iTerm2 implementation: **WI-2** — the
AppleScript iterated `repeat with w in windows`, but
**iTerm2's AppleScript does not populate the standard
`windows` collection**. Live probes (`count of windows`,
`every window`, `name of every window`) all return 0 even
when iTerm has active terminal windows; only `current window`
is reachable. The WI-1 iteration was therefore always empty,
producing `iTerm session <UUID> not found in any window` for
every inject attempt regardless of whether the user had
switched focus. (CT-AC-48 still passed because the test
stubbed `osascript`, so the broken live AppleScript was never
exercised.) The fix narrows the iteration to `tabs of current
window`, which fixes the practical cases (different tab in
same iTerm window, different pane in same iTerm window, focus
moved to a non-iTerm app) at the cost of admitting that
**different iTerm WINDOWS are unsolvable via AppleScript**:
iTerm2 simply does not expose an enumeration API for them.
For multi-iTerm-window workflows the failure message now
recommends tmux, and the docstring captures the limitation
explicitly. Live verification: the originally-failing UUID
`80E38DE0-…` from the field session is found by the new
iteration on the same machine + iTerm version.

A second `test_simple_workflow27` dogfood run surfaced a much
deeper defect that affected every earlier "working" run by sheer
luck: **WI-3** — the v7 auto-compact hooks gated on the literal
substring `ship: completed` (Gate 2 payload regex, shipped_count
grep anchor, `parse_ticket_ship_dirs` yq predicate
`.steps.ship == "completed"`). The canonical state-file.md schema
DOES write `steps.ship: completed` as a flat string value, but
the autopilot orchestrator in test_simple_workflow27 wrote the
NESTED form `steps.ship: {status: completed, invocation_method:
skill}` — fusing the canonical sibling map
`invocation_method.{step}` into the per-step map. Every gate in
both hooks therefore missed every ship: completed write, the
shipped_count stayed at 0 for the entire 53-minute / 3-ticket
pipeline, and zero `/compact` were injected. Earlier dogfood runs
(`test_simple_workflow24` / `26`) happened to choose the flat
form and so appeared to work. The fix has two layers: (a)
**hook robustness** — Gate 2 now accepts the nested form via a
small POSIX-awk state machine alongside the flat-form regex, and
both hooks compute shipped_count via `parse_ticket_ship_dirs`
(yq → python3+PyYAML → POSIX awk; tolerates both shapes plus
`tickets:` as either list or map); (b) **SKILL enforcement** —
`autopilot/SKILL.md` step 3d post-condition now says **MUST emit
the canonical FLAT schema** with an explicit anti-pattern block,
and `references/state-file.md` adds a "Schema invariants" section
showing the canonical and forbidden forms side-by-side. CT-AC-45
is rewritten to verify the YAML-aware helper (not the
now-superseded M7 strict grep anchor) and CT-AC-49 reproduces the
exact test_simple_workflow27 T-001 ship-completed payload to
prove the safety-net reaches the dispatcher under the nested
schema.

A third `test_simple_workflow28` dogfood run (parent_slug
`pomodoro-timer-web-app`, brief mode=auto, full pipeline 3/3
shipped 2026-05-17 13:01Z→14:05Z) revealed a follow-on schema slip
that WI-3 did not cover: **WI-4** — the autopilot orchestrator
wrote `tickets:` as a MAP keyed by `logical_id`
(`pomodoro-timer-web-app-part-1: { ... }`) instead of the
canonical LIST (`- logical_id: pomodoro-timer-web-app-part-1`)
that `references/state-file.md` documents. `parse_ticket_ship_dirs`
already tolerated both shapes after WI-3 (`yq .tickets | .[]`
iterates either; Python tier branches on `isinstance(dict|list)`;
awk recognises both openers), so auto-compact worked correctly on
test28. However TWO other hook surfaces remained LIST-only and
**silently bypassed** when given the MAP form:
**(a) `parse_ticket_statuses`** in `hooks/lib/parse-state-file.sh`,
used by `hooks/autopilot-continue.sh` to count ticket statuses for
Stop-hook loop-guard runtime_metrics; **(b) `parse_proposed_tickets`**
in `hooks/pre-state-transition.sh`, the PreToolUse:Write/Edit guard
that blocks `unauthorized_skip_with_active_siblings` and
`unauthorized_skip_with_forbidden_rationale`. Either bypass is a
security-relevant regression because a MAP-form state file could
mark a ticket `skipped` with a forbidden rationale while siblings
are `in_progress` and the guard would let the write through. The
fix has two layers, mirroring WI-3: **(a) hook robustness** —
`parse_ticket_statuses` is extended across all three tiers (yq
predicate switches to `.tickets | .[] | .status // ""`; Python
tier branches on `isinstance(tickets, dict|list)`; awk fallback
recognises the `^  <key>:` map-form opener alongside the existing
`^[[:space:]]*-` dash opener). `parse_proposed_tickets` gets the
same treatment in both its Python tier and the pure-shell
`_pst_shell_parse` fallback, and the hook script is restructured
to allow safe sourcing (function definitions hoisted above a
`BASH_SOURCE != $0` sourcing guard) so the new contract test can
call `parse_proposed_tickets` directly. **(b) SKILL enforcement** —
`autopilot/SKILL.md` State file initialization step now carries an
inline sentence stating `tickets:` MUST be emitted as a YAML list,
and `references/state-file.md` adds a "Schema invariants —
`tickets:` is a YAML list" sub-section parallel to the WI-3
`steps.ship` block, showing the canonical list form and the
MAP anti-pattern side-by-side with the
`pomodoro-timer-web-app-part-1:` literal as the field reproducer.
The two new contract tests **CT-AC-50** (parse_ticket_statuses
MAP/LIST parity across all three tiers via stubbed PATH) and
**CT-AC-51** (pre-state-transition MAP-form invariant guard
reproduces the silent-bypass regression on a MAP-form Edit payload)
lock the fix.

Phase 3 defensive / observability improvements (H9, H11-H12, M4, M7)
land in the same release to avoid an immediate v7.0.1 follow-up:
**H9** — `inject_keys` failure path now produces a disambiguating
hint (backend identity + specific remediation) instead of the
single "unsupported terminal" blanket message that masked kitty's
`allow_remote_control no` default, iTerm2's macOS Automation TCC
prompt, and WezTerm's `--no-paste` flag-rejection cases.
**H11** — `INJECT_KEYS_DRY_RUN=1` alone no longer
short-circuits the dispatcher; `SW_TEST_HARNESS=1` must also be
set, so a leaked profile-level `INJECT_KEYS_DRY_RUN=1` cannot
silently disable every auto-compact. **H12** — CT-AC-43 replaces
CT-AC-23's manual `rm -f` sentinel-simulation with a real
`hooks/autopilot-continue.sh` invocation, proving the full
safety-net → Stop-hook yield → primary post-resume short-circuit
contract end-to-end. **M4** — both hooks record one
`runtime_metrics` entry per successful injection
(`boundary: auto_compact_inject; stop_reason: primary | safety_net`)
so users can correlate `/compact` fires with state transitions
for forensics. **M7** — both hooks tighten the `shipped_count`
grep anchor from `^[[:space:]]+ship: completed` (matches
anywhere) to `^      ship: completed$` (canonical 6-space yq
indent + end-of-line) so a stray `ship: completed` literal in a
`runtime_metrics` note, free-form commentary, or future field
addition cannot inflate `shipped_count` and skew Gate 5
loop-detection. (Two findings from the original review — **H4**
atomic marker write and **H10** slug sanitization — were
intentionally NOT applied: H4's race window only opens if two
hook invocations of the same kind run concurrently, which the
Claude Code event model does not produce; H10 protects against a
slug source that is autopilot-internal, so a tampering attacker
already has greater capability via direct `autopilot-state.yaml`
writes. Both were judged over-engineering for the actual threat
profile, and dropping them keeps the hook surface smaller and
avoids the lock-step duplication that H4 introduced.)

The same pre-merge review surfaced eight high-risk concerns that
landed as Phase 2 hardening in the same release (H4 was
intentionally dropped — see the over-engineering note above):
**H5** — the safety net's `STATE_FILE_PATH` was derived from the
most-recently-modified state file across all briefs, which could
place the sentinel and loop-guard markers in the wrong brief when
two were concurrently active; now derived deterministically from
the just-written `$TOOL_FILE_PATH`. **H6** — `hooks/autopilot-continue.sh`
rm'd the sentinel unconditionally BEFORE the freshness check,
discarding observability on stale paths and creating a brief race
window when `cat` failed mid-read; the rm now lives in each
decided branch (fresh: remove + yield; stale: remove + log + fall
through). **H7**
— the safety net's additionalContext now branches on
`shipped_count == total_tickets`: for the FINAL ticket it asks the
model to complete the post-loop phase (Split Autopilot Log →
Completion Report → Brief Lifecycle → State File Cleanup) BEFORE
end_turn, instead of the literal-compliance failure mode where a
last-ticket end_turn-now would skip those terminal writes. **H8**
— the `SW_AUTO_COMPACT_ON_SHIP_MODE` kill switch is now documented
in `README.md` (Operational Notes section), `ARCHITECTURE.md`
(Context Conservation Protocol), and `CLAUDE.md` (Runtime env knobs)
so users can discover the opt-out without reading hook source.
**H1–H3 test gap closure** — CT-AC-28, CT-AC-30..39 close every
missing branch from the safety net's Gates 3/4/5/6 and the primary's
Gate 5 stale path, plus a Write `tool_input.content` path (the hook
registers under both Edit and Write but Phase 1 fixtures exercised
only Edit). 11 new contract assertions land in `tests/test-skill-contracts.sh`.

### BREAKING CHANGES

- **Auto-`/compact` now fires at the end of every ticket loop inside an
  `/autopilot` pipeline by default** (strict boundary = right before the
  next ticket's `/scout` is invoked, or as a safety net at the moment
  the orchestrator writes `steps.ship: completed`). Existing
  `/autopilot` users will see `/compact` injected into the controlling
  PTY between tickets with no configuration change. Mid-pipeline
  `/compact` is safe by design because autopilot's resume contract
  (`autopilot-state.yaml` + `hooks/pre-compact-save.sh` snapshot +
  `hooks/autopilot-continue.sh` + `hooks/session-start.sh` PTY-injected
  `/autopilot {parent-slug}` after compaction) is documented at
  `skills/autopilot/SKILL.md:180` as the canonical context-pressure
  response. **To preserve the prior behaviour (no auto-`/compact`), set
  `SW_AUTO_COMPACT_ON_SHIP_MODE=off` in your environment.** On
  unsupported terminals (Apple Terminal, Windows, anything outside
  tmux / GNU screen / kitty / WezTerm / iTerm2) both hooks are silent
  no-ops; the underlying `/scout` and `Edit/Write` are never blocked.
- **The v6 hook `hooks/post-ship-auto-compact.sh` is removed and
  replaced.** It fired on `PostToolUse(Skill: simple-workflow:ship)` —
  which Claude Code emits when the `/ship` skill is *invoked* (the
  "Launching skill" tool_result lands ~50ms after the Skill tool call),
  not when the skill body actually completes its work. Field evidence
  from `test_simple_workflow23` (session
  `e47e7151-1081-47f6-a484-fe99eb5624c1`, 3-ticket pipeline): on T-001
  ship #1 the model state-LIED (wrote `ship: completed` to
  autopilot-state.yaml before any git commit) and end_turned, so
  `/compact` did fire but on bogus state; on T-002 (10:22:56) and T-003
  (10:40:25) the model recognised the same trap and explicitly DEFIED
  the additionalContext (text at 10:23:23: "T-001 と同じ問題: hook が
  /ship body 実行**前**に発動。literal compliance だと state lie になり
  ... /ship body を inline 実行してから..."), executing the full `/ship`
  body inline without end_turning — so no auto-`/compact` happened
  between tickets at all. Root cause: PostToolUse(Skill) is the wrong
  event for "ship completed"; there is no "skill completed" hook in
  Claude Code's model. The v7 redesign waits until the autopilot
  orchestrator GENUINELY writes `steps.ship: completed` to disk
  (safety net) or the next ticket's `/scout` is about to launch
  (primary), both of which happen AFTER the entire ship body — including
  the chained `/tune` Step 6 — has run.

### Added

- **`hooks/pre-next-scout-auto-compact.sh`** — new PreToolUse(Skill)
  hook (primary trigger). Fires when the autopilot orchestrator invokes
  `Skill(simple-workflow:scout)` AND at least one prior ticket has
  `steps.ship: completed` in `autopilot-state.yaml` (i.e. this is the
  start of a NON-FIRST ticket). At that point the previous ticket's
  full pipeline (scout → impl → audit → ship → tune) has completed and
  the model is about to start a fresh ticket — exactly the cadence the
  user asked for ("one /compact at the end of each ticket loop"). On
  inject success the hook writes `<state_dir>/.auto-compact-pending`
  (UNIX timestamp) so `autopilot-continue.sh` can yield the next Stop
  tick, and returns an `additionalContext` payload that asks the model
  to end the turn WITHOUT invoking the next `/scout`. Gate 5
  state-consistency check (`<state_dir>/.auto-compact-last-attempt`,
  format `{shipped_count}:{unix_timestamp}`): if the shipped-ticket
  count is unchanged from the previous attempt within 300s, the inject
  is skipped to break any residual loop. Default ON within autopilot
  (`SW_AUTO_COMPACT_ON_SHIP_MODE=off` to opt out). Alternative mode
  `metric-only` emits additionalContext without injection.
- **`hooks/post-ship-state-auto-compact.sh`** — new PostToolUse(Write/
  Edit) hook (safety net). Fires when `tool_input.file_path` matches
  `**/autopilot-state.yaml` AND `tool_input.new_string` /
  `tool_input.content` contains `ship: completed`. Catches the
  last-ticket case (no next `/scout` follows) and any future autopilot
  flow change that bypasses `/scout` as the next-ticket entry point.
  Gate 5 state-lie protection (**element-scoped — CD-1/CD-2 fix**):
  enumerates every `tickets[]` element whose `steps.ship == "completed"`
  in the just-written payload via the new `parse_ticket_ship_dirs`
  helper, resolves each element's `ticket_dir:` against the repo root
  (with the `backlog/active/` → `backlog/done/` rewrite for in-flight
  paths), and refuses to inject when ANY element references a
  directory that does not exist under `backlog/done/`. The previous
  single-pass awk exited at the first `ship: completed` match and
  returned whatever `ticket_dir:` was last seen anywhere upstream,
  which silently passed Gate 5 when a multi-ticket payload had a
  genuine done/-dir T-001 followed by a lying active/-dir T-002 (CD-1)
  and on shuffled within-element key orders where `steps:` appeared
  textually before `ticket_dir:` (CD-2 — the element inherited the
  previous element's dir). Both bypasses are closed structurally at
  the parser layer; CT-AC-24 and CT-AC-25 lock in the regression.
  Gate 6 dedup: if a fresh `.auto-compact-pending` sentinel (<=120s)
  is already present, the primary trigger already fired for this
  boundary and the safety net short-circuits. Gate 7 cross-hook
  loop-guard (test_24 fix): reads/writes the SAME
  `<state_dir>/.auto-compact-last-attempt` marker the primary's
  Gate 5 uses, so a /compact triggered by the safety-net is detected
  by the primary on the post-compact-resumed `/scout` (and vice versa
  for safety-net firing twice for split Edit calls). Without Gate 7
  the user observes TWO `/compact` per ticket boundary because
  `.auto-compact-pending` is consumed by `hooks/autopilot-continue.sh`
  when yielding the Stop tick — the sentinel does NOT survive the
  compact/resume cycle, so the marker-file is the only shared state
  between the two hooks across the boundary (test_simple_workflow24
  evidence: 5 `/compact` invocations over 3 tickets, expected 2 — see
  Verification section).
- **`hooks/lib/inject-keys.sh`** — shared library exporting
  `inject_keys "<text>" [--enter|--no-enter]`, a terminal-aware
  keystroke injector. Multiplexer-first detection
  (tmux > screen > kitty > WezTerm > iTerm2). Apple Terminal is
  deliberately not supported — the macOS Accessibility keystroke API
  is system-wide and would focus-leak to other apps.
  `INJECT_KEYS_DRY_RUN=1` for test fixtures. **Every backend targets
  the ORIGINATING surface** (pane / window / session) rather than
  whichever the user is focused on at injection time, closing the
  focus-leak failure mode for all five supported terminals: tmux
  via `-t "$TMUX_PANE"` (C3), screen via `-S "$STY" -p "$WINDOW"`
  (C3), kitty via `--match id:$KITTY_WINDOW_ID` (WI-1), WezTerm via
  `--pane-id "$WEZTERM_PANE"` (WI-1, defense-in-depth even though
  the CLI infers it implicitly), iTerm2 via an AppleScript
  session-id lookup keyed on the UUID portion of
  `$ITERM_SESSION_ID` (WI-1). The iTerm2 path explicitly raises an
  AppleScript `error "iTerm session ... not found in any window"`
  rather than falling back to `current session of current window`
  — silently routing to the focused window would defeat the whole
  fix. Each backend falls back to its pre-targeting untargeted
  call only when the relevant env var is absent (degraded
  execution still attempts injection). DRY_RUN log is
  backend-aware: `target=` shows the value of the per-backend
  identifier so CT-AC-26 / CT-AC-46..48 can audit the contract.
- **`hooks/lib/parse-state-file.sh`** — adds `find_any_autopilot_state_file
  [start_dir]` (slug-free state-file locator used by both new hooks) and
  `parse_ticket_ship_dirs <file_path>` (element-scoped YAML parser used
  by the safety net's Gate 5; three-tier yq → python3+PyYAML → POSIX
  awk fallback matching the existing helpers' policy). The
  element-scoped parser is the structural fix for CD-1 / CD-2 — it
  pairs each `steps.ship` status with the ticket_dir of the SAME
  `tickets[]` element regardless of within-element key order.

### Changed

- **`hooks/autopilot-continue.sh`** — Stop hook continues to consume
  `<state_dir>/.auto-compact-pending` exactly as in v6.x (yield Stop
  tick, delete sentinel, emit `[AUTO-COMPACT-YIELD]` + `session_end`
  runtime metric with `stop_reason=auto_compact_yield`, stale sentinels
  >120s deleted and ignored). No behavioural change — the sentinel
  contract is shared verbatim between the v6 and v7 producers.
- **`hooks/session-start.sh`** — post-compaction resume kick continues
  to PTY-inject `/autopilot {parent-slug}` on `source=compact` events
  when an autopilot run is in_progress AND
  `SW_AUTO_COMPACT_ON_SHIP_MODE != off`. No behavioural change — the
  resume kick is shared verbatim between v6 and v7.
- **`skills/autopilot/SKILL.md`** — Step 3d (ship) post-condition is
  simplified back to the standard `CHECKPOINT — RE-ANCHOR` (no
  AUTO-COMPACT EXCEPTION inline). The exception block now lives at
  step e (loop-tail) and names BOTH new hooks' additionalContext
  labels: `auto-compact-on-ship (ticket-boundary):` from the primary
  and `auto-compact-on-ship (state-write safety-net):` from the safety
  net, immediately followed by the literal `` `/compact` has been queued ``
  (C4 fix). Labels are written with the SAME byte sequence the hooks
  emit at runtime so substring-match between SKILL.md and the
  additionalContext is one-to-one; the previous
  `` \`/compact\`` `` backslash-escape rendering risked the model
  classifying the present payload as "label did not match" and
  defaulting back to the strict "Do NOT end turn" rule. CT-AC-27
  enforces byte-for-byte equality. When EITHER label is present, the
  orchestrator end_turns immediately instead of iterating to the next
  ticket; after compaction, the resume contract
  (`autopilot-continue.sh` + `[RESUME] Skipping {logical_id}: already
  completed`) picks the NEXT ticket up from `autopilot-state.yaml`
  (the just-completed ticket is already `steps.ship = completed`, so
  resume skips it). The v6.x two-step "State update first, end_turn
  second" ordering is removed — by the time either new hook fires,
  the orchestrator has already written `steps.ship: completed` to
  disk (it is the safety-net's trigger condition, and the primary's
  precondition).

### Removed

- **`hooks/post-ship-auto-compact.sh`** — replaced by the two-hook
  v7 design above. See BREAKING CHANGES for the rationale and
  `test_simple_workflow23` evidence.

### Verification

- `bash tests/test-skill-contracts.sh` exits 0 with 499 / 499 PASS,
  including the 47 assertions CT-AC-01..28, CT-AC-30..40,
  CT-AC-42..49 (CT-AC-29 and CT-AC-41 retired with H4 and H10 —
  see the over-engineering note above) covering:
  both hooks' presence + executability (CT-AC-01); `inject_keys` export
  (CT-AC-02); hooks.json registration of both new hooks as independent
  top-level entries AND absence of the removed v6 hook (CT-AC-03);
  primary trigger functional fixtures — non-scout silent no-op,
  non-autopilot context silent no-op, first-ticket scout silent no-op,
  default-on dispatcher reach, opt-out silent no-op, metric-only
  emission (CT-AC-04..09); safety-net trigger functional fixtures —
  wrong file_path silent no-op, missing `ship: completed` silent no-op,
  state-lie protection (done/ dir absent → skip), dedup against fresh
  primary sentinel, valid state-write dispatcher reach (CT-AC-10..14);
  5-backend dispatcher coverage + Apple Terminal exclusion (CT-AC-15);
  both hook docstrings document kill-switch / PTY dependency / silent
  no-op (CT-AC-16); CHANGELOG v7.0.0 shape + opt-out env migration
  sentence (CT-AC-17); primary hook sentinel creation (CT-AC-18);
  Stop-hook yield-and-delete contract (CT-AC-19); end_turn coordination
  spanning both hooks' additionalContext + SKILL.md step e
  AUTO-COMPACT EXCEPTION naming both hooks (CT-AC-20);
  SessionStart:compact resume-kick three-path contract (CT-AC-21);
  primary loop-detection three-path contract (CT-AC-22); cross-hook
  loop-guard marker sharing (test_simple_workflow24 double-compact fix)
  — safety-net writes `.auto-compact-last-attempt`, primary reads it
  on the post-compact-resumed `/scout`, both skip duplicates within
  300s (CT-AC-23); **CD-1 fix** — element-scoped state-lie protection
  blocks a multi-ticket payload when ANY element references a missing
  done/ dir (CT-AC-24); **CD-2 fix** — element-scoped parser pairs
  `ship` / `ticket_dir` in any within-element key order, defeating the
  awk-inheritance bypass (CT-AC-25); **C3 fix** — dispatcher targets
  the calling pane/window (`tmux -t "$TMUX_PANE"` /
  `screen -p "$WINDOW"`) and DRY_RUN log exposes `target=…` for audit
  (CT-AC-26); **C4 fix** — SKILL.md AUTO-COMPACT EXCEPTION label
  literals are byte-for-byte identical with hook additionalContext
  (grep -F equality + legacy `` \`/compact\``` backslash-escape
  regression guard) (CT-AC-27); **H5 fix** — safety-net derives
  `STATE_FILE_PATH` from `$TOOL_FILE_PATH` so markers land in the
  just-written brief regardless of mtime (CT-AC-28); **H7 fix** —
  safety-net additionalContext branches on last-ticket vs non-last,
  with the last-ticket branch requiring the post-loop completion
  phase before end_turn (CT-AC-30 / CT-AC-31); **H8 fix** —
  `SW_AUTO_COMPACT_ON_SHIP_MODE` kill switch documented in
  `README.md`, `ARCHITECTURE.md`, and `CLAUDE.md` (CT-AC-32);
  **H1–H3 closure** — safety-net Gate 3 defence-in-depth (CT-AC-33),
  Gate 4 kill-switch (CT-AC-34), Gate 4 metric-only (CT-AC-35),
  Gate 5 active→done rewrite (CT-AC-36), Gate 6 stale sentinel
  >120s (CT-AC-37), Write `tool_input.content` path (CT-AC-38),
  primary Gate 5 stale >300s (CT-AC-39). Also: CT-AC-19 extended
  to cover the H6 fresh/stale sentinel-rm timing fix in
  `hooks/autopilot-continue.sh`. **H9 fix** —
  `inject_keys_failure_hint` disambiguates 5 distinct failure
  causes (no backend, kitty `allow_remote_control`, iTerm2
  Automation TCC, WezTerm flag, unknown backend) and the hook
  additionalContext propagates the hint (CT-AC-40).
  **H11 fix** — `INJECT_KEYS_DRY_RUN=1` requires co-presence of
  `SW_TEST_HARNESS=1` to short-circuit; a leaked profile env var
  alone is now harmless (CT-AC-42). **H12 fix** — full
  cross-hook integration test exercises the safety-net →
  real `autopilot-continue.sh` Stop yield → primary post-resume
  short-circuit contract (CT-AC-43). **M4 fix** — both hooks
  record a `runtime_metrics` entry
  (`boundary: auto_compact_inject`,
  `stop_reason: primary | safety_net`) on successful inject so
  the user can correlate `/compact` fires with state transitions
  during forensics (CT-AC-44). **M7 fix** — `shipped_count` grep
  anchor tightened from `^[[:space:]]+ship: completed` to
  `^      ship: completed$` (canonical 6-space yq indent +
  end-of-line) so a stray `ship: completed` literal in a
  `runtime_metrics` note or free-form commentary cannot inflate
  the count (CT-AC-45). **WI-1 + WI-2 fix** — every backend in
  `hooks/lib/inject-keys.sh` targets the originating surface
  rather than the focused one: kitty via `--match
  id:$KITTY_WINDOW_ID` (CT-AC-46), WezTerm via `--pane-id
  $WEZTERM_PANE` (CT-AC-47), iTerm2 via an AppleScript
  session-id lookup keyed on the UUID portion of
  `$ITERM_SESSION_ID`, scoped to `tabs of current window`
  because iTerm2's AppleScript `windows` collection is empty
  (live-verified `count of windows = 0` on iTerm 3.6.8). The
  iTerm path raises a hard error referring users to tmux for
  multi-iTerm-window workflows rather than silently re-routing
  to the focused window (CT-AC-48 — assertions cover the
  `current window` iteration, the absence of the broken
  `repeat with w in windows`, and the failure-hint copy).
  Field reproducer for WI-1: `brief mode=auto` in iTerm window
  A, focus iTerm window B, the legacy `current session of
  current window` AppleScript injected `/compact<Enter>` into
  window B's shell. Field reproducer for WI-2
  (`test_simple_workflow26`, session
  `7d8e45d3-8730-4dd1-87d0-48e804e1d8d4`): every iTerm2 inject
  failed with `iTerm session
  80E38DE0-327D-4958-854C-21B104413CF4 not found in any
  window` even though that UUID was live in the user's current
  iTerm window — root cause was the broken `windows`
  iteration in WI-1, fixed in WI-2. Closes the focus-leak
  failure mode for all five supported terminals within their
  respective AppleScript / CLI limits (tmux + screen were
  C3-fixed at Phase 1; kitty + WezTerm + iTerm2 close at WI-1;
  WI-2 corrects the iTerm2 iteration mistake). **WI-3 fix** —
  both hooks now tolerate BOTH the canonical flat
  `steps.ship: completed` schema and the nested
  `steps.ship: {status: completed, invocation_method: skill}`
  schema observed in `test_simple_workflow27` (session
  `d3748705-f477-44e9-8c88-229b78b7a29a`). Safety-net Gate 2
  payload regex accepts both shapes; shipped_count in both
  hooks routes through `parse_ticket_ship_dirs` (yq → python3
  → POSIX awk), which also handles `tickets:` as either list
  or map. The `autopilot/SKILL.md` step 3d post-condition is
  hardened to **MUST emit the canonical FLAT schema** with an
  explicit anti-pattern block, and `state-file.md` adds a
  "Schema invariants" section. The pre-WI-3 hooks silently
  exited at Gate 2 / shipped_count = 0 for every nested-schema
  write, producing zero `/compact` over the entire
  test_simple_workflow27 53-minute pipeline despite the v7
  plugin being correctly loaded via `--plugin-dir
  ../simple-workflow`. CT-AC-45 is rewritten to verify
  `parse_ticket_ship_dirs` behaviour against a fixture with a
  `runtime_metrics` note containing the literal substring
  `ship: completed` (a YAML-aware parser ignores it; a naive
  grep anchor would not), and CT-AC-49 reproduces the exact
  test_simple_workflow27 T-001 ship-completed payload to prove
  the safety-net reaches the dispatcher under the nested
  schema. M7's strict-grep-anchor approach is superseded by
  the YAML-aware helper.
- `bash tests/test-hooks-lib.sh` exits 0 with 132 / 132 PASS;
  `find_any_autopilot_state_file` continues to behave correctly.
- `bash tests/test-path-consistency.sh` exits 0 with 139 / 139 PASS;
  no regression in the path-rewrite suite.
- `INJECT_KEYS_DRY_RUN=1` fixtures (CT-AC-07, CT-AC-14, CT-AC-18,
  CT-AC-22, CT-AC-23, CT-AC-26, CT-AC-27) confirm both hooks reach the
  dispatcher inside a default-on autopilot context with appropriate
  gating, the cross-hook marker prevents double-fires, the dispatcher
  emits `target=…` so audits can confirm the pane/window targeting
  (C3), and the SKILL.md AUTO-COMPACT EXCEPTION label literals
  byte-match the runtime additionalContext (C4).
- `test_simple_workflow24` dogfood (session
  `48c15d9e-cfa2-4148-9268-1cfdcf9c9cbb`, 3-ticket Pomodoro pipeline,
  with the v7 redesign in place BEFORE Gate 7 was added) recorded
  FIVE `/compact` invocations over three ticket boundaries (expected
  TWO — one between T-001/T-002 and one between T-002/T-003; the
  trailing fifth at 15:11:22 was a user-typed manual compact after the
  pipeline finished). Timing: T-001 ship at 14:40:37 → safety-net at
  14:41:59 (state-write fired) → /compact #1 at 14:42:02 → resume +
  T-002 scout at 14:43:11 → primary fired → /compact #2 at 14:43:15.
  Identical pattern at T-002/T-003 boundary (14:55:19 → 14:56:16 +
  14:57:05). Root cause: `.auto-compact-pending` sentinel is consumed
  by `hooks/autopilot-continue.sh` when it yields the Stop tick, so
  the primary's Gate 6 sentinel-dedup cannot fire on the
  post-compact-resumed `/scout`. The primary's own Gate 5 marker
  (`.auto-compact-last-attempt`) was only written by the primary, so
  a safety-net-first boundary left the marker absent. Fix (Gate 7 in
  `hooks/post-ship-state-auto-compact.sh`): the safety-net now writes
  the same `.auto-compact-last-attempt` marker, format
  `{shipped_count}:{unix_timestamp}`, AND reads it for its own
  self-dedup (split Edit calls). The marker file is NOT consumed by
  `autopilot-continue.sh`, so it survives the compact/resume cycle.
  Post-fix: expected exactly two /compact per three-ticket boundary
  pair, verified by CT-AC-23.
- Field evidence motivating the v7 redesign — `test_simple_workflow23`
  (session `e47e7151-1081-47f6-a484-fe99eb5624c1`, 3-ticket pipeline,
  with the v6.x four-axis design including the test_22 two-step
  ordering fix in place):
  - T-001 ship #1 (10:03:33): model interpreted the v6 additionalContext
    literally, wrote `ship: completed` to autopilot-state.yaml at
    10:03:56 BEFORE any git commit (state-lie), end_turned, /compact
    fired at 10:03:58 — but on bogus state. The compact-resume re-ran
    `/ship` for T-001 at 10:05:52 (ship #2), which actually performed
    the commit, move, tune, and final state update at 10:07:53.
  - T-002 ship (10:22:56): model recognised the pattern from T-001 and
    chose to DEFY the additionalContext. Assistant text at 10:23:23:
    "T-001 と同じ問題: hook が /ship body 実行**前**に発動。literal
    compliance だと state lie になり T-003 の commit が T-002+T-003 を
    混合してしまいます。/ship body を inline 実行してから契約 STEP 1
    (state update が genuine になる) → STEP 2 (end_turn) します。" The
    model then executed git commit (cf714d1), ticket move,
    `Skill(simple-workflow:tune)` chain-call (10:23:53), tune body
    through 10:26:43, and the orchestrator's `ship: completed` state
    write at 10:26:50 — but never end_turned. The sentinel written by
    the v6 hook at 10:22:56 (ship invocation time) had already aged
    past the 120s freshness window by 10:26:50, so `autopilot-continue.sh`
    did NOT yield (assistant text at 10:26:57: "Stop hook が end_turn
    を override して T-003 続行を指示。T-003 pipeline 開始します。"),
    and T-003 started in the same turn at 10:27:03 with NO auto-compact
    between T-002 and T-003.
  - T-003 ship (10:40:25): same defiance pattern, no auto-compact
    between T-003 and pipeline end. The user typed `/compact` manually
    at 10:45:49 once the pipeline finished.
  - Root cause: PostToolUse(Skill: simple-workflow:ship) fires when the
    Skill tool is *invoked*, not when its body completes. The v7
    redesign waits until the orchestrator GENUINELY writes
    `steps.ship: completed` to disk (safety net) or the next ticket's
    `/scout` is about to launch (primary). Both events happen AFTER
    the full ship body — including the chained `/tune` Step 6 — has
    run, eliminating both the state-lie window and the
    inline-defiance escape hatch.


## [6.6.7] — 2026-05-13

Patch release that formalises simple-workflow as **Claude Code only**.
Earlier versions documented GitHub Copilot CLI as a co-equal harness
in the README and shipped dual `tools:` lists (Claude Code +
Copilot CLI) in every sub-agent and skill frontmatter, but the
plugin's hook layer (`pre-bash-safety`, `pre-write-safety`,
`session-start`, `pre-compact-save`, `session-stop-log`,
`autopilot-continue`, `pre-level1-guard`) was never wired up on the
Copilot CLI side. The Generator-Evaluator firewall,
context-conservation pre-compact save, and `/catchup` recovery flow
have therefore never worked under Copilot CLI in practice. v6.6.7
brings the documentation, prerequisites list, sub-agent frontmatter,
and skill frontmatter in line with that runtime reality. The same
release adds Quick Start documentation for the `--scope project` /
`--scope user` / `--scope local` plugin install modes and the
user-scope → project-scope migration recipe. No skill, sub-agent,
hook, test, or runtime behavior changed; the
`tests/test-skill-contracts.sh` (452/452 PASS) and
`tests/test-path-consistency.sh` (139/139 PASS) suites remain green
without modification.

### Changed

- README `## Prerequisites`, `## Quick Start`, and `## Limitations`
  declare Claude Code as the sole supported harness. The Copilot CLI
  mirrored command lines, the `> **Note on GitHub Copilot CLI.**`
  caveat block, the `GitHub Copilot CLI` reference in the opening
  one-liner and prerequisites, and the two Copilot-related bullets
  under `## Limitations` (the dual-CLI design statement and the
  hook-not-firing note) are removed.
- All 10 sub-agents (`agents/*.md`) have their `tools:` frontmatter
  trimmed to the Claude Code-only list. The `# Copilot CLI` comment
  and the trailing Copilot CLI tool names (`view`, `create`, `edit`,
  `grep`, `glob`, `shell(...)` variants) are removed; the
  now-redundant `# Claude Code` comment is also dropped.
- All 13 skills (`skills/*/SKILL.md`) have the same Copilot CLI block
  removed from their `allowed-tools:` frontmatter.

### Added

- README `### Installation scope` subsection under `## Quick Start`,
  documenting the four plugin install scopes recognised by Claude
  Code (Managed / Project / User / Local), where each scope is
  written on disk, the `claude plugin install ... --scope project`
  invocation for repository-scoped install, and the
  `uninstall --scope user` then `install --scope project` migration
  recipe for users moving off the default user-scoped install.

### Verification

- `bash tests/test-skill-contracts.sh` — 452/452 PASS, identical to
  the v6.6.6 baseline. The contract tests do not assert on the
  presence of the `# Claude Code` / `# Copilot CLI` comments or on
  the Copilot CLI tool names, so removing them leaves the suite
  green.
- `bash tests/test-path-consistency.sh` — 139/139 PASS, identical to
  the v6.6.6 baseline.
- `git grep -in 'copilot' -- agents/ skills/ README.md` returns zero
  matches.

### Migration

This is a documentation-and-frontmatter alignment release, not a
runtime change. Users running simple-workflow under Claude Code see
no behavioral difference. The plugin had never functioned correctly
under GitHub Copilot CLI (hooks did not fire), so the
`copilot plugin install …` instructions previously printed in the
README never produced a working install; users who tried that path
and ended up with a non-functional plugin should remove it from
Copilot CLI and reinstall under Claude Code following the updated
`## Quick Start` section.

## [6.6.6] — 2026-05-13

Hotfix on top of v6.6.5. v6.6.5 rewrote `.claude-plugin/marketplace.json`
`plugins[0].source` to the canonical `github` source object, but Claude
Code's `claude plugin install` path attempts to clone `github`-typed
sources over **SSH** (`git@github.com:owner/repo.git`) with no HTTPS
fallback. Users without a GitHub-registered SSH key hit
`Permission denied (publickey). fatal: Could not read from remote
repository.` even though the prior `marketplace add` step succeeded
(that path has an HTTPS fallback and logs `SSH not configured, cloning
via HTTPS:`). The Claude Code marketplace schema documents no
transport override (no `transport`, `https`, `CLAUDE_PLUGIN_GITHUB_TRANSPORT`,
etc.) for the `github` source type, so the only documented way to pin
HTTPS is to switch to the `url` source type and supply an explicit
`https://...git` URL. v6.6.6 makes that switch, matching the pattern
used by the [`obra/superpowers-marketplace`](https://github.com/obra/superpowers-marketplace/blob/main/.claude-plugin/marketplace.json)
manifest, whose 10 plugin entries all use `source: url` with HTTPS
URLs. The marketplace name (`aimsise-simple-workflow`) and the plugin
name (`simple-workflow`) are unchanged, so the documented install
command `claude plugin install simple-workflow@aimsise-simple-workflow`
stays valid. No skill, sub-agent, hook, test, or runtime behavior
changed; the `tests/test-skill-contracts.sh` (452/452 PASS) and
`tests/test-path-consistency.sh` (139/139 PASS) suites remain green
without modification.

### Fixed

- `.claude-plugin/marketplace.json` `plugins[0].source` rewritten from
  `{ "source": "github", "repo": "aimsise/simple-workflow" }` to
  `{ "source": "url", "url": "https://github.com/aimsise/simple-workflow.git" }`.
  The `url` source type accepts an explicit `https://` URL, so Claude
  Code can no longer dispatch into the SSH branch. `ref` is omitted to
  follow the `obra/superpowers-marketplace` idiom of letting the
  default branch (`main`) drive resolution; tag-pinned installs remain
  achievable with `ref: "vX.Y.Z"` if needed in the future.
- Users who already registered the marketplace at v6.6.4 or v6.6.5
  must refresh their local cache to pick up the corrected manifest:
  `claude plugin marketplace remove aimsise-simple-workflow` followed
  by `claude plugin marketplace add aimsise/simple-workflow`. The
  install command itself is unchanged.

### Verification

- `bash tests/test-skill-contracts.sh` — 452/452 PASS, identical to
  the v6.6.5 baseline (no `SKILL.md`, agent, or hook contract was
  touched in this release).
- `bash tests/test-path-consistency.sh` — 139/139 PASS, identical to
  the v6.6.5 baseline.
- End-to-end install rehearsal against v6.6.5 reproduced the SSH
  failure: `marketplace add` succeeded via HTTPS fallback, but
  `claude plugin install simple-workflow@aimsise-simple-workflow`
  aborted with `git@github.com: Permission denied (publickey). fatal:
  Could not read from remote repository.` against a host with no SSH
  key registered to GitHub. With v6.6.6 published and the marketplace
  re-added per the migration step above, the same two-step flow is
  expected to clone over HTTPS and complete without error,
  to be re-verified post-merge from a fresh checkout once the v6.6.6
  annotated tag and matching GitHub Release are published.

## [6.6.5] — 2026-05-13

Hotfix on top of v6.6.4. The marketplace manifest shipped in v6.6.4
used `"source": "."` for the plugin entry, which Claude Code rejects
with `This plugin uses a source type your Claude Code version does not
support` because `"."` is parsed as a source-type discriminator and
matches none of the supported types (`github`, `url`, `git-subdir`,
`npm`, or a relative-path string that begins with `./`).
`claude plugin marketplace add aimsise/simple-workflow` succeeds — the
manifest itself loads — but `claude plugin install
simple-workflow@aimsise-simple-workflow` fails on the malformed source
field. v6.6.5 rewrites `plugins[0].source` to the canonical GitHub
source object (`{ "source": "github", "repo": "aimsise/simple-workflow" }`),
matching the worked example in the official Claude Code marketplace
schema documentation. The marketplace name (`aimsise-simple-workflow`)
and the plugin name (`simple-workflow`) are unchanged, so the documented
install command `claude plugin install simple-workflow@aimsise-simple-workflow`
stays valid. No skill, sub-agent, hook, test, or runtime behavior
changed; the `tests/test-skill-contracts.sh` (452/452 PASS) and
`tests/test-path-consistency.sh` (139/139 PASS) suites remain green
without modification.

### Fixed

- `.claude-plugin/marketplace.json` `plugins[0].source` rewritten from
  the invalid string `"."` to a canonical GitHub source object
  (`{ "source": "github", "repo": "aimsise/simple-workflow" }`). This
  is the worked example shape from the Claude Code marketplace schema
  docs and is what unblocks `claude plugin install
  simple-workflow@aimsise-simple-workflow` on the first attempt.
- Users who already registered the marketplace at v6.6.4 must refresh
  their local marketplace cache to pick up the corrected manifest:
  `claude plugin marketplace remove aimsise-simple-workflow` followed
  by `claude plugin marketplace add aimsise/simple-workflow`. The
  install command itself is unchanged.

### Verification

- `bash tests/test-skill-contracts.sh` — 452/452 PASS, identical to
  the v6.6.4 baseline (no `SKILL.md`, agent, or hook contract was
  touched in this release).
- `bash tests/test-path-consistency.sh` — 139/139 PASS, identical to
  the v6.6.4 baseline.
- End-to-end install rehearsal in a clean working directory served as
  the reproducer for this hotfix: at v6.6.4, `claude plugin marketplace
  add aimsise/simple-workflow` succeeded but `claude plugin install
  simple-workflow@aimsise-simple-workflow` aborted with `This plugin
  uses a source type your Claude Code version does not support`. The
  same two-step flow against v6.6.5 (after `marketplace remove` +
  `marketplace add` to refresh the cached manifest) is expected to
  complete without error, to be re-verified post-merge from a fresh
  checkout once the v6.6.5 annotated tag and matching GitHub Release
  are published.

## [6.6.4] — 2026-05-13

Patch release that makes the plugin installable from a clean Claude
Code environment. v6.6.3 and earlier shipped
`.claude-plugin/plugin.json` but no marketplace manifest, so
`claude plugin marketplace add aimsise/simple-workflow` could not
register the repo and downstream `claude plugin install …` calls
failed with `Plugin "aimsise/simple-workflow" not found in any
configured marketplace`. This release adds the required
`.claude-plugin/marketplace.json` and rewrites the README Quick Start
to the correct two-step `marketplace add` → `install` flow. No skill,
sub-agent, hook, test, or runtime behavior changed; the
`tests/test-skill-contracts.sh` (452/452 PASS) and
`tests/test-path-consistency.sh` (139/139 PASS) suites remain green
without modification.

### Added

- `.claude-plugin/marketplace.json` — minimal Claude Code marketplace
  manifest declaring the `aimsise-simple-workflow` marketplace with a
  single `simple-workflow` plugin entry rooted at the repo
  (`source: "."`). This is the file `claude plugin marketplace add
  aimsise/simple-workflow` looks for; without it the repo cannot be
  registered as a marketplace and no `claude plugin install` command
  can resolve `simple-workflow`.

### Fixed

- README `## Quick Start` previously instructed users to run a
  single-line `claude plugin install aimsise/simple-workflow`, which
  always failed because Claude Code's `plugin install` resolves plugin
  names only against marketplaces that were previously registered via
  `claude plugin marketplace add`. The section now documents the
  correct two-step flow (`marketplace add` then `install
  simple-workflow@aimsise-simple-workflow`) and matches the manifest
  added under `### Added`.

### Verification

- `bash tests/test-skill-contracts.sh` — 452/452 PASS, identical to
  the v6.6.3 baseline (no `SKILL.md`, agent, or hook contract was
  touched in this release).
- `bash tests/test-path-consistency.sh` — 139/139 PASS, identical to
  the v6.6.3 baseline.
- End-to-end install rehearsal (`claude plugin marketplace add
  aimsise/simple-workflow` followed by `claude plugin install
  simple-workflow@aimsise-simple-workflow`) is intentionally
  post-merge-only: `marketplace add` resolves against the GitHub
  default branch (`main`), so the new manifest is only fetchable after
  this PR merges and the `v6.6.4` annotated tag plus matching GitHub
  Release are published.

## [6.6.3] — 2026-05-13

Patch release completing the BP-compliance refactor sweep across every
skill under `skills/`. All 13 skills (`audit`, `autopilot`, `brief`,
`catchup`, `create-ticket`, `impl`, `investigate`, `plan2doc`,
`refactor`, `scout`, `ship`, `test`, `tune`) now follow the
`.docs/create-skill/index.html` template — third-person verb-led
`description` with `(1) (2) (3)` scenarios and `Triggers on "..."`
keyword enumeration, an `Invocation policy:` paragraph in the body
(not the description), a `## Mandatory Skill Invocations` table for
each delegated agent or Skill, an explicit orchestrator/subagent
boundary statement in the agent-spawning step, and a `Return contract`
block citing the delegate's 5-field envelope from its
`## Context Conservation Protocol`. This is a structural alignment
release: no behavior, no Acceptance Criteria, no skill chain, and no
external contract surface changed. The full
`tests/test-skill-contracts.sh` (452/452 PASS) and
`tests/test-path-consistency.sh` (139/139 PASS) suites remain green
without modification.

### Changed

- 13 `skills/*/SKILL.md` files restructured to the BP template
  (`audit`, `autopilot`, `brief`, `catchup`, `create-ticket`, `impl`,
  `investigate`, `plan2doc`, `refactor`, `scout`, `ship`, `test`,
  `tune`). Each refactor: (a) rewrites `description` to third-person
  verb-led prose with three numbered invocation scenarios and a
  `Triggers on "..."` keyword list; (b) relocates the "Do not
  auto-invoke" / "Invocation policy" prose out of the description and
  into the body; (c) adds or strengthens a `## Mandatory Skill
  Invocations` table with `MUST invoke` / `NEVER bypass` / `Fail the`
  binding rules for each delegated agent or Skill chain-call; (d)
  adds an explicit orchestrator/subagent boundary sentence in the
  agent-spawning step; (e) adds a `Return contract` block citing the
  delegate's 5-field envelope (`**Status**`, `**Output**`, plus
  delegate-specific fields) and the under-500-tokens cap from the
  `## Context Conservation Protocol`. Each refactor preserves all
  pre-existing pin literals (`name:`, `disable-model-invocation:`,
  `argument-hint:`, `allowed-tools` entries, Step numbering, YAML
  schema references, Error Handling cases, Pre-computed Context
  shell substitutions) byte-identical, and preserves every Cat I,
  Cat A-2/A-3, Cat V, Cat Y, Cat 11, and Cat AE trigger literal so
  the existing test contracts stay green without modification.

- `.gitignore` — track `.DS_Store` exclusion (chore, no functional
  impact).

### Verification

- `bash tests/test-skill-contracts.sh` exits 0 → 452/452 PASS
  (unchanged baseline from v6.6.2; no new assertions, no removed
  assertions; all Cat I, Cat A-2/A-3, Cat V, Cat Y, Cat AE, Cat AK
  invariants stay green across all 13 refactored SKILL.md files).
- `bash tests/test-path-consistency.sh` exits 0 → 139/139 PASS
  (unchanged baseline; Cat 11 `Bash(*)` scope guard still finds only
  `agents/implementer.md` + `agents/test-writer.md`; no refactored
  SKILL.md acquired `Bash(*)`).
- Each of the 13 refactors was driven through a Generator-Evaluator
  (`/gen-eval`) loop and reached PASS in round 1 with no round 2
  needed. Independent verification per refactor (4-stage protocol):
  (1) round-1 Evaluator AC verification with per-AC `grep`/`awk`
  evidence; (2) cross-reference auditor enumerating every external
  callsite of the refactored skill (sibling SKILL.md citations,
  agent-file references, README/CHANGELOG mentions, hook comments,
  test assertions) and confirming each still resolves; (3) regression
  evaluator comparing pre-refactor and post-refactor diffs surface by
  surface to confirm additive-only change with byte-identical or
  semantically equivalent preservation of all pre-existing behavior;
  (4) direct re-run of both full test suites.

## [6.6.2] — 2026-05-11

Patch release replacing the timestamp-proxy review gate in `/ship` Phase 2
Step 9 with a content-identity check based on git blob SHAs. `/audit` now
appends an HTML-comment-fenced YAML coverage block to
`quality-round-{n}.md` that records the per-file blob SHAs of every
changed file the audit reviewed; `/ship` reads that block and confirms
the committed tree's blob SHAs match before passing the gate. This
eliminates the structural false positive in chained `/impl → /ship`
flows (where `quality-round-*.md` mtime always predates commit time even
when content is unchanged), and works correctly across sessions and in
manual sequences. The autopilot-policy (`stop` / `proceed_if_eval_passed`)
and interactive sub-flows are preserved verbatim — only their trigger
condition narrows.

### Added

- `hooks/lib/audit-coverage.sh` — new shared library exporting two
  helper functions (one to emit a coverage block at `/audit` time and
  one to check content identity at `/ship` time). Captures per-file
  blob SHAs at `/audit` time and verifies content identity at `/ship`
  time. Three-tier YAML fallback (`yq` → `python3 + PyYAML` → pure-shell
  `awk`).
- `/audit` Step 4b — appends an HTML-comment-fenced YAML coverage block
  to `quality-round-{n}.md` after the structured review body, recording
  the base commit SHA, the working-state tree SHA, and per-file blob
  SHAs of every changed file the audit reviewed.
- 5 hermetic fixtures under `tests/fixtures/quality-rounds/`
  (match-clean, blob-mismatch, extra-file-in-commit,
  deleted-file-handling, legacy-no-block) and contract category
  **Cat AK** (CT-MODE-COV-1..6 + CT-MODE-COV-DOC-1..4).

### Changed

- `/ship` Phase 2 Step 9 review gate now compares git blob SHAs recorded
  by `/audit` against the blob SHAs in the committed tree, instead of
  comparing `quality-round-*.md` mtime with commit time. The trigger
  condition narrows from "mtime predates commit" to "blob SHA mismatch
  (or legacy file missing the coverage block AND mtime predates commit)".
  Autopilot policy semantics (`stop` / `proceed_if_eval_passed`) and the
  interactive prompt are preserved verbatim.

  **Migration**: legacy `quality-round-*.md` files (those written before
  v6.6.2) lack the coverage block and continue to use the timestamp
  heuristic — no re-audit is required for in-flight tickets. Set the
  `SW_AUDIT_COVERAGE=off` environment variable to force legacy mtime
  behavior for all files; default is `on`.

### Verification

- `bash tests/test-skill-contracts.sh` exits 0; 10 new assertions under
  Cat AK (CT-MODE-COV-1..6 + CT-MODE-COV-DOC-1..4).
- `bash tests/test-path-consistency.sh` exits 0; no new fixture-path
  drift.
- All 5 hermetic fixtures under `tests/fixtures/quality-rounds/` exit 0
  individually under both default and `SW_AUDIT_COVERAGE=off` modes.

## [6.6.1] — 2026-05-11

Patch release introducing `scout-checkpoint-guard.sh`, the harness-side
defense for the `/scout ↔ /plan2doc` handoff. Mirrors the structural prior
established by `impl-checkpoint-guard.sh` (v6.4.6+) for the `/impl ↔ /audit`
handoff. The new hook anchors on the `plan2doc: ac-source=ticket.md
verbatim=true` ssot-line in the transcript tail rather than on
`phase-state.yaml`, so the legacy `product_backlog → active` ticket flow —
which has no `phase-state.yaml` and was the canonical site of the
recurring premature `end_turn` failure observed in conversation
`22df418d-5716-472a-be05-42826729acef` — is now covered. The L1 prompt
defense (a new `### Post-/plan2doc Checklist (mandatory)` section in
`skills/scout/SKILL.md`) and the L3 contract assertion (P-12 in
`tests/test-skill-contracts.sh`) round out the three-layer defense.

### Added

- **`hooks/scout-checkpoint-guard.sh`** — Stop hook that mirrors `impl-checkpoint-guard.sh` for the `/scout ↔ /plan2doc` handoff. Blocks `end_turn` when `/plan2doc` has emitted the ssot-line (`plan2doc: ac-source=ticket.md verbatim=true`) but `/scout` has not yet emitted `## [SW-CHECKPOINT]`, with the same 3-attempt counter+release UX as the impl variant. Counter file: `/tmp/.scout-checkpoint-${SESSION_ID}`; release at 3 emits `[SCOUT-CHECKPOINT-RELEASE] ... Resume with: /scout <ticket-dir>` (or `/autopilot <parent-slug>` inside autopilot context). Kill switch: `SW_SCOUT_CHECKPOINT_MODE` (`block` default, `metric-only`, `off`). Anchors on the transcript tail's ssot-line rather than `phase-state.yaml.phases.scout.status`, so the legacy `product_backlog → active` ticket flow (no `phase-state.yaml`) is covered (NAC-2).
- **`skills/scout/SKILL.md` Post-/plan2doc Checklist** — new section immediately under `## Instructions` that enumerates Steps 8 / 8a / 9 / 10 as a mandatory checklist after `/plan2doc` returns, with a negative cue stating that the plan2doc summary is the delegate's return value, not `/scout`'s final output to the user. The existing `CHECKPOINT — RE-ANCHOR` blockquote ahead of Step 8 is preserved (P-11 still PASS).
- **`tests/test-scout-checkpoint-guard.sh`** — fixture-driven regression suite covering 8 cases: C1 missing transcript, C2 missing ssot-line, C3 SW-CHECKPOINT present (counter cleared), C4 no /scout Skill invocation, C5 3-AND block without phase-state.yaml (the NAC-2 regression case), C6 3-AND block with phase-state.yaml in-progress, C7 short-circuit when scout.status == completed, C8 release at counter=3 with `[SCOUT-CHECKPOINT-RELEASE]` stdout.
- **`tests/test-skill-contracts.sh` P-12** — static assertion that `skills/scout/SKILL.md` contains the new `Post-/plan2doc Checklist` heading at least once. Emits `PASS P-12: scout Post-/plan2doc Checklist count` on success. P-11 (`CHECKPOINT — RE-ANCHOR`) continues to be enforced alongside P-12.

### Changed

- **`hooks/hooks.json`** — registers `scout-checkpoint-guard.sh` in the `Stop` array between `impl-checkpoint-guard.sh` and `autopilot-continue.sh`. The three Stop hooks evaluate independently: disjoint session-scoped counter files (`/tmp/.impl-checkpoint-*`, `/tmp/.scout-checkpoint-*`, `/tmp/.autopilot-continue-*`) and mutually exclusive transcript-tail signatures (impl: `**Status**: ... **Reports**:`; scout: `plan2doc: ac-source=ticket.md verbatim=true`; autopilot: phase-level). Existing entries (`impl-checkpoint-guard.sh`, `autopilot-continue.sh`, `session-stop-log.sh`) are unchanged (NAC-7).

### Verification

- `bash tests/test-skill-contracts.sh` → exit 0; P-11 still PASS, P-12 added (NEW). Baseline shift: 433/433 (v6.6.0) → 434/434 (+1 from P-12).
- `bash tests/test-path-consistency.sh` → exit 0; no new fixture files, path-consistency drift unchanged.
- `bash tests/test-scout-checkpoint-guard.sh` → exit 0; 8/8 PASS (C1 through C8).
- `bash tests/test-impl-checkpoint-guard.sh` → exit 0; existing 8/8 PASS (no regression, NAC-1).
- `bash tests/test-checkpoint-template.sh` → exit 0; no template changes.
- PATH-restricted matrix (`PATH=/usr/bin:/bin bash tests/test-scout-checkpoint-guard.sh`) exercises the three-tier fallback path (yq → python3+PyYAML → awk) for state-file parsing under minimal-PATH environments, matching the existing impl-checkpoint-guard.sh regime.

## [6.6.0] — 2026-05-11

### Added

- `/audit` Step 3.5 (Skeptical Third-Pass): triggered, conditional `general-purpose` Agent call that runs in addition to `code-reviewer` and `security-scanner` when one or more of the documented triggers (T-A..T-E) fires. Trigger taxonomy: T-A `hooks/lib/` shared library changes, T-B sanitization/escape function changes, T-C `tools:` permission edits in `agents/*.md`, T-D prior `ac-evaluator` round returned `PASS-WITH-CAVEATS` due to missing tooling, T-E cross-cutting changes touching `hooks/` AND `agents/` AND `skills/`. The third-pass uses the built-in `general-purpose` subagent (deliberately not a new file under `agents/`) to preserve cross-rubric reasoning. A `DO_NOT_SHIP` verdict from the third-pass is treated as `Critical += 1` in the existing aggregation tally and produces `Status: FAIL`. The third-pass runs at most once per `/audit` invocation regardless of how many triggers fire (OR-set), is suppressed when `only_security_scan=true`, and saves its report to `{ticket-dir}/skeptical-pass-{n}.md`. For non-risk-elevated PRs (the common case), `/audit`'s behaviour is byte-identical to its pre-T-5 form.
- `tests/test-skill-contracts.sh` Category AJ: 12 assertions locking the SKILL.md contract for Step 3.5, the Triggers subsection, the Prompt Template fenced block, the aggregation rule, the `only_security_scan` suppression, the OR-set / at-most-once invariant, and the CHANGELOG bullet itself.

### Verification

- `bash tests/test-skill-contracts.sh` — 433/433 PASS (417 baseline + 16 new AJ-* assertion increments across AJ-1 through AJ-12b).
- `bash tests/test-path-consistency.sh` — expected 0 failures (no path constants moved).
- Manual smoke (AC-9, AC-10): documented in `skills/audit/SKILL.md`; live verification deferred to ad-hoc fixture PRs (a fixture PR adding `hooks/lib/foo.sh` MUST produce 3 Agent invocations + a `skeptical-pass-{n}.md` artifact; a fixture PR editing only `README.md` MUST produce exactly 2 Agent invocations and NO `skeptical-pass-*.md` file).

## [6.5.1] — 2026-05-11

Patch release implementing T-4: robust pre-existing-failure attribution for `ac-evaluator`. The Round-1 ac-evaluator in T-003 / v6.3.2 had labelled a `tests/test-skill-contracts.sh:AF-2` failure as "pre-existing on clean HEAD" using bare `git stash` to validate — a verdict later proven wrong because `git stash` (without `--include-untracked` or `--all`) silently skips gitignored paths such as `.simple-workflow/`. This release adds a new `### Pre-existing Failure Attribution` sub-section to `agents/ac-evaluator.md` documenting the correct two-step recipe: (1) path-intersection via `git diff --name-only <base>..HEAD` (using `git merge-base HEAD origin/<default-branch>` for the base), and (2) when the evidence path is gitignored, a clean worktree rebuild via `git worktree add` against the base commit. A new anti-pattern callout explicitly forbids the bare `git stash` recipe. Post-impl security review tightened the new `git worktree` tool permissions to the scoped `add` / `remove` / `list` sub-commands instead of the originally proposed blanket wildcard. Non-breaking; no action required for existing tickets.

### Added

- **`### Pre-existing Failure Attribution` sub-section in `agents/ac-evaluator.md`** documenting the path-intersection recipe (with explicit `merge-base` / `<base>..HEAD` references), the worktree fallback for gitignored evidence paths, and a `DO NOT use git stash` anti-pattern callout that names `.simple-workflow/` as the canonical gitignored leak source.
- **Six new tool-permission entries** in the `agents/ac-evaluator.md` frontmatter (Claude-Code `tools:` and Copilot `shell()` sections): `Bash(git merge-base:*)`, `Bash(git worktree add:*)`, `Bash(git worktree remove:*)`, `Bash(git worktree list:*)`, plus the matching `shell()` entries.
- **Category AI in `tests/test-skill-contracts.sh`** (5 assertions: AI-1 through AI-5) covering the new sub-section heading, the path-intersection recipe (`git diff --name-only` + `merge-base`), the anti-pattern callout (`git stash` + `gitignored` + skip-phrase), the worktree recipe (`git worktree add`), and the scoped tool-permission entries (`Bash(git worktree add:` + matching `shell()` form).

### Fixed

- **ac-evaluator pre-existing attribution**: replaced the ad-hoc `git stash` approach (which silently skips gitignored paths such as `.simple-workflow/`) with the documented path-intersection + worktree recipes in `agents/ac-evaluator.md`. The previous behaviour produced false "pre-existing" verdicts whenever the failing diagnostic's evidence path lived under a gitignored directory — the canonical T-003 / v6.3.2 AF-2 misclassification scenario this ticket fixes.
- **`DEFAULT_BRANCH` resolution in the documented recipe** uses `git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@'` so the strip step targets the canonical `origin/<branch>` short form. The previous un-`--short` recipe would have leaked the full `refs/remotes/origin/...` path through `sed` unchanged on environments with unexpected ref prefixes (shallow clones, detached remote HEAD).

### Security

- **`git worktree` tool permissions scoped from blanket wildcard to `add` / `remove` / `list`** in both the Claude-Code (`tools:`) and Copilot (`shell()`) frontmatter sections of `agents/ac-evaluator.md`. The original draft used `Bash(git worktree:*)` / `shell(git worktree:*)`, which also granted `prune`, `lock`, `unlock`, and any future `git worktree` sub-command. The post-impl security review (S-1, Medium) flagged this as broader than the documented recipe needs. AC-5 (T-4 plan / ticket) and Category AI assertion AI-5 were updated to require the scoped variants so a regression to the broader wildcard is caught by `tests/test-skill-contracts.sh`.

### Changed (test infrastructure)

- **`tests/test-skill-contracts.sh` Category AI awk end-anchor relaxed** from `^## Status Decision$` to a generic `^## ` (any H2 boundary). The hardcoded heading text would have silently extended the awk range to EOF on a future rename of `## Status Decision`, letting `count_matches` pass vacuously against an over-extended buffer. The generic H2 anchor is robust to that rename.

### Verification

- `bash tests/test-skill-contracts.sh` — 417/417 PASS (5 new Category AI assertions AI-1 through AI-5 added on top of the v6.5.0 release tree).
- `bash tests/test-path-consistency.sh` — 138/138 PASS. No new fixture files; path-consistency drift unchanged.
- AC-7 smoke verification: a transient fixture under `.simple-workflow/backlog/active/T-4-smoke-fixture/af2-fixture/` with a `## 5. Acceptance Criteria` heading reproduced the exact T-003 / v6.3.2 failure mode (`ac-ssot: drift (missing-heading)`). The post-fix recipe correctly classified the failure as **PR-caused** via the worktree alternative (`git worktree add` at the BASE commit had no fixture present, so `ac-ssot-scan` returned `synced` — the failure was not pre-existing). Persistent evidence saved to `eval-round-1-ac7-smoke.md` under the T-4 ticket directory.

## [6.5.0] — 2026-05-11

Minor release implementing T-2: dynamic `maxTurns` and horizontal-split partitioning for AC-heavy plans in `/impl` Step 15. The `ac-evaluator` agent is now invoked with an AC-count-aware soft turn budget (`EVALUATOR_MAX_TURNS = max(60, AC_COUNT * 4)`) embedded in the prompt. Plans with `AC_COUNT >= 30` trigger a partition branch: the rubric is split into two contiguous halves by AC-ID order, each evaluated by a separate `ac-evaluator` invocation whose report is persisted as `eval-round-{n}-part-1.md` or `eval-round-{n}-part-2.md`; the orchestrator merges verdicts using the severity ladder FAIL-CRITICAL > FAIL > PASS-WITH-CAVEATS > PASS and unions the AC results. Plans with fewer than 30 ACs continue to use a single evaluator invocation with `EVALUATOR_MAX_TURNS = max(60, AC_COUNT * 4)` — the `max(60, ...)` floor ensures that small plans (AC_COUNT <= 15) always receive exactly 60 turns, preserving the v6.3.2 baseline. The Agent tool's JSONSchema was inspected at implementation time: the tool does not accept per-invocation `maxTurns` overrides (Strategy A), so the frontmatter ceiling of `agents/ac-evaluator.md` was raised to `maxTurns: 200` (Strategy B) and the soft turn budget is communicated to the agent via a prompt-level field. The `ac-evaluator` agent now recognises a `--- partition: <i>/2 ---` header in its prompt and evaluates only the AC subset in its partition. Partition awareness is strictly scoped to `ac-evaluator`: `code-reviewer` and `security-scanner` are not modified. Migration: no action required for existing tickets. The only behavioural change is for plans where `ac-evaluator` previously exhausted its 60-turn budget mid-evaluation (the empty-envelope / IN_PROGRESS pattern observed at 18–22 ACs in v6.3.0 and T-002/T-003). Those plans now receive up to 88–128 turns depending on AC count.

### Changed

- **`/impl` Step 15 now computes dynamic `maxTurns` via `EVALUATOR_MAX_TURNS = max(60, AC_COUNT * 4)`.** The AC-counting algorithm (primary regex `^[0-9]+\.\s+\*\*AC-`; fallbacks `^- AC-` and `^AC-`; stop condition at `### Negative Acceptance Criteria` / `#### Negative Acceptance Criteria`) counts positive ACs in the extracted rubric before every evaluator invocation. The computed value is embedded in the prompt as a soft turn budget. The `max(60, ...)` floor preserves the v6.3.2 baseline for plans with 15 or fewer ACs. The per-invocation `maxTurns` override (Strategy A) is infeasible because the Agent tool's JSONSchema rejects unknown fields; Strategy B (frontmatter ceiling 200, soft target in prompt) is the active implementation.
- **`/impl` Step 15 introduces a partition branch at the partition threshold of 30 ACs (`AC_COUNT >= 30`).** When the threshold is exceeded, the rubric is split into two contiguous halves by AC-ID order and `ac-evaluator` is invoked twice. Reports are persisted as `eval-round-{n}-part-1.md` and `eval-round-{n}-part-2.md`. The merge algorithm uses the severity ladder FAIL-CRITICAL > FAIL > PASS-WITH-CAVEATS > PASS (worst-of-2) and the AC-result union with a disjoint-partition invariant (`partition-1 ∩ partition-2 = ∅`). Plans with fewer than 30 ACs use the existing single-invocation path.
- **`agents/ac-evaluator.md` frontmatter `maxTurns` raised from `60` to `200`** (Strategy B). The documented floor of 60 is preserved via the `EVALUATOR_MAX_TURNS` formula and its `max(60, ...)` guard. A YAML comment documents the reason and links back to the T-2 formula.
- **`agents/ac-evaluator.md` `## AC Verification Method` gains a partition-awareness paragraph.** When the agent receives a `--- partition: <i>/2 ---` header, it evaluates only the ACs in its partition and must not comment on ACs outside its partition.
- **`tests/test-skill-contracts.sh` CT-MODE-GREP-C-2 threshold raised from `>= 30` to `>= 200`** to guard against rollback of the Strategy B frontmatter ceiling.

### Added

- **Four fixture plans under `tests/fixtures/ac-count-plans/`**: `plan-5ac.md` (5 ACs, floor case), `plan-22ac.md` (22 ACs, heavy single-invocation case), `plan-32ac.md` (32 ACs, partition branch case), and `plan-5ac-5negac.md` (5 positive + 5 negative ACs, Negative-AC stop-condition regression fixture).
- **Category AH in `tests/test-skill-contracts.sh`** (7 assertions: AH-1 through AH-7) covering AC-1/AC-2/AC-3/AC-4/AC-5 and Negative AC-4/Negative AC-6. All assertions use `count_matches` per CT-MODE-GREP-C-1.

### Verification

- `bash tests/test-skill-contracts.sh` — 413/413 PASS (v6.4.6 baseline 403/403 + 10 new assertions: 1 CT-MODE-GREP-C-2 threshold update + 9 Category AH assertions AH-1 through AH-7 with AH-5 and AH-6 split into sub-assertions).
- `bash tests/test-path-consistency.sh` — 138/138 PASS. New fixture files land under `tests/fixtures/` (canonical fixture location), no path-consistency drift.
- `bash tests/test-hooks-lib.sh` — all existing hooks-lib assertions PASS.

## [6.4.6] — 2026-05-11

Patch release implementing T-3 (S4 closure): single-shot recovery from the `IN_PROGRESS` envelope first persisted by v6.3.3's Persistence-First Protocol. When `/impl` Step 16 detects an `IN_PROGRESS` partial-state file written by a turn-budget-exhausted `ac-evaluator`, the orchestrator now invokes `ac-evaluator` a second time — capped at exactly 1 recovery attempt per round per file — with a resumption prompt that points the agent at the on-disk partial file and instructs it to resume verification from the first unchecked `[ ]` AC, preserving already-recorded `[x]` verdicts. If the recovery invocation also fails to produce a terminal verdict (`PASS` / `FAIL` / `PASS-WITH-CAVEATS` / `FAIL-CRITICAL`), Step 16 emits `[CONTRACT-VIOLATION] ac-evaluator recovery invocation did not produce a terminal verdict; treating as FAIL-CRITICAL` and halts: no third invocation occurs. Closes the no-recovery cliff identified in the `50ec6ffa` post-mortem as S4 (the only deferred mitigation that conflicted with v4.1.0's idempotency clause). The idempotency contract is preserved: the prohibition `MUST NOT re-invoke solely to persist` stays, now scope-qualified `(i.e., with no IN_PROGRESS context)`; the recovery call has a distinct input shape (partial IN_PROGRESS file + resumption rubric) and is not a duplicate request. `v6.4.5 → v6.4.6` is byte-identical for any plan whose Round 1 produces a terminal verdict — the recovery branch only fires when Round 1 leaves an `IN_PROGRESS` file on disk. When T-2's partition branch is active, the cap applies per partition file: worst-case 4 invocations for a 2-partition plan.

### Added

- **`tests/fixtures/mock-ac-evaluator-always-in-progress.sh` and `tests/fixtures/mock-ac-evaluator-second-call-terminal.sh`.** Two new shell fixtures that simulate the IN_PROGRESS-persistence path without requiring a real `ac-evaluator` LLM invocation. The first always writes `## Status: IN_PROGRESS` + `[ ]` AC skeleton lines to `$EVAL_REPORT_PATH` and returns empty stdout, incrementing `$COUNTER_FILE` each call. The second behaves identically on call 1, then on call 2 writes `## Status: PASS` with `[x]` lines and returns non-empty stdout. Both run under `bash -euo pipefail` with quoted expansions and `mktemp -d`-driven test paths.
- **Cat T contract assertions in `tests/test-skill-contracts.sh` (CT-MODE-SINGLESHOT-1 through CT-MODE-SINGLESHOT-7).** Seven new assertions covering the T-3 deliverable: CT-MODE-SINGLESHOT-1..5 are static contract checks (the IN_PROGRESS recovery branch in `skills/impl/SKILL.md` Step 16, the single-shot cap language, the fenced resumption-prompt template containing `Read the IN_PROGRESS file` / `resume from` / `[ ]`, the rule 4 paragraph in `agents/ac-evaluator.md` Persistence-First Protocol, and the idempotency-clause scope clarification in Report Persistence Contract). CT-MODE-SINGLESHOT-6 and -7 are fixture-driven smoke assertions: a shell `simulate_step16` helper exercises Step 16's branching logic against the two new mock fixtures. SINGLESHOT-6 verifies exactly-2-invocations + terminal PASS on the recovery call (AC-6 of the ticket); SINGLESHOT-7 verifies that double-IN_PROGRESS halts at exactly 2 calls with a `[CONTRACT-VIOLATION]` emit and exit 1 (AC-7). A Negative-AC-3 cross-check inside the same block uses `awk '/^17\./,/^18\./'` to confirm `IN_PROGRESS` matches stay inside Step 16 and never leak into Step 17.

### Changed

- **`/impl` Step 16 IN_PROGRESS handling promoted from `3-way decision` to `4-way decision`.** Branch (ii) (Output empty + file exists + first `## Status:` line is `IN_PROGRESS`) is no longer the FAIL-CRITICAL hard-stop placeholder it was in v6.3.3. It now executes the single-shot recovery: emit `[IN_PROGRESS] ac-evaluator persisted partial state at <path>; attempting single-shot recovery`, invoke `ac-evaluator` once more via the Agent tool with the fenced resumption prompt template, and dispatch the second call's Output / on-disk Status to either the (iv) terminal-Status path (success) or the new `[CONTRACT-VIOLATION] ac-evaluator recovery invocation did not produce a terminal verdict; treating as FAIL-CRITICAL` line (recovery also IN_PROGRESS / empty). The implementation is a single conditional — no `while` / `for` construct is permitted around the recovery invocation (Negative AC-5), which keeps the call count strictly bounded at 2 per round per file. Tickets that previously hit branch (ii) and immediately halted now have a defensible second chance; tickets whose `ac-evaluator` Round 1 succeeds outright see zero behavioural difference.
- **`agents/ac-evaluator.md` Persistence-First Protocol gains rule 4 (resumption mode).** When invoked with an `## Status: IN_PROGRESS` file already present at the target path, the agent now reads the file first, identifies ACs already verdicted (lines matching `- [x]` or `- [ ]` followed by an AC ID), resumes verification from the first unchecked AC, and rewrites the file with the merged verdicts before returning. This is the agent-side contract that pairs with the orchestrator-side recovery branch — without rule 4 the second `ac-evaluator` invocation would re-verify from scratch and almost certainly exhaust the turn budget on the same AC that exhausted Round 1.
- **`agents/ac-evaluator.md` Report Persistence Contract idempotency clause scope-qualified.** The prohibition `Callers MUST NOT re-invoke this agent solely to persist the report` is preserved verbatim and supplemented with `(i.e., with no IN_PROGRESS context)` plus a trailing sentence: `A single recovery invocation when the on-disk file shows `## Status: IN_PROGRESS` is permitted and is a distinct call shape, not a duplicate.` The `before returning` invariant in the same paragraph is unchanged. This is the smallest possible clarification that lets the new recovery branch coexist with v4.1.0's idempotency guarantee — the call shape, not the call count, determines whether a re-invoke is duplicate.

### Verification

- `bash tests/test-skill-contracts.sh` — 403/403 PASS (v6.4.5 baseline 396/396 + 7 new Cat T assertions: CT-MODE-SINGLESHOT-1..5 static + CT-MODE-SINGLESHOT-6..7 fixture-driven). The 396 → 403 jump is documented in the audit-round-2 report under the ticket directory.
- `bash tests/test-path-consistency.sh` — 138/138 PASS. The two new shell fixtures land under `tests/fixtures/` (the canonical fixture location) and are referenced by absolute repo-relative paths in Cat T, so no path-consistency drift fires.
- `/audit` round 2 status: **PASS_WITH_CONCERNS** (Critical=0, Warnings=2, Suggestions=3). The two Warnings are coverage gaps in the simulator (the recovery-call stdout is captured but not asserted non-empty; the `trap - EXIT` reset in the Cat T cleanup could clobber an outer harness EXIT trap if one is ever registered upstream). The three Suggestions are non-blocking: a `recovery_output` dead-store comment, an optional cross-reference between rule 4 and rule 3 of the Persistence-First Protocol, and an `$EVAL_REPORT_PATH` non-empty guard in branch (ii) prose. None of these block correctness of the AC-1..AC-8 acceptance criteria.

## [6.4.5] — 2026-05-11

Patch release root-causing the AF-2 (`ac-ssot-scan against live brief tree`) failure that v6.4.4's `### Verification` block flagged as "out of v6.4.4 scope". The `tests/helpers/ac-ssot-scan.sh` extractor terminated the `## Acceptance Criteria` collection window only on H2 (`^##[[:space:]]`), which silently skipped over the H4 `#### Negative Acceptance Criteria` sub-heading that the project's ticket template uses. The scanner therefore continued counting list items beneath the negative-AC sub-heading as part of the positive-AC list, producing spurious `count-mismatch` drift between tickets that hold both positive + negative ACs and plans that correctly mirror only the positive list (per the `/plan2doc` SSoT discipline established in v6.3.x: "Mention but do not duplicate the Negative AC list — the implementer will read ticket.md directly for those"). The terminator regex is widened to `^#+[[:space:]]` so any heading depth (H2 / H3 / H4 / ...) closes the window. The `## Acceptance Criteria` start line itself is consumed by the existing `next` rule above the new guard, so it cannot be re-matched as a terminator. v6.4.4 → v6.4.5 is byte-identical for any ticket / plan pair where the AC sections were already structurally aligned at H2 — the change only affects pairs that previously slipped through because of the H2-only window. There are no skill / hook / agent changes in this release.

### Fixed

- **`tests/helpers/ac-ssot-scan.sh` section-end regex widened from `^##[[:space:]]` (H2-only) to `^#+[[:space:]]` (any heading depth).** Closes the long-standing H4 leak where `#### Negative Acceptance Criteria` did NOT terminate the `## Acceptance Criteria` collection window. Before the fix, a ticket holding 8 positive + 7 negative ACs and a plan holding 8 positive ACs (the post-v6.3.x convention) was reported as `count-mismatch plan=8 ticket=15` — exactly the spurious AF-2 failure recorded in v6.4.4's Verification block. After the fix, the same pair is reported as `synced`. The fix is symmetric: any plan that legitimately mirrors negative ACs under a `#### Negative Acceptance Criteria` sub-heading also lines up correctly (positive-only count on both sides). A multi-line awk comment block was added next to the new guard documenting the original H2-only failure mode and the `next`-rule interaction that prevents the start heading from being re-matched as a terminator.

### Verification

- `bash tests/test-skill-contracts.sh` — 396/396 PASS. AF-2 (`ac-ssot-scan against live brief tree`) flips from FAIL (recorded in v6.4.4 Verification) to PASS, with no other test drift. The 396 total is unchanged from v6.4.4 — this release adds no new assertions, only widens the matcher in the existing scanner helper consumed by AF-2.
- `bash tests/test-path-consistency.sh` — 138/138 PASS.
- `bash tests/helpers/ac-ssot-scan.sh .simple-workflow` — exits 0 with stdout `ac-ssot: synced` against the contributor-local backlog tree (after re-aligning the legacy `done/hooks-lib-foundation/001-jsonl-tail-audit-lib/plan.md` to use a `#### Negative Acceptance Criteria` sub-heading; that file is gitignored under `.simple-workflow/` and not part of this commit).

## [6.4.4] — 2026-05-11

Patch release closing the manual-vs-autopilot round-cap asymmetry in `/impl`. Until v6.4.3 the manual default was 3 rounds while autopilot's `aggressive` profile already permitted 12 (`constraints.max_total_rounds: 12`), a 4× gap (3× against the default `conservative` / `moderate` profiles which both set `max_total_rounds: 9`) that caused hand-driven `/impl` runs on M / L / XL tickets to fall through to Phase 3 with unresolved AC issues much more often than autopilot did on the same plan. The documented workaround — drop an `autopilot-policy.yaml` into a manual ticket directory — is broken because the Phase 1 auto-select rule at `skills/impl/SKILL.md` step 1 explicitly **excludes** any directory containing `autopilot-policy.yaml` (those are autopilot-managed by definition). v6.4.4 lifts the manual default to 9, adds a first-class `rounds=N` CLI argument with the same case-insensitive key / positive-integer validation used by `/audit`'s `round=N`, and pins the precedence chain to `arg > policy > default 9`. The new soft cap of 24 emits `[ARG-WARN] rounds=<N> exceeds soft cap 24; proceeding with user-specified value` on stderr but does NOT clamp — a deliberate `rounds=50` runs for 50 rounds. For `/impl`, v6.4.3 → v6.4.4 is byte-identical for any ticket that explicitly carries `constraints.max_total_rounds` in its policy file (autopilot path) or that completes well under 9 rounds today; the manual-default fallback is the only `/impl` behaviour actually changed. `/scout` separately gets a prose-only LLM-instruction guard between Step 7 (`/plan2doc`) and Step 8 (see `### Added` below) — no runtime / state-file change.

### Added

- **`rounds=N` argument for `/impl`.** Phase 1 step 1a tokenizes `$ARGUMENTS` on whitespace and matches each token against `^[Rr][Oo][Uu][Nn][Dd][Ss]=([^[:space:]]*)$` (case-insensitive `rounds=` key, e.g. `rounds=15`, `Rounds=7`, `ROUNDS=24`; the `*` quantifier on the capture group lets a bare `rounds=` match as a token so it can be rejected by validation rather than silently dropped). Only whole whitespace-delimited tokens count, so a substring inside a quoted plan path (e.g. `.simple-workflow/docs/plans/some-rounds=5-test.md`) or inside another token (`myrounds=15`) is NOT recognized. If multiple matching tokens appear (e.g. `/impl rounds=5 rounds=15 plan.md`), the first wins and only that first token is stripped from `$ARGUMENTS`; subsequent `rounds=` tokens are left in the additional-instructions tail. The resolved value is written into `phases.impl.max_rounds` in the Phase 2 init block (between Step 12 and Step 13). Two distinct caps apply: a **hard cap of 999999** rejects pathological inputs (`rounds=1000000`) with `[ARG-WARN] rounds=<raw> exceeds 999999 (bash arithmetic safety hard cap); falling back to policy or default 9` to keep the soft-cap arithmetic safely inside bash signed-64-bit range; and a **soft cap of 24** emits `[ARG-WARN] rounds=<N> exceeds soft cap 24; proceeding with user-specified value` but honours the user-specified value (no clamp). Boundary `rounds=24` is silent. Other malformed inputs (`rounds=0`, `rounds=-1`, `rounds=abc`, `rounds=1.5`, `rounds==5`, bare `rounds=`) emit `[ARG-WARN] rounds=<raw> is not a positive integer; falling back to policy or default 9` and fall through; the loop never aborts on a bad token. Precedence is fixed at `rounds=N` argument (when valid) > `{ticket-dir}/autopilot-policy.yaml` `constraints.max_total_rounds` (when present) > **default 9**.
- **Four new contract assertions in `tests/test-skill-contracts.sh`.** J-20a verifies `skills/impl/SKILL.md`'s `argument-hint:` line still advertises the `rounds=N` token (regex anchored to the frontmatter line, not the body); J-20b verifies the `else default 9` precedence-fallback prose; J-20c verifies the `soft cap 24` documentation; P-11 verifies that `skills/scout/SKILL.md` carries at least one `CHECKPOINT — RE-ANCHOR` block (mirrors P-9 for `/impl`). Together these lock in v6.4.4's `/impl` documentation surface against future "raise the default" or "drop the soft cap" patches that forget to update SKILL.md, and lock in the new `/scout` post-`/plan2doc` guard.
- **`CHECKPOINT — RE-ANCHOR BEFORE CONTINUING` block in `/scout`.** Inserted between Step 7 (`/plan2doc` invocation) and Step 8 (plan summary print) at `skills/scout/SKILL.md` to prevent `/scout` from prematurely ending its turn after `/plan2doc` returns, before Steps 8 / 8a / 9 / 10 (including the SW-CHECKPOINT emit) execute. Mirrors the `impl-checkpoint-guard` Stop-hook pattern that protects `/impl` Step 17's post-`/audit` handoff. No runtime / state-file changes — prose-only LLM-instruction guard.

### Changed

- **Manual `/impl` default round cap raised from 3 to 9.** Closes the 4× asymmetry with autopilot's `aggressive` profile (12 rounds) so hand-driven `/impl` runs no longer fall through to Phase 3 with unresolved AC issues 3× more often than the same plan executed under `/autopilot --profile aggressive`. Tickets that previously hit the 3-round cap and were marked PASS_WITH_CONCERNS in Phase 3 will now run additional Generator → AC Evaluator → `/audit` rounds. Override per-invocation with `/impl rounds=3` to restore v6.4.3 behaviour, or per-ticket with `constraints.max_total_rounds: 3` in `autopilot-policy.yaml` (autopilot-managed path only).
- **`/impl` argument tokenization is no longer transparent for free-form additional instructions that begin with `rounds=N`.** Under v6.4.3 a free-form invocation like `/impl rounds=5 of feedback` was passed verbatim as the additional-instructions string with the round cap still at the default 3. Under v6.4.4 the FIRST matching `rounds=5` token (matched by the case-insensitive `^[Rr][Oo][Uu][Nn][Dd][Ss]=([^[:space:]]*)$` regex per whitespace-delimited token, regardless of position in `$ARGUMENTS`) is consumed by the new Phase 1 step 1a parser, the round cap is set to 5, and the additional-instructions string becomes the post-strip tail (`of feedback`). Real-world impact is expected to be near-zero (free-form prose rarely starts with `rounds=N`), but anyone scripting `/impl` invocations should be aware that the `rounds=` prefix is now reserved for the new argument.
- **All hardcoded round-count prose in `skills/impl/SKILL.md` parameterized.** Phase 2 header `(max 3 rounds)` → `(max N rounds, default 9)`; AC Evaluator template `{n}` = current round (1, 2, or 3) → `{n}` = current round (1..max_rounds); `/audit` failure prose `on round 3` → `on the final round`; Combined Decision `Round 3 + FAIL` → `Final round + FAIL`; Error Handling `3 rounds FAIL` → `Max-rounds FAIL`. The Phase 2 section now opens with an explicit precedence block (`rounds=N` arg > policy > default 9) so future readers do not infer a fixed cap from any single line.
- **`README.md` pipeline diagram + Harness Engineering prose synced to the new defaults.** Three sites updated and standardized on the numeric form: the canonical pipeline diagram (`/impl 🔁 max 9 rounds (default; override via rounds=N)`), the Generator-Evaluator paragraph in Harness Engineering ("up to 9 rounds by default (configurable per invocation via `/impl rounds=N` or per ticket via `autopilot-policy.yaml`)"), and the `/impl` deep-dive paragraph ("up to 9 rounds by default (override per invocation with `/impl rounds=N`, with a soft cap warning above 24)"). Without this sync the README would have continued to advertise the v6.4.3 cap of 3 to anyone reading the project entry point.
- **`skills/impl/SKILL.md` Phase 1 step 1a documents the stderr placeholder convention.** Added a one-line legend distinguishing `<N>` (the parsed positive integer used in the soft-cap warning, where parsing succeeded) from `<raw>` (the original token's right-hand side used in the malformed and hard-cap warnings, where parsing rejected the value). Prevents downstream log-grep ambiguity now that three distinct `[ARG-WARN]` formats coexist.
- **`CLAUDE.md` `## Releases` section acknowledges `### Verification` as an accepted Keep a Changelog extension.** The Releases group enumeration now explicitly names `### Verification` alongside the seven canonical Keep a Changelog groups, documenting that the project intentionally adds a test-evidence group (used by every entry from v6.4.1 onwards). Removes a recurring skeptical-review false flag without altering any prior CHANGELOG entry.

### Verification

- `bash tests/test-skill-contracts.sh` — 395/396 PASS today, with 1 pre-existing AF-2 failure unrelated to v6.4.4. v6.4.4 adds 4 new test cases on top of v6.4.3's 392-assertion surface (J-20a / J-20b / J-20c for the `/impl` `rounds=N` surface; P-11 for the new `/scout` `CHECKPOINT — RE-ANCHOR` guard), bringing the total to 396. v6.4.3's own CHANGELOG entry recorded 392/392 PASS at release time; AF-2 has since flipped to failing on the current working tree (root-causing AF-2 is out of v6.4.4 scope), which is why the today-vs-release-time numbers differ — v6.4.4 itself does NOT introduce or alter the AF-2 path.
- `bash tests/test-path-consistency.sh` — 138/138 PASS. The Phase 2 round-precedence list uses bullets (`- **First**:`, `- **Else**`) instead of `1. / 2. / 3.` so the Category 17 step-continuity scan does not misinterpret the precedence list as Phase 2 sub-steps.
- `bash tests/test-impl-checkpoint-guard.sh` — 8/8 PASS. The fixture at `tests/test-impl-checkpoint-guard.sh:138` explicitly sets `max_rounds: 3`, so the default-bump from 3 to 9 does not affect it.

## [6.4.3] — 2026-05-10

Patch release closing the four `Residual / deferred` items recorded in the v6.4.2 evaluator self-eval. Three of the four are POSIX-awk migrations of the same gawk-only `match($0, regex, m)` anti-pattern v6.4.2 fixed in `parse_phase_status` / `parse_ticket_statuses`; the fourth is a tier-2 SC2259 stdin-pipe-vs-heredoc collision in `transcript_contains_skill_invocation`. The largest fix (F-1') eliminates a stock-macOS duplicate-row bug in `runtime_metrics:`: under BSD awk + no PyYAML + no yq, `_pphc_entry_already_present` always returned "no entry present" and every PostToolUse:Write of `phase-state.yaml` appended a duplicate (ticket_id, phase, boundary) row. The other two F-2' / F-3' fixes are consistency / dead-code cleanups with no observable production impact today. F-4' migrates the `tests/test-per-phase-metrics.sh` scaffolding off the same gawk syntax, which unblocks the BSD-only PATH end-to-end coverage that v6.4.2 had to defer. v6.4.2 → v6.4.3 is byte-identical on hosts with `yq` or PyYAML installed; the changes only flip behaviour where the tier-3 awk fallback is exercised.

### Fixed

- **F-1' — `_pphc_entry_already_present` BSD-awk fail on stock macOS produced duplicate `runtime_metrics:` rows.** The pure-shell idempotency probe in `hooks/post-phase-checkpoint.sh` (lines ~297-327) used the gawk-only 3-arg `match($0, regex, m)` form across three sites (ticket_id / phase / boundary value extraction). Under BSD awk the script aborted with `syntax error / illegal statement` (exit 2), the surrounding `grep -q '^MATCH$'` saw empty input, the function returned 1 ("not present"), and `_pphc_append_entry` appended a duplicate row on every PostToolUse:Write of `phase-state.yaml`. Pre-existing since v6.1.1. v6.4.3 replaces all three sites with POSIX `sub()` strip-by-prefix on a local copy of the line — same template applied to `parse_phase_status` / `parse_ticket_statuses` in v6.4.2. The new `tests/test-hooks-lib.sh` Section 3-bis exercises `_pphc_entry_already_present` directly through a tier-3-only PATH (yq / python3 / jq absent, awk pinned to `/usr/bin/awk`), so any future re-introduction of gawk-only syntax fails CI.
- **F-2' — `_pphc_read_ticket_id` lacked a PyYAML up-front gate.** The python3 tier in `hooks/post-phase-checkpoint.sh` (lines ~154-174) entered the `python3 - ... <<'PY'` heredoc unconditionally and only handled PyYAML's absence with an in-script `try / except ImportError: sys.exit(1)`. The function was functionally correct (the awk fallback recovered) but every Write/Edit on stock macOS paid the ~30 ms python3 spawn cost only to ImportError its way to awk. v6.4.3 gates the python3 tier on `python3 -c 'import yaml'` succeeding (matching the v6.4.2 pattern in `parse_phase_status` / `parse_ticket_statuses`) and drops the now-redundant `try / except` block. Behaviour-preserving on hosts with PyYAML; pure cost reduction otherwise.
- **F-3' — `transcript_contains_skill_invocation` tier-2 always returned 1 (SC2259 stdin-pipe-vs-heredoc collision).** `hooks/lib/jsonl-tail-audit.sh:194-231` shaped tier-2 as `tail -n 5000 ... | python3 - "$arg" <<'PY' ... PY`. The `<<'PY'` heredoc OVERRODE python3's stdin, so `for line in sys.stdin` iterated the python source itself, every `json.loads` raised, and `sys.exit(1)` always fired — the tier never matched any record. Production impact was zero because `jq` is a required dependency (`CLAUDE.md ## Dependencies`) and tier-1 always wins, but the tier was dead code that gave the appearance of fall-through coverage if `jq` ever became optional. v6.4.3 routes the python source through `python3 -c "$_tier2_src" "$skill_name"`: the heredoc resolves at command-substitution time and python3's stdin stays the `tail | ...` pipe. New `AC-CS-4` in `tests/test-hooks-lib.sh` exercises the tier under a `jq`-stripped PATH against a positive (Skill record present) and negative (no Skill records) transcript.

### Changed

- **F-4' — `tests/test-per-phase-metrics.sh` scaffolding migrated off gawk-only `match($0, regex, m)`.** Five sites (lines ~123 / ~204 / ~262-264) used the 3-arg form for phase-name, boundary, ticket_id, phase, and boundary value extraction inside the `write_phase_state` helper, `count_boundary_entries`, and `count_triple_entries`. Under `PATH=/usr/bin:/bin` the suite aborted with `awk: syntax error / bailing out` before reaching the F-1 / F-1' regression checks v6.4.2 / v6.4.3 added. v6.4.3 replaces all five with POSIX `sub()` strip-by-prefix; production behaviour is unchanged (this is test infrastructure only) but the consumer matrix High observability check is now exercisable end-to-end on stock macOS / BSD-only PATH.

### Verification

- `bash tests/test-hooks-lib.sh` — 132/132 PASS (full PATH), including the four new v6.4.3 tier-3 / tier-2 regression cases (AC-CS-4 ×2 for `transcript_contains_skill_invocation` tier-2 under jq-stripped PATH; Section 3-bis ×2 for `_pphc_entry_already_present` under tier-3-only PATH with awk pinned to `/usr/bin/awk`).
- `bash tests/test-per-phase-metrics.sh` — 38/38 PASS (full PATH).
- `PATH=/usr/bin:/bin bash tests/test-per-phase-metrics.sh` — **38/38 PASS, newly unblocked by F-4'**. v6.4.2 had to defer this verification because the test scaffolding itself aborted under BSD awk before exercising the F-1 / F-1' fixes.
- `PATH=/usr/bin:/bin bash tests/test-impl-checkpoint-guard.sh` — 8/8 PASS (unchanged from v6.4.1 / v6.4.2 behavior).
- `bash tests/test-skill-contracts.sh` — 392/392 PASS (full PATH). Under `PATH=/usr/bin:/bin` the suite passes with `Failed: 0` but the Total fluctuates in the 389-391 range across runs because several CT-MODE-* assertions skip when their probed tool is absent from the BSD-only PATH; this orthogonal flakiness is not introduced by v6.4.3 and the v6.4.3 fixes (F-1' / F-4') are exercised by the test-per-phase-metrics + test-hooks-lib lines above.
- `bash tests/test-impl-checkpoint-guard.sh` — 8/8 PASS.
- `bash tests/test-path-consistency.sh` — 138/138 PASS.
- `bash tests/test-checkpoint-template.sh` — 10/10 PASS.
- `bash tests/test-pre-bash-contract-guard.sh` — 5/5 PASS.
- `bash tests/test-state-transition-guard.sh` — 16/16 PASS.
- `bash tests/test-pre-write-safety.sh` — 29/29 PASS.
- `bash tests/test-pre-edit-safety.sh` — 29/29 PASS.

## [6.4.2] — 2026-05-10

Patch release closing five skeptical-review follow-ups deferred from v6.4.1. The largest fix completes the BSD-awk + PyYAML-absent migration that v6.4.1 began: `parse_phase_status` and `parse_ticket_statuses` carried the same gawk-only `match($0, regex, m)` anti-pattern, and an audit of their consumers showed the silent-empty fallback was actively breaking core invariants on stock macOS — `/ship`'s legitimate `git commit` was being blocked by `pre-bash-contract-guard.sh` and the active-sibling skip-guard in `pre-state-transition.sh` was running fail-OPEN. A second fix removes a `_comment` key from `hooks/hooks.json` that matches the schema-validation failure pattern reproduced in [anthropics/claude-code#31278](https://github.com/anthropics/claude-code/issues/31278). The third widens the cross-session staleness window in `transcript_contains_skill_invocation` from 500 to 5000 lines so long autopilot runs stop missing the originating `Skill(simple-workflow:impl)` record. v6.4.1 → v6.4.2 is byte-identical on hosts with `yq` + PyYAML installed; the changes only flip behaviour where the fallback tiers are exercised.

### Fixed

- **F-1 — `parse_phase_status` / `parse_ticket_statuses` BSD-awk fail on stock macOS.** Both helpers used the gawk-only 3-arg `match($0, regex, m)` form in their tier-3 awk fallback and short-circuited their tier-2 python3 branch on `ImportError` instead of falling through to awk. v6.4.1 patched the two new v6.4.0 functions (`parse_impl_next_action` / `get_plan_path`) but explicitly deferred these older callers. A consumer audit found the silent-empty result drove TWO Critical regressions on stock macOS (no yq, no PyYAML): `hooks/pre-bash-contract-guard.sh:147` interpreted the empty `phases.ship.status` as "not in /ship context" and BLOCKED legitimate `git commit` invocations made from inside `/ship`; `hooks/pre-state-transition.sh:376,386` interpreted the empty ticket-status list as "no active siblings" and let through skip writes that should have been blocked. Plus a HIGH observability gap: `hooks/post-phase-checkpoint.sh:439` skipped every phase whose `STATUS` came back empty, so no `runtime_metrics` rows landed for `phase_complete` boundaries on stock macOS. v6.4.2 (a) replaces the gawk syntax with POSIX `sub()` strip-by-prefix anchored at canonical 2/4-space `yq` indents, AND (b) gates the python3 tier on `python3 -c 'import yaml'` succeeding so PyYAML's absence falls through cleanly to awk. New `tests/test-hooks-lib.sh` Section 2-bis exercises both functions through a mocked tier-3 path with `awk` pinned to `/usr/bin/awk` (stock BSD on macOS), so any future re-introduction of gawk-only syntax fails CI.
- **F-2 — `_comment` key in `hooks/hooks.json` matches a known schema-validation failure pattern.** v6.4.0's Stop entry for `impl-checkpoint-guard.sh` carried a sibling `_comment` key documenting the chain order. The Claude Code hooks schema does not document `_comment` ([code.claude.com/docs/en/hooks.md](https://code.claude.com/docs/en/hooks.md)) and the same pattern surfaced in [anthropics/claude-code#31278](https://github.com/anthropics/claude-code/issues/31278) as `Stop hook error: JSON validation failed` for the `ralph-loop` plugin. v6.4.2 removes the key (the design intent is already documented in `hooks/impl-checkpoint-guard.sh`'s header). No formal `description` field exists yet — see [anthropics/claude-code#4475](https://github.com/anthropics/claude-code/issues/4475) and [#17968](https://github.com/anthropics/claude-code/issues/17968) for upstream proposals.
- **F-4 — `transcript_contains_skill_invocation` 500-line tail-window risked silent fail-OPEN on long autopilot runs.** The cross-session staleness guard (5-AND condition (e)) used a hardcoded `tail -n 500` window across all three tiers. A typical 1-3 round `/impl` session is ~1500 transcript lines once tool-use records are counted; longer autopilot retry chains push past that easily, and once the originating `Skill(simple-workflow:impl)` slid out of the 500-line window the hook stopped blocking premature `/audit` handoffs it was designed to catch. v6.4.2 introduces a `_JTA_CROSS_SESSION_TAIL=5000` constant used only by `transcript_contains_skill_invocation` (`_jta_iter_tool_uses` callers stay at 500 by design — they are short-context lookups). The 5000-line choice is empirically backed: timed at ~50 ms per call on a 6.6 MB / 2387-line transcript, vs ~10 ms at 500 — a +40 ms cost for ~10x headroom. Two new in-test fixtures (4900-line within-window, 6000-line overflow) lock in both the detection and the boundary.

### Changed

- **F-3 — `CT-MODE-ICG-3` distance regex now anchors on the Step 4 closing fence instead of the internal `**Summary**:` literal.** The previous regex `\`\`\`\n\*\*Status\*\*:.*?\*\*Summary\*\*:.*?\n\`\`\`` would silently drop to `-1` if a future revision removed or renamed `**Summary**:`, surfacing a misleading `distance=-1 chars` failure. The new regex matches `### 4\. .*?\`\`\`\n.*?\n\`\`\`` (Step 4 heading through closing fence), and the test reports separate `block matcher failed` (sentinel `-1`) and `phase-state.yaml not found` (sentinel `-2`) failure messages so structural drift is distinguishable from distance regression.
- **F-5c — `CT-MODE-ICG-6` proximity check tightened to filter on `[IMPL-CHECKPOINT-RELEASE] Pipeline halted` lines.** The previous check asserted `[IMPL-CHECKPOINT-RELEASE]`, `Resume with: /impl`, and `Resume with: /autopilot` each appeared somewhere in the file; comments or documentation drift could satisfy that without the hook actually emitting them. The new check filters to lines carrying the literal `[IMPL-CHECKPOINT-RELEASE] Pipeline halted` prefix and asserts both Resume variants appear on those filtered lines, so the proximity guarantee is enforced at the contract layer.
- **F-5a / F-5d — micro-cleanups in `hooks/lib/audit-block-pattern.sh` and `hooks/impl-checkpoint-guard.sh`.** The audit-block-pattern.sh header comment now correctly describes the two independent contract checks (`CT-MODE-ICG-2` for SKILL.md literals, `CT-MODE-ICG-5` for the export ERE), and a dead `${INPUT:-}` default in `_runtime_metrics_payload_field` is replaced with `$INPUT` (the `INPUT=$(cat 2>/dev/null || echo '{}')` at script start already guarantees the variable is set).

### Verification

- `bash tests/test-hooks-lib.sh` — 128/128 PASS, including 7 new tier-3 BSD-awk regression cases for `parse_phase_status` / `parse_ticket_statuses` / `parse_impl_next_action` and 3 new cross-session-window cases for `transcript_contains_skill_invocation`. The tier-3 cases mock `_psf_have` to disable the yq + python3 tiers and pin `awk` to `/usr/bin/awk` via `PATH=/usr/bin:/bin`, so the BSD-awk path is exercised under the same modern bash that runs the rest of the suite.
- `bash tests/test-skill-contracts.sh` — 392/392 PASS with the new Status-anchored CT-MODE-ICG-3 regex (`distance=151`) and the tightened ICG-6 proximity check.
- `bash tests/test-impl-checkpoint-guard.sh` — 8/8 PASS under both full PATH and `PATH=/usr/bin:/bin`.
- `bash tests/test-pre-bash-contract-guard.sh` — 5/5 PASS (full PATH; consumer matrix Critical 1 regression check). The end-to-end BSD-only PATH re-run is blocked by `state-authority.sh`'s `declare -A` (bash 4+ only), an orthogonal pre-existing limitation; the F-1 awk fix itself is verified by the new test-hooks-lib tier-3 cases.
- `bash tests/test-state-transition-guard.sh` — 16/16 PASS (full PATH; consumer matrix Critical 2 regression check). Same BSD-only PATH caveat as above.
- `bash tests/test-per-phase-metrics.sh` — 38/38 PASS (full PATH; consumer matrix High observability check). The test scaffolding itself contains gawk-only `match($0, regex, m)` constructs (4 sites, v6.1.1 era), so a BSD-only PATH re-run aborts before exercising the F-1 fix; migrating that suite is deferred (see "Residual / deferred" below).
- `bash tests/test-pre-write-safety.sh` — 29/29 PASS.
- `bash tests/test-pre-edit-safety.sh` — 29/29 PASS.
- `bash tests/test-path-consistency.sh` — 138/138 PASS.
- `bash tests/test-checkpoint-template.sh` — 10/10 PASS.

### Residual / deferred

The skeptical review of v6.4.2 surfaced three same-shape latent defects that were intentionally LEFT OUT of this patch to keep the diff focused on the v6.4.1 follow-up scope:

- **`hooks/post-phase-checkpoint.sh::_pphc_entry_already_present`** uses the same gawk-only 3-arg `match($0, regex, m)` form in its pure-shell idempotency check (lines ~312-320). Under BSD awk + no PyYAML, the helper returns "no entry present" for everything and `runtime_metrics:` rows will be appended duplicates on reentry. Pre-existing since v6.1.1; same fix template as F-1.
- **`hooks/post-phase-checkpoint.sh::_pphc_read_ticket_id`** (lines ~154-174) does NOT gate its python3 tier on `python3 -c 'import yaml'` succeeding, so PyYAML's absence short-circuits to ImportError instead of falling through to awk. Same fix template as F-1.
- **`tests/test-per-phase-metrics.sh`** scaffolding uses the same gawk-only awk syntax in 4 sites (lines ~123/204/262-264), which is why the suite cannot currently be re-run end-to-end under `PATH=/usr/bin:/bin`. POSIX-migrating the test scaffolding is what unblocks BSD-only PATH coverage of the post-phase-checkpoint consumer.

These three items are tracked for v6.4.3 as a single coherent "post-phase-checkpoint POSIX migration" commit, gated on the same release-PR-style verification as v6.4.2.

## [6.4.1] — 2026-05-10

Patch release closing six findings from a skeptical review of v6.4.0's `hooks/impl-checkpoint-guard.sh`. The most serious — a fail-OPEN under macOS's stock `/usr/bin/python3` (no PyYAML) plus `/usr/bin/awk` (BSD, no gawk-style `match()`) — meant a fresh macOS install had ZERO Stop-hook protection against the post-`/audit` handoff failure even though CI showed 8/8 PASS (CI runs with yq + PyYAML installed). v6.4.0 → v6.4.1 is a behaviour-preserving fix on the prompt-side success path and a correctness fix on the harness-side fail-open path; no kill-switch or schema changes. Migration is `bash tests/test-impl-checkpoint-guard.sh` plus a re-run with `PATH=/usr/bin:/bin` to verify the awk-tier path is exercised on the target host.

### Fixed

- **C1 — BSD awk fallback fail-OPEN on stock macOS.** `hooks/lib/parse-state-file.sh::parse_impl_next_action` and `hooks/impl-checkpoint-guard.sh::get_plan_path` used the gawk-only 3-arg `match($0, regex, m)` form in their tier-3 awk fallbacks; macOS `/usr/bin/awk` rejects this with a syntax error and exits non-zero. Combined with `/usr/bin/python3` shipping without PyYAML, the tier-2 python3 branch ALSO failed (`ImportError`) but returned 1 from the function instead of falling through to awk. Net effect: on a fresh macOS without yq, both helpers returned empty, the hook short-circuited at the denylist (empty → `null` → exit 0), and the failure mode the hook was designed to catch passed silently. v6.4.1 (a) replaces the gawk syntax with POSIX `sub()` strip-by-prefix on a local copy of the line, AND (b) gates the python3 tier on `python3 -c 'import yaml'` succeeding so PyYAML's absence falls through cleanly to awk. Indent matching is anchored at exactly 2 / 4 / 6 spaces (canonical `yq` output) so a deeper-nested `artifacts:` line cannot falsely match the phase-key rule. NOTE: existing `parse_phase_status` / `parse_ticket_statuses` carry the same gawk anti-pattern and are tracked separately — this patch is scoped to functions added in v6.4.0.
- **H2 — `find_phase_state_file` selected lex-first, not active.** When two active tickets carried `phase-state.yaml` (e.g. `001-foo/` plus `002-bar/`), the helper always returned `001-foo`'s state regardless of which ticket the model was working on. The Stop hook's 5-AND check ran against the wrong file and could fire incorrectly on ticket 001 while the model was completing ticket 002 normally. Now picks the most-recently-modified candidate via bash's portable `[ -nt ]` test; ties resolve to `find` order.
- **H3 — `get_autopilot_parent_slug` printed wrong slug under concurrent autopilot runs.** Same lex-first flaw as H2 — the release branch's `Resume with: /autopilot <wrong-slug>` could name an unrelated parent when multiple `briefs/active/<slug>/autopilot-state.yaml` existed. Now does a two-pass search: (1) walk upward from `$PWD` and prefer an ancestor that sits directly under `briefs/active/` or `product_backlog/`, (2) fall back to the mtime-newest candidate. The walk-up pins the suggestion to the autopilot worktree the user is actually in.
- **H4 — Fixture (iv) did not assert the SLO denominator metric was emitted.** `tests/test-impl-checkpoint-guard.sh` fixture (iv) only checked `LAST_EXIT_CODE -eq 0` and empty stdout; the new `audit_handoff_via_prompt` metric (the denominator of convergence.md §9's primary SLO ratio `audit_handoff_via_prompt / (audit_handoff_via_prompt + premature_audit_handoff_blocked) >= 0.95`) was never validated in CI. A future change to the conditional gating in the SW-CHECKPOINT branch would have silently regressed the SLO. Now asserts `grep -cF 'stop_reason: audit_handoff_via_prompt' phase-state.yaml >= 1` after the run.
- **H6 — Counter file leaked across SW-CHECKPOINT-seen exits.** When the prompt-side AuditTail completed Phase 3 normally (`## [SW-CHECKPOINT]` visible in tail), the hook exited 0 but did NOT clean `/tmp/.impl-checkpoint-${SESSION_ID}`. A subsequent re-entry under the same SESSION_ID with the counter at, say, 2 would be 1 false-block away from immediate release instead of having a fresh 3-attempt budget. The mtime-reset (`STATE_FILE -nt COUNTER_FILE`) caught the common case via `post-phase-checkpoint.sh`'s state write but only as a coincidental coupling. Now `rm -f` the counter on the SW-CHECKPOINT-seen path explicitly.
- **H10 — SW-CHECKPOINT lag-tolerance grep matched backtick-quoted prose mentions.** `grep -qF '## [SW-CHECKPOINT]'` fired on instruction-prose mentions like `` `## [SW-CHECKPOINT]` `` (in audit/SKILL.md or in `/audit`'s `**Summary**` field if a future SKILL revision describes the marker). Now anchored on `("text":"|\\n)## \[SW-CHECKPOINT\]` so only JSON-text-start or post-newline occurrences (the actual emit shapes) qualify; backtick-quoted prose between other characters does not match.

### Verification

- `bash tests/test-impl-checkpoint-guard.sh` — 8/8 PASS under both full PATH (yq + PyYAML present) and `PATH=/usr/bin:/bin` (BSD awk, no PyYAML, no yq). The latter was the C1 reproducer.
- `bash tests/test-skill-contracts.sh` — 392/392 PASS.
- `bash tests/test-path-consistency.sh` — 138/138 PASS.
- `bash tests/test-hooks-lib.sh` — 118/118 PASS (Negative-AC-1 still passes at 5 public functions).
- `bash tests/test-checkpoint-template.sh` — 10/10 PASS.

## [6.4.0] — 2026-05-09

Hardens the `/impl` orchestration loop against a recurring failure where the agent emits `/audit`'s structured block (`**Status**: ... **Reports**: ...`) and ends the turn before `/impl` Step 18 (Combined Decision) and Phase 3 (`## [SW-CHECKPOINT]` emit + `phases.impl.status: completed`) finalize. Defense is layered: prompt-side first-line via `audit/SKILL.md` Step 4-bis + `impl/SKILL.md` Step 17 strengthening, harness-side last-resort via the new `hooks/impl-checkpoint-guard.sh` Stop hook. Non-breaking: when the prompt path completes Phase 3 normally, the Stop hook stays silent. Default deployment is `block` mode with provisional SLO thresholds; the kill switch `SW_IMPL_CHECKPOINT_MODE` provides a `metric-only` fallback if false-positive rates become problematic.

### Added

- `hooks/impl-checkpoint-guard.sh` (new Stop hook, ~250 lines) — 5-AND gate that returns `decision:"block"` only when ALL of: `**Status**:` AND `**Reports**:` literals in the transcript tail, `phases.impl.next_action ∉ {null, "", proceed-to-phase-3, stop-critical}` (denylist; fail-closed on unknown values), `phases.impl.status != completed`, no `## [SW-CHECKPOINT]` in the recent assistant turn, and a `Skill(name=simple-workflow:impl)` invocation present in the transcript (cross-session staleness guard). Loop counter at `/tmp/.impl-checkpoint-${SESSION_ID}`; release at 3 consecutive blocks. Release stdout pattern mirrors `autopilot-continue.sh:295`: `[IMPL-CHECKPOINT-RELEASE] ... Resume with: /impl <plan-path>` outside autopilot context, or `... Resume with: /autopilot <parent-slug>` inside autopilot context (auto-detected from `briefs/active/*/autopilot-state.yaml`). Counter is independent of `autopilot-continue.sh`'s — both hooks evaluate independently in `/autopilot` context, with asymmetric release thresholds (3 vs 5+) yielding ~8 cumulative attempts before pipeline halt.
- `hooks/lib/audit-block-pattern.sh` (new shared helper) — single source of truth for the `/audit` Step 4 structured-block ERE patterns. Exports `AUDIT_BLOCK_PATTERN_STATUS` and `AUDIT_BLOCK_PATTERN_REPORTS` as hardcoded literals; the skill-contract test asserts these literals appear in `audit/SKILL.md` Step 4 so a documentation drift fails CI rather than silently breaking the runtime guard.
- `hooks/lib/jsonl-tail-audit.sh` `transcript_contains_skill_invocation <skill_name> <transcript_path>` — bounded to the same `tail -n 500` window as the other helpers, returns 0 (found) / 1 (not found). 3-tier fallback (jq → python3+json → grep). Drives the Stop hook's 5-AND condition (e).
- `hooks/lib/parse-state-file.sh` `find_phase_state_file [start_dir]` and `parse_impl_next_action <file_path>` — thin wrappers that re-use the existing `_psf_repo_root` walk and the same yq/python3+PyYAML/awk three-tier strategy as `parse_phase_status`. No yaml-parsing logic is duplicated.
- `hooks/lib/runtime-metrics.sh` documents the four new `stop_reason` values consumed by `impl-checkpoint-guard.sh`: `premature_audit_handoff_blocked`, `audit_handoff_via_prompt`, `phasegate_released_after_N_blocks`, `phasegate_disabled`. Header now also documents the `boundary` × `stop_reason` orthogonality (PX-05's `phase_complete` partition vs. the Stop-hook `session_end` partition) so tune-skill aggregations partition correctly.
- `skills/audit/SKILL.md` — new Step 4-bis `MANDATORY: Handoff back to caller` directly after the Step 4 structured-block emit instructions. Reframes the structured block as INTERMEDIATE (input to the calling skill, not turn-terminal) and mandates the read-`phase-state.yaml`-then-execute-`next_action` continuation when `.simple-workflow/backlog/active/*/phase-state.yaml` is present. Standalone-fallback prose preserves the prior turn-terminal behaviour for manual `/audit` invocations.
- `skills/impl/SKILL.md` Step 17 — strengthened CHECKPOINT line: `/audit has just emitted its structured block. That block is /impl's input, not your output. Read phase-state.yaml; execute phases.impl.next_action immediately (you are now AT Step 18, not done with /impl). Do NOT end your turn. Do NOT summarize the audit. Required next emit: ` `\`## [SW-CHECKPOINT]\`` ` in Phase 3.` Phase 2 prefix gains a paragraph naming PreToolUse intervention as structurally unsuitable for this failure mode (omission, not commission — the Stop hook is the only layer where "the state that should have been written wasn't" is observable).
- `tests/test-impl-checkpoint-guard.sh` (new) — eight fixture-driven cases covering the 5-AND gate ((i) block on full match), three short-circuit denylist values ((ii) `next_action: null`, (iii) `phases.impl.status: completed`), the SW-CHECKPOINT lag-tolerance branch ((iv) silent exit when SW-CHECKPOINT visible), the loop-counter release at 3 ((v) `/impl` Resume command), the cross-session staleness guard (cases (vi) absent `phase-state.yaml` and (vii) absent `Skill(impl)` in transcript), and the autopilot-context release UX ((viii) `/autopilot` Resume command names the parent slug).
- `tests/fixtures/impl-checkpoint-guard/README.md` (new) — fixture-construction notes covering canonical `phase-state.yaml` shapes, transcript shapes, the counter-mtime invariant required for the deterministic release tests, and the boundary-orthogonality reminder.
- `tests/replay/audit-emit-only.jsonl` (new) — narratively-shaped real-transcript replay corpus for ad-hoc manual replay against the hook (the test suite uses inline transcripts for hermeticity).
- `tests/test-skill-contracts.sh` Cat S (six new assertions, IDs `CT-MODE-ICG-1` through `CT-MODE-ICG-6`): Step 4-bis heading literal, `**Status**:` + `**Reports**:` presence in `audit/SKILL.md`, distance-guard for `phase-state.yaml` within 200 chars after the Step 4 structured-block example, the strengthened Step 17 CHECKPOINT line in `impl/SKILL.md`, single-source-of-truth match between `audit-block-pattern.sh` exports and `audit/SKILL.md` literals, and the `[IMPL-CHECKPOINT-RELEASE]` release prefix + both Resume variants in the hook script.
- Kill switch `SW_IMPL_CHECKPOINT_MODE` (3 values): `block` (default; 4-AND-met → `decision:"block"` up to 3 times), `metric-only` (record metric only, never block — false-positive-rate fallback), `off` (record `phasegate_disabled` once and exit; CI / debug only — never production. The `off`-records-a-metric semantic is intentional: a disabled session that produces zero metric rows is invisible to monitoring).
- Stop chain order in `hooks/hooks.json`: `impl-checkpoint-guard.sh` registers BEFORE `autopilot-continue.sh`. A `_comment` key adjacent to the new entry summarises the independent-evaluation contract; the full design rationale (5-AND gating, asymmetric ~8-attempt release in autopilot context) lives in the hook script header.

### Changed

- `tests/test-hooks-lib.sh` Negative-AC-1: jsonl-tail-audit.sh public-function count expectation rises from 4 to 5 to accommodate the new `transcript_contains_skill_invocation` helper. The four pre-existing functions are unchanged.
- `tests/test-checkpoint-template.sh` AC 13.4 / AC 14.2: the assertion that `/audit` and `/plan2doc` "do NOT reference SW-CHECKPOINT" is tightened from `grep -q 'SW-CHECKPOINT'` to `grep -qE '^## \[SW-CHECKPOINT\]'`. The original AC's intent was "no SW-CHECKPOINT *emit*"; v6.4.0's `audit/SKILL.md` Step 4-bis legitimately *references* the marker (in prose, inside backticks) to describe the caller's expected continuation pattern. The tightened pattern still rejects any standalone level-2 SW-CHECKPOINT header (which is the actual emit shape) while permitting prose mentions.

### Deployment notes

Default mode on this release is `block` (not `metric-only`). The recurring failure this hook addresses is already observed in production, so a 4-week metric-only ramp would mean four weeks of NOT blocking a known failure — the wrong default. Provisional SLO thresholds (5% / 10% / 30% hook-fire rates as drift signals; 1 `phasegate_released_after_N_blocks` event as incident trigger) hold for alerting only; final thresholds will be re-derived from the first 4 weeks of observed P50/P95 distributions on `audit_handoff_via_prompt` ratio. If false-positive rate becomes problematic in production, switch to `SW_IMPL_CHECKPOINT_MODE=metric-only` while the prompt-side path is debugged. `SW_IMPL_CHECKPOINT_MODE=off` is reserved for CI / debug scenarios that need to avoid metric-population pollution; the `phasegate_disabled` row keeps disabled sessions visible to monitoring.

## [6.3.3] — 2026-05-09

ac-evaluator gains a Persistence-First Protocol that writes a partial-state marker before any verification tool runs, so 20+ AC plans no longer produce empty `Output` envelopes on turn-budget exhaustion. `/impl` Step 16 distinguishes "no report persisted" (CONTRACT-VIOLATION) from "partial state on disk" (new `[IN_PROGRESS]` diagnostic). The recovery branch that consumes the partial state is deferred to the next ticket.

### Changed

- Persistence-First Protocol added to `agents/ac-evaluator.md`: agents MUST write a `## Status: IN_PROGRESS` skeleton with an AC checklist before invoking any verification tool, then rewrite with terminal verdicts before return. The v4.1.0 idempotency clause forbidding re-invocation solely to persist is preserved.
- `skills/impl/SKILL.md` Step 16 envelope check now branches 3-way: empty Output without a persisted file remains a `[CONTRACT-VIOLATION]` halt; empty Output with a persisted `## Status: IN_PROGRESS` file emits a new `[IN_PROGRESS]` diagnostic and halts as FAIL-CRITICAL pending the recovery branch in the follow-up ticket; non-empty Output proceeds to the existing Status parsing path.

## [6.3.2] — 2026-05-08

Extract `append_runtime_metrics_entry` from inline hook code into a shared `hooks/lib/runtime-metrics.sh` library.

### Changed

- `hooks/lib/runtime-metrics.sh` (new): the `append_runtime_metrics_entry` function is extracted from `hooks/autopilot-continue.sh` into a dedicated shared library. The function body is byte-for-byte identical to the removed inline copy — only the function name changes (underscore prefix dropped). Supports the same three-tier fallback (yq → python3+PyYAML → pure-shell) as the original.
- `hooks/autopilot-continue.sh` refactor: deletes the inline `_append_runtime_metrics_entry` definition and sources `hooks/lib/runtime-metrics.sh` via `$SCRIPT_DIR/lib/runtime-metrics.sh`. The single callsite is renamed from `_append_runtime_metrics_entry` to `append_runtime_metrics_entry` with the same eight arguments. Hook behaviour is byte-for-byte unchanged for all inputs.
- `hooks/pre-compact-save.sh` refactor: deletes `_pc_append_session_compaction` and sources `hooks/lib/runtime-metrics.sh`. The callsite is rewritten from a one-argument wrapper call to an eight-argument `append_runtime_metrics_entry` call with bare variable assignments (not `local` — the loop body is at script top-level). Literal `"null"` is passed for `stop_reason` and `consecutive_stop_blocks`, mirroring the deleted wrapper's hard-coded values. Hook behaviour is byte-for-byte unchanged for all inputs.
- `CLAUDE.md ## Dependencies`: additive paragraph listing all five `hooks/lib/` shared helpers (`forbidden-rationale-patterns.sh`, `parse-state-file.sh`, `jsonl-tail-audit.sh`, `state-authority.sh`, `runtime-metrics.sh`).

## [6.3.1] — 2026-05-08

Defense-in-depth + correctness fix release for `hooks/lib/state-authority.sh`. Closes the six audit warnings that the v6.2.2 ship explicitly deferred (`H-1`, `M-1`, `M-2`, plus three code-quality items) **before** Foundation 3 populates `HOOK_OWNED_FIELDS`, plus four additional latents surfaced by the 2026-05-08 skeptical self-eval (extglob-state leak from `is_hook_owned_field`, two awk YAML scalar parse gaps for quoted scalars and trailing `#`-comments, and a blank-out semantic gap in `state_field_change_blocked`). The registry remains shipped empty (Negative AC-2 of v6.2.2 preserved), so `state_field_change_blocked` still always returns 1 (allow) for every existing payload — behaviour is byte-identical to v6.3.0 for all in-spec inputs. **None — registry remains empty; no migration required.**

### Security

- `hooks/lib/state-authority.sh`: ERE-meta in registry-key leaves can no longer leak into the `grep -E` pattern that detects key-value lines (F-H1). The leaf segment (`${reg_key##*.}`) was previously spliced verbatim into `^[[:space:]]*${leaf}:[[:space:]]`, so a registry key like `.prefix.[abc]` produced the unintended pattern `^[[:space:]]*[abc]:[[:space:]]` and would match any unrelated YAML key starting with `a:`, `b:`, or `c:`. The new internal helper `_sa_ere_escape` neutralises the POSIX ERE metacharacters `[ ] . * ^ $ | ( ) + ? { }` (plus `/` and `\\`) before splicing, eliminating the false-positive block surface. Dormant under v6.2.2/v6.3.0 because the registry shipped empty; closed before Foundation 3 populates it.
- `hooks/lib/state-authority.sh`: registry keys with glob meta other than `*` (i.e. `?`, `[`, `]`, `{`, `}`) are now rejected at the first call to `is_hook_owned_field` and `state_field_change_blocked` with a `state-authority: registry key "<key>" contains glob meta other than * (rejected)` diagnostic on stderr and exit code 2 (F-M1). The new helper `_sa_validate_registry` runs once per process (cached via `_SA_REGISTRY_VALIDATED=1`); callers that mutate the registry mid-process must unset the flag to force re-validation. Fail-fast: a misregistered key is a programmer error, surface it loudly. Dormant under the empty registry today; closed before Foundation 3 makes it observable.

### Fixed

- `hooks/lib/state-authority.sh` `_sa_all_phases_completed`: the awk-based phase-status parser now recognises `briefs/done/<slug>/autopilot-state.yaml` files whose phase statuses are quoted (`status: "completed"` or `status: 'completed'`) (F-QYAML), and strips trailing `# comment` segments (`status: completed  # done`) before equality testing (F-COMMENT). Previously, a quoted scalar or trailing comment caused `resolve_active_state_file` to skip an otherwise-valid done-completed slug. The line filter now admits a leading `"` / `'` character; the strip pipeline runs `# comment` removal before existing trailing-`}` / whitespace trimming, then strips one leading and one trailing quote. Plain unquoted block-form remains the canonical writer output and is unaffected.
- `hooks/lib/state-authority.sh` `is_hook_owned_field`: the function now captures the parent shell's `extglob` state via `shopt -p extglob` on entry and restores it via `eval "$_prev"` on exit (F-EXTGLOB). Previously, calling the function with `extglob` unset in the parent left it permanently set after the first invocation — a side-effect that could subtly change glob semantics elsewhere in the same shell process.
- `hooks/lib/state-authority.sh` `state_field_change_blocked`: a blank-out of an owned field (old value present, new value empty) is now classified as a block, not an allow (F-BLANK). The previous predicate `[ -n "$old_val" ] && [ -n "$new_val" ] && [ "$old_val" != "$new_val" ]` allowed a state-file write that silently cleared a registered field — exactly the lifecycle-violation the hook is supposed to catch. The new predicate fires whenever `old_val` is non-empty AND the value changed (including `new_val` empty). Initial-set (key absent in `old_string`) is still allowed via the early-exit on empty `old_val`.
- `hooks/pre-edit-safety.sh`, `hooks/pre-write-safety.sh`: the unused `REPO_HOOKS_DIR=...` derivation is removed, and the `source` line targets `$SCRIPT_DIR/lib/state-authority.sh` directly (F-M2). Both variables resolved to the same path at runtime, so the change is functionally a no-op; removing the dead line eliminates a confusing second source-of-truth and a static-analysis flag. `hooks/pre-bash-contract-guard.sh` retains the same legacy pattern for now (out of scope; tracked as a follow-up `chore(hooks)` ticket).

### Changed

- `hooks/lib/state-authority.sh`: the three call sites that extracted a key's value from `old_string` / `new_string` (and the `grep -qE` presence probe) are factored into a single internal helper `_sa_extract_leaf_value <leaf> <yaml_blob>` (F-DUP). The helper applies the F-H1 escape exactly once and returns the trimmed value (or empty when absent). `state_field_change_blocked` now treats `[ -z "$old_val" ]` as the canonical "absent" signal, removing the redundant second `grep -qE` call. Public contract unchanged; new internal helpers (`_sa_ere_escape`, `_sa_extract_leaf_value`, `_sa_validate_registry`) carry the `_sa_` prefix and remain non-public.
- `hooks/lib/state-authority.sh`, `hooks/lib/parse-state-file.sh`: header comments on `_sa_repo_root` / `_psf_repo_root` now name the divergence between the two helpers (F-RR). `_sa_repo_root` intentionally adds a `.git` fallback and `pwd -P` canonicalisation; `_psf_repo_root` intentionally omits both because its callers compare against literal `$PWD` and only matter inside an autopilot context. Reconciliation into a shared `hooks/lib/repo-root.sh` is deferred — the in-place comments serve as a documentation anchor.
- `tests/test-hooks-lib.sh` Section 4b (`--- state-authority.sh hardening (v6.3.1) ---`): 22 new assertions covering AC-A1 (F-H1 ERE escape across five distinct unrelated payloads + literal-leaf positive control), AC-A2 (F-M1 registry rejection on `is_hook_owned_field` AND `state_field_change_blocked`, with stderr diagnostic check), AC-B1 (F-M2 absence + `$SCRIPT_DIR/lib` source), AC-B2 (F-DUP helper presence + no inline `grep -E` in old_val/new_val assignments), AC-B3 (F-RR divergence comment in both libs), AC-C1 (F-BLANK blank-out blocked + initial-set still allowed), AC-C2 (F-EXTGLOB preserved across both ON and OFF parent states), and AC-D1 / AC-D2 / AC-D3 (F-QYAML double-quoted, F-COMMENT trailing comment, F-QYAML single-quoted briefs/done adoption). Total assertion count rises from 81 to 103, all green.
- `tests/test-skill-contracts.sh` Cat Q: three new static-contract assertions (`CT-MODE-STATE-AUTH-1` checks `_sa_validate_registry` is present in the lib with the `contains glob meta other than *` diagnostic; `CT-MODE-STATE-AUTH-2` checks `is_hook_owned_field` captures via `shopt -p extglob` and restores via `eval "$_prev"`; `CT-MODE-STATE-AUTH-3` rejects any reintroduction of `REPO_HOOKS_DIR` in `hooks/pre-{edit,write}-safety.sh` and asserts both source from `$SCRIPT_DIR/lib/state-authority.sh`). Total Cat Q assertion count rises from 2 to 5; overall test-skill-contracts.sh count rises from 378 to 381.

## [6.3.0] — 2026-05-07

Hardens the `/impl` orchestration loop against three recurring manual-run footguns surfaced while shipping v6.2.2: (1) the Generator can silently skip files declared in the plan's Affected-files table, (2) a stray unprotected `grep -c` under `tests/` can kill a `set -euo pipefail` test section mid-run when a count is zero, and (3) the v6.2.2 `maxTurns: 20 → 60` floor on `agents/ac-evaluator.md` had no automated guard against accidental rollback. v6.3.0 catches (1) before it reaches the AC Evaluator (S2), migrates the unprotected callsites and adds a permanent contract scanner for (2) (S5), and locks in the 60-floor with a `maxTurns ≥ 30` regression contract (S1). No existing skill behaviour changes when plans declare no Affected-files section or when every declared file is in the diff. Non-breaking, no migration required.

### Added

- `skills/impl/SKILL.md` Step 14 gains a `§14a — Plan-Compliance Pre-Check` sub-step (warn-only). After the post-Generator `git diff --shortstat`, the orchestrator now greps the plan for `^## Affected [Ff]iles$|^## Critical files to modify$`, parses the markdown table that follows (first column, backticks stripped, hard-capped at 80 lines / 50 paths), diffs the declared paths against the union of `git diff --name-only HEAD` and `git ls-files --others --exclude-standard`, and emits one of three verdict lines: `[PLAN-COMPLIANCE] OK (N files matched)`, `[PLAN-COMPLIANCE] no Affected-files section in plan; skipped`, or one `[PLAN-COMPLIANCE-WARN] plan declares "<path>" in Affected files but it is not in git diff (round={n})` per missing path. Per-task / `## Task 1` style plans without an Affected-files section emit the skipped verdict and proceed cleanly. The check is pure read-only (Grep + Read + `git diff` + `git ls-files`); it never blocks the round, never burns round budget, and never invokes an agent.
- `skills/impl/SKILL.md` Step 15 prompt gains a conditional field `h. Plan-Compliance hint`. When `§14a` emitted any `[PLAN-COMPLIANCE-WARN]` lines, the same list is folded into the AC Evaluator prompt so the Evaluator can mark the related AC FAIL when the missing files are load-bearing for it. The hint is omitted entirely on the OK and skipped verdicts.
- `tests/test-impl-plan-compliance.sh` (new) — executable specification for `§14a`. Exercises the parser against four fixture plans (`plan-ok.md`, `plan-missing.md`, `plan-no-section.md`, `plan-critical-files.md` for the alternate `## Critical files to modify` heading) plus a round-number propagation case and two SKILL.md prose contract checks (9/9 PASS). The reference parser implementation in this file MUST stay in lock-step with the `§14a` prose.
- `tests/fixtures/impl-plan-compliance/` (new) — the four fixture plans backing `tests/test-impl-plan-compliance.sh`.
- `tests/test-helper.sh` gains a `count_matches PATTERN [FILE]` helper. It wraps `grep -cE` so that the count is always echoed and the exit code is always 0 — `grep -c` itself exits 1 on zero matches, which kills any `set -euo pipefail` test section that captures the count via simple command substitution. Reads stdin when `FILE` is omitted.
- `tests/test-skill-contracts.sh` gains a new `Cat Q: Test-suite shell hygiene` category with two assertions. `CT-MODE-GREP-C-1` scans every `grep -c` invocation under `tests/` and fails if any is unprotected, where "protected" means an inline `|| true` / `|| count=0` / `|| return 0` / `|| exit N` / `|| count_matches` guard, a surrounding `set +e` ... `set -e` block, a comment line, or an `echo` / `printf` documentation string. The form `|| echo 0` is deliberately rejected (see `### Fixed` below). `tests/test-helper.sh` is exempt because it owns the `count_matches` primitive that legitimately wraps `grep -c`. `CT-MODE-GREP-C-2` asserts `agents/ac-evaluator.md` `maxTurns >= 30` so a future regression that lowers the cap below the v6.2.2 floor (60) cannot silently undo the AC-budget headroom.

### Fixed

- Fifteen previously-unprotected `grep -c` callsites under `tests/` cleaned up. Seven were originally identified by manual audit (`tests/test-hooks-lib.sh:355`, `tests/test-path-consistency.sh:224,788`, `tests/test-per-phase-metrics.sh:321,341`, `tests/test-session-start.sh:272,347`, `tests/test-skill-contracts.sh:3420`); the remaining eight were surfaced by Cat Q's `CT-MODE-GREP-C-1` once the buggy `|| echo 0` form was removed from its accept-list (`tests/test-ac-evaluator-static-rules.sh:47`, `tests/test-path-consistency.sh:429`, `tests/test-pre-compact-save.sh:402`, `tests/test-skill-contracts.sh:3050,3210,3223,3238,3239`). Each is migrated to either `count_matches` (in files that source `tests/test-helper.sh`) or `|| true` followed by a `${VAR:-0}` fallback (in files that do not). The earlier widespread `|| echo 0` idiom is a latent bug: when `grep -c` reads from a real file and finds zero matches, it writes `0` to stdout AND exits 1, so the `|| echo 0` branch fires and appends a SECOND `0`, yielding `"0\n0"` and breaking the surrounding `[ "$VAR" -ge N ]` integer comparison with a stderr `integer expression expected` error. Tests passed today only because the targeted files happened to have non-zero match counts. `|| true` swallows the exit code without appending to stdout, so the captured value is the literal `0` that grep already produced. Cat Q's `CT-MODE-GREP-C-1` accept-list deliberately omits `|| echo 0` to prevent reintroduction.

## [6.2.2] — 2026-05-07

Adds the second of three foundation libraries for the upcoming hook-side enforcement work. This release ships `hooks/lib/state-authority.sh` plus the registry-driven `case` block wiring in `hooks/pre-edit-safety.sh` / `hooks/pre-write-safety.sh`. The registry (`HOOK_OWNED_FIELDS`) ships **empty**, so the new block path is unreachable and behaviour is byte-identical to v6.2.1 for all existing payloads. Subsequent foundation 3 will populate the registry. Non-breaking, no migration required.

### Added

- `hooks/lib/state-authority.sh`: shared library exposing the `HOOK_OWNED_FIELDS` associative array (declared empty) plus three public functions: `resolve_active_state_file [start_dir]` (walks upward to the repo root, then enumerates `briefs/active/`, `product_backlog/`, and `briefs/done/` for `autopilot-state.yaml`; the `briefs/done/` adoption is conditional on every phase status equalling `completed`), `is_hook_owned_field <yaml_key_path>` (registry lookup using `case` glob match; `*` segments are converted to `+([!.])` extglob to match exactly one path segment without dots), and `state_field_change_blocked <state_file> <old_string> <new_string>` (returns 0 when an old/new string pair changes a registered hook-owned field's value; initial-set is permitted). The awk-based phase-status parser handles inline YAML flow mapping (`scout: {status: completed}`) by stripping trailing `}` from extracted values. Foundation 2 of 3.
- `hooks/pre-edit-safety.sh`, `hooks/pre-write-safety.sh`: SCRIPT_DIR/REPO_HOOKS_DIR derivation (modelled on `hooks/pre-bash-contract-guard.sh:66-68`) plus a lazy-source `case` block that fires only when the target `FILE_PATH` matches `*/autopilot-state.yaml` or `*/phase-state.yaml`. The case body sources `hooks/lib/state-authority.sh`, calls `state_field_change_blocked`, and emits `{"decision":"block","reason":"hook_owned_field_violation"}` when the function returns 0. With the registry shipped empty, the function always returns 1 (allow), so the new path is unreachable and the byte-equivalence guarantee on existing payloads holds.
- `tests/test-hooks-lib.sh`: new `--- state-authority.sh ---` section adds 26 assertions covering AC 1-13 (file existence, public function exports, `resolve_active_state_file` for briefs/active and briefs/done-completed (inline-YAML) and briefs/done-incomplete cases, `is_hook_owned_field` exact and glob match semantics including the dotted-segment guard, `state_field_change_blocked` empty / exact / glob / initial-set permutations) plus Negative-AC 1, 2, 3, 5 (no extra public API, no registry pre-population, no CronCreate / cron-handoff coupling in the lib, no `skills/` or `agents/` path leaks). Total assertion count rises from 55 to 81, all green. AC-14/15 (100-fixture batch byte-equivalence) and AC-16/17 (registry-populated block path) are not in the unit suite (verified out-of-band during /audit smoke; full coverage deferred to a /test follow-up).

### Changed

- `agents/ac-evaluator.md` `maxTurns` from 20 to 60. The previous ceiling could not accommodate larger acceptance-criteria sets (e.g. T-002's 22 ACs each requiring fixture setup + run + verify), causing the agent to exhaust its turn budget mid-investigation and fail the Report Persistence Contract by terminating before the Write call. Bumping the ceiling restores the contract's load-bearing guarantee that the report is always written before return. Note: a deeper concern remains — the agent can still terminate its turn before the Write call even within the budget; addressing that requires prompt / contract changes filed as a separate follow-up. The contract semantics, return shape, and tool list are unchanged.

## [6.2.1] — 2026-05-07

Adds the first of three foundation libraries planned for the upcoming hook-side enforcement work. This release ships only `hooks/lib/jsonl-tail-audit.sh` plus its test suite — there are no consumers yet (the existing hooks are unchanged). Subsequent foundations 2 and 3 will wire the helpers into `pre-edit-safety.sh` / `pre-write-safety.sh` and the pre-skill / pre-agent contract guards. Non-breaking, no migration required.

### Added

- `hooks/lib/jsonl-tail-audit.sh`: shared helper exposing four public functions (`jsonl_tail_skill_uses`, `jsonl_tail_agent_uses`, `jsonl_tail_tool_use_count`, `jsonl_tail_most_recent_skill`) that inspect the session JSONL transcript via a hard-bounded `tail -n 500 -- "$transcript"` window. The bound is a literal constant — callers cannot widen it — and the `--` separator rejects leading-dash filenames. Filters use `jq --arg` for both tool name and output field, ruling out filter injection. Foundation 1 of 3; no consumers in this PR.
- `tests/fixtures/jsonl-tail-audit/`: four JSONL fixtures (empty, 3-skill in document order, 600-line overflow with all skill records in the first 100 lines, mixed-tool with 5 Skill / 3 Agent / 12 Bash tool_use records). Used by both the new lib's tests and any future consumer that needs deterministic transcript shapes.
- `tests/test-hooks-lib.sh`: new `--- jsonl-tail-audit.sh ---` section adds 20 assertions (AC-1..AC-7 plus Negative AC-1..AC-4) covering the four public functions, the literal-bound `tail -n 500` invariant, document-order preservation, mixed-tool counting, and the no-`skills/`-or-`agents/`-path-leak negative AC. Total assertion count rises from 35 to 55, all green.

## [6.2.0] — 2026-05-07

Unifies bare-description, brief, and findings modes of `/create-ticket` onto a single decomposer-led partition path. Bare and brief modes previously used the `planner` agent's Split Judgment as a side task during ticket drafting; the partition decision now lives exclusively in the `decomposer` agent in every mode. The plugin's external interface (CLI arguments, file layouts, ticket-template / split-plan / phase-state schemas) is unchanged — only the partition heuristic and an internal env-var scope move.

### Added

- `agents/decomposer.md` documents two input forms (`findings_doc` for findings mode, `scope_context` for bare/brief modes) selected via the spawn-prompt header `Input form: <form-name>`. `findings_doc` preserves the v6.1.x contract (frontmatter parsing, `## Required Work Units` authoritative). `scope_context` is the new form: caller-supplied `Parent slug:` header, `## Context` (bare description verbatim, or brief.md `## Vision` + `## Business Context`), `## Investigation Summary` (researcher's `investigation.md`), optional `## Socratic Answers`. The agent enumerates Work Units itself in `scope_context` mode, grounded in the supplied investigation evidence.
- `skills/create-ticket/references/spec-decomposer-input.md` — canonical schema for both decomposer input forms. Loaded into create-ticket SKILL.md Pre-computed Context via the standard backtick-bang pattern. Failure modes (missing input-form header, missing parent-slug header, missing required-work-units in `findings_doc`, cycle in dependency graph) documented as a single section.
- `skills/create-ticket/SKILL.md` Bare Description Mode steps D-0..D-7 (capability guard → parent_slug derivation → Phase 1 researcher → Phase 2 Socratic → `scope_context` synthesis + decomposer invocation → per-skeleton planner expansion → per-ticket evaluation → Common Write Path). The previous D-1..D-3 monolithic dispatch is replaced.
- `skills/create-ticket/SKILL.md` Brief Mode steps B-0..B-8 with the same shape as bare mode. Investigation reuse (`{ticket-dir}/investigation.md` freshness check) is preserved verbatim from v6.1.x for re-entry scenarios; fresh runs use a transient `.simple-workflow/.tmp/create-ticket-{parent-slug}/investigation.md` location.
- `tests/test-skill-contracts.sh` Category DEC: 8 new assertions (CT-DEC-1, CT-DEC-1b ×2, CT-DEC-2, CT-DEC-3, CT-DEC-4, CT-DEC-5, CT-DEC-6) covering decomposer input contract, per-mode SKILL.md steps, the negative removal of legacy Split Judgment vocabulary, the Mandatory Skill Invocations table coverage, and the all-modes capability-guard reference count.

### Changed

- `/create-ticket` bare-description and brief modes now route partition through the `decomposer` agent instead of the `planner` Split Judgment heuristic. The change is internal to `/create-ticket` — argument shape, output paths, ticket structure, and SW-CHECKPOINT format are all preserved. Observable behaviour: short bare descriptions and short briefs that previously produced a single ticket may now produce 2+ tickets when the decomposer identifies multiple independently-deployable work units in the synthesized `scope_context`; conversely, scopes that previously produced N>1 via Split Judgment may collapse to N=1 when the decomposer judges the work indivisible. **Pinning the partition**: when a specific ticket count is required, supply a `findings=<path>` document with explicit `## Required Work Units` headings — Form A (`findings_doc`) treats those headings as authoritative.
- The environment variable `SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1` now fails-close in **all three modes** (bare / brief / findings), not just findings mode. The error message and stdout contract are unchanged — only the scope of where the guard fires expands. **Compatibility note**: callers that previously relied on the env var to disable findings mode while keeping bare/brief running will see all three modes refuse. Unset the variable to restore prior behaviour, or pin the plugin to a v6.1.x release. The expanded scope is intentional: with all three modes routed through the decomposer, a single guard now covers the full partition surface.
- The `planner` agent no longer receives Split Judgment instructions in any mode. The `confidence:` signal field, the `runtime_metrics:`-driven dynamic split-loop shrinkage, and the lazy re-evaluation skip are all removed from `skills/create-ticket/SKILL.md` Phase 3. The `agents/planner.md` agent file itself is unchanged (Split Judgment was always a skill-level instruction, never agent-resident logic). **Downstream-skill note**: anything that grepped `skills/create-ticket/SKILL.md` for the literals `Split criteria` / `Split Rationale` / `at least Size S` must update to grep the new Cat DEC contract markers (`Input form: scope_context`, `Step D-4`, `Step B-5`).
- `skills/create-ticket/SKILL.md` Mandatory Skill Invocations table: the `decomposer` row now reads "All modes — after Phase 1 (researcher in bare/brief modes; findings file in findings mode) and any Socratic Refinement, before planner". The Binding rule for `MUST invoke decomposer via the Agent tool` is generalised from "in findings mode" to "in every mode (bare / brief / findings)".
- `skills/create-ticket/SKILL.md` Phase 3 contains a single short paragraph "Partition is owned by the decomposer (all modes)" replacing the previous Split Judgment / Dynamic split-loop shrinkage / Lazy re-evaluation subsections. The planner spawn prompt no longer carries split judgment instructions in any mode.
- `agents/decomposer.md` Hard Constraint #2 generalised from "NEVER invent work units not grounded in the findings document" to "NEVER invent work units not grounded in the provided context", with explicit per-form grounding scopes (`findings_doc` grounds in `## Required Work Units` / `## Investigation Summary` / `## Context`; `scope_context` grounds in `## Investigation Summary` / `## Context` / `## Socratic Answers`).

### Removed

- `skills/create-ticket/SKILL.md` Phase 3 sections: Split Judgment (bare / brief modes only), Dynamic split-loop shrinkage (one-shot read of `runtime_metrics:`), and Lazy re-evaluation (skip the re-evaluation loop on high-confidence drafts). The closing parenthetical referencing findings-mode decomposer authority is also removed; the new "Partition is owned by the decomposer (all modes)" paragraph subsumes its meaning.
- `tests/test-skill-contracts.sh` Cat L assertions L-4 (Split criteria / Split Rationale presence) and L-5 (split guardrails). Cat BL assertion CT-MODE-BL-4 (lazy re-evaluation + one-shot read presence). All three were tied to mechanisms that no longer exist in v6.2.0.

## [6.1.1] — 2026-05-03

### Added
- `ac-evaluator` tautological assertion static detector (PX-07). Three deterministic anti-patterns — **R1** (reference equality of the same symbol), **R2** (vacuous numeric boundary against a literal extremum), **R3** (constant-only boolean assertions) — are surfaced every round as `R<N>: <file>:<line> — <excerpt>`. A `// intentional reference equality test` hint comment exempts legitimate reference-identity tests. No env-var bypass and no warning-only mode.
- `hooks/lib/forbidden-rationale-patterns.sh` and `hooks/lib/parse-state-file.sh` (PX-01): shared helper scripts under the new `hooks/lib/` directory. The first exports the canonical 10-regex `FORBIDDEN_RATIONALE_PATTERNS` array so every guard checks the same context-pressure rationale list. The second exposes autopilot-context / phase-status / ticket-status / state-file lookup helpers backed by a `yq` → `python3 + PyYAML` → `awk` graceful-degrade chain. Neither helper introduces an environment-variable bypass.
- `tests/test-hooks-lib.sh`: 28 unit assertions exercising the two helpers above (10 forbidden-pattern probes, 4 declared-function checks, full coverage of the parse-state-file fixtures across `briefs/active/`, `product_backlog/`, and `briefs/done/` lookup branches). Runs without yq or PyYAML installed.
- `tests/test-skill-contracts.sh` Category CP (PX-01 AC #1..#4): four new assertions guarding the Manual Bash Fallback bullet list, the `## Context-Pressure Response Paths` heading position, the new section body, and the `auto compact is normal operation` taxonomy literal.
- `hooks/pre-bash-contract-guard.sh` (PX-02a): new `PreToolUse:Bash` hook that blocks Manual Bash Fallback contract violations at the moment a Bash call is about to fire. Inside an autopilot tree it rejects (1) appends to `manual_bash_fallbacks[]` whose `reason` matches a forbidden rationale (`context_budget_fallback`), and (2) direct `git commit` invocations outside a `/ship` Skill phase (`unauthorized_ship_inline`). No environment-variable bypass and no rate / threshold concept.
- `tests/test-skill-contracts.sh` Phase B (PX-02b): post-hoc audit that scans `manual_bash_fallbacks[].reason` text in fixture YAML files for the canonical forbidden-rationale regex list. Phase B is the run-after counterpart to PX-02a's PreToolUse:Bash guard, flagging any rationale that slipped past the runtime block. Detection is restricted to the `reason` field — `invocation_method == manual-bash` itself remains a legitimate state for anomaly recovery.
- `tests/test-precompact-end-to-end.sh` (PX-06): end-to-end fixture that forces the PreCompact hook to fire and asserts `runtime_metrics:` gains a `boundary: session_compaction` entry. Four scenarios cover the PX-03 hook-discovery extension and its NAC #7 guard (active-only append, done-with-all-completed append, done-with-pending no-append, no-state-file graceful exit). Each scenario runs in its own tempdir and cleans up via `trap cleanup EXIT`.
- `hooks/pre-state-transition.sh` (PX-04): new `PreToolUse:Write` and `PreToolUse:Edit` guard that blocks unauthorized `status: skipped` transitions on `autopilot-state.yaml` / `phase-state.yaml` before the write lands. Inside an autopilot tree it rejects (1) skipped writes with active siblings absent a ticket-level `override_skip: true` or a dependency-cascade marker (`unauthorized_skip_with_active_siblings`), and (2) skipped writes whose `skip_reason` matches a forbidden rationale even with `override_skip: true` (`unauthorized_skip_with_forbidden_rationale`) — closing the override-as-context-budget-bypass escape route. No environment-variable bypass, no `AskUserQuestion` escalation path.
- `hooks/post-phase-checkpoint.sh` (PX-05): new `PostToolUse:Write` / `PostToolUse:Edit` hook that appends `boundary: phase_complete` / `phase_failed` / `phase_skipped` entries to the parent `autopilot-state.yaml.runtime_metrics` whenever a `phase-state.yaml` transitions a phase to one of those three terminal values. Provides the per-phase observation density Plan 07 dynamic phase shrinking needs, beyond the single session-level entry the existing Stop / PreCompact writers emit. Idempotent against repeated writes via a full-array `(ticket_id, phase, boundary)` triple check. Per-phase entries carry `stop_reason: null`; existing `session_end` / `session_compaction` entries are unchanged. Emit failures warn to stderr and exit 0 so observability outages never halt autopilot progression.

### Changed
- `skills/autopilot/SKILL.md` `## Manual Bash Fallback Discipline` (PX-01): added a clarification that context window / context budget pressure is **NEVER** an anomaly, and a third bullet under `**MUST NOT treat as Manual Bash Fallback**:` enumerating the forbidden context-pressure rationales (`context window`, `context budget`, `context pressure`, `context exhausted`, `context occupancy`, `token budget`). The canonical Manual Bash Fallback definition line is preserved verbatim.
- `skills/autopilot/SKILL.md` (PX-01): new `## Context-Pressure Response Paths` section immediately above `## Stop Reason` enumerating two canonical responses — **(a)** accept auto-compaction (PreCompact + resume path) and **(b)** stop via `unexpected_error.action: stop` — and explicitly forbidding any third path (no `AskUserQuestion`, no inline-equivalent fallback, no Skill bypass to "save tokens"). All predicates use `MUST NOT` / `NEVER` verbs.
- `skills/autopilot/references/stop-reason-taxonomy.md` (PX-01): the PreCompact discrimination heuristic note now states `auto compact is normal operation, not a failure mode` so taxonomy readers see the normalisation explicitly.

### Fixed
- `hooks/pre-state-transition.sh` structural override placement check (Rule 2) now emits the distinct `malformed_override_placement` reason tag instead of reusing Rule 1's `unauthorized_skip_with_active_siblings`. The duplicate tag previously masked Rule 2 regressions because no test fixture reached Rule 2 (every existing fixture tripped Rule 1 first), and the existing `assert_guard_block` substring match could not have distinguished the two anyway. `tests/test-state-transition-guard.sh` gains fixture (e3) which genuinely exercises Rule 2 — every plain-skipped ticket carries a `dependency_failed` cascade marker (clearing Rule 1) while a top-level `override_skip: true` is planted at column 0 — and fixture (e)'s expected tag is narrowed from the `unauthorized_skip` prefix to the full `unauthorized_skip_with_active_siblings` literal so a future Rule 2 regression cannot hide behind Rule 1's tag. Rule 1's tag, block conditions, and check order are unchanged; no env-var bypass introduced.
- `pre-bash-contract-guard.sh` now compares `phases.ship.status` against the canonical hyphen form `in-progress` (matching `phase-state-schema.md` and `/ship` SKILL writes) instead of the underscore form `in_progress`. The mismatch previously caused real `/ship` runs to be blocked as `unauthorized_ship_inline` because `parse_phase_status` returns the hyphen literal verbatim and never matched the underscore comparison. The companion test fixture (`tests/test-pre-bash-contract-guard.sh`) is updated to write the hyphen form so the suite no longer false-greens against the wrong literal.
- `runtime_metrics:` write window for terminal Stop / PreCompact events. After `/ship`'s Split State File Cleanup moves `autopilot-state.yaml` from `briefs/active/` to `briefs/done/`, the same-turn Stop hook (`hooks/autopilot-continue.sh`) and PreCompact hook (`hooks/pre-compact-save.sh`) previously failed to discover the moved state file and silently skipped the `runtime_metrics:` append, leaving the list empty for the entire run. Both hooks now scan `briefs/done/` as a third fallback lookup root, evaluated after `briefs/active/` and `product_backlog/`. To avoid a premature `partial_completion` emit against a half-finished run that was moved by mistake, a `briefs/done/` candidate is adopted only when every pipeline step has reached `completed`; pending or in-progress steps disqualify the candidate. No new dependencies — the existing `yq` → `python3 + PyYAML` → pure-shell fallback chain is preserved.
- `hooks/post-phase-checkpoint.sh` (PY-02) now iterates the canonical 3 phases (`scout` / `impl` / `ship`) rather than the original five-phase list, matching the schema in `skills/create-ticket/references/phase-state-schema.md` (no skill writes `phases.audit:` or `phases.tune:`). The runtime_metrics per-run capacity ceiling for a clean six-ticket run is therefore 18 entries (6 tickets × 3 phases), correcting the inflated upper bound previously documented in the PX-05 entry. Fixtures under `tests/fixtures/per-phase-metrics-samples/` drop their fabricated `audit:` / `tune:` slots, and `tests/test-per-phase-metrics.sh` plus the new `tests/test-skill-contracts.sh` Cat PY assertions guard the reduced scope.
- `hooks/post-phase-checkpoint.sh` (PY-05) trailing-newline check now uses `tail -c 1` directly instead of an `awk 'END{print substr(...)}'` workaround, and PX-05 NAC #6 narrows its grep from the overbroad `tail.*[0-9]+` (which collided with `tail -c 1` byte-reads and `tail -f`) to `\btail[[:space:]]+-n([[:space:]]+|=)?[0-9]+` so only the actual window-cap idiom (`tail -n N`) is forbidden. The evasion comment that admitted the awk form existed solely to dodge the previous grep is removed; trailing-newline behaviour for fixtures with and without a final `\n` is preserved.

## [6.1.0] — 2026-04-30

Bundles the test_simple_workflow13 mitigation work (Plans 01–07): observability, an autopilot stall guard, return-value caps for sub-agents, and dynamic phase shrinking. Non-breaking — the one behaviour change (Stop hook release rule) carries a kill switch for immediate rollback.

### Changed
- `/autopilot` Stop hook (`hooks/autopilot-continue.sh`) now releases only when **both** the state-mtime counter (`FILE_COUNT`) and a new tool-use counter (`NOTOOL_COUNT`) reach 5 (Plan 02). `NOTOOL_COUNT` increments when the most recent assistant turn invokes none of `Skill` / `Agent` / `Bash` / `Edit` / `Write` / `NotebookEdit`; `Read`-only turns do not reset it. On release, stdout: `[AUTOPILOT-STALL] Pipeline halted: model emitted N consecutive end_turn attempts without tool calls or state progress. Resume with: /autopilot {parent-slug}`. **Migration / kill switch**: `AUTOPILOT_LEGACY_LOOPGUARD=1` reverts to the v6.0.5 single-counter behaviour bit-for-bit — intended for immediate rollback only.
- Per-Agent return-value cap (`< 500 tokens`) now reaches every entry-point Skill launch site (Plan 04): `skills/scout/SKILL.md` (`/investigate`, `/plan2doc`), `skills/impl/SKILL.md` (`implementer`, `ac-evaluator`, `/audit`), and `skills/create-ticket/SKILL.md` (`researcher`, `decomposer`, `planner`, `ticket-evaluator`). The 4-status verdict enum, **Report Persistence Contract**, and `runtime_metrics:` schema are unchanged. No new Agent or Skill files were introduced.
- `/brief` Phase 2 and `/create-ticket` split judgment perform a single one-shot read of `autopilot-state.yaml.runtime_metrics:` last entry at phase start (Plan 07). `remaining_pct = 1.0 − (input_tokens + cache_read_input_tokens) / context_window_size`. `/brief` Phase 2 ceiling: `≥ 70%` → 30 questions (existing); `50–70%` → 15; `30–50%` → 6; `< 30%` → 1. `/create-ticket` skips the `ticket-evaluator` / `re-evaluator` loop when the initial `planner` returns `confidence ≥ 0.8`. Standalone invocations (no `autopilot-state.yaml`) keep the existing 30-question ceiling and full re-evaluation loop. The `mode independence guard`, Phase 1 `researcher` paragraph, and S/M/L/XL split thresholds are unchanged.

### Added
- `runtime_metrics:` measurement foundation in `autopilot-state.yaml` (Plan 01). Stop / PreCompact hooks append session-level entries (`boundary: session_end` / `boundary: session_compaction`) capturing `cache_creation_input_tokens`, `cache_read_input_tokens`, `input_tokens`, `consecutive_stop_blocks`, and a discriminated `stop_reason` (`normal_completion` / `partial_completion` / `loop_guard_release` / `null`). Append is graceful: `yq` → `python3 + PyYAML` → pure-shell fallback. Per-ticket boundaries are out of scope for Plan 01.
- `skills/autopilot/references/stop-reason-taxonomy.md`: tracked source of truth for the `boundary` (2 values) and `stop_reason` (6 values) enums plus the discrimination heuristic. `skills/autopilot/SKILL.md ### State file initialization` cites it via a relative path.
- `## Stop Reason` section in `skills/autopilot/SKILL.md` (Plan 05) describing the `autopilot-log.md` Stop Reason format. Tag values reference [`references/stop-reason-taxonomy.md`](skills/autopilot/references/stop-reason-taxonomy.md) — per-tag conditions are not duplicated in SKILL.md prose. Same `stop_reason` namespace as `autopilot-state.yaml` `runtime_metrics:`.
- `hooks/post-skill-cleanup.sh` (Plan 03): `PostToolUse` hook that physically removes any stale `auto-kick.yaml` after every `simple-workflow:autopilot` Skill invocation. Defense-in-depth backstop for the Phase 1 step 0 MUST clause. Idempotent on missing files; depth-agnostic (flat and nested `briefs/active/` layouts). Non-autopilot Skills are no-ops; logs to stderr only. `hooks/hooks.json` extended with the matching `PostToolUse` matcher; `skills/autopilot/SKILL.md` Phase 1 step 0 carries a one-line `Note:` explaining the hook is defense-in-depth.
- `### Long-session symptoms` subsection inside `README.md ## Limitations` (Plan 06): docs-only guidance for the `/autopilot` self-abort failure mode below the context-window cap. Names the resume design, the Plan 02 / 04 mitigations, and the separately-scheduled future work (per-ticket session split). Deliberately omits `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` references (deferred pending official documentation).
- `agents/decomposer.md` now carries the explicit `## Context Conservation Protocol` heading — the only in-scope agent that previously lacked it.
- `## Dependencies` section in `CLAUDE.md` listing `git`, `gh`, `jq`, and `yq` (mikefarah/yq v4) with one-line purpose for each.
- `tests/test-skill-contracts.sh` gains four contract guard families (348 → 364 assertions): **Cat RM** (`CT-MODE-RM-1/2/3`, taxonomy + SKILL.md citation + schema), **Cat LT** (`CT-MODE-LT-1/2/3`, loop-tail + Stop Reason + 6-tag discoverability), **Cat RV** (`CT-MODE-RV-{scout,impl,front,agents}`, cap-clause references), **Cat BL** (`CT-MODE-BL-1..4`, dynamic shrinkage + lazy-evaluation conventions).
- New / extended test suites: `tests/test-autopilot-runtime-metrics.sh` (16 / 6 cases), `tests/test-post-skill-cleanup.sh` (23 / 6 cases), `tests/test-brief-lightening.sh` (15 / 3 fixtures plus consistency checks), `tests/test-autopilot-continue.sh` extended with 9 Plan-02 cases (34 → 43 assertions).
- Shared fixtures (per `00-index.md` Common Fixture Layout): `tests/fixtures/transcripts/{tool_use_present,text_only_5_consecutive,state_advancing,read_only_turns,malformed,realistic_full_turn}.jsonl`; `tests/fixtures/autopilot-state-samples/{empty,single-ticket,multi-ticket,mock_state_{80,40,10}pct}.yaml`; `tests/fixtures/payloads/{stop-hook-end-turn,empty}.json`; `tests/fixtures/briefs/{flat-layout,nested-layout}/`.

## [6.0.5] — 2026-04-28

### Changed
- `## Quick Start` in `README.md` trimmed to the install commands only. The previous section additionally rendered a six-line pure-manual flow preview, a forward-pointer sentence to `## Three Ways to Run`, and a Note about Copilot CLI session-lifecycle hooks. Every one of those was either duplicated by the immediately-following `## Three Ways to Run` comparison table (the manual flow is row 3 of that table) or made redundant by section adjacency (the forward-pointer pointed at the next heading). The trim makes the install command the only artifact in `## Quick Start`, so the reader's eye lands on the `## Three Ways to Run` decision matrix — where `/brief <idea>` (full automation) is row 1 — within a few lines of installation. README length: 266 → 249 lines.

### Removed
- `Contributors` and `Discussions` shields.io badges from the README header. The Contributors badge added no real signal at the project's current scale; the Discussions badge linked to a tab that is not the canonical support channel for end users.
- `GitHub Stars` shields.io badge from the README header. Stars are visible on the GitHub repository chrome itself and do not need a duplicate badge.

The README header now displays exactly three badges — **CI** (build status), **Release** (latest version), and **License** (Apache-2.0) — covering the only signals that are not already visible on the GitHub repo chrome.

### Moved
- The Note about Copilot CLI session-lifecycle hooks (`pre-compact-save`, `session-stop-log`) and the recommendation to use `/catchup` after compaction. Previously a blockquote inside `## Quick Start`, now a bullet under `## Limitations` next to the IDE-extensions compatibility caveat. Same content, better section fit.

## [6.0.4] — 2026-04-28

### Added
- `## How it Works` section in `README.md`: a fenced ASCII tree that names every skill in the canonical pipeline and the sub-agents each one dispatches, sourced directly from `skills/*/SKILL.md` rather than from prose. The tree shows `/brief`, `/create-ticket`, `/scout`, `/impl` (with its chained `/audit`), `/ship`, and `/tune` in dispatch order, marks the two real verification loops with `🔁` (the `ticket-evaluator` quality-gate retry inside `/create-ticket`, and the `ac-evaluator` / `code-reviewer` / `security-scanner` retry-to-`implementer` cycle inside `/impl`), and lists the artifacts each phase writes (`brief.md`, `ticket.md`, `investigation.md`, `plan.md`, `eval-round-N.md`, `quality-round-N.md`, `security-scan-N.md`). A `Reading guide` legend explains the `├─` / `└─` / `🔁` / `(chained)` / `produces:` notation. A separate fenced block enumerates the six out-of-pipeline skills (`/investigate`, `/plan2doc`, `/test`, `/refactor`, `/catchup`, `/autopilot`) with their sub-agents. Surfaces the previously-undocumented `decomposer` agent (used by `/brief` and `/create-ticket`).
- `## Why simple-workflow?` now opens with a TL;DR three-pillar bullet list (Generator-Evaluator firewall / Context Conservation / cross-session learning) before the existing four-threats prose. The bullets were promoted from the removed `## At a Glance` section so the rationale is now reachable without scrolling past the threat-table introduction.

### Changed
- `README.md` restructured for a tighter information architecture (207 → 266 lines): `Quick Start` reaches the install command at line 30, `Three Ways to Run` at line 43, `How it Works` at line 61, and `Why simple-workflow?` at line 124. The new `## How it Works` heading sits between `Three Ways to Run` (how a user drives the system) and `Why simple-workflow?` (why the architecture exists), so the document now answers `what / how to run / what happens internally / why` in that order.

### Removed
- `## At a Glance` section in `README.md` (heading, overview paragraph, and three differentiator bullets). The differentiator bullets were not deleted — they moved verbatim to the top of `## Why simple-workflow?` as a TL;DR.
- `docs/assets/demo.svg` (the hand-crafted terminal-mockup SVG embedded as the README hero in v6.0.3). The file is replaced by the textual `## How it Works` ASCII tree, which is grounded in `skills/*/SKILL.md` rather than a hand-curated demo, renders identically in every Markdown renderer (Mermaid, SVG-embed, and asciinema-cast paths all have at least one renderer that fails them), and is editable without touching binary assets. The empty `docs/` parent directory is also removed.

## [6.0.3] — 2026-04-28

### Changed
- `README.md` refactored end-to-end for clarity and brevity (380 → 200 lines, ~47% reduction). Restructured the document so readers reach `## Quick Start` within the first 25 lines instead of after ~155 lines of "Why" prose. Removed `## Table of Contents` (GitHub auto-anchors cover it). Added two new top-level sections: `## At a Glance` (one-paragraph functional summary plus three differentiator bullets — Generator-Evaluator firewall, Context Conservation, cross-session learning) and `## Three Ways to Run` (a single comparison table that consolidates the previously-scattered `Full Automation with /brief + /autopilot` and `Manual flow with /brief` subsections into one place). Compressed `### Harness Engineering`, `### Knowledge Base`, and `### Ticket Management` while preserving every load-bearing claim — the Four Threats table, the full three-bullet `### Context Conservation Protocol` block, and the literal phrase `weights × context = output` are all retained verbatim. Merged the previous `## Setup` and `## Configuration` H2 sections into `## Setup & Configuration` and collapsed the two prior `.gitignore` opt-out examples (ticket-counter sharing and shared-spec sharing) into a single parameterized fenced block. Renamed `## All Skills` to `## Skill Reference` (same 13-row table). Reduced the standalone `## Migrating from v4.x` H2 to a one-line blockquote footer that still links to the v5.0.0 migration announcement. No Mermaid diagrams introduced — kept the README in pure ASCII / Markdown for renderer-independent display. No changes to skills, agents, hooks, tests, or any other tracked file.

## [6.0.2] — 2026-04-27

### Added
- `skills/audit/references/categories.md`: canonical per-Category checklist source for `/audit`, with the six required `## Category: <name>` sections (`CodeQuality`, `Security`, `Performance`, `Reliability`, `Documentation`, `Testing`) and at least three `- [ ] <Capitalized item>` checklist items under each. Adding a seventh `## Category: <name>` (e.g. `Accessibility`) is permitted and is not flagged as drift.
- `tests/test-skill-contracts.sh` Category AD: contract test for the new checklist source. Emits the literal stdout line `audit-references: present` when the file has all six required headers and >=3 items each, and emits the literal stderr lines `audit-references: missing`, `audit-references: empty`, or `audit-references: incomplete-headers` for the corresponding failure modes. Guards (`AD-4`, `AD-5`) verify that `skills/audit/SKILL.md` continues to document the `category=<value>` / `checklist_source=...` dispatch-log format and the `(Category: <CategoryName>)` report-line format.
- `## PII` section in the project `CLAUDE.md` documenting the `<repo>` placeholder convention, the `absolute home path` detection contract, the fenced-code-block exemption, and the `.gitignore` allowlist. Mirrors the new hook-side guard so the human-readable policy and the enforcement layer stay in lockstep.
- `tests/test-skill-contracts.sh` `CT-PII-1`: emits `pii-policy: declared` to stdout when `CLAUDE.md` contains all three required tokens (`## PII`, `<repo>`, `absolute home path`); emits `pii-policy: missing in CLAUDE.md (...)` to stderr and fails when any token is missing.
- New PII regression suites in `tests/test-pre-write-safety.sh` and `tests/test-pre-edit-safety.sh` covering each AC, Negative AC, and Edge Case from the plan (rejection on `/Users/<name>/` and `/home/<name>/`; acceptance for `<repo>/...`, fenced code blocks, lowercase `/users/`, Windows backslashes, `.gitignore`, `/Users/` at EOL, `<repo>` mixed with a real home path, and empty payloads).
- **Autopilot gate-decision canonical format** (`skills/autopilot/SKILL.md`): documented the explicit `[AUTOPILOT-POLICY] gate=<name> action=<allow|deny|skip> reason=<evaluated|not_reached|condition_unmet|dependency_skipped>` stdout shape, the matching `## Decisions Made` table-row shape, and a new `## Unreached Gates` section that enumerates canonical pipeline gates (`scout`, `plan`, `build`, `verify`, `retro`) which the run terminated before considering. The `## Unreached Gates` heading MUST NOT appear when every canonical gate was evaluated. Reason semantics: `evaluated` (gate was decided), `not_reached` (run terminated first), `condition_unmet` (preconditions not met), `dependency_skipped` (cascade from upstream `deny`).
- **tune-analyzer persistently-unreached-gate surfacing** (`agents/tune-analyzer.md`): documented the `tune-candidate-line` stdout regex `^candidate: gate=[a-z][a-z0-9_-]* reason=not_reached consecutive=[0-9]+$` and the `>= 3` consecutive-runs threshold for surfacing a gate as a tuning candidate by reading `## Decisions Made` rows and `## Unreached Gates` enumerations across a brief's run history.
- **Cat AD gate-logging contract test** (`tests/test-skill-contracts.sh`): emits literal stdout line `gate-logging: canonical` against a fixture autopilot-log containing at least one `decisions-table-row` for each of the four canonical reasons, and emits stderr `gate-logging: invalid line at <file>:<lineno>` when a `## Decisions Made` row carries a non-canonical reason. HTML-comment-scoped and fenced-block illustrative examples are guarded against false positives.
- **Test fixtures** under `tests/fixtures/`: `autopilot-log-canonical.md` (covers all four canonical reasons + documentation false-positive guards) and `autopilot-log-invalid-reason.md` (carries a `reason=unknown` row to drive the test-the-test scanner check).
- `/ship` Phase 1 step 5d: explicit post-move path-rewrite contract for the three reference surfaces that still embed the OLD source-path string after `mv` — `audit-round-*.md` files under the moved ticket directory, the brief-side `autopilot-state.yaml` (under the parent-slug's done directory), and the moved ticket's `autopilot-log.md`. The rewrite operates outside fenced code blocks and HTML comments and is scoped to the moved ticket only (cross-ticket references are left intact).
- `tests/helpers/check-ticket-move-drift.sh`: standalone scanner that detects residual OLD-path substrings on the three surfaces above. Strips fenced code blocks and HTML comments before scanning, scopes the search to one `<slug>/<ticket-id>` pair, and emits one `drift:` line per residual on stderr. Exits 0 when clean, 1 on drift.
- `tests/test-path-consistency.sh` Category 25 (post-/ship path-rewrite drift): twelve fixture-driven assertions invoking the scanner — clean fixture (AC 6), active-residual + product_backlog-residual (AC 7 + Edge Case 1), fenced-only / HTML-comment-only / cross-ticket / absent-audit / regex-in-fence carve-outs (Negative ACs 1-4 + Edge Case 3), idempotent re-move (Edge Case 2), `ticket_dir:` value-shape check (AC 4), and ship/SKILL.md contract-clause guards.
- **AC SSoT (Single Source of Truth) contract for `/plan2doc`**: `ticket.md` is now the canonical source for the `## Acceptance Criteria` list of any ticket. The generated `plan.md` MUST contain a `## Acceptance Criteria` section that is a verbatim copy of the ticket's AC list — equal item count, byte-identical bodies after stripping leading list markers (`- `, `* `, or `[0-9]+. `). List-marker style differences (numbered vs bullet) are NOT drift; sections outside `## Acceptance Criteria` are not compared. Documented in `skills/plan2doc/SKILL.md` under a new "AC Single Source of Truth (SSoT)" heading.
- **`ssot-line` Observable Contract**: every `/plan2doc` invocation emits exactly one stdout line matching `^plan2doc: ac-source=ticket\.md verbatim=true$`, declaring at runtime that the AC list was sourced verbatim from `ticket.md`. Documented in `skills/plan2doc/SKILL.md` under "Observable Contract: `ssot-line`" and emitted as the first line of Step 5.
- **`tests/helpers/ac-ssot-scan.sh`**: standalone scanner that walks every `plan.md`/`ticket.md` pair under `.simple-workflow/backlog/{active,product_backlog,done}/<slug>/<ticket-id>/` and verifies the SSoT invariant. Exits 0 with stdout `ac-ssot: synced` on full sync (including empty trees and empty-AC pairs); exits non-zero with a stderr line containing both file paths on count mismatch, body drift, or missing `## Acceptance Criteria` heading.
- **`tests/test-skill-contracts.sh` Cat AF**: new test category that runs the AC-SSoT scanner against the live brief tree and verifies that `skills/plan2doc/SKILL.md` documents the SSoT discipline, the `ssot-line` literal, and the byte-equality rule with the canonical marker set.
- `/ship` Audit Summary embedding contract: when a ticket is moved to `.simple-workflow/backlog/done/{ticket-dir}/` and the latest `audit-round-N.md` exists, `/ship` MUST embed the canonical line `Audit Summary: <Status> (Critical=<N>, Warnings=<N>, Suggestions=<N>)` into both the commit message body (visible via `git log -1 --format=%B HEAD`) AND the PR body (visible via `gh pr view --json body --jq .body`), and propagate every `### Warning: <title>` heading into the PR body so reviewers without access to gitignored `.simple-workflow/` artifacts see the audit verdict on GitHub. Latest-round selection uses **numeric** ordering of `N` (so `audit-round-10.md` beats `audit-round-2.md`, not lexicographic). The parser masks lines inside triple-backtick fenced code blocks and inside `<!-- ... -->` HTML comments before extracting fields. Backticks inside warning titles (e.g. `` `SECRET_TOKEN` ``) propagate verbatim. Documented in `skills/ship/SKILL.md` "Audit Summary embedding" section, referenced from Phase 1 step 3.e (commit body) and Phase 2 step 14 (PR body).
- `/ship` audit-summary error contracts: a missing `Status:` line in the latest `audit-round-N.md` causes /ship to exit non-zero with stderr containing `audit-summary: missing Status line in audit-round-`; a `Warnings:` count that disagrees with the number of `### Warning:` headings causes /ship to exit non-zero with stderr containing `audit-summary: count-mismatch (Warnings declared=<X>, headings=<Y>)`.
- `tests/helpers/audit-summary.sh`: pure-bash parser helper that mirrors the /ship Audit Summary embedding contract — given an `audit-round-N.md` path (or a `--dir <ticket-dir>` for numeric-latest selection), prints the canonical line to stdout, applies the fenced/HTML masking rules, and enforces the missing-Status / count-mismatch error contracts on stderr. Supports `--warning-titles` to dump every `### Warning:` heading verbatim. Mechanically verifies the contract from `tests/test-skill-contracts.sh` without requiring a real /ship invocation.
- `tests/fixtures/audit-rounds/`: eight fixture files exercising every Audit Summary AC and edge case (PASS, PASS_WITH_CONCERNS, FAIL, fenced-masked Status, HTML-comment-masked Status, missing Status, count mismatch, backtick-quoted warning title) plus a `multi-round-ticket/` subdirectory with `audit-round-1.md`, `-2.md`, `-10.md` to verify numeric-not-lexicographic ordering.
- `tests/test-skill-contracts.sh` Category 25 ("Audit Summary embedding contract"): static checks that `skills/ship/SKILL.md` documents every contract literal (canonical line shape, both stderr literals, no-audit fallback, numeric ordering, fenced/HTML masking, backtick preservation), runs the parser helper against every fixture, and emits the marker line `audit-summary: contract-declared` to stdout when the contract is in place.

### Changed
- `skills/audit/SKILL.md`: wired per-ticket Category propagation. `/audit` now reads the ticket's `| Category |` table row (first occurrence on multi-row tickets, with a `warn: multiple Category rows in ticket.md` stderr line; trailing whitespace stripped; missing row resolves to `unspecified`; unknown values like lowercase `accessibility` pass through verbatim with no rejection), selects the matching `## Category: <name>` body from `skills/audit/references/categories.md` for the canonical six, writes a `audit-dispatch.log` with `category=<value>` and `checklist_source=skills/audit/references/categories.md` keys before spawning agents, and propagates the selected checklist body to both `code-reviewer` and `security-scanner`. The aggregated `audit-round-{n}.md` report now transcribes evaluated checklist items as `- [ ] <item> (Category: <CategoryName>)` lines (or `- [x] ...`) outside fenced and HTML-comment regions when the Category matches one of the canonical six.
- `hooks/pre-write-safety.sh` now also scans `tool_input.content` for absolute home paths matching the POSIX regex `(/Users/[^/]+/|/home/[^/]+/)` and rejects with `pii: absolute home path detected` on stderr. Triple-backtick fenced code blocks are skipped, `.gitignore` is allowlisted, and the regex is case-sensitive (lowercase `/users/` and Windows-style `C:\Users\...` paths are out of scope). Empty content is a no-op.
- `hooks/pre-edit-safety.sh` mirrors the same scan against `tool_input.new_string`.

### Security
- Block contributors from accidentally writing absolute home paths (e.g. `/Users/<username>/...`, `/home/<username>/...`) into tracked files via the Write or Edit tools. Such paths leak the local username and directory layout when the file is later committed and pushed.

## [6.0.1] — 2026-04-26

### Added
- `CLAUDE.md` at the repository root, capturing two project-wide conventions for every Claude Code session that runs in this tree: (1) a Language policy stating that all Git / GitHub artifacts (commit messages, branch names, tag names and annotations, PR titles and bodies, PR review comments, Issue titles and bodies, Issue comments, Discussions posts, GitHub Release notes) and every tracked file (anything not matched by `.gitignore`) MUST be written in English; (2) a Release discipline section codifying SemVer with the `v` prefix, `plugin.json` ↔ CHANGELOG version alignment (CT-MODE-14), no `YYYY-MM-DD` placeholders (CT-MODE-13), Conventional-Commits-style `release(vX.Y.Z)[!]:` subject lines, mandatory annotated tags for new releases (lightweight tags do not propagate to forks and are ignored by `git describe`), GitHub Release creation for every released tag, and a Discussions-based migration-guide requirement for breaking changes. The file follows the official Claude Code memory guidance (target under 200 lines; this one is ~37) and uses bullet-dense, verifiable instructions per Anthropic best practices.

### Fixed
- `tests/test-skill-contracts.sh` CT-MODE-14 used a hard-coded `6.0.0` literal as the expected `plugin.json` version, so the assertion would have silently failed on any subsequent bump (it did, in fact, fail locally on this very release before being fixed). The check now reads the newest `## [X.Y.Z]` header from `CHANGELOG.md` dynamically and compares it against `plugin.json` `version`, keeping the guard correct across all future patch / minor / major bumps with no source-edit churn.

## [6.0.0] — 2026-04-26

### BREAKING CHANGES
- **`/brief` argument syntax**: `auto=true` has been removed. Use `mode=auto` (default) or `mode=manual`. Invocations with the old `auto=true` token now exit with an `ERROR:` message instead of being silently rewritten. Migration: replace every `auto=true` with `mode=auto`. Note that `mode=auto` is **not** strictly identical to the prior `auto=true` semantics — pre-v6.0.0 `auto=true` required an interactive yes/no confirmation before chaining, whereas v6.0.0 `mode=auto` chains unconditionally. Non-interactive callers (e.g. `claude -p`, CI) see equivalent end-to-end behavior; interactive callers who relied on the confirmation prompt must adjust their workflows.
- **`/brief` default behavior reversal**: bare `/brief <text>` now chains to `/create-ticket → /autopilot` (formerly: bare `/brief` produced artifacts and stopped). To preserve the old "produce artifacts and stop" behavior, pass `mode=manual` explicitly.

### Added
- **`/brief mode=manual`**: makes `/brief` a first-class entry point for the manual `/scout → /impl → /ship` flow. Manual-mode briefs:
  - skip the auto-chain handoff (no `auto-kick.yaml` is written)
  - propagate no `autopilot-policy.yaml` to ticket directories (so `/impl`'s FIFO auto-select picks them up)
  - still preserve the brief-level `autopilot-policy.yaml`, allowing a later opt-in to `/autopilot {slug}`
- `mode:` field added to `brief.md` frontmatter (`auto` or `manual`).

### Changed
- `/create-ticket brief=<path>` Step W-8 (autopilot-policy propagation) now runs only when the brief frontmatter resolves `mode: auto` (legacy briefs without `mode:` are treated as `auto` for backward compatibility). When `mode: manual`, propagation is skipped and a `[POLICY-PROPAGATION] skipped: brief mode=manual` audit-trace line is emitted.
- `/create-ticket brief=<path>` Phase 4 ticket-evaluator's `gates.ticket_quality_fail` brief-parent policy lookup is skipped when `mode: manual`.
- `/autopilot` error message updated: "run /brief with auto=true" → "run /brief with mode=auto".
- `/autopilot` emits `[WARN] brief mode=manual but /autopilot was invoked; per-ticket autopilot-policy.yaml is absent (only brief-level policy is in effect).` when invoked against a `mode: manual` brief — informational only; the run continues using the brief-level policy.

### Removed
- `auto=true` argument form for `/brief`.

## [5.0.0] — 2026-04-25

### ⚠ BREAKING CHANGE — Directory consolidation

The three top-level directories (`.docs/`, `.backlog/`, `.simple-wf-knowledge/`) are consolidated under a single `.simple-workflow/` root. Existing users must perform a one-time manual migration.

**Migration guide**: see [GitHub Discussions Announcement v5.0.0](https://github.com/aimsise/simple-workflow/discussions/40) for the full step-by-step instructions.

#### Path mapping

| Old | New |
|-----|-----|
| `.docs/` | `.simple-workflow/docs/` |
| `.backlog/` | `.simple-workflow/backlog/` |
| `.backlog/.ticket-counter` | `.simple-workflow/.ticket-counter` |
| `.simple-wf-knowledge/` | `.simple-workflow/kb/` |
| `.simple-wf-knowledge/.gitignore-setup-done` | `.simple-workflow/.setup-done` |

#### Why

- Reduced project-root pollution from 3 directories to 1
- `.gitignore` management collapses to a single line (`.simple-workflow/`)
- Uninstall is now `rm -rf .simple-workflow/`

#### What is NOT changed

- YAML schemas such as `phase-state.yaml` are unchanged
- Public contracts of skills, hooks, and agents (arguments, SW-CHECKPOINT format, etc.) are unchanged
- This release does NOT bundle an automated migration script (manual replacement)

#### Internal changes

- `hooks/session-start.sh` `.gitignore` upkeep collapses to a single entry
- `skills/impl/SKILL.md` `git stash` exclusion shrinks from 3 patterns to 1
- 10 of the 16 test files updated their fixture paths

## [4.2.0] - 2026-04-25

### Changed
- **License switched from MIT to Apache License 2.0**: starting with v4.2.0, simple-workflow is distributed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0). Apache-2.0 preserves every permission previously granted under MIT (free use, modification, redistribution, sublicensing) and adds: (1) an **explicit patent grant** from each contributor for any patents necessarily infringed by their contributions (Section 3); (2) a **defensive termination clause** that revokes the patent license if a user files patent litigation alleging that the Work infringes their patents; (3) explicit **trademark exclusion** (Section 6) — the license does not grant any rights to the project name or marks; (4) a clear **contribution-licensing rule** (Section 5) — submitted contributions are automatically under Apache-2.0 unless explicitly stated otherwise, removing the need for a separate Contributor License Agreement. Versions up to and including v4.1.0 remain available under MIT (existing users of those versions retain their MIT rights forever); only new versions starting from v4.2.0 are under Apache-2.0. A `NOTICE` file has been added at the repo root per Apache-2.0 convention to document the license history. README badge updated; `.claude-plugin/plugin.json` `license` field updated to `Apache-2.0` (SPDX identifier).

### Added
- `NOTICE` file at the repo root (Apache-2.0 convention) documenting the copyright owner and the v4.1.0 → v4.2.0 license transition.

## [4.1.0] - 2026-04-24

### Added
- **Gitignore auto-setup hook with setup flag** (`hooks/session-start.sh`): on first use of `/brief`, `/autopilot`, or any git-dependent skill, the `SessionStart` hook ensures the target project is ready — `git init -b main` (fallback to `git init` on git <2.28), initial commit when the repo has no HEAD, append `.docs/` / `.backlog/` / `.simple-wf-knowledge/` to `.gitignore` if any are missing, and commit the `.gitignore` update with `chore: add simple-workflow artifacts to .gitignore`. Idempotency is enforced by a marker file (`.simple-wf-knowledge/.gitignore-setup-done`): once present, the hook NEVER modifies `.gitignore` again, even if the user removes an entry manually. The marker is withheld if the chore commit fails (missing `git config user.email`/`user.name`, rejected pre-commit hook, etc.), so the hook self-heals on a subsequent session once the user resolves the underlying issue. Retry detection uses `git status --porcelain` so untracked `.gitignore` also triggers the commit path.
- **`Manual Bash Fallback Discipline` section in `/autopilot`**: codifies three invariants that `test_simple_workflow9`'s audit exposed. (1) Subagent response truncation / timeout is NEVER a Manual Bash Fallback — such cases MUST trigger the configured retry gate (`ac_eval_fail`, `evaluator_dry_run_fail`, etc.) and re-spawn the subagent, NOT be covered by orchestrator-run shadow execution. (2) Destructive operations (`rm -rf`, `rm -f .git/index`, `git reset --hard`, `git clean -f`, `git checkout .`, `git branch -D` of an active branch) are NOT error-recovery shortcuts — when a tool's error output names a non-destructive flag (e.g. `use -f to force removal`), apply that before considering destructive alternatives. (3) Every Manual Bash Fallback MUST be logged immediately to `autopilot-state.yaml` under a structured `manual_bash_fallbacks[]` list (`timestamp`, `command`, `reason`, `exit_code`, `destructive`) and replayed verbatim into `autopilot-log.md` at finalization. Silent drops are a contract violation. The structured list is the single source of truth; the pre-existing per-step `invocation_method == manual-bash` flag is a derived indicator.
- **`autopilot-state.yaml` retention**: at Split State File Cleanup, the state file is now **moved** to `.backlog/briefs/done/{parent-slug}/autopilot-state.yaml` instead of deleted. Combined with the new `manual_bash_fallbacks[]` log, this gives a permanent post-mortem trail.
- **AC Verification Method prohibition for `ac-evaluator`** (`agents/ac-evaluator.md`): forbids ad-hoc source writes to the project root or any source dir during AC evaluation (no `.tmp-*` / `tmp-*` / `scratch-*` / `verify-*` files, no heredoc-into-project-root `.ts`/`.js`/`.py` scratch scripts). Lists five acceptable verification methods in priority order: existing test suite, type/lint checker, Read tool, Grep tool, declared CLI entry points. Origin of the prohibition: `T-001` ac-evaluator in `test_simple_workflow9` used the `cat > .tmp-verify.ts << EOF ... && rm` pattern; the trailing `rm` was silently denied by the permission layer, leaving three `.tmp-verify*.ts` files in the working tree. Frontmatter tool allowlist is unchanged — enforcement is via prose.
- **`tests/test-session-start.sh`** (new, 7-case matrix): C1 fresh dir / C2 empty repo / C3 existing repo + no entries / C4 partial entries / C5 idempotency (second-run zero-commit + mtime stable) / C6 flag-respect / C7 commit-failure + recovery. Each case runs in a `mktemp -d` sandbox with host git config neutralised (`GIT_CONFIG_GLOBAL=/dev/null`, local `user.email`/`user.name`). 38 assertions total.

### Changed
- **`/ship` simplified to single-commit per ticket**: with `.backlog/` now fully gitignored via the setup hook, step 3.b no longer needs the `.backlog/briefs/` exclusion clause ("Autopilot mode → stage all modified/new files... except files under `.backlog/briefs/`"); the clause is removed. Stage selection trusts `.gitignore`. Phase 1 gains a `**Destructive shortcut prohibition**` directive: if a git command fails with an error that suggests a non-destructive remediation, apply the suggestion before reaching for `rm -f .git/index` / `git reset --hard` / `git clean -f`. Step 5 gains a `**Post-move commit policy**` clarification: the ticket lifecycle produces exactly ONE commit per ticket (the step-3 `feat:`/`fix:` commit); the `chore: move ticket artifacts to .backlog/done` follow-up commit is **retired** — the move happens on disk but is not committed because `.backlog/` is gitignored.
- **`README.md` setup documentation**: new `## Setup` section documents the `SessionStart` hook behaviour (git init, initial commit, `.gitignore` append, chore commit, marker file). `### Ticket counter is per-developer` (nested under Setup) documents that `.backlog/.ticket-counter` is per-developer by design and provides the surgical recipe to opt out for team-shared numbering.
- **`README.md` Table of Contents**: `#setup` anchor added.

### Fixed
- **`/ship` destructive `rm -f .git/index` path** (observed in `test_simple_workflow9`): when a pre-v4.1.0 fresh-repo `/autopilot` chain hit an AM-state `.backlog/briefs/active/{parent-slug}/autopilot-state.yaml` conflict in ship's unstage dance, the orchestrator resorted to `rm -f .git/index` as error recovery — ignoring git's explicit `use -f to force removal` hint. The Manual Bash Fallback Discipline section (new in `/autopilot`) and the Destructive shortcut prohibition (new in `/ship`) together forbid that class of shortcut and require the tool-suggested remediation.
- **`.tmp-verify*.ts` working-tree pollution** (observed in `test_simple_workflow9`): three ad-hoc tsx scratch scripts were left in the project root because the ac-evaluator subagent used `cat > .tmp-verify.ts << EOF ... && rm` and the trailing `rm` was denied by the permission gate. The ac-evaluator AC Verification Method section now forbids project-root scratch writes outright and documents a `$TMPDIR`-via-`finally` exception for genuinely temporary files.
- **`autopilot-log.md` "Manual Bash Fallbacks: none" misreporting**: the previous format emitted `none` purely from the absence of `invocation_method == manual-bash` flags, so a Manual Bash Fallback that the orchestrator forgot to flag would disappear from the log. The new format requires replaying `manual_bash_fallbacks[]` verbatim; `none` is valid **only** when that structured list is empty or absent.

## [4.0.0] - 2026-04-21

### Breaking Changes
- **`/brief` no longer writes `split-plan.md`**: Phase 5 (Split Analysis) has been removed from `/brief`. The skill now ends after writing `brief.md` and `autopilot-policy.yaml` (the new "Finalization" phase). Ticket decomposition moves exclusively to `/create-ticket` — either via the `planner` agent's Split Judgment in bare / `brief=<path>` modes, or via the `decomposer` agent in the new **findings mode** (`/create-ticket findings=<path>`). Briefs produced before v4.0.0 that still have a sibling `split-plan.md` are left untouched on disk (legacy artefact retention — see `.docs/fix_structure/spec-migration-policy.md`), and a fresh `/brief` invocation for a different slug does not remove them.
- **`brief.md` frontmatter slim**: the fields `split:` and `ticket_count:` are no longer emitted by `/brief` (they were coupled to Phase 5 and are now obsolete). A new scalar `interview_complete: {true|false}` is added to record whether the Phase 2 Socratic interview ran to at least one user response; `/create-ticket brief=<path>` consumes this flag to skip its own Socratic when set to `true`.
- **Uniform `parent_slug` nesting for tickets**: `/create-ticket` always writes to `.backlog/product_backlog/{parent-slug}/{NNN}-{slug}/` — even for N=1 bare-description tickets. The legacy bare `.backlog/product_backlog/{NNN}-{slug}/` layout is no longer produced. Existing legacy tickets on disk are preserved and remain readable by the depth-agnostic glob used in hooks / `/catchup` (Plan 3). Readers detect both layouts during the transition.
- **`ticket_dir:` top-level field removed from `phase-state.yaml`**: the file path itself encodes the ticket location, so the scalar is redundant. New writes omit it; legacy files that still carry it are ignored by readers (schema-slim, Plan 3).
- **`/autopilot` is a pure consumer of `split-plan.md`** (Plan 4): `/autopilot <parent-slug>` no longer invokes `/create-ticket` to materialize tickets. It reads `.backlog/product_backlog/{parent-slug}/split-plan.md` (produced by `/create-ticket`) as the single source of truth for the ticket set and drives `/scout → /impl → /ship` per ticket. Legacy `split-plan.md` at `.backlog/briefs/active/{parent-slug}/split-plan.md` is explicitly NOT read. If `split-plan.md` is missing but a brief exists, autopilot prints an actionable error telling the user to run `/create-ticket brief=<path>` first. The `autopilot-policy.yaml` byte-identical copy into each ticket directory is now the responsibility of `/create-ticket brief=<path>` (propagation moved upstream, Plan 1).

### Added
- **findings mode for `/create-ticket`**: new entrypoint `/create-ticket findings=<path>` consumes a structured findings document, invokes the `decomposer` agent to partition `## Required Work Units` into N tickets with a DAG of `depends_on` links, then runs per-ticket `planner` + `ticket-evaluator` passes with atomic all-or-nothing commit semantics. A dedicated `SIMPLE_WORKFLOW_DISABLE_DECOMPOSER=1` kill-switch exits non-zero before any filesystem mutation. The decomposer output schema + first-unblocked tiebreak rule are documented in `.docs/fix_structure/spec-split-plan-schema.md` and `.docs/fix_structure/spec-findings-fixture.md`. For N>1 runs, `/create-ticket` emits a dual-recommendation SW-CHECKPOINT (`next_recommended_auto: /autopilot <parent-slug>` + `next_recommended_manual: /scout <first-unblocked-ticket-dir>`); for N=1 it emits the classic single `next_recommended:` line.
- **Capped Socratic interview for both `/brief` and `/create-ticket`**: both skills enforce **at most 3 questions per round**, **at most 10 rounds**, and therefore **at most 30 questions total** before the terminal artifact (`brief.md` for `/brief`, `ticket.md` for `/create-ticket`) appears. Non-interactive environments (`claude -p` / closed stdin) still skip the interview via the `AskUserQuestion` fallback; `/create-ticket brief=<path>` with `interview_complete: true` in the brief frontmatter skips the Socratic entirely even with closed stdin (a ticket file appears within 10 seconds).
- **`/brief` dual-recommendation SW-CHECKPOINT**: on the success path, the final `## [SW-CHECKPOINT]` block carries both `next_recommended_auto: /autopilot <slug>` and `next_recommended_manual: /create-ticket brief=<path>`, letting the user choose to hand off to `/autopilot` or stage the decomposition manually via `/create-ticket`. On the failure path (any write failure or `auto=true` chained `/create-ticket` failure), both keys are emitted with empty-string values `""`.
- **`/brief ... auto=true` chained handoff**: after writing `brief.md` and `autopilot-policy.yaml`, if `auto=true` was passed AND the interactive confirmation returned `yes`, `/brief` chains `/create-ticket brief=<path>` followed by `/autopilot <parent-slug>`. If `/create-ticket` fails, stdout contains the literals `ERROR:` and `create-ticket failed`, and `/autopilot` is NOT invoked. Interactive `no` and the non-interactive default `no` both save the brief + policy without chaining.

### Changed
- **`/create-ticket` entrypoint parsing**: arguments are parsed into exactly one of three mutually exclusive modes — `findings=<path>` / `brief=<path>` / bare description. Passing both `brief=` and `findings=` prints `ERROR: brief= and findings= are mutually exclusive. Pass exactly one.` and exits non-zero before any counter read or directory creation.
- **Policy-copy propagation** (`autopilot-policy.yaml`): moved from `/autopilot` into `/create-ticket brief=<path>` using `cp -p` for byte-identical, timestamp-preserving copies into each newly-created ticket directory. Findings mode and bare-description mode do NOT emit `autopilot-policy.yaml` per ticket — the absence is an explicit signal to `/autopilot`'s downstream Policy guard that the ticket is "not autopilot-eligible" (see `spec-migration-policy.md`).
- **Depth-agnostic reader glob** (Plan 3): hooks, `/catchup`, and `phase-state.yaml` consumers use a glob that matches both the legacy flat `.backlog/active/{NNN}-{slug}/` and the new nested `.backlog/active/{parent-slug}/{NNN}-{slug}/` layouts without duplicates. Legacy tickets remain in place.

### Removed
- **`/brief` Phase 5 (Split Analysis)**: removed in its entirety. The `estimated_size` L / XL branch that used to produce `split-plan.md` and set `split: true` / `ticket_count: N` in brief frontmatter is gone; the same responsibility now lives in `/create-ticket` (planner Split Judgment in bare / brief modes, decomposer in findings mode). Anything a caller used to grep for about `Phase 5` in `/brief`'s skill prose has been renamed (e.g., "Phase 5 → Split Analysis" is now "Finalization" and ends at the SW-CHECKPOINT emission).
- **`split:` and `ticket_count:` frontmatter fields in `brief.md`**: no longer emitted by `/brief`; existing briefs with these fields are ignored by downstream consumers (schema-slim).
- **`ticket_dir:` top-level field in `phase-state.yaml`**: no longer emitted by `/create-ticket`; the file's path already encodes the ticket location.

### findings mode refactor — summary

This release consolidates the "findings mode" refactor across four plans:
- **Plan 1**: findings mode in `/create-ticket`, decomposer agent, uniform `parent_slug` nesting, policy-copy responsibility moved to `/create-ticket`.
- **Plan 2**: `/brief` Phase 5 removal, capped Socratic interview (3 per round / 10 rounds / 30 total) in both `/brief` and `/create-ticket`, `interview_complete` frontmatter scalar, dual-recommendation SW-CHECKPOINT in `/brief`, `auto=true` chain.
- **Plan 3**: depth-agnostic reader glob, `phase-state.yaml` schema slim (`ticket_dir:` dropped).
- **Plan 4**: `/autopilot` consumer-only mode — reads `.backlog/product_backlog/{parent-slug}/split-plan.md`, never `/create-ticket`.

The refactor surface area and migration policy (which legacy artefacts are preserved vs. no-op) are documented in `.docs/fix_structure/spec-migration-policy.md`.

## [3.8.0] - 2026-04-20

### Changed
- **Plugin-slim (Remedy 4 Phase A)**: Compressed the four heaviest contract-bearing SKILL files and consolidated the ac-evaluator Report Persistence Contract into the agent definition. Aggregate byte reduction across `skills/{impl,autopilot,create-ticket,ship}/SKILL.md` + `agents/ac-evaluator.md` is **-30,419 bytes (-22.9%)** against `main`: `impl` -28.8%, `autopilot` -30.4%, `ship` -20.7%, `create-ticket` -12.7% (net, after FU add-backs for Gate 1/2/3/4 content), `ac-evaluator` +21.9% (absorbed the persistence contract from impl/SKILL.md). Semantic content (MUST rules, Mandatory Skill Invocations tables, phase-state ownership) was preserved; only prose redundancy and duplicated examples were removed. Token-count helper `tests/helpers/count-tokens.sh` gained a tiktoken branch with a `chars/4` fallback so future compression audits can be measured consistently.
- **Contract hardening**: `agents/ac-evaluator.md` now carries the Report Persistence Contract (Output MUST be non-empty; write failures MUST return `Status: FAIL-CRITICAL` / `Output: ERROR-WRITE-FAILED`; callers MUST NOT re-invoke solely to persist). `skills/impl/SKILL.md` step 16 AC Gate rejects empty / `ERROR-`-prefixed Output as `FAIL-CRITICAL` before Status parsing, making the contract load-bearing at runtime rather than prose-only.
- **Test coverage**: `tests/test-skill-contracts.sh` grew to 289 assertions (from 267 on `main`), adding Cat V / W-1..W-6 / X / Y / Z / AA / AA-M / AB to guard Mandatory Skill Invocations targets, the Report Persistence Contract (positive and negative patterns including retry-permission / return-without-writing phrasings), HTML-comment-hidden RFC 2119 normative tokens (MUST/SHALL/REQUIRED/MANDATORY/PROHIBITED/FORBIDDEN/NEVER/Fail), and tiktoken/fallback numerical agreement on the token helper.

### Notes / Scope limits (Phase A)
- **Runtime cache_read delta is NOT yet measured**. The perf motivation is the main-session `cache_read` accounting observed in a prior heavy-session trace (`d87a5d22`), but this branch ships only the static byte reduction above; a before/after JSONL comparison on a comparable `/autopilot` run is queued as follow-up work (plan D-6). Do not infer a specific per-session token savings from the byte-reduction figures — per-turn consumption depends on invocation frequency and tool-result accumulation.
- **This is a compression-only pass**. The wrapper-architecture approach scoped in `.docs/cost-analysis/rate-limit-projection.md` (interposing a summarizer sub-agent to shrink tool-result payloads, projected ~30% main-session reduction) is NOT implemented here; tool-result accumulation remains untouched. Phase B will evaluate the wrapper direction separately.

## [3.7.0] - 2026-04-17

### Added
- Unified ticket-lifecycle state file `phase-state.yaml` (PR A): created once by `/create-ticket` at the moment a ticket directory is created, updated in place by each phase-owner skill (`/scout`, `/impl`, `/ship`), and **never deleted** — moved alongside the ticket to `.backlog/done/` as a permanent record. Replaces the legacy round-scoped `impl-state.yaml`, absorbing all intra-impl loop state (`current_round`, `phase_sub`, `last_ac_status`, `last_audit_status`, `last_audit_critical`, `next_action`, `feedback_files.*`) under `phases.impl.*`. Canonical schema, field enums, status transitions, and per-skill write-ownership rules are documented in `skills/create-ticket/references/phase-state-schema.md`.
- Legacy migration in `/impl` (PR A): on first run, a legacy `{ticket-dir}/impl-state.yaml` is converted to `phase-state.yaml` with every field mapped 1:1 (top-level `phase` becomes `phases.impl.phase_sub`; all others keep their names under `phases.impl.*`), then the legacy file is deleted only after the unified file is written successfully. A bootstrap path also generates a fresh `phase-state.yaml` when `/impl` is invoked on a plan-only ticket authored without `/create-ticket`.
- `[SW-CHECKPOINT]` convention (PR B): every phase-terminating skill (`/create-ticket`, `/scout`, `/plan2doc`, `/impl`, `/ship`) appends an English-only YAML-parseable `## [SW-CHECKPOINT]` block as the last section of its output, with fields `phase`, `ticket`, `artifacts`, `next_recommended`, and a literal `context_advice` line telling the user that `/clear` followed by `/catchup` is safe. `/audit` deliberately does NOT emit a CHECKPOINT to keep the `/impl` loop presentation intact. Autopilot ignores the block and continues to parse the pre-existing `## Result` / `## Summary` structured returns.
- `hooks/session-start.sh` now scans `.backlog/active/*/phase-state.yaml` and appends a compact per-ticket summary (`phase=… last_completed=… status=…`) to `additionalContext` along with a `Tip: run /catchup for full recovery.` line. YAML extraction uses `grep` + `sed` only (no `yq`), matching the pattern already in `pre-compact-save.sh`. Corrupt or unreadable files are skipped silently so that session start is never blocked. On a repository with no `phase-state.yaml` files, output is byte-identical to the prior hook (branch + changed-file count).
- `/catchup` Step 1-pre reads `phase-state.yaml` as the **primary** state source (before the compact-state / session-log sources). Step 4 adds Rule 0.5 which fires when a ticket has `overall_status: in-progress` and `last_completed_phase != ship`, mapping the completed phase to a recommended next command (`create_ticket → /scout`, `scout → /impl`, `impl → /ship`). When multiple tickets are in-progress, all are listed and the one with the most recent `started_at` is highlighted. Step 5 appends a `[SW-RESUME]` block (`Active: {dir} @ {phase}` / `Run: {command}`) mirroring the CHECKPOINT shape emitted by phase-terminating skills. The `researcher` agent is additionally skipped when `phase-state.yaml` was modified within the last hour.
- `skills/create-ticket/references/phase-state-schema.md` — canonical schema reference with field enums, status transitions, write-ownership table, reader table, legacy migration path, and the full legacy `impl-state.yaml → phase-state.yaml` rename table.

### Changed
- `/impl` Size → Generator-model routing is now configurable via `constraints.sonnet_size_threshold` in `{ticket-dir}/autopilot-policy.yaml`. Accepted values: `S`, `M`, `L`, `off`. The default — applied when the field or the policy file is absent — is `M`, preserving the prior shipped behavior (Size S and M use sonnet; L/XL/unknown use opus). Briefs that want to force every ticket to opus can set the threshold to `off`; briefs that want a sonnet-only mode for a scoped experiment can set it to `L`. The knob is documented in `skills/create-ticket/references/autopilot-policy-reference.md`.
- `README.md` — "Built-in Ticket Management" section now describes `phase-state.yaml` as the unified lifecycle file (with explicit "never deleted" statement) and links to `skills/create-ticket/references/phase-state-schema.md`. A one-line note about the `[SW-CHECKPOINT]` convention also added.
- `skills/create-ticket/references/workflow-patterns.md` — tool reference table now mentions `phase-state.yaml` as the unified per-ticket state file and notes that `[SW-CHECKPOINT]` blocks are emitted by phase-terminating skills.
- `skills/catchup/SKILL.md`: freshness check simplified to "if `phase_state_records` is non-empty, set `phase_state_fresh = true`" — dropping the prior mtime-based rule and the `Bash(stat:*)` / `shell(stat:*)` permissions it required. The dual-state precedence check (autopilot-state vs phase-state) likewise drops the mtime tiebreak in favor of a simpler location-based rule: prefer `autopilot-state.yaml` only when the ticket is under `.backlog/briefs/active/` (an autopilot-managed brief); otherwise prefer `phase-state.yaml`. YAML parsing itself remains `Read` + `Grep` only (AC 4.7).
- `/impl`: `plan.md` and `investigation.md` content is no longer held in the main session — the implementer agent receives paths and reads the files in its own isolated context, reducing main-session cache accumulation. Ticket Size extraction uses a bounded `Read(limit=30)` with a `limit=80` fallback.
- `/impl`: Evaluator prompts (Dry Run at §8 and the main AC gate at §15) now receive the plan path instead of the full plan content — each prompt carries an explicit read instruction so the ac-evaluator loads the plan in its own isolated context.
- `/impl`: Acceptance Criteria extraction in §5 uses a bounded `Grep -n "^### Acceptance Criteria"` to locate the header line `L`, followed by `Read(offset=L, limit=80)` to load only the AC section body, instead of a full-file `Read`.
- `/impl`: Main-session change-summary in step 14 is replaced with `git diff --shortstat` (single summary line) to stay consistent with `/catchup`'s `--shortstat` and avoid large per-file diffstats in main context; the ac-evaluator can still invoke `git diff --stat` independently via its `Bash(git diff:*)` permission if per-file detail is needed.
- `/catchup`: pre-computed `git log` bounded to 5 commits (was 20), to prevent long-history output from saturating the main session.
- `/catchup`: pre-computed diff uses `git diff --shortstat` (was unbounded `--stat`), emitting a single summary line instead of a per-file diffstat.

### Removed
- Legacy active-mechanism references to `impl-state.yaml` in skill bodies. Remaining mentions (in `/impl`'s one-shot migration step and in the legacy-rename table of `phase-state-schema.md`) are explicitly marked as legacy and kept to document the migration contract.
- `skills/catchup/SKILL.md`: `Bash(stat:*)` / `shell(stat:*)` from `allowed-tools` — no longer needed after the freshness-flag and dual-state precedence simplifications (see the corresponding `### Changed` entry above).

## [3.6.0] - 2026-04-17

### Reverted
- Wrapper agent nesting (Phase A-E, v3.5.0-v3.5.4) — removed due to permission mode not inherited by sub-agents (Claude Code platform limitation) and ticket-pipeline not completing in 1 dispatch (3-4 retries needed)
- Deleted 8 wrapper agents: `wrapped-researcher`, `wrapped-planner`, `wrapped-ticket-evaluator`, `wrapped-implementer`, `wrapped-ac-evaluator`, `wrapped-code-reviewer`, `wrapped-security-scanner`, `ticket-pipeline`
- 4 skills restored to bare agent names: `/audit` (security-scanner, code-reviewer), `/plan2doc` (planner), `/create-ticket` (researcher, planner, ticket-evaluator), `/impl` (implementer, ac-evaluator)
- `/autopilot` SKILL.md restored to pre-Phase-E structure: `Skill` in allowed-tools (not `Agent`), 4 individual skill entries in Mandatory Skill Invocations table (`/create-ticket`, `/scout`, `/impl`, `/ship`), per-step Skill tool calls with CHECKPOINT blocks restored to 8+

### Added (absorbed from wrapper architecture)
- Artifact Presence Gate in `/autopilot`: after each ticket's `/ship` step, verifies 7 artifact patterns exist (`ticket.md`, `investigation.md`, `plan.md`, `eval-round-*.md`, `audit-round-*.md`, `quality-round-*.md`, `security-scan-*.md`); FAIL-CRITICAL / all-rounds-FAIL exception skips audit/quality/security checks
- Skill Invocation Audit in `/autopilot`: tracks `invocation_method` per step (`skill` | `manual-bash` | `unknown`) in `autopilot-state.yaml`
- `completed-with-warnings` status in `autopilot-log.md` `final_status` enum — triggered when all tickets completed but at least one step used manual-bash fallback
- `## Warnings` section in `autopilot-log.md` listing manual-bash fallback steps

### Kept (Phase 0 measures, unrelated to wrapper)
- Phase 0a: auto-inject initial commit on empty repository
- Phase 0b: `/ship` pre-compute resilience for all initial git states
- Phase 0c: Mandatory Skill Invocations + MUST/NEVER/Fail enforcement language in all 7 orchestrator skills

### Changed
- Cat Q/R/S (wrapper agent contract tests) removed from `test-skill-contracts.sh`
- Cat O-5b (ticket-pipeline CHECKPOINT) removed from `test-skill-contracts.sh`
- Cat T adapted to T' (artifact presence gate targets `autopilot/SKILL.md` instead of `ticket-pipeline.md`)
- Cat U adapted to U' (skill invocation audit targets `autopilot/SKILL.md` instead of `ticket-pipeline.md`)
- Cat O-5 CHECKPOINT threshold restored from 2 to 8
- Cat M-4/M-5/M-6/M-7 Phase E phase-guards removed (autopilot checked directly again)
- Cat 6/7/10/11 agent counts reflect 9 original agents (not 17)
- Cat 22 Phase E phase-guards removed (autopilot checked directly again)

## [3.5.4] - 2026-04-17

### Changed
- Phase E wrapper wiring: `/autopilot` SKILL.md now dispatches `ticket-pipeline` agent via the Agent tool instead of calling `/create-ticket`, `/scout`, `/impl`, `/ship` individually via Skill tool — Phase 2 per-ticket execution (Single Ticket Flow steps 10-13 and Split Execution Flow steps 3a-3e) replaced with a single `ticket-pipeline` dispatch per ticket, reducing autopilot from ~445 lines to ~365 lines
- `/autopilot` allowed-tools: replaced `Skill` with `Agent` (Claude Code) and `skill` with `task` (Copilot CLI) to enable Agent tool dispatch of `ticket-pipeline`
- Mandatory Skill Invocations table: replaced 4 individual skill entries (`/create-ticket`, `/scout`, `/impl`, `/ship`) with single `ticket-pipeline` agent entry
- `autopilot-log.md` now includes a `## Warnings` section when any ticket returned `completed-with-warnings` or had non-empty `Manual Bash Fallbacks`
- `final_status` in autopilot-log.md now supports `completed-with-warnings` for tickets where skill invocation fell back to manual bash
- Cat O-5 CHECKPOINT threshold changed from 8 to 2 (per-ticket checkpoints moved to ticket-pipeline)
- Cat M-4/M-5/M-6/M-7 tests phase-guarded for Phase E: per-step policy guards and /impl plan paths now checked in ticket-pipeline.md instead of autopilot SKILL.md
- Cat P-8 CHECKPOINT threshold aligned with O-5 (8 → 2)
- Cat R-4, U-3, U-4 phase-guard tests auto-activate now that `ticket-pipeline` is referenced in autopilot SKILL.md

### Added
- Cat O-5b: ticket-pipeline.md CHECKPOINT count >= 4

## [3.5.3] - 2026-04-17

### Changed
- Phase D wrapper wiring: `/impl` SKILL.md now delegates to `wrapped-implementer` and `wrapped-ac-evaluator` instead of bare `implementer` and `ac-evaluator` agents — all Agent tool invocations in Step 13 (Generator), Step 15 (AC Evaluator), Phase 1 Step 8 (Evaluator Dry Run), the Mandatory Skill Invocations table, and Binding rules reference the wrapped versions
- Cat R phase-guard test R-2 (impl) auto-activates now that `wrapped-*` references are present in `impl/SKILL.md`

## [3.5.2] - 2026-04-17

### Changed
- Phase C wrapper wiring: `/create-ticket` SKILL.md now delegates to `wrapped-researcher`, `wrapped-planner`, and `wrapped-ticket-evaluator` instead of bare `researcher`, `planner`, and `ticket-evaluator` agents — all Agent tool invocations in Phase 1, Phase 3, Phase 4 (including retry loop re-spawns), the Mandatory Skill Invocations table, and Binding rules reference the wrapped versions
- Cat R phase-guard test R-1 (create-ticket) auto-activates now that `wrapped-*` references are present in `create-ticket/SKILL.md`

## [3.5.1] - 2026-04-17

### Changed
- Phase B wrapper wiring: `/audit` SKILL.md now delegates to `wrapped-security-scanner` and `wrapped-code-reviewer` instead of bare `security-scanner` and `code-reviewer` agents — all Agent tool invocations in Step 2 and the Mandatory Skill Invocations table reference the wrapped versions
- Phase B wrapper wiring: `/plan2doc` SKILL.md now delegates to `wrapped-planner` instead of bare `planner` agent — Step 4 Agent tool invocation, `subagent_type`, Mandatory Skill Invocations table, and Binding rules all reference the wrapped version
- Cat R phase-guard tests R-3 (audit) and R-5 (plan2doc) auto-activate now that `wrapped-*` references are present in the corresponding SKILL.md files

## [3.5.0] - 2026-04-15

### Added
- Phase A wrapper agent architecture — 8 new agents under `agents/` that provide isolated per-step contexts for Agent tool nesting (confirmed viable by the R1 verification report). This phase is **additive only**: no existing SKILL.md or agent file is modified, so all current flows keep their current behavior while the wrapper infrastructure becomes available for Phase B-E to wire up
  - `agents/wrapped-researcher.md` (sonnet) — wraps `researcher`; used by `/investigate`, `/scout`, `/create-ticket` Phase 1, `/brief` Phase 1 once Phase C lands
  - `agents/wrapped-planner.md` (opus) — wraps `planner`; used by `/plan2doc`, `/create-ticket` Phase 3, `/refactor` once Phase B/C land
  - `agents/wrapped-ticket-evaluator.md` (sonnet) — wraps `ticket-evaluator`; used by `/create-ticket` Phase 4 once Phase C lands
  - `agents/wrapped-implementer.md` (opus) — wraps `implementer`; used by `/impl` Generator step once Phase D lands
  - `agents/wrapped-ac-evaluator.md` (sonnet) — wraps `ac-evaluator`; used by `/impl` Evaluator + Dry Run once Phase D lands
  - `agents/wrapped-code-reviewer.md` (sonnet) — wraps `code-reviewer`; used by `/audit` Step 2 (parallel with security scanner) once Phase B lands
  - `agents/wrapped-security-scanner.md` (sonnet) — wraps `security-scanner`; used by `/audit` Step 2 (parallel with code reviewer) once Phase B lands
  - `agents/ticket-pipeline.md` (opus) — per-ticket pipeline orchestrator (`create-ticket → scout → impl → ship`) with Artifact Presence Gate (AC-4-B), Skill Invocation Audit (AC-4-C), and `completed-with-warnings` status (AC-4-D); used by `/autopilot` once Phase E lands
- All 8 wrapper agents declare a strict ≤200 token Return Format with `**Status**`, `**Output**`, and `**Next**` fields per AC-2; `ticket-pipeline` additionally exposes `**Ticket Dir**`, `**PR URL**`, `**Manual Bash Fallbacks**`, `**Failure Reason**` per AC-4-A
- `tests/test-skill-contracts.sh`: Cat Q (wrapper agent contract), Cat R (orchestrator wrapper references — phase-guarded and deferred until Phase B-E rewrites land), Cat S (state file separation — S-1 phase-guarded until Phase C), Cat T (Artifact Presence Gate contract), Cat U (Skill Invocation Audit contract — U-3/U-4 phase-guarded until Phase E)

### Notes
- Wrapper agents dispatch to their wrapped real agent by bare name (e.g., `subagent_type: "researcher"`), matching the existing convention. The naming-convention record lives at the top of `agents/wrapped-researcher.md`; if behavioral verification in Phase E-gate surfaces resolution issues, all wrappers can be revised globally in one follow-up commit (see `.docs/cost-analysis/agent-resolution-verification.md`)

## [3.4.0] - 2026-04-17

### Added
- `hooks/session-start.sh`: auto-inject initial commit on empty repository — detects an empty git repo (no `HEAD`) at session start and creates `Initial commit: project baseline` (staging `.gitignore` when present, otherwise `--allow-empty`), eliminating the `/ship` pre-compute shortcut that occurred when the pipeline ran against a freshly `git init`-ed project
- `tests/test-session-start.sh`: Phase 0a scenarios A-D covering empty repo with `.gitignore`, empty repo without `.gitignore`, idempotency on existing commits, and non-git directory no-op
- `/ship`: pre-compute resilience for all initial git states — every bash command in the `Pre-computed Context` block now uses a `2>/dev/null || echo "<fallback>"` pattern so that no-remote, no-commit, single-commit, detached-HEAD, and uncommitted-only repositories all resolve to a meaningful fallback marker instead of halting the skill. Added a new `Pre-compute Resilience Contract` section clarifying the agent's responsibility to interpret these markers rather than falling back to ad-hoc git commands
- `tests/test-ship-precompute.sh`: Phase 0b scenarios A-G verifying every pre-compute command exits 0 across no-remote, no-commits, single-`.gitignore`-commit, detached HEAD, uncommitted-only, remote-in-sync, and local-ahead-of-remote git states
- SKILL.md: mandatory invocation contract for orchestrator skills — added `## Mandatory Skill Invocations` section to 7 orchestrator skills (`/autopilot`, `/create-ticket`, `/scout`, `/impl`, `/audit`, `/ship`, `/plan2doc`) with a 3-column table (Invocation Target / When / Skip consequence) and explicit MUST/NEVER/Fail binding language. Hardens the linguistic binding force against JSONL-observed failure modes (Ticket 003 skill-invocation bypass L646-L687, Ticket 002 model self-AC-judgment L554-L559) where SKILL.md instructions were interpreted as recommendations rather than contractual requirements
- `tests/test-skill-contracts.sh`: Cat V "SKILL.md instruction strength verification" — V-1 asserts all 7 orchestrator skills have the Mandatory Skill Invocations section, V-2 asserts each has ≥ 3 MUST/NEVER/Fail strong-language markers, V-3 asserts the section includes a Skip-consequence column with real consequence language (detected/trigger/missing/etc.)

## [3.3.0] - 2026-04-15

### Added
- `hooks/autopilot-continue.sh` — Stop hook that prevents premature `end_turn` during `/autopilot` pipeline by returning `decision: "block"` when `autopilot-state.yaml` has unfinished steps
- Loop guard (environment variable + file-based counter) to prevent infinite continuation loops (threshold: 5 consecutive blocks)
- `tests/test-autopilot-continue.sh` — 15 unit tests covering all acceptance criteria (AC-1 through AC-12)

### Changed
- `hooks/hooks.json` — registered `autopilot-continue.sh` in the `Stop` hook section (before `session-stop-log.sh`)
- `/autopilot` SKILL.md — removed GitHub auth gate (step 4) and renumbered subsequent steps; removed `gh auth` pre-computed context block

## [3.2.2] - 2026-04-15

### Added
- `hooks/pre-level1-guard.sh` — PreToolUse hook that blocks `test-integration.sh` and `spike-claude-p.sh` from running without `RUN_LEVEL1_TESTS=true`, preventing accidental Anthropic API charges
- `.claude/settings.json` — registers the guard hook for the `Bash` tool
- `RUN_LEVEL1_TESTS` opt-in guard in `test-integration.sh` — skips integration tests unless explicitly enabled (works in both manual and automated runs)

### Fixed
- `/impl` SKILL.md: add RE-ANCHOR checkpoints after Generator (Step 14) and Evaluator (Step 16) to ensure Evaluator always runs in `claude -p` headless mode
- `/impl` SKILL.md: state management table clarified — `impl-state.yaml` is updated at the start of Step 14 (before `git diff --stat`) to minimize stale-state window

## [3.2.1] - 2026-04-15

### Fixed
- Remove unused `impl_success` variable in `test-integration.sh` (ShellCheck SC2034 warning caused CI failure)

## [3.2.0] - 2026-04-14

### Added
- Level 1 integration test suite (`tests/test-integration.sh`) — exercises real skill invocations via `claude -p` in headless mode:
  - `/ship` integration test: verifies ticket is moved to `.backlog/done/` and `autopilot-state.yaml` is not committed
  - `/audit` integration test: verifies `quality-round-1.md` and `security-scan-1.md` are written to the correct ticket directory
  - `/impl` integration test: verifies `eval-round-*.md`, `quality-round-*.md`, `audit-round-*.md`, and `security-scan-*.md` are produced (retry logic for non-determinism)
  - `/autopilot` integration test: full pipeline for a 2-ticket brief — verifies `investigation.md`, `plan.md`, and `eval-round-*.md` per ticket, brief moved to `briefs/done/`, `autopilot-log.md` written, state file cleaned up
- Behavioral tests for `session-start.sh` `.gitignore` auto-append in `tests/test-session-start.sh`: creation, idempotency, existing-entry preservation, non-git directory guard
- `tests/run-all.sh` automatically runs `test-integration.sh` last; auto-skipped when `claude` CLI is unavailable (CI-safe)

## [3.1.4] - 2026-04-14

### Added
- Session-start hook automatically ensures `.gitignore` contains entries for `.docs/`, `.backlog/`, `.simple-wf-knowledge/` — prevents pipeline artifacts from being committed to user projects
- Category 24 contract test for `/ship` staging exclusion

### Changed
- `/ship` Step 3b now explicitly excludes `.backlog/briefs/` files (e.g., `autopilot-state.yaml`, `brief.md`) from staging in autopilot mode — defense-in-depth for cases where `.gitignore` is missing

## [3.1.3] - 2026-04-14

### Added
- `ticket-dir=` argument for `/ship`, `/audit`, and `/refactor` — callers can now pass the ticket directory explicitly, eliminating dependency on branch-name matching (which fails on `main` branch)
- Artifact verification in `/autopilot` — post-scout checks for `investigation.md` and `plan.md`, post-impl checks for `eval-round-*.md`, `audit-round-*.md`, and `quality-round-*.md`, post-ship checks that ticket was moved to `done/`
- Category 22 contract tests for `ticket-dir=` propagation across skills

### Changed
- `/impl` Step 17 now passes `ticket-dir=` to `/audit` for reliable output path resolution
- `/autopilot` now passes `ticket-dir=` to `/ship` in both single and split execution flows
- Split Autopilot Log section strengthened: per-ticket `autopilot-log.md` is now a MUST requirement with explicit numbered steps

### Fixed
- Tickets not moved to `.backlog/done/` when autopilot commits directly on `main` branch
- Audit artifacts (`quality-round-*.md`, `security-scan-*.md`, `audit-round-*.md`) written to wrong location when branch name doesn't match ticket slug
- Autopilot reporting `completed` status when required artifacts are missing
- Individual `autopilot-log.md` not written to ticket directories in split mode

## [3.1.2] - 2026-04-14

### Fixed
- `/ship` now gracefully handles missing remote (no `origin` configured) — commits succeed, push/PR creation is skipped with a clear message instead of failing on pre-computed context shell errors

## [3.1.1] - 2026-04-14

### Changed
- Autopilot pipeline: replaced 8 passive `PIPELINE CONTINUATION REQUIRED` reminders with active `CHECKPOINT — RE-ANCHOR` blocks that force a Read of `autopilot-state.yaml` before continuing, preventing premature `end_turn` after deep skill nesting
- `/impl` round-level state tracking via `impl-state.yaml` — phase, next_action, and feedback_files are persisted at 4 points within each Generator-Evaluator-Audit round
- `/impl` active re-anchoring after `/audit`: CHECKPOINT — RE-ANCHOR block forces Read of `impl-state.yaml` and immediate execution of `next_action`
- `/impl` crash recovery: `impl_resume_mode` detects existing `impl-state.yaml` on startup and skips to the step corresponding to `next_action`
- `/impl` Phase 3 cleanup: `impl-state.yaml` is deleted on completion; `eval-round-*.md` and `quality-round-*.md` serve as permanent records

### Added
- Cat P contract tests — pipeline re-anchoring verification (P-1 through P-10)

## [3.1.0] - 2026-04-14

### Added
- Autopilot pipeline resilience: checkpoint reminders, state file management, and automatic resume
  - `autopilot-state.yaml` tracks per-ticket step progress (pending/in_progress/completed/failed) for crash recovery
  - 8 `PIPELINE CONTINUATION REQUIRED` reminders (4 Single + 4 Split) prevent premature `end_turn` after deep skill nesting
  - Automatic resume: re-running `/autopilot {slug}` detects interrupted state and continues from the last checkpoint
  - State file deleted on successful completion; `autopilot-log.md` remains as permanent record
  - 7-day stale state warning to prevent stale resume after codebase changes
- Cat O contract tests — autopilot resilience verification (O-1 through O-7)

### Fixed
- `/impl` pre-computed context shell commands now use `|| true` to prevent exit code 1 when only autopilot-managed tickets exist in `.backlog/active/`

## [3.0.0] - 2026-04-14

### Breaking Changes
- Removed `/ticket-move` skill — blocked-state moves now use manual `mv` commands
- Removed `/commit` skill — commit logic inlined into `/ship` Phase 1

### Changed
- `disable-model-invocation` changed from `true` to `false` on 8 skills (autopilot, create-ticket, scout, impl, ship, audit, plan2doc, tune) with "Do not auto-invoke" description guardrail replacing hard block, enabling skill-to-skill invocation via Skill tool
- Ticket completion in `/ship` moved from after-merge (Phase 3) to after-commit (Phase 1 Step 5) — tickets move to `.backlog/done/` earlier in the flow
- `/ship` Phase 1 now handles commit logic directly (previously delegated to `/commit` via Skill tool)
- `/ship` Phase 2 review gate and Phase 3 autopilot-policy reads now reference `.backlog/done/{ticket-dir}/` (ticket already moved in Step 5)
- `/autopilot` Phase 3 autopilot-log.md write path now uses filesystem check (`.backlog/done/` first, then `.backlog/active/`) instead of assuming ticket location
- `/impl` stash exclusion now skips `.backlog`, `.docs`, and `.simple-wf-knowledge` directories to preserve plugin artifacts

## [2.3.0] - 2026-04-13

### Added
- Bidirectional workflow isolation between manual `/impl` and `/autopilot` — `/impl` excludes `autopilot-policy.yaml` directories and uses FIFO (lowest ticket number) selection; `/autopilot` uses Policy guards and passes explicit plan paths to `/impl`
- Cat M contract tests — workflow isolation verification (M-1 through M-9, 13 assertions)

### Changed
- `/impl` pre-computed context: `ls -t` (newest timestamp) replaced with shell loop excluding autopilot-managed tickets
- `/impl` auto-selection logic: ascending sort order (FIFO) replaces newest-first, with explicit fallback message when all active tickets are autopilot-managed
- `/autopilot` single ticket flow (steps 10-12): added Policy guard before scout, impl, and ship steps
- `/autopilot` step 11: changed from no-argument `/impl` invocation to explicit `.backlog/active/{ticket-dir}/plan.md` path
- `/autopilot` split execution flow (steps c-e): added Policy guard and explicit `/impl` path

## [2.2.0] - 2026-04-13

### Added
- Autopilot `ticket_mapping` for split flow crash recovery
- `brief_slug`/`brief_part` traceability metadata in create-ticket

### Changed
- autopilot/tune-analyzer `{ticket-slug}` unified to `{ticket-dir}`
- Split-plan logical name annotation in brief

## [2.1.0] - 2026-04-12

### Added
- Sequential ticket numbering via `.backlog/.ticket-counter` — ticket directories now use `{NNN}-{slug}` format (3-digit zero-padded prefix)
- `/create-ticket` split support — tickets of Size >= M with independent AC groups can be split into up to 5 sub-tickets, each numbered sequentially

### Changed
- `{slug}` variable unified to `{ticket-dir}` across all skills and agents — `{ticket-dir}` represents the full directory name including the numeric prefix (e.g., `001-add-search-feature`)
- `/ticket-move` suffix-match fallback — when exact directory match fails, falls back to suffix matching on the slug portion
- Branch matching updated to NNN-prefix stripping — extracts the slug portion by removing the leading `NNN-` prefix, then checks if the branch name contains the slug

## [2.0.0] - 2026-04-12

### Added
- `/brief` skill — structured interview to generate brief documents and autopilot-policy.yaml for full automation
- `/autopilot` skill — execute the full pipeline (create-ticket → scout → impl → ship) from a brief document with zero human intervention
- Autopilot-policy.yaml mechanism — file-based autonomous decision making at all pipeline gates
- Auto-split feature — large scopes (L/XL) automatically split into multiple tickets with dependency-ordered execution
- Decision pattern learning — `/tune` extracts decision outcomes from autopilot logs into the knowledge base
- Human override learning — policy edits by users are tracked and fed back into the knowledge base
- Cat J contract tests — autopilot policy structural integrity verification (J-1 through J-19)
- Cat K contract tests — kb-suggested / kb_override contract verification (K-1 through K-7)
- Cat I extensions (I-16 through I-20) — decision pattern and tune-analyzer contract tests

### Changed
- `/create-ticket` — added `brief=<path>` parameter for brief injection, autopilot-policy gate check
- `/impl` — added autopilot-policy gate checks for evaluator dry-run failure and audit infrastructure failure
- `/ship` — added autopilot-policy gate checks for review gate and CI pending, added Read to allowed-tools
- `/tune` — added autopilot-log.md as analysis source, decision category support
- `tune-analyzer` agent — added decision pattern extraction, success/failure tracking, regression detection, human override learning

## [1.3.1] - 2026-04-12

### Fixed
- `session-stop-log.sh`: add pipefail fallback to `CHANGED_FILES` pipeline to prevent non-zero exit when `git status` fails

## [1.3.0] - 2026-04-12

### Added
- AC Evaluator multi-language support: JVM (Gradle/Maven/sbt), .NET, Ruby, Elixir, Swift, Flutter/Dart, and PHP test/lint runners added to `ac-evaluator` agent and `/refactor` skill
- `PASS-WITH-CAVEATS` status for AC Evaluator: transparently reports when automated test/lint verification was skipped due to unavailable runner
- Test Execution Fallback protocol: Makefile `make test`/`make lint` as universal fallback before degrading to static-analysis-only evaluation

### Changed
- `/impl` AC Gate (Step 15) now handles `PASS-WITH-CAVEATS` as PASS with caveats recorded in Phase 3 summary
- `test-path-consistency.sh` Category 10 KNOWN_TOKENS updated to include `PASS-WITH-CAVEATS`
- README Limitations section now documents supported test ecosystems and Makefile fallback

## [1.2.0] - 2026-04-11

### Added
- GitHub Copilot CLI tool name equivalents across all 20 skill and agent definition files for cross-platform compatibility
- GitHub Copilot CLI installation and usage instructions in README
- Consolidated Quick Start section for both Claude Code and Copilot CLI
- `/tune` skill: automatic evaluation log analysis and knowledge base management
- `tune-analyzer` agent: cross-ticket pattern extraction from evaluation logs
- Knowledge base infrastructure (`.simple-wf-knowledge/`) for cross-session learning
- `/ship` Step 18: automatic `/tune` invocation after ticket completion
- `/impl` Step 12h: knowledge base pattern injection into Generator prompts
- Test Category I: `/tune` knowledge base contract tests (20 assertions)

### Changed
- `/impl` Evaluator Tuning section updated to reference automated `/tune` workflow

## [1.1.0] - 2026-04-10

### Breaking Changes
- Removed `/create-pr` and `/create-pr-with-merge` skills. Use `/ship` (which includes commit + PR + optional merge) instead.
- Removed `/plan2doc-light` skill. `/plan2doc` now auto-selects the planner model (sonnet for S-size tickets, opus for M/L/XL).
- Removed `/ticket-active`, `/ticket-blocked`, `/ticket-done` skills. Use the unified `/ticket-move <slug> <state>` instead.
- Removed `/memorize` skill. Use Claude Code's native memory features.
- Removed `/review-diff` and `/security-scan` skills. Use the unified `/audit` skill instead. `/audit` always runs `security-scanner` and runs `code-reviewer` by default. Pass `only_security_scan=true` for security-only audits.
- Removed `/phase-clear` skill. Its phase detection, auto-detection, and guidance responsibilities have been folded into `/catchup`.
- Removed `planner-light` and `implementer-light` agents. The base `planner` and `implementer` agents now accept a dynamic model parameter.
- Removed `doc-writer` agent. Documentation tasks should use `/impl` with a doc-focused plan.

### Added
- New `/audit` skill that aggregates `code-reviewer` and `security-scanner` results into a single structured return block (`Status`, `Critical`, `Warnings`, `Suggestions`, `Reports`, `Summary`) parseable by callers.

### Changes
- `/ship` Phase 1 now delegates to `/commit` via the Skill tool (no logic duplication).
- `/impl` Evaluator Dry Run is now blocking on failure (asks user via AskUserQuestion) and runs only for L/XL tickets.
- `/impl` Step 16 now invokes `/audit` via the Skill tool instead of spawning `code-reviewer` directly. This eliminates code-reviewer duplication and brings security scanning into the `/impl` review loop.
- `hooks/session-stop-log.sh` now emits a YAML frontmatter so `/catchup` can recover state from session logs.
- `hooks/pre-compact-save.sh` now emits a YAML frontmatter (`date`, `branch`, `active_tickets`, `active_plans`, `latest_eval_round`, `latest_audit_round`, `last_round_outcome`, `in_progress_phase`) and computes an in-progress phase heuristic so `/catchup` can detect mid-loop interruptions. Reads `audit-round-{n}.md` (written by `/audit`, vocabulary `PASS / PASS_WITH_CONCERNS / FAIL`) instead of `quality-round-{n}.md` (code-reviewer's raw report, vocabulary `success / partial / failed`) so the Status contract is consistent end-to-end.
- `/audit` now writes its aggregated structured result to `{ticket-dir}/audit-round-{n}.md` when an active ticket is detected, in addition to printing the block. Consumed by `pre-compact-save` to compute `last_round_outcome`.
- `/catchup` Step 1 parses the compact-state YAML frontmatter, Step 4 adds a Rule 0 that recommends resuming `/impl` when `in_progress_phase == impl-loop`, and Step 5 surfaces the active tickets recorded at compact time. The YAML field name is now `latest_audit_round`.
- `/catchup` reads session logs as a fallback when no compact-state file is available.
- `/catchup` absorbs the former `/phase-clear` responsibilities (phase detection, auto-detection, guidance) so users have a single entry point for resuming work.
- `hooks/session-start.sh` simplified: plan detection and memory reading were removed since those responsibilities now live in `/catchup`. Now also gracefully falls back to a `(not a git repo)` context when invoked outside a git working tree, instead of exiting non-zero.
- `/ship` Review Gate now references `/audit` instead of `/review-diff`.

### Fixed
- **`/ship` no longer hardcodes `main`**: pre-computed context (`git diff origin/main --stat`, `git log origin/main..HEAD --oneline`) and the argument default now resolve the repository's default branch dynamically via `git symbolic-ref refs/remotes/origin/HEAD` (with `main` as fallback). Same `<default-branch>` placeholder pattern as `/catchup`. Previously, `/ship` would `fatal: ambiguous argument 'origin/main'` on `master` / `develop` repos before any argument parsing could override it.
- **`/audit` no longer silently downgrades partial-failure to PASS**: a single agent failure now returns `Status: FAIL` with `Critical = 1` (forcing a retry round); a complete failure (all spawned agents failed) deliberately omits the structured result block so the calling skill (`/impl`) detects "no block" and escalates via `AskUserQuestion`. The previous "treat counts as 0" behavior could mask Critical security findings.
- **`/impl` Step 16 audit-failure handling tightened**: silent `PASS_WITH_CONCERNS` fallback removed. On audit infrastructure failure, the user is asked via `AskUserQuestion` whether to STOP or treat as FAIL. "Never silently treat audit failure as PASS" is now an explicit invariant.
- **`/impl` non-interactive environment fallback**: both `AskUserQuestion` paths (Evaluator Dry Run failure for L/XL tickets and `/audit` infrastructure failure) now have an explicit fallback to `stop` with a message instructing the user to re-run in interactive mode. Prevents stalls in `claude -p` / CI automation.
- **`README.md` `pre-bash-safety` description corrected**: the hook is now documented as **best-effort** with explicit examples of commands it does NOT catch (`gh repo delete`, `aws s3 rm`, `kubectl delete`, `terraform destroy`, `sh -c`, `python -c`). Treat as guardrail, not security boundary.

### Fixed (v1.1.0 audit follow-up)
- **`pre-bash-safety.sh` regex hardened**: now detects `rm -Rf`/`rm -fR`/`rm --recursive --force` (uppercase and long-option variants), case-insensitive `drop table/database`, `find -delete`, and `find -exec bash/sh -c` (HIGH-3, HIGH-4, MED-8).
- **`pre-compact-save.sh` per-ticket processing**: round numbers, outcome, and phase are now computed per-ticket instead of a single global maximum. Fixes incorrect `last_round_outcome` when multiple tickets are active (HIGH-5).
- **`/audit` round synchronization**: accepts explicit `round=N` argument; `/impl` now passes its loop counter to keep `eval-round-{n}` and `quality-round-{n}`/`audit-round-{n}` aligned across retries (MED-7).
- **README corrected**: "minimum set of tool permissions" replaced with explicit per-role scope description; information firewall documented as asymmetric (HIGH-6, MED-9).
- **`catchup/SKILL.md` allowed-tools compliance**: grep/sed pipe example replaced with `Read`/`Grep` tool instructions matching the skill's allowed-tools (LOW-11).
- **`ac-evaluator.md` whitespace consistency**: `Bash(cmd :*)` entries unified to `Bash(cmd:*)` matching other agents (LOW-12).
- **CHANGELOG/plugin.json version sync**: Unreleased section released as 1.1.0; plugin.json version bumped to match (MED-10).

### Tests
- New `tests/test-path-consistency.sh` Categories 11-15: Bash(*) scope guard, /audit round=N contract, Bash permission whitespace consistency, catchup allowed-tools compliance, CHANGELOG/plugin.json version consistency.
- New `tests/test-pre-compact-save.sh` Test Group 5: multi-ticket per-ticket mapping with aggregate value verification.
- New `tests/test-pre-bash-safety.sh` tests for `rm -Rf`/`--recursive --force`, lowercase `drop table`, `find -delete`, `find -exec bash/sh -c`.
- New `tests/test-path-consistency.sh` Category 9 (Default-branch hardcode guard): grep guard preventing literal `origin/main` from reappearing in any `skills/*.md`. Same regression-prevention pattern can be reused for future "hardcode" classes.
- New `tests/test-path-consistency.sh` Category 10 (Agent Status contract): asserts every agent in `agents/` has a `**Status**:` line in its return format, catching contract drift between agent return formats and consumers.
- New `tests/test-path-consistency.sh` Categories 5-8 (Skill / Agent structural validity): YAML frontmatter validation, body section presence, agent reachability, and `bash -n` syntax check on inline `!`...`` interpolations.
- New `tests/test-pre-compact-save.sh` Tests 20-21 (Status vocabulary regression): verify that `pre-compact-save` correctly rejects `**Status**: success` (code-reviewer's vocabulary) when erroneously placed in `audit-round-{n}.md`, and that `quality-round-{n}.md` is no longer consulted by the hook.
- `tests/test-session-start.sh` Test 6 rewritten: previously asserted "expected non-zero exit outside git repo" (a documented bug) — now asserts graceful `exit 0` with `(not a git repo)` fallback context.

## [1.0.0] - 2026-04-06

### Added
- Complete development lifecycle: scout > investigate > plan > implement > ship
- 12 skills covering discovery, planning, implementation, quality, and delivery
- 8 specialized agents (implementer, planner, ac-evaluator, code-reviewer, researcher, test-writer, ticket-evaluator, security-scanner)
- Generator-Evaluator architecture for `/impl` with AC compliance verification
- Safety hooks: destructive command blocking, sensitive file protection
- Session lifecycle hooks with state preservation
- Backlog-based ticket management system
- Ticket quality evaluation with 5 quality gates
- Test suite for all hook scripts

[4.2.0]: https://github.com/aimsise/simple-workflow/releases/tag/v4.2.0
[4.1.0]: https://github.com/aimsise/simple-workflow/releases/tag/v4.1.0
[4.0.0]: https://github.com/aimsise/simple-workflow/releases/tag/v4.0.0
[3.8.0]: https://github.com/aimsise/simple-workflow/releases/tag/v3.8.0
[3.7.0]: https://github.com/aimsise/simple-workflow/releases/tag/v3.7.0
[3.6.0]: https://github.com/aimsise/simple-workflow/releases/tag/v3.6.0
[3.5.4]: https://github.com/aimsise/simple-workflow/releases/tag/v3.5.4
[3.5.3]: https://github.com/aimsise/simple-workflow/releases/tag/v3.5.3
[3.5.2]: https://github.com/aimsise/simple-workflow/releases/tag/v3.5.2
[3.5.1]: https://github.com/aimsise/simple-workflow/releases/tag/v3.5.1
[3.5.0]: https://github.com/aimsise/simple-workflow/releases/tag/v3.5.0
[3.4.0]: https://github.com/aimsise/simple-workflow/releases/tag/v3.4.0
[3.3.0]: https://github.com/aimsise/simple-workflow/releases/tag/v3.3.0
[3.2.2]: https://github.com/aimsise/simple-workflow/releases/tag/v3.2.2
[3.2.1]: https://github.com/aimsise/simple-workflow/releases/tag/v3.2.1
[3.2.0]: https://github.com/aimsise/simple-workflow/releases/tag/v3.2.0
[3.1.4]: https://github.com/aimsise/simple-workflow/releases/tag/v3.1.4
[3.1.3]: https://github.com/aimsise/simple-workflow/releases/tag/v3.1.3
[3.1.2]: https://github.com/aimsise/simple-workflow/releases/tag/v3.1.2
[3.1.1]: https://github.com/aimsise/simple-workflow/releases/tag/v3.1.1
[3.1.0]: https://github.com/aimsise/simple-workflow/releases/tag/v3.1.0
[3.0.0]: https://github.com/aimsise/simple-workflow/releases/tag/v3.0.0
[2.3.0]: https://github.com/aimsise/simple-workflow/releases/tag/v2.3.0
[2.2.0]: https://github.com/aimsise/simple-workflow/releases/tag/v2.2.0
[2.1.0]: https://github.com/aimsise/simple-workflow/releases/tag/v2.1.0
[2.0.0]: https://github.com/aimsise/simple-workflow/releases/tag/v2.0.0
[1.3.1]: https://github.com/aimsise/simple-workflow/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/aimsise/simple-workflow/releases/tag/v1.3.0
[1.2.0]: https://github.com/aimsise/simple-workflow/releases/tag/v1.2.0
[1.1.0]: https://github.com/aimsise/simple-workflow/releases/tag/v1.1.0
[1.0.0]: https://github.com/aimsise/simple-workflow/releases/tag/v1.0.0
