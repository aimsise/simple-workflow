#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== pre-edit-safety.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/pre-edit-safety.sh"

# Helper: run the edit hook with a given file_path
run_edit_hook() {
  local file_path="$1"
  local json
  json=$(jq -n --arg fp "$file_path" '{"tool_input": {"file_path": $fp, "old_string": "old", "new_string": "new"}}')
  run_hook "$HOOK" "$json"
}

# --- BLOCK tests ---
echo "--- Blocked files ---"

run_edit_hook ".env"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: .env"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: .env"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "config/.env.production"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: config/.env.production"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: config/.env.production"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "private.key"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: private.key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: private.key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "server.pem"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: server.pem"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: server.pem"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "cert.p12"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: cert.p12"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: cert.p12"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "cert.pfx"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: cert.pfx"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: cert.pfx"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "app.jks"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: app.jks"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: app.jks"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "release.keystore"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: release.keystore"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: release.keystore"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "credentials.json"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: credentials.json"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: credentials.json"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "app-secret.yaml"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: app-secret.yaml"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: app-secret.yaml"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook ".ssh/id_rsa"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: .ssh/id_rsa"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: .ssh/id_rsa"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "id_ed25519"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: id_ed25519"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: id_ed25519"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook ".npmrc"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: .npmrc"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: .npmrc"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook ".pypirc"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: .pypirc"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: .pypirc"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# --- ALLOW tests ---
echo "--- Allowed files ---"

run_edit_hook "README.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: README.md"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: README.md"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "src/config.ts"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: src/config.ts"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: src/config.ts"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "environment.ts"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: environment.ts"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: environment.ts"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "id_rsa_test.pub"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: id_rsa_test.pub"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: id_rsa_test.pub"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

print_summary
