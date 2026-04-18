---
name: create-ticket
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Create a structured ticket with scope analysis, acceptance
  criteria, and Claude Code workflow recommendations. Use when defining
  new work items or breaking down features into tickets.
disable-model-invocation: false
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
argument-hint: "<ticket description> [brief=<path>]"
---

## Pre-computed Context

Workflow patterns:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/workflow-patterns.md" 2>/dev/null || echo "[WARNING: workflow-patterns.md not found]"`

Ticket template:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/ticket-template.md" 2>/dev/null || echo "[WARNING: ticket-template.md not found]"`

`phase-state.yaml` schema (canonical reference for all writers):
!`cat "$CLAUDE_PLUGIN_ROOT/skills/create-ticket/references/phase-state-schema.md" 2>/dev/null || echo "[WARNING: phase-state-schema.md not found]"`

## phase-state.yaml write ownership

Writes the **whole** `phase-state.yaml` template at creation and transitions `phases.create_ticket` through `in-progress` → `completed` in the same invocation. Never writes other phase sections beyond the initial pending template. Top-level `current_phase` / `last_completed_phase` / `overall_status` are owned on initial write; subsequent writers update them per their own phase.

Reference: `skills/create-ticket/references/phase-state-schema.md`.

## Mandatory Skill Invocations

`/create-ticket` MUST delegate to each agent below via the Agent tool. Direct model output without delegation bypasses the independent research/planning/evaluation layers and is a contract violation detected by the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `researcher` agent (Agent tool) | Phase 1 Investigation — before drafting | No investigation findings; planner operates on model-internal assumptions rather than codebase evidence. Detected by missing researcher trace in skill invocation audit |
| `planner` agent (Agent tool) | Phase 3 Ticket Draft — after Phase 1 (+ optional Phase 2) | No structured draft; skill falls back to ad-hoc output with no category/size/AC separation — ticket-evaluator will FAIL the quality gate |
| `ticket-evaluator` agent (Agent tool) | Phase 4 per-ticket evaluation — after Phase 3 | No quality gate; ticket marked "NOT EVALUATED" and may contain untestable/ambiguous ACs. Detected by autopilot's post-create-ticket quality check |

**Binding rules**:
- `MUST invoke researcher via the Agent tool` — the researcher's independent findings are load-bearing for ticket scope definition.
- `MUST invoke planner via the Agent tool` — never draft ticket content inline; the planner's output is the canonical draft.
- `MUST invoke ticket-evaluator via the Agent tool` — never self-assess ticket quality; the ticket-evaluator is the independent quality gate.
- `NEVER bypass any of these agents via direct file operations` — writing `ticket.md` without going through all three phases is a contract violation.
- `Fail the task immediately if any mandatory agent invocation cannot be completed` — print the reason and stop; do not fabricate a ticket.

# /create-ticket

