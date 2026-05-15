# simple-workflow

[![CI](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/aimsise/simple-workflow)](https://github.com/aimsise/simple-workflow/releases)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

The [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin for **end-to-end AI development workflows**. From idea to pull request: structured interview, codebase investigation, multi-agent implementation, security audit, code review, and PR creation, all automated.

Built on a **Harness for long-running AI agents** with strict context management, information firewalls, and a cross-session knowledge base that improves accuracy with every completed ticket.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and authenticated
- [GitHub CLI](https://cli.github.com/) (`gh`) — required for pull-request creation
- `git` and `jq`

simple-workflow runs entirely against your local filesystem and your existing GitHub remote — no external services, no database, no separate auth.

## Quick Start

Claude Code resolves plugin names only against marketplaces that have already been registered, so installing `simple-workflow` is a two-step flow: register the repository as a marketplace, then install the plugin by name from it.

```bash
# Step 1 — register aimsise/simple-workflow as a marketplace
claude plugin marketplace add aimsise/simple-workflow

# Step 2 — install the simple-workflow plugin from that marketplace
claude plugin install simple-workflow@aimsise-simple-workflow
```

Inside an active Claude Code session, the equivalent slash commands are `/plugin marketplace add aimsise/simple-workflow` and `/plugin install simple-workflow@aimsise-simple-workflow`. The `aimsise-simple-workflow` suffix is the `name` declared in [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) and is what disambiguates the plugin when more than one marketplace is registered.

### Installation scope

`claude plugin install` writes to your **user scope** (`~/.claude/settings.json`) by default, making the plugin available across every project on your machine. To pin the plugin to a single repository so collaborators inherit it on clone, install at **project scope** instead:

```bash
claude plugin install simple-workflow@aimsise-simple-workflow --scope project
```

Project scope writes the marketplace and plugin entry to `<repo>/.claude/settings.json` — commit that file to share the configuration with your team. To migrate an existing user-scope install to project scope, uninstall first so the two entries do not coexist:

```bash
claude plugin uninstall simple-workflow@aimsise-simple-workflow --scope user
claude plugin install   simple-workflow@aimsise-simple-workflow --scope project
```

`--scope local` is also accepted; it writes to `<repo>/.claude/settings.local.json`, which is gitignored, so the plugin stays installed for you on this clone but does not propagate to collaborators. Slash-command forms (`/plugin install ... --scope project`, `/plugin uninstall ... --scope user`) work identically from within an active Claude Code session.

## Usage

Inside an active Claude Code session, type `/brief <idea>` and the plugin handles the rest end-to-end: codebase investigation, requirements interview, ticket creation, implementation, multi-agent review, and pull request.

| Mode | Command | Result |
|------|---------|--------|
| Full automation (default) | `/brief <idea>` | Idea → PR with zero intervention; large scopes are auto-split into multiple tickets and executed in dependency order |
| Brief-assisted manual | `/brief <idea> mode=manual` | Structured brief and decision policy are produced; you drive each subsequent step |
| Resume an interrupted run | `/autopilot <slug>` | Pick up where a previous automated run left off using state files under `.simple-workflow/backlog/` |

### Execution chains

What the plugin runs and what you need to type:

- **Full automation** — You type `/brief <idea>` only. The plugin chains it as `/brief` → `/autopilot` → (per ticket: `/create-ticket` → `/scout` → `/impl` → `/ship`), ending with the PR opened.
- **Brief-assisted manual** — You type `/brief <idea> mode=manual` to produce the brief, then drive each subsequent step yourself: `/create-ticket` → `/scout` → `/impl` → `/ship`.

For phase-by-phase workflows on an existing backlog (skipping the brief), run `/help` inside Claude Code to discover the individual slash commands, or browse `skills/` in this repository.

## Why simple-workflow?

simple-workflow stands on three pillars:

- **Harness Engineering**: structural constraints — an asymmetric information firewall between code authors and code judges (the Generator-Evaluator pattern), bounded sub-agent returns, ticket-confined artifacts, and safe-clear `[SW-CHECKPOINT]` markers — enforce quality by architecture rather than by prompt instructions
- **Context Conservation**: the context window is treated as a consumable resource — sub-agents return < 500-token summaries, artifacts live on disk, and state survives compaction
- **Cross-session learning**: evaluation logs are distilled into reusable patterns that future implementations inject into their prompts, so the system gets better at your project the more tickets it completes

These pillars exist because Claude Code is powerful, but its context window is finite — and fragile. Long-running agent sessions face four structural threats:

| Threat | What happens | Structural countermeasure |
|--------|-------------|--------------------------|
| **Loss** | Session boundaries — compaction, exit — discard accumulated understanding | Automatic state snapshots, on-restart recovery, cross-session learning |
| **Exhaustion** | The window fills up, degrading instruction-following and response quality | Bounded sub-agent returns (< 500 tokens), phase-aware context release |
| **Contamination** | Biasing information leaks into contexts where it distorts judgment | Information firewall + ticket directory confinement (see [Harness Engineering](ARCHITECTURE.md#harness-engineering)) |
| **Bloat** | Unbounded intermediate output crowds out critical instructions | Artifacts written to files, structured summaries returned to orchestrator |

simple-workflow addresses each threat with architectural constraints that hold regardless of model behavior — not prompt-level instructions that the model might rationalize away. For a deeper walkthrough of each pillar — Context Conservation Protocol, Harness Engineering, Knowledge Base, and Ticket Management state machine — see [ARCHITECTURE.md](ARCHITECTURE.md).

## Setup & Configuration

The first time the plugin runs in a project, the target repository is prepared automatically: `git init -b main` if no repo exists (falls back to plain `git init` on git <2.28), an initial commit if HEAD is missing, and an idempotent append of `.simple-workflow/` to `.gitignore` (committed as `chore: add simple-workflow artifacts to .gitignore`). Once `.simple-workflow/.setup-done` is written, simple-workflow will **never** touch your `.gitignore` again — manual deletions are permanent.

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

## Operational Notes

### Long idle gaps: start a new session before resuming

Claude Code's ephemeral prompt-cache entries have a roughly 1-hour TTL. If a session sits idle past that window — for example, an overnight pause — the next turn re-warms the cache from scratch and can rewrite **hundreds of thousands of cache_creation tokens** in a single turn.

**Recommendation**: if a simple-workflow session has been idle for more than ~1 hour, exit and start a fresh session. Phase-terminating workflows emit a `[SW-CHECKPOINT]` block precisely so that `/clear` or session exit is safe, and the plugin reconstructs the in-progress phase from `phase-state.yaml` on the next session.

### Resuming an interrupted automated run

If an automated run ends with a `partial` status before reaching the context-window cap, the model likely self-aborted before Claude Code's auto-Compaction had a chance to fire. Run `/autopilot <slug>` in a fresh session to pick up where it left off — state files in `.simple-workflow/backlog/` provide the resume point.

## Limitations

- Designed for use with Claude Code CLI. IDE extensions (VS Code, JetBrains) may have limited support for hooks and plugin features.
- Pull-request creation requires GitHub CLI (`gh`) with authentication. Other Git hosting services are not supported.
- Ticket management uses the local filesystem (`.simple-workflow/backlog/`). There is no sync with external issue trackers (Jira, Linear, etc.).
- Sub-agents consume API tokens independently. Large tickets (L/XL) using Opus may result in higher API costs.
- Built-in test/lint detection covers JS, Python, Rust, Go, JVM (Gradle/Maven/sbt), .NET, Ruby, Elixir, Swift, Flutter/Dart, PHP, and Make. For other ecosystems, wrap your test/lint commands in a Makefile (`make test` / `make lint`) or the evaluator falls back to static code analysis only.
- Some recovery paths require interactive mode; running in `claude -p` or CI may stop with an explanatory message rather than complete the recovery.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[Apache License 2.0](LICENSE)
