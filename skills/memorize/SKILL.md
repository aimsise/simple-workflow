---
name: memorize
description: >-
  Update project memory with current branch progress, completed tickets, and
  next work item. Use only when the user explicitly asks to save progress.
disable-model-invocation: true
allowed-tools:
  - "Bash(git:*)"
  - Read
  - Edit
  - Write
  - Glob
  - AskUserQuestion
argument-hint: "[progress note (optional)]"
---

Update project memory with current progress.
User note: $ARGUMENTS

Current branch:
!`git branch --show-current`

Branch commits (vs main):
!`git log main..HEAD --oneline 2>/dev/null || git log --oneline -10`

## Instructions

### 1. Locate memory files

- Read MEMORY.md from the project memory directory
- Find the "Active Feature Development" section
- Read the linked project memory file (e.g., `project_*.md`)
- If no project memory file exists, create one following the frontmatter format:
  ```
  ---
  name: <feature name>
  description: <one-line description>
  type: project
  ---
  ```

### 2. Determine progress

**If $ARGUMENTS is provided**: use it as the authoritative progress note. Still capture branch name.

**If $ARGUMENTS is empty**: cross-reference branch commits with the ticket table:
- Match commit messages to ticket descriptions
- Mark matched tickets as `DONE (<short-sha>)`
- Set the first remaining TODO ticket as `**NEXT**`

### 3. Handle completion

If ALL tickets are DONE (no TODO or NEXT remaining):

1. Use AskUserQuestion to ask: "All tickets are complete. Remove progress tracking from MEMORY.md?"
   - Options: "Yes - remove entry and memory file" / "No - keep as completed record"
2. **If Yes**:
   - Remove the corresponding bullet line from "Active Feature Development" in MEMORY.md
   - If the section becomes empty (no remaining entries), also remove the `## Active Feature Development` header
   - Delete the project memory file
   - Report what was removed and stop (skip steps 4-6)
3. **If No**:
   - Update MEMORY.md one-liner to show completion status (no NEXT)
   - Continue to steps 4-6

### 4. Update project memory file

- Update the ticket/progress table with completion status
- Update the date in the section header to today
- Replace the detail section below the table:
  - Remove completed ticket details (the table row + commit hash is sufficient)
  - Add a brief detail section for the NEXT ticket only
  - Include path to plan doc (`.docs/plans/` or `.backlog/active/{slug}/plan.md`) if one exists
  - Include path to research doc (`.docs/research/` or `.backlog/active/{slug}/investigation.md`) if one exists

### 5. Update MEMORY.md

Each feature MUST be a separate, self-contained bullet under "Active Feature Development".
Never combine multiple features into a single line. Format:

`- [<Feature>](<memory_file>.md) - <version>, <N> tickets, Ticket #1-#X done -> next is Ticket #Y (<title>)`

If a plan doc path is known, append: `. Plan: .docs/plans/<file>.md` (or `.backlog/active/{slug}/plan.md` if the plan is in the backlog)

### 6. Report

Print a concise summary:
- Branch name
- Tickets marked DONE (with hashes)
- Next ticket number and title
- Files updated
