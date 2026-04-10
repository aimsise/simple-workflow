#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

echo "=== pre-bash-safety.sh Tests ==="
echo ""

# ============================================================
# Category A: Destructive command detection (BLOCK, exit 2)
# ============================================================
echo "--- Category A: Destructive command detection ---"

assert_blocked "BLOCK: rm -rf /path" \
  "rm -rf /some/path"

assert_blocked "BLOCK: rm -fr /path (reversed flags)" \
  "rm -fr /some/path"

assert_blocked "BLOCK: rm -rfi /path (extra flags mixed)" \
  "rm -rfi /some/path"

assert_blocked "BLOCK: rm -rf / (root)" \
  "rm -rf /"

assert_blocked "BLOCK: rm -rf . (current directory)" \
  "rm -rf ."

assert_blocked "BLOCK: git push --force" \
  "git push --force"

assert_blocked "BLOCK: git push --force origin main" \
  "git push --force origin main"

assert_blocked "BLOCK: git push -f" \
  "git push -f"

assert_blocked "BLOCK: git push -f origin feature" \
  "git push -f origin feature"

assert_blocked "BLOCK: git push --force-with-lease" \
  "git push --force-with-lease"

assert_blocked "BLOCK: git push --force-with-lease origin feature" \
  "git push --force-with-lease origin feature"

assert_blocked "BLOCK: git reset --hard" \
  "git reset --hard"

assert_blocked "BLOCK: git reset --hard HEAD" \
  "git reset --hard HEAD"

assert_blocked "BLOCK: git reset --hard HEAD~1" \
  "git reset --hard HEAD~1"

assert_blocked "BLOCK: git reset --hard HEAD~3" \
  "git reset --hard HEAD~3"

assert_blocked "BLOCK: git clean -f" \
  "git clean -f"

assert_blocked "BLOCK: git clean -fd" \
  "git clean -fd"

assert_blocked "BLOCK: git clean -fx" \
  "git clean -fx"

assert_blocked "BLOCK: git clean -xfd" \
  "git clean -xfd"

assert_blocked "BLOCK: DROP TABLE users" \
  "DROP TABLE users"

assert_blocked "BLOCK: DROP DATABASE mydb" \
  "DROP DATABASE mydb"

assert_blocked "BLOCK: DROP TABLE IF EXISTS users" \
  "DROP TABLE IF EXISTS users"

# --- rm uppercase/long-option variants (HIGH-3) ---
assert_blocked "BLOCK: rm -Rf /path (uppercase R)" \
  "rm -Rf /some/path"

assert_blocked "BLOCK: rm -fR /path (uppercase R, reversed)" \
  "rm -fR /some/path"

assert_blocked "BLOCK: rm --recursive --force /path (long options)" \
  "rm --recursive --force /some/path"

assert_blocked "BLOCK: rm --force --recursive /path (long options reversed)" \
  "rm --force --recursive /some/path"

assert_blocked "BLOCK: rm -r --force /path (mixed short+long)" \
  "rm -r --force /some/path"

assert_blocked "BLOCK: rm -R --force /path (mixed short+long uppercase)" \
  "rm -R --force /some/path"

assert_blocked "BLOCK: rm --recursive -f /path (mixed long+short)" \
  "rm --recursive -f /some/path"

assert_blocked "BLOCK: rm -f --recursive /path (mixed short+long reversed)" \
  "rm -f --recursive /some/path"

assert_blocked "BLOCK: rm --force -r /path (mixed long+short reversed)" \
  "rm --force -r /some/path"

assert_blocked "BLOCK: rm --force -R /path (mixed long+short reversed uppercase)" \
  "rm --force -R /some/path"

# --- drop table/database case-insensitive (HIGH-4) ---
assert_blocked "BLOCK: drop table users (lowercase)" \
  "drop table users"

assert_blocked "BLOCK: drop database mydb (lowercase)" \
  "drop database mydb"

assert_blocked "BLOCK: Drop Table users (mixed case)" \
  "Drop Table users"

assert_blocked "BLOCK: drop table IF EXISTS users (lowercase drop)" \
  "drop table IF EXISTS users"

echo ""

# ============================================================
# Category B: Pipe/chain detection (BLOCK)
# ============================================================
echo "--- Category B: Pipe/chain detection ---"

