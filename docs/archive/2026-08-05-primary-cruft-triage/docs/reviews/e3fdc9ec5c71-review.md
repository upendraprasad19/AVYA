---
reviewed_at: 2026-06-12T23:40:00+05:30
staged_against: e3fdc9ec5c71
blast_radius: catastrophic
reviewer: claude-sonnet-via-bpass-subagent
lens_set: [auth_correctness, exception_flow_correctness, blast_radius_dpdp, secrets_in_tree, regression_test_adequacy]
findings_count: 3
findings_by_severity: { P0: 0, P1: 0, P2: 1, false_alarm: 2 }
verdict: accepted
---

# Code Review (B-pass) — e3fdc9ec5c71 — delete-account auth + audit fix

## Method

Full read of `supabase/functions/delete-account/index.ts` (518 lines), both diagnose-docs, and the regression test. All regex assertions were executed via `node -e` against both the new code and a reconstructed OLD code block to confirm each test correctly flips.

---

## Lens 1 — auth_correctness

**Verdict: CLEAN**

`createClient(SUPABASE_URL, SERVICE_ROLE)` + `getUser(token)` is the correct pattern. GoTrue validates the user JWT against the project (service-role is a valid apikey) and returns the user. `userId` is derived exclusively from `userRes.user.id` (line 133) — the value returned by GoTrue after validating the token, not from any caller-controlled body field.

`userClient` is used exactly once after creation (line 125, `auth.getUser(token)`) and nowhere else. All privileged DB and storage operations use the separate `admin` client. There is no path where a forged or expired token could bypass the check: `if (userErr || !userRes?.user)` returns 401 immediately.

The `body.confirmation_token` (the only body field used) is compared against `expected = \`DELETE-MY-ACCOUNT-${userId.substring(0, 8)}\`` where `userId` comes from the validated token, not from the body. A stolen JWT without knowledge of the first 8 chars of the UUID is insufficient; and knowing those 8 chars is useless without the JWT.

**Verification command:**
```
node -e "const src=require('fs').readFileSync('supabase/functions/delete-account/index.ts','utf8'); const s=src.replace(/\/\*[\s\S]*?\*\//g,'').replace(/\/\/[^\n]*/g,''); console.log(s.match(/userClient\./g))"
```
Returns: `[ 'userClient.' ]` — exactly one use, the `auth.getUser(token)` call.

---

## Lens 2 — exception_flow_correctness

**Verdict: CLEAN (one false-alarm variant noted below)**

The audit insert `try/catch` at lines 463–496 is correct: `await admin.from(...).insert(...)` is the idiomatic supabase-js pattern for awaiting a PostgREST builder. `if (auditErr) throw auditErr` surfaces the error inside the catch, which logs and executes the ORPHAN_BILLING guard — and critically, never rethrows.

After `deleteUser(userId)` succeeds (line 440), the only potentially-throwing code before the 200 response is:
1. `console.log(...)` at line 450 — cannot throw.
2. The audit `try/catch` at lines 463–496 — cannot escape (never rethrows).
3. `console.log(...)` at line 498 — cannot throw.
4. `return new Response(...)` at line 503 — cannot throw in normal Deno operation.

So the outer catch at line 510 cannot be triggered after the irreversible delete. The 500 path is structurally unreachable once `deleteUser` succeeds. This is the precise fix intended.

**Remaining `.catch()` on a PostgREST builder:** The fire-and-forget attempt-counter insert at lines 174–190 uses `.then(({ error }) => {...})` — NOT `.catch()`. A PostgREST builder IS a thenable (has `.then`) but does NOT have `.catch`. Using `.then()` is correct and safe. However, this pattern pre-dates this diff and is unaffected by it.

**The OneSignal fetch `.catch()` at lines 315–319** is on a real `fetch()` Promise (a native Deno/browser API), which IS a full Promise with `.catch()`. This is valid and correct.

**No other `.catch()` calls on PostgREST builders were found in the diff or the file.**

**Verification command:**
```
node -e "const src=require('fs').readFileSync('supabase/functions/delete-account/index.ts','utf8'); const s=src.replace(/\/\*[\s\S]*?\*\//g,'').replace(/\/\/[^\n]*/g,''); const matches=s.match(/\.from\([^)]+\)[\s\S]{0,200}?\.catch\(/g); console.log(matches);"
```
Returns: `null` — no PostgREST builder chain ends in `.catch()`.

---

## Lens 3 — blast_radius_dpdp

**Verdict: CLEAN**

Gate ordering is correct and verified by line number: auth (`getUser`, line 125) → confirmation token (line 203) → Razorpay cancel (line 241) → OneSignal (line 291) → Storage purge (line 385) → `deleteUser` (line 440) → audit log (line 463). No destructive operation runs before both auth AND the confirmation token check.

