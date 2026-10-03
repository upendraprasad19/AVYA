// Merge review F4 (day-swapper + sync-load, 2026-09-28). When the cloud says a
// day is rest and no template resolves, `_restoreScheduledWorkouts` types the
// row `rest` (diagnose b6e1c8) — but the `...existingMap` spread kept the
// workout it replaced: template_id, name, exercises. The next push then sent
// that template_id with a rest status, and another device's restore resolved
// it into a `custom_template` row with status rest (the b6e1c8 hybrid again).
// A cross-device day swap is the everyday way a date turns rest in the cloud.
//
// Second half: the completed-row carve-out only covered `cloud planned`, so a
// local completion not yet pushed was demoted by a cloud rest row (spec I6).
//
// BEHAVIORAL: real workoutBox + the real merge through
// `restoreScheduledWorkoutsForTest` (preFetched rows, no Supabase query).
// closes-diagnose: a3e7d9

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  const date = '2026-09-25';
  const tmplKey = 'tmpl_cccccccc-1111-4222-8333-444444444444';

  Map<String, dynamic> cloudRow(String status) => {
        'scheduled_date': date,
        'status': status,
        'completed_at': null,
        'week_number': 3,
        'day_of_week': null,
        'template_id': null,
      };

  Map row() => HiveService.instance.workoutBox.get('schedule_$date') as Map;

  Future<void> restore(String cloudStatus) =>
      SyncService.instance.restoreScheduledWorkoutsForTest(kTestUserId,
          preFetched: [cloudRow(cloudStatus)]);

  Map<String, dynamic> localWorkout({String status = 'planned'}) => {
        'date': date,
        'type': 'custom_template',
        'template_id': tmplKey,
        'workout_name': 'Push A',
        'status': status,
        'exercises': [
          {'exercise_name': 'Bench Press'},
        ],
      };

  test('a workout day the cloud now says is rest keeps NO template link and '
      'NO workout content', () async {
    await HiveService.instance.workoutBox.put('schedule_$date', localWorkout());

    await restore('rest');

    final r = row();
    expect(r['type'], 'rest');
    expect(r['status'], 'rest');
    expect(r.containsKey('template_id'), isFalse,
        reason: 'a kept template_id is pushed with a rest status, and another '
            "device's restore rebuilds a custom_template row with status rest");
    expect(r['exercises'], isEmpty);
    expect(r['workout_name'], 'Rest Day');
  });

  test('MIRROR: a row that was already rest keeps its own name (only the '
      'template link goes)', () async {
    await HiveService.instance.workoutBox.put('schedule_$date', {
      'date': date,
      'type': 'rest',
      'template_id': tmplKey,
      'workout_name': 'Joined later',
      'status': 'rest',
      'exercises': <dynamic>[],
    });

    await restore('rest');

    final r = row();
    expect(r['workout_name'], 'Joined later');
    expect(r.containsKey('template_id'), isFalse);
  });

  test('MIRROR: a cloud PLANNED row leaves the workout content alone', () async {
    await HiveService.instance.workoutBox.put('schedule_$date', localWorkout());

    await restore('planned');

    final r = row();
    expect(r['template_id'], tmplKey);
    expect(r['exercises'], isNotEmpty);
    expect(r['workout_name'], 'Push A');
  });

  test('a local completion not yet pushed is NOT demoted by a cloud rest row '
      '(spec I6), and keeps its exercises', () async {
    await HiveService.instance.workoutBox.put('schedule_$date', {
      ...localWorkout(status: 'completed'),
      'completed_at_ms': DateTime.utc(2026, 9, 25, 6).millisecondsSinceEpoch,
    });

    await restore('rest');

    final r = row();
    expect(r['status'], 'completed');
    expect(r['exercises'], isNotEmpty);
    expect(r['template_id'], tmplKey);
  });
}
