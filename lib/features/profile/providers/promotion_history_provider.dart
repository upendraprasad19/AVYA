import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/repositories/rank_promotion_repository.dart';

/// Theme B · APK Test #8 — single rank promotion record fetched from
/// the `rank_promotions` table. Consumed only by
/// [RankServiceRecordSheet]; if the sheet ever needs different shape
/// (e.g. trigger metadata) extend this class rather than introducing a
/// second model.
class PromotionRecord {
  final String rankCode;
  final DateTime achievedAt;

  const PromotionRecord({
    required this.rankCode,
    required this.achievedAt,
  });

  factory PromotionRecord.fromMap(Map<String, dynamic> m) => PromotionRecord(
        rankCode: m['rank_code'] as String,
        achievedAt: DateTime.parse(m['achieved_at'] as String),
      );
}

/// Last 5 rank promotions for the current user, most-recent first.
///
/// Returns an empty list on any failure (silent — same fire-and-forget
/// posture used elsewhere in this codebase) or when the user is not
/// signed in. The sheet's empty-state handles both branches identically.
///
/// Audit A5 (2026-05-21): direct `.from('rank_promotions')` query
/// moved into [RankPromotionRepository.getRecent] per CLAUDE.md rule #4.
final promotionHistoryProvider =
    FutureProvider<List<PromotionRecord>>((ref) async {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  final user = SupabaseService.instance.currentUser;
  if (user == null) return const [];
  return RankPromotionRepository.instance.getRecent(user.id);
});
