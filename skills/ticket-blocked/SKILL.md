---
name: ticket-blocked
description: >-
  Move one or more ticket directories to .backlog/blocked/.
  Use when tickets are blocked by external dependencies or issues.
disable-model-invocation: true
allowed-tools:
  - "Bash(ls:*)"
  - "Bash(mv:*)"
  - "Bash(mkdir:*)"
argument-hint: "<ticket-slug> [ticket-slug ...] — one or more ticket directory names to move to .backlog/blocked/"
---

Move tickets to blocked: $ARGUMENTS

## Instructions

1. If `$ARGUMENTS` is empty, print "Usage: /ticket-blocked <ticket-slug> [ticket-slug ...]" and stop.
2. Split `$ARGUMENTS` by whitespace to get a list of ticket slugs.
3. For each slug:
   a. Search for a directory matching the slug in `.backlog/product_backlog/`, `.backlog/active/`, `.backlog/done/`.
   b. If found, run `mkdir -p .backlog/blocked && mv <source-path> .backlog/blocked/<slug>`.
   c. Print "Moved: <source-path> -> .backlog/blocked/<slug>".
   d. If not found in any location, print "Not found: <slug>" as an error.
4. Print a summary: number of tickets moved, number not found.