assert_blocked "BLOCK: find . | xargs rm -rf (indirect destructive via xargs)" \
  "find . | xargs rm -rf"

assert_blocked "BLOCK: ls ; rm -rf /tmp" \
  "ls ; rm -rf /tmp"

assert_blocked "BLOCK: make clean && rm -rf build" \
  "make clean && rm -rf build"

assert_blocked "BLOCK: test -f file || rm -rf /path" \
  "test -f file || rm -rf /path"

assert_blocked "BLOCK: echo hello | git push --force" \
  "echo hello | git push --force"

assert_blocked "BLOCK: ls && git reset --hard" \
  "ls && git reset --hard"

echo ""

# ============================================================
# Category C: env/command prefix bypass prevention (BLOCK)
# ============================================================
echo "--- Category C: env/command prefix bypass prevention ---"

assert_blocked "BLOCK: env rm -rf /tmp" \
  "env rm -rf /tmp"

assert_blocked "BLOCK: command rm -rf /tmp" \
  "command rm -rf /tmp"

assert_blocked "BLOCK: env git push --force" \
  "env git push --force"

echo ""

# ============================================================
# Category D: Allowed exceptions (ALLOW, exit 0)
# ============================================================
echo "--- Category D: Allowed exceptions ---"

assert_allowed "ALLOW: git reset --hard origin/main" \
  "git reset --hard origin/main"

assert_allowed "ALLOW: git reset --hard origin/feature-branch" \
  "git reset --hard origin/feature-branch"

assert_allowed "ALLOW: git reset --hard origin/release-1.0.0" \
  "git reset --hard origin/release-1.0.0"

assert_allowed "ALLOW: git reset --hard origin/feature/sub-branch" \
  "git reset --hard origin/feature/sub-branch"

echo ""

# ============================================================
# Category E: Safe commands (ALLOW)
# ============================================================
echo "--- Category E: Safe commands ---"

assert_allowed "ALLOW: rm file.txt (no flags)" \
  "rm file.txt"

assert_allowed "ALLOW: rm -r dir (no -f)" \
  "rm -r dir"

assert_allowed "ALLOW: rm -i file.txt (interactive)" \
  "rm -i file.txt"

assert_allowed "ALLOW: git push origin main (no force)" \
  "git push origin main"

assert_allowed "ALLOW: git push -u origin feature" \
  "git push -u origin feature"

assert_allowed "ALLOW: git push (no args)" \
  "git push"

assert_allowed "ALLOW: git reset HEAD file.txt (no --hard)" \
  "git reset HEAD file.txt"

assert_allowed "ALLOW: git reset --soft HEAD~1" \
  "git reset --soft HEAD~1"

assert_allowed "ALLOW: git reset --mixed HEAD~1" \
  "git reset --mixed HEAD~1"

assert_allowed "ALLOW: git clean -n (dry run)" \
  "git clean -n"

assert_allowed "ALLOW: git clean -d (no -f)" \
  "git clean -d"

assert_allowed "ALLOW: ls -la" \
  "ls -la"

assert_allowed "ALLOW: npm test && echo done" \
  "npm test && echo done"

assert_allowed "ALLOW: grep -r secret src/" \
  "grep -r \"secret\" src/"

assert_allowed "ALLOW: echo 'rm -rf is dangerous' (inside echo args)" \
  "echo \"rm -rf is dangerous\""

assert_allowed "ALLOW: cat rm-rf-notes.txt (rm in filename)" \
  "cat rm-rf-notes.txt"

assert_allowed "ALLOW: git add file.txt (normal add)" \
  "git add file.txt"

# --- False positive prevention (M3) ---
assert_allowed "ALLOW: git add id_rsa_test.pub (public key is safe)" "git add id_rsa_test.pub"
assert_allowed "ALLOW: git add secretariat.md (contains 'secret' but harmless)" "git add secretariat.md"
assert_allowed "ALLOW: git add environment.ts (contains 'env' but wrong extension)" "git add environment.ts"

# --- rm long-option safe variants (HIGH-3 regression guard) ---
assert_allowed "ALLOW: rm --recursive dir (no force)" \
  "rm --recursive /tmp/foo"

assert_allowed "ALLOW: rm --force file (no recursive)" \
  "rm --force /tmp/foo"

