#!/usr/bin/env bash
# fetch-pr-history.sh — fetch merged-PR review history from a target
# repo, filter to substantive comments, and write a JSONL file ready
# for semantic clustering by the echo-extract skill.
#
# Usage: fetch-pr-history.sh TARGET_REPO SINCE_WINDOW [MAX_PRS] [COVERAGE]
#
# Positional args
#   TARGET_REPO    owner/name (e.g. vueuse/vueuse)
#   SINCE_WINDOW   Nd|Nw|Nmo|Ny (e.g. 6mo, 30d, 1y)
#   MAX_PRS        optional, default 500
#   COVERAGE       optional, recent|balanced|full, default balanced. Controls
#                  which PRs in the window get mined when MAX_PRS < window size:
#                    recent   — newest MAX_PRS only (legacy behavior)
#                    balanced — newest block + a slice across the full window
#                    full     — even coverage across the whole window
#                  Ignored in estimate-only mode.
#
# Environment
#   WORK_DIR                 default /tmp/echoreview-extract
#   ECHOREVIEW_ESTIMATE_ONLY 1 to short-circuit after estimate.json

set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
    echo "usage: fetch-pr-history.sh TARGET_REPO SINCE_WINDOW [MAX_PRS] [COVERAGE]" >&2
    exit 2
fi

TARGET_REPO="$1"
SINCE_WINDOW="$2"
MAX_PRS="${3:-500}"
COVERAGE="${4:-balanced}"
WORK_DIR="${WORK_DIR:-/tmp/echoreview-extract}"
ESTIMATE_ONLY="${ECHOREVIEW_ESTIMATE_ONLY:-0}"

# GitHub's search API caps any merged-PR listing at 1000 results, so the full
# window we can ever see is bounded by this. balanced reserves this fraction of
# --limit for the newest contiguous block; the rest samples the older window.
WINDOW_CAP=1000
BALANCED_RECENT_FRAC=0.70

if [[ ! "$TARGET_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    echo "error: TARGET_REPO must be 'owner/name', got '${TARGET_REPO}'" >&2
    exit 2
fi

if [[ ! "$MAX_PRS" =~ ^[0-9]+$ ]] || (( MAX_PRS < 1 )); then
    echo "error: MAX_PRS must be a positive integer, got '${MAX_PRS}'" >&2
    exit 2
fi

if [[ ! "$COVERAGE" =~ ^(recent|balanced|full)$ ]]; then
    echo "error: COVERAGE must be recent|balanced|full, got '${COVERAGE}'" >&2
    exit 2
fi

command -v gh >/dev/null || { echo "error: gh CLI not found. https://cli.github.com" >&2; exit 1; }
command -v jq >/dev/null || { echo "error: jq not found. brew install jq" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh not authenticated. Run 'gh auth login'." >&2; exit 1; }

mkdir -p "$WORK_DIR"

# Resolve a relative window (e.g. "3mo") to YYYY-MM-DD. Works with both
# GNU date (Linux, Homebrew coreutils) and BSD date (macOS default).
resolve_since_date() {
    local window="$1"
    local n unit
    if [[ "$window" =~ ^([0-9]+)(d|w|mo|y)$ ]]; then
        n="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
    else
        echo "error: SINCE_WINDOW must match Nd|Nw|Nmo|Ny (e.g. 6mo, 30d, 1y); got '${window}'" >&2
        return 2
    fi

    if date -d "1 day ago" +%Y-%m-%d >/dev/null 2>&1; then
        case "$unit" in
            d)  date -d "${n} days ago"   +%Y-%m-%d ;;
            w)  date -d "${n} weeks ago"  +%Y-%m-%d ;;
            mo) date -d "${n} months ago" +%Y-%m-%d ;;
            y)  date -d "${n} years ago"  +%Y-%m-%d ;;
        esac
    else
        case "$unit" in
            d)  date -v-"${n}"d +%Y-%m-%d ;;
            w)  date -v-"${n}"w +%Y-%m-%d ;;
            mo) date -v-"${n}"m +%Y-%m-%d ;;
            y)  date -v-"${n}"y +%Y-%m-%d ;;
        esac
    fi
}

# List merged PRs in the window. Writes pr-list.json. Always fresh.
# Used by the estimate path (newest N) — kept verbatim for contract stability.
list_prs() {
    local target="$1" since_date="$2" max="$3"
    gh pr list \
        --repo "$target" \
        --state merged \
        --search "merged:>=${since_date}" \
        --limit "$max" \
        --json number,title,author,mergedAt \
        > "${WORK_DIR}/pr-list.json"
}

