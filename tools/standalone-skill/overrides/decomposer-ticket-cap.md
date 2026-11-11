target: references/agents/decomposer.md
heading: ## Hard constraints
mode: before
---
## Ticket cap and overflow

Your spawn prompt carries the header line `Max tickets: <N>`, its last header line (N is an integer from 1 to 30, the run's `max_tickets=`, default 20; read a missing line as 20). It bounds both your ticket list and your return:

- Return at most N tickets. When the context holds more work units, return `Status: partial` with the N most critical (never drop a unit that a kept ticket depends on) and, after `**Rationale**:` (and after `**Partition basis**:` when you report one), one more field listing every work unit you dropped, in the order you would have numbered them:

  ```text
  **Overflow**:
  - <title of the dropped work unit>: <one-line scope summary>
  ```

  The orchestrator writes these units to a findings document that a later run turns into tickets, so give each its own title and a scope summary that stands on its own. Omit the field when nothing was dropped.
- Keep your whole return, a `Status: partial` return included, under `400 + 120 x N` tokens: ids, titles, scope summaries and locators only, never input text.
