// Contract test — refill + consume diagnostic telemetry (2026-05-19).
//
// Pins the three event names emitted by StreakProgressService so a future
// edit can't accidentally drop a diagnostic event we need for post-mortem.
// Source-grep with comment-stripping.

import 'dart:io';
import 'package:test/test.dart';
import '../helpers/read_screen_source.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('Streak freeze diagnostic telemetry', () {
    final src =
        File('lib/core/services/streak_progress_service.dart').readAsStringSync();
    final stripped = _stripComments(src);

    test('imports error_telemetry', () {
      expect(
        stripped.contains("import 'error_telemetry.dart'"),
        isTrue,
        reason: 'StreakProgressService must import ErrorTelemetry to emit '
            'the refill/consume diagnostic events.',
      );
    });

    test('emits streak_freeze_refill_check on every refill check', () {
      expect(
        stripped.contains("'streak_freeze_refill_check'"),
        isTrue,
        reason: 'refillIfNewWeek must emit streak_freeze_refill_check so we '
            'can see willRefill + lastRefill values in client_errors.',
      );
    });

    test('emits streak_freeze_refill_done after commitRefill', () {
      expect(
        stripped.contains("'streak_freeze_refill_done'"),
        isTrue,
        reason: 'commitRefill must emit streak_freeze_refill_done so we can '
            'confirm the refill landed and what the count bumped to.',
      );
    });

    test('emits streak_freeze_consume_done on every consume', () {
      expect(
        stripped.contains("'streak_freeze_consume_done'"),
        isTrue,
        reason: 'commitConsume must emit streak_freeze_consume_done with '
            'newly-flagged dates so a spurious banner can be traced to the '
            'exact day the walk-back penalised.',
      );
    });

    test('commitConsume accepts newlyConsumedDates + walkStartDate plumbing',
        () {
      expect(
        stripped.contains('newlyConsumedDates') &&
            stripped.contains('walkStartDate'),
        isTrue,
        reason: 'commitConsume signature must expose newlyConsumedDates + '
            'walkStartDate so WorkoutRepository._calculateStreak can pass the '
            'missed-date context for telemetry.',
      );
    });

    test(
        'WorkoutRepository._calculateStreak passes missed-date context to commitConsume',
        () {
      final wsrc = File('lib/features/train/repositories/workout_repository.dart')
          .readAsStringSync();
      final wstripped = _stripComments(wsrc);
      expect(
        wstripped.contains('newlyConsumedDates:') &&
            wstripped.contains('walkStartDate:'),
        isTrue,
        reason: '_calculateStreak must pass newlyConsumedDates + walkStartDate '
            'into commitConsume so the diagnostic telemetry has context.',
      );
    });
  });

  group('SyncService restore step + per-op timing telemetry', () {
    final src = File('lib/core/services/sync_service.dart').readAsStringSync();
    final stripped = _stripComments(src);

    test('emits restore_op_done with elapsed ms per _safeRestoreOp', () {
      expect(
        stripped.contains("'restore_op_done'"),
        isTrue,
        reason: '_safeRestoreOp must emit restore_op_done {op, ms} on success '
            'so we can identify the long-pole op behind a slow RestoringScreen.',
      );
    });

    test('emits restore_step_done for each step boundary', () {
      expect(
        stripped.contains("'restore_step_done'"),
        isTrue,
        reason: 'restoreFromCloudForUser must emit restore_step_done {step, '
            'ms} at each step boundary (A/B/C/sub).',
      );
    });

    test('restore_completed includes total_ms', () {
      // The success-path emission must include total_ms in its message.
      expect(
        RegExp(r"'restore_completed'[\s\S]{0,200}total_ms").hasMatch(stripped),
        isTrue,
        reason: 'restore_completed event must carry total_ms so the post-'
            'mortem reads end-to-end restore duration without joining events.',
      );
    });

    test('exposes restoreProgressLabel ValueNotifier for RestoringScreen', () {
      expect(
        stripped.contains('restoreProgressLabel') &&
            stripped.contains('ValueNotifier<String>'),
        isTrue,
        reason: 'SyncService.restoreProgressLabel ValueNotifier must exist so '
            'RestoringScreen can bind to dynamic progress text.',
      );
    });
  });

  group('RestoringScreen migrator timing telemetry', () {
    final src =
        readRestoringScreenSource();
    final stripped = _stripComments(src);

    test('emits restoring_screen_migrator_done for ExlogKeyMigrator', () {
      expect(
        stripped.contains("'restoring_screen_migrator_done'"),
        isTrue,
        reason: 'RestoringScreen must wrap migrators with Stopwatch + emit '
            'restoring_screen_migrator_done so their cost is visible in the '
            'post-mortem.',
      );
    });

    test('binds progress text via ValueListenableBuilder', () {
      expect(
        stripped.contains('ValueListenableBuilder<String>') &&
            stripped.contains('SyncService.instance.restoreProgressLabel'),
        isTrue,
        reason: 'RestoringScreen must render the dynamic progress label via '
            'ValueListenableBuilder so users see step progress during long '
            'restores.',
      );
    });
  });
}
