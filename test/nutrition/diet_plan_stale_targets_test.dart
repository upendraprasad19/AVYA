// goal-change-targets B4 (pure): when does a saved diet chart owe the user a "targets changed" banner.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_stale_targets.dart';

void main() {
  const stamp = (calories: 2400, protein: 150);

  group('staleTargetsOf', () {
    test('calories only differ', () {
      final r = staleTargetsOf(stamp,
          calories: 2200, protein: 150, usingFallback: false);
      expect(r, isNotNull);
      expect(r!.current, (calories: 2200, protein: 150));
    });

    test('protein only differs', () {
      expect(
          staleTargetsOf(stamp, calories: 2400, protein: 140, usingFallback: false),
          isNotNull);
    });

    test('both equal -> nothing', () {
      expect(
          staleTargetsOf(stamp, calories: 2400, protein: 150, usingFallback: false),
          isNull);
    });

    test('rounding: 2400.4 and 150.4 still match the stamp, 2400.6 does not', () {
      expect(
          staleTargetsOf(stamp, calories: 2400.4, protein: 150.4, usingFallback: false),
          isNull);
      expect(
          staleTargetsOf(stamp, calories: 2400.6, protein: 150, usingFallback: false),
          isNotNull);
    });

    test('no stamp -> nothing; fallback targets -> nothing', () {
      expect(staleTargetsOf(null, calories: 1, protein: 1, usingFallback: false), isNull);
      expect(staleTargetsOf(stamp, calories: 1900, protein: 130, usingFallback: true),
          isNull);
    });
  });

  group('dietTargetStampOfSaved', () {
    test('reads both numbers, rounded', () {
      expect(
          dietTargetStampOfSaved(
              {kDietTargetCaloriesKey: 2400, kDietTargetProteinKey: 149.6}),
          (calories: 2400, protein: 150));
    });

    test('a plan without the keys, or with one of them, or a non-number, has no stamp', () {
      expect(dietTargetStampOfSaved({}), isNull);
      expect(dietTargetStampOfSaved({kDietTargetCaloriesKey: 2400}), isNull);
      expect(
          dietTargetStampOfSaved(
              {kDietTargetCaloriesKey: '2400', kDietTargetProteinKey: 150}),
          isNull);
    });
  });
}
