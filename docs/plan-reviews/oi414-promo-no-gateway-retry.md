---
branch: oi414-promo-no-gateway-retry
date: 2026-10-25
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/eb8fea69c002-review.md
---

# Plan-review record - OI-414: a metered call is not re-sent after a gateway 502/503/504 (payment class, platform)

Keystone record for the section 4.12 merge gate (`check_plan_review_record_exists.dart`). Plan: `docs/plans/2026-10-25-oi414-promo-no-gateway-retry.md` (version 3). Fix tier L (payment; a recurrence of c7e3b1 H1, so the diagnose-doc `a6d2f9` takes the full template). Lenses (section 4.8): L1 writer/reader drift, L21 Edge Function semantic correctness, L29 endpoint rate-limit matrix, L36 idempotency replay completeness.

**Tier `platform`, COMPUTED:** `dart run scripts/blast_radius_from_diff.dart <the staged paths>` printed `Blast-radius: platform` for the fix commit. `supabase/functions/CLAUDE.md` and `docs/architecture/functions-detail.md` are platform paths (`docs/blast_radius.yaml:125`); the code paths alone (`supabase_service.dart`, `day_swap_allowance.dart`) are account and `paywall_sheet.dart` is feature. The pre-commit NOTE agreed. No catastrophic path, so no hermes pass.

## What this branch is

A new optional argument `spendsQuotaPerCall` (default false) on `SupabaseService.callFunction` and `retryColdStart`. A flagged call throws a gateway 502, 503 or 504 on the first answer instead of being sent again after 2 s, 6 s and 12 s, and logs `edge_function_no_retry_quota_call`. `validate-promo` (the paywall's APPLY) and `consume-day-swap` (the PRO day swap) pass it. `isColdStart` is byte-identical, `retryOn500` stays independent, every other caller is unchanged. No migration, no Edge Function change, no deploy: it reaches testers with the next `/build-apk`. The defect is latent (NOT observed live: the 30-day `client_errors` read, 7,142 rows, holds no re-send event for either function).

## Two deliberate departures, stated in words

1. **CLAUDE.md 4.6 (feature-flag protocol), payment being on its list.** The gate is the compile-time call-site argument, not a runtime flag. Default false is the old path verbatim for every other caller; rollback is a revert of the PR or dropping the argument at the two call sites, and needs a new build. The direction is the safe one (less re-sending), the fault mode is a second tap, and no real user exists yet (CLAUDE.md section 1). The fallback, if the founder rejects this reading at merge, is a lazily read Hive key `disable_no_gateway_resend`, which would owe a removal OI (4.6 step 4) and a `docs/ship_dark_pending_review.yaml` line. The B-pass (finding 9 and the review's header) records that no seat rejected the reading and that the diagnose-doc states it.
2. **OI-414's wording "the 503 boot-failure retry is unchanged" was not kept.** A flagged call is not sent again on a 503 either. A BOOT_ERROR 503 means the handler never ran, but the repo has never observed that body (0 of 7,142 `client_errors` rows mention BOOT_ERROR; only prose in 0a7b9f), so a carve-out keyed on `details['code']` would be an unverified helper that fails silently into "never send again". Cost: a cold-start 503 on APPLY shows "Network error. Try again."; the next tap is free. This was the one design change AFTER round 2: it strictly reduces the reviewed surface. If a real body is ever captured, a carve-out can be added with that fixture.

The guarantee is worded honestly everywhere: **at most one unit per tap** (a gateway error may arrive before or after the handler ran and the user cannot tell). The OI's "never a unit" is corrected in its closing text.

## Rounds

| Round | Kind | Findings |
|---|---|---|
| 1 | Two context-blind Sonnet seats (A mechanism, B tests/gates/census) plus one read-only census agent over every Edge Function the client reaches through `callFunction`, every claim verified against code | `not_converged`: 0 P1 on the fix itself; the shared finding that v1's "one OI for the other functions" was the section 4.2 deferral shape, so v2 classifies every census row with a terminal state in a closure ledger. |
| 2 | Two fresh seats on the post-round-1 plan v2 (C mechanism and tests: 0 P1, 6 P2 test hardening; D governance and ledger: 1 P1 ledger row, 6 P2 bookkeeping) | `converged` after v3 folded every finding. Two changed ledger facts and were re-read in the code first: `food_text_analysis` is NOT clean (its dedupe covers only a still-pending row, `ai-proxy/index.ts:385-393`), and `assess-body-composition` has two facets (`index.ts:105-115,185-230`). |
| B-pass | Three fresh read-only Sonnet seats on the implemented diff (`docs/reviews/eb8fea69c002-review.md`) | 15 distinct findings (2 P2, 13 P3), 0 P0/P1, 0 false alarms; every one dispositioned (13 fixed in the fix commit, 1 spawned as OI-434, the counts in the review). Verdict `accepted`. |

Round 2 returned P2 findings but no P1 on the mechanism; the unit is small (one wrapper argument and two call sites), so it converged at two rounds without a split. One disclosure: seat D of round 2 ran one command outside its allowed list, a read-only `git ls-remote --heads origin 'oi/*'`; it changed nothing and showed `oi/425..427` reserved, so new OIs were numbered above 427 (OI-428..OI-434).

## Verification state at the time of this record

- Mutation proof (rule 21): 21 mutants plus M11 run apart, each confirmed applied, all red, none survived, none a compile error, source sha256 restored equal; run twice (before and after the B-pass fixes), the table is in the diagnose-doc. The script is session-local and not retained.
- Closure ledger `docs/audit/oi414-promo-no-gateway-retry.closure.yaml`: 20 of 20 entries terminal (Gate 40): 3 `closed_in_commit`, 10 `verified_clean` (a census reading, self-attested; `create-razorpay-order` is unflagged by the agent's judgement), 7 `blocked_on_user` (OI-428..OI-433 and the founder's post-build phone check). The use of `blocked_on_user` for OI-431..OI-433 is borderline (the fix is agent work, only the Edge Function deploy go is user-only) and the ledger header says so.
- Local gate loop on the final tree (before commit 1): whole-project `flutter analyze --no-fatal-infos` exit 0, 0 warnings, 386 infos (all pre-existing); `TZ=Asia/Kolkata flutter test --exclude-tags golden`: **11,449 passed, 11 skipped, 0 failed**; `PRE_COMMIT_GATE_JOBS=1` pre-commit loop OK on both commits. No Deno change. CI on the PR is the full-suite gate for `main`; its result goes in the PR description, not here.
- Not established: a gateway error AFTER the handler ran cannot be forced from a device, so the only device check is that APPLY (valid and invalid code) and one day swap still behave on normal answers (an OI-348 post-build line).
