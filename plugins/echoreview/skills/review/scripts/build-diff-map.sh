#!/usr/bin/env bash
# build-diff-map.sh — parse a unified diff and emit a map of
# "file:new_line" -> {position, line, side, hunk} so the skill can validate
# that each finding lands on a commentable line before posting.
#
# Position semantics follow GitHub's review-comment API: position 1 is the
# line immediately after the first "@@" hunk header in a file; every
# subsequent line (context, addition, deletion, or another @@ within the
# same file) increments position by 1. Position resets at each new file.
# Only "+" and " " (context) lines have a new-side line number and are
# recorded in the map.
#
# Usage: build-diff-map.sh OWNER REPO PR_NUMBER

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: build-diff-map.sh OWNER REPO PR_NUMBER" >&2
    exit 2
fi

OWNER="$1"
REPO="$2"
NUMBER="$3"
WORK_DIR="${WORK_DIR:-/tmp/echoreview-${NUMBER}}"
DIFF="${WORK_DIR}/diff.patch"
OUT="${WORK_DIR}/diff-map.json"

command -v jq >/dev/null || { echo "error: jq not found. brew install jq" >&2; exit 1; }

if [[ ! -r "$DIFF" ]]; then
    echo "error: ${DIFF} not readable. Run extract-context.sh first." >&2
    exit 1
fi

# Mark unused so shellcheck doesn't complain — kept in the signature for
# parity with the other scripts and in case future versions need them.
: "${OWNER}" "${REPO}"

LC_ALL=C awk '
    function reset_file() {
        position = 0
        new_line = 0
        in_hunk = 0
        hunk_id = 0
    }
    # Decode git C-style quoting. Git wraps paths containing special bytes in
    # double quotes and escapes them: \\, \", \t, \n, \r, plus three-digit
    # octal \NNN for non-ASCII bytes (the form emitted when core.quotePath
    # is true, which is the default).
    function unquote(s,    out, i, n, c, c2, oct) {
        if (substr(s, 1, 1) != "\"") return s
        n = length(s)
        if (substr(s, n, 1) == "\"") { s = substr(s, 2, n - 2); n -= 2 }
        else { s = substr(s, 2); n -= 1 }
        out = ""
        i = 1
        while (i <= n) {
            c = substr(s, i, 1)
            if (c != "\\") { out = out c; i++; continue }
            c2 = substr(s, i + 1, 1)
            if (c2 == "\\" || c2 == "\"") { out = out c2; i += 2 }
            else if (c2 == "t") { out = out "\t"; i += 2 }
            else if (c2 == "n") { out = out "\n"; i += 2 }
            else if (c2 == "r") { out = out "\r"; i += 2 }
            else if (c2 ~ /[0-7]/) {
                oct = substr(s, i + 1, 3)
                if (oct ~ /^[0-7]{3}$/) {
                    out = out sprintf("%c", \
                        (substr(oct,1,1)+0)*64 + \
                        (substr(oct,2,1)+0)*8 + \
                        (substr(oct,3,1)+0))
                    i += 4
                } else { out = out c2; i += 2 }
            }
            else { out = out c2; i += 2 }
        }
        return out
    }
    BEGIN { reset_file(); file = "" }
    /^diff --git / {
        reset_file()
        file = ""
        next
    }
    /^\+\+\+ / {
        rest = substr($0, 5)
        # Unified-diff spec: the filename ends at the first tab; anything
        # after is a timestamp (git omits it, but plain diff -u emits one).
        tab = index(rest, "\t")
        if (tab > 0) rest = substr(rest, 1, tab - 1)
        sub(/[ ]+$/, "", rest)
        if (rest == "/dev/null") { file = ""; next }
        rest = unquote(rest)
        if (substr(rest, 1, 2) == "b/") rest = substr(rest, 3)
        file = rest
        next
    }
    /^@@ / {
        if (file == "") next
        if (in_hunk == 0) {
            in_hunk = 1
            position = 0
        } else {
            position++
        }
        hunk_id++
        if (match($0, /\+[0-9]+/)) {
            spec = substr($0, RSTART + 1, RLENGTH - 1)
            new_line = spec - 1
        }
        next
    }
    in_hunk == 0 { next }
    {
        position++
        c = substr($0, 1, 1)
        if (c == "+" || c == " ") {
            new_line++
            printf "%s\t%d\t%d\t%d\n", file, new_line, position, hunk_id
        }
    }
' "$DIFF" | jq -Rn '
    [ inputs
      | select(length > 0)
      | split("\t")
      | { key: "\(.[0]):\(.[1])",
          value: { position: (.[2] | tonumber),
                   line: (.[1] | tonumber),
                   side: "RIGHT",
                   hunk: (.[3] | tonumber) } }
    ]
    | from_entries
' > "$OUT"

count=$(jq 'length' "$OUT")
echo "wrote: ${OUT} (${count} commentable lines)"