`deleteUser(userId)` is awaited and error-checked (lines 440–448): a failure returns 500 with opaque code `auth_delete_failed` before the audit step is reached. The audit step is only reachable after a confirmed successful delete.

All `jsonError` responses contain only `{ error: <opaque_code>, request_id: <8-hex> }`. No PII (userId, email, JWT fragment, Razorpay subscription ID) appears in any response body. `userErr?.message` is logged server-side only (line 129), not returned to the caller. Razorpay subscription IDs are logged server-side but never echoed in a response body.

**Verification command:**
```
node -e "const src=require('fs').readFileSync('supabase/functions/delete-account/index.ts','utf8'); console.log(src.match(/return jsonError\([^)]+\)/g))"
```
Confirms all 8 `jsonError` calls use only opaque string codes + requestId.

---

## Lens 4 — secrets_in_tree

**Verdict: CLEAN**

All credentials are sourced via `Deno.env.get(...)` (lines 39–44). The diff's `+` lines were grepped for `sk_live`, `rzp_live_`, `AKIA[A-Z0-9]{16}`, `-----BEGIN (RSA |EC )?PRIVATE`, and Supabase JWT prefix `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9`. No credential-shaped literals were found in any staged file.

**Verification command:**
```
git diff --cached -- "supabase/functions/delete-account/index.ts" | grep "^+" | grep -iE "sk_live|rzp_live|AKIA[A-Z0-9]{16}|-----BEGIN"
```
Returns empty.

---

## Lens 5 — regression_test_adequacy

**Verdict: CLEAN (with P2 note)**

All 5 assertions in `delete_account_auth_pattern_test.dart` were executed via `node -e` against:
- **New code (comment-stripped):** all 5 PASS.
- **Reconstructed OLD broken code:** all 5 FAIL (in the correct direction — positive assertions become false, negative assertions become true).

The test correctly pins: (1) `getUser(token)` present, (2) `createClient(...SERVICE_ROLE)` present, (3) the broken `authHeader.replace` + bare `getUser()` absent, (4) `error: auditErr` destructuring present, (5) `account_deletion_log...\.catch(` absent.

Comment-stripping is applied correctly per `feedback_source_grep_strip_comments_first.md` — without stripping, the fix's own explanatory comment (which quotes the old broken pattern) would cause tests 3a/3b to false-positive on OLD code.

**P2 finding — test file path is relative, not absolute:**

`File('supabase/functions/delete-account/index.ts')` at line 27 uses a CWD-relative path. This is the established convention for all source-grep contract tests in this codebase (`test/contracts/`) and works correctly when run via `flutter test` from the project root. However, if this test were ever run from a different CWD (e.g., a subagent with a different working directory, or a future worktree), it would produce a misleading `FileSystemException: cannot open file` rather than a test failure, potentially masking the regression it is supposed to catch.

**Severity: P2** — consistent with all other source-grep contract tests in the codebase; this is a known limitation of the convention, not introduced by this diff. No action required in this batch.

**Verification command:**
```
flutter test test/contracts/delete_account_auth_pattern_test.dart
```
Expected: 4 tests, all passing.

---

## False Alarms

### FA-1 — SERVICE_ROLE client used for both userClient and admin
**Assessed:** Could the admin client's elevated privileges be reached via the `userClient` reference?
**Resolution:** `userClient` is used once for `auth.getUser(token)` only. It holds the same SERVICE_ROLE key as `admin` but is never passed to any storage, DB, or auth-admin operation. The separation is stylistic (matching the pattern in other EFs); there is no security boundary violation because both clients use the same key. A single client with `auth.getUser(token)` + admin ops would be equivalent.

### FA-2 — fire-and-forget counter insert `.then()` on PostgREST builder
**Assessed:** Could `.then()` on a PostgREST builder be the same class of bug as the d5b2f8 `.catch()` bug?
**Resolution:** PostgREST builders are thenables — they implement `.then()` (that is how `await builder` works) but NOT `.catch()`. The d5b2f8 bug was specifically that `.catch` is `undefined` on the builder object, so `undefined(fn)` threw a TypeError. `.then()` is the one method they do have. This pattern is the established fire-and-forget idiom for this codebase and is not affected by this diff.

---

## Summary

Zero P0, zero P1. The two fixes are correct, well-scoped, and confirmed by verified execution of the regression tests against both old and new code. The single P2 (relative file path in the test) is a pre-existing convention limitation shared by all source-grep contract tests, not introduced by this diff.

**verdict: accepted**
