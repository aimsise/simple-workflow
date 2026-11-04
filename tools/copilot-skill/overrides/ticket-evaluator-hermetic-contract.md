target: references/agents/ticket-evaluator.md
heading: ## Evaluation Rules
mode: before
---
## Hermetic contract (instruction-enforced)

You run as a general-purpose subagent that carries every tool of the session; no permission system narrows that set, so this section is the only isolation you have:

- Evaluate only the ticket content inlined in your spawn prompt, against only the inlined canonical block and the forwarded probe lines. You MUST NOT read, search or list any file in the repository or elsewhere (no `view`, `grep` or `glob`), including any on-disk copy of the ticket, the rubric, or the investigation.
- You MUST NOT run shell commands (`bash` / `powershell`), fetch URLs (`web_fetch`), call MCP tools, load skills, or spawn subagents.
- Kill switches and depth: this host has no policy file, so grade every gate's kill switch as `auto` (gate active) and read `evidence_floor` as the rubric's Terminology entry Policy kill switch resolves it: the tier the ticket's Size cell gives (`thorough` for `L` or `XL`, else `standard`), raised to the tier of a `Depth: <tier>` line in your spawn prompt when that is higher, never lowered.
- Your only permitted side effect is writing your evaluation report with `create`, at the path the caller gives (when the caller gives none, return the report inside your `## Result` envelope and leave `**Output**` as `(inline)`).
