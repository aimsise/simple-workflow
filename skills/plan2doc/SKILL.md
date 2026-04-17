---
name: plan2doc
description: >-
  Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill.
  Create an implementation plan and save to ticket dir or .docs/plans/.
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
!`ls -t .docs/research/*.md 2>/dev/null | head -5`

## Mandatory Skill Invocations

The following agent invocation is **contractual** — `/plan2doc` MUST delegate to the `planner` agent via the Agent tool. `/plan2doc` itself writes no plan content; its entire role is to detect Size, resolve the output destination, and spawn the `planner` agent with the appropriate model (sonnet for S, opus for M/L/XL). Any bypass is a contract violation and will be detected by the skill invocation audit (Phase A+).

| Invocation Target | When | Skip consequence |
|---|---|---|
| `planner` agent (Agent tool) | Step 4 — always, after Size detection and output-path resolution | No structured plan written to the output path; `/impl` has no `### Acceptance Criteria` section to drive the Generator → Evaluator loop and will stop at Phase 1 step 6 with "ERROR: Plan has no Acceptance Criteria". Detected by absence of `plan.md` in the ticket dir (or `.docs/plans/`) and absence of planner trace in skill invocation audit |

**Binding rules**:
- `MUST invoke the planner agent via the Agent tool` with the correct `model` parameter (`sonnet` for Size S, `opus` otherwise). Never substitute by writing `plan.md` directly from `/plan2doc`.
- `NEVER bypass the planner via direct file operations` — `/plan2doc` must NOT write the plan content itself; the planner agent is the sole author.
- `Fail the task immediately if the planner agent cannot be invoked via the Agent tool` — print the failure reason and the resolved output path so the user can retry.

## Instructions

0a. **Size detection**. Parse `$ARGUMENTS` for `(ticket-dir: <path>)`. If `ticket-dir` is specified, read `{ticket-dir}/ticket.md` and extract the Size value from the `| Size |` table row (S/M/L/XL). If `ticket.md` does not exist, or no `| Size |` row is found, default `Size = M`. If no `ticket-dir` is specified at all, default `Size = M`. Record the resolved Size for use in Step 4.

0b. **Resolve output destination**. Decide where the plan will be written:
   - If `ticket-dir` is specified: output the plan to `{ticket-dir}/plan.md`.
   - If `ticket-dir` is not specified: **search** `.backlog/product_backlog/` and `.backlog/active/` using `Glob` for directories matching `$ARGUMENTS` keywords (e.g., `.backlog/product_backlog/*<keyword>*` and `.backlog/active/*<keyword>*`). If a matching directory is found in `product_backlog`, move it to `active` with `mv .backlog/product_backlog/{ticket-dir} .backlog/active/{ticket-dir}` and use `.backlog/active/{ticket-dir}/plan.md`. If already in `active`, use `.backlog/active/{ticket-dir}/plan.md` as-is. In this ticket-matched case, also attempt to read `.backlog/active/{ticket-dir}/ticket.md` to refine the Size detection from Step 0a (the ticket-dir-less path can still pick up a Size row).
   - If no `ticket-dir` was given and no matching ticket directory exists anywhere: output to `.docs/plans/{feature}.md` (default), where `{feature}` is a slug derived from `$ARGUMENTS`.

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
     - The resolved output path (`{ticket-dir}/plan.md` or `.docs/plans/{feature}.md`).
     - The research file path(s) that were read (if any).
     - The original `$ARGUMENTS` string (verbatim).
     - The list of available skills/agents from Step 3.
     - An explicit instruction that the planner MUST write the full plan to the output path, including these sections:
       - **Overview** and goals
       - **Affected files** and components
       - **Step-by-step implementation plan** (numbered)
       - **Risk assessment** and testing strategy
       - **Acceptance Criteria** (bullet list of measurable, verifiable criteria)
       - `### Claude Code Workflow` section with a phase/command/agent table referencing the scanned skills/agents

5. **Return summary**. After the planner agent returns, verify the plan file exists at the resolved output path, then print a short summary to the user containing:
   - The resolved Size and model used (sonnet or opus)
   - The plan file path
   - A one-line synopsis from the planner's return value

## Error Handling

- **Empty arguments**: Print `Usage: /plan2doc <feature or change to plan>` and stop.
- **Missing .docs/ directories**: Create `.docs/plans/` automatically.
- **Missing .backlog/ directories**: Create `.backlog/active/{ticket-dir}/` automatically when `ticket-dir` is specified.
- **ticket.md exists but has no `| Size |` row**: Treat as unknown Size and default to `M` (→ opus).
- **planner agent failure**: Report the error and the resolved output path so the user can retry.
