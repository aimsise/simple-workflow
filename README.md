# simple-workflow

[![CI](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/aimsise/simple-workflow)](https://github.com/aimsise/simple-workflow/releases)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) / [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) plugin for a complete development lifecycle with built-in ticket management. Conserves context by delegating to sub-agents, and guarantees quality through a Generator-Evaluator pipeline.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI or [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) installed and authenticated
- [GitHub CLI](https://cli.github.com/) (`gh`) — required for `/ship`
- `git` and `jq`

simple-workflow runs entirely against your local filesystem and your existing GitHub remote — no external services, no database, no separate auth.

## Quick Start

```bash
# Install the plugin
claude plugin install aimsise/simple-workflow   # Claude Code
copilot plugin install aimsise/simple-workflow   # GitHub Copilot CLI
```

## Three Ways to Run

`/brief` is the single entry point for both fully automated and manual flows. The `mode=auto|manual` argument selects the behavior; `mode=auto` is the default when omitted.

| Mode | Entry | Best for |
|------|-------|----------|
| Full automation | `/brief <idea>` (or `/brief <idea> mode=auto`) | Idea -> PR with no intervention |
| Brief-assisted manual | `/brief <idea> mode=manual` | Structured kickoff, then drive each step |
| Pure manual | `/investigate` -> `/create-ticket` -> `/scout` -> `/impl` -> `/ship` | Existing tickets, full control |

**Full automation.** `/brief` investigates the codebase, runs a structured interview, and generates a brief plus an `autopilot-policy.yaml` that encodes autonomous decision rules. It then chains into `/create-ticket` -> `/autopilot`, which executes the full pipeline (`create-ticket -> scout -> impl -> ship`) with zero intervention. Large scopes are auto-split into multiple tickets and executed in dependency order. An Artifact Presence Gate validates expected artifacts at every step, and a Skill Invocation Audit flags any step that fell back to manual bash dispatch as `completed-with-warnings`.

**Brief-assisted manual.** `mode=manual` produces the same brief + `autopilot-policy.yaml` artifacts but **stops** there: no chained `/create-ticket`, no `/autopilot`. Use the brief as the structured starting point for the standard manual flow (`/create-ticket brief=... -> /scout -> /impl -> /ship`). Tickets created from a `mode=manual` brief carry no per-ticket `autopilot-policy.yaml`, so `/impl`'s FIFO auto-select picks them up correctly. The brief-level policy is preserved on disk under `.simple-workflow/backlog/briefs/active/{slug}/` as a rescue path — running `/autopilot {slug}` later opts the brief back into autopilot.

**Pure manual.** Drive each phase yourself with `/investigate`, `/create-ticket`, `/scout`, `/impl`, and `/ship`. This is the right path when you already have tickets in `.simple-workflow/backlog/product_backlog/`, when you want to inspect intermediate artifacts at every step, or when you are exploring a new codebase and want full control over scope and direction. Workflow isolation is bidirectional: `/autopilot` only processes tickets it created from a brief and does not pick up existing product-backlog tickets, and manual `/impl` excludes autopilot-managed tickets (those containing `autopilot-policy.yaml`) and selects the lowest-numbered non-autopilot ticket first (FIFO).

The autopilot-policy evolves over time — `/tune` extracts decision patterns from execution logs, and future `/brief` runs use these patterns to suggest more accurate defaults.

## How it Works

Canonical pipeline — one ticket from idea to PR:

```
[idea]
  │
  ▼
/brief                                                      (entry point)
  ├─ researcher        codebase investigation
  ├─ planner           brief drafting
  └─ decomposer        large-scope ticket split
  │   produces: brief.md, autopilot-policy.yaml
  ▼
/create-ticket                  🔁 retry until 5 quality gates pass
  ├─ researcher        Phase 1: scope investigation
  ├─ planner           Phase 3: ticket drafting
  ├─ decomposer        large-scope split
  └─ ticket-evaluator  Phase 4: quality gate (loop driver)
  │   produces: ticket.md
  ▼
/scout                          (chains two skills sequentially)
  ├─ /investigate  →  researcher
  └─ /plan2doc     →  planner
  │   produces: investigation.md, plan.md
  ▼
/impl                           🔁 max 3 rounds; FAIL → implementer
  ├─ implementer       Generator (writes code)
  ├─ ac-evaluator      acceptance-criteria verifier (loop driver)
  └─ /audit (chained):
       ├─ code-reviewer       quality review
       └─ security-scanner    security audit       (loop driver)
  │   produces: eval-round-N.md, quality-round-N.md, security-scan-N.md
  ▼
/ship                           (no sub-agents)
  │   commits, opens PR, moves ticket → done/, chains /tune
  ▼
[PR opened]
  │
  ▼  (post-completion, automatic)
/tune
  └─ tune-analyzer     pattern extraction → .simple-workflow/kb/
                       injected into next /impl's implementer prompt
```

Reading guide:

- `├─` / `└─`: sub-agents that the skill dispatches
- `🔁`: an internal verification loop, with the loop driver named on the right
- `/X (chained):`: the skill calls another skill (its sub-agents listed below it)
- `produces:`: artifacts written to the ticket directory

Out-of-pipeline skills:

```
/investigate  →  researcher                  (research-only, standalone)
/plan2doc     →  planner                     (planning-only, given a ticket)
/test         →  test-writer                 (test design + execution)
/refactor     →  planner, code-reviewer      (refactoring with backup branch)
/catchup      →  researcher                  (state recovery after /clear)
/autopilot    →  drives the canonical pipeline end-to-end from a brief
```

## Why simple-workflow?

simple-workflow stands on three pillars:

- **Generator-Evaluator firewall**: code authors and code judges run in separate contexts with an asymmetric information firewall, so quality is enforced by structure rather than by prompt instructions
- **Context Conservation**: the context window is treated as a consumable resource — sub-agents return < 500-token summaries, artifacts live on disk, and state survives compaction
- **Cross-session learning**: `/tune` distills evaluation logs into `.simple-workflow/kb/` patterns that future `/impl` runs inject into the Generator's prompt, so the system gets better at your project the more tickets it completes

These pillars exist because Claude Code is powerful, but its context window is finite — and fragile. Long-running agent sessions face four structural threats:

| Threat | What happens | Structural countermeasure |
|--------|-------------|--------------------------|
| **Loss** | Session boundaries — compaction, exit — discard accumulated understanding | Pre-compact hooks, `/catchup` recovery, `/tune` cross-session learning |
| **Exhaustion** | The window fills up, degrading instruction-following and response quality | Bounded sub-agent returns (< 500 tokens), phase-aware context release |
| **Contamination** | Biasing information leaks into contexts where it distorts judgment | Information firewall + ticket directory confinement (see [Harness Engineering](#harness-engineering)) |
| **Bloat** | Unbounded intermediate output crowds out critical instructions | Artifacts written to files, structured summaries returned to orchestrator |

simple-workflow addresses each threat with architectural constraints that hold regardless of model behavior — not prompt-level instructions that the model might rationalize away. The four sections below describe each pillar: **Context Conservation Protocol** (Loss + Exhaustion), **Harness Engineering** (Contamination + Bloat), the **Knowledge Base** (Loss across sessions), and **Ticket Management** (Contamination across tickets).

### Context Conservation Protocol

Treats the context window as a consumable resource and systematically conserves it.

- **Bounded sub-agent returns**: Each sub-agent launches with a fresh context, writes detailed artifacts to files, and returns only a structured summary (< 500 tokens). Without this bound, multi-round orchestration would accumulate unbounded output and degrade the orchestrator's decision quality
- **Phase-aware context release**: `/catchup` auto-detects your current phase (investigate -> plan -> implement -> test -> review -> commit) and recommends the next action. Completed phases live on disk — clear the context and move on
- **Structured state preservation**: Before context compaction, a hook saves per-ticket state as YAML frontmatter. `/catchup` parses this to resume interrupted work — including mid-`/impl` loops

### Harness Engineering

A **Generator** writes code, independent **Evaluators** verify it, and failures trigger automatic retry with specific feedback — up to 3 rounds. The information firewall is asymmetric: Evaluators never see the Generator's self-assessment and judge solely from `git diff` and test results, while the Generator does receive Evaluator feedback on retry.

Even though both sides run the same model, **weights × context = output** — by excluding the Generator's trial-and-error history from the Evaluator's context, sunk-cost bias is structurally eliminated rather than merely discouraged by prompt. Orchestrator skills enforce sub-agent dispatch via the `Skill` tool with MUST/NEVER/Fail language, making proper context isolation a structural contract rather than a suggestion. FAIL-CRITICAL violations halt execution immediately, and after ticket completion evaluation logs feed into the Knowledge Base, closing a cross-session feedback loop.

### Knowledge Base (Cross-Session Learning)

`.simple-workflow/kb/` is an automatically maintained knowledge base. `/tune` analyzes completed ticket evaluations (eval-round, audit-round files) via the `tune-analyzer` agent, extracts actionable patterns (common failures, recurring feedback themes), and persists them as structured entries; at implementation time, `/impl` injects relevant entries into the Generator's dispatch prompt, so lessons learned from past tickets inform future ones.

The more tickets you complete in a project, the more project-specific patterns accumulate, and the higher the probability that future implementations pass evaluation on the first round. In effect the system develops project-specific expertise over time — analogous to a human developer becoming more effective the longer they work on a codebase — without fine-tuning the underlying model.

### Ticket Management (State Machine)

`.simple-workflow/backlog/` is a state machine. Tickets transition between states via physical directory moves (`product_backlog/` -> `active/` -> `blocked/` -> `done/`), making state visible, traceable, and greppable — no database required. Each ticket is a directory where every artifact (`ticket.md`, `investigation.md`, `plan.md`, `eval-round-N.md`, `quality-round-N.md`) accumulates, providing both an audit trail and contamination prevention: artifacts from one ticket never leak into another's context.

Every ticket carries a `phase-state.yaml` file declaring its full lifecycle state (`create_ticket -> scout -> impl -> ship -> done`). It is written by `/create-ticket`, updated by each phase-owner skill, never deleted, and read by the `SessionStart` hook and `/catchup` to recover active-ticket context in one step. The canonical schema and per-skill write-ownership rules — including how `/catchup` reconciles `phase-state.yaml` with `/autopilot`'s separate `autopilot-state.yaml` — live in [`skills/create-ticket/references/phase-state-schema.md`](skills/create-ticket/references/phase-state-schema.md). Phase-terminating skills close their output with a standardized `[SW-CHECKPOINT]` block, signalling that running `/clear` is safe.

> **Manual transitions**: moving tickets between states (e.g. `active/` -> `blocked/`) is done with a plain `mv` — see the schema reference for the canonical commands.

## Building Blocks

simple-workflow is composed of three component types: **Skills** (slash commands), **Sub-agents** (specialists with isolated contexts), and **Hooks** (automatic safety guardrails).

**Skills** come in two flavors. *Orchestrators* coordinate sub-agents to drive a workflow (`/impl`, `/ship`, `/create-ticket`, `/brief`, `/autopilot`). *Delegators* hand off work to a single sub-agent (`/investigate`, `/plan2doc`, `/test`).

**Sub-agents** run in isolated contexts with role-appropriate tool permissions. Generator agents (`implementer`, `test-writer`) get broad `Bash(*)` access; Evaluator agents (`ac-evaluator`, `code-reviewer`, `security-scanner`, `ticket-evaluator`) are restricted to read-only file utilities plus specific test/lint runners; Research/planning agents (`researcher`, `planner`) get read-only git and filesystem tools. This asymmetry is deliberate — the Generator-Evaluator separation relies on evaluators being unable to execute destructive commands even if prompted to do so.

| Role | Agent | Model |
|------|-------|-------|
| Research | researcher | Sonnet |
| Planning | planner | Opus / Sonnet |
| Implementation | implementer | Opus / Sonnet |
| Acceptance evaluation | ac-evaluator | Sonnet |
| Quality review | code-reviewer | Sonnet |
| Testing | test-writer | Sonnet |
| Ticket evaluation | ticket-evaluator | Sonnet |
| Security audit | security-scanner | Sonnet |
| Pattern analysis | tune-analyzer | Sonnet |

Models are auto-selected based on ticket size (S/M/L/XL): `planner` uses Sonnet for S and Opus for M/L/XL, `implementer` uses Sonnet for S/M and Opus for L/XL. Both agents accept a dynamic model parameter — orchestrator skills pass the appropriate model at invocation time.

Inside `/impl`, the Generator-Evaluator loop runs up to three rounds. Each round (1) the **implementer** writes code with a test-first approach, (2) **ac-evaluator** independently verifies acceptance criteria from `git diff` and test output, and (3) on AC pass, `/audit` runs `security-scanner` and `code-reviewer` in parallel and aggregates a `Status / Critical / Warnings / Suggestions` block. Round artifacts are persisted as `eval-round-{n}.md`, `quality-round-{n}.md`, and `security-scan-{n}.md` under the ticket directory, providing a complete evaluation history that `/tune` later mines for cross-session patterns.

**Hooks** fire automatically on tool execution: `pre-bash-safety` (best-effort blocking of common destructive commands — *not* a security boundary), `pre-write-safety` / `pre-edit-safety` (block writes to `.env`, private keys, credentials), `session-start` (initialize session, auto-append `.gitignore` entries), `pre-compact-save` (snapshot state before compaction), `session-stop-log` (work log on session end), `autopilot-continue` (block premature `end_turn` during `/autopilot`), and `pre-level1-guard` (block expensive integration tests without `RUN_LEVEL1_TESTS=true`).

## Skill Reference

| Phase | Skill | Description |
|-------|-------|-------------|
| Discovery | `/investigate` | Deep-dive codebase exploration |
| Discovery | `/catchup` | Recover context from compact-state / session-log, detect current phase, and recommend next action (including resuming an in-progress `/impl` loop) |
| Discovery | `/brief` | Structured interview to generate brief + autopilot-policy. Investigates codebase and conducts Q&A to gather requirements |
| Planning | `/scout` | Chain investigation + planning in one step |
| Planning | `/plan2doc` | Create a detailed implementation plan (auto-selects model by ticket size) |
| Tickets | `/create-ticket` | Create a structured ticket with quality evaluation |
| Implementation | `/impl` | Implement via Generator-Evaluator pipeline |
| Implementation | `/refactor` | Safe refactoring with backup branch |
| Testing | `/test` | Design and run tests |
| Quality | `/audit` | Multi-agent code quality + security audit (use `only_security_scan=true` for security-only) |
| Quality | `/tune` | Analyze evaluation logs and maintain project knowledge base |
| Delivery | `/ship` | Commit + PR in one step (optionally merge) |
| Full Pipeline | `/autopilot` | Execute the full pipeline (create-ticket -> scout -> impl -> ship) from a brief document with zero human intervention. Auto-splits large scopes |

### `/ship` summary

`/ship` runs through up to three phases: **commit** (Conventional Commits formatted), **PR** (push + `gh pr create`), and an optional **squash-merge** with `merge=true` (deletes the branch and syncs local). If no prior `/audit` is detected, a review gate recommends running one first. Pre-computed context (branch name, diff stats, commit log) uses a resilience contract so `/ship` never fails on unexpected git state — missing remotes, empty diffs, or detached HEAD are all handled gracefully. After a successful commit, the ticket is moved to `.simple-workflow/backlog/done/` and `/tune` is invoked to extract reusable patterns from the ticket's evaluation logs into the project knowledge base.

> **Interactive-mode caveats**: `/impl` requires interactive mode for L/XL Evaluator Dry Run failure recovery and `/audit` infrastructure failure paths — in `claude -p` or CI, these stop with an explanatory message rather than hang. `/create-ticket`'s Phase 2 Socratic Refinement is skipped in non-interactive mode, and Phase 4 quality FAIL escalation stops with the ticket saved on disk for manual editing.

## Setup & Configuration

On your first `/brief`, `/autopilot`, or other git-dependent skill, the `SessionStart` hook prepares the target project: `git init -b main` if no repo exists (falls back to plain `git init` on git <2.28), an initial commit if HEAD is missing, and an idempotent append of `.simple-workflow/` to `.gitignore` (committed as `chore: add simple-workflow artifacts to .gitignore`). Once `.simple-workflow/.setup-done` is written, simple-workflow will **never** touch your `.gitignore` again — manual deletions are permanent.

Model selection is automatic based on ticket size — orchestrator skills (`/impl`, `/plan2doc`) pass the appropriate model to agents at invocation time. Hook scripts are registered in `hooks/hooks.json`; to customize, edit the JSON or override individual scripts while keeping the same interface (read stdin, exit 0 to allow / exit 2 to block).

### Sharing selected paths under `.simple-workflow/`

`.simple-workflow/` is gitignored by default, so the ticket counter (`.simple-workflow/.ticket-counter`) and every other artifact stay local — each developer starts independently at T-001. To share specific paths across a team (e.g. the counter for shared numbering, or project-wide spec docs), use the surgical opt-out below. The single-line `!.simple-workflow/.ticket-counter` does **not** work because git does not descend into an ignored parent directory; the structure must always be (1) un-ignore the directory, (2) re-ignore everything by default, (3) selectively un-ignore the path(s) you want tracked.

```gitignore
!.simple-workflow/                            # un-ignore the directory so git descends into it
.simple-workflow/*                            # re-ignore all contents by default
!.simple-workflow/.ticket-counter             # ...except the shared ticket counter
!.simple-workflow/docs/                       # ...and the docs/ directory
.simple-workflow/docs/*                       # re-ignore its contents
!.simple-workflow/docs/specs/                 # ...except specs/
!.simple-workflow/docs/specs/**               # ...including everything under specs/
```

Anything not explicitly un-ignored stays gitignored, so research notes, plans, eval logs, and the knowledge base remain private. Concurrent ticket creation by multiple developers will produce git conflicts on a shared counter — that is the expected trade-off. simple-workflow's behavior does not depend on whether files are tracked; these patterns are purely a per-team policy decision.

## Limitations

- Designed for use with Claude Code CLI and GitHub Copilot CLI. IDE extensions (VS Code, JetBrains) may have limited support for hooks and plugin features.
- On GitHub Copilot CLI, session lifecycle hooks (`pre-compact-save`, `session-stop-log`) may not fire. Context recovery via `/catchup` after compaction works best on Claude Code.
- The `/ship` skill requires GitHub CLI (`gh`) with authentication. Other Git hosting services are not supported.
- Ticket management uses the local filesystem (`.simple-workflow/backlog/`). There is no sync with external issue trackers (Jira, Linear, etc.).
- Sub-agents consume API tokens independently. Large tickets (L/XL) using Opus may result in higher API costs.
- AC Evaluator ships with built-in test/lint runners for JS, Python, Rust, Go, JVM (Gradle/Maven/sbt), .NET, Ruby, Elixir, Swift, Flutter/Dart, PHP, and Make. For other ecosystems, wrap your test/lint commands in a Makefile (`make test` / `make lint`) or the evaluator will rely on static code analysis only (reported as PASS-WITH-CAVEATS).

## Acknowledgements

simple-workflow is heavily inspired by:

- [Harness design for long-running agents](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Anthropic's guide on designing harnesses for reliable, long-running AI agents
- [obra/superpowers](https://github.com/obra/superpowers) — Patterns for maximizing Claude Code's capabilities through skills, agents, and hooks

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[Apache License 2.0](LICENSE) (since v4.2.0). Versions up to and including v4.1.0 were distributed under the MIT License — see the [NOTICE](NOTICE) file and `CHANGELOG.md` `## [4.2.0]` entry for details.

> Migrating from v4.x: v5.0.0 consolidated `.docs/`, `.backlog/`, and `.simple-wf-knowledge/` into a single `.simple-workflow/` directory — see the [v5.0.0 Migration Announcement](https://github.com/aimsise/simple-workflow/discussions/40) for the one-time manual move.
