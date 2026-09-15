// Behavioral regression — W3.3 (Batch 11-A): ID-keyed exercise history in
// ProgressionResolver, behind `enable_exercise_id_history` (default OFF, ship
// dark). The resolver matches a logged `exlog_*` row to a plan exercise by the
// library `exercise_id` — INCLUSIVE with name (id-matched ∪ name-matched, the
// MORE-RECENT of the two) — so a renamed/swapped exercise no longer splits its
// weight history. Forward-only: legacy / restored / no-id rows still match by
// name. Flag OFF → the id-index is never built → name-only (byte-identical).
//
// Sessions are seeded at a ≤7d gap so the ⑦a detraining decay factor is 1.0
// (base == logged weight) and the progression math is clean. Upper-body names
// ("Bench…") → +2.5 on progress / −1.25 on back-off (per `_isLowerBody`).

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
  final fixedNow = DateTime(2026, 7, 13, 12, 0);
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_exlog_id');
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

  // One exlog session under [name], [daysAgo] IST-days back. [exerciseId] (when
  // non-null) stamps the library id the WriteService now persists. [suffix]
  // keeps two same-name/same-day rows distinct.
  Future<void> seedExlog(
    String name, {
    required double weight,
    required int reps,
    required int daysAgo,
    String? exerciseId,
    String suffix = '',
  }) async {
    final dateStr = istDateStr(fixedNow.subtract(Duration(days: daysAgo)));
    final row = <String, dynamic>{
      'exercise_name': name,
      'date': dateStr,
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': weight, 'reps_completed': reps}
      ],
    };
    if (exerciseId != null) row['exercise_id'] = exerciseId;
    await HiveService.instance.workoutBox.put('exlog_${dateStr}_$name$suffix', row);
  }

  Future<void> enableIdHistory() async =>
      HiveService.instance.configBox.put('enable_exercise_id_history', true);
  Future<void> enableGraded() async =>
      HiveService.instance.configBox.put('enable_graded_progression', true);

  Future<void> setIntermediateProfile() async =>
      HiveService.instance.userBox.put('profile', {
        'fitness_experience': 'intermediate',
        'onboarding_completed_at':
            fixedNow.subtract(const Duration(days: 400)).toUtc().toIso8601String(),
      });

  // resolve() for a single plan exercise (name + optional library id).
  double? resolved(String planName, {String? planId, String? repRange}) =>
      ProgressionResolver.resolve(
        phase: 2,
        exerciseNames: [planName],
        repRanges: {planName: repRange},
        exerciseIds: {planName: planId},
      )[planName];

  group('inclusive id-OR-name match (flag ON)', () {
    setUp(enableIdHistory);

    test('id match survives a rename — log under a different name, same id',
        () async {
      // Logged under "Bench" with library id 'lib_bench'; the current plan
      // calls the same movement "Barbell Bench Press" (renamed). Name-match
      // fails, id-match wins → progression continues from the id-logged set.
      await seedExlog('Bench',
          weight: 100, reps: 10, daysAgo: 3, exerciseId: 'lib_bench');
      expect(resolved('Barbell Bench Press', planId: 'lib_bench'), 102.5);
    });

    test('no exercise_id on the row → name fallback (forward-only)', () async {
      // A legacy / restored row carries NO exercise_id; the flag is ON but the
      // id-index is empty for it → the name match still resolves it.
      await seedExlog('Bench', weight: 100, reps: 10, daysAgo: 3); // no id
      expect(resolved('Bench', planId: 'lib_bench'), 102.5);
    });

    test('split history — id-log and name-log both counted, MORE-RECENT wins',
        () async {
      // A pre-flag name-log (older) + a post-flag id-log under a different name
      // (newer). The inclusive match takes the more-recent (the id-log @120),
      // NOT the stale name-log @100 → no split-history loss.
      await seedExlog('Bench', weight: 100, reps: 10, daysAgo: 6); // name, older
      await seedExlog('Bench Variant',
          weight: 120, reps: 10, daysAgo: 2, exerciseId: 'lib_bench'); // id, newer
      expect(resolved('Bench', planId: 'lib_bench'), 122.5);
    });

    test('empty-string exercise_id is NOT indexed (isNotEmpty guard)', () async {
      // An empty id must never become a matchable key: log under a DIFFERENT
      // name AND an empty id → nothing matches → no weight (contrast the
      // real-id rename case above, which resolves to 102.5).
      await seedExlog('Bench',
          weight: 100, reps: 10, daysAgo: 3, exerciseId: '');
      expect(resolved('Barbell Bench Press', planId: 'lib_bench'), isNull);
    });
  });

  test('flag OFF (default) → name-only, byte-identical (rename NOT matched)',
      () async {
    // Same seed as the rename case, flag OFF: the id-index is never built and
    // the name differs → no match → no weight. Flag ON resolves 102.5; the
    // delta proves the id path is genuinely gated.
    await seedExlog('Bench',
        weight: 100, reps: 10, daysAgo: 3, exerciseId: 'lib_bench');
    expect(resolved('Barbell Bench Press', planId: 'lib_bench'), isNull);
  });

  test('graded union — id-index sessions feed the 2-consecutive back-off gate',
      () async {
    // graded ON + id-history ON. One below-range session arrives via the NAME
    // index (older), the other via the ID index (newer, different name). The
    // graded rule unions BOTH → 2 consecutive distinct-day below-range → back
    // off (−1.25 → 98.8). Without the union only the name session counts → 1
    // session → HOLD (100.0); 98.8 proves the id-index sessions are unioned in.
    await enableIdHistory();
    await enableGraded();
    await setIntermediateProfile();
    await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 5); // name, below
    await seedExlog('Bench Variant',
        weight: 100, reps: 7, daysAgo: 2, exerciseId: 'lib_bench'); // id, below
    expect(resolved('Bench', planId: 'lib_bench', repRange: '8-12'), 98.8);
  });
}
