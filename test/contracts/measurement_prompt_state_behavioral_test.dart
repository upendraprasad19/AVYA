@Timeout(Duration(minutes: 3))
library;

// L2b Landing B (B3) - BEHAVIOURAL. Which body-measurements prompt the Home
// banner and the Weight-sheet link show: the PURE rule (measurementPromptFor),
// the strict date parser and its parity with the reader's, and the providers
// that feed it (history, profile stamp, the two dismissal keys, the flag, the
// anonymous token).
//
// Every day count is a LITERAL, and every `none` row has exactly ONE clause
// that makes it `none` (a row with two reasons kills nothing). The constants
// are pinned by value too, so a mutation of one constant alone reddens a row.
//
// Plan: docs/plans/coach-measurement-sheet-ui.md (B3, section 4)

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';

import '../helpers/dart_source_slice.dart';
import '../helpers/hive_test_setup.dart';

const _otherUser = '7a1b2c3d-aaaa-bbbb-cccc-eeeeeeeeeeee';
const _dismissKey = 'body_measurement_prompt_dismissed_at';
const _skipKey = 'body_measurement_prompt_baseline_skipped_at';

/// 2026-10-12 06:00Z is 11:30 IST on 2026-10-12.
final _now = DateTime.utc(2026, 10, 12, 6);

MeasurementPrompt p({
  bool flagOn = true,
  bool historyKnown = true,
  String today = '2026-10-12',
  String? onboarded = '2026-09-01',
  String? lastEntry,
  String? dismissed,
  String? skipped,
}) =>
    measurementPromptFor(
      flagOn: flagOn,
      historyKnown: historyKnown,
      todayIst: today,
      onboardedIst: onboarded,
      lastEntryIst: lastEntry,
      dismissedIst: dismissed,
      baselineSkippedIst: skipped,
    );

