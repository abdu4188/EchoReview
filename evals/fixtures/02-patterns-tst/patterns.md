# EchoReview patterns

Source: synthetic (eval fixture)
Generated: 2026-06-01
Requested:    --since 3mo, --min-freq 3, --limit 500, --coverage balanced
Window mined: 2026-03-02 → 2026-05-30 (~12 weeks)
Mined:        8 PRs, 14 comments, 1 rule

---

### [ECHO-TST-001] No conditional logic in tests. (freq: 4)

severity: warning
applies_to: **/*.test.ts

```ts
// DO
expect(first).toBe(1)

// DON'T
if (first) {
  expect(first).toBe(1)
}
```

> *"we shouldn't have conditions in tests. if the value ever became null, the assertion silently doesn't run."* — @alice, PR #42
> *"just the if part. drop the conditional."* — @bob, PR #57

---
