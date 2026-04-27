#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Sensitive file patterns (aligned with pre-bash-safety.sh)
SENSITIVE='(\.(env|key|pem|p12|pfx|jks|keystore)\b|credentials\b|secret\b|id_rsa\b|id_ed25519\b|id_ecdsa\b|\.npmrc$|\.pypirc$)'

if echo "$FILE_PATH" | grep -qiE "$SENSITIVE"; then
  echo "Blocked: editing sensitive file not allowed: $FILE_PATH" >&2
  exit 2
fi

# PII guard: reject absolute home paths ( /Users/<name>/... or /home/<name>/... )
# in the new_string field. Triple-backtick fenced code blocks are skipped, and
# `.gitignore` is allowlisted (it legitimately stores absolute paths).
BASENAME=$(basename "$FILE_PATH")
if [ "$BASENAME" != ".gitignore" ]; then
  NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
  if [ -n "$NEW_STRING" ]; then
    if printf '%s' "$NEW_STRING" | awk '
      BEGIN {
        fenced = 0
        hit = 0
        re = "(/Users/[^/]+/|/home/[^/]+/)"
      }
      /^[[:space:]]*```/ { fenced = 1 - fenced; next }
      {
        if (!fenced && match($0, re)) {
          hit = 1
          exit
        }
      }
      END { exit (hit ? 0 : 1) }
    '; then
      echo "pii: absolute home path detected in $FILE_PATH" >&2
      exit 2
    fi
  fi
fi

exit 0
