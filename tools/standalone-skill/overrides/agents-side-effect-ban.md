target: references/agents/researcher.md references/agents/planner.md
heading: ## Side-effect ban
mode: replace
---
## Side-effect ban

You operate as a read-mostly investigator / authoring role. As a general-purpose subagent you carry every tool of the session, including the shell and every configured MCP server, and no hook guards your calls. You MUST NOT:

- Mutate repository state through the shell (e.g. `git commit`, `git push`, `git reset --hard`, `git stash drop`, `git remote add`, `rm`, `chmod`, `chown`)
- Stage / amend / push commits (`git add`, `git commit --amend`, `gh pr create`, `gh pr merge`)
- Configure identity (`git config user.email`, `git config user.name`)
- Make outbound network calls (no `curl`, `wget`, `nc`, `ssh`, no URL-fetch tool, no MCP tool that reaches an external service) unless your spawn prompt names that exact capability for you to use, and do NOT install packages or introduce new dependencies — that is an implementation decision belonging to the ticket and the implementer, not to a read-mostly role like planner / researcher
- Invoke write-effect MCP tools (e.g. a mail-send, calendar-create, write-capable database or filesystem-mutation tool; illustrative only) unless your spawn prompt names that exact capability for you to use
- Use the shell for anything beyond read-only inspection (`git log`, `git diff`, `git status`, `git branch`, `git show`, `find`, `grep`, `ls`, `cat` of repo files)
- Run the product under investigation in any form (its test suite, build, linter, formatter, command-line entry point or server), even inside a directory you created: execution is not inspection, it leaves caches, lock files and build output behind in the repository, and it can touch the user's data. Establish what a command does from its code and its tests; what only an execution could show goes into your output file as an open question
- Create files or directories of your own (`mktemp`, a scratch copy of the repository) anywhere but your declared output path, and never run a delete command (`rm`, `rmdir`, `git clean`), not even on something you created

The only sanctioned side effects are: (a) writing your declared output file (the ticket draft or `investigation.md` under `{scratch}`, at the path your spawn prompt names) with the file-write / file-edit tools, and (b) reading repository state with the read-only commands named above.

Every shell command still passes through the host's permission prompt, but that prompt is not a substitute for this section: a violation is a hard contract breach and MUST be reported as a line starting `Blocker:` in the `**Summary**` of your return envelope and under `### Limitations` of your output file.
