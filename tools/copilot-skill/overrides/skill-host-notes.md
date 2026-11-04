target: SKILL.md
heading: (end of file)
mode: append
---
## Host notes

This skill runs with no hooks installed, so these guarantees rest on these instructions alone:

- **Tool names**: the tool names used here (`bash`, `view`, `create`, `edit`, `grep`, `glob`, `task`, `ask_user`) are those GitHub Copilot CLI lists; on another Copilot surface with equivalent read / write / shell / subagent / ask-user tools, map each name to that surface's tool.
- **PII and secrets**: never write an absolute home path (a path that begins with the user's home directory) into any generated file, spawn prompt, ticket or summary. Two exceptions: `{scratch}` (Argument Parsing) may be absolute (it lies under the system temporary directory, which may itself lie under the home directory when `TMPDIR` points there) and appears inside spawn prompts and in the Final summary's "saved at" and `Scratch:` lines; a `brief=` / `findings=` path is the user's own input and is echoed exactly as the user typed it in error lines and the Final summary. Neither is ever written into a ticket or sent to a destination. Pass the rubric as `{rubric_path}` (Pre-computed Context: `{skill_root}` as found, repository-relative or `~`-prefixed), never expanded. The same holds for secrets: the value of the variable an `api:` destination's `auth_env=` names, and any other token, never appears in a prompt, ticket, summary, error line or file; a `bash` command refers to it only as `$VAR` (see `references/destinations.md`).
- **Shell commands**: this skill declares no `allowed-tools`, so every shell command (`date`, `mktemp`, `ls`, `mkdir`, `mv`, `printf`, `git`, `curl`, `jq`) goes through the host's own permission prompt. Approve only the commands the steps above name.
- **File access and approvals**: `view` and `create` must be able to reach the system temporary directory (`{scratch}`) in every mode, so allow it when the host limits file access to the repository. With `confirm=yes`, the `api:` adapter's shell commands (`jq`, `curl`) still go through the host's permission prompts unless the host pre-approves them.
- **Remote creates are not transactional**: an `mcp:` or `api:` destination cannot roll back, so a failure part-way leaves the items already created in place; the run prints their identifiers and stops (Step DL-4).
- **Evaluator independence**: the ticket-evaluator is hermetic by instruction only. A general-purpose `task` subagent carries every tool; its prompt (`references/agents/ticket-evaluator.md`) forbids reading any file other than the ticket inlined in that prompt, and the orchestrator inlines both the ticket and the rubric so the evaluator never needs to.
