# Reasoning-pass calibrated examples

These four worked examples are **calibration anchors** for the confidence values used by [`reasoning-pass.md`](./reasoning-pass.md). Their only job is to make "95" and "85" feel concrete — a stable reference for how strong the evidence must be at each level, instead of a number you reinvent every run.

What matters in each example is the **shape and strength of the evidence**, not the specific bug. The languages, domains, library names, and surface details are arbitrary stand-ins. A finding that looks nothing like any of these four — a Rust ownership inconsistency, a SQL migration that breaks an invariant, a shell script that drops a return code — is still valid if its evidence is as strong as the example at its claimed level.

If a candidate finding's evidence is **weaker** than any of the four examples at its claimed level, drop it. Calibrate on evidence strength, not on surface similarity.

---

## What these examples are NOT

- **Not a list of bug types to look for.** The reasoning pass surfaces any contradiction, unjustified-code shape, or missing-error-handling shape it finds — not only ones that resemble caches, billing math, audit trails, or Stripe handlers.
- **Not codebase-specific.** The TypeScript cache, the Go invoice, the TypeScript handler, and the Python Stripe call are illustrative. The same shapes occur in Rust, SQL migrations, shell scripts, React components, and every other context this skill runs in.
- **Not exhaustive of the shapes.** Other concrete contradictions and gaps can clear the ≥80 bar — these four are simply common, well-shaped examples. If you find a different shape with evidence as strong as Example 1 or 2, surface it.

---

## Example 1 — Contradiction, confidence 95

**Shape:** contradiction

**Diff (excerpt):**

```diff
@@ src/cache.ts
 export class Cache {
   private store = new Map<string, Entry>();
+
+  async get(key: string): Promise<Entry | null> {
+    return this.store.get(key) ?? null;
+  }
 }
```

**Elsewhere in the file (unchanged):**

```ts
private store = new Map<string, Entry>();
private async refresh(key: string): Promise<Entry> {
  const fresh = await this.loader(key);
  this.store.set(key, fresh);
  return fresh;
}
```

**Finding:** the new `get` returns `null` on a miss; every other call site in the codebase invokes `refresh` on miss, and the type contract elsewhere assumes `Entry`, not `Entry | null`. The new method silently changes the cache's miss semantics for any caller that uses it.

**Why 95:** the contradiction is structural — the diff introduces a new public path that bypasses the existing miss handling. The evidence is in the file itself. No interpretation needed.

*This is what 95 looks like: structural evidence sitting inside the diff itself, no interpretation required, the contradiction mechanical and visible.*

**Posted comment:** *"`get()` returns null on miss; the rest of this cache uses `refresh()` to populate on miss. Either route through `refresh()` or document that callers must handle the null case."*

---

## Example 2 — Contradiction, confidence 95

**Shape:** contradiction

**Diff (excerpt):**

```diff
@@ src/billing/invoice.go
 func (i *Invoice) Total() Money {
-    return i.Subtotal.Add(i.Tax)
+    return i.Subtotal.Add(i.Tax).Sub(i.Discount)
 }
```

**Elsewhere in the same PR:**

```diff
@@ src/billing/invoice_test.go
 func TestInvoiceTotal(t *testing.T) {
     inv := &Invoice{Subtotal: USD(100), Tax: USD(10)}
-    require.Equal(t, USD(110), inv.Total())
+    require.Equal(t, USD(110), inv.Total())
 }
```

**Finding:** `Total()` now subtracts `Discount`, but the test fixture has no `Discount` field set and the assertion still expects `110`. If `Discount` defaults to zero this passes, but every existing caller in the codebase that doesn't pass `Discount` now silently has its total reduced — and the test doesn't exercise the new path at all. The test wasn't updated to match the new behavior.

**Why 95:** the diff explicitly changes the formula and leaves the test asserting the old formula's intermediate. The test gap is a structural fact, not interpretation.

*This is what 95 looks like: structural evidence sitting inside the diff itself, no interpretation required, the contradiction mechanical and visible.*

**Posted comment:** *"`Total()` now subtracts `Discount`, but `TestInvoiceTotal` still asserts the pre-discount total with no `Discount` field on the fixture. Add a discount case to the test or this change is uncovered."*

---

## Example 3 — Unjustified code, confidence 85

**Shape:** unjustified-code

**Diff (excerpt):**

```diff
@@ src/server/handlers.ts
 export async function userHandler(req: Request, res: Response) {
   const user = await getUser(req.params.id);
+  const audit = buildAuditTrail(user, req);
   res.json(user);
 }

+function buildAuditTrail(user: User, req: Request): AuditEntry {
+  return {
+    user_id: user.id,
+    ip: req.ip,
+    timestamp: Date.now(),
+    action: 'read',
+  };
+}
```

**Finding:** `buildAuditTrail` is called and assigned to `audit`, but `audit` is never read, never logged, never persisted, never returned. The variable is constructed and dropped. Either a `logger.audit(audit)` call was meant to be added and got dropped from the diff, or this is leftover scaffolding.

**Why 85:** the gap is concrete (the value is computed and immediately discarded), the surrounding context suggests a clear intent (audit logging), and the missing call is the obvious resolution. Some interpretation is needed — maybe the author intended to come back to it — but the diff in its current state is broken-looking.

*This is what 85 looks like: concrete, visible evidence that requires connecting two facts (or seeing the convention the surrounding code sets), with small room for the author having a deliberate reason.*

**Posted comment:** *"`audit` is built but never read or persisted. Was a logger call dropped, or should this construction be removed?"*

---

## Example 4 — Missing error handling, confidence 85

**Shape:** missing-error-handling

**Diff (excerpt):**

```diff
@@ src/integrations/stripe.py
 def fetch_subscription(customer_id: str) -> Subscription:
     try:
         return stripe.Subscription.retrieve(customer_id)
     except stripe.error.InvalidRequestError:
         logger.warning("invalid customer", customer_id=customer_id)
         raise SubscriptionNotFound(customer_id)
+
+def cancel_subscription(customer_id: str) -> None:
+    sub = stripe.Subscription.retrieve(customer_id)
+    sub.delete()
```

**Finding:** every existing call to `stripe.Subscription.retrieve` in this module wraps it in a `try/except stripe.error.InvalidRequestError` and raises a domain error. The new `cancel_subscription` skips the handler entirely; an invalid customer ID would surface as a raw `stripe.error.InvalidRequestError` to the caller, breaking the module's error-translation contract.

**Why 85:** the gap is concrete (one new call site, no handler) and the surrounding code establishes a clear convention. Confidence drops below 95 because there's a small chance the author deliberately wants the raw error to propagate — but the inconsistency alone is worth surfacing.

*This is what 85 looks like: concrete, visible evidence that requires connecting two facts (or seeing the convention the surrounding code sets), with small room for the author having a deliberate reason.*

**Posted comment:** *"`cancel_subscription` calls `stripe.Subscription.retrieve` without the `InvalidRequestError` handler the rest of this module uses. Either raise `SubscriptionNotFound` here too or document why this call site is different."*

---

If you find yourself dropping a candidate finding because "it doesn't look like Example 1–4," that's the wrong reason to drop it. Drop on evidence strength, not surface similarity.
