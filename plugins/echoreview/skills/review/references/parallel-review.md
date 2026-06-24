# Parallel review (multi-agent mode)

This is the multi-agent variant of the review's finding-production step. The
skill enters here **only when `AGENT_MODE == multi`** (resolved in Phase 0), and
it runs **between Checkpoint 1 and Phase 4** — it replaces single-pass Phase 2
(pattern review) and Phase 3 (reasoning pass). Everything before it (setup,
context extract, Checkpoint 1) and everything after it (the entire Phase 4 submit
path, both checkpoints, re-review handling) is unchanged. The only contract this
step owes Phase 4 is a populated `$WORK_DIR/findings.json` — Phase 4 cannot tell
whether one agent or five produced it.

The point of fanning out is independence: each lens reviews the whole diff
without being primed by the others, so a security issue and a performance issue
surface in parallel instead of one reasoning pass having to hold all five
concerns at once.

## Step 0 — capability check (fallback is the whole safety net)

Multi-agent mode needs the Task tool. If it is unavailable, or your first
subagent launch is denied or errors out, print one line —
`Subagents unavailable; running single-pass.` — and run single-pass Phase 2+3
from `SKILL.md` instead. The single-pass path is the fallback; it always
produces the same `findings.json` shape, so nothing downstream changes.

## Step 1 — launch the reviewer agents in parallel

Launch these agents at once (in a single batch of Task calls so they run
concurrently). If `AGENT_CAP` is a number, keep at most that many in flight at a
time; if it is `auto`, launch all applicable agents together.

| Agent (`subagent_type`) | Launch when |
|---|---|
| `echo-security-reviewer` | always |
| `echo-correctness-reviewer` | always |
| `echo-quality-reviewer` | always |
| `echo-patterns-reviewer` | only if `.echoreview/patterns.md` exists in the user's cwd |
| `echo-reasoning-reviewer` | only if **no** reasoning-pass skip condition matched (see `reasoning-pass.md`) — same skip gate as single-pass Phase 3 |

Give each agent a prompt with the **absolute paths** it needs:

- `WORK_DIR=$WORK_DIR`, and within it `diff.patch` and `file-types.json`.
- The relevant reference file(s) under
  `${CLAUDE_PLUGIN_ROOT}/skills/review/references/`:
  `universal-best-practices.md` for the three floor reviewers,
  `reasoning-pass.md` + `reasoning-examples.md` for the reasoning reviewer,
  `patterns.md` (the cwd `.echoreview/patterns.md`) + `comment-template.md` for
  the patterns reviewer.

Each agent returns **only** a JSON findings array. Write each return value to its
own file: `$WORK_DIR/findings-security.json`, `findings-correctness.json`,
`findings-quality.json`, `findings-patterns.json`, `findings-reasoning.json`
(only the files for agents you launched).

If file-based plugin agents are not available in this Claude Code version, launch
generic subagents with the same role prompts inline (copy the agent file's body
into the Task prompt). The behavior is identical; only the packaging differs.

## Step 2 — mechanical merge

Run the deterministic half through the helper:

```
${CLAUDE_PLUGIN_ROOT}/skills/review/scripts/merge-findings.sh \
    $WORK_DIR/findings-*.json > $WORK_DIR/findings-merged.json
```

It concatenates the arrays, enforces the reasoning-pass guardrail (drops
`source: "reasoning"` findings below confidence 80 or below warning severity),
and sorts by severity then `file:line`.

## Step 3 — semantic dedup (your judgement, not the script's)

Read `findings-merged.json`. Two lenses sometimes flag the **same** issue at the
same `file:line` in different words — that is a judgement call a string match
can't make, so you collapse those here:

- Group findings that describe the same problem at the same `file:line`.
- Within a group, keep one comment and resolve metadata by priority
  **`patterns` > `universal` > `reasoning`** (team voice beats the floor beats
  the open-ended pass), and take the **highest** severity present.
- Distinct problems on the same line stay as separate findings.

## Step 4 — optional verifier stage (only if `AGENT_VERIFY == 1`)

For each surviving finding, launch one `echo-finding-verifier` (in parallel,
respecting `AGENT_CAP`), passing the finding plus the `diff.patch` path (and the
relevant rule for a `patterns` finding). Drop any finding the verifier returns as
`refuted`. This trades tokens for precision, which is why it is off unless the
team opts into the `verify` tier.

## Step 5 — hand off to Phase 4

Write the final, deduped (and optionally verified) array to
`$WORK_DIR/findings.json` and continue with **Phase 4 — Submit** in `SKILL.md`
exactly as written: the skip gate, `build-diff-map.sh`, the PENDING payload,
Checkpoint 2, and `submit-review.sh`. Re-review handling and the PENDING-only
guarantee are unaffected, because only the way `findings.json` was produced
changed.
