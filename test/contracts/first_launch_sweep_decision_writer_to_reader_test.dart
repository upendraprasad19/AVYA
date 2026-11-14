@Timeout(Duration(minutes: 5))
library;

// SoT concept `first_launch_sweep_decision` (sync-storm-first-sweep W3, Gate 9):
// the WRITER of the durable `fresh_device_<userId>` marker
// (`SyncService._markFreshDeviceIfEmpty`, which also reads the key to stay
// first-wins) and its only CONSUMER (`SyncService._postponeFirstSweep`: reads and
// deletes it) agree on the key, the value and the stamp.
// The truth tables, the guards and the wiring pins live in
// test/sync/first_sweep_decision_test.dart; this file pins the round trip the
// registry entry names, with a marker key spelled as a LITERAL so a drift in
// `freshDeviceMarkerKey` cannot move writer and reader together unnoticed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';
import '../sync/sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final svc = SyncService.instance;
  const literalKey = 'fresh_device_$kTestUserId';
  Object? raw(String key) => HiveService.instance.syncBox.get(key);
  DateTime? lastFull() {
    final v = HiveService.instance.syncBox.get('last_full_sync');
    return v == null ? null : DateTime.parse(v.toString());
  }

  test('writer -> reader: the marker an empty device wrote is the one the '
      'sweep decision consumes, and the stamp is the marker instant', () async {
    await svc.markFreshDeviceForTest(kTestUserId);
    final written = raw(literalKey);
    expect(written, isNotNull,
        reason: 'the writer stores the marker under fresh_device_<userId>');
    expect(written.toString().endsWith('Z'), isTrue,
        reason: 'the marker is a UTC instant whatever zone the device is in');
    final markerInstant = DateTime.parse(written.toString());

    expect(await svc.postponeFirstSweepForTest(kTestUserId), isTrue);

    final stamp = lastFull();
    expect(stamp, isNotNull);
    expect(stamp!.isAtSameMomentAs(markerInstant), isTrue,
        reason: 'last_full_sync carries the MARKER instant, not now');
    expect(raw(literalKey), isNull, reason: 'the reader consumes the marker');
  });

  test('the reader honours a marker planted under the literal key and ignores '
      'one planted under any other spelling', () async {
    final box = HiveService.instance.syncBox;
    final recent = DateTime.now().toUtc().subtract(const Duration(minutes: 5));

    await box.put('fresh_device', recent.toIso8601String());
    await box.put('fresh_device_someone-else', recent.toIso8601String());
    expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse,
        reason: 'no marker for this user: today\'s sweep runs');
    expect(lastFull(), isNull);
    expect(raw('fresh_device'), isNotNull, reason: 'other keys are left alone');
    expect(raw('fresh_device_someone-else'), isNotNull);

    await box.put(literalKey, recent.toIso8601String());
    expect(await svc.postponeFirstSweepForTest(kTestUserId), isTrue);
    expect(lastFull()!.isAtSameMomentAs(recent), isTrue);
  });

  test('presence only: sync_service.dart builds the key through '
      'freshDeviceMarkerKey in exactly the writer and the reader, never as a '
      'literal', () {
    final src = File('lib/core/services/sync_service.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(RegExp(r'freshDeviceMarkerKey\(').allMatches(src).length, 2,
        reason: 'one call in _markFreshDeviceIfEmpty, one in '
            '_postponeFirstSweep');
    expect(src.contains("'fresh_device_"), isFalse);
    expect(src.contains('"fresh_device_'), isFalse);
  });
}
