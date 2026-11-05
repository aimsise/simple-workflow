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
  optionally with `source=` inputs (documents, `.xlsx` workbooks, a directory,
  a read-only MCP tool result, an HTTP document) and `destination=` (a local directory, a ticket platform
  reached through an MCP server, or an HTTP API); the input and the output
  may also be stated in prose after the name. Triggers on "create a
  ticket", "/create-ticket", "draft a ticket".
compatibility: Any agent host that loads SKILL.md skills and offers file read, file write, file edit, text and file-pattern search, a POSIX shell and a subagent tool (Python 3 on that shell only for .xlsx sources; without a subagent tool the skill runs degraded, every verdict SELF-EVALUATED; without an ask-user tool it runs non-interactively). Host notes map each tool role to the host's own tool.
argument-hint: "<ticket description> | brief=<path> | findings=<path> [source=<spec> ...] [destination=local:<dir> | mcp:<server>[/<tool>] | api:<url>] [parent=<id>] [confirm=yes] [depth=<tier>] [constraint_<key>=off]"
metadata:
  source: generated skill; do not edit by hand
  source-version: "@SOURCE_VERSION@"
  source-commit: "@SOURCE_COMMIT@"
---
