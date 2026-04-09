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
disable-model-invocation: true
argument-hint: "<ticket description>"
---

## Pre-computed Context

Workflow patterns:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/workflow-patterns.md" 2>/dev/null || echo "[WARNING: workflow-patterns.md not found]"`

Ticket template:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/ticket-template.md" 2>/dev/null || echo "[WARNING: ticket-template.md not found]"`

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

### Phase 2: Socratic Refinement

Before drafting the ticket, refine the scope through targeted questions.

1. Analyze the researcher's findings from Phase 1
2. Identify unclear points in the following areas:
   - **Scope boundaries**: Related functionality that may or may not be included
   - **Priority**: When multiple concerns exist, which takes precedence
   - **Edge cases**: Boundary conditions or error cases discovered during investigation
   - **Constraints**: Performance, security, or backward compatibility requirements
3. Use AskUserQuestion to ask up to 3 targeted questions (multiple questions in a single call)
4. Save the user's answers for inclusion in the Phase 3 planner prompt

Note: If the investigation results provide sufficient clarity (e.g., a simple S-size change with obvious scope), skip questioning and proceed directly to Phase 3.

### Phase 3: Ticket Draft (planner agent)

Use the planner agent to design:

1. Ticket structure (Background, Scope, Acceptance Criteria, Implementation Notes)
2. Appropriate category (Security / CodeQuality / Doc / DevOps / Community) and size (S/M/L/XL)
3. Workflow recommendations based on category x size, using the workflow patterns from Pre-computed Context above

Provide the planner agent with the following additional context:
- User's answers from Phase 2 (scope decisions, priority, edge cases, constraints)
- "Each Acceptance Criterion will be evaluated by an independent evaluator against these quality gates: Testability (objectively verifiable with PASS/FAIL), Unambiguity (only one interpretation possible). AC that are not testable or ambiguous will be rejected."

### Phase 4: Ticket Evaluation

Evaluate the ticket quality using the ticket-evaluator agent.

1. Read the ticket file generated in Phase 3 (`.backlog/product_backlog/{slug}/ticket.md`)
2. Spawn the **ticket-evaluator** agent with the ticket content
3. Decision:
   - **Status: PASS** → proceed to Phase 5
   - **Status: FAIL** →
     a. Save the evaluator's Feedback
     b. Re-spawn the **planner** agent with:
        - Original ticket content
        - Evaluator's Feedback (all FAIL items with specific improvement suggestions)
        - Instruction: "For each FAIL item you revise, prepend a 'Change rationale: [why this revision addresses the feedback]' comment above the revised section. This rationale will be reviewed by the evaluator to verify the fix is intentional and correct."
     c. Re-spawn the **ticket-evaluator** agent to evaluate the revised ticket
     d. Max 2 rounds (initial evaluation + 1 revision). If still FAIL after 2 rounds:
        - Use AskUserQuestion to present the remaining FAIL gates to the user
        - Ask: "The ticket has unresolved quality issues: [list FAIL gates and their issues]. Proceed with this ticket anyway, or stop to revise manually?"
        - If user chooses to proceed → continue to Phase 5 with remaining issues noted in the summary
        - If user chooses to stop → print the ticket file path and remaining issues, then stop

### Phase 5: Output

Use the ticket template from Pre-computed Context above for the output format.

After generating the ticket content:

1. Derive a `{slug}` from the ticket title using kebab-case (e.g., "Add User Auth" -> `add-user-auth`).
2. Create the directory `.backlog/product_backlog/{slug}/` if it does not exist.
3. Write the ticket to `.backlog/product_backlog/{slug}/ticket.md`.

After writing the ticket, print a summary:
- Ticket file path
- Category, Size
- Number of Acceptance Criteria
- Quality evaluation result (PASS / FAIL with remaining issues if any)
- Recommended workflow: `/scout → /impl → /ship`

### Workflow selection guide

Identify available skills and agents by scanning `.claude/skills/` and `.claude/agents/` (if present),
listing installed plugin skills/agents, and using the workflow patterns from Pre-computed Context above to design the workflow.

**Category-specific guidelines**:
- **Security**: Wrap with `/audit only_security_scan=true` before and after. Spec-first with documentation leading.
- **CodeQuality**: Use `/refactor` skill. Guarantee no behavior changes.
- **Doc**: Use `/impl` with a doc-focused plan.
- **DevOps**: CI/CD configs are hard to test; design carefully with `/plan2doc`.
- **Community**: Reference industry-standard templates.

**Size-specific guidelines**:
- **S**: `/plan2doc` optional. Direct implementation.
- **M**: `/plan2doc` recommended.
- **L/XL**: `/plan2doc` required. Incremental implementation recommended.

## Error Handling

- **Empty arguments**: Print "Usage: /create-ticket <ticket description>" and stop.
- **Researcher failure**: Report error and stop.
- **Planner failure**: Report error and stop.
- **Ticket-evaluator failure**: Output ticket without evaluation. Display "Quality: NOT EVALUATED" in summary.
- **2 rounds FAIL**: Present remaining issues to user via AskUserQuestion. Proceed only with user confirmation. If user declines, stop and print ticket path for manual editing.
