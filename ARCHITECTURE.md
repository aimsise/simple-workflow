# simple-workflow architecture

This document explains the design philosophy of simple-workflow in detail. For the elevator-pitch summary and the three-pillar overview, see [README.md](README.md). For implementation details — which skills, sub-agents, and hooks execute the workflow — browse `skills/`, `agents/`, and `hooks/` in this repository.

## Context Conservation Protocol

Treats the context window as a consumable resource and systematically conserves it.

- **Bounded sub-agent returns**: Each sub-agent launches with a fresh context, writes detailed artifacts to files, and returns only a structured summary (< 500 tokens). Without this bound, multi-round orchestration would accumulate unbounded output and degrade the orchestrator's decision quality.
- **Phase-aware context release**: A dedicated recovery skill auto-detects the current phase and recommends the next action. Completed phases live on disk — clear the context and move on.
- **Structured state preservation**: Before context compaction, per-ticket state is saved as YAML frontmatter so the recovery skill can resume interrupted work — including mid-implementation loops.
- **Proactive auto-`/compact` at ticket boundaries**: long-running `/autopilot` pipelines fire `/compact` automatically at each ticket boundary (default ON inside autopilot) so the conversation does not exhaust its window between tickets. Two hooks coordinate the injection — `hooks/pre-next-scout-auto-compact.sh` (primary) and `hooks/post-ship-state-auto-compact.sh` (safety net) — both routed through `hooks/lib/inject-keys.sh` (tmux / GNU screen / kitty / WezTerm / iTerm2 backends). After compaction `hooks/session-start.sh` re-injects `/autopilot <slug>` and the resume contract picks up. Opt out with `SW_AUTO_COMPACT_ON_SHIP_MODE=off`; `metric-only` logs intent without injecting; Apple Terminal / Windows / no-multiplexer environments are silent no-ops.

## Harness Engineering

A **Generator** writes code, independent **Evaluators** verify it, and failures trigger automatic retry with specific feedback — up to 9 rounds by default (configurable per invocation or per ticket via policy). The information firewall is asymmetric: Evaluators never see the Generator's self-assessment and judge solely from `git diff` and test results, while the Generator does receive Evaluator feedback on retry.

Even though both sides run the same model, **weights × context = output** — by excluding the Generator's trial-and-error history from the Evaluator's context, sunk-cost bias is structurally eliminated rather than merely discouraged by prompt. FAIL-CRITICAL violations halt execution immediately, and after ticket completion evaluation logs feed into the Knowledge Base, closing a cross-session feedback loop.

## Knowledge Base (Cross-Session Learning)

`.simple-workflow/kb/` is an automatically maintained knowledge base. After each completed ticket, evaluation logs are analyzed to extract actionable patterns (common failures, recurring feedback themes), which are persisted as structured entries; at implementation time, relevant entries are injected into the next implementation's prompt, so lessons learned from past tickets inform future ones.

The more tickets you complete in a project, the more project-specific patterns accumulate, and the higher the probability that future implementations pass evaluation on the first round. In effect the system develops project-specific expertise over time — analogous to a human developer becoming more effective the longer they work on a codebase — without fine-tuning the underlying model.

## Ticket Management (State Machine)

`.simple-workflow/backlog/` is a state machine. Tickets transition between states via physical directory moves (`product_backlog/` → `active/` → `blocked/` → `done/`), making state visible, traceable, and greppable — no database required. Each ticket is a directory where every artifact accumulates, providing both an audit trail and contamination prevention: artifacts from one ticket never leak into another's context.

Each ticket carries a `phase-state.yaml` declaring its full lifecycle state. Phase-terminating workflows close their output with a standardized `[SW-CHECKPOINT]` block, signalling that running `/clear` is safe.

> **Manual transitions**: moving tickets between states (e.g. `active/` → `blocked/`) is done with a plain `mv`.
