# EchoReview

> Reviews PRs the way your team would.

A Claude Code plugin that learns a team's PR review patterns from git history and applies them — alongside a universal best-practices floor — when Claude reviews new PRs. Output is always a **PENDING** GitHub review that you own.

## Status

v0.1.0 — Sprint 1: scaffold + `echo-review` skill with the universal best-practices floor.

`echo-extract` (pattern mining) and the eval harness land in subsequent sprints. See [`DESIGN.md`](./DESIGN.md) for the full brief.

## Install

```sh
# Add this repo as a local marketplace
/plugin marketplace add /path/to/echoreview

# Install the plugin
/plugin install echoreview@echoreview
```

Once published to a GitHub remote, `/plugin marketplace add abdu4188/echoreview` works too.

## Use

```sh
# Review a PR (URL or owner/repo#N form recommended)
/echo-review https://github.com/your-org/your-repo/pull/42
```

The skill walks four phases with two checkpoints:

1. **Context extract** — pulls PR metadata, diff, and existing comments via `gh` CLI. Pauses for your confirmation on the summary.
2. **Pattern review** — applies the universal best-practices floor (and `.echoreview/patterns.md` if present in the target repo).
3. **Reasoning pass** — open-ended contradiction-finding pass, ≥80 confidence, BLOCKER/WARNING only. Skipped for lockfile-only, docs-only, generated, or pure version-bump PRs.
4. **Submit** — composes inline comments validated against the diff position map, then pauses before posting the PENDING review.

You always click **Submit review** on GitHub yourself. EchoReview never finalizes a review for you.

## Privacy

- Runs entirely inside your Claude Code session on your machine.
- Uses your Claude Code subscription auth — no Anthropic API key required.
- Shells out only to `gh` CLI and `git`. No third-party endpoints.
- Does not send code, diffs, or patterns to any server we control. We have no server.

How Anthropic processes data once it enters your Claude Code context is governed by their privacy policy, not this plugin. As with any Claude Code plugin, review the contents of `SKILL.md` and the bash scripts under `plugins/echoreview/skills/` before installing.

## License

MIT — see [`LICENSE`](./LICENSE).
