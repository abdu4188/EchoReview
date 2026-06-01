# 04-skip-lockfile

A PR that touches only lockfiles. The reasoning pass should be a
no-op here (per DESIGN.md "Skip conditions") because there's no
hand-written code to find contradictions in.

The harness validates the bash-plumbing precondition that flips that
no-op: every changed file is classified as `lockfile`, so the skill's
Phase 3 skip-condition check fires.

Note: the universal-floor and team-patterns phases still run on
lockfile-only PRs (a docs-only PR can still leak a secret in a code
snippet), so this fixture intentionally does not assert that those
phases are skipped — only that the classifier produces the right
input for the reasoning-pass decision.
