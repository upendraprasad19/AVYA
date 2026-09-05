// lib/core/services/workout_schedule_read_service.dart
//
// Tech-debt audit 2026-05-20 / A2 (final closure batch B5 D13-D17).
//
// Split out of `workout_schedule_service.dart` (was ~1970 lines). This file
// owns:
//   - Plan generation orchestration (generateAndSchedule,
//     generateAndScheduleFromDate, autoGenerateNextPhaseIfNeeded, redoWeek4
//     stays in WriteService).
//   - Calendar / week queries (getScheduleForDate, getWeek,
//     getCurrentWeekNumber, getCurrentDayInPhase, isPhaseExpired,
//     getPlanStartDate, getPlanEndDate, getCurrentPlan, getCurrentPlanMap,
//     hasPlan, getCurrentCalendarWeek).
//
// closes-diagnose: 2026-05-22-a2-workout-schedule-4way-split-<6char>

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'migrated_key.dart';
import 'seed_service.dart';
import 'singleton_lifecycle_registry.dart';
import 'sync_service.dart';
import 'workout_write_service.dart';
import 'write_result.dart';
import '../utils/date_utils.dart';
import '../utils/hold_week_labels.dart';
import '../utils/ist_date.dart';
import '../utils/phase_completion.dart';
import '../../features/profile/services/profile_write_service.dart';
import '../../shared/repositories/plan_generator.dart';
import '../../shared/repositories/plan_engine/plan_engine_flags.dart';
import '../constants/fitness_goals.dart';
import '../../shared/repositories/user_repository.dart';

/// A prior (completed or abandoned) 28-day phase block: the `schedule_*` rows
/// strictly before the current `plan_start_date`, bucketed into 28-day windows
/// from the earliest such row. The COUNT of these blocks is the single source
/// of truth for "how many phases the user has moved past" — consumed by BOTH
/// the Train week selector (rendering completed phases) AND
/// `PhaseProgressReconciler` (the `current_phase` invariant). Keeping the
/// bucketing in one place avoids a parallel reader that could drift (the
/// recurring writer/reader-drift class). Introduced 2026-06-02 (two-Phase-1).
class PastPhaseBlock {
  final DateTime startDate;
  final DateTime endDate;

  /// Raw `schedule_*` row maps in this block (date-ascending), for the week
  /// selector's past-week sheet. The reconciler only needs the block COUNT.
  final List<Map<String, dynamic>> rows;

  const PastPhaseBlock({
    required this.startDate,
    required this.endDate,
    required this.rows,
  });
}

/// One materialized **hold week** — a free-tier "Hold the Line" repeat of the
/// phase's canonical Peak (or every-4th deload) week, written by
/// `WorkoutScheduleWriteService.holdWeek()` behind `enable_hold_weeks`.
///
/// Display-side view of the row-stamped `is_hold` / `hold_ordinal` fields. Note
/// the hold rows also carry `week = 4 + ordinal`, but that week number is NOT
/// usable for display today: `CurrentPlanData.weeks` only ever holds 4 entries
/// for phase 1 (`train_provider.dart` hardcodes `totalWeeks = 4`), so
/// `getWeek(5)` returns empty. Hold weeks are therefore surfaced by ORDINAL and
/// DATE, never by the clamped week index — see `holdWeeks()`.
class HoldWeekInfo {
  /// 1-based hold number — H1, H2, H3… Sourced from the row-stamped
  /// `hold_ordinal` (gap-proof; the writer computes it as max-so-far + 1).
  final int ordinal;

  /// Monday of this hold week (holds are always Monday-backdated by the writer).
  final DateTime weekStart;

  /// True when this hold sourced the phase's deload week instead of Peak.
  /// See [isDeloadHold] — mirrors the writer's cadence.
  final bool isDeload;

  /// ≥1 completed day in this hold week — the SAME "any completed day that
  /// week" rule [completedWeekNumbers] applies to the regular W-chips, so an
  /// H-chip's ✓ means exactly what a W-chip's ✓ means (a stricter all-days rule
  /// here would read as punitive next to an identical-looking W-chip).
  final bool isCompleted;

  const HoldWeekInfo({
    required this.ordinal,
    required this.weekStart,
    required this.isDeload,
    required this.isCompleted,
  });
}

/// The **honest week identity** for today — the one answer every surface that
/// prints a week counter must ask for.
///
/// Exactly one of [weekInPhase] / [holdOrdinal] is non-null. A hold week sits
/// OUTSIDE the phase's four weeks, so there is no honest "WK n OF 4" for it:
/// [WorkoutScheduleReadService.getCurrentWeekNumber] clamps to `[1,4]` and a
/// hold starts at `plan_start + 28`, so it returns **4 for every hold at every
/// ordinal, forever** (diagnose c8b3f2 D1). The rule the shipped Train surfaces
/// already chose — and which this type carries to the rest of the app (FOB-1,
/// OI-60) — is: **a hold suppresses the week number; Hn is the identity.**
///
/// Deliberately NOT a projected number. Do not add a `4 + ordinal` getter: that
/// manufactures the exact value the UI ruled dishonest, and it demotes a
/// phase-2 holder from program week 8 to 5. A caller that genuinely needs a
/// program week for a NON-hold day uses
/// [WorkoutScheduleReadService.programWeekFor] (diagnose c9f4a2).
class WeekIdentity {
  /// Week within the current phase (1..4). Null while holding.
  final int? weekInPhase;

  /// 1-based hold number — H1, H2, H3… Null when not holding.
  final int? holdOrdinal;

  const WeekIdentity.week(int this.weekInPhase) : holdOrdinal = null;
  const WeekIdentity.hold(int this.holdOrdinal) : weekInPhase = null;

  bool get isHolding => holdOrdinal != null;
}

/// Read + plan-generation orchestrator portion of the former
/// `WorkoutScheduleService`. See file-level doc-comment for the split rationale.
class WorkoutScheduleReadService {
  WorkoutScheduleReadService._() {
    _registerLifecycle();
  }
  static final WorkoutScheduleReadService _instance =
      WorkoutScheduleReadService._();

  /// Prefer `ref.read(workoutScheduleReadServiceProvider)`.
  @Deprecated(
      'Use ref.read(workoutScheduleReadServiceProvider) — singleton path will be removed after full migration')
  static WorkoutScheduleReadService get instance => _instance;

  final HiveService _hive = HiveService.instance;

  void _registerLifecycle() {
    SingletonLifecycleRegistry.register(
        'WorkoutScheduleReadService', _onUserChanged);
  }

  void _onUserChanged() {
    // Re-arm the tripwire below for the newly-signed-in account.
    _strictEmptyTripwireLogged = false;
  }

  // Session-scoped dedup for the pastPhaseBlocksForDisplay tripwire below —
  // pastPhaseBlocksForDisplay is called from WeekSelector.build(), which can
  // rebuild on every scroll frame (its own scroll listener setState()s).
  // Without this guard the probe would fire a real network call per rebuild
  // instead of once per account per session.
  bool _strictEmptyTripwireLogged = false;

  // ── Keys (kept in sync with WorkoutScheduleWriteService / SwapService) ──

  static const String _planKey = 'current_plan';
  static const String _schedulePrefix = 'schedule_';
  static const String _planStartKey = 'plan_start_date';
  static const String _planEndKey = 'plan_end_date';

  // ── Generate & Schedule ─────────────────────────────────────────

