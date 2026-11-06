@Timeout(Duration(minutes: 5))
library;

// OI-389 Batch 1a T19 payload legs: after a moveExerciseLogs collision the
// km the reader shows and the summary's pushed `distance_km` agree, and a
// sheet-edited destination's stale `sets_detail` no longer narrows the pushed
// per-set rows to the destination side (sync_service prefers sets_detail).
// Hive-level legs (a)-(g): test/contracts/cardio_duration_distance_writer_to_reader_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

import 'sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    h.server.clear();
  });
  tearDown(h.tearDown);

  final to = DateTime.utc(2026, 10, 15);
  final from = DateTime.utc(2026, 10, 14);

  Future<Map<String, dynamic>> merge(
      Map<String, dynamic> dest, Map<String, dynamic> moved) async {
    final box = HiveService.instance.workoutBox;
    await box.put(WorkoutWriteService.exlogKey(to, 'Rowing Machine'),
        {'exercise_name': 'Rowing Machine', 'date': '2026-10-15', ...dest});
    await box.put(WorkoutWriteService.exlogKey(from, 'Rowing Machine'),
        {'exercise_name': 'Rowing Machine', 'date': '2026-10-14', ...moved});
    await WorkoutWriteService.instance
        .moveExerciseLogs(fromDate: '2026-10-14', toDate: '2026-10-15');
    h.server.clear();
    await SyncService.instance
        .pushExerciseLogsForSyncDomain()
        .timeout(const Duration(minutes: 2));
    return Map<String, dynamic>.from(
        box.get(WorkoutWriteService.exlogKey(to, 'Rowing Machine')) as Map);
  }

  List<Map<String, dynamic>> summaries() => [
        for (final r in h.server.writesTo('workout_log_exercises'))
          ...(r.body is List
              ? (r.body! as List).map((e) => Map<String, dynamic>.from(e as Map))
              : [Map<String, dynamic>.from(r.body! as Map)]),
      ];

  List<Map<String, dynamic>> setRows() => [
        for (final r in h.server.writesTo('workout_log_sets'))
          ...(r.body! as List).map((e) => Map<String, dynamic>.from(e as Map)),
      ];

  num? pushedKm() => summaries()
      .singleWhere((s) => s['exercise_name'] == 'Rowing Machine')['distance_km']
      as num?;

  const restored5 = {
    'logging_type': 'cardio',
    'set_number': 1,
    'duration_seconds': 600,
    'distance_km': 5.0,
  };
  Map<String, dynamic> perSet(double? km) => {
        'logging_type': 'cardio',
        'set_number': 1,
        'distance_km': ?km,
        'sets': [
          {'duration_sec': 600, 'distance_km': ?km},
        ],
      };

  test('(a) both restore-shaped: reader and push agree on 8.0', () async {
    final m = await merge(restored5, {...restored5, 'distance_km': 3.0});
    expect(WorkoutReadService.aggregateDistanceKm(m), 8.0);
    expect(pushedKm(), 8.0);
  });

  test('(d) mixed: 3.0 on both (the OI-393 limit, pinned)', () async {
    final m = await merge(restored5, perSet(3));
    expect(WorkoutReadService.aggregateDistanceKm(m), 3.0);
    expect(pushedKm(), 3.0);
  });

  test('(e) restore-shaped 5 km + per-set side with no km: 5.0 on both',
      () async {
    final m = await merge(restored5, perSet(null));
    expect(WorkoutReadService.aggregateDistanceKm(m), 5.0);
    expect(pushedKm(), 5.0);
  });

  test('(f) a sheet-edited destination: the pushed per-set rows cover both '
      'sides', () async {
    await merge({
      ...perSet(2),
      'sets_detail': [
        {'set_number': 1, 'duration_seconds': 600, 'distance_km': 2.0},
      ],
    }, perSet(1));
    expect(setRows().length, 2);
    expect(pushedKm(), 3.0);
  });

  test('(g) a sets_detail-only destination + a per-set moved row: 4 sets, '
      '3.0 km on the reader and the push', () async {
    final m = await merge({
      'logging_type': 'cardio',
      'set_number': 3,
      'sets_detail': [
        for (var i = 0; i < 3; i++)
          {'set_number': i + 1, 'duration_seconds': 300, 'distance_km': 2 / 3},
      ],
    }, perSet(1));
    expect((m['sets'] as List).length, 4);
    expect(WorkoutReadService.aggregateDistanceKm(m), 3.0);
    expect(pushedKm(), 3.0);
    expect(setRows().length, 4);
  });
}
