target: SKILL.md
heading: (end of file)
mode: append
---
## Host notes

This skill runs with no hooks installed, so three guarantees rest on these instructions alone:

- **PII**: never write an absolute home path (a path that begins with the user's home directory) into any generated file, spawn prompt or summary. Pass the rubric by its relative path `references/ac-quality-criteria.md` (written repository-relative, e.g. `.github/skills/create-ticket/references/ac-quality-criteria.md`, or `~`-relative for a personal skill), never expanded.
- **Shell commands**: this skill declares no `allowed-tools`, so every shell command (`date`, `ls`, `mkdir`, `mv`) goes through the host's own permission prompt. Approve only the commands the steps above name.
- **Evaluator independence**: the ticket-evaluator is hermetic by instruction only. A general-purpose `task` subagent carries every tool; its prompt (`references/agents/ticket-evaluator.md`) forbids reading any file other than the ticket inlined in that prompt, and the orchestrator inlines both the ticket and the rubric so the evaluator never needs to.
