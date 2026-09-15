// test/contracts/phase_unlock_start_date_test.dart
//
// Contract — Theme H (closes-diagnose b0baa5).
//
// Pins the phase-unlock startDate fix + the completed-day overwrite
// guard in WorkoutWriteService.upsertScheduled.
//
// Pre-fix:
//   graduation_screen.dart:448 + workout_schedule_read_service.dart:399
//   (autoGenerateNextPhaseIfNeeded) both passed `DateTime.now()` as
//   startDate into generateAndSchedule. _normalizeToMonday(today)
//   resolved to THIS WEEK's Monday, overwriting the user's current
//   phase's final week entries. Founder hit this 2026-05-21 — Phase 2
//   W1 generation clobbered Phase 1 W4 completed-day entries on a Wed
//   tap. The completed history vanished from the train screen.
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('nextPhaseStartDate helper present in WorkoutScheduleReadService', () {
    final src = File('lib/core/services/workout_schedule_read_service.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('declares nextPhaseStartDate method', () {
      expect(
        RegExp(r'DateTime\s+nextPhaseStartDate\s*\(').hasMatch(stripped),
        isTrue,
        reason:
            'WorkoutScheduleReadService must expose nextPhaseStartDate() — '
            'the canonical helper for computing next-phase startDate. '
            'Pre-fix every caller passed DateTime.now() directly, which '
            'normalize-to-Monday clobbered the current phase final week.',
      );
    });

    test('helper reads plan_end_date via MigratedKey', () {
      expect(
        // Must read _planEndKey to find when current phase ends.
        stripped.contains('_planEndKey'),
        isTrue,
        reason: 'nextPhaseStartDate must consult plan_end_date — the '
            'storage already written by every generateAndSchedule call.',
      );
    });

    test('helper falls back via max(today, currentPhaseEnd + 1)', () {
      // The guard against retroactive starts when a user lets Phase 1 expire.
      expect(
        RegExp(r'candidate\.isAfter\(today\)').hasMatch(stripped),
        isTrue,
        reason: 'nextPhaseStartDate must compute max(today, '
            'currentPhaseEnd + 1) so an expired phase does not start the '
            'new phase retroactively.',
      );
    });
  });

  group('Callers route through nextPhaseStartDate (no raw DateTime.now)', () {
    final gradSrc = File('lib/features/train/screens/graduation_screen.dart')
        .readAsStringSync();
    final gradStripped = _stripComments(gradSrc);
    final svcSrc = File('lib/core/services/workout_schedule_read_service.dart')
        .readAsStringSync();
    final svcStripped = _stripComments(svcSrc);

    test('the graduation advance calls nextPhaseStartDate (not DateTime.now)',
        () {
      // Unit B / OI-84 (2026-08-03): the graduation generate block moved out of
      // graduation_screen._onPro into runGraduationPhaseAdvance in
      // pro_phase_advance.dart. FOLLOW THE CODE, don't keep grepping the old
      // file — `gradStripped.contains('nextPhaseStartDate()')` would now be
      // false and, worse, the negative assertion below would pass vacuously
      // against a file that no longer contains any generate call at all.
      final advanceStripped = _stripComments(
          File('lib/shared/services/pro_phase_advance.dart').readAsStringSync());
      expect(
        advanceStripped.contains('nextPhaseStartDate()'),
        isTrue,
        reason: 'runGraduationPhaseAdvance must call nextPhaseStartDate() '
            'before invoking generateAndSchedule. Pre-fix '
            '`startDate: DateTime.now()` clobbered Phase 1 W4.',
      );
      // The pre-fix `startDate: DateTime.now()` literal must be gone — checked
      // in BOTH files, so the defect cannot reappear by moving back.
      for (final entry in {
        'pro_phase_advance.dart': advanceStripped,
        'graduation_screen.dart': gradStripped,
      }.entries) {
        expect(
          RegExp(r'startDate:\s*DateTime\.now\(\)').hasMatch(entry.value),
          isFalse,
          reason: '${entry.key} must not pass `startDate: DateTime.now()` '
              '— use nextPhaseStartDate().',
        );
      }
      // And the screen must still ROUTE to that advance — otherwise the
      // assertions above describe code the unlock no longer reaches.
      expect(
        gradStripped.contains('runGraduationPhaseAdvance('),
        isTrue,
        reason: 'graduation_screen._onPro must route through the shared '
            'advance that owns the start-date computation.',
      );
    });

    test('autoGenerateNextPhaseIfNeeded calls nextPhaseStartDate', () {
      // Locate the method body
      final autoIdx = svcStripped.indexOf('autoGenerateNextPhaseIfNeeded');
      expect(autoIdx, greaterThan(-1));
      // Take a window after the signature for the body.
      final tail = svcStripped.substring(autoIdx, autoIdx + 1500);
      expect(
        tail.contains('nextPhaseStartDate()'),
        isTrue,
        reason: 'autoGenerateNextPhaseIfNeeded must call '
            'nextPhaseStartDate() (not raw DateTime.now()) so the '
            'splash-time auto-generate path has the same fix.',
      );
    });
  });

  group('upsertScheduled completed-day guard', () {
    final src = File('lib/core/services/workout_write_service.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('refuses to overwrite status=completed from planGenerator', () {
      // The defensive guard. Extract upsertScheduled body and look for
      // the refusal predicate.
      final idx = stripped.indexOf('upsertScheduled');
      expect(idx, greaterThan(-1));
      final body = stripped.substring(idx, idx + 3000);
      expect(
        RegExp(r"existingMap\['status'\]\s*==\s*'completed'").hasMatch(body),
        isTrue,
        reason: 'upsertScheduled must check existing entry status before '
            'overwriting. Pre-fix planGenerator silently clobbered '
            'completed days.',
      );
      expect(
        body.contains('WriteSource.planGenerator'),
        isTrue,
        reason: 'guard must scope refusal to WriteSource.planGenerator '
            '(other sources like editSheet/activeWorkout/swap legitimately '
            'mutate completed days).',
      );
    });

    test('emits upsert_scheduled_skipped_completed_day telemetry on refusal',
        () {
      expect(
        stripped.contains("'upsert_scheduled_skipped_completed_day'"),
        isTrue,
        reason: 'guard must emit upsert_scheduled_skipped_completed_day '
            'telemetry on refusal so we can detect regression of the '
            'caller-side fix.',
      );
    });
  });
}
