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

    test('a NEW record differs from the old writer output only in the rounded '
        'value', () async {
      expect((await log('Waist', 82.34)).success, isTrue);
      final r = Map<String, dynamic>.from(record());
      // What the writer before Landing A produced for the same call: the same
      // keys, the raw value, `source` = the WriteSource code.
      final old = <String, dynamic>{
        'id': r['id'],
        'date': '2026-10-05',
        'created_at': r['created_at'],
        'waist': 82.34,
        'source': WriteSource.aiCoach.code,
        'updated_at_ms': r['updated_at_ms'],
        'updated_at': r['updated_at'],
      };
      expect(r.keys.toSet(), old.keys.toSet());
      for (final k in r.keys) {
        if (k == 'waist') continue;
        expect(r[k], old[k], reason: k);
      }
      expect(r['waist'], 82.3);
      expect((r['id'] as String).startsWith('meas_'), isTrue);
      expect(r['updated_at_ms'], isA<int>());
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
    });
  });

  // ── A3: the chat parse ──────────────────────────────────────────────────

  group('A3 chat parse (PendingLogActionsNotifier, log_measurement)', () {
    late Directory tempDir;
    late List<_Event> events;

    setUp(() async {
      tempDir = await setUpHiveForTests();
      events = <_Event>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add((op: op, message: message));
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
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
      final inf = jsonDecode('1e999') as num;
      expect(inf.isInfinite, isTrue);
      expect(parse({'type': 'waist', 'value_cm': inf}), isEmpty);
      expect(events.single.message, 'tier=chat site=waist side=nonfinite');
      events.clear();
      expect(parse({'type': 'waist', 'value_cm': double.nan}), isEmpty);
      expect(events.single.message, 'tier=chat site=waist side=nonfinite');
    });

    test('no event for an unknown site, a missing value or a wrong-typed value',
        () {
      expect(parse({'type': 'thighs', 'value_cm': 3000}), isEmpty);
      expect(parse({'type': 'Waist', 'value_cm': 3000}), isEmpty);
      expect(parse({'type': 'waist'}), isEmpty);
      expect(parse({'type': 'waist', 'value_cm': null}), isEmpty);
      expect(parse({'value_cm': 80}), isEmpty);
      expect(events, isEmpty);
    });

    test('wrong-typed fields are dropped without throwing and without an event',
        () {
      // Before Landing A `data['value_cm'] as num?` and `data['type'] as String?`
      // threw a TypeError on each of these.
      for (final bad in <Object>['82', true, <Object>[], <String, Object>{}]) {
        expect(
          () => parse({'type': 'waist', 'value_cm': bad}),
          returnsNormally,
          reason: 'value_cm $bad',
        );
        expect(parse({'type': 'waist', 'value_cm': bad}), isEmpty);
      }
      for (final bad in <Object>[5, true, <Object>[], 4.5]) {
        expect(
          () => parse({'type': bad, 'value_cm': 80}),
          returnsNormally,
          reason: 'type $bad',
        );
        expect(parse({'type': bad, 'value_cm': 80}), isEmpty);
      }
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
  });
}
