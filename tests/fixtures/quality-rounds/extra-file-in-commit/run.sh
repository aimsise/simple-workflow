#!/usr/bin/env bash
# Fixture: extra-file-in-commit
# Coverage covers F1 only; commit changes F1 and F2 (new). F1 is unchanged
# from emit time. Expected: STALE: uncovered f2.txt, exit 1.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
HELPER="$REPO_ROOT/hooks/lib/audit-coverage.sh"

WORKDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$WORKDIR'" EXIT

cd "$WORKDIR" || { echo "FAIL: cannot cd to workdir"; exit 1; }

git init -q -b main 2>/dev/null || git init -q
git config user.email "fixture@example.com"
git config user.name "Fixture"

# Baseline.
echo "baseline" > README.md
git add README.md
git commit -q -m "baseline"

# Stage F1 only.
echo "first-file" > f1.txt
git add f1.txt

QR="$WORKDIR/qr.md"
echo "# Quality Round 1" > "$QR"

# shellcheck disable=SC1090
source "$HELPER"
audit_coverage_emit "$QR" || { echo "FAIL: emit returned non-zero"; exit 1; }

# Now stage F2 in addition (audit did NOT cover F2). F1 unchanged.
echo "second-file" > f2.txt
git add f2.txt
git commit -q -m "add f1.txt and f2.txt"

set +e
OUT=$(audit_coverage_check "$QR")
RC=$?
set -e

if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -qE '^STALE: uncovered f2\.txt$'; then
  echo "PASS"
  exit 0
fi

echo "FAIL: rc=$RC out='$OUT' (expected exit 1 with 'STALE: uncovered f2.txt')"
exit 1
