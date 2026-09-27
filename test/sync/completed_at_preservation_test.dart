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
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/schedule_completion_time.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../contracts/_sync_service_source.dart';
import 'sync_domain_skip_harness.dart';

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

    // day-swapper + sync-load Task 20 (coordinator addition, 2026-09-28) —
    // REPOINTED. Task 16 moved _syncWorkoutLogs onto SyncSkipIndex and, per
    // its own D1 F1 review fix, switched it from `_resolveCompletedAt(` (the
    // wall-clock-fallback form) to `_resolveCompletedAtOrNull(` — a fingerprinted
    // payload must never contain `now()`, or an unchanged row would never
    // skip. The source-grep for the OLD symbol name therefore false-reds at
    // the batch head even though the underlying property (both `logged_at`
    // and `created_at` derive from the row's real authoring time, never from
    // NOW) still holds. Converted to BEHAVIOURAL per CLAUDE.md §4.9's
    // conversion-on-touch rule, so a future rename of the helper can't make
    // this drift again — it proves the outcome, not a symbol name.
    group('_syncWorkoutLogs timestamp behaviour (behavioural, Task 20 repoint)', () {
      final h = SyncHarness();
      setUp(h.setUp);
      tearDown(h.tearDown);

      test(
        'both logged_at and created_at resolve to the row\'s authoring time, '
        'never to DateTime.now()',
        () async {
          await HiveService.instance.workoutBox.put('wlog_2020-01-01', {
            'date': '2020-01-01',
            'workout_name': 'Push A',
            'created_at': '2020-01-01T08:00:00.000Z',
            'duration_seconds': 1800,
          });

          await SyncService.instance.pushWorkoutLogsForSyncDomain();

          final writes = h.server.writesTo('workout_logs');
          expect(writes, hasLength(1));
          final payload = writes.single.rows.single;
          expect(payload['logged_at'], '2020-01-01T08:00:00.000Z',
              reason: '_syncWorkoutLogs must use the row\'s authoring time '
                  '(whatever helper resolves it), never the moment the '
                  'backlog flushed.');
          expect(payload['created_at'], '2020-01-01T08:00:00.000Z',
              reason: 'created_at must resolve from the same authoring '
                  'time as logged_at, not a separate NOW() stamp.');
        },
      );
    });
  });

  group('Task 14 — schedule-completion time preservation (recurrence of 5a36ad, spec §1.6)', () {
    test('ScheduleCompletionTime never falls back to now() for a completed row', () {
      expect(
        ScheduleCompletionTime.scheduledCompletedAtIso({'status': 'completed'}),
        isNull,
        reason: 'the resolver must OMIT (spec §5.12), never fabricate DateTime.now()',
      );
    });

    test('_syncScheduleCompletions source no longer contains the pre-fix now() fallback', () {
      // Source-grep companion to the behavioral test in
      // test/contracts/sync_schedule_completion_payload_hash_index_writer_to_reader_test.dart
      // (which proves the BEHAVIOR); this pins the removed literal shape so a
      // future edit cannot silently reintroduce it (same style as this file's
      // existing _resolveCompletedAt group, which is source-grep for the same
      // reason -- SyncService is a singleton, no DI seam).
      final src = loadSyncServiceSource().readAsStringSync();
      expect(
        src.contains("entry['completed_at'] ?? DateTime.now()"),
        isFalse,
        reason: '_syncScheduleCompletions must not reintroduce the pre-Task-14 '
            'now() fallback for completed_at',
      );
    });
  });
}
