// lib/features/dev/simulation_service.dart
//
// DEBUG-ONLY year-simulation harness. Drives the REAL write path
// (WorkoutWriteService / HealthWriteService / NutritionWriteService) +
// the REAL phase-generation + rank-evaluation code, dating every write to
// a simulated day via the clock seam (`setTestClock` in
// `lib/core/utils/ist_date.dart`). Lets us watch a full free→PRO journey
// (Phase 1 free, Phases 2-12 PRO) progress over ~1 simulated year without
// waiting real time.
//
// Built 2026-05-31 for the "simulate the entire 12-week journey to one
// year for amar" exercise. The clock seam is a hard release no-op
// (`setTestClock` returns immediately when `dart.vm.product` is true) and
// this file is only ever invoked from the kDebugMode-gated `/dev` panel,
// so it can never run in a production build.
//
// Engine: clock-seam time-travel + real WriteServices (the founder-locked
// "in-app sim driver, real path"). The seam-aware reads it relies on
// (schedule phase-expiry, rank weeks-since-signup, streak walk-back) were
// routed through `nowWall()` in the same batch.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Aggregated outcome of a simulation run. All fields mutable so the run
/// loop can tally as it goes.
class SimReport {
  int daysSimulated = 0;
  int workoutsCompleted = 0;
  int workoutsSkipped = 0;
  int restDays = 0;
  int mealsLogged = 0;
  int phasesGenerated = 0;
  DateTime? startDate;
  DateTime? endDate;
  final List<String> events = [];

  /// 2026-05-31 — every generated phase's week-1 plan, captured so the run can
  /// export "all workout plans to Lieutenant" to Excel (SpreadsheetML). Each
  /// entry: {phase, deployment, name, focus, weeks, rank, days:[{name, focus,
  /// exercises:[{name, sets, reps, suggested_weight, weight_cue, logging_type}]}]}.
  final List<Map<String, dynamic>> capturedPhases = [];

  String summarize() {
    final b = StringBuffer();
    b.writeln('── Simulation report ──');
    b.writeln('Range: ${startDate == null ? "?" : istDateStr(startDate!)}'
        ' → ${endDate == null ? "?" : istDateStr(endDate!)}');
    b.writeln('Days simulated:      $daysSimulated');
    b.writeln('Workouts completed:  $workoutsCompleted');
    b.writeln('Workouts skipped:    $workoutsSkipped');
    b.writeln('Rest days:           $restDays');
    b.writeln('Meals logged:        $mealsLogged');
    b.writeln('Phases generated:    $phasesGenerated');
    if (events.isNotEmpty) {
      b.writeln('Milestones:');
      for (final e in events) {
        b.writeln('  • $e');
      }
    }
    return b.toString();
  }
}

/// Debug-only deterministic simulation driver. Singleton; holds a sim
/// cursor + seeded RNG so chunked runs from the dev panel are reproducible
/// and resumable.
class SimulationService {
  SimulationService._();
  static final SimulationService instance = SimulationService._();

  static const int _seed = 424242;

  Random _rng = Random(_seed);
  DateTime? _cursor;
  bool _busy = false;

  bool get isBusy => _busy;
  DateTime? get cursor => _cursor;

