import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/phase_completion.dart';

/// Runtime kill-switches for the plan engine (§4.6 feature-flag protocol).
///
/// Read from the local `configBox`; each defaults to the SAFE (feature-ON)
/// behavior when the flag is unset OR Hive is unavailable (a pure unit test that
/// never opened a box). The engine stays testable — a test can force a flag by
/// putting the key in `configBox`, or rely on the safe default.
class PlanEngineFlags {
  PlanEngineFlags._();

  /// OI-454 kill-switch for the 6-day build_muscle Quads floor: the Legs B Quads compound slot
  /// AND the Glutes credit rule that goes with it (they are one change). Default ON. Set
  /// `configBox['disable_quad_legs_b'] = true` to restore the pre-OI-454 Legs B (its Glutes
  /// hip_isolation slot) and the full Glutes credit of a squat or a lunge, for plans generated
  /// from then on (a plan already stored is not rewritten).
  static bool get quadLegsBEnabled {
    try {
      return HiveService.instance.configBox.get('disable_quad_legs_b') != true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: the new Legs B
    }
  }

  /// Unit 1B-Q kill-switch (OI-475 L1): the B leg day of the 3-day (build_muscle, strength), 4-day and 5-day
  /// build_muscle splits carries a Quads / knee_dominant / compound slot at priority 1, second. Default ON. Set
  /// `configBox['disable_variant_b_quad'] = true` to restore the pre-1B-Q B lists verbatim, for plans generated
  /// from then on (a plan already stored is not rewritten). Read once per `SplitResolver.selectV4` call.
  static bool get variantBQuadEnabled {
    try {
      return HiveService.instance.configBox.get('disable_variant_b_quad') != true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: the new B lists
    }
  }

  /// Unit 1B-R kill-switch (OI-497, founder d25): for an equipped user the loaded move wins over the bodyweight one
  /// (`CoreListSelector.rankedPool`'s fit key in every non-core slot, and in phase 1 a bodyweight row gives way to the
  /// loaded row that will be picked when it matches the slot as well). Default ON. Set
  /// `configBox['disable_loaded_wins'] = true` to restore the pre-1B-R ranking verbatim, for plans generated from then
  /// on (a plan already stored is not rewritten). Read once per `_pickCoreList` call.
  static bool get loadedWinsEnabled {
    try {
      return HiveService.instance.configBox.get('disable_loaded_wins') != true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: the new ranking
    }
  }

  /// Unit 2A kill-switch (OI-486, founder d26-d29): the lead-first set allocator. A day's lead (the budgeted row the
  /// sequencer opens it with) is seated at the base sets when that fits, no other budgeted row ends more than 1 set
  /// above it (focus rows excepted, in the focus pass and in week 2), and each variant falls back to the capped world,
  /// then to main's, when the new one would leave a day under its count floor or a group at 0. Default ON. Set
  /// `configBox['disable_lead_first'] = true` to restore the pre-2A allocation and week-2 gains verbatim, for plans
  /// generated from then on (a plan already stored is not rewritten). Read once by `SessionSetAllocator.allocate` and
  /// once by `PeriodizationEngine.apply` per generation, each overridable by its `leadFirst` argument.
  static bool get leadFirstEnabled {
    try {
      return HiveService.instance.configBox.get('disable_lead_first') != true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: the lead-first allocator
    }
  }

  /// Unit 2B kill-switch (OI-452, founder d30-d33): the 3-exercise day floor. A day left under min(3, its reach) after
  /// pass A2 seats remaining slots at 2 sets past a group's weekly top (no excess limit, every phase, not bound by the
  /// clock; never past a session cap), named in `AllocationStats.floorSeats`. Default ON. Set
  /// `configBox['disable_day_floor'] = true` to restore the pre-2B allocation verbatim (in both Unit 2A paths), for
  /// plans generated from then on. Read once by `SessionSetAllocator.allocate` per call, overridable by its `dayFloor`
  /// argument.
  static bool get dayFloorEnabled {
    try {
      return HiveService.instance.configBox.get('disable_day_floor') != true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: the day floor
    }
  }

