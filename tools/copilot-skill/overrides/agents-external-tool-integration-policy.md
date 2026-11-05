target: references/agents/researcher.md references/agents/decomposer.md references/agents/planner.md
heading: ## External Tool Integration Policy
mode: replace
---
## External Tool Integration Policy

- **Use available utility skills.** When a utility skill named in your spawn prompt (or listed on its `Available user skills:` line) materially advances the work (e.g. a browser-automation skill for UI checks, a documentation skill for API lookups; illustrative only), load it the way this host offers skills (for example by reading its `SKILL.md` under the skill root that lists it) and follow it. Do not load skills speculatively; only when they help the task at hand.
- **Never run orchestrator skills.** You MUST NOT run `create-ticket`, or any other skill that orchestrates tickets, plans, commits or pull requests, from inside this subagent. The orchestrator that spawned you owns that flow; recursing into it from a subagent is a contract violation.
- **Degrade gracefully.** If no relevant skill is available, fall back to your in-house capabilities (the file-read tool, the search tools, read-only shell commands, in-context reasoning) and do NOT fail your task over a missing optional tool.
