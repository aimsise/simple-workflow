#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# --- Destructive command patterns ---
# Detect at any token position: start, after pipe, after semicolon, after &&/||
# Optional env/command prefix before the actual destructive command
DESTRUCTIVE='(^|[|;&]|\$\(|`)\s*(env\s+|command\s+)?(rm\s+-[A-Za-z]*[rR][A-Za-z]*f|rm\s+-[A-Za-z]*f[A-Za-z]*[rR]|rm\s+(--recursive\s+--force|--force\s+--recursive|-[A-Za-z]*[rR]\s+--force|--force\s+-[A-Za-z]*[rR]|--recursive\s+-[A-Za-z]*f|-[A-Za-z]*f\s+--recursive)|git\s+push\s+(--force|--force-with-lease|-f)\b|git\s+reset\s+--hard|git\s+clean\s+-[A-Za-z]*f|[Dd][Rr][Oo][Pp]\s+([Tt][Aa][Bb][Ll][Ee]|[Dd][Aa][Tt][Aa][Bb][Aa][Ss][Ee]))'

# Strip allowed pattern before checking: git reset --hard origin/<branch>
CHECKED=$(echo "$COMMAND" | sed -E 's/git +reset +--hard +origin\/[A-Za-z0-9._/-]+//g')

if echo "$CHECKED" | grep -qE "$DESTRUCTIVE"; then
  echo "Blocked: destructive command not allowed: $COMMAND" >&2
  exit 2
fi

# --- Indirect destructive patterns (xargs, find -exec) ---
INDIRECT_DESTRUCTIVE='(xargs\s+|find\s+.*-exec\s+)(rm\s+-[A-Za-z]*[rR][A-Za-z]*f|rm\s+-[A-Za-z]*f[A-Za-z]*[rR]|rm\s+(--recursive\s+--force|--force\s+--recursive|-[A-Za-z]*[rR]\s+--force|--force\s+-[A-Za-z]*[rR]|--recursive\s+-[A-Za-z]*f|-[A-Za-z]*f\s+--recursive))|find\s+.*-delete|find\s+.*-exec\s+(bash|sh|zsh|ksh)\s+-c\s+'

if echo "$COMMAND" | grep -qE "$INDIRECT_DESTRUCTIVE"; then
  echo "Blocked: indirect destructive command not allowed: $COMMAND" >&2
  exit 2
fi

# --- Bulk staging guard ---
# git add . or git add -A may accidentally stage sensitive files
BULK_ADD='git\s+add\s+(\.(\s|$)|--all\b|-A\b)'

if echo "$COMMAND" | grep -qE "$BULK_ADD"; then
  # Check if any sensitive files exist in the working tree changes
  SENSITIVE_FILES=$(cd "$(echo "$INPUT" | jq -r '.cwd // "."')" && git status --short 2>/dev/null | grep -iE '\.(env|key|pem|p12|pfx|jks|keystore)$|credentials($|[^a-z])|secret($|[^a-z])|(id_rsa|id_ed25519|id_ecdsa)($|[^a-z0-9_.])|\.npmrc$|\.pypirc$' || true)
  if [ -n "$SENSITIVE_FILES" ]; then
    echo "Blocked: bulk staging (git add . / -A) with sensitive files in working tree: $SENSITIVE_FILES" >&2
    exit 2
  fi
fi

# --- Sensitive file staging patterns ---
# Best-effort filename check; does not catch `git add .` or `git add -A`
SENSITIVE_ADD='git\s+add\s+.*(\.(env|key|pem|p12|pfx|jks|keystore)\b|credentials\b|secret\b|id_rsa\b|id_ed25519\b|id_ecdsa\b|\.npmrc\b|\.pypirc\b)'

if echo "$COMMAND" | grep -qiE "$SENSITIVE_ADD"; then
  echo "Blocked: staging sensitive file not allowed: $COMMAND" >&2
  exit 2
fi