  /// Hard reset amar (or whoever is signed in) to a clean day-0 baseline:
  /// free tier, rank SD2, day-0 progress counters, and a freshly-generated
  /// Phase 1 starting this week's Monday. The cloud-side cleanup (deleting
  /// stray logs + rank_promotions) is done out-of-band via Supabase; this
  /// handles the local Hive state so the two agree after sync.
  Future<void> resetJourney(WidgetRef ref) async {
    if (!kDebugMode) return;
    // Ensure user-scoped Hive boxes are open (the panel may be reached via a
    // deep link to /dev before the post-auth session bootstrap ran).
    await HiveUserSession.ensureOpenedForCurrentSession();
    resetTestClock();
    final read = ref.read(workoutScheduleReadServiceProvider);
    final profile = UserRepository.instance.getProfile() ?? {};

    // Wipe all previously-logged journey data so re-runs start clean (the
    // WriteServices key by date; without this a re-drive double-logs).
    await _clearKeysWithPrefixes(HiveService.instance.workoutBox, const [
      'exlog_', 'wlog_', 'schedule_', 'displaced_', 'exercise_log_index_'
    ]);
    await _clearKeysWithPrefixes(HiveService.instance.healthBox,
        const ['weight_', 'sleep_log_', 'water_ml_', 'hydration_', 'step_']);
    await HiveService.instance.healthBox.delete('streaks');
    await HiveService.instance.healthBox.delete('steps_today');
    await HiveService.instance.healthBox.delete('steps_date');
    await _clearKeysWithPrefixes(
        HiveService.instance.nutritionBox, const ['nlog_']);

    // Free tier.
    await ref.read(subscriptionServiceProvider).writeSubscriptionState(
          isPro: false,
          expiresAt: '',
          plan: 'free',
        );

    // Day-0 progress + rank floor (SD2 = the recruit rung).
    final prog = Map<String, dynamic>.from(
        UserRepository.instance.getProgress() ?? {});
    prog['current_phase'] = 1;
    prog['current_week'] = 1;
    prog['total_workouts_done'] = 0;
    prog['current_streak_days'] = 0;
    prog['current_streak_weeks'] = 0;
    prog['last_streak_week'] = -1;
    prog.remove('last_workout_date');
    await UserRepository.instance.saveProgress(prog);

    final prof = Map<String, dynamic>.from(profile);
    prof['current_rank_code'] = 'SD2';
    prof.remove('current_rank_achieved_at');
    await UserRepository.instance.saveProfile(prof);

    // Fresh Phase 1 starting this Monday (overwrites the existing plan +
    // non-completed schedule; advances plan_start/plan_end via line 103-104).
    await read.generateAndSchedule(
      goal: (prof['primary_goal'] as String?) ?? 'general_fitness',
      equipment: (prof['equipment_access'] as String?) ?? 'bodyweight',
      daysPerWeek: (prof['days_per_week'] as num?)?.toInt() ?? 4,
      startDate: istMidnight(DateTime.now()),
      experienceLevel: (prof['fitness_experience'] as String?) ?? 'intermediate',
      phase: 1,
    );

    resetCursor(ref);
  }

  /// Reset the cursor to the plan start (day-0 of the journey) and reseed
  /// the RNG so a fresh run is reproducible.
  void resetCursor(WidgetRef ref) {
    final read = ref.read(workoutScheduleReadServiceProvider);
    final start = read.getPlanStartDate();
    _cursor = start != null
        ? DateTime(start.year, start.month, start.day)
        : istMidnight(DateTime.now());
    _rng = Random(_seed);
  }

