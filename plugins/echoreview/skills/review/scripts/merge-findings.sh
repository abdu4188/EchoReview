#!/usr/bin/env bash
# merge-findings.sh — combine the findings arrays returned by the parallel
# reviewer agents into one sorted array, applying the deterministic, purely
# mechanical part of the merge so the skill never re-derives it in prose.
#
# It does two things and only two things:
#   1. Concatenate every input array into one.
#   2. Enforce the Phase 3 reasoning-pass guardrail: drop findings whose
#      `source` is "reasoning" unless they clear confidence >= 80 AND carry
#      a blocker/warning severity. (Universal- and patterns-sourced findings
#      keep their declared severities, suggestions included — only the
#      open-ended reasoning pass is held to the higher bar.)
#   3. Sort by severity (blocker > warning > suggestion > note), then
#      file, then line — the same order Phase 4 expects.
#
# The *semantic* dedup (two lenses flagging the same issue) stays with the
# orchestrating skill: deciding that two differently-worded comments are the
# "same finding" is a judgement call, not a string match. This script only
# does what is deterministic.
#
# Usage:   merge-findings.sh FILE [FILE ...]
#   Each FILE is a JSON array of findings, each finding shaped
#     {file, line, severity, source, pattern_id?, comment, confidence}
# Output:  the merged, filtered, sorted JSON array on stdout.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: merge-findings.sh FILE [FILE ...]" >&2
    exit 2
fi

command -v jq >/dev/null || { echo "error: jq not found. brew install jq" >&2; exit 1; }

jq -s '
    def srank(s): {"blocker":0, "warning":1, "suggestion":2, "note":3}[s] // 4;
    (add // [])
    | map(select(
        (.source != "reasoning")
        or (((.confidence // 0) >= 80)
            and (.severity != "suggestion")
            and (.severity != "note"))
      ))
    | sort_by(srank(.severity), (.file // ""), (.line // 0))
' "$@"
