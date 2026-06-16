#!/usr/bin/env bash
set -euo pipefail

# jq is a documented hard dependency. When it is missing this guard cannot parse
# the tool payload; rather than dying with a silent `exit 127` (which Claude Code
# treats as a non-blocking error — a fail-OPEN), resolve the behaviour through
# SW_SAFETY_JQ_MISSING_MODE (UX-11):
#   on          -> fail CLOSED (exit 2) with an explicit message
#   metric-only -> (default) log the would-be fail-closed and ALLOW (exit 0)
#   off         -> silently allow (exit 0)
# A typo collapses to metric-only (the observe-only default), never to a silent
# fail-open. Default is metric-only so this hardening does not change the shipped
# fail-open behaviour until an operator opts in with `=on` (post-dogfood promote).
if ! command -v jq >/dev/null 2>&1; then
  case "${SW_SAFETY_JQ_MISSING_MODE:-metric-only}" in
    on)
      echo "[SAFETY-JQ-MISSING] pre-bash-safety: jq not found on PATH — failing closed (exit 2). Install jq (e.g. 'brew install jq') to run this guard." >&2
      exit 2 ;;
    off)
      exit 0 ;;
    metric-only|*)
      echo "[SAFETY-JQ-MISSING] metric-only: pre-bash-safety would fail closed (exit 2) — jq not found on PATH; allowing this call. Install jq, or set SW_SAFETY_JQ_MISSING_MODE=on to enforce." >&2
      exit 0 ;;
  esac
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# --- Destructive command patterns ---
# Detect at any token position: start, after pipe, after semicolon, after &&/||
# Optional env/command prefix before the actual destructive command
# `rm -r -f` / `rm -f -r` (and `-r … -f` with intervening flags) are SEPARATED
# short flags that the combined (`-rf`) and long-form alternatives below miss;
# the two `rm\s+-…\s+…-…` alternatives close that gap (F-HOOKS-04).
DESTRUCTIVE='(^|[|;&]|\$\(|`)\s*(env\s+|command\s+)?(rm\s+-[A-Za-z]*[rR][A-Za-z]*f|rm\s+-[A-Za-z]*f[A-Za-z]*[rR]|rm\s+(--recursive\s+--force|--force\s+--recursive|-[A-Za-z]*[rR]\s+--force|--force\s+-[A-Za-z]*[rR]|--recursive\s+-[A-Za-z]*f|-[A-Za-z]*f\s+--recursive)|rm\s+-[A-Za-z]*[rR][A-Za-z]*\s+(-[A-Za-z]+\s+)*-[A-Za-z]*f[A-Za-z]*|rm\s+-[A-Za-z]*f[A-Za-z]*\s+(-[A-Za-z]+\s+)*-[A-Za-z]*[rR][A-Za-z]*|git\s+push\s+(--force|--force-with-lease|-f)\b|git\s+reset\s+--hard|git\s+clean\s+-[A-Za-z]*f|[Dd][Rr][Oo][Pp]\s+([Tt][Aa][Bb][Ll][Ee]|[Dd][Aa][Tt][Aa][Bb][Aa][Ss][Ee]))'

# Strip allowed pattern before checking: git reset --hard origin/<branch>
CHECKED=$(echo "$COMMAND" | sed -E 's/git +reset +--hard +origin\/[A-Za-z0-9._/-]+//g')

if echo "$CHECKED" | grep -qE "$DESTRUCTIVE"; then
  echo "Blocked: destructive command not allowed: $COMMAND" >&2
  exit 2
fi

# --- Indirect destructive patterns (xargs, find -exec) ---
INDIRECT_DESTRUCTIVE='(xargs\s+|find\s+.*-exec\s+)(rm\s+-[A-Za-z]*[rR][A-Za-z]*f|rm\s+-[A-Za-z]*f[A-Za-z]*[rR]|rm\s+(--recursive\s+--force|--force\s+--recursive|-[A-Za-z]*[rR]\s+--force|--force\s+-[A-Za-z]*[rR]|--recursive\s+-[A-Za-z]*f|-[A-Za-z]*f\s+--recursive)|rm\s+-[A-Za-z]*[rR][A-Za-z]*\s+(-[A-Za-z]+\s+)*-[A-Za-z]*f[A-Za-z]*|rm\s+-[A-Za-z]*f[A-Za-z]*\s+(-[A-Za-z]+\s+)*-[A-Za-z]*[rR][A-Za-z]*)|find\s+.*-delete|find\s+.*-exec\s+(bash|sh|zsh|ksh)\s+-c\s+'

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
# The four denylist patterns below are consumed via indirect expansion
# (${!pattern_name}) in the loop that follows; ShellCheck SC2034 cannot trace
# indirect references and false-flags them as unused, so each carries an
# explicit disable. test-pre-bash-safety.sh exercises all four at runtime.
# shellcheck disable=SC2034
NETWORK_EGRESS="(^|[|;&]|\\\$\\(|\`)\\s*${PREFIX}(curl|wget|scp|rsync\\s+.*ssh)\\b"
# shellcheck disable=SC2034
IDENTITY_SPOOF="(^|[|;&]|\\\$\\(|\`)\\s*${PREFIX}git\\s+config\\s+(--global\\s+)?(user\\.email|user\\.name|core\\.hooksPath)\\b"
# shellcheck disable=SC2034
PRIVILEGE_ESC="(^|[|;&]|\\\$\\(|\`)\\s*${PREFIX}(sudo\\b|chmod\\s+777\\b|chown\\s+root\\b)"
# shellcheck disable=SC2034
COMMIT_SUBVERT="(^|[|;&]|\\\$\\(|\`)\\s*${PREFIX}git\\s+(commit\\s+--amend\\b|stash\\s+drop\\b|reflog\\s+expire\\b|push(\\s+.+)*\\s+--no-verify\\b)"

for pattern_name in NETWORK_EGRESS IDENTITY_SPOOF PRIVILEGE_ESC COMMIT_SUBVERT; do
  pattern_value="${!pattern_name}"
  if echo "$COMMAND" | grep -qE "$pattern_value"; then
    echo "Blocked: $pattern_name pattern matched (v8.0.0 defense-in-depth): $COMMAND" >&2
    exit 2
  fi
done

exit 0
