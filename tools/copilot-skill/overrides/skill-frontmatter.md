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
compatibility: GitHub Copilot CLI (tool names as the CLI lists them); other Copilot surfaces with equivalent read / write / shell / subagent / ask-user tools, mapping the names.
argument-hint: "<ticket description> | brief=<path> | findings=<path> [destination=local:<dir> | mcp:<server>[/<tool>] | api:<url>] [depth=<tier>] [constraint_<key>=off]"
metadata:
  source: generated skill; do not edit by hand
  source-version: "@SOURCE_VERSION@"
  source-commit: "@SOURCE_COMMIT@"
---
