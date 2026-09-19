---
branch: unit6-cqrs-entitlement
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/21300a16c95d-review.md
hermes_report: not_required
---

# Plan review — `unit6-cqrs-entitlement`

Unit 6 of the OI-25/44/45/46/48/50 batch — the last one. **Closes OI-44.** Diagnose `a9c4e1`.

## Tier

Measured on the actual staged set, after the LAST edit:

```
git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -
→ account
```

**The plan predicted `platform` and was wrong.** `docs/blast_radius.yaml:183` carries an
explicit `{ glob: lib/core/services/subscription_service.dart, tier: account }` — a deliberate
classification, not a catch-all fallthrough. The genuinely payment-critical paths in that
registry (`razorpay-webhook`, `verify-payment`, `subscriptions` RLS, `:41-49`) are all
`catastrophic`; the client entitlement cache sits one rung below, correctly. Recorded because
"payment-adjacent therefore platform" was an assumption, and the classifier is the authority.
The trailing `-` is load-bearing.

## Ground truth verified

Every load-bearing claim checked against the artifact:

- The self-invalidation chain, hop by hop: `profile_provider.dart:380` → `isPro()` →
  `subscription_service.dart` `_downgradeLocally()` → `onStateChanged` → `app.dart:47`
  `ref.invalidate(subscriptionInfoProvider)`. Also verified its *limits*: it terminates, and
  `_downgradeLocally` is `async` + unawaited so the invalidation lands a microtask after
  `build()` returns. Reported at that precision rather than as a crash.
- `refreshFromSupabase()` does NOT perform the cross-account check — read directly. The startup
  guard it claims to back up is `hive_user_session.dart:208` + `restoring_screen.dart:272-280`.
- Callsite counts COUNTED, not estimated (see the counting-discipline note below).
- Both gate exemptions traced to real code.

## Round 1 — 11 findings

Two **P0s that made the repo red**, and both were mine:

- `test/contracts/gate_coverage_test.dart:35` — a regex pinning the literal `.gate(` that my
  rename broke. A `test/contracts/` test, which pre-commit runs.
- `test/workout_repository/streak_workout_only_test.dart:68,87,115` — 3 compile errors from the
  `calculateCurrentStreak` deletion. **My completeness grep had used `| head -20` and truncated
  this file out of its own evidence.** The diagnose-doc had confidently enumerated "3 files".

The consequential P1s: the self-invalidation loop was **not actually closed** —
`home_provider.dart:464` (`SubscriptionExpiryBannerNotifier.build`) still called the mutating
read, and a systematic sweep then found **seven** build-path sites, not one. And the §4.6
kill-switch, as first written, produced a state **weaker than both** paths: the pure-read
callsites were not behind the flag, so closing it left build methods pure *and* made the
explicit enforcement inert.

## Round 2 — 4 findings, the top one a P0 REGRESSION from a round-1 fix

Third batch running in which round 2's material finding is a round-1 regression rather than a
defect in the original work — the §4.12.1 signature.

Round 1 added a `HiveUserSession.currentOwnerFullId == null` guard to `evaluateEntitlement()`
(correct in itself — it stops sign-out from writing through to the shared configBox). But the
boot caller was **synchronous**, and at cold start no `openForUser` has run, so
`currentOwnerFullId` is null and **boot enforcement was a permanent no-op**. The unit was
claiming boot coverage it did not have, having already made the build readers pure — strictly
worse than before. The evidence was sitting 86 lines above my own call:
`splash_screen.dart:127-134` documents this exact trap, and every sibling initializer fired
from that point awaits `ensureOpenedForCurrentSession()` first (`refreshFromSupabase:778`,
`rank_service.dart:83`).

Its knock-on (P1): `pro_lapsed_at` is stamped **only** on the enforcement path —
`_downgradeLocally` does not stamp it — so with boot enforcement dead and the banner provider
now pure, the red "your PRO expired" banner could stop appearing entirely.

Fix: `evaluateEntitlementAtBoot()` opens the session first, and splash **awaits** it before
`refreshFromSupabase`, making the ordering deterministic rather than a microtask race.

## B-pass — accepted

1 P1, fixed pre-merge: `gateAndVerify`'s server-verified branch left the callbacks inside the
region guarded by `.catchError`, so a **throwing `onFree()` (paywall) fell through to
`onPro()` — granting a PRO feature to a free user**. A defect in the original 7b3eaf code that
this unit's own exactly-once claim exposed. Record:
`docs/reviews/21300a16c95d-review.md`.

## Convergence

| | P0 | P1 | P2 | P3 | new defects in the ORIGINAL work |
|---|---|---|---|---|---|
| Round 1 | 2 | 2 | 3 | 4 | 11 |
| Round 2 | 1 | 1 | 0 | 2 | **0** — the P0/P1 pair are round-1 regressions |
| B-pass | 0 | 1 | 0 | 0 | 1 (pre-dates this unit — original 7b3eaf) |

Severity is falling, round 2 found nothing new in the original work, and the B-pass's single
finding is older than this unit. **Verdict: converged.**

Not a §4.12.1 "split it" signal: the split criterion is successive rounds surfacing *new
material issues in the original work*. Rounds 2 and 3 surfaced (a) regressions from round 1's
own corrections and (b) one pre-existing defect. Splitting would have shipped a unit whose
headline fix — closing the self-invalidation — was only 1/7 done.

## Feature flag

§4.6 kill-switch `disable_cqrs_pure_pro_read`, default **ON** (new path live). This is a
kill-switch, **not** ship-dark: §4.12.4's lighter 1-round tiering requires default-OFF, so it
does not apply and no `docs/ship_dark_pending_review.yaml` entry is owed. Full ×2 + B-pass ran.
Its scope is documented precisely rather than overclaimed: it restores the pre-split behaviour
**of `isPro()`** for the decision callsites; it does not revert the build-method readers, and
`evaluateEntitlement` is deliberately outside it so closing the switch can never reduce guard
coverage below either path.

## Counting discipline — three wrong numbers, each caught by a reviewer

The `isPro()` callsite count was published wrong three times: the plan said **32** (counted
grep LINES, comments included); a first correction said **28** (a `grep -vE` filter that let one
indented comment through); round 2 measured **27** and was right. Verified final: **27 call
expressions across 22 files on `main`, 18 across 17 files after.** A count is a claim, and
`wc -l` on a grep is not a count of call expressions.

## Process findings

- **`| head -N` on a completeness check is self-deception.** It converted a full reference
  sweep into a truncated one and produced a confidently wrong "3 files" claim in the
  diagnose-doc, which became a P0. Never pipe an exhaustiveness grep through `head`.
- **A gate that misses its own worked example is theatre.** The CQRS gate initially failed to
  flag `calculateCurrentStreak` — the very case its header cites — because the write was two
  delegation hops away and behind a repository call rather than a raw `box.put(`. It needed a
  writer-verb layer *and* transitive resolution before it detected anything real.
- **Reviewers were told, in the brief, not to write to the tree**, with the Unit 7 incident
  quoted. Both complied and used the committed fixture (`test/fixtures/cqrs_gate/`) for their
  negative controls. The whole diff was staged before any reviewer ran.
