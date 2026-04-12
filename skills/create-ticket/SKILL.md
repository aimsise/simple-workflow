---
name: create-ticket
description: >-
  Create a structured ticket with scope analysis, acceptance
  criteria, and Claude Code workflow recommendations. Use when defining
  new work items or breaking down features into tickets.
allowed-tools:
  # Claude Code
  - Agent
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - AskUserQuestion
  # Copilot CLI
  - task
  - view
  - glob
  - grep
  - create
  - edit
  - ask_user
disable-model-invocation: true
argument-hint: "<ticket description> [brief=<path>]"
---

## Pre-computed Context

Workflow patterns:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/workflow-patterns.md" 2>/dev/null || echo "[WARNING: workflow-patterns.md not found]"`

Ticket template:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/ticket-template.md" 2>/dev/null || echo "[WARNING: ticket-template.md not found]"`

# /create-ticket

Ticket description: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS` for the optional `brief=<path>` parameter:
- If `brief=<path>` is present, extract the path and remove it from the ticket description.
- If the brief file path does not exist, print "ERROR: Brief file not found at <path>" and stop.
- If `brief=<path>` is not present, proceed with the ticket description as-is.

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

**Brief mode**: If a `brief=<path>` parameter was provided, skip Phase 2 entirely. The brief document contains all necessary context gathered through a prior structured interview. Proceed directly to Phase 3 with the brief content.

Before drafting the ticket, refine the scope through targeted questions.

1. Analyze the researcher's findings from Phase 1
2. Identify unclear points in the following areas:
   - **Scope boundaries**: Related functionality that may or may not be included
   - **Priority**: When multiple concerns exist, which takes precedence
   - **Edge cases**: Boundary conditions or error cases discovered during investigation
   - **Constraints**: Performance, security, or backward compatibility requirements
3. Use AskUserQuestion to ask up to 3 targeted questions (multiple questions in a single call)
   - **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), skip Phase 2 entirely and proceed directly to Phase 3 with the researcher's findings only. Note "Phase 2 skipped (non-interactive mode)" in the final summary so the user knows refinement did not happen. Do NOT hang waiting for input.
4. Save the user's answers for inclusion in the Phase 3 planner prompt

Note: If the investigation results provide sufficient clarity (e.g., a simple S-size change with obvious scope), skip questioning and proceed directly to Phase 3.

### Phase 3: Ticket Draft (planner agent)

Use the planner agent to design:

1. Ticket structure (Background, Scope, Acceptance Criteria, Implementation Notes)
2. Appropriate category (Security / CodeQuality / Doc / DevOps / Community) and size (S/M/L/XL)
3. Workflow recommendations based on category x size, using the workflow patterns from Pre-computed Context above

Provide the planner agent with the following additional context:
- User's answers from Phase 2 (scope decisions, priority, edge cases, constraints)
- If brief was provided: Full brief document content (replaces user's answers from Phase 2)
- "Each Acceptance Criterion will be evaluated by an independent evaluator against these quality gates: Testability (objectively verifiable with PASS/FAIL), Unambiguity (only one interpretation possible). AC that are not testable or ambiguous will be rejected."

#### Split Judgment

Instruct the planner agent to evaluate whether the ticket should be split into multiple tickets:

- **Split criteria**: Size >= M **and** the Acceptance Criteria can be grouped into 2 or more independent work units (no inter-AC dependencies within the same group).
- **Split quality guardrails**:
  - Each sub-ticket must be at least Size S with 2 or more Acceptance Criteria. Do not create a ticket with only 1 AC.
  - The purpose of splitting is to create **independently deployable and verifiable work units**, not to mechanically distribute ACs. Each sub-ticket must represent a coherent piece of functionality.
  - The planner must output a **Split Rationale** explaining why the split is justified (e.g., "These ACs form an independent feature boundary" or "This group can be deployed and tested without the others").
  - If no split candidate satisfies all of the above guardrails, fall back to **N = 1** (do not split). Forcing an invalid split is worse than keeping a larger single ticket.
- **When splitting (N > 1)**: The planner outputs each sub-ticket draft individually, each with its own title, category, size, scope, and Acceptance Criteria. Each sub-ticket must be self-contained and independently implementable.
- **When not splitting (N = 1)**: The planner outputs a single ticket draft exactly as before (no change from existing behavior).

### Phase 4: Ticket Evaluation

Evaluate the ticket quality using the ticket-evaluator agent.

**When split (N > 1)**: Execute the evaluation process below **independently for each sub-ticket**. Each sub-ticket is evaluated on its own merits. If any single sub-ticket FAILs after exhausting the retry/escalation flow, the entire create-ticket process stops (all sub-tickets are affected).

**When not split (N = 1)**: Execute the evaluation process below for the single ticket (no change from existing behavior).

#### Per-ticket evaluation process

1. Read the ticket content generated in Phase 3
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
        - **Autopilot policy check**: Check if `{ticket-dir}/autopilot-policy.yaml` exists (where ticket-dir is `.backlog/product_backlog/{ticket-dir}/`). If not found **and** a `brief=<path>` parameter was provided, also check `{brief-parent-dir}/autopilot-policy.yaml` (where brief-parent-dir is the parent directory of the brief file path, e.g., `.backlog/briefs/active/{slug}/`).
          - If it exists (in either location), read `gates.ticket_quality_fail`:
            - If `action` is `retry_with_feedback` and current retry count < `max_retries`: continue retrying with the evaluator's feedback. Print `[AUTOPILOT-POLICY] gate=ticket_quality_fail action=retry_with_feedback round={n}`.
            - Otherwise: stop. Print `[AUTOPILOT-POLICY] gate=ticket_quality_fail action=stop`.
          - If it does not exist, proceed with the existing interactive flow below.
        - Use AskUserQuestion to present the remaining FAIL gates to the user
        - Ask: "The ticket has unresolved quality issues: [list FAIL gates and their issues]. Proceed with this ticket anyway, or stop to revise manually?"
        - If user chooses to proceed → continue to Phase 5 with remaining issues noted in the summary
        - If user chooses to stop → print the ticket file path and remaining issues, then stop
        - **Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), default to **stop**. Print "Stopped: /create-ticket cannot resolve unresolved quality FAIL gates without interactive confirmation. Ticket saved at <path>. Re-run in interactive mode to decide whether to proceed." and exit. The ticket file remains on disk for manual editing. Do NOT hang waiting for input.

### Phase 5: Output

Use the ticket template from Pre-computed Context above for the output format.

After generating the ticket content:

1. **Counter read & ticket-dir derivation**:
   a. Read `.backlog/.ticket-counter`. If the file does not exist, initialize the counter value to `1`.
   b. If the file exists but contains non-numeric content, print "ERROR: .backlog/.ticket-counter contains non-numeric value '<content>'. Fix or delete the file and retry." and stop.
   c. Let `counter` = the current counter value. Let `N` = number of tickets (1 if not split, >1 if split).
   d. For each ticket `i` (0-indexed, `i = 0 … N-1`):
      - Compute `number_i` = `counter + i`.
      - Zero-pad `number_i` to 3 digits → `{NNN}` (e.g., `1` → `001`, `12` → `012`).
      - Derive `{slug_i}` from the ticket's title using kebab-case.
      - Define `{ticket-dir_i}` = `{NNN}-{slug_i}`.
      - In the ticket template, replace the `{NNN}` placeholder in `## T-{NNN}:` with the actual number (e.g., `## T-005: Add User Auth`).
