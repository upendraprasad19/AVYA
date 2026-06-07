import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'sync_service.dart';
import 'write_result.dart';

/// The ONE writer for workout_logs / workout_log_exercises /
/// workout_log_sets. All Hive `exlog_*`, `wlog_*`, and `schedule_<date>`
/// mutations flow through this service.
///
/// Per-(date, exerciseName) mutex serializes concurrent writes — two
/// simultaneous logExercise calls for the same exercise will merge
/// their sets into a single Hive entry rather than racing.
///
/// Hive key scheme (post Plan A):
/// - `exlog_<istDateStr>_<hash(name)>`  — deterministic; one row per
///   (date, exerciseName).
/// - `wlog_<istDateStr>`                — workout-level summary.
/// - `schedule_<istDateStr>`            — schedule entry.
///
/// Cloud sync is 3-tier (writes 1 + 1 + N rows):
/// - `workout_logs`             (1 per date)
/// - `workout_log_exercises`    (1 per (date, exerciseName))
/// - `workout_log_sets`         (N per (date, exerciseName) — one per
///                               ExerciseSet)
///
/// Cloud sync fires fire-and-forget after the Hive write succeeds.
class WorkoutWriteService {
  WorkoutWriteService._();
  static final WorkoutWriteService instance = WorkoutWriteService._();

  /// Per-key mutex. Key format: `<istDateStr>::<exerciseName>` for
  /// per-exercise methods, `<istDateStr>` for schedule-only methods.
  final Map<String, Completer<void>> _locks = {};

  /// 60-second dedup window for per-set duplicate detection.
  static const int kDedupWindowMs = 60000;

  /// Provider invalidation batch fired after every successful write.
  /// Caller injects [ref] when running under Riverpod; pure-Hive
  /// callers (tests, headless paths) pass null.
  void Function(WidgetRef ref)? onInvalidate;

  // ─────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────

