# EchoReview eval harness

The harness validates the bash-plumbing layer of EchoReview — file-type
classification, diff-position mapping, re-review iteration detection,
and PR-history filter behavior. It does **not** test Claude's review
reasoning (the actual finding generation, voice matching, and
severity calls); those are exercised by the end-to-end test described
under "Manual verification" below.

Multi-agent fan-out is part of that Claude-driven layer, so the harness
pins `ECHOREVIEW_AGENTS=off` and validates the single-pass plumbing both
modes share. The one exception is the `resolve-agents.sh` mode resolver
itself, which is pure bash and is unit-tested directly (fixture
`05-agents-resolution`).

## Run

```sh
bash evals/run.sh
```

Requirements: `bash`, `jq`, `awk`. No `gh` CLI needed for the harness
itself — each fixture pre-populates the artifacts the gh-fetching
scripts would have produced, and the harness invokes the scripts with
`ECHOREVIEW_SKIP_FETCH=1` so the network layer is bypassed.

Exit code is 0 when every fixture passes, 1 otherwise. Failures print
fixture name and the offending assertion.

## Fixtures

Each subdirectory of `evals/fixtures/` is one fixture. Layout:

```
fixtures/<name>/
├── README.md         # what this fixture covers
├── input/            # files copied into a temp WORK_DIR before the run
│   ├── files.txt              # → triggers extract-context.sh
│   ├── diff.patch             # → triggers build-diff-map.sh
│   ├── existing-comments.json # → triggers fetch-comments.sh
│   └── existing-reviews.json
├── patterns.md       # (optional) synthetic team patterns for this fixture
└── expected.json     # the assertions
```

`expected.json` shape:

```json
{
  "name": "Short human-readable name",
  "description": "What this fixture validates in one sentence.",
  "checks": [
    { "type": "file_type", "file": "src/auth.ts", "expected": "js-ts" },
    { "type": "diff_map_line", "file": "src/auth.ts", "line": 15 },
    { "type": "review_iteration", "expected": "2" }
  ]
}
```

The harness routes each `type` to a check function in `evals/lib.sh`.
Supported check types:

| Type | Asserts |
|---|---|
| `file_type` | `file-types.json` classifies `file` as `expected`. |
| `file_count_with_type` | exactly `expected_count` files in `file-types.json` have type `expected_type`. |
| `only_file_types` | every entry in `file-types.json` has a type in the `allowed` array. |
| `diff_map_line` | `diff-map.json` contains an entry for `file:line`. |
| `review_iteration` | `review-iteration.txt` equals `expected` ("1" or "2"). |
| `summary_contains_count` | `previous-comments.md` heads with `Prior review comments (expected)`. |
| `summary_quotes_author` | `previous-comments.md` mentions `@author`. |
| `summary_preserves_reply_chain` | at least one `in_reply_to_id: <n>` record present. |
| `patterns_readable` | sibling `patterns.md` has ≥ `expected_rule_count` rules, each with ≥ 1 verbatim quote. |
| `patterns_header` | sibling `patterns.md` contains every header token in `requires` (catches a header-field rename, e.g. `Requested:`/`Window mined:`). |
| `agents_resolution` | `resolve-agents.sh` maps the check's `env` value + `args` flags to `expected_mode`/`expected_cap`/`expected_verify`. Drives the script directly; no WORK_DIR artifacts. |

Comparisons are by substance, not byte-for-byte. The Claude-driven
parts (comment voice, severity rationale text) are intentionally not
asserted here — they vary per run.

## What counts as a regression

- Any fixture flipping from PASS to FAIL.
- An assertion stops finding what it used to find — e.g., file-type
  classifier no longer recognizes a test file because its extension
  matcher changed.
- A new edge case the harness should cover but doesn't (add a fixture).

## Manual verification (not run by the harness)

The harness can't drive Claude's review reasoning. To validate that
the full skill stack still produces voice-matched team-pattern
comments and neutral universal-floor comments, post-install:

1. From a clone of a repo with a checked-in `.echoreview/patterns.md`,
   open a small PR with one universal-floor issue and one issue that
   matches a `patterns.md` rule.
2. Run `/echo-review <pr-url>`.
3. Inspect the resulting PENDING review on github.com — verify both
   findings land inline and the pattern-driven comment reads in the
   team's voice.

## Adding a fixture

1. Create `evals/fixtures/<NN>-<slug>/`.
2. Write `README.md` describing what it covers.
3. Drop the input files the bash scripts expect into `input/` (the
   harness copies them into a fresh `WORK_DIR` per run).
4. Write `expected.json` with the assertions.
5. Re-run `bash evals/run.sh`.
