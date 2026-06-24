#!/usr/bin/env bash
# resolve-agents.sh — resolve EchoReview's multi-agent mode from the
# ECHOREVIEW_AGENTS env var plus any per-run flag tokens.
#
# Multi-agent fan-out is ON by default: EchoReview spreads a review's
# lenses (or extraction's clusters) across parallel subagents whenever the
# session can run them. A team opts out durably by setting
# ECHOREVIEW_AGENTS=off in the `env` block of their Claude settings.json
# (or in the shell); a single run can override either way with flags. This
# script is the one place that resolution lives, so both skills read the
# setting identically and the eval harness can pin every branch.
#
# Usage:   resolve-agents.sh [FLAG ...]
#   FLAG is any raw slash-command token the skill saw; only these matter:
#     --no-agents     force single-pass for this run
#     --agents        force multi-agent (keep any explicit cap)
#     --agents=N      force multi-agent, cap N concurrent subagents
#     --verify        add the adversarial verifier stage
#   Unrelated tokens are ignored, so the skill can forward argv as-is.
#
# Input:   $ECHOREVIEW_AGENTS (env) + flags (args). Flags win over env.
# Output:  one line "MODE<TAB>CAP<TAB>VERIFY" on stdout:
#            MODE   = single | multi
#            CAP    = auto | <positive int>   ("-" when single)
#            VERIFY = 0 | 1
#
# Pure string logic — no gh, no jq, no network — so it is cheap to call on
# every run and trivial to unit-test.

set -euo pipefail

mode="multi"
cap="auto"
verify="0"

# A usable concurrency cap is a positive integer; 0 is treated as "off"
# upstream, never as a cap.
is_uint() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

# --- 1. Seed from the env var (the durable setting). ---
raw="${ECHOREVIEW_AGENTS:-}"
val="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"

case "$val" in
    ""|on|1|true|auto|yes)
        mode="multi"; cap="auto"; verify="0" ;;
    off|0|false|no)
        mode="single" ;;
    verify)
        mode="multi"; cap="auto"; verify="1" ;;
    verify:*)
        mode="multi"; verify="1"
        n="${val#verify:}"
        if is_uint "$n"; then cap="$n"; else cap="auto"; fi ;;
    *)
        if is_uint "$val"; then
            mode="multi"; cap="$val"; verify="0"
        else
            mode="multi"; cap="auto"; verify="0"
            echo "warning: unrecognized ECHOREVIEW_AGENTS='${raw}'; defaulting to multi-agent." >&2
        fi ;;
esac

# --- 2. Per-run flags override the env, processed left to right. ---
for tok in "$@"; do
    case "$tok" in
        --no-agents)
            mode="single" ;;
        --agents)
            mode="multi"; [[ "$cap" == "-" ]] && cap="auto" ;;
        --agents=*)
            mode="multi"
            n="${tok#--agents=}"
            if is_uint "$n"; then cap="$n"; else cap="auto"; fi ;;
        --verify)
            mode="multi"; [[ "$cap" == "-" ]] && cap="auto"; verify="1" ;;
        *)
            : ;;
    esac
done

# --- 3. Normalize: single-pass carries no cap and no verifier. ---
if [[ "$mode" == "single" ]]; then
    cap="-"
    verify="0"
fi

printf '%s\t%s\t%s\n' "$mode" "$cap" "$verify"
