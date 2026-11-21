// Unit 4a: the two pure guards of the Diet Plan screen's Supplements handling.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_supplements_state.dart';

void main() {
  group('savedPlanMatchesSupplements', () {
    test('a stamped plan matches only an active state', () {
      expect(savedPlanMatchesSupplements({'diet_supplements': true}, true), isTrue);
      expect(savedPlanMatchesSupplements({'diet_supplements': true}, false), isFalse);
    });
    test('an unstamped plan (and a non-true stamp) matches only an inactive state', () {
      expect(savedPlanMatchesSupplements({}, false), isTrue);
      expect(savedPlanMatchesSupplements({}, true), isFalse);
      expect(savedPlanMatchesSupplements({'diet_supplements': 'true'}, true), isFalse);
      expect(savedPlanMatchesSupplements({'diet_supplements': false}, false), isTrue);
    });
  });

  group('dietPlanNeedsRegenerationForSupplements', () {
    bool needs(int epoch, bool planActive, bool active) =>
        dietPlanNeedsRegenerationForSupplements(
            planEpoch: epoch, planActive: planActive, active: active);
    test('never before the first plan', () {
      expect(needs(0, false, true), isFalse);
      expect(needs(0, true, false), isFalse);
    });
    test('once a plan exists, only a changed state regenerates', () {
      expect(needs(1, false, true), isTrue);
      expect(needs(1, true, false), isTrue);
      expect(needs(1, true, true), isFalse);
      expect(needs(1, false, false), isFalse);
    });
  });
}
