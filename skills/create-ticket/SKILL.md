---
name: create-ticket
description: >-
  Create a structured ticket with scope analysis, acceptance
  criteria, and Claude Code workflow recommendations. Use when defining
  new work items or breaking down features into tickets.
allowed-tools:
  - Agent
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - AskUserQuestion
argument-hint: "<ticket description>"
---

# /create-ticket

Ticket description: $ARGUMENTS

## Instructions

Generate a structured ticket from the given ticket description.

### Phase 1: Investigation (researcher agent)

Use the researcher agent to investigate:

1. Source code related to the ticket description
2. Affected files and line ranges
3. Existing test coverage
4. Related documentation
5. Dependencies (relationships with other tickets)

### Phase 2: Planning (planner agent)

Use the planner agent to design:

1. Ticket structure (Background, Scope, Acceptance Criteria, Implementation Notes)
2. Appropriate category (Security / CodeQuality / Doc / DevOps / Community) and size (S/M/L/XL)
3. Workflow recommendations based on category x size, referencing `references/workflow-patterns.md`

### Phase 3: Ticket output

Read `references/ticket-template.md` for the output format.

After generating the ticket content:

1. Derive a `{slug}` from the ticket title using kebab-case (e.g., "Add User Auth" -> `add-user-auth`).
2. Create the directory `.backlog/product_backlog/{slug}/` if it does not exist.
3. Write the ticket to `.backlog/product_backlog/{slug}/ticket.md`.

### Workflow selection guide

Identify available skills and agents by scanning `.claude/skills/` and `.claude/agents/` (if present),
listing installed plugin skills/agents, and referencing patterns in `references/workflow-patterns.md` to design the workflow.

**Category-specific guidelines**:
- **Security**: Wrap with `/security-scan` before and after. Spec-first with documentation leading.
- **CodeQuality**: Use `/refactor` skill. Guarantee no behavior changes.
- **Doc**: Use doc-writer agent.
- **DevOps**: CI/CD configs are hard to test; design carefully with `/plan2doc`.
- **Community**: Reference industry-standard templates.

**Size-specific guidelines**:
- **S**: `/plan2doc` optional. Direct implementation.
- **M**: `/plan2doc` recommended.
- **L/XL**: `/plan2doc` required. Incremental implementation recommended.
