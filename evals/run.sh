#!/usr/bin/env bash
# evals/run.sh — EchoReview eval harness entry point.
#
# Iterates fixtures under evals/fixtures/, seeds each into a temp
# WORK_DIR, runs the relevant review-skill scripts with
# ECHOREVIEW_SKIP_FETCH=1 so the gh-API layer is bypassed, then runs
# the assertions declared in each fixture's expected.json.
#
# Usage: bash evals/run.sh
#
# Exit code: 0 if all fixtures pass, 1 otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT is used by lib.sh after sourcing.
# shellcheck disable=SC2034
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

command -v jq >/dev/null || { echo "error: jq not found. brew install jq" >&2; exit 1; }
command -v awk >/dev/null || { echo "error: awk not found" >&2; exit 1; }

# Globals consumed by lib.sh
PASS_COUNT=0
FAIL_COUNT=0
FAIL_MESSAGES=()

# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

if [[ ! -d "$FIXTURES_DIR" ]]; then
    echo "error: no fixtures directory at ${FIXTURES_DIR}" >&2
    exit 1
fi

shopt -s nullglob
fixture_paths=( "${FIXTURES_DIR}"/*/ )
shopt -u nullglob

if [[ ${#fixture_paths[@]} -eq 0 ]]; then
    echo "error: no fixtures found in ${FIXTURES_DIR}" >&2
    exit 1
fi

echo "EchoReview eval harness — ${#fixture_paths[@]} fixtures"
echo

for fixture_path in "${fixture_paths[@]}"; do
    fixture_name="$(basename "${fixture_path%/}")"
    run_fixture "$fixture_name" "$fixture_path"
    echo
done

echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed."
if (( FAIL_COUNT > 0 )); then
    echo "Failures:"
    printf '  - %s\n' "${FAIL_MESSAGES[@]}"
    exit 1
fi
