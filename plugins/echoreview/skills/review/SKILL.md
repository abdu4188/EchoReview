---
name: echo-review
description: Review a GitHub PR and post a PENDING review with inline comments. Applies a universal best-practices floor and, if present in the target repo, team-mined patterns from .echoreview/patterns.md. Use when the user types /echo-review <pr> or asks you to review a PR for them.
user_invocable: true
---

# echo-review

Review a single GitHub PR and post a **PENDING** review back to GitHub. The human always clicks Submit — never finalize a review automatically.

This skill walks four phases with two user checkpoints (after Phase 1 and before Phase 4 submission). Skip neither.

## Inputs

`/echo-review <pr>` where `<pr>` is one of:
- A full PR URL: `https://github.com/OWNER/REPO/pull/N`
- An `OWNER/REPO#N` reference
- A bare number `N` (only valid when the current working directory is a clone of the target repo)

If the user gave no argument, ask for one. Don't guess.

## Phase 0 — Setup (silent, do this before Phase 1)

1. Resolve the input to `OWNER`, `REPO`, `NUMBER`:
   - URL form: parse `OWNER`, `REPO`, `N` from the URL path.
   - `OWNER/REPO#N` form: split on `/` and `#`.
   - Bare number: run `gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'` from the current working directory to fill in `OWNER/REPO`; if that fails (not in a repo), tell the user and stop.
2. Verify `gh auth status` succeeds. If not, instruct the user to run `gh auth login` and stop.
3. Set `WORK_DIR=/tmp/echoreview-${NUMBER}` and `mkdir -p` it.

## Phase 1 — Context extract

Run the two extract scripts **in parallel** from `${CLAUDE_PLUGIN_ROOT}/skills/review/scripts/`:

- `extract-context.sh "$OWNER" "$REPO" "$NUMBER"` — writes `metadata.json`, `diff.patch`, `files.txt`, `file-types.json` to `$WORK_DIR`.
- `fetch-comments.sh "$OWNER" "$REPO" "$NUMBER"` — writes `existing-comments.json`, `existing-reviews.json`, `review-iteration.txt`, `previous-comments.md` to `$WORK_DIR`.

After both complete:

1. Read `metadata.json` for the PR title, author, base/head refs, and stats.
2. Read `file-types.json` and tally counts per `type` field.
3. Read `review-iteration.txt`. If `2`, this is a re-review — load [`references/re-review.md`](./references/re-review.md) and read `previous-comments.md`.

### Checkpoint 1 — confirm before proceeding

Print a summary to the user that looks like:

```
PR #<N>: <title>
  Author: @<login>
  Base ← Head: <base> ← <head>
  Files changed: <count> (<type breakdown>)
  Prior comments: <count> (<iteration label: first review | re-review>)

Continue with the review? (y/N)
```

**Pause and wait for the user's explicit y/N.** If anything other than `y` / `yes` / `Y`, stop and report no review was created.

## Phase 2 — Pattern review

