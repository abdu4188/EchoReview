# 01-universal-security

A small PR adds a TypeScript file with a hardcoded API key — the kind
of finding the universal-best-practices floor catches even without a
team patterns file.

The harness validates the bash-plumbing preconditions for that finding:

- The file is classified as `js-ts` (so the skill knows it's source
  code, not config or docs).
- The line containing the secret is in the diff-position map (so the
  skill can post an inline comment on it).
- The fixture is in first-review mode (no prior comments).

The actual security-finding text and its severity (`blocker`/`warning`)
are produced by Claude in Phase 2 of the review skill and are not
asserted here — see `evals/README.md` for the manual end-to-end check.

The hardcoded-key string in `input/diff.patch` is a clearly-fake
placeholder (`REPLACE-BEFORE-COMMIT-fixture-placeholder`) rather than a
realistic-shape secret on purpose: GitHub's push protection blocks any
real-shape secret (e.g. `sk_live_...`) even inside a test fixture in a
diff file. The fixture is testing the bash-plumbing layer, which only
needs *a* code line at the expected position — it doesn't read or
validate the string itself.
