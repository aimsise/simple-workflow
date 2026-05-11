#!/usr/bin/env bash
# Fixture: blob-mismatch
# Audit-time captures F at blob B1; ship-time commits F at blob B2 (one extra line).
# Expected: STALE: f.txt audit=..., exit 1.

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

# Stage F1 (audit-time blob B1).
echo "version1" > f.txt
git add f.txt

QR="$WORKDIR/qr.md"
echo "# Quality Round 1" > "$QR"

# shellcheck disable=SC1090
source "$HELPER"
audit_coverage_emit "$QR" || { echo "FAIL: emit returned non-zero"; exit 1; }

# Append a line: blob B2 != B1.
echo "extra-line" >> f.txt
git add f.txt
git commit -q -m "add f.txt with extra line"

set +e
OUT=$(audit_coverage_check "$QR")
RC=$?
set -e

if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -qE '^STALE: f\.txt audit='; then
  echo "PASS"
  exit 0
fi

echo "FAIL: rc=$RC out='$OUT' (expected exit 1 with 'STALE: f.txt audit=' prefix)"
exit 1
