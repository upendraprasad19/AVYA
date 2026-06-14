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
      // Unambiguous leg names (avoid "Back Squat"→BACK→pull + "Leg Press"→
      // PRESS→push keyword-precedence quirks).
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
  });
}
