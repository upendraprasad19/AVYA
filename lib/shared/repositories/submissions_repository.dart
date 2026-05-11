import 'package:icanbefitter/core/services/supabase_service.dart';

/// Community submissions repository — wraps all direct Supabase queries for
/// user custom submissions and community review. Follows CLAUDE.md rule #4:
/// no widget may call Supabase directly.
///
/// All methods are read-only or single-row writes that fire from widget
/// interactions (vote). Business logic (sorting, tagging) is left to the
/// caller so this layer stays thin.
class SubmissionsRepository {
  SubmissionsRepository._();
  static final SubmissionsRepository instance = SubmissionsRepository._();

  // ── My Submissions ──────────────────────────────────────────────────────

  /// Fetches all custom foods submitted to the public DB by [userId].
  ///
  /// Returns rows with: id, name, submitted_to_db, approved, created_at.
  Future<List<Map<String, dynamic>>> fetchMyFoodSubmissions(
      String userId) async {
    final res = await SupabaseService.instance.client
        .from('user_custom_foods')
        .select('id, name, submitted_to_db, approved, created_at')
        .eq('user_id', userId)
        .eq('submitted_to_db', true)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Fetches all custom exercises submitted to the library by [userId].
  ///
  /// Returns rows with: id, name, submitted_to_library,
  /// approved_for_library, created_at.
  Future<List<Map<String, dynamic>>> fetchMyExerciseSubmissions(
      String userId) async {
    final res = await SupabaseService.instance.client
        .from('user_custom_exercises')
        .select(
            'id, name, submitted_to_library, approved_for_library, created_at')
        .eq('user_id', userId)
        .eq('submitted_to_library', true)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  // ── Community Review ────────────────────────────────────────────────────

  /// Fetches up to 20 pending community food submissions not authored by
  /// [currentUserId] and not yet approved.
  ///
  /// Returns rows with: id, name, calories_per_100g, protein_per_100g,
  /// carbs_per_100g, fat_per_100g, user_id.
  Future<List<Map<String, dynamic>>> fetchPendingFoodReviews(
      String currentUserId) async {
    final res = await SupabaseService.instance.client
        .from('user_custom_foods')
        .select(
            'id, name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, user_id')
        .eq('submitted_to_db', true)
        .eq('approved', false)
        .neq('user_id', currentUserId)
        .limit(20);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Fetches up to 20 pending community exercise submissions not authored by
  /// [currentUserId] and not yet approved.
  ///
  /// Returns rows with: id, name, category, logging_type, user_id.
  Future<List<Map<String, dynamic>>> fetchPendingExerciseReviews(
      String currentUserId) async {
    final res = await SupabaseService.instance.client
        .from('user_custom_exercises')
        .select('id, name, category, logging_type, user_id')
        .eq('submitted_to_library', true)
        .eq('approved_for_library', false)
        .neq('user_id', currentUserId)
        .limit(20);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Returns a set of 'kind:id' keys for items the user has already reviewed,
  /// used to filter pending review lists.
  ///
  /// Returns rows with: item_type, item_id.
  Future<Set<String>> fetchAlreadyReviewedKeys(String reviewerId) async {
    final res = await SupabaseService.instance.client
        .from('community_reviews')
        .select('item_type, item_id')
        .eq('reviewer_id', reviewerId);
    return {
      for (final r in res as List)
        '${(r as Map)['item_type']}:${r['item_id']}',
    };
  }

  /// Records a community review vote (approve or reject) for a submission.
  ///
  /// [itemKind] — 'food' or 'exercise'.
  /// [itemId] — UUID of the submission.
  /// [approve] — true = approve, false = reject.
  Future<void> castCommunityVote({
    required String reviewerId,
    required String itemKind,
    required String itemId,
    required bool approve,
  }) async {
    await SupabaseService.instance.client.from('community_reviews').insert({
      'reviewer_id': reviewerId,
      'item_type': itemKind,
      'item_id': itemId,
      'vote': approve ? 'approve' : 'reject',
    });
  }
}
