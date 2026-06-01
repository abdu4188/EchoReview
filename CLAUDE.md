# CLAUDE.md — EchoReview

This file is loaded automatically into every Claude Code session in this repo. It encodes the operational rules and conventions Claude should honor each turn.

---

## Project

**EchoReview** is a Claude Code plugin that learns a team's PR review patterns from git history and applies them — alongside a universal best-practices floor — when Claude reviews new PRs. Output is always a PENDING GitHub review the human owns.

---

## Non-negotiable constraints

- Runs inside the user's Claude Code session. No standalone CLI, no SaaS, no API key prompts.
- No Anthropic API key — inference uses the user's Claude Code subscription.
- No GitHub App. All GitHub interaction shells out to `gh` CLI.
- No backend, no telemetry, no analytics.
- No external embedding API. Clustering uses Claude reasoning.
- No starter rule files. Universal best practices are inlined into the review skill; team patterns come exclusively from extraction.
- **PENDING reviews only.** The submit step is non-blocking; the user clicks Submit on GitHub.

If a request would violate any of the above, stop and ask.

---

## Git workflow

### Branching — GitHub Flow

- `main` is always releasable.
- Work happens on short-lived branches off `main`:
  - `feat/<slug>` — new feature
  - `fix/<slug>` — bug fix
  - `docs/<slug>` — documentation only
  - `refactor/<slug>` — internal change, no behavior diff
  - `test/<slug>` — tests or eval fixtures
  - `chore/<slug>` — tooling, deps, repo plumbing
  - `perf/<slug>`, `ci/<slug>`, `build/<slug>` as needed
- One PR per branch. Squash-merge into `main`. Delete the branch after merge.
- Never force-push to `main`. Force-push on feature branches is fine after a rebase, but confirm with the user before doing it.

### Commit messages — Conventional Commits

Format: `<type>(<optional scope>): <subject>`

- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `build`, `ci`, `perf`, `revert`.
- Scope (optional) names the affected area, e.g. `extract`, `review`, `evals`, `marketplace`.
- Subject: imperative mood ("add", not "added"/"adds"), ≤72 chars, no trailing period.
- Body (optional): wrap at 72 chars; explain the **why**, not the what.
- Breaking changes: append `!` after type/scope (`feat(review)!: …`) and include a `BREAKING CHANGE:` footer.
- Reference issues in the footer: `Closes #N`, `Refs #N`.

Examples:

```
feat(extract): cluster comments via reasoning
fix(review): handle empty diff map
docs: clarify reasoning-pass threshold
chore: bump version to 0.2.0
```

### Versioning — SemVer 2.0.0

- `plugins/echoreview/.claude-plugin/plugin.json` `version` field is the source of truth.
- Bump on every release. Self-hosted marketplaces only refresh when the version string changes.
- Tag releases as `vMAJOR.MINOR.PATCH`.

---

## Pull requests

- Title follows Conventional Commits (will become the squash-merge commit message).
- Body includes: **Summary**, **Motivation**, **Test plan**. Add screenshots or recordings for any user-facing change.
- Link related issues with `Closes #N` in the body.
- Keep PRs focused: one logical change per PR.

---

## Code conventions

- **Shell scripts:** `#!/usr/bin/env bash`, `set -euo pipefail`, `shellcheck`-clean. Quote variables. Use `mktemp` for temp paths under `/tmp/echoreview-*/`.
- **Repo layout:** match the existing structure exactly. Don't invent new top-level directories without discussion.
- **Skills:** every `SKILL.md` has valid frontmatter — `name` and `description`. Skills are user-invocable by default; set `user-invocable: false` (note the hyphen) only to hide a skill from the `/` menu.
- **References:** files under `skills/*/references/` are pure markdown — no executable side effects, no scripts.
- **JSON:** `plugin.json`, `marketplace.json`, and eval fixtures must be valid JSON — no trailing commas, no comments.
- **Comments:** default to none. Add one only when the *why* is non-obvious (per global rules).

---

## Open-source hygiene

- **License:** MIT, `LICENSE` at repo root. No per-file copyright headers required.
- **`.gitignore`** covers at minimum: `.echoreview/` (if test repos are nested locally), `node_modules/`, `.DS_Store`, editor cruft (`.idea/`, `.vscode/` unless intentionally shared), `*.log`. The plugin writes intermediates to `/tmp/`, so they're already outside the repo.
- **No secrets ever.** No API keys, tokens, OAuth secrets, or `.env` files committed. If something secret-looking shows up in a diff, flag it and refuse to include it.
- **Privacy posture:** contributor-facing docs (README, CONTRIBUTING) must not overclaim — no "SOC 2", "audited", or similar guarantees unless actually done. The README sets the baseline wording; mirror it in any new contributor docs.

---

## Testing & evals

- `evals/fixtures/` holds anonymized `*.patch` + `*.expected.json` for the eval harness.
- Every new fixture comes with a one-line entry in `evals/README.md` describing what it covers.
- Never commit fixtures with identifiable PII or proprietary code from any real org. Anonymize handles, repo names, and inline strings.

---

## Working directory hygiene

- Intermediate artifacts live in `/tmp/echoreview-{pr-number}/` (review runs) and `/tmp/echoreview-extract/` (extract runs). Never inside the repo.
- Cleanup is the user's call — don't auto-delete.

---

## Precedence

User instruction in current session > `CLAUDE.md` > global defaults. When these conflict or a case feels ambiguous, ask before acting.