# List ALL merged PRs in the window (numbers+dates are cheap), up to the
# GitHub search cap, so select_prs can sample across the full span instead of
# silently collapsing --since into the newest few weeks. Writes window-list.json.
list_window() {
    local target="$1" since_date="$2"
    gh pr list \
        --repo "$target" \
        --state merged \
        --search "merged:>=${since_date}" \
        --limit "$WINDOW_CAP" \
        --json number,title,author,mergedAt \
        > "${WORK_DIR}/window-list.json"
}

# Pick the subset of window-list.json to actually mine, up to MAX_PRS, per the
# coverage mode. Writes pr-list.json (the mined set). Selection lives in jq to
# avoid fragile bash float math; pick_even spreads $k indices evenly across an
# array (both endpoints inclusive) with no duplicates for $k <= length.
select_prs() {
    local mode="$1" limit="$2"
    jq --arg mode "$mode" --argjson limit "$limit" --argjson frac "$BALANCED_RECENT_FRAC" '
        def pick_even($arr; $k):
          ($arr | length) as $n |
          if   $k <= 0  then []
          elif $k >= $n then $arr
          elif $k == 1  then [$arr[0]]
          else [ range(0; $k) | $arr[ ((. * ($n - 1) / ($k - 1)) | round) ] ]
          end;
        ( sort_by(.mergedAt) | reverse ) as $sorted     # newest first
        | ($sorted | length) as $n
        | if   $mode == "recent" then $sorted[0:$limit]
          elif $mode == "full"   then pick_even($sorted; $limit)
          else
            if $n <= $limit then $sorted
            else
              (($limit * $frac) | floor) as $recent_n
              | ($sorted[0:$recent_n]) + pick_even($sorted[$recent_n:]; ($limit - $recent_n))
            end
          end
    ' "${WORK_DIR}/window-list.json" > "${WORK_DIR}/pr-list.json"
}

# Record the realized window of the SET ACTUALLY MINED (not the raw newest-N
# list). Derived from pr-list.json — no extra API calls. Writes manifest.json.
write_manifest() {
    local mode="$1"
    local pr_list="${WORK_DIR}/pr-list.json"
    jq --arg mode "$mode" --arg since_window "$SINCE_WINDOW" '
        . as $p
        | ($p | length) as $count
        | (if $count > 0 then ($p | map(.mergedAt) | min) else null end) as $earliest
        | (if $count > 0 then ($p | map(.mergedAt) | max) else null end) as $latest
        | { pr_count: $count,
            coverage_mode: $mode,
            since_window: $since_window,
            earliest_merged: $earliest,
            latest_merged: $latest,
            window_weeks: (if $count > 0
                           then ((($latest | fromdateiso8601) - ($earliest | fromdateiso8601)) / 86400 / 7 | floor)
                           else 0 end) }
    ' "$pr_list" > "${WORK_DIR}/manifest.json"
}

# Count review-comments + reviews for one PR; tolerant of API errors.
count_comments_for_pr() {
    local n="$1"
    local c r
    c=$(gh api "repos/${TARGET_REPO}/pulls/${n}/comments" --paginate 2>/dev/null \
            | jq -s 'map(length) | add // 0' 2>/dev/null) || c=0
    r=$(gh api "repos/${TARGET_REPO}/pulls/${n}/reviews" --paginate 2>/dev/null \
            | jq -s 'map(length) | add // 0' 2>/dev/null) || r=0
    echo $(( c + r ))
}

