#!/usr/bin/env bash
# Fixture: deleted-file-handling
# Two sub-cases run in sequence (each in its own subshell so the EXIT trap
# scopes correctly and 'source' inside a function does not fire a RETURN trap):
#   (a) baseline has F, stage delete of F, emit, commit delete -> OK 1
#   (b) baseline has F, stage delete of F, emit, unstage (re-add F with
#       original content), commit -> STALE: F audit=__deleted__

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
HELPER="$REPO_ROOT/hooks/lib/audit-coverage.sh"

run_case_a() (
  WORKDIR=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$WORKDIR'" EXIT

  cd "$WORKDIR" || { echo "cannot cd"; exit 1; }
  git init -q -b main 2>/dev/null || git init -q
  git config user.email "fixture@example.com"
  git config user.name "Fixture"

  echo "content" > F.txt
  git add F.txt
  git commit -q -m "baseline with F"

  # Stage delete of F.
  git rm -q F.txt

  QR="$WORKDIR/qr.md"
  echo "# Quality Round 1" > "$QR"

  # shellcheck disable=SC1090
  source "$HELPER"
  if ! audit_coverage_emit "$QR"; then
    echo "emit non-zero"; exit 1
  fi

  # Commit the delete.
  git commit -q -m "delete F.txt"

  set +e
  OUT=$(audit_coverage_check "$QR")
  RC=$?
  set -e

  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qE '^OK 1$'; then
    exit 0
  fi
  echo "rc=$RC out='$OUT' (expected OK 1 exit 0)"
  exit 1
)

run_case_b() (
  WORKDIR=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$WORKDIR'" EXIT

  cd "$WORKDIR" || { echo "cannot cd"; exit 1; }
  git init -q -b main 2>/dev/null || git init -q
  git config user.email "fixture@example.com"
  git config user.name "Fixture"

  echo "content" > F.txt
  git add F.txt
  git commit -q -m "baseline with F"

  # Stage delete of F (so emit records F as deleted).
  git rm -q F.txt

  QR="$WORKDIR/qr.md"
  echo "# Quality Round 1" > "$QR"

  # shellcheck disable=SC1090
  source "$HELPER"
  if ! audit_coverage_emit "$QR"; then
    echo "emit non-zero"; exit 1
  fi

  # Unstage and restore: HEAD will keep F.txt because we cancel the delete.
  git reset -q HEAD -- F.txt 2>/dev/null || true
  git checkout -q -- F.txt 2>/dev/null || true
  # Force an allow-empty commit so HEAD advances beyond base. The commit-side
  # diff (base..HEAD) is empty, but the coverage entry validation MUST still
  # catch F.txt's __deleted__ marker against the live HEAD blob.
  git commit -q --allow-empty -m "no-op (F.txt resurrected)"

  set +e
  OUT=$(audit_coverage_check "$QR")
  RC=$?
  set -e

  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -qE '^STALE: F\.txt audit=__deleted__'; then
    exit 0
  fi
  echo "rc=$RC out='$OUT' (expected exit 1 with 'STALE: F.txt audit=__deleted__')"
  exit 1
)

FAIL_A=""
FAIL_B=""

OUT_A=$(run_case_a) || FAIL_A="$OUT_A"
OUT_B=$(run_case_b) || FAIL_B="$OUT_B"

if [ -z "$FAIL_A" ] && [ -z "$FAIL_B" ]; then
  echo "PASS"
  exit 0
fi

echo "FAIL: case_a='$FAIL_A' case_b='$FAIL_B'"
exit 1