  /// Generates a plan and maps it to calendar dates starting from [startDate].
  Future<Phase> generateAndSchedule({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required DateTime startDate,
    String experienceLevel = 'beginner',
    int phase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
    // ⑧ 2-int (W2.5): per-day PINNED exercise names (variant A → weeks 1/3,
    // variant B → weeks 2/4), forwarded to generate() so the new phase repeats
    // the prior phase's SELECTION at detrained loads. null (every existing
    // caller) → verbatim fresh generation → byte-identical.
    Map<int, ({List<String> a, List<String> b})>? pinnedExercisesByDay,
    // W2.7 (Batch 9): opt-in volume titration — the two fresh-advance callers
    // pass `pins == null` so a REPEAT advance never gains volume. Threaded to
    // generate(); default false → inert.
    bool applyVolumeTitration = false,
    // W3.4 (Batch 11-B): per-day previous-phase picks (LOWERCASED) for cross-phase
    // variety, forwarded to generate(). null (every existing caller) → inert.
    Map<int, ({List<String> a, List<String> b})>? previousPhaseByDay,
    // W3.5 (Batch 12-A): opt-in plateau escalation — the two fresh-advance callers
    // pass `pins == null`; every other caller defaults false → inert.
    bool applyPlateauEscalation = false,
  }) async {
    final exerciseBox = _hive.exerciseBox;
    if (exerciseBox.isEmpty) {
      await SeedService.instance.seedIfNeeded();
    }

    final plan = PlanGenerator.instance.generate(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      phase: phase,
      experienceLevel: experienceLevel,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
      pinnedExercisesByDay: pinnedExercisesByDay,
      applyVolumeTitration: applyVolumeTitration,
      previousPhaseByDay: previousPhaseByDay,
      applyPlateauEscalation: applyPlateauEscalation,
    );

    final dayPattern = preferredDays ?? _getDayPattern(daysPerWeek);
    final workoutBox = _hive.workoutBox;
    final monday = _normalizeToMonday(startDate);
    final endDate = monday.add(const Duration(days: 27));

    await MigratedKey.write(_planStartKey, monday.toIso8601String());
    await MigratedKey.write(_planEndKey, endDate.toIso8601String());
    await workoutBox.put(_planKey, plan.toMap());
    // ⑧ 2-int (W2.5): stamp the profile THIS phase was generated under, so the
    // NEXT advance's G5 gate can decide whether a "repeat" is faithful (same
    // planGoal + equipment + daysPerWeek + effectiveExp ⇒ same split frames).
    // Stores the GENERATION PARAMS (apples-to-apples with the advance's own args),
    // NOT profile fields. Flag-gated → ship-dark OFF ⇒ no new write ⇒ byte-identical.
    if (PlanEngineFlags.adherenceGateEnabled) {
      // USER-SCOPED (MigratedKey → userBox), NOT the shared configBox — this is
      // per-user data, and a shared box would let a 2nd account on the same device
      // read a stale baseline and misjudge the G5 gate (cross-account isolation,
      // same reason plan_start_date/plan_end_date above use MigratedKey). Registered
      // in UserConfigMigrator.userScopedKeys.
      await MigratedKey.write('last_phase_profile', {
        'plan_goal': FitnessGoals.of(goal).planGoal,
        'equipment': equipment,
        'days_per_week': daysPerWeek,
        'effective_exp': PlanGenerator.effectiveLevel(experienceLevel, phase),
      });
    }
    unawaited(SyncService.instance.syncWorkoutData());
    unawaited(SyncService.instance.pushSnapshot());
    if (preferredDays != null) {
      await MigratedKey.write('preferred_training_days', preferredDays);
    }

    for (int week = 0; week < 4; week++) {
      final weekPlan = week < plan.weekPlans.length
          ? plan.weekPlans[week]
          : plan.weekPlans.last;
      final weekStart = monday.add(Duration(days: week * 7));
      int workoutDayIndex = 0;

      for (int dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) {
        final date = weekStart.add(Duration(days: dayOfWeek));
        final dateKey = _dateKey(date);
        final isWorkoutDay = dayPattern.contains(dayOfWeek);

        if (isWorkoutDay && workoutDayIndex < weekPlan.workoutDays.length) {
          final workoutDay = weekPlan.workoutDays[workoutDayIndex];
          await WorkoutWriteService.instance.upsertScheduled(
            date: date,
            entry: {
              'date': dateKey,
              'phase': phase,
              'week': week + 1,
              'day_of_week': dayOfWeek,
              'type': 'workout',
              'workout_day_index': workoutDayIndex,
              'workout_name': workoutDay.name,
              'workout_focus': workoutDay.focus,
              'exercises':
                  workoutDay.exercises.map((e) => e.toMap()).toList(),
              if (workoutDay.warmup.isNotEmpty)
                'warmup':
                    workoutDay.warmup.map((e) => e.toMap()).toList(),
              if (workoutDay.cooldown.isNotEmpty)
                'cooldown':
                    workoutDay.cooldown.map((e) => e.toMap()).toList(),
              if (workoutDay.finisher.isNotEmpty)
                'finisher':
                    workoutDay.finisher.map((e) => e.toMap()).toList(),
              'week_character': weekPlan.weekCharacter,
              'status': 'planned',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
          workoutDayIndex++;
        } else {
          await WorkoutWriteService.instance.upsertScheduled(
            date: date,
            entry: {
              'date': dateKey,
              'phase': phase,
              'week': week + 1,
              'day_of_week': dayOfWeek,
              'type': 'rest',
              'workout_name': 'Rest Day',
              'workout_focus': 'Recovery & mobility',
              'exercises': <Map<String, dynamic>>[],
              'week_character': weekPlan.weekCharacter,
              'status': 'rest',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
        }
      }
    }

    return plan;
  }

  /// Regenerates plan + reschedules from [fromDate] forward.
  Future<Phase> generateAndScheduleFromDate({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required DateTime fromDate,
    String experienceLevel = 'beginner',
    int phase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
  }) async {
    final exerciseBox = _hive.exerciseBox;
    if (exerciseBox.isEmpty) {
      await SeedService.instance.seedIfNeeded();
    }

    final plan = PlanGenerator.instance.generate(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      phase: phase,
      experienceLevel: experienceLevel,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
    );

    final workoutBox = _hive.workoutBox;
    final today = istMidnight(fromDate);
    final planEndStr = MigratedKey.read<String>(_planEndKey);
    final planEnd =
        planEndStr != null ? DateTime.parse(planEndStr) : today.add(const Duration(days: 28));

    for (var d = today; !d.isAfter(planEnd); d = d.add(const Duration(days: 1))) {
      final dateKey = _dateKey(d);
      final key = '$_schedulePrefix$dateKey';
      final displacedKey = 'displaced_$dateKey';
      final existing = workoutBox.get(key);
      if (existing != null) {
        final map = existing is Map ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
        final status = map['status'] as String? ?? '';
        if (status != 'completed') {
          await workoutBox.delete(key);
        }
      }
      if (workoutBox.containsKey(displacedKey)) {
        await workoutBox.delete(displacedKey);
      }
    }

    final monday = _normalizeToMonday(today);
    final endDate = monday.add(const Duration(days: 27));

    final existingStart = MigratedKey.read<String>(_planStartKey);
    final isFirstGeneration = existingStart == null;
    if (isFirstGeneration) {
      await MigratedKey.write(_planStartKey, monday.toIso8601String());
      await MigratedKey.write(_planEndKey, endDate.toIso8601String());
    }
    await workoutBox.put(_planKey, plan.toMap());
    unawaited(SyncService.instance.syncWorkoutData());
    unawaited(SyncService.instance.pushSnapshot());
    if (preferredDays != null) {
      await MigratedKey.write('preferred_training_days', preferredDays);
    }

    if (isFirstGeneration) {
      await ProfileWriteService.instance.updateField(
        'phase_started_at',
        today.toUtc().toIso8601String(),
      );
    }

    if (isFirstGeneration) {
      for (var d = monday;
          d.isBefore(today);
          d = d.add(const Duration(days: 1))) {
        final dateKey = _dateKey(d);
        final scheduleKey = '$_schedulePrefix$dateKey';
        if (workoutBox.get(scheduleKey) == null) {
          await WorkoutWriteService.instance.upsertScheduled(
            date: d,
            entry: {
              'date': dateKey,
              'phase': phase,
              'week': 1,
              'day_of_week': d.weekday - 1,
              'type': 'rest',
              'workout_name': 'Joined later',
              'workout_focus': 'You joined AVYA mid-week',
              'exercises': <Map<String, dynamic>>[],
              'week_character': '',
              'status': 'rest',
              'reason': 'pre_onboarding',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
        }
      }
    }

    final dayPattern = preferredDays ?? _getDayPattern(daysPerWeek);

    for (int week = 0; week < 4; week++) {
      final weekPlan = week < plan.weekPlans.length
          ? plan.weekPlans[week]
          : plan.weekPlans.last;
      final weekStart = monday.add(Duration(days: week * 7));
      int workoutDayIndex = 0;

      for (int dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) {
        final date = weekStart.add(Duration(days: dayOfWeek));
        final dateKey = _dateKey(date);
        final scheduleKey = '$_schedulePrefix$dateKey';

        if (date.isBefore(today)) {
          if (dayPattern.contains(dayOfWeek) && workoutDayIndex < weekPlan.workoutDays.length) {
            workoutDayIndex++;
          }
          continue;
        }

        final existing = workoutBox.get(scheduleKey);
        if (existing != null) {
          final map = existing is Map ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
          if (map['status'] == 'completed') {
            if (dayPattern.contains(dayOfWeek) && workoutDayIndex < weekPlan.workoutDays.length) {
              workoutDayIndex++;
            }
            continue;
          }
        }

        final isWorkoutDay = dayPattern.contains(dayOfWeek);
        if (isWorkoutDay && workoutDayIndex < weekPlan.workoutDays.length) {
          final workoutDay = weekPlan.workoutDays[workoutDayIndex];
          await WorkoutWriteService.instance.upsertScheduled(
            date: date,
            entry: {
              'date': dateKey,
              'phase': phase,
              'week': week + 1,
              'day_of_week': dayOfWeek,
              'type': 'workout',
              'workout_day_index': workoutDayIndex,
              'workout_name': workoutDay.name,
              'workout_focus': workoutDay.focus,
              'exercises':
                  workoutDay.exercises.map((e) => e.toMap()).toList(),
              if (workoutDay.warmup.isNotEmpty)
                'warmup':
                    workoutDay.warmup.map((e) => e.toMap()).toList(),
              if (workoutDay.cooldown.isNotEmpty)
                'cooldown':
                    workoutDay.cooldown.map((e) => e.toMap()).toList(),
              'week_character': weekPlan.weekCharacter,
              'status': 'planned',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
          workoutDayIndex++;
        } else {
          await WorkoutWriteService.instance.upsertScheduled(
            date: date,
            entry: {
              'date': dateKey,
              'phase': phase,
              'week': week + 1,
              'day_of_week': dayOfWeek,
              'type': 'rest',
              'workout_name': 'Rest Day',
              'workout_focus': 'Recovery & mobility',
              'exercises': <Map<String, dynamic>>[],
              'week_character': weekPlan.weekCharacter,
              'status': 'rest',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
        }
      }
    }

    return plan;
  }

  /// PRO-only: if current Phase expired, generate next Phase starting today.
  /// Returns `(generated, repeated)` — `generated` is true iff a new phase was
  /// written; `repeated` is true iff a faithful G5-gated repeat pin was applied
  /// (⑧ 3-a2 — drives the low-adherence "you repeated" nudge). `pins != null`
  /// means the G5 gate passed AND a pin map was built (not necessarily that
  /// every day is identical — an absent variant-B day fresh-fills).
  Future<({bool generated, bool repeated})> autoGenerateNextPhaseIfNeeded({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    String experienceLevel = 'intermediate',
    int currentPhase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
    // ⑧ 2-int (W2.5): when true (UNIT 3's low-adherence "repeat" choice — not yet
    // wired) AND the adherence-gate flag is ON, the new phase REPEATS the just-
    // finished phase's exercise selection (at detrained loads) instead of a fresh
    // pick. Default false + flag-gated → ship-dark inert → byte-identical.
    bool repeatContent = false,
  }) async {
    if (!isPhaseExpired()) return (generated: false, repeated: false);
    // 2026-05-31 (post-12 deployment cycles): the old `currentPhase >= 12`
    // dead-end is removed. Phases now generate indefinitely so a graduated user
    // always has the next "Deployment" to train, current_phase increments
    // monotonically (driving deployments_complete), and the plan engine recycles
    // the advanced phase-9-12 content templates with continued LOAD overload.

    // Theme H fix (diagnose <id>) — was `DateTime.now()` directly. Now
    // computes max(today, currentPhaseEnd + 1) Monday-normalized so the
    // new phase doesn't overwrite the just-completed phase's final week.
    final newPhase = currentPhase + 1;
    // ⑧ 2-int: build the repeat pins from the JUST-FINISHED phase's rows BEFORE
    // generateAndSchedule overwrites plan_start (getWeek reads the current window).
    final pins = (repeatContent && PlanEngineFlags.adherenceGateEnabled)
        ? _buildRepeatPins(
            goal: goal,
            equipment: equipment,
            daysPerWeek: daysPerWeek,
            experienceLevel: experienceLevel,
            newPhase: newPhase,
          )
        : null;
    // W3.4 (Batch 11-B): on a FRESH advance (pins == null), feed the just-finished
    // phase's picks as variety avoid-names (previousPhaseNamesByDay self-gates on
    // the flag → empty when OFF). Read BEFORE generateAndSchedule overwrites
    // plan_start (same obligation as pins).
    final previousPhaseByDay =
        pins == null ? previousPhaseNamesByDay() : null;
    final startDate = nextPhaseStartDate();
    await generateAndSchedule(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      startDate: startDate,
      experienceLevel: experienceLevel,
      phase: newPhase,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
      pinnedExercisesByDay: pins,
      // W2.7 (Batch 9): titrate ONLY a FRESH advance (pins == null). A
      // low-adherence repeat (pins != null) must NOT gain volume.
      applyVolumeTitration: pins == null,
      previousPhaseByDay: previousPhaseByDay,
      // W3.5 (Batch 12-A): plateau escalation likewise only on a FRESH advance.
      applyPlateauEscalation: pins == null,
    );
    return (generated: true, repeated: pins != null);
  }

  /// ⑧ 2-int (W2.5): build the per-day pinned A/B exercise names for a "repeat"
  /// advance, or null when the repeat isn't faithful/available (→ caller passes
  /// null → fresh generation). Reads the just-finished phase's week-1 (variant A)
  /// + week-2 (variant B) workout rows (keyed by `workout_day_index`) — MUST be
  /// called BEFORE generateAndSchedule overwrites plan_start.
  ///
  /// G5 faithfulness gate: the pin is coherent only when the NEW phase's split
  /// frames match the prior phase's — i.e. the prior generation's
  /// {planGoal, equipment, daysPerWeek, effectiveExp} (persisted as
  /// `last_phase_profile`) equals the NEW phase's. `effectiveExp` matters because
  /// `effectiveLevel(exp, phase)` WIDENS with phase (beginner→intermediate@3,
  /// →advanced@5) — so a beginner advancing 2→3 gets DIFFERENT frames even with
  /// goal/equipment/days unchanged, and the pin would slot full-body names into
  /// Push/Pull/Legs frames. Absent baseline (legacy / first flip-on) → null.
  Map<int, ({List<String> a, List<String> b})>? _buildRepeatPins({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required String experienceLevel,
    required int newPhase,
  }) {
    final stored = MigratedKey.read<Map>('last_phase_profile');
    return repeatPinsFrom(
      stored: stored, // user-scoped (userBox); null (absent) → fresh
      week1: getWeek(1), // just-finished phase, variant A (weeks 1/3)
      week2: getWeek(2), // variant B (weeks 2/4)
      currentPlanGoal: FitnessGoals.of(goal).planGoal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      newPhaseEffectiveExp:
          PlanGenerator.effectiveLevel(experienceLevel, newPhase),
    );
  }

  /// ⑧ 3-b: public entry to [_buildRepeatPins] for the graduation choice sheet's
  /// "repeat" branch (graduation calls the read service DIRECTLY, not the
  /// facade + not autoGenerate). Visibility-only delegate — identical G5 gate +
  /// A/B extraction. MUST be called BEFORE generateAndSchedule overwrites
  /// plan_start (same ordering obligation as [_buildRepeatPins] — getWeek reads
  /// the just-finished window).
  Map<int, ({List<String> a, List<String> b})>? buildRepeatPinsForAdvance({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required String experienceLevel,
    required int newPhase,
  }) =>
      _buildRepeatPins(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        experienceLevel: experienceLevel,
        newPhase: newPhase,
      );

  /// PURE decision behind [_buildRepeatPins] (visible for testing — no Hive/clock).
  /// [stored] = the prior generation's `last_phase_profile`; [week1]/[week2] = the
  /// just-finished phase's variant-A/B workout rows (keyed by `workout_day_index`).
  /// Returns null (⇒ caller falls back to FRESH generation) when the baseline is
  /// absent, the frame-shape profile MISMATCHES (planGoal / equipment / daysPerWeek
  /// / effectiveExp — effectiveExp because `effectiveLevel(exp,phase)` widens with
  /// phase, so a beginner 2→3 gets different frames), or there's nothing to repeat.
  /// A gap day-index (a missing/displaced workout row) yields an empty-name entry
  /// → buildPinnedDays fresh-fills that frame; the union of A+B keys is spanned so
  /// a B-only index isn't dropped.
  @visibleForTesting
  static Map<int, ({List<String> a, List<String> b})>? repeatPinsFrom({
    required Map? stored,
    required List<Map<String, dynamic>> week1,
    required List<Map<String, dynamic>> week2,
    required String currentPlanGoal,
    required String equipment,
    required int daysPerWeek,
    required String newPhaseEffectiveExp,
  }) {
    if (stored == null) return null;
    final matches = stored['plan_goal'] == currentPlanGoal &&
        stored['equipment'] == equipment &&
        stored['days_per_week'] == daysPerWeek &&
        stored['effective_exp'] == newPhaseEffectiveExp;
    if (!matches) return null;

    final aByIdx = _namesByDayIndex(week1);
    final bByIdx = _namesByDayIndex(week2);
    if (aByIdx.isEmpty && bByIdx.isEmpty) return null;

    final maxIdx =
        <int>{...aByIdx.keys, ...bByIdx.keys}.reduce((a, b) => a > b ? a : b);
    return {
      for (var i = 0; i <= maxIdx; i++)
        i: (a: aByIdx[i] ?? const [], b: bByIdx[i] ?? const []),
    };
  }

  /// SHARED parser (Batch 11-B fold): the `exercise_name`s of a workout schedule
  /// row, order preserved, empties dropped, ORIGINAL case (repeatPinsFrom's
  /// getByExactName consumer needs original case).
  static List<String> _exerciseNamesOfRow(Map<String, dynamic> row) =>
      ((row['exercises'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => (e['exercise_name'] as String?) ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

  /// SHARED (Batch 11-B fold): a week's `type=='workout'` rows keyed by
  /// `workout_day_index` → their exercise names. Used by BOTH repeatPinsFrom AND
  /// previousPhaseNamesByDay (one parser — #1 drift class).
  static Map<int, List<String>> _namesByDayIndex(
      List<Map<String, dynamic>> week) {
    final out = <int, List<String>>{};
    for (final row in week) {
      if (row['type'] != 'workout') continue;
      final idx = row['workout_day_index'];
      if (idx is int) out[idx] = _exerciseNamesOfRow(row);
    }
    return out;
  }

  /// W3.4 (Batch 11-B): the just-finished phase's per-day A/B exercise names,
  /// LOWERCASED, for the cross-phase VARIETY avoid-set. Reads the SAME rows as
  /// repeatPinsFrom (`getWeek(1)`/`getWeek(2)`) but WITHOUT the G5
  /// `last_phase_profile` gate — a stale avoid-name that no longer matches a live
  /// candidate is a HARMLESS no-op (queryV4 candidates are pattern-locked). Empty
  /// map when there's no prior phase → avoidNames empty → inert. The caller gates
  /// this call on `crossPhaseVarietyEnabled && pins == null`.
  Map<int, ({List<String> a, List<String> b})> previousPhaseNamesByDay() {
    // Ship-dark, service-layer gate: flag OFF → no getWeek reads, empty avoid-set
    // → the cascade is byte-identical. The callers pass this only when pins==null.
    if (!PlanEngineFlags.crossPhaseVarietyEnabled) return const {};
    return previousPhaseNamesFrom(week1: getWeek(1), week2: getWeek(2));
  }

  /// PURE core of [previousPhaseNamesByDay] (visible for testing — no Hive/clock/
  /// flag). [week1]/[week2] = the just-finished phase's variant-A/B workout rows.
  /// Returns per-day A/B exercise names LOWERCASED (variety avoid-set), spanning the
  /// union of A+B day-indices; empty when there's nothing to avoid. Mirrors
  /// repeatPinsFrom's pure/instance split.
  @visibleForTesting
  static Map<int, ({List<String> a, List<String> b})> previousPhaseNamesFrom({
    required List<Map<String, dynamic>> week1,
    required List<Map<String, dynamic>> week2,
  }) {
    List<String> lc(List<String> ns) =>
        ns.map((n) => n.toLowerCase()).toList();
    final aByIdx = _namesByDayIndex(week1);
    final bByIdx = _namesByDayIndex(week2);
    if (aByIdx.isEmpty && bByIdx.isEmpty) return const {};
    final maxIdx =
        <int>{...aByIdx.keys, ...bByIdx.keys}.reduce((a, b) => a > b ? a : b);
    return {
      for (var i = 0; i <= maxIdx; i++)
        i: (a: lc(aByIdx[i] ?? const []), b: lc(bByIdx[i] ?? const [])),
    };
  }

  // ── Queries ─────────────────────────────────────────────────────

  /// Get scheduled data for a specific date.
  Map<String, dynamic>? getScheduleForDate(DateTime date) {
    final key = '$_schedulePrefix${_dateKey(date)}';
    final data = _hive.workoutBox.get(key);
    if (data == null) return null;
    final map = Map<String, dynamic>.from(data as Map);

    if (map['status'] == 'completed') {
      final completedAt = map['completed_at'] as String?;
      if (completedAt != null) {
        final completedDate = DateTime.tryParse(completedAt);
        if (completedDate != null) {
          final requestedDateStr = _dateKey(date);
          final completedDateStr = _dateKey(completedDate);
          if (completedDateStr.compareTo(requestedDateStr) < 0) {
            final safe = Map<String, dynamic>.from(map);
            safe['status'] = 'planned';
            safe['completed_at'] = null;
            return safe;
          }
        }
      }
    }

    return map;
  }

  // ── Hold weeks (free-tier "Hold the Line" display read-path) ────
  //
  // Additive read surface over the `is_hold` / `hold_ordinal` fields stamped by
  // `WorkoutScheduleWriteService.holdWeek()`. Deliberately does NOT touch
  // `getCurrentWeekNumber()` / `getProgramWeek()` / `currentPhaseCompletionRate()`
  // — those stay clamped exactly as they are today, so surfacing holds cannot
  // perturb their 11 downstream consumers (restore, AI snapshot, deload
  // evaluator, streak, the PRO advance gate). See
  // `docs/plan-reviews/free-tier-hold-findings.md`.

  /// Whether hold number [ordinal] is a **deload** hold.
  ///
  /// ⚠ MUST mirror the writer's cadence in
  /// `workout_schedule_write_service.holdWeek()` (`final deload = n % 4 == 0`).
  /// The writer never PERSISTS this as a field — it only uses it to choose the
  /// source week — so display recomputes it from the stored `hold_ordinal`.
  /// Pure + static so the write/display agreement is behaviorally testable.
  static bool isDeloadHold(int ordinal) => ordinal % 4 == 0;

  /// Hold-week dates grouped by `hold_ordinal`, each list date-ascending.
  ///
  /// Single walk of `schedule_*`; every public hold reader below builds on it so
  /// the "what counts as a hold row" predicate lives in exactly one place.
  ///
  /// **Scoped to the CURRENT plan window** (`date >= plan_start`). Holds extend
  /// the phase they belong to, so once the user leaves that phase (a PRO advance
  /// moves `plan_start` forward) their old holds are ordinary history and belong
  /// to [pastPhaseBlocks] — the same rows, under their real phase number. Without
  /// this bound the chips would linger forever AND be relabelled with the new
  /// phase's numeral, double-rendering a converted user's history under the wrong
  /// heading. Hold rows are never re-stamped with `phase` (deliberately — an
  /// explicit stamp trips legacy `bucketPastRows` carry-forward), so the date
  /// window, not a phase field, is what scopes them.
  ///
  /// No UPPER bound: free users may hold indefinitely (founder decision:
  /// unlimited holds), so this must never inherit the 12-week caps other readers
  /// apply.
  /// Midnight of `plan_start`, or null when no plan exists. The lower bound
  /// every hold reader shares (see [_holdDatesByOrdinal]).
  DateTime? _holdWindowStart() {
    final planStart = getPlanStartDate();
    if (planStart == null) return null;
    return DateTime(planStart.year, planStart.month, planStart.day);
  }

  Map<int, List<DateTime>> _holdDatesByOrdinal() {
    final windowStart = _holdWindowStart();
    if (windowStart == null) return const {};
    final box = _hive.workoutBox;
    final out = <int, List<DateTime>>{};
    for (final entry in box.toMap().entries) {
      final key = entry.key.toString();
      if (!key.startsWith(_schedulePrefix)) continue;
      final value = entry.value;
      if (value is! Map || value['is_hold'] != true) continue;
      final ordinal = value['hold_ordinal'];
      if (ordinal is! int || ordinal < 1) continue;
      final date = DateTime.tryParse(key.substring(_schedulePrefix.length));
      if (date == null || date.isBefore(windowStart)) continue;
      (out[ordinal] ??= <DateTime>[]).add(date);
    }
    for (final dates in out.values) {
      dates.sort();
    }
    return out;
  }

  /// The hold number covering [date], or null when that date is not a hold day
  /// of the CURRENT phase.
  ///
  /// Window-scoped on the same rule as [_holdDatesByOrdinal] so the whole hold
  /// read surface agrees: a hold the user has since advanced past is history,
  /// not a live hold, and must not resurface through this entry point either.
  int? holdOrdinalForDate(DateTime date) {
    final windowStart = _holdWindowStart();
    if (windowStart == null) return null;
    final day = DateTime(date.year, date.month, date.day);
    if (day.isBefore(windowStart)) return null;
    final raw = _hive.workoutBox.get('$_schedulePrefix${_dateKey(date)}');
    if (raw is! Map || raw['is_hold'] != true) return null;
    final ordinal = raw['hold_ordinal'];
    return (ordinal is int && ordinal >= 1) ? ordinal : null;
  }

  /// Every materialized hold week, ordinal-ascending (H1, H2, H3…).
  ///
  /// Empty when the user has never held — which is every user while
  /// `enable_hold_weeks` is OFF, since only `holdWeek()` writes `is_hold`.
  List<HoldWeekInfo> holdWeeks() {
    final byOrdinal = _holdDatesByOrdinal();
    final ordinals = byOrdinal.keys.toList()..sort();
    return [
      for (final ordinal in ordinals)
        HoldWeekInfo(
          ordinal: ordinal,
          weekStart: byOrdinal[ordinal]!.first,
          isDeload: isDeloadHold(ordinal),
          // Routed through getScheduleForDate (not the raw row) so the
          // completed-in-the-future normalization guard applies here exactly as
          // it does for the regular week chips.
          isCompleted: byOrdinal[ordinal]!
              .any((d) => getScheduleForDate(d)?['status'] == 'completed'),
        ),
    ];
  }

  /// [holdWeeks] **gated on `enable_hold_weeks`** — the ONE place the hold READ
  /// path consults the flag.
  ///
  /// [holdWeeks] and [holdOrdinalForDate] stay raw row readers so tests can
  /// exercise the row contract directly, but every PRODUCTION consumer goes
  /// through this pair instead, so the flag empties the whole read surface from
  /// a single point. `holdStatusProvider` and [weekIdentity] both delegate here
  /// rather than each restating the check — two independently-maintained copies
  /// of one gate is the writer/reader drift class CLAUDE.md §4.1 names as the
  /// default suspect.
  List<HoldWeekInfo> activeHoldWeeks() =>
      PlanEngineFlags.holdWeeksEnabled ? holdWeeks() : const [];

  /// [holdOrdinalForDate] gated on `enable_hold_weeks`. Null whenever the flag
  /// is OFF, whatever `is_hold` rows exist on disk.
  int? activeHoldOrdinalFor(DateTime date) =>
      PlanEngineFlags.holdWeeksEnabled ? holdOrdinalForDate(date) : null;

  /// The honest week identity for TODAY — see [WeekIdentity].
  ///
  /// Returns [WeekIdentity.hold] only when today is a live hold day AND the
  /// flag is ON; otherwise the clamped week-in-phase, byte-identical to what
  /// every caller printed before hold weeks existed. That flag-OFF equality is
  /// the ship-dark property the §4.12.4 review tier rests on, and it is pinned
  /// by the flag-OFF group in
  /// `test/contracts/hold_week_identity_behavioral_test.dart`.
  ///
  /// Reads `nowWall()` (not `DateTime.now()`) so the dev time-travel / year-sim
  /// seam `holdWeek()` writes against also drives what "today" means here.
  WeekIdentity weekIdentity() {
    final ordinal = activeHoldOrdinalFor(nowWall());
    return ordinal == null
        ? WeekIdentity.week(getCurrentWeekNumber())
        : WeekIdentity.hold(ordinal);
  }

  /// The coach snapshot's `hold` block — FOB-3 / OI-60 — or **null** when the
  /// user is not on a hold day today.
  ///
  /// NULL IS THE CONTRACT, not an oversight. The caller must OMIT the key
  /// entirely rather than emit `"hold": null`: with `enable_hold_weeks` OFF
  /// [activeHoldOrdinalFor] is always null, so omission is what makes the
  /// flag-OFF snapshot BYTE-IDENTICAL to the pre-FOB-3 one — the ship-dark
  /// property §4.12.4's lighter review tier rests on. A literal null key would
  /// change every snapshot in the fleet and forfeit it.
  ///
  /// Carries FACTS ONLY. The instruction for what the coach should DO with them
  /// lives in `supabase/functions/_shared/captain_manual.ts` (the system
  /// prompt), not here: the manual is sent once per request while this block
  /// would repeat the same prose in every holder's snapshot and be charged
  /// against the 8500-char trim budget. That split is also why FOB-3 needs an
  /// ai-proxy redeploy for only half of itself.
  ///
  /// The caller MUST also add `'hold'` to [AiSnapshotBuilder.trimSnapshotToBudget]'s
  /// keep set: the trimmer halves a non-kept map BY INSERTION ORDER, so an
  /// over-budget snapshot would silently drop `sessions_total` first and
  /// `ordinal` last — leaving a hold block that says less the more the user has
  /// logged.
  Map<String, dynamic>? holdSnapshotBlock() {
    final ordinal = activeHoldOrdinalFor(nowWall());
    if (ordinal == null) return null;
    // Read from the SAME gated list every other production consumer reads, so
    // a hold that the flag hides here cannot be visible there.
    HoldWeekInfo? info;
    for (final h in activeHoldWeeks()) {
      if (h.ordinal == ordinal) {
        info = h;
        break;
      }
    }
    // ALL-OR-NOTHING, deliberately. Both reads come from the same rows —
    // activeHoldOrdinalFor returns TODAY's stamped hold_ordinal, and
    // activeHoldWeeks groups every hold row by that same stamp — so an ordinal
    // present in one and absent from the other is not expressible today. The
    // guard is here for what happens IF it ever becomes expressible: a block
    // with a missing week_start is a block whose key set varies, and the
    // trimmer halves a map BY INSERTION ORDER, so a 4-key block degrades to
    // {ordinal, label} instead of the 6-key block the contract promises.
    // Emitting nothing is honest; emitting a partial block that looks complete
    // is not, and inventing a default for is_deload would be worse than both.
    if (info == null) return null;
    final progress = holdWeekSessionProgress(ordinal);
    return <String, dynamic>{
      'ordinal': ordinal,
      // The identity the UI prints, from the ONE place the `H` prefix is
      // spelled, so the coach quotes the same token the user is reading on
      // screen rather than a second literal that can drift from it.
      'label': holdIdentityLabel(ordinal),
      'week_start': istDateStr(info.weekStart),
      'is_deload': info.isDeload,
      'sessions_completed': progress.completed,
      'sessions_total': progress.total,
    };
  }

  /// Completed vs. scheduled workout days within hold week [ordinal] — the
  /// "4 / 5 SESSIONS" progress readout. Rest/off days are excluded from both
  /// counts. Unknown ordinal → (0, 0).
  ///
  /// Independent of [currentPhaseCompletionRate], which hardcodes a 4-week phase
  /// and is also the PRO-advance gate's input — reusing it here would both
  /// mis-count and couple display to that gate.
  ({int completed, int total}) holdWeekSessionProgress(int ordinal) {
    final dates = _holdDatesByOrdinal()[ordinal];
    if (dates == null) return (completed: 0, total: 0);
    var completed = 0;
    var total = 0;
    for (final date in dates) {
      final row = getScheduleForDate(date);
      if (row == null) continue;
      // Shares the ONE training-day predicate with the weekly-streak reckoning
      // (a3f8d1). This used to restate `type == 'rest' || type == 'off'`
      // inline; a doc comment asserting the two "must agree" is not
      // enforcement, and two independently-maintained copies of one rule is
      // the drift class this batch exists to close. `?? ''` is kept so a
      // type-less legacy row still counts, which is what isTrainingDayType
      // does with null.
      if (!isTrainingDayType((row['type'] ?? '').toString())) continue;
      total++;
      if (row['status'] == 'completed') completed++;
    }
    return (completed: completed, total: total);
  }

  /// Global week numbers (1-based from `plan_start_date`) in the CURRENT plan
  /// window with ≥1 completed scheduled day — the same "any completed day that
  /// week" rule the past-phase chips use, so the CURRENT phase's week chips can
  /// show the same ✓ (Obs 3a, 2026-06-05). Future / not-yet-dated weeks have no
  /// completed rows → naturally excluded.
  /// ⚠ HOLD ROWS ARE EXCLUDED. [completedWeekNumbersFrom] maps a date onto a
  /// week number by walking `plan_start + 7k`, but a hold week is NOT on that
  /// grid — `holdWeek()` places it in the calendar week containing *today*
  /// (`normalizeToMonday(nowWall())`), so a user who lapses and returns late
  /// leaves a gap. A completed hold day therefore lands on whatever week index
  /// its date happens to hit (H1 taken 3 weeks late → week 8), crediting a ✓ to
  /// a PHASE II/III chip for a week that was never trained.
  ///
  /// Today that ✓ is invisible only because `_WeekChip` suppresses it on a
  /// locked chip (`week_selector.dart`, `hasCompletedDay && !isLocked`) and a
  /// holder is by definition free. That guard evaporates the instant they
  /// upgrade — `week_selector` watches `subscriptionInfoProvider`, so the chip
  /// unlocks BEFORE any phase advance moves `plan_start`, and the now-unlocked
  /// chip is tappable straight into "Week 5 hasn't started yet".
  ///
  /// Hold weeks carry their own ✓ via [HoldWeekInfo.isCompleted], computed
  /// independently in [holdWeeks], so excluding them here costs nothing.
  Set<int> completedWeekNumbers({int maxWeek = 12}) {
    return completedWeekNumbersFrom(
      getPlanStartDate(),
      (date) {
        final row = getScheduleForDate(date);
        if (row == null || row['is_hold'] == true) return false;
        return row['status'] == 'completed';
      },
      maxWeek: maxWeek,
    );
  }

  /// Pure decision behind [completedWeekNumbers] (visible for testing — no Hive,
  /// Hermes L1/L37 behavioral-test gap). Returns the 1-based week numbers in
  /// `[1, maxWeek]` from [planStart] that have ≥1 day where [isCompletedOn] is
  /// true (the "any completed day that week" rule). Null planStart → empty.
  @visibleForTesting
  static Set<int> completedWeekNumbersFrom(
      DateTime? planStart, bool Function(DateTime) isCompletedOn,
      {int maxWeek = 12}) {
    if (planStart == null) return const {};
    final ps = DateTime(planStart.year, planStart.month, planStart.day);
    final result = <int>{};
    for (var w = 1; w <= maxWeek; w++) {
      final weekStart = ps.add(Duration(days: (w - 1) * 7));
      for (var d = 0; d < 7; d++) {
        if (isCompletedOn(weekStart.add(Duration(days: d)))) {
          result.add(w);
          break;
        }
      }
    }
    return result;
  }

  /// Get all scheduled days for a given week number (1-4).
  List<Map<String, dynamic>> getWeek(int weekNumber) {
    final startStr = MigratedKey.read<String>(_planStartKey);
    if (startStr == null) return [];

    final planStart = DateTime.parse(startStr);
    final weekStart = planStart.add(Duration(days: (weekNumber - 1) * 7));
    final days = <Map<String, dynamic>>[];

    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final schedule = getScheduleForDate(date);
      if (schedule != null) {
        days.add(schedule);
      }
    }
    return days;
  }

  /// Batch 10 (W3.1 explainability): the Hive key prefix for the per-phase deload
  /// "why" string (writer: `DeloadEvaluator`; reader: [currentDeloadReason]).
  static const String deloadReasonKeyPrefix = 'deload_reason_phase_';

  /// The phase a week-4 deload belongs to — the first `phase`-stamped row in the
  /// week-4 rows. The SINGLE derivation shared by the eval (reason WRITER + its
  /// flag/marker) and [currentDeloadReason] (reason READER), so the reason key can
  /// never drift between writer and reader.
  static int? deloadPhaseFromWeek4(List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      final p = r['phase'];
      if (p is int) return p;
    }
    return null;
  }

  /// Batch 10 (W3.1): the one-line deload "why" for the CURRENT phase's week-4
  /// decision, or null. Gated on `triggeredDeloadEnabled` for clean kill-switch
  /// reversibility (a stale reason hides the moment the flag is turned OFF). Reads
  /// the same `deload_reason_phase_<P>` key the eval wrote, deriving P via
  /// [deloadPhaseFromWeek4] → writer==reader by construction. Crash-safe.
  ///
  /// Unit B: the stored value is a MAP (`{week_character, text}`) and this reader
  /// returns `text` ONLY while the stamped character still equals week 4's
  /// character in the blob [currentWaveCharacters] → the strip can never show a
  /// reason that contradicts the wave node above it. Legacy bare Strings and any
  /// mismatch resolve to `null` (no line), which is byte-identical to the
  /// pre-flip state.
  String? currentDeloadReason() {
    try {
      if (!PlanEngineFlags.triggeredDeloadEnabled) return null;
      final phase = deloadPhaseFromWeek4(getWeek(4));
      if (phase == null) return null;
      final v =
          HiveService.instance.workoutBox.get('$deloadReasonKeyPrefix$phase');
      // Unit B — SELF-VALIDATING. A bare String is a LEGACY value (the writer
      // stamped prose alone from 2026-09-01 until Unit B) carrying no outcome to
      // check against, so it is indistinguishable from a stale one → drop it.
      if (v is! Map) return null;
      final text = v['text'];
      if (text is! String || text.isEmpty) return null;
      final stamped = v['week_character'];
      if (stamped is! String || stamped.isEmpty) return null;
      // Validate against the SAME source the strip RENDERS — the blob, via
      // [currentWaveCharacters] — not the scheduled rows this method derives its
      // phase from. A reason contradicting the node directly above it is worse
      // than no reason. Two plan-mutating paths re-stamp week 4 back to `deload`
      // after a lift (`generateAndScheduleFromDate` at :388 via
      // `edit_profile_screen.dart:2029`, and `regenerate_plan_planner.dart:294`)
      // while `deload_evaluator.dart:79`'s idempotency flag blocks any re-eval
      // from correcting the string; guarding at the READER covers both, plus
      // cross-device sync, restore, and any future third path.
      //
      // EQUALITY, not `== 'working'`: the mirror case — stored `deload` while the
      // blob says `working`, reachable when a sync lands a lifted blob over a
      // local keep — is exactly as stale and must drop too.
      final waves = currentWaveCharacters();
      if (waves.length < 4) return null; // strip renders nothing below 4 anyway
      if (waves[3] != stamped) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  /// ⑧ Batch 8 (W2.5 adherence gate) — the current phase's completion rate:
  /// completed / total NON-REST scheduled days across the phase's materialized
  /// weeks. Byte-identical to the Train phase-unlock card's
  /// `_computePhaseCompletionRate` (both feed the shared `phaseCompletionRate`
  /// the SAME rule: `type ∈ {workout, custom_template}` counts, `status ==
  /// 'completed'` is done) — reads via [getWeek] → [getScheduleForDate], so the
  /// completed→planned demotion the card also reads through is inherited. The
  /// `totalWeeks` span mirrors the card (`train_provider.dart:767-777`, citation
  /// corrected 2026-08-25 — it read `:582-592`, which is hold-streak code):
  /// `phase<=1 ? 4 : scan(weeks 5-12)`, with `phase` from the SAME source
  /// (`current_phase`). This matters — a mid-phase Edit-Profile regen
  /// (`generateAndScheduleFromDate`, which does NOT move `plan_start` when
  /// `!isFirstGeneration`) can leave a `current_phase==1` plan with week-5/6 rows,
  /// so a bare scan would over-count vs the card's 4-week cap (B-pass P2). That
  /// concern is a `phase<=1` one and both sides still cap at 4, so it is untouched
  /// by the hold filter below.
  ///
  /// ⚠ **FOB-7(a), 2026-08-25: the mirror is now DELIBERATELY IMPERFECT.** This
  /// function drops `is_hold` rows; the card does NOT. That asymmetry is correct
  /// and must not be "repaired" by filtering the card: what the Train screen
  /// renders during a hold is FOB-6, which founder split out to **OI-125** as a
  /// FEATURE explicitly not gating the `enable_hold_weeks` flip. Filtering the
  /// card here would ship half of OI-125 by accident.
  ///
  /// Ⓐ No longer INERT-by-two-flags in the sense the old note implied: this
  /// function still runs only when `enable_adherence_gate` is ON (both readers
  /// `&&`-short-circuit), but the hold rows it now excludes are produced by a
  /// SEPARATE flag (`enable_hold_weeks`), and the defect needed both.
  double currentPhaseCompletionRate() {
    final progress = UserRepository.instance.getProgress();
    final phase = (progress?['current_phase'] as int?) ?? 1;
    final int totalWeeks;
    if (phase <= 1) {
      totalWeeks = 4;
    } else {
      var scanned = 4;
      for (int w = 5; w <= 12; w++) {
        // RAW week, deliberately NOT _withoutHoldRows. Round 2 caught the
        // filtered form here as an UNDERCOUNT: a fully-hold week 5 filters to
        // empty, breaks the scan, and silently drops real phase-2 weeks 7-12
        // from BOTH numerator and denominator. This loop answers "how far does
        // the schedule extend", which hold rows legitimately answer; the
        // accumulator below is where holds must not COUNT.
        if (getWeek(w).isEmpty) break;
        scanned = w;
      }
      totalWeeks = scanned;
    }
    final days = <({bool isRest, bool isDone})>[];
    for (int w = 1; w <= totalWeeks; w++) {
      for (final day in _withoutHoldRows(getWeek(w))) {
        final type = (day['type'] as String?) ?? 'rest';
        final isRest = type != 'workout' && type != 'custom_template';
        final status = (day['status'] as String?) ?? 'planned';
        days.add((isRest: isRest, isDone: status == 'completed'));
      }
    }
    return phaseCompletionRate(days);
  }

  /// Schedule rows with hold weeks removed — the input every PHASE-completion
  /// reckoning wants (FOB-7(a) / OI-60).
  ///
  /// A hold week is a free-tier pause the user CHOSE; its days are materialized
  /// `planned` and are not part of any phase's prescribed work. Folding them in
  /// dilutes the rate, and the dilution lands on precisely the user who stayed.
  /// Measured on a seeded reproduction (28 of 28 real days completed, two holds
  /// taken): the rate read **0.667 instead of 1.0** — a perfect record scored as
  /// two-thirds, which `shouldOfferAdvanceChoice` would then read as low
  /// adherence and offer the "detrained / repeat the phase" path to.
  ///
  /// UNGATED on `enable_hold_weeks`, and that is deliberate. It matches the
  /// established precedent one screen over — [completedWeekNumbers] excludes
  /// `row['is_hold'] == true` with no flag check either, and these two are the
  /// non-hold day-sources for closely-related ratios, so they must not drift.
  /// Gating it would leave the rate wrong for exactly the population that can
  /// have hold rows while the flag reads OFF (held once, flag later turned off)
  /// — a byte-identical flag-OFF path bought by keeping a known-wrong number.
  /// Rows can only carry `is_hold` if `holdWeek()` ever ran, so for every user
  /// who never held, this filter is a no-op and behaviour IS byte-identical.
  static Iterable<Map<String, dynamic>> _withoutHoldRows(
          List<Map<String, dynamic>> rows) =>
      rows.where((r) => r['is_hold'] != true);

  /// Current week number (1-4) based on today.
  int getCurrentWeekNumber() {
    final startStr = MigratedKey.read<String>(_planStartKey);
    if (startStr == null) return 1;

    final planStart = DateTime.parse(startStr);
    final today = nowWall(); // seam-aware (dev time-travel / year-sim)
    final diff = today.difference(planStart).inDays;
    return (diff ~/ 7 + 1).clamp(1, 4);
  }

  /// ⑥ Batch 7-A (W3.2 phase arc): the periodization wave character per week of
  /// the CURRENT phase — baseline / overreach / peak / deload, plus `working`
  /// once a deload is lifted (deload_evaluator.dart:231) — read from the
  /// materialized `current_plan` blob (`week_plans[i]['week_character']`,
  /// snake_case per `WeekPlan.toMap`). Read-only DISPLAY source for the
  /// Train-screen wave strip; no engine coupling. Crash-safe: a missing /
  /// malformed / short blob returns `const []` (widget then renders nothing).
  List<String> currentWaveCharacters() {
    final raw = _hive.workoutBox.get(_planKey);
    if (raw is! Map) return const [];
    final weeks = raw['week_plans'];
    if (weeks is! List) return const [];
    return weeks
        .map((w) => (w is Map ? w['week_character'] : null)?.toString() ?? '')
        .toList();
  }

  /// Canonical phase name for the 3-phase deployment cycle (1-indexed):
  /// Foundation → Strength → Hypertrophy, repeating each deployment. Derived
  /// from the phase NUMBER (not the plan blob's `name`, which can go stale /
  /// polluted) so the displayed label never drifts from `current_phase`
  /// (diagnose 2026-06-06).
  static const List<String> phaseCycleNames = [
    'Foundation',
    'Strength',
    'Hypertrophy',
  ];

  /// PURE (visible for testing): canonical phase name from the phase NUMBER.
  @visibleForTesting
  static String phaseNameFor(int phase) =>
      phaseCycleNames[((phase < 1 ? 1 : phase) - 1) % 3];

  /// PURE (visible for testing): 1-based program week within the 12-week
  /// deployment: `phaseInDeployment * 4 + weekInPhase`. e.g. Phase 2 wk 3 → 7.
  @visibleForTesting
  static int programWeekFor(int phase, int weekInPhase) =>
      (((phase < 1 ? 1 : phase) - 1) % 3) * 4 + weekInPhase;

  String phaseName(int phase) => phaseNameFor(phase);

  /// 1-based week within the current 12-week deployment ("program week"),
  /// distinct from [getCurrentWeekNumber] (week WITHIN the 4-week phase, 1-4)
  /// which the phase-relative headline counters use. The 12-week Roadmap uses
  /// this so its counter + % reflect true deployment progress (diagnose
  /// 2026-06-06 — the Roadmap previously fed it the clamped 1-4 phase week and
  /// stuck at "Phase I active / 33% complete").
  int getProgramWeek(int currentPhase) =>
      programWeekFor(currentPhase, getCurrentWeekNumber());

  /// Value to project into the `user_progress.current_week` cloud column on
  /// sync (diagnose c9f4a2). When [disabled] (kill-switch on), returns the
  /// frozen Hive passthrough verbatim — byte-identical to the pre-fix write;
  /// otherwise the derived program week (1..12), which is never null, so the
  /// caller writes it UNCONDITIONALLY. Extracted here so the sync-projection
  /// decision (flag polarity + which value) has a behavioral test that fails
  /// when the runtime path is mis-wired, even if `getProgramWeek` still appears
  /// in the source (rule 21).
  int? currentWeekColumnProjection({
    required int? frozenWeek,
    required int phase,
    required bool disabled,
  }) =>
      disabled ? frozenWeek : getProgramWeek(phase);

  /// 1-based day number within the current Phase.
  int getCurrentDayInPhase() {
    final start = getPlanStartDate();
    if (start == null) return 0;
    final today = nowWall(); // seam-aware (dev time-travel / year-sim)
    final startMidnight = DateTime(start.year, start.month, start.day);
    final todayMidnight = DateTime(today.year, today.month, today.day);
    return todayMidnight.difference(startMidnight).inDays + 1;
  }

  /// True if the current Phase has run its course — i.e., today is past the
  /// stored plan window AND no real workout day is scheduled today or later.
  ///
  /// BUG-A (a1d4f9, APK +34 obs 1/5.1/6): the stored `plan_end_date` (restored
  /// from the cloud `plan_json` snapshot) can LAG the actually-materialized
  /// `scheduled_workouts` when a regeneration advanced the per-day table but the
  /// `plan_json` snapshot never re-persisted (a source-of-truth split; the push
  /// 401 in BUG-C was the enabler). Trusting the stale constant made the app
  /// report "expired / wrong week / not scheduled" even though future workouts
  /// existed (scheduled_workouts ran a month past the stale plan_end_date). We
  /// now treat the plan as expired only if the stored window says so AND there
  /// is no materialized workout day from today onward. Fast-pathed: the schedule
  /// scan only runs when the cheap stored-window check already says expired.
  bool isPhaseExpired() {
    final stored = getPlanEndDate();
    if (stored == null) return false;
    final today = nowWall(); // seam-aware (dev time-travel / year-sim)
    final todayD = DateTime(today.year, today.month, today.day);
    final endD = DateTime(stored.year, stored.month, stored.day);
    if (!todayD.isAfter(endD)) return false; // inside the stored window — fast
    return isPhaseExpiredFrom(today, stored, _scheduledWorkoutDays());
  }

  /// PURE decision behind [isPhaseExpired] (visible for testing — no Hive, no
  /// clock). Expired ⇔ [storedEnd] non-null AND date(today) strictly after
  /// date(storedEnd) AND NO day in [scheduledWorkoutDays] is on/after today. A
  /// future scheduled workout means the plan is still active even if the stored
  /// plan_end_date is stale (the cloud plan_json snapshot lagged the live table).
  @visibleForTesting
  static bool isPhaseExpiredFrom(DateTime today, DateTime? storedEnd,
      Iterable<DateTime> scheduledWorkoutDays) {
    if (storedEnd == null) return false;
    final todayD = DateTime(today.year, today.month, today.day);
    final endD = DateTime(storedEnd.year, storedEnd.month, storedEnd.day);
    if (!todayD.isAfter(endD)) return false;
    for (final d in scheduledWorkoutDays) {
      final dD = DateTime(d.year, d.month, d.day);
      if (!dD.isBefore(todayD)) return false; // a workout today-or-later
    }
    return true;
  }

  /// Dates of real (non-rest/off) scheduled workout days in the local schedule.
  Iterable<DateTime> _scheduledWorkoutDays() {
    final box = _hive.workoutBox;
    final out = <DateTime>[];
    for (final key in box.keys) {
      final k = key.toString();
      if (!k.startsWith(_schedulePrefix)) continue;
      final d = DateTime.tryParse(k.substring(_schedulePrefix.length));
      if (d == null) continue;
      final v = box.get(key);
      if (v is! Map) continue;
      final type = (v['type'] ?? '').toString();
      if (type == 'rest' || type == 'off') continue;
      out.add(d);
    }
    return out;
  }

  /// Plan start date (Monday of Week 1).
  DateTime? getPlanStartDate() {
    final startStr = MigratedKey.read<String>(_planStartKey);
    if (startStr == null) return null;
    return DateTime.parse(startStr);
  }

  /// Plan end date (inclusive — last day of current Phase).
  DateTime? getPlanEndDate() {
    final endStr = MigratedKey.read<String>(_planEndKey);
    if (endStr == null) return null;
    return DateTime.tryParse(endStr);
  }

  /// Current plan deserialized (TODO — currently returns null).
  Phase? getCurrentPlan() {
    final data = _hive.workoutBox.get(_planKey);
    if (data == null) return null;
    return null;
  }

  /// Raw current-plan map.
  Map<String, dynamic>? getCurrentPlanMap() {
    final data = _hive.workoutBox.get(_planKey);
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  /// True if a plan has been generated.
  bool hasPlan() {
    return _hive.workoutBox.containsKey(_planKey);
  }

  /// SoT for prior phase blocks (see [PastPhaseBlock]). Walks `schedule_*`
  /// Hive entries strictly before `plan_start_date`, buckets into 28-day
  /// windows from the earliest, and returns them oldest-first. `length` =
  /// the number of phases the user has completed/moved past. Cheap
  /// (≤~200 keys typical). Used by the week selector (display) and
  /// `PhaseProgressReconciler` (current_phase invariant) — single bucketing
  /// SoT, no drift. Fix 2026-06-02 (two-Phase-1 bug).
  List<PastPhaseBlock> pastPhaseBlocks() =>
      bucketPastRows(_scheduleRowsBefore(getPlanStartDate()));

  /// Every `schedule_*` row, clipped to those strictly before [cutoff] when it
  /// is non-null. ONE walk, shared by [pastPhaseBlocks] and
  /// [pastPhaseBlocksForDisplay], so the two can never drift in how they parse
  /// a row (#1 bug class).
  List<(DateTime, Map<String, dynamic>)> _scheduleRowsBefore(DateTime? cutoff) {
    final rows = <(DateTime, Map<String, dynamic>)>[];
    for (final entry in _hive.workoutBox.toMap().entries) {
      final key = entry.key.toString();
      if (!key.startsWith(_schedulePrefix)) continue;
      final value = entry.value;
      if (value is! Map) continue;
      final map = Map<String, dynamic>.from(value);
      final dateStr = map['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      // Only rows strictly before the active plan window count as "past".
      if (cutoff != null && !date.isBefore(cutoff)) continue;
      rows.add((date, map));
    }
    return rows;
  }

  /// DISPLAY-ONLY recovery wrapper around [pastPhaseBlocks].
  ///
  /// [pastPhaseBlocks] decides "past" SOLELY from `plan_start_date`. When an
  /// account's `current_phase` advanced but `plan_start_date` did NOT move with
  /// it, that filter keeps nothing — the earliest schedule row IS `plan_start`
  /// — so the Train strip renders "PHASE II" as the current group while showing
  /// zero completed phases behind it. Founder account, verified 2026-08-07:
  /// `current_phase=2`, `plan_start=2026-04-27`, earliest row also 2026-04-27,
  /// 77 rows through 2026-07-23 (18 completed) → zero blocks → no PHASE I group
  /// rendered anywhere (diagnose c9e4b7). The window is self-reinforcing:
  /// `_syncWorkoutPlan` mirrors local → cloud `plan_json`, `PlanWindowReanchor`
  /// mirrors it back on restore, so it never heals on its own.
  ///
  /// Recovery: when the strict filter comes back empty AND the counter says at
  /// least one phase is behind us, re-bucket EVERY schedule row and drop the
  /// newest block (the window being trained now). `bucketPastRows` already
  /// handles both stamped-`phase` identity grouping and the 28-day calendar
  /// fallback, so this also works for cloud-restored rows — cloud
  /// `scheduled_workouts` has no `phase` column, so those rows carry no stamp.
  ///
  /// ⚠ DISPLAY ONLY — [pastPhaseBlocks] itself is deliberately left alone.
  /// `PhaseProgressReconciler` feeds on it to ADVANCE `current_phase`
  /// monotonically and irreversibly ("a monotonic over-advance is
  /// unrecoverable", `phase_progress_reconciler.dart:55-58`), so widening its
  /// notion of "past" there could over-advance a counter that can never be
  /// walked back. The reconciler must never call this method.
  List<PastPhaseBlock> pastPhaseBlocksForDisplay(int currentPhase) {
    final strict = pastPhaseBlocks();
    if (strict.isNotEmpty || currentPhase <= 1) return strict;
    final all = bucketPastRows(_scheduleRowsBefore(null));
    // <2 blocks means every row belongs to the window we are training in now —
    // nothing is genuinely behind us, so show nothing rather than invent a group.
    final recovered = all.length < 2 ? const <PastPhaseBlock>[] : all.sublist(0, all.length - 1);
    // Tripwire (2026-08-30) — every account known to hit this branch so far
    // (upendraprasad19@gmail.com, amar@gmail.com) is a test/QA account with
    // no organic Phase-2+ user ever observed in this shape; see diagnose
    // b7f1c8. Pure observability
    // — does not change `recovered`, which is returned either way. Logged at
    // most ONCE per account per session (`_strictEmptyTripwireLogged`) — this
    // method is called from WeekSelector.build(), which rebuilds on every
    // scroll frame; without the guard a session in this state would post a
    // real network call per rebuild instead of once.
    if (!_strictEmptyTripwireLogged) {
      _strictEmptyTripwireLogged = true;
      unawaited(ErrorTelemetry.logEvent(
        'past_phase_blocks_strict_empty',
        message: 'currentPhase=$currentPhase recoveredBlocks=${recovered.length} '
            'phaseStartedAt=${UserRepository.instance.getPhaseStartedAtIso()}',
      ));
    }
    return recovered;
  }

  /// Pure bucketing behind [pastPhaseBlocks] (visible for testing — no Hive).
  ///
  /// F-B (2026-06-05): when ANY past row carries an explicit stamped `phase`
  /// (the plan generator stamps it), group by phase identity with carry-forward
  /// — an unstamped row inherits the nearest preceding stamped phase (leading
  /// unstamped rows take the first stamped phase, B-pass F-2). A single logical
  /// phase becomes ONE block even when its calendar span exceeds 28 days
  /// (gaps/overlaps) — fixing the 28-day-window over-count. Only when NO row is
  /// stamped (fully-legacy data — e.g. the founder's existing duplicate-week
  /// data) does it fall back to the proven 28-day calendar bucketing, which
  /// correctly collapses that duplicate-week residue into one block.
  @visibleForTesting
  static List<PastPhaseBlock> bucketPastRows(
      List<(DateTime, Map<String, dynamic>)> rows) {
    if (rows.isEmpty) return const [];
    final sorted = [...rows]..sort((a, b) => a.$1.compareTo(b.$1));

    // Phase-identity grouping (preferred) — used when ANY past row carries a
    // stamped int `phase`. Unstamped rows (e.g. a SwapService-written or legacy
    // row) INHERIT the phase of the nearest preceding stamped row (carry-forward;
    // leading unstamped rows take the first stamped phase). B-pass F-2: this
    // replaces an all-or-nothing `every` guard so a single unstamped row can't
    // silently collapse the whole dataset back to 28-day bucketing.
    int? firstStamped;
    for (final r in sorted) {
      final raw = r.$2['phase'];
      if (raw is int) {
        firstStamped = raw;
        break;
      }
    }
    if (firstStamped != null) {
      final byPhase = <int, List<Map<String, dynamic>>>{};
      final boundsByPhase = <int, (DateTime, DateTime)>{};
      int carry = firstStamped;
      for (final (date, map) in sorted) {
        final raw = map['phase'];
        final p = raw is int ? raw : carry;
        if (raw is int) carry = raw;
        (byPhase[p] ??= []).add(map);
        final b = boundsByPhase[p];
        // rows are date-ascending → first seen is min, last seen max.
        boundsByPhase[p] = b == null ? (date, date) : (b.$1, date);
      }
      final phases = byPhase.keys.toList()..sort();
      return phases
          .map((p) => PastPhaseBlock(
                startDate: boundsByPhase[p]!.$1,
                endDate: boundsByPhase[p]!.$2,
                rows: byPhase[p]!,
              ))
          .toList();
    }

    // Legacy fallback — 28-day calendar bucketing from the earliest row.
    final earliest = sorted.first.$1;
    final byBucket = <int, List<Map<String, dynamic>>>{};
    final boundsByBucket = <int, (DateTime, DateTime)>{};
    for (final (date, map) in sorted) {
      final idx = date.difference(earliest).inDays ~/ 28;
      (byBucket[idx] ??= []).add(map);
      final bounds = boundsByBucket[idx];
      // rows are date-ascending → first seen is the min, last seen the max.
      boundsByBucket[idx] =
          bounds == null ? (date, date) : (bounds.$1, date);
    }
    final sortedIdxs = byBucket.keys.toList()..sort();
    return sortedIdxs
        .map((idx) => PastPhaseBlock(
              startDate: boundsByBucket[idx]!.$1,
              endDate: boundsByBucket[idx]!.$2,
              rows: byBucket[idx]!,
            ))
        .toList();
  }

  /// The phase number that was active on [date].
  ///
  /// Returns `current_phase` when [date] is in (or after) the active plan
  /// window, else the 1-based index of the [pastPhaseBlocks] bucket the date
  /// falls in — so a workout receipt for a past day shows the phase it was
  /// logged under instead of a hardcoded "PHASE 1" (Obs 1, 2026-06-05). Reuses
  /// the SAME bucketing as the week selector + reconciler (single SoT, no
  /// parallel reader). Null-safe: falls back to `current_phase` (or 1).
  int phaseForDate(DateTime date) {
    try {
      final progress = UserRepository.instance.getProgress();
      final currentPhase = (progress?['current_phase'] as int?) ?? 1;
      final planStart = getPlanStartDate();
      final blockStarts = pastPhaseBlocks().map((b) => b.startDate).toList();
      return phaseForDatePure(currentPhase, planStart, date, blockStarts);
    } catch (e, st) {
      // Hive not ready (e.g. a pure unit test that didn't open userBox) →
      // display-only fallback, never crash the receipt. In prod the boxes ARE
      // open, so an exception here is a real (programming) error — record it
      // non-fatally so a silent wrong-phase regression stays observable
      // instead of always rendering "PHASE 1" (B-pass F-5).
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'phase_for_date_fallback'));
      return 1;
    }
  }

  /// Pure decision behind [phaseForDate] (visible for testing — no Hive).
  /// [blockStarts] are the `pastPhaseBlocks()` start dates, oldest-first.
  /// In/after the plan window → [currentPhase]; else the 1-based index of the
  /// last block whose start ≤ [date] (gaps resolve to the preceding phase;
  /// before all blocks → 1).
  @visibleForTesting
  static int phaseForDatePure(int currentPhase, DateTime? planStart,
      DateTime date, List<DateTime> blockStarts) {
    if (planStart == null || !date.isBefore(planStart)) return currentPhase;
    final d = DateTime(date.year, date.month, date.day);
    int phase = 1;
    for (var i = 0; i < blockStarts.length; i++) {
      final s = blockStarts[i];
      final sMid = DateTime(s.year, s.month, s.day);
      if (!d.isBefore(sMid)) {
        phase = i + 1;
      } else {
        break; // oldest-first → once a block starts after the date, stop
      }
    }
    return phase;
  }

  /// All dates in the current calendar week (Mon–Sun).
  List<Map<String, dynamic>> getCurrentCalendarWeek() {
    final today = nowWall(); // seam-aware (dev time-travel / year-sim)
    final monday = _normalizeToMonday(today);
    final days = <Map<String, dynamic>>[];

    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final schedule = getScheduleForDate(date);
      if (schedule != null) {
        days.add(schedule);
      } else {
        days.add({
          'date': _dateKey(date),
          'day_of_week': i,
          'type': 'none',
          'workout_name': '',
          'status': 'none',
        });
      }
    }
    return days;
  }

  /// Day pattern (which weekdays are workout days).
  List<int> getDayPattern(int daysPerWeek) => _getDayPattern(daysPerWeek);

  /// Normalise a date to Monday of its week.
  DateTime normalizeToMonday(DateTime date) => _normalizeToMonday(date);

  /// Computes the start date for a NEW phase.
  ///
  /// Bug 2026-05-22 (Theme H, obs 11) — graduation_screen + autoGenerateNext
  /// previously passed `DateTime.now()` directly into [generateAndSchedule],
  /// which normalizeToMonday-ed it to THIS week's Monday. For a user mid-
  /// Phase-1-Week-4 tapping unlock on Wed, that overwrote Phase 1 W4
  /// (Mon-Sun of current week) with a fresh Phase 2 W1 — visibly corrupting
  /// the completed-history view.
  ///
  /// Correct semantic: new phase starts the MONDAY AFTER the current phase
  /// ends. Reads `plan_end_date` (already stored by every [generateAndSchedule]
  /// call at line 104) and returns `(plan_end + 1 day)` Monday-normalized.
  /// Falls back to `max(today, today)` if `plan_end_date` is missing
  /// (defensive — every code path that calls this should have generated
  /// a phase first).
  ///
  /// The `max(today, currentPhaseEnd + 1)` guard handles the edge case
  /// where a user lets Phase 1 expire (e.g. inactivity) — start the new
  /// phase from THIS Monday, not retroactively from the historical end.
  DateTime nextPhaseStartDate({DateTime? now}) {
    final today = now ?? nowWall(); // seam-aware (dev time-travel / year-sim)
    final endStr = MigratedKey.read<String>(_planEndKey);
    if (endStr != null) {
      final end = DateTime.tryParse(endStr);
      if (end != null) {
        final candidate = end.add(const Duration(days: 1));
        final useDate = candidate.isAfter(today) ? candidate : today;
        return _normalizeToMonday(useDate);
      }
    }
    return _normalizeToMonday(today);
  }

  /// Format date as YYYY-MM-DD.
  String dateKey(DateTime date) => _dateKey(date);

  // ── Helpers ─────────────────────────────────────────────────────

  List<int> _getDayPattern(int daysPerWeek) {
    switch (daysPerWeek) {
      case 3:
        return [0, 2, 4];
      case 4:
        return [0, 1, 3, 5];
      case 5:
        return [0, 1, 2, 4, 5];
      case 6:
        return [0, 1, 2, 3, 4, 5];
      default:
        return [0, 1, 3, 5];
    }
  }

  DateTime _normalizeToMonday(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  String _dateKey(DateTime date) => formatDateKey(date);
}
