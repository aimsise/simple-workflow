# simple-workflow

[![CI](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/aimsise/simple-workflow)](https://github.com/aimsise/simple-workflow/stargazers)

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin for a complete development lifecycle with built-in ticket management. Conserves context by delegating to sub-agents, and guarantees quality through a Generator-Evaluator pipeline.

## Table of Contents

- [Why simple-workflow?](#why-simple-workflow)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Building Blocks](#building-blocks)
- [Core Workflow](#core-workflow)
- [All Skills](#all-skills)
- [Configuration](#configuration)
- [Limitations](#limitations)
- [Acknowledgements](#acknowledgements)
- [Contributing](#contributing)

## Why simple-workflow?

Claude Code is powerful, but its context window is finite. When you tackle a large task in a single conversation, context overflows mid-work and progress is lost.

simple-workflow solves this with two design principles: **Context Conservation Protocol** and **Harness Engineering**.

### Context Conservation Protocol

Treats the context window as a consumable resource and systematically conserves it.

- **Delegate to sub-agents**: Investigation, planning, implementation, and review are each delegated to specialist sub-agents. Each agent launches with a fresh context, writes detailed artifacts to files, and returns only a summary (under 500 tokens) to the caller
- **Release context between phases**: Once an investigation phase is complete, its artifacts live on disk — you can clear the context and move to the next phase. `/catchup` restores your working state at any time
- **Auto-save before compaction**: When Claude Code compresses context, a hook automatically saves the current work state to a file so nothing is lost

### Harness Engineering

Structurally separates "writing code" from "judging code" to guarantee quality by design.

- A **Generator** (implementer) writes code, an **AC Evaluator** independently verifies compliance against acceptance criteria, and `/audit` runs a multi-agent quality + security review (code-reviewer + security-scanner) on the resulting diff
- **Information firewall (asymmetric)**: evaluators judge solely from `git diff` and test results — they never see the Generator's self-assessment. The reverse direction is intentionally open: on retry, the Generator receives evaluator feedback (via `eval-round-{n}.md` / `quality-round-{n}.md`), and for L/XL tickets, the Evaluator Dry Run verification plan. This asymmetry is deliberate — bias from Generator to Evaluator is blocked, while corrective feedback from Evaluator to Generator is allowed
- On failure, the Generator receives specific, actionable feedback and retries — up to 3 rounds
- Critical AC violations (FAIL-CRITICAL) halt execution immediately

### Built-in Ticket Management

Your project's `.backlog/` directory becomes a ticket board. No external tools required.

```
.backlog/
├── product_backlog/   # New tickets
├── active/            # In-progress tickets
├── blocked/           # Blocked tickets
└── done/              # Completed tickets
```

Each ticket is a directory where all work artifacts accumulate:

```
.backlog/active/add-search-feature/
├── ticket.md          # The ticket (size, acceptance criteria, scope)
├── investigation.md   # Research findings
├── plan.md            # Implementation plan
├── eval-round-1.md    # Acceptance evaluation (round 1)
└── quality-round-1.md # Quality review (round 1)
```

From creation to completion, every intermediate artifact is preserved as a file. This is the heart of the Context Conservation Protocol — information accumulates in the filesystem, not the context window.

## Building Blocks

simple-workflow is composed of three types of components: **Skills**, **Sub-agents**, and **Hooks**.

### Skills (Slash Commands)

Operations invoked as slash commands like `/scout` or `/impl`. There are two kinds:

- **Orchestrators**: Don't do work themselves — they coordinate sub-agents to drive a workflow (`/impl`, `/ship`, `/create-ticket`, etc.)
- **Delegators**: Hand off work to a specific sub-agent (`/investigate`, `/plan2doc`, `/test`, etc.)

### Sub-agents

Specialists launched by skills. Each runs in an isolated context with a tool permission scope appropriate to its role:

- **Generator agents** (`implementer`, `test-writer`) need broad `Bash(*)` access to run arbitrary build/test tools defined by the target project
- **Evaluator agents** (`ac-evaluator`, `code-reviewer`, `security-scanner`, `ticket-evaluator`) are restricted to read-only git, specific test/lint runners, and read-only file utilities
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

Models are auto-selected based on ticket size (S/M/L/XL). S-size tickets use Sonnet for speed; M and above use Opus for depth. The `planner` and `implementer` agents accept a dynamic model parameter; orchestrator skills pass the appropriate model at invocation time.

### Hooks (Safety Hooks)

Guardrails that fire automatically on tool execution to protect your project.

- **pre-bash-safety** — **Best-effort** blocking of common destructive commands (`rm -rf`, `git push --force`, `git reset --hard`, `git clean -f`, `DROP TABLE/DATABASE`, and bulk-staging of sensitive files). Does NOT catch arbitrary destructive commands from cloud / orchestration CLIs (`gh repo delete`, `aws s3 rm`, `kubectl delete`, `terraform destroy`, etc.) or shell-string indirection (`sh -c '...'`, `python -c '...'`). Treat this hook as a guardrail for common slip-ups, **not** as a security boundary.
- **pre-write-safety / pre-edit-safety** — Blocks writes to sensitive files (`.env`, private keys, credentials)
- **session-start** — Loads branch info and changed file count at session start
- **pre-compact-save** — Auto-saves work state before context compaction as a YAML-frontmatter snapshot (active tickets, plans, latest evaluation rounds, in-progress phase). `/catchup` parses this to resume mid-loop work after compaction.
- **session-stop-log** — Records a work log (branch, last commit, status, recent commits) on session end as a YAML-frontmatter file. Used by `/catchup` as a fallback state source when no compact-state file exists.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and authenticated
- [GitHub CLI](https://cli.github.com/) (`gh`) — required for `/ship`
- `git` and `jq`

## Quick Start

```bash
# Install the plugin
claude plugin install aimsise/simple-workflow

# Start Claude Code in your project
claude
```

Once inside a Claude Code session:

```
# Investigate an issue and create a ticket
/investigate <topic>
/create-ticket <description>

# Research + plan in one step
/scout .backlog/product_backlog/{slug}/ticket.md

# Implement
/impl

# Review and deliver
/audit
/ship
```

## Core Workflow

A typical development flow follows these five steps:

```
investigate ──> create-ticket ──> scout ──> impl ──> ship
```

### 1. `/investigate` — Research

```
/investigate how is user authentication currently implemented
```

The researcher agent explores the codebase and writes its findings to `.docs/research/` or the ticket directory. Only a summary is returned to the caller.

### 2. `/create-ticket` — Create a Ticket

```
/create-ticket migrate from JWT auth to session-based auth
```

Creates a structured ticket through four phases:

1. **Investigation**: The researcher examines scope and impact
2. **Socratic dialogue**: Asks clarifying questions to align understanding with the user
3. **Ticket drafting**: The planner creates a ticket with size, acceptance criteria, and scope
4. **Quality evaluation**: The ticket-evaluator checks five quality gates (testability, unambiguity, completeness, implementability, size fit) — if any gate fails, the ticket is revised and re-evaluated

The resulting ticket is saved to `.backlog/product_backlog/{slug}/ticket.md`.

### 3. `/scout` — Research + Plan

```
/scout .backlog/product_backlog/migrate-to-session-auth/ticket.md
```

Chains `/investigate` and `/plan2doc` in sequence. Moves the ticket to `.backlog/active/`, then runs research and creates an implementation plan in one go. `/plan2doc` selects model based on ticket size (sonnet for S, opus for M/L/XL).

At this point, `.backlog/active/{slug}/` contains `ticket.md`, `investigation.md`, and `plan.md` — everything needed for implementation.

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
1. **Generator** (implementer) writes code using a test-first approach. Model is auto-selected: sonnet for S, opus for M/L/XL.
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

If no prior review via `/audit` is detected, a review gate recommends running one first. On successful merge, the ticket is automatically moved to `.backlog/done/`.

## All Skills

| Phase | Skill | Description |
|-------|-------|-------------|
| Discovery | `/investigate` | Deep-dive codebase exploration |
| Discovery | `/catchup` | Recover context from compact-state / session-log, detect current phase, and recommend next action (including resuming an in-progress `/impl` loop) |
| Planning | `/scout` | Chain investigation + planning in one step |
| Planning | `/plan2doc` | Create a detailed implementation plan (auto-selects model by ticket size) |
| Tickets | `/create-ticket` | Create a structured ticket with quality evaluation |
| Tickets | `/ticket-move` | Move tickets to a target backlog state (active/blocked/done) |
| Implementation | `/impl` | Implement via Generator-Evaluator pipeline |
| Implementation | `/refactor` | Safe refactoring with backup branch |
| Testing | `/test` | Design and run tests |
| Quality | `/audit` | Multi-agent code quality + security audit (use `only_security_scan=true` for security-only) |
| Delivery | `/commit` | Create a Conventional Commits-formatted commit |
| Delivery | `/ship` | Commit + PR in one step (optionally merge) |

## Configuration

Model selection is automatic based on ticket size — S-size tickets use Sonnet for speed, M and above use Opus for depth. This behavior is defined in each agent's frontmatter and orchestrator skill.

Hook scripts are registered in `hooks/hooks.json`. To customize, edit the JSON file or override individual scripts while keeping the same interface (read stdin, exit 0 to allow / exit 2 to block).

## Limitations

- Designed for use with Claude Code CLI. IDE extensions (VS Code, JetBrains) may have limited support for hooks and plugin features.
- The `/ship` skill requires GitHub CLI (`gh`) with authentication. Other Git hosting services are not supported.
- Ticket management uses the local filesystem (`.backlog/`). There is no sync with external issue trackers (Jira, Linear, etc.).
- Sub-agents consume API tokens independently. Large tickets (L/XL) using Opus may result in higher API costs.

## Acknowledgements

simple-workflow is heavily inspired by:

- [Harness design for long-running agents](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Anthropic's guide on designing harnesses for reliable, long-running AI agents
- [obra/superpowers](https://github.com/obra/superpowers) — Patterns for maximizing Claude Code's capabilities through skills, agents, and hooks

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE)
