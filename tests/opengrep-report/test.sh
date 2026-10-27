#!/usr/bin/env bash
# report.sh's gate count decides pass/fail for every caller, so assert it against a fixture with
# findings at every severity.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
report="$here/../../.github/actions/opengrep/report.sh"
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

expect_gating ERROR 2
expect_gating ERROR,WARNING 3
expect_gating 'error, warning' 3
expect_gating INFO 1

run ERROR "$here/results.json"
errors=$(grep -c '^::error ' "$tmp/annotations" || true)
warnings=$(grep -c '^::warning ' "$tmp/annotations" || true)
if [ "$errors" != 2 ] || [ "$warnings" != 1 ]; then
    echo "FAIL: annotations errors=$errors warnings=$warnings, want 2 and 1 (INFO is not annotated)"
    exit 1
fi
rows=$(grep -c '^| \(ERROR\|WARNING\|INFO\) |' "$tmp/report.md" || true)
if [ "$rows" != 4 ]; then
    echo "FAIL: report table has $rows rows, want 4"
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
