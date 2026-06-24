# 06-merge-findings

Drives `plugins/echoreview/skills/review/scripts/merge-findings.sh` directly with
inline findings arrays, asserting the merged output. It has no `input/` artifacts
that trigger the review scripts — the only check type is `merge_findings`, which
supplies its own input arrays and expected order/count.

This is the unit test that guards the deterministic multi-agent merge: it must
never crash on off-contract agent output (null/missing `severity`, a non-array
file, string `confidence`/`line`), must enforce the reasoning-pass confidence-80
floor, and must sort by severity then `file:line` numerically.
