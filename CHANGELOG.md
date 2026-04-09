# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Breaking Changes
- Removed `/create-pr` and `/create-pr-with-merge` skills. Use `/ship` (which includes commit + PR + optional merge) instead.
- Removed `/plan2doc-light` skill. `/plan2doc` now auto-selects the planner model (sonnet for S-size tickets, opus for M/L/XL).
- Removed `/ticket-active`, `/ticket-blocked`, `/ticket-done` skills. Use the unified `/ticket-move <slug> <state>` instead.
- Removed `/memorize` skill. Use Claude Code's native memory features.
- Removed `/review-diff` and `/security-scan` skills. Use the unified `/audit` skill instead. `/audit` always runs `security-scanner` and runs `code-reviewer` by default. Pass `only_security_scan=true` for security-only audits.
- Removed `planner-light` and `implementer-light` agents. The base `planner` and `implementer` agents now accept a dynamic model parameter.
- Removed `doc-writer` agent. Documentation tasks should use `/impl` with a doc-focused plan.

### Added
- New `/audit` skill that aggregates `code-reviewer` and `security-scanner` results into a single structured return block (`Status`, `Critical`, `Warnings`, `Suggestions`, `Reports`, `Summary`) parseable by callers.

### Changes
- `/ship` Phase 1 now delegates to `/commit` via the Skill tool (no logic duplication).
- `/impl` Evaluator Dry Run is now blocking on failure (asks user via AskUserQuestion) and runs only for L/XL tickets.
- `/impl` Step 16 now invokes `/audit` via the Skill tool instead of spawning `code-reviewer` directly. This eliminates code-reviewer duplication and brings security scanning into the `/impl` review loop.
- `hooks/session-stop-log.sh` now emits a YAML frontmatter so `/catchup` can recover state from session logs.
- `/catchup` reads session logs as a fallback when no compact-state file is available.
- `/ship` Review Gate now references `/audit` instead of `/review-diff`.

## [1.0.0] - 2026-04-06

### Added
- Complete development lifecycle: scout > investigate > plan > implement > ship
- 20 skills covering discovery, planning, implementation, quality, and delivery
- 11 specialized agents (implementer, planner, evaluator, reviewer, researcher, etc.)
- Generator-Evaluator architecture for `/impl` with AC compliance verification
- Safety hooks: destructive command blocking, sensitive file protection
- Session lifecycle hooks with state preservation
- Backlog-based ticket management system
- Ticket quality evaluation with 5 quality gates
- Test suite for all hook scripts

[1.0.0]: https://github.com/aimsise/simple-workflow/releases/tag/v1.0.0
