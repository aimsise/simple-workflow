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

# F-HOOKS-03: legitimate source/doc files that merely CONTAIN "credentials" or
# "secret" in the name must NOT be false-blocked — only secret-bearing
# extensions are. These two ALLOW assertions FAIL under the prior
# `credentials\b|secret\b` regex (revert guard), while `.env` / `.ssh/id_rsa` /
# `credentials.json` / `app-secret.yaml` remain blocked above.
run_edit_hook "credentials.ts"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: credentials.ts (source file, not a secret)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: credentials.ts"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

run_edit_hook "secret.md"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: secret.md (doc file, not a secret)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: secret.md"
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

# UX-11 (proposal 5): jq-missing fail-close is knob-gated (SW_SAFETY_JQ_MISSING_MODE).
# PATH-restricted — an empty dir as PATH hides jq while bash is invoked by absolute
# path so the guard reaches its jq preflight.
_JQ_BASH="$(command -v bash)"
_JQ_NOPATH="$(mktemp -d)"

set +e
_jq_on_out="$(printf '{"tool_input":{"file_path":"x"}}' | env PATH="$_JQ_NOPATH" SW_SAFETY_JQ_MISSING_MODE=on "$_JQ_BASH" "$HOOK" 2>&1)"
_jq_on_rc=$?
set -e
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$_jq_on_rc" -eq 2 ] && printf '%s' "$_jq_on_out" | grep -qF '[SAFETY-JQ-MISSING]'; then
  echo -e "  ${GREEN}PASS${NC} jq-missing + knob=on: fail-closed (exit 2) with [SAFETY-JQ-MISSING] message"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} jq-missing + knob=on: expected exit 2 + message (rc=$_jq_on_rc, out=${_jq_on_out:0:80})"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

set +e
_jq_def_out="$(printf '{"tool_input":{"file_path":"x"}}' | env PATH="$_JQ_NOPATH" "$_JQ_BASH" "$HOOK" 2>&1)"
_jq_def_rc=$?
set -e
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$_jq_def_rc" -eq 0 ] && printf '%s' "$_jq_def_out" | grep -qF 'metric-only'; then
  echo -e "  ${GREEN}PASS${NC} jq-missing + default: metric-only allows (exit 0) with message"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} jq-missing + default: expected exit 0 + metric-only message (rc=$_jq_def_rc)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
rmdir "$_JQ_NOPATH" 2>/dev/null || true

echo ""

# Proposal 4 / ST-03: HOOK_OWNED_FIELDS enforcement is gated by
# SW_STATE_FIELD_GUARD_MODE (default metric-only). With the knob ON, an Edit that
# changes the hook-owned `.runtime_metrics` field on a state file is blocked, and
# the block reason names the violated field AND references docs/state-schema.md.
# Default (metric-only) does NOT block — it logs a [STATE-FIELD-GUARD] line.
_SFG_EDIT_INPUT=$(jq -n \
  --arg fp "/tmp/sfg/autopilot-state.yaml" \
  --arg o 'runtime_metrics: []' \
  --arg n 'runtime_metrics: [{boundary: x}]' \
  '{tool_input:{file_path:$fp, old_string:$o, new_string:$n}}')

set +e
_sfg_on_out="$(printf '%s' "$_SFG_EDIT_INPUT" | env SW_STATE_FIELD_GUARD_MODE=on bash "$HOOK" 2>&1)"
set -e
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if printf '%s' "$_sfg_on_out" | grep -q '"decision":"block"' \
   && printf '%s' "$_sfg_on_out" | grep -q 'hook_owned_field_violation' \
   && printf '%s' "$_sfg_on_out" | grep -q '\.runtime_metrics' \
   && printf '%s' "$_sfg_on_out" | grep -q 'docs/state-schema.md'; then
  echo -e "  ${GREEN}PASS${NC} state-field guard knob=on: .runtime_metrics Edit blocked (reason names field + docs/state-schema.md)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} state-field guard knob=on: expected decision:block with field name + schema ref. out: ${_sfg_on_out:0:140}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

set +e
_sfg_def_out="$(printf '%s' "$_SFG_EDIT_INPUT" | env SW_STATE_FIELD_GUARD_MODE=metric-only bash "$HOOK" 2>&1)"
set -e
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if ! printf '%s' "$_sfg_def_out" | grep -q '"decision":"block"' \
   && printf '%s' "$_sfg_def_out" | grep -q '\[STATE-FIELD-GUARD\] metric-only'; then
  echo -e "  ${GREEN}PASS${NC} state-field guard metric-only (default): .runtime_metrics Edit not blocked, logs would-block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} state-field guard metric-only: expected allow + [STATE-FIELD-GUARD] log. out: ${_sfg_def_out:0:140}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

print_summary
