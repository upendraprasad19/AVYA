// APK Test #12.7 — pin that workout-related sync paths do NOT pass
// empty-string timestamps to PostgREST.
//
// Pre-fix: `_syncScheduledWorkouts` set `'completed_at': entry['completed_at']`
// without filtering `''`. Hive entries written by legacy code paths
// stored an empty string for in-progress schedules; the upsert hit
// `invalid input syntax for type timestamp with time zone: ""`.
//
// Fix: sanitize empty/missing values to `null` before upsert.
//
// Source-grep test pinning the absence of the buggy pattern.

import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

void main() {
  group('Test #12.7 — workout_logs null timestamp handling', () {
    test(
      '_syncScheduledWorkouts sanitizes empty-string completed_at',
      () {
        final src = loadSyncServiceSource().readAsStringSync();

        final mIdx = src.indexOf('Future<void> _syncScheduledWorkouts(');
        expect(mIdx, greaterThan(0));
        final mEnd = src.indexOf('\n  /// ', mIdx + 10);
        final body = src.substring(mIdx,
            mEnd > mIdx ? mEnd : (mIdx + 4000).clamp(0, src.length));

        // The bug pattern: passing entry['completed_at'] directly.
        expect(
          body.contains("'completed_at': entry['completed_at'],"),
          isFalse,
          reason: 'Direct pass-through of entry["completed_at"] sends '
              'empty strings to a timestamptz column → 22007 rejection. '
              'The sync path must sanitize.',
        );

        // The fix introduces a local variable that isNotEmpty-checks.
        expect(
          body,
          contains('isNotEmpty'),
          reason: '_syncScheduledWorkouts must check '
              'rawCompletedAt.isNotEmpty before sending the value. '
              'Empty strings collapse to null.',
        );
      },
    );

    test(
      '_syncWorkoutLogs uses _resolveCompletedAt which rejects empty strings',
      () {
        final src = loadSyncServiceSource().readAsStringSync();

        // The helper itself filters empty strings. Slice from the
        // declaration to the next sibling helper.
        final helperIdx = src.indexOf('String _resolveCompletedAt(');
        expect(helperIdx, greaterThan(0));
        final nextSibling = src.indexOf('String? _dateFromKey(', helperIdx);
        expect(nextSibling, greaterThan(helperIdx));
        final helperBody = src.substring(helperIdx, nextSibling);

        expect(
          helperBody,
          contains('isNotEmpty'),
          reason: '_resolveCompletedAt must reject empty strings on '
              'the string-ISO fields. Without this, empty `completed_at` '
              'entries (legacy Hive rows) reach PostgREST as `""` and '
              '22007.',
        );

        // _syncWorkoutLogs MUST call the helper.
        final mIdx = src.indexOf('Future<void> _syncWorkoutLogs(');
        expect(mIdx, greaterThan(0));
        final mEnd = src.indexOf('\n  ///', mIdx + 10);
        final mBody = src.substring(mIdx,
            mEnd > mIdx ? mEnd : (mIdx + 3000).clamp(0, src.length));

        expect(
          mBody,
          contains('_resolveCompletedAt('),
          reason: '_syncWorkoutLogs must route logged_at + created_at '
              'through _resolveCompletedAt so empty strings can never '
              'reach the cloud upsert.',
        );
      },
    );
  });
}