  /// Drive [days] simulated days forward from the current cursor.
  ///
  /// Each day: sets the app's "now" to that day's evening via the clock
  /// seam, completes the scheduled workout (subject to [adherence] + a
  /// deliberate streak-break window), logs weight / 3 meals / water /
  /// sleep / steps dated to that day, advances the phase via the REAL
  /// auto-gen path when expired + PRO, and evaluates rank weekly.
  Future<SimReport> run({
    required WidgetRef ref,
    required int days,
    double adherence = 0.85,
    void Function(String line)? onProgress,
  }) async {
    final report = SimReport();
    if (_busy) {
      report.events.add('run() ignored — a simulation is already in flight');
      return report;
    }
    if (!kDebugMode) {
      report.events.add('run() ignored — not a debug build');
      return report;
    }
    _busy = true;
    await HiveUserSession.ensureOpenedForCurrentSession();
    // Suppress the per-write snapshot storm during the bulk backfill; we fire
    // ONE pushSnapshot + a steps push at the end. Per-domain syncs (workout /
    // weight / sleep / nutrition / water) still fire live so the cloud stays
    // current and sync stays under test.
    SyncService.pausedForSimulation = true;
    // Keep the dev-granted PRO alive: the sim user has no real subscriptions
    // row, so an un-paused refreshFromSupabase would downgrade mid-run and
    // gate off phase generation (stuck-at-Phase-1 → rank stuck at SD2).
    SubscriptionService.pausedForSimulation = true;
    try {
      final read = ref.read(workoutScheduleReadServiceProvider);
      final sub = ref.read(subscriptionServiceProvider);

      _cursor ??= () {
        final s = read.getPlanStartDate();
        return s != null
            ? DateTime(s.year, s.month, s.day)
            : istMidnight(DateTime.now());
      }();
      var cursor = _cursor!;
      report.startDate = cursor;

      // Capture the phase the run starts on (free Phase 1, or wherever a resumed
      // run picks up) so the Excel export covers the full journey to Lieutenant.
      _captureCurrentPlan(
          read,
          report,
          (UserRepository.instance.getProgress()?['current_phase'] as int?) ?? 1);

      final profile = UserRepository.instance.getProfile() ?? {};

      for (int i = 0; i < days; i++) {
        // App "now" = this simulated day at 19:30 local. nowWall() (used by
        // schedule / rank / streak reads) now resolves to this instant.
        setTestClockTo(DateTime(cursor.year, cursor.month, cursor.day, 19, 30));

        // Weekly streak-freeze refill (what the real app does on day-rollover
        // / splash). Idempotent per simulated Monday; free=1/PRO=3 internally.
        // Without this the ~15% adherence skips break the streak every week so
        // rank can never clear the SD1(7)/LS(14) streak gates.
        StreakProgressService.instance.refillIfNewWeek();

        await _simulateDay(ref, cursor, adherence, report);

        // Real phase-rollover path: PRO + expired → generate next phase.
        // Phase gen is local (plan generator + Hive) — no network in-loop.
        if (sub.isPro()) {
          await _maybeAdvancePhase(ref, profile, report);
        }

        // Weekly rank evaluation — mirrors PRODUCTION cadence (the real app
        // calls evaluateAndPromote after every workout / on splash / via cron).
        // RANK IS A PEAK (monotonic): rank_promotions keeps every rung ever
        // crossed and current_rank_code never demotes. A single eval at the END
        // of the run only sees the END-state streak, so a mid-year 14+ streak
        // (Leading Seaman) that later decays to ~11 would NEVER be recorded —
        // the harness would under-report rank progression vs production. So we
        // evaluate at each simulated week boundary while the seam clock is at
        // that week. evaluateAndPromote is idempotent (upsert by rank_code) and
        // self-guards errors; weekly (not per-day) keeps the in-loop cloud I/O
        // to ~52 sequential awaited calls over a year — no concurrency storm.
        if (i % 7 == 6) {
          await RankService.instance.evaluateAndPromote();
        }

        report.daysSimulated++;
        onProgress?.call('Day ${i + 1}/$days — ${istDateStr(cursor)}');

        cursor = cursor.add(const Duration(days: 1));
        _cursor = cursor;
      }

      report.endDate = cursor.subtract(const Duration(days: 1));

      // Loop done. Unpause and bulk-flush EVERYTHING in one controlled pass.
      // Per-write sync was suppressed during the loop so the bulk historical
      // backfill didn't flood Supabase auth (token-refresh 504 storm) +
      // pushSnapshot. Now there's no concurrency storm, so one pass per domain
      // pushes the whole journey cleanly with a single fresh token.
      SyncService.pausedForSimulation = false;
      final sync = ref.read(syncServiceProvider);
      Future<void> flush(String label, Future<void> Function() f) async {
        try {
          await f();
        } catch (e) {
          report.events.add('sync $label failed: $e');
        }
      }
      await flush('workout', sync.syncWorkoutData);
      await flush('nutrition+water', sync.syncNutritionData);
      await flush('weight', sync.syncWeightNow);
      await flush('sleep', sync.syncSleepNow);
      await flush('measurements', sync.syncMeasurementsNow);
      await flush('steps', sync.pushStepsLogsForSyncDomain);

      // Final rank pass (cloud read/write) + record the end-state rank.
      await RankService.instance.evaluateAndPromote();
      final rank = RankService.instance.getCurrentRank();
      report.events.add('End rank: ${rank.entry.code} (${rank.entry.displayName})');

      await flush('snapshot', sync.pushSnapshot);
    } finally {
      SyncService.pausedForSimulation = false;
      SubscriptionService.pausedForSimulation = false;
      _busy = false;
    }
    return report;
  }

  // ── Per-day simulation ────────────────────────────────────────────

