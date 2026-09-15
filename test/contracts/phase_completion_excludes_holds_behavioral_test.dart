// BEHAVIORAL TEST — phase completion excludes hold weeks (FOB-7(a) / OI-60)
//
// Concept:  phase_completion_hold_exclusion
// Writer:   lib/core/services/workout_schedule_write_service.dart holdWeek()
//           (stamps `is_hold` / `hold_ordinal` on each schedule_* row)
// Reader:   lib/core/services/workout_schedule_read_service.dart
//           currentPhaseCompletionRate() -> _withoutHoldRows()
//           -> shouldOfferAdvanceChoice (graduation_screen, pro_phase_advance)
//
// THE RULE UNDER TEST: a hold week is a pause the user CHOSE; its planned days
// are not part of any phase's prescribed work, so they must not dilute the
// phase completion rate that gates the PRO advance.
//
// REACHABILITY WAS SETTLED BY EXECUTION, NOT ANALYSIS. Three rounds on the OI
// board and round 1 of this batch's plan review all reasoned about whether the
// `phase >= 2` branch can see hold rows, and produced four different answers.
// Seeding the state directly answered it in one run: getWeek(5) and getWeek(6)
// each return 7 rows with is_hold=true, and with all 28 real days COMPLETED the
// pre-fix rate read 0.6667 instead of 1.0.
//
// The precondition -- current_phase >= 2 while plan_start has NOT moved past the
// holds -- is not hypothetical. Diagnose
// docs/diagnoses/2026-08-09-past-phase-display-and-expired-copy-c9e4b7.md
// records a real production account in exactly that state (2026-08-05:
// current_phase=2, plan_start unmoved, 77 rows spanning ~13 weeks) and states
// the writer responsible is unconfirmed and NOT FIXED.
//
// WHY THE HARM IS ASYMMETRIC: the dilution only ever pushes the rate DOWN, and
// only for a user who took a hold -- i.e. the free user who chose to stay rather
// than churn. With enable_adherence_gate ON they are then offered the
// "detrained / repeat the phase" path on a perfect record.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
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
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-00000000f07a';

  final planStart = DateTime(2026, 6, 1); // Monday
  final planEnd = planStart.add(const Duration(days: 27)); // Sunday +27
  final hold1Start = DateTime(2026, 6, 29); // == planStart + 28 == "week 5" by date

  // ignore: deprecated_member_use_from_same_package
  final read = WorkoutScheduleReadService.instance;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('fob7aprobe_');
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
    await HiveService.instance.configBox.delete('enable_hold_weeks');
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write('plan_end_date', planEnd.toIso8601String());
    // 4 weeks of phase-1 rows, ALL COMPLETED, so the regular window scores 1.0
    // and any dilution in the result can only have come from hold days.
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
            'status': 'completed',
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

  Future<void> takeHolds(int count) async {
    await HiveService.instance.configBox.put('enable_hold_weeks', true);
    for (var i = 0; i < count; i++) {
      setTestClockTo(hold1Start.add(Duration(days: 7 * i, hours: 10)));
      await WorkoutScheduleWriteService.instance.holdWeek();
    }
  }

  group('FOB-7(a) — hold days must not dilute the phase completion rate', () {
    test('phase>=2 + unmoved plan_start + holds: a perfect record scores 1.0',
        () async {
      await takeHolds(2); // H1 at planStart+28, H2 at +35 -- "weeks 5 and 6"
      await UserRepository.instance.updateProgress({'current_phase': 2});

      // The holds really are where the phase>=2 scan looks -- if this ever stops
      // being true the test below would pass vacuously.
      expect(read.getWeek(5).length, 7,
          reason: 'hold week 1 must land in the phase>=2 scan range');
      expect(read.getWeek(5).first['is_hold'], isTrue);
      expect(read.getWeek(6).length, 7);

      // All 28 real days are completed. Pre-fix this read 0.6667.
      expect(read.currentPhaseCompletionRate(), 1.0,
          reason: '28 of 28 prescribed days done; the 14 hold days are a chosen '
              'pause, not missed work');
    });

    test('the dilution is what the fix removes: unfiltered would be 28/42',
        () async {
      await takeHolds(2);
      await UserRepository.instance.updateProgress({'current_phase': 2});

      // Pin the exact arithmetic the fix defeats, so a future change that
      // re-admits hold rows fails with a recognisable number rather than a
      // vague inequality. 28 completed / (28 + 14 planned hold) = 0.6667.
      final holdDays =
          read.getWeek(5).length + read.getWeek(6).length;
      expect(holdDays, 14);
      expect(28 / (28 + holdDays), closeTo(0.6667, 0.0001));
      expect(read.currentPhaseCompletionRate(), isNot(closeTo(0.6667, 0.0001)));
    });

    test('a partially-completed phase still scores on its OWN days only',
        () async {
      // Mark one real day planned, so the honest rate is 27/28, and prove the
      // hold days neither add to the denominator nor to the numerator.
      final d = planStart.add(const Duration(days: 3));
      await WorkoutWriteService.instance.upsertScheduled(
        date: d,
        entry: {
          'type': 'workout',
          'date': formatDateKey(d),
          'week': 1,
          'phase': 1,
          'status': 'planned',
          'workout_name': 'Upper Body',
          'exercises': <Map<String, dynamic>>[
            {'name': 'Squat', 'sets': 3, 'reps': 5, 'weight': 100.0},
          ],
        },
        source: WriteSource.schedSwap,
      );
      await takeHolds(1);
      await UserRepository.instance.updateProgress({'current_phase': 2});

      expect(read.currentPhaseCompletionRate(), closeTo(27 / 28, 0.0001));
    });

    test('NO holds taken: behaviour is byte-identical (the no-op case)',
        () async {
      await UserRepository.instance.updateProgress({'current_phase': 2});
      // No hold rows exist, so _withoutHoldRows filters nothing and the scan
      // finds no week 5. This is every user who never held.
      expect(read.getWeek(5), isEmpty);
      expect(read.currentPhaseCompletionRate(), 1.0);
    });

    test('phase 1 is unaffected — the cap was already 4 weeks', () async {
      await takeHolds(2);
      await UserRepository.instance.updateProgress({'current_phase': 1});
      // The phase<=1 branch hard-caps totalWeeks at 4, so holds at "weeks 5-6"
      // were never in range. Pinned so the fix cannot be credited with a change
      // it did not make.
      expect(read.currentPhaseCompletionRate(), 1.0);
    });

    test('a hold-only week extends the scan but contributes NO days', () async {
      await takeHolds(1);
      await UserRepository.instance.updateProgress({'current_phase': 2});
      // getWeek(5) is non-empty (7 hold rows), so the `scanned` loop DOES reach
      // week 5 — deliberately. The scan answers "how far does the schedule
      // extend"; the accumulator is where holds must not count. Filtering the
      // scan too was round 2's undercount bug (see the next test).
      expect(read.getWeek(5).length, 7);
      expect(read.currentPhaseCompletionRate(), 1.0);
    });

    test('ROUND-2 REGRESSION: hold weeks must not hide real phase-2 weeks '
        'BEYOND them', () async {
      // The bug round 2 constructed: filtering the `scanned` loop made a
      // fully-hold week 5 read as empty, break the scan at w=5, and silently
      // drop real weeks 7+ from BOTH numerator and denominator — inflating the
      // rate for a user whose later weeks were genuinely incomplete.
      await takeHolds(2); // weeks 5 and 6 become all-hold

      // Real, INCOMPLETE phase-2 content at week 7 (planStart + 42).
      for (int d = 0; d < 7; d++) {
        final date = planStart.add(Duration(days: 42 + d));
        await WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: {
            'type': 'workout',
            'date': formatDateKey(date),
            'week': 7,
            'phase': 2,
            'status': 'planned', // NOT completed
            'workout_name': 'Lower Body',
            'exercises': <Map<String, dynamic>>[
              {'name': 'Deadlift', 'sets': 3, 'reps': 5, 'weight': 140.0},
            ],
          },
          source: WriteSource.schedSwap,
        );
      }
      await UserRepository.instance.updateProgress({'current_phase': 2});

      // 28 completed real days + 7 planned real days = 28/35 = 0.8.
      // If the scan breaks at the hold week, week 7 vanishes and this reads 1.0.
      expect(read.currentPhaseCompletionRate(), closeTo(28 / 35, 0.0001),
          reason: 'week 7 is real work and must stay in the denominator; the '
              'hold weeks between must not truncate the scan');
    });
  });
}
