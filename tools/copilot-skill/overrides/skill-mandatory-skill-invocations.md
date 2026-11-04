target: SKILL.md
heading: ## Mandatory Skill Invocations
mode: replace
---
## Mandatory Skill Invocations

`/create-ticket` MUST delegate to each of the four roles below. Each role MUST be run as a separate `task` subagent (`agent_type: general-purpose`) whose prompt is the full body of `references/agents/<name>.md` followed by the input described in `references/agent-spawn-prompts.md`. Direct model output bypasses the independent layers — a contract violation.

| Role | Prompt body | When | Skip consequence |
|---|---|---|---|
| `researcher` | `references/agents/researcher.md` | Phase 1 — bare always; brief unless a freshness-validated `{ticket-dir}/investigation.md` is reused per [references/agent-spawn-prompts.md](references/agent-spawn-prompts.md); findings skips (findings doc IS the investigation) | No findings; planner falls back to model assumptions. Freshness-validated brief reuse OK; stale reuse forbidden |
| `decomposer` | `references/agents/decomposer.md` | All modes — after Phase 1 (+Socratic), before planner. Caller picks `Input form: findings_doc` or `Input form: scope_context` per [references/spec-decomposer-input.md](references/spec-decomposer-input.md) | No dependency graph; cannot partition; run cannot proceed in any mode |
| `planner` | `references/agents/planner.md` | Phase 3 — after Phase 1 (+optional Phase 2) | No structured draft; ticket-evaluator FAILs quality gate |
| `ticket-evaluator` | `references/agents/ticket-evaluator.md` | Phase 4 per-ticket — after Phase 3 | No quality gate; ticket "NOT EVALUATED" with possibly untestable ACs |

**Binding rules**: `MUST invoke` each role above as its own `task` subagent. `NEVER bypass` via direct file ops or self-assessment. `Fail the task` if a `task` spawn for a mandatory role cannot complete. Each return capped under 500 tokens (Context Conservation Protocol in `references/agents/<name>.md`).

**Degraded branch (no subagents)**: If the `task` tool is unavailable on this surface, perform the role inline in this conversation and stamp the ticket `Quality: SELF-EVALUATED` so the loss of evaluator independence is visible. Concretely: follow the role's `references/agents/<name>.md` body yourself, keep each role's output as a separate artifact shaped exactly like the subagent return, add a `| Quality | SELF-EVALUATED |` row to every ticket's field table, and report `SELF-EVALUATED` (never `PASS`) as the quality result in Step W-10. The branch applies only when the surface offers no `task` tool at all; a `task` spawn that is attempted and fails still fails the task.
