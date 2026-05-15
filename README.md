# simple-workflow

[![CI](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/aimsise/simple-workflow/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/aimsise/simple-workflow)](https://github.com/aimsise/simple-workflow/releases)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

The [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin for an **end-to-end AI development workflow** — structured interview, ticket management, codebase investigation, multi-agent implementation, security audit, code review, and automated PR creation — built on a **Harness for long-running AI agents** with strict context management, information firewalls, and a cross-session knowledge base that improves accuracy with every completed ticket.

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

For phase-by-phase workflows on an existing backlog, individual slash commands are available — run `/help` inside Claude Code to discover them, or browse `skills/` in this repository.

## Why simple-workflow?

simple-workflow stands on three pillars:

- **Harness Engineering**: structural constraints — an asymmetric information firewall between code authors and code judges (the Generator-Evaluator pattern), bounded sub-agent returns, ticket-confined artifacts, and safe-clear `[SW-CHECKPOINT]` markers — enforce quality by architecture rather than by prompt instructions
- **Context Conservation**: the context window is treated as a consumable resource — sub-agents return < 500-token summaries, artifacts live on disk, and state survives compaction
- **Cross-session learning**: evaluation logs are distilled into reusable patterns that future implementations inject into their prompts, so the system gets better at your project the more tickets it completes

These pillars exist because Claude Code is powerful, but its context window is finite — and fragile. Long-running agent sessions face four structural threats:

| Threat | What happens | Structural countermeasure |
|--------|-------------|--------------------------|
| **Loss** | Session boundaries — compaction, exit — discard accumulated understanding | Pre-compact state snapshots, recovery on restart, cross-session learning |
| **Exhaustion** | The window fills up, degrading instruction-following and response quality | Bounded sub-agent returns (< 500 tokens), phase-aware context release |
| **Contamination** | Biasing information leaks into contexts where it distorts judgment | Information firewall + ticket directory confinement (see [Harness Engineering](#harness-engineering)) |
| **Bloat** | Unbounded intermediate output crowds out critical instructions | Artifacts written to files, structured summaries returned to orchestrator |

simple-workflow addresses each threat with architectural constraints that hold regardless of model behavior — not prompt-level instructions that the model might rationalize away. The four sections below describe each pillar: **Context Conservation Protocol** (Loss + Exhaustion), **Harness Engineering** (Contamination + Bloat), the **Knowledge Base** (Loss across sessions), and **Ticket Management** (Contamination across tickets).

### Context Conservation Protocol

Treats the context window as a consumable resource and systematically conserves it.

- **Bounded sub-agent returns**: Each sub-agent launches with a fresh context, writes detailed artifacts to files, and returns only a structured summary (< 500 tokens). Without this bound, multi-round orchestration would accumulate unbounded output and degrade the orchestrator's decision quality
- **Phase-aware context release**: A dedicated recovery skill auto-detects the current phase and recommends the next action. Completed phases live on disk — clear the context and move on
- **Structured state preservation**: Before context compaction, per-ticket state is saved as YAML frontmatter so the recovery skill can resume interrupted work — including mid-implementation loops

### Harness Engineering

A **Generator** writes code, independent **Evaluators** verify it, and failures trigger automatic retry with specific feedback — up to 9 rounds by default (configurable per invocation or per ticket via policy). The information firewall is asymmetric: Evaluators never see the Generator's self-assessment and judge solely from `git diff` and test results, while the Generator does receive Evaluator feedback on retry.

Even though both sides run the same model, **weights × context = output** — by excluding the Generator's trial-and-error history from the Evaluator's context, sunk-cost bias is structurally eliminated rather than merely discouraged by prompt. FAIL-CRITICAL violations halt execution immediately, and after ticket completion evaluation logs feed into the Knowledge Base, closing a cross-session feedback loop.

### Knowledge Base (Cross-Session Learning)

`.simple-workflow/kb/` is an automatically maintained knowledge base. After each completed ticket, evaluation logs are analyzed to extract actionable patterns (common failures, recurring feedback themes), which are persisted as structured entries; at implementation time, relevant entries are injected into the next implementation's prompt, so lessons learned from past tickets inform future ones.

The more tickets you complete in a project, the more project-specific patterns accumulate, and the higher the probability that future implementations pass evaluation on the first round. In effect the system develops project-specific expertise over time — analogous to a human developer becoming more effective the longer they work on a codebase — without fine-tuning the underlying model.

### Ticket Management (State Machine)

`.simple-workflow/backlog/` is a state machine. Tickets transition between states via physical directory moves (`product_backlog/` → `active/` → `blocked/` → `done/`), making state visible, traceable, and greppable — no database required. Each ticket is a directory where every artifact accumulates, providing both an audit trail and contamination prevention: artifacts from one ticket never leak into another's context.

Each ticket carries a `phase-state.yaml` declaring its full lifecycle state. Phase-terminating workflows close their output with a standardized `[SW-CHECKPOINT]` block, signalling that running `/clear` is safe.

> **Manual transitions**: moving tickets between states (e.g. `active/` → `blocked/`) is done with a plain `mv`.

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

## Limitations

- Designed for use with Claude Code CLI. IDE extensions (VS Code, JetBrains) may have limited support for hooks and plugin features.
- Pull-request creation requires GitHub CLI (`gh`) with authentication. Other Git hosting services are not supported.
- Ticket management uses the local filesystem (`.simple-workflow/backlog/`). There is no sync with external issue trackers (Jira, Linear, etc.).
- Sub-agents consume API tokens independently. Large tickets (L/XL) using Opus may result in higher API costs.
- Built-in test/lint detection covers JS, Python, Rust, Go, JVM (Gradle/Maven/sbt), .NET, Ruby, Elixir, Swift, Flutter/Dart, PHP, and Make. For other ecosystems, wrap your test/lint commands in a Makefile (`make test` / `make lint`) or the evaluator falls back to static code analysis only.
- Some recovery paths require interactive mode; running in `claude -p` or CI may stop with an explanatory message rather than complete the recovery.

### Long-session resume

If an automated run ends with a `partial` status before reaching the context-window cap, the model likely self-aborted before Claude Code's auto-Compaction had a chance to fire. State files written to `.simple-workflow/backlog/` enable resumption in a fresh session — rerun the same starting command and the plugin picks up where it left off.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[Apache License 2.0](LICENSE)
