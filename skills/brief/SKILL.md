---
name: brief
description: >-
  Conduct a structured interview to gather requirements and generate
  a brief document with autopilot policy for a new feature or task.
disable-model-invocation: true
allowed-tools:
  # Claude Code
  - Agent
  - Skill
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
  - "Bash(git log:*)"
  - "Bash(git status:*)"
  - "Bash(git diff:*)"
  - "Bash(git branch:*)"
  - "Bash(mkdir:*)"
  - "Bash(mv:*)"
  - "Bash(ls:*)"
  - "Bash(date:*)"
  # Copilot CLI
  - task
  - skill
  - view
  - create
  - glob
  - grep
  - ask_user
  - "shell(git log:*)"
  - "shell(git status:*)"
  - "shell(git diff:*)"
  - "shell(git branch:*)"
  - "shell(mkdir:*)"
  - "shell(mv:*)"
  - "shell(ls:*)"
  - "shell(date:*)"
argument-hint: "<what-to-build> [auto=true]"
---

## Pre-computed Context

Interview templates:
!`cat "$CLAUDE_PLUGIN_ROOT/skills/brief/references/interview-templates.md" 2>/dev/null || echo "[WARNING: interview-templates.md not found]"`

Existing briefs:
!`ls -t .backlog/briefs/active/*/brief.md 2>/dev/null | head -5`

Knowledge base (autopilot patterns):
!`cat .simple-wf-knowledge/index.yaml 2>/dev/null | grep -A2 "^autopilot:" || echo "[No autopilot patterns in knowledge base]"`

# /brief

User input: $ARGUMENTS

## Argument Parsing

Parse `$ARGUMENTS`:
- Extract `auto=true` if present (case-insensitive). Remove it from the description.
- Remaining text is `<what-to-build>`.
- If `<what-to-build>` is empty, print "Usage: /brief <what-to-build> [auto=true]" and stop.
- Generate `{slug}` from `<what-to-build>` using kebab-case (e.g., "Add User Auth" -> `add-user-auth`).

## Phase 1: Initial Investigation

1. Spawn the **researcher** agent (sonnet) via the Agent tool:
   - description: "Investigate codebase for: <what-to-build>"
   - Prompt: "Investigate the codebase to understand existing patterns, dependencies, similar features, and technical constraints related to: <what-to-build>. Focus on: (1) existing code patterns and architecture, (2) related dependencies, (3) similar existing features, (4) potential technical constraints. Return a concise summary under 500 tokens."
   - model: sonnet
2. Save the researcher's summary for use in Phase 2 and Phase 3.

## Phase 2: Structured Interview

Conduct an iterative Q&A to gather comprehensive requirements.

**Non-interactive environment fallback**: If `AskUserQuestion` is unavailable or returns an error (typical in `claude -p` / CI automation where stdin is not a TTY), skip Phase 2 entirely and proceed directly to Phase 3 with the researcher's findings only. Note "Phase 2 skipped (non-interactive mode)" in the final summary. Do NOT hang waiting for input.

For each round (max 5 rounds):

1. Based on the researcher's findings and any previous answers, identify the most important unanswered questions from the interview templates (see Pre-computed Context above).
2. Select up to 3 questions from the template categories that are most relevant and not yet answered. Adapt the questions based on the specific context — do not ask generic template questions verbatim.
3. Use `AskUserQuestion` to ask the selected questions.
4. After receiving answers, output a brief summary of "Current understanding" to the user:
   - What is known so far
   - What categories still need information
5. **Convergence check**: Stop the interview if ANY of these conditions are met:
   - The user responds with "sufficient", "enough", or similar
   - All 7 categories have sufficient information
   - 5 rounds have been completed
6. Continue to next round if convergence is not reached.

## Phase 3: Brief Document Generation

