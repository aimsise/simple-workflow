target: references/agents/researcher.md references/agents/decomposer.md references/agents/planner.md references/agents/ticket-evaluator.md
heading: ## Context Conservation Protocol
mode: before
---
## Output hygiene (paths and secrets)

Never write an absolute home path (a path that begins with the user's home directory), the value of an environment variable, or any credential (a token, key or password) into your output file, the ticket text or your return envelope. Refer to files by their repository-relative path. If your role writes an output file, its path under the run scratch directory `{scratch}` (always relative to the working directory, `.create-ticket-scratch/run.XXXXXX`) is carried in your `**Output**:` field exactly as your spawn prompt names it, never expanded to an absolute path. A role that writes no file (the decomposer) carries none.
