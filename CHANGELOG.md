# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

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

[2.2.0]: https://github.com/aimsise/simple-workflow/releases/tag/v2.2.0
[2.1.0]: https://github.com/aimsise/simple-workflow/releases/tag/v2.1.0
[2.0.0]: https://github.com/aimsise/simple-workflow/releases/tag/v2.0.0
[1.3.1]: https://github.com/aimsise/simple-workflow/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/aimsise/simple-workflow/releases/tag/v1.3.0
[1.2.0]: https://github.com/aimsise/simple-workflow/releases/tag/v1.2.0
[1.1.0]: https://github.com/aimsise/simple-workflow/releases/tag/v1.1.0
[1.0.0]: https://github.com/aimsise/simple-workflow/releases/tag/v1.0.0
