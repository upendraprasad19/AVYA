// OI-170 — `day_of_week` is 0=Mon..6=Sun everywhere, and the cloud round-trip
// must not be able to change that.
//
// THE BUG. The push sent `parsedDate.weekday` (Dart's 1..7) and the restore
// wrote the wire value back **after** the `...existingMap` spread, so a correct
// local 0..6 was OVERWRITTEN by a wrong 1..7 on every round-trip — reinstall,
// new device, or the background restore most returning users get on cold start.
// Readers add one (`train_provider.dart:619` / `:816`:
// `(week - 1) * 7 + day_of_week + 1`) and render the result as the `D<n>` badge
// (`week_rows.dart:54`, `day_card.dart:54`, `expandable_day_card.dart:196`), so
// Monday of week 1 displayed `D2` and Sunday `D8` inside a seven-day week.
// `preview_plan_provider.dart:117` also MATCHES on that number, silently falling
// through to its positional fallback at `:122`.
//
// THE FIX, and why it is on the restore side. `day_of_week` is a pure function
// of `scheduled_date`, so it never needed to round-trip. Deriving it at restore
// SELF-HEALS every already-corrupted cloud row with no migration — which no
// push-side fix alone could do, because rows that never change would never be
// re-pushed.
//
// SCOPE, stated honestly: the derivation is covered behaviorally below; the two
// sync seams are covered by source pins, because exercising them behaviorally
// needs a live Supabase round-trip. The pins assert the defect's exact shape is
// ABSENT, not merely that something changed.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_flags.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';

