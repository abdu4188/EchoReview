#!/usr/bin/env bash
# merge-findings.sh — combine the findings arrays returned by the parallel
# reviewer agents into one sorted array, applying the deterministic, purely
# mechanical part of the merge so the skill never re-derives it in prose.
#
# It does three things and only three things:
#   1. Concatenate every input array into one.
#   2. Enforce the Phase 3 reasoning-pass guardrail: drop findings whose
#      `source` is "reasoning" unless they clear confidence >= 80 AND carry
#      a blocker/warning severity. (Universal- and patterns-sourced findings
#      keep their declared severities, suggestions included — only the
#      open-ended reasoning pass is held to the higher bar.)
#   3. Sort by severity (blocker > warning > suggestion > note), then
#      file, then line — the same order Phase 4 expects.
#
# A well-formed agent return is a JSON array. Any input file that is missing,
# not valid JSON, or not an array is skipped with a warning to stderr, never
# fatal — one off-contract agent must not abort the merge and discard every
# other agent's findings.
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

# Validate inputs up front: keep only files that are a readable JSON array.
# Skipping (not aborting) on a malformed file is the whole point — a single
# bad agent response can't sink the well-formed ones.
valid_files=()
for f in "$@"; do
    if [[ ! -r "$f" ]]; then
        echo "warning: merge-findings: '$f' is unreadable; skipping." >&2
        continue
    fi
    if ! jq -e 'type == "array"' "$f" >/dev/null 2>&1; then
        echo "warning: merge-findings: '$f' is not a JSON array; skipping." >&2
        continue
    fi
    valid_files+=("$f")
done

if [[ ${#valid_files[@]} -eq 0 ]]; then
    echo "[]"
    exit 0
fi

# Report how many reasoning findings the floor drops, so the loss is visible
# rather than silent (a genuine blocker that omits `confidence` is treated as
# unscored and dropped — see the guardrail below).
dropped=$(jq -s '
    def num(v): (v | if type == "number" then .
                     elif type == "string" then (tonumber? // 0)
                     else 0 end);
    [ (add // [])[] | select(type == "object") | select(.source == "reasoning") ] as $r
    | ($r | length)
      - ([ $r[] | select((num(.confidence) >= 80)
                         and (.severity != "suggestion")
                         and (.severity != "note")) ] | length)
' "${valid_files[@]}")

if [[ "${dropped:-0}" -gt 0 ]]; then
    echo "note: merge-findings: dropped ${dropped} reasoning finding(s) below the confidence-80 / blocker-warning floor." >&2
fi

# The reasoning-pass floor (confidence >= 80 AND blocker/warning) is also
# authored in references/reasoning-pass.md and agents/echo-reasoning-reviewer.md.
# Keep all three in lockstep if the threshold ever changes.
jq -s '
    def num(v): (v | if type == "number" then .
                     elif type == "string" then (tonumber? // 0)
                     else 0 end);
    def srank(s): {"blocker":0, "warning":1, "suggestion":2, "note":3}[s // ""] // 4;
    (add // [])
    | map(select(type == "object"))
    | map(select(
        (.source != "reasoning")
        or ((num(.confidence) >= 80)
            and (.severity != "suggestion")
            and (.severity != "note"))
      ))
    | sort_by(srank(.severity), (.file // ""), num(.line))
' "${valid_files[@]}"
