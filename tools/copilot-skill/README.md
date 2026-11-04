# Copilot skill generator inputs

`tools/build-copilot-skill.sh` turns this plugin's ticket-creation workflow into a single, self-contained GitHub Copilot Agent Skill, `create-ticket/` (a `SKILL.md` plus `references/`). The generated skill needs no plugin, no hooks and no custom agent files: copy the directory into another repository's `.github/skills/` and invoke it from GitHub Copilot CLI or VS Code.

```bash
bash tools/build-copilot-skill.sh --out <dir>            # writes <dir>/create-ticket/
bash tools/build-copilot-skill.sh --out <dir> --force    # replaces a non-empty <dir>/create-ticket/
bash tools/build-copilot-skill.sh --help
```

The output is never committed (there is no golden copy). Its correctness is enforced by the build's own exit audit and by `tests/test-copilot-skill-build.sh`, which builds into a temporary directory and re-checks the result independently.

## What the generator does

For every file in `files.tsv` it applies four layers, in this order:

1. **Sections** (`drop-sections.txt`, `overrides/*.md`): drop or replace a section by its exact heading line, insert new content before a heading, or append content at the end of a file. A section runs to the next heading of the same or a higher level at the same fence depth, so a heading inside a fenced template never swallows the fence that closes it.
2. **Paragraphs** (`drop-paragraphs.txt`): drop by anchor ERE. A hit on a list item drops that item, a hit on a table row or on a line inside a fenced block drops that line, and any other hit drops the whole paragraph.
3. **Substitutions** (`substitutions.tsv`): `sed -E` rewrites applied in file order. Specific sentence rewrites come first, then paths, tool names and the pipeline role phrases.
4. **Exit audit**: `denylist.txt` (any hit fails), the foreign tool names of `tool-vocabulary.txt`, a non-English (CJK) byte scan, link and `references/...` path resolution, balanced inline code spans, the frontmatter contract (`name`, `description` length, no `allowed-tools`), and rubric parity for `references/ac-quality-criteria.md` (same Gate headings, same Terminology entry count, word count within 5% of the source). The rubric files are zero-loss in intent: never delete a gate, an example or a rule; rename tokens, and restate a host-bound sentence (a role, a tool-access rule, a file or setting this host does not have) so it is true on the Copilot host.

Agent files listed under `references/agents/` lose their frontmatter; the body is the prompt the generated skill hands to a `task` subagent.

## Maintenance model

Re-run the build after any change to the shipped sources. If the audit fails, add a manifest line: a substitution for a renamed token, a paragraph or section drop for host-only machinery, or an override for a section that needs a host-specific rewrite. Every manifest line must match at least once in its scope; a stale line fails the build too, so delete the line when its source text is gone.

## Manifest formats

All manifests are plain text; `#` comment lines and blank lines are ignored. Patterns are POSIX ERE evaluated with `LC_ALL=C` (no `\b`, `\s` or `\w` in substitutions, since BSD `sed -E` lacks them).

| File | Line format |
|---|---|
| `files.tsv` | `<destination under create-ticket/><TAB><source relative to --src>`, or `-` as the source for a file with no plugin source (it starts empty, one `append` override supplies its whole content, and a `-` file left empty fails the build) |
| `drop-sections.txt` | `<destination glob><TAB><exact heading line>` |
| `drop-paragraphs.txt` | `<destination glob><TAB><anchor ERE>` |
| `substitutions.tsv` | `<ERE><TAB><replacement>[<TAB><destination glob>]` (sed replacement syntax; default scope is every file) |
| `denylist.txt` | `<ERE>` |
| `tool-vocabulary.txt` | `allow <name>` or `deny <name>` |

An override file starts with three header lines and a `---` separator; everything after the separator is the content:

```text
target: <destination> [<destination> ...]
heading: <exact heading line> | (frontmatter) | (end of file)
mode: replace | before | after | append
---
<content>
```

`replace` swaps the whole section (heading included) for the content, `before` / `after` insert the content around the section, and `append` adds the content at the end of the file. The frontmatter override may use the placeholders `@SOURCE_VERSION@`, filled from `.claude-plugin/plugin.json`, and `@SOURCE_COMMIT@`, filled with the short commit of `--src` (`git rev-parse --short HEAD`; the literal `unknown` when `--src` is not a git repository or git is unavailable).

## Delivery and destinations

The generated skill is decoupled from this repository's own backlog layout: producing the tickets (Phases 1-4, the four agent prompts, the rubric and grading files) is unchanged, while the upstream write path is replaced whole by a `## Delivery` section (`overrides/skill-delivery.md`) and the destination adapters live in `references/destinations.md`, a file with no upstream source (`overrides/destinations.md`). The skill takes `destination=local:<dir>` (default `local:tickets`), `destination=mcp:<server>[/<tool>]` or `destination=api:<url>`. The denylist rejects the plugin name, its backlog paths, `{ticket-dir}` and the dropped investigation-reuse key, so an upstream edit that reintroduces them fails the build.
