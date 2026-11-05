target: SKILL.md
heading: ## Pre-computed Context
mode: replace
---
## Pre-computed Context

This host runs no command while the skill loads, so compute the values below yourself, once, before Phase 1, and reuse them verbatim for the rest of the run:

1. `UTC time:` run `date -u +%Y-%m-%dT%H:%M:%SZ` with the shell tool (tool roles: Host notes).
2. `Available user skills:` list the skill directory names under the project skill roots `.github/skills/`, `.claude/skills/` and `.agents/skills/` and the personal skill roots this host reads (such as `~/.agents/skills/`, `~/.claude/skills/` or `~/.copilot/skills/`; each root that exists; for example `ls -1 <root>`). Merge, sort, de-duplicate and join the names with `,`. Write `(none)` when no root lists a skill. Record names only, never a path.
3. `Available MCP servers:` take the server names from the live tool inventory this session shows (the host lists every MCP tool together with the server it belongs to; the `mcp:` destination preflight reads the same inventory). Sort, de-duplicate and join them with `,`; write `(none)` when the inventory shows no MCP tool.
4. `{skill_root}`: the directory that contains this skill's `SKILL.md`, found by checking, in this order, `.github/skills/create-ticket/`, `.claude/skills/create-ticket/`, `.agents/skills/create-ticket/`, then `~/.agents/skills/create-ticket/` and the personal skill root this host reads (for example `~/.claude/skills/create-ticket/` or `~/.copilot/skills/create-ticket/`), each without the trailing slash. Record it exactly as found, repository-relative or `~`-prefixed, never expanded to an absolute path. When none of them holds it, use the directory this skill was loaded from, written the same way. Then `{rubric_path}` = `{skill_root}/references/ac-quality-criteria.md`, and the grading file is `{skill_root}/references/ac-quality-grading.md`.

Write the first three as `<label> <value>` lines (for example `Available user skills: (none)`). Both probe lines are forwarded verbatim to the planner (Phase 3) and to the ticket-evaluator (Phase 4, initial and retry): Gate 6.5 grades the ticket against exactly these draft-time lines, so never recompute or edit them between spawns.
