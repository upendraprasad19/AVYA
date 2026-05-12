import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #15.3 / Bug 7 — workout_log_exercises.duration_seconds must be
/// populated from the per-set sum for timed/cardio exercises.
///
/// Pre-fix: `SyncService._syncExerciseLogs` projection wrote
/// `'duration_seconds': log['duration_seconds']` reading a top-level field
/// the new WorkoutWriteService never sets. The Hive `exlog_*` map carries
/// per-set entries inside `sets[]` with `duration_sec` (canonical) or
/// `duration_seconds` (legacy after restore). Result: cloud column was
/// always null for WriteService-shaped rows; consumers (receipt,
/// train_screen, weekly_report) all worked around by summing per-set
/// `workout_log_sets.duration_secs`. Future analytics joining on
/// `workout_log_exercises` directly would see 0/null — dead schema data.
///
/// Fix — projection now aggregates per-set durations from the resolved
/// per-set list when logging_type is 'timed' or 'cardio'. Per-set entries
/// support BOTH key names (`duration_sec` and `duration_seconds`) matching
/// the dual-name precedent from Bug 4c (6e1b45) and Bug 6 (e1f8a2).
///
/// closes-diagnose: 2026-05-12-duration-seconds-dead-column-a2b3c4
void main() {
  late String syncSrc;
  late String projectionBlock;

  setUpAll(() {
    syncSrc = File('lib/core/services/sync_service.dart').readAsStringSync();
    // Scope assertions to the projection block built right before the
    // workout_log_exercises upsert call, so a coincidental match
    // elsewhere in the file doesn't pass the test.
    final upsertMarker = "from('workout_log_exercises').upsert(";
    final upsertStart = syncSrc.indexOf(upsertMarker);
    expect(upsertStart, greaterThan(0),
        reason: 'workout_log_exercises upsert call must exist');
    // The map literal opens within ~50 chars after `.upsert(` and closes
    // before the `}, onConflict:` clause.
    final blockEnd = syncSrc.indexOf('}, onConflict:', upsertStart);
    expect(blockEnd, greaterThan(upsertStart));
    projectionBlock = syncSrc.substring(upsertStart, blockEnd);
  });

  group('workout_log_exercises.duration_seconds aggregate populated', () {
    test('projection map carries duration_seconds key', () {
      expect(
        projectionBlock.contains("'duration_seconds':"),
        isTrue,
        reason:
            'workout_log_exercises projection must include a duration_seconds '
            'key in the upserted map. closes-diagnose: '
            '2026-05-12-duration-seconds-dead-column-a2b3c4',
      );
    });

    test('forbidden: dead-column read of log[duration_seconds]', () {
      // The pre-fix line was `'duration_seconds': log['duration_seconds'],`
      // which always evaluated to null for WorkoutWriteService rows
      // (writer never sets a top-level duration_seconds field — only
      // per-set `duration_sec` inside `sets[]`).
      expect(
        projectionBlock.contains("'duration_seconds': log['duration_seconds']"),
        isFalse,
        reason:
            'forbidden — projection must not read log[\'duration_seconds\'] '
            'directly. WorkoutWriteService never writes a top-level '
            'duration_seconds field; it lives inside sets[] entries as '
            'duration_sec. Aggregate the per-set list instead.',
      );
    });

    test('projection sums per-set durations for timed/cardio', () {
      // The fix aggregates from the resolved per-set list (already built
      // earlier in _syncExerciseLogs as `resolvedSets`). The aggregate
      // must run for both 'timed' and 'cardio' logging types and support
      // both per-set field name spellings (duration_sec canonical;
      // duration_seconds legacy after restore).
      //
      // Look for the aggregate variable in the projection block: the
      // computed value name we use is `aggregateDurationSecs`.
      expect(
        projectionBlock.contains('aggregateDurationSecs'),
        isTrue,
        reason:
            'projection must reference the per-set duration aggregate '
            '(aggregateDurationSecs) — not the dead top-level read.',
      );
    });

    test('aggregate computation handles both per-set field names', () {
      // The aggregate code lives just above the upsert call within
      // _syncExerciseLogs. Pull a wider window so we can assert on it.
      final methodStart =
          syncSrc.indexOf('Future<void> _syncExerciseLogs(');
      expect(methodStart, greaterThan(0));
      final upsertStart =
          syncSrc.indexOf("from('workout_log_exercises').upsert(", methodStart);
      final preUpsert = syncSrc.substring(methodStart, upsertStart);

      expect(
        preUpsert.contains("'duration_sec'") &&
            preUpsert.contains("'duration_seconds'"),
        isTrue,
        reason:
            'aggregate computation must read both per-set field names '
            '(duration_sec canonical + duration_seconds legacy). Mirrors '
            'the dual-name fallback in workout_receipt_card.dart and the '
            'Bug 4c / Bug 6 precedents.',
      );

      // Aggregate only meaningful for timed/cardio. Other logging types
      // (weight_reps, bodyweight_reps, weighted_bodyweight, distance)
      // should land as 0 — the column is integer NULL but a deterministic
      // 0 is preferable to mixing nulls into analytics.
      expect(
        preUpsert.contains("'timed'") && preUpsert.contains("'cardio'"),
        isTrue,
        reason:
            'aggregate must gate on logging_type in {timed, cardio} — '
            'other types should resolve to 0, not the dead top-level read.',
      );
    });
  });
}