import '../../scripts/schedule_row_builder_gate_lib.dart' show stripDartComments;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('dayOfWeekFromDate — the canon', () {
    test('Monday is 0 and Sunday is 6', () {
      // 2026-06-01 is a Monday.
      expect(dayOfWeekFromDate('2026-06-01'), 0);
      expect(dayOfWeekFromDate('2026-06-07'), 6);
    });

    test('every day of one week maps to 0..6 in order', () {
      for (var i = 0; i < 7; i++) {
        final d = DateTime(2026, 6, 1).add(Duration(days: i));
        final key = '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        expect(dayOfWeekFromDate(key), i, reason: '$key should be day $i');
      }
    });

    test('never returns Dart\'s 1..7 — the exact defect', () {
      // Pre-fix this value was `DateTime.weekday`, i.e. 1 for Monday.
      expect(dayOfWeekFromDate('2026-06-01'), isNot(1));
      // And nothing may ever exceed 6.
      for (var i = 0; i < 14; i++) {
        final d = DateTime(2026, 6, 1).add(Duration(days: i));
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        expect(dayOfWeekFromDate(key), inInclusiveRange(0, 6));
      }
    });

    test('an unparseable date returns null rather than throwing', () {
      expect(dayOfWeekFromDate('not-a-date'), isNull);
      expect(dayOfWeekFromDate(''), isNull);
    });

    test('the reader arithmetic lands on the right day number', () {
      // train_provider.dart:619/:816 — `(week - 1) * 7 + day_of_week + 1`.
      int dayNumber(int week, int dow) => (week - 1) * 7 + dow + 1;

      expect(dayNumber(1, dayOfWeekFromDate('2026-06-01')!), 1,
          reason: 'Monday of week 1 is D1, not D2');
      expect(dayNumber(1, dayOfWeekFromDate('2026-06-07')!), 7,
          reason: 'Sunday of week 1 is D7, not D8');
      expect(dayNumber(2, dayOfWeekFromDate('2026-06-08')!), 8);
    });
  });

  group('sync seams (source pins — presence only)', () {
    // ⚠ COMMENTS STRIPPED FIRST, and this is not optional here. The fix's own
    // explanatory comments QUOTE the old literal (`'day_of_week':
    // parsedDate?.weekday`) to say what went wrong — so an absent-pattern grep
    // over the raw source fails on the very documentation of the fix. Same
    // self-trapping shape as a migration header quoting the value it replaced.
    // Reuses the gate's stripper rather than growing a second one.
    final src = stripDartComments(
        File('lib/core/services/sync/sync_workout.dart').readAsStringSync());

    test('the push no longer sends raw weekday', () {
      expect(src, isNot(contains("'day_of_week': parsedDate?.weekday")),
          reason: 'this literal WAS the bug');
      expect(src, contains("'day_of_week': entry['day_of_week'] ?? dayOfWeekFromDate(date)"));
    });

    test('the restore DERIVES rather than trusting the wire value', () {
      expect(src, contains('final derivedDayOfWeek ='));
      expect(src, contains('dayOfWeekFromDate(date)'));
      expect(src, isNot(contains("'day_of_week': map['day_of_week']")),
          reason: 'trusting the transmitted value is what overwrote the good '
              'local value after the existingMap spread');
    });
  });

  group('hotel planner uses the same canon (source pin)', () {
    final src = File('lib/features/ai_coach/services/hotel_workout_planner.dart')
        .readAsStringSync();

    test('writes weekday - 1', () {
      expect(src, contains("'day_of_week': d.weekday - 1"));
    });
  });

  // ── The kill-switch (§4.6 + blast_radius `platform` requires: feature_flag) ──
  //
  // Added after a B-pass finding: this batch is `platform` tier because it
  // touches `lib/core/services/sync/**`, and that tier's `requires:` list in
  // docs/blast_radius.yaml:25 includes `feature_flag`. Nothing ENFORCES that
  // list mechanically — `check_blast_radius_coverage.dart` does not read it —
  // so it is a review-read requirement, and review is what caught its absence.
  //
  // Polarity is OPT-OUT: the fix is live by default. Default-OFF would have
  // preserved the KNOWN-BROKEN path, which is not a safety mechanism.
  group('deriveDayOfWeekOnRestore kill-switch', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('test_dow_flag');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.instance.markInitializedForTests();
    });

    tearDownAll(() async {
      await Hive.close();
      // Cleanup is hygiene, never an assertion.
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    tearDown(() async {
      await HiveService.instance.configBox.delete('disable_day_of_week_derive');
    });

    test('defaults to DERIVING when the key is absent — the fix is live', () {
      expect(SyncFlags.deriveDayOfWeekOnRestore, isTrue);
    });

    test('setting the kill-switch reaches the LEGACY path', () async {
      await HiveService.instance.configBox
          .put('disable_day_of_week_derive', true);
      expect(SyncFlags.deriveDayOfWeekOnRestore, isFalse,
          reason: '§4.6 step 2 — the old path must stay REACHABLE when the '
              'gate is closed, not merely present in the source');
    });

    test('only the literal `true` closes the gate', () async {
      // A stray string or int must not silently disable a live fix.
      for (final junk in <dynamic>['true', 1, 'yes']) {
        await HiveService.instance.configBox
            .put('disable_day_of_week_derive', junk);
        expect(SyncFlags.deriveDayOfWeekOnRestore, isTrue,
            reason: 'a non-bool $junk must not read as "disabled"');
      }
    });

    test('explicit false also derives', () async {
      await HiveService.instance.configBox
          .put('disable_day_of_week_derive', false);
      expect(SyncFlags.deriveDayOfWeekOnRestore, isTrue);
    });
  });

  group('both branches survive in the restore source', () {
    final src = stripDartComments(
        File('lib/core/services/sync/sync_workout.dart').readAsStringSync());

    test('the restore is gated and BOTH arms are present', () {
      expect(src, contains('SyncFlags.deriveDayOfWeekOnRestore'));
      // The legacy arm, preserved verbatim per §4.6 step 2.
      expect(src, contains(": map['day_of_week'] as int?"),
          reason: 'the pre-fix behaviour must remain reachable');
    });
  });
}
