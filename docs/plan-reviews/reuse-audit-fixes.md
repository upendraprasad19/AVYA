---
branch: reuse-audit-fixes
plan: docs/superpowers/plans/2026-09-26-reuse-audit-fixes.md
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/reuse-audit-fixes-bpass.md
---

# Plan review — reuse-audit fixes (B1 + C + D shipped; A + B2 split out)

**Blast radius:** account (auth sign-up + onboarding referral path; nutrition + train writers).

**Origin:** founder asked for a screen-wise functionality map and a check that screens reuse the
common functions. A re-verification pass kept 5 real defects (A deleted templates resurrect,
B1 saved-meal times_used, B2 saved meals never sync, C referral code lost at email sign-up,
D custom-exercise create bypasses its writer) and dropped 5 duplication-only candidates. A
read-only live DB check (2026-09-26) found no real user affected by A/B2 today.

## Round 1 (context-blind) — plan rev 1 → needs revision, 14 findings

Rename and AI-create resurrect paths for A; the restore sweep deleting local-only templates; B2
delete resurrection, cross-format name collisions, missing macro columns on the cloud table; C's
configBox approach breaking cross-device (→ switched to auth user metadata); D's source-grep pins
(P0), signature callers, maxLength, the ignored WriteResult; tests that did not exercise restore;
case-exact tombstones; a stale gate allowlist; the syncSavedMealsNow snapshot pin; registry naming.
All folded into rev 2.

## Round 2 (context-blind, on hardened rev 2) — needs revision, 4 P1 + 5 P2

P1s were ALL in A/B2 and all introduced by the round-1 corrections: keeping local-only names in
the sweep defeats cross-device delete/rename; unconditional tombstoning + the sweep can delete a
same-named template the user kept; MigratedKey's configBox fallback can leak a tombstone across
accounts; five unlisted source-grep tests break. For B1/C/D round 2 verified the premises
(upsertTemplate callers, signUp(data:), userMetadata use, EF referee check, 7-day window, D's
duplicate guard seeing restored rows) and raised only P2s: R2-7 (re-save resets times_used) and
R2-9 (upsertCustomExercise can report fail after a successful put).

## Decision — split per §4.12.1

Successive rounds kept finding NEW material issues in A/B2 (multi-device deletion semantics for a
push-everything-as-active sync), which is the split signal. This branch ships the converged
piece — B1, C, D with R2-7 and R2-9 folded in (plan rev 3 header). A and B2 continue as the next
unit in the same session, with the multi-device delete semantics taken to the founder as options
before any code. Not a deferral: both remain in this batch's scope.

## Ground truth

Every writer/reader cited in the three diagnose-docs was read at file:line on the branch; live
DB state (templates, user_saved_meals = 0 rows, 3 referral redemptions, latest 26 June) queried
read-only. Implementation-time deviation from rev 3, recorded in the plan: `pending_referral_code`
stays on the documentation-only `_intentionallyShared` list (legacy devices may hold it); only its
false comment is fixed.

## Verification

flutter analyze on every changed lib file clean; full pre-commit gate loop exit 0; targeted tests
green; 12 mutations each reddening its intended test (recorded per diagnose-doc). Full
`flutter test` before the B-pass: 6462 pass / 8 skip / 1 fail (`null_guard_test` pinned the
removed sign-in configBox use — repointed to the stricter "no configBox" form, green).

## B-pass (`docs/reviews/reuse-audit-fixes-bpass.md`) — 3 findings

F1 (P1, referral redeem before users row) false_alarm — verified live: the auth trigger creates
public.users at sign-up (0/36 missing), and callFunction already retries transient 5xx. F2 (P2,
double-tapped SAVE writes two rows sharing an id) and F3 (P3, false "could not save") fixed, F2
with two mutation-proven concurrency tests.
