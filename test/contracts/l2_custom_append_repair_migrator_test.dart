// c3e9a4 (d4b8e1 Batch 0b) — L2CustomAppendRepairMigrator removes the customs
// the removed generator lever L2 appended to FUTURE planned days, once per user.
//
// Fixture: the founder's live 2026-10-21 row (cloud plan_json, read
// 2026-10-21): 8 library exercises + 6 of his customs interleaved, with an
// arranged_at_ms stamp. Real Hive, the full bundled library (the library-wins
// check), the real WorkoutWriteService.upsertScheduled. The clock is
// 2026-10-21 09:30 IST, so `schedule_2026-10-21` is TODAY.
//
// Mutations (rule 21): (a) remove the restore-settled gate → "withheld" RED;
// (b) latch despite a failed write → "a failed write does not latch" RED;
// (c) latch on empty customs → "no customs: no latch" RED.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/day_swap/day_swap_rules.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/l2_custom_append_repair_migrator.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

const _user = 'c3e9a4c3-e9a4-4c3e-9a4c-3e9a4c3e9a4c';
const _flagKey = 'l2_custom_repair_v1_done';
const _oldStamp = 1760000000000;

const _founderCustoms = [
  'tuck planche',
  'Barbell Planche Hollow Press',
  'Cable Pull Down',
  'L Sit',
  'Elbow Lever',
  'Single Leg Back Lever',
];
const _founderLibrary = [
  'Barbell Overhead Press',
  'Dumbbell Bench Press',
  'Russian Twist',
  'Reverse Crunch',
  'Tricep Pushdown (Cable)',
  'Machine Lateral Raise',
  'Skull Crusher',
  'Cable Fly',
];

Map<String, dynamic> _ex(String name, {bool coach = false}) => {
      'exercise_name': name,
      'sets': 3,
      'reps': '10',
      'rest_seconds': 60,
      'logging_type': 'weight_reps',
      if (coach) 'swapped_via': 'ai_coach',
    };

/// The founder's 2026-10-21 order: 2 library, the 6 customs, 6 library.
Map<String, dynamic> _founderRow(String date) => {
      'date': date,
      'phase': 4,
      'week': 2,
      'type': 'workout',
      'workout_day_index': 0,
      'workout_name': 'Upper push + core',
      'status': 'planned',
      'completed_at': null,
      'arranged_at_ms': _oldStamp,
      'exercises': [
        _ex(_founderLibrary[0]),
        _ex(_founderLibrary[1]),
        for (final c in _founderCustoms) _ex(c),
        for (final l in _founderLibrary.skip(2)) _ex(l),
      ],
    };

