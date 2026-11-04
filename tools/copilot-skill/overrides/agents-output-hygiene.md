target: references/agents/researcher.md references/agents/decomposer.md references/agents/planner.md references/agents/ticket-evaluator.md
heading: ## Context Conservation Protocol
mode: before
---
## Output hygiene (paths and secrets)

Never write an absolute home path (a path that begins with the user's home directory), the value of an environment variable, or any credential (a token, key or password) into your output file, the ticket text or your return envelope. Refer to files by their repository-relative path. If your role writes an output file, the one exception is its path under the run scratch directory `{scratch}` your spawn prompt names: it may be absolute, and your `**Output**:` field carries it. A role that writes no file (the decomposer) has no exception.