# Sample 5 random PRs, compute avg comments/PR, project total.
# Writes estimate.json. Skipped on the full-fetch invocation.
estimate_costs() {
    local since_date="$1"
    local pr_list="${WORK_DIR}/pr-list.json"
    local out="${WORK_DIR}/estimate.json"
    local pr_count
    pr_count=$(jq 'length' "$pr_list")

    # Window coverage: detect when --limit truncated the requested --since
    # window. Compare the date span actually returned against the requested
    # threshold; if the returned PR count saturates MAX_PRS, run a count-only
    # query to discover how many PRs exist in the full window.
    local earliest_merged="" latest_merged="" weeks=0
    if (( pr_count > 0 )); then
        earliest_merged=$(jq -r '[.[].mergedAt] | min' "$pr_list")
        latest_merged=$(jq -r '[.[].mergedAt] | max' "$pr_list")
        weeks=$(jq -n --arg e "$earliest_merged" --arg l "$latest_merged" \
            '(($l | fromdateiso8601) - ($e | fromdateiso8601)) / 86400 / 7 | floor')
    fi

    local total_in_window
    if (( pr_count > 0 )) && (( pr_count >= MAX_PRS )); then
        total_in_window=$(gh pr list \
            --repo "$TARGET_REPO" \
            --state merged \
            --search "merged:>=${since_date}" \
            --json number \
            --limit 99999 \
            2>/dev/null | jq 'length' 2>/dev/null) || total_in_window="$pr_count"
        [[ -z "$total_in_window" ]] && total_in_window="$pr_count"
    else
        total_in_window="$pr_count"
    fi

    local truncated suggested
    if (( total_in_window > MAX_PRS )); then
        truncated="true"
        if   (( total_in_window <= 500 )); then suggested=500
        elif (( total_in_window <= 1000 )); then suggested=1000
        elif (( total_in_window <= 2000 )); then suggested=2000
        else suggested=$(( ((total_in_window + 999) / 1000) * 1000 ))
        fi
    else
        truncated="false"
        suggested="$MAX_PRS"
    fi

    if (( pr_count == 0 )); then
        jq -n \
            --arg target "$TARGET_REPO" \
            --arg since "$since_date" \
            --arg since_window "$SINCE_WINDOW" \
            --argjson max_prs "$MAX_PRS" \
            '{target_repo: $target,
              since: $since,
              since_window: $since_window,
              max_prs: $max_prs,
              pr_count: 0,
              sampled_prs: [],
              sampled_avg_comments: 0,
              projected_total_comments: 0,
              earliest_merged: null,
              latest_merged: null,
              window_weeks: 0,
              total_in_window: 0,
              truncation_detected: false,
              suggested_limit: $max_prs}' \
            > "$out"
        return 0
    fi

    local sampled
    sampled=$(jq -r '.[].number' "$pr_list" \
              | awk 'BEGIN{srand()} {print rand() "\t" $0}' \
              | sort -k1,1 \
              | head -n 5 \
              | cut -f2-)

    local total=0
    local n_sampled=0
    local n c
    while IFS= read -r n; do
        [[ -z "$n" ]] && continue
        c=$(count_comments_for_pr "$n")
        total=$(( total + c ))
        n_sampled=$(( n_sampled + 1 ))
    done <<< "$sampled"

    local avg projected
    if (( n_sampled > 0 )); then
        avg=$(awk -v t="$total" -v s="$n_sampled" 'BEGIN { printf "%.4f", t / s }')
        projected=$(awk -v a="$avg" -v p="$pr_count" 'BEGIN { printf "%d", a * p + 0.5 }')
    else
        avg="0"
        projected="0"
    fi

    local sampled_json
    sampled_json=$(printf '%s\n' "$sampled" | jq -R 'select(length > 0) | tonumber' | jq -s '.')

    jq -n \
        --arg target "$TARGET_REPO" \
        --arg since "$since_date" \
        --arg since_window "$SINCE_WINDOW" \
        --argjson max_prs "$MAX_PRS" \
        --argjson pr_count "$pr_count" \
        --argjson sampled "$sampled_json" \
        --argjson avg "$avg" \
        --argjson projected "$projected" \
        --arg earliest_merged "$earliest_merged" \
        --arg latest_merged "$latest_merged" \
        --argjson weeks "$weeks" \
        --argjson total_in_window "$total_in_window" \
        --argjson truncated "$truncated" \
        --argjson suggested "$suggested" \
        '{target_repo: $target,
          since: $since,
          since_window: $since_window,
          max_prs: $max_prs,
          pr_count: $pr_count,
          sampled_prs: $sampled,
          sampled_avg_comments: $avg,
          projected_total_comments: $projected,
          earliest_merged: $earliest_merged,
          latest_merged: $latest_merged,
          window_weeks: $weeks,
          total_in_window: $total_in_window,
          truncation_detected: $truncated,
          suggested_limit: $suggested}' \
        > "$out"
}

