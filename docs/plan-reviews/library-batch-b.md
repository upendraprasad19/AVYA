---
branch: library-batch-b
date: 2026-10-23
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/library-batch-b-bpass.md
---

# Plan-review record — Batch B1: core-list pool (platform, ship-dark)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`.** Confirmed on 2026-10-23 over the whole branch (`git diff origin/main...HEAD --name-only | dart run scripts/blast_radius_from_diff.dart -`). The diff touches `lib/shared/repositories/plan_engine/**`, `lib/core/services/seed_service.dart` and the bundled library. The new path is ship-dark behind configBox `enable_core_list_pool` (default OFF, `docs/ship_dark_pending_review.yaml`, build commit `06c02bed`). It still took the full ×2 review because two LIVE fixes ride in the same batch (b1c4e7, c2d5e8).

## Plan
`docs/plans/2026-10-22-library-core-list-pool.md` implements spec `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md` §9 row B1. Executed INLINE (founder, 2026-10-23).

## Review rounds (context-blind Sonnet reviewers, every claim checked against code and data)

1. **Round 1:** 2 P0, 7 P1, 12 P2. All applied in r2.
   - **P0:**
     - The level rule let lower-level rows back in. It is now a P2 rank rule with a level oracle in the tests and the gate.
     - Custom repeat pins were dropped by the new capability check. Fixed with `canOfferInPicker(isCustom:)`, two custom-pin tests and golden pin personas.
   - **P1:**
     - The implement preference is keyed on capability.
     - The tier rule applies when capability is null.
     - The shared `_isContraindicated` is passed in.
     - The stale-library test discriminates through `delegations`.
     - `debugTrace` added.
     - Strength retags moved to `slot_pattern` ON-only; safety tags applied live (founder).
     - Frozen per-row reference fixture added.
2. **Round 2** (on the post-round-1 plan): 2 P1, 10 P2. All applied in r3.
   - B soft-avoids A.
   - An empty variant copies the other.
   - A doubly-empty day takes any-level core rows, and the OFF cascade runs last.
   - Gym multi-drop count on uninjured personas.
3. **Round 3** (on the post-round-2 plan): **CONVERGED**, 0 P0, 0 P1, 6 P2 (Ruling 12 confirmation, emergency trace source, avoidNames widening, multi-injury sweep, B-repeats-A rate, `cables` test). All applied before execution.

## Task 4 counts (ON world, 998 golden personas, real `generateV4`)

**Hard zeros, all 0** (`core_list_pool_gate_test.dart` `bad.add` classes):
- `canPerform`, injury and exclusion violations
- discipline (skill/olympic) picks
- level (a pick not core at the effective level, or a bad fill)
- improvised picks while a non-improvised row is in the pool
- retired-row picks, in the trace and in the BUILT lists (`built:`, B-pass F1)
- uninjured multi-drop lists
- OFF refills
- empty days

**Reported, not gated (flip criteria):**
- `emergencyAnyLevel` in 2 personas (shoulder-injured bodyweight intermediate, p1/p2).
- `copied` variants: 2.
- Injured lists dropping 2+ slots: 16.
- Multi-injury sweep: 576 runs, emergency in 54, refilled in 22. The built lists carry retired E261 and E234 (from those refills) and no skill/olympic id.
- Strength picks per day:
  - bodyweight advanced: mean 4.67 ON vs 8.56 OFF;
  - bodyweight intermediate: min 1 ON vs 3 OFF.
- High-impact picks: E193 ×812.

Full table: `test/plan_generator/core_list_pool_report.md`.

## Founder gates
- Plan approval: **APPROVED** in chat, 2026-10-22 ("Approve both").
- Safety tags live: **APPROVED** ("Apply all 5 live"). E173/E127 sit inside the 13-B carve-out, so they are flagged back as closure item `CARVEOUT-E173-E127` (blocked_on_user).
- Phase 1 foundational is a preference: **APPROVED**.
- Empty day falls back to easier core moves (Ruling 12): **APPROVED**, 2026-10-23.
- Execution mode: **INLINE**, 2026-10-23.

## B-pass (2026-10-23, reviewed at `0ef6b3f5`)

`docs/reviews/library-batch-b-bpass.md`: 0 P0, 0 P1, 6 P2, **accepted**. Five were fixed in `4526ddc9`, each with a test run red then green:
- **F2:** the empty-day emergency now admits only easier-or-equal core rows, nearest level first (founder: "easier core moves").
- **F1:** the gate checks the built lists. The sweep's OFF-cascade refills serve retired E261 / E234, so the flip criteria are widened.
- **F3:** the registry nesting is fixed, with a new test.
- **F5:** E274 added to the OI-387 test.
- **F6:** the two-pin effect is pinned and named in diagnose b1c4e7.

F4 was this record's forward reference to the review file, by design.
