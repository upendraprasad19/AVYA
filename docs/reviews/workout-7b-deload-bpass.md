---
review: workout-7b-deload B-pass (7-B-1 generation-stash, ship-dark)
branch: workout-7b-deload
date: 2026-07-17
reviewer: context-blind adversarial subagent (B-pass, §4.3, platform)
blast_radius: platform
verdict: accepted
---

# B-pass — Batch 7-B-1 generation-stash (W2.4)

Context-blind adversarial review of the implemented diff (5 files + 1 new test) + a live run
(194 tests pass — the new behavioral test + full `plan_engine_v4` suite + equipment/physique/wu2/
phase-arc NO-OP tests; `flutter analyze` clean).

## Verdict: ACCEPTED — no P0/P1

6 points CONFIRMED with file:line evidence:
1. **N1 linchpin — the stash survives every post-periodization stage.** `copyWith` threads the fields
   with the preserve idiom (`models.dart:208-209` `workingSets: workingSets ?? this.workingSets`).
   Traced ALL 4 stages that run after periodization: superset pairer `copyWith(supersetGroup:)`
   (`superset_pairer.dart:56`) → preserved; sequencing `copyWith(warmupSet:)` (`sequencing_engine.dart:91`)
   → preserved; cardio finisher (`cardio_finisher.dart:52`) + warmup/cooldown (`warmup_cooldown.dart:215`)
   → `exercises` passthrough, untouched. No post-periodization stage reconstructs a main exercise via the
   `PlannedExercise(...)` constructor. The behavioral test's non-vacuous superset case passes.
2. **Peak** — `_applyWave(ex, 2, …)` on the SAME `ex` with matching isBeginner/isDeload/multiplier/
   archetype/day.intensity; the min-4 clamp applies for weekIdx 2 (`weekIdx != 3` true) + is skipped for
   the deload call/deload-phase; body-focus +1 replicated. Variant-agnostic (`ex`) → correct for both
   non-6-day (wk4 = variant B) + 6-day (variant A).
3. **working_reps** — `_applyWave` emits `reps: '$reps'` (single-int String) on the rep path, `ex.reps`
   (non-null String) on the non-rep path; the range lives only in `repRange`. No malformed-swap risk.
4. **Flag-OFF byte-identical** — `stashWorkingBase` defaults false; the `weekIdx==3 && stashWorkingBase`
   block is skipped; `toMap` omit-when-null drops the keys. Whole-Phase NO-OP tests pass.
5. **Purity / layering** — periodization imports only `dart:math` + `models.dart` (no Hive/flag); the flag
   is read in `generateV4` (`plan_generator.dart:187`), matching equipment_exclusions/physique_focus.
6. **Else** — `weekIdx==3` is the deload week; `working_sets < deload` is impossible (peak ≥ deload ∀
   base≥2, +1 body-focus symmetric); SoT `deload_working_base_stash` present with a behavioral_test_path;
   restore-durable (`mergeScheduleEntry` whole-map `Map.from` copy; `WorkoutDay.toMap → e.toMap()` carries the keys).

## Findings (P3, non-blocking)
- **F1 (test completeness):** the test covered 4-day / rep-based / phase-1. ADDED a 6-day (variant-A wk4)
  case (verifies the variant-agnostic path the B-pass flagged). The deload-phase + non-rep paths hold
  `peak ≥ deload` analytically (min-4 skipped on BOTH calls; non-rep sets `reps = ex.reps`).
- **F2 (7-B-2 handoff — NOT a 7-B-1 defect):** the stash captures sets+reps ONLY; the deload week's
  `weight_cue` ("Light week…"), `overload_notes`, and `week_character` are NOT stashed → 7-B-2's un-deload
  MUST also correct those (tracked on the 7-B-2 plan; Reviewer A Item 3).
- **F3 (process):** this bpass record — written now, before the `--no-ff` merge.

Additive, write-only, ship-dark stash; flag OFF is byte-identical (proven by 194 passing tests incl. the
whole-Phase NO-OP). The one genuinely risky seam (the superset pairer's `copyWith`) is correctly threaded
and non-vacuously tested end-to-end through the real `generateV4` pipeline. No open issues.
