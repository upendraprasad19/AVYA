@Timeout(Duration(minutes: 5))
library;

// L1a-2 unit U3 (plan docs/plans/coach-history-correctness-client.md): an
// exercise-log PUSH is dated by the workout day and carries the latest local
// write time, and per-set numbers are made unique. Related bugs: e6a2d4, APK
// Test #12.7, OI-313.
//
//  - day = `date`, else the date in the Hive key, else NO push (a missing date
//    used to land in the shared `v5('workout_')` bucket);
//  - `completed_at` = max(resolved, updated_at_ms) so an edit or move made
//    after a cross-device delete is always LATER than the delete (U4 drains
//    with `completed_at <= deleted_at`); a restored unedited row pushes
//    exactly what it pushes today;
//  - duplicate explicit `set_number`s are renumbered 1..N, gapped legacy sets
//    are left alone;
//  - a non-collision move is a write: it stamps `updated_at_ms`.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/exlog_push_rules.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

import 'sync_domain_skip_harness.dart';

Map<String, dynamic> _bench({
  String date = '2026-09-01',
  Map<String, dynamic> extra = const {},
}) =>
    {
      'exercise_name': 'Bench Press',
      'date': date,
      'logging_type': 'weight_reps',
      'weight_kg': 60.0,
      'reps_completed': 16,
      'set_number': 2,
      'created_at': '${date}T10:00:00.000Z',
      'sets': [
        {'weight_kg': 60.0, 'reps': 8},
        {'weight_kg': 60.0, 'reps': 8},
      ],
      ...extra,
    };

