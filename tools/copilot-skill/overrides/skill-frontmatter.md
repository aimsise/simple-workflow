target: SKILL.md
heading: (frontmatter)
mode: replace
---
---
name: create-ticket
description: >-
  Do not auto-invoke. Only invoke when called by name. Use when (1) user
  types `/create-ticket`, or (2) user provides description / `brief=<path>` /
  `findings=<path>` asking for structured, independently evaluated tickets,
  optionally with `destination=` (a local directory, a ticket platform
  reached through an MCP server, or an HTTP API). Triggers on "create a
  ticket", "/create-ticket", "draft a ticket".
compatibility: Any agent host that loads SKILL.md skills and offers file read, file write, file edit, text and file-pattern search, a POSIX shell and a subagent tool (without a subagent tool the skill runs degraded, every verdict SELF-EVALUATED; without an ask-user tool it runs non-interactively). Host notes map each tool role to the host's own tool.
argument-hint: "<ticket description> | brief=<path> | findings=<path> [destination=local:<dir> | mcp:<server>[/<tool>] | api:<url>] [depth=<tier>] [constraint_<key>=off]"
metadata:
  source: generated skill; do not edit by hand
  source-version: "@SOURCE_VERSION@"
  source-commit: "@SOURCE_COMMIT@"
---
