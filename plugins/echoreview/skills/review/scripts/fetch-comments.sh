#!/usr/bin/env bash
# fetch-comments.sh — pull prior review comments and reviews for a PR, and
# emit a re-review flag plus a markdown summary the skill can read.
#
# Usage: fetch-comments.sh OWNER REPO PR_NUMBER
#
# Set ECHOREVIEW_SKIP_FETCH=1 to skip the gh-API fetches and re-run only
# the local iteration-detection and summary on a pre-populated WORK_DIR
# (expects existing-comments.json and existing-reviews.json already
# present). The eval harness uses this to drive re-review detection
# against checked-in fixtures.

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: fetch-comments.sh OWNER REPO PR_NUMBER" >&2
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

COMMENTS="${WORK_DIR}/existing-comments.json"
REVIEWS="${WORK_DIR}/existing-reviews.json"
ITERATION="${WORK_DIR}/review-iteration.txt"
SUMMARY="${WORK_DIR}/previous-comments.md"

if [[ "$SKIP_FETCH" != "1" ]]; then
    # Fetch inline review comments (line-anchored) and top-level reviews
    # (approve/comment/changes-requested + their summary body) in parallel.
    # `gh api --paginate` may emit each page as its own top-level JSON value;
    # `jq -s 'add'` normalizes to a single array, piped directly off gh so we
    # don't write the multi-page form to disk first.

    (
        gh api "repos/${OWNER}/${REPO}/pulls/${NUMBER}/comments" --paginate \
            | jq -s 'if length == 0 then [] else add end' > "$COMMENTS"
    ) &
    PID_COMMENTS=$!

    (
        gh api "repos/${OWNER}/${REPO}/pulls/${NUMBER}/reviews" --paginate \
            | jq -s 'if length == 0 then [] else add end' > "$REVIEWS"
    ) &
    PID_REVIEWS=$!

    wait "$PID_COMMENTS" || { echo "error: failed to fetch PR comments" >&2; exit 1; }
    wait "$PID_REVIEWS"  || { echo "error: failed to fetch PR reviews"  >&2; exit 1; }
else
    [[ -r "$COMMENTS" ]] || { echo "error: ECHOREVIEW_SKIP_FETCH=1 but ${COMMENTS} is missing." >&2; exit 1; }
    [[ -r "$REVIEWS"  ]] || { echo "error: ECHOREVIEW_SKIP_FETCH=1 but ${REVIEWS} is missing."  >&2; exit 1; }
fi

# Mark OWNER and REPO as deliberately unused when SKIP_FETCH is on — kept
# in the signature so the call shape stays uniform across callers.
: "${OWNER}" "${REPO}"

count=$(jq 'length' "$COMMENTS")

if (( count > 0 )); then
    echo "2" > "$ITERATION"
else
    echo "1" > "$ITERATION"
fi

# Markdown summary, ordered by file then line.
{
    if (( count == 0 )); then
        echo "_No prior review comments._"
    else
        echo "# Prior review comments (${count})"
        echo
        jq -r '
            sort_by(.path, (.original_line // .line // 0)) | .[] |
            "## @\(.user.login // "?") on `\(.path)` (line \(.original_line // .line // "?"))\n\n> \(.body | gsub("\n"; "\n> "))\n\n_id: \(.id), in_reply_to_id: \(.in_reply_to_id // "-")_\n"
        ' "$COMMENTS"
    fi
} > "$SUMMARY"

echo "wrote: ${WORK_DIR}/{existing-comments.json,existing-reviews.json,review-iteration.txt,previous-comments.md}"
