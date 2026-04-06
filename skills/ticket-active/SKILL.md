---
name: ticket-active
description: >-
  Move one or more ticket directories to .backlog/active/.
  Use to resume work on tickets from backlog, blocked, or done states.
disable-model-invocation: true
allowed-tools:
  - "Bash(ls:*)"
  - "Bash(mv:*)"
  - "Bash(mkdir:*)"
argument-hint: "<ticket-slug> [ticket-slug ...] — one or more ticket directory names to move to .backlog/active/"
---

Move tickets to active: $ARGUMENTS

## Instructions

1. If `$ARGUMENTS` is empty, print "Usage: /ticket-active <ticket-slug> [ticket-slug ...]" and stop.
2. Split `$ARGUMENTS` by whitespace to get a list of ticket slugs.
3. For each slug:
   a. Search for a directory matching the slug in `.backlog/product_backlog/`, `.backlog/blocked/`, `.backlog/done/`.
   b. If found, run `mkdir -p .backlog/active && mv <source-path> .backlog/active/<slug>`.
   c. Print "Moved: <source-path> -> .backlog/active/<slug>".
   d. If not found in any location, print "Not found: <slug>" as an error.
4. Print a summary: number of tickets moved, number not found.
