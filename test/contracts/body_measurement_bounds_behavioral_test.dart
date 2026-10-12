@Timeout(Duration(minutes: 2))
library;

// L2b Landing A (OI-297) - BEHAVIOURAL. Body-measurement values are bounded
// where they enter: the predicate and the rounding (kBodyMeasurementSpecs), the
// writer (HealthWriteService.logMeasurement + measurementRecordWith) and the
// chat parse (PendingLogActionsNotifier, case 'log_measurement'). The READ tier
// is test/contracts/body_measurement_readers_behavioral_test.dart; the confirm
// handler's end of the same bound is in
// test/ai_coach/log_measurement_site_whitelist_test.dart.
//
// Probe values are LITERALS, never read from kBodyMeasurementSpecs: a table that
// reads the spec follows a moved bound and its mutant stays green.
//
// Diagnose: docs/diagnoses/2026-10-11-measurement-values-unbounded-7c3e9a.md

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/constants/body_measurement_specs.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';

import '../helpers/hive_test_setup.dart';

typedef _Event = ({String op, String? message});

final _refProvider = Provider<Ref>((ref) => ref);

/// 2026-10-05 06:00Z is 11:30 IST on 2026-10-05: the day key is 2026-10-05.
final _day = DateTime.utc(2026, 10, 5, 6);
const _dayKey = 'measurement_2026-10-05';

