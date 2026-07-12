// lib/core/services/template_service.dart
//
// Tech-debt audit 2026-05-20 / A2 (final closure batch B5 D13-D17).
//
// Owns custom-template scheduling:
//   - assignTemplateToDate
//   - unscheduleTemplateFromDate
//   - cleanSyncTemplateSchedule
//
// Also hosts the public [LoggingTypeResolver] utility used both by this
// service and by [SwapService.swapExerciseInDay].
//
// closes-diagnose: 2026-05-22-a2-workout-schedule-4way-split-<6char>

// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'migrated_key.dart';
import 'singleton_lifecycle_registry.dart';
import 'sync_service.dart';
import 'workout_schedule_read_service.dart';
import 'workout_write_service.dart';
import 'write_result.dart';
import '../utils/date_utils.dart';
import '../utils/injury_vocab.dart';
import '../../shared/repositories/plan_engine/warmup_cooldown.dart';
import '../../shared/repositories/plan_generator.dart';

/// Result returned by [TemplateService.assignTemplateToDate].
sealed class AssignTemplateResult {
  const AssignTemplateResult();
}

class AssignTemplateOk extends AssignTemplateResult {
  const AssignTemplateOk();
}

class AssignTemplateRejected extends AssignTemplateResult {
  const AssignTemplateRejected(this.reason);
  final AssignTemplateRejectionReason reason;
}

enum AssignTemplateRejectionReason {
  alreadyCompleted,
  templateMissing,
}

/// Template-scheduling portion of the former WorkoutScheduleService.
class TemplateService {
  TemplateService._() {
    _registerLifecycle();
  }
  static final TemplateService _instance = TemplateService._();

  /// Prefer `ref.read(templateServiceProvider)`.
  @Deprecated(
      'Use ref.read(templateServiceProvider) — singleton path will be removed after full migration')
  static TemplateService get instance => _instance;

  final HiveService _hive = HiveService.instance;

  void _registerLifecycle() {
    SingletonLifecycleRegistry.register('TemplateService', _onUserChanged);
  }

  void _onUserChanged() {
    // No in-memory caches.
  }

  static const String _schedulePrefix = 'schedule_';
  static const String _displacedPrefix = 'displaced_';
  static const String _planStartKey = 'plan_start_date';

