# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
