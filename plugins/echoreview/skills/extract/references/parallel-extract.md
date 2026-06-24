# Parallel extract (multi-agent mode)

This is the multi-agent variant of extraction's reasoning steps. The skill enters
here **only when `AGENT_MODE == multi`** (resolved in Phase 0), and it replaces
single-pass **Phase 2 (cluster)** and **Phase 3 (synthesize rules)**. Phase 0/1
(setup, fetch + filter, the cost checkpoint) and Phase 4 (the pre-write
checkpoint, header, schema, and file write) are unchanged.

The hard requirement is **determinism**: a multi-agent run must produce the same
rules, in the same order, with the same IDs that a single-pass run would. Two
design choices guarantee that — synthesizer agents never assign IDs, and the
orchestrator assigns them only after collecting and sorting every rule.

## Step 0 — capability check (fallback)

This step needs the Task tool. If it is unavailable or the first subagent launch
fails, print `Subagents unavailable; running single-pass.` and run single-pass
Phase 2+3 from `SKILL.md`. The single-pass path produces the same rule set, so
nothing downstream changes.

## Step 1 — cluster

Count the lines in `${WORK_DIR}/comments.jsonl`.

- **≤ 300 comments:** do **not** fan out. Cluster globally in your own context
  exactly per single-pass Phase 2. A whole-corpus view is what lets "same theme,
  different wording" collapse correctly, and that signal is worth more than the
  parallelism on a small set.
- **> 300 comments:** map-reduce.
  - **Map.** Split `comments.jsonl` into chunks of ~200 lines. For each chunk,
    launch an `echo-cluster-mapper` (respecting `AGENT_CAP`), telling it the
    chunk's path and its **global index offset** (chunk 0 → offset 0, chunk 1 →
    offset 200, …) so it reports global indices. Each returns cluster proposals.
  - **Reduce.** Collect all proposals and union same-theme clusters **across**
    chunks into final clusters: merge their `member_indices` and recompute
    `freq` as the merged count. Then **re-derive each merged cluster's category
    over its full unioned member set** — categorize the whole cluster exactly as
    single-pass Phase 2 would, rather than inheriting either chunk's partial
    label (each mapper saw only a subset, so its category is provisional). Use
    the Phase 2 gloss order only to break a genuine tie in that whole-cluster
    judgement. This keeps a fanned-out run in the same `ECHO-<CAT>` bucket — and
    therefore the same IDs — as single-pass. This reduce is your reasoning, not a
    script — no regex, cluster on meaning.

Either way you end Step 1 with the same kind of cluster set single-pass Phase 2
would hold: `{theme, category, member_indices, freq}`.

## Step 2 — synthesize (one agent per qualifying cluster)

For each cluster with `freq >= MIN_FREQ`, launch an `echo-rule-synthesizer`
(in parallel, respecting `AGENT_CAP`). To keep agent count bounded on large runs
you may batch several clusters of the same category into one synthesizer call;
the output shape is the same, one rule object per cluster.

Pass each synthesizer:

- the cluster's `theme`, `category`, `freq`, and its **full member comments**
  (resolve `member_indices` against `comments.jsonl` so the agent has each
  member's `body`, `author`, `pr`, `path`, `kind`); and
- the path to `${CLAUDE_PLUGIN_ROOT}/skills/extract/SKILL.md` so it follows the
  normative **Phase 3** spec (severity's five ordered moves, `applies_to`, quote
  selection).

Each synthesizer returns one rule object **without an ID**:
`{category, freq, title, severity, applies_to, lang, do, dont, quotes[]}`.
Drop clusters below `MIN_FREQ` — never send them to a synthesizer.

## Step 3 — assign IDs (the determinism step)

Collect every synthesized rule. Order them by **category** (ARC, TST, STY, NAM,
API, PRF, DOC, MISC) then by **freq descending** within each category — the exact
single-pass order. Only now assign `[ECHO-<CAT>-<NNN>]`, zero-padded sequential
within each category. Because IDs are assigned after the full set is sorted, the
parallel run and a single-pass run yield identical IDs.

## Step 4 — hand off to Phase 4

Continue with **Phase 4 — Write** in `SKILL.md` exactly as written: Checkpoint 2
(the pre-write confirmation and the rules-to-write summary), the file header from
`manifest.json` / `estimate.json`, and the per-rule schema. The patterns file,
the checkpoints, and the cwd-only write location are unchanged.