# --- Uppercase false positive prevention (CRITICAL-2 regression guard) ---
assert_allowed "ALLOW: git add ENVIRONMENT.ts (uppercase, no dot prefix)" "git add ENVIRONMENT.ts"
assert_allowed "ALLOW: git add SECRETARIAT.md (uppercase, word boundary)" "git add SECRETARIAT.md"
assert_allowed "ALLOW: git add KEY_METRICS.md (uppercase, no dot prefix)" "git add KEY_METRICS.md"

echo ""

# ============================================================
# Category F: Sensitive file staging detection (BLOCK)
# ============================================================
echo "--- Category F: Sensitive file staging detection ---"

assert_blocked "BLOCK: git add .env" \
  "git add .env"

assert_blocked "BLOCK: git add config/.env" \
  "git add config/.env"

assert_blocked "BLOCK: git add .env.production" \
  "git add .env.production"

assert_blocked "BLOCK: git add private.key" \
  "git add private.key"

assert_blocked "BLOCK: git add server.pem" \
  "git add server.pem"

assert_blocked "BLOCK: git add credentials.json" \
  "git add credentials.json"

assert_blocked "BLOCK: git add something-secret.yaml" \
  "git add something-secret.yaml"

assert_blocked "BLOCK: git add README.md .env (mixed files)" \
  "git add README.md .env"

# --- New sensitive patterns (M3) ---
assert_blocked "BLOCK: git add cert.p12" "git add cert.p12"
assert_blocked "BLOCK: git add cert.pfx" "git add cert.pfx"
assert_blocked "BLOCK: git add app.jks" "git add app.jks"
assert_blocked "BLOCK: git add release.keystore" "git add release.keystore"
assert_blocked "BLOCK: git add id_rsa" "git add id_rsa"
assert_blocked "BLOCK: git add .ssh/id_ed25519" "git add .ssh/id_ed25519"
assert_blocked "BLOCK: git add id_ecdsa" "git add id_ecdsa"
assert_blocked "BLOCK: git add .npmrc" "git add .npmrc"
assert_blocked "BLOCK: git add .pypirc" "git add .pypirc"
assert_blocked "BLOCK: git add path/to/id_rsa" "git add path/to/id_rsa"

# --- Uppercase sensitive file staging (CRITICAL-2) ---
assert_blocked "BLOCK: git add .ENV (uppercase)" \
  "git add .ENV"

assert_blocked "BLOCK: git add CREDENTIALS.json (uppercase)" \
  "git add CREDENTIALS.json"

assert_blocked "BLOCK: git add PRIVATE.KEY (uppercase)" \
  "git add PRIVATE.KEY"

assert_blocked "BLOCK: git add path/ID_RSA (uppercase)" \
  "git add path/ID_RSA"

assert_blocked "BLOCK: git add .NPMRC (uppercase)" \
  "git add .NPMRC"

assert_blocked "BLOCK: git add .Env.Production (mixed case)" \
  "git add .Env.Production"

assert_blocked "BLOCK: git add Secret.yaml (mixed case)" \
  "git add Secret.yaml"

echo ""

# ============================================================
# Category G: Bulk staging guard (mock git repo)
# ============================================================
echo "--- Category G: Bulk staging guard ---"

# G1: git add . with sensitive file -> BLOCK
setup_test_repo
echo "SECRET=abc" > "$TEST_REPO/.env"
run_safety_hook "git add ." "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: git add . with sensitive file present"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: git add . with sensitive file present"
  echo -e "       Expected: exit 2, Got: exit $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# G2: git add . without sensitive file -> ALLOW
setup_test_repo
echo "safe content" > "$TEST_REPO/app.js"
run_safety_hook "git add ." "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: git add . without sensitive files"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: git add . without sensitive files"
  echo -e "       Expected: exit 0, Got: exit $LAST_EXIT_CODE"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# G3: git add --all with sensitive file -> BLOCK
setup_test_repo
echo "SECRET=abc" > "$TEST_REPO/.env"
run_safety_hook "git add --all" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: git add --all with sensitive file present"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: git add --all with sensitive file present"
  echo -e "       Expected: exit 2, Got: exit $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# G4: git add -A with sensitive file -> BLOCK
