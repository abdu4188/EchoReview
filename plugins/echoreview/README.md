# echoreview plugin

The `echoreview` Claude Code plugin. Contains the `echo-review` skill (PR review against a universal best-practices floor plus an optional team `.echoreview/patterns.md`).

`echo-extract` (mining team patterns from PR history) ships in a later sprint.

## Layout

```
plugins/echoreview/
├── .claude-plugin/
│   └── plugin.json
├── skills/
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

## Requirements

- `gh` CLI authenticated against the target repo (`gh auth login`).
- `jq` on `$PATH`.
- Write/triage permission on the target repo (GitHub requires it to POST a review).

See the repo root [`README.md`](../../README.md) and [`DESIGN.md`](../../DESIGN.md) for the broader product brief.
