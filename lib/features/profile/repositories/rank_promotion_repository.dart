import 'dart:async';

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/profile/providers/promotion_history_provider.dart'
    show PromotionRecord;

/// Rank promotion history repository — wraps direct Supabase reads on
/// the `rank_promotions` table. Created 2026-05-21 (audit A5) to
/// satisfy CLAUDE.md rule #4 ("no Supabase from widgets / providers").
///
/// `rank_promotions` is a server-authored append-only log (rows are
/// written by the rank-promotion Edge Function on milestone events);
/// this repository is read-only.
class RankPromotionRepository {
  RankPromotionRepository._();
  static final RankPromotionRepository instance = RankPromotionRepository._();

  /// Returns up to [limit] most recent promotion records for [userId],
  /// ordered by `achieved_at` descending.
  ///
  /// Returns an empty list on either "no rows" or any network/transport
  /// failure — the calling sheet renders the same empty state in both
  /// cases. Failures are telemetered through
  /// [ErrorTelemetry.recordNonFatal] so silent regressions still leave
  /// a server-side trail (pre-A5 the inline catch swallowed the error
  /// with no signal at all).
  Future<List<PromotionRecord>> getRecent(
    String userId, {
    int limit = 5,
  }) async {
    try {
      final rows = await SupabaseService.instance.client
          .from('rank_promotions')
          .select('rank_code, achieved_at')
          .eq('user_id', userId)
          .order('achieved_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(PromotionRecord.fromMap)
          .toList();
    } catch (e, stack) {
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        stack,
        reason: 'rank_promotion_repository_get_recent',
        extra: {'user_id': userId, 'limit': limit.toString()},
      ));
      return const [];
    }
  }
}
