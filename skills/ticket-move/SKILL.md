---
name: ticket-move
description: >-
  Move one or more ticket directories to a target backlog state
  (active/blocked/done). Replaces /ticket-active, /ticket-blocked,
  and /ticket-done with a single unified entry point.
disable-model-invocation: true
allowed-tools:
  - "Bash(ls:*)"
  - "Bash(mv:*)"
  - "Bash(mkdir:*)"
argument-hint: "<ticket-slug> [<ticket-slug>...] <state:active|blocked|done>"
---

Move tickets to target state: $ARGUMENTS

## Instructions

### Argument Parsing

1. If `$ARGUMENTS` is empty, print the usage message and stop:
   ```
   Usage: /ticket-move <slug> [<slug>...] <state:active|blocked|done>
   ```
2. Split `$ARGUMENTS` by whitespace into a list of tokens.
3. If the list contains only one token, print the following error and stop:
   ```
   Error: missing state argument.
   Usage: /ticket-move <slug> [<slug>...] <state:active|blocked|done>
   ```
4. Extract the **last token** as `state`.
5. If `state` is not one of `active`, `blocked`, or `done`, print the following error and stop:
   ```
   Error: invalid state "<state>". Valid values: active, blocked, done.
   Usage: /ticket-move <slug> [<slug>...] <state:active|blocked|done>
   ```
6. Treat all remaining tokens (everything except the last) as the list of `slugs`.

### Per-Slug Processing

For each slug in `slugs`:

1. Determine the **search paths** — all four known backlog directories except the destination:
   - `.backlog/product_backlog/`
   - `.backlog/active/` (skip when `state` is `active`)
   - `.backlog/blocked/` (skip when `state` is `blocked`)
   - `.backlog/done/` (skip when `state` is `done`)

2. Search each search path for a directory whose name matches the slug exactly. Use `ls` to list the contents of each search path and check for a match.

3. **If found:**
   - Run `mkdir -p .backlog/<state>` to ensure the destination directory exists.
   - Run `mv <source-path> .backlog/<state>/<slug>` to move the ticket.
   - Print: `Moved: <source-path> → .backlog/<state>/<slug>`

4. **If not found in any search path:**
   - Print: `Not found: <slug>`
   - Continue to the next slug.

### Summary Output

After processing all slugs, print a summary that includes:
- Number of tickets successfully moved
- Number of tickets not found

Example:
```
Summary: 2 moved, 1 not found.
```

## Error Handling

| Situation | Behavior |
|---|---|
| `$ARGUMENTS` is empty | Print usage and stop |
| Only one token provided | Print "missing state" error and usage, then stop |
| Last token is not `active`/`blocked`/`done` | Print "invalid state" error and usage, then stop |
| A slug is not found in any search path | Print "Not found: <slug>" and continue |
| All slugs not found | Print summary (0 moved, N not found) and exit 0 |
