@Timeout(Duration(minutes: 2))
library;

// L2b Landing A (OI-297) - the WRITER TO READER contract of the SoT concept
// `body_measurement_value_bounds` (docs/sot_registry.yaml). Gate 9
// (scripts/check_writeservice_contracts.dart) asks for this file name for every
// concept that names its Hive prefix with the singular `key_prefix`.
//
// What it pins is the name-and-shape agreement between the one writer
// (HealthWriteService.logMeasurement, through measurementRecordWith) and the one
// reader (HealthReadService.measurementHistory / latestBySite) plus the coach
// context built from it: the writer stores a site under ITS TOKEN, the day under
// `date`, the stamp under `updated_at_ms`, and the reader and the coach read
// exactly those names. The bounds themselves (the predicate, the rounding, the
// chat parse, every rejection edge) are
// test/contracts/body_measurement_bounds_behavioral_test.dart; the reader's
// tie-breaks and dirty-data rows are
// test/contracts/body_measurement_readers_behavioral_test.dart.
//
// The clock is pinned (2026-10-10 11:30 IST): the reader hides future-dated
// records, so a fixture dated after the real "today" would flip with the day the
// file runs.
//
// Diagnose: docs/diagnoses/2026-10-11-measurement-values-unbounded-7c3e9a.md

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/constants/body_measurement_specs.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

import '../helpers/hive_test_setup.dart';

/// 2026-10-10 06:00Z is 11:30 IST on 2026-10-10: "today" is 2026-10-10.
final _now = DateTime.utc(2026, 10, 10, 6);
const _today = 'measurement_2026-10-10';

/// One in-range literal per site, none of them a bound.
const _mid = <String, double>{
  'chest': 98.0,
  'waist': 84.5,
  'hips': 96.0,
  'arms': 32.5,
};

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    setTestClockTo(_now);
    // An accepted write fans out a background sync pass and a rejected one posts
    // a telemetry event; there is no cloud here.
    SyncService.pausedForSimulation = true;
    ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
  });

  tearDown(() async {
    resetTestClock();
    ErrorTelemetry.debugOnLogEventForTests = null;
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  Future<WriteResult> write(String part, double cm) =>
      HealthWriteService.instance.logMeasurement(
        date: nowWall(),
        partName: part,
        valueCm: cm,
        source: WriteSource.aiCoach,
      );

  Map<dynamic, dynamic>? stored() =>
      HiveService.instance.healthBox.get(_today) as Map?;

  Map<String, dynamic> coach() => Map<String, dynamic>.from(
      AiCoachRepository.instance.buildAiContext()['body_measurements'] as Map);

  test('the fixture below covers exactly the registered sites', () {
    expect(_mid.keys.toSet(), kBodyMeasurementSites.toSet());
    expect(kBodyMeasurementSpecs.keys.toSet(), kBodyMeasurementSites.toSet());
    for (final e in _mid.entries) {
      final spec = kBodyMeasurementSpecs[e.key]!;
      expect(e.value > spec.minCm && e.value < spec.maxCm, isTrue,
          reason: '${e.key}: the literal must sit strictly inside its bounds');
    }
  });

  for (final site in kBodyMeasurementSites) {
    test('$site: the writer stores it under its token; the reader and the '
        'coach read that token back', () async {
      final value = _mid[site]!;
      final res = await write(site, value);
      expect(res.success, isTrue);

      final rec = stored()!;
      expect(rec['date'], '2026-10-10');
      expect(rec[site], value, reason: 'the field name IS the site token');
      expect(rec['updated_at_ms'], isA<int>());

      expect(HealthReadService.instance.latestBySite(), {
        site: (cm: value, date: '2026-10-10'),
      });
      expect(HealthReadService.instance.measurementHistory().single.sites, {
        site: value,
      });
      expect(coach(), {site: value});
    });
  }

  test('four sites written one after another share ONE day record; the '
      'reader and the coach return them in the registry order', () async {
    // Written in the reverse of the registry order on purpose.
    for (final site in kBodyMeasurementSites.reversed) {
      expect((await write(site, _mid[site]!)).success, isTrue);
    }
    expect(
      HiveService.instance.healthBox.keys
          .where((k) => k.toString().startsWith('measurement_'))
          .toList(),
      [_today],
    );
    expect(HealthReadService.instance.measurementHistory().single.sites, _mid);
    expect(
      jsonEncode(coach()),
      '{"chest":98.0,"waist":84.5,"hips":96.0,"arms":32.5}',
      reason: 'the key order is the registry order, whatever the write order',
    );
  });

  test('both bounds of every site go in and come back unchanged', () async {
    for (final site in kBodyMeasurementSites) {
      final spec = kBodyMeasurementSpecs[site]!;
      for (final cm in [spec.minCm, spec.maxCm]) {
        expect((await write(site, cm)).success, isTrue,
            reason: '$site $cm is a bound, so it is valid');
        expect(HealthReadService.instance.latestBySite()[site],
            (cm: cm, date: '2026-10-10'));
      }
    }
  });

  test('a value the writer rejects never reaches the reader or the coach, '
      'and a good value already there is left byte for byte', () async {
    const rejected = <double>[3000.0, 49.9, 200.1, -82.0, double.nan, double.infinity];
    for (final v in rejected) {
      expect((await write('waist', v)).success, isFalse, reason: 'waist $v');
    }
    expect(stored(), isNull, reason: 'a rejected write must not create the day');
    expect(HealthReadService.instance.latestBySite(), isEmpty);
    expect(coach(), isEmpty);

    expect((await write('waist', 82.0)).success, isTrue);
    final before = Map<dynamic, dynamic>.from(stored()!);
    for (final v in rejected) {
      expect((await write('waist', v)).success, isFalse, reason: 'waist $v');
    }
    expect(stored(), before);
    expect(HealthReadService.instance.latestBySite()['waist'],
        (cm: 82.0, date: '2026-10-10'));
    expect(coach(), {'waist': 82.0});
  });

  test('a record shaped like the restore and the pull leave it (the cloud row '
      'plus source, no updated_at_ms) is read by the same reader; the next day '
      "the writer's record wins by date", () async {
    await HiveService.instance.healthBox.put(
      'measurement_2026-10-09',
      <dynamic, dynamic>{
        'id': 'meas_1',
        'date': '2026-10-09',
        'created_at': '2026-10-09T08:00:00.000Z',
        'waist': 81.0,
        'source': 'restore',
      },
    );
    expect(HealthReadService.instance.latestBySite(), {
      'waist': (cm: 81.0, date: '2026-10-09'),
    });
    expect(coach(), {'waist': 81.0});

    expect((await write('waist', 80.5)).success, isTrue);
    expect(HealthReadService.instance.latestBySite(), {
      'waist': (cm: 80.5, date: '2026-10-10'),
    });
    expect(coach(), {'waist': 80.5});
  });
}
