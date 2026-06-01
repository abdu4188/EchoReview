# 02-patterns-tst

A small PR adds a test file with a conditional `if`-wrapped assertion
— the anti-pattern a hypothetical team's `.echoreview/patterns.md`
flags as "no conditional logic in tests."

The harness validates the bash-plumbing preconditions for the
patterns-driven layer:

- The test file is classified as `test` (so the skill scopes
  team rules whose `applies_to: **/*.test.ts` will match).
- The diff-position map contains the offending line.
- The fixture's synthetic `patterns.md` parses to a schema-valid rule
  with at least one verbatim evidence quote (the voice signal the
  review skill mirrors when posting an inline comment).

Voice matching itself runs in Claude — see `evals/README.md` for the
manual end-to-end check.
