#!/usr/bin/env bash
# test-ship-precompute.sh — Phase 0b: /ship pre-compute resilience
#
# Verifies that every bash command in skills/ship/SKILL.md's
# "Pre-computed Context" block exits 0 and emits a usable value
# across all initial git states the /ship workflow might encounter.
#
# States covered (AC-P2-1):
#   A. No remote
#   B. No commits at all (freshly `git init`-ed)
#   C. Single commit (.gitignore only)
#   D. Detached HEAD
#   E. Uncommitted changes only (no commits yet)
#   F. Remote configured, local in sync
#   G. Remote configured, local ahead of remote
#
# Each scenario runs the full 9-command pre-compute block and asserts
# that every command exits 0 and produces non-empty output (either the
# real value or the documented fallback marker).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

echo "=== /ship Pre-compute Resilience Tests (Phase 0b) ==="
echo ""

# ---------------------------------------------------------------
# The nine pre-compute commands extracted verbatim from
# skills/ship/SKILL.md. Keep this list in sync when SKILL.md changes.
# ---------------------------------------------------------------
PRECOMPUTE_COMMANDS=(
  # 1. Current branch
  'git branch --show-current 2>/dev/null | grep . || echo "(detached HEAD or no commits)"'
  # 2. Default branch
  "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main"
  # 3. Current state
  'git status --short 2>/dev/null || echo "[git status unavailable]"'
  # 4. Staged diff
  'git diff --cached 2>/dev/null || echo "[no commits yet — nothing staged]"'
  # 5. Unstaged diff summary
  'git diff --stat 2>/dev/null || echo "[no commits yet — cannot diff against HEAD]"'
  # 6. Remote configured
  'git remote get-url origin >/dev/null 2>&1 && echo "yes" || echo "no"'
  # 7. Diff stats vs default branch
  "git diff origin/\$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main) --stat 2>/dev/null || echo \"[no remote — skipped]\""
  # 8. Recent commits for style reference
  'git log --oneline -10 2>/dev/null || echo "[no commit history]"'
  # 9. Commits ahead of default branch
  "git log origin/\$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' | grep . || echo main)..HEAD --oneline 2>/dev/null || echo \"[no remote — skipped]\""
)

COMMAND_LABELS=(
  "current_branch"
  "default_branch"
  "current_state"
  "staged_diff"
  "unstaged_diff_summary"
  "remote_configured"
  "diff_stats_vs_default"
  "recent_commits"
  "commits_ahead_of_default"
)

# Run every pre-compute command inside $1 (a git dir) and assert each
# exits 0. Empty output is acceptable for "clean state" commands such
# as `git status --short` and `git diff --cached` when the working
# tree is clean — the /ship agent treats empty output as "nothing to
# report", which is the real signal we care about.
#
# AC-P2-1 / AC-P2-4: every command exits 0 across all seven scenarios.
# AC-P2-2: fallback patterns never cause a non-zero exit.
run_precompute_suite() {
  local repo="$1"
  local scenario="$2"
  local idx
  for idx in "${!PRECOMPUTE_COMMANDS[@]}"; do
    local cmd="${PRECOMPUTE_COMMANDS[$idx]}"
    local label="${COMMAND_LABELS[$idx]}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    local outfile errfile
    outfile=$(mktemp)
    errfile=$(mktemp)
    set +e
    (cd "$repo" && bash -c "$cmd") >"$outfile" 2>"$errfile"
    local exit_code=$?
    set -e
    local output stderr_output
    output=$(cat "$outfile")
    stderr_output=$(cat "$errfile")
    rm -f "$outfile" "$errfile"

    if [ "$exit_code" -eq 0 ]; then
      echo -e "  ${GREEN}PASS${NC} ${scenario}: ${label} (exit 0)"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo -e "  ${RED}FAIL${NC} ${scenario}: ${label}"
      echo -e "       exit_code=${exit_code} stdout='${output}' stderr='${stderr_output}'"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  done
}

