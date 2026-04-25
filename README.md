# simple-workflow

[![CI](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Stars](https://img.shields.io/github/stars/aimsise/simple-workflow)](https://github.com/aimsise/simple-workflow/stargazers)

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) / [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) plugin for a complete development lifecycle with built-in ticket management. Conserves context by delegating to sub-agents, and guarantees quality through a Generator-Evaluator pipeline.

## Table of Contents

- [Why simple-workflow?](#why-simple-workflow)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Setup](#setup)
- [Building Blocks](#building-blocks)
- [Core Workflow](#core-workflow)
- [All Skills](#all-skills)
- [Configuration](#configuration)
- [Limitations](#limitations)
- [Acknowledgements](#acknowledgements)
- [Contributing](#contributing)

## Why simple-workflow?

Claude Code is powerful, but its context window is finite — and fragile. Long-running agent sessions face four structural threats:

| Threat | What happens | Structural countermeasure |
|--------|-------------|--------------------------|
| **Loss** | Session boundaries — compaction, exit — discard accumulated understanding | Pre-compact hooks, `/catchup` recovery, `/tune` cross-session learning |
| **Exhaustion** | The window fills up, degrading instruction-following and response quality | Bounded sub-agent returns (< 500 tokens), phase-aware context release |
| **Contamination** | Biasing information leaks into contexts where it distorts judgment | Information firewall (Generator → Evaluator blocked), ticket directory confinement |
| **Bloat** | Unbounded intermediate output crowds out critical instructions | Artifacts written to files, structured summaries returned to orchestrator |

simple-workflow addresses each threat with architectural constraints that hold regardless of model behavior — not prompt-level instructions that the model might rationalize away.

### Context Conservation Protocol

Treats the context window as a consumable resource and systematically conserves it.

- **Bounded sub-agent returns**: Each sub-agent launches with a fresh context, writes detailed artifacts to files, and returns only a structured summary (< 500 tokens). Without this bound, multi-round orchestration would accumulate unbounded output and degrade the orchestrator's decision quality
- **Phase-aware context release**: `/catchup` auto-detects your current phase (investigate → plan → implement → test → review → commit) and recommends the next action. Completed phases live on disk — clear the context and move on
- **Structured state preservation**: Before context compaction, a hook saves per-ticket state as YAML frontmatter. `/catchup` parses this to resume interrupted work — including mid-`/impl` loops

### Harness Engineering

Structurally separates "writing code" from "judging code" to guarantee quality by design.

- A **Generator** writes code, independent **Evaluators** verify it, and failures trigger automatic retry with specific feedback — up to 3 rounds. See [`/impl`](#4-impl--implement) for the full pipeline
- **Information firewall (asymmetric)**: Evaluators never see the Generator's self-assessment — they judge solely from `git diff` and test results. The reverse is intentionally open: on retry, the Generator receives Evaluator feedback. Even though both sides run the same model, **weights × context = output**: by excluding the Generator's trial-and-error history and implicit knowledge of shortcuts from the Evaluator's context, sunk-cost bias is structurally eliminated rather than merely discouraged by prompt
- **Mandatory Skill Invocations**: Orchestrator skills enforce that sub-agent dispatch uses the `Skill` tool rather than manual bash fallbacks. MUST/NEVER/Fail language in skill definitions makes this a structural contract, not a suggestion — ensuring sub-agents always launch with proper context isolation
- **FAIL-CRITICAL** violations halt execution immediately — no rationalization, no retry
- After ticket completion, evaluation logs feed into the [Knowledge Base](#knowledge-base-cross-session-learning), creating a cross-session feedback loop

### Built-in Ticket Management

Your project's `.simple-workflow/backlog/` directory is a state machine. Tickets transition between states via physical directory moves (`mv .simple-workflow/backlog/product_backlog/{ticket-dir} .simple-workflow/backlog/active/{ticket-dir}`), making state visible, traceable, and greppable — no database or external tools required.

```
.simple-workflow/backlog/
├── product_backlog/   # New tickets
├── active/            # In-progress tickets
├── blocked/           # Blocked tickets
└── done/              # Completed tickets
```

> **Note**: Moving tickets to `blocked/` is done manually:
> ```bash
> mv .simple-workflow/backlog/active/{ticket-dir} .simple-workflow/backlog/blocked/{ticket-dir}
> ```
> To unblock and resume work:
> ```bash
> mv .simple-workflow/backlog/blocked/{ticket-dir} .simple-workflow/backlog/active/{ticket-dir}
> ```

Each ticket is a directory where all work artifacts accumulate:

```
.simple-workflow/backlog/active/001-add-search-feature/
├── ticket.md          # The ticket (size, acceptance criteria, scope)
├── investigation.md   # Research findings
├── plan.md            # Implementation plan
├── eval-round-1.md    # Acceptance evaluation (round 1)
└── quality-round-1.md # Quality review (round 1)
```

From creation to completion, every intermediate artifact is confined within its ticket directory. This directory-level confinement serves dual purposes: **audit trail** (the complete history of investigation, planning, evaluation, and review is preserved as files) and **contamination prevention** (artifacts from one ticket never leak into another's context). The directory structure itself enforces governance — information accumulates in the filesystem, not the context window.

#### Unified ticket state: `phase-state.yaml`

Every ticket carries a `phase-state.yaml` file that declares its full lifecycle state (`create_ticket → scout → impl → ship → done`). `/create-ticket` creates it, each subsequent phase-owner skill updates only its own section, and `/ship` moves it alongside the ticket directory to `.simple-workflow/backlog/done/`. **`phase-state.yaml` is never deleted** — it is the permanent lifecycle record for the ticket. The `SessionStart` hook and `/catchup` both read this file to recover active-ticket context in one step, without walking every artifact. The canonical schema, field enums, and per-skill write-ownership rules live in [`skills/create-ticket/references/phase-state-schema.md`](skills/create-ticket/references/phase-state-schema.md).

> **Scope note**: `phase-state.yaml` tracks the manual workflow (`/create-ticket` → `/scout` → `/impl` → `/ship`). Cost accounting and orchestration state for `/autopilot` are tracked in `autopilot-state.yaml`, a separate schema. See [`skills/create-ticket/references/phase-state-schema.md`](skills/create-ticket/references/phase-state-schema.md) §5 "Dual-state precedence" for how `/catchup` reconciles the two.

Phase-terminating skills (`/create-ticket`, `/scout`, `/plan2doc`, `/impl`, `/ship`) close their output with a standardized `[SW-CHECKPOINT]` block that lists the phase, ticket, artifacts, and recommended next command — a signal that running `/clear` is safe and that `/catchup` can recover from `phase-state.yaml` with minimal token spend.

### Knowledge Base (Cross-Session Learning)

`.simple-workflow/kb/` is an automatically maintained knowledge base that captures recurring patterns from evaluation logs. `/tune` analyzes completed ticket evaluations (eval-round, audit-round files) via the `tune-analyzer` agent, extracts actionable patterns (common failures, recurring feedback themes), and persists them as structured entries. At implementation time, `/impl` injects relevant knowledge base patterns into the Generator's dispatch prompt, so lessons learned from past tickets inform future implementation — closing the loop between evaluation feedback and code generation across sessions.

This feedback loop means simple-workflow is not a static tool — it is a **learning system that improves with use**. The more tickets you complete in a project, the more project-specific patterns accumulate, and the higher the probability that future implementations pass evaluation on the first round. In effect, the system develops project-specific expertise over time — analogous to a human developer becoming more effective the longer they work on a codebase — without fine-tuning the underlying model.

## Building Blocks

simple-workflow is composed of three types of components: **Skills**, **Sub-agents**, and **Hooks**.

### Skills (Slash Commands)

Operations invoked as slash commands like `/scout` or `/impl`. There are two kinds:

- **Orchestrators**: Don't do work themselves — they coordinate sub-agents to drive a workflow (`/impl`, `/ship`, `/create-ticket`, `/brief`, `/autopilot`, etc.)
- **Delegators**: Hand off work to a specific sub-agent (`/investigate`, `/plan2doc`, `/test`, etc.)

### Sub-agents

Specialists launched by skills. Each runs in an isolated context with a tool permission scope appropriate to its role:

- **Generator agents** (`implementer`, `test-writer`) need broad `Bash(*)` access to run arbitrary build/test tools defined by the target project
- **Evaluator agents** (`ac-evaluator`, `code-reviewer`, `security-scanner`, `ticket-evaluator`) are restricted to read-only file utilities, with `ac-evaluator` additionally having read-only git access and specific test/lint runners
- **Research/planning agents** (`researcher`, `planner`) are restricted to read-only git and filesystem tools

This asymmetry is deliberate: the Generator-Evaluator separation relies on evaluators being unable to execute destructive commands even if prompted to do so.

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

Models are auto-selected based on ticket size (S/M/L/XL). `planner` uses Sonnet for S and Opus for M/L/XL. `implementer` uses Sonnet for S/M and Opus for L/XL. Both agents accept a dynamic model parameter; orchestrator skills pass the appropriate model at invocation time.

### Hooks (Safety Hooks)

Guardrails that fire automatically on tool execution to protect your project.

- **pre-bash-safety** — **Best-effort** blocking of common destructive commands (`rm -rf`, `git push --force`, `git reset --hard`, `git clean -f`, `DROP TABLE/DATABASE`, and bulk-staging of sensitive files). Does NOT catch arbitrary destructive commands from cloud / orchestration CLIs (`gh repo delete`, `aws s3 rm`, `kubectl delete`, `terraform destroy`, etc.) or shell-string indirection (`sh -c '...'`, `python -c '...'`). Treat this hook as a guardrail for common slip-ups, **not** as a security boundary.
- **pre-write-safety / pre-edit-safety** — Blocks writes to sensitive files (`.env`, private keys, credentials)
- **session-start** — Initializes the session environment: loads branch info and changed file count, auto-injects an initial commit on empty repositories, auto-appends `.gitignore` entries for plugin-managed directories, and cleans old session logs
- **pre-compact-save** — Auto-saves work state before context compaction as a YAML-frontmatter snapshot (active tickets, plans, latest evaluation rounds, in-progress phase). `/catchup` parses this to resume mid-loop work after compaction.
- **session-stop-log** — Records a work log (branch, last commit, status, recent commits) on session end as a YAML-frontmatter file. Used by `/catchup` as a fallback state source when no compact-state file exists.
- **autopilot-continue** — Stop hook that prevents premature `end_turn` during `/autopilot` pipeline execution. Returns `decision: "block"` when `autopilot-state.yaml` has unfinished steps, keeping the pipeline running until all steps complete.
- **pre-level1-guard** — PreToolUse hook that blocks integration test scripts from running without `RUN_LEVEL1_TESTS=true`, preventing accidental API charges from expensive test suites.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI or [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) installed and authenticated
- [GitHub CLI](https://cli.github.com/) (`gh`) — required for `/ship`
- `git` and `jq`

## Quick Start

```bash
# Install the plugin
claude plugin install aimsise/simple-workflow   # Claude Code
copilot plugin install aimsise/simple-workflow   # GitHub Copilot CLI
```

Once installed, all slash commands work the same on both platforms:

```
/investigate <topic>
/create-ticket <description>
/scout .simple-workflow/backlog/product_backlog/001-migrate-to-session-auth/ticket.md
/impl
/audit
/ship
```

> **Note**: Session lifecycle hooks (`pre-compact-save`, `session-stop-log`) may not fire on Copilot CLI. Context recovery via `/catchup` after compaction works best on Claude Code.

## Migrating from v4.x

v5.0.0 consolidates the 3 top-level directories (`.docs/`, `.backlog/`, `.simple-wf-knowledge/`) into a single `.simple-workflow/` directory. See the [v5.0.0 Migration Announcement](https://github.com/aimsise/simple-workflow/discussions/40) for the full step-by-step guide. Existing users must perform a one-time manual move; new installs need no action.

## Setup

On your first `/brief`, `/autopilot`, or other git-dependent skill, simple-workflow's `SessionStart` hook prepares the target project:

1. `git init -b main` if there is no repo (falls back to plain `git init` on git <2.28)
2. An initial commit if the repo has no HEAD
3. Appends `.simple-workflow/` to `.gitignore` (idempotent — only added if missing) and commits with `chore: add simple-workflow artifacts to .gitignore`
4. Writes `.simple-workflow/.setup-done` as the idempotency marker — once present, simple-workflow will **never** touch your `.gitignore` again, even across sessions. If you delete an entry manually, that decision is permanent.

### Ticket counter is per-developer

`.simple-workflow/.ticket-counter` lives under the gitignored `.simple-workflow/` tree, so each developer starts independently at T-001. This is deliberate for individual productivity workflows.

If you want to share ticket numbering across a team, use this surgical opt-out in your `.gitignore` (the single-line `!.simple-workflow/.ticket-counter` does **not** work — git does not descend into an ignored parent directory):

    !.simple-workflow/                 # un-ignore the directory so git descends into it
    .simple-workflow/*                 # re-ignore all contents by default
    !.simple-workflow/.ticket-counter  # …except the counter

That tracks only the counter; briefs, active tickets, and the knowledge base stay local. Concurrent ticket creation by multiple developers will produce git conflicts on the counter — that is the expected trade-off for team-shared numbering.

### Tracking other paths under `.simple-workflow/`

The same opt-out pattern works for any path you want to keep in version control — for example, shared spec or template files maintained by your team. The structure is always:

1. Un-ignore the directory so git can descend into it.
2. Re-ignore everything by default.
3. Selectively un-ignore only the path(s) you actually want tracked.

Example — share project-wide spec docs but keep everything else local:

    !.simple-workflow/                            # un-ignore the directory
    .simple-workflow/*                            # re-ignore all contents
    !.simple-workflow/docs/                       # …except docs/
    .simple-workflow/docs/*                       # …re-ignore its contents
    !.simple-workflow/docs/specs/                 # …except specs/
    !.simple-workflow/docs/specs/**               # …including everything under specs/

Anything you do NOT explicitly un-ignore stays gitignored, so research notes, plans, eval logs, and the knowledge base remain private. simple-workflow's own behavior does not depend on whether files are tracked — these patterns are purely a per-team policy decision.

## Core Workflow

A typical development flow follows these five steps:

```
investigate ──> create-ticket ──> scout ──> impl ──> ship
```

### 1. `/investigate` — Research

```
/investigate how is user authentication currently implemented
```

The researcher agent explores the codebase and writes its findings to `.simple-workflow/docs/research/` or the ticket directory. Only a summary is returned to the caller.

### 2. `/create-ticket` — Create a Ticket

```
/create-ticket migrate from JWT auth to session-based auth
```

Creates a structured ticket through four phases:

1. **Investigation**: The researcher examines scope and impact
2. **Socratic dialogue**: Asks clarifying questions to align understanding with the user
3. **Ticket drafting**: The planner creates a ticket with size, acceptance criteria, and scope
4. **Quality evaluation**: The ticket-evaluator checks five quality gates (testability, unambiguity, completeness, implementability, size fit) — if any gate fails, the ticket is revised and re-evaluated

The resulting ticket is saved to `.simple-workflow/backlog/product_backlog/{ticket-dir}/ticket.md` (where `{ticket-dir}` is `{NNN}-{slug}`, e.g., `001-migrate-to-session-auth`).

### 3. `/scout` — Research + Plan

```
/scout .simple-workflow/backlog/product_backlog/001-migrate-to-session-auth/ticket.md
```

Chains `/investigate` and `/plan2doc` in sequence. Moves the ticket to `.simple-workflow/backlog/active/`, then runs research and creates an implementation plan in one go. `/plan2doc` selects model based on ticket size (sonnet for S, opus for M/L/XL).

At this point, `.simple-workflow/backlog/active/{ticket-dir}/` contains `ticket.md`, `investigation.md`, and `plan.md` — everything needed for implementation.

### 4. `/impl` — Implement

```
/impl
```

Implements code through a three-phase pipeline:

**Phase 1: Preparation**
- Loads the active plan and detects ticket size
- For M-size and above: AC sanity check (the Generator flags ambiguous AC up front)
- For L/XL only: blocking Evaluator dry run (agreement on the verification plan before any code is written; on failure, the user is asked whether to proceed)
- Saves current state with `git stash` for safety

**Phase 2: Implementation loop (up to 3 rounds)**
1. **Generator** (implementer) writes code using a test-first approach. Model is auto-selected: sonnet for S/M, opus for L/XL.
2. **AC Evaluator** independently verifies acceptance criteria compliance — on failure, sends specific feedback back to the Generator
3. **`/audit`** runs after AC passes — a multi-agent review that always invokes `security-scanner` and runs `code-reviewer` in parallel, returning an aggregated `Status / Critical / Warnings / Suggestions` block

Each round's evaluation results are saved as `eval-round-{n}.md` / `quality-round-{n}.md` / `security-scan-{n}.md` in the ticket directory.

**Phase 3: Completion report**
- Outputs a summary of all evaluation rounds

> **Note**: `/impl` requires interactive mode for specific failure recovery paths (Evaluator Dry Run failure for L/XL tickets, `/audit` infrastructure failure). In `claude -p` or CI automation, these paths will stop the skill with an explanatory message rather than hang. For fully autonomous pipelines, avoid relying on L/XL ticket sizes or pre-validate your audit infrastructure.
>
> Similarly, `/create-ticket` requires interactive mode for two paths: (1) Phase 2 Socratic Refinement is **skipped** in non-interactive mode (the ticket is generated from researcher findings alone without Q&A refinement, and the summary notes "Phase 2 skipped"); (2) Phase 4 quality FAIL escalation **stops** the skill with the ticket saved on disk for manual editing — non-interactive mode will not silently bypass unresolved quality gates.

### 5. `/ship` — Commit and PR

```
/ship                # Commit + PR (default)
/ship merge=true     # Commit + PR + squash-merge
```

Ships the current changes through up to three phases:

1. **Commit** — Stages changes and creates a Conventional Commits-formatted commit
2. **Create PR** — Pushes to GitHub and creates a pull request
3. **Merge** (optional, `merge=true`) — Squash-merges, deletes the branch, and syncs local

If no prior review via `/audit` is detected, a review gate recommends running one first. Pre-computed context (branch name, diff stats, commit log) is gathered with a resilience contract that ensures `/ship` never fails due to unexpected git state — missing remotes, empty diffs, or detached HEAD are all handled gracefully. After a successful commit, the ticket is automatically moved to `.simple-workflow/backlog/done/`, and `/tune` is invoked to extract reusable patterns from the ticket's evaluation logs into the project knowledge base.

### Full Automation with /brief + /autopilot

For a fully automated pipeline from idea to PR:

1. **`/brief <what-to-build>`** — Investigates the codebase and conducts a structured interview to gather all requirements. Generates a brief document and an autopilot-policy.yaml defining autonomous decision rules.

2. **`/autopilot <slug>`** — Reads the brief and executes the full pipeline (`create-ticket → scout → impl → ship`) with zero human intervention. Decision points are resolved by the autopilot-policy. Large scopes are automatically split into multiple tickets and executed in dependency order. Quality safeguards run at each pipeline step: an **Artifact Presence Gate** validates that all expected artifacts (investigation, plan, evaluation logs, etc.) exist before marking a step complete, and a **Skill Invocation Audit** tracks whether each step used proper Skill tool dispatch. Steps that fell back to manual bash invocation are flagged as `completed-with-warnings`.

> **Note**: Workflow isolation is bidirectional. `/autopilot` requires a brief as its starting point — it creates tickets internally and processes only those tickets. It does not pick up existing tickets from `.simple-workflow/backlog/product_backlog/`. Conversely, manual `/impl` excludes autopilot-managed tickets (those containing `autopilot-policy.yaml`) and selects the lowest-numbered non-autopilot ticket first (FIFO). To process tickets created manually via `/create-ticket`, use the individual skill flow: `/scout → /impl → /ship`.

The autopilot-policy evolves over time: `/tune` extracts decision patterns from execution logs, and future `/brief` runs use these patterns to suggest more accurate defaults.

## All Skills

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
| Full Pipeline | `/autopilot` | Execute the full pipeline (create-ticket → scout → impl → ship) from a brief document with zero human intervention. Auto-splits large scopes |

## Configuration

Model selection is automatic based on ticket size — S-size tickets use Sonnet for speed, M and above use Opus for depth. This selection is driven by the orchestrator skills (`/impl`, `/plan2doc`), which pass the appropriate model to agents at invocation time.

Hook scripts are registered in `hooks/hooks.json`. To customize, edit the JSON file or override individual scripts while keeping the same interface (read stdin, exit 0 to allow / exit 2 to block).

## Limitations

- Designed for use with Claude Code CLI and GitHub Copilot CLI. IDE extensions (VS Code, JetBrains) may have limited support for hooks and plugin features.
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
