#!/usr/bin/env bash
# tests/test-session-start.sh
#
# v4.1.0 gitignore-setup behavior matrix for hooks/session-start.sh.
#
# Test matrix for hooks/session-start.sh gitignore-setup block
# Covers: no git, empty repo, existing repo w/o entries, existing repo w/ all
# entries, flag present.
#
# Each case:
#   - Uses `mktemp -d` for isolated FS state
#   - Sets local `user.email`/`user.name` (or GIT_AUTHOR_*/GIT_COMMITTER_* env)
#     so commits succeed regardless of the host's git config
#   - Cleans up via trap
#
# Exits 0 only when every C1-C6 case reports PASS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/session-start.sh"

if [ ! -x "$HOOK" ]; then
  echo "ERROR: hook not executable: $HOOK" >&2
  exit 2
fi

# ---------- Isolation harness ----------
# A single sandbox dir that owns a fake HOME and a scratch area for per-case
# workdirs. Everything is removed by the EXIT trap.

SANDBOX="$(mktemp -d)"
FAKE_HOME="$SANDBOX/home"
CASE_ROOT="$SANDBOX/cases"
mkdir -p "$FAKE_HOME" "$CASE_ROOT"

# Never let host git configuration leak in; GIT_CONFIG_GLOBAL=/dev/null
# neutralises ~/.gitconfig even when tests run under other users.
export HOME="$FAKE_HOME"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="simple-workflow test"
export GIT_AUTHOR_EMAIL="test@example.invalid"
export GIT_COMMITTER_NAME="simple-workflow test"
export GIT_COMMITTER_EMAIL="test@example.invalid"

cleanup() {
  rm -rf "$SANDBOX" 2>/dev/null || true
}
trap cleanup EXIT

# ---------- Reporting ----------

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

report_pass() {
  local name="$1"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '  [PASS] %s\n' "$name"
}

report_fail() {
  local name="$1"; shift
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILURES+=("$name")
  printf '  [FAIL] %s\n' "$name"
  if [ "$#" -gt 0 ]; then
    while [ "$#" -gt 0 ]; do
      printf '         %s\n' "$1"
      shift
    done
  fi
}

# ---------- Helpers ----------

# Run the hook in a target dir with a fresh HOME/git config env.
run_hook_in() {
  local dir="$1"
  (
    cd "$dir"
    printf '{}' | "$HOOK" >/dev/null 2>&1
  )
}

# Count commits on HEAD (0 when no HEAD).
commit_count() {
  local dir="$1"
  (
    cd "$dir"
    if git rev-parse HEAD >/dev/null 2>&1; then
      git rev-list --count HEAD
    else
      echo 0
    fi
  )
}