  Future<void> _simulateDay(
    WidgetRef ref,
    DateTime day,
    double adherence,
    SimReport report,
  ) async {
    final read = ref.read(workoutScheduleReadServiceProvider);
    final dateStr = istDateStr(day);
    final sched = read.getScheduleForDate(day);

    // ── Workout ──
    if (sched != null && (sched['type'] as String?) == 'workout') {
      final alreadyDone = (sched['status'] as String?) == 'completed';
      if (!alreadyDone) {
        final inBreak = _inStreakBreakWindow(ref, day);
        final doWorkout = !inBreak && _rng.nextDouble() < adherence;
        if (doWorkout) {
          await _completeScheduledWorkout(ref, day, sched, report);
        } else {
          report.workoutsSkipped++;
        }
      }
    } else if (sched != null && (sched['type'] as String?) == 'rest') {
      report.restDays++;
    }

    // ── Weight (slow trend toward target with noise) ──
    await _logWeight(ref, day);

    // ── Nutrition (3 meals on adherent days) ──
    if (_rng.nextDouble() < adherence) {
      await _logMeals(day);
      report.mealsLogged += 3;
    }

    // ── Water (overwrite total for the day) ──
    await HealthWriteService.instance.setWaterMl(
      date: day,
      totalMl: 2000 + _rng.nextInt(1200),
      source: WriteSource.manual,
    );

    // ── Sleep ──
    await HealthWriteService.instance.logSleep(
      date: day,
      hours: 6.3 + _rng.nextDouble() * 2.2,
      quality: 'good',
      source: WriteSource.manual,
    );

    // ── Steps (no WriteService — write the step_log Hive entry directly,
    //    matching HealthSyncService's shape so sync_health pushes it). ──
    await HiveService.instance.healthBox.put('step_$dateStr', {
      'type': 'step_log',
      'date': dateStr,
      'steps': 5500 + _rng.nextInt(7000),
      'source': 'simulation',
      'created_at': DateTime(day.year, day.month, day.day, 21).toIso8601String(),
    });
  }

  /// Skip the entirety of one calendar week (~Phase 2 / week 2) to create a
  /// deliberate streak break, so we can verify freeze-consumption +
  /// streak-reset behaviour.
  bool _inStreakBreakWindow(WidgetRef ref, DateTime day) {
    final start = ref.read(workoutScheduleReadServiceProvider).getPlanStartDate();
    if (start == null) return false;
    final dayNum = day.difference(DateTime(start.year, start.month, start.day)).inDays;
    return dayNum >= 35 && dayNum < 42; // days 35-41 = the streak-break week
  }

  Future<void> _completeScheduledWorkout(
    WidgetRef ref,
    DateTime day,
    Map<String, dynamic> sched,
    SimReport report,
  ) async {
    final exercises = (sched['exercises'] as List?) ?? const [];
    final start = ref.read(workoutScheduleReadServiceProvider).getPlanStartDate();
    final weeksIn = start == null
        ? 0
        : day.difference(DateTime(start.year, start.month, start.day)).inDays ~/ 7;

    for (final raw in exercises) {
      if (raw is! Map) continue;
      final ex = Map<String, dynamic>.from(raw);
      final name = (ex['exercise_name'] as String?) ?? (ex['name'] as String?);
      if (name == null || name.trim().isEmpty) continue;

      final loggingType = (ex['logging_type'] as String?) ?? 'weight_reps';
      final targetSets = (ex['sets'] as num?)?.toInt() ?? 3;
      final targetReps = _parseReps(ex['reps']);
      final baseWeight = (ex['suggested_weight'] as num?)?.toDouble() ?? 0.0;
      // Progressive overload: ~+0.5 kg per simulated week.
      final weight = baseWeight + (weeksIn * 0.5);
      final durationSec = (ex['duration_seconds'] as num?)?.toInt() ?? 45;

      final sets = <ExerciseSet>[];
      final baseMs = DateTime(day.year, day.month, day.day, 19, 35).millisecondsSinceEpoch;
      for (int s = 0; s < targetSets; s++) {
        if (loggingType == 'timed' || loggingType == 'cardio') {
          sets.add(ExerciseSet(
            weightKg: 0,
            reps: 0,
            durationSec: durationSec,
            loggedAtMs: baseMs + s * 90000,
          ));
        } else if (loggingType.contains('bodyweight')) {
          sets.add(ExerciseSet(
            weightKg: 0,
            reps: targetReps,
            loggedAtMs: baseMs + s * 90000,
          ));
        } else {
          sets.add(ExerciseSet(
            weightKg: weight,
            reps: targetReps,
            loggedAtMs: baseMs + s * 90000,
          ));
        }
      }

      await WorkoutWriteService.instance.logExercise(
        date: day,
        exerciseName: name,
        sets: sets,
        source: WriteSource.activeWorkout,
      );
    }

    await WorkoutWriteService.instance.markCompleted(
      date: day,
      workoutName: (sched['workout_name'] as String?) ?? 'Workout',
      durationSec: 2100 + _rng.nextInt(1500),
    );

    // Replicate the progress bump that train_provider.completeWorkout does
    // after the service writes (markCompleted does NOT touch user_progress).
    final repo = WorkoutRepository.instance;
    final progress = UserRepository.instance.getProgress() ?? {};
    final totalDone = ((progress['total_workouts_done'] as int?) ?? 0) + 1;
    // Mutating variant. NOTE (Hermes L1, f9d2e7): this calls consume DIRECTLY,
    // intentionally bypassing reckonStreakDecayAndPersist's restoreCompletedTick +
    // non-empty-schedule gates — the sim drives its own clock seam and never waits
    // for a real restore tick. Dev-only (kDebugMode, release-inert); NOT a third
    // production consume site (reckon's "single site" docstring means prod).
    final streakDays = repo.consumeMissedDayIfFreezeAvailable(); // seam-aware (sim)
    await UserRepository.instance.updateProgress({
      'total_workouts_done': totalDone,
      'current_streak_days': streakDays,
      'last_workout_date': istDateStr(day),
    });

    report.workoutsCompleted++;
  }

