target: references/spec-decomposer-input.md
heading: ## Form A — `findings_doc`
mode: before
---
## Header `Max tickets:` (both forms)

Every decomposer spawn, in either form, carries one more header line, `Max tickets: <N>`, as its last header line: in Form A right after `Input form: findings_doc`, in Form B after `Parent slug:` and, when present, `Dossier role:`. N is the run's `max_tickets=` (SKILL.md Argument Parsing), an integer from 1 to 30, default 20. The decomposer returns at most N tickets (`Status: partial` with an `**Overflow**:` list of the dropped work units, each with its title and a one-line scope summary, when the context holds more) and keeps its return under `400 + 120 x N` tokens (`references/agents/decomposer.md`, `## Ticket cap and overflow`); the orchestrator writes the dropped units to `{scratch}/overflow-findings.md` (SKILL.md Step D-4).
