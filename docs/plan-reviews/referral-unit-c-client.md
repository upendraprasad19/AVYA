---
branch: referral-unit-c-client
plan: docs/plans/referral-unit-c-client.md
date: 2026-10-17
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/0dd0bab609aa-review.md
---

# Plan review - unit C, the referral client surface (OI-336)

Founder decisions (2026-10-16, chat): the referrer sees AGGREGATES ONLY (friends joined, subscribed, PRO days earned, a pending count; no names, no payment time, no plan class); a credit is announced IN-APP when the user next opens the app (no push); the first run on a device is SILENT; Phone OTP is described as not live in the root and auth CLAUDE.md. The founder's "go" to build was given on 2026-10-17 ("go", after the migration 160 merge). The plan's tier is platform because the plan commit edits the root `CLAUDE.md` Auth row; the build commit is account (client code under `lib/features/{profile,home,auth,onboarding}`).

## Review rounds

- **Plan round 1** (fresh, context-blind): 2 P1, 6 P2, 4 P3. An existing contract test named nowhere would go red; the friend disclosure "not who" was not true of what stays readable; "dark until 160" overclaimed; `_applyCode`'s side effects were misdescribed; account-swap and key registration were unspecified; the notice algorithm had gaps; the RPC call shape was open; the sheet layout overflowed.
- **Plan round 2** (review #2 on the post-#1 plan): 0 P1, 6 P2, 9 P3. The kill switch is a local key, not a remote kill; the ground truth still said three hidden columns; an in-flight account swap was only half guarded; `verifyFromServer()` is cached for 5 minutes; the silent first-run baseline loses credits earned before install; the friend disclosure was missing from the apply sheet.
- **Plan round 3**: 0 P1, 3 P2, 9 P3. No diagnose-doc / recurrence / commit type for the `_applyCode` repair (recurrence of d2b9e6); the single-flight, throttle stamp and verified-for memory were not keyed per account; the onboarding welcome screen's live referral field was missing; plus the gate-test name, the unforced verify in the apply sheet and copy details. All folded into plan v4.
- **B-pass** (`docs/reviews/0dd0bab609aa-review.md`), two fresh context-blind Sonnet seats on the built, staged tree: 0 P0, 0 P1, 2 P2, 10 P3, every one a row of the closure ledger (8 fixed with a test, 2 verified clean by the plan, 1 vacuous test renamed and its guard documented, 1 left to the founder's wording review).
- **Convergence, stated plainly.** Plan v4 was NOT re-reviewed as a plan after round 3 (rounds 1 to 3 each found P2s in the plan); the review that read the finished design was the B-pass on the built tree. It found one real concurrency defect (a second concurrent trigger skipped the shared forced verify) and one overpromising copy line, both fixed and mutation-proven. The founder approved v4 as written on 2026-10-16 ("1, 2, 3 go approved") and again gave the build go on 2026-10-17.

## Ground truth

- Read in the worktree on 2026-10-17 at `origin/main` `45250e91`: `referral_repository.dart`, `invite_friends_sheet.dart`, `apply_referral_sheet.dart`, `home_screen.dart`, the measurement slot/provider/flag pattern, `user_config_migrator.dart`, `sync_retry_controller.dart` (`isOutageShapedFailure`, `httpStatusOfError`), `service_providers.dart`, the migration 159 reward conditions (first qualifying payment, 90-day window, 7-day vest, void on cancel) and the migration 160 grants.
- The server half was applied live and verified on 2026-10-17 (migration 160, PR #121); the client can only observe `referrer_summary()` through a real user session, which is OI-348 rows A10 and B1 (filed on branch `pending-checks-oi`).

## What this record does NOT claim

No device check, no live PostgREST check with a user JWT, and no `/build-apk` has happened. The welcome screen's 2x-text overflow predates this unit (OI-349). The privacy-policy sentence and the founder's wording review of `lib/core/copy/referral_copy.dart` are open (ledger rows X7, BP-B8).
