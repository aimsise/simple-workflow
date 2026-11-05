target: references/agents/decomposer.md
heading: ## Decomposition principles
mode: before
---
## Source dossier handling

The caller may append a section `## Source dossier` to either input form: the concatenation of every source the user handed in (documents, spreadsheets dumped as Markdown tables whose first column is the worksheet row number, MCP tool results, HTTP documents), each preceded by a header block (`Source: S<n>` on its line 1, then `Kind:`, `Origin:`, `Fetched:`, `Chars:`, `Truncated:`). A **locator** names lines of one source: `S<n>:L<a>-L<b>`, `S<n>:L<a>` or `S<n>`, counting from that source's `Source:` line as line 1.

When the section is present you MUST:

1. **Decide the partition basis** (only under the header `Dossier role: candidate`, which the caller sets in Form B for a bare or absent description; `Dossier role: context`, set with a brief, and Form A keep their basis and skip this step; a `## Source dossier` without a `Dossier role:` header is treated as `context` and the omission is noted in `**Rationale**`). A source, or one part of it (a sheet, a section, a list), is **partition-authoritative** when it enumerates two or more discrete items that each state their own scope and outcome as work still to be done (illustrative only: a backlog sheet with one row per item, a numbered requirements list, a task list). It is **context** when it describes one deliverable's attributes (a field list, a configuration table), defines terms, records finished work (a status table of done items, a changelog) or narrates without enumerating work. When exactly one part qualifies, map its items to tickets one-to-one, as `## Required Work Units` are mapped in Form A (the merge, cap and overflow rules apply unchanged), and report `**Partition basis**: <locator of that part>`. When no part qualifies, enumerate the work units yourself from the whole context and report `**Partition basis**: derived`. When two or more parts qualify, take the one whose items carry the most scope and outcome detail (ties: the earliest in the dossier), report it, and name the alternative in `**Rationale**`; never merge two candidate lists into one. Form A always reports `**Partition basis**: findings`; Form B under `Dossier role: context` always reports `**Partition basis**: brief`.
2. **Cite the dossier per ticket.** Give every ticket a sub-line `source_refs: [<locator>, ...]` naming the lines of the dossier its scope rests on (for a partition-authoritative part, at least the item's own lines); `source_refs: []` for a ticket that rests on none.
3. **Treat a truncation as a gap.** A `[truncated: ...]` line or `Truncated: yes` means the source continues beyond what you see: say so in `**Rationale**` when the cut part could hold more items, and never guess at what was cut.
4. **Ground in the dossier as in any context.** The dossier extends the grounding rule of `## Hard constraints`: a work unit present (or directly entailed) in `## Source dossier` is grounded; a work unit the dossier does not support is not.

Place `**Partition basis**:` right after `**Rationale**:` in your `## Result`. The 1000-token cap still applies: locators and ids only, never dossier text.