2. For each ticket `i`, create the directory `.backlog/product_backlog/{ticket-dir_i}/` if it does not exist.
3. For each ticket `i`, write the ticket to `.backlog/product_backlog/{ticket-dir_i}/ticket.md`.
4. After **all** tickets are successfully written, write `counter + N` to `.backlog/.ticket-counter` (e.g., if `counter` was `5` and `N` is `3`, write `8`).

5. **Brief metadata injection**: If `brief=<path>` was provided:
   a. Read the brief file's YAML frontmatter and extract the `slug` field value → `{brief_slug}`.
   b. If the ticket creation context includes a part indicator (e.g., "This is part {N} of {total}" passed by `/autopilot` for split briefs), extract the part number → `{brief_part}`.
   c. In each generated ticket.md, add the following fields to the metadata table (the `| Key | Value |` table in the ticket template):
      - `| Brief Slug | {brief_slug} |`
      - `| Brief Part | {brief_part} |` (only if `{brief_part}` was extracted; omit this row entirely if not a split ticket)

**Non-split (N = 1)**: The above steps reduce to the same behavior as creating a single ticket and incrementing the counter by 1.

After writing the ticket(s), print a summary:

**Non-split (N = 1)**:
- Ticket file path
- Category, Size
- Number of Acceptance Criteria
- Quality evaluation result (PASS / FAIL with remaining issues if any)
- Recommended workflow: `/scout → /impl → /ship`

**Split (N > 1)**: Print a ticket list table followed by per-ticket details:

```
### Created Tickets (N tickets)

| # | Path | Category | Size | ACs | Quality |
|---|------|----------|------|-----|---------|
| T-005 | .backlog/product_backlog/005-foo/ticket.md | CodeQuality | M | 3 | PASS |
| T-006 | .backlog/product_backlog/006-bar/ticket.md | CodeQuality | S | 2 | PASS |
| ... | ... | ... | ... | ... | ... |

Recommended workflow per ticket: `/scout → /impl → /ship`
```

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

- **Counter file invalid**: If `.backlog/.ticket-counter` contains non-numeric content, print error with the invalid value and stop. Do not create any ticket.
- **Empty arguments**: Print "Usage: /create-ticket <ticket description>" and stop.
- **Researcher failure**: Report error and stop.
- **Planner failure**: Report error and stop.
- **Ticket-evaluator failure**: Output ticket without evaluation. Display "Quality: NOT EVALUATED" in summary.
- **2 rounds FAIL**: Present remaining issues to user via AskUserQuestion. Proceed only with user confirmation. If user declines, stop and print ticket path for manual editing. **In non-interactive mode** (when `AskUserQuestion` is unavailable / errors, typical in `claude -p` / CI automation), default to stop and print the ticket path with remaining issues. Do NOT hang waiting for input.
- **Split ticket partial failure**: If any sub-ticket FAILs evaluation and the process stops, no tickets are written and the counter is not updated (atomic: all-or-nothing).
