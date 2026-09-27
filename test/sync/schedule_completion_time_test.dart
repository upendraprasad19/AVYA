import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync/schedule_completion_time.dart';

void main() {
  group('scheduledCompletedAtIso', () {
    test('not completed -> null, even when completed_at_ms is present (defensive)', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtIso({
          'status': 'planned',
          'completed_at_ms': 1700000000000,
        }),
        isNull,
      );
    });

    test('completed with a legacy ISO completed_at -> that value, unchanged', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtIso({
          'status': 'completed',
          'completed_at': '2026-05-05T10:00:00.000Z',
          'completed_at_ms': 9999999999999, // must NOT be preferred over the ISO field
        }),
        '2026-05-05T10:00:00.000Z',
      );
    });

    test('completed with only completed_at_ms (the field markCompleted actually writes on '
        'the schedule row) -> derives the ISO string', () {
      final ms = DateTime.utc(2026, 5, 5, 10).millisecondsSinceEpoch;
      expect(
        ScheduleCompletionTime.scheduledCompletedAtIso({
          'status': 'completed',
          'completed_at_ms': ms,
        }),
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false).toUtc().toIso8601String(),
      );
    });

    test('completed, empty completed_at string, no ms -> null, never now()', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtIso({
          'status': 'completed',
          'completed_at': '',
        }),
        isNull,
      );
    });

    test('completed, no completion-time fields at all -> null, never now()', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtIso({'status': 'completed'}),
        isNull,
      );
    });

    test('completed_at_ms == 0 is not treated as a real timestamp', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtIso({
          'status': 'completed',
          'completed_at_ms': 0,
        }),
        isNull,
      );
    });

    test('never falls back to updated_at_ms (the 5a36ad-recurrence trap, spec §1.6: every '
        'schedule row carries updated_at_ms from its last upsertScheduled, often plan '
        'generation -- reading it here would return the PLAN-GENERATION time)', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtIso({
          'status': 'completed',
          'updated_at_ms': 1700000000000,
        }),
        isNull,
      );
    });
  });

  group('scheduledCompletedAtMs', () {
    test('not completed -> null', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtMs({
          'status': 'planned',
          'completed_at_ms': 123,
        }),
        isNull,
      );
    });

    test('completed_at_ms present -> returned directly', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtMs({
          'status': 'completed',
          'completed_at_ms': 1700000000000,
        }),
        1700000000000,
      );
    });

    test('only a legacy ISO completed_at -> parsed to ms', () {
      final at = DateTime.utc(2026, 5, 5, 10);
      expect(
        ScheduleCompletionTime.scheduledCompletedAtMs({
          'status': 'completed',
          'completed_at': at.toIso8601String(),
        }),
        at.millisecondsSinceEpoch,
      );
    });

    test('never falls back to updated_at_ms', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtMs({
          'status': 'completed',
          'updated_at_ms': 1700000000000,
        }),
        isNull,
      );
    });
  });
}
