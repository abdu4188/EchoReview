# EchoReview

> Reviews PRs the way your team would.

A Claude Code plugin that learns a team's PR review patterns from git
history and applies them — alongside a universal best-practices floor —
when Claude reviews new PRs. Output is always a **PENDING** GitHub
review that you own.

## What it does

`/echo-extract` mines your team's merged PRs once, clusters reviewer
comments semantically, and writes a verbatim-quoted rule catalog to
`.echoreview/patterns.md` in your repo. After that, every
`/echo-review <pr>` applies that catalog on top of a universal floor
(security, correctness, accessibility, performance footguns, common
bug patterns) and posts a PENDING review with inline comments. You
click **Submit review** on GitHub when you're ready.

The catalog carries verbatim evidence quotes — and Claude mirrors that
voice when posting comments. A flagged conditional in a test from a
team that's reviewed many like it sounds like the team, not like an AI
checklist:

```text
# Universal-floor voice (no team patterns):
Avoid conditional logic in tests. Branches that don't execute the
assertion will silently pass.

# After mining a team patterns.md (same finding, different voice):
we shouldn't have conditions in tests. if `items[0]` ever became null
here, the assertion silently doesn't run — we'd miss the failure.
drop the `if` and use a non-null assertion: `expect(items[0]!).toBe(1)`.
```

The second form mirrors the team's own evidence quotes — lowercase
"we shouldn't", the "miss the failure" rationale, the
non-null-assertion suggestion with backticks — because those quotes
sit in the rule that drove the comment.

## Install

Prerequisites: `gh` (the GitHub CLI), `jq`, and Claude Code.

1. **Authenticate `gh`** if you haven't already:
   ```sh
   gh auth login
   ```
2. **Add this repo as a marketplace** in Claude Code:
   ```sh
   /plugin marketplace add abdu4188/echoreview
   ```
3. **Install the plugin**:
   ```sh
   /plugin install echoreview@echoreview
   ```
4. **Verify**: run `/plugin list` — `echoreview` should appear as
   installed.
5. **Optional but recommended — mine your team patterns** from a
   checkout of the repo you want reviewed:
   ```sh
   cd ~/code/your-repo
   /echo-extract --since 12mo
   ```
   The skill walks you through a cost-estimate checkpoint, then writes
   `.echoreview/patterns.md` to the current working directory. Commit
   that file (or not — your call). Skipping this step still gives you
   reviews against the universal-best-practices floor.

## Use

```sh
# Review a PR. The URL form is most reliable; OWNER/REPO#N and the
# bare-number form (when cwd is a clone of the target repo) also work.
/echo-review https://github.com/your-org/your-repo/pull/42
```

The review skill walks four phases with two checkpoints:

1. **Context extract** — pulls PR metadata, diff, and prior comments
   via `gh`. Pauses for you to confirm the summary.
2. **Pattern review** — applies the universal best-practices floor
   and, if present, `.echoreview/patterns.md` from cwd.
3. **Reasoning pass** — open-ended contradiction-finding pass, ≥80
   confidence, BLOCKER/WARNING only. Skipped for lockfile-only,
   docs-only, generated-only, or pure-version-bump PRs.
4. **Submit** — composes inline comments validated against the diff
   position map, then pauses before posting a PENDING review.

You always click **Submit review** on GitHub yourself. EchoReview
never finalizes a review for you.

To learn your team's patterns once before reviewing:

```sh
# From a checkout of the repo to mine. --repo lets you mine an upstream
# you don't have write access to (e.g., run from a fork's checkout).
# --coverage (recent|balanced|full) chooses how --limit samples the
# --since window when the window holds more PRs than --limit.
/echo-extract [--repo owner/name] [--since 12mo] [--min-freq 3] [--limit 500] [--coverage balanced]
```

## Privacy

- Runs entirely inside your Claude Code session on your machine.
- Uses your Claude Code subscription auth — no Anthropic API key required.
- Shells out only to `gh` CLI and `git`. No third-party endpoints.
- Does not send code, diffs, or patterns to any server we control. We
  have no server.

How Anthropic processes data once it enters your Claude Code context
is governed by their privacy policy, not this plugin. As with any
Claude Code plugin, review the contents of `SKILL.md` and the bash
scripts under `plugins/echoreview/skills/` before installing.

## Evals

The repo includes a small eval harness covering the bash-plumbing
layer of the review skill (file-type classification, diff-position
mapping, re-review detection, lockfile-skip behavior). To run:

```sh
bash evals/run.sh
```

See [`evals/README.md`](./evals/README.md) for what's covered and how
to add a fixture.

## License

MIT — see [`LICENSE`](./LICENSE).