# --- v8.0.0 defense-in-depth denylist ---
# Group A productive agents (implementer / planner / researcher / test-writer)
# now inherit the parent session's full Bash surface (the v7.x scoped
# `Bash(git log|diff|status|branch:*)` allowlist was dropped so MCP servers can
# also be inherited). The patterns below are hook-level back-stops covering
# the categories enumerated by the v8.0.0 release plan:
#
#   1. Network egress      — outbound HTTP(S) and arbitrary remote shells
#                            (curl, wget, scp, rsync via ssh).
#   2. Identity spoofing   — rewriting commit author / email at the git layer
#                            (`git config user.email`, `git config user.name`,
#                            `git config --global *`).
#   3. Privilege escalation — `sudo`, world-writable chmod, root chown.
#   4. Branch / commit subversion — history rewrites and verification bypass
#                            (`git commit --amend`, `git stash drop`,
#                            `git reflog expire`, `git push --no-verify`).
#
# Package-manager installs (`npm install`, `pnpm install`, `yarn add`,
# `pip install`, `gem install`, `cargo install`, `brew install`,
# `apt-get install`, `apk add`, `go install`, `composer require`,
# `bundle install`, `mix deps.get`, `dart pub get`, `conda install`,
# `nuget restore`, etc., across every language) and `git remote add` are
# intentionally NOT blocked — the dev loop relies on autopilot being able
# to install declared dependencies and add remotes without manual `! npm
# install` interruptions. The mitigation against attacker-controlled
# packages from prompt injection lives at the prompt level: the
# `## Bound capabilities (per AC)` discipline and the planner Pre-emit
# Self-Audit step 6(d) constrain what the productive subagent is asked
# to do; the agent body's `## Bound Capabilities (Handoff from
# Orchestrator)` section forbids speculative tool use.
#
# Each pattern uses word boundaries to avoid false positives. Token
# aliases that must literally appear in this file for AC-5 / CT-AN-7
# grep validation:
#   curl  wget  "git config user.email"  "git commit --amend"
#
# v8.0.0 best-effort scope: each pattern accepts a permissive prefix that
# blocks the common obfuscations:
#   - full-path invocation (e.g. `/usr/bin/curl example.com`)
#   - relative-path invocation (e.g. `./curl`, `../bin/curl`,
#     `bin/curl`, `node_modules/.bin/curl`, `~/bin/curl`,
#     `$HOME/bin/curl`)
#   - arbitrary env-var assignments (e.g. `FOO=bar curl example.com`)
#   - command wrappers `env`, `command`, `exec`, `time`, `nice`, `ionice`,
#     `nohup` (e.g. `exec curl example.com`)
#   - flags between `git push` and `--no-verify` at any argument
#     position, including quoted args containing `|` / `;` / `&` (e.g.
#     `git push -u --no-verify origin main` or
#     `git push origin main --no-verify` or
#     `git push 'arg|piped' --no-verify`)
# Out of scope — these are explicitly NOT inspected at the hook layer; the
# agent-body `## Side-effect ban` (planner/researcher) and the
# `## Bound capabilities (per AC)` discipline are the defense layers for
# these cases:
#   - the quoted argument inside `bash -c '...'` / `sh -c '...'`
#   - parenthesised subshell `(cmd)` token-start
#   - brace group `{ cmd; }` token-start
PREFIX='(([A-Za-z_][A-Za-z0-9_]*=\S*|env|command|exec|time|nice|ionice|nohup)\s+)*(\.{0,2}/)?(\S+/)*'
NETWORK_EGRESS="(^|[|;&]|\\\$\\(|\`)\\s*${PREFIX}(curl|wget|scp|rsync\\s+.*ssh)\\b"
IDENTITY_SPOOF="(^|[|;&]|\\\$\\(|\`)\\s*${PREFIX}git\\s+config\\s+(--global\\s+)?(user\\.email|user\\.name|core\\.hooksPath)\\b"
PRIVILEGE_ESC="(^|[|;&]|\\\$\\(|\`)\\s*${PREFIX}(sudo\\b|chmod\\s+777\\b|chown\\s+root\\b)"
COMMIT_SUBVERT="(^|[|;&]|\\\$\\(|\`)\\s*${PREFIX}git\\s+(commit\\s+--amend\\b|stash\\s+drop\\b|reflog\\s+expire\\b|push(\\s+.+)*\\s+--no-verify\\b)"

for pattern_name in NETWORK_EGRESS IDENTITY_SPOOF PRIVILEGE_ESC COMMIT_SUBVERT; do
  pattern_value="${!pattern_name}"
  if echo "$COMMAND" | grep -qE "$pattern_value"; then
    echo "Blocked: $pattern_name pattern matched (v8.0.0 defense-in-depth): $COMMAND" >&2
    exit 2
  fi
done

exit 0