void main() {
  group('latestWriteIso (pure)', () {
    const resolved = '2026-09-01T10:00:00.000Z';
    test('no updated_at_ms: the resolved value, untouched', () {
      expect(latestWriteIso(resolved, null), resolved);
      expect(latestWriteIso(resolved, 0), resolved);
    });
    test('updated_at_ms later than resolved wins', () {
      final later = DateTime.utc(2026, 10, 5, 12).millisecondsSinceEpoch;
      expect(latestWriteIso(resolved, later), '2026-10-05T12:00:00.000Z');
    });
    test('updated_at_ms earlier than resolved loses (max, not overwrite)', () {
      final earlier = DateTime.utc(2026, 8, 1).millisecondsSinceEpoch;
      expect(latestWriteIso(resolved, earlier), resolved);
    });
    test('an unparseable resolved value is replaced by updated_at_ms', () {
      final ms = DateTime.utc(2026, 10, 5).millisecondsSinceEpoch;
      expect(latestWriteIso('garbage', ms), '2026-10-05T00:00:00.000Z');
    });
  });

  group('uniquePerSetNumbers (pure)', () {
    test('two set_number 2 -> the whole list renumbered 1..N in order', () {
      final out = uniquePerSetNumbers([
        {'set_number': 1, 'reps': 5},
        {'set_number': 2, 'reps': 6},
        {'set_number': 2, 'reps': 7},
      ]);
      expect(out.map((s) => s['set_number']), [1, 2, 3]);
      expect(out.map((s) => s['reps']), [5, 6, 7]);
    });
    test('gapped legacy {1,2,4} is kept as it is', () {
      final input = [
        {'set_number': 1},
        {'set_number': 2},
        {'set_number': 4},
      ];
      expect(identical(uniquePerSetNumbers(input), input), isTrue);
    });
  });

  group('exlog push (behavioral, real SyncService + stub)', () {
    final h = SyncHarness();
    setUp(() async {
      await h.setUp();
      h.server.clear();
    });
    tearDown(h.tearDown);

    Future<void> push() => SyncService.instance
        .pushExerciseLogsForSyncDomain()
        .timeout(const Duration(minutes: 2));

    List<Map<String, dynamic>> summaries() => [
          for (final r in h.server.writesTo('workout_log_exercises'))
            ...(r.body is List
                ? (r.body as List).map((e) => Map<String, dynamic>.from(e as Map))
                : [Map<String, dynamic>.from(r.body as Map)]),
        ];

    List<Map<String, dynamic>> setRows() => [
          for (final r in h.server.writesTo('workout_log_sets'))
            ...(r.body as List).map((e) => Map<String, dynamic>.from(e as Map)),
        ];

    test('a row with a date derives workout_log_id from it (unchanged)',
        () async {
      await HiveService.instance.workoutBox
          .put('exlog_2026-09-01_a1b2', _bench());
      await push();
      expect(summaries().single['workout_log_id'],
          SyncService.workoutLogIdForDate('2026-09-01'));
    });

    test('a missing date falls back to the date in the Hive key', () async {
      final row = _bench()..remove('date');
      await HiveService.instance.workoutBox.put('exlog_2026-09-03_a1b2', row);
      await push();
      expect(summaries().single['workout_log_id'],
          SyncService.workoutLogIdForDate('2026-09-03'));
      expect(summaries().single['workout_log_id'],
          isNot(SyncService.workoutLogIdForDate('')),
          reason: 'never the shared missing-date bucket');
    });

    test('no date and no date in the key: nothing is pushed', () async {
      final row = _bench()..remove('date');
      await HiveService.instance.workoutBox.put('exlog_legacykey', row);
      await push();
      expect(summaries(), isEmpty);
      expect(setRows(), isEmpty);
    });

    test(
        'a restored row edited later pushes the edit time; the row\'s old '
        'created_at no longer wins', () async {
      final editMs = DateTime.utc(2026, 10, 5, 12).millisecondsSinceEpoch;
      await HiveService.instance.workoutBox.put(
          'exlog_2026-09-01_a1b2', _bench(extra: {'updated_at_ms': editMs}));
      await push();
      final s = summaries().single;
      expect(s['completed_at'], '2026-10-05T12:00:00.000Z');
      expect(s['workout_log_id'], SyncService.workoutLogIdForDate('2026-09-01'),
          reason: 'the DAY is still the workout day');
    });

    test('a restored unedited row pushes exactly what it pushes today',
        () async {
      await HiveService.instance.workoutBox
          .put('exlog_2026-09-01_a1b2', _bench());
      await push();
      expect(summaries().single['completed_at'], '2026-09-01T10:00:00.000Z');
    });

    test('duplicate explicit set_numbers are renumbered; gapped are kept',
        () async {
      await HiveService.instance.workoutBox.put(
        'exlog_2026-09-01_dup',
        _bench(extra: {
          'exercise_name': 'Row',
          'sets_detail': [
            {'set_number': 1, 'weight_kg': 40.0, 'reps': 8},
            {'set_number': 2, 'weight_kg': 40.0, 'reps': 8},
            {'set_number': 2, 'weight_kg': 42.5, 'reps': 6},
          ],
        })
          ..remove('sets'),
      );
      await HiveService.instance.workoutBox.put(
        'exlog_2026-09-01_gap',
        _bench(extra: {
          'exercise_name': 'Squat',
          'sets_detail': [
            {'set_number': 1, 'weight_kg': 80.0, 'reps': 5},
            {'set_number': 2, 'weight_kg': 80.0, 'reps': 5},
            {'set_number': 4, 'weight_kg': 80.0, 'reps': 5},
          ],
        })
          ..remove('sets'),
      );
      await push();
      final byEx = <String, List<int>>{};
      for (final r in setRows()) {
        (byEx[r['exercise_id'] as String] ??= []).add(r['set_number'] as int);
      }
      expect(byEx['Row']!..sort(), [1, 2, 3]);
      expect(byEx['Squat']!..sort(), [1, 2, 4]);
    });
  });

  group('moveExerciseLogs stamps updated_at_ms (the write that a restored '
      'row\'s created_at would otherwise hide)', () {
    final h = SyncHarness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    test('non-collision branch', () async {
      final box = HiveService.instance.workoutBox;
      final from = WorkoutWriteService.exlogKey(
          DateTime.utc(2026, 9, 1), 'Bench Press');
      await box.put(from, {..._bench(), 'id': from});
      final before = DateTime.now().millisecondsSinceEpoch;
      await WorkoutWriteService.instance
          .moveExerciseLogs(fromDate: '2026-09-01', toDate: '2026-09-02');
      final to = WorkoutWriteService.exlogKey(
          DateTime.utc(2026, 9, 2), 'Bench Press');
      final moved = Map<String, dynamic>.from(box.get(to) as Map);
      expect(moved['date'], '2026-09-02');
      expect(moved['updated_at_ms'], isA<int>());
      expect(moved['updated_at_ms'] as int, greaterThanOrEqualTo(before));
    });
  });
}
