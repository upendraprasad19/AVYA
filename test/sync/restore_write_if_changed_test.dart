// Hermes h7F1/h7F2 (L31, diagnose f1c6b4). `_restoreWorkoutTemplates`,
// `_restoreUserProgress` and `_restoreUserProfile` all run on EVERY launch
// (restoreLightweightAlways) and used to write Hive unconditionally, even when
// the cloud row matched what was stored. Each now writes only when the
// restored value differs. These tests count the actual Hive write EVENTS
// (`box.watch`), so "skipped" is observed, not inferred from the value — a
// rewrite of identical content would leave the value unchanged and still be
// the I/O this fix removes.
//
// Every test pairs the skip with a positive case (a real change IS written)
// so none of them would pass if the restore simply never wrote at all, plus a
// kill-switch case (disable_restore_write_if_changed restores the old
// unconditional write).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/template_identity.dart';

import '../helpers/hive_test_setup.dart';

const _cloudId = 'ffffffff-1111-2222-3333-444444444444';

List<Map<String, dynamic>> _templateRows({String name = 'Push Day'}) => [
      {
        'id': _cloudId,
        'name': name,
        'description': null,
        'workout_type': 'strength',
        'created_at': '2026-09-01T00:00:00Z',
        'last_used_at': null,
        'deleted_at': null,
        'template_exercises': [
          {
            'exercise_name': 'Bench Press',
            'exercise_id': 'ex-1',
            'order_index': 0,
            'prescribed_sets': 3,
            'prescribed_reps': '8-12',
            'prescribed_weight': 60,
            'rest_seconds': 90,
          },
        ],
      },
    ];

/// Runs [body] and returns how many Hive write events hit [key] in [box].
Future<int> _writesTo(Box box, String key, Future<void> Function() body) async {
  var count = 0;
  final sub = box.watch(key: key).listen((_) => count++);
  await body();
  // Box events are delivered asynchronously; let them drain.
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await sub.cancel();
  return count;
}

Future<void> _killSwitch(bool on) async {
  if (on) {
    await HiveService.instance.configBox
        .put('disable_restore_write_if_changed', true);
  } else {
    await HiveService.instance.configBox
        .delete('disable_restore_write_if_changed');
  }
}

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

  test('_restoreWorkoutTemplates: unchanged template is not re-written; a '
      'changed one is; the kill switch restores the unconditional write',
      () async {
    final box = HiveService.instance.workoutBox;
    final key = templateKeyFor(_cloudId);
    Future<void> restore(String name) => SyncService.instance
        .restoreWorkoutTemplatesForTest(kTestUserId,
            preFetched: _templateRows(name: name));

    expect(await _writesTo(box, key, () => restore('Push Day')), 1,
        reason: 'first restore must write the template');
    expect(await _writesTo(box, key, () => restore('Push Day')), 0,
        reason: 'an identical cloud row must not be re-written every launch');
    expect(await _writesTo(box, key, () => restore('Push Day B')), 1,
        reason: 'a template edited on another device must still refresh');
    expect((box.get(key) as Map)['name'], 'Push Day B');

    await _killSwitch(true);
    expect(await _writesTo(box, key, () => restore('Push Day B')), 1,
        reason: 'kill switch on: unconditional write, the old behaviour');
    await _killSwitch(false);
  });

  test('_restoreUserProgress: unchanged progress is not re-written; a '
      'changed one is; the kill switch restores the unconditional write',
      () async {
    final box = HiveService.instance.userBox;
    List<Map<String, dynamic>> row(int workouts) => [
          {
            'user_id': kTestUserId,
            'current_phase': 2,
            'total_workouts_done': workouts,
            'current_streak': 4,
          },
        ];
    Future<void> restore(int w) => SyncService.instance
        .restoreUserProgressForTest(kTestUserId, preFetched: row(w));

    expect(await _writesTo(box, 'progress', () => restore(10)), 1);
    expect(await _writesTo(box, 'progress', () => restore(10)), 0,
        reason: 'identical cloud progress must not be re-written');
    expect(await _writesTo(box, 'progress', () => restore(11)), 1,
        reason: 'a real change must still land');
    expect((box.get('progress') as Map)['total_workouts_done'], 11);

    await _killSwitch(true);
    expect(await _writesTo(box, 'progress', () => restore(11)), 1);
    await _killSwitch(false);
  });

  test('_restoreUserProfile: unchanged profile is not re-written even though '
      'updateProfile would re-stamp updated_at; a changed one is; the kill '
      'switch restores the unconditional write', () async {
    final box = HiveService.instance.userBox;
    List<Map<String, dynamic>> profileRow(num weight) => [
          {'user_id': kTestUserId, 'weight_kg': weight, 'goal': 'muscle_gain'},
        ];
    final users = <String, dynamic>{'full_name': 'Test User'};
    Future<void> restore(num w) => SyncService.instance
        .restoreUserProfileForTest(kTestUserId,
            preFetched: profileRow(w), preFetchedUsers: users);

    expect(await _writesTo(box, 'profile', () => restore(70)), 1);
    final stampAfterFirst = (box.get('profile') as Map)['updated_at'];
    expect(await _writesTo(box, 'profile', () => restore(70)), 0,
        reason: 'identical cloud profile must not be re-written — only '
            'updated_at would differ, and only because the write itself '
            'stamps it');
    expect((box.get('profile') as Map)['updated_at'], stampAfterFirst);
    expect(await _writesTo(box, 'profile', () => restore(71)), 1,
        reason: 'a real change must still land');
    expect((box.get('profile') as Map)['weight_kg'], 71);

    await _killSwitch(true);
    expect(await _writesTo(box, 'profile', () => restore(71)), 1);
    await _killSwitch(false);
  });
}
