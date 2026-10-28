#!/usr/bin/env bash
# Turns Semgrep JSON into GitHub annotations and a markdown report.
# Usage: report.sh <results.json> <report.md>; FAIL_ON is a comma-separated severity list.
set -euo pipefail

results=$1
report=$2
# Normalized so "error, warning" gates the same as "ERROR,WARNING" instead of silently gating nothing.
fail_on=$(tr '[:lower:]' '[:upper:]' <<<"${FAIL_ON:-ERROR}" | tr -d '[:space:]')
max_rows=100

# Rule ids from local config files are prefixed with the rules' absolute path; keep the last segment.
findings=$(jq -c '[.results[] | {
    severity: .extra.severity,
    rule: (.check_id | split(".") | last),
    path: .path,
    line: .start.line,
    message: (.extra.message | split("\n") | map(select(length > 0)) | first // "")
}] | sort_by(.severity != "ERROR", .severity != "WARNING", .path, .line)' "$results")

total=$(jq 'length' <<<"$findings")
gating=$(jq --arg fail_on "$fail_on" '[.[] | select(.severity as $s | $fail_on | split(",") | index($s))] | length' <<<"$findings")

# GitHub shows only the first 10 error and 10 warning annotations per step; the report lists all.
jq -r '.[] | select(.severity != "INFO")
    | "::\(if .severity == "ERROR" then "error" else "warning" end) file=\(.path),line=\(.line),title=\(.rule)::\(.message | gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A"))"' <<<"$findings"

{
    echo '<!-- semgrep-report -->'
    if [ "$total" -eq 0 ]; then
        echo '### Semgrep: no findings'
    else
        echo "### Semgrep: $total findings ($(jq -r 'group_by(.severity) | map("\(length) \(.[0].severity)") | join(", ")' <<<"$findings"))"
        echo
        echo "Fails on: \`$fail_on\`. Findings at those severities: **$gating**."
        echo
        echo '| Severity | Rule | Location | Message |'
        echo '|---|---|---|---|'
        jq -r --argjson max "$max_rows" '.[:$max][]
            | "| \(.severity) | `\(.rule)` | `\(.path):\(.line)` | \(.message | gsub("\\|"; "\\|") | .[:140]) |"' <<<"$findings"
        if [ "$total" -gt "$max_rows" ]; then
            echo
            echo "Showing the first $max_rows of $total. The job log has the full list."
        fi
    fi
    errors=$(jq '.errors | length' "$results")
    if [ "$errors" -gt 0 ]; then
        echo
        echo "Semgrep reported $errors non-fatal errors (e.g. files it could not parse); see the job log."
    fi
} >"$report"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "gating=$gating" >>"$GITHUB_OUTPUT"
fi
