# simple-workflow

[![CI](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/aimsise/simple-workflow)](https://github.com/aimsise/simple-workflow/stargazers)

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin providing a complete development lifecycle — from discovery through delivery — with backlog-based ticket management.

## Overview

simple-workflow organizes development work into a clear lifecycle:

```
Scout ──> Investigate ──> Plan ──> Implement ──> Review ──> Ship
```

Each phase is powered by specialized **skills** (slash commands) and **agents**, with **safety hooks** protecting against destructive operations throughout.

## Quick Start

Install the plugin:

```bash
claude plugin add aimsise/simple-workflow
```

Start with a scout to investigate a topic and create an implementation plan:

```
/scout <topic>
```

Or go step by step:

```
/investigate <topic>     # Research the codebase
/plan2doc                # Create an implementation plan
/impl                    # Implement the plan
/ship                    # Commit, create PR, and merge
```

## Skills

### Discovery

| Skill | Description |
|-------|-------------|
| `/scout` | Investigate codebase and create an implementation plan (chains /investigate + /plan2doc) |
| `/investigate` | Deep-dive codebase exploration via researcher agent |
| `/catchup` | Recover working context from current branch state |

### Planning

| Skill | Description |
|-------|-------------|
| `/plan2doc` | Create a detailed implementation plan (Opus) |
| `/plan2doc-light` | Lightweight implementation plan (Sonnet) |
| `/create-ticket` | Create a structured ticket with scope analysis and acceptance criteria |

### Implementation

| Skill | Description |
|-------|-------------|
| `/impl` | Implement a plan using Generator > AC Evaluator > Code Reviewer pipeline |
| `/refactor` | Plan and execute a refactoring with safety checks |
| `/test` | Create and run tests for specified files or features |

### Quality

| Skill | Description |
|-------|-------------|
| `/review-diff` | Multi-agent code review (code quality + security) |
| `/security-scan` | Security audit against known vulnerability patterns |

### Delivery

| Skill | Description |
|-------|-------------|
| `/commit` | Stage changes and create a conventional commit |
| `/create-pr` | Create a pull request |
| `/create-pr-with-merge` | Create a PR and squash-merge it |
| `/ship` | All-in-one: commit + create PR + merge |

### Utility

| Skill | Description |
|-------|-------------|
| `/memorize` | Save current progress to project memory |
| `/phase-clear` | Switch work phase with context preservation |
| `/ticket-active` | Move tickets to active status |
| `/ticket-blocked` | Move tickets to blocked status |
| `/ticket-done` | Move tickets to done status |

## Agents

| Agent | Model | Description |
|-------|-------|-------------|
| `implementer` | Opus | Implements code changes for M/L/XL tickets with test-first protocol |
| `implementer-light` | Sonnet | Lightweight implementation for S-size tickets |
| `planner` | Opus | Creates detailed implementation plans |
| `planner-light` | Sonnet | Lightweight planning for small changes |
| `ac-evaluator` | Sonnet | Verifies acceptance criteria compliance |
| `code-reviewer` | Sonnet | Reviews code quality, security, and conventions |
| `researcher` | Sonnet | Codebase exploration and architecture investigation |
| `test-writer` | Sonnet | Designs and implements test cases |
| `ticket-evaluator` | Sonnet | Evaluates ticket quality and implementability |
| `security-scanner` | Sonnet | Security audit for common vulnerability patterns |
| `doc-writer` | Haiku | Generates documentation from code |

## Safety Hooks

simple-workflow includes safety hooks that run automatically to protect your project:

- **pre-bash-safety** — Blocks destructive shell commands (e.g., `rm -rf`, `git push --force`)
- **pre-write-safety** — Prevents writing to sensitive files (e.g., `.env`, credentials)
- **pre-edit-safety** — Prevents editing sensitive files
- **session-start** — Initializes session context (branch info, active plan, memory)
- **session-stop-log** — Logs session activity
- **pre-compact-save** — Preserves state before context compaction

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE)
