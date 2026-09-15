---
branch: oi150-phase-merge
date: 2026-08-30
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/375e3a351e7b-review.md
hermes: not_required
diagnose: 321062
---

# Plan review record — oi150-phase-merge (OI-150)

## What shipped

Four units, one batch. `commitPhaseAdvance` writes four fields as one atomic delta;
OI-83 guarded only `current_phase`, so a stale cloud row split the group on restore and
the merged result was written back to Hive.

1. **Couple the phase delta** as a post-pass in `mergeCloudProgress`, keyed on whether
   the merge kept local's `current_phase`, with a per-key carve-out so a companion local
   does not hold is never refused into absence.
2. **Anchor the login plan regeneration** on the guarded Hive value, not the raw
   pre-merge cloud row.
3. **Recompute the profile's derived targets** after the restore merge, but only when a
   derivation input changed.
4. **Route progress + profile writes through `SyncQueue`** as markers, and flip
   `sync_reliability_v1` on.

## Review rounds

**Rounds 1-3 — on a design that was WITHDRAWN.** Context-blind, all `not_converged`
(6, 5, 5 blocking). Round 2 found three defects introduced by round 1's own hardening.
The design was withdrawn rather than reviewed a fourth time: it was compensating for a
lost write instead of preventing one, and it was re-deriving a who-owns-this-field rule
that the push path had already answered in a comment. See
`docs/superpowers/specs/2026-08-30-progress-write-durability-design.md` §8.

**Round 4 — on the implementation plan.** `not_converged`, 9 blocking. Four Dart API
errors (constructing a `sealed` class; an `import` in a `part of` file; a `static` getter
reading an instance field; `Ok`/`Err` where the codebase uses `Result.ok`/`Result.err`),
a non-existent goal token in five fixtures, and a task order that made three tasks
uncommittable because the commit-msg gate requires the diagnose-doc to exist first.

**Round 5 — on the implemented CODE**, after `flutter analyze` and the full suite were
green. `not_converged`, 5 blocking + 13 non-blocking. All 18 fixed. The core merge
post-pass was attacked hardest and verified sound; every defect was in what had been
built around it.

**B-pass** — fresh context-blind Sonnet, 4 findings, 0 false alarms, all fixed.
`docs/reviews/375e3a351e7b-review.md`.

## Ground truth verified

- All 17 live `user_progress` rows queried on `dedsavbjuwgarrhphgnl`. Only two at
  `current_phase >= 2`; **both are QA accounts**. No heal — `scheduled_workouts.week_number`
  holds only 1..4, so no phase discriminator exists and any heal value would be invented.
  Terminal state `verified_clean` (founder decision 2026-08-30).
- The lost write is **not theoretical**: `sync_user_progress_retry_dropped` fired 8 times
  across 3 users in the 30-day `client_errors` window.
- `weeklyFullSync` is misnamed — the interval is ONE DAY — so a lost write already
  self-heals daily. That is why the outbox is scoped to the two surfaces that merge cloud
  back into Hive rather than all ~30 fire-and-forget sync sites.
- Write volume measured live: ~5-10 user-generated writes per user per active day. The
  batch is justified by correctness alone, not cost.

## Founder decisions taken during review

- **Flip `sync_reliability_v1` in this batch** rather than shipping dark. Consequently this
  does NOT claim §4.12.4's ship-dark tier — a flag-flip commit takes the full ×2.
- **Outbox scope = progress + profile only.** The other surfaces are additive-by-id,
  completion-preserving, or derived and recomputed daily.
- **Honour the founder-locked no-silent-backfill decision** at
  `body_fat_default_healer.dart:28`. This is why the recompute is gated on
  `derivedTargetInputsChanged` rather than running on every restore: the healer clears
  cloud then local, so the merge sees no change and nothing recomputes. The lock is
  honoured structurally, not by a special case.
- **No data heal** (see above).

## Filed rather than folded in — terminal records, not deferrals

- **OI-151** — telemetry outweighs user data 1.7:1; `restore_op_done` is 64% of it and
  scales to ~240k rows/day at 10k DAU. Bounded today at ~1.2% of the 2000/user/day cap.
- **OI-152** — eight call sites fire `syncX()` + `pushSnapshot()` back to back.
- **`check_sot_registry_parity.dart`'s dotted-path weakness** (B-pass F3): `_extractSymbol`
  takes the FIRST identifier of `Class.method`, so every such citation is validated against
  the class, not the method. Recorded in the review; not patched inside a platform-tier
  batch it does not belong to.

## Verification at time of writing

- Full suite: **5192 passed, 7 skipped, 0 failed**, runner exit 0.
- `flutter analyze` repo-wide: **0 warnings, 0 errors**.
- `sh scripts/pre-commit.sh`: all gates PASS.
- Diagnose-doc `321062` passes `validate_diagnose_doc.dart`.
- Mutation-proven on every protective leg; two mutations were ABSORBED on first run and
  both are recorded in the diagnose-doc's `mutation_evidence` rather than quietly re-run.
