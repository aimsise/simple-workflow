target: references/agent-spawn-prompts.md
heading: ## Phase 1: Investigation (researcher agent)
mode: before
---
## Rules for every spawn prompt

- Every spawn prompt this skill builds (researcher, decomposer, planner, ticket-evaluator, initial and retry) carries this rule verbatim: "Never write an absolute home path, an environment variable's value, or any credential into your output file, the ticket or your return envelope; refer to files by their repository-relative path." Each agent body repeats it under `## Output hygiene (paths and secrets)`.
- When the request text carried `depth=<tier>` (SKILL.md Argument Parsing), every planner and ticket-evaluator spawn prompt carries the line `Depth: <tier>`; either way, both resolve `evidence_floor` from the ticket's Size (`thorough` for `L` or `XL`, else `standard`), raised to the `Depth:` tier when that is higher, never lowered (rubric Terminology, Policy kill switch).