Ticket description: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS` for the optional `brief=<path>`:
- If present, extract the path and remove from the ticket description.
- If the path does not exist, print "ERROR: Brief file not found at <path>" and stop.
- If absent, proceed with the ticket description as-is.

## Instructions

Generate a structured ticket from the given description.

### Phase 1: Investigation (researcher agent)

**MUST invoke the `researcher` via the Agent tool.** **NEVER bypass** via direct `Grep`/`Read`/`Glob` — independent findings are required for Phase 3. Fail the task immediately if the researcher cannot be invoked.

Researcher scope:

1. Source code related to the ticket description
2. Affected files and line ranges
3. Existing test coverage
4. Related documentation
5. Dependencies (relationships with other tickets)

### Phase 2: Socratic Refinement

**Brief mode**: If `brief=<path>` was provided, skip Phase 2 — the brief already contains structured-interview context. Proceed to Phase 3.

Otherwise, refine scope through targeted questions:

1. Analyze the researcher's findings.
2. Identify unclear points across:
   - **Scope boundaries**: Related functionality that may or may not be included
   - **Priority**: Which concern takes precedence when multiple exist
   - **Edge cases**: Boundary / error cases from investigation
   - **Constraints**: Performance, security, backward-compat requirements
3. Use `AskUserQuestion` for up to 3 targeted questions (single call).
   - **Non-interactive fallback**: If `AskUserQuestion` is unavailable / errors (typical in `claude -p` / CI where stdin is not a TTY), skip Phase 2 and proceed to Phase 3 with researcher findings only. Note "Phase 2 skipped (non-interactive mode)" in the final summary. Do NOT hang.
4. Save the answers for the Phase 3 planner prompt.

If investigation yields sufficient clarity (e.g., simple S-size with obvious scope), skip questioning and proceed to Phase 3.

### Phase 3: Ticket Draft (planner agent)

**MUST invoke the `planner` via the Agent tool.** **NEVER draft inline** — the planner's structured output (Background / Scope / Acceptance Criteria / Implementation Notes + category/size/workflow) is the canonical draft for Phase 4. Fail the task immediately if the planner cannot be invoked.

Planner scope:

1. Ticket structure (Background, Scope, Acceptance Criteria, Implementation Notes)
2. Category (Security / CodeQuality / Doc / DevOps / Community) and size (S/M/L/XL)
3. Workflow recommendations based on category × size, using workflow patterns from Pre-computed Context above

Additional context for the planner:
- Phase 2 answers (scope, priority, edge cases, constraints)
- If brief was provided: full brief content (replaces Phase 2 answers)
- "Each AC will be evaluated by an independent evaluator for Testability (objectively verifiable PASS/FAIL) and Unambiguity (single interpretation). ACs that fail either gate will be rejected."

#### AC Quality Criteria

Every AC must pass both gates. Match the GOOD pattern; the evaluator rejects the BAD pattern.

- **Gate 1 — Testability**: each AC must be objectively verifiable with a clear PASS/FAIL outcome. Replace vague adjectives with concrete thresholds.
  - BAD: "Improve performance" (no threshold)
  - GOOD: "Response time under 200ms for 95th percentile"
- **Gate 2 — Unambiguity**: each AC must have exactly one interpretation. Define any term open to multiple readings.
  - BAD: "Support large files" ("large" undefined)
  - GOOD: "Stream files over 100MB without loading into memory"

Pattern: vague threshold → concrete threshold (Gate 1); undefined term → defined term (Gate 2).

#### Split Judgment

Instruct the planner to evaluate whether the ticket should be split:

- **Split criteria**: Size ≥ M **and** ACs group into 2+ independent work units (no inter-AC deps within a group).
- **Split quality guardrails**:
  - Each sub-ticket must be at least Size S with 2 or more Acceptance Criteria. Never create a ticket with only 1 AC.
  - Splits must produce **independently deployable and verifiable work units**, not mechanical AC distribution — each sub-ticket represents coherent functionality.
  - The planner must emit a **Split Rationale** justifying the split (e.g., "These ACs form an independent feature boundary" or "This group can be deployed/tested in isolation").
  - If no candidate satisfies all guardrails, fall back to **N = 1** (invalid split is worse than one larger ticket).
- **N > 1**: Planner outputs each sub-ticket individually with its own title, category, size, scope, ACs. Each must be self-contained and independently implementable.
- **N = 1**: Planner outputs a single ticket draft (existing behavior).

### Phase 4: Ticket Evaluation

**MUST invoke the `ticket-evaluator` via the Agent tool.** **NEVER self-assess** — the ticket-evaluator is the independent gate verifying AC Testability/Unambiguity. Fail immediately if it cannot be invoked.

**When split (N > 1)**: Run the evaluation process below **independently per sub-ticket**. If any sub-ticket FAILs after exhausting retry/escalation, the entire create-ticket stops (all sub-tickets affected).

**When not split (N = 1)**: Run the evaluation for the single ticket (existing behavior).

#### Per-ticket evaluation process

1. Read the ticket content from Phase 3.
2. Spawn the **ticket-evaluator** with the ticket content.
3. Decision:
   - **PASS** → proceed to Phase 5.
   - **FAIL** →
     a. Save the evaluator's Feedback.
     b. Re-spawn the **planner** with: original ticket content; evaluator Feedback (all FAIL items + improvement suggestions); instruction "For each FAIL item you revise, prepend a 'Change rationale: [why this addresses the feedback]' comment above the revised section. The evaluator reviews the rationale to verify intent."
     c. Re-spawn the **ticket-evaluator** on the revised ticket.
     d. Max 2 rounds (initial + 1 revision). If still FAIL:
        - **Autopilot policy check**: Check `{ticket-dir}/autopilot-policy.yaml` at `.backlog/product_backlog/{ticket-dir}/`. If missing **and** `brief=<path>` was given, also check `{brief-parent-dir}/autopilot-policy.yaml` (e.g. `.backlog/briefs/active/{slug}/`).
          - If present, read `gates.ticket_quality_fail`: `retry_with_feedback` + retry count < `max_retries` → continue retrying (print `[AUTOPILOT-POLICY] gate=ticket_quality_fail action=retry_with_feedback round={n}`); else stop (print `[AUTOPILOT-POLICY] gate=ticket_quality_fail action=stop`).
          - Else interactive flow below.
        - `AskUserQuestion`: "The ticket has unresolved quality issues: [list]. Proceed anyway or stop to revise manually?"
        - Proceed → Phase 5 with issues noted; Stop → print ticket path + issues.
        - **Non-interactive fallback**: If `AskUserQuestion` unavailable / errors, default to **stop**. Print "Stopped: /create-ticket cannot resolve FAIL gates non-interactively. Ticket saved at <path>. Re-run interactively." and exit. Do NOT hang.

### Phase 5: Output

Use the ticket template from Pre-computed Context for the output format.

After generating the ticket content:

1. **Counter read & ticket-dir derivation**:
   a. Read `.backlog/.ticket-counter`. If missing, initialize counter to `1`.
   b. If non-numeric, print "ERROR: .backlog/.ticket-counter contains non-numeric value '<content>'. Fix or delete the file and retry." and stop.
   c. Let `counter` = current value, `N` = ticket count (1 or >1 if split).
   d. For each ticket `i` (0-indexed, `i = 0 … N-1`):
      - `number_i` = `counter + i`.
      - Zero-pad `number_i` to 3 digits → `{NNN}` (e.g., `1` → `001`).
      - Derive `{slug_i}` from the title in kebab-case.
      - `{ticket-dir_i}` = `{NNN}-{slug_i}`.
      - Replace `{NNN}` in the `## T-{NNN}:` placeholder with the actual number (e.g. `## T-005: Add User Auth`).
