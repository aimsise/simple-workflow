---
name: ticket-done
description: >-
  Move one or more ticket directories to .backlog/done/.
  Use when tickets are completed.
disable-model-invocation: true
allowed-tools:
  - "Bash(ls:*)"
  - "Bash(mv:*)"
  - "Bash(mkdir:*)"
argument-hint: "<ticket-slug> [ticket-slug ...] — one or more ticket directory names to move to .backlog/done/"
---

Move tickets to done: $ARGUMENTS

## Instructions

1. If `$ARGUMENTS` is empty, print "Usage: /ticket-done <ticket-slug> [ticket-slug ...]" and stop.
2. Split `$ARGUMENTS` by whitespace to get a list of ticket slugs.
3. For each slug:
   a. Search for a directory matching the slug in `.backlog/product_backlog/`, `.backlog/active/`, `.backlog/blocked/`.
   b. If found, run `mkdir -p .backlog/done && mv <source-path> .backlog/done/<slug>`.
   c. Print "Moved: <source-path> -> .backlog/done/<slug>".
   d. If not found in any location, print "Not found: <slug>" as an error.
4. Print a summary: number of tickets moved, number not found.
