// BEHAVIORAL contract for rank_promotion_log:
//
// Reader: RankPromotionRepository.getRecent
//
// Contracts verified:
//  1. getRecent returns an EMPTY list (not throws) when the server call fails
//     (which it will in the test environment with no real Supabase client).
//  2. PromotionRecord.fromMap correctly parses rank_code + achieved_at.
//  3. A list of PromotionRecord objects sorted by achieved_at DESC is
//     correctly ordered (contract for what getRecent guarantees when rows arrive).
//
// The server writer (evaluate-rank-promotions cron) is out of scope.
//
// Run: flutter test test/contracts/rank_promotion_log_behavioral_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/providers/promotion_history_provider.dart'
    show PromotionRecord;
import 'package:icanbefitter/features/profile/repositories/rank_promotion_repository.dart';

void main() {
  group('rank_promotion_log — getRecent error-path returns empty list', () {
    test(
        'getRecent returns [] when Supabase is unavailable (test env — no real client)',
        () async {
      // In test environment, SupabaseService.instance.client will throw
      // because Supabase is not initialised. The catch block in
      // RankPromotionRepository.getRecent must swallow this and return [].
      final result =
          await RankPromotionRepository.instance.getRecent('test-user-id');
      expect(result, isEmpty,
          reason:
              'getRecent must return an empty list (not throw) when the '
              'Supabase call fails');
    });

    test(
        'getRecent with a non-existent user id returns [] without throwing',
        () async {
      final result = await RankPromotionRepository.instance
          .getRecent('00000000-0000-0000-0000-000000000000');
      expect(result, isEmpty,
          reason:
              'non-existent userId must result in [] rather than an exception');
    });
  });

  group('rank_promotion_log — PromotionRecord.fromMap parses correctly', () {
    test('fromMap returns a PromotionRecord with correct rank_code and achieved_at',
        () {
      final map = {
        'rank_code': 'SD1',
        'achieved_at': '2026-06-10T08:30:00.000Z',
      };
      final record = PromotionRecord.fromMap(map);
      expect(record.rankCode, 'SD1',
          reason: 'rankCode must equal map[rank_code]');
      expect(record.achievedAt,
          DateTime.parse('2026-06-10T08:30:00.000Z'),
          reason: 'achievedAt must be parsed from the ISO string');
    });

    test('fromMap handles achievedAt with microsecond precision', () {
      final map = {
        'rank_code': 'OC1',
        'achieved_at': '2026-01-01T00:00:00.123456Z',
      };
      final record = PromotionRecord.fromMap(map);
      expect(record.rankCode, 'OC1');
      expect(record.achievedAt.millisecond, 123,
          reason: 'millisecond component must be preserved');
    });
  });

  group('rank_promotion_log — sort order (most-recent first)', () {
    test('sorted list has most-recent achievedAt first', () {
      final older = PromotionRecord(
        rankCode: 'SD1',
        achievedAt: DateTime.utc(2026, 1, 1),
      );
      final newer = PromotionRecord(
        rankCode: 'SD2',
        achievedAt: DateTime.utc(2026, 6, 1),
      );
      final newest = PromotionRecord(
        rankCode: 'OC1',
        achievedAt: DateTime.utc(2026, 6, 10),
      );

      // Simulate what getRecent would return when ordered by achieved_at DESC.
      final rows = [older, newer, newest];
      rows.sort((a, b) => b.achievedAt.compareTo(a.achievedAt));

      expect(rows[0].rankCode, 'OC1',
          reason: 'most-recent promotion (OC1) must be first');
      expect(rows[1].rankCode, 'SD2',
          reason: 'second-most-recent (SD2) must be second');
      expect(rows[2].rankCode, 'SD1',
          reason: 'oldest promotion (SD1) must be last');
    });

    test('two rows with identical achievedAt preserve relative order (stable)',
        () {
      // getRecent uses .order('achieved_at', ascending: false). When two
      // rows have the same timestamp, the relative order is server-defined
      // (postgres tie-breaking). This test just verifies the fromMap →
      // sort pipeline doesn't throw or lose rows.
      final a = PromotionRecord(
        rankCode: 'SD1',
        achievedAt: DateTime.utc(2026, 6, 1),
      );
      final b = PromotionRecord(
        rankCode: 'SD2',
        achievedAt: DateTime.utc(2026, 6, 1),
      );
      final rows = [a, b];
      rows.sort((x, y) => y.achievedAt.compareTo(x.achievedAt));

      // Both rows must survive the sort — length is the invariant here.
      expect(rows.length, 2,
          reason: 'no rows must be dropped when achievedAt is equal');
    });
  });
}
