---
branch: library-batch-m2b-viewer
date: 2026-11-03
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
---

# Plan-review record - library-batch-m2b-viewer (Batch M2b Part B: the logging viewer, OI-354; account)

Plan: `docs/plans/2026-11-03-library-batch-m2b-viewer.md` (r4). Tier `account`: the new strings go into `WardroomCopy`
(`lib/core/**`, `docs/blast_radius.yaml:619`); the rest of the diff is `lib/features/train/**` and
`lib/shared/widgets/exercise_plate/**` (feature). This is the viewer half split off the original M2b plan under
section 4.12.1; Part A (rows to the card edge + tile-led header) merged as PR #199 (`9dc64abb`) with its own record
`docs/plan-reviews/library-batch-m2b.md`. OI-354 closes with this unit.

## Rounds (context-blind Sonnet reviewers, each verifying claims against the code and the framework sources; executed spikes where the lens allowed)

1. Round 1 (4 reviewers on r1, as a plan of its own: ground truth, Flutter mechanics, tests and gates, product and
   states): 0 P0, 4 distinct P1 and about 12 P2. P1s: Part A tests that B2 turns red were not scheduled; three harness
   checks were vacuous on `pumpScreen`'s single Navigator (tile freeze, orphan, root navigator); mutations that could
   not go red (the `changes` notifier, the shared pop guard); a viewer orphaned by a branch switch (`indexedStack`
   keeps the branch offstage). Folded in r2; the `changes` notifier was dropped as redundant (the provider write after
   a `+` already rebuilds the viewer).
2. Round 2 (4 reviewers on r2: ground truth, Flutter mechanics, tests and gates, product and simplicity): 0 P0.
   Ground truth converged (5 P2, 3 P3). The others: the animation sizing rule contradicted the approved mockup
   (product and mechanics), `Semantics(scopesRoute)` without `explicitChildNodes` asserts on every build, `tester.tap`
   cannot deliver a same-frame double event, the `_closed` flag / `route.popped` hook were redundant with the
   route-state guard (all four executed, mechanics), 2 P1 test-specification from the tests and gates lens, and one
   DESIGN change decided by me with an executed spike on a real go_router `StatefulShellRoute`: the viewer is
   pushed on the BRANCH navigator, not the root, which deletes the dispose-time `removeRoute`, the `TickerMode`
   watch, the viewer-owned `ScaffoldMessenger`, the nested-Navigator harness and six mutations. Folded in r3.
3. Round 3 (2 reviewers on r3: Flutter mechanics with executed spikes, ground truth and consistency): 0 P0, 2 P1,
   about 11 P2, 8 P3. NO design finding: hosting, the handle, the count guard, the route-state `_close()` guard and the
   sizing formula held under executed spikes (a real shell, the single-Navigator `pumpScreen` shape, nine layout
   scenarios). The two P1s were spec defects: a `data.workoutDay == null` self-close term that would close the viewer
   in every Part A card-only host (their seed has no `workoutDay`), and a mutation / test pair on `unfocus()` in
   `_close()` that cannot redden because the framework releases a popping route's field focus itself. The P2/P3s:
   `kViewerScrollMinDp` re-derived from measured content (210, with the scroll view's 10 dp padding), a hide
   threshold of 100 dp, the opaque-route mutation needs a settled frame, `_close()` caches `route` and `navigator`
   in `didChangeDependencies`, direct-driver callbacks named, back-label `Flexible`, a `Material` ancestor for the
   B1 host, route-flags test, Keys on the LAST/TRY lines, three Part A assertions to repoint, the thumb needs no new
   Semantics wrapper (it would remount the thumb), and citation fixes. Folded in r4.

No fourth round was run: round 3 produced no design finding and every item is a mechanical spec or test-specification
fix with executed proof, so by section 4.12.1 the unit is not too large and the next check is the build itself (TDD,
the mutation proofs of B1/B2 Step 4, the full gate loop) and the self-triggered B-pass before the merge. The
`converged` verdict above is the coordinator's judgment after folding round 3, not a reviewer's: record it as such
if the B-pass finds a plan-level defect.

## Ground truth

Every file:line citation in r4 was read by the round-3 ground-truth reviewer on the tree (`exercise_card.dart`,
`screen.dart`, `card_harness.dart`, `exercise_header_tile_test.dart`, `sot_registry.yaml`, the framework sources); the
corrections it found are folded. `git diff 0d95a747 FETCH_HEAD -- lib test supabase/functions` is empty (main moved
by 9 docs / migration / OI-board commits), so no line number moved.

## B-pass

`bpass: accepted` is NOT required at `account` tier (`scripts/check_plan_review_record_exists.dart`: >= platform). The
B-pass still runs before the merge (CLAUDE.md section 4.3, >= account, self-triggered) and its file is
`docs/reviews/<branch>-bpass.md`.
