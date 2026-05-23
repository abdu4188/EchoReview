# Comment template

## What this file is

Comment style comes almost entirely from the team's verbatim evidence quotes in `.echoreview/patterns.md`. Treat those quotes as the voice guide for any comment that applies their rule. This file exists only to set the three guardrails that hold regardless of team voice, and to give fallback guidance when no evidence quotes are available.

## The three guardrails

- **No impersonation of named individuals.** EchoReview never poses as a specific reviewer, even if the team's evidence quotes name people.
- **No harassment of the PR author.** A bot doing this at scale is materially different from a human doing it once. Strip personal attacks; keep the technical point.
- **No pattern IDs in the comment body.** These are system metadata, not reader signal.

## When there are no evidence quotes

The universal-floor and reasoning-pass findings have no rule and therefore no quotes to mirror. Keep the comment direct and concrete. If `.echoreview/patterns.md` exists with several rules, sample its overall register and let these comments drift toward it so the whole review reads as one voice.

---

Re-review bookkeeping uses fixed wording — these are EchoReview's own status lines, not comments on the team's behalf:

- `NOT_FIXED` → *"Previously flagged: {original}. Still unresolved."*
- `PARTIALLY_FIXED` → *"Previous fix is incomplete. {what was fixed}, but {what remains}."*

`FIXED` and `WONTFIX_ACKNOWLEDGED` items get a row in the resolution table, not a comment.
