// Theme B · APK Test #8 — Rank service record bottom sheet.
//
// Replaces the inline accordion expansion of WardRankPill that lived
// in profile_screen.dart (`_buildRankServiceRecord`). Tapping the
// compact rank chip in [ProfileIdentity] opens this sheet.
//
// Layout (top → bottom):
//   1. SERVICE RECORD eyebrow
//   2. Current rank big card (48dp insignia + display name + status badge)
//   3. Status tiles: CURRENT STREAK (days) | FREEZES LEFT (n / total)
//   4. UPCOMING (next 2 ladder entries)
//   5. PROMOTION HISTORY (last 5 from rank_promotions; loading/empty
//      states handled inline)
//   6. VIEW FULL ROADMAP → → /train/roadmap
//
// Source: docs/superpowers/specs/2026-05-02-apk-test-8-design.md §4.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';

import '../providers/promotion_history_provider.dart';

class RankServiceRecordSheet extends ConsumerWidget {
  const RankServiceRecordSheet({super.key});

  /// Convenience entry point — every call site uses this rather than
  /// `showModalBottomSheet` directly so the styling stays consistent.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const RankServiceRecordSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankService = RankService.instance;
    final current = rankService.getCurrentRank();
    final ladder = rankService.getLadder();

    final currentIdx =
        ladder.indexWhere((e) => e.entry.code == current.entry.code);
    final upcomingCount = current.entry.isTerminal ? 0 : 2;
    final upcoming = (currentIdx >= 0 && currentIdx + 1 < ladder.length)
        ? ladder.skip(currentIdx + 1).take(upcomingCount).toList()
        : <LadderEntryView>[];

    final history = ref.watch(promotionHistoryProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter, 14, AppSpacing.gutter, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _eyebrow('SERVICE RECORD'),
              const SizedBox(height: 12),
              _currentRankBigCard(current),
              const SizedBox(height: 14),
              _statusTilesRow(),
              if (upcoming.isNotEmpty) ...[
                const SizedBox(height: 16),
                _divider(),
                const SizedBox(height: 14),
                _eyebrow('UPCOMING'),
                const SizedBox(height: 10),
                ...upcoming.map(_upcomingRow),
              ],
              const SizedBox(height: 16),
              _divider(),
              const SizedBox(height: 14),
              _eyebrow('PROMOTION HISTORY'),
              const SizedBox(height: 10),
              _promotionHistorySection(history, ladder),
              const SizedBox(height: 18),
              _divider(),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  // Test #10 obs 2 — was VIEW FULL ROADMAP → /train/roadmap.
                  // Now points at the new full-screen lifetime ladder.
                  // Train roadmap stays accessible from the Train tab.
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.go('/profile/rank-ladder');
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    foregroundColor: AppColors.accent,
                  ),
                  child: Text(
                    'VIEW LIFETIME LADDER →',
                    style: AppTypography.mono.copyWith(
                      fontSize: 11,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Section primitives ─────────────────────────────────────────────

  Widget _eyebrow(String label) {
    return Text(
      label,
      style: AppTypography.mono.copyWith(
        fontSize: 10,
        color: AppColors.textDim,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _divider() {
    return Container(height: 1, color: AppColors.line2);
  }

  Widget _currentRankBigCard(RankInfo current) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          WardRankInsignia(rankCode: current.entry.code, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.entry.displayName,
                  style: AppTypography.titleM
                      .copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  current.entry.isTerminal ? 'TERMINAL RANK' : 'CURRENT',
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    color: AppColors.accent,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTilesRow() {
    final streakDays = WorkoutRepository.instance.calculateCurrentStreak();
    final progress = UserRepository.instance.getProgress() ?? {};
    final freezesAvailable =
        (progress['streak_freezes_available'] as int?) ?? 0;
    // Freezes refill weekly: PRO=3, FREE=1. Total tile shows the
    // capacity, not historical count, so the user reads "X of Y left
    // this week".
    final isPro = SubscriptionService.instance.isPro();
    final maxFreezes = isPro ? 3 : 1;

    return Row(
      children: [
        Expanded(
          child: _statusTile(
            label: 'CURRENT STREAK',
            valueLine: '$streakDays',
            unitLine: streakDays == 1 ? 'DAY' : 'DAYS',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statusTile(
            label: 'FREEZES LEFT',
            valueLine: '$freezesAvailable / $maxFreezes',
            unitLine: 'THIS WEEK',
          ),
        ),
      ],
    );
  }

  Widget _statusTile({
    required String label,
    required String valueLine,
    required String unitLine,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.mono.copyWith(
              fontSize: 9,
              color: AppColors.textMute,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valueLine,
            style: AppTypography.titleL.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unitLine,
            style: AppTypography.mono.copyWith(
              fontSize: 9,
              color: AppColors.textDim,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingRow(LadderEntryView view) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Opacity(
            opacity: 0.55,
            child: WardRankInsignia(rankCode: view.entry.code, size: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.entry.shortName,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (view.gateText != null)
                  Text(
                    view.gateText!,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textMute,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Promotion history ──────────────────────────────────────────────

  Widget _promotionHistorySection(
    AsyncValue<List<PromotionRecord>> history,
    List<LadderEntryView> ladder,
  ) {
    return history.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _SkeletonRow(),
          SizedBox(height: 8),
          _SkeletonRow(),
        ],
      ),
      error: (_, _) => Text(
        'Could not load promotion history.',
        style: AppTypography.bodySm.copyWith(color: AppColors.textMute),
      ),
      data: (records) {
        if (records.isEmpty) {
          return Text(
            'No promotions yet.',
            style: AppTypography.bodySm.copyWith(color: AppColors.textMute),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: records.map((r) => _historyRow(r, ladder)).toList(),
        );
      },
    );
  }

  Widget _historyRow(
    PromotionRecord record,
    List<LadderEntryView> ladder,
  ) {
    // Resolve a display name: prefer a matching ladder entry; fall
    // back to the raw rank_code (always non-null) so a stale ladder
    // never produces an empty label.
    String displayName = record.rankCode;
    for (final view in ladder) {
      if (view.entry.code == record.rankCode) {
        displayName = view.entry.displayName;
        break;
      }
    }

    final dateLabel = _formatDate(record.achievedAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          WardRankInsignia(rankCode: record.rankCode, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Promoted to $displayName',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textMute,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.bgRaise,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 160,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.bgRaise,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 80,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.bgRaise.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
