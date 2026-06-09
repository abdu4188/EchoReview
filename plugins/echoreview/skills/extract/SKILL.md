---
name: echo-extract
description: Mine a team's PR review patterns from git history into .echoreview/patterns.md. Reads merged PRs from a target repo, clusters review comments semantically, and writes a verbatim-quoted rules file to the current working directory. Use when the user types /echo-extract or asks you to learn their team's review patterns.
user_invocable: true
---

# echo-extract

One-time-ish mining of a repo's PR review history. Produces `.echoreview/patterns.md` in the **current working directory** — never in the target repo, never in `/tmp/`. That file becomes the team-voice input to `/echo-review`.

This skill walks five phases with two user checkpoints (the cost-estimate check and the pre-write check). Skip neither.

## Inputs

```
/echo-extract [--repo owner/name] [--since 12mo] [--min-freq 3] [--limit 500] [--coverage balanced]
```

- `--repo owner/name` — target repo to mine. If absent, derive from `git remote get-url origin` in the current working directory. The canonical case is running from a fork's checkout to mine the upstream.
- `--since` — time window, format `Nd|Nw|Nmo|Ny`. Default `12mo`.
- `--min-freq` — minimum cluster frequency to emit a rule. Default `3`.
- `--limit` — maximum PRs to fetch. Default `500`.
- `--coverage recent|balanced|full` — how `--limit` samples the `--since` window when the window holds more PRs than `--limit`. Default `balanced`.
  - `recent` — newest `--limit` PRs only. Densest signal for current norms; ignores older history.
  - `balanced` — most-recent contiguous block plus a slice sampled across the rest of the window.
  - `full` — even coverage across the mined window. Note GitHub's search API caps any listing at 1000 results, so when a window holds more than 1000 merged PRs even `full` cannot reach past that cap.
  When the window fits within `--limit` (no truncation), all three behave identically — every PR is mined.

## Phase 0 — Setup (silent, do this before Phase 1)

1. Parse flags. Apply defaults: `--since 12mo`, `--min-freq 3`, `--limit 500`, `--coverage balanced`. Remember whether `--coverage` was **explicitly passed** — the truncation prompt in Phase 1 only fires when it was *not*.
2. Verify `gh auth status` succeeds. If not, instruct the user to run `gh auth login` and stop.
3. Resolve `TARGET_REPO`:
   - If `--repo` was passed, validate it matches `owner/name` and use it.
   - Otherwise run `git remote get-url origin` from the current working directory and parse out `owner/name` (handle both `https://github.com/OWNER/REPO(.git)?` and `git@github.com:OWNER/REPO(.git)?` forms).
   - If neither yields a valid `owner/name`, tell the user to pass `--repo owner/name` and stop.
4. Set `WORK_DIR=/tmp/echoreview-extract` and `mkdir -p` it.

## Phase 1 — Fetch + filter

### Step 1a — Cost estimate

Run the fetch script in estimate-only mode:

```
ECHOREVIEW_ESTIMATE_ONLY=1 ${CLAUDE_PLUGIN_ROOT}/skills/extract/scripts/fetch-pr-history.sh \
    "$TARGET_REPO" "$SINCE" "$LIMIT"
```

This lists merged PRs in the window, samples 5 random PRs to compute average comments per PR, projects the total, and writes `${WORK_DIR}/pr-list.json` and `${WORK_DIR}/estimate.json`. Then exits.

Read `${WORK_DIR}/estimate.json` and print to the user:

```
Mining <target_repo> since <since>.
  PRs in window: <pr_count>
  Projected comments: ~<projected_total_comments>
```

### Coverage decision (only if estimate.json `truncation_detected` is true)

If `truncation_detected` is `true`, `--limit` is smaller than the number of merged
PRs in the requested `--since` window, so the run cannot cover the whole window —
it can only choose *how* to sample it. Decide the coverage mode **before** the
cost-guardrail checkpoint:

- **`--coverage` was explicitly passed** → honor it. Print one line, no prompt:
  ```
  --limit <max_prs> can't cover --since <since_window> (~<total_in_window> PRs in range). Sampling with <coverage> coverage.
  ```
