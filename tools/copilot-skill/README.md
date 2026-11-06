# Standalone skill generator inputs

`tools/build-copilot-skill.sh` turns this plugin's ticket-creation workflow into a single, self-contained, host-neutral Agent Skill, `create-ticket/` (a `SKILL.md` plus `references/`). The generated skill needs no plugin, no hooks and no custom agent files (Python 3 only to read `.xlsx` sources), and it names tools by role (see `## Tool roles` below) rather than by any host's tool name: copy the directory into the skill root the host reads (`.github/skills/`, `.claude/skills/` or `.agents/skills/`) and invoke it by name. The generator keeps its historical name; its output was first shaped for GitHub Copilot CLI and has not been run live on any host yet.

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
4. **Exit audit**: `denylist.txt` (any hit fails), the host tool names of `tool-vocabulary.txt` (Claude Code and GitHub Copilot names alike), a non-English (CJK) byte scan, link and `references/...` path resolution, balanced inline code spans, the frontmatter contract (`name`, `description` length, no `allowed-tools`), and rubric parity for `references/ac-quality-criteria.md` (same Gate headings, same Terminology entry count, word count within 5% of the source). The rubric files are zero-loss in intent: never delete a gate, an example or a rule; rename tokens, and restate a host-bound sentence (a role, a tool-access rule, a file or setting this host does not have) so it is true on any host.

Agent files listed under `references/agents/` lose their frontmatter; the body is the prompt the generated skill hands to a general-purpose subagent through the host's subagent tool.

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
| `tool-vocabulary.txt` | `deny <name>` |

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

## Sources (intake)

`source=<spec>` tokens (repeatable, any mode) let the user hand the skill its input material instead of a pre-written brief or findings file: `file:<path>` (Markdown, text, CSV, TSV, JSON, YAML, or an `.xlsx` workbook read as a workbook), `dir:<path>`, `mcp:<server>/<tool>[?name=value]` (one read-only call) and `api:<url>` (one `GET`, `source_auth_env=` for the token). The contract lives in `references/sources.md` (`overrides/sources.md`, a file with no upstream source), the sequence in SKILL.md `## Intake` (`overrides/skill-intake.md`), and the partition decision in the decomposer (`overrides/decomposer-source-dossier.md`, `overrides/spec-decomposer-source-dossier.md`): the decomposer judges whether one source enumerates the work units (then they map to tickets one-to-one) or whether every source is context, and reports `Partition basis`. The workbook converter `scripts/xlsx_to_text.py` (`overrides/scripts-xlsx-to-text.md`) uses only the Python 3 standard library; the test builds a fixture workbook with the same library and checks its output. The upstream `/create-ticket` has no `source=`; the feature exists only in the generated skill.

Later additions on the same layer: the default destination is `local:.docs/tickets`; `parent=<id>` links delivered items to an existing platform item through the create tool's parent-link parameter (found by its description) or the `{parent}` template placeholder; `?sheet=<name>` on an `.xlsx` source selects worksheets (`--sheet` on the converter); the request's input and output may be stated in prose, resolved to the canonical tokens before the token scan and echoed as a `Resolved:` line; user paths and names follow a character exclusion rule instead of an ASCII-only pattern, so names in any script are accepted.

## Skill README

The run scratch directory (`{scratch}`, every transient file of a run) is created with `mktemp -d` under `.create-ticket-scratch/` inside the working directory and added to the repository's `.gitignore`, never under a system temporary directory: the first live run showed that a host may confine the file tools of the orchestrator and of every subagent to the working directory, so a scratch outside it cannot be written or cannot be read back. The same run showed the researcher running the product's test suite and a delete command on a directory of its own, so `overrides/agents-side-effect-ban.md` names execution of the product and delete commands explicitly, and Phase 4 now spawns every ticket's evaluator in one message.

The generated directory ships its own `README.md` (`overrides/readme.md`, a file with no upstream source): install, host requirements, usage, the three modes, sources, destinations, the other options, the verdicts, the file map and the limits, written for the person who receives the directory and never sees this repository. It is subject to the same exit audit as every generated file (no host name, no upstream name, every relative link resolves), and the test checks its sections.

## Self-contained vocabulary

Every term in the generated tree must be resolvable from the tree alone. The denylist therefore also rejects plugin-internal jargon that nothing in the tree defines: the implementation-time eval panel and its lens names, the evidence-floor shorthands, the lettered failure-class codes, the plugin's downstream role names (the rubric defines one phrase instead, the **downstream implementer/verifier**), `load-bearing`, `plan.md`, a mid-sentence `Read` (the Claude Code tool name), the generator's own paths and the old `Stopped:` message. The rubric's kill switches are real on this host: a `constraint_<key>=off` request token turns a gate off for the whole run, and Argument Parsing rejects an unknown key.

## Tool roles

The generated text never names a host's tool. It names eight roles, defined once in `SKILL.md` `## Host notes` (**Tool roles**): the file-read tool, the file-write tool, the file-edit tool, the search tools, the shell tool, the URL-fetch tool, the subagent tool and the ask-user tool. The skill resolves each role to one concrete tool of the host before Phase 1; a host without a subagent tool takes the degraded branch (`SELF-EVALUATED`), a host without an ask-user tool takes the non-interactive fallbacks. The frontmatter `compatibility:` states the same requirements without naming a host, and the denylist rejects `Copilot`, `GitHub.com`, `cloud agent`, `agent_type` and the "on this surface" phrasing of the earlier Copilot-bound output, while `tool-vocabulary.txt` rejects every backticked Claude Code and GitHub Copilot tool name. When a new manifest line has to mention a tool, write the role phrase ("read it with the file-read tool", "via the subagent tool"), never a product's tool name. The vocabulary denylist matches the exact backticked token, so a future upstream example that legitimately backticks a common word such as `create`, `edit`, `view` or `task` fails the build with a "foreign tool name" finding: restate the example or re-anchor the row, as for any stale manifest line.
