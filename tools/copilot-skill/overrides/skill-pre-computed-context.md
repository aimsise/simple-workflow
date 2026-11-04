target: SKILL.md
heading: ## Pre-computed Context
mode: replace
---
## Pre-computed Context

This host runs no command while the skill loads, so compute the three context lines below yourself, once, before Phase 1, and reuse them verbatim for the rest of the run:

1. `UTC time:` run `date -u +%Y-%m-%dT%H:%M:%SZ` (via `bash`; on Windows, the `powershell` equivalent).
2. `Available user skills:` list the skill directory names under the project skill roots `.github/skills/`, `.claude/skills/` and `.agents/skills/` and the personal skill roots `~/.copilot/skills/` and `~/.agents/skills/` (each root that exists; for example `ls -1 <root>`). Merge, sort, de-duplicate and join the names with `,`. Write `(none)` when no root lists a skill. Record names only, never a path.
3. `Available MCP servers:` read the server names from the MCP configuration this surface uses (e.g. `.github/copilot/mcp.json`, or the IDE's `mcp.json` / the CLI's MCP configuration; illustrative only). Sort, de-duplicate and join them with `,`; write `(none)` when no server is configured or no configuration is readable.

Write each line as `<label> <value>` (for example `Available user skills: (none)`). Both probe lines are forwarded verbatim to the planner (Phase 3) and to the ticket-evaluator (Phase 4, initial and retry): Gate 6.5 grades the ticket against exactly these draft-time lines, so never recompute or edit them between spawns.
