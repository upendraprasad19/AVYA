---
branch: referral-redeem-paid-guard
plan: docs/plans/referral-pay-on-conversion.md
date: 2026-10-12
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/referral-redeem-paid-guard-bpass.md
---

# Plan review - unit S2 of the referral pay-on-conversion plan (the paid-referee guard in `redeem-referral`)

Founder decision (2026-10-12): the referrer is rewarded when the friend PAYS, the friend still gets 7 days when they apply a code, and a friend who has ever paid is not a "new recruit". Unit S2 is the Edge Function half of that rule; the database half (migration 159, the hourly reward job) is unit S1 on branch `referral-pay-on-conversion` and carries the plan, `docs/plans/referral-pay-on-conversion.md`, whose section 2.2 is this unit.

## Review rounds

S2 was designed inside the plan, so it was reviewed by the plan's rounds; each ran on the plan text and a draft, by a fresh context-blind reader that verified claims against the tree.

- **Plan rounds 1, 2 and 3** (recorded in the plan, sections 7 to 9): S2's shape came out of them - `serve()` wrapped for testability, the check AFTER the idempotency step, a read error falling through to the RPC's authoritative refusal, the RPC's `referee_has_paid_plan` mapped to the same 400, a Deno behavioural test with a fake client, the deploy through the deploy skill with a boot check. Round 2 found the unit was too large and split it (S1 / S2 / C); round 3 found nothing that needed another split.
- **B-pass** (`docs/reviews/referral-redeem-paid-guard-bpass.md`) on the real staged diff: no P0/P1, two P2 and five P3, every one verified and resolved in the batch (a read error was silently discarded; the three literals shared with migration 159 had no cross-file pin; stale line citations; two false comments; the client message for a paid friend until Unit C; the tier; a thrown read untested).

## Ground truth

- Read at base `aa4da6a4` and the working tree by the plan readers, the B-pass and the author: `supabase/functions/redeem-referral/index.ts`, `redeem_referral_atomic` (live migration 158 and the 159 draft), the writers of a paid `subscriptions` row (`razorpay-webhook`, `verify-payment`: only these two insert one; plan `monthly`/`yearly`, `razorpay_payment_id` set), the three clients of the response shape (`ReferralRepository.redeem`, `invite_friends_sheet._applyCode`, the onboarding redeem), `backups/live_schema_columns.json` for the four columns read.
- Run, not just read: the Deno file (12 behavioural tests), `deno check --node-modules-dir=none`, the Dart source pins, the full Dart suite (the only failures are the four cross-pin tests that need migration 159, red by design until S1 is on `main`), and a 19-mutant matrix on the Edge Function plus 6 on the migration side of the cross-pin (every mutant killed by the intended tests; a compile-error kill was re-done as a behavioural variant).

## Section 4.6 / registry `requires: feature_flag` - position

The code tier is account (`redeem-referral/**`); the diff reaches platform only through the one-line `supabase/functions/CLAUDE.md` edit. No runtime kill switch, on purpose: the pre-check is a refusal the RPC repeats authoritatively once migration 159 is applied, and before that the RPC is unchanged, so the guard cannot make a payment or a redemption of a new recruit fail. The "off" state is the pre-deploy bundle, which the deploy protocol backs up from the live function first.

## What this record does NOT cover

- Commit, push, PR and merge of `referral-redeem-paid-guard`: each is a separate founder go; the merge is only via `sh scripts/safe_pr_merge.sh <pr>`, and it can only happen AFTER unit S1 is on `main` (the cross-pin test is red without migration 159; merge `origin/main` into the branch first).
- A smoke of the deployed guard with a REAL paid account's token: not run, see the deploy record below (no credentials for a paid account; a real user is not impersonated). The guard's refusal is covered by the 12 Deno tests, the RPC's own refusal (migration 159, live verify R4-R6 on the real project) and the filter replay below.

## Deploy record (2026-10-13, founder approval: "Go / Commit / Push / Pr / Deploy all approved")

- **What:** `redeem-referral` on project `dedsavbjuwgarrhphgnl`, v19 to **v20**, `verify_jwt` true (unchanged), deployed from commit `797b914e` with `.claude/emit_payload.js` + `.claude/deploy_via_api.js` (HTTP 201, 9,867 bytes, one file, no `_shared` import). The payload equals `git show HEAD:supabase/functions/redeem-referral/index.ts` byte for byte; it is archived at `backups/edge_function_payloads/redeem-referral/v3_797b914.json`.
- **Before:** live v19 was read through the decoded multipart `/body` fetch: its `index.ts` equals commit `f309a843` (2026-06-13); it differs from `main` only by the type-only chore `bec0f06c`. Rollback payload rebuilt from `f309a843` BEFORE the deploy (the tool's own pre-deploy snapshot wrote 0 files, OI-334, as the deploy log again showed); to roll back, forward-deploy it with `verify_jwt` stated explicitly as `true`.
- **Boot check:** the tool's built-in smoke printed a gateway 401 (`UNAUTHORIZED_NO_AUTH_HEADER`), which proves nothing (deploy skill 6.5). With the anon key as Bearer, three POSTs returned the module's OWN sanitized 401 (`{"error":"Authentication required","request_id":"..."}`), not a 503: the module booted.
- **The guard's query against the live PostgREST:** the exact URL built by supabase-js 2.39.3 for the guard's chain (`plan=in.(monthly,yearly)&razorpay_payment_id=not.is.null&limit=1`, captured with a fake fetch) returned HTTP 200 `[]` for the anon key (RLS hides the rows); a deliberately malformed control (`plan=in.monthly,yearly`) returned HTTP 400 PGRST100, so the 200 is meaningful. A live read with the same predicate: 10 rows match (5 distinct users, 4 of the rows not `active`), which is why the predicate has no status filter.
- **Not done, stated plainly:** an authenticated call as a known paid account expecting the 400 (the deploy skill's real-token backstop). No credentials for a paid account exist in the tree or the environment, and impersonating a real user through the service role was not done. Until someone with such an account runs it (or gives a dedicated paid test account), the end-to-end 400 for a real paid friend is covered by composition, not observed.
- **Still to do:** the S2 pull request (#115) merges only after S1 (#114) is on `main`, via `sh scripts/safe_pr_merge.sh`; its cross-pin test is red until then. Shipped app builds show their generic message for the 400 until unit C moves the invite sheet onto `ReferralRepository.redeem`.
- Unit C (the client): until it ships, `invite_friends_sheet._applyCode` shows its generic message for a paid friend's 400.
