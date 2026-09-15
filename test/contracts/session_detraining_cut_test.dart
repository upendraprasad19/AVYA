// Behavioral regression — ⑦(b) (Batch 3, remaining half): session-time detraining
// resume cut. On starting a workout after a training gap, the last-logged-weight
// prefill is scaled by `detrainingFactorForGap(getDaysSinceLastWorkout())`, behind
// `enable_session_detraining_cut` (default OFF, ship dark). The factor lives on
// `ActiveWorkoutData` (session-only) and MUST survive `copyWith` (round-2 F1) — the
// 1×/sec timer's `copyWith(elapsedSeconds:)` would otherwise revert it to 1.0 within
// a frame while a prefill-only test still passed. The ⑦a-decayed PRESCRIPTION weight
// is never cut (disjoint prefill branches).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/detraining.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detrainingFactorForGap — bands + mis-fire guards (D2 + ⑦b guards)', () {
    test('≤7d band incl. -1 (first-ever) and 0 (only log today) → 1.0', () {
      expect(detrainingFactorForGap(-1), 1.0); // getDaysSinceLastWorkout no-history
      expect(detrainingFactorForGap(0), 1.0); // only log is today
      expect(detrainingFactorForGap(7), 1.0);
    });
    test('8–21d → 0.925', () {
      expect(detrainingFactorForGap(8), 0.925);
      expect(detrainingFactorForGap(21), 0.925);
    });
    test('22–35d → 0.825', () {
      expect(detrainingFactorForGap(22), 0.825);
      expect(detrainingFactorForGap(35), 0.825);
    });
    test('>35d → 0.5', () {
      expect(detrainingFactorForGap(36), 0.50);
      expect(detrainingFactorForGap(100), 0.50);
    });
  });

  group('ActiveWorkoutData.copyWith — F1 reactive survival (round-2)', () {
    test('default factor is 1.0 (no cut)', () {
      expect(const ActiveWorkoutData().sessionDetrainingFactor, 1.0);
    });
    test('factor SURVIVES the timer copyWith(elapsedSeconds:) — the F1 bug', () {
      const data = ActiveWorkoutData(sessionDetrainingFactor: 0.825);
      // The 1×/sec timer fires exactly this; if copyWith drops the field it
      // reverts to 1.0 while a prefill-only assertion still passes.
      expect(data.copyWith(elapsedSeconds: 5).sessionDetrainingFactor, 0.825);
    });
    test('factor SURVIVES the post-frame copyWith(setInputValues:)', () {
      const data = ActiveWorkoutData(sessionDetrainingFactor: 0.5);
      expect(
          data.copyWith(setInputValues: const {}).sessionDetrainingFactor, 0.5);
    });
    test('copyWith can still override the factor explicitly', () {
      const data = ActiveWorkoutData(sessionDetrainingFactor: 0.5);
      expect(
          data.copyWith(sessionDetrainingFactor: 0.925).sessionDetrainingFactor,
          0.925);
    });
  });

  group('startWorkout writer — gap → factor, flag-gated (integration)', () {
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    final fixedNow = DateTime(2026, 7, 13, 12, 0);
    late Directory tempDir;
    late ProviderContainer container;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('test_sess_detrain');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      for (final name in [
        HiveService.configBoxName,
        HiveService.migrationBoxName,
        'userBox_aaaaaaaa',
        'workoutBox_aaaaaaaa',
        'nutritionBox_aaaaaaaa',
        'healthBox_aaaaaaaa',
        'coachBox_aaaaaaaa',
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box(name).close();
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser(testUser);
      setTestClockTo(fixedNow);
      container = ProviderContainer();
    });

    tearDown(() async {
      container.dispose(); // cancels the notifier timer (ref.onDispose :903)
      resetTestClock();
      await HiveUserSession.closeAll();
    });

    // A logged workout session [daysAgo] days back. getDaysSinceLastWorkout scans
    // workoutBox for `type == 'workout_log'` rows and takes the max date.
    Future<void> seedWorkoutLog(int daysAgo) async {
      final dateStr = istDateStr(fixedNow.subtract(Duration(days: daysAgo)));
      await HiveService.instance.workoutBox.put('wlog_$dateStr', {
        'type': 'workout_log',
        'date': dateStr,
      });
    }

    Future<void> enableCut() async => HiveService.instance.configBox
        .put('enable_session_detraining_cut', true);

    double factorAfterStart() {
      const day = WorkoutDayData(dayNumber: 1, name: 'Push');
      container.read(activeWorkoutProvider.notifier).startWorkout(day);
      return container.read(activeWorkoutProvider).sessionDetrainingFactor;
    }

    test('flag ON + 25d gap → 0.825, SURVIVES setElapsedSeconds (F1 integration)',
        () async {
      await enableCut();
      await seedWorkoutLog(25);
      expect(factorAfterStart(), 0.825);
      // The screen ticks elapsed every second → copyWith; factor must persist.
      container.read(activeWorkoutProvider.notifier).setElapsedSeconds(10);
      expect(
          container.read(activeWorkoutProvider).sessionDetrainingFactor, 0.825);
    });

    test('kill-switch OFF (default) → 1.0 (no cut, verbatim)', () async {
      await seedWorkoutLog(25); // large gap, but flag off → no cut
      expect(factorAfterStart(), 1.0);
    });

    test('flag ON + 3d gap → 1.0 (≤7d, no cut / no banner)', () async {
      await enableCut();
      await seedWorkoutLog(3);
      expect(factorAfterStart(), 1.0);
    });

    test('flag ON + no history (gap -1) → 1.0 (first-ever, no cut)', () async {
      await enableCut();
      expect(factorAfterStart(), 1.0);
    });
  });
}
