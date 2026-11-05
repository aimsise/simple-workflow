target: SKILL.md
heading: ## Mandatory Skill Invocations
mode: replace
---
## Mandatory role invocations

`/create-ticket` MUST delegate to each of the four roles below. Each role MUST be run as a separate subagent through the subagent tool (the host's general-purpose, default agent type; no custom agent definition) whose prompt is the full body of `references/agents/<name>.md` followed by the input described in `references/agent-spawn-prompts.md`. Direct model output bypasses the independent layers — a contract violation.

| Role | Prompt body | When | Skip consequence |
|---|---|---|---|
| `researcher` | `references/agents/researcher.md` | Phase 1 — bare and brief always (output in the run scratch directory, per [references/agent-spawn-prompts.md](references/agent-spawn-prompts.md)); findings skips (findings doc IS the investigation) | No findings; planner falls back to model assumptions |
| `decomposer` | `references/agents/decomposer.md` | All modes — after Phase 1 (+Socratic), before planner. Caller picks `Input form: findings_doc` or `Input form: scope_context` per [references/spec-decomposer-input.md](references/spec-decomposer-input.md) | No dependency graph; cannot partition; run cannot proceed in any mode |
| `planner` | `references/agents/planner.md` | Phase 3 — after Phase 1 (+optional Phase 2) | No structured draft; ticket-evaluator FAILs quality gate |
| `ticket-evaluator` | `references/agents/ticket-evaluator.md` | Phase 4 per-ticket — after Phase 3 | No quality gate: the run fails and nothing is delivered |

**Binding rules**: `MUST invoke` each role above as its own subagent. `NEVER bypass` via direct file ops or self-assessment. `Fail the task` if a subagent spawn for a mandatory role cannot complete. Each return capped under 500 tokens (decomposer: 1000; Context Conservation Protocol in `references/agents/<name>.md`).

**Degraded branch (no subagents)**: If this host offers no subagent tool, perform the role inline in this conversation and give every ticket the verdict `SELF-EVALUATED` so the loss of evaluator independence is visible. Concretely: follow the role's `references/agents/<name>.md` body yourself, keep each role's output as a separate artifact shaped exactly like the subagent return, record `SELF-EVALUATED` (never `PASS`) as each ticket's verdict, which Step DL-2 writes into its `Quality` row once and Step DL-5 reports. The branch applies only when the host offers no subagent tool at all; a subagent spawn that is attempted and fails still fails the task.
