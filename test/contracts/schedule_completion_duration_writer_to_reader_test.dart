// Regression test for audit 2026-05-16 / F3-1.3
// (schedule completion duration_seconds join fix).
//
// Bug: `workout_schedule_completions.duration_seconds` was 100% NULL in
// cloud (11/11 prod rows). The Hive-to-cloud sync method
// `_syncScheduleCompletions` (`lib/core/services/sync/sync_workout.dart`)
// projected `entry['duration_seconds']` where `entry` was a
// `schedule_<date>` Hive row. Schedule entries don't carry that field —
// `duration_seconds` is written by `WorkoutWriteService.markCompleted`
// onto the `wlog_<istDateStr>` workout-log row (NOT the schedule row).
//
// `workout_logs.duration_seconds` was 0/8 NULL (correctly populated), so
// the data existed; the writer was simply joining the wrong Hive key.
//
// Fix: before the projection, look up `wlog_<dateStr>` from workoutBox and
// pull `duration_seconds` from it. Project the field only when non-null
// (absent beats explicit null on the wire; column is nullable).
//
// This is a source-grep contract test: it scans `sync_workout.dart` for
// the canonical pattern (1) the wlog lookup keyed by IST `dateStr`, (2)
// the `duration_seconds` read from that wlog, and (3) the lookup happens
// BEFORE the upsert payload map literal. If any of these three breaks,
// the test fails before the next APK ships.
//
// closes-diagnose: 2026-05-16-schedule-completion-duration

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workout_schedule_completions.duration_seconds writer joins wlog', () {
    late String src;
    late int methodStart;
    late String slice;
    late int upsertOffset;

    setUpAll(() {
      final file = File('lib/core/services/sync/sync_workout.dart');
      expect(file.existsSync(), isTrue,
          reason: 'sync_workout.dart must exist at the expected path');
      src = file.readAsStringSync();

      // Find the `_syncScheduleCompletions` method body.
      methodStart =
          src.indexOf('Future<void> _syncScheduleCompletions(String userId)');
      expect(methodStart, isNot(-1),
          reason: '_syncScheduleCompletions method must exist');

      // Grab a slice large enough to cover the method body. The body is
      // ~30 lines pre-fix, ~40 lines post-fix — 2500 bytes is plenty and
      // bounded to avoid bleeding into the next method.
      final sliceEnd = (methodStart + 2500).clamp(0, src.length);
      slice = src.substring(methodStart, sliceEnd);

      // Find the upsert call — fix must happen BEFORE this point in the
      // method body. The call may be split across lines (`.from(...)\n
      // .upsert(...)`) so we anchor on the table name, which is unique
      // within this method body.
      upsertOffset = slice.indexOf("'workout_schedule_completions'");
      expect(upsertOffset, isNot(-1),
          reason: 'upsert to workout_schedule_completions must exist');
    });

    test(
        'wlog_<dateStr> lookup is present in _syncScheduleCompletions and '
        'happens BEFORE the upsert call', () {
      // The fix must look up the matching wlog from workoutBox by
      // `wlog_<dateStr>`. The schedule entry's `date` field is already
      // IST (docs/architecture/sync.md) so reusing it for the wlog key preserves the
      // IST convention.
      final lookupOffset = slice.indexOf("workoutBox.get('wlog_");
      expect(lookupOffset, isNot(-1),
          reason:
              "_syncScheduleCompletions must look up wlog_<dateStr> from "
              "workoutBox. The schedule entry has no `duration_seconds` "
              "field — pre-fix the projection was 100% NULL on cloud.");

      // The lookup must precede the upsert (we need the value to project it).
      expect(lookupOffset, lessThan(upsertOffset),
          reason:
              "wlog lookup must happen BEFORE the upsert payload is "
              "constructed — otherwise the projection still reads from "
              "the schedule entry which never has the field.");
    });

    test(
        'duration_seconds is read from the wlog row (not the schedule entry)',
        () {
      // The wlog read MUST extract `duration_seconds`. We also tolerate a
      // `num?` cast — `WorkoutWriteService.markCompleted` writes int but
      // restore paths may write num. The signal we need: the field name
      // appears in the slice with the wlog (Map) read.
      expect(slice.contains("'duration_seconds'"), isTrue,
          reason:
              "_syncScheduleCompletions must reference the "
              "'duration_seconds' field name (either reading from wlog or "
              "projecting onto cloud). Without this the column stays NULL.");

      // Anti-regression: the OLD broken projection was
      // `entry['duration_seconds']`. The schedule entry never carries
      // this field, so reading from `entry` is a bug. Permit it nowhere
      // in the method body.
      expect(slice.contains("entry['duration_seconds']"), isFalse,
          reason:
              "Pre-fix code read entry['duration_seconds'] from the "
              "schedule entry — that field NEVER exists there. The fix "
              "must read from the wlog_<dateStr> row instead.");
    });

    test(
        'duration_seconds projection is conditional (omit on null, do not '
        'send explicit null)', () {
      // The fix uses `if (durationSeconds != null) 'duration_seconds': ...`
      // — `cloud column is nullable` so absence beats explicit null
      // (matches the rest of sync_workout.dart's projection style; cf.
      // `_syncStreaks` which uses `if (... != null)` guards on every
      // optional column).
      //
      // Accept either the inline-if form OR a guarded write. The key
      // anti-pattern is unconditional `'duration_seconds': <var>` where
      // <var> could be null.
      final hasConditional = RegExp(
        r"if\s*\(\s*[\w?.\[\]']+\s*!=\s*null\s*\)\s*'duration_seconds'\s*:",
      ).hasMatch(slice);
      expect(hasConditional, isTrue,
          reason:
              "duration_seconds projection must be guarded by a non-null "
              "check (omit when wlog is missing or field is null). This "
              "matches the projection-style convention in this file "
              "(_syncStreaks, _syncWorkoutLogs).");
    });
  });
}