1. Create directory: `mkdir -p .backlog/briefs/active/{slug}`
2. Synthesize all gathered information into a structured brief document.
3. Estimate the ticket size (S/M/L/XL) based on:
   - S: 1-3 files, simple change
   - M: 4-8 files, moderate complexity
   - L: 9+ files, significant complexity
   - XL: Architecture-level changes
4. Estimate the category: Security / CodeQuality / Doc / DevOps / Community
5. Write to `.backlog/briefs/active/{slug}/brief.md`:

```
---
slug: {slug}
created: {date}
status: draft
estimated_size: {S|M|L|XL}
estimated_category: {category}
split: false
---

## Vision
[Refined expression of the user's goal]

## Business Context
[Motivation, stakeholders, timeline — from interview or "Not specified"]

## Technical Requirements
[Specific technical requirements gathered from investigation + interview]

## Scope
### In Scope
- [items]
### Out of Scope
- [items, or "Not explicitly defined"]
### Edge Cases
- [case]: [expected behavior]

## Constraints
[Technical constraints, compatibility requirements]

## Quality Expectations
[Test coverage expectations, review requirements]

## Investigation Summary
[Key findings from Phase 1 researcher]
```

## Phase 4: Policy Generation

1. Read `.simple-wf-knowledge/index.yaml` if it exists.
   - Filter entries under the `autopilot` section. These are historical decision patterns (from `/tune` analysis of autopilot-log.md) that inform default policy values.
   - For each gate in the policy template, search the `autopilot` section for patterns whose `summary` matches the gate name (e.g., `ac_eval_fail`, `ship_review_gate`).
2. Determine default policy values based on:
   - User's risk tolerance answers from Phase 2 (maps to conservative/moderate/aggressive)
   - KB autopilot patterns (if any), applying confidence-based 3-tier judgment per gate:
     - confidence >= 0.7 → use the pattern's action as recommended default; append `# kb-suggested` comment to the gate line
     - confidence 0.5-0.7 → use the pattern's action but append `# [low confidence]` comment
     - confidence < 0.5 → use conservative default (stop)
   - **Size-scoped pattern priority**: If the `autopilot` section contains patterns with a `scope` matching the current brief's `estimated_size` (S/M/L/XL), prefer those over patterns with `scope=general`. Fall back to `scope=general` only when no size-specific pattern exists for a gate.
   - If `.simple-wf-knowledge/index.yaml` does not exist or has no `autopilot` section (first run), use conservative defaults for all gates and add `# KB patterns: none` comment to the generated policy file.
3. Write to `.backlog/briefs/active/{slug}/autopilot-policy.yaml`:

```yaml
version: 1
risk_tolerance: {conservative|moderate|aggressive}

gates:
  ticket_quality_fail:
    action: retry_with_feedback
    max_retries: 2
  evaluator_dry_run_fail:
    action: {proceed_without|stop}  # conservative=stop, moderate/aggressive=proceed_without
  ac_eval_fail:
    action: retry
    on_critical: stop
  audit_infrastructure_fail:
    action: {treat_as_fail|stop}  # conservative=stop, moderate/aggressive=treat_as_fail
  ship_review_gate:
    action: {proceed_if_eval_passed|stop}  # conservative=stop, moderate/aggressive=proceed_if_eval_passed
  ship_ci_pending:
    action: wait
    timeout_minutes: {30|60}  # conservative/moderate=30, aggressive=60
    on_timeout: stop
  unexpected_error:
    action: stop

constraints:
  max_total_rounds: {9|12}  # conservative/moderate=9, aggressive=12
  allow_breaking_changes: {false|true}  # conservative/moderate=false, aggressive=true
```

## Phase 5: Split Analysis

Analyze whether the brief scope should be split into multiple tickets.

1. **Split trigger evaluation**:
   - If `estimated_size` is L or XL → evaluate for splitting
   - If `estimated_size` is S or M → skip splitting, set `split: false` in brief.md frontmatter, proceed to Phase 6
   - If the user explicitly stated "no splitting" or "分割不要" during the interview → skip splitting

