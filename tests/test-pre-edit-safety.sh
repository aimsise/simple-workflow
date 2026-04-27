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

# --- PII / absolute-home-path tests ---
echo "--- PII (absolute home path) ---"

# Helper: invoke the hook with file_path + new_string (old_string left empty)
run_edit_hook_with_new_string() {
  local file_path="$1"
  local new_string="$2"
  local json
  json=$(jq -n --arg fp "$file_path" --arg ns "$new_string" \
    '{"tool_input": {"file_path": $fp, "old_string": "", "new_string": $ns}}')
  run_hook "$HOOK" "$json"
}

assert_pii_block_edit() {
  local description="$1"
  local file_path="$2"
  local new_string="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_edit_hook_with_new_string "$file_path" "$new_string"
  if [ "$LAST_EXIT_CODE" -ne 0 ] && echo "$LAST_STDERR" | grep -qF "pii: absolute home path detected"; then
    echo -e "  ${GREEN}PASS${NC} BLOCK (pii): $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} BLOCK (pii): $description"
    echo -e "       Expected: non-zero exit + 'pii: absolute home path detected' in stderr"
    echo -e "       Got: exit $LAST_EXIT_CODE; stderr=$LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_pii_allow_edit() {
  local description="$1"
  local file_path="$2"
  local new_string="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_edit_hook_with_new_string "$file_path" "$new_string"
  if [ "$LAST_EXIT_CODE" -eq 0 ] && ! echo "$LAST_STDERR" | grep -qF "pii:"; then
    echo -e "  ${GREEN}PASS${NC} ALLOW (pii): $description"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} ALLOW (pii): $description"
    echo -e "       Expected: exit 0 with no 'pii:' in stderr"
    echo -e "       Got: exit $LAST_EXIT_CODE; stderr=$LAST_STDERR"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# AC 3: /Users/<name>/ in new_string is rejected
assert_pii_block_edit "AC3: /Users/<name>/ in new_string rejected" \
  "notes/example.md" \
  "see /Users/alice/projects/foo/bar.md"

# AC 2 (edit-side mirror): /home/<name>/ rejected
assert_pii_block_edit "AC2-edit: /home/<name>/ rejected" \
  "notes/example.md" \
  "deploy: /home/bob/work/output.log"

# AC 5: <repo>/... only new_string is allowed
assert_pii_allow_edit "AC5: <repo>/... only new_string allowed" \
  "notes/example.md" \
  "see <repo>/some/path/foo.md"

# Negative AC 6: fenced /Users/runner/work/ inside new_string is allowed
fenced_ns='outside line
```
build log: /Users/runner/work/repo/file.txt
```
trailing'
assert_pii_allow_edit "Neg AC6: fenced /Users/runner/work/ allowed" \
  "CHANGELOG.md" \
  "$fenced_ns"

# Negative AC 2: lowercase /users/foo/bar is not flagged
assert_pii_allow_edit "Neg AC2: lowercase /users/foo/bar allowed" \
  "notes/case.md" \
  "see /users/foo/bar"

# Negative AC 5: lowercase /users/runner/work/ is not flagged
assert_pii_allow_edit "Neg AC5: lowercase /users/runner/work/ allowed" \
  "notes/case.md" \
  "see /users/runner/work/"

# Edit-side .gitignore allowlist
assert_pii_allow_edit "Neg AC3 (edit): .gitignore allowlist" \
  ".gitignore" \
  "/Users/runner/work/cache"

# Windows backslash path
assert_pii_allow_edit "Neg AC4 (edit): Windows C:\\Users\\foo\\ allowed" \
  "notes/win.md" \
  'reference: C:\Users\foo\file.txt'

# Edge Case 1: /Users/ at EOL
assert_pii_allow_edit "Edge1 (edit): /Users/ at EOL allowed" \
  "notes/eol.md" \
  "trailing token: /Users/"

# Edge Case 2: <repo> + real home path on different lines still rejected
assert_pii_block_edit "Edge2 (edit): <repo> does not whitelist real home path" \
  "notes/mixed.md" \
  "first line: <repo>/foo.md
second line: /Users/charlie/bin/tool"

# Edge Case 3: empty new_string is allowed
assert_pii_allow_edit "Edge3 (edit): empty new_string allowed" \
  "notes/empty.md" \
  ""

echo ""

print_summary
