target: SKILL.md
heading: (frontmatter)
mode: replace
---
---
name: create-ticket
description: >-
  Do not auto-invoke. Invoke only when the user names this skill: the
  request starts with `/create-ticket` (or the host's own form of calling a
  skill by name) followed by a ticket description, `brief=<path>` or
  `findings=<path>`, optionally with `source=` inputs (documents, `.xlsx`
  workbooks, PDF and image files, a directory, a read-only MCP tool result,
  an HTTP document, a page or item reached through a signed-in command-line
  client or a browser-automation tool of the session) and `destination=` (a
  local directory, a ticket platform reached through an MCP server, its
  command-line client or its create form in the browser, or an HTTP API);
  the input and the output may also be stated in prose after the name. A request about tickets that
  does not name this skill is never a trigger.
compatibility: Any agent host that loads SKILL.md skills and offers file read, file write, file edit, text and file-pattern search, a POSIX shell and a subagent tool (Python 3 on that shell only for .xlsx sources; without a subagent tool the skill runs degraded, every verdict SELF-EVALUATED; without an ask-user tool it runs non-interactively; a browser-automation tool is used when present and never required). Host notes map each tool role to the host's own tool.
argument-hint: "<ticket description> | brief=<path> | findings=<path> [source=<spec> ...] [destination=local:<dir> | mcp:<server>[/<tool>] | api:<url> | browser:<url> | cli:<command>] [parent=<id>] [confirm=yes] [depth=<tier>] [rounds=<N>] [max_tickets=<N>] [render=auto|off|excel|soffice] [constraint_<key>=off]"
metadata:
  source: generated skill; do not edit by hand
  source-version: "@SOURCE_VERSION@"
  source-commit: "@SOURCE_COMMIT@"
---