  Future<void> _logWeight(WidgetRef ref, DateTime day) async {
    final profile = UserRepository.instance.getProfile() ?? {};
    final startW = (profile['weight_kg'] as num?)?.toDouble() ??
        (profile['current_weight_kg'] as num?)?.toDouble() ??
        75.0;
    final targetW = (profile['target_weight_kg'] as num?)?.toDouble() ?? startW;
    final start = ref.read(workoutScheduleReadServiceProvider).getPlanStartDate();
    final dayNum = start == null
        ? 0
        : day.difference(DateTime(start.year, start.month, start.day)).inDays;
    // Converge ~50% of the gap over a year, plus daily noise.
    final progressFrac = (dayNum / 365.0).clamp(0.0, 1.0);
    final trend = startW + (targetW - startW) * progressFrac * 0.5;
    final noise = (_rng.nextDouble() - 0.5) * 0.6;
    final w = (trend + noise).clamp(35.0, 250.0);
    await HealthWriteService.instance.logWeight(
      date: day,
      weightKg: double.parse(w.toStringAsFixed(1)),
      source: WriteSource.manual,
    );
  }

  Future<void> _logMeals(DateTime day) async {
    // ~2200 kcal / ~150 g protein split across 3 meals, with noise.
    Future<void> meal(String type, double cal, double pro, double carb,
        double fat, String name) async {
      await NutritionWriteService.instance.logMeal(
        date: day,
        mealType: type,
        items: [
          FoodItem(
            name: name,
            quantityG: 300,
            calories: cal + _rng.nextInt(80) - 40,
            protein: pro + _rng.nextInt(10) - 5,
            carbs: carb,
            fat: fat,
            fiber: 4,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
    }

    await meal('breakfast', 550, 35, 60, 18, 'Eggs, oats & banana');
    await meal('lunch', 800, 55, 85, 22, 'Chicken, rice & dal');
    await meal('dinner', 750, 55, 70, 20, 'Paneer, roti & salad');
  }

  Future<void> _maybeAdvancePhase(
    WidgetRef ref,
    Map<String, dynamic> profile,
    SimReport report,
  ) async {
    final read = ref.read(workoutScheduleReadServiceProvider);
    if (!read.isPhaseExpired()) return;

    final progress = UserRepository.instance.getProgress() ?? {};
    final currentPhase = (progress['current_phase'] as int?) ?? 1;
    // 2026-05-31 (post-12 deployment cycles): no phase cap — phases generate
    // indefinitely so the sim can drive a user past phase 12 through the
    // deployment cycles all the way to Lieutenant (~phase 32 / 130 weeks).

    final rawInjuries = profile['injuries'];
    final injuries = rawInjuries is List
        ? rawInjuries.map((e) => e.toString()).toList()
        : const <String>[];

    final generated = await read.autoGenerateNextPhaseIfNeeded(
      goal: (profile['primary_goal'] as String?) ?? 'general_fitness',
      equipment: (profile['equipment_access'] as String?) ?? 'bodyweight',
      daysPerWeek: (profile['days_per_week'] as num?)?.toInt() ?? 4,
      experienceLevel:
          (profile['fitness_experience'] as String?) ?? 'intermediate',
      currentPhase: currentPhase,
      injuries: injuries,
      sessionDuration: (profile['session_duration_minutes'] as num?)?.toInt(),
    );

    if (generated) {
      final updated = Map<String, dynamic>.from(progress);
      updated['current_phase'] = currentPhase + 1;
      updated['current_week'] = 1;
      updated['plan_generated_at'] = nowWall().toIso8601String();
      updated['phase_started_at'] = nowWall().toIso8601String();
      await UserRepository.instance.saveProgress(updated);
      unawaited(ref.read(syncServiceProvider).pushSnapshot());
      report.phasesGenerated++;
      report.events.add(
          'Phase ${currentPhase + 1} generated on ${istDateStr(nowWall())}');
      _captureCurrentPlan(read, report, currentPhase + 1);
    }
  }

  /// Captures the just-generated phase's week-1 plan into [report] for the
  /// Excel export. Reads the canonical `current_plan` Hive map (already includes
  /// the personalized `suggested_weight` / `weight_cue` from ProgressionResolver).
  /// Deduped by phase number so resumed/repeat runs don't double-record.
  void _captureCurrentPlan(
    WorkoutScheduleReadService read,
    SimReport report,
    int phaseNum,
  ) {
    try {
      if (report.capturedPhases.any((p) => p['phase'] == phaseNum)) return;
      final plan = read.getCurrentPlanMap();
      if (plan == null) return;

      // Week-1 days: prefer `workouts` (week-1 convenience list), else
      // week_plans[0].workout_days.
      List daysRaw = (plan['workouts'] as List?) ?? const [];
      if (daysRaw.isEmpty) {
        final wp = plan['week_plans'] as List?;
        if (wp != null && wp.isNotEmpty && wp.first is Map) {
          daysRaw = (wp.first as Map)['workout_days'] as List? ?? const [];
        }
      }

      final days = <Map<String, dynamic>>[];
      for (final d in daysRaw) {
        if (d is! Map) continue;
        final exsRaw = (d['exercises'] as List?) ?? const [];
        final exs = <Map<String, dynamic>>[];
        for (final e in exsRaw) {
          if (e is! Map) continue;
          exs.add({
            'name': e['exercise_name'] ?? e['name'] ?? '',
            'sets': e['sets'],
            'reps': e['reps'],
            'suggested_weight': e['suggested_weight'],
            'weight_cue': e['weight_cue'],
            'logging_type': e['logging_type'],
          });
        }
        days.add({
          'name': d['name'] ?? '',
          'focus': d['focus'] ?? '',
          'exercises': exs,
        });
      }

      report.capturedPhases.add({
        'phase': phaseNum,
        'deployment': phaseNum > 1 ? phaseNum - 1 : 0,
        'name': plan['name'] ?? 'Phase $phaseNum',
        'focus': plan['focus'] ?? '',
        'weeks': plan['weeks'] ?? '',
        'rank': RankService.instance.getCurrentRank().entry.code,
        'captured_on': istDateStr(nowWall()),
        'days': days,
      });
    } catch (e) {
      report.events.add('capture phase $phaseNum failed: $e');
    }
  }

  /// Deletes every key in [box] whose string form starts with any of
  /// [prefixes]. [box] is a Hive `Box` (typed dynamic to avoid the import).
  Future<void> _clearKeysWithPrefixes(Box box, List<String> prefixes) async {
    final toDelete = <dynamic>[];
    for (final k in box.keys) {
      final ks = k.toString();
      if (prefixes.any(ks.startsWith)) toDelete.add(k);
    }
    if (toDelete.isNotEmpty) await box.deleteAll(toDelete);
  }

  int _parseReps(dynamic reps) {
    if (reps is num) return reps.toInt();
    if (reps is String) {
      // "8-12" → 10, "10" → 10, "AMRAP" → 12
      final m = RegExp(r'(\d+)').allMatches(reps).map((e) => int.parse(e.group(1)!)).toList();
      if (m.isEmpty) return 12;
      if (m.length == 1) return m.first;
      return ((m.first + m[1]) / 2).round();
    }
    return 10;
  }
}