2. For each ticket `i`, create `.backlog/product_backlog/{ticket-dir_i}/` if absent.
3. For each ticket `i`, write to `.backlog/product_backlog/{ticket-dir_i}/ticket.md`.
4. After **all** writes succeed, write `counter + N` to `.backlog/.ticket-counter`.

4a. **Initialize `phase-state.yaml`** for each ticket `i` (always, even when `/create-ticket` is invoked standalone):

   a. `now` = ISO-8601 UTC (`date -u +%Y-%m-%dT%H:%M:%SZ`).
   b. `size_i` = Size from Phase 3 (S/M/L/XL).
   c. `ticket_dir_path_i` = `.backlog/product_backlog/{ticket-dir_i}` (stays here until `/scout` moves to `.backlog/active/`). No top-level `ticket_dir:` field — the path encodes location.
   d. Write `{ticket_dir_path_i}/phase-state.yaml` with the pending template below. Canonical schema: `skills/create-ticket/references/phase-state-schema.md`:

      ```yaml
      version: 1
      size: {size_i}
      created: {now}

      current_phase: create_ticket
      last_completed_phase: null
      overall_status: in-progress

      phases:
        create_ticket:
          status: in-progress
          started_at: {now}
          completed_at: null
          artifacts:
            ticket: null

        scout:
          status: pending
          started_at: null
          completed_at: null
          artifacts:
            investigation: null
            plan: null

        impl:
          status: pending
          started_at: null
          completed_at: null
          current_round: null
          max_rounds: null
          phase_sub: null
          last_ac_status: null
          last_audit_status: null
          last_audit_critical: 0
          last_round: null
          next_action: null
          feedback_files:
            eval: null
            quality: null

        ship:
          status: pending
          started_at: null
          completed_at: null
          artifacts:
            pr_url: null
      ```

   e. **Immediately** transition `phases.create_ticket` to `completed` in the same invocation (before returning) via read-modify-write:
      - `phases.create_ticket.status: completed`
      - `phases.create_ticket.completed_at: {now}` (recomputed immediately before write)
      - `phases.create_ticket.artifacts.ticket: {ticket_dir_path_i}/ticket.md`
      - `last_completed_phase: create_ticket`
      - `current_phase: scout`

   f. Do NOT modify other `phases.*` sections. The `scout`, `impl`, `ship` sections remain in the pending template for their owning skills.

   **Atomicity**: On write failure, report the error but do NOT delete already-created `ticket.md` files — retry is idempotent on the state file.

