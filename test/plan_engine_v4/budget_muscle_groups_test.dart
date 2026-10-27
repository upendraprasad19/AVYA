// B2 Task 2 (docs/plans/2026-10-22-session-set-budget.md): the budget muscle
// normaliser. Pure Dart.
//
// ⚠ Batch C's new library rows will change the "no group" row set below BY
// DESIGN (M11): when it fails after a library change, recompute the set from the
// data, read each new row, and update the literal; do not loosen the assertion.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

void main() {
  Set<String> of(List<String> tokens) => BudgetMuscleGroups.of(tokens);

  group('BudgetMuscleGroups.of — token table', () {
    test('the ten groups', () {
      expect(BudgetMuscleGroups.groups, [
        'Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps',
        'Quads', 'Hamstrings', 'Glutes', 'Core', 'Calves',
      ]);
    });

    test('the plan cases', () {
      expect(of(['Calves (Gastrocnemius)']), {'Calves'});
      expect(of(['Lateral Delts']), {'Shoulders'});
      expect(of(['Lats']), {'Back'});
      expect(of(['Lower Back', 'Glutes', 'Hamstrings']), {'Glutes', 'Hamstrings'});
      expect(of(['Upper Chest']), {'Chest'});
      expect(of(['thoracic']), <String>{});
    });

    test('Ruling 12: the erectors map to no group (they are not the lats)', () {
      expect(of(['Lower Back']), <String>{});
      expect(of(['Erector Spinae']), <String>{});
      expect(of(['Spinal Erectors']), <String>{});
      expect(of(['Thoracic Spine']), <String>{});
      // ...while the upper back is Back.
      expect(of(['Upper Back']), {'Back'});
      expect(of(['Traps', 'Rhomboids']), {'Back'});
    });

    test('lat matches only as a whole word', () {
      expect(of(['Lat']), {'Back'});
      expect(of(['Lats']), {'Back'});
      expect(of(['Lateral Delts']), {'Shoulders'}); // not Back
      expect(of(['Lateral Stabilisers']), <String>{});
    });

    test('spelling variants a future row could carry (B-pass R1 P3-4)', () {
      // The lower back in every spelling is the erectors, never the Back group the
      // `back` keyword would otherwise give it; quadratus lumborum is not Quads.
      for (final t in [
        'Low Back', 'lower-back', 'Lower_Back', 'LowerBack', 'Lumbar Spine', 'Quadratus Lumborum',
        'Quadratus', // the bare muscle name must not fall through to the `quad` keyword
      ]) {
        expect(of([t]), <String>{}, reason: t);
      }
      expect(of(['Latissimus Dorsi']), {'Back'});
      expect(of(['Abdominals']), {'Core'});
      expect(of(['Rectus Abdominis']), {'Core'});
      expect(of(['Upper Abs']), {'Core'});
      // `abs` stays a whole word: no substring of another word credits Core.
      expect(of(['Absorption']), <String>{});
    });

    test('every group has its keywords', () {
      expect(of(['Pectorals']), {'Chest'});
      expect(of(['Rear Delts', 'Front Delts']), {'Shoulders'});
      expect(of(['Shoulder Stabilisers']), {'Shoulders'});
      expect(of(['Biceps']), {'Biceps'});
      expect(of(['Brachialis']), {'Biceps'});
      expect(of(['Triceps']), {'Triceps'});
      expect(of(['Quadriceps']), {'Quads'});
      expect(of(['Hamstrings']), {'Hamstrings'});
      expect(of(['Gluteus Medius']), {'Glutes'});
      // One token each: a union would let one keyword mask another's removal.
      expect(of(['Abs']), {'Core'});
      expect(of(['Obliques']), {'Core'});
      expect(of(['Transverse Abdominis']), {'Core'});
      expect(of(['Core']), {'Core'});
      expect(of(['Soleus']), {'Calves'});
      expect(of(['Calf']), {'Calves'});
    });

    test('tokens that train no budget group map to nothing', () {
      for (final t in [
        'Full Body', 'Forearms', 'Forearms (extensors)', 'Hip Flexors',
        'Hip Flexors (Psoas)', 'Adductors', 'Abductors', 'Neck', 'Grip', 'Legs',
        'Achilles', 'Anti-rotation', 'Reactive Strength', '',
      ]) {
        expect(of([t]), <String>{}, reason: t);
      }
      expect(of(const []), <String>{});
    });

    test('case and a parenthetical do not matter; tokens are unioned', () {
      expect(of(['CHEST']), {'Chest'});
      expect(of(['  chest (upper)  ']), {'Chest'});
      expect(of(['Chest', 'Triceps', 'chest']), {'Chest', 'Triceps'});
      // A parenthetical that names ANOTHER muscle must not leak into the result.
      // (The plan's own example, "Calves (Gastrocnemius)", cannot show this: the
      // word before the bracket already says calves.)
      expect(of(['Forearms (biceps assist)']), <String>{});
    });

    test('one token naming two muscles credits both (no first-match-wins)', () {
      expect(of(['Chest / Triceps']), {'Chest', 'Triceps'});
    });
  });

  group('over the shipped library', () {
    final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();
    List<String> primary(Map<String, dynamic> r) =>
        [for (final m in (r['primary_muscles'] as List? ?? const [])) '$m'];

    test('no single token is credited to two groups', () {
      final tokens = {for (final r in rows) ...primary(r)};
      for (final t in tokens) {
        expect(of([t]).length, lessThanOrEqualTo(1), reason: '"$t" maps to ${of([t])}');
      }
    });

    test('the rep-based rows with no group are exactly this set (Ruling 12)', () {
      const repBased = {'weight_reps', 'bodyweight_reps', 'weighted_bodyweight', 'reps_only'};
      final noGroup = {
        for (final r in rows)
          if (repBased.contains(r['logging_type']) && of(primary(r)).isEmpty) r['id'] as String,
      };
      // E029 Hyperextension (lower back only, Ruling 12); E065 Burpee, E078 Surya
      // Namaskar, E137 Tire Flip, E184 Sandbag Clean, E194 Depth Jump, E200 Hindu
      // Warrior Flow (full body); E099 Wrist Curl, E100 Reverse Wrist Curl
      // (forearms); E108 Hip Adduction Machine (adductors); E157 Psoas March.
      // Batch C1 added 34 more, all with no budget group by the same rule (the expected set below is a literal, not a
      // recomputation): Forearms (Finger Curls, Pronation / Supination, the wrist-curl family), Adductors (Cable and Side
      // Lying Hip Adduction), Serratus (the Incline Shoulder Raises, Scapula Push Up), Rotator Cuff (the four shoulder-rotation
      // rows), Full Body (Dumbbell Burpee) and Tibialis Raise (N03).
      expect(noGroup, {
        'E029', 'E065', 'E078', 'E099', 'E100', 'E108',
        'E137', 'E157', 'E184', 'E194', 'E200',
        'G1201', 'G1437', 'G0455', 'G0168', 'G3667', 'G2705', 'G2706', 'G3021',
        'G0050', 'G0328', 'G0759', 'G0235', 'G0216', 'G0863', 'G0864', 'N03',
        'G0994', 'G1016', 'G0082', 'G0104', 'G0126', 'G0210', 'G0224', 'G0247',
        'G0365', 'G0368', 'G0366', 'G1441', 'G0367', 'G0369', 'G0397', 'G0358',
        'G1415', 'G0364',
      });
    });

    test('a barbell bench press credits Chest; a back squat credits Quads and Glutes', () {
      final byName = {for (final r in rows) r['name'] as String: r};
      expect(of(primary(byName['Barbell Bench Press']!)), {'Chest'});
      expect(of(primary(byName['Barbell Back Squat']!)), {'Quads', 'Glutes'});
    });
  });

  group('the focus tokens the generator passes', () {
    test('physique_focus glutes_legs -> Glutes, Quads, Hamstrings, Calves', () {
      expect(
        of(TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('glutes_legs')),
        {'Glutes', 'Quads', 'Hamstrings', 'Calves'},
      );
    });

    test('physique_focus chest_shoulders_arms -> Chest, Shoulders, Triceps, Biceps', () {
      expect(
        of(TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('chest_shoulders_arms')),
        {'Chest', 'Shoulders', 'Triceps', 'Biceps'},
      );
    });

    test('balanced and strength carry no focus', () {
      expect(of(TrainingHistoryAnalyzer.physiqueFocusToBodyFocus('balanced')), <String>{});
      expect(of(TrainingHistoryAnalyzer.physiqueFocusToBodyFocus(null)), <String>{});
    });

    test('the laggard tokens weakMuscles returns are lowercased library tokens', () {
      expect(of(['lats', 'quadriceps', 'lower back']), {'Back', 'Quads'});
    });
  });
}
