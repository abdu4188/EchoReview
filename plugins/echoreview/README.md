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
├── skills/
│   ├── extract/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       └── fetch-pr-history.sh
│   └── review/
│       ├── SKILL.md
│       ├── references/
│       │   ├── universal-best-practices.md
│       │   ├── reasoning-pass.md
│       │   ├── reasoning-examples.md
│       │   ├── comment-template.md
│       │   └── re-review.md
│       └── scripts/
│           ├── extract-context.sh
│           ├── fetch-comments.sh
│           ├── build-diff-map.sh
│           └── submit-review.sh
└── README.md
```

## Slash commands

| Command | Purpose |
|---|---|
| `/echo-review <pr-number-or-url>` | Review a PR and post a PENDING review with inline comments. |
| `/echo-extract [--repo owner/name] [--since 6mo] [--min-freq 3] [--limit 200]` | Mine merged-PR review history into `.echoreview/patterns.md` in the current working directory. |

`/echo-extract` flag defaults: `--since 6mo`, `--min-freq 3`,
`--limit 200`. The `--repo` flag is optional; if omitted, the skill
infers the target from `git remote get-url origin` in cwd.

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
