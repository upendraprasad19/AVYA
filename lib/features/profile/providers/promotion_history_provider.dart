import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

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
final promotionHistoryProvider =
    FutureProvider<List<PromotionRecord>>((ref) async {
  final user = SupabaseService.instance.currentUser;
  if (user == null) return const [];
  try {
    final rows = await SupabaseService.instance.client
        .from('rank_promotions')
        .select('rank_code, achieved_at')
        .eq('user_id', user.id)
        .order('achieved_at', ascending: false)
        .limit(5);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PromotionRecord.fromMap)
        .toList();
  } catch (_) {
    return const [];
  }
});
