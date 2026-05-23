# Re-review handling

How `echo-review` behaves when the PR already has prior review comments — from EchoReview itself, from human reviewers, or from any other reviewer/bot.

---

## Detection

After `fetch-comments.sh` runs, `existing-comments.json` will be a (possibly empty) array. The skill reads `review-iteration.txt`:

- `1` → first review on this PR. Standard flow.
- `2` → re-review mode. Adjust output shape as described below.

Re-review detection is **inclusive**: any prior comment (bot or human) flips the run into re-review mode. The product question being answered is "has this PR been reviewed before?", not "has *EchoReview specifically* reviewed it before."

---

## Output shape

A re-review review body **leads with a resolution table** for the prior comments, then lists new findings as inline comments below.

```
## Resolution of prior comments

| Status                | Path                | Original comment                                  |
|-----------------------|---------------------|---------------------------------------------------|
| FIXED                 | src/cache.ts:42     | Missing null guard on `user.email`                |
| PARTIALLY_FIXED       | src/billing/sub.go  | Discount applied but test still asserts old total |
| NOT_FIXED             | src/api/handler.ts  | N+1 query in user listing                         |
| WONTFIX_ACKNOWLEDGED  | src/util/format.ts  | Helper feels premature                            |

## New findings

(inline comments follow as normal)
```

The resolution table goes in the review **body**. Inline comments only cover new findings and `NOT_FIXED` / `PARTIALLY_FIXED` items (which get a fresh inline comment using the re-review wording in [`comment-template.md`](./comment-template.md)). `FIXED` and `WONTFIX_ACKNOWLEDGED` do **not** get inline comments — they exist only in the table.

---

## Status definitions

| Status | When to assign |
|---|---|
| `FIXED` | The diff shows the line referenced by the prior comment has been changed in a way that addresses the concern. |
| `PARTIALLY_FIXED` | Some of the prior concern is addressed in the new diff; some is not. Both halves should be named in the new comment. |
| `NOT_FIXED` | The line still violates the prior concern, or the prior concern's spirit applies to a moved/renamed equivalent. |
| `WONTFIX_ACKNOWLEDGED` | The author has replied in the comment thread dismissing the concern. Walk `in_reply_to_id` chains in `existing-comments.json` to find the latest reply; if the latest reply is from the PR author and reads as a dismissal (e.g., *"we're keeping this, it's intentional"*, *"won't fix"*, *"by design"*), mark this status. When uncertain, default to `NOT_FIXED` — don't assume acquiescence. |

---

## Re-review comment wording

For items that re-surface (`NOT_FIXED` and `PARTIALLY_FIXED`), use the phrasings from [`comment-template.md`](./comment-template.md):

- `NOT_FIXED` → *"Previously flagged: {original}. Still unresolved."*
- `PARTIALLY_FIXED` → *"Previous fix is incomplete. {what was fixed}, but {what remains}."*

Don't re-comment on `FIXED` items. The resolution table is enough.

---

## Walking `in_reply_to_id` chains

`existing-comments.json` is a flat array of inline comments. Threading is via `in_reply_to_id` — a reply has `in_reply_to_id` set to the id of the comment it replies to.

To check whether a prior comment was acknowledged-as-wontfix:

1. Find all comments where `in_reply_to_id` equals the candidate's `id` (or transitively chain).
2. Take the latest reply (highest `created_at` or just the last in id order — both are stable).
3. If `user.login` of that reply matches the PR author and the body reads as a clear dismissal, mark `WONTFIX_ACKNOWLEDGED`.

The PR author's login is in `metadata.json` under `.user.login`.

When in doubt, treat as `NOT_FIXED`. The cost of nudging the author once more is lower than the cost of silently dropping a real issue.
