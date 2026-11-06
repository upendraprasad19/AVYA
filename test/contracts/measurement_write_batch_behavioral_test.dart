@Timeout(Duration(minutes: 3))
library;

// L2b Landing B (B1 + B2) - BEHAVIOURAL. The sheet saves its edited sites in
// ONE write: HealthWriteService.logMeasurements (all-or-nothing, rounded then
// judged, one rejection event per call, one put per call) and the save notifier
// that wraps it (MeasurementWriteNotifier.save: the history provider is
// refreshed AFTER the awaited write, the cm/in preference is remembered only
// under token agreement).
//
// Probe values are LITERALS, never read from kBodyMeasurementSpecs.
//
// Plan: docs/plans/coach-measurement-sheet-ui.md (B1, B2, section 4)

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';

import '../helpers/dart_source_slice.dart';
import '../helpers/hive_test_setup.dart';

typedef _Event = ({String op, String? message});

/// 2026-10-05 06:00Z is 11:30 IST on 2026-10-05: the day key is 2026-10-05.
final _day = DateTime.utc(2026, 10, 5, 6);
const _dayKey = 'measurement_2026-10-05';
const _unitKey = 'body_measurement_sheet_unit';

final class _Created extends ProviderObserver {
  final List<ProviderBase<Object?>> providers = [];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    providers.add(context.provider);
  }

  bool saw(ProviderBase<Object?> p) => providers.contains(p);
}

