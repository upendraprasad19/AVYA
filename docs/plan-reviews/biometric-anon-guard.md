---
branch: biometric-anon-guard
date: 2026-11-24
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/b48f07cf-review.md
---

# Plan-review record — signed-out provider rebuild guards (a2d9f4, account)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `account`, COMPUTED** — `dart run scripts/blast_radius_from_diff.dart $(git diff --name-only origin/main HEAD)` → `account` (36 paths, Hive/auth session reads in provider builds; no schema, no Edge Function, no payment path).

## What this branch is

Crashlytics build 50: `BiometricNotifier.build` read a raw user-scoped Hive box while a tester signed out and into another account (61 fatal-flagged events from one user). A probe over every provider on real Hive found 35 provider builds that throw in the three sign-out windows (A Hive closed with the auth user still set, B both gone, C owner and auth disagree). Each now returns its empty value on the `'<anon>'` token before any box read (the `body_measurements_provider.dart:55` pattern). Two Diet Plan screen listeners, the plan heal and `SwapConfirmSheet.build` got the same treatment where a build-level guard could not reach. Diagnose `a2d9f4`; OI-526 files the separate closing-gap defect (`HiveUserSession._closeAllLocked` clears the owner after the box close).

## Review rounds (each on the plan/diff left by the previous one)

1. **Seat A** (fresh Sonnet, on `e41f824d`, the first ten guards): the class is far larger than ten (21+ further providers, three windows not two). Scope decision by the founder: "Fix all in this PR". The first fix's diagnose claims were corrected (wrong "methods run on user action", reader lines).
2. **Seat B** (fresh Sonnet, on `7f4fc263`, 23 guards; `docs/reviews/7f4fc263-review.md`): no P0/P1; five lower findings (strategy listener regenerating in the window, test oracles that could not tell guard-present from guard-absent, a swallowed `MigratedKey` fallback, the tripwire's blind spots). 23 mutants, 8 reddened nothing. All fixed in `b48f07cf`, plus the coordinator's own measurement that `daySwapWeekProvider` / `daySwapAllowanceProvider` (sync `Provider.family`) throw and needed guards.
3. **Seat C** (fresh Sonnet, on the delta `b48f07cf`; `docs/reviews/b48f07cf-review.md`): no P0/P1; four lower findings (supplements listener unpinned, guard placement unpinned, the swallowed edge when the real value equals the empty one, `SwapConfirmSheet` reading boxes). All fixed in `7e89a3cf`; six mutants on the fix, all red.

Convergence: findings fell from "the class is 3x bigger" (round 1) to five P2/P3 (round 2) to four P2/P3 on a ~400-line delta (round 3), none P0/P1 in rounds 2-3. The unit stayed large for the reason the founder chose (one class, one PR); each round's delta got smaller.

## Ground truth

Verified against code and live runs, not against the plans: every provider's guard placement (first statement after the token watch); real Hive, real token provider, real notifiers in `signed_out_provider_rebuild_behavioral_test.dart` (68 providers x 3 windows, a signed-in value that differs from the empty one for every guarded provider, full-field empties, a mention-count tripwire with its residue stated); mutants run with `grep -c` proving each applied and `sha256sum -c` restoring each file (M1-M9 plus the Seat B and Seat C mutants); whole-project `flutter analyze --no-fatal-infos` (0 warnings); CI green on `7f4fc263` and `b48f07cf`.

## Stated residue (self-attested)

- The final commit `7e89a3cf` (Seat C's four fixes) was verified by mutation and CI, not by a fourth reviewer.
- The closing gap (OI-526) is out of scope by decision; the test clears its error list after the sign-out switch for that reason and says so.
- A provider that reads a raw box and never mentions the token is not seen by the tripwire; a sweep over provider files found none today (`sync_state_provider.dart` reads only the shared configBox).
- Real-device check (sign out and into a second account on a build) is the founder's, with the next APK; the second Crashlytics issue (`AuthRetryableFetchException`, build 48) is untouched and needs its stack frames.