  /// Assign a saved template to [date].
  Future<AssignTemplateResult> assignTemplateToDate(
      String templateId, DateTime date) async {
    final tmpl = _hive.workoutBox.get(templateId);
    if (tmpl == null) {
      return const AssignTemplateRejected(
          AssignTemplateRejectionReason.templateMissing);
    }

    final tmplMap = Map<String, dynamic>.from(tmpl as Map);
    final dateKey = formatDateKey(date);
    final scheduleKey = '$_schedulePrefix$dateKey';
    final displacedKey = '$_displacedPrefix$dateKey';

    final existing = _hive.workoutBox.get(scheduleKey);
    if (existing is Map) {
      final existingMap = Map<String, dynamic>.from(existing);
      if (existingMap['status'] == 'completed') {
        unawaited(ErrorTelemetry.logEvent(
          'template_assign_rejected_completed',
          message: 'date=$dateKey templateId=$templateId',
        ));
        return const AssignTemplateRejected(
            AssignTemplateRejectionReason.alreadyCompleted);
      }

      final isAlreadyTemplate = existingMap['type'] == 'custom_template';
      final alreadyBackedUp = _hive.workoutBox.containsKey(displacedKey);
      if (!isAlreadyTemplate && !alreadyBackedUp) {
        await _hive.workoutBox.put(displacedKey, existingMap);
      }
    }

    final planStartStr = MigratedKey.read<String>(_planStartKey);
    int weekNum = 1;
    if (planStartStr != null) {
      final planStart = DateTime.tryParse(planStartStr);
      if (planStart != null) {
        final diff = date.difference(planStart).inDays;
        weekNum = (diff ~/ 7 + 1).clamp(1, 4);
      }
    }

    final workoutName = tmplMap['name'] as String? ?? 'Custom Workout';
    final normalizedExercises =
        _normalizeExercises(tmplMap['exercises'] as List? ?? []);

    final templateEntry = <String, dynamic>{
      'date': dateKey,
      'week': weekNum,
      'type': 'custom_template',
      'template_id': templateId,
      'workout_name': workoutName,
      'workout_focus': 'Custom',
      'exercises': normalizedExercises,
      'status': 'planned',
      'is_swapped': false,
      'completed_at': null,
    };

    if (normalizedExercises.isNotEmpty) {
      final dayType = _detectDayTypeFromExercises(normalizedExercises);

      final profile = _hive.userBox.get('profile');
      final profileMap = profile is Map
          ? Map<String, dynamic>.from(profile)
          : <String, dynamic>{};
      final experience =
          (profileMap['fitness_experience'] as String?) ?? 'intermediate';
      final equipmentStr =
          (profileMap['equipment_access'] as String?) ?? 'full_gym';

      final equipmentList = [equipmentStr];
      // U3: the custom-template auto-warmup was UNFILTERED — thread the user's
      // injuries so it drops contraindicated warmup/cooldown moves too.
      final injuries = InjuryVocab.normalize(
          InjuryVocab.fromProfile(profileMap['injuries']));

      final tempDay = WorkoutDay(
        dayNumber: 1,
        name: workoutName,
        focus: dayType,
        exercises: const [],
      );
      final tempWeek = WeekPlan(
        weekNumber: 1,
        weekInPhase: 1,
        overloadNotes: '',
        weekCharacter: 'baseline',
        workoutDays: [tempDay],
      );

      final withWarmup = WarmupCooldownSelector.attach(
        [tempWeek],
        experience,
        equipmentList,
        injuries: injuries,
      );

      final enrichedDay = withWarmup.first.workoutDays.first;
      if (enrichedDay.warmup.isNotEmpty) {
        templateEntry['warmup'] = enrichedDay.warmup
            .map((e) => e.toMap()..['auto_generated'] = true)
            .toList();
      }
      if (enrichedDay.cooldown.isNotEmpty) {
        templateEntry['cooldown'] = enrichedDay.cooldown
            .map((e) => e.toMap()..['auto_generated'] = true)
            .toList();
      }
    }

    await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: templateEntry,
      source: WriteSource.schedSwap,
    );

    try {
      final updatedTmpl = Map<String, dynamic>.from(tmplMap);
      updatedTmpl['last_used_at'] = DateTime.now().toUtc().toIso8601String();
      await _hive.workoutBox.put(templateId, updatedTmpl);
      unawaited(SyncService.instance.syncWorkoutData());
    } catch (_) {/* non-fatal */}

