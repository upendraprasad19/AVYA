import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDownAll(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('Officer rank completion-rate qualification', () {
    test('SubLt qualifies at >=80% over 26 weeks', () {
      final svc = RankService.instance;
      final qualified = svc.testQualify(
        code: 'SubLt',
        streak: 0,
        totalWorkouts: 200,
        weeksSinceSignup: 110,
        deploymentsComplete: 0,
        completionRateOverride: 0.85, // > 0.80 minimum
      );
      expect(qualified, isTrue);
    });

    test('SubLt fails at 75% completion', () {
      final svc = RankService.instance;
      final qualified = svc.testQualify(
        code: 'SubLt',
        streak: 0,
        totalWorkouts: 200,
        weeksSinceSignup: 110,
        deploymentsComplete: 0,
        completionRateOverride: 0.75, // < 0.80 minimum
      );
      expect(qualified, isFalse);
    });

    test('Lt requires 26-week 80% rate at W130+', () {
      final svc = RankService.instance;
      expect(
        svc.testQualify(
          code: 'Lt',
          weeksSinceSignup: 130,
          completionRateOverride: 0.80,
        ),
        isTrue,
      );
      expect(
        svc.testQualify(
          code: 'Lt',
          weeksSinceSignup: 129, // 1 week short
          completionRateOverride: 0.95,
        ),
        isFalse,
      );
    });

    test('Capt requires 85% over 104 weeks at W260+', () {
      final svc = RankService.instance;
      expect(
        svc.testQualify(
          code: 'Capt',
          weeksSinceSignup: 260,
          completionRateOverride: 0.85,
        ),
        isTrue,
      );
      expect(
        svc.testQualify(
          code: 'Capt',
          weeksSinceSignup: 260,
          completionRateOverride: 0.84,
        ),
        isFalse,
      );
    });

    test('Sailor rank without completionRateMinimum unaffected', () {
      // LS only has streakAtLeast=14 and minWeeksSinceSignup=4;
      // completion rate field is null → not evaluated.
      expect(kRankGates['LS']!.completionRateMinimum, isNull);
    });
  });
}