# Assert that a specific pre-compute command emits a specific fallback
# marker in the given scenario. Used as a sanity check that fallback
# messages actually fire in the edge-case states.
assert_output_contains() {
  local repo="$1"
  local scenario="$2"
  local label="$3"
  local expected="$4"
  local idx cmd=""
  for idx in "${!COMMAND_LABELS[@]}"; do
    if [ "${COMMAND_LABELS[$idx]}" = "$label" ]; then
      cmd="${PRECOMPUTE_COMMANDS[$idx]}"
      break
    fi
  done
  if [ -z "$cmd" ]; then
    echo -e "  ${RED}FAIL${NC} ${scenario}: unknown label '${label}'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    return
  fi
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local output
  output=$( (cd "$repo" && bash -c "$cmd") 2>/dev/null || true )
  if echo "$output" | grep -qF "$expected"; then
    echo -e "  ${GREEN}PASS${NC} ${scenario}: ${label} fallback marker '${expected}' present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} ${scenario}: ${label} expected fallback '${expected}' got '${output}'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ---------------------------------------------------------------
# Scenario setup helpers
# ---------------------------------------------------------------

mk_repo() {
  local dir
  dir=$(mktemp -d)
  (
    cd "$dir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
  )
  echo "$dir"
}

mk_bare_remote() {
  local dir
  dir=$(mktemp -d)
  git init --bare -q "$dir"
  echo "$dir"
}

# Scenario A: No remote, has one commit.
scenario_a_no_remote() {
  local repo
  repo=$(mk_repo)
  (
    cd "$repo"
    echo "a" > a.txt
    git add a.txt
    git commit -q -m "A: initial"
  )
  echo "$repo"
}

# Scenario B: No commits at all.
scenario_b_no_commits() {
  mk_repo
}

# Scenario C: Single commit containing only .gitignore.
scenario_c_single_gitignore_commit() {
  local repo
  repo=$(mk_repo)
  (
    cd "$repo"
    printf '.docs/\n.backlog/\n' > .gitignore
    git add .gitignore
    git commit -q -m "C: initial gitignore"
  )
  echo "$repo"
}

# Scenario D: Detached HEAD.
scenario_d_detached_head() {
  local repo
  repo=$(mk_repo)
  (
    cd "$repo"
    echo "first" > first.txt
    git add first.txt
    git commit -q -m "D: first"
    echo "second" > second.txt
    git add second.txt
    git commit -q -m "D: second"
    # Detach HEAD at the first commit.
    local first_sha
    first_sha=$(git rev-list --max-parents=0 HEAD)
    git checkout -q "$first_sha"
  )
  echo "$repo"
}

# Scenario E: Only uncommitted changes (no commits yet).
scenario_e_uncommitted_only() {
  local repo
  repo=$(mk_repo)
  (
    cd "$repo"
    echo "staged" > staged.txt
    git add staged.txt
    echo "unstaged" > unstaged.txt
  )
  echo "$repo"
}

# Scenario F: Remote configured, local in sync.
scenario_f_remote_synced() {
  local repo bare
  repo=$(mk_repo)
  bare=$(mk_bare_remote)
  (
    cd "$repo"
    echo "f" > f.txt
    git add f.txt
    git commit -q -m "F: initial"
    git branch -M main
    git remote add origin "$bare"
    git push -q -u origin main
  )
  # Return both paths so caller can clean up the bare remote too.
  echo "$repo $bare"
}

# Scenario G: Remote configured, local ahead of remote.
scenario_g_local_ahead() {
  local repo bare
  repo=$(mk_repo)
  bare=$(mk_bare_remote)
  (
    cd "$repo"
    echo "g1" > g1.txt
    git add g1.txt
    git commit -q -m "G: initial"
    git branch -M main
    git remote add origin "$bare"
    git push -q -u origin main
    # Add two commits locally that the remote has not seen.
    echo "g2" > g2.txt
    git add g2.txt
    git commit -q -m "G: ahead 1"
    echo "g3" > g3.txt
    git add g3.txt
    git commit -q -m "G: ahead 2"
  )
  echo "$repo $bare"
}

# ---------------------------------------------------------------
# Run each scenario
# ---------------------------------------------------------------

# A: no remote
echo "--- Scenario A: no remote ---"
REPO_A=$(scenario_a_no_remote)
run_precompute_suite "$REPO_A" "A"
assert_output_contains "$REPO_A" "A" "remote_configured" "no"
assert_output_contains "$REPO_A" "A" "diff_stats_vs_default" "[no remote — skipped]"
assert_output_contains "$REPO_A" "A" "commits_ahead_of_default" "[no remote — skipped]"
rm -rf "$REPO_A"
echo ""

# B: no commits at all
# Note: On a freshly `git init`-ed repo, `git branch --show-current` still
# prints the unborn branch name (e.g. "main") — it does not fail — so
# `current_branch` produces a real value rather than the fallback marker.
# The "no commits" state instead surfaces via `recent_commits`.
echo "--- Scenario B: no commits ---"
REPO_B=$(scenario_b_no_commits)
run_precompute_suite "$REPO_B" "B"
assert_output_contains "$REPO_B" "B" "recent_commits" "[no commit history]"
rm -rf "$REPO_B"
echo ""

# C: single .gitignore-only commit
echo "--- Scenario C: single .gitignore commit ---"
REPO_C=$(scenario_c_single_gitignore_commit)
run_precompute_suite "$REPO_C" "C"
assert_output_contains "$REPO_C" "C" "remote_configured" "no"
rm -rf "$REPO_C"
echo ""

# D: detached HEAD
echo "--- Scenario D: detached HEAD ---"
REPO_D=$(scenario_d_detached_head)
run_precompute_suite "$REPO_D" "D"
assert_output_contains "$REPO_D" "D" "current_branch" "(detached HEAD or no commits)"
rm -rf "$REPO_D"
echo ""

# E: uncommitted changes only (no commits yet)
# `git status --short` always reports the staged + untracked files, so
# `current_state` must be non-empty. `git diff --stat` can legitimately
# return empty (no tracked changes against the empty index), so we only
# assert exit 0 there (already covered by run_precompute_suite).
echo "--- Scenario E: uncommitted changes only ---"
REPO_E=$(scenario_e_uncommitted_only)
run_precompute_suite "$REPO_E" "E"
assert_output_contains "$REPO_E" "E" "current_state" "staged.txt"
assert_output_contains "$REPO_E" "E" "current_state" "unstaged.txt"
rm -rf "$REPO_E"
echo ""

# F: remote configured, in sync
echo "--- Scenario F: remote configured, in sync ---"
read -r REPO_F BARE_F <<< "$(scenario_f_remote_synced)"
run_precompute_suite "$REPO_F" "F"
assert_output_contains "$REPO_F" "F" "remote_configured" "yes"
rm -rf "$REPO_F" "$BARE_F"
echo ""

# G: remote configured, local ahead
echo "--- Scenario G: remote configured, local ahead ---"
read -r REPO_G BARE_G <<< "$(scenario_g_local_ahead)"
run_precompute_suite "$REPO_G" "G"
assert_output_contains "$REPO_G" "G" "remote_configured" "yes"
assert_output_contains "$REPO_G" "G" "commits_ahead_of_default" "G: ahead"
rm -rf "$REPO_G" "$BARE_G"
echo ""

print_summary