# Fetch comments + reviews for one PR and append normalized JSONL lines
# to a per-PR file so concurrent appends across PRs never collide.
fetch_pr_comments() {
    local n="$1"
    local out="${WORK_DIR}/raw-pr-${n}.jsonl"
    : > "$out"

    local inline_tmp reviews_tmp
    inline_tmp="${WORK_DIR}/.tmp-inline-${n}.json"
    reviews_tmp="${WORK_DIR}/.tmp-reviews-${n}.json"
    echo "[]" > "$inline_tmp"
    echo "[]" > "$reviews_tmp"

    (
        gh api "repos/${TARGET_REPO}/pulls/${n}/comments" --paginate 2>/dev/null \
            | jq -s 'if length == 0 then [] else add end' > "$inline_tmp"
    ) &
    local pid_inline=$!
    (
        gh api "repos/${TARGET_REPO}/pulls/${n}/reviews" --paginate 2>/dev/null \
            | jq -s 'if length == 0 then [] else add end' > "$reviews_tmp"
    ) &
    local pid_reviews=$!

    wait "$pid_inline" || true
    wait "$pid_reviews" || true

    if [[ -s "$inline_tmp" ]]; then
        jq -c --argjson pr "$n" '
            map(select((.user.type // "") != "Bot"))
            | .[]
            | {
                id: .id,
                pr: $pr,
                author: (.user.login // ""),
                kind: "inline",
                path: .path,
                line: (.line // .original_line),
                body: (.body // ""),
                url: (.html_url // ""),
                created_at: (.created_at // ""),
                in_reply_to_id: (.in_reply_to_id // null)
              }
        ' "$inline_tmp" >> "$out" || true
    fi

    if [[ -s "$reviews_tmp" ]]; then
        jq -c --argjson pr "$n" '
            map(select((.user.type // "") != "Bot"))
            | .[]
            | select((.body // "") | length > 0)
            | {
                id: .id,
                pr: $pr,
                author: (.user.login // ""),
                kind: "review",
                path: null,
                line: null,
                body: (.body // ""),
                url: (.html_url // ""),
                created_at: (.submitted_at // ""),
                in_reply_to_id: null
              }
        ' "$reviews_tmp" >> "$out" || true
    fi

    rm -f "$inline_tmp" "$reviews_tmp"
}

fetch_all_comments() {
    local pr_list="${WORK_DIR}/pr-list.json"
    local raw="${WORK_DIR}/raw-comments.jsonl"
    : > "$raw"

    rm -f "${WORK_DIR}"/raw-pr-*.jsonl

    local pr_numbers total i n
    pr_numbers=$(jq -r '.[].number' "$pr_list")
    if [[ -z "$pr_numbers" ]]; then
        return 0
    fi
    total=$(printf '%s\n' "$pr_numbers" | wc -l | tr -d ' ')
    i=0

    while IFS= read -r n; do
        [[ -z "$n" ]] && continue
        i=$((i+1))
        fetch_pr_comments "$n"
        if (( i % 25 == 0 )); then
            echo "  fetched ${i}/${total} PRs..." >&2
        fi
    done <<< "$pr_numbers"

    if compgen -G "${WORK_DIR}/raw-pr-*.jsonl" >/dev/null; then
        cat "${WORK_DIR}"/raw-pr-*.jsonl > "$raw"
        rm -f "${WORK_DIR}"/raw-pr-*.jsonl
    fi
}

# Filter pipeline: drop bot logins, empty bodies, LGTM-class, single
# emojis, and <10-token comments. Outputs JSONL (one object per line).
filter_comments() {
    local raw="${WORK_DIR}/raw-comments.jsonl"
    local out="${WORK_DIR}/comments.jsonl"

    if [[ ! -s "$raw" ]]; then
        : > "$out"
        return 0
    fi

    jq -s -c '
        map(
          select(
            ((.author // "") | test("(\\[bot\\]|-bot)$") | not)
            and ((.body // "") | length > 0)
          )
          | .body_norm = ((.body // "") | gsub("\\s+"; " ")
                                         | sub("^ +"; "")
                                         | sub(" +$"; "")
                                         | ascii_downcase)
        )
        | map(
            select(
              (.body_norm | test("^(lgtm|looks good( to me)?|\\+1|ship it|approved|nice( one)?|thanks|thx|great|cool|perfect|done|ok|👍|🚀|🎉)[.!\\s]*$") | not)
              and ((.body_norm | length > 4) or (.body_norm | test("[a-z]")))
              and ((.body_norm | gsub("[^a-z0-9]+"; " ") | split(" ") | map(select(length > 0)) | length) >= 10)
            )
          )
        | map(del(.body_norm))
        | .[]
    ' "$raw" > "$out"
}

# --- main flow ---

SINCE_DATE=$(resolve_since_date "$SINCE_WINDOW")

if [[ "$ESTIMATE_ONLY" == "1" ]]; then
    list_prs "$TARGET_REPO" "$SINCE_DATE" "$MAX_PRS"
    estimate_costs "$SINCE_DATE"
    echo "wrote: ${WORK_DIR}/estimate.json"
    exit 0
fi

# Full fetch: list the whole window cheaply, then select up to MAX_PRS per the
# coverage mode before paying for the per-PR comment/review fetches.
list_window "$TARGET_REPO" "$SINCE_DATE"
select_prs "$COVERAGE" "$MAX_PRS"
write_manifest "$COVERAGE"

fetch_all_comments
filter_comments

raw_count=$(wc -l < "${WORK_DIR}/raw-comments.jsonl" | tr -d ' ')
final_count=$(wc -l < "${WORK_DIR}/comments.jsonl" | tr -d ' ')
echo "wrote: ${WORK_DIR}/comments.jsonl (${final_count} kept of ${raw_count} raw)"
