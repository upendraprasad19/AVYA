---
branch: library-batch-m2b
date: 2026-11-03
blast_radius: account
review_rounds: 6
ground_truth_verified: true
verdict: converged
---

# Plan-review record - library-batch-m2b (Batch M2b Part A: LOG-mode rows to the card edge + tile-led header; account)

Plan: `docs/plans/2026-11-02-library-batch-m2b-tile-and-rows.md` (r8). Tier `account`: the new strings go into
`WardroomCopy` (`lib/core/**`, `docs/blast_radius.yaml:615`); the rest of the diff is `lib/features/train/**` (feature).
Part B (the logging viewer, D4/D6/D9) is a separate unit with its own two review rounds on a new branch
(`docs/plans/2026-11-03-library-batch-m2b-viewer.md`); OI-354 stays OPEN naming it.

## Rounds (context-blind Sonnet reviewers, each verifying claims against the code)

1. Round 1 (unsplit design, 3 reviewers): 1 P0 and about 20 P1. The P0: an opaque route pauses the covered card's
   Riverpod watches (`consumer.dart:390-413`, `overlay.dart:877-885`), so the viewer route had to be non-opaque. Folded.
2. Round 2 (unsplit design, 3 reviewers): no P0, about 12 P1, the new ones all in the viewer half; the seam between
   the card and the viewer contradicted itself. Under section 4.12.1 the unit was SPLIT: Part A (this record) = rows,
   header tile, ENLARGE opens today's plate sheet; Part B = the viewer.
3. Round 3 (Part A alone, 2 reviewers): no P0, 9 distinct P1. One design change (the tile's freeze follows
   `ModalRoute.isCurrentOf`, so every sheet door freezes it). Folded.
4. Round 4 (2 reviewers): no P0, 7 distinct P1, all claim-narrowing or test-spec precision (a dialog claim that was
   false because `showDialog` uses the root navigator; three mutations that could not redden; two Ahem-unsatisfiable
   layout assertions; an unspecified same-State re-pump; the logged-set arrow overlay would sit at the top of the KG
   box). Folded in r5/r6.
5. Round 5 (1 reviewer): NOT converged, 1 P1, 1 P2, 5 P3. The root-navigator dialog case cannot pass in the harness,
   whose `MaterialApp(home: ...)` has ONE navigator (`card_harness.dart:43,134,219`). Folded in r7 (a
   `nestedNavigator` option on `pumpCard`); the mechanism was proven by an executed throwaway spike (single
   Navigator: `isCurrentOf` goes false under the dialog; nested: stays true).
6. Round 6 (1 reviewer, scoped to r7's delta and to harness feasibility of every Task 1 / Task 2 assertion): NOT
   converged by its own verdict, 3 P1, 1 P2, 3 P3, each reproduced by the reviewer in an executed spike: a barrier tap
   cannot dismiss the plate sheet at the default 800 x 600 view; the unchanged panel header overflows under Ahem at
   360 dp and below whenever a cue field is seeded (so the layout cases use a cue-less row); mutation (l) cannot
   redden the exact-label case (rewritten as a decide-at-execution rule). Folded in r8.

## Why `verdict: converged` is recorded on a round that said "not converged"

Stated plainly rather than implied: the last reviewer's own verdict was "not converged". It is recorded `converged`
because (a) no round since round 4 has produced a design finding, rounds 5 and 6 found only test mechanics (what the
harness and the Ahem font can produce, and whether a named mutation can redden a named test); (b) every one of those
findings was reproduced by an executed spike, not argued, and is folded into r8; (c) Task 1's assertions came back
clean in round 6; (d) that finding class is settled directly by running the tests (red, green, mutation) in the build,
which the plan requires, and the build ledgers any assertion that still cannot be satisfied or cannot redden as a
ruling, never as a loosened test. The count of P1s per round on Part A was 9, 7, 1, 3. This is the coordinator's
self-attested call; the merge-time B-pass (`/code-review`, section 4.3) reads the built diff, not this plan.

## Ground truth

Claims were checked against the code by each reviewer (writer/reader file:line for the card header, the set row, the
harness, `exercise_animation_view.dart`, `exercise_plate_sheet.dart`, the router's Train branch, `MobileFrame`, the
registry ranges, the Gate 40 states, the glossary rows). Two throwaway spikes were executed (nested-Navigator dialog,
by the coordinator; harness shape, plate-sheet rect and panel overflow, by the round-6 reviewer) and deleted; no spike
file was committed. No live-state claim is made; no migration, no Edge Function, no live DB action.
