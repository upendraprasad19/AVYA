@Timeout(Duration(minutes: 2))
library;

// L2b Landing A (OI-297) - BEHAVIOURAL, the READ tier. The records a person (or
// an older build, a restore, the Telegram bot) put in healthBox are read by
// HealthReadService.measurementHistory / latestBySite / latestBySiteOf, and the
// AI snapshot's `body_measurements` goes through them. The ENTRY tiers (the
// predicate, the writer, the chat parse) are
// test/contracts/body_measurement_bounds_behavioral_test.dart.
//
// The clock is pinned in setUp for the whole file (setTestClockTo, reset in
// tearDown): the reader hides future-dated records, so a fixture dated after the
// real "today" would flip with the day the file runs.
//
// The suite runs with TZ=Asia/Kolkata (CI pins it), where the device-local date
// and the IST date coincide. The instant whose UTC date differs from its IST
// date (the future-filter group) is what separates them on any other host, so a
// "today" built from the host-local clock is invisible here and red under
// TZ=UTC; that run was done by hand and is recorded in the diagnose-doc.
//
// Diagnose: docs/diagnoses/2026-10-11-measurement-values-unbounded-7c3e9a.md

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

import '../helpers/hive_test_setup.dart';

/// 2026-10-10 06:00Z is 11:30 IST on 2026-10-10: "today" is 2026-10-10.
final _now = DateTime.utc(2026, 10, 10, 6);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    setTestClockTo(_now);
  });

  tearDown(() async {
    resetTestClock();
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  /// Hive hands a record back as Map<dynamic, dynamic> once it has been read
  /// from disk, so the fixtures take that shape: a Map<String, ...> literal
  /// would hide a reader that narrows the type (the app would then see no
  /// record at all after a restart).
  Future<void> put(String key, Object? value) =>
      HiveService.instance.healthBox.put(
        key,
        value is Map ? Map<dynamic, dynamic>.from(value) : value,
      );

  /// A day record the way the writer, a restore or the bot would leave it.
  Future<void> day(
    String date,
    Map<String, Object?> body, {
    String? key,
  }) => put(key ?? 'measurement_$date', <String, Object?>{'date': date, ...body});

  List<MeasurementEntry> history() =>
      HealthReadService.instance.measurementHistory();

  List<String> dates() => [for (final e in history()) e.date];

  // ── measurementHistory ──────────────────────────────────────────────────

  group('measurementHistory', () {
    test('newest first, whatever order the records were written in', () async {
      await day('2026-10-03', {'waist': 84.0});
      await day('2026-10-09', {'waist': 82.0, 'chest': 100.0});
      await day('2026-10-01', {'waist': 85.0});
      expect(dates(), ['2026-10-09', '2026-10-03', '2026-10-01']);
      expect(history().first.sites, {'waist': 82.0, 'chest': 100.0});
      expect(
        history().first.sites.keys.toList(),
        ['chest', 'waist'],
        reason: "an entry's sites come in registry order, not the record's",
      );
    });

    test('reads only measurement_ keys that hold a map', () async {
      await put('weight_2026-10-05', {'date': '2026-10-05', 'weight_kg': 70.0});
      await put('measurements_2026-10-05', {'date': '2026-10-05', 'waist': 80.0});
      await put('old_measurement_2026-10-05', {'date': '2026-10-05', 'waist': 80.0});
      await put('measurement_2026-10-05', 'not a map');
      await put('measurement_2026-10-06', 42);
      await HiveService.instance.healthBox
          .put(7, {'date': '2026-10-07', 'waist': 80.0}); // a non-String key
      await day('2026-10-08', {'waist': 81.0});
      expect(dates(), ['2026-10-08']);
    });

    // The two lower sort levels are DEFENSIVE: every in-repo writer keys a
    // record by its own date, so an equal-date pair needs a foreign or corrupt
    // key. The fixtures are labelled F1/F2/F3 in the plan. A stable sort over
    // the ascending box keys leaves an unresolved tie in key-ascending order,
    // which is why no single fixture kills every mutant of the comparator.
    Future<double?> winnerWaist(
      Object? stampOnSmallerKey,
      Object? stampOnLargerKey, {
      String smallerKey = 'measurement_2026-10-05',
      String largerKey = 'measurement_2026-10-05b',
    }) async {
      await day('2026-10-05', {
        'waist': 80.0,
        'updated_at_ms': ?stampOnSmallerKey,
      }, key: smallerKey);
      await day('2026-10-05', {
        'waist': 81.0,
        'updated_at_ms': ?stampOnLargerKey,
      }, key: largerKey);
      return history().first.sites['waist'];
    }

    test('F1 tie on date: the greater updated_at_ms wins (on the LARGER key)',
        () async {
      expect(await winnerWaist(1000, 2000), 81.0);
    });

    test('F2 tie on date: the greater updated_at_ms wins (on the SMALLER key)',
        () async {
      expect(await winnerWaist(2000, 1000), 80.0);
    });

    test('F3a tie on date and on updated_at_ms (both absent, the restore '
        'shape): the larger key wins', () async {
      expect(await winnerWaist(null, null), 81.0);
    });

    test('F3b a String updated_at_ms counts as 0 (not parsed, no throw): the '
        'larger key wins against an absent stamp', () async {
      expect(await winnerWaist('5000', null), 81.0);
    });

    test('F3c a String updated_at_ms does not outrank a real number', () async {
      expect(await winnerWaist(1, '9999'), 80.0);
    });

    test('F2b a fractional updated_at_ms is a number too (the greater wins, on '
        'the SMALLER key)', () async {
      expect(await winnerWaist(2000.5, 1000.5), 80.0);
    });

    test('F3d tie on date and stamp with keys of EQUAL length: the larger key '
        'wins (the order is the key text, not its length)', () async {
      expect(
        await winnerWaist(
          null,
          null,
          smallerKey: 'measurement_x1',
          largerKey: 'measurement_x2',
        ),
        81.0,
      );
    });

    test('equal dates: both records are still read (no record is lost)', () async {
      await winnerWaist(1000, 2000);
      expect(history(), hasLength(2));
    });

    test('per site: an invalid newer value falls through to the older day',
        () async {
      await day('2026-10-09', {'waist': 81.0, 'chest': 3000.0});
      await day('2026-10-03', {'chest': 95.0});
      // the newest entry keeps only its valid site
      expect(history().first.sites, {'waist': 81.0});
      expect(history(), hasLength(2));
      final latest = HealthReadService.instance.latestBySite();
      expect(latest['waist'], (cm: 81.0, date: '2026-10-09'));
      expect(
        latest['chest'],
        (cm: 95.0, date: '2026-10-03'),
        reason: 'chest 3000 on the newest day is hidden, the older day shows',
      );
    });

    // (site, literal just under the floor, floor, ceiling, literal just over).
    // Literals on purpose: a table read from the spec follows a moved bound.
    const boundRows = <(String, double, double, double, double)>[
      ('chest', 59.9, 60, 200, 200.1),
      ('waist', 49.9, 50, 200, 200.1),
      ('hips', 59.9, 60, 200, 200.1),
      ('arms', 19.9, 20, 70, 70.1),
    ];

    test('every site: a value just outside either bound is dropped', () async {
      var n = 0;
      for (final r in boundRows) {
        await day('2026-09-0${++n}', {r.$1: r.$2});
        await day('2026-09-0${++n}', {r.$1: r.$5});
      }
      expect(history(), isEmpty);
    });

    test('every site: the bounds themselves are kept', () async {
      var n = 0;
      for (final r in boundRows) {
        await day('2026-09-0${++n}', {r.$1: r.$3}); // the floor
        await day('2026-09-0${++n}', {r.$1: r.$4}); // the ceiling
      }
      // dates 09-01 .. 09-08, newest first
      expect([for (final e in history()) e.sites], [
        {'arms': 70.0},
        {'arms': 20.0},
        {'hips': 200.0},
        {'hips': 60.0},
        {'waist': 200.0},
        {'waist': 50.0},
        {'chest': 200.0},
        {'chest': 60.0},
      ]);
    });

    test('a value an older build stored unrounded is judged, and shown, as the '
        'writer would have stored it', () async {
      // The writer rounds to 0.1 cm and validates the ROUNDED value, so it
      // accepts 49.96 (stored 50.0). The reader accepts the same inputs.
      await day('2026-10-09', {
        'chest': 59.97,
        'waist': 49.96,
        'hips': 200.04,
        'arms': 70.04,
      });
      // These round to 0.1 on the far side of each edge: dropped, as the
      // writer would refuse them.
      await day('2026-10-08', {
        'chest': 59.94,
        'waist': 49.94,
        'hips': 200.06,
        'arms': 70.06,
      });
      await day('2026-10-07', {'waist': 82.34});
      expect(dates(), ['2026-10-09', '2026-10-07']);
      expect(history().first.sites, {
        'chest': 60.0,
        'waist': 50.0,
        'hips': 200.0,
        'arms': 70.0,
      });
      expect(history()[1].sites, {'waist': 82.3});
    });

    test('a record read back from disk after a restart is read the same '
        '(Hive decodes it as Map<dynamic, dynamic>)', () async {
      SyncService.pausedForSimulation = true;
      final res = await HealthWriteService.instance.logMeasurement(
        date: nowWall(),
        partName: 'waist',
        valueCm: 82.34,
        source: WriteSource.aiCoach,
      );
      expect(res.success, isTrue);
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(kTestUserId);
      final raw = HiveService.instance.healthBox.get('measurement_2026-10-10');
      expect(raw, isA<Map>());
      expect(
        raw is Map<String, dynamic>,
        isFalse,
        reason: 'the point of this test: a map from disk is not Map<String, _>',
      );
      expect(HealthReadService.instance.latestBySite(), {
        'waist': (cm: 82.3, date: '2026-10-10'),
      });
    });

    test('a record with no valid site is dropped', () async {
      await day('2026-10-09', {
        'chest': null,
        'waist': null,
        'hips': null,
        'arms': null,
      });
      await day('2026-10-08', {'thigh': 55.0}); // not a registered site
      await day('2026-10-07', {'waist': 0.0});
      await day('2026-10-06', {'waist': -5.0});
      await day('2026-10-05', {'waist': 49.9, 'arms': 19.9});
      await day('2026-10-04', {'waist': 80.0});
      expect(dates(), ['2026-10-04']);
    });

    test('NaN and Infinity stored by a direct put are dropped per site',
        () async {
      await day('2026-10-09', {'waist': double.nan, 'chest': 95.0});
      await day('2026-10-08', {'waist': double.infinity, 'hips': 97.0});
      await day('2026-10-07', {'arms': double.negativeInfinity});
      expect(history().first.sites, {'chest': 95.0});
      expect(history()[1].sites, {'hips': 97.0});
      expect(history(), hasLength(2));
      final latest = HealthReadService.instance.latestBySite();
      expect(latest.containsKey('waist'), isFalse);
      expect(latest.containsKey('arms'), isFalse);
    });

    test('a numeric-String site, a non-String date and a missing date are '
        'skipped without throwing', () async {
      await day('2026-10-09', {'hips': '97', 'chest': 95.0});
      await put('measurement_2026-10-08', {'date': 20261008, 'waist': 81.0});
      await put('measurement_2026-10-07', {'date': null, 'waist': 81.0});
      await put('measurement_2026-10-06', {'waist': 81.0}); // no date at all
      await put('measurement_2026-10-05', {'date': true, 'waist': 81.0});
      expect(() => history(), returnsNormally);
      expect(dates(), ['2026-10-09']);
      expect(history().single.sites, {'chest': 95.0});
    });

    test('an integer value is read as a double', () async {
      await day('2026-10-09', {'waist': 82, 'arms': 33});
      expect(history().single.sites, {'waist': 82.0, 'arms': 33.0});
      expect(history().single.sites['waist'], isA<double>());
    });

    // The first group matches the YYYY-MM-DD shape, so only the calendar
    // round-trip can drop it (Dart normalises 2026-13-45 and 2026-02-30 instead
    // of failing, and so does DateTime.tryParse). Two of its rows, 2026-13-45
    // and 2026-10-32, are also later than the pinned "today" and the future
    // filter would drop them too; the other five belong to the round-trip
    // alone. The second group fails the shape (tryParse accepts 20261001 and a
    // timestamp, so a tryParse-based round-trip alone would absorb the shape
    // check).
    test('an impossible calendar day is dropped (round-trip)', () async {
      for (final d in [
        '2026-13-45',
        '2026-02-30',
        '2026-02-29', // 2026 is not a leap year
        '2026-04-31',
        '2026-00-10',
        '2026-10-00',
        '2026-10-32',
      ]) {
        await put('measurement_$d', {'date': d, 'waist': 80.0});
      }
      expect(() => history(), returnsNormally);
      expect(history(), isEmpty);
    });

    test('a real leap day is kept', () async {
      await day('2024-02-29', {'waist': 80.0});
      expect(dates(), ['2024-02-29']);
    });

    test('a date that is not exactly YYYY-MM-DD is dropped (shape)', () async {
      final arabicIndic = String.fromCharCodes([
        0x0662, 0x0660, 0x0662, 0x0666, // 2026
        0x2d,
        0x0661, 0x0660, // 10
        0x2d,
        0x0660, 0x0665, // 05
      ]);
      var n = 0;
      for (final d in [
        '20261001',
        '2026-10-01T10:00:00',
        '2026-10-5',
        '2026-1-05',
        ' 2026-10-05',
        '2026-10-05 ',
        '2026-10-05${String.fromCharCode(0x0a)}',
        '26-10-05',
        arabicIndic,
        '',
        '2025/10/05', // another separator: the shape wants a hyphen
        '2025.10.05',
        '2026-10-050', // an extra digit
        '2026-10-05x', // trailing text
        'x2026-10-05', // leading text
        '2026-10-052026-10-05', // a doubled date: the tail is a date, the head is read too
      ]) {
        await put('measurement_row${n++}', {'date': d, 'waist': 80.0});
      }
      expect(() => history(), returnsNormally);
      expect(history(), isEmpty);
    });

    group('a future-dated record is hidden until its day', () {
      Future<void> seed() => day('2026-10-06', {'waist': 80.0});

      test('the day before: hidden', () async {
        await seed();
        setTestClockTo(DateTime.utc(2026, 10, 5, 10)); // 15:30 IST on 10-05
        expect(history(), isEmpty);
      });

      test('the same IST day: visible (the boundary is inclusive)', () async {
        await seed();
        setTestClockTo(DateTime.utc(2026, 10, 6, 10));
        expect(dates(), ['2026-10-06']);
      });

      test('an instant whose UTC date differs from its IST date: the IST day '
          'decides', () async {
        await seed();
        // 2026-10-05T20:00Z is 01:30 IST on 2026-10-06: already the record's day.
        setTestClockTo(DateTime.utc(2026, 10, 5, 20));
        expect(dates(), ['2026-10-06']);
      });

      test('a far-future record and a day-after record are hidden', () async {
        await day('2099-01-01', {'waist': 99.0});
        await day('2026-10-11', {'waist': 98.0}); // clock is 2026-10-10
        await day('2026-10-10', {'waist': 81.0});
        expect(dates(), ['2026-10-10']);
      });

      test('a future record does not shadow the real latest value', () async {
        await day('2026-10-09', {'waist': 81.0});
        await day('2027-01-01', {'waist': 99.0}); // a wrong device clock stored it
        expect(
          HealthReadService.instance.latestBySite()['waist'],
          (cm: 81.0, date: '2026-10-09'),
        );
      });
    });

    test('the real writer and the reader agree (writer to reader)', () async {
      SyncService.pausedForSimulation = true;
      final res = await HealthWriteService.instance.logMeasurement(
        date: nowWall(),
        partName: ' Chest',
        valueCm: 95.04,
        source: WriteSource.aiCoach,
      );
      expect(res.success, isTrue);
      expect(HealthReadService.instance.latestBySite(), {
        'chest': (cm: 95.0, date: '2026-10-10'),
      });
      expect(history().single.sites, {'chest': 95.0});
    });
  });

  // ── latestBySite / latestBySiteOf ───────────────────────────────────────

  group('latestBySiteOf (pure; input newest first)', () {
    const newest = MeasurementEntry(date: '2026-10-09', sites: {'waist': 81.0});
    const middle = MeasurementEntry(
      date: '2026-10-03',
      // deliberately not in registry order
      sites: {'arms': 33.0, 'waist': 79.0, 'chest': 95.0},
    );
    const oldest = MeasurementEntry(
      date: '2026-10-01',
      sites: {'hips': 97.0, 'chest': 90.0},
    );

    test('the newest entry holding a site wins that site', () {
      final out = HealthReadService.latestBySiteOf([newest, middle, oldest]);
      expect(out, {
        'chest': (cm: 95.0, date: '2026-10-03'),
        'waist': (cm: 81.0, date: '2026-10-09'),
        'hips': (cm: 97.0, date: '2026-10-01'),
        'arms': (cm: 33.0, date: '2026-10-03'),
      });
    });

    test("the key order is the registry's, not the entries'", () {
      final out = HealthReadService.latestBySiteOf([newest, middle, oldest]);
      expect(out.keys.toList(), kBodyMeasurementSites);
      final partial = HealthReadService.latestBySiteOf([middle]);
      expect(partial.keys.toList(), ['chest', 'waist', 'arms']);
    });

    test('a site never measured is absent; no history is an empty map', () {
      expect(HealthReadService.latestBySiteOf(const []), isEmpty);
      expect(
        HealthReadService.latestBySiteOf([newest]).keys.toList(),
        ['waist'],
      );
    });

    test('oldest-first input is refused in a debug build (the newest-first '
        'contract is asserted)', () {
      expect(
        () => HealthReadService.latestBySiteOf([oldest, middle, newest]),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => HealthReadService.latestBySiteOf([newest, oldest, middle]),
        throwsA(isA<AssertionError>()),
        reason: 'one out-of-order pair is enough',
      );
    });

    test('two entries with the same date are in order', () {
      const a = MeasurementEntry(date: '2026-10-05', sites: {'waist': 81.0});
      const b = MeasurementEntry(date: '2026-10-05', sites: {'waist': 80.0});
      expect(
        HealthReadService.latestBySiteOf([a, b]),
        {'waist': (cm: 81.0, date: '2026-10-05')},
      );
    });
  });

  // ── firstBySiteOf (L2b Landing C) ───────────────────────────────────────

  group('firstBySiteOf (pure; input newest first)', () {
    // `waist` is held by all three days, `chest` by the middle and the oldest,
    // `hips` by the oldest only, `arms` by the middle only: the OLDEST holder
    // of a site is not always the oldest entry, and not always the newest.
    const newest = MeasurementEntry(date: '2026-10-09', sites: {'waist': 81.0});
    const middle = MeasurementEntry(
      date: '2026-10-03',
      // deliberately not in registry order
      sites: {'arms': 33.0, 'waist': 79.0, 'chest': 95.0},
    );
    const oldest = MeasurementEntry(
      date: '2026-10-01',
      sites: {'waist': 80.0, 'hips': 97.0, 'chest': 90.0},
    );

    test('the OLDEST entry holding a site wins that site', () {
      final out = HealthReadService.firstBySiteOf([newest, middle, oldest]);
      expect(out, {
        'chest': (cm: 90.0, date: '2026-10-01'),
        'waist': (cm: 80.0, date: '2026-10-01'),
        'hips': (cm: 97.0, date: '2026-10-01'),
        'arms': (cm: 33.0, date: '2026-10-03'),
      });
    });

    test('a site absent from the oldest entry comes from the next holder', () {
      const oldestWithoutWaist = MeasurementEntry(
        date: '2026-10-01',
        sites: {'hips': 97.0},
      );
      final out = HealthReadService.firstBySiteOf([
        newest,
        middle,
        oldestWithoutWaist,
      ]);
      expect(
        out['waist'],
        (cm: 79.0, date: '2026-10-03'),
        reason: 'not the newest (81.0) and not skipped past the middle',
      );
      expect(out['hips'], (cm: 97.0, date: '2026-10-01'));
    });

    test('a single entry is both the first and the latest', () {
      expect(HealthReadService.firstBySiteOf([newest]), {
        'waist': (cm: 81.0, date: '2026-10-09'),
      });
    });

    test("the key order is the registry's, not the entries'", () {
      final out = HealthReadService.firstBySiteOf([newest, middle, oldest]);
      expect(out.keys.toList(), kBodyMeasurementSites);
      final partial = HealthReadService.firstBySiteOf([middle]);
      expect(partial.keys.toList(), ['chest', 'waist', 'arms']);
    });

    test('a site never measured is absent; no history is an empty map', () {
      expect(HealthReadService.firstBySiteOf(const []), isEmpty);
      expect(HealthReadService.firstBySiteOf([newest]).keys.toList(), [
        'waist',
      ]);
    });

    test('oldest-first input is refused in a debug build (the newest-first '
        'contract is asserted)', () {
      expect(
        () => HealthReadService.firstBySiteOf([oldest, middle, newest]),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => HealthReadService.firstBySiteOf([newest, oldest, middle]),
        throwsA(isA<AssertionError>()),
        reason: 'one out-of-order pair is enough',
      );
      // The two fixtures above also break a LATER pair, so a check that skipped
      // the first pair would still catch them. These break the FIRST pair only.
      expect(
        () => HealthReadService.firstBySiteOf([oldest, middle]),
        throwsA(isA<AssertionError>()),
        reason: 'two entries: the only pair is the first',
      );
      expect(
        () => HealthReadService.firstBySiteOf([oldest, newest, newest]),
        throwsA(isA<AssertionError>()),
        reason: 'the later pair (equal dates) is fine; the first is not',
      );
    });

    test(
      'two entries with the same date: the LAST in list order is the first',
      () {
        const a = MeasurementEntry(date: '2026-10-05', sites: {'waist': 81.0});
        const b = MeasurementEntry(date: '2026-10-05', sites: {'waist': 80.0});
        expect(HealthReadService.firstBySiteOf([a, b]), {
          'waist': (cm: 80.0, date: '2026-10-05'),
        });
      },
    );

    test('first and latest agree when only one entry holds the site', () {
      final list = [newest, middle, oldest];
      final first = HealthReadService.firstBySiteOf(list);
      final latest = HealthReadService.latestBySiteOf(list);
      expect(
        first['arms'],
        latest['arms'],
        reason: 'arms is held by the middle entry alone',
      );
      expect(first['waist'], isNot(latest['waist']));
    });
  });

  // ── the AI snapshot's body_measurements ─────────────────────────────────

  group('AI snapshot body_measurements', () {
    Map<String, dynamic> bodyMeasurements() {
      final ctx = AiCoachRepository.instance.buildAiContext();
      return Map<String, dynamic>.from(ctx['body_measurements'] as Map);
    }

    test('no records: an empty map', () {
      expect(bodyMeasurements(), isEmpty);
    });

    test('GOLDEN clean data: the same keys, values and key order the previous '
        'reader produced', () async {
      // The literal below is the OUTPUT OF THE PREVIOUS _getBodyMeasurements
      // loop on exactly this fixture (run before the edit; recorded in the
      // diagnose-doc). The oldest record holds all four sites, so the previous
      // loop's key order (box discovery order) was chest, waist, hips, arms.
      await day('2026-09-20', {
        'chest': 98.0,
        'waist': 84.5,
        'hips': 96.0,
        'arms': 32.5,
      });
      await day('2026-10-01', {'waist': 82.0, 'hips': 97.0});
      await day('2026-10-04', {'chest': 100.0, 'arms': 33.0});
      final m = bodyMeasurements();
      expect(m, {'chest': 100.0, 'waist': 82.0, 'hips': 97.0, 'arms': 33.0});
      expect(
        jsonEncode(m),
        '{"chest":100.0,"waist":82.0,"hips":97.0,"arms":33.0}',
        reason: 'the key order is part of what the coach receives',
      );
    });

    test('DIRTY data: NaN, an absurd value, a numeric-String site and a '
        'non-String date neither throw nor reach the coach', () async {
      await day('2026-10-01', {
        'chest': 96.0,
        'waist': 83.0,
        'hips': 98.0,
        'arms': 34.0,
      });
      await day('2026-10-03', {
        'chest': 3000.0,
        'waist': double.nan,
        'hips': '97',
        'arms': 33.5,
      });
      await put('measurement_2026-10-04', {'date': 20261004, 'waist': 81.0});
      late Map<String, dynamic> m;
      expect(() => m = bodyMeasurements(), returnsNormally);
      expect(m, {'chest': 96.0, 'waist': 83.0, 'hips': 98.0, 'arms': 33.5});
      // The previous loop put the NaN into the snapshot, where the size trim's
      // jsonEncode threw: every chat context build and every snapshot push died.
      expect(
        () => jsonEncode(AiCoachRepository.instance.buildAiContext()),
        returnsNormally,
      );
    });

    test('a future-dated record never reaches the coach', () async {
      await day('2026-10-09', {'waist': 81.0});
      await day('2026-12-25', {'waist': 99.0});
      expect(bodyMeasurements(), {'waist': 81.0});
    });
  });
}
