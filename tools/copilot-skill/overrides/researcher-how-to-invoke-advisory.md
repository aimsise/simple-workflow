target: references/agents/researcher.md
heading: ### How to invoke each Advisory entry (deferred-tool resolution, capability-name-agnostic)
mode: replace
---
### How to invoke each Advisory entry (capability-name-agnostic)

The translation depends ONLY on the Advisory table's `Type` column, so a user-installed skill or a user-added MCP server is handled identically — there is no skill-name-specific or server-name-specific branch:

1. **`Type = skill`** — load the skill named in `Name`, exactly as listed, the way this host offers skills (for example by reading `<skill root>/<Name>/SKILL.md` from the root the `Available user skills:` probe found it under) and follow it.
2. **`Type = MCP`** — the entry's `Name` identifies the MCP server and tool; call that tool directly under the name the host exposes it by. Use `Name` verbatim from the Advisory table — do NOT paraphrase, shorten, or substitute a similar name.
3. **Either type, environmental failure** — if the skill is not installed, the MCP tool is not exposed to you, or the MCP server is unreachable at invocation time, record a one-line rationale under `### Limitations` of your investigation output file (or, fallback, in the return-envelope `**Advisory consultation**:` bullet for that entry) and continue. Environmental failure is an acceptable skip reason under the consultation discipline above; do NOT block the investigation on a missing Advisory tool.

- The Advisory block has shape `Name | Type | Purpose | Used by` (no `Bound AC(s)` column). Entries whose `Used by` column lists `researcher` are the ones you may invoke; entries listing only `implementer` / `test-writer` are for downstream productive roles and are out of scope for you.
- Treat Advisory entries as **reference / guidance** tools — for example a library-documentation MCP tool for looking up a library's current API surface during investigation, or a UI/UX skill for understanding existing UI patterns before recommending a new one (illustrative only). Use them to inform `investigation.md`'s findings; do NOT use them to fabricate evidence the codebase does not actually contain.
- When the spawn prompt says `## Advisory capabilities (per ticket): (none)`, the Advisory pathway is empty for this ticket; the speculative-invocation ban applies in full.