void main() {
  // ── A1: the table, the predicate, the rounding, the message ─────────────

  group('A1 kBodyMeasurementSpecs and its helpers', () {
    test('the table has exactly the registry tokens, both directions', () {
      expect(
        kBodyMeasurementSpecs.keys.toSet(),
        kBodyMeasurementSites.toSet(),
      );
      expect(kBodyMeasurementSpecs, hasLength(kBodyMeasurementSites.length));
    });

    test('every site has min < max', () {
      for (final e in kBodyMeasurementSpecs.entries) {
        expect(e.value.minCm, lessThan(e.value.maxCm), reason: e.key);
      }
    });

    test('every bound is a fixed point of the 0.1 rounding', () {
      // The chat parse checks the RAW value and the writer checks the ROUNDED
      // one. A bound that rounding moves (say an arms maximum of 70.25) would let
      // the parse accept a value the writer then rejects: the card would show,
      // Confirm would do nothing.
      for (final e in kBodyMeasurementSpecs.entries) {
        expect(
          roundMeasurementToTenth(e.value.minCm),
          e.value.minCm,
          reason: '${e.key} min',
        );
        expect(
          roundMeasurementToTenth(e.value.maxCm),
          e.value.maxCm,
          reason: '${e.key} max',
        );
      }
    });

    // (site, value, valid) - literals on purpose.
    const probes = <(String, double, bool)>[
      ('chest', 59.9, false),
      ('chest', 60, true),
      ('chest', 200, true),
      ('chest', 200.1, false),
      ('waist', 49.9, false),
      ('waist', 50, true),
      ('waist', 200, true),
      ('waist', 200.1, false),
      ('hips', 59.9, false),
      ('hips', 60, true),
      ('hips', 200, true),
      ('hips', 200.1, false),
      ('arms', 19.9, false),
      ('arms', 20, true),
      ('arms', 70, true),
      ('arms', 70.1, false),
    ];
    for (final p in probes) {
      test('${p.$1} ${p.$2} is ${p.$3 ? 'valid' : 'invalid'}', () {
        expect(isValidBodyMeasurementCm(p.$1, p.$2), p.$3);
      });
    }

    test('NaN, the infinities, null, an unknown site and a cased site fail', () {
      expect(isValidBodyMeasurementCm('waist', double.nan), isFalse);
      expect(isValidBodyMeasurementCm('waist', double.infinity), isFalse);
      expect(isValidBodyMeasurementCm('waist', double.negativeInfinity), isFalse);
      expect(isValidBodyMeasurementCm('waist', null), isFalse);
      expect(isValidBodyMeasurementCm(null, 80), isFalse);
      expect(isValidBodyMeasurementCm('thigh', 80), isFalse);
      expect(isValidBodyMeasurementCm('neck', 80), isFalse);
      expect(isValidBodyMeasurementCm('Waist', 80), isFalse, reason: 'case');
      expect(isValidBodyMeasurementCm('', 80), isFalse);
      expect(isValidBodyMeasurementCm(' waist', 80), isFalse, reason: 'padding');
    });

    test('roundMeasurementToTenth rounds to one decimal', () {
      expect(roundMeasurementToTenth(49.94), 49.9);
      expect(roundMeasurementToTenth(49.96), 50.0);
      expect(roundMeasurementToTenth(200.04), 200.0);
      expect(roundMeasurementToTenth(70.25), 70.3);
      expect(roundMeasurementToTenth(82.34), 82.3);
      expect(roundMeasurementToTenth(82.0), 82.0);
      // idempotent
      for (final v in <double>[49.9, 50.0, 82.3, 200.0, 95.5]) {
        expect(roundMeasurementToTenth(roundMeasurementToTenth(v)), v);
      }
    });

    test('roundMeasurementToTenth rounds the way the confirm card prints the '
        'value (toStringAsFixed(1)), ties included', () {
      // The card shows value.toStringAsFixed(1) and the writer stores the same
      // rounding, so what the person confirmed is what is stored. These doubles
      // sit just below or above the decimal tie (82.35 is 82.3499999999999943,
      // 33.35 is 33.3500000000000014); 70.25 is an exact tie, which rounds away
      // from zero. A rounding written (v * 10).roundToDouble() / 10 is also
      // total and monotone, but it disagrees on 82.35 (82.4), 70.05 (70.1, over
      // the arms ceiling) and 199.95 (200.0).
      expect(roundMeasurementToTenth(82.35), 82.3);
      expect(roundMeasurementToTenth(70.05), 70.0);
      expect(roundMeasurementToTenth(199.95), 199.9);
      expect(roundMeasurementToTenth(33.35), 33.4);
      expect(roundMeasurementToTenth(70.25), 70.3);
    });

    test('roundMeasurementToTenth is TOTAL: NaN and the infinities come back '
        'unchanged and then fail the predicate', () {
      // `(v * 10).round() / 10` throws UnsupportedError on all three; this is
      // the row that reddens it.
      final nan = roundMeasurementToTenth(double.nan);
      expect(nan.isNaN, isTrue);
      expect(roundMeasurementToTenth(double.infinity), double.infinity);
      expect(
        roundMeasurementToTenth(double.negativeInfinity),
        double.negativeInfinity,
      );
      expect(isValidBodyMeasurementCm('waist', nan), isFalse);
    });

    test('measurementRejectionMessage: exact strings, never the number', () {
      expect(
        measurementRejectionMessage('chat', 'waist', 49.9),
        'tier=chat site=waist side=below',
      );
      expect(
        measurementRejectionMessage('writer', 'arms', 70.1),
        'tier=writer site=arms side=above',
      );
      expect(
        measurementRejectionMessage('chat', 'hips', 0),
        'tier=chat site=hips side=below',
      );
      expect(
        measurementRejectionMessage('chat', 'hips', -3),
        'tier=chat site=hips side=below',
      );
      expect(
        measurementRejectionMessage('writer', 'chest', double.nan),
        'tier=writer site=chest side=nonfinite',
      );
      expect(
        measurementRejectionMessage('chat', 'chest', double.infinity),
        'tier=chat site=chest side=nonfinite',
      );
      expect(
        measurementRejectionMessage('chat', 'chest', double.negativeInfinity),
        'tier=chat site=chest side=nonfinite',
        reason: '-Infinity is non-finite, not "below"',
      );
      // nothing to report
      expect(measurementRejectionMessage('chat', 'waist', 80), isNull);
      expect(measurementRejectionMessage('chat', 'waist', 50), isNull);
      expect(measurementRejectionMessage('chat', 'thigh', 3000), isNull);
      expect(measurementRejectionMessage('chat', null, 3000), isNull);
      expect(measurementRejectionMessage('chat', 'waist', null), isNull);
      // a value that is not a number: wrongtype, for a registered site only
      for (final bad in <Object>[
        '82',
        'abc',
        '',
        true,
        <Object>[],
        <String, Object>{},
      ]) {
        expect(
          measurementRejectionMessage('chat', 'waist', bad),
          'tier=chat site=waist side=wrongtype',
          reason: '$bad',
        );
      }
      expect(measurementRejectionMessage('writer', 'arms', '30'),
          'tier=writer site=arms side=wrongtype');
      expect(measurementRejectionMessage('chat', 'thigh', '82'), isNull);
      expect(measurementRejectionMessage('chat', null, '82'), isNull);
      // the number never appears
      expect(
        measurementRejectionMessage('chat', 'waist', 3141.5)!.contains('3141'),
        isFalse,
      );
    });
  });

  // ── A2: the writer ──────────────────────────────────────────────────────

  group('A2 HealthWriteService.logMeasurement', () {
    late Directory tempDir;
    late List<_Event> events;

    setUp(() async {
      tempDir = await setUpHiveForTests();
      // An accepted write fans out a background sync pass; there is no cloud.
      SyncService.pausedForSimulation = true;
      events = <_Event>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add((op: op, message: message));
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      SyncService.pausedForSimulation = false;
      await tearDownHiveForTests(tempDir);
    });

    Future<WriteResult> log(String part, double v, {DateTime? date}) =>
        HealthWriteService.instance.logMeasurement(
          date: date ?? _day,
          partName: part,
          valueCm: v,
          source: WriteSource.aiCoach,
        );

    List<String> measurementKeys() => HiveService.instance.healthBox.keys
        .whereType<String>()
        .where((k) => k.startsWith('measurement_'))
        .toList();

    Map<dynamic, dynamic> record() =>
        HiveService.instance.healthBox.get(_dayKey) as Map;

    test('an out-of-range value fails, writes nothing and leaves ONE event '
        'with the exact message', () async {
      const rows = <(String, double, String)>[
        ('waist', 3000, 'above'),
        ('waist', 40, 'below'),
        ('arms', 80, 'above'),
        ('chest', 59.9, 'below'),
        ('hips', 200.1, 'above'),
        ('waist', 0, 'below'),
        ('waist', -1, 'below'),
      ];
      for (final r in rows) {
        events.clear();
        final res = await log(r.$1, r.$2);
        expect(res.success, isFalse, reason: '${r.$1} ${r.$2}');
        expect(measurementKeys(), isEmpty, reason: '${r.$1} ${r.$2}');
        expect(events, hasLength(1), reason: '${r.$1} ${r.$2}');
        expect(events.single.op, 'measurement_value_rejected');
        expect(
          events.single.message,
          'tier=writer site=${r.$1} side=${r.$3}',
          reason: '${r.$1} ${r.$2}',
        );
      }
    });

    test('NaN and the infinities fail with the nonfinite side', () async {
      for (final v in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        events.clear();
        final res = await log('waist', v);
        expect(res.success, isFalse, reason: '$v');
        expect(measurementKeys(), isEmpty, reason: '$v');
        expect(events.single.message, 'tier=writer site=waist side=nonfinite');
      }
    });

    test("an unregistered or blank part fails, writes nothing, emits no event "
        '(the handler pre-filters, so only a direct call can reach this)', () async {
      for (final part in ['thigh', ' ', '', 'neck', 'thighs']) {
        final res = await log(part, 80);
        expect(res.success, isFalse, reason: "'$part'");
      }
      expect(measurementKeys(), isEmpty);
      expect(events, isEmpty, reason: 'an unknown site has nothing to report');
    });

    test('the bounds are checked on the ROUNDED value, and the rounded value '
        'is what is stored', () async {
      // 49.96 rounds to 50.0 (valid); validated raw it would be rejected.
      expect((await log('waist', 49.96)).success, isTrue);
      expect(record()['waist'], 50.0);
      // 200.04 rounds to 200.0 (valid).
      expect((await log('chest', 200.04)).success, isTrue);
      expect(record()['chest'], 200.0);
      // 82.34 is stored as 82.3, not 82.34.
      expect((await log('hips', 82.34)).success, isTrue);
      expect(record()['hips'], 82.3);
      expect(events, isEmpty, reason: 'accepted values emit nothing');
    });

    test('49.94 rounds to 49.9, below the waist floor: rejected', () async {
      final res = await log('waist', 49.94);
      expect(res.success, isFalse);
      expect(measurementKeys(), isEmpty);
      expect(events.single.message, 'tier=writer site=waist side=below');
    });

    test('a padded or mixed-case part is stored under the normalised key', () async {
      expect((await log('  Waist ', 80)).success, isTrue);
      final r = record();
      expect(r['waist'], 80.0);
      expect(
        r.keys.toSet(),
        {'id', 'date', 'created_at', 'waist', 'source', 'updated_at_ms', 'updated_at'},
        reason: 'no key named after the raw part',
      );
    });

    test('a rejected write leaves an existing record exactly as it was', () async {
      await HiveService.instance.healthBox.put(_dayKey, <String, dynamic>{
        'id': 'meas_1',
        'date': '2026-10-05',
        'chest': 99.0,
        'waist': 85.0,
        'updated_at_ms': 1,
      });
      final before = jsonEncode(record());
      expect((await log('waist', 3000)).success, isFalse);
      expect((await log('arms', 5)).success, isFalse);
      expect(jsonEncode(record()), before);
    });

    test('an existing record with no date gains its date', () async {
      // A dateless record is skipped by the cloud push and by the reader; the
      // first write after the fix stamps it.
      await HiveService.instance.healthBox.put(_dayKey, <String, dynamic>{
        'id': 'meas_1',
        'chest': 99.0,
      });
      expect((await log('waist', 80)).success, isTrue);
      final r = record();
      expect(r['date'], '2026-10-05');
      expect(r['chest'], 99.0);
      expect(r['waist'], 80.0);
    });

    test('a NEW record has the old writer shape: every stamp comes from ONE '
        'clock reading and only the value is rounded', () async {
      final before = DateTime.now();
      expect((await log('Waist', 82.34)).success, isTrue);
      final after = DateTime.now();
      final r = Map<String, dynamic>.from(record());
      // What the writer before Landing A produced for the same call: the same
      // keys, the raw value, `source` = the WriteSource code.
      expect(r.keys.toSet(), {
        'id',
        'date',
        'created_at',
        'waist',
        'source',
        'updated_at_ms',
        'updated_at',
      });
      expect(r['date'], '2026-10-05');
      expect(r['source'], WriteSource.aiCoach.code);
      expect(r['waist'], 82.3);
      // created_at is pushed to the cloud (measurement_push_rules.dart), so it
      // must be a real timestamp taken during the call; every other stamp
      // derives from the same reading.
      final created = DateTime.parse(r['created_at'] as String);
      expect(created.isBefore(before), isFalse);
      expect(created.isAfter(after), isFalse);
      expect(r['updated_at'], r['created_at']);
      final ms = r['updated_at_ms'] as int;
      expect(ms, created.millisecondsSinceEpoch);
      expect(r['id'], 'meas_$ms');
    });

    test("the source is the caller's: a manual write is stamped manual",
        () async {
      final res = await HealthWriteService.instance.logMeasurement(
        date: _day,
        partName: 'hips',
        valueCm: 97,
        source: WriteSource.manual,
      );
      expect(res.success, isTrue);
      expect(record()['source'], WriteSource.manual.code);
      expect(WriteSource.manual.code, isNot(WriteSource.aiCoach.code));
    });

    test('the key and the stamped date are the IST day, not the UTC day',
        () async {
      // 2026-10-05T20:00Z is 01:30 IST on 2026-10-06: the record belongs to the
      // 6th. A date taken from the UTC clock would file it under the 5th.
      final res = await log('waist', 80, date: DateTime.utc(2026, 10, 5, 20));
      expect(res.success, isTrue);
      expect(measurementKeys(), ['measurement_2026-10-06']);
      final r =
          HiveService.instance.healthBox.get('measurement_2026-10-06') as Map;
      expect(r['date'], '2026-10-06');
    });

    test('a Hive-decoded existing record (Map<dynamic, dynamic>, the shape a '
        'record has after an app restart) is merged, not replaced', () async {
      await HiveService.instance.healthBox.put(_dayKey, <dynamic, dynamic>{
        'id': 'meas_1',
        'date': '2026-10-05',
        'chest': 99.0,
      });
      expect((await log('waist', 80)).success, isTrue);
      final r = record();
      expect(r['id'], 'meas_1');
      expect(r['chest'], 99.0);
      expect(r['waist'], 80.0);
    });

    test('the rejection event names the NORMALISED site', () async {
      final res = await log('  Waist ', 3000);
      expect(res.success, isFalse);
      expect(events.single.message, 'tier=writer site=waist side=above');
    });

    test('a tie value just under the arms ceiling rounds DOWN and is accepted',
        () async {
      // 70.05 is 70.0499999999999972, which toStringAsFixed(1) prints as 70.0;
      // (v * 10).roundToDouble() / 10 gives 70.1 and would refuse it.
      expect((await log('arms', 70.05)).success, isTrue);
      expect(record()['arms'], 70.0);
      expect(events, isEmpty);
    });

    test('a second site on the same day merges and keeps the first', () async {
      expect((await log('chest', 95)).success, isTrue);
      expect((await log('waist', 80)).success, isTrue);
      expect(measurementKeys(), [_dayKey]);
      final r = record();
      expect(r['chest'], 95.0);
      expect(r['waist'], 80.0);
      expect(events, isEmpty);
    });

    test('measurementRecordWith: a non-map existing value starts a new record; '
        'date is stamped on every write; other keys survive', () {
      final fresh = measurementRecordWith(
        'not a map',
        dateStr: '2026-10-05',
        sites: {'hips': 95.0},
        source: WriteSource.aiCoach,
      );
      expect(fresh['date'], '2026-10-05');
      expect(fresh['hips'], 95.0);
      expect((fresh['id'] as String).startsWith('meas_'), isTrue);
      expect(fresh['created_at'], isA<String>());

      // an existing record with a wrong date is re-stamped; explicit nulls (the
      // restore shape) and unrelated keys survive; the given site overwrites.
      final merged = measurementRecordWith(
        <String, dynamic>{
          'id': 'meas_9',
          'date': 'garbage',
          'chest': null,
          'waist': 85.0,
          'notes': 'kept',
        },
        dateStr: '2026-10-05',
        sites: {'waist': 80.0, 'hips': 95.0},
        source: WriteSource.aiCoach,
      );
      expect(merged['date'], '2026-10-05');
      expect(merged['id'], 'meas_9');
      expect(merged.containsKey('chest'), isTrue);
      expect(merged['chest'], isNull);
      expect(merged['waist'], 80.0);
      expect(merged['hips'], 95.0);
      expect(merged['notes'], 'kept');
      expect(merged['source'], WriteSource.aiCoach.code);
      expect(merged['updated_at_ms'], isA<int>());

      // a Hive-decoded map (Map<dynamic, dynamic>) is copied, not rejected
      final decoded = measurementRecordWith(
        <dynamic, dynamic>{'id': 'meas_7', 'chest': 99.0},
        dateStr: '2026-10-05',
        sites: {'waist': 80.0},
        source: WriteSource.aiCoach,
      );
      expect(decoded['id'], 'meas_7');
      expect(decoded['chest'], 99.0);
      expect(decoded['waist'], 80.0);
    });
  });

  // ── A3: the chat parse ──────────────────────────────────────────────────

  group('A3 chat parse (PendingLogActionsNotifier, log_measurement)', () {
    late Directory tempDir;
    late List<_Event> events;

    setUp(() async {
      tempDir = await setUpHiveForTests();
      // The agreement tests below call the writer, whose accepted write fans
      // out a background sync pass; there is no cloud.
      SyncService.pausedForSimulation = true;
      events = <_Event>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add((op: op, message: message));
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      SyncService.pausedForSimulation = false;
      await tearDownHiveForTests(tempDir);
    });

    List<PendingLogAction> parseAll(List<Map<String, dynamic>> actions) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(pendingLogActionsProvider.notifier)
          .addActions(actions, c.read(_refProvider));
      return c.read(pendingLogActionsProvider);
    }

    List<PendingLogAction> parse(Map<String, dynamic> data) => parseAll([
      {'action': 'log_measurement', 'data': data},
    ]);

    test('an accepted value shows a card and emits NOTHING', () {
      for (final row in <(String, num)>[
        ('chest', 95),
        ('waist', 50),
        ('waist', 80.5),
        ('hips', 200),
        ('arms', 20),
        ('arms', 70),
      ]) {
        final pending = parse({'type': row.$1, 'value_cm': row.$2});
        expect(pending, hasLength(1), reason: '${row.$1} ${row.$2}');
      }
      expect(events, isEmpty);
    });

    test('a rejected value of a known site: no card and ONE event, exact message',
        () {
      const rows = <(String, num, String)>[
        ('waist', 3000, 'above'),
        ('waist', 40, 'below'),
        ('waist', 49.9, 'below'),
        ('arms', 80, 'above'),
        ('arms', 70.1, 'above'),
        ('chest', 59.9, 'below'),
        ('hips', 0, 'below'),
        ('hips', -1, 'below'),
        // within 0.05 of a bound: the parse checks the RAW value, so these are
        // refused here although the writer would round them into range (see
        // 'the chat parse is never looser than the writer' below)
        ('waist', 49.96, 'below'),
        ('arms', 70.04, 'above'),
        ('chest', 59.96, 'below'),
        ('hips', 200.04, 'above'),
      ];
      for (final r in rows) {
        events.clear();
        final pending = parse({'type': r.$1, 'value_cm': r.$2});
        expect(pending, isEmpty, reason: '${r.$1} ${r.$2}');
        expect(events, hasLength(1), reason: '${r.$1} ${r.$2}');
        expect(events.single.op, 'measurement_value_rejected');
        expect(
          events.single.message,
          'tier=chat site=${r.$1} side=${r.$3}',
          reason: '${r.$1} ${r.$2}',
        );
      }
    });

    test('Infinity (jsonDecode of 1e999) is dropped as nonfinite', () {
      // A client-side decode: the proxy's own JSON.stringify turns an Infinity
      // into null before a reply reaches the app, so this is the latent-hazard
      // row (the Landing B text field parses user text), not a wire case.
      final inf = jsonDecode('1e999') as num;
      expect(inf.isInfinite, isTrue);
      expect(parse({'type': 'waist', 'value_cm': inf}), isEmpty);
      expect(events.single.message, 'tier=chat site=waist side=nonfinite');
      events.clear();
      expect(parse({'type': 'waist', 'value_cm': double.nan}), isEmpty);
      expect(events.single.message, 'tier=chat site=waist side=nonfinite');
    });

    test('no event for an unknown site, a missing value or a null value', () {
      expect(parse({'type': 'thighs', 'value_cm': 3000}), isEmpty);
      expect(parse({'type': 'Waist', 'value_cm': 3000}), isEmpty);
      expect(parse({'type': 'waist'}), isEmpty);
      expect(parse({'type': 'waist', 'value_cm': null}), isEmpty);
      expect(parse({'value_cm': 80}), isEmpty);
      expect(events, isEmpty);
    });

    test('a wrong-typed value of a known site is dropped without throwing and '
        'leaves ONE wrongtype event', () {
      // Before Landing A `data['value_cm'] as num?` threw a TypeError on each of
      // these inside send's try: the error bubble replaced the reply that was
      // shown. Dropping them quietly would turn a model that starts writing
      // numbers as strings (a String survives the proxy) into a silent outage,
      // so each leaves one event.
      for (final bad in <Object>[
        '82',
        'abc',
        '',
        true,
        <Object>[],
        <String, Object>{},
      ]) {
        events.clear();
        late List<PendingLogAction> pending;
        expect(
          () => pending = parse({'type': 'waist', 'value_cm': bad}),
          returnsNormally,
          reason: 'value_cm $bad',
        );
        expect(pending, isEmpty, reason: 'value_cm $bad');
        expect(events, hasLength(1), reason: 'value_cm $bad');
        expect(events.single.op, 'measurement_value_rejected');
        expect(
          events.single.message,
          'tier=chat site=waist side=wrongtype',
          reason: 'value_cm $bad',
        );
      }
    });

    test('a wrong-typed type, or a wrong-typed value of an unknown site, is '
        'dropped without throwing and without an event', () {
      // `data['type'] as String?` threw on each of these before Landing A. There
      // is no registered site to name, so there is nothing to report.
      for (final bad in <Object>[5, true, <Object>[], 4.5]) {
        late List<PendingLogAction> pending;
        expect(
          () => pending = parse({'type': bad, 'value_cm': 80}),
          returnsNormally,
          reason: 'type $bad',
        );
        expect(pending, isEmpty, reason: 'type $bad');
      }
      expect(parse({'type': 'thighs', 'value_cm': '82'}), isEmpty);
      expect(events, isEmpty);
    });

    test('a wrong-typed action does not take the rest of the response with it',
        () {
      final pending = parseAll([
        {
          'action': 'log_measurement',
          'data': {'type': 'waist', 'value_cm': '82'},
        },
        {
          'action': 'log_measurement',
          'data': {'type': 5, 'value_cm': 80},
        },
        {
          'action': 'log_measurement',
          'data': {'type': 'chest', 'value_cm': 95},
        },
        {
          'action': 'log_water',
          'data': {'ml': 500},
        },
      ]);
      expect(
        pending.map((a) => a.type).toList(),
        [LogActionType.measurement, LogActionType.water],
      );
      expect(pending.first.displayText, 'Chest: 95.0cm');
    });

    test('two actions of one type in one response get distinct ids, and '
        'confirming or skipping one does not touch the other', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(pendingLogActionsProvider.notifier);
      notifier.addActions([
        {
          'action': 'log_water',
          'data': {'ml': 250},
        },
        {
          'action': 'log_water',
          'data': {'ml': 500},
        },
        {
          'action': 'log_measurement',
          'data': {'type': 'waist', 'value_cm': 80},
        },
        {
          'action': 'log_measurement',
          'data': {'type': 'chest', 'value_cm': 95},
        },
      ], c.read(_refProvider));
      final pending = c.read(pendingLogActionsProvider);
      expect(pending, hasLength(4));
      expect(
        pending.map((a) => a.id).toSet(),
        hasLength(4),
        reason: 'one id per action (the id was millisecond + action name)',
      );
      notifier.markLogged(pending[0].id);
      expect(
        c.read(pendingLogActionsProvider).map((a) => a.isLogged).toList(),
        [true, false, false, false],
      );
      notifier.dismiss(pending[3].id);
      expect(
        c.read(pendingLogActionsProvider).map((a) => a.isDismissed).toList(),
        [false, false, false, true],
      );
    });

    // The parse checks the RAW value, the writer the value ROUNDED to 0.1 cm.
    // Every bound is a multiple of 0.1, so anything the parse accepts the writer
    // accepts, and the parse is stricter by under 0.05 cm at an edge. The table
    // is literal on purpose (a table read from the spec follows a moved bound).
    test('the chat parse is never looser than the writer, edge by edge',
        () async {
      // (site, literal floor, literal ceiling)
      const sites = <(String, double, double)>[
        ('chest', 60, 200),
        ('waist', 50, 200),
        ('hips', 60, 200),
        ('arms', 20, 70),
      ];
      for (final s in sites) {
        // (value, the parse accepts it, the writer accepts it)
        final rows = <(double, bool, bool)>[
          (s.$2 - 0.06, false, false), // rounds to 0.1 under the floor
          (s.$2 - 0.04, false, true), // the writer rounds it up onto the floor
          (s.$2, true, true),
          (s.$3, true, true),
          (s.$3 + 0.04, false, true), // the writer rounds it down to the ceiling
          (s.$3 + 0.06, false, false), // rounds to 0.1 over the ceiling
        ];
        for (final r in rows) {
          final why = '${s.$1} ${r.$1}';
          final parsed = parse({'type': s.$1, 'value_cm': r.$1}).isNotEmpty;
          final written = (await HealthWriteService.instance.logMeasurement(
            date: _day,
            partName: s.$1,
            valueCm: r.$1,
            source: WriteSource.aiCoach,
          ))
              .success;
          expect(parsed, r.$2, reason: 'parse: $why');
          expect(written, r.$3, reason: 'writer: $why');
          expect(!parsed || written, isTrue, reason: 'parse looser: $why');
        }
      }
    });

    test('the value on the confirm card is the value the writer stores',
        () async {
      // The card prints value.toStringAsFixed(1) and the writer stores the same
      // rounding, so what the person confirms is what lands. Each raw value
      // sits just under a decimal tie (82.35, 33.35 is just over) or on one
      // (80.25).
      const rows = <(String, double, String, double)>[
        ('waist', 82.35, 'Waist: 82.3cm', 82.3),
        ('chest', 95.15, 'Chest: 95.2cm', 95.2),
        ('hips', 80.25, 'Hips: 80.3cm', 80.3),
        ('arms', 33.35, 'Arms: 33.4cm', 33.4),
      ];
      for (final r in rows) {
        final card = parse({'type': r.$1, 'value_cm': r.$2});
        expect(card.single.displayText, r.$3, reason: r.$1);
        final res = await HealthWriteService.instance.logMeasurement(
          date: _day,
          partName: r.$1,
          valueCm: r.$2,
          source: WriteSource.aiCoach,
        );
        expect(res.success, isTrue, reason: r.$1);
        final rec = HiveService.instance.healthBox.get(_dayKey) as Map;
        expect(rec[r.$1], r.$4, reason: r.$1);
      }
    });
  });
}
