#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Sensitive file patterns (aligned with pre-bash-safety.sh)
SENSITIVE='(\.(env|key|pem|p12|pfx|jks|keystore)\b|credentials\b|secret\b|id_rsa\b|id_ed25519\b|id_ecdsa\b|\.npmrc$|\.pypirc$)'

if echo "$FILE_PATH" | grep -qiE "$SENSITIVE"; then
  echo "Blocked: writing to sensitive file not allowed: $FILE_PATH" >&2
  exit 2
fi

exit 0