  Future<WriteResult> logExercise({
    required DateTime date,
    required String exerciseName,
    required List<ExerciseSet> sets,
    String? notes,
    required WriteSource source,
    WidgetRef? ref,
    /// APK Test #12 / Task A-2 — receipt scoping. Stamps the parent
    /// workout session id on this exercise log row. Receipt query for
    /// a date can then filter by `workout_log_id` to show only that
    /// session's exercises (not all exercises logged on that IST date).
    /// Defaults to `wlogKey(date)` (one workout per IST date) — for
    /// users with multiple sessions per day, the caller should pass an
    /// explicit id (e.g. `'wlog_<date>_<sequence>'`).
    String? workoutLogId,
  }) async {
    // 1. Validate
    if (exerciseName.trim().isEmpty) {
      return WriteResult.fail('exerciseName must be non-empty');
    }
    if (sets.isEmpty) {
      return WriteResult.fail('sets must be non-empty');
    }
    for (final s in sets) {
      if (s.weightKg < 0) return WriteResult.fail('weightKg must be >= 0');
      if (s.reps < 0) return WriteResult.fail('reps must be >= 0');
    }

    final dateStr = istDateStr(date);
    final lockKey = '$dateStr::${exerciseName.toLowerCase().trim()}';
    final c = await _acquireLock(lockKey);

    try {
      final box = HiveService.instance.workoutBox;
      final key = exlogKey(date, exerciseName);
      final existing = box.get(key);

      // 2. Build merged sets[] list with 60s dedup
      final List<ExerciseSet> mergedSets;
      if (existing != null) {
        final m = (existing as Map).cast<String, dynamic>();
        final existingSets = (m['sets'] as List? ?? const [])
            .cast<Map>()
            .map((e) => ExerciseSet.fromMap(e))
            .toList();

        final List<ExerciseSet> additions = [];
        for (final candidate in sets) {
          // Stamp loggedAtMs if caller didn't.
          final stamped = candidate.loggedAtMs == null
              ? ExerciseSet(
                  weightKg: candidate.weightKg,
                  reps: candidate.reps,
                  durationSec: candidate.durationSec,
                  loggedAtMs: DateTime.now().millisecondsSinceEpoch,
                )
              : candidate;

          // Dedup against existing sets (60s window).
          final isDup = existingSets.any((existing) =>
              stamped.isDuplicateWithin(existing, windowMs: kDedupWindowMs));
          if (!isDup) additions.add(stamped);
        }

        mergedSets = [...existingSets, ...additions];
      } else {
        mergedSets = sets
            .map((s) => s.loggedAtMs == null
                ? ExerciseSet(
                    weightKg: s.weightKg,
                    reps: s.reps,
                    durationSec: s.durationSec,
                    loggedAtMs: DateTime.now().millisecondsSinceEpoch,
                  )
                : s)
            .toList();
      }

      // 3. Recompute aggregates
      final totalReps = mergedSets.fold<int>(0, (a, s) => a + s.reps);
      final maxWeight = mergedSets.fold<double>(
          0.0, (a, s) => s.weightKg > a ? s.weightKg : a);
      final volume = mergedSets.fold<double>(
          0.0, (a, s) => a + (s.weightKg * s.reps));

      // APK Test #12.5 / Class 1a-1b — library-aware logging_type +
      // phantom-durationSec stripping.
      //
      // Pre-fix `_inferLoggingType` was data-shape-only: it returned
      // `'timed'` whenever any set had durationSec>0 AND no weight.
      // The active workout UI's `_durationControllers` could be hot
      // even for bodyweight slots (post-swap state retention or input
      // bleed), stuffing durationSec onto Push Up / Hanging Leg Raise
      // sets and wrongly stamping them as timed. Receipt then rendered
      // "× 540 reps" / "0s" depending on the renderer.
      //
      // Fix: consult exerciseBox first. Library type wins for known
      // exercises; data-shape fallback only for custom exercises.
      // When resolved type ≠ 'timed', strip durationSec from per-set
      // entries so downstream renderers and the cloud projection don't
      // carry phantom values.
      final resolvedType = _resolveLoggingType(exerciseName, mergedSets);
      final cleanedSets = _stripPhantomFields(mergedSets, resolvedType);

      // APK Test #12 / Task A-2 — workout session id. Defaults to
      // `wlog_<date>` (one workout per IST date). Multi-session days
      // can pass an explicit id to keep receipts scoped per session.
      // Pre-existing rows without this field still load via the
      // legacy "all exercises on date" fallback in receipt code.
      final wid = workoutLogId ?? wlogKey(date);

      final entry = <String, dynamic>{
        'exercise_name': exerciseName,
        'date': dateStr,
        'workout_log_id': wid,
        'sets': cleanedSets.map((s) => s.toMap()).toList(),
        'set_number': cleanedSets.length,
        'reps_completed': totalReps,
        'weight_kg': maxWeight,
        'volume_kg': volume,
        'logging_type': resolvedType,
        'source': source.code,
        'notes': ?notes,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };

      // 4. PR rescan (chronological — strict > comparison; existing
      // pattern from EditWorkoutLogSheet).
      entry['is_pr'] = _rescanPrFor(box, exerciseName, dateStr, maxWeight);

      // 5. Write Hive
      await box.put(key, entry);

      // 6. Update exercise_log_index_<date> — AWAITED so the index reaches disk
      // before this method returns (and before the UI paints the log). A
      // fire-and-forget put here meant the row persisted (awaited above) but the
      // index did not flush before an app close → on reopen the reader, which
      // finds logs via this index, showed the just-logged exercise as "gone"
      // while the orphaned row survived on disk. closes-diagnose: e4a8b1.
      await _appendToIndex(box, dateStr, key);

      // 7. Fire-and-forget cloud sync
      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      // 8. Provider invalidation
      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          // audit-2026-05-11 H-42 — telemetry pair.
          debugPrint('[WorkoutWriteService] invalidation failed: $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'workout_write_service_log_exercise_invalidation'));
        }
      }

      return WriteResult.ok(key);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[WorkoutWriteService.logExercise] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_write_service_log_exercise'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// APK Test #12.5 / Class 1a — library-aware logging_type resolver.
  ///
  /// Consults the bundled exercise library first. For known exercises
  /// (Push Up, Hanging Leg Raise, Jump Rope, …) the library type wins
  /// regardless of what the data shape suggests — the data may be
  /// corrupt (swap-state retention, controller bleed) and the library
  /// is the canonical truth.
  ///
  /// Custom exercises (not in the library) fall back to data-shape
  /// inference — same logic the old `_inferLoggingType` used.
  String _resolveLoggingType(String exerciseName, List<ExerciseSet> sets) {
    // Library lookup. Tolerate missing/uninitialized exerciseBox —
    // fall back to data inference rather than throw.
    try {
      final exb = HiveService.instance.exerciseBox;
      final trimmed = exerciseName.trim();
      for (final v in exb.values) {
        if (v is! Map) continue;
        final name = v['name'] as String?;
        if (name == null) continue;
        if (name.trim().toLowerCase() == trimmed.toLowerCase()) {
          final lt = v['logging_type'] as String?;
          if (lt != null && lt.isNotEmpty) return lt;
          break;
        }
      }
    } catch (_) {
      // Box not open / not seeded — data-driven fallback.
    }

    // Data-shape inference (custom exercise path).
    final hasDur = sets.any((s) => s.durationSec != null && s.durationSec! > 0);
    final hasWeight = sets.any((s) => s.weightKg > 0);
    if (hasDur && !hasWeight) return 'timed';
    if (hasWeight) return 'weight_reps';
    return 'bodyweight_reps';
  }

  /// APK Test #12.5 / Class 1b — strip phantom fields when the
  /// resolved logging_type doesn't accommodate them.
  ///
  /// Examples of phantoms we've observed in production:
  /// - Push Up (`bodyweight_reps`) with `durationSec=18` from a stale
  ///   `_durationControllers` text after a swap.
  /// - Handstand Hold (`timed`) with `weightKg=1.0` (bogus 1kg).
  ///
  /// Per-set entries that would surface as "18 secs" for a bodyweight
  /// chip get cleaned here before persistence so every reader (receipt,
  /// train calendar, cloud projection) sees consistent data.
  List<ExerciseSet> _stripPhantomFields(
    List<ExerciseSet> sets,
    String resolvedType,
  ) {
    switch (resolvedType) {
      case 'bodyweight_reps':
      case 'weight_reps':
      case 'weighted_bodyweight':
        // Duration doesn't apply.
        return sets
            .map((s) => ExerciseSet(
                  weightKg: s.weightKg,
                  reps: s.reps,
                  durationSec: null,
                  loggedAtMs: s.loggedAtMs,
                ))
            .toList();
      case 'timed':
        // Weight + reps don't apply for pure-timed.
        return sets
            .map((s) => ExerciseSet(
                  weightKg: 0.0,
                  reps: 0,
                  durationSec: s.durationSec,
                  loggedAtMs: s.loggedAtMs,
                ))
            .toList();
      default:
        return sets;
    }
  }

  bool _rescanPrFor(
    Box box,
    String exerciseName,
    String dateStr,
    double maxWeight,
  ) {
    final lower = exerciseName.toLowerCase().trim();
    double bestBefore = 0.0;
    for (final k in box.keys) {
      if (!k.toString().startsWith('exlog_')) continue;
      final v = box.get(k);
      if (v is! Map) continue;
      final n = (v['exercise_name'] as String?)?.toLowerCase().trim();
      if (n != lower) continue;
      final d = v['date'] as String?;
      if (d == null) continue;
      if (d.compareTo(dateStr) >= 0) continue; // strict before
      final w = (v['weight_kg'] as num?)?.toDouble() ?? 0.0;
      if (w > bestBefore) bestBefore = w;
    }
    return maxWeight > bestBefore;
  }

  /// Durably appends [key] to `exercise_log_index_<date>`. The `box.put` is
  /// AWAITED (and the method is async) so the index entry reaches disk before
  /// the caller returns. Previously this was a `void` helper that dropped the
  /// put Future — the row write was awaited but the index write was not, so an
  /// app close before Hive flushed lost the index entry and the just-logged
  /// exercise vanished from the reader (orphaned row left on disk).
  /// closes-diagnose: e4a8b1.
  Future<void> _appendToIndex(Box box, String dateStr, String key) async {
    final indexKey = 'exercise_log_index_$dateStr';
    final raw = box.get(indexKey);
    final List<String> list = (raw is List)
        ? raw.cast<String>().toList()
        : <String>[];
    if (!list.contains(key)) list.add(key);
    await box.put(indexKey, list);
  }

  Future<WriteResult> markCompleted({
    required DateTime date,
    required String workoutName,
    required int durationSec,
    int? rpe,
    WidgetRef? ref,
  }) async {
    if (workoutName.trim().isEmpty) {
      return WriteResult.fail('workoutName must be non-empty');
    }
    if (durationSec < 0) {
      return WriteResult.fail('durationSec must be >= 0');
    }

    final dateStr = istDateStr(date);
    final c = await _acquireLock(dateStr);
    try {
      final box = HiveService.instance.workoutBox;
      final sKey = scheduleKey(date);
      final wKey = wlogKey(date);

      // 1. Update schedule entry status='completed' (preserve other fields)
      final sched = box.get(sKey);
      if (sched is Map) {
        final m = Map<String, dynamic>.from(sched);
        m['status'] = 'completed';
        m['completed_at_ms'] = DateTime.now().millisecondsSinceEpoch;
        await box.put(sKey, m);
      } else {
        // No prior schedule (e.g. AI-coach-only logging) — synthesize one.
        await box.put(sKey, {
          'workout_name': workoutName,
          'status': 'completed',
          'type': 'logged',
          'completed_at_ms': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // 2. Upsert wlog_<date>
      final wlog = <String, dynamic>{
        'workout_name': workoutName,
        'date': dateStr,
        'duration_seconds': durationSec,
        if (rpe != null) 'rpe': rpe,
        'completed_at_ms': DateTime.now().millisecondsSinceEpoch,
      };
      await box.put(wKey, wlog);

      // 3. Fire-and-forget cloud sync
      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      // 4. Provider invalidation
      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          // audit-2026-05-11 H-42 — telemetry pair.
          debugPrint('[WorkoutWriteService.markCompleted] inv: $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'workout_write_service_mark_completed_invalidation'));
        }
      }

      return WriteResult.ok(wKey);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[WorkoutWriteService.markCompleted] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_write_service_mark_completed'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(dateStr, c);
    }
  }

  Future<WriteResult> upsertScheduled({
    required DateTime date,
    required Map<String, dynamic> entry,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final dateStr = istDateStr(date);
    final c = await _acquireLock(dateStr);
    try {
      final box = HiveService.instance.workoutBox;
      final key = scheduleKey(date);

      // Theme H fix (diagnose <id>) — refuse to overwrite a completed day
      // from planGenerator. Pre-fix: phase regeneration that normalize-to-
      // Monday'd onto a date with an already-completed workout silently
      // clobbered the completed entry (no `status`, no `completed_at`).
      // Founder hit this 2026-05-21 — Phase 2 W1 generation overwrote
      // Phase 1 W4 entries the founder had completed.
      //
      // Scope to planGenerator only — every other source has a legitimate
      // reason to write to a completed day:
      //   - activeWorkout / editSheet — user is editing or re-logging.
      //   - aiCoach / manual — user explicitly invoked.
      //   - schedSwap — reschedule keeps the completed status intact via
      //     a separate path (rescheduleDay).
      //   - restore — cloud restore must be able to replay history.
      final existingRaw = box.get(key);
      final existingMap = existingRaw is Map
          ? Map<String, dynamic>.from(existingRaw)
          : null;
      if (existingMap != null &&
          existingMap['status'] == 'completed' &&
          source == WriteSource.planGenerator) {
        unawaited(ErrorTelemetry.logEvent(
            'upsert_scheduled_skipped_completed_day',
            message: 'date=$dateStr source=${source.code} key=$key'));
        return WriteResult.fail(
            'refusing to overwrite completed day from planGenerator');
      }

      final stamped = <String, dynamic>{
        ...entry,
        'date': dateStr,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };
      await box.put(key, stamped);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          // audit-2026-05-11 H-42 — telemetry pair.
          debugPrint('[WorkoutWriteService.upsertScheduled] inv: $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'workout_write_service_upsert_scheduled_invalidation'));
        }
      }

      return WriteResult.ok(key);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[WorkoutWriteService.upsertScheduled] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_write_service_upsert_scheduled'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(dateStr, c);
    }
  }

  Future<WriteResult> rescheduleDay({
    required DateTime fromDate,
    required DateTime toDate,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final fromStr = istDateStr(fromDate);
    final toStr = istDateStr(toDate);
    if (fromStr == toStr) {
      return WriteResult.fail('fromDate and toDate are the same');
    }

    // Lock both dates (deterministic order to avoid deadlock)
    final keys = [fromStr, toStr]..sort();
    final c1 = await _acquireLock(keys[0]);
    final c2 = await _acquireLock(keys[1]);
    try {
      final box = HiveService.instance.workoutBox;
      final fromKey = scheduleKey(fromDate);
      final toKey = scheduleKey(toDate);

      final fromRaw = box.get(fromKey);
      final toRaw = box.get(toKey);
      final fromEntry = fromRaw is Map
          ? Map<String, dynamic>.from(fromRaw)
          : <String, dynamic>{};
      final toEntry = toRaw is Map
          ? Map<String, dynamic>.from(toRaw)
          : <String, dynamic>{};

      // Swap (entries keep their original date stamps but the
      // workout content moves).
      final newFrom = <String, dynamic>{
        ...toEntry,
        'date': fromStr,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };
      final newTo = <String, dynamic>{
        ...fromEntry,
        'date': toStr,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };

      await box.put(fromKey, newFrom);
      await box.put(toKey, newTo);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          // audit-2026-05-11 H-42 — telemetry pair.
          debugPrint('[WorkoutWriteService.rescheduleDay] inv: $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'workout_write_service_reschedule_day_invalidation'));
        }
      }

      return WriteResult.ok(toKey);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[WorkoutWriteService.rescheduleDay] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_write_service_reschedule_day'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(keys[1], c2);
      _releaseLock(keys[0], c1);
    }
  }

  Future<WriteResult> regenerateWeek({
    required DateTime fromDate,
    required Map<String, dynamic> params,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final workouts = (params['workouts'] as List?)?.cast<Map>() ?? const [];
    if (workouts.isEmpty) {
      return WriteResult.fail('params.workouts must be non-empty');
    }

    final dateStr = istDateStr(fromDate);
    final c = await _acquireLock('week_$dateStr');
    try {
      final box = HiveService.instance.workoutBox;

      for (var i = 0; i < workouts.length; i++) {
        final d = fromDate.add(Duration(days: i));
        final m = Map<String, dynamic>.from(workouts[i]);
        await box.put(scheduleKey(d), {
          ...m,
          'date': istDateStr(d),
          'source': source.code,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        });
      }

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          // audit-2026-05-11 H-42 — telemetry pair.
          debugPrint('[WorkoutWriteService.regenerateWeek] inv: $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'workout_write_service_regenerate_week_invalidation'));
        }
      }

      return WriteResult.ok('week_$dateStr');
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[WorkoutWriteService.regenerateWeek] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_write_service_regenerate_week'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock('week_$dateStr', c);
    }
  }

  Future<WriteResult> editLog({
    required String logKey,
    required Map<String, dynamic> updates,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final box = HiveService.instance.workoutBox;
    final existing = box.get(logKey);
    if (existing is! Map) {
      return WriteResult.fail('logKey not found: $logKey');
    }

    final m = existing.cast<String, dynamic>();
    final exerciseName = m['exercise_name'] as String?;
    final dateStr = m['date'] as String?;
    if (exerciseName == null || dateStr == null) {
      return WriteResult.fail('log missing exercise_name or date');
    }

    final lockKey = '$dateStr::${exerciseName.toLowerCase().trim()}';
    final c = await _acquireLock(lockKey);
    try {
      // APK Test #12.1 — legacy field-name normalization for callers
      // that still write the pre-Test-#6 names. EditWorkoutLogSheet
      // writes `sets_completed` + `sets_detail` (legacy names); the
      // canonical readers (receipt, Train expanded view, AI snapshot)
      // prefer `set_number` + `sets`. Without this normalization, a
      // user who completed a workout with set_number=0 (no checked
      // sets) and then edited via the sheet to add weight+reps would
      // see `set_number=0, sets_completed=N` — readers report 0 sets.
      // Promote legacy fields to canonical names BEFORE merging so
      // the receipt and Train view see consistent data. Founder
      // observation 2026-05-06: "0 sets · 26 reps · 85 kg".
      final normalizedUpdates = Map<String, dynamic>.from(updates);
      if (normalizedUpdates.containsKey('sets_completed') &&
          !normalizedUpdates.containsKey('set_number')) {
        normalizedUpdates['set_number'] = normalizedUpdates['sets_completed'];
      }
      if (normalizedUpdates.containsKey('sets_detail') &&
          !normalizedUpdates.containsKey('sets')) {
        // sets_detail uses `duration_seconds`; sets[] uses `duration_sec`.
        // Translate field-by-field so ExerciseSet.fromMap works.
        final raw = normalizedUpdates['sets_detail'];
        if (raw is List) {
          normalizedUpdates['sets'] = raw.map((entry) {
            if (entry is! Map) return <String, dynamic>{};
            final m = Map<String, dynamic>.from(entry);
            if (m.containsKey('duration_seconds') &&
                !m.containsKey('duration_sec')) {
              m['duration_sec'] = m['duration_seconds'];
            }
            return m;
          }).toList();
        }
      }

      // Apply updates
      final updated = <String, dynamic>{...m, ...normalizedUpdates};

      // If sets[] was updated, recompute aggregates
      if (normalizedUpdates.containsKey('sets')) {
        final newSets = (normalizedUpdates['sets'] as List).cast<Map>().map((e) {
          return ExerciseSet.fromMap(e);
        }).toList();
        updated['sets'] = newSets.map((s) => s.toMap()).toList();
        updated['set_number'] = newSets.length;
        updated['reps_completed'] =
            newSets.fold<int>(0, (a, s) => a + s.reps);
        updated['weight_kg'] = newSets.fold<double>(
            0, (a, s) => s.weightKg > a ? s.weightKg : a);
        updated['volume_kg'] = newSets.fold<double>(
            0.0, (a, s) => a + (s.weightKg * s.reps));
      }

      updated['source'] = source.code;
      updated['updated_at_ms'] = DateTime.now().millisecondsSinceEpoch;

      // Pre-write the updated entry so PR rescan sees the new weight
      await box.put(logKey, updated);

      // Chronologically rescan PR for ALL logs of this exercise
      await _rescanAllPrsFor(box, exerciseName);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          // audit-2026-05-11 H-42 — telemetry pair.
          debugPrint('[WorkoutWriteService.editLog] inv: $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'workout_write_service_edit_log_invalidation'));
        }
      }

      return WriteResult.ok(logKey);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[WorkoutWriteService.editLog] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_write_service_edit_log'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// Walk all logs of [exerciseName] in date-ascending order, mark
  /// is_pr=true for each weight that strictly exceeds the prior best.
  /// Async + awaited puts: the is_pr writes must reach disk before the caller
  /// returns, else an app close before Hive flushes loses the PR-flag updates
  /// (same fire-and-forget durability class as the exlog index, e4a8b1).
  Future<void> _rescanAllPrsFor(Box box, String exerciseName) async {
    final lower = exerciseName.toLowerCase().trim();
    final logs = <MapEntry<String, Map<String, dynamic>>>[];
    for (final k in box.keys) {
      final ks = k.toString();
      if (!ks.startsWith('exlog_')) continue;
      final v = box.get(k);
      if (v is! Map) continue;
      final m = v.cast<String, dynamic>();
      final n = (m['exercise_name'] as String?)?.toLowerCase().trim();
      if (n != lower) continue;
      logs.add(MapEntry(ks, m));
    }
    logs.sort((a, b) {
      final ad = a.value['date'] as String? ?? '';
      final bd = b.value['date'] as String? ?? '';
      return ad.compareTo(bd);
    });

    double best = 0.0;
    for (final entry in logs) {
      final w = (entry.value['weight_kg'] as num?)?.toDouble() ?? 0.0;
      final isPr = w > best;
      if (isPr) best = w;
      final mut = <String, dynamic>{...entry.value, 'is_pr': isPr};
      await box.put(entry.key, mut);
    }
  }

  Future<WriteResult> deleteLog({
    required String logKey,
    bool allowUndo = true,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final box = HiveService.instance.workoutBox;
    final existing = box.get(logKey);
    if (existing is! Map) {
      return WriteResult.fail('logKey not found: $logKey');
    }
    final m = existing.cast<String, dynamic>();
    final exerciseName = m['exercise_name'] as String?;
    final dateStr = m['date'] as String?;
    if (exerciseName == null || dateStr == null) {
      return WriteResult.fail('log missing exercise_name or date');
    }

    final lockKey = '$dateStr::${exerciseName.toLowerCase().trim()}';
    final c = await _acquireLock(lockKey);
    try {
      // Stash for undo (1-hour TTL)
      if (allowUndo) {
        await box.put('undo_$logKey', {
          'data': jsonEncode(m),
          'expires_at_ms': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        });
      }

      await box.delete(logKey);

      // Drop from exercise_log_index_<date>
      final indexKey = 'exercise_log_index_$dateStr';
      final idx = (box.get(indexKey) as List?)?.cast<String>().toList() ?? [];
      idx.remove(logKey);
      if (idx.isEmpty) {
        await box.delete(indexKey);
      } else {
        await box.put(indexKey, idx);
      }

      // PR rescan (a deleted PR may promote a prior log)
      await _rescanAllPrsFor(box, exerciseName);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          // audit-2026-05-11 H-42 — telemetry pair.
          debugPrint('[WorkoutWriteService.deleteLog] inv: $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'workout_write_service_delete_log_invalidation'));
        }
      }

      return WriteResult.ok(logKey);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[WorkoutWriteService.deleteLog] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_write_service_delete_log'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Template + custom-exercise writers (audit 2026-05-20 / A3)
  // ─────────────────────────────────────────────────────────────
  //
  // Previously written directly via `hive.workoutBox.put(id, ...)` or
  // `customBox.put(key, ...)` from train_provider.dart + workout_repository
  // .dart. Each direct put bypassed canonical sync-fanout + telemetry-pair
  // discipline. Recurring writer/reader drift class — see
  // `feedback_writer_reader_field_drift_recurring.md`.

  /// Upsert a workout template at workoutBox key `<templateId>`.
  /// Stamps `updated_at` IST timestamp; triggers sync fan-out.
  Future<WriteResult> upsertTemplate({
    required String templateId,
    required Map<String, dynamic> template,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final c = await _acquireLock('template::$templateId');
    try {
      final box = HiveService.instance.workoutBox;
      final stamped = <String, dynamic>{
        ...template,
        'id': templateId,
        'type': 'template',
        'source': source.code,
        'updated_at': DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String(),
      };
      // Preserve created_at on update; only stamp on insert.
      if (!stamped.containsKey('created_at')) {
        stamped['created_at'] = stamped['updated_at'];
      }
      await box.put(templateId, stamped);

      // C-11 (audit-2026-05-11) — template is part of workout-domain fan-out.
      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.upsertTemplate] inv: $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'workout_write_service_upsert_template_invalidation'));
        }
      }
      return WriteResult.ok(templateId);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.upsertTemplate] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_write_service_upsert_template'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock('template::$templateId', c);
    }
  }

  /// Upsert a user-created custom exercise at customBox key.
  /// Triggers `syncCustomItemsNow` + snapshot push.
  Future<WriteResult> upsertCustomExercise({
    required String key,
    required Map<String, dynamic> exercise,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final c = await _acquireLock('custom_exercise::$key');
    try {
      final customBox = HiveService.instance.customBox;
      final stamped = <String, dynamic>{
        ...exercise,
        'source': source.code,
        'updated_at': DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String(),
      };
      if (!stamped.containsKey('created_at')) {
        stamped['created_at'] = stamped['updated_at'];
      }
      await customBox.put(key, stamped);

      unawaited(SyncService.instance.syncCustomItemsNow());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.upsertCustomExercise] inv: $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'workout_write_service_upsert_custom_exercise_invalidation'));
        }
      }
      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.upsertCustomExercise] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_write_service_upsert_custom_exercise'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock('custom_exercise::$key', c);
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Helpers (used by methods implemented in later tasks)
  // ─────────────────────────────────────────────────────────────

  /// IST-derived YYYY-MM-DD string. Public for callers that already
  /// have an IST-aware DateTime and need the same hashing rule.
  static String istDateStr(DateTime dt) {
    // Convert to IST regardless of input zone.
    final ist = dt.toUtc().add(const Duration(hours: 5, minutes: 30));
    final y = ist.year.toString().padLeft(4, '0');
    final m = ist.month.toString().padLeft(2, '0');
    final d = ist.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Namespace + UUID generator for the deterministic exlog key tag.
  /// Shared cross-device — must NEVER change without a migration.
  static const _exlogUuidGen = Uuid();
  static const _exlogNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  /// Deterministic Hive key for an exercise log.
  ///
  /// H-16 (audit-2026-05-11) — was `exerciseName.hashCode` which is
  /// not stable across Dart VM versions / isolates / platforms.
  /// Restore on a different device could produce a different `_<h>`
  /// suffix → duplicate logical entries in Hive. Switched to UUID
  /// v5 (stable cross-platform); take the first 8 hex chars to
  /// match the previous shape.
  static String exlogKey(DateTime date, String exerciseName) {
    final d = istDateStr(date);
    final h = _exlogUuidGen
        .v5(_exlogNamespace, exerciseName.toLowerCase().trim())
        .replaceAll('-', '')
        .substring(0, 8);
    return 'exlog_${d}_$h';
  }

  /// Deterministic Hive key for a workout-level summary.
  static String wlogKey(DateTime date) => 'wlog_${istDateStr(date)}';

  /// Deterministic Hive key for a schedule entry.
  static String scheduleKey(DateTime date) =>
      'schedule_${istDateStr(date)}';

  /// Acquire mutex for the given key. Returns the completer the
  /// caller MUST `complete()` in a finally block.
  Future<Completer<void>> _acquireLock(String key) async {
    while (_locks.containsKey(key)) {
      await _locks[key]!.future;
    }
    final c = Completer<void>();
    _locks[key] = c;
    return c;
  }

  void _releaseLock(String key, Completer<void> c) {
    _locks.remove(key);
    if (!c.isCompleted) c.complete();
  }
}
