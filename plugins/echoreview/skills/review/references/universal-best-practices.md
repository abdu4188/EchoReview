# Universal best-practices floor

This reference is loaded by `echo-review` on every run, regardless of whether the target repo has an `.echoreview/patterns.md`. The checks here are deliberately **stack- and language-agnostic** — anything framework-specific belongs in a mined team `patterns.md`, not here.

The bullets under each category name **common shapes**, not an exhaustive checklist. The categories themselves are the floor; the bullets are illustrations. If you find an issue that clearly fits a category — security, correctness, accessibility, performance footgun, common bug pattern — surface it even when it doesn't match any bullet verbatim. A new SSRF sink, an accessibility regression in a custom component, an N+1 hiding behind an ORM helper, a race in a less-obvious place: all in scope. Treat the lists as anchors for the *kind* of issue that belongs here, not the closed set of issues to look for.

When you flag an issue from this floor, attach a `severity` per the rubric in the **Severity** section below. Use the comment voice rules in [`comment-template.md`](./comment-template.md).

---

## Categories

### Security — severity: warning minimum (blocker for clear vulns)

Look for:
- **Hardcoded secrets**: API keys, tokens, passwords, private keys, JWT secrets, or session secrets committed into source. A plausible secret in a test fixture is still a finding.
- **Injection sinks**: SQL/NoSQL queries built by string-concatenating user input; shell commands with unescaped arguments (`exec`, `system`, `subprocess.run(..., shell=True)`); template rendering with `eval`-equivalents.
- **XSS sinks**: writing untrusted strings into `innerHTML`, `dangerouslySetInnerHTML`, `document.write`, or unescaped server-rendered HTML.
- **Missing authorization checks**: route handlers that read or mutate per-user resources without verifying the caller owns the resource.
- **Unsafe deserialization**: `pickle.loads`, `yaml.load` (instead of `safe_load`), `unserialize` on attacker-controlled input.
- **Insecure crypto choices**: MD5/SHA-1 for passwords or signatures, `Math.random()` for tokens, hand-rolled encryption, missing IVs, ECB mode.
- **Disabled TLS verification**: `verify=False`, `rejectUnauthorized: false`, `InsecureSkipVerify: true` in production paths.

### Correctness — severity: warning, blocker if data loss or crash

Look for:
- **Unhandled async rejection / dropped errors**: `await` missing on a Promise; `.catch` absent on a fire-and-forget; Go `_` discarding an error; `try/except: pass` without justification.
- **Missing null/undefined guards**: dereferencing values that the type signature or surrounding code shows can be absent.
- **Off-by-one**: loop bounds, slice/substring indices, array-end conditions.
- **Type assertions hiding bugs**: `as Foo`, `!`, `cast`, `unwrap()` on values whose narrowing wasn't actually established.
- **Dead code after `throw`/`return`**: usually a sign of a refactor gone wrong; the dead branch may have been the intended path.
- **Mismatched units**: seconds vs milliseconds, bytes vs KB, dollars vs cents.

### Accessibility — severity: warning

Look for:
- **Missing alt text** on `<img>`, `Image`, icon components used for non-decorative purposes.
- **Semantic HTML misuse**: `<div onClick>` instead of `<button>`; headings out of order; lists made of `<div>`s.
- **ARIA mis-application**: `role` overrides on elements that already have the correct semantics; `aria-label` on elements with visible text; required ARIA attributes missing for the chosen role.
- **Keyboard navigation breaks**: focus traps, focus loss on dialog open/close, custom controls without `tabindex` or key handlers.
- **Color-only state indication**: red/green error states, sort indicators, validation feedback without an accompanying icon or text.

### Performance footguns — severity: warning (suggestion for non-hot paths)

Look for:
- **N+1 queries**: looping over results and issuing one query per row. Particularly damning in route handlers, GraphQL resolvers, and serializers.
- **Blocking I/O in hot paths**: synchronous file/network reads in request handlers, render functions, or animation loops.
- **Unbounded loops over user input**: iterating arrays whose size is attacker-controlled with no cap.
- **Large synchronous bundles on the client**: importing entire libraries when a function would do; missing dynamic imports for heavy modules in client bundles.
- **Repeated work**: recomputing inside a loop what could be computed once; not memoizing pure functions on hot paths.

### Common bug patterns — severity: warning

Look for:
- **Race conditions in async code**: shared state mutated by interleaved promises; checks separated from their use by an `await`.
- **Mutating shared state**: in-place mutation of props, defaults, module-level objects, or cached values.
- **Missing cleanup in long-lived processes**: unsubscribed event listeners, leaked timers/intervals, unclosed file handles or DB connections.
- **Swallowed exceptions**: `catch` blocks that log and continue without re-throwing or returning a meaningful error.
- **Boolean coercion traps**: `if (count)` when `0` is a valid value; `if (value)` when `""` is meaningful.

---

## Severity

Per finding from the universal floor:

| Severity | When to use |
|---|---|
| `blocker` | Clear vulnerability, data loss, crash, or regression of existing behavior. The PR shouldn't merge as-is. |
| `warning` | Likely bug or accessibility violation that the author should address before merge. |
| `suggestion` | Stylistic or non-hot-path performance nudge — author can ignore with no real risk. |
| `note` | Information-only; almost never used from the universal floor (reserved for pattern reviews). |

The reasoning pass (see [`reasoning-pass.md`](./reasoning-pass.md)) is restricted to `blocker` and `warning` only.

---

## What this floor deliberately is not

- **Not framework-specific.** No React-specific, Django-specific, Rails-specific, Express-specific checks. Those live in `.echoreview/patterns.md` (mined from the team's own PR history) or, in a future version, optional reference files loaded on demand.
- **Not a linter substitute.** Don't surface findings that a typical project's linter or formatter would catch (semicolons, unused variables, indentation, `==` vs `===`). The team's CI already handles that.
- **Not a style guide.** Style preferences belong in a team-mined `patterns.md`, not here.
- **Not a closed checklist.** If a finding fits a category above but isn't named in its bullets, that's still a valid floor finding. Conversely, if a bullet would technically apply but the issue is trivial in context, you can skip it — the categories are the obligation, the bullets are illustration.
