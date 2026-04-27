---
name: plan2doc
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Create an implementation plan and save to ticket dir or .simple-workflow/docs/plans/.
  Spawns planner agent with model auto-selected by ticket size
  (sonnet for S, opus for M/L/XL). Use for any size of planning work.
disable-model-invocation: false
allowed-tools:
  # Claude Code
  - Agent
  - Read
  - Glob
  - Write
  - Edit
  - "Bash(git diff:*)"
  - "Bash(git status:*)"
  - "Bash(git log:*)"
  - "Bash(ls:*)"
  - "Bash(mv:*)"
  - "Bash(mkdir:*)"
  # Copilot CLI
  - task
  - view
  - glob
  - create
  - edit
  - "shell(git diff:*)"
  - "shell(git status:*)"
  - "shell(git log:*)"
  - "shell(ls:*)"
  - "shell(mv:*)"
  - "shell(mkdir:*)"
argument-hint: "<feature or change to plan>"
---

Create an implementation plan for: $ARGUMENTS

Current changes:
!`git diff --stat`

Existing research (if any):
!`ls -t .simple-workflow/docs/research/*.md 2>/dev/null | head -5`

## Mandatory Skill Invocations

The following agent invocation is **contractual** — `/plan2doc` MUST delegate to the `planner` agent via the Agent tool. `/plan2doc` itself writes no plan content; its entire role is to detect Size, resolve the output destination, and spawn the `planner` agent with the appropriate model (sonnet for S, opus for M/L/XL). Any bypass is a contract violation and will be detected by the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `planner` agent (Agent tool) | Step 4 — always, after Size detection and output-path resolution | No structured plan written to the output path; `/impl` has no `### Acceptance Criteria` section to drive the Generator → Evaluator loop and will stop at Phase 1 step 6 with "ERROR: Plan has no Acceptance Criteria". Detected by absence of `plan.md` in the ticket dir (or `.simple-workflow/docs/plans/`) and absence of planner trace in skill invocation audit |

**Binding rules**:
- `MUST invoke the planner agent via the Agent tool` with the correct `model` parameter (`sonnet` for Size S, `opus` otherwise). Never substitute by writing `plan.md` directly from `/plan2doc`.
- `NEVER bypass the planner via direct file operations` — `/plan2doc` must NOT write the plan content itself; the planner agent is the sole author.
- `Fail the task immediately if the planner agent cannot be invoked via the Agent tool` — print the failure reason and the resolved output path so the user can retry.

## AC Single Source of Truth (SSoT)

`ticket.md` is the **Single Source of Truth** for the Acceptance Criteria of any ticket. When `/plan2doc` runs against a ticket directory (i.e. `ticket-dir` is resolved and `{ticket-dir}/ticket.md` exists), the resulting `{ticket-dir}/plan.md` MUST contain a `## Acceptance Criteria` section that is a **verbatim copy** of the ticket's AC list. The planner agent rewrites no AC body text; it transcribes.

Verbatim copy is defined item-by-item:

- Item count: the number of list items under `## Acceptance Criteria` in `plan.md` MUST equal the number of list items under `## Acceptance Criteria` in `ticket.md`.
- Item body: after stripping each leading list marker — one of `- `, `* `, or `[0-9]+\. ` — the remaining bytes of every item in `plan.md` MUST be byte-identical to the corresponding item in `ticket.md`. Backtick-quoted code spans, punctuation, capitalization, and surrounding whitespace inside the body all count as bytes.

What is NOT drift:

- List-marker style differences alone. `plan.md` may use `1. `, `2. ` numbered markers while `ticket.md` uses `- ` bullets, as long as item bodies match after marker stripping.
- Sections other than `## Acceptance Criteria`. `plan.md` legitimately carries planning-specific sections (`## Overview`, `## Affected files`, `## Step-by-step implementation plan`, `## Risk assessment`, `### Claude Code Workflow`, etc.) that do not exist in `ticket.md`. `ticket.md` may have its own non-AC sections (`## Negative AC`, `## Edge Cases`) that the plan does not mirror. Only the `## Acceptance Criteria` section is compared.

The drift guard is enforced by `tests/test-skill-contracts.sh` Cat AD (AC-SSoT contract), which walks every `plan.md`/`ticket.md` pair under `.simple-workflow/backlog/{active,product_backlog,done}/<slug>/<ticket-id>/` and compares the two AC lists per the rules above. Drift produces a non-zero exit and a stderr line containing both file paths.

## Observable Contract: `ssot-line`

Every `/plan2doc` invocation MUST emit **exactly one line** to stdout that matches the regex `^plan2doc: ac-source=ticket\.md verbatim=true$`. This is the `ssot-line` Observable Contract. The line is the runtime declaration that the AC list in the generated `plan.md` was sourced verbatim from `ticket.md`. `/plan2doc` itself prints this line at the start of Step 5 (Return summary), after the planner agent has written `plan.md` and before the human-readable summary. No other line on stdout may match this regex during a single invocation — exactly one ssot-line per run.

When `ticket-dir` does not resolve to an existing `ticket.md` (i.e. the plan is being written to `.simple-workflow/docs/plans/{feature}.md` with no ticket pair), the ssot-line is still emitted because the AC SSoT discipline is unconditional: even in the no-ticket case, the line documents that the skill respects the ticket-as-SSoT contract whenever a ticket exists, and that no AC was fabricated outside that boundary.

## Instructions

