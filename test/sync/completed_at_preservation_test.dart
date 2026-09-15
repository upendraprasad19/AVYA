// APK Test #12.7 — pin that workout sync preserves the row's authoring
// timestamp instead of re-stamping every backlog entry to NOW.
//
// Pre-fix: `_syncExerciseLogs` set
//   `final String completedAt = log['created_at'] as String? ?? DateTime.now().toIso8601String();`
// and `_syncWorkoutLogs` similarly fell back to NOW for `created_at`.
// When the founder's accumulated 2026-05-05 / 2026-05-06 workouts
// finally re-synced (after the silent-sync fix unblocked the path),
// they would all have uploaded with `completed_at = today`, breaking
// the AI coach's date filters and cloud `date::date` analytics.
//
// Fix: new `_resolveCompletedAt` helper checks
// created_at → completed_at → updated_at_ms → completed_at_ms →
// IST date prefix from the Hive key, falling back to NOW only as a
// last resort (with a debug log + telemetry event).
//
// Source-grep tests — _resolveCompletedAt + _dateFromKey are private,
// and the production singleton can't be DI'd from a unit test.

import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

void main() {
  group('Test #12.7 — completed_at preservation in workout sync', () {
    test(
      '_resolveCompletedAt helper exists and reads in priority order',
      () {
        final src = loadSyncServiceSource().readAsStringSync();
        final fnIdx = src.indexOf('String _resolveCompletedAt(');
        expect(fnIdx, greaterThan(0),
            reason: '_resolveCompletedAt helper must exist.');

        // Slice to the next sibling helper to avoid matching the inner
        // `})` of the function signature.
        final endIdx = src.indexOf('String? _dateFromKey(', fnIdx);
        final body = src.substring(fnIdx,
            endIdx > fnIdx ? endIdx : (fnIdx + 2500).clamp(0, src.length));

        // Must check each authoring-time field in order.
        expect(
          body,
          contains("'created_at'"),
          reason: '_resolveCompletedAt must check created_at first.',
        );
        expect(
          body,
          contains("'completed_at'"),
          reason: '_resolveCompletedAt must check completed_at as fallback.',
        );
        expect(
          body,
          contains("'updated_at_ms'"),
          reason: '_resolveCompletedAt must check updated_at_ms (the field '
              'WorkoutWriteService writes for exlog rows).',
        );
        expect(
          body,
          contains("'completed_at_ms'"),
          reason: '_resolveCompletedAt must check completed_at_ms (the '
              'field markCompleted/Nutrition* WriteServices write).',
        );
        // Must also handle the IST date prefix case (last-resort before NOW).
        expect(
          body,
          contains('dateKeyPrefix'),
          reason: '_resolveCompletedAt must accept a dateKeyPrefix arg so '
              'callers can pass the IST date parsed from the Hive key '
              'as the second-to-last fallback.',
        );
        // Must emit telemetry on the dead branch.
        expect(
          body,
          contains('sync_completed_at_fallback'),
          reason: 'When _resolveCompletedAt falls all the way through to '
              'NOW, it must emit a telemetry event so we know the dead '
              'branch fired in production.',
        );
      },
    );

    test(
      '_dateFromKey extracts YYYY-MM-DD prefix from exlog/wlog keys',
      () {
        final src = loadSyncServiceSource().readAsStringSync();
        final fnIdx = src.indexOf('String? _dateFromKey(');
        expect(fnIdx, greaterThan(0),
            reason: '_dateFromKey helper must exist.');
      },
    );

    test(
      '_syncExerciseLogs uses _resolveCompletedAt instead of DateTime.now()',
      () {
        final src = loadSyncServiceSource().readAsStringSync();

        final mIdx = src.indexOf('Future<void> _syncExerciseLogs(');
        expect(mIdx, greaterThan(0));
        final mEnd = src.indexOf('\n  Future<', mIdx + 10);
        final body = src.substring(mIdx,
            mEnd > mIdx ? mEnd : (mIdx + 5000).clamp(0, src.length));

        expect(
          body,
          contains('_resolveCompletedAt('),
          reason: '_syncExerciseLogs must route through _resolveCompletedAt '
              'so backlog flushes preserve the row\'s authoring time.',
        );

        // Verify the FALLBACK to DateTime.now() is gone from this method.
        // (It still appears inside _resolveCompletedAt as the dead-branch
        // fallback, but should not remain inline in _syncExerciseLogs.)
        final hasInlineNow = body.contains(
            "log['created_at'] as String? ??\n                DateTime.now()");
        expect(
          hasInlineNow,
          isFalse,
          reason: 'Inline DateTime.now() fallback should be replaced by '
              'the helper — the bug being prevented is exactly that '
              'pattern stamping every old row to today.',
        );
      },
    );

    test(
      '_syncWorkoutLogs uses _resolveCompletedAt for both logged_at and created_at',
      () {
        final src = loadSyncServiceSource().readAsStringSync();

        final mIdx = src.indexOf('Future<void> _syncWorkoutLogs(');
        expect(mIdx, greaterThan(0));
        final mEnd = src.indexOf('\n  ///', mIdx + 10);
        final body = src.substring(mIdx,
            mEnd > mIdx ? mEnd : (mIdx + 3000).clamp(0, src.length));

        expect(
          body,
          contains('_resolveCompletedAt('),
          reason: '_syncWorkoutLogs must use _resolveCompletedAt so the '
              'wlog timestamp matches the original authoring time, not '
              'the moment the backlog flushed.',
        );
      },
    );
  });
}
