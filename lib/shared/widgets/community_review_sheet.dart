import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Bottom sheet showing pending community food/exercise submissions
/// for the user to approve or reject.
class CommunityReviewSheet extends StatefulWidget {
  const CommunityReviewSheet({super.key});

  @override
  State<CommunityReviewSheet> createState() => _CommunityReviewSheetState();
}

class _CommunityReviewSheetState extends State<CommunityReviewSheet> {
  List<Map<String, dynamic>> _pendingItems = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPendingItems();
  }

  Future<void> _loadPendingItems() async {
    try {
      final supabase = SupabaseService.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Get pending foods (submitted but not approved, not by current user)
      final foods = await supabase
          .from('user_custom_foods')
          .select('id, name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, user_id')
          .eq('submitted_to_db', true)
          .eq('approved', false)
          .neq('user_id', userId)
          .limit(20);

      // Get pending exercises
      final exercises = await supabase
          .from('user_custom_exercises')
          .select('id, name, category, logging_type, user_id')
          .eq('submitted_to_library', true)
          .eq('approved_for_library', false)
          .neq('user_id', userId)
          .limit(20);

      // Check which items the user has already voted on
      final allIds = [
        ...foods.map((f) => f['id']),
        ...exercises.map((e) => e['id']),
      ];

      Set<String> votedIds = {};
      if (allIds.isNotEmpty) {
        final votes = await supabase
            .from('community_reviews')
            .select('item_id')
            .eq('reviewer_id', userId);
        votedIds = votes.map((v) => v['item_id'].toString()).toSet();
      }

      final items = <Map<String, dynamic>>[];
      for (final f in foods) {
        final id = f['id'].toString();
        if (!votedIds.contains(id)) {
          items.add({...Map<String, dynamic>.from(f as Map), 'item_type': 'food'});
        }
      }
      for (final e in exercises) {
        final id = e['id'].toString();
        if (!votedIds.contains(id)) {
          items.add({...Map<String, dynamic>.from(e as Map), 'item_type': 'exercise'});
        }
      }

      if (mounted) {
        setState(() {
          _pendingItems = items;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[CommunityReviewSheet] $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load items';
          _loading = false;
        });
      }
    }
  }

  Future<void> _vote(Map<String, dynamic> item, String vote) async {
    // Optimistic removal — prevents double-tap submitting duplicate votes
    if (mounted) {
      setState(() {
        _pendingItems.remove(item);
      });
    }

    try {
      final supabase = SupabaseService.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('community_reviews').insert({
        'reviewer_id': userId,
        'item_type': item['item_type'],
        'item_id': item['id'],
        'vote': vote,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            vote == 'approve' ? 'Approved' : 'Rejected',
            style: AppTypography.bodySm,
          ),
          backgroundColor: vote == 'approve' ? AppColors.ok : AppColors.card,
          duration: const Duration(seconds: 1),
        ));
      }
    } catch (e) {
      debugPrint('[CommunityReviewSheet._vote] $e');
      // On failure, re-add the item so user can retry
      if (mounted) {
        setState(() {
          _pendingItems.add(item);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        border: Border(
          top: BorderSide(color: AppColors.line2),
          left: BorderSide(color: AppColors.line2),
          right: BorderSide(color: AppColors.line2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.stackM),
          // Letterhead
          WardLetterhead(
            eyebrow: 'COMMUNITY REVIEW',
            title: 'Pending submissions',
            divider: false,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.stackS,
              AppSpacing.gutter,
              AppSpacing.stackS,
            ),
            trailing: Text(
              '10 approvals = live',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const WardRule(margin: EdgeInsets.symmetric(horizontal: AppSpacing.gutter)),
          const SizedBox(height: AppSpacing.stackM),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                _error!,
                style: AppTypography.body.copyWith(color: AppColors.bad),
              ),
            )
          else if (_pendingItems.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.ok, size: 32),
                  const SizedBox(height: AppSpacing.stackS),
                  Text(
                    'No items to review right now',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  0,
                  AppSpacing.gutter,
                  AppSpacing.stackL + 6,
                ),
                itemCount: _pendingItems.length,
                separatorBuilder: (_, index) => const SizedBox(height: AppSpacing.stackS),
                itemBuilder: (ctx, i) {
                  final item = _pendingItems[i];
                  final isFood = item['item_type'] == 'food';

                  return WardCard(
                    variant: WardCardVariant.inset,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // Icon
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: (isFood ? AppColors.warn : AppColors.accent)
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.soft),
                          ),
                          child: Icon(
                            isFood ? Icons.restaurant : Icons.fitness_center,
                            size: 18,
                            color: isFood ? AppColors.warn : AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.stackM),
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['name'] as String?) ?? 'Unknown',
                                style: AppTypography.h3.copyWith(fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isFood
                                    ? '${(item['calories_per_100g'] as num?)?.round() ?? 0} kcal \u2022 P:${(item['protein_per_100g'] as num?)?.round() ?? 0}g \u2022 C:${(item['carbs_per_100g'] as num?)?.round() ?? 0}g \u2022 F:${(item['fat_per_100g'] as num?)?.round() ?? 0}g'
                                    : '${item['category'] ?? ''} \u2022 ${item['logging_type'] ?? ''}',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.textMute,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Approve/Reject buttons
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.bad, size: 20),
                          onPressed: () => _vote(item, 'reject'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.check,
                              color: AppColors.ok, size: 20),
                          onPressed: () => _vote(item, 'approve'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
