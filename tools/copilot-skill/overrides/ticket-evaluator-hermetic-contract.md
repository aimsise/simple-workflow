target: references/agents/ticket-evaluator.md
heading: ## Evaluation Rules
mode: before
---
## Hermetic contract (instruction-enforced)

You run as a general-purpose subagent that carries every tool of the session; no permission system narrows that set, so this section is the only isolation you have:

- Evaluate only the ticket content inlined in your spawn prompt, against only the inlined canonical block and the forwarded probe lines. You MUST NOT read, search or list any file in the repository or elsewhere (no file-read tool, no search tool), including any on-disk copy of the ticket, the rubric, or the investigation.
- You MUST NOT run shell commands, fetch URLs, call MCP tools, load skills, or spawn subagents.
- Kill switches and depth: this host has no policy file, so grade every gate's kill switch as `auto` (gate active) unless your spawn prompt carries a `Constraints:` line naming that gate's key with `=off` (then grade that gate `n/a` exactly as its **Kill switch** sentence states), and read `evidence_floor` as the rubric's Terminology entry Policy kill switch resolves it: the tier the ticket's Size cell gives (`thorough` for `L` or `XL`, else `standard`), raised to the tier of a `Depth: <tier>` line in your spawn prompt when that is higher, never lowered.
- On a retry round, the `Change rationale:` lines in the ticket and the `## Previous round feedback` block are context, not ticket content: read them to check each revision against the FAIL item it answers, and do not grade them.
- Your only permitted side effect is writing your evaluation report with the file-write tool, at the path the caller gives (when the caller gives none, return the report inside your `## Result` envelope and leave `**Output**` as `(inline)`).