2. **Split analysis** (for L/XL briefs):
   Analyze the Technical Requirements and In Scope sections to identify natural boundaries:
   - Independent components that can be implemented and tested separately
   - Features with no mutual dependencies
   - Layers (e.g., backend API first, then frontend, then integration)

3. **Split decision**:
   - If 2+ independent components are identified → proceed to split
   - If requirements are tightly coupled and inseparable → skip splitting, note "Split analysis: requirements are tightly coupled" in brief.md
   - Each sub-ticket should target size M or smaller (S is ideal)
   - If a sub-ticket would still be L, attempt further decomposition (max 2 levels)

4. **Generate split-plan.md** (only if splitting):
   Write to `.backlog/briefs/active/{slug}/split-plan.md`:

   ```yaml
   ---
   parent_slug: {slug}
   ticket_count: {N}
   ---
   ```

   Followed by:

   ```markdown
   ## Split Rationale
   [Why this brief is being split and the splitting strategy]

   ## Tickets

   ### 1. {slug}-part-1: {title}
   - **Size**: S | M
   - **depends_on**: [] (no dependencies, executes first)
   - **Scope**: [What this ticket covers from the brief]
   - **Brief Sections**: [Which sections of the brief apply]

   ### 2. {slug}-part-2: {title}
   - **Size**: S | M
   - **depends_on**: [{slug}-part-1]
   - **Scope**: [What this ticket covers]
   - **Brief Sections**: [Which sections apply]

   ### 3. {slug}-part-3: {title}
   - **Size**: S
   - **depends_on**: [] (can run in parallel with part-1)
   - **Scope**: [What this ticket covers]
   - **Brief Sections**: [Which sections apply]
   ```

   > **Note**: `{slug}-part-N` names in the split plan are **logical identifiers** used for dependency ordering. They are NOT physical directory names. The actual ticket directory name is assigned by `/create-ticket` at execution time using the `{NNN}-{slug}` sequential numbering format (e.g., `005-auth-login`). The `/autopilot` skill maintains a mapping table from logical names to physical directory names during execution.

5. **Dependency validation**: Verify the dependency graph is a DAG (no circular dependencies). If circular dependencies are detected, restructure the split to eliminate them.

6. **Update brief.md frontmatter**: Set `split: true` if split-plan was generated.

## Phase 6: Output & Auto-kick

1. Print summary:
   - Brief file path: `.backlog/briefs/active/{slug}/brief.md`
   - Policy file path: `.backlog/briefs/active/{slug}/autopilot-policy.yaml`
   - Estimated size and category
   - Number of interview rounds completed

2. If `auto=true` was specified:
   a. Display the brief and policy content to the user
   b. Use `AskUserQuestion` to ask "This will start the autopilot pipeline. Proceed?" with options "yes" and "no"
      - **Non-interactive fallback**: If AskUserQuestion is unavailable, default to "no". Print "Auto-kick skipped (non-interactive mode). Run /autopilot {slug} manually to start the pipeline."
   c. If "yes": Update brief.md status from `draft` to `confirmed`. Then invoke the autopilot skill via the Skill tool with argument `{slug}`.
   d. If "no": Keep status as `draft`. Print "Brief saved. To start the pipeline, update status to 'confirmed' and run /autopilot {slug}."

3. If `auto=true` was NOT specified:
   Print "Brief generated. To proceed:
   1. Review and edit the brief if needed
   2. Update status to 'confirmed' in brief.md frontmatter
   3. Run /autopilot {slug} to start the full pipeline"

## Error Handling

- **Empty arguments**: Print "Usage: /brief <what-to-build> [auto=true]" and stop.
- **Researcher failure**: Report error. Continue to Phase 2 without investigation summary.
- **AskUserQuestion failure**: Skip Phase 2, proceed with researcher findings only.
- **Write failure**: Report error and stop.
