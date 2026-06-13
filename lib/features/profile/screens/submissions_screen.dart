import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/error_telemetry.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/repositories/submissions_repository.dart';
import '../../../shared/widgets/error_state.dart';

/// S1 — unified Submissions screen with two tabs.
///
/// Before the APK-test-1-batch (2026-04-24) the community submission
/// surfaces were split across Profile as two separate rows:
///   * "Review Community Items" -> a community-review bottom sheet (since removed)
///   * "My Submissions"          -> `MySubmissionsScreen` route
///
/// Users tested the app and couldn't find their own submissions because
/// they kept tapping "Review Community Items" expecting it to surface
/// both their submissions AND things to vote on. This screen fixes that
/// by collapsing both into one entry point with a clear segment toggle.
///
/// Uses a handrolled 2-segment pill instead of Material `TabBar` — the
/// coach-screen status pill that could have been reused was removed in
/// 2026-04-18 (single-model migration), so no in-repo tab primitive
/// exists to ride. Pill styling matches WardChip conventions.
class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({super.key});

  @override
  State<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<SubmissionsScreen> {
  int _tab = 0; // 0 = MY SUBMISSIONS, 1 = COMMUNITY REVIEW

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COMMUNITY',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 2),
            Text('Submissions', style: AppTypography.h3),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              4,
              AppSpacing.screenPadding,
              12,
            ),
            child: _pillToggle(),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              sizing: StackFit.expand,
              children: const [
                _MySubmissionsBody(),
                _CommunityReviewBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillToggle() {
    return Row(
      children: [
        _pillSegment(index: 0, label: 'MY SUBMISSIONS'),
        const SizedBox(width: 8),
        _pillSegment(index: 1, label: 'COMMUNITY REVIEW'),
      ],
    );
  }

  Widget _pillSegment({required int index, required String label}) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.input,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.line2,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sharp),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: selected ? AppColors.bgDeep : AppColors.textDim,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tab 1: MY SUBMISSIONS ───────────────────────────────────────────
//
// Mirrors `MySubmissionsScreen._load`. Shows the current user's foods
// + exercises that are `submitted_to_*=true`, with approval status.

class _MySubmissionsBody extends StatefulWidget {
  const _MySubmissionsBody();

  @override
  State<_MySubmissionsBody> createState() => _MySubmissionsBodyState();
}

class _MySubmissionsBodyState extends State<_MySubmissionsBody> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      setState(() => _error = 'Sign in to see your submissions.');
      return;
    }
    try {
      final repo = SubmissionsRepository.instance;
      final foods = await repo.fetchMyFoodSubmissions(userId);
      final exercises = await repo.fetchMyExerciseSubmissions(userId);

      final rows = <Map<String, dynamic>>[
        for (final f in foods)
          {
            ...f,
            'kind': 'food',
            '_approved': f['approved'] == true,
          },
        for (final e in exercises)
          {
            ...e,
            'kind': 'exercise',
            '_approved': e['approved_for_library'] == true,
          },
      ];
      rows.sort((a, b) {
        final ca = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime(0);
        final cb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime(0);
        return cb.compareTo(ca);
      });

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'submissions_my_load'));
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t load submissions.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ErrorState(
        title: 'Couldn\'t load',
        subtitle: _error,
        onRetry: _load,
      );
    }
    if (_rows == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_rows!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'No submissions yet',
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Create a custom food or exercise and tick "Share with community" to contribute.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      itemCount: _rows!.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = _rows![i];
        final approved = r['_approved'] == true;
        final kind = r['kind'] == 'food' ? 'FOOD' : 'EXERCISE';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line2),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['name']?.toString() ?? 'Unnamed',
                      style: AppTypography.h3.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      kind,
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                approved ? 'APPROVED' : 'PENDING',
                style: AppTypography.monoXs.copyWith(
                  color: approved ? AppColors.ok : AppColors.warn,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Tab 2: COMMUNITY REVIEW ─────────────────────────────────────────
//
// Shows pending foods/exercises from OTHER users (fetched via the
// get-community-review-items Edge Function — own-only RLS blocks a direct
// cross-user read) that the current user hasn't voted on yet. Approve/Reject
// writes to `community_reviews`.

class _CommunityReviewBody extends StatefulWidget {
  const _CommunityReviewBody();

  @override
  State<_CommunityReviewBody> createState() => _CommunityReviewBodyState();
}

class _CommunityReviewBodyState extends State<_CommunityReviewBody> {
  List<Map<String, dynamic>> _pendingItems = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) {
        setState(() {
          _loading = false;
          _error = 'Sign in to review community items.';
        });
        return;
      }

      final repo = SubmissionsRepository.instance;
      final foods = await repo.fetchPendingFoodReviews(userId);
      final exercises = await repo.fetchPendingExerciseReviews(userId);

      // Filter out items the user already voted on.
      final reviewedKeys = await repo.fetchAlreadyReviewedKeys(userId);

      final items = <Map<String, dynamic>>[
        for (final f in foods)
          if (!reviewedKeys.contains('food:${f['id']}'))
            {
              ...f,
              'kind': 'food',
            },
        for (final e in exercises)
          if (!reviewedKeys.contains('exercise:${e['id']}'))
            {
              ...e,
              'kind': 'exercise',
            },
      ];

      if (!mounted) return;
      setState(() {
        _pendingItems = items;
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'submissions_community_review_load'));
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load items to review.";
      });
    }
  }

  Future<void> _vote(Map<String, dynamic> item, bool approve) async {
    // Optimistic removal.
    setState(() => _pendingItems.remove(item));
    try {
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return;
      await SubmissionsRepository.instance.castCommunityVote(
        reviewerId: userId,
        itemKind: item['kind'] as String,
        itemId: item['id'] as String,
        approve: approve,
      );
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'submissions_community_vote'));
      if (mounted) {
        setState(() => _pendingItems.add(item));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error != null) {
      return ErrorState(
        title: 'Couldn\'t load',
        subtitle: _error,
        onRetry: _load,
      );
    }
    if (_pendingItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'No items to review right now',
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Come back later \u2014 community submissions are audited before they go live.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      itemCount: _pendingItems.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = _pendingItems[i];
        final name = item['name']?.toString() ?? 'Unnamed';
        final kind = item['kind'] == 'food' ? 'FOOD' : 'EXERCISE';
        final subtitle = item['kind'] == 'food'
            ? '${item['calories_per_100g'] ?? '?'} kcal/100g \u00B7 ${item['protein_per_100g'] ?? '?'}g protein'
            : '${item['category'] ?? 'Exercise'} \u00B7 ${item['logging_type'] ?? '?'}';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line2),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: AppTypography.h3.copyWith(fontSize: 15),
                    ),
                  ),
                  Text(
                    kind,
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _vote(item, false),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.bad),
                          borderRadius:
                              BorderRadius.circular(AppRadius.sharp),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'REJECT',
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.bad,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _vote(item, true),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius:
                              BorderRadius.circular(AppRadius.sharp),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'APPROVE',
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.bgDeep,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
