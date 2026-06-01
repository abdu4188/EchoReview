#!/usr/bin/env bash
# submit-review.sh — POST a PENDING review to GitHub using the payload the
# skill assembled in submission-payload.json. The review is non-blocking:
# the user clicks "Submit review" on github.com.
#
# Usage: submit-review.sh OWNER REPO PR_NUMBER

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: submit-review.sh OWNER REPO PR_NUMBER" >&2
    exit 2
fi

OWNER="$1"
REPO="$2"
NUMBER="$3"
WORK_DIR="${WORK_DIR:-/tmp/echoreview-${NUMBER}}"
PAYLOAD="${WORK_DIR}/submission-payload.json"

command -v gh >/dev/null || { echo "error: gh CLI not found. https://cli.github.com" >&2; exit 1; }
command -v jq >/dev/null || { echo "error: jq not found. brew install jq" >&2; exit 1; }

if [[ ! -r "$PAYLOAD" ]]; then
    echo "error: ${PAYLOAD} not readable. Skill must compose the payload before submission." >&2
    exit 1
fi

# A PENDING review on GitHub is created by POSTing without an `event`
# field. Any present `event` value (APPROVE / REQUEST_CHANGES / COMMENT)
# would submit the review immediately, which violates the plugin's
# promise that the human owns the click. This is the enforcement point.
event=$(jq -r '.event // empty' "$PAYLOAD")
if [[ -n "$event" ]]; then
    echo "refusing to submit: payload has 'event=\"${event}\"' set. PENDING reviews must omit the event field." >&2
    exit 1
fi

# Schema sanity check. Run before the network call so malformed payloads
# fail loud and locally instead of via a 422 from GitHub.
schema_error=$(
    jq -r '
        if type != "object" then "payload must be a JSON object"
        elif (.body | type) != "string" then "payload.body must be a string"
        elif (.comments | type) != "array" then "payload.comments must be an array"
        elif any(.comments[]; (.path | type) != "string") then "each comment must have a string .path"
        elif any(.comments[]; (.position | type) != "number" or (.position | floor) != .position or .position < 1)
            then "each comment must have an integer .position >= 1"
        elif any(.comments[]; (.body | type) != "string") then "each comment must have a string .body"
        else "" end
    ' "$PAYLOAD"
) || { echo "error: ${PAYLOAD} is not valid JSON" >&2; exit 1; }

if [[ -n "$schema_error" ]]; then
    echo "error: ${schema_error}" >&2
    exit 1
fi

RESPONSE="${WORK_DIR}/submission-response.json"

gh api "repos/${OWNER}/${REPO}/pulls/${NUMBER}/reviews" \
    --method POST \
    --input "$PAYLOAD" \
    > "$RESPONSE"

review_id=$(jq -r '.id // empty' "$RESPONSE")
pr_url=$(jq -r '.html_url // empty' "${WORK_DIR}/metadata.json" 2>/dev/null || true)

if [[ -n "$pr_url" && -n "$review_id" ]]; then
    echo "pending review: ${pr_url}#pullrequestreview-${review_id}"
else
    echo "pending review created (id=${review_id:-unknown}); open the PR on github.com to find it"
fi
echo "wrote: ${RESPONSE}"
