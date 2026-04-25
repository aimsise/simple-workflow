---
name: investigate
description: >-
  Investigate codebase topics via researcher agent. Saves structured findings
  to .simple-workflow/docs/research/. Use when exploring code, tracking dependencies, or
  understanding architecture.
context: fork
agent: researcher
argument-hint: "<topic or question to investigate>"
---

Investigate the following topic: $ARGUMENTS

Current repo state:
!`git status --short | head -20`

## Instructions

1. Parse `$ARGUMENTS` for `(ticket-dir: <path>)` to determine the output destination:
   - If `ticket-dir` is specified: output findings to `{ticket-dir}/investigation.md`
   - If `ticket-dir` is not specified: search `.simple-workflow/backlog/product_backlog/` and `.simple-workflow/backlog/active/` using Glob for directories matching `$ARGUMENTS` keywords. If a match is found in `product_backlog`, move it to `active` (`mv .simple-workflow/backlog/product_backlog/{ticket-dir} .simple-workflow/backlog/active/{ticket-dir}`) and use `.simple-workflow/backlog/active/{ticket-dir}` as the ticket-dir. If already in `active`, use it as-is.
   - If no ticket-dir and no matching ticket found: use the default `.simple-workflow/docs/research/` directory
2. Investigate this topic thoroughly
3. Use Grep/Glob to find relevant code, then Read to understand it
4. If investigating a ticket, include the ticket's Size (S/M/L/XL) in the research file header
5. Write ALL detailed findings to the determined output path (either `{ticket-dir}/investigation.md` or `.simple-workflow/docs/research/{topic}.md`). Tell the researcher agent the exact output file path.
6. Return a brief executive summary with the output file path
