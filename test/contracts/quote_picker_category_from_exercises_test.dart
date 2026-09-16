// Contract for Unit 3 obs 2 — the share-card quote category is derived from the
// workout's ACTUAL EXERCISES, not just its (possibly generic / custom) name.
//
// Pre-fix: a "test template" of pull exercises got a name-derived 'general' (or
// a mismatched) quote — the founder saw a "lat" quote on a non-lat workout.
// QuotePicker.categoryForExercises votes on the exercise names (which carry the
// muscle signal), falling back to the workout name, then 'general'.
//
// Pure function — no Hive / rootBundle (categoryForExercises only uses the
// keyword logic in categoryForWorkout, never loads the JSON pool).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/services/quote_picker.dart';

void main() {
  group('QuotePicker.categoryForExercises (Unit 3 obs 2)', () {
    test('pull exercises win over a generic custom workout name', () {
      expect(
        QuotePicker.categoryForExercises(
            ['Lat Pulldown', 'Barbell Row', 'Bicep Curl'], 'test template'),
        'pull',
      );
    });

    test('leg exercises → legs even when the name says nothing', () {
      expect(
        QuotePicker.categoryForExercises(
            ['Goblet Squat', 'Leg Extension', 'Calf Raise'], 'Day 1'),
        'legs',
      );
    });

    test('majority specific category wins on a mixed list', () {
      // 2 pull (Pull-up, Barbell Row) + 1 legs (Goblet Squat) → pull
      expect(
        QuotePicker.categoryForExercises(
            ['Pull-up', 'Barbell Row', 'Goblet Squat'], 'Mixed'),
        'pull',
      );
    });

    test('empty exercise list falls back to the workout NAME', () {
      expect(QuotePicker.categoryForExercises(const [], 'Push Day'), 'push');
    });

    test('no signal in exercises OR name → general', () {
      expect(
        QuotePicker.categoryForExercises(
            ['test exercise', 'thing'], 'test template'),
        'general',
      );
    });

    test('no exercise signal but a muscle keyword in the name → name category',
        () {
      expect(
        QuotePicker.categoryForExercises(['Custom Move A'], 'Leg Day'),
        'legs',
      );
    });

    test('deterministic — same exercise list always yields the same category',
        () {
      final a =
          QuotePicker.categoryForExercises(['Bench Press', 'Push-up'], 'x');
      final b =
          QuotePicker.categoryForExercises(['Bench Press', 'Push-up'], 'x');
      expect(a, b);
      expect(a, 'push');
    });

    test('word-bounded keywords — mid-word matches no longer mis-map (obs 2 root cause)',
        () {
      // "test template" contains "lat" (tem-p-LAT-e) but is NOT a pull workout
      // — this loose .contains('LAT') match WAS the founder's stray "lat" quote.
      expect(QuotePicker.categoryForWorkout('test template'), isNot('pull'));
      expect(QuotePicker.categoryForWorkout('Lateral Raise'), isNot('pull'));
      expect(QuotePicker.categoryForWorkout('Morning Warm-up'), isNot('arms'));
      // …genuine whole-word matches still resolve.
      expect(QuotePicker.categoryForWorkout('Lat Pulldown'), 'pull');
      expect(QuotePicker.categoryForWorkout('Barbell Row'), 'pull');
    });

    test(
        'BACK/CURL/PRESS cross-category collisions — the founder-reported '
        '"lats lit" bug on an all-legs day', () {
      // Pre-fix: "BACK" and "CURL" were checked as part of the PULL branch,
      // which ran BEFORE the LEGS branch. "Barbell Back Squat" and "Leg Curl
      // (Lying)" both genuinely contain a whole PULL-shaped word (BACK,
      // CURL) alongside a whole LEGS-shaped word (SQUAT, LEG) — a real
      // cross-category collision, not a substring bug, so tightening BACK/
      // CURL to \b-bounded regex alone would NOT have fixed this (both are
      // already whole words in these names). The fix reorders LEGS ahead of
      // PULL/PUSH so the leg-specific qualifier wins the tie.
      expect(QuotePicker.categoryForWorkout('Barbell Back Squat'), 'legs');
      expect(QuotePicker.categoryForWorkout('Leg Curl (Lying)'), 'legs');
      expect(
        QuotePicker.categoryForWorkout('Standing Single Leg Curl'),
        'legs',
      );
      expect(QuotePicker.categoryForWorkout('Sliding Leg Curl'), 'legs');

      // Same PRE-EXISTING collision class the reorder also fixes, surfaced
      // by this batch's audit of the real exercise library, not previously
      // reported: "Leg Press" matched PUSH's "PRESS" keyword and never
      // reached the legs check under the old pull -> push -> legs order.
      expect(QuotePicker.categoryForWorkout('Leg Press'), 'legs');

      // Genuine mid-word substring bugs (same CLASS as the original obs-2
      // "template"->LAT fix, this time for BACK): "Kickback" contains
      // "back" mid-word with no legs-qualifier to rescue it via reordering,
      // so BACK itself needed the \b-bounded fix. This only asserts the
      // fix stops the wrong-category regression (pull) — it does NOT assert
      // the true category (push, per exercise_library.json ground truth):
      // "Dumbbell Kickback" has no TRICEP/PUSH/PRESS/CHEST/SHOULDER keyword
      // of its own and falls to 'general', an accepted residual gap (B-pass
      // Finding 1, docs/reviews/08821dc5a27b-review.md; see the diagnose-doc's
      // impact_analysis) — do not read this assertion as "resolves correctly".
      expect(
        QuotePicker.categoryForWorkout('Dumbbell Kickback'),
        isNot('pull'),
      );
      expect(
        QuotePicker.categoryForWorkout('Glute Kickback'),
        'legs', // GLUTE wins regardless, via the reorder
      );

      // The exact founder-reported workout (leg day; screenshot showed the
      // "Lats lit. Standing taller already." pull/back quote on this list).
      expect(
        QuotePicker.categoryForExercises([
          'Barbell Back Squat',
          'Leg Extension',
          'Leg Curl (Lying)',
          'Handstand Hold',
          'Front Lever Hold',
        ], 'Legs'),
        'legs',
      );
    });
  });
}