setup_test_repo
echo "SECRET=abc" > "$TEST_REPO/.env"
run_safety_hook "git add -A" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: git add -A with sensitive file present"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: git add -A with sensitive file present"
  echo -e "       Expected: exit 2, Got: exit $LAST_EXIT_CODE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# G5: git add -A without sensitive file -> ALLOW
setup_test_repo
echo "safe content" > "$TEST_REPO/app.js"
run_safety_hook "git add -A" "$TEST_REPO"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$LAST_EXIT_CODE" -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC} ALLOW: git add -A without sensitive files"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} ALLOW: git add -A without sensitive files"
  echo -e "       Expected: exit 0, Got: exit $LAST_EXIT_CODE"
  echo -e "       Stderr: $LAST_STDERR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_test_repo

# --- New bulk staging patterns (M3) ---
echo "--- Category G (M3 additions): Bulk staging with new sensitive patterns ---"

setup_test_repo
echo "cert-data" > "$TEST_REPO/cert.p12"
git -C "$TEST_REPO" add README.md  # stage something safe first
run_safety_hook "git add ." "$TEST_REPO"
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: git add . with .p12 file present"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: git add . with .p12 file present"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))
cleanup_test_repo

setup_test_repo
echo "token=xxx" > "$TEST_REPO/.npmrc"
run_safety_hook "git add ." "$TEST_REPO"
if [ "$LAST_EXIT_CODE" -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC} BLOCK: git add . with .npmrc file present"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} BLOCK: git add . with .npmrc file present"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))
cleanup_test_repo

echo ""

# ============================================================
# Category H: Edge cases (ALLOW)
# ============================================================
echo "--- Category H: Edge cases ---"

assert_allowed "ALLOW: empty command" \
  ""

assert_allowed "ALLOW: whitespace only" \
  "   "

assert_allowed "ALLOW: git add (no arguments)" \
  "git add"

assert_allowed "ALLOW: cat rm-rf-notes.txt (rm in path, not a command)" \
  "cat rm-rf-notes.txt"

assert_allowed "ALLOW: npm run clean:build (clean is not targeted)" \
  "npm run clean:build"

echo ""

# ============================================================
# Category I: Subshell / backtick / indirect destructive (BLOCK)
# ============================================================
echo "--- Category I: Subshell and indirect destructive ---"

assert_blocked "BLOCK: rm -rf in \$() subshell" \
  'echo $(rm -rf /)'

assert_blocked "BLOCK: rm -rf in backtick substitution" \
  'echo `rm -rf /`'

assert_blocked "BLOCK: git push --force in \$() subshell" \
  'result=$(git push --force origin main)'

assert_blocked "BLOCK: xargs rm -rf" \
  'find . -name "*.tmp" | xargs rm -rf'

assert_blocked "BLOCK: find -exec rm -rf" \
  'find /tmp -exec rm -rf {} \;'

assert_blocked "BLOCK: xargs rm -fr (flag variant)" \
  'cat files.txt | xargs rm -fr'

assert_allowed "ALLOW: echo \$(date) (safe subshell)" \
  'echo $(date)'

assert_allowed "ALLOW: xargs cat (safe xargs)" \
  'find . -name "*.md" | xargs cat'

assert_allowed "ALLOW: find -exec cat (safe find)" \
  'find . -name "*.md" -exec cat {} \;'

# --- find -delete and find -exec bash/sh -c (MED-8) ---
assert_blocked "BLOCK: find -delete" \
  'find /tmp -name "*.log" -delete'

assert_blocked "BLOCK: find -delete without name filter" \
  'find /tmp -delete'

assert_blocked "BLOCK: find -exec bash -c (shell indirect)" \
  'find . -exec bash -c "rm -rf $1" _ {} \;'

assert_blocked "BLOCK: find -exec sh -c (shell indirect)" \
  'find . -exec sh -c "rm -f /tmp/foo" \;'

# --- xargs with uppercase/long-option rm (HIGH-3 indirect) ---
assert_blocked "BLOCK: xargs rm -Rf (uppercase)" \
  'find . | xargs rm -Rf'

assert_blocked "BLOCK: xargs rm --recursive --force (long options)" \
  'find . | xargs rm --recursive --force'

echo ""

# ============================================================
# Summary
# ============================================================
print_summary
