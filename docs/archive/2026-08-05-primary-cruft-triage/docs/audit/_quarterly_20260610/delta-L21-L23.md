# Delta audit — L21 (EF semantic correctness) + L23 (auth defense-in-depth)

Scope: `git diff --name-only 969c117..HEAD` ∪ `git show a767725`, restricted to
supabase/functions/ + EF callers. Delta EF **code** actually changed:
`_shared/rank_engine.ts`, `_shared/tools/plan/regeneratePlanBlock.ts` (+ tests).
delete-account / verify-payment / razorpay-webhook **source is unchanged in the
delta** — only their backup payload JSONs, migration 088, and diagnose-docs
moved. I still ran L23 over all five per the brief.

---

## L21 — Edge Function semantic correctness — CLEAN (delta code)

`rank_engine.ts` `highestQualified` walks the ladder sequentially and `break`s on
the first failed gate (line 99-110); `qualifies` `await`s the completion-rate
provider correctly (85-89); `completionRateOverWindow` no longer selects the
absent `reason` column (d7c3f1 fix verified, line 144-152). The cron caller
`evaluate-rank-promotions` is strictly monotonic — `if (winner.ordinal >
currentOrdinal)` guards the denorm write (line 245), no demote path.
`regeneratePlanBlock.ts` schema enum includes `recompose` (line 13). No TDZ,
missing-await, or swallowed-exception in the changed code.

## L23 — Authorization defense-in-depth — CLEAN (delta code + all 5 named EFs)

- **regeneratePlanBlock** (a4f7e1): dispatcher `_executeRegeneratePlanBlock`
  rejects any goal `!FitnessGoals.isKnown` BEFORE applying (tool_dispatcher.dart
  :676); `recompose` IS known (fitness_goals.dart:105-113). Schema enum ⊇ tokens.
  isKnown guard covers recompose — **REAL / correctly fixed**.
- **rank_engine / evaluate-rank-promotions**: `isAuthorizedCronCall` gate
  (index.ts:55) precedes every service-role read; not anon-reachable.
- **delete-account** (b4e2a9 context): server-side `auth.getUser()` (index.ts
  :115) derives userId from the JWT, not the body; confirmation-token gate
  (192); every admin op `.eq("user_id", userId)`. verify_jwt=true. CLEAN.
- **verify-payment**: `auth.getUser(token)` (201); entitlement derived from the
  Razorpay amount, not body.plan; two-step notes.user_id present-AND-match
  ownership check (397-420, no fail-open, OI-29). CLEAN.
- **razorpay-webhook**: HMAC verified before any DB work (253); `supabaseClient`
  declared before first use (OI-26 TDZ closed, 339); notes.user_id UUID-validated
  (467). CLEAN.

The migrations 090/091 anon-exec hole is excluded per brief (already fixed).

---

## Findings

### F1 — delete-account Razorpay-cancel still fatal can block DPDP erasure
- lens: L21
- severity: P3 (known, documented follow-up — out of delta-code scope)
- file:line: supabase/functions/delete-account/index.ts:215-221, 246, 258
- verbatim: `return jsonError(502, "razorpay_cancel_failed", requestId);` (on
  subscription-lookup error AND on Razorpay cancel non-ok/throw)
- claim: A Razorpay API hiccup (or a future query error) aborts the entire
  erasure with 502 before `auth.users` is deleted — a legally-required DPDP §17
  right can be indefinitely blocked by an external dependency. The b4e2a9
  diagnose itself recommends making this step non-fatal once recurring billing
  launches. NOT introduced by this delta (source unchanged); surfaced while
  reading the b4e2a9-adjacent code.
- verification cmd: `git log -1 --format=%H -- supabase/functions/delete-account/index.ts`
  (confirms unchanged in delta) + read lines 215-260.
- REAL (pre-existing, out of delta-code scope — already logged as a follow-up in
  diagnose b4e2a9 frontmatter `impact_analysis`). No new action required this batch.

### F2 — razorpay-webhook HMAC uses RAZORPAY_KEY_SECRET, not RAZORPAY_WEBHOOK_SECRET
- lens: L23
- severity: P3 (pre-existing, out of delta-code scope; behavior may be intentional)
- file:line: supabase/functions/razorpay-webhook/index.ts:253 (vs header :20)
- verbatim: `const isValid = await verifySignature(rawBody, signature, RAZORPAY_KEY_SECRET);`
  while the header docstring states `RAZORPAY_WEBHOOK_SECRET (HMAC verification
  of inbound signature)` and "the webhook secret (NOT the Razorpay key secret;
  separate value)".
- claim: Code signs with the API key secret; the docstring says it should use a
  separate webhook secret. If the Razorpay dashboard webhook secret was set equal
  to the key secret this is functionally fine but contractually drifted; if not,
  signatures would never validate and PRO would never unlock via webhook — but
  live `account_deletion_log`/subscription data and the OI-26 history imply the
  webhook path works, so the secrets are almost certainly configured equal.
  `RAZORPAY_WEBHOOK_SECRET` is referenced ONLY in the comment, never in code.
- verification cmd: `rg -n "RAZORPAY_WEBHOOK_SECRET" supabase/functions/` (only
  the comment hit) + check the Razorpay dashboard webhook secret == key secret.
- REAL-doc-drift / likely-FALSE_ALARM-functionally. Pre-existing, source
  unchanged in this delta. Recommend reconciling the docstring with reality (or
  switching to a true separate webhook secret) in a payment-hardening batch — not
  this delta.

---

Net: delta-touched EF code (rank_engine, regeneratePlanBlock) is CLEAN on both
lenses; the recompose enum/guard fix is correctly complete. Two pre-existing P3
observations on payment EFs whose source was NOT modified in this delta, both
already known/benign. No P0/P1/P2 in scope. No fixes applied.