void main() {
  late Directory tempDir;
  late List<_Event> events;
  late List<String> nonFatals;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    // An accepted write fans out a background sync pass; there is no cloud.
    SyncService.pausedForSimulation = true;
    setTestClockTo(_day);
    events = <_Event>[];
    nonFatals = <String>[];
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => events.add((op: op, message: message));
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) => nonFatals.add(reason);
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    SyncService.pausedForSimulation = false;
    resetTestClock();
    await tearDownHiveForTests(tempDir);
  });

  Future<WriteResult> logMany(Map<String, double> sites, {DateTime? date}) =>
      HealthWriteService.instance.logMeasurements(
        date: date ?? _day,
        sites: sites,
        source: WriteSource.manual,
      );

  List<String> measurementKeys() => HiveService.instance.healthBox.keys
      .whereType<String>()
      .where((k) => k.startsWith('measurement_'))
      .toList();

  Map<dynamic, dynamic> record() =>
      HiveService.instance.healthBox.get(_dayKey) as Map;

  // ── B1: HealthWriteService.logMeasurements ────────────────────────────────

  group('B1 logMeasurements', () {
    test('four valid sites are stored in ONE put, rounded to 0.1 cm', () async {
      var puts = 0;
      final sub = HiveService.instance.healthBox
          .watch(key: _dayKey)
          .listen((_) => puts++);
      final res = await logMany({
        'chest': 100.04,
        'waist': 81.0,
        'hips': 95.56,
        'arms': 33.3,
      });
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(res.success, isTrue);
      expect(puts, 1, reason: 'one put per call, never one per site');
      final r = record();
      expect(r['chest'], 100.0);
      expect(r['waist'], 81.0);
      expect(r['hips'], 95.6);
      expect(r['arms'], 33.3);
      expect(r['date'], '2026-10-05');
      expect(events, isEmpty, reason: 'accepted values emit nothing');
    });

    test('the bounds are checked on the ROUNDED value: 49.96 is stored as '
        '50.0, 49.94 is rejected', () async {
      expect((await logMany({'waist': 49.96})).success, isTrue);
      expect(record()['waist'], 50.0);
      events.clear();
      final res = await logMany({'waist': 49.94});
      expect(res.success, isFalse);
      expect(events, hasLength(1));
      expect(events.single.message, 'tier=writer site=waist side=below');
      expect(record()['waist'], 50.0, reason: 'the rejected value did not land');
    });

    test('one offender among valid sites fails ALL, writes nothing and logs '
        'ONE event naming the offender and its side', () async {
      final res = await logMany({'chest': 100.0, 'waist': 3000, 'hips': 95.0});
      expect(res.success, isFalse);
      expect(measurementKeys(), isEmpty);
      expect(events, hasLength(1));
      expect(events.single.op, 'measurement_value_rejected');
      expect(events.single.message, 'tier=writer site=waist side=above');
    });

    test('two offenders still log ONE event, for the FIRST known offender in '
        'map order', () async {
      var res = await logMany({'waist': 40, 'chest': 300});
      expect(res.success, isFalse);
      expect(events, hasLength(1));
      expect(events.single.message, 'tier=writer site=waist side=below');

      events.clear();
      res = await logMany({'chest': 300, 'waist': 40});
      expect(res.success, isFalse);
      expect(events, hasLength(1));
      expect(events.single.message, 'tier=writer site=chest side=above');
      expect(measurementKeys(), isEmpty);
    });

    test('NaN and the infinities are rejected with the nonfinite side', () async {
      for (final v in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        events.clear();
        final res = await logMany({'waist': v});
        expect(res.success, isFalse, reason: '$v');
        expect(events.single.message, 'tier=writer site=waist side=nonfinite');
      }
      expect(measurementKeys(), isEmpty);
    });

    test('an empty map fails, logs nothing and writes nothing', () async {
      final res = await logMany(<String, double>{});
      expect(res.success, isFalse);
      expect(events, isEmpty);
      expect(measurementKeys(), isEmpty);
    });

    test('an unregistered key fails the whole call and logs nothing (an '
        'unknown site has nothing to report)', () async {
      var res = await logMany({'thigh': 80});
      expect(res.success, isFalse);
      res = await logMany({'thigh': 80, 'waist': 80});
      expect(res.success, isFalse, reason: 'all-or-nothing');
      res = await logMany({'Waist': 80});
      expect(res.success, isFalse, reason: 'tokens are exact, not normalised');
      expect(events, isEmpty);
      expect(measurementKeys(), isEmpty);
    });

    test('an unregistered key next to a known offender still reports the '
        'known one', () async {
      final res = await logMany({'thigh': 80, 'waist': 40});
      expect(res.success, isFalse);
      expect(events, hasLength(1));
      expect(events.single.message, 'tier=writer site=waist side=below');
    });

    test('the event never carries the value', () async {
      await logMany({'waist': 3141.5});
      expect(events.single.message!.contains('3141'), isFalse);
    });

    test('sites merge onto a day that already holds others, and untouched '
        'sites keep their value', () async {
      await HiveService.instance.healthBox.put(_dayKey, <String, dynamic>{
        'id': 'meas_1',
        'date': '2026-10-05',
        'chest': 99.0,
        'created_at': '2026-10-05T01:00:00.000Z',
      });
      final res = await logMany({'waist': 80.0, 'arms': 31.0});
      expect(res.success, isTrue);
      final r = record();
      expect(r['chest'], 99.0, reason: 'a site not in the call is kept');
      expect(r['waist'], 80.0);
      expect(r['arms'], 31.0);
      expect(r['id'], 'meas_1', reason: 'the record keeps its identity');
    });

    test('a rejected call leaves an existing record exactly as it was',
        () async {
      await HiveService.instance.healthBox.put(_dayKey, <String, dynamic>{
        'id': 'meas_1',
        'date': '2026-10-05',
        'chest': 99.0,
        'created_at': '2026-10-05T01:00:00.000Z',
      });
      final before = Map<String, dynamic>.from(record());
      final res = await logMany({'waist': 80.0, 'hips': 5});
      expect(res.success, isFalse);
      expect(Map<String, dynamic>.from(record()), before);
    });

    test('the day key is the IST day, not the UTC day', () async {
      // 2026-10-05 20:00Z is 01:30 IST on 2026-10-06.
      final res = await logMany({'waist': 80}, date: DateTime.utc(2026, 10, 5, 20));
      expect(res.success, isTrue);
      expect(measurementKeys(), ['measurement_2026-10-06']);
    });

    test('a logMeasurement and a logMeasurements racing on one day both land',
        () async {
      final a = HealthWriteService.instance.logMeasurement(
        date: _day,
        partName: 'chest',
        valueCm: 100.0,
        source: WriteSource.aiCoach,
      );
      final b = logMany({'waist': 81.0, 'hips': 95.0});
      final results = await Future.wait([a, b]);
      expect(results.every((r) => r.success), isTrue);
      final r = record();
      expect(r['chest'], 100.0);
      expect(r['waist'], 81.0);
      expect(r['hips'], 95.0);
    });

    test('the record is stamped with the CALLER\'s source, whichever it is',
        () async {
      await logMany({'waist': 80.0}); // WriteSource.manual
      expect(record()['source'], WriteSource.manual.code);
      await HealthWriteService.instance.logMeasurements(
        date: _day,
        sites: {'chest': 100.0},
        source: WriteSource.aiCoach,
      );
      expect(record()['source'], WriteSource.aiCoach.code);
      expect(WriteSource.manual.code, isNot(WriteSource.aiCoach.code));
    });

    test('a two-site call is ONE put (and a second call, one more)', () async {
      var puts = 0;
      final sub = HiveService.instance.healthBox
          .watch(key: _dayKey)
          .listen((_) => puts++);
      await logMany({'chest': 100.0, 'waist': 81.0});
      await Future<void>.delayed(Duration.zero);
      expect(puts, 1);
      await logMany({'hips': 95.0});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(puts, 2);
    });

    test('a mixed map next to an existing record leaves it byte for byte and '
        'the box sees ZERO events, whichever order the keys come in', () async {
      await HiveService.instance.healthBox.put(_dayKey, <String, dynamic>{
        'id': 'meas_1',
        'date': '2026-10-05',
        'chest': 99.0,
        'created_at': '2026-10-05T01:00:00.000Z',
      });
      final before = Map<String, dynamic>.from(record());
      var seen = 0;
      final sub = HiveService.instance.healthBox
          .watch(key: _dayKey)
          .listen((_) => seen++);
      for (final m in <Map<String, double>>[
        {'waist': 80.0, 'chest': 3000.0},
        {'chest': 3000.0, 'waist': 80.0},
      ]) {
        final res = await logMany(m);
        expect(res.success, isFalse, reason: '$m');
        expect(Map<String, dynamic>.from(record()), before, reason: '$m');
      }
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, 0, reason: 'a rejected call must not touch the box at all');
    });

    // Hive hands back Map<dynamic, dynamic> for a record that survived a
    // restart; a `Map<String, dynamic>` cast at the call site would throw and
    // turn every second-session save into a failure.
    test('an existing record in the restart shape (Map<dynamic, dynamic>) is '
        'merged, not cast', () async {
      await HiveService.instance.healthBox.put(_dayKey, <dynamic, dynamic>{
        'id': 'meas_1',
        'date': '2026-10-05',
        'chest': 99.0,
        'created_at': '2026-10-05T01:00:00.000Z',
      });
      final res = await logMany({'waist': 80.0});
      expect(res.success, isTrue, reason: res.errorMessage ?? '');
      final r = record();
      expect(r['chest'], 99.0);
      expect(r['waist'], 80.0);
    });

    test('a restore-written record (explicit nulls, user_id, notes) keeps '
        'every field the call does not name', () async {
      await HiveService.instance.healthBox.put(_dayKey, <dynamic, dynamic>{
        'id': 'cloud-id',
        'user_id': kTestUserId,
        'date': '2026-10-05',
        'chest': 101.0,
        'waist': null,
        'hips': null,
        'arms': null,
        'notes': 'from the cloud',
        'created_at': '2026-10-05T01:00:00.000Z',
        'source': 'cloud_restore',
      });
      final res = await logMany({'waist': 80.0});
      expect(res.success, isTrue, reason: res.errorMessage ?? '');
      final r = record();
      expect(r['waist'], 80.0);
      expect(r['chest'], 101.0, reason: 'a site not in the call is kept');
      expect(r.containsKey('hips') && r['hips'] == null, isTrue,
          reason: 'an explicit null is kept as an explicit null');
      expect(r.containsKey('arms') && r['arms'] == null, isTrue);
      expect(r['notes'], 'from the cloud');
      expect(r['user_id'], kTestUserId);
      expect(r['id'], 'cloud-id');
      expect(r['source'], WriteSource.manual.code,
          reason: 'the stamp follows the latest writer');
    });

    // The lock is SHARED with logMeasurement (same day key). With it, a batch
    // that arrives while a single-site write is in flight waits for that write
    // to finish: when the first writer's future completes the batch has not
    // written. Without the shared lock the batch writes (in memory) before the
    // first writer's disk write completes, so the value is already there. This
    // is the positive control for the contended-order test below, and the one
    // row that fails if the batch writer takes another lock.
    test('lock: while another writer holds the day lock the batch has NOT '
        'written yet', () async {
      Object? waistWhenFirstDone = 'unset';
      final first = HealthWriteService.instance
          .logMeasurement(
            date: nowWall(),
            partName: 'chest',
            valueCm: 100.0,
            source: WriteSource.aiCoach,
          )
          .then((r) {
        waistWhenFirstDone = record()['waist'];
        return r;
      });
      final batch = logMany({'waist': 81.0});
      await Future.wait([first, batch]);
      expect(waistWhenFirstDone, isNull,
          reason: 'the batch must wait behind the held day lock');
      expect(record()['chest'], 100.0);
      expect(record()['waist'], 81.0);
    });

    test('the write fans out to the sync layer: both calls are made, after '
        'the put, inside the try (source pin; the behavioural half is '
        'test/sync/measurement_batch_push_test.dart)', () {
      final src = stripDartComments(
          File('lib/core/services/health_write_service.dart').readAsStringSync());
      final body = functionBody(src, 'Future<WriteResult> logMeasurements(');
      expect(countOf(body, 'syncMeasurementsNow()'), 1);
      expect(countOf(body, 'pushSnapshot()'), 1);
      final put = body.indexOf('await box.put(key, record);');
      final sync = body.indexOf('SyncService.instance.syncMeasurementsNow()');
      final push = body.indexOf('SyncService.instance.pushSnapshot()');
      final ret = body.indexOf('return WriteResult.ok(key);');
      expect(put, greaterThan(0));
      expect(sync, greaterThan(put));
      expect(push, greaterThan(put));
      expect(ret, greaterThan(sync));
      expect(ret, greaterThan(push));
      expect(body.indexOf('try {'), lessThan(put),
          reason: 'the fan-out is inside the try, behind the awaited put');
    });

    test('a failing box write is caught and reported under the batch '
        "writer's own reason", () async {
      await HiveUserSession.closeAll();
      final res = await logMany({'waist': 80});
      expect(res.success, isFalse);
      expect(nonFatals, contains('health_write_service_log_measurements'));
      expect(nonFatals, isNot(contains('health_write_service_log_measurement')));
    });
  });

  // ── B2: MeasurementWriteNotifier.save ─────────────────────────────────────

  group('B2 MeasurementWriteNotifier.save', () {
    ProviderContainer makeContainer({String token = kTestUserId}) {
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(token),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('a successful save stores the sites and remembers the unit',
        () async {
      final c = makeContainer();
      final notifier = c.read(measurementWriteProvider.notifier);
      expect(notifier.lastUnitInches(), isNull);
      final res = await notifier.save(
        sites: {'waist': 81.0},
        source: WriteSource.manual,
        inchesUsed: true,
      );
      expect(res.success, isTrue);
      expect(record()['waist'], 81.0);
      expect(notifier.lastUnitInches(), isTrue);
      expect(HiveService.instance.userBox.get(_unitKey), 'in',
          reason: 'stored per user, not in the shared config box');
      expect(HiveService.instance.configBox.containsKey(_unitKey), isFalse);

      await notifier.save(
        sites: {'chest': 100.0},
        source: WriteSource.manual,
        inchesUsed: false,
      );
      expect(notifier.lastUnitInches(), isFalse);
    });

    test('a failed save does NOT remember the unit', () async {
      final c = makeContainer();
      final notifier = c.read(measurementWriteProvider.notifier);
      final res = await notifier.save(
        sites: {'waist': 3000},
        source: WriteSource.manual,
        inchesUsed: true,
      );
      expect(res.success, isFalse);
      expect(notifier.lastUnitInches(), isNull);
    });

    test('a failed save still refreshes a live history provider (a new state '
        'object)', () async {
      final c = makeContainer();
      final sub = c.listen(bodyMeasurementsProvider, (_, _) {});
      addTearDown(sub.close);
      final before = c.read(bodyMeasurementsProvider);
      final res = await c.read(measurementWriteProvider.notifier).save(
            sites: {'waist': 3000},
            source: WriteSource.manual,
            inchesUsed: false,
          );
      expect(res.success, isFalse);
      expect(identical(before, c.read(bodyMeasurementsProvider)), isFalse,
          reason: 'the provider is invalidated whatever the outcome');
    });

    test('the history provider shows the new site after the awaited save',
        () async {
      final c = makeContainer();
      final sub = c.listen(bodyMeasurementsProvider, (_, _) {});
      addTearDown(sub.close);
      expect(c.read(bodyMeasurementsProvider).latest, isEmpty);
      await c.read(measurementWriteProvider.notifier).save(
            sites: {'waist': 81.0},
            source: WriteSource.manual,
            inchesUsed: false,
          );
      final s = c.read(bodyMeasurementsProvider);
      expect(s.loaded, isTrue);
      expect(s.latest['waist']?.cm, 81.0);
      expect(s.lastEntryDate, '2026-10-05');
    });

    // The contended order (plan R5B-6). A first writer holds the day lock; the
    // save waits behind it. A provider refresh placed BEFORE the awaited write
    // is scheduled on a zero-delay timer and builds from a box that holds the
    // first writer's site and not yet this one; nothing would refresh it again.
    // Placed AFTER the await, the refresh reads both. The one assumption is the
    // Dart VM running that timer before the first writer's file write completes;
    // its failure direction is a surviving mutant, so the mutate-and-run in the
    // B-pass file is the control.
    test('contended: with a day lock held by another writer, the refresh after '
        'the awaited save sees BOTH sites', () async {
      final c = makeContainer();
      final sub = c.listen(bodyMeasurementsProvider, (_, _) {});
      addTearDown(sub.close);
      expect(c.read(bodyMeasurementsProvider).latest, isEmpty);

      final first = HealthWriteService.instance.logMeasurement(
        date: nowWall(),
        partName: 'chest',
        valueCm: 100.0,
        source: WriteSource.aiCoach,
      );
      final saved = c.read(measurementWriteProvider.notifier).save(
            sites: {'waist': 81.0},
            source: WriteSource.manual,
            inchesUsed: false,
          );
      await Future.wait([first, saved]);

      final s = c.read(bodyMeasurementsProvider);
      expect(s.latest.keys.toSet(), {'chest', 'waist'},
          reason: 'a refresh scheduled before the await would miss waist');
    });

    // The wiring row for shouldRememberUnit: the token flips while the save is
    // waiting on the held lock, so the unit must not be written for the new
    // account. A control run without the flip proves the harness writes it.
    test('wiring: a token change while the save waits means the unit is NOT '
        'remembered, in either box', () async {
      final c = makeContainer();
      final notifier = c.read(measurementWriteProvider.notifier);

      final first = HealthWriteService.instance.logMeasurement(
        date: nowWall(),
        partName: 'chest',
        valueCm: 100.0,
        source: WriteSource.aiCoach,
      );
      final saved = notifier.save(
        sites: {'waist': 81.0},
        source: WriteSource.manual,
        inchesUsed: true,
      );
      // The save has read tokenBefore (synchronously) and is parked behind the
      // lock; the account changes now.
      c.updateOverrides([
        authUserIdTokenProvider.overrideWithValue('someone-else'),
      ]);
      await Future.wait([first, saved]);

      expect(notifier.lastUnitInches(), isNull);
      expect(HiveService.instance.userBox.containsKey(_unitKey), isFalse);
      expect(HiveService.instance.configBox.containsKey(_unitKey), isFalse);
      expect(record()['waist'], 81.0, reason: 'the value itself was saved');
    });

    test('wiring control: the same sequence WITHOUT the token change '
        'remembers the unit', () async {
      final c = makeContainer();
      final notifier = c.read(measurementWriteProvider.notifier);
      final first = HealthWriteService.instance.logMeasurement(
        date: nowWall(),
        partName: 'chest',
        valueCm: 100.0,
        source: WriteSource.aiCoach,
      );
      final saved = notifier.save(
        sites: {'waist': 81.0},
        source: WriteSource.manual,
        inchesUsed: true,
      );
      await Future.wait([first, saved]);
      expect(notifier.lastUnitInches(), isTrue);
    });

    test('an anonymous token before the save means the unit is NOT remembered',
        () async {
      final c = makeContainer(token: '<anon>');
      final notifier = c.read(measurementWriteProvider.notifier);
      final res = await notifier.save(
        sites: {'waist': 81.0},
        source: WriteSource.manual,
        inchesUsed: true,
      );
      expect(res.success, isTrue);
      expect(notifier.lastUnitInches(), isNull);
    });

    test('noteWritten never CREATES the history provider, and refreshes a live '
        'one', () async {
      final obs = _Created();
      final c = ProviderContainer(
        observers: [obs],
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
      );
      addTearDown(c.dispose);
      final notifier = c.read(measurementWriteProvider.notifier);
      notifier.noteWritten(); // never built: must not throw or create it
      expect(obs.saw(measurementWriteProvider), isTrue, reason: 'control');
      expect(obs.saw(bodyMeasurementsProvider), isFalse);
      final sub = c.listen(bodyMeasurementsProvider, (_, _) {});
      addTearDown(sub.close);
      expect(c.read(bodyMeasurementsProvider).latest, isEmpty);
      await HealthWriteService.instance.logMeasurement(
        date: nowWall(),
        partName: 'arms',
        valueCm: 32.0,
        source: WriteSource.aiCoach,
      );
      notifier.noteWritten();
      expect(c.read(bodyMeasurementsProvider).latest['arms']?.cm, 32.0);
    });
  });
}