5. **Brief metadata injection**: If `brief=<path>` was provided:
   a. Read the brief's YAML frontmatter; extract `slug` → `{brief_slug}`.
   b. If the creation context includes a part indicator (e.g., "This is part {N} of {total}" from `/autopilot` for split briefs), extract → `{brief_part}`.
   c. In each ticket.md, add to the metadata table:
      - `| Brief Slug | {brief_slug} |`
      - `| Brief Part | {brief_part} |` (only if extracted; omit otherwise)

**Non-split (N = 1)**: Equivalent to creating a single ticket and incrementing the counter by 1.

After writing, print a summary:

**Non-split (N = 1)**:
- Ticket file path
- Category, Size
- Number of ACs
- Quality evaluation result (PASS / FAIL + remaining issues)
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

### Phase 6: Emit SW-CHECKPOINT block

Emit the `## [SW-CHECKPOINT]` block per `skills/create-ticket/references/sw-checkpoint-template.md` as the FINAL section of the skill's output, after `### Created Tickets` and any other summary content. Fill: `phase=create_ticket`, `ticket=<first created ticket-dir or "none">` (for N>1 use the first), `artifacts=[<repo-relative paths to every `ticket.md` written>]`, `next_recommended=/scout {ticket-dir}` (or `""` if none created). Emit on failure paths with `artifacts: []`.

### Workflow selection guide

Identify available skills/agents by scanning `.claude/skills/` and `.claude/agents/`, listing installed plugin skills/agents, and using the workflow patterns from Pre-computed Context.

**Category guidelines**:
- **Security**: Wrap with `/audit only_security_scan=true` before and after. Spec-first; documentation leads.
- **CodeQuality**: Use `/refactor`. Guarantee no behavior changes.
- **Doc**: Use `/impl` with a doc-focused plan.
- **DevOps**: CI/CD configs are hard to test; design with `/plan2doc`.
- **Community**: Reference industry-standard templates.

**Size guidelines**:
- **S**: `/plan2doc` optional. Direct implementation.
- **M**: `/plan2doc` recommended.
- **L/XL**: `/plan2doc` required. Incremental implementation recommended.

## Error Handling

- **Counter file invalid**: Non-numeric `.backlog/.ticket-counter` → print error with the invalid value and stop; create no ticket.
- **Empty arguments**: Print "Usage: /create-ticket <ticket description>" and stop.
- **Researcher failure**: Report error and stop.
- **Planner failure**: Report error and stop.
- **Ticket-evaluator failure**: Output ticket without evaluation; display "Quality: NOT EVALUATED" in summary.
- **2 rounds FAIL**: Present remaining issues via `AskUserQuestion`. Proceed only with user confirmation. Decline → stop + print ticket path. **Non-interactive fallback**: default to stop + print ticket path with issues. Do NOT hang.
- **Split ticket partial failure**: If any sub-ticket FAILs evaluation and stops, no tickets are written and the counter is not updated (atomic).
