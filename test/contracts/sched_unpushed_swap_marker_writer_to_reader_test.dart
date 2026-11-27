// Contract (Gate 9): sched_unpushed_swap_marker (OI-532, diagnose f5a2c8).
// WRITER WorkoutWriteService.swapScheduledDays -> workoutBox
// ['sched_swap_unpushed'] {date: token} -> READER _restoreScheduledWorkouts.
// Pins the literal key, the per-date shape, and that the reader honours what
// the writer stored. The full behaviour (push clear, races, kill switch) is
// test/sync/sched_restore_unpushed_swap_test.dart.
// closes-diagnose: f5a2c8

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sched_unpushed_swaps.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory dir;
  const a = '2026-09-25';
  const b = '2026-09-26';

  setUp(() async {
    dir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
    SchedUnpushedSwaps.resetForUser();
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    SchedUnpushedSwaps.resetForUser();
    await tearDownHiveForTests(dir);
  });

  test('the swap writes both dates under the literal key, and the restore '
      'reads them and keeps the swapped rows', () async {
    final wb = HiveService.instance.workoutBox;
    await wb.put('schedule_$a', {
      'date': a,
      'type': 'workout',
      'workout_name': 'Pull',
      'exercises': [
        {'name': 'Row'}
      ],
      'status': 'planned',
    });
    await wb.put('schedule_$b', {
      'date': b,
      'type': 'rest',
      'workout_name': 'Rest Day',
      'exercises': <dynamic>[],
      'status': 'rest',
    });

    final r = await WorkoutWriteService.instance.swapScheduledDays(
      dateA: DateTime.parse(a),
      dateB: DateTime.parse(b),
      build: (live) => (
        rowA: Map<String, dynamic>.from(live.rowB!),
        rowB: Map<String, dynamic>.from(live.rowA!),
        displacedA: null,
        displacedB: null,
      ),
    );
    expect(r.success, isTrue);

    final stored = wb.get('sched_swap_unpushed');
    expect(kSchedSwapUnpushedKey, 'sched_swap_unpushed');
    expect(stored, isA<Map>());
    expect((stored as Map)[a], isA<int>());
    expect(stored[b], isA<int>());

    // The cloud still holds the pre-swap rows.
    await SyncService.instance.restoreScheduledWorkoutsForTest(kTestUserId,
        preFetched: [
          {
            'scheduled_date': a,
            'status': 'planned',
            'week_number': 1,
            'template_id': null,
          },
          {
            'scheduled_date': b,
            'status': 'rest',
            'week_number': 1,
            'template_id': null,
          },
        ]);

    final rowB = Map<String, dynamic>.from(wb.get('schedule_$b') as Map);
    expect(rowB['workout_name'], 'Pull');
    expect(rowB['exercises'], isNotEmpty);
    expect(rowB['type'], 'workout');
  });
}