- **`--coverage` was not passed** → print this numbered prompt and read a typed
  choice (this is a terminal agent — no GUI). Default to `2` on empty input:
  ```
  --limit <max_prs> can't cover --since <since_window> (~<total_in_window> PRs in range). How should I sample?
    1) recent   — newest ~<window_weeks> weeks only (<earliest> → <latest>), densest signal for current norms
    2) balanced — recent + a slice across the full window (default)
    3) full     — even coverage across the full window (up to GitHub's 1000-PR cap)
  Choose [2]:
  ```
  Map `1`→`recent`, `2`→`balanced`, `3`→`full`. Set `COVERAGE` to the chosen mode.

**Escape hatch.** When `estimate.json` `suggested_limit` is `≤ 1000` **and**
`total_in_window < 1000` — i.e. the whole window fits under GitHub's search cap and a
higher `--limit` would give *genuine* full coverage — append this line to the prompt
(just above `Choose [2]:`) and to the explicit-coverage one-liner:
```
  Or re-run with --limit <suggested_limit> to cover the whole window.
```
If `total_in_window` has reached the 1000 cap, omit it — no `--limit` can exceed the
cap, so full coverage is genuinely unavailable.

`<total_in_window>`, `<window_weeks>`, `<earliest>`, `<latest>`, and `<suggested_limit>`
come verbatim from `estimate.json` (render `earliest_merged` / `latest_merged` as
`YYYY-MM-DD` — slice the date prefix). `window_weeks` is the span of the
newest-`--limit` slice — i.e. the "last ~W weeks" (`<earliest>` → `<latest>`) that
`recent` would mine. `total_in_window` is itself capped at 1000 by GitHub's search API.

If `truncation_detected` is `false`, **skip this step entirely** — every preset
mines the same full window, so there is nothing to choose.

### Checkpoint 1 — cost guardrail (only if projected > 2000)

If `projected_total_comments > 2000`, print:

```
Large mining run. Proceed? (y/N)
```

**Pause and wait for the user's explicit `y`.** Anything else stops the run with no further work and no files written outside `WORK_DIR`.

If `projected_total_comments <= 2000`, skip the prompt — proceed silently.

If `pr_count == 0`, stop and tell the user the window is empty — suggest widening `--since`.

### Step 1b — Full fetch + filter

Run the same script without the env flag, passing the resolved coverage mode:

```
${CLAUDE_PLUGIN_ROOT}/skills/extract/scripts/fetch-pr-history.sh \
    "$TARGET_REPO" "$SINCE" "$LIMIT" "$COVERAGE"
```