    return const AssignTemplateOk();
  }

  /// Restore on remove — pulls displaced backup if present.
  Future<void> unscheduleTemplateFromDate(DateTime date) async {
    final dateKey = formatDateKey(date);
    final scheduleKey = '$_schedulePrefix$dateKey';
    final displacedKey = '$_displacedPrefix$dateKey';

    final current = _hive.workoutBox.get(scheduleKey);
    if (current is Map) {
      final currentMap = Map<String, dynamic>.from(current);
      if (currentMap['status'] == 'completed') {
        if (_hive.workoutBox.containsKey(displacedKey)) {
          await _hive.workoutBox.delete(displacedKey);
        }
        return;
      }
    }

    final backup = _hive.workoutBox.get(displacedKey);
    if (backup is Map) {
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: Map<String, dynamic>.from(backup),
        source: WriteSource.schedSwap,
      );
      await _hive.workoutBox.delete(displacedKey);
    } else {
      await _hive.workoutBox.delete(scheduleKey);
    }
  }

  /// Wipe all future non-completed schedule entries for a template.
  Future<void> cleanSyncTemplateSchedule(String templateId) async {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);

    final planEnd = WorkoutScheduleReadService.instance.getPlanEndDate() ??
        todayMidnight.add(const Duration(days: 28));

    for (var d = todayMidnight;
        !d.isAfter(planEnd);
        d = d.add(const Duration(days: 1))) {
      final key = '$_schedulePrefix${formatDateKey(d)}';
      final entry = _hive.workoutBox.get(key);
      if (entry is! Map) continue;

      final map = Map<String, dynamic>.from(entry);
      if (map['type'] != 'custom_template') continue;
      if (map['template_id'] != templateId) continue;
      if (map['status'] == 'completed') continue;

      await unscheduleTemplateFromDate(d);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────

  String _detectDayTypeFromExercises(List exercises) {
    final categories = <String>[];
    for (final ex in exercises) {
      if (ex is Map) {
        final cat = ex['category'] as String? ?? '';
        if (cat.isNotEmpty) categories.add(cat.toLowerCase());
      }
    }
    if (categories.isEmpty) return 'full_body';

    final pushCount = categories.where((c) => c == 'push').length;
    final pullCount = categories.where((c) => c == 'pull').length;
    final legsCount = categories.where((c) => c == 'legs').length;

    if (legsCount > pushCount && legsCount > pullCount) return 'legs';
    if (pushCount > pullCount) return 'push';
    if (pullCount > pushCount) return 'pull';
    if (pushCount > 0 && pullCount > 0) return 'upper';
    return 'full_body';
  }

  List<Map<String, dynamic>> _normalizeExercises(List raw) {
    return raw.map((e) {
      final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
      final exerciseName =
          (m['exercise_name'] ?? m['name'] ?? 'Unknown').toString();
      final rawSets =
          m['sets'] ?? m['prescribed_sets'] ?? m['default_sets'] ?? 3;
      final int setsInt;
      if (rawSets is int) {
        setsInt = rawSets;
      } else if (rawSets is num) {
        setsInt = rawSets.toInt();
      } else if (rawSets is String) {
        setsInt = int.tryParse(rawSets) ?? 3;
      } else {
        setsInt = 3;
      }
      return {
        'exercise_name': exerciseName,
        'sets': setsInt,
        'reps': (m['reps'] ?? m['prescribed_reps'] ?? m['default_reps'] ?? '10')
            .toString(),
        'rest_seconds': m['rest_seconds'] ?? m['default_rest_secs'] ?? 60,
        'logging_type': _resolveLoggingType(m, exerciseName),
        'category': m['category'],
        'exercise_type': m['exercise_type'],
        'equipment_needed': m['equipment_needed'],
        'superset_group': m['superset_group'],
      };
    }).toList();
  }

  String _resolveLoggingType(Map<String, dynamic> m, String exerciseName) {
    final explicit = m['logging_type'];
    if (explicit is String && explicit.isNotEmpty) return explicit;

    final hive = HiveService.instance;

    try {
      final libEntry = hive.exerciseBox.get(exerciseName);
      if (libEntry is Map) {
        final lt = libEntry['logging_type'];
        if (lt is String && lt.isNotEmpty) return lt;
      }
    } catch (_) {/* continue */}

    try {
      for (final key in hive.customBox.keys) {
        if (key is! String || !key.startsWith('custom_exercise_')) continue;
        final raw = hive.customBox.get(key);
        if (raw is! Map) continue;
        if (raw['name']?.toString().toLowerCase() ==
            exerciseName.toLowerCase()) {
          final lt = raw['logging_type'];
          if (lt is String && lt.isNotEmpty) return lt;
        }
      }
    } catch (_) {/* continue */}

    final n = exerciseName.toLowerCase();
    if (n.contains('hold') ||
        n.contains('plank') ||
        n.contains('handstand') ||
        n.contains('l-sit')) {
      return 'timed';
    }
    if (n.contains('run') ||
        n.contains('row') ||
        n.contains('bike') ||
        n.contains('cycle') ||
        n.contains('walk')) {
      return 'cardio';
    }
    return 'weight_reps';
  }
}

/// Resolves the logging_type for an exercise payload. Used by
/// [SwapService.swapExerciseInDay] + (via the private helper) by
/// [TemplateService._normalizeExercises].
class LoggingTypeResolver {
  static String? resolve({
    required Map<String, dynamic> exercise,
    required Map<dynamic, dynamic> exerciseLibrary,
    required Map<dynamic, dynamic> customLibrary,
  }) {
    final direct = exercise['logging_type'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;

    final name = exercise['name'] as String?;
    if (name == null || name.isEmpty) return null;

    for (final value in customLibrary.values) {
      if (value is Map && value['name'] == name) {
        final t = value['logging_type'] as String?;
        if (t != null && t.isNotEmpty) return t;
      }
    }

    for (final value in exerciseLibrary.values) {
      if (value is Map && value['name'] == name) {
        final t = value['logging_type'] as String?;
        if (t != null && t.isNotEmpty) return t;
      }
    }

    return null;
  }
}
