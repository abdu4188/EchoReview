# echoreview plugin

The `echoreview` Claude Code plugin. Contains two user-invocable
skills:

- `echo-review` — review a PR against a universal best-practices floor
  and the team's `.echoreview/patterns.md` (if present), posting a
  PENDING review with inline comments.
- `echo-extract` — mine merged-PR review history into
  `.echoreview/patterns.md` in the current working directory, ready
  for `echo-review` to apply on subsequent reviews.

## Layout

```
plugins/echoreview/
├── .claude-plugin/
│   └── plugin.json
├── agents/                         # read-only subagent roles (multi-agent mode)
│   ├── echo-security-reviewer.md
│   ├── echo-correctness-reviewer.md
│   ├── echo-quality-reviewer.md
│   ├── echo-patterns-reviewer.md
│   ├── echo-reasoning-reviewer.md
│   ├── echo-finding-verifier.md
│   ├── echo-cluster-mapper.md
│   └── echo-rule-synthesizer.md
├── scripts/
│   └── resolve-agents.sh           # ECHOREVIEW_AGENTS / flags → mode (shared)
├── skills/
│   ├── extract/
│   │   ├── SKILL.md
│   │   ├── references/
│   │   │   └── parallel-extract.md
│   │   └── scripts/
│   │       └── fetch-pr-history.sh
│   └── review/
│       ├── SKILL.md
│       ├── references/
│       │   ├── universal-best-practices.md
│       │   ├── reasoning-pass.md
│       │   ├── reasoning-examples.md
│       │   ├── comment-template.md
│       │   ├── re-review.md
│       │   └── parallel-review.md
│       └── scripts/
│           ├── extract-context.sh
│           ├── fetch-comments.sh
│           ├── build-diff-map.sh
│           ├── merge-findings.sh
│           └── submit-review.sh
└── README.md
```

## Slash commands

| Command | Purpose |
|---|---|
| `/echo-review <pr-number-or-url> [--agents N \| --no-agents] [--verify]` | Review a PR and post a PENDING review with inline comments. |
| `/echo-extract [--repo owner/name] [--since 12mo] [--min-freq 3] [--limit 500] [--agents N \| --no-agents]` | Mine merged-PR review history into `.echoreview/patterns.md` in the current working directory. |

`/echo-extract` flag defaults: `--since 12mo`, `--min-freq 3`,
`--limit 500`. The `--repo` flag is optional; if omitted, the skill
infers the target from `git remote get-url origin` in cwd.

## Multi-agent mode

Both skills fan out to parallel subagents by default — `echo-review`
runs one reviewer per lens (security, correctness, quality, team
patterns, reasoning) and merges their findings; `echo-extract`
synthesizes rules in parallel. The roles are the read-only definitions
under `agents/`, and `scripts/resolve-agents.sh` is the single place
the mode is resolved.

Turn it off with `ECHOREVIEW_AGENTS=off` (in your Claude
`settings.json` `env` block or your shell), or per run with
`--no-agents`. `--agents N` caps concurrent subagents and `--verify`
adds an adversarial pass that drops weak findings. When subagents
aren't available the skills fall back to the original single pass, which
produces identical output and is what the eval harness exercises.

## Requirements

- `gh` CLI authenticated against the target repo (`gh auth login`).
- `jq` on `$PATH`.
- Write/triage permission on the target repo (GitHub requires it to
  POST a review). `/echo-extract` is read-only — it only mines
  history — so the `--repo` flag works against upstreams you don't
  have write access to.

See the repo root [`README.md`](../../README.md) for install
instructions and [`DESIGN.md`](../../DESIGN.md) for the broader product
brief.
