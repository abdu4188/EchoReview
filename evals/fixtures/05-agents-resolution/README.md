# 05-agents-resolution

Drives `plugins/echoreview/scripts/resolve-agents.sh` directly across the full
`ECHOREVIEW_AGENTS` decision table and the per-run flag precedence, asserting the
resolved `mode / cap / verify` triple for each case.

It has no `input/` artifacts that trigger the review scripts — the only check
type is `agents_resolution`, which supplies its own env value and flags. This is
the unit test that guards the multi-agent opt-out: single-pass on `off`, fan-out
by default, the `verify` tier, an integer concurrency cap, and flags overriding
the env var either way.
