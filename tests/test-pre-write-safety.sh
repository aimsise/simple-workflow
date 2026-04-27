#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== pre-write-safety.sh Tests ==="
echo ""

HOOK="$HOOK_DIR/pre-write-safety.sh"

# Helper: run the write hook with a given file_path
run_write_hook() {
  local file_path="$1"
  local json
  json=$(jq -n --arg fp "$file_path" '{"tool_input": {"file_path": $fp, "content": "test content"}}')
  run_hook "$HOOK" "$json"
}

# --- BLOCK tests ---
echo "--- Blocked files ---"

run_write_hook ".env"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: .env"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: .env"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "config/.env.production"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: config/.env.production"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: config/.env.production"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "private.key"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: private.key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: private.key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "server.pem"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: server.pem"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: server.pem"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "cert.p12"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: cert.p12"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: cert.p12"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "cert.pfx"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: cert.pfx"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: cert.pfx"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "app.jks"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: app.jks"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: app.jks"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "release.keystore"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: release.keystore"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: release.keystore"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "credentials.json"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: credentials.json"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: credentials.json"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "app-secret.yaml"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: app-secret.yaml"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: app-secret.yaml"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook ".ssh/id_rsa"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: .ssh/id_rsa"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: .ssh/id_rsa"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "id_ed25519"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: id_ed25519"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: id_ed25519"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook ".npmrc"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: .npmrc"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: .npmrc"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook ".pypirc"
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

run_write_hook "README.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: README.md"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: README.md"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "src/config.ts"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: src/config.ts"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: src/config.ts"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "environment.ts"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: environment.ts"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: environment.ts"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_write_hook "id_rsa_test.pub"
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

# Helper: invoke the hook with file_path + content
run_write_hook_with_content() {
  local file_path="$1"
  local content="$2"
  local json
  json=$(jq -n --arg fp "$file_path" --arg c "$content" \
    '{"tool_input": {"file_path": $fp, "content": $c}}')
  run_hook "$HOOK" "$json"
}

# Assertion helpers scoped to the PII suite
assert_pii_block() {
  local description="$1"
  local file_path="$2"
  local content="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_write_hook_with_content "$file_path" "$content"
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

assert_pii_allow() {
  local description="$1"
  local file_path="$2"
  local content="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  run_write_hook_with_content "$file_path" "$content"
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

# AC 1: /Users/<name>/ in plain content is rejected
assert_pii_block "AC1: /Users/<name>/ rejected" \
  ".simple-workflow/backlog/active/foo/bar/plan.md" \
  "see /Users/alice/projects/foo/bar.md"

# AC 2: /home/<name>/ in plain content is rejected
assert_pii_block "AC2: /home/<name>/ rejected" \
  "notes/example.md" \
  "log path: /home/bob/work/output.log"

# AC 4: <repo>/... only content is allowed
assert_pii_allow "AC4: <repo>/... only content allowed" \
  "notes/example.md" \
  "see <repo>/some/path/foo.md"

# Negative AC 1: /Users/runner/work/ inside fenced code block is allowed
fenced_block_content='outside line
```
build log: /Users/runner/work/repo/file.txt
```
trailing'
assert_pii_allow "Neg AC1: fenced /Users/runner/work/ allowed" \
  "CHANGELOG.md" \
  "$fenced_block_content"

# Negative AC 3: .gitignore filename is allowlisted even with /Users/runner/work/
assert_pii_allow "Neg AC3: .gitignore allowlist" \
  ".gitignore" \
  "/Users/runner/work/cache"

# Negative AC 4: Windows backslash path is not flagged
assert_pii_allow "Neg AC4: Windows C:\\Users\\foo\\ allowed" \
  "notes/win.md" \
  'reference: C:\Users\foo\file.txt'

# Negative AC 2/5: lowercase /users/ is not flagged (case-sensitive)
assert_pii_allow "Neg AC2/5: lowercase /users/ allowed" \
  "notes/case.md" \
  "see /users/foo/bar"

# Edge Case 1: /Users/ followed by EOL (no username segment) is allowed
assert_pii_allow "Edge1: /Users/ at EOL allowed" \
  "notes/eol.md" \
  "trailing token: /Users/"

# Edge Case 2: home path AND <repo> on different lines still rejected
assert_pii_block "Edge2: <repo> does not whitelist real home path" \
  "notes/mixed.md" \
  "first line: <repo>/foo.md
second line: /Users/charlie/bin/tool"

# Edge Case 3: empty content is allowed
assert_pii_allow "Edge3: empty content allowed" \
  "notes/empty.md" \
  ""

# Negative AC 6 (mirrors fenced exemption for write side): fenced /Users/runner/work/
nested_fence='preamble
```bash
echo /Users/runner/work/build/output
```
postamble'
assert_pii_allow "Neg AC6 (write): fenced /Users/runner/work/ in code block allowed" \
  "docs/log.md" \
  "$nested_fence"

echo ""

print_summary
