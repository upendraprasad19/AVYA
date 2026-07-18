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

  /// ⑥ Batch 6 (W2.3) readiness check-in + session adjustment + PRO trends.
  /// Ship-dark DEFAULT OFF (§4.6 — a new active-workout sheet + a session load/
  /// set adjustment). When OFF: no sheet shown, no `readiness_*` read/write, no
  /// session adjustment → byte-identical to today. Home is a domain stretch
  /// (readiness is active-workout/health, not the generator) but mirrors ⑦b's
  /// `sessionDetrainingCutEnabled` precedent. Set
  /// `configBox['enable_readiness'] = true` to enable.
  static bool get readinessEnabled {
    try {
      return HiveService.instance.configBox.get('enable_readiness') == true;
    } catch (_) {
      return false; // no Hive (pure unit test) → safe default: OFF
    }
  }

  /// ⑥ Batch 7-A (W3.2 phase arc): the Train-screen strip showing the current
  /// phase's periodization wave (baseline→overreach→peak→deload) with this week
  /// highlighted, sourced from the already-materialized `week_character` (no engine
  /// change — pure read-only DISPLAY). Ship-dark DEFAULT OFF (§4.6 — a new visible
  /// UI element, verify on-device before it ships lit). OFF → the strip renders
  /// nothing → byte-identical. Set `configBox['enable_phase_arc'] = true` to enable.
  static bool get phaseArcEnabled {
    try {
      return HiveService.instance.configBox.get('enable_phase_arc') == true;
    } catch (_) {
      return false;
    }
  }

  /// ⑥ Batch 7-B (W2.4 triggered deload): the whole deload feature flag. 7-B-1
  /// gates the GENERATION-STASH of peak-equivalent `working_sets`/`working_reps` on
  /// the deload week (so a later lifted deload is lossless — the deload cut is
  /// non-invertible). Ship-dark DEFAULT OFF (§4.6 — a plan-engine change). OFF → no
  /// stash → byte-identical. NOTE: the 7-B-2 eval/trigger that CONSUMES the stash
  /// additionally requires readiness ON (`&& readinessEnabled` at the eval site —
  /// flag-ordering safety; the readiness clause is a keep-deload signal, so running
  /// the eval without it biases toward LIFTING). Set
  /// `configBox['enable_triggered_deload'] = true` to enable.
  static bool get triggeredDeloadEnabled {
    try {
      return HiveService.instance.configBox.get('enable_triggered_deload') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// ⑧ Batch 8 (W2.5 adherence gate): the "repeat the last phase's content"
  /// advance. When ON, a phase advance that passes `repeatContent:true`
  /// (UNIT 3's low-adherence choice, not yet wired) PINS the just-finished
  /// phase's exercises into the new phase (via generateV4's pinnedExercisesByDay)
  /// instead of a fresh selection, gated on the prior phase's
  /// {planGoal, equipment, daysPerWeek, effectiveExp} being UNCHANGED. Ship-dark
  /// DEFAULT OFF (§4.6 — changes generated content + adds a `last_phase_profile`
  /// config write). OFF → no extraction, no gate, no config write, `repeatContent`
  /// inert → byte-identical to today. Set `configBox['enable_adherence_gate'] =
  /// true` to enable.
  static bool get adherenceGateEnabled {
    try {
      return HiveService.instance.configBox.get('enable_adherence_gate') == true;
    } catch (_) {
      return false;
    }
  }

  /// W2.7 (Batch 9 volume titration): phase-boundary per-major-group ±1 weekly-set
  /// adjustment from the phase-N e1RM trend (+ readiness recovery evidence for the
  /// +1 direction), clamped [MEV,MRV]. Ship-dark DEFAULT OFF (§4.6 — changes
  /// prescribed volume). Applied ONLY when the caller opts in
  /// (`applyVolumeTitration`, passed `pins == null` by the two fresh-advance
  /// callers) AND phase>=2. Flag OFF / intent false / phase<2 → resolveDeltas {}
  /// → applyToWeeks identity → byte-identical. Set
  /// `configBox['enable_volume_titration'] = true` to enable.
  static bool get volumeTitrationEnabled {
    try {
      return HiveService.instance.configBox.get('enable_volume_titration') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// W3.3 (Batch 11-A ID-keyed history): the READER switch. When ON,
  /// `ProgressionResolver` matches a logged `exlog_*` row to a plan exercise by
  /// the library `exercise_id` — INCLUSIVE with name (id-matched ∪ name-matched,
  /// the more-recent of the two, no split-history loss) — instead of name-only.
  /// Ship-dark DEFAULT OFF → name-only (byte-identical). The WRITE side (stamping
  /// `exercise_id` on new exlog rows) is unflagged-additive; only this READ switch
  /// is gated. The cloud sync onConflict key stays name-derived regardless. Set
  /// `configBox['enable_exercise_id_history'] = true` to enable.
  static bool get exerciseIdHistoryEnabled {
    try {
      return HiveService.instance.configBox.get('enable_exercise_id_history') ==
          true;
    } catch (_) {
      return false;
    }
  }
}
