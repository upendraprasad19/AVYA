---
branch: play-billing-fallback
date: 2026-11-20
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/a6d240c137b5-review.md
---

# Plan-review record: play-billing-fallback (platform; payment, tier L)

Plan: `docs/plans/2026-11-20-android-play-billing.md` (v3). Decision record: `docs/adr/0022-android-play-billing-via-revenuecat-web-stays-razorpay.md`.
`bpass: accepted` since the `/code-review` B-pass ran on the built diff (three fresh seats, 23 findings, all fixed or recorded; `docs/reviews/a6d240c137b5-review.md`, whose hash names the whole reviewed range `a1849656..HEAD` of the three code commits). The verdict in that file is the coordinator's triage, self-attested; this record lands as its own commit after the code so that citing the review does not move the hash it is named for (code-review skill, dispatch step 3). The tier is stated, not yet computed: MEASURED 2026-11-20 on the built diff (positional paths incl. `CLAUDE.md`, `razorpay_service.dart`, `paywall_sheet.dart`, `pubspec.yaml`): `Blast-radius: platform` (board card `p05-blast`).

## Round 1 (context-blind Sonnet, read-only, on plan v1)

22 findings: 4 P1, 9 P2, 9 P3. Verdict: NOT executable as written. Every finding was checked against the code by the coordinator before it was folded; the 22-row disposition table is section 13 of the plan. Material fixes: `play_billing` defined as no-purchase in the `+50` code with an `openCheckout` guard; the release-default wiring made testable (no platform input, source pin with mutants); the on-device build line moved from the unreachable Settings screen to the Profile tab; one missed live CTA (`plan_expired_card.dart:264`) and several server-sent price strings added; the section 8 collision with `grant_referral_days` and the "paid" readers written down.

## Round 2 (a fresh context-blind Sonnet, read-only, on the HARDENED plan v2)

19 findings: 2 P1, 9 P2, 8 P3. Reviewer verdict: NOT CONVERGED until folded. Every finding was checked against the code; the table is section 14 of the plan. Material fixes: the client canned-reply edit dropped (a byte-identity twin test pins it to the server file); the server-sent copy contradiction resolved by stating that a production release of `+50` is the store launch and recording the decision as `blocked_on_user` for the founder rather than parking it; migration cites corrected to 160 and 094; `DeepAnalysisCard` left to OI-304; mode seam made a static read; test 5 reworked; the two `fix(profile)` commits (sheet text, wrong Play package id in the referral share link) added as U4a with diagnose-docs.

Why `converged` is recorded after a "NOT CONVERGED" reviewer verdict: the round 2 P1s were (a) mechanical (a unit row removed) and (b) a contradiction whose resolution is a recorded founder decision, not a design change to the units. The changes since round 2 are mechanical edits or decisions written with their reason; no new mechanism was added except the two U4a fixes, which are separate commits with their own tests. This follows the precedent of `docs/plan-reviews/web-razorpay-checkout.md` (round 2 with one P1, folded, recorded converged). A third round was NOT run. This is the coordinator's judgement, self-attested, and the B-pass at the merge is where it is tested again.

## Ground-truth verification

Both reviewers verified claims against the live worktree at `a1849656` (file:line), including the 32 `showPaywallSheet(` call sites, `openCheckout` having a single caller, `dart.vm.product` precedent, the existing tests that pin source text, the referral and payment migrations 159, 160 and 094, and `backups/built_versioncodes.json`. Claims about Google Play policy, the Console, `purchases_flutter`, RevenueCat and Google's APIs are NOT verified by anyone (listed in the plan as unverifiable; `F9` is a build-time check, board card `p02-f9`).
