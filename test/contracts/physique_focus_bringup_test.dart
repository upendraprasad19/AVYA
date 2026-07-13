// Behavioral regression — ⑤ (Batch 4, Option 1): physique_focus bring-up. The
// user's self-selected `physique_focus` is CENTRALLY translated to muscle-
// substring tokens (TrainingHistoryAnalyzer.physiqueFocusToBodyFocus), read from
// the profile via a try/catch helper (physiqueFocusMuscles → [] on null/corrupt),
// and fed to effectiveBodyFocus, which PeriodizationEngine turns into +1 set per
// matching exercise. The dedicated isolation SLOT is a founder-deferred future
// batch — this pins the +1-set mechanism only.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

import '../plan_engine_v4/_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('physiqueFocusToBodyFocus — pure translation table', () {
    test('glutes_legs → [glutes, quads, hamstrings, calves]', () {
      expect(TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('glutes_legs'),
          ['glutes', 'quads', 'hamstrings', 'calves']);
    });
    test('chest_shoulders_arms → [chest, delt, shoulder, triceps, biceps]', () {
      expect(
          TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('chest_shoulders_arms'),
          ['chest', 'delt', 'shoulder', 'triceps', 'biceps']);
    });
    test('balanced / strength / null / unknown → [] (no bring-up)', () {
      expect(TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('balanced'), isEmpty);
      expect(TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('strength'), isEmpty);
      expect(TrainingHistoryAnalyzer.physiqueFocusToBodyFocus(null), isEmpty);
      expect(TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('nonsense'), isEmpty);
    });
  });

  group('translated physique_focus → +1 set via PeriodizationEngine (effect)', () {
    // Mirrors hypertrophy_archetype_test "Body focus +1 set", but drives the
    // REAL reader with the TRANSLATED glutes_legs tokens — proving the
    // token→muscle-substring translation actually produces the +1-set on the
    // right muscles. (No generateV4 Hive-boot harness exists; apply-direct is the
    // established pattern for this stage.)
    test('glutes_legs → a Glutes exercise gets +1 set; a non-matching does not',
        () {
      final populated = [
        populatedDay(exercisesA: [
          exercise(name: 'Hip Thrust', primaryMuscles: ['Glutes', 'Hamstrings']),
          exercise(name: 'Bench Press', primaryMuscles: ['Chest', 'Triceps']),
        ]),
      ];
      final focus =
          TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('glutes_legs');
      final withFocus = PeriodizationEngine.apply(
          populated: populated, phase: 1, is6Day: false, bodyFocus: focus);
      final without = PeriodizationEngine.apply(
          populated: populated, phase: 1, is6Day: false, bodyFocus: const []);

      // Hip Thrust matches 'glutes'/'hamstrings' → +1 set.
      expect(withFocus[0].workoutDays[0].exercises[0].sets,
          without[0].workoutDays[0].exercises[0].sets + 1);
      // Bench Press matches none of the glutes_legs tokens → unchanged.
      expect(withFocus[0].workoutDays[0].exercises[1].sets,
          without[0].workoutDays[0].exercises[1].sets);
    });
  });

  group('physique_focus seam (Hive) — helper read + resolveBodyFocus glue', () {
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('test_physique_focus');
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
    });

    tearDown(() async {
      await HiveUserSession.closeAll();
    });

    test('seeded physique_focus=glutes_legs → translated tokens', () async {
      await HiveService.instance.userBox
          .put('profile', {'physique_focus': 'glutes_legs'});
      expect(TrainingHistoryAnalyzer.physiqueFocusMuscles(),
          ['glutes', 'quads', 'hamstrings', 'calves']);
    });

    test('balanced → [] (seam then falls back to weakMuscles)', () async {
      await HiveService.instance.userBox
          .put('profile', {'physique_focus': 'balanced'});
      expect(TrainingHistoryAnalyzer.physiqueFocusMuscles(), isEmpty);
    });

    test('no profile / absent physique_focus → [] (graceful, no throw)',
        () async {
      // No profile written, and a profile without the field.
      expect(TrainingHistoryAnalyzer.physiqueFocusMuscles(), isEmpty);
      await HiveService.instance.userBox.put('profile', {'name': 'x'});
      expect(TrainingHistoryAnalyzer.physiqueFocusMuscles(), isEmpty);
    });

    // resolveBodyFocus — the flag-gate + precedence GLUE (B-pass P2). This is the
    // generateV4 seam extracted; these pin it so reverting the seam fails a test,
    // not just the components. The flag-ON case fails if the seam stops calling
    // physiqueFocusMuscles; the flag-OFF case fails if ship-dark ever leaks.
    test('flag ON + physique_focus=glutes_legs → physique tokens (phase 1, wins)',
        () async {
      await HiveService.instance.configBox
          .put('enable_physique_focus_bringup', true);
      await HiveService.instance.userBox
          .put('profile', {'physique_focus': 'glutes_legs'});
      expect(
          TrainingHistoryAnalyzer.resolveBodyFocus(
              explicitBodyFocus: const [], phase: 1),
          ['glutes', 'quads', 'hamstrings', 'calves']);
    });

    test('flag OFF (default) → byte-identical (physique_focus ignored)', () async {
      await HiveService.instance.userBox
          .put('profile', {'physique_focus': 'glutes_legs'});
      // phase 1: no weakMuscles → []; phase 2: weakMuscles (no 14 days) → [].
      expect(
          TrainingHistoryAnalyzer.resolveBodyFocus(
              explicitBodyFocus: const [], phase: 1),
          isEmpty);
      expect(
          TrainingHistoryAnalyzer.resolveBodyFocus(
              explicitBodyFocus: const [], phase: 2),
          isEmpty);
    });

    test('flag ON + balanced → [] at phase 1 (no bring-up, no phase-1 fallback)',
        () async {
      await HiveService.instance.configBox
          .put('enable_physique_focus_bringup', true);
      await HiveService.instance.userBox
          .put('profile', {'physique_focus': 'balanced'});
      expect(
          TrainingHistoryAnalyzer.resolveBodyFocus(
              explicitBodyFocus: const [], phase: 1),
          isEmpty);
    });

    test('explicit bodyFocus param passes through unchanged', () async {
      await HiveService.instance.configBox
          .put('enable_physique_focus_bringup', true);
      expect(
          TrainingHistoryAnalyzer.resolveBodyFocus(
              explicitBodyFocus: const ['chest'], phase: 1),
          ['chest']);
    });
  });
}
