target: SKILL.md
heading: ### Step W-1: Counter read & validate
mode: before
---
### Step W-0: Ensure `.simple-workflow/` is gitignored

Ensure `.simple-workflow/` is listed in the repository `.gitignore` (append the line when absent): read the `.gitignore` at the repository root; when no line equals `.simple-workflow/`, `.simple-workflow` or `/.simple-workflow/`, append `.simple-workflow/` on its own line (create the file when it does not exist). Never rewrite, reorder or remove existing lines. Every file this skill writes lives under `.simple-workflow/`, so this step keeps the backlog, the counter and the transient investigation files out of commits.
