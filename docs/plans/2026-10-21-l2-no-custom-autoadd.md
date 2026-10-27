# Batch 0a — the plan generator never auto-adds custom exercises (L2 removal)

**Date:** 2026-10-21 · **Branch:** `l2-no-custom-autoadd` · **Tier:** L (plan engine) · **Execution mode:** inline.
**Review:** rounds 1 and 2 (context-blind, verified against code) both confirmed this part complete and correct; the
material findings of both rounds were all in the repair half, which §4.12.1 splits out to
`docs/plans/2026-10-21-l2-custom-repair.md` (Batch 0b, separate branch after this merges).

## Symptom (founder, web app, 2026-10-21)

Today's "Upper push + core" workout for upendraprasad19 lists **14 exercises / 56 sets**: 8 library picks + 6 of the
founder's own custom exercises (tuck planche, Barbell Planche Hollow Press, Cable Pull Down, L Sit, Elbow Lever, Single
Leg Back Lever). Cloud `user_progress.plan_json.schedules` (Phase 4, plan_start 2026-10-12): every push day 8 + 6
customs (56–66 sets), pull 8 + 2, legs 8 + 1. Every Phase-3 day before 2026-10-12 had 8; the customs were created
2026-09-14 → 2026-10-02, after Phase 3 was generated. Only this user has customs inside a plan.

## Root cause — writer + reader by file:line

- **Writer:** `lib/shared/repositories/plan_engine/exercise_selector.dart`
  - `:585-587` `customs = phase >= 2 ? _eligibleCustomExercises(exerciseRepo) : []`
  - `:633-650` post-pass gate `phase >= 2 && (demoted.isNotEmpty || customs.isNotEmpty)`; call sites `:634`, `:641`
  - `:906-932` **L2** in `_applyHistoryAdjustments`: every custom with non-empty `primary_muscles` whose muscles
    SUBSTRING-match any slot `targetMuscle`/`subFocus` of the day is appended (`_buildCustomExercise`). No cap, no
    skill/level/pattern filter. Added 2026-05-31.
  - `:954-967` `_eligibleCustomExercises` (the only other `getCustomExercises(` site in the file besides `:739`).
- **Readers:** `PopulatedDay.exercisesA/B` → `PeriodizationEngine` (4×10) → `generateAndSchedule`
  (`workout_schedule_read_service.dart:~280`) → `schedule_<date>` rows (`WorkoutWriteService.upsertScheduled`,
  `workout_write_service.dart:629`) → Train tab (`train_provider.dart:884`) + active workout → cloud
  `user_progress.plan_json` (`pushWorkoutPlanForSyncDomain`, `sync_workout.dart:2939`).
- No other path auto-adds customs (round 1: every other `getCustomExercises(` caller in lib/ is an explicit user picker;
  hotel / regenerate planners go through the generator; no server-side generation).

## Founder decision (2026-10-21, chat)

"never auto-add customs". Customs reach a plan only through an explicit user/coach action (swap sheet, add-exercise
picker, template builder, coach `swapExercise`). L6 (demote swapped-out lifts) in the same function STAYS.

## §4.6 tiering decision (waiver)

Plan-engine change ⇒ §4.6 would default to a kill switch. Waived, recorded here and in the diagnose doc: the removed
path IS the defect; a kill switch would keep a known-bad path reachable, and §4.6 step 4 requires deleting the old
path anyway. Revert = `git revert` of the merge. Full ×2 review + B-pass apply (tier L).

## Bug history (§4.1.5)

Related, not a recurrence: **e7b2d4** (2026-09-17, customs invisible in the swap picker). Its fix made the creation
sheet store `primary_muscles`, which `custom_exercise_writer_to_reader_test.dart:105-110` notes "re-arms the
plan-generator supplement path" — i.e. made customs ELIGIBLE for L2. L2 itself was always unbounded.

## Changes

1. `exercise_selector.dart`: delete the `customs` local, the L2 block, the `customs` parameter of
   `_applyHistoryAdjustments` + both call-site arguments, and `_eligibleCustomExercises`. Gate →
   `phase >= 2 && demoted.isNotEmpty`. KEEP `_buildCustomExercise` + `_muscleTokens` (buildPinnedDays `:772`, `:992`).
   Rewrite comments at `:575-581`, `:632`, `:833-853` (L6 only) + a one-line note where L2 was.
2. `scripts/exercise_seam_lib.dart:59` — `exercise_selector.dart` SeamEntry 16 → 15 (round 2 recounted 16 with comments
   stripped; `:960` goes, `:739` stays); reason text updated.
3. Docs / comments (wording only, never loosen an assertion): `plan_engine/CLAUDE.md:~103` (+ invariant "the generator
   never auto-adds custom exercises"; then `check_context_artifact_budget.dart`, `--record` if intended);
   `docs/architecture/plan-engine-detail.md:~284, ~305`; `docs/sot_registry.yaml:~10851, ~11478, ~11495`;
   `create_custom_exercise_sheet.dart:492-496`; `plan_engine_flags.dart:160`;
   `custom_duration_key_convergence_test.dart:9` (remaining reader = buildPinnedDays → `_buildCustomExercise`);
   `equipment_exclusion_filter_behavioral_test.dart:8, 163`; `plateau_rotation_behavioral_test.dart:10`;
   `custom_exercise_writer_to_reader_test.dart:106-107`; `custom_picker_capability_wiring_test.dart:92`.
   `plan_generator.dart:133` is NOT edited (root rule 14).
4. Test `test/contracts/l2_no_custom_autoadd_behavioral_test.dart` (harness from
   `repeat_phase_pinned_selection_behavioral_test.dart:280-300`): a custom with `primary_muscles: ['Chest']` →
   a Phase ≥ 2 plan has it on no day (A or B); Phase 1 clean too; L6 still swaps a demoted lift (seed a `swapped_from`
   schedule row within 84 days, `training_history_analyzer.dart:311-345`). **Mutation:** re-add the L2 append →
   reddens (count recorded in the diagnose doc; `grep -c` confirms the mutation applied).
5. Diagnose doc `docs/diagnoses/2026-10-21-l2-custom-autoappend-<id>.md` (FULL template, `related_bugs: [e7b2d4]`,
   `touched_layers_checked` incl. tier 4 cloud query), validated by `scripts/validate_diagnose_doc.dart`. It states that
   existing plans are repaired by Batch 0b.

## Verification
`flutter analyze lib/`; the new test + every test that greps `exercise_selector.dart`
(`bodyweight_capability_leak`, `custom_duration_key_convergence`, `equipment_exclusion_filter_behavioral`,
`injury_safe_omission_production`, `plan_generator_targetcount_cascade`, `universal_pool_mirror`,
`repeat_phase_pinned_selection_behavioral`, `plateau_rotation_behavioral`) + `test/scripts/exercise_seam_lib_test.dart`;
full gate loop (§4.12.8); `/code-review` B-pass before merge.
