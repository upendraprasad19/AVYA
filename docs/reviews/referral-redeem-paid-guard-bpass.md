---
reviewed_at: 2026-10-12
staged_against: referral-redeem-paid-guard (staged diff b376c3cef617 at dispatch; the fixes below were made afterwards)
blast_radius: platform (code tier account; lifted to platform by the one-line supabase/functions/CLAUDE.md edit, see Finding 6)
reviewer: claude-sonnet-b-pass (fresh, context-blind, read-only)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 7
verdict: accepted
---

# Code Review (B-pass) - unit S2, the paid-referee guard in `redeem-referral`

A fresh reader with no access to the author's reasoning read the staged diff (Edge Function, its new Deno test, three source pins, one registry entry, one CLAUDE.md line) plus the RPC it talks to (migration 159 in a sibling worktree). **No P0 or P1.** Predicate parity with the RPC, the order of the steps, the response shapes the three clients read, the column names (4 of 4 in `backups/live_schema_columns.json`), the `import.meta.main` precedent (7 deployed functions) and the absence of secrets and floating promises were all re-derived and held. Seven findings; every one was verified against the tree by the author and is resolved in this batch.

## Finding 1 - P2 - function_exception_swallow - RESOLVED

The paid read dropped its `error`; a failing read (schema drift, a PostgREST 4xx) would turn the guard into dead code with no trace, and the comment called the RPC refusal "the authoritative check" although that is true only once migration 159 is applied (before it, the RPC refuses nobody). Verified: `grep paidErr supabase/functions/redeem-referral/index.ts` returned nothing; `verify-payment` logs the same situation.

Fix: `const { data: paidRows, error: paidErr }`; a read error is `console.warn`-ed (server log only, rule 17 untouched) and still falls through to the RPC; the comment now says "once migration 159 is applied" and states the pre-apply behaviour. Tests: the Deno test "a READ ERROR on subscriptions is LOGGED and falls through" asserts exactly one warning containing the read's message; "a successful paid read logs nothing"; RR-src-7 now pins the error binding and that nothing between the warn and the refusal `return`s. Plan section 2.2 adds a known-paid account to the deploy smoke (the PostgREST filter encoding is otherwise exercised by no test; `.not(col, "is", null)` has production precedent in `daily-snapshot` and `plateau-alert`). Mutation (S2 matrix E14-E19, all killed): drop the binding, keep it and drop the warn, fail-closed on a read error, warn on every read (with a non-compile-error variant), a third plan name, a different mapped text, a status filter.

## Finding 2 - P2 - writer_reader_drift - RESOLVED

Three literals (the plan list, the payment-id clause with no status filter, the exception text) are shared with migration 159 and no test tied them: the EF-side pins compared only against the EF's own literals.

Fix: `test/contracts/redeem_referral_paid_referee_migration_pin_test.dart` reads migration 159 and the Edge Function and asserts: the RPC refusal is `plan IN (monthly, yearly)` + `razorpay_payment_id IS NOT NULL` with no `status`, raising `referee_has_paid_plan` / `P0001`; `PAID_PLANS` equals the RPC list (extracted, not hard-coded); the EF read carries `.in("plan", PAID_PLANS)` and `.not("razorpay_payment_id", "is", null)` and no status filter; the EF maps exactly the text the RPC raises; the reward job's reconcile uses the same plan list. It is **red on a branch without migration 159 on purpose**: merge order S1 then S2 becomes a CI fact (`safe_pr_merge.sh` refuses a red head). Mutation (G1-G6 on the migration side, E17-E19 on the EF side): all killed, each by the intended test.

## Finding 3 - P3 - documentation-rot - RESOLVED

The diff shifted `index.ts` by +10 lines before step 5 and +29 after step 5b; several citations were not updated. Fix: the live citations are now symbols ("the 401 branch", "the 23505 race branch") in `test/edge_functions/redeem_referral_test.dart`, `referral_repository.dart` and `.claude/skills/debugging/bug-classes.md`; the registry range `100-170` of `referral_redemption` covers the RPC call (`137-142`); the S1 registry reader range for the idempotency read is widened to `100-120` (it covers 104-106 before and 113-117 after this unit). Historical plans and ledgers keep their point-in-time line numbers on purpose.

## Finding 4 - P3 - documentation-rot - RESOLVED

`index.ts:2` still said "grants 7-day PRO to both parties"; the `PAID_PLANS` comment attributed "any status" to the reward job too (the job also requires `status = 'active'`, not cancelled, inside the window). Both corrected; the status-filter absence is now pinned against the RPC (Finding 2).

## Finding 5 - P3 - writer_reader_drift (client) - RESOLVED (recorded, accepted knowingly)

`invite_friends_sheet._applyCode` calls `callFunction` directly, so a paid friend's 400 lands in its `catch` as the generic "Could not apply code. Please try again." until Unit C moves it onto `ReferralRepository.redeem`. Plan sections 2.2 and 2.3 now say so ("after Unit C"); S2 may be deployed ahead of Unit C knowingly; the cost is that one message for a paid friend inside their first 7 days.

## Finding 6 - P3 - blast_radius_mismatch - RESOLVED (position recorded)

`redeem-referral/**` is account tier; the diff reaches platform only through the one-line `supabase/functions/CLAUDE.md` edit (falls to `supabase/functions/**`). Position, recorded in the plan-review record: the tier is lifted by a docs line, the code is account; the platform `requires: feature_flag` is answered there (no flag: the guard is a refusal that the RPC repeats authoritatively; the off state is the pre-deploy bundle, which the deploy protocol (`.claude/skills/edge-function-deploy-rollback`) backs up from the live function before the deploy). The line stays with the test it describes.

## Finding 7 - P3 - asserted_fixture_value - RESOLVED

The fake applies no filter (the cancelled paid row, the referral_trial row with a payment id and the NULL-payment-id row are covered by the exact ops array and by the RPC-side cases in migration 159's live verify R5/R11/P1-P5), and a THROWN read was untested. Fix: a Deno test where the subscriptions read rejects: `handleRedeemReferral` propagates it (the outer `handler`'s `return await ... catch` turns it into the generic 500) and the RPC never runs; the filter encoding is covered by the known-paid-account deploy smoke (Finding 1).

## Checked and clean (reviewer's list, abridged)

Secrets (regex over the diff); floating promises (every `redeem(`/`handleRedeemReferral(` awaited; `serve(...)` was already un-awaited); column existence; plan values and writers (only `razorpay-webhook` and `verify-payment` insert paid rows); predicate parity with the RPC; the error string once in migration 159; step order; the client response contracts (`success`, `alreadyRedeemed`, `error`, `request_id`); RR-src-7/8/9 hand-squashed; the registry range; Deno test values recomputed from the code.

## Not verified by the reviewer

Nothing was run by the reviewer. The author ran: the Deno file (12 tests), the Dart pins, `deno check`, the full Dart suite (the only failures are the four cross-pin tests that need migration 159, by design) and the mutation matrix named above.
