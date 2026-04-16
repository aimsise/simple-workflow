# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- `tests/test-skill-contracts.sh`: Cat V "SKILL.md 指示強度検証" — V-1 asserts all 7 orchestrator skills have the Mandatory Skill Invocations section, V-2 asserts each has ≥ 3 MUST/NEVER/Fail strong-language markers, V-3 asserts the section includes a Skip-consequence column with real consequence language (detected/trigger/missing/etc.)

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