This lists the **full** `--since` window (cheap: numbers + merge dates, up to
GitHub's 1000-result cap → `window-list.json`), selects the PRs to mine per
`$COVERAGE` up to `$LIMIT` (→ `pr-list.json`), records the realized window of that
mined set (→ `manifest.json`), then fetches `/comments` + `/reviews` for each
selected PR (`--paginate`, normalized with `jq -s 'if length == 0 then [] else add end'`), writes `raw-comments.jsonl`, and filters to `${WORK_DIR}/comments.jsonl`.

Filter rules applied by the script:
- Drop bot accounts (`user.type == "Bot"` at fetch time; login matches `\[bot\]$` or `-bot$` at filter time).
- Drop empty bodies.
- Drop LGTM-class noise (anchored whole-body match, lowercased).
- Drop single-emoji bodies (`<=4` chars after strip, no ASCII letter).
- Drop comments under 10 tokens.

Read the final line count from `comments.jsonl`. If 0, stop and tell the user the window or filters produced no signal — suggest widening `--since` or checking whether the target repo reviews via PR comments at all.

## Phase 2 — Cluster (in-memory, Claude reasoning only)

Read every line of `${WORK_DIR}/comments.jsonl`. Each line is one normalized comment with `{id, pr, author, kind, path, line, body, url, created_at, in_reply_to_id}`.

Group comments by semantic theme. Each cluster is an internal object:

```
{
  "cluster_id": "C001",
  "theme": "<one-line semantic summary>",
  "category": "ARC | TST | STY | NAM | API | PRF | DOC | MISC",
  "member_indices": [<0-based line indices into comments.jsonl>],
  "freq": <int = len(member_indices)>
}
```

Constraints:
- **No regex / no keyword grouping as preprocessing.** Cluster on meaning, not on string match.
- Comments with the same theme but different wording belong in the same cluster — that voice variety is the signal Phase 3 wants.
- A comment belongs to at most one cluster.
- Singletons are fine; they'll be filtered by `--min-freq` in Phase 3.
- Keep clusters in working memory only. Do not write them to disk in v0.1.

## Phase 3 — Synthesize rules

For each cluster with `freq >= MIN_FREQ`, synthesize one rule.

1. **Category.** Use the cluster's category (`ECHO-ARC`, `ECHO-TST`, `ECHO-STY`, `ECHO-NAM`, `ECHO-API`, `ECHO-PRF`, `ECHO-DOC`, `ECHO-MISC`).
2. **ID.** `[ECHO-<CAT>-<NNN>]` where `<NNN>` is zero-padded sequential within category for this run. Rule IDs renumber on every extraction — never pin downstream automation to them.
3. **Severity.** Default by frequency:
   - `freq >= 20` → `blocker`
   - `freq 5–19` → `warning`
   - `freq 2–4` → `suggestion`
   - `freq 1` → `note`
   Clamp to **`warning` minimum** if the rule's subject matter is security, correctness, or accessibility — judge by reading the cluster, not by the category bucket.
4. **`applies_to`.** Take the longest common path prefix across `member_indices`' `path` fields, suffixed with the uniform file extension if all members share one. Fall back to `"*"` if the cluster is heterogeneous or contains `kind: "review"` members (which have no path).
5. **Title.** One line, imperative voice ("Prefer composition API over options API"). Do not include the pattern ID inside the title — only inside the `[...]` heading bracket.
6. **DO / DON'T code block.** Language tag matches the dominant member-file type; fall back to `text`.
7. **Verbatim quotes (1–3).** **Prioritize characteristic quotes over the most-frequent ones.** Three identical "use translations" comments give weaker voice signal than three different phrasings of the same idea. If one phrasing dominates the cluster, pick one example of it plus 1–2 differently-worded members. Each quote line:

   ```
   > *"<verbatim quote>"* — @<handle>, PR #<number>
   ```

   Pull `<handle>` from the comment's `author` and `<number>` from `pr`. Preserve original casing, punctuation, emoji — these are what carry voice to `/echo-review` later.

Drop clusters whose `freq < MIN_FREQ`.

## Phase 4 — Write

### Checkpoint 2 — confirm before writing

Print to the user:

```
Mined <pr_count> PRs, <comment_count> comments, <cluster_count> clusters → <rule_count> rules.

Rules to write:
  [ECHO-ARC-001] <title>  (freq: N, severity: warning)
  [ECHO-TST-001] <title>  (freq: N, severity: blocker)
  ...
```

If `./.echoreview/patterns.md` already exists in the current working directory:

```
.echoreview/patterns.md already exists. Overwrite? (y/N)
```

**Pause and wait for the user's explicit `y`.** Anything else stops the run; tell the user the rule set is in working memory and they can rerun to regenerate (rule IDs will renumber).

If `./.echoreview/patterns.md` does not exist, skip the prompt.

### Write the file

1. `mkdir -p ./.echoreview/` in the current working directory (**not** in `WORK_DIR`).
2. Write `./.echoreview/patterns.md` per the schema below.

#### File header (top of patterns.md)

The header separates what was **requested** from what was actually **mined**, so
the frequencies below are never read as covering more than they do. Pull the
realized window from `${WORK_DIR}/manifest.json` (`earliest_merged`,
`latest_merged`, `window_weeks`, `coverage_mode`, `pr_count`) and the truncation
facts from `${WORK_DIR}/estimate.json` (`truncation_detected`, `total_in_window`,
`suggested_limit`).
Render `earliest_merged` / `latest_merged` as `YYYY-MM-DD` (slice the date prefix).

```
# EchoReview patterns

Source: <target_repo>
Generated: <YYYY-MM-DD>
Requested:    --since <since>, --min-freq <min_freq>, --limit <limit>, --coverage <coverage>
Window mined: <earliest> → <latest> (~<window_weeks> weeks)
Mined:        <pr_count> PRs, <comment_count> comments, <rule_count> rules
<caveat line>

---
```

The `<caveat line>` depends on coverage mode and whether the window was truncated.
`<total_in_window>` is itself capped at GitHub's 1000-result search limit, so when it
reads `1000` treat it as a floor: render the count `≥1000` and drop the leading `~`
(not an exact `~1000`) — no preset can mine past that cap.

- **not truncated** (`truncation_detected` is `false`) → omit the line entirely.
  The full `--since` window was mined; there is nothing to caveat.
- **truncated + `recent`** →
  ```
  Truncation:   --limit capped the window to ~<window_weeks> weeks; ~<total_in_window> PRs exist in --since range; frequencies reflect only that window.
  ```
- **truncated + `balanced` or `full`** →
  ```
  Sampling:     mined <pr_count> of ~<total_in_window> PRs sampled across the mined window (<coverage> coverage, ≤1000 PRs — GitHub's search cap); frequencies are raw counts over a non-uniform sample and are approximate.
  ```

In **either** truncated case, if `suggested_limit` is `≤ 1000` and `total_in_window <
1000` (the whole window fits under the cap), append a second caveat line offering
genuine full coverage:
```
              Re-run with --limit <suggested_limit> to cover the whole window.
```
If `total_in_window` has reached the 1000 cap, omit it — raising `--limit` cannot
exceed GitHub's search limit, so full coverage is not available.

> **Known limitation.** `freq` is a raw count, not a rate. Under `balanced`, most of
> `--limit` is reserved for the recent block and only the remainder lands on the
> historical tail, so a rare-but-evergreen norm that appears steadily across the full
> window may still fall below `--min-freq` and get dropped. This is accepted, not
> bugged — re-run with `--coverage full` for flatter historical coverage, or lower
> `--min-freq`, if the tail matters to you.

#### Per-rule schema (exactly per DESIGN.md "Patterns schema")

```
### [ECHO-<CAT>-<NNN>] <one-line title>. (freq: <N>)

severity: <blocker | warning | suggestion | note>
applies_to: <glob pattern or "*">

```<lang>
// DO
<good example>

// DON'T
<bad example>
```

> *"<verbatim reviewer quote>"* — @<reviewer-handle>, PR #<number>
> *"<another verbatim quote>"* — @<reviewer-handle>, PR #<number>

---
```

Rules ordered by category (ARC, TST, STY, NAM, API, PRF, DOC, MISC), then by frequency descending within each category.

### Final user message

Short — two lines:

```
Wrote ./.echoreview/patterns.md (<rule_count> rules).
Next: run /echo-review <pr> from a repo where these patterns apply.
```

Do not write a celebration, a roadmap, or a summary of what the rules mean.

## Working directory

All intermediates (`pr-list.json`, `window-list.json`, `estimate.json`, `manifest.json`, `raw-comments.jsonl`, `comments.jsonl`) live in `/tmp/echoreview-extract/`. The patterns file goes to **the user's cwd**, never `/tmp/`. The user owns cleanup of both — don't auto-delete.

## What this skill must not do

- Do not call any external embedding API. Clustering is Claude reasoning only.
- Do not preprocess comments with regex / keyword grouping before clustering. The semantic clustering is the entire point.
- Do not write `patterns.md` anywhere other than `./.echoreview/` in the current working directory.
- Do not classify rules into tiers / `automated` vs `manual` / any non-uniform schema. Every extracted rule carries equal weight at application time.
- Do not invent severity values beyond `blocker | warning | suggestion | note`.
- Do not include pattern IDs inside the rule title — only in the heading bracket.
- Do not pick the most-frequent quote as the example. Pick characteristic quotes that show voice variety.
- Do not exceed `--limit` PRs without the user explicitly raising it.
- Do not add a `config.yml` or any other tunable file. Flags only in v0.1.
