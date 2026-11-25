target: references/agent-spawn-prompts.md
heading: ### Partition is owned by the decomposer (all modes)
mode: before
---
**Draft file** (every planner spawn: this Phase 3 spawn and step b of the Phase 4 retry-with-feedback loop): the spawn prompt carries the literal instruction "Your output file holds the ticket and nothing else: its first line is the ticket's `## <logical id>: <Title>` heading of `references/ticket-template.md`, the text is not wrapped in a code fence, and notes, analysis, file contents and your return envelope never go into it. A change rationale is one line that starts with `Change rationale:`, or one `<!-- Change rationale: ... -->` comment." When the planner returns, the orchestrator checks that file as SKILL.md Phase 4 **Graded draft** says.
