// BEHAVIORAL TEST — gatherHoldRows anchors on the real Monday
// (FOB-7(b) / OI-60, added after round 2)
//
// Concept:  plan_integrity_hold_row_gathering
// Writer:   lib/core/services/workout_schedule_write_service.dart holdWeek()
// Reader:   lib/core/services/plan_integrity_reconciler.dart gatherHoldRows()
//
// WHY THIS FILE EXISTS. Round 2 found this batch reintroducing a pattern that
// had already been found, rejected BY NAME, and scar-commented for the streak
// arm: `HoldWeekInfo.weekStart` is `byOrdinal[ordinal]!.first`, the first
// SURVIVING hold date (workout_schedule_read_service.dart:870). A hold week
// whose Monday row is missing therefore yields a TUESDAY, and walking 0..6 from
// there reads [Tue..Sun, next Monday] — one day short at the front, one day of
// the FOLLOWING week at the back.
//
// Prior art, all of which predates this batch:
//   - train_provider.dart:577-579 — "Never `HoldWeekInfo.weekStart` either —
//     that is the first SURVIVING hold date, so a missing Monday row makes it a
//     Tuesday, which is wrong for a row key."
//   - docs/audit/oi60-streak-identity.closure.yaml:51 — lists it among the
//     REJECTED designs for FOB-2.
//   - test/contracts/hold_week_streak_identity_behavioral_test.dart — carries
//     the missing-Monday construction this file reuses.
//
// IT SHIPPED PAST TWO REVIEW ROUNDS' TEST SUITES because the loop was INLINE in
// reconcile(), which needs a live Supabase client, so no test could reach it.
// Extracting it was the actual fix; this file is the guard. A loop no test can
// reach is a loop no test protects.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-0000000007b0';
  final planStart = DateTime(2026, 6, 1); // Monday
  final planEnd = planStart.add(const Duration(days: 27));
  final hold1Monday = planStart.add(const Duration(days: 28));

  // ignore: deprecated_member_use_from_same_package
  final read = WorkoutScheduleReadService.instance;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('gatherholdrows_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    resetTestClock();
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.configBox.put('enable_hold_weeks', true);
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write('plan_end_date', planEnd.toIso8601String());
    for (int week = 1; week <= 4; week++) {
      for (int d = 0; d < 7; d++) {
        final date = planStart.add(Duration(days: (week - 1) * 7 + d));
        await WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: {
            'type': 'workout',
            'date': formatDateKey(date),
            'week': week,
            'phase': 1,
            'status': 'planned',
            'workout_name': 'Upper Body',
            'exercises': <Map<String, dynamic>>[
              {'name': 'Squat', 'sets': 3, 'reps': 5, 'weight': 100.0},
            ],
          },
          source: WriteSource.schedSwap,
        );
      }
    }
  });

  tearDown(() async {
    resetTestClock();
    await HiveService.instance.configBox.delete('enable_hold_weeks');
    final box = HiveService.instance.workoutBox;
    for (final k in box.keys
        .where((k) => k.toString().startsWith('schedule_'))
        .toList()) {
      await box.delete(k);
    }
    await HiveUserSession.closeAll();
  });

  group('gatherHoldRows — the missing-Monday case', () {
    /// Materializes [count] consecutive holds from hold1Monday onward.
    Future<void> takeHolds(int count) async {
      for (var i = 0; i < count; i++) {
        setTestClockTo(hold1Monday.add(Duration(days: 7 * i, hours: 10)));
        await WorkoutScheduleWriteService.instance.holdWeek();
      }
    }

    test('a hold missing its Monday must not absorb the NEXT hold Monday',
        () async {
      // TWO holds, then delete hold 1's Monday row. Both halves are load-bearing
      // and the first version of this test had only the second, so it passed
      // under the very mutation it existed to catch:
      //
      //   - deleting hold 1's Monday shifts weekStart to TUESDAY (the trigger);
      //   - hold 2 supplies a REAL row at hold1Monday + 7 (the detector).
      //
      // With one hold there is nothing at +7, so getScheduleForDate returns null
      // for both the correct and the rejected walk and the results are
      // byte-identical. A test whose input set cannot contain the symptom
      // reports "no bug" in the same colour as "no bug found".
      await takeHolds(2);
      await HiveService.instance.workoutBox
          .delete('schedule_${formatDateKey(hold1Monday)}');

      final holds = read.activeHoldWeeks();
      expect(holds, hasLength(2));
      final hold1 = holds.firstWhere((h) => h.ordinal == 1);
      expect(hold1.weekStart.weekday, isNot(DateTime.monday),
          reason: 'the deleted Monday must actually shift weekStart, or the '
              'rejected pattern and the correct one behave identically');

      final rows = PlanIntegrityReconciler.gatherHoldRows(read);
      final dates = rows.map((r) => r['date'] as String).toList();

      // 6 (hold 1, Monday deleted) + 7 (hold 2) = 13, each exactly once.
      expect(dates, hasLength(13));
      expect(dates.toSet(), hasLength(13),
          reason: 'walking 0..6 from a Tuesday weekStart reaches hold 2 '
              'Monday and gathers it TWICE');

      final hold2Monday = hold1Monday.add(const Duration(days: 7));
      expect(dates.where((d) => d == formatDateKey(hold2Monday)), hasLength(1),
          reason: 'the hold 2 Monday belongs to hold 2 alone');
    });

    test('an intact hold week gathers all seven days', () async {
      await takeHolds(1);
      final rows = PlanIntegrityReconciler.gatherHoldRows(read);
      expect(rows, hasLength(7),
          reason: 'the normalization must not COST days in the ordinary case — '
              'a fix that under-reads is not a fix');
    });

    test('flag OFF: empty even with hold rows on disk (ship-dark property)',
        () async {
      await takeHolds(1);
      expect(read.activeHoldWeeks(), isNotEmpty);
      await HiveService.instance.configBox.put('enable_hold_weeks', false);
      expect(PlanIntegrityReconciler.gatherHoldRows(read), isEmpty,
          reason: 'this is what keeps the whole FOB-7(b) path byte-identical '
              'with the flag off');
    });
  });
}