  /// Unit 2C kill-switch (OI-475 L2 / L3, founder d35-d46, plan `docs/plans/2026-11-14-generator-step2c-balanced-week.md`):
  /// the balanced week. Part 2C-a: build_muscle 3 / 4 / 5-day plans at 60+ minutes get the balanced splits (Upper /
  /// Lower / Full Body, Upper / Lower x2, Push / Pull / Legs / Upper / Lower + Core) and the credit rule (a quad-first
  /// row credits Quads, not Glutes); repeat pins refuse rows of the other split family. Default ON. Set
  /// `configBox['disable_balanced_week'] = true` to restore today's lists and credit verbatim, for plans generated from
  /// then on. Read by each callee (`SplitResolver.balancedWeekApplies`, so `selectV4`, `quadPrimaryCreditsGlutes` and
  /// `WorkoutScheduleReadService.foreignDayNamesFor`), overridable by their `balancedWeek` argument; `generateV4` has
  /// no `await`, so one generation never mixes the two.
  static bool get balancedWeekEnabled {
    try {
      return HiveService.instance.configBox.get('disable_balanced_week') != true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: the balanced week
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

  /// W2.1 (Batch 3b-ii) graded double progression in ProgressionResolver. LIVE
  /// since 2026-09-16 (OI-53 batch 2). Rep-range-aware banding (progress at the
  /// top of the rep-range / hold within / back off on 2 consecutive
  /// below-range sessions) replaces the old fixed-10/5 rule; beginner
  /// auto-linear window (<120d training age) always progresses. Independent of
  /// ⑦a's reduce-only decay. Kill-switch
  /// `configBox['disable_graded_progression'] = true` restores the verbatim
  /// fixed-10/5 rule.
  static bool get gradedProgressionEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_graded_progression') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
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

  /// ⑦(b) session-time detraining resume cut. LIVE since 2026-09-16 (OI-53
  /// batch 2). Like W2.1 (and unlike ⑦a's gen-time number) it changes the
  /// interactive active-workout UI (a resume banner + a reduced weight prefill
  /// + the overload indicator / "TRY:" hint): `ActiveWorkoutNotifier.startWorkout`
  /// scales ONLY the last-logged-weight prefill by
  /// `detrainingFactorForGap(getDaysSinceLastWorkout())` for that session
  /// (never persisted; never the ⑦a-decayed prescription). Kill-switch
  /// `configBox['disable_session_detraining_cut'] = true` restores the
  /// verbatim prefill (no cut).
  static bool get sessionDetrainingCutEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_session_detraining_cut') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }

  /// ⑤ (Batch 4) physique-focus bring-up. LIVE since 2026-09-16 (OI-53 batch 2).
  /// The user's self-selected `physique_focus` translates to muscle tokens that
  /// PeriodizationEngine turns into +1 set on matching exercises (INCREASES
  /// prescribed volume). Kill-switch
  /// `configBox['disable_physique_focus_bringup'] = true` restores the
  /// verbatim `effectiveBodyFocus` seam (explicit focus ignored; the auto
  /// weakMuscles() path unchanged).
  static bool get physiqueFocusBringupEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_physique_focus_bringup') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }

  /// ⑥ slice B1 equipment item-level EXCLUSION filter.
  ///
  /// **FLIPPED ON 2026-08-05** (`deps-board-equipment`). Was ship-dark DEFAULT
  /// OFF behind `enable_equipment_exclusions`; the kill-switch is now
  /// `disable_equipment_exclusions` and the default is ON, matching the four
  /// sibling default-ON flags in this file then (`disable_injury_universal_filter`, deleted with the universal pool by Unit 1B-F,
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
  ///    profile instead of `{}`, so every `.isNotEmpty`-guarded drop (the
  ///    core-list pool's hard filter, queryV4, repeat pins) becomes live. Affects
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
  /// stays `week_character: 'working'` and the hero label says `Baseline`.
  /// (The phase-arc strip and the week-4 "why" line, which used to sit on this
  /// switch's surface, were removed 2026-11-02, train-header-b2.)
  static bool get triggeredDeloadEnabled {
    try {
      return HiveService.instance.configBox.get('disable_triggered_deload') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }

  /// ⑧ Batch 8 (W2.5 adherence gate): the "repeat the last phase's content"
  /// advance. LIVE since 2026-09-16 (OI-53 batch 2). When ON, a phase advance
  /// that passes `repeatContent:true` PINS the just-finished phase's exercises
  /// into the new phase (via generateV4's pinnedExercisesByDay) instead of a
  /// fresh selection, gated on the prior phase's {planGoal, equipment,
  /// daysPerWeek, effectiveExp} being UNCHANGED (the G5 faithfulness gate).
  /// `repeatContent`/`repeat` is computed at TWO call sites —
  /// `pro_phase_advance.dart`'s automatic low-adherence repeat
  /// (`adherenceGateEnabled && currentPhaseCompletionRate() <
  /// AppConstants.phaseUnlockCompletionRate`) and `graduation_screen.dart`'s
  /// explicit choice sheet (`adherenceGateEnabled &&
  /// shouldOfferAdvanceChoice(...)`), but the two are NOT symmetric: the
  /// automatic path re-checks the flag a second, redundant time immediately
  /// before `_buildRepeatPins` (mutation-confirmed 2026-09-16: neutering
  /// either check alone is invisible to `pro_phase_advance_behavioral_test.dart`;
  /// only neutering both reddens it), while the choice-sheet path takes the
  /// user's already-made choice straight through with no re-check of its own
  /// — a kill-switch flip during the human-time gap between the sheet opening
  /// and the tap was NOT honored until a B-pass finding (2026-09-16) moved the
  /// check into `_buildRepeatPins` itself: the ONE method BOTH callers funnel
  /// through, so it is now checked exactly once for the choice-sheet path and
  /// redundantly for the automatic path, universally rather than
  /// caller-dependent (also mutation-confirmed: reverting that check reddens
  /// exactly the graduation-path kill-switch test). Kill-switch
  /// `configBox['disable_adherence_gate'] = true` restores the verbatim path:
  /// no extraction, no gate, no `last_phase_profile` write, `repeatContent`
  /// inert everywhere → byte-identical.
  static bool get adherenceGateEnabled {
    try {
      return HiveService.instance.configBox.get('disable_adherence_gate') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
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

  /// W3.3 (Batch 11-A ID-keyed history): the READER switch. LIVE since
  /// 2026-09-16 (OI-53). `ProgressionResolver` matches a logged `exlog_*` row to
  /// a plan exercise by the library `exercise_id` — INCLUSIVE with name
  /// (id-matched ∪ name-matched, the more-recent of the two, no split-history
  /// loss) — instead of name-only. The WRITE side (stamping `exercise_id` on new
  /// exlog rows) is unflagged-additive; only this READ switch was gated. The
  /// cloud sync onConflict key stays name-derived regardless.
  /// Kill-switch `configBox['disable_exercise_id_history'] = true` restores the
  /// pre-flip name-only match.
  ///
  /// ⚠ Forward-only, same as before the flip: turning this back OFF does not
  /// retro-strip an `exercise_id` already stamped on an exlog row written while
  /// it was ON — the CODE path reverts verbatim (§4.6's actual requirement); the
  /// DATA persists, harmlessly, since an OFF resolver never reads it.
  static bool get exerciseIdHistoryEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_exercise_id_history') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
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
  /// five sibling default-ON flags in this file then (`disable_equipment_exclusions`,
  /// `disable_injury_universal_filter` (deleted by Unit 1B-F), `disable_warmup_injury_filter`,
  /// `disable_detraining_decay`, `disable_cardio_goal_default`).
  ///
  /// **Why it is flipped in the same batch that built it:** the collection half
  /// was already lit and the library correction lands here too, so leaving this
  /// dark would ship a library that correctly says Chin Up needs a pull-up bar
  /// alongside a generator that is not reading the field. `equipment_tier` alone
  /// still leaks — measured with this flag OFF against the CORRECTED library,
  /// the bodyweight tier carried 468 equipment violations, because the attempt-5
  /// universal pool (deleted by Unit 1B-F) bypassed queryV4 entirely and picked by NAME. The tier fix and
  /// the capability fix each close a hole the other cannot reach.
  ///
  /// **Fail-OPEN on the way in, fail-CLOSED on the way through:**
  /// `resolveCapability` returns null (do not enforce) only when this flag is
  /// off or Hive is unreadable — so a storage fault can never empty a plan. It
  /// answers at EVERY tier since OI-144, and an unknown tier resolves to
  /// `bodyweight`. Since B1 Task 1 repeat pins check it too (they had been
  /// unchecked; only the diagnostic mirror did), as did the attempt-5 pool until
  /// Unit 1B-F deleted it. `EquipmentCapability.canPerform` then fails CLOSED on an
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

  /// ①.1d (Batch 11-C): curated per-injury safe-substitute PREFERENCE. LIVE
  /// since 2026-09-16 (OI-53). `_selectCandidate` (from `_pickCoreList` and the top-up) re-ranks the already-safe
  /// (post-injury-filter), same-pattern candidate list to PREFER a curated
  /// `InjurySubstitutes` sub over queryV4's generic sort. It re-ranks the
  /// POST-filter list so it can NEVER surface a contraindicated exercise; a
  /// PREFERENCE (falls through when no curated sub is a candidate).
  /// Kill-switch `configBox['disable_injury_substitute_pref'] = true` restores
  /// the verbatim `candidates.first` pick.
  static bool get injurySubstitutePreferenceEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_injury_substitute_pref') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }

  /// W3.4 (Batch 11-B): cross-phase VARIETY. LIVE since 2026-09-16 (OI-53). A
  /// fresh phase advance passes the PREVIOUS phase's per-slot picks as
  /// `avoidNames` to `_pickCoreList`, and the pure `_selectCandidate`
  /// (`_preferNovel` inner) prefers a same-pattern SIBLING not used last phase
  /// (bounded — never forces a wrong pattern / empties a slot). Read at the
  /// SERVICE layer to gate the `previousPhaseNamesByDay()` read.
  /// Kill-switch `configBox['disable_cross_phase_variety'] = true` restores the
  /// verbatim `candidates.first` pick (avoidNames empty everywhere).
  static bool get crossPhaseVarietyEnabled {
    try {
      return HiveService.instance.configBox
              .get('disable_cross_phase_variety') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
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

  /// OI-401 thin-day top-up. Default ON: a generated day left with fewer than 3
  /// exercises by injury filtering gets safe moves for its own muscles added
  /// (own pattern, then a neighbouring pattern, then core, then stop). Applies to
  /// injured users only; an uninjured plan is returned untouched.
  ///
  /// Unlike [warmupInjuryFilterEnabled] (and the universal pool's injury filter Unit 1B-F deleted), which
  /// DROP moves, this ADDS them; it ships ON anyway because the thin days are the
  /// live result of the v14 injury tags and every account is a testing account
  /// pre-launch (`docs/plans/2026-10-24-thin-day-topup.md`, Ruling R3). Kill-switch
  /// `configBox['disable_thin_day_topup'] = true` restores the verbatim thin day.
  /// ⚠ The flag is device-local; there is no remote rollback (OI-95), so reverting
  /// means shipping a build.
  static bool get thinDayTopupEnabled {
    try {
      return HiveService.instance.configBox.get('disable_thin_day_topup') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }

  /// OI-126: a `type: 'logged'` schedule row (AI-coach-only log, or a
  /// cloud-restore synthesize row) currently counts as a training day for the
  /// weekly streak (`isTrainingDayType`, exclusion-shaped) but as REST for
  /// phase completion (the direct input to the PRO-advance gate — the two
  /// are the SAME call site, not two), the home rest-day banner, and 10
  /// other call sites (whitelist-shaped, via `isPhaseCompletionTrainingType`
  /// — 12 sites total, incl. the visible calendar strip, found only in the
  /// whole-branch review) — see `phase_completion.dart`. This flag makes
  /// every whitelist-shaped call site ALSO count `logged`, via
  /// [isRestDayConsideringLogged] below.
  /// Set `configBox['enable_logged_counts_as_phase_training_day'] = true` to
  /// enable. Ship-dark default OFF; flip only in its own reviewed commit per
  /// §4.12.4.
  static bool get loggedCountsAsPhaseTrainingDayEnabled {
    try {
      return HiveService.instance.configBox
              .get('enable_logged_counts_as_phase_training_day') ==
          true;
    } catch (_) {
      return false; // no Hive (pure unit test) → default: OFF
    }
  }

  /// The ONE call every OI-126 call site makes instead of re-inlining
  /// `type != 'workout' && type != 'custom_template'`. Centralizing this is
  /// deliberate: 12 independent inline copies of the same ternary is exactly
  /// how a future edit silently diverges at one site and not the others —
  /// including a 12th call site (weekly_calendar.dart) that split the
  /// ternary across two separately-named booleans instead of one joined
  /// expression, which is exactly the shape that let it evade every earlier
  /// grep until the whole-branch review found it.
  /// Flag OFF → byte-identical to the pre-fix inline expression for every
  /// `type` value. Flag ON → widens to also treat `logged` as training.
  static bool isRestDayConsideringLogged(Object? type) {
    if (loggedCountsAsPhaseTrainingDayEnabled) {
      return !isPhaseCompletionTrainingType(type);
    }
    return type != 'workout' && type != 'custom_template';
  }
}
