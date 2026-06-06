import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';

/// Behavioral + wiring regression for the restore plan_json-skip bug
/// (diagnose 2026-06-06-restore-plan-json-skip).
///
/// ROOT CAUSE: `_restoreWorkoutPlan` early-returned when a local `current_plan`
/// already existed, so the exercise-rich `plan_json.schedules` snapshot (+ the
/// correct `plan_start_date`) was never applied on a reinstall. Planned days
/// then restored exercise-less (the cloud `scheduled_workouts` table has no
/// exercises/name column) → "REST DAY / No exercises scheduled" + a dead START
/// button, and the week number was computed off a stale plan_start.
///
/// These tests fail on the PRE-FIX code: the merge helper didn't exist, and the
/// blanket `if (current_plan != null) return` skip was present.
String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('mergeScheduleEntry (completed-preserving, exercise-filling)', () {
    test('no local row → takes the plan_json snapshot wholesale (exercises)',
        () {
      final merged = PlanIntegrityReconciler.mergeScheduleEntry(
        null,
        {'type': 'workout', 'workout_name': 'Legs B', 'exercises': [1, 2, 3]},
      );
      expect(merged['workout_name'], 'Legs B');
      expect((merged['exercises'] as List).length, 3);
    });

    test(
        'planned day that LOST its exercises → filled from snapshot, local '
        'status kept (the bug)', () {
      final merged = PlanIntegrityReconciler.mergeScheduleEntry(
        // What the exercise-less scheduled_workouts restore left behind:
        {'type': 'workout', 'status': 'planned', 'exercises': <dynamic>[]},
        // What plan_json holds:
        {
          'type': 'workout',
          'workout_name': 'Legs B',
          'exercises': [1, 2, 3, 4, 5, 6, 7, 8],
          'status': 'planned',
        },
      );
      expect((merged['exercises'] as List).length, 8,
          reason: 'planned-day exercises must be rehydrated from plan_json');
      expect(merged['workout_name'], 'Legs B');
      expect(merged['status'], 'planned');
    });

    test('planned day that ALREADY has exercises → kept (swap-safe, review P1)',
        () {
      final merged = PlanIntegrityReconciler.mergeScheduleEntry(
        // local row carries an unsynced swap:
        {'type': 'workout', 'status': 'planned', 'exercises': ['localSwap']},
        // plan_json snapshot is stale for this day:
        {'type': 'workout', 'workout_name': 'Legs B', 'exercises': [1, 2, 3]},
      );
      expect((merged['exercises'] as List).first, 'localSwap',
          reason: 'a non-empty local exercises list is authoritative — the '
              'heal must only FILL empties, never clobber an unsynced swap');
    });

    test('completed day is authoritative — never overwritten by the snapshot',
        () {
      final merged = PlanIntegrityReconciler.mergeScheduleEntry(
        {
          'type': 'workout',
          'status': 'completed',
          'completed_at': '2026-06-05T10:00:00Z',
          'exercises': ['logged'],
        },
        {'type': 'workout', 'status': 'planned', 'exercises': ['planned']},
      );
      expect(merged['status'], 'completed');
      expect(merged['completed_at'], '2026-06-05T10:00:00Z');
      expect((merged['exercises'] as List).first, 'logged');
    });

    test('local completed_at survives on a non-completed merge', () {
      final merged = PlanIntegrityReconciler.mergeScheduleEntry(
        {'status': 'planned', 'completed_at': '2026-06-02T08:00:00Z'},
        {'type': 'workout', 'exercises': [1]},
      );
      expect(merged['completed_at'], '2026-06-02T08:00:00Z');
    });
  });

  group('needsHeal (restore-skip symptom)', () {
    test('a planned workout day with NO exercises → needs heal', () {
      expect(
        PlanIntegrityReconciler.needsHeal([
          {'type': 'workout', 'status': 'planned', 'exercises': <dynamic>[]},
        ]),
        isTrue,
      );
    });

    test('custom_template planned day with no exercises → needs heal', () {
      expect(
        PlanIntegrityReconciler.needsHeal([
          {'type': 'custom_template', 'status': 'planned'},
        ]),
        isTrue,
      );
    });

    test('all planned days HAVE exercises → no heal', () {
      expect(
        PlanIntegrityReconciler.needsHeal([
          {'type': 'workout', 'status': 'planned', 'exercises': [1, 2]},
          {'type': 'rest', 'exercises': <dynamic>[]},
        ]),
        isFalse,
      );
    });

    test('a completed workout day with no top-level exercises → no heal', () {
      // Completed days render from logs, not the schedule exercises field.
      expect(
        PlanIntegrityReconciler.needsHeal([
          {'type': 'workout', 'status': 'completed', 'exercises': <dynamic>[]},
        ]),
        isFalse,
      );
    });

    test('genuine rest day (no exercises) → no heal', () {
      expect(
        PlanIntegrityReconciler.needsHeal([
          {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]},
        ]),
        isFalse,
      );
    });
  });

  group('wiring', () {
    final reconcilerSrc = _strip(
        File('lib/core/services/plan_integrity_reconciler.dart')
            .readAsStringSync());
    final restoreSrc = _strip(
        File('lib/core/services/sync/sync_workout.dart').readAsStringSync());
    final bootSrc = _strip(
        File('lib/features/auth/screens/restoring_screen.dart')
            .readAsStringSync());

    test('reconcile() is symptom-gated + kill-switchable + plan_start-guarded',
        () {
      expect(reconcilerSrc.contains('needsHeal('), isTrue);
      expect(reconcilerSrc.contains('killSwitchKey'), isTrue);
      expect(reconcilerSrc.contains('getPlanStartDate()'), isTrue);
    });

    test(
        '_restoreWorkoutPlan no longer skips on existing current_plan + uses '
        'the shared merge', () {
      final slice = _methodSlice(restoreSrc, '_restoreWorkoutPlan');
      expect(slice, isNotNull);
      // The pre-fix blanket early-return is gone: there must be NO bare
      // `return;` guarded only by a current_plan presence check at the top.
      expect(
        RegExp(r"workoutBox\.get\('current_plan'\)\s*!=\s*null\)\s*return;")
            .hasMatch(slice!),
        isFalse,
        reason: 'the blanket early-return that skipped plan_json must be gone '
            '— it is the restore-skip root cause',
      );
      expect(slice.contains('PlanIntegrityReconciler.mergeScheduleEntry'),
          isTrue,
          reason: 'restore must apply plan_json via the shared merge helper');
      expect(slice.contains("MigratedKey.write('plan_start_date'"), isTrue,
          reason: 'restore must always re-anchor plan_start_date');
    });

    test('boot heal runs in restoring_screen (foreground + background)', () {
      expect(bootSrc.contains('PlanIntegrityReconciler.reconcile('), isTrue);
    });
  });
}

/// Extracts a Dart method body by brace-matching (mirror of the helper in
/// restore_round_trip_field_coverage_test.dart).
String? _methodSlice(String src, String methodName) {
  final sigRe = RegExp(
    r'\b(Future<[^>]+>\s+|void\s+|Map<[^>]+>\s+)?\s*' +
        RegExp.escape(methodName) +
        r'\s*\(',
  );
  final m = sigRe.firstMatch(src);
  if (m == null) return null;
  var i = m.end;
  while (i < src.length && src[i] != '{') {
    i++;
  }
  if (i >= src.length) return null;
  var depth = 0;
  final start = i;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  return null;
}
