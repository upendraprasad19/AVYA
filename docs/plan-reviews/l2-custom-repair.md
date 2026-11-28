---
branch: l2-custom-repair
date: 2026-10-21
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/77090eddcb7e-review.md
---

# Plan-review record — Batch 0b: remove the custom exercises L2 already put into plans (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED** — `scripts/pre-commit.sh` on the staged diff reports
`blast-radius=platform`. The rules: `lib/core/services/sync_flags.dart` is platform at
`docs/blast_radius.yaml:517`, and `lib/shared/repositories/plan_engine/**` at `:105`.

## Plan
`docs/plans/2026-10-21-l2-custom-repair.md` (r5 plus the r6 B-pass section); diagnose `c3e9a4`.
It is stacked on Batch 0a (`l2-no-custom-autoadd`, PR #138) and merges after it.

## Review rounds (context-blind Sonnet reviewers, every claim checked against code and live data)
1. **Round 1** reviewed the combined 0a + 0b plan: 1 P0 and 6 P1, all in the repair half.
2. **Round 2** reviewed the post-round-1 plan: 5 P1, again all in the repair half. Per §4.12.1 the
   unit was split, and 0a shipped the converged generator removal.
3. **Round 3** reviewed the 0b plan alone (r3): 0 P0, 3 P1 and 9 P2, all applied in r4.
4. **Round 4** reviewed the post-round-3 plan: CONVERGED, with 0 P0, 0 P1 and 12 P2, all applied
   in r5.

## B-pass
`docs/reviews/77090eddcb7e-review.md` found 0 P0, 0 P1, 2 P2 and 7 P3. All nine were fixed in commit
`d042162d`. Each fix was proven by mutation: 15 scripted mutations, each restored by copy and
sha1-checked, and each turned only its target red. The verdict is accepted.

One follow-up came from the author after the B-pass, commit `3b6f907c`. The repeat-pin
`custom_origin` stamp now reads the same kill switch, so `disable_l2_custom_strip` restores the
generator output of the build before (§4.6 point 2). It changes 3 lines and is proven by
mutation m16, which turns `repeat_phase_pinned_selection_behavioral_test.dart` (7) red.

## §4.6
Kill switch `disable_l2_custom_strip` (`SyncFlags.l2CustomStripEnabled`, configBox; absent means
ON). Setting it skips the one-time migrator, the repeat-pin strip and the `custom_origin` stamp.
That is byte-identical to the build before, and the tests cover it: the migrator kill-switch test,
repeat pins (4), and pinned selection (7). No waiver is needed.

## Verification
- `flutter analyze lib/` and the touched tests: 0 errors, 0 warnings (60 pre-existing infos).
- Targeted suites green:
  - migrator (24 tests);
  - predicate;
  - repeat pins (7);
  - pinned selection;
  - `upsert_scheduled`;
  - wired.
- 144 neighbour tests green, plus the exercise-seam gate (inventory unchanged).
- The full pre-commit gate loop is green on both commits. That includes SoT parity: the line pins
  were remapped through the real diff hunks, not a guessed offset.
- The full suite runs as CI on the PR. The founder stopped the 50-minute local run on 2026-10-21,
  and PR CI is the full-suite gate (§4.3).
