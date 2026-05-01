import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

      final entry = <String, dynamic>{
        'exercise_name': exerciseName,
        'date': dateStr,
        'sets': mergedSets.map((s) => s.toMap()).toList(),
        'set_number': mergedSets.length,
        'reps_completed': totalReps,
        'weight_kg': maxWeight,
        'volume_kg': volume,
        'logging_type': _inferLoggingType(mergedSets),
        'source': source.code,
        'notes': ?notes,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };

      // 4. PR rescan (chronological — strict > comparison; existing
      // pattern from EditWorkoutLogSheet).
      entry['is_pr'] = _rescanPrFor(box, exerciseName, dateStr, maxWeight);

      // 5. Write Hive
      await box.put(key, entry);

      // 6. Update exercise_log_index_<date>
      _appendToIndex(box, dateStr, key);

      // 7. Fire-and-forget cloud sync
      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      // 8. Provider invalidation
      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService] invalidation failed: $e\n$st');
        }
      }

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.logExercise] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  String _inferLoggingType(List<ExerciseSet> sets) {
    final hasDur = sets.any((s) => s.durationSec != null && s.durationSec! > 0);
    final hasWeight = sets.any((s) => s.weightKg > 0);
    if (hasDur && !hasWeight) return 'timed';
    if (hasWeight) return 'weight_reps';
    return 'bodyweight_reps';
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

  void _appendToIndex(Box box, String dateStr, String key) {
    final indexKey = 'exercise_log_index_$dateStr';
    final raw = box.get(indexKey);
    final List<String> list = (raw is List)
        ? raw.cast<String>().toList()
        : <String>[];
    if (!list.contains(key)) list.add(key);
    box.put(indexKey, list);
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
          debugPrint('[WorkoutWriteService.markCompleted] inv: $e\n$st');
        }
      }

      return WriteResult.ok(wKey);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.markCompleted] $e\n$st');
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
          debugPrint('[WorkoutWriteService.upsertScheduled] inv: $e\n$st');
        }
      }

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.upsertScheduled] $e\n$st');
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
          debugPrint('[WorkoutWriteService.rescheduleDay] inv: $e\n$st');
        }
      }

      return WriteResult.ok(toKey);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.rescheduleDay] $e\n$st');
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
          debugPrint('[WorkoutWriteService.regenerateWeek] inv: $e\n$st');
        }
      }

      return WriteResult.ok('week_$dateStr');
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.regenerateWeek] $e\n$st');
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
      // Apply updates
      final updated = <String, dynamic>{...m, ...updates};

      // If sets[] was updated, recompute aggregates
      if (updates.containsKey('sets')) {
        final newSets = (updates['sets'] as List).cast<Map>().map((e) {
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
      _rescanAllPrsFor(box, exerciseName);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.editLog] inv: $e\n$st');
        }
      }

      return WriteResult.ok(logKey);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.editLog] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// Walk all logs of [exerciseName] in date-ascending order, mark
  /// is_pr=true for each weight that strictly exceeds the prior best.
  void _rescanAllPrsFor(Box box, String exerciseName) {
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
      box.put(entry.key, mut);
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
      _rescanAllPrsFor(box, exerciseName);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.deleteLog] inv: $e\n$st');
        }
      }

      return WriteResult.ok(logKey);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.deleteLog] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
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

  /// Deterministic Hive key for an exercise log.
  static String exlogKey(DateTime date, String exerciseName) {
    final d = istDateStr(date);
    final h = exerciseName.toLowerCase().trim().hashCode;
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
