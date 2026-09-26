// test/contracts/cloud_workout_logs_uses_workout_name_test.dart
//
// Drift-fix batch 2026-05-25 / F4 workout (P2).
//
// Pins that the cloud `workout_logs` upsert projection uses
// `workout_name` (renamed from `exercise_name` in migration 068).
// The value coming from Hive is the session label (e.g. "Push A"),
// never a per-exercise identifier — the column name now matches the
// semantic.
//
// Strips block + line comments per
// feedback_source_grep_strip_comments_first.md so explanatory
// comments don't trigger false positives.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Cloud workout_logs uses workout_name (not exercise_name)', () {
    final file = File('lib/core/services/sync/sync_workout.dart');

    test('source file exists', () {
      expect(file.existsSync(), isTrue);
    });

    test('workout_logs projection emits workout_name key', () {
      final source = file.readAsStringSync();
      final stripped = _stripComments(source);

      final hasWorkoutName = stripped.contains("'workout_name':") ||
          stripped.contains('"workout_name":');

      expect(
        hasWorkoutName,
        isTrue,
        reason: 'sync_workout.dart must project `workout_name` to '
            '`workout_logs`. See migration 068.',
      );
    });

    test('workout_logs upsert onConflict targets workout_name not exercise_name',
        () {
      final source = file.readAsStringSync();
      final stripped = _stripComments(source);

      // The new onConflict clause references workout_name.
      final hasNewConflict =
          stripped.contains('user_id,date,workout_name');

      expect(
        hasNewConflict,
        isTrue,
        reason: 'workout_logs upsert must use '
            'onConflict: "user_id,date,workout_name" matching the '
            'new UNIQUE INDEX `uniq_workout_logs_user_date_workout_name` '
            'created in migration 068.',
      );

      // And does NOT reference the old shape.
      final hasOldConflict =
          stripped.contains('user_id,date,exercise_name');
      expect(
        hasOldConflict,
        isFalse,
        reason: 'Stale onConflict clause "user_id,date,exercise_name" '
            'still present. Update to "user_id,date,workout_name".',
      );
    });
  });
}

String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
