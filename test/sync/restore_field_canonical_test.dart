// Regression tests for Theme D1 + D2 (Test #11):
//   D1 — WorkoutRepository.logExercise / updateExerciseLog delegate to
//        WorkoutWriteService (single source-of-truth per CLAUDE.md §15).
//   D2 — sync_service._restoreExerciseLogs writes canonical Hive field
//        names (`set_number` / `sets`) instead of legacy
//        (`sets_completed` / `sets_detail`).
//
// Source-scan tests follow the same pattern as sync_gap_test.dart:
// no Hive / Flutter / plugin bootstrapping required.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

String _src(String relativePath) {
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

void main() {
  // ── D2 — sync_service canonical field names ──────────────────────

  group('D2 — restore writes canonical exlog field names', () {
    late String src;

    setUpAll(() {
      src = loadSyncServiceSource().readAsStringSync();
    });

    test("_restoreExerciseLogs must NOT write legacy 'sets_completed'", () {
      // Narrow to the _restoreExerciseLogs function body only so we don't
      // false-positive on wlog_* restore which legitimately uses the field.
      final restoreStart = src.indexOf('Future<void> _restoreExerciseLogs(');
      expect(restoreStart, greaterThan(0),
          reason: '_restoreExerciseLogs function must exist');

      // Find the end of _restoreExerciseLogs by finding the next
      // `Future<void>` top-level method after it.
      final afterRestore = src.indexOf(
          'Future<void> _restoreScheduleCompletions', restoreStart);
      expect(afterRestore, greaterThan(restoreStart));

      final body = src.substring(restoreStart, afterRestore);
      expect(
        body,
        isNot(contains("'sets_completed':")),
        reason:
            'D2: _restoreExerciseLogs must write canonical set_number, '
            'not legacy sets_completed',
      );
    });

    test("_restoreExerciseLogs must NOT write legacy 'sets_detail'", () {
      final restoreStart = src.indexOf('Future<void> _restoreExerciseLogs(');
      final afterRestore = src.indexOf(
          'Future<void> _restoreScheduleCompletions', restoreStart);
      final body = src.substring(restoreStart, afterRestore);

      // `sets_detail` may appear in COMMENTS explaining the change; check
      // that no Hive key assignment uses it (i.e., no `logMap['sets_detail'] =`).
      expect(
        body,
        isNot(contains("logMap['sets_detail']")),
        reason:
            'D2: _restoreExerciseLogs must write canonical sets, '
            'not legacy sets_detail',
      );
    });

    test("_restoreExerciseLogs writes canonical 'set_number'", () {
      final restoreStart = src.indexOf('Future<void> _restoreExerciseLogs(');
      final afterRestore = src.indexOf(
          'Future<void> _restoreScheduleCompletions', restoreStart);
      final body = src.substring(restoreStart, afterRestore);

      expect(
        body,
        contains("logMap['set_number']"),
        reason:
            'D2: _restoreExerciseLogs must write canonical set_number field',
      );
    });

    test("_restoreExerciseLogs writes canonical 'sets'", () {
      final restoreStart = src.indexOf('Future<void> _restoreExerciseLogs(');
      final afterRestore = src.indexOf(
          'Future<void> _restoreScheduleCompletions', restoreStart);
      final body = src.substring(restoreStart, afterRestore);

      expect(
        body,
        contains("logMap['sets']"),
        reason:
            'D2: _restoreExerciseLogs must write canonical sets field '
            '(per-set Map list)',
      );
    });
  });

  // ── D1 — WorkoutRepository delegation shims ──────────────────────

  group('D1 — WorkoutRepository.logExercise delegates to WorkoutWriteService',
      () {
    late String src;

    setUpAll(() {
      src = _src(
          'lib/features/train/repositories/workout_repository.dart');
    });

    test('logExercise method exists and delegates to WorkoutWriteService',
        () {
      // Confirm the delegation shim section header exists.
      expect(
        src,
        contains('Deprecated delegation shims (Theme D1'),
        reason: 'D1: delegation shims section header must exist',
      );

      // Confirm the @Deprecated logExercise method exists.
      expect(
        src,
        contains('Future<WriteResult> logExercise('),
        reason: 'D1: @Deprecated logExercise method signature must exist',
      );

      // Find the logExercise method body after the delegation shims header.
      final shimsStart = src.indexOf('Deprecated delegation shims (Theme D1');
      expect(shimsStart, greaterThan(0));

      final logExerciseStart = src.indexOf(
          'Future<WriteResult> logExercise(', shimsStart);
      expect(logExerciseStart, greaterThan(shimsStart));

      // Slice a reasonable window from the method start.
      final body = src.substring(logExerciseStart,
          (logExerciseStart + 2000).clamp(0, src.length));

      expect(
        body,
        contains('WorkoutWriteService.instance.logExercise'),
        reason:
            'D1: WorkoutRepository.logExercise must delegate to '
            'WorkoutWriteService.instance.logExercise',
      );

      // Confirm @Deprecated annotation is present before the method.
      final annotationWindow = src.substring(
          (logExerciseStart - 500).clamp(0, src.length), logExerciseStart);
      expect(
        annotationWindow,
        contains('@Deprecated'),
        reason: 'D1: logExercise must carry @Deprecated annotation',
      );
    });

    test(
        'updateExerciseLog method exists and delegates to WorkoutWriteService.editLog',
        () {
      expect(
        src,
        contains('Future<WriteResult> updateExerciseLog('),
        reason: 'D1: @Deprecated updateExerciseLog method signature must exist',
      );

      final shimsStart = src.indexOf('Deprecated delegation shims (Theme D1');
      final updateExStart = src.indexOf(
          'Future<WriteResult> updateExerciseLog(', shimsStart);
      expect(updateExStart, greaterThan(shimsStart),
          reason:
              'D1: updateExerciseLog must appear after delegation shims header');

      final body = src.substring(updateExStart,
          (updateExStart + 800).clamp(0, src.length));

      expect(
        body,
        contains('WorkoutWriteService.instance.editLog'),
        reason:
            'D1: WorkoutRepository.updateExerciseLog must delegate to '
            'WorkoutWriteService.instance.editLog',
      );

      // Confirm @Deprecated annotation is present before the method.
      final annotationWindow = src.substring(
          (updateExStart - 500).clamp(0, src.length), updateExStart);
      expect(
        annotationWindow,
        contains('@Deprecated'),
        reason: 'D1: updateExerciseLog must carry @Deprecated annotation',
      );
    });

    test('WriteSource.legacyRepository is defined in write_result.dart', () {
      final wrSrc = _src('lib/core/services/write_result.dart');
      expect(
        wrSrc,
        contains('legacyRepository'),
        reason:
            'D1: WriteSource.legacyRepository enum value must exist for '
            'delegation telemetry',
      );
    });
  });
}