1. Load [`references/universal-best-practices.md`](./references/universal-best-practices.md).
2. From the user's current working directory, check whether `.echoreview/patterns.md` exists. If so, load it. If not, proceed with the universal floor only — this is the expected v0.1 path until `echo-extract` ships.
3. Read `$WORK_DIR/diff.patch`.
4. Apply both rule sets against the diff. For each finding, capture:
   - `file` (post-rename, new-side path)
   - `line` (new-side line number)
   - `severity` per [`universal-best-practices.md`](./references/universal-best-practices.md) (or the rule's declared severity from `patterns.md`)
   - `source` — one of `universal`, `patterns`
   - `pattern_id` — only set for patterns-driven findings (e.g. `ECHO-ARC-001`); used as metadata, never printed in the comment
   - `comment` — drafted per [`references/comment-template.md`](./references/comment-template.md). For findings tied to a `patterns.md` rule, the rule's verbatim evidence quotes are the voice guide for this comment — match their register, length, vocabulary, emoji usage, code-block usage, capitalization, punctuation, and phrasing patterns. Do not impose a house style on top of them.
5. Write the structured findings to `$WORK_DIR/findings.json` as a JSON array.

## Phase 3 — Reasoning pass

Check the skip conditions from [`references/reasoning-pass.md`](./references/reasoning-pass.md). If any matches, **skip this phase entirely** — do not surface any reasoning-pass findings and do not penalize the PR for being lockfile-only / docs-only / generated / a pure version bump.

Otherwise:

1. Load [`references/reasoning-pass.md`](./references/reasoning-pass.md) and [`references/reasoning-examples.md`](./references/reasoning-examples.md).
2. Run the open-ended contradiction-finding pass over `$WORK_DIR/diff.patch`.
3. For each candidate finding, assign an explicit numeric `confidence` (0–100). **Drop any finding below 80.** **Drop any finding whose severity would be `suggestion` or `note`** — Phase 3 is BLOCKER/WARNING only.
4. Drop any finding you would have to hedge with "possibly", "could be", "might".
5. Append surviving findings to `$WORK_DIR/findings.json` with `source: "reasoning"`.

## Phase 4 — Submit

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/review/scripts/build-diff-map.sh "$OWNER" "$REPO" "$NUMBER"` to produce `$WORK_DIR/diff-map.json`.
2. For each finding in `$WORK_DIR/findings.json`:
   - Look up `"<file>:<line>"` in `diff-map.json`.
   - If present, record the comment with `path`, `position`, `body`.
   - If missing, demote to the review body under a section `## Additional findings (outside diff range):`.
3. Sort comments by severity (`blocker` → `warning` → `suggestion` → `note`), then by `file:line` ascending. No count cap.
4. If `review-iteration.txt` is `2`, prepend the resolution table from [`references/re-review.md`](./references/re-review.md) to the review body.
5. Write `$WORK_DIR/review-comments.json` (the in-diff comment array) and `$WORK_DIR/submission-payload.json` with this shape:

```json
{
  "body": "<resolution table + out-of-diff findings, or empty string>",
  "comments": [
    { "path": "<file>", "position": <int>, "body": "<comment body>" }
  ]
}
```

**Do not include an `event` field.** On GitHub's API, omitting `event` produces a PENDING review; setting it to `APPROVE` / `REQUEST_CHANGES` / `COMMENT` submits the review immediately. `submit-review.sh` refuses to POST any payload that has an `event` field set.

### Checkpoint 2 — confirm before submission

Print to the user:

- The compiled findings list, grouped by severity, each shown as `<severity>  <file>:<line>  <comment>` (truncate the comment to one line for the summary).
- A count line: `<N> inline, <M> in body (out-of-diff)`.
- The question: `Submit PENDING review on PR #<N>? (y/N)`

**Pause and wait for the user's explicit y/N.** Anything other than `y` / `yes` / `Y` stops the run; tell the user the payload is on disk at `$WORK_DIR/submission-payload.json` if they want to inspect.

On `y`:

6. Run `${CLAUDE_PLUGIN_ROOT}/skills/review/scripts/submit-review.sh "$OWNER" "$REPO" "$NUMBER"`. It POSTs the payload.
7. Print the resulting PR URL (read from `metadata.json` `.html_url`) so the user can click through and Submit on GitHub.

## Output to the user (final message)

Short — three lines:

```
Posted PENDING review on PR #<N>: <html_url>
<inline_count> inline comments, <body_count> in body.
Click "Submit review" on GitHub when you're ready.
```

Do not write a celebration, a next-steps list, or a summary of what the PR was about.

## Working directory

All intermediates live in `/tmp/echoreview-${NUMBER}/`. Never write inside the user's repo. The user owns cleanup — don't auto-delete.

## What this skill must not do

- Do not change the `event` to `COMMENT`, `APPROVE`, or `REQUEST_CHANGES`. PENDING only.
- Do not skip either checkpoint.
- Do not invent skip conditions beyond those listed in [`references/reasoning-pass.md`](./references/reasoning-pass.md).
- Do not include pattern IDs in posted comment bodies, impersonate named reviewers, or harass the PR author (see [`references/comment-template.md`](./references/comment-template.md) for the three guardrails).
- Do not cap the number of comments. Trust the severity declarations and the reasoning-pass threshold.
