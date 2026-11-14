// Behavioral regression — ⑤ (Batch 4, Option 1): physique_focus bring-up. LIVE
// since 2026-09-16 (OI-53 batch 2); kill-switch `disable_physique_focus_bringup`.
// The user's self-selected `physique_focus` is CENTRALLY translated to muscle-
// substring tokens (TrainingHistoryAnalyzer.physiqueFocusToBodyFocus), read from
// the profile via a try/catch helper (physiqueFocusMuscles → [] on null/corrupt),
// and fed to effectiveBodyFocus, which `generateV4` turns into the allocator's
// focus groups (raised weekly top / session cap; the per-exercise +1 in
// PeriodizationEngine was deleted with the unbudgeted body, flip 2026-11-02). The
// dedicated isolation SLOT is a founder-deferred future batch.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

import '../helpers/session_budget_fixtures.dart';

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

  group('translated physique_focus → focus groups in the set-budget allocator (effect)',
      () {
    // The flip (2026-11-02) deleted `PeriodizationEngine`'s per-exercise +1 (it
    // lived in the unbudgeted body). The same translated tokens now reach
    // `generateV4` as `BudgetMuscleGroups.of(effectiveBodyFocus)`, which raise those
    // groups' weekly top to 25 and their session cap to 12 in the allocator's focus
    // pass. This drives the REAL translation table, the REAL group mapper and the
    // REAL allocator: the tokens must produce the focus groups, and a focus group
    // must end the week with more sets than the same plan without focus.
    test('glutes_legs tokens map to exactly the four budget groups', () {
      final focus = BudgetMuscleGroups.of(
          TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('glutes_legs'));
      expect(focus, {'Glutes', 'Quads', 'Hamstrings', 'Calves'});
    });

    test('a focus group ends the week with more sets than without; others do not',
        () {
      final fx = Fx()
        ..row('Hip Thrust', ['Glutes'], type: 'compound')
        ..row('Glute Bridge', ['Glutes'], type: 'isolation')
        ..row('Cable Kickback', ['Glutes'], type: 'isolation')
        ..row('Bench Press', ['Chest'], type: 'compound')
        ..row('Cable Fly', ['Chest'], type: 'isolation')
        ..row('Pec Deck', ['Chest'], type: 'isolation');
      List<PopulatedDay> days() => [
            for (var d = 0; d < 3; d++)
              fx.day('hypertrophy', [
                fx.ex('Hip Thrust'),
                fx.ex('Glute Bridge'),
                fx.ex('Cable Kickback'),
                fx.ex('Bench Press'),
                fx.ex('Cable Fly'),
                fx.ex('Pec Deck'),
              ]),
          ];
      int weekly(List<PopulatedDay> out, Set<String> names) => [
            for (final d in out)
              for (final e in d.exercisesA)
                if (names.contains(e.exerciseName)) e.sets
          ].fold(0, (a, b) => a + b);
      const glutes = {'Hip Thrust', 'Glute Bridge', 'Cable Kickback'};
      const chest = {'Bench Press', 'Cable Fly', 'Pec Deck'};

      final focusGroups = BudgetMuscleGroups.of(
          TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('glutes_legs'));
      final withFocus = fx.run(days(), minutes: 90, focus: focusGroups, is6Day: false);
      final without = fx.run(days(), minutes: 90, is6Day: false);

      expect(weekly(withFocus, glutes), greaterThan(weekly(without, glutes)),
          reason: 'the focus pass grows a focus group past the ordinary top');
      expect(weekly(withFocus, chest), weekly(without, chest),
          reason: 'a non-focus group is untouched by the focus');
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
    test(
        'flag ON (LIVE default) + physique_focus=glutes_legs → physique '
        'tokens (phase 1, wins)', () async {
      await HiveService.instance.userBox
          .put('profile', {'physique_focus': 'glutes_legs'});
      expect(
          TrainingHistoryAnalyzer.resolveBodyFocus(
              explicitBodyFocus: const [], phase: 1),
          ['glutes', 'quads', 'hamstrings', 'calves']);
    });

    test(
        'kill-switch ON (disable_physique_focus_bringup) → byte-identical '
        '(physique_focus ignored)', () async {
      await HiveService.instance.configBox
          .put('disable_physique_focus_bringup', true);
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

    test(
        'flag ON (LIVE default) + balanced → [] at phase 1 (no bring-up, no '
        'phase-1 fallback)', () async {
      await HiveService.instance.userBox
          .put('profile', {'physique_focus': 'balanced'});
      expect(
          TrainingHistoryAnalyzer.resolveBodyFocus(
              explicitBodyFocus: const [], phase: 1),
          isEmpty);
    });

    test('explicit bodyFocus param passes through unchanged', () async {
      expect(
          TrainingHistoryAnalyzer.resolveBodyFocus(
              explicitBodyFocus: const ['chest'], phase: 1),
          ['chest']);
    });
  });
}
