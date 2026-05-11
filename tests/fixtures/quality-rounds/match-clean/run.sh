#!/usr/bin/env bash
# Fixture: match-clean
# Audit-time change set == ship-time commit (both files unchanged after emit).
# Expected: OK 2, exit 0.
# Kill-switch mode (SW_AUDIT_COVERAGE=off): LEGACY exit 2.

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

# Baseline commit (empty README so we have a HEAD).
echo "baseline" > README.md
git add README.md
git commit -q -m "baseline"

# Stage two files (the audit-time change set).
echo "alpha" > a.txt
echo "beta" > b.txt
git add a.txt b.txt

QR="$WORKDIR/qr.md"
echo "# Quality Round 1" > "$QR"

# shellcheck disable=SC1090
source "$HELPER"

audit_coverage_emit "$QR" || { echo "FAIL: emit returned non-zero"; exit 1; }

# Commit the staged files (ship-time commit, identical to audit-time).
git commit -q -m "add a.txt and b.txt"

set +e
OUT=$(audit_coverage_check "$QR")
RC=$?
set -e

EXPECTED_RC=0
EXPECTED_PATTERN='^OK 2$'
if [ "${SW_AUDIT_COVERAGE:-on}" = "off" ]; then
  EXPECTED_RC=2
  EXPECTED_PATTERN='^LEGACY$'
fi

if [ "$RC" -eq "$EXPECTED_RC" ] && printf '%s' "$OUT" | grep -qE "$EXPECTED_PATTERN"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: rc=$RC expected=$EXPECTED_RC out='$OUT' expected_pattern='$EXPECTED_PATTERN'"
exit 1