# Make a per-case workdir and configure local git identity after init (when a
# .git dir is present; when the case expects the hook to init, the caller can
# skip this).
make_case_dir() {
  local name="$1"
  local dir="$CASE_ROOT/$name"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

configure_local_git() {
  local dir="$1"
  (
    cd "$dir"
    git config --local user.email "test@example.invalid"
    git config --local user.name "simple-workflow test"
  )
}

# ---------- C1: fresh dir, no git ----------
# Expected: .git created, .gitignore with 3 entries, >=1 commit, flag file.

case_c1() {
  echo "=== C1: fresh dir (no git) ==="
  local dir
  dir="$(make_case_dir c1)"

  run_hook_in "$dir"

  local name=".git/ directory created"
  if [ -d "$dir/.git" ]; then report_pass "$name"; else report_fail "$name"; fi

  name=".gitignore contains .docs/"
  if grep -qxF '.docs/' "$dir/.gitignore" 2>/dev/null; then report_pass "$name"; else report_fail "$name"; fi
  name=".gitignore contains .backlog/"
  if grep -qxF '.backlog/' "$dir/.gitignore" 2>/dev/null; then report_pass "$name"; else report_fail "$name"; fi
  name=".gitignore contains .simple-wf-knowledge/"
  if grep -qxF '.simple-wf-knowledge/' "$dir/.gitignore" 2>/dev/null; then report_pass "$name"; else report_fail "$name"; fi

  local cnt
  cnt="$(commit_count "$dir")"
  name="git log has >=1 commit (got $cnt)"
  if [ "$cnt" -ge 1 ]; then report_pass "$name"; else report_fail "$name"; fi

  name=".simple-wf-knowledge/.gitignore-setup-done present"
  if [ -f "$dir/.simple-wf-knowledge/.gitignore-setup-done" ]; then
    report_pass "$name"
  else
    report_fail "$name"
  fi
}

# ---------- C2: git-init'd, no commits, no .gitignore ----------

case_c2() {
  echo "=== C2: git init, no commits, no .gitignore ==="
  local dir
  dir="$(make_case_dir c2)"
  (cd "$dir" && git init -q -b main 2>/dev/null || git init -q)
  configure_local_git "$dir"

  run_hook_in "$dir"

  local name=".gitignore created"
  if [ -f "$dir/.gitignore" ]; then report_pass "$name"; else report_fail "$name"; fi

  for entry in '.docs/' '.backlog/' '.simple-wf-knowledge/'; do
    name=".gitignore contains $entry"
    if grep -qxF "$entry" "$dir/.gitignore" 2>/dev/null; then report_pass "$name"; else report_fail "$name"; fi
  done

  local cnt
  cnt="$(commit_count "$dir")"
  name="git log has >=1 commit (got $cnt)"
  if [ "$cnt" -ge 1 ]; then report_pass "$name"; else report_fail "$name"; fi

  name="flag file present"
  if [ -f "$dir/.simple-wf-knowledge/.gitignore-setup-done" ]; then
    report_pass "$name"
  else
    report_fail "$name"
  fi
}

# ---------- C3: existing repo with commits, no entries ----------

case_c3() {
  echo "=== C3: repo with commits, no entries in .gitignore ==="
  local dir
  dir="$(make_case_dir c3)"
  (
    cd "$dir"
    git init -q -b main 2>/dev/null || git init -q
  )
  configure_local_git "$dir"
  (
    cd "$dir"
    echo 'hello' > README.md
    git add README.md
    git commit -q -m "initial"
  )

  local before_cnt
  before_cnt="$(commit_count "$dir")"

  run_hook_in "$dir"

  for entry in '.docs/' '.backlog/' '.simple-wf-knowledge/'; do
    local name=".gitignore appended with $entry"
    if grep -qxF "$entry" "$dir/.gitignore" 2>/dev/null; then report_pass "$name"; else report_fail "$name"; fi
  done

  local after_cnt
  after_cnt="$(commit_count "$dir")"
  local name="chore commit created (commits $before_cnt -> $after_cnt)"
  if [ "$after_cnt" -eq $((before_cnt + 1)) ]; then report_pass "$name"; else report_fail "$name"; fi

  name="latest commit is 'chore: add simple-workflow artifacts to .gitignore'"
  local subject
  subject="$(cd "$dir" && git log -1 --format=%s)"
  if [ "$subject" = "chore: add simple-workflow artifacts to .gitignore" ]; then
    report_pass "$name"
  else
    report_fail "$name" "got: $subject"
  fi

  name="flag file present"
  if [ -f "$dir/.simple-wf-knowledge/.gitignore-setup-done" ]; then
    report_pass "$name"
  else
    report_fail "$name"
  fi
}

# ---------- C4: existing repo, 1 of 3 entries present ----------

case_c4() {
  echo "=== C4: repo with commits, 1 of 3 entries already present ==="
  local dir
  dir="$(make_case_dir c4)"
  (
    cd "$dir"
    git init -q -b main 2>/dev/null || git init -q
  )
  configure_local_git "$dir"
  (
    cd "$dir"
    echo 'hello' > README.md
    printf '.docs/\n' > .gitignore
    git add README.md .gitignore
    git commit -q -m "initial with partial gitignore"
  )

  local before_cnt
  before_cnt="$(commit_count "$dir")"

  run_hook_in "$dir"

  for entry in '.docs/' '.backlog/' '.simple-wf-knowledge/'; do
    local name=".gitignore contains $entry"
    if grep -qxF "$entry" "$dir/.gitignore" 2>/dev/null; then report_pass "$name"; else report_fail "$name"; fi
  done

  # .docs/ must appear exactly once (no duplication).
  local docs_count
  docs_count="$(grep -cxF '.docs/' "$dir/.gitignore")"
  local name=".docs/ not duplicated (count=$docs_count)"
  if [ "$docs_count" -eq 1 ]; then report_pass "$name"; else report_fail "$name"; fi

  local after_cnt
  after_cnt="$(commit_count "$dir")"
  name="chore commit created (commits $before_cnt -> $after_cnt)"
  if [ "$after_cnt" -eq $((before_cnt + 1)) ]; then report_pass "$name"; else report_fail "$name"; fi

  name="flag file present"
  if [ -f "$dir/.simple-wf-knowledge/.gitignore-setup-done" ]; then
    report_pass "$name"
  else
    report_fail "$name"
  fi
}

# ---------- C5: all 3 entries already present (AC-5) ----------

case_c5() {
  echo "=== C5: repo with commits, all 3 entries already present (idempotency) ==="
  local dir
  dir="$(make_case_dir c5)"
  (
    cd "$dir"
    git init -q -b main 2>/dev/null || git init -q
  )
  configure_local_git "$dir"
  (
    cd "$dir"
    printf '.docs/\n.backlog/\n.simple-wf-knowledge/\n' > .gitignore
    echo 'hello' > README.md
    git add README.md .gitignore
    git commit -q -m "initial with all entries"
  )

  # Remove the flag if the hook wrote it in a previous case (same sandbox
  # tree uses separate case dirs, so this is defensive only).
  rm -f "$dir/.simple-wf-knowledge/.gitignore-setup-done"

  # First run establishes the flag. AC-5 actually asks about the SECOND run
  # producing zero additional commits + no mtime change; record mtime and
  # commit count AFTER the first run.
  run_hook_in "$dir"

  local mid_cnt
  mid_cnt="$(commit_count "$dir")"
  # Capture mtime after first run in a portable way (nanoseconds on GNU, seconds on BSD).
  local mtime_before
  mtime_before="$(stat -f %m "$dir/.gitignore" 2>/dev/null || stat -c %Y "$dir/.gitignore" 2>/dev/null || echo 0)"

  # Sleep long enough to expose an unwanted mtime change on 1-sec-resolution filesystems.
  sleep 1

  run_hook_in "$dir"

  local after_cnt
  after_cnt="$(commit_count "$dir")"
  local name="second run produced zero additional commits ($mid_cnt -> $after_cnt)"
  if [ "$after_cnt" -eq "$mid_cnt" ]; then report_pass "$name"; else report_fail "$name"; fi

  local mtime_after
  mtime_after="$(stat -f %m "$dir/.gitignore" 2>/dev/null || stat -c %Y "$dir/.gitignore" 2>/dev/null || echo 0)"
  name=".gitignore mtime unchanged across second run"
  if [ "$mtime_before" = "$mtime_after" ]; then report_pass "$name"; else report_fail "$name" "before=$mtime_before after=$mtime_after"; fi

  # Sanity: all 3 entries appear exactly once.
  for entry in '.docs/' '.backlog/' '.simple-wf-knowledge/'; do
    local cnt
    cnt="$(grep -cxF "$entry" "$dir/.gitignore")"
    name="$entry present exactly once (count=$cnt)"
    if [ "$cnt" -eq 1 ]; then report_pass "$name"; else report_fail "$name"; fi
  done

  name="flag file present"
  if [ -f "$dir/.simple-wf-knowledge/.gitignore-setup-done" ]; then
    report_pass "$name"
  else
    report_fail "$name"
  fi
}

# ---------- C6: flag already present (AC-6) ----------

case_c6() {
  echo "=== C6: flag file already present -> hook is a no-op ==="
  local dir
  dir="$(make_case_dir c6)"
  (
    cd "$dir"
    git init -q -b main 2>/dev/null || git init -q
  )
  configure_local_git "$dir"
  (
    cd "$dir"
    echo 'hello' > README.md
    git add README.md
    git commit -q -m "initial"
  )
  # Flag exists BEFORE any simple-workflow entries are in .gitignore.
  # .gitignore does not exist yet; hook MUST NOT create or modify it.
  mkdir -p "$dir/.simple-wf-knowledge"
  : > "$dir/.simple-wf-knowledge/.gitignore-setup-done"

  local before_cnt
  before_cnt="$(commit_count "$dir")"

  run_hook_in "$dir"

  local after_cnt
  after_cnt="$(commit_count "$dir")"
  local name="no additional commits ($before_cnt -> $after_cnt)"
  if [ "$after_cnt" -eq "$before_cnt" ]; then report_pass "$name"; else report_fail "$name"; fi

  name=".gitignore NOT created"
  if [ ! -f "$dir/.gitignore" ]; then report_pass "$name"; else report_fail "$name"; fi

  name=".docs/ NOT appended"
  if ! grep -qxF '.docs/' "$dir/.gitignore" 2>/dev/null; then
    report_pass "$name"
  else
    report_fail "$name"
  fi
}

# ---------- C7: commit failure (no git identity) -> flag NOT written ----------
# Regression guard for A5 from the v4.1.0 skeptical review.
#
# If .gitignore is mutated but the commit fails (e.g. because no git identity
# is configured), the setup flag must NOT be written. Otherwise the repo ends
# up in a permanent staged-but-uncommitted state (flag blocks future retries).
#
# Expected post-hook state (FIRST run, no identity): .gitignore contains the
# entries (mutation happened), but no new commit (commit failed silently), and
# no flag file exists. Second run with identity configured must finalize and
# write the flag.

case_c7() {
  echo "=== C7: commit-failure (pre-commit hook fails) -> flag NOT written ==="
  local dir
  dir="$(make_case_dir c7)"
  (
    cd "$dir"
    git init -q -b main 2>/dev/null || git init -q
    echo 'hello' > README.md
    git add README.md
    git commit -q -m "initial"
  )
  configure_local_git "$dir"

  # Install a pre-commit hook that always fails. This is the most portable way
  # to force `git commit` to fail deterministically across git versions —
  # attempting to simulate "no identity" via env unset is unreliable because
  # modern git auto-detects identity from hostname in some configurations.
  cat > "$dir/.git/hooks/pre-commit" << 'HOOK_EOF'
#!/bin/sh
echo "pre-commit: forced test failure" >&2
exit 1
HOOK_EOF
  chmod +x "$dir/.git/hooks/pre-commit"

  local before_cnt
  before_cnt="$(commit_count "$dir")"

  run_hook_in "$dir"

  local after_cnt
  after_cnt="$(commit_count "$dir")"

  local name="no additional commits when pre-commit fails ($before_cnt -> $after_cnt)"
  if [ "$after_cnt" -eq "$before_cnt" ]; then report_pass "$name"; else report_fail "$name"; fi

  name=".gitignore was appended (mutation happened regardless of commit result)"
  if grep -qxF '.docs/' "$dir/.gitignore" 2>/dev/null; then
    report_pass "$name"
  else
    report_fail "$name"
  fi

  name="flag file NOT written when commit failed (silent state inconsistency prevented)"
  if [ ! -f "$dir/.simple-wf-knowledge/.gitignore-setup-done" ]; then
    report_pass "$name"
  else
    report_fail "$name"
  fi

  # Recovery path: remove the failing pre-commit hook, re-run. Flag must appear
  # and HEAD must advance by exactly one commit.
  rm -f "$dir/.git/hooks/pre-commit"
  run_hook_in "$dir"

  local final_cnt
  final_cnt="$(commit_count "$dir")"

  name="chore commit recorded on retry ($after_cnt -> $final_cnt, expect $((after_cnt + 1)))"
  if [ "$final_cnt" -eq "$((after_cnt + 1))" ]; then
    report_pass "$name"
  else
    report_fail "$name"
  fi

  name="flag file written after retry succeeds"
  if [ -f "$dir/.simple-wf-knowledge/.gitignore-setup-done" ]; then
    report_pass "$name"
  else
    report_fail "$name"
  fi
}

# ---------- Run all cases ----------

case_c1
echo
case_c2
echo
case_c3
echo
case_c4
echo
case_c5
echo
case_c6
echo
case_c7

echo
echo "=================================="
echo "Results: $PASS_COUNT pass, $FAIL_COUNT fail"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "Failed checks:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
exit 0
