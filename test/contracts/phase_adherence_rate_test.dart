// ⑧ 8-A/D1 (W2.5 adherence gate): `phase_adherence_rate` behavioral test.
// Pins `WorkoutScheduleReadService.currentPhaseCompletionRate()` == the Train
// phase-unlock card's rule (completed / total NON-REST scheduled days), computed
// through the REAL `getWeek`→`getScheduleForDate` path (so the completed→planned
// demotion is inherited, NOT bypassed by hand-assembled day data — Rev B fix 3).
// Drift axes seeded: rest vs workout vs custom_template, paused (non-rest, not
// done), the cross-date-completed demotion, a partial week, and a phase≥2 />4-week
// plan (the dynamic totalWeeks scan the card computes via `phase<=1?4:scan`).
// Also pins the extracted pure `phaseCompletionRate` primitive directly.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/phase_completion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Box wb; // workoutBox (schedule_* rows)
  late Box cb; // configBox (plan_start_date)
  late Box ub; // userBox (progress.current_phase)

  final planStart = DateTime(2026, 6, 1); // a Monday
  String dk(DateTime d) => istDateStr(d);
  double rate() =>
      WorkoutScheduleReadService.instance.currentPhaseCompletionRate();

  // Seed one schedule_<date> row for (week, dayOfWeek).
  Future<void> seedDay(int week, int dow,
      {required String type,
      String status = 'planned',
      String? completedAt}) async {
    final date = planStart.add(Duration(days: (week - 1) * 7 + dow));
    await wb.put('schedule_${dk(date)}', {
      'date': dk(date),
      'week': week,
      'day_of_week': dow,
      'type': type,
      'workout_name': type == 'rest' ? 'Rest Day' : 'Push',
      'exercises': <Map<String, dynamic>>[],
      'status': status,
      'completed_at': completedAt,
    });
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('phase_adherence');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    wb = HiveService.instance.workoutBox;
    cb = HiveService.instance.configBox;
    ub = HiveService.instance.userBox;
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await wb.clear();
    await cb.clear();
    await ub.clear();
    await cb.put('plan_start_date', planStart.toIso8601String());
  });

  // Seed current_phase (drives the card-mirrored `phase<=1?4:scan` span).
  Future<void> setPhase(int phase) =>
      ub.put('progress', {'current_phase': phase});

  group('phaseCompletionRate (pure primitive)', () {
    test('rest days excluded; done/total over workout days', () {
      final r = phaseCompletionRate([
        (isRest: false, isDone: true),
        (isRest: true, isDone: false), // rest — skipped
        (isRest: false, isDone: true),
        (isRest: false, isDone: false),
      ]);
      expect(r, closeTo(2 / 3, 1e-9));
    });
    test('zero workout days → 0.0 (no divide-by-zero)', () {
      expect(phaseCompletionRate([(isRest: true, isDone: false)]), 0.0);
      expect(phaseCompletionRate(const []), 0.0);
    });
  });

  group('currentPhaseCompletionRate (real getWeek path)', () {
    test('basic: 3 workout days (2 completed on-time), 4 rest → 2/3', () async {
      await seedDay(1, 0,
          type: 'workout',
          status: 'completed',
          completedAt: planStart.toIso8601String());
      await seedDay(1, 1, type: 'rest');
      await seedDay(1, 2,
          type: 'workout',
          status: 'completed',
          completedAt: planStart.add(const Duration(days: 2)).toIso8601String());
      await seedDay(1, 3, type: 'rest');
      await seedDay(1, 4, type: 'workout'); // planned
      await seedDay(1, 5, type: 'rest');
      await seedDay(1, 6, type: 'rest');
      expect(rate(), closeTo(2 / 3, 1e-9));
    });

    test('custom_template counts as a workout day', () async {
      // 1 workout (done) + 1 custom_template (done) + 1 workout (planned) → 2/3.
      await seedDay(1, 0,
          type: 'workout',
          status: 'completed',
          completedAt: planStart.toIso8601String());
      await seedDay(1, 1,
          type: 'custom_template',
          status: 'completed',
          completedAt: planStart.add(const Duration(days: 1)).toIso8601String());
      await seedDay(1, 2, type: 'workout'); // planned
      expect(rate(), closeTo(2 / 3, 1e-9));
    });

    test('paused workout counts to total but is not done', () async {
      await seedDay(1, 0,
          type: 'workout',
          status: 'completed',
          completedAt: planStart.toIso8601String());
      await seedDay(1, 1, type: 'workout', status: 'paused');
      // 2 workout days, 1 done → 1/2.
      expect(rate(), closeTo(1 / 2, 1e-9));
    });

    test('cross-date-completed row is DEMOTED (completed_at < its date) → not done',
        () async {
      // day-2 completed but completed_at is day-0 (earlier) → getScheduleForDate
      // demotes it to planned → not counted as done.
      await seedDay(1, 0,
          type: 'workout',
          status: 'completed',
          completedAt: planStart.toIso8601String());
      await seedDay(1, 2,
          type: 'workout',
          status: 'completed',
          completedAt: planStart.toIso8601String()); // date is day-2, completed day-0
      // day-0 done (on time); day-2 demoted → 1 of 2 done.
      expect(rate(), closeTo(1 / 2, 1e-9));
    });

    test('zero workout days (all rest) → 0.0', () async {
      for (var d = 0; d < 7; d++) {
        await seedDay(1, d, type: 'rest');
      }
      expect(rate(), 0.0);
    });

    test('phase>=2 plan with 6 materialized weeks → dynamic totalWeeks scans to 6',
        () async {
      await setPhase(2);
      // 1 workout day per week for weeks 1-6, weeks 1-3 completed.
      for (var w = 1; w <= 6; w++) {
        await seedDay(w, 0,
            type: 'workout',
            status: w <= 3 ? 'completed' : 'planned',
            completedAt: w <= 3
                ? planStart
                    .add(Duration(days: (w - 1) * 7))
                    .toIso8601String()
                : null);
      }
      // 6 workout days (one per week), 3 done → 3/6. If the scan stopped at 4 it
      // would be 3/4 — this pins the dynamic span.
      expect(rate(), closeTo(3 / 6, 1e-9));
    });

    test('phase 1 with week-5/6 rows (mid-phase regen) → totalWeeks capped at 4',
        () async {
      await setPhase(1);
      // A mid-phase Edit-Profile regen can leave a current_phase==1 plan with
      // week-5/6 rows (generateAndScheduleFromDate keeps plan_start when
      // !isFirstGeneration). The card caps phase-1 at 4 weeks; the service MUST
      // match — a bare scan would count weeks 5-6 and under-report (B-pass P2).
      for (var w = 1; w <= 6; w++) {
        await seedDay(w, 0,
            type: 'workout',
            status: w <= 2 ? 'completed' : 'planned',
            completedAt: w <= 2
                ? planStart.add(Duration(days: (w - 1) * 7)).toIso8601String()
                : null);
      }
      // phase<=1 → totalWeeks=4 → 4 workout days, weeks 1-2 done → 2/4 (NOT 2/6).
      expect(rate(), closeTo(2 / 4, 1e-9));
    });
  });
}