0a. **Size detection**. Parse `$ARGUMENTS` for `(ticket-dir: <path>)`. If `ticket-dir` is specified, read `{ticket-dir}/ticket.md` and extract the Size value from the `| Size |` table row (S/M/L/XL). If `ticket.md` does not exist, or no `| Size |` row is found, default `Size = M`. If no `ticket-dir` is specified at all, default `Size = M`. Record the resolved Size for use in Step 4.

0b. **Resolve output destination**. Decide where the plan will be written:
   - If `ticket-dir` is specified: output the plan to `{ticket-dir}/plan.md`.
   - If `ticket-dir` is not specified: **search** `.simple-workflow/backlog/product_backlog/` and `.simple-workflow/backlog/active/` using `Glob` for directories matching `$ARGUMENTS` keywords (e.g., `.simple-workflow/backlog/product_backlog/*<keyword>*` and `.simple-workflow/backlog/active/*<keyword>*`). If a matching directory is found in `product_backlog`, move it to `active` with `mv .simple-workflow/backlog/product_backlog/{ticket-dir} .simple-workflow/backlog/active/{ticket-dir}` and use `.simple-workflow/backlog/active/{ticket-dir}/plan.md`. If already in `active`, use `.simple-workflow/backlog/active/{ticket-dir}/plan.md` as-is. In this ticket-matched case, also attempt to read `.simple-workflow/backlog/active/{ticket-dir}/ticket.md` to refine the Size detection from Step 0a (the ticket-dir-less path can still pick up a Size row).
   - If no `ticket-dir` was given and no matching ticket directory exists anywhere: output to `.simple-workflow/docs/plans/{feature}.md` (default), where `{feature}` is a slug derived from `$ARGUMENTS`.

1. **Read research context**. If `$ARGUMENTS` contains `(research: <path>)`, read that specific file first. If `ticket-dir` is set and `{ticket-dir}/investigation.md` exists, also read it for additional context. Otherwise, if research files are listed above, read the most relevant ones to build on prior findings.

2. **Analyze**. Identify dependencies, affected files, risks, and implementation order from the research and current repository state.

3. **Scan available tooling**. Identify available skills and agents by scanning `.claude/skills/` and `.claude/agents/` (if present), and listing installed plugin skills/agents. Read frontmatter only (not full file contents). This list will be passed to the planner agent so it can reference them in the `### Claude Code Workflow` section.

4. **MUST invoke the `planner` agent via the Agent tool**. **NEVER bypass the planner** by writing `plan.md` directly from `/plan2doc` — the planner agent is the sole author of plan content. Fail the task immediately if the planner agent cannot be invoked. Set the `Agent` tool call as follows:
   - `subagent_type`: `planner`
   - `model`:
     - If `Size == S` → `"sonnet"`
     - If `Size` is `M`, `L`, `XL`, or unknown → `"opus"`
   - `description`: `"Create implementation plan for <feature>"` (substitute the topic from `$ARGUMENTS`).
   - `prompt`: Pass the following to the planner agent as structured content:
     - The detected `Size` (S/M/L/XL) and how it was detected (ticket.md Size row, or default).
     - The resolved output path (`{ticket-dir}/plan.md` or `.simple-workflow/docs/plans/{feature}.md`).
     - The research file path(s) that were read (if any).
     - The original `$ARGUMENTS` string (verbatim).
     - The list of available skills/agents from Step 3.
     - An explicit instruction that the planner MUST write the full plan to the output path, including these sections:
       - **Overview** and goals
       - **Affected files** and components
       - **Step-by-step implementation plan** (numbered)
       - **Risk assessment** and testing strategy
       - **Acceptance Criteria** (bullet list of measurable, verifiable criteria) — when `ticket.md` exists at `{ticket-dir}/ticket.md`, the planner MUST copy the AC list verbatim from `ticket.md` per the AC SSoT discipline above (item count equal; each item body byte-identical after stripping leading list markers `- `, `* `, or `[0-9]+\. `). The planner MAY swap list-marker style (e.g. `- ` → `1. `) but MUST NOT rewrite, paraphrase, or augment item bodies.
       - `### Claude Code Workflow` section with a phase/command/agent table referencing the scanned skills/agents

5. **Return summary**. After the planner agent returns, verify the plan file exists at the resolved output path. Then emit the `ssot-line` Observable Contract event as the **first** line of stdout for this step:

   ```
   plan2doc: ac-source=ticket.md verbatim=true
   ```

   The line MUST appear exactly once per invocation and MUST match `^plan2doc: ac-source=ticket\.md verbatim=true$` (no leading or trailing whitespace, no extra tokens). Then print a short human-readable summary to the user containing:
   - The resolved Size and model used (sonnet or opus)
   - The plan file path
   - A one-line synopsis from the planner's return value

`/plan2doc` does NOT emit a checkpoint block. It is a delegate of `/scout` (analogous to `/audit`, which also does not emit). Standalone `/plan2doc` usage is rare and `/scout` already emits a checkpoint that covers the plan2doc work. See `skills/create-ticket/references/sw-checkpoint-template.md` for the canonical block contract and the list of skills that DO emit it.

## Error Handling

- **Empty arguments**: Print `Usage: /plan2doc <feature or change to plan>` and stop.
- **Missing .simple-workflow/docs/ directories**: Create `.simple-workflow/docs/plans/` automatically.
- **Missing .simple-workflow/backlog/ directories**: Create `.simple-workflow/backlog/active/{ticket-dir}/` automatically when `ticket-dir` is specified.
- **ticket.md exists but has no `| Size |` row**: Treat as unknown Size and default to `M` (→ opus).
- **planner agent failure**: Report the error and the resolved output path so the user can retry.
