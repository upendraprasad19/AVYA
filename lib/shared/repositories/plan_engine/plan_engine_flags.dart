import 'package:icanbefitter/core/services/hive_service.dart';

/// Runtime kill-switches for the plan engine (§4.6 feature-flag protocol).
///
/// Read from the local `configBox`; each defaults to the SAFE (feature-ON)
/// behavior when the flag is unset OR Hive is unavailable (a pure unit test that
/// never opened a box). The engine stays testable — a test can force a flag by
/// putting the key in `configBox`, or rely on the safe default.
class PlanEngineFlags {
  PlanEngineFlags._();

  /// U2 universal-pool injury filter. Default ON (attempt-5 pool picks are
  /// injury-filtered like attempts 1-4). Set
  /// `configBox['disable_injury_universal_filter'] = true` to revert to the
  /// verbatim pre-U2 behavior (the pool bypasses the injury filter).
  static bool get injuryUniversalFilterEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_injury_universal_filter') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: filter ON
    }
  }

  /// U3 warmup/cooldown injury filter (Ship 2). Default ON (contraindicated
  /// warmup/cooldown/cardio moves are dropped for an injured user). Set
  /// `configBox['disable_warmup_injury_filter'] = true` to revert to the
  /// verbatim pre-U3 behavior (warmup/cooldown built from the raw dayType lists).
  static bool get warmupInjuryFilterEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_warmup_injury_filter') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: filter ON
    }
  }

  /// W2.1 (Batch 3b-ii) graded double progression in ProgressionResolver.
  /// **Default OFF (ship dark, §4.6)** — unlike the reduce-only ⑦a decay, W2.1
  /// can INCREASE prescribed load (progress at the top of the rep-range;
  /// beginner auto-linear), so it is NOT the safe direction: it ships inert and
  /// is flipped ON after APK verification. When OFF, resolve() uses the verbatim
  /// fixed-10/5 rule (+ independent ⑦a decay). Set
  /// `configBox['enable_graded_progression'] = true` to enable.
  static bool get gradedProgressionEnabled {
    try {
      return HiveService.instance.configBox.get('enable_graded_progression') ==
          true;
    } catch (_) {
      return false; // no Hive (pure unit test) → safe default: OFF (verbatim)
    }
  }

  /// ⑦(a) (Batch 3b-i) detraining WEIGHT decay in ProgressionResolver. Default
  /// ON: when a Phase-2+ user resumes after a training gap, their suggested
  /// starting weights are decayed by the gap (8–21d −7.5%, 22–35d −17.5%, >35d
  /// −50%) BEFORE the reps-rule. Reduce-only + Epley-capped (never over-loads).
  /// Set `configBox['disable_detraining_decay'] = true` to revert to the
  /// verbatim pre-⑦a weights (no gap decay).
  static bool get detrainingDecayEnabled {
    try {
      return HiveService.instance.configBox.get('disable_detraining_decay') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: decay ON
    }
  }

  /// ④ (Batch 3a) goal-aware cardio finisher default. Default ON: when no
  /// `cardioPreference` is stored (always, today — there is no preference UI),
  /// the finisher shape is keyed to the goal (lose_fat→hiit, general_fitness→
  /// cycling, recompose→jump_rope) instead of the blanket mildest mini-HIIT.
  /// Set `configBox['disable_cardio_goal_default'] = true` to revert to the
  /// verbatim pre-④ behavior (every cardio-goal user gets `hate_cardio`).
  static bool get cardioGoalDefaultEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_cardio_goal_default') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: goal-aware ON
    }
  }

  /// ⑦(b) session-time detraining resume cut. **Default OFF (ship dark, §4.6)** —
  /// like W2.1 (and unlike ⑦a's gen-time number) it changes the interactive
  /// active-workout UI (a resume banner + a reduced weight prefill + the overload
  /// indicator / "TRY:" hint), so it ships inert and is flipped ON after APK
  /// verification. When ON, `ActiveWorkoutNotifier.startWorkout` scales ONLY the
  /// last-logged-weight prefill by `detrainingFactorForGap(getDaysSinceLastWorkout())`
  /// for that session (never persisted; never the ⑦a-decayed prescription).
  /// Set `configBox['enable_session_detraining_cut'] = true` to enable.
  static bool get sessionDetrainingCutEnabled {
    try {
      return HiveService.instance.configBox
              .get('enable_session_detraining_cut') ==
          true;
    } catch (_) {
      return false; // no Hive (pure unit test) → safe default: OFF (no cut)
    }
  }

  /// ⑤ (Batch 4) physique-focus bring-up. **Default OFF (ship dark, §4.6)** — the
  /// user's self-selected `physique_focus` translates to muscle tokens that
  /// PeriodizationEngine turns into +1 set on matching exercises (INCREASES
  /// prescribed volume), so it ships inert and is flipped ON after APK
  /// verification. When OFF, the `effectiveBodyFocus` seam is byte-identical to
  /// today (explicit focus ignored; the auto weakMuscles() path is unchanged).
  /// Set `configBox['enable_physique_focus_bringup'] = true` to enable.
  static bool get physiqueFocusBringupEnabled {
    try {
      return HiveService.instance.configBox
              .get('enable_physique_focus_bringup') ==
          true;
    } catch (_) {
      return false; // no Hive (pure unit test) → safe default: OFF (no bring-up)
    }
  }

  /// ⑥ slice B1 equipment item-level EXCLUSION filter. **Default OFF (ship dark,
  /// §4.6)** — it SHRINKS the selectable pool (a user subtracts equipment they
  /// don't have), which changes exercise selection, so it ships inert and is
  /// flipped ON after APK verification (and once slice C's Customize UI writes
  /// the `equipment_exclusions` profile field it reads). When OFF, `generateV4`
  /// threads an EMPTY exclusions set → every `.isNotEmpty`-guarded drop in
  /// queryV4 / the att5 pool / the L2 custom-append is inert → byte-identical to
  /// today. Set `configBox['enable_equipment_exclusions'] = true` to enable.
  static bool get equipmentExclusionsEnabled {
    try {
      return HiveService.instance.configBox
              .get('enable_equipment_exclusions') ==
          true;
    } catch (_) {
      return false; // no Hive (pure unit test) → safe default: OFF (no exclusions)
    }
  }
}
