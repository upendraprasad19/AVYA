// goal-change-targets B3 (pure): when does Edit Profile's Save owe the user a "Targets updated" dialog.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/services/target_impact.dart';

Map<String, dynamic> _p({
  Object dob = '1995-06-15',
  num height = 178,
  num weight = 80,
  String pace = 'balanced',
  num calories = 2000,
  num protein = 150,
}) =>
    {
      'date_of_birth': dob,
      'height_cm': height,
      'current_weight_kg': weight,
      'pace_preference': pace,
      'primary_goal': 'lose_fat',
      'gender': 'male',
      'daily_calories': calories,
      'protein_grams': protein,
    };

void main() {
  group('derivationInputsChangedForDialog', () {
    test('an ISO timestamp date of birth against YYYY-MM-DD of the same day is unchanged', () {
      expect(
          derivationInputsChangedForDialog(
              _p(dob: '1995-06-15T00:00:00.000'), _p(dob: '1995-06-15')),
          isFalse);
      expect(
          derivationInputsChangedForDialog(_p(dob: '1995-06-15'), _p(dob: '1995-06-16')),
          isTrue);
    });

    test('a fractional height within 0.5 is unchanged, beyond it is a change', () {
      expect(derivationInputsChangedForDialog(_p(height: 177.8), _p(height: 178)), isFalse);
      expect(derivationInputsChangedForDialog(_p(height: 177.4), _p(height: 178)), isTrue);
    });

    test('a weight, pace or goal change is a change; a 0.04 kg wobble is not', () {
      expect(derivationInputsChangedForDialog(_p(), _p(weight: 79)), isTrue);
      expect(derivationInputsChangedForDialog(_p(weight: 80), _p(weight: 80.04)), isFalse);
      expect(derivationInputsChangedForDialog(_p(), _p(pace: 'aggressive')), isTrue);
      expect(
          derivationInputsChangedForDialog(_p(), {..._p(), 'primary_goal': 'build_muscle'}),
          isTrue);
    });

    test('null on one side only is a change; null on both is not', () {
      expect(derivationInputsChangedForDialog({}, {}), isFalse);
      expect(derivationInputsChangedForDialog({}, {'body_fat_percent': 20}), isTrue);
    });
  });

  group('targetImpactFor', () {
    test('calories only moved', () {
      final i = targetImpactFor(_p(), _p(pace: 'slow', calories: 2200));
      expect(i, isNotNull);
      expect(i!.caloriesFrom, 2000);
      expect(i.caloriesTo, 2200);
      expect(i.proteinFrom, i.proteinTo);
    });

    test('protein only moved', () {
      final i = targetImpactFor(_p(), _p(pace: 'slow', protein: 160));
      expect(i, isNotNull);
      expect(i!.proteinTo, 160);
    });

    test('neither moved, even with an input changed: nothing to say', () {
      expect(targetImpactFor(_p(), _p(pace: 'slow')), isNull);
    });

    test('moved but no input really changed (a re-derivation): nothing to say', () {
      expect(targetImpactFor(_p(height: 177.8), _p(calories: 1900)), isNull);
    });

    test('no calorie target after the Save: nothing to say', () {
      expect(targetImpactFor(_p(), {..._p(pace: 'slow'), 'daily_calories': null}), isNull);
    });
  });
}
