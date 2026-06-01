# 03-re-review

The PR has three prior inline review comments — one of them is the
author's reply (`in_reply_to_id` populated) dismissing an earlier
concern. The harness validates that `fetch-comments.sh` correctly:

- Sets `review-iteration.txt` to `2` (re-review mode triggered by any
  prior comment).
- Generates `previous-comments.md` with the expected count in the
  heading, the reviewer handles preserved, and the `in_reply_to_id`
  records intact so the skill can walk the reply chain to detect
  `WONTFIX_ACKNOWLEDGED`.

This fixture has no `diff.patch` and no `files.txt` because the
re-review detection layer is independent of the diff-extraction layer.
