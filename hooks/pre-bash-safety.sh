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

exit 0