List<String> _names(Object row) => [
      for (final e in ((row as Map)['exercises'] as List))
        '${(e as Map)['exercise_name']}',
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box wb;
  late int pushes;
  late List<String> events;
  // This migrator's own events only: a previous test's fire-and-forget sync
  // can still report into the capture.
  List<String> own() => [
        for (final e in events)
          if (e.startsWith('l2_') || e.startsWith('nonfatal:l2_')) e,
      ];

  /// Records every row write the migrator attempts, instead of writing.
  List<String> recordWrites() {
    final written = <String>[];
    L2CustomAppendRepairMigrator.debugUpsertOverride = (date, entry) async {
      written.add(istDateStr(date));
      return WriteResult.ok(istDateStr(date));
    };
    return written;
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('l2_custom_repair');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put(
          (r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(_user);
    wb = HiveService.instance.workoutBox;
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await wb.clear();
    await HiveService.instance.customBox.clear();
    await HiveService.instance.configBox.clear();
    var i = 0;
    for (final c in [..._founderCustoms, 'Barbell Jump Squats']) {
      await HiveService.instance.customBox.put('custom_exercise_f$i', {
        'type': 'exercise',
        'name': c,
        'primary_muscles': ['Chest'],
      });
      i++;
    }
    setTestClockTo(DateTime(2026, 10, 21, 9, 30));
    HiveUserSession.debugCurrentUidResolverForTests = () => _user;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(_user);
    SyncService.instance.debugSetLastRestoreWithheldReasonForTest(null);
    SyncService.pausedForSimulation = false;
    pushes = 0;
    SyncService.debugPlanPushOverride = () async => pushes++;
    events = <String>[];
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => events.add(op);
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) => events.add('nonfatal:$reason');
    L2CustomAppendRepairMigrator.debugUpsertOverride = null;
  });

  tearDown(() {
    resetTestClock();
    HiveUserSession.debugCurrentUidResolverForTests = null;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    SyncService.instance.debugSetLastRestoreWithheldReasonForTest(null);
    SyncService.debugPlanPushOverride = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    L2CustomAppendRepairMigrator.debugUpsertOverride = null;
  });

  test('strips the 6 customs from future founder rows, keeps the 8 in order, '
      'same key, latches, pushes once', () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    await wb.put('schedule_2026-10-23', _founderRow('2026-10-23'));

    final n = await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(n, 2);
    for (final k in ['schedule_2026-10-22', 'schedule_2026-10-23']) {
      final row = wb.get(k) as Map;
      expect(_names(row), _founderLibrary, reason: k);
      expect(row['status'], 'planned');
      expect(row['workout_name'], 'Upper push + core');
    }
    expect(wb.keys.where((k) => '$k'.startsWith('schedule_')).length, 2,
        reason: 'written under the key it was scanned from, no neighbour');
    expect(wb.get(_flagKey), isTrue);
    expect(pushes, 1);
    expect(events, contains('l2_custom_strip'));
  });

  test('a rewritten row carrying arranged_at_ms is re-stamped with the write '
      'time; a row without one gets none', () async {
    final unstamped = _founderRow('2026-10-23')..remove('arranged_at_ms');
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    await wb.put('schedule_2026-10-23', unstamped);
    final before = DateTime.now().millisecondsSinceEpoch;

    await L2CustomAppendRepairMigrator.runIfNeeded();

    final stamp = (wb.get('schedule_2026-10-22') as Map)['arranged_at_ms'];
    expect(stamp, isA<int>());
    expect(stamp as int, greaterThanOrEqualTo(before),
        reason: 'strictly newer than any stamp a polluted copy carries, so '
            'the stripped week wins the restore merge');
    expect((wb.get('schedule_2026-10-23') as Map).containsKey('arranged_at_ms'),
        isFalse);
  });

  test("today's row is never rewritten and blocks the latch; the next day "
      'it is past and the pass latches', () async {
    final today = _founderRow('2026-10-21');
    await wb.put('schedule_2026-10-21', today);
    await wb.put('schedule_2026-10-23', _founderRow('2026-10-23'));

    await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(_names(wb.get('schedule_2026-10-21')), _names(today));
    expect(_names(wb.get('schedule_2026-10-23')), _founderLibrary);
    expect(wb.get(_flagKey), isNull);
    expect(pushes, 1, reason: 'the rows it did strip still reach the cloud');

    setTestClockTo(DateTime(2026, 10, 22, 7, 0));
    await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(_names(wb.get('schedule_2026-10-21')), _names(today),
        reason: 'yesterday is past: never written');
    expect(wb.get(_flagKey), isTrue);
  });

  test('a paused future day is stripped (pending, not terminal)', () async {
    await wb.put('schedule_2026-10-22',
        {..._founderRow('2026-10-22'), 'status': 'paused'});

    await L2CustomAppendRepairMigrator.runIfNeeded();

    final row = wb.get('schedule_2026-10-22') as Map;
    expect(_names(row), _founderLibrary);
    expect(row['status'], 'paused');
  });

  test('a coach swap to a custom stays', () async {
    final row = _founderRow('2026-10-22');
    (row['exercises'] as List)[2] = _ex('tuck planche', coach: true);
    await wb.put('schedule_2026-10-22', row);

    await L2CustomAppendRepairMigrator.runIfNeeded();

    final names = _names(wb.get('schedule_2026-10-22'));
    expect(names.where(_founderCustoms.contains), ['tuck planche']);
  });

  test('a community-approved custom in exerciseBox is not library: stripped',
      () async {
    final exBox = HiveService.instance.exerciseBox;
    await exBox.put('0c0ffee0-community-l-sit',
        {'name': 'L Sit', 'source': 'community'});
    try {
      await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));

      await L2CustomAppendRepairMigrator.runIfNeeded();

      expect(_names(wb.get('schedule_2026-10-22')), _founderLibrary);
    } finally {
      await exBox.delete('0c0ffee0-community-l-sit');
    }
  });

  test('a community row sharing a bundled name does not hide the bundled row: '
      'the library exercise stays', () async {
    // Keyed to sort BEFORE the bundled E007 'Cable Fly', so a lookup that
    // stops at the first row of the name sees only the community one.
    final exBox = HiveService.instance.exerciseBox;
    await exBox.put('0c0ffee0-community-cable-fly',
        {'name': 'Cable Fly', 'source': 'community'});
    await HiveService.instance.customBox.put('custom_exercise_cf', {
      'type': 'exercise',
      'name': 'Cable Fly',
      'primary_muscles': ['Chest'],
    });
    try {
      await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));

      await L2CustomAppendRepairMigrator.runIfNeeded();

      expect(_names(wb.get('schedule_2026-10-22')), _founderLibrary);
    } finally {
      await exBox.delete('0c0ffee0-community-cable-fly');
    }
  });

  test('completed, past, rest, travel and template rows are never written',
      () async {
    final mixed = [_ex(_founderLibrary[0]), _ex('tuck planche')];
    final rows = <String, Map<String, dynamic>>{
      '2026-10-24': {
        ..._founderRow('2026-10-24'),
        'status': 'completed',
        'exercises': mixed,
      },
      '2026-10-20': _founderRow('2026-10-20'),
      '2026-10-25': {..._founderRow('2026-10-25'), 'template_id': 'tmpl_x'},
      '2026-10-26': {..._founderRow('2026-10-26'), 'type': 'custom_template'},
      '2026-10-27': {'type': 'rest', 'status': 'rest', 'exercises': mixed},
      '2026-10-28': {..._founderRow('2026-10-28'), 'status': 'travel'},
    };
    for (final e in rows.entries) {
      await wb.put('schedule_${e.key}', e.value);
    }
    final written = recordWrites();

    final n = await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(written, isEmpty,
        reason: 'no write is even attempted (the write service would refuse '
            'a completed day anyway, which would hide a missing filter)');
    expect(n, 0);
    for (final e in rows.entries) {
      expect(wb.get('schedule_${e.key}'), e.value, reason: e.key);
    }
  });

  test('never empties a row', () async {
    final onlyCustoms = {
      ..._founderRow('2026-10-22'),
      'exercises': [for (final c in _founderCustoms) _ex(c)],
    };
    await wb.put('schedule_2026-10-22', onlyCustoms);

    await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(_names(wb.get('schedule_2026-10-22')), _founderCustoms);
  });

  test('idempotent: with the latch cleared, a re-scan attempts no write',
      () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    await L2CustomAppendRepairMigrator.runIfNeeded();
    final after = Map<String, dynamic>.from(wb.get('schedule_2026-10-22') as Map);
    await wb.delete(_flagKey);
    final written = recordWrites();

    final again = await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(again, 0);
    expect(written, isEmpty);
    expect(wb.get('schedule_2026-10-22'), after);
    expect(wb.get(_flagKey), isTrue);
  });

  test('a latched user is not scanned again', () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    await wb.put(_flagKey, true);
    final written = recordWrites();

    final n = await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(n, 0);
    expect(written, isEmpty);
    expect(pushes, 0);
  });

  test('a pass that stripped every row but stopped before the push: the next '
      'pass pushes the plan though it has nothing left to strip', () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    // Pass 1: the write clears the restore marker (an account swap mid-pass),
    // so the pass ends without the push.
    L2CustomAppendRepairMigrator.debugUpsertOverride = (date, entry) async {
      await wb.put(WorkoutWriteService.scheduleKey(date), entry);
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
      return WriteResult.ok('x');
    };

    expect(await L2CustomAppendRepairMigrator.runIfNeeded(), 1);

    expect(_names(wb.get('schedule_2026-10-22')), _founderLibrary);
    expect(pushes, 0);
    expect(wb.get(_flagKey), isNull);

    // Pass 2: settled again, and the row is already clean.
    SyncService.instance.debugSetRestoreSettledUserIdForTest(_user);
    final written = recordWrites();

    expect(await L2CustomAppendRepairMigrator.runIfNeeded(), 0);

    expect(written, isEmpty);
    expect(pushes, 1, reason: 'the cloud plan still holds the customs');
    expect(wb.get(_flagKey), isTrue);
  });

  test('withheld (restore not settled): no scan, no latch, no push', () async {
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    SyncService.instance
        .debugSetLastRestoreWithheldReasonForTest('restore_failed');
    final row = _founderRow('2026-10-22');
    await wb.put('schedule_2026-10-22', row);

    final n = await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(n, 0);
    expect(_names(wb.get('schedule_2026-10-22')), _names(row));
    expect(wb.get(_flagKey), isNull);
    expect(pushes, 0);
    expect(own(), ['l2_custom_repair_withheld']);
  });

  test('withheld with no reason recorded logs nothing', () async {
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));

    await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(own(), isEmpty);
  });

  test('a failed write does not latch (next launch retries)', () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    L2CustomAppendRepairMigrator.debugUpsertOverride =
        (date, entry) async => WriteResult.fail('disk full');

    await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(wb.get(_flagKey), isNull);
  });

  test('a row another writer changed after the read: no write, no latch',
      () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    L2CustomAppendRepairMigrator.debugUpsertOverride = (date, entry) async =>
        WriteResult.fail(WorkoutWriteService.rowChangedMessage);

    final n = await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(n, 0);
    expect(wb.get(_flagKey), isNull);
  });

  test('another writer that replaces the row while the pass waits for the date '
      'lock wins: the stale strip is not written, no latch', () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    final theirs = {..._founderRow('2026-10-22'), 'workout_name': 'Swapped in'};
    // upsertScheduled takes the per-date lock synchronously at the call, so
    // this writer holds 10-22 while the pass reads the old row and queues.
    final other = WorkoutWriteService.instance.upsertScheduled(
      date: L2CustomAppendRepairMigrator.writeDateForSuffix('2026-10-22')!,
      entry: theirs,
      source: WriteSource.planGenerator,
    );
    final pass = L2CustomAppendRepairMigrator.runIfNeeded();
    expect((await other).success, isTrue);

    expect(await pass, 0);

    final row = wb.get('schedule_2026-10-22') as Map;
    expect(row['workout_name'], 'Swapped in');
    expect(_names(row), _names(theirs));
    expect(wb.get(_flagKey), isNull,
        reason: 'the next launch strips the new row');
  });

  test('a completed-day refusal is benign: still latches', () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    L2CustomAppendRepairMigrator.debugUpsertOverride = (date, entry) async =>
        WriteResult.fail(WorkoutWriteService.completedDayRefusedMessage);

    await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(wb.get(_flagKey), isTrue);
  });

  test('no customs: nothing stripped and no latch', () async {
    await HiveService.instance.customBox.clear();
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));

    final n = await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(n, 0);
    expect(wb.get(_flagKey), isNull,
        reason: 'a later restore may bring the customs back');
  });

  test('kill switch disable_l2_custom_strip: byte-identical, no latch',
      () async {
    await HiveService.instance.configBox.put('disable_l2_custom_strip', true);
    final row = _founderRow('2026-10-22');
    await wb.put('schedule_2026-10-22', row);

    final n = await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(n, 0);
    expect(wb.get('schedule_2026-10-22'), row);
    expect(wb.get(_flagKey), isNull);
    expect(own(), isEmpty);
  });

  test('push withheld when a future planned workout day has no exercises: '
      'no latch', () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));
    await wb.put('schedule_2026-10-28', {
      'type': 'workout',
      'status': 'planned',
      'exercises': const <dynamic>[],
    });

    await L2CustomAppendRepairMigrator.runIfNeeded();

    expect(_names(wb.get('schedule_2026-10-22')), _founderLibrary);
    expect(pushes, 0);
    expect(events, contains('l2_custom_repair_push_skipped'));
    expect(wb.get(_flagKey), isNull);
  });

  test('a second caller during a pass gets the same pass', () async {
    await wb.put('schedule_2026-10-22', _founderRow('2026-10-22'));

    final results = await Future.wait([
      L2CustomAppendRepairMigrator.runIfNeeded(),
      L2CustomAppendRepairMigrator.runIfNeeded(),
    ]);

    expect(results, [1, 1]);
    expect(pushes, 1);
  });

  group('writeDateForSuffix', () {
    test('UTC midnight of the key date; istDateStr round-trips', () {
      for (final s in ['2026-10-21', '2026-12-31', '2027-01-01']) {
        final d = L2CustomAppendRepairMigrator.writeDateForSuffix(s)!;
        expect(d.isUtc, isTrue, reason: s);
        expect(istDateStr(d), s, reason: s);
        expect(DaySwapRules.format(d), s, reason: s);
      }
    });

    test('rejects a non-date suffix', () {
      for (final s in ['2026-13-45', '2026-02-30', '2026-1-1', 'x', '']) {
        expect(L2CustomAppendRepairMigrator.writeDateForSuffix(s), isNull,
            reason: s);
      }
    });
  });
}