void main() {
  // ── the pure rule ─────────────────────────────────────────────────────────

  group('measurementPromptFor - constants', () {
    test('the four constants have their stated values (literals)', () {
      expect(kMeasurementDueIntervalDays, 28);
      expect(kMeasurementBaselineSnoozeDays, 28);
      expect(kMeasurementDismissSnoozeDays, 7);
      expect(kMeasurementBaselineFromTenureDays, 7);
    });
  });

  group('measurementPromptFor - gates', () {
    test('the flag off is none (everything else would give due)', () {
      expect(p(lastEntry: '2026-09-01', flagOn: false), MeasurementPrompt.none);
      expect(p(lastEntry: '2026-09-01'), MeasurementPrompt.due);
    });

    test('an unknown history is none (everything else would give due), so a '
        'failed read never looks like "never measured"', () {
      expect(p(lastEntry: '2026-09-01', historyKnown: false),
          MeasurementPrompt.none);
      expect(p(historyKnown: false), MeasurementPrompt.none,
          reason: 'baseline-eligible, history unknown');
    });

    test('an unparsable today is none', () {
      for (final bad in ['', 'today', '2026-13-45', '2026-02-30', '12/10/2026']) {
        expect(p(today: bad, lastEntry: '2026-09-01'), MeasurementPrompt.none,
            reason: bad);
      }
    });
  });

  group('measurementPromptFor - measured (due)', () {
    test('27 days since the last entry is none, 28 is due, 29 is due', () {
      expect(p(lastEntry: '2026-09-15'), MeasurementPrompt.none); // 27
      expect(p(lastEntry: '2026-09-14'), MeasurementPrompt.due); // 28
      expect(p(lastEntry: '2026-09-13'), MeasurementPrompt.due); // 29
    });

    test('an entry today or yesterday is none', () {
      expect(p(lastEntry: '2026-10-12'), MeasurementPrompt.none);
      expect(p(lastEntry: '2026-10-11'), MeasurementPrompt.none);
    });

    test('due needs no tenure and no onboarding stamp', () {
      expect(p(lastEntry: '2026-09-01', onboarded: null), MeasurementPrompt.due);
      expect(p(lastEntry: '2026-09-01', onboarded: '2026-10-11'),
          MeasurementPrompt.due);
    });

    test('the baseline snooze does not apply to a measured user', () {
      expect(p(lastEntry: '2026-09-01', skipped: '2026-10-09'),
          MeasurementPrompt.due);
    });

    test('month, year and leap-day boundaries count real days', () {
      // 2026-02-01 -> 2026-03-01 is 28 days.
      expect(p(today: '2026-03-01', lastEntry: '2026-02-01'),
          MeasurementPrompt.due);
      expect(p(today: '2026-03-01', lastEntry: '2026-02-02'),
          MeasurementPrompt.none);
      // 2028 is a leap year: 2028-02-01 -> 2028-03-01 is 29 days.
      expect(p(today: '2028-03-01', lastEntry: '2028-02-02'),
          MeasurementPrompt.due); // 28
      expect(p(today: '2028-03-01', lastEntry: '2028-02-03'),
          MeasurementPrompt.none); // 27
      // Across a year end.
      expect(p(today: '2027-01-10', lastEntry: '2026-12-13'),
          MeasurementPrompt.due); // 28
      expect(p(today: '2027-01-10', lastEntry: '2026-12-14'),
          MeasurementPrompt.none); // 27
    });
  });

  group('measurementPromptFor - never measured (baseline)', () {
    test('tenure 6 days is none, 7 is baseline, 8 is baseline', () {
      expect(p(onboarded: '2026-10-06'), MeasurementPrompt.none); // 6
      expect(p(onboarded: '2026-10-05'), MeasurementPrompt.baseline); // 7
      expect(p(onboarded: '2026-10-04'), MeasurementPrompt.baseline); // 8
    });

    test('no onboarding stamp is none (NO-STAMP-NO-BASELINE)', () {
      expect(p(onboarded: null), MeasurementPrompt.none);
    });

    test('a skipped baseline 27 days ago is none, 28 days ago is baseline',
        () {
      expect(p(skipped: '2026-09-15'), MeasurementPrompt.none); // 27
      expect(p(skipped: '2026-09-14'), MeasurementPrompt.baseline); // 28
    });
  });

  group('measurementPromptFor - dismissal', () {
    test('dismissed 6 days ago is none, 7 days ago lets the prompt through '
        '(due)', () {
      expect(p(lastEntry: '2026-09-01', dismissed: '2026-10-06'),
          MeasurementPrompt.none); // 6
      expect(p(lastEntry: '2026-09-01', dismissed: '2026-10-05'),
          MeasurementPrompt.due); // 7
    });

    test('dismissal silences the baseline prompt as well (one clause)', () {
      expect(p(dismissed: '2026-10-09'), MeasurementPrompt.none);
      expect(p(dismissed: '2026-10-05'), MeasurementPrompt.baseline);
    });

    test('a dismissal and an old baseline skip: the dismissal alone silences',
        () {
      expect(p(dismissed: '2026-10-09', skipped: '2026-08-01'),
          MeasurementPrompt.none);
    });
  });

  group('measurementPromptFor - dates from the future are absent', () {
    test('a future dismissal is ignored', () {
      expect(p(lastEntry: '2026-09-01', dismissed: '2026-10-20'),
          MeasurementPrompt.due);
    });

    test('a future baseline skip is ignored', () {
      expect(p(skipped: '2026-10-20'), MeasurementPrompt.baseline);
    });

    test('a future last entry counts as never measured', () {
      expect(p(lastEntry: '2026-10-20'), MeasurementPrompt.baseline);
      expect(p(lastEntry: '2026-10-20', onboarded: '2026-10-11'),
          MeasurementPrompt.none);
    });

    test('a future onboarding date is no tenure', () {
      expect(p(onboarded: '2026-10-20'), MeasurementPrompt.none);
    });

    // Tomorrow and a year-plus ahead, for each of the three stored dates: the
    // boundary is "after today", not "more than a day after today".
    test('tomorrow and 400 days ahead are future for every stored date', () {
      for (final future in ['2026-10-13', '2027-11-16']) {
        expect(p(lastEntry: '2026-09-01', dismissed: future),
            MeasurementPrompt.due,
            reason: 'dismissed $future');
        expect(p(skipped: future), MeasurementPrompt.baseline,
            reason: 'skipped $future');
        expect(p(lastEntry: future), MeasurementPrompt.baseline,
            reason: 'lastEntry $future counts as never measured');
        expect(p(onboarded: future), MeasurementPrompt.none,
            reason: 'onboarded $future');
      }
      // Today itself is NOT future.
      expect(p(lastEntry: '2026-09-01', dismissed: '2026-10-12'),
          MeasurementPrompt.none);
      expect(p(skipped: '2026-10-12'), MeasurementPrompt.none);
    });
  });

  group('parseIstKeyStrict', () {
    test('accepts a real day and returns a UTC date', () {
      final d = parseIstKeyStrict('2026-10-05')!;
      expect(d.isUtc, isTrue);
      expect((d.year, d.month, d.day), (2026, 10, 5));
      expect(parseIstKeyStrict('2028-02-29'), isNotNull);
    });

    test('rejects every impossible or misshapen value', () {
      final arabicDigit = String.fromCharCode(0x0662); // ARABIC-INDIC DIGIT TWO
      for (final bad in <Object?>[
        null,
        42,
        true,
        '',
        '2026-02-30',
        '2026-13-01',
        '2026-00-10',
        '2026-10-00',
        '2026-10-32',
        '2027-02-29',
        '2026-1-5',
        '2026-10-5',
        '26-10-05',
        ' 2026-10-05',
        '2026-10-05 ',
        '2026-10-05T00:00:00Z',
        '2026/10/05',
        '20261001',
        '2026-10-05\n',
        '\n2026-10-05',
        '${arabicDigit}026-10-05',
        DateTime.utc(2026, 10, 5),
        <String>['2026-10-05'],
      ]) {
        expect(parseIstKeyStrict(bad), isNull, reason: '$bad');
      }
    });
  });

  group('the rules file does its day arithmetic on UTC dates only', () {
    test('DateTime.utc( is used; DateTime( and .toLocal() are not', () {
      final src = stripDartComments(File(
        'lib/features/profile/services/measurement_prompt_rules.dart',
      ).readAsStringSync());
      expect(src.contains('DateTime.utc('), isTrue);
      expect(RegExp(r'DateTime\(').hasMatch(src), isFalse);
      expect(src.contains('.toLocal()'), isFalse);
      expect(src.contains('padLeft'), isFalse);
    });
  });

  // ── providers ─────────────────────────────────────────────────────────────

  group('providers', () {
    late Directory tempDir;
    late List<({String op, String? message})> events;

    setUp(() async {
      tempDir = await setUpHiveForTests();
      setTestClockTo(_now);
      events = [];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add((op: op, message: message));
      await HiveService.instance.configBox.put('enable_body_measurements', true);
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      resetTestClock();
      await tearDownHiveForTests(tempDir);
    });

    ProviderContainer container({String token = kTestUserId}) {
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(token),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> putEntry(String date, {double waist = 80.0}) =>
        HiveService.instance.healthBox.put('measurement_$date', {
          'id': 'meas_$date',
          'date': date,
          'waist': waist,
          'created_at': '${date}T01:00:00.000Z',
          'updated_at_ms': 1,
        });

    Future<void> putProfile(Object? onboardingStamp, {bool omit = false}) =>
        HiveService.instance.userBox.put('profile', <String, dynamic>{
          'full_name': 'Test',
          if (!omit) 'onboarding_completed_at': onboardingStamp,
        });

    /// Reads once with the provider kept alive (an auto-disposed read would
    /// rebuild between calls).
    MeasurementPrompt read(ProviderContainer c) {
      final sub = c.listen(measurementPromptProvider, (_, _) {});
      addTearDown(sub.close);
      return c.read(measurementPromptProvider);
    }

    test('flag ON, last entry 28 days old -> due; 27 days old -> none',
        () async {
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-14');
      expect(read(container()), MeasurementPrompt.due);

      await HiveService.instance.healthBox.delete('measurement_2026-09-14');
      await putEntry('2026-09-15');
      expect(read(container()), MeasurementPrompt.none);
    });

    test('the prompt follows the NEWEST entry: an old entry beside a recent '
        'one is not due', () async {
      await putProfile('2026-07-01T00:00:00Z');
      await putEntry('2026-08-01');
      await putEntry('2026-09-15'); // 27 days: not due
      final c = container();
      expect(read(c), MeasurementPrompt.none);
      expect(c.read(bodyMeasurementsProvider).lastEntryDate, '2026-09-15');
      await HiveService.instance.healthBox.delete('measurement_2026-09-15');
      await putEntry('2026-09-14'); // 28 days: due
      expect(read(container()), MeasurementPrompt.due);
    });

    test('flag OFF -> none, even for a due history', () async {
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-01');
      await HiveService.instance.configBox.put('enable_body_measurements', false);
      expect(read(container()), MeasurementPrompt.none);
    });

    test('the onboarding stamp is read in IST: 2026-09-30T19:00:00Z is '
        '2026-10-01 in IST, tenure 6 on 2026-10-07 and 7 on 2026-10-08',
        () async {
      await putProfile('2026-09-30T19:00:00Z');
      setTestClockTo(DateTime.utc(2026, 10, 7, 6)); // IST 2026-10-07
      expect(read(container()), MeasurementPrompt.none,
          reason: 'its first ten characters would make this tenure 7');
      setTestClockTo(DateTime.utc(2026, 10, 8, 6)); // IST 2026-10-08
      expect(read(container()), MeasurementPrompt.baseline);
    });

    test('a missing or non-String onboarding stamp: due still shows, baseline '
        'does not, and nothing throws', () async {
      await putEntry('2026-09-01');
      for (final bad in <Object?>[null, 5, true, 'not a date']) {
        await putProfile(bad);
        expect(read(container()), MeasurementPrompt.due, reason: '$bad');
      }
      await putProfile(null, omit: true);
      expect(read(container()), MeasurementPrompt.due);

      await HiveService.instance.healthBox.delete('measurement_2026-09-01');
      for (final bad in <Object?>[null, 5, true, 'not a date']) {
        await putProfile(bad);
        expect(read(container()), MeasurementPrompt.none, reason: '$bad');
      }
      expect(events, isEmpty, reason: 'a bad stamp is data, not a defect');
    });

    test('dismiss() silences the prompt now, writes today into the USER box '
        'only, and a second user is not silenced', () async {
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-01');
      final c = container();
      expect(read(c), MeasurementPrompt.due);

      await c.read(measurementPromptProvider.notifier).dismiss();
      expect(c.read(measurementPromptProvider), MeasurementPrompt.none);
      expect(HiveService.instance.userBox.get(_dismissKey), '2026-10-12');
      expect(HiveService.instance.configBox.containsKey(_dismissKey), isFalse);

      // The second user on the same device: their own box, their own history.
      await HiveUserSession.openForUser(_otherUser);
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-01');
      final c2 = container(token: _otherUser);
      expect(read(c2), MeasurementPrompt.due,
          reason: "the first user's dismissal is not theirs");
      expect(HiveService.instance.userBox.containsKey(_dismissKey), isFalse);
    });

    test('skipBaseline() silences a baseline prompt and writes only its own '
        'key', () async {
      await putProfile('2026-08-01T00:00:00Z');
      final c = container();
      expect(read(c), MeasurementPrompt.baseline);
      await c.read(measurementPromptProvider.notifier).skipBaseline();
      expect(c.read(measurementPromptProvider), MeasurementPrompt.none);
      expect(HiveService.instance.userBox.get(_skipKey), '2026-10-12');
      expect(HiveService.instance.userBox.containsKey(_dismissKey), isFalse);
    });

    test('with no session owner the X writes nothing (not into configBox) '
        'and does not throw', () async {
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-01');
      final c = container();
      final n = c.read(measurementPromptProvider.notifier);
      await HiveUserSession.closeAll();
      expect(HiveUserSession.currentOwnerFullId, isNull);
      await n.dismiss();
      await n.skipBaseline();
      expect(HiveService.instance.configBox.containsKey(_dismissKey), isFalse);
      expect(HiveService.instance.configBox.containsKey(_skipKey), isFalse);
    });

    test('a closed history box: loaded false, the prompt is none, ONE '
        'measurement_history_read_failed event with stage=history', () async {
      await putProfile('2026-08-01T00:00:00Z');
      await Hive.box(HiveUserSession.namespacedBoxName(
              HiveService.healthBoxName, kTestUserId))
          .close();
      final c = container();
      final s = c.read(bodyMeasurementsProvider);
      expect(s.loaded, isFalse);
      expect(s.latest, isEmpty);
      expect(read(c), MeasurementPrompt.none);
      await Future<void>.delayed(Duration.zero);
      final failed =
          events.where((e) => e.op == 'measurement_history_read_failed');
      expect(failed, hasLength(1));
      expect(failed.single.message, 'stage=history');
      expect(events.where((e) => e.op == 'measurement_prompt_build_failed'),
          isEmpty);
    });

    test('a closed user box: the prompt is none and ONE '
        'measurement_prompt_build_failed event with stage=prompt', () async {
      await putEntry('2026-09-01');
      await Hive.box(HiveUserSession.namespacedBoxName(
              HiveService.userBoxName, kTestUserId))
          .close();
      final c = container();
      expect(read(c), MeasurementPrompt.none);
      await Future<void>.delayed(Duration.zero);
      final failed =
          events.where((e) => e.op == 'measurement_prompt_build_failed');
      expect(failed, hasLength(1));
      expect(failed.single.message, 'stage=prompt');
    });

    test('a non-String stored dismissal or skip is data, not a defect: it is '
        'ignored and nothing is reported', () async {
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-01');
      await HiveService.instance.userBox.put(_dismissKey, 5);
      await HiveService.instance.userBox.put(_skipKey, true);
      expect(read(container()), MeasurementPrompt.due,
          reason: 'a number under the dismissal key silences nothing');
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('flipping the flag under a built prompt rebuilds it (the flag is '
        'WATCHED, not read once)', () async {
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-01');
      final c = container();
      expect(read(c), MeasurementPrompt.due);
      await HiveService.instance.configBox
          .put('enable_body_measurements', false);
      c.invalidate(measurementsEnabledProvider); // what the dev toggle does
      expect(c.read(measurementPromptProvider), MeasurementPrompt.none);
      await HiveService.instance.configBox
          .put('enable_body_measurements', true);
      c.invalidate(measurementsEnabledProvider);
      expect(c.read(measurementPromptProvider), MeasurementPrompt.due);
    });

    test('X on a due prompt: none for 6 days, due again at 7', () async {
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-01');
      final c = container();
      expect(read(c), MeasurementPrompt.due);
      await c.read(measurementPromptProvider.notifier).dismiss();
      expect(HiveService.instance.userBox.get(_dismissKey), '2026-10-12');
      setTestClockTo(_now.add(const Duration(days: 6)));
      expect(read(container()), MeasurementPrompt.none, reason: 'day 6');
      setTestClockTo(_now.add(const Duration(days: 7)));
      expect(read(container()), MeasurementPrompt.due, reason: 'day 7');
    });

    test('X on a baseline prompt: none for 27 days, baseline again at 28',
        () async {
      await putProfile('2026-08-01T00:00:00Z');
      final c = container();
      expect(read(c), MeasurementPrompt.baseline);
      await c.read(measurementPromptProvider.notifier).skipBaseline();
      expect(HiveService.instance.userBox.get(_skipKey), '2026-10-12');
      setTestClockTo(_now.add(const Duration(days: 27)));
      expect(read(container()), MeasurementPrompt.none, reason: 'day 27');
      setTestClockTo(_now.add(const Duration(days: 28)));
      expect(read(container()), MeasurementPrompt.baseline, reason: 'day 28');
    });

    // The prompt follows a save through its watch of the history, on the real
    // graph: nothing is overridden.
    test('after a real save() the banner clears: due -> none', () async {
      SyncService.pausedForSimulation = true;
      addTearDown(() => SyncService.pausedForSimulation = false);
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-01');
      final c = container();
      expect(read(c), MeasurementPrompt.due);
      final res = await c.read(measurementWriteProvider.notifier).save(
            sites: {'waist': 81.0},
            source: WriteSource.manual,
            inchesUsed: false,
          );
      expect(res.success, isTrue);
      expect(c.read(measurementPromptProvider), MeasurementPrompt.none);
    });

    test('the cloud form of the onboarding stamp (+00:00, or any offset) '
        'reads the same IST day as the Z form', () async {
      for (final stamp in [
        '2026-09-30T19:00:00+00:00',
        '2026-10-01T00:30:00+05:30',
      ]) {
        await putProfile(stamp);
        setTestClockTo(DateTime.utc(2026, 10, 7, 6)); // IST 2026-10-07
        expect(read(container()), MeasurementPrompt.none, reason: stamp);
        setTestClockTo(DateTime.utc(2026, 10, 8, 6)); // IST 2026-10-08
        expect(read(container()), MeasurementPrompt.baseline, reason: stamp);
      }
    });

    // 20:00Z is already the NEXT day in IST. The clock sits months away from
    // the real date, so a stamp taken from `DateTime.now()` cannot agree with
    // it by coincidence either.
    group('the IST day, not the UTC day, and not the real clock', () {
      final lateUtc = DateTime.utc(2026, 3, 15, 20); // IST 2026-03-16 01:30

      test('dismiss() and skipBaseline() stamp the IST day', () async {
        setTestClockTo(lateUtc);
        await putProfile('2026-01-01T00:00:00Z');
        await putEntry('2026-01-20');
        final c = container();
        expect(read(c), MeasurementPrompt.due);
        await c.read(measurementPromptProvider.notifier).dismiss();
        expect(HiveService.instance.userBox.get(_dismissKey), '2026-03-16');

        await HiveService.instance.healthBox.delete('measurement_2026-01-20');
        final c2 = container();
        expect(read(c2), MeasurementPrompt.none, reason: 'dismissed just now');
        await HiveService.instance.userBox.delete(_dismissKey);
        expect(read(container()), MeasurementPrompt.baseline);
        await container().read(measurementPromptProvider.notifier).skipBaseline();
        expect(HiveService.instance.userBox.get(_skipKey), '2026-03-16');
      });

      test('the prompt counts days from the IST today', () async {
        // 2026-02-16 -> IST today 2026-03-16 is 28 days (due); the UTC day
        // 2026-03-15 would make it 27 (none).
        setTestClockTo(lateUtc);
        await putProfile('2026-01-01T00:00:00Z');
        await putEntry('2026-02-16');
        expect(read(container()), MeasurementPrompt.due);
      });
    });

    test('the anonymous token is silent: none, no event, no profile read; a '
        'real token then gives due', () async {
      await putProfile('2026-08-01T00:00:00Z');
      await putEntry('2026-09-01');
      var profileBuilt = 0;
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue('<anon>'),
        userProfileProvider.overrideWith(() {
          profileBuilt++;
          throw StateError('the profile throws in the swap window');
        }),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(measurementPromptProvider, (_, _) {});
      addTearDown(sub.close);
      expect(c.read(measurementPromptProvider), MeasurementPrompt.none);
      expect(c.read(bodyMeasurementsProvider).loaded, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty, reason: 'not a defect, so no event');
      expect(profileBuilt, 0, reason: 'the anonymous window never reads it');

      c.updateOverrides([
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
        userProfileProvider.overrideWith(UserProfileNotifier.new),
      ]);
      expect(c.read(measurementPromptProvider), MeasurementPrompt.due,
          reason: 'the token change alone rebuilds the prompt');
    });
  });

  // ── parity with the reader's private date check ──────────────────────────

  group('parseIstKeyStrict agrees with the reader on which dates are real', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
      setTestClockTo(_now);
    });

    tearDown(() async {
      resetTestClock();
      await tearDownHiveForTests(tempDir);
    });

    test('same verdict on a table of valid and invalid keys', () async {
      final arabicDigit = String.fromCharCode(0x0662);
      final table = <String>[
        '2026-10-05',
        '2026-10-12',
        '2024-02-29', // a real leap day, in the past
        '2026-02-30',
        '2027-02-29',
        '2026-13-01',
        '2026-00-10',
        '2026-10-00',
        '2026-10-32',
        '2026-1-5',
        '2026-10-5',
        '26-10-05',
        ' 2026-10-05',
        '2026-10-05 ',
        '2026-10-05T00:00:00Z',
        '20261001',
        '2026-10-05\n',
        '${arabicDigit}026-10-05',
      ];
      final box = HiveService.instance.healthBox;
      for (var i = 0; i < table.length; i++) {
        await box.put('measurement_row_$i', {
          'id': 'row_$i',
          'date': table[i],
          'waist': 80.0, // in range
          'updated_at_ms': 1,
        });
      }
      final readerAccepts = {
        for (final e in HealthReadService.instance.measurementHistory()) e.date,
      };
      for (final s in table) {
        // The reader also drops dates after today (2026-10-12): none of the
        // valid rows here is later.
        expect(readerAccepts.contains(s), parseIstKeyStrict(s) != null,
            reason: "'$s'");
        // Not just "both accept": both mean the SAME day.
        final parsed = parseIstKeyStrict(s);
        if (parsed != null) {
          final parts = s.split('-').map(int.parse).toList();
          expect(parsed, DateTime.utc(parts[0], parts[1], parts[2]),
              reason: "'$s'");
        }
      }
    });
  });
}
