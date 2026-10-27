---
branch: age-floor-signup-consent
date: 2026-10-16
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/age-floor-signup-consent-bpass.md
---

# Plan-review record — one age floor of 13 and a "by tapping" sign-up consent (`age-floor-signup-consent`)

Plan: `docs/plans/age-floor-signup-consent.md` (v2, with the round-1 corrections in its header; the round-2 corrections are in the text of section 1 item 5 and section 2). Founder decisions this plan builds on (chat 2026-10-16): the floor is 13 for every date-of-birth picker; the sign-up consent is a tap on CREATE ACCOUNT under a notice, with no checkbox (option B, chosen over the recommended unticked box after the DPDP and Google Play risk was stated once); the privacy policy is published at https://icanbefitter.com/privacy and was read.

**Tier.** `account` (`lib/features/auth/**`, `lib/core/**`), processed as an L-tier change (auth, CLAUDE.md 4.12.6): a full ×2 plan review and a B-pass. Not `ship_dark_build`: the change is live the moment it merges (no kill switch).

**`bpass: accepted`** (2026-10-16, `docs/reviews/age-floor-signup-consent-bpass.md`, with the same-dated entry in the code-review tuning history): two fresh context-blind Sonnet reviewers on the working tree (A: code and tests with 15 proposed mutants; B: documents and claims), 0 P0, 0 P1, 7 P2, 16 P3, 0 false alarms, every one fixed or recorded with a reason in the review file. The ones that changed the build: the picker clamp is now observed through the wheel controllers, the picker ceilings are pinned verbatim, the picker-open path with a too-young carried value is tested, `ScrollDatePicker` clamps a seeded date, the consent notice follows the system text size, and GO_LIVE 3.5 no longer says the Google / phone posture is resolved.

## Rounds

- **Round 1** (v1 of the plan; two context-blind Sonnet lenses under `docs/agent_brief_preamble.md` and an exhaustive read-only command list): every finding adopted. The ones that changed the build: the conversational picker's `ScrollDatePicker` bounded only `lastDate.year`, so a month or day later in that year was reachable; `identity_screen.dart` CONTINUE checked only `_dob != null`, so a date of birth carried in through the route extras skipped the floor; `integration_test` T3 and the auth helper still drove the removed checkbox; GO_LIVE rows 3.1, 3.4, 3.5 described the checkbox; the Google / phone fallback would have labelled an account that predates the new policy with the new version (hence `termsVersionForAccountCreatedAt`).
- **Round 2** (the post-round-1 text and the built tree; lens A ground truth and writer/reader, lens B tests and mutation adequacy): 0 P0. Lens B: the CONTINUE compare must be date-only, the `ScrollDatePicker` clamp must be minimal (pull the month back, keep the day unless it still overshoots), an unused parameter on `_buildPrimaryButton`, device-test leftovers (T5 removed). Lens A: P2 the fallback's two call-site lines were observed by no test (now a comment-stripped source pin plus two mutants that redden it), P2 the device-test cleanup was incomplete (done), P2 the closure ledger and this record did not exist (written), P3 the plan's claim that the tap stamp cannot be written under email confirmation was not traced (reworded: it may land; the fallback covers the case where it did not), P3 stale statements in `docs/architecture/database.md:57` and a test reason text (both corrected), P3 stale line numbers in plan prose and registry ranges (cosmetic, ungated), P3 `ScrollDatePicker.initState` does not clamp `initialDate` (the old chat floor was 16, stricter, so a saved answer cannot be later than the new `lastDate`; recorded as `verified_clean`).
- **No round 3**: round 2 returned no P0 and reopened no decision; its P2 items are closed by falsifiable tests or by the files now existing.

`review_rounds: 2` counts the rounds on this unit's lineage; review #2 ran on the post-review-#1 plan (CLAUDE.md 4.12.1).

## Ground truth verified

The coordinator re-verified against the code: exactly three date-of-birth picker call sites (`identity_screen.dart`, `onboarding_chat_screen.dart`, `edit_profile_screen.dart`) plus the `ScrollDatePicker` definition; no reader enforces an age; nothing in `lib/`, `supabase/`, `scripts/` or `test/` compares `terms_version` (hence OI-346); `2026-10-15T18:30:00Z` is IST midnight of 16 October (UTC+5:30); `latestAllowedDob` clamps 29 February to 28 February (13 years back is never a leap offset from a leap day); the fallback call sites at `auth_session_bootstrapper.dart` stamp `termsVersionForAccountCreatedAt(stamp)` in both the cloud update and the Hive write.

## Could not verify (the device check)

- The live Supabase email-confirmation setting (OI-343 recorded `mailer_autoconfirm=false` on 2026-10-13 from a Management API read; not re-queried).
- Whether the tap stamp lands in the per-user Hive box on the no-session sign-up path (`signUpWithEmail` calls `_ensureLocalUser` in a try/catch there); the fallback makes the end state the same either way.
- Play Console Data Safety wording and counsel's view of "by continuing" for a health-data app: ledger rows `PLAY-REVIEW-RISK`, `DEVICE-CHECK-AGE-CONSENT`.

## Merge order

The published privacy policy already says "13 or older" and that the date of birth is checked at sign-up; the build still accepted 10. Binding order: PR #117 (decisions) → this PR → PR #118 (the measurements flag flip).
