// C-8 (audit-2026-05-11) — regression test that
// `submitWorkoutDraft` routes through `WorkoutWriteService.logExercise`
// + `markCompleted` instead of writing `exlog_*` / `wlog_*` rows
// directly with the legacy field shape (`sets_completed`, no `sets[]`,
// no `set_number`, no IST date stamping). Pre-fix, chat-confirmed
// workouts were invisible to receipts, AI snapshot readers, and
// per-set cloud sync.
//
// Source-grep style — the production handler depends on
// `WidgetRef`/Riverpod and a live Hive box, so booting it from a unit
// test isn't tractable. The contract we pin instead: the function
// MUST funnel writes through WorkoutWriteService.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  const handlerPath =
      'lib/features/ai_coach/services/conversational_log_handler.dart';

  group('C-8 conversational_log_handler routes through WorkoutWriteService',
      () {
    test('imports WorkoutWriteService + WriteResult (ExerciseSet/WriteSource)',
        () {
      final src = _src(handlerPath);
      expect(
        src,
        contains(
            "import 'package:icanbefitter/core/services/workout_write_service.dart'"),
        reason:
            'Handler must import WorkoutWriteService — it is the sole writer '
            'for workout_log + exercise_log Hive rows per CLAUDE.md §15.',
      );
      expect(
        src,
        contains(
            "import 'package:icanbefitter/core/services/write_result.dart'"),
        reason:
            'ExerciseSet + WriteSource enums live in write_result.dart and '
            'are required to call logExercise.',
      );
    });

    test('submitWorkoutDraft calls WorkoutWriteService.logExercise', () {
      final src = _src(handlerPath);
      final idx = src.indexOf(
          'Future<void> submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref)');
      expect(idx, greaterThan(0));
      final end = src.indexOf('\n}\n', idx);
      final body = src.substring(idx, end > idx ? end : src.length);

      expect(
        body,
        contains('WorkoutWriteService.instance.logExercise('),
        reason: 'Every exercise in the chat draft must be funneled through '
            'logExercise so it inherits IST date stamping, set_number, '
            'per-set sets[] array, PR rescan, and 3-tier cloud sync.',
      );
      expect(
        body,
        contains('WriteSource.aiCoach'),
        reason: 'AI-coach-confirmed writes must be tagged with '
            'WriteSource.aiCoach for downstream telemetry / per-source '
            'policy.',
      );
    });

    test('submitWorkoutDraft calls WorkoutWriteService.markCompleted', () {
      final src = _src(handlerPath);
      final idx = src.indexOf(
          'Future<void> submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref)');
      final end = src.indexOf('\n}\n', idx);
      final body = src.substring(idx, end > idx ? end : src.length);
      expect(
        body,
        contains('WorkoutWriteService.instance.markCompleted('),
        reason: 'The single wlog_<date> row + schedule-status flip must '
            'route through markCompleted so it stays consistent with '
            'active-workout completion.',
      );
    });

    test(
      'submitWorkoutDraft does NOT write exlog_*/wlog_* directly to Hive',
      () {
        final src = _src(handlerPath);
        final idx = src.indexOf(
            'Future<void> submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref)');
        final end = src.indexOf('\n}\n', idx);
        final body = src.substring(idx, end > idx ? end : src.length);

        // Forbidden legacy direct-Hive shapes.
        expect(body.contains("workoutBox.put('exlog_"), isFalse,
            reason: 'Legacy direct exlog_ Hive write — must route through '
                'WorkoutWriteService.logExercise.');
        expect(body.contains("workoutBox.put('wlog_"), isFalse,
            reason: 'Legacy direct wlog_ Hive write — must route through '
                'WorkoutWriteService.markCompleted.');
        // The legacy code prefixed both `exlog_` and `wlog_` via string
        // interpolation (`'exlog_\$\{ts\}_...'`). Catch the generic shape
        // too.
        expect(
          RegExp("workoutBox\\.put\\('?exlog_").hasMatch(body),
          isFalse,
          reason: 'No interpolated exlog_ keys may be written directly.',
        );
        expect(
          RegExp("workoutBox\\.put\\('?wlog_").hasMatch(body),
          isFalse,
          reason: 'No interpolated wlog_ keys may be written directly.',
        );

        // Pre-fix used `sets_completed` as the per-exercise summary
        // field (the legacy shape Test #8 closed for receipts).
        expect(
          body.contains("'sets_completed'"),
          isFalse,
          reason: 'Legacy `sets_completed` field is the shape Test #8 '
              'replaced with `set_number` + `sets[]`. Must not reappear.',
        );
      },
    );
  });
}
