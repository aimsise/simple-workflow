# Contributing to simple-workflow

Thank you for your interest in contributing! This guide will help you get started.

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/simple-workflow.git
   cd simple-workflow
   ```
3. Create a feature branch:
   ```bash
   git checkout -b feat/your-feature
   ```

No build step is required — this project consists of shell scripts and Markdown files.

## Repository Structure

```
simple-workflow/
├── agents/           # Claude agent definitions (.md with YAML frontmatter)
├── skills/           # Claude Code skills (each skill has a SKILL.md)
│   └── <name>/
│       └── SKILL.md
├── hooks/            # Lifecycle hook scripts + hooks.json config
├── tests/            # Shell-based test suite
├── .claude-plugin/   # Plugin metadata (plugin.json)
└── .github/          # GitHub templates and CI workflows
```

## Development Guide

### Adding a New Skill

1. Create a directory under `skills/<your-skill-name>/`
2. Add a `SKILL.md` file with YAML frontmatter:
   ```yaml
   ---
   name: your-skill
   description: What the skill does
   ---
   ```
3. Document the skill's behavior in the body of `SKILL.md`

### Adding a New Agent

1. Create `agents/<your-agent-name>.md` with YAML frontmatter:
   ```yaml
   ---
   name: your-agent
   model: sonnet
   description: What the agent does
   ---
   ```

### Adding a New Hook

1. Create a shell script in `hooks/` (e.g., `hooks/your-hook.sh`)
2. Ensure it starts with `#!/usr/bin/env bash` and `set -euo pipefail`
3. Register it in `hooks/hooks.json`
4. Add tests in `tests/test-your-hook.sh`

### Measuring SKILL.md Size

For compression work, measure token count with `tests/helpers/count-tokens.sh` rather than bytes:

```bash
tests/helpers/count-tokens.sh skills/impl/SKILL.md
```

The helper prefers `tiktoken` (cl100k_base) when Python has it installed and falls back to a `chars/4` estimate otherwise. Stdout is a single integer; stderr carries a mode label (`[tiktoken]` or `[fallback: chars/4]`).

Rationale: byte caps invite proxy over-optimization — trimming characters to hit a round byte count rather than compressing redundant prose. Token counts track closer to actual `cache_read` cost, which is what compression is ultimately trying to reduce.

## Testing

Run the full test suite:

```bash
bash tests/run-all.sh
```

**Dependencies:** `jq`, `git`

Tests follow the pattern in `tests/test-helper.sh`, using `assert_allowed`, `assert_blocked`, and `assert_blocked_message` helpers.

## Code Style

- Shell scripts must pass [ShellCheck](https://www.shellcheck.net/) (`--severity=warning`)
- Use `set -euo pipefail` at the top of all shell scripts
- Use conventional commit prefixes: `feat:`, `fix:`, `docs:`, `test:`, `chore:`

## Pull Request Process

1. Ensure all tests pass: `bash tests/run-all.sh`
2. Ensure ShellCheck passes: `shellcheck --severity=warning hooks/*.sh tests/*.sh`
3. Create a PR to `main` with a clear description
4. Fill out the PR template

## Questions?

For usage questions and general discussion, please use [GitHub Discussions](https://github.com/aimsise/simple-workflow/discussions) instead of opening an issue.
