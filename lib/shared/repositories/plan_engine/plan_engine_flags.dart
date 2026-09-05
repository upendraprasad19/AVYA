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

  /// Free-tier "Hold the Line" week materialization (`holdWeek` replaces
  /// `redoWeek4`). **Default OFF (ship dark, §4.6)** — it materializes NEW
  /// week-5+ schedule rows + extends `plan_end`, so it is NOT the safe
  /// direction: it ships inert and is flipped ON only after the display slices
  /// (un-clamp / chip strip / header / roadmap / entry card) land + APK
  /// verification. When OFF, the plan-expired triggers run the verbatim
  /// `redoWeek4`. Set `configBox['enable_hold_weeks'] = true` to enable.
  static bool get holdWeeksEnabled {
    try {
      return HiveService.instance.configBox.get('enable_hold_weeks') == true;
    } catch (_) {
      return false; // no Hive (pure unit test) → safe default: OFF (redoWeek4)
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

  /// ⑥ slice B1 equipment item-level EXCLUSION filter.
  ///
  /// **FLIPPED ON 2026-08-05** (`deps-board-equipment`). Was ship-dark DEFAULT
  /// OFF behind `enable_equipment_exclusions`; the kill-switch is now
  /// `disable_equipment_exclusions` and the default is ON, matching the four
  /// sibling default-ON flags in this file (`disable_injury_universal_filter`,
  /// `disable_warmup_injury_filter`, `disable_detraining_decay`,
  /// `disable_cardio_goal_default`).
  ///
  /// **Why it was flipped:** the *collection* half shipped lit while the
  /// *consumption* half stayed dark. `edit_profile_screen.dart:1686` already
  /// writes `equipment_exclusions` and `sync_profile.dart:200` already syncs it,
  /// so a user could tell the app they own no barbell, watch it save, and still
  /// be prescribed barbell lifts. That is a live broken promise, not a dormant
  /// feature — which is what separated this flag from the other twelve in OI-53.
  ///
  /// ⚠ **This flag gates TWO behaviours; a reviewer must weigh both.**
  /// 1. `plan_generator.dart:140-142` — the exclusion set is sourced from the
  ///    profile instead of `{}`, so every `.isNotEmpty`-guarded drop (queryV4
  ///    att1-4 / att5 pool / L2 custom-append / L6 swap) becomes live. Affects
  ///    only users who actually set an exclusion.
  /// 2. `plan_generator.dart:298-308` — ⑥ C2's `hasGymOverride` stops being
  ///    `null`. Per diagnose b7a4e2 the fallback predicate it defers to was
  ///    **always false on the generated path**, so this ACTIVATES the gym-cardio
  ///    warmup/finisher pools (Treadmill/Bike) for **every gym-tier user,
  ///    including those with no exclusions set**. This is the wider half of the
  ///    blast radius and the reason the flip is not "byte-identical for users
  ///    who ignore the feature."
  ///
  /// Set `configBox['disable_equipment_exclusions'] = true` to revert BOTH
  /// behaviours to the verbatim pre-flip path (§4.6 requires the old path stay
  /// reachable).
  static bool get equipmentExclusionsEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_equipment_exclusions') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: exclusions ON
    }
  }

  /// ⑥ Batch 6 (W2.3) readiness check-in + session adjustment + trends.
  /// LIVE since 2026-09-01 (OI-53 flag 1 of 12). Kill-switch
  /// `configBox['disable_readiness'] = true` restores the pre-flip path: no
  /// sheet, no `readiness_*` read/write, no session adjustment.
  ///
  /// ⚠ The kill-switch stops new COLLECTION; it does not retroactively hide
  /// readiness history already rendered by the Reports trend card, which reads
  /// `readiness_*` rows directly with no flag gate. The CODE path reverts
  /// verbatim (§4.6's actual requirement); the DATA persists.
  static bool get readinessEnabled {
    try {
      return HiveService.instance.configBox.get('disable_readiness') != true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }

  /// ⑥ Batch 7-A (W3.2 phase arc): the Train-screen strip showing the current
  /// phase's periodization wave with this week highlighted, sourced from the
  /// already-materialized `week_character` (no engine change — pure read-only
  /// DISPLAY). LIVE since 2026-09-05 (OI-53 flag 3 of 12).
  /// Kill-switch `configBox['disable_phase_arc'] = true`.
  ///
  /// ⚠ The wave vocabulary is FIVE tokens, not the four this comment used to
  /// name: `baseline | overreach | peak | deload`, plus **`working`**, written
  /// by `deload_evaluator.dart:231` when a deload is lifted. A sixth state, the
  /// empty string, is synthesised by the READER
  /// (`workout_schedule_read_service.dart:1229`) for a malformed entry.
  /// `PhaseArcStrip` maps all five and floors the empty case.
  ///
  /// ⚠ There is NO release-build kill-switch: every flag toggle lives in the
  /// `kDebugMode`-gated dev panel and there is no RemoteConfig, so reverting
  /// means a code revert plus a store round-trip (OI-95, accepted risk across
  /// all OI-53 flags).
  static bool get phaseArcEnabled {
    try {
      return HiveService.instance.configBox.get('disable_phase_arc') != true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }

  /// ⑥ Batch 10 (W3.1 explainability): the week-4 deload "why" line rendered
  /// INSIDE `PhaseArcStrip`. LIVE since 2026-09-06 (OI-53 flag 4 of 12).
  /// Kill-switch `configBox['disable_deload_reason_line'] = true`.
  ///
  /// Split out of the phase-arc flip on 2026-09-05 (founder decision) because the
  /// line carried a stale-reason defect: `deload_reason_phase_<P>` is never
  /// deleted anywhere in `lib/`, while TWO plan-mutating paths re-stamp week 4
  /// back to `deload` after a lift — `generateAndScheduleFromDate`
  /// (`workout_schedule_read_service.dart:388`, live caller
  /// `edit_profile_screen.dart:2029`) and the AI-coach regen
  /// (`regenerate_plan_planner.dart:294`) — while `deload_evaluator.dart:79`'s
  /// idempotency flag blocks any re-evaluation from correcting the string. The
  /// strip would have rendered a `DELOAD` node above "Working week — you've
  /// recovered", permanently.
  ///
  /// FIXED in Unit B (diagnose `c5a8f3`) at the READER rather than by adding a
  /// deleter to each path: the eval now stamps the outcome `week_character`
  /// beside the prose, and `currentDeloadReason()` returns the text only while
  /// that character still equals week 4's in the blob the strip renders. Any
  /// mismatch, and every legacy bare-String value, → no line, which is
  /// byte-identical to the pre-flip state.
  ///
  /// ⚠ There is NO release-build kill-switch (OI-95) — see [phaseArcEnabled].
  static bool get deloadReasonLineEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_deload_reason_line') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }

  /// ⑥ Batch 7-B (W2.4 triggered deload): the whole deload feature flag. 7-B-1
  /// gates the GENERATION-STASH of peak-equivalent `working_sets`/`working_reps`
  /// on the deload week (so a later lifted deload is lossless — the deload cut
  /// is non-invertible). LIVE since 2026-09-01 (OI-53 flag 2 of 12).
  /// Kill-switch `configBox['disable_triggered_deload'] = true`.
  ///
  /// ⚠ Flipped in the SAME commit as `disable_readiness`, and the coupling is
  /// MECHANICAL, not convenience: `plan_generator.dart` gates `stashWorkingBase`
  /// on THIS flag at GENERATION time, so a plan generated while it was OFF
  /// carries no stash and can never be lifted (`deload_evaluator.dart` guards on
  /// stash presence). The eval also early-returns without readiness.
  ///
  /// ⚠ Killing this switch does NOT revert a lift already applied — the week
  /// stays `week_character: 'working'`. Corrected 2026-09-05: this used to add
  /// "and only the reason strip disappears", which is no longer true — the
  /// reason line has its own flag, [deloadReasonLineEnabled], DEFAULT OFF, so
  /// killing this switch changes nothing visible until that one flips too. The
  /// lifted week still renders as `WORKING` on the phase-arc strip either way.
  static bool get triggeredDeloadEnabled {
    try {
      return HiveService.instance.configBox.get('disable_triggered_deload') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }

  /// ⑧ Batch 8 (W2.5 adherence gate): the "repeat the last phase's content"
  /// advance. When ON, a phase advance that passes `repeatContent:true` PINS
  /// the just-finished
  /// phase's exercises into the new phase (via generateV4's pinnedExercisesByDay)
  /// instead of a fresh selection, gated on the prior phase's
  /// {planGoal, equipment, daysPerWeek, effectiveExp} being UNCHANGED. Ship-dark
  /// DEFAULT OFF (§4.6 — changes generated content + adds a `last_phase_profile`
  /// config write). OFF → no extraction, no gate, no config write, `repeatContent`
  /// inert → byte-identical to today. Set `configBox['enable_adherence_gate'] =
  /// true` to enable.
  ///
  /// ⚠ Corrected 2026-08-05: this comment used to say the `repeatContent:true`
  /// caller was "not yet wired". It IS wired — `pro_phase_advance.dart:167-169`
  /// computes it as `adherenceGateEnabled && currentPhaseCompletionRate() <
  /// AppConstants.phaseUnlockCompletionRate` and passes it through
  /// `autoGenerateNextPhaseIfNeeded`. The `&&` short-circuits, so with the flag
  /// OFF the completion-rate scan never runs and the path stays byte-identical
  /// — which is why the stale note survived: flag-OFF behaviour is the same
  /// either way, so nothing failed to make it visible. Same phantom-citation
  /// class as the `check_writer_reader_drift.dart` gate `lib/CLAUDE.md` cited
  /// for months without it ever existing: a doc claiming LESS coverage than
  /// reality is quieter than one claiming more, but it still mis-scopes the
  /// next person's plan.
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

  /// ⑦ OI-89: HARD equipment capability floor, scoped to the `bodyweight` tier.
  /// When ON, every seam that can emit an exercise drops candidates the user
  /// cannot physically perform, keyed on `equipment_needed` (NOT
  /// `equipment_tier`, which the SoT registry documents as ADD-only with
  /// "over-tags tolerated" — imprecise in exactly the unsafe direction).
  ///
  /// **FLIPPED ON 2026-08-28** (`oi89-bodyweight-floor`). Was ship-dark DEFAULT
  /// OFF behind `enable_equipment_capability_floor`; the kill-switch is now
  /// `disable_equipment_capability_floor` and the default is ON, matching the
  /// five sibling default-ON flags in this file (`disable_equipment_exclusions`,
  /// `disable_injury_universal_filter`, `disable_warmup_injury_filter`,
  /// `disable_detraining_decay`, `disable_cardio_goal_default`).
  ///
  /// **Why it is flipped in the same batch that built it:** the collection half
  /// was already lit and the library correction lands here too, so leaving this
  /// dark would ship a library that correctly says Chin Up needs a pull-up bar
  /// alongside a generator that is not reading the field. `equipment_tier` alone
  /// still leaks — measured with this flag OFF against the CORRECTED library,
  /// the bodyweight tier carried 468 equipment violations, because the attempt-5
  /// universal pool bypasses queryV4 entirely and picks by NAME. The tier fix and
  /// the capability fix each close a hole the other cannot reach.
  ///
  /// **Fail-OPEN on the way in, fail-CLOSED on the way through:**
  /// `resolveCapability` returns null (do not enforce) on a Hive error, an
  /// unknown tier, or any tier above `bodyweight` — so a storage fault can never
  /// empty a plan. `EquipmentCapability.canPerform` then fails CLOSED on an
  /// unreadable requirement, which is why warm-up and finisher moves had to have
  /// `equipmentNeeded` POPULATED before this could be switched on at all.
  ///
  /// Kill switch: `configBox['disable_equipment_capability_floor'] = true`.
  static bool get equipmentCapabilityFloorEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_equipment_capability_floor') !=
          true;
    } catch (_) {
      // No Hive (pure unit test). The safe default is now ON: the floor only
      // ever REMOVES an exercise the user cannot perform, and every removal site
      // has a documented substitute path, so defaulting it off would be the
      // riskier direction once the library depends on it.
      return true;
    }
  }

  /// ①.1d (Batch 11-C): curated per-injury safe-substitute PREFERENCE. When ON,
  /// `_cascadeFill` re-ranks the already-safe (post-injury-filter), same-pattern
  /// candidate list to PREFER a curated `InjurySubstitutes` sub over queryV4's
  /// generic sort. Ship-dark DEFAULT OFF → verbatim `candidates.first` at every
  /// attempt (byte-identical). It re-ranks the POST-filter list so it can NEVER
  /// surface a contraindicated exercise; a PREFERENCE (falls through when no
  /// curated sub is a candidate). Set `configBox['enable_injury_substitute_pref']
  /// = true` to enable.
  static bool get injurySubstitutePreferenceEnabled {
    try {
      return HiveService.instance.configBox
              .get('enable_injury_substitute_pref') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// W3.4 (Batch 11-B): cross-phase VARIETY. When ON, a fresh phase advance passes
  /// the PREVIOUS phase's per-slot picks as `avoidNames` to `_cascadeFill`, and the
  /// pure `_selectCandidate` (`_preferNovel` inner) prefers a same-pattern SIBLING
  /// not used last phase (bounded — never forces a wrong pattern / empties a slot).
  /// Read at the SERVICE layer to gate the `previousPhaseNamesByDay()` read; OFF →
  /// not called → avoidNames empty everywhere → `candidates.first` (byte-identical).
  /// Set `configBox['enable_cross_phase_variety'] = true` to enable.
  static bool get crossPhaseVarietyEnabled {
    try {
      return HiveService.instance.configBox
              .get('enable_cross_phase_variety') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// W3.5 (Batch 12-A) plateau escalation rung-2 (+sets), PRO. When ON, at a
  /// genuine FRESH phase advance a plateaued major group (a COMPOUND lift with flat
  /// e1RM across ≥3 sessions spanning ≥28d) that is NOT already titration-bumped and
  /// NOT under persistent readiness fatigue gains +1 weekly set — merged into the
  /// W2.7 titration deltas so ONE clamped applyToWeeks pass applies both
  /// (`PlateauScan.mergePlateauSetDeltas`, `putIfAbsent` → no double-bump / an
  /// existing −1 wins). Ship-dark DEFAULT OFF (§4.6 — changes prescribed volume) →
  /// merge returns the input map unchanged → applyToWeeks identity → byte-identical.
  /// Presupposes `enable_readiness` ON (the fatigue gate needs data; `plateauedGroups`
  /// self-gates on `readinessEnabled`, mirroring DeloadEvaluator). Set
  /// `configBox['enable_plateau_escalation'] = true` to enable.
  static bool get plateauEscalationEnabled {
    try {
      return HiveService.instance.configBox
              .get('enable_plateau_escalation') ==
          true;
    } catch (_) {
      return false;
    }
  }
}
