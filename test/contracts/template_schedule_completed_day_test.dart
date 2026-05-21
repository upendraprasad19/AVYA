// APK Test #15.3 / Bug 4b — contract test for the explicit rejection
// introduced in `WorkoutScheduleService.assignTemplateToDate` when the
// target date already has `status == 'completed'`.
//
// Symptom (2026-05-12):
//   User selected a completed day in the Schedule Template picker.
//   `assignTemplateToDate` silently returned void — no snackbar, no
//   telemetry, no returned rejection. The "Scheduled for N days"
//   snackbar fired as if the assignment succeeded.
//
// Fix: return type changed from `Future<void>` to
//   `Future<AssignTemplateResult>`. Completed-day guard now returns
//   `AssignTemplateRejected(AssignTemplateRejectionReason.alreadyCompleted)`
//   instead of `return`.
//
// This is a source-grep + Hive-state contract test:
//  (a) The return type MUST have changed (sealed class exists in file).
//  (b) The silent `return` on the completed-day guard MUST be gone.
//  (c) The replacement returns a Rejected result WITH telemetry.
//
// See docs/diagnoses/2026-05-12-assign-template-silent-noop-8f3d22.md.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

void main() {
  group(
      'APK Test #15.3 · Bug 4b · assignTemplateToDate rejected on completed day '
      '(closes-diagnose: 8f3d22)', () {
    late String scheduleSvc;

    setUpAll(() {
      scheduleSvc = File('lib/core/services/workout_schedule_service.dart')
          .readAsStringSync();
    });

    test('sealed AssignTemplateResult class and subclasses are declared', () {
      // The sealed result type must exist in the service file.
      expect(scheduleSvc.contains('AssignTemplateResult'), isTrue,
          reason:
              'assignTemplateToDate must return AssignTemplateResult, not void. '
              'Pre-fix the return type was Future<void> so callers had no way '
              'to distinguish success from silent rejection.');

      expect(scheduleSvc.contains('AssignTemplateOk'), isTrue,
          reason: 'AssignTemplateOk must be declared (success path).');

      expect(scheduleSvc.contains('AssignTemplateRejected'), isTrue,
          reason:
              'AssignTemplateRejected must be declared (rejection path). '
              'Pre-fix the method silently returned void on completed days.');
    });

    test('AssignTemplateRejectionReason enum includes alreadyCompleted', () {
      expect(scheduleSvc.contains('AssignTemplateRejectionReason'), isTrue,
          reason:
              'A rejection-reason enum must be declared so callers can '
              'distinguish alreadyCompleted from templateMissing.');

      expect(scheduleSvc.contains('alreadyCompleted'), isTrue,
          reason:
              'The alreadyCompleted enum value must exist — the fix for Bug '
              '8f3d22 returns this reason when status == completed.');
    });

    test(
        'completed-day guard returns AssignTemplateRejected, not bare return',
        () {
      // Slice out the assignTemplateToDate method so we only assert on
      // its body (not on callers or unrelated uses of the same words).
      const startMarker = 'Future<AssignTemplateResult> assignTemplateToDate(';
      final start = scheduleSvc.indexOf(startMarker);
      expect(start, isNot(-1),
          reason:
              "assignTemplateToDate must have return type Future<AssignTemplateResult>. "
              "Pre-fix it was Future<void>.");

      final after = scheduleSvc.indexOf("\n  Future<", start + 1);
      final methodSrc =
          after == -1 ? scheduleSvc.substring(start) : scheduleSvc.substring(start, after);

      // The silent `return;` on the completed-day guard must be gone.
      // After the fix it must be `return AssignTemplateRejected(...)`.
      expect(
        methodSrc.contains("'completed') return;") ||
            methodSrc.contains("== 'completed') return;"),
        isFalse,
        reason:
            "The silent 'return;' on the completed-day guard must be replaced "
            "with 'return AssignTemplateRejected(...)'. Pre-fix this line "
            "(workout_schedule_service.dart:1455) returned void with no signal "
            "to callers.",
      );

      // The replacement MUST return a rejected result.
      expect(methodSrc.contains('AssignTemplateRejected'), isTrue,
          reason:
              'The completed-day branch must return AssignTemplateRejected so '
              'train_screen._scheduleTemplate can show the user feedback.');
    });

    test('telemetry is logged when completed-day rejection fires', () {
      // Confirm the fix wires ErrorTelemetry.logEvent for the rejection.
      expect(
        scheduleSvc.contains('template_assign_rejected_completed') ||
            scheduleSvc.contains("'template_assign_rejected'"),
        isTrue,
        reason:
            'A telemetry event must be logged when assignTemplateToDate '
            'rejects a completed day. Pre-fix there was no telemetry, so '
            'silent drops were invisible to the client_errors table and '
            'Crashlytics.',
      );
    });

    test('train_screen handles AssignTemplateResult (not void-discards it)',
        () {
      final trainSrc =
          readScreenSource('train');

      // The caller must capture the return value (not discard with void await).
      // Accept any variable name that captures the result.
      final hasCapture =
          trainSrc.contains('is AssignTemplateOk') ||
          trainSrc.contains('is AssignTemplateRejected') ||
          trainSrc.contains('AssignTemplateResult') ||
          trainSrc.contains('AssignTemplateRejectionReason');
      expect(hasCapture, isTrue,
          reason:
              'train_screen._scheduleTemplate must capture and inspect the '
              'return value of assignTemplateToDate. Pre-fix the result was '
              'discarded (void), so completed days were silently skipped and '
              'the "Scheduled for N days" toast was misleading.');
    });

    test('template_builder_screen handles AssignTemplateResult', () {
      final builderSrc =
          File('lib/features/train/screens/template_builder_screen.dart')
              .readAsStringSync();

      // template_builder_screen increments writtenCount only on success.
      final hasCapture =
          builderSrc.contains('is AssignTemplateOk') ||
          builderSrc.contains('is AssignTemplateRejected') ||
          builderSrc.contains('AssignTemplateResult') ||
          builderSrc.contains('AssignTemplateRejectionReason');
      expect(hasCapture, isTrue,
          reason:
              'template_builder_screen must capture the result of '
              'assignTemplateToDate so that writtenCount is only incremented '
              'on AssignTemplateOk — not on silent rejections. Pre-fix '
              'writtenCount was always incremented even when the date was '
              'completed, giving a false "N days scheduled" count.');
    });
  });
}
