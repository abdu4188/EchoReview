#!/usr/bin/env bash
# extract-context.sh — pull PR metadata, diff, file list, and a type
# classification for a single GitHub PR. Outputs land in
# /tmp/echoreview-${PR_NUMBER}/ (override via WORK_DIR env).
#
# Usage: extract-context.sh OWNER REPO PR_NUMBER
#
# Set ECHOREVIEW_SKIP_FETCH=1 to skip the gh-API fetches and re-run only
# the local file-type classifier on a pre-populated WORK_DIR. The eval
# harness uses this to drive the classifier against checked-in fixtures
# without hitting GitHub. OWNER/REPO/NUMBER are still required so the
# usage stays uniform across callers.

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: extract-context.sh OWNER REPO PR_NUMBER" >&2
    exit 2
fi

OWNER="$1"
REPO="$2"
NUMBER="$3"
WORK_DIR="${WORK_DIR:-/tmp/echoreview-${NUMBER}}"
SKIP_FETCH="${ECHOREVIEW_SKIP_FETCH:-0}"

command -v jq >/dev/null || { echo "error: jq not found. brew install jq" >&2; exit 1; }

if [[ "$SKIP_FETCH" != "1" ]]; then
    command -v gh >/dev/null || { echo "error: gh CLI not found. https://cli.github.com" >&2; exit 1; }
fi

mkdir -p "$WORK_DIR"

if [[ "$SKIP_FETCH" != "1" ]]; then
    # Fetch metadata, diff, and the changed-file list in parallel — they're
    # independent network calls and used to dominate wall time when run
    # sequentially. Each background job is waited on individually so a failure
    # in any one aborts the script under `set -e`.

    gh api "repos/${OWNER}/${REPO}/pulls/${NUMBER}" > "${WORK_DIR}/metadata.json" &
    PID_META=$!

    gh pr diff "$NUMBER" --repo "${OWNER}/${REPO}" > "${WORK_DIR}/diff.patch" &
    PID_DIFF=$!

    (
        gh api "repos/${OWNER}/${REPO}/pulls/${NUMBER}/files" --paginate \
            | jq -r '.[].filename' > "${WORK_DIR}/files.txt"
    ) &
    PID_FILES=$!

    wait "$PID_META"  || { echo "error: failed to fetch PR metadata"  >&2; exit 1; }
    wait "$PID_DIFF"  || { echo "error: failed to fetch PR diff"      >&2; exit 1; }
    wait "$PID_FILES" || { echo "error: failed to fetch PR file list" >&2; exit 1; }
else
    [[ -r "${WORK_DIR}/files.txt" ]] || {
        echo "error: ECHOREVIEW_SKIP_FETCH=1 but ${WORK_DIR}/files.txt is missing." >&2
        exit 1
    }
fi

# Mark OWNER and REPO as deliberately unused when SKIP_FETCH is on — kept
# in the signature so the call shape stays uniform across callers.
: "${OWNER}" "${REPO}"

# File-type classification — stack-agnostic buckets used by the skill to
# detect skip conditions (lockfile-only, docs-only) and to summarize the PR
# for the user. Extension- and path-based; deliberately coarse.
jq -Rn '
[ inputs
  | select(length > 0)
  | . as $f
  | {
      file: $f,
      type: (
        if ($f | test("(package-lock\\.json|yarn\\.lock|pnpm-lock\\.yaml|Pipfile\\.lock|composer\\.lock|Gemfile\\.lock|poetry\\.lock|Cargo\\.lock|go\\.sum)$")) then "lockfile"
        elif ($f | test("(^|/)(package\\.json|Cargo\\.toml|composer\\.json|Gemfile|go\\.mod|pyproject\\.toml|requirements[^/]*\\.txt)$")) then "manifest"
        elif ($f | test("\\.(md|mdx|rst|txt)$")) then "docs"
        elif ($f | test("\\.(test|spec)\\.[a-z0-9]+$|(^|/)test_[^/]+\\.(py|pyi)$|_test\\.[a-z0-9]+$|(^|/)(test|tests|spec|specs|__tests__)/")) then "test"
        elif ($f | test("\\.(yml|yaml|toml|ini|conf|json)$")) then "config"
        elif ($f | test("\\.(sh|bash|zsh|fish)$")) then "shell"
        elif ($f | test("\\.(js|jsx|ts|tsx|mjs|cjs)$")) then "js-ts"
        elif ($f | test("\\.(py|pyi)$")) then "python"
        elif ($f | test("\\.go$")) then "go"
        elif ($f | test("\\.rs$")) then "rust"
        elif ($f | test("\\.rb$")) then "ruby"
        elif ($f | test("\\.(java|kt|kts)$")) then "jvm"
        elif ($f | test("\\.(c|h|cc|cpp|hpp|cxx)$")) then "c-cpp"
        elif ($f | test("\\.(vue|svelte)$")) then "frontend-component"
        elif ($f | test("\\.(html|htm)$")) then "html"
        elif ($f | test("\\.(css|scss|sass|less)$")) then "css"
        else "other"
        end
      )
    }
]
' "${WORK_DIR}/files.txt" > "${WORK_DIR}/file-types.json"

echo "wrote: ${WORK_DIR}/{metadata.json,diff.patch,files.txt,file-types.json}"
