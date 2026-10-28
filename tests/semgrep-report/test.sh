#!/usr/bin/env bash
# report.sh's gate count decides pass/fail for every caller, so assert it against a fixture with
# findings at every severity.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
report="$here/../../.github/actions/semgrep/report.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

run() {
    : >"$tmp/output"
    FAIL_ON="$1" GITHUB_OUTPUT="$tmp/output" "$report" "$2" "$tmp/report.md" >"$tmp/annotations"
}

expect_gating() {
    run "$1" "$here/results.json"
    local got
    got=$(sed -n 's/^gating=//p' "$tmp/output")
    if [ "$got" != "$2" ]; then
        echo "FAIL: FAIL_ON='$1' gave gating=$got, want $2"
        exit 1
    fi
    echo "ok: FAIL_ON='$1' -> gating=$got"
}

# The fixture holds 2 ERROR, 1 WARNING, 1 INFO plus one each of Semgrep's CRITICAL, HIGH, MEDIUM
# and LOW, which must count as ERROR, ERROR, WARNING and INFO respectively.
expect_gating ERROR 4
expect_gating ERROR,WARNING 6
expect_gating 'error, warning' 6
expect_gating INFO 2

run ERROR "$here/results.json"
errors=$(grep -c '^::error ' "$tmp/annotations" || true)
warnings=$(grep -c '^::warning ' "$tmp/annotations" || true)
if [ "$errors" != 4 ] || [ "$warnings" != 2 ]; then
    echo "FAIL: annotations errors=$errors warnings=$warnings, want 4 and 2 (INFO is not annotated)"
    exit 1
fi
rows=$(grep -c '^| \(ERROR\|WARNING\|INFO\)' "$tmp/report.md" || true)
if [ "$rows" != 8 ]; then
    echo "FAIL: report table has $rows rows, want 8"
    exit 1
fi
if ! grep -q '^| ERROR (CRITICAL)' "$tmp/report.md"; then
    echo "FAIL: the table should show Semgrep's own severity next to the mapped one"
    exit 1
fi
echo "ok: annotations and report table"

echo '{"results": [], "errors": []}' >"$tmp/clean.json"
run ERROR "$tmp/clean.json"
if [ "$(sed -n 's/^gating=//p' "$tmp/output")" != 0 ] || ! grep -q 'no findings' "$tmp/report.md"; then
    echo "FAIL: a clean scan must gate 0 and say 'no findings'"
    exit 1
fi
echo "ok: clean scan"
