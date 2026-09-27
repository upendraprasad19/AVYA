import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory dir;
  late Box<dynamic> box;
  late List<String> reports;
  late List<MapEntry<String, Map<String, String>?>> telemetryCalls;
  var ownerChanged = false;

  SyncSkipIndex index({bool disabled = false}) => SyncSkipIndex(
        box: box,
        domain: SyncSkipDomain.water,
        disabled: disabled,
        ownerChangedNow: () => ownerChanged,
        reportFailure: (op, e, st) => reports.add(op),
      );

  setUp(() async {
    dir = await setUpHiveForTests();
    box = HiveService.instance.healthBox;
    reports = <String>[];
    ownerChanged = false;
    telemetryCalls = <MapEntry<String, Map<String, String>?>>[];
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) {
      telemetryCalls.add(MapEntry(reason, extra));
    };
  });
  tearDown(() async {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    await tearDownHiveForTests(dir);
  });

  Future<bool> ok() async => true;

  test('first push records; an unchanged second pass skips without calling push', () async {
    final a = index();
    expect(await a.pushIfChanged('2026-09-20', () => 'fp1', ok), isTrue);
    await a.commit(liveKeys: {'2026-09-20'});
    var calls = 0;
    final b = index();
    expect(
        await b.pushIfChanged('2026-09-20', () => 'fp1', () async {
          calls++;
          return true;
        }),
        isTrue);
    expect(calls, 0);
    expect(b.skipped, 1);
  });

  test('a changed fingerprint pushes again and records the new value', () async {
    final a = index();
    await a.pushIfChanged('d', () => 'fp1', ok);
    await a.commit(liveKeys: {'d'});
    final b = index();
    await b.pushIfChanged('d', () => 'fp2', ok);
    await b.commit(liveKeys: {'d'});
    expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.water.indexKey), {'d': 'fp2'});
  });

  test('a thrown push is not recorded, DROPS the old fingerprint, and is reported once', () async {
    final a = index();
    await a.pushIfChanged('d', () => 'fp1', ok);
    await a.commit(liveKeys: {'d'});
    final b = index();
    expect(await b.pushIfChanged('d', () => 'fp2', () async => throw StateError('net')), isFalse);
    expect(await b.pushIfChanged('e', () => 'fp3', () async => throw StateError('net')), isFalse);
    await b.commit(liveKeys: {'d', 'e'});
    expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.water.indexKey), isEmpty,
        reason: 'the edit-then-revert residue: fp1 must not survive a failed push of fp2');
    expect(reports, ['upsert_water_log'], reason: 'first failure of the pass only (D13)');
    expect(b.failed, 2);
  });

  test('push returning false (unconfirmed) records nothing and reports nothing', () async {
    final a = index();
    expect(await a.pushIfChanged('d', () => 'fp1', () async => false), isFalse);
    await a.commit(liveKeys: {'d'});
    expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.water.indexKey), isEmpty);
    expect(reports, isEmpty);
    expect(a.unconfirmed, 1);
  });

  test('a throwing fingerprint fails OPEN: push runs, nothing recorded', () async {
    var calls = 0;
    final a = index();
    expect(
        await a.pushIfChanged('d', () => throw const FormatException('x'), () async {
          calls++;
          return true;
        }),
        isTrue);
    await a.commit(liveKeys: {'d'});
    expect(calls, 1);
    expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.water.indexKey), isEmpty);
  });

  test('two fingerprint failures in one pass report ErrorTelemetry exactly once (H-42/D13)',
      () async {
    final a = index();
    expect(
        await a.pushIfChanged('d', () => throw const FormatException('x'), () async => true),
        isTrue);
    expect(
        await a.pushIfChanged('e', () => throw const FormatException('y'), () async => true),
        isTrue);
    final fpReports =
        telemetryCalls.where((c) => c.key == 'sync_skip_fingerprint_water').toList();
    expect(fpReports, hasLength(1),
        reason: 'first fingerprint failure of the pass only (D13)');
  });

  test('kill switch: every row pushes, nothing recorded, commit deletes the index', () async {
    await box.put(SyncSkipDomain.water.indexKey, {'d': 'fp1'});
    var calls = 0;
    final a = index(disabled: true);
    await a.pushIfChanged('d', () => 'fp1', () async {
      calls++;
      return true;
    });
    await a.commit(liveKeys: {'d'});
    expect(calls, 1, reason: 'a matching stored fingerprint must not skip while disabled');
    expect(box.containsKey(SyncSkipDomain.water.indexKey), isFalse);
  });

  test('owner changed before the push: nothing pushed, pass aborted, commit writes nothing', () async {
    ownerChanged = true;
    var calls = 0;
    final a = index();
    expect(
        await a.pushIfChanged('d', () => 'fp1', () async {
          calls++;
          return true;
        }),
        isFalse);
    await a.commit(liveKeys: {'d'});
    expect(calls, 0);
    expect(a.aborted, isTrue);
    expect(box.containsKey(SyncSkipDomain.water.indexKey), isFalse);
  });

  test('owner changes DURING the push: the push is not recorded', () async {
    final a = index();
    expect(
        await a.pushIfChanged('d', () => 'fp1', () async {
          ownerChanged = true;
          return true;
        }),
        isFalse);
    await a.commit(liveKeys: {'d'});
    expect(box.containsKey(SyncSkipDomain.water.indexKey), isFalse);
  });

  test('commit prunes dead rows and skips the Hive write when nothing changed', () async {
    await box.put(SyncSkipDomain.water.indexKey, {'d': 'fp1', 'gone': 'fp9'});
    final a = index();
    await a.pushIfChanged('d', () => 'fp1', ok);
    await a.commit(liveKeys: {'d'});
    expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.water.indexKey), {'d': 'fp1'});

    final events = <BoxEvent>[];
    final sub = box.watch(key: SyncSkipDomain.water.indexKey).listen(events.add);
    final b = index();
    await b.pushIfChanged('d', () => 'fp1', ok);
    await b.commit(liveKeys: {'d'});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events, isEmpty, reason: 'an idle pass must not rewrite the index');
  });

  test('readIndex tolerates garbage', () async {
    await box.put(SyncSkipDomain.water.indexKey, 'not a map');
    expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.water.indexKey), isEmpty);
    await box.put(SyncSkipDomain.water.indexKey, {'a': 1, 2: 'b', 'c': 'fp'});
    expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.water.indexKey), {'c': 'fp'});
  });

  test('readIndex reports to ErrorTelemetry when the box throws (H-42)', () async {
    final scratch = await Hive.openBox<dynamic>('scratchIndexBox');
    await scratch.close();
    final result = SyncSkipIndex.readIndex(scratch, 'some_key');
    expect(result, isEmpty);
    final idxReports =
        telemetryCalls.where((c) => c.key == 'sync_skip_read_index').toList();
    expect(idxReports, hasLength(1));
    expect(idxReports.single.value, {'index_key': 'some_key'});
  });

  test('recordConfirmed writes one row; clearAll deletes every domain index', () async {
    final wb = HiveService.instance.workoutBox;
    await SyncSkipIndex.recordConfirmed(wb, SyncSkipDomain.plan, kPlanBundleRowKey, 'fpP');
    expect(SyncSkipIndex.readIndex(wb, SyncSkipDomain.plan.indexKey), {'bundle': 'fpP'});
    await box.put(SyncSkipDomain.water.indexKey, {'d': 'x'});
    final cleared = await SyncSkipIndex.clearAll((b) => switch (b) {
          SyncSkipBox.workout => HiveService.instance.workoutBox,
          SyncSkipBox.nutrition => HiveService.instance.nutritionBox,
          SyncSkipBox.health => HiveService.instance.healthBox,
          SyncSkipBox.custom => HiveService.instance.customBox,
        });
    expect(cleared, 2);
    expect(wb.containsKey(SyncSkipDomain.plan.indexKey), isFalse);
    expect(box.containsKey(SyncSkipDomain.water.indexKey), isFalse);
  });

  group('SyncFingerprint', () {
    test('is independent of map key order, recursively', () {
      expect(SyncFingerprint.of({'b': 1, 'a': {'y': 2, 'x': 3}}),
          SyncFingerprint.of({'a': {'x': 3, 'y': 2}, 'b': 1}));
    });

    test('keeps list order', () {
      expect(SyncFingerprint.of([1, 2]), isNot(SyncFingerprint.of([2, 1])));
    });

    test('is the same primitive SyncService used for sched (no re-push burst)', () {
      final payload = <String, dynamic>{'status': 'planned', 'user_id': 'u', 'scheduled_date': '2026-09-26'};
      final sorted = <String, dynamic>{for (final k in payload.keys.toList()..sort()) k: payload[k]};
      expect(SyncFingerprint.ofCanonical(jsonEncode(sorted)),
          SyncService.schedPayloadFingerprint(payload));
    });
  });

  test('domain table: unique keys, the three shipped domains keep their names', () {
    final keys = SyncSkipDomain.values.map((d) => d.indexKey).toList();
    expect(keys.toSet(), hasLength(keys.length));
    expect(SyncSkipDomain.values.map((d) => d.killSwitchKey).toSet(),
        hasLength(SyncSkipDomain.values.length));
    for (final d in SyncSkipDomain.values) {
      expect(d.indexKey, matches(RegExp(r'^sync_[a-z_]+_payload_hash_index$')));
      expect(d.killSwitchKey, matches(RegExp(r'^disable_[a-z_]+_hash_skip$')));
    }
    expect(SyncSkipDomain.sched.indexKey, 'sync_sched_payload_hash_index');
    expect(SyncSkipDomain.exlog.indexKey, 'sync_exlog_payload_hash_index');
    expect(SyncSkipDomain.nlog.indexKey, 'sync_nlog_payload_hash_index');
    expect(SyncSkipDomain.sched.killSwitchKey, 'disable_sched_hash_skip');
    expect(SyncSkipDomain.exlog.killSwitchKey, 'disable_exlog_hash_skip');
    expect(SyncSkipDomain.nlog.killSwitchKey, 'disable_nlog_hash_skip');
  });
}
