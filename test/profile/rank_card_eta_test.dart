import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('B4: rank ETA non-negative', () {
    test('daysUntilNextRank is always non-negative', () {
      final days = RankService.instance.daysUntilNextRank();
      expect(days, greaterThanOrEqualTo(0),
          reason: 'B4 fix: ETA must never be negative');
      expect(days, lessThanOrEqualTo(365),
          reason: 'B4 fix: ETA clamped to 365 max');
    });

    test('getNextRank daysUntilEligible is always non-negative when not null', () {
      final next = RankService.instance.getNextRank();
      if (next?.daysUntilEligible != null) {
        expect(next!.daysUntilEligible!, greaterThanOrEqualTo(0),
            reason: 'B4: daysUntilEligible from getNextRank must be non-negative');
        expect(next.daysUntilEligible!, lessThanOrEqualTo(365),
            reason: 'B4: daysUntilEligible from getNextRank must be <= 365');
      }
    });
  });
}
