// Behavioral regression — ⑦(a) (Batch 3b-i): detraining WEIGHT decay in
// ProgressionResolver. A Phase-2+ user resuming after a training gap restarts
// lighter (decay applied to the baseline BEFORE the reps-rule; Epley-capped on
// the pre-decay 1RM; kill-switch disable_detraining_decay).
//
// Deterministic: `setTestClockTo` fixes "now" so istTodayStr() (and thus the
// day-gap) is stable. Pins the round-2 review findings:
//   • F7 — assert in the HOLD band (5≤reps<10 → suggested = base) so the Epley
//     clamp can't mask the decay;
//   • F4 — boundary days 7/8/21/22/35/36;
//   • F3 — a light lower-body lift at >35d/<5-reps must go DOWN (the <=0 back-off
//     floor resets to the DECAYED base, never the original weight);
//   • kill-switch → verbatim pre-⑦a weight (non-vacuity).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/progression_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  final fixedNow = DateTime(2026, 7, 13, 12, 0); // +5:30 IST → same calendar day
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_detraining_decay');
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
  });

  tearDown(() async {
    resetTestClock();
    await HiveUserSession.closeAll();
  });

  // Seed one exlog_ row for [name]: weight/reps logged [daysAgo] IST-days back.
  Future<void> seedExlog(String name,
      {required double weight, required int reps, required int daysAgo}) async {
    final dateStr = istDateStr(fixedNow.subtract(Duration(days: daysAgo)));
    await HiveService.instance.workoutBox.put('exlog_${dateStr}_$name', {
      'exercise_name': name,
      'date': dateStr,
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': weight, 'reps_completed': reps}
      ],
    });
  }

  double? resolved(String name) =>
      ProgressionResolver.resolve(phase: 2, exerciseNames: [name])[name];

  test('F7 — HOLD band decays exactly by the band factor (clamp never fires)',
      () async {
    // reps 7 → HOLD → suggested == base == weight × factor. 30d → 0.825.
    await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 30);
    expect(resolved('Bench'), 82.5);
  });

  test('F4 — band boundary days 7/8/21/22/35/36 (HOLD reps)', () async {
    Future<double?> at(int daysAgo) async {
      await HiveService.instance.workoutBox.clear();
      await seedExlog('Bench', weight: 100, reps: 7, daysAgo: daysAgo);
      return resolved('Bench');
    }

    expect(await at(7), 100.0, reason: '≤7d → no decay');
    expect(await at(8), 92.5, reason: '8d → −7.5%');
    expect(await at(21), 92.5, reason: '21d → −7.5%');
    expect(await at(22), 82.5, reason: '22d → −17.5%');
    expect(await at(35), 82.5, reason: '35d → −17.5%');
    expect(await at(36), 50.0, reason: '>35d → −50%');
  });

  test('F3 — light lower-body / >35d / <5 reps goes DOWN, never resets up',
      () async {
    // 5kg squat, 4 reps (<5 → back-off), 40d → factor 0.5 → base 2.5.
    // back-off 2.5 → 2.5−2.5 = 0 → floor resets to the DECAYED base (2.5),
    // NOT the original 5kg. Without the F3 fix this would prescribe 5.0 (UP).
    await seedExlog('Squat', weight: 5, reps: 4, daysAgo: 40);
    final w = resolved('Squat');
    expect(w, 2.5);
    expect(w! < 5.0, isTrue, reason: 'decay must never increase the weight');
  });

  test('kill-switch disable_detraining_decay → verbatim pre-⑦a weight',
      () async {
    await HiveService.instance.configBox
        .put('disable_detraining_decay', true);
    await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 30);
    expect(resolved('Bench'), 100.0); // no decay (vs 82.5 with decay ON)
  });

  test('phase 1 → no progression map (decay path never runs)', () async {
    await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 30);
    expect(
        ProgressionResolver.resolve(phase: 1, exerciseNames: ['Bench']), isEmpty);
  });
}
