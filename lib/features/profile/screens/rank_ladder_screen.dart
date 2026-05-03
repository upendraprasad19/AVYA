// Test #10 obs 2 — Lifetime ladder full-screen.
//
// Reachable from `RankServiceRecordSheet`'s footer link
// `VIEW LIFETIME LADDER →` (replaces the old `VIEW FULL ROADMAP →`
// which routed to /train/roadmap; that destination stays accessible
// from the Train tab).
//
// Renders all 11 rank ladder rows with 3-state styling:
//   PASSED  — insignia 100% opacity · dim PASSED chip · `Earned · MMM yyyy`
//             from promotion_history_provider when available
//   CURRENT — gold 2px ring · 3px gold left-border · accent-10 row bg ·
//             gold-fill CURRENT chip · gateText hidden
//   FUTURE  — insignia 35% opacity · small lock glyph overlay ·
//             gateText visible per the new RankService._humanGateText
//
// Bottom summary tile: DEPLOYMENTS · SERVICE · VOLUME with totals
// pulled from UserRepository.progress, signupAt, and
// WorkoutRepository.totalLifetimeVolumeKg().

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/promotion_history_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';

enum _RowState { passed, current, future }

class RankLadderScreen extends ConsumerWidget {
  const RankLadderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankService = RankService.instance;
    final ladder = rankService.getLadder();
    final current = rankService.getCurrentRank();
    final currentIdx = ladder.indexWhere(
      (e) => e.entry.code == current.entry.code,
    );
    final history = ref.watch(promotionHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Lifetime ladder',
          style: AppTypography.titleL.copyWith(fontSize: 18),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
        itemCount: ladder.length + 1, // +1 for summary tile
        itemBuilder: (ctx, i) {
          if (i == ladder.length) {
            return _SummaryTile();
          }
          final view = ladder[i];
          final state = i < currentIdx
              ? _RowState.passed
              : i == currentIdx
                  ? _RowState.current
                  : _RowState.future;
          final earnedAt = state == _RowState.passed
              ? _earnedAtFor(history, view.entry.code)
              : null;
          return _LadderRow(
            view: view,
            state: state,
            earnedAt: earnedAt,
          );
        },
      ),
    );
  }

  /// Returns the achievedAt timestamp for a given rank code from the
  /// loaded promotion history, or null if not yet hydrated / not found.
  DateTime? _earnedAtFor(
    AsyncValue<List<PromotionRecord>> history,
    String rankCode,
  ) {
    return history.maybeWhen(
      data: (records) {
        for (final r in records) {
          if (r.rankCode == rankCode) return r.achievedAt;
        }
        return null;
      },
      orElse: () => null,
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Ladder row — 3-state styling
// ══════════════════════════════════════════════════════════════════

class _LadderRow extends StatelessWidget {
  const _LadderRow({
    required this.view,
    required this.state,
    required this.earnedAt,
  });

  final LadderEntryView view;
  final _RowState state;
  final DateTime? earnedAt;

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == _RowState.current;
    final isPassed = state == _RowState.passed;
    final isFuture = state == _RowState.future;

    return Container(
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.accent.withValues(alpha: 0.10)
            : Colors.transparent,
        border: Border(
          bottom: const BorderSide(color: AppColors.line2, width: 1),
          left: isCurrent
              ? const BorderSide(color: AppColors.accent, width: 3)
              : BorderSide.none,
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        isCurrent ? AppSpacing.gutter - 3 : AppSpacing.gutter,
        14,
        AppSpacing.gutter,
        14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: isFuture ? 0.35 : 1.0,
                child: WardRankInsignia(
                  rankCode: view.entry.code,
                  size: 36,
                ),
              ),
              if (isFuture)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.lock_outline,
                      size: 8,
                      color: AppColors.textMute,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        view.entry.shortName,
                        style: AppTypography.mono.copyWith(
                          fontSize: 11,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w700,
                          color: isFuture
                              ? AppColors.textDim
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      _StateChip.current()
                    else if (isPassed)
                      _StateChip.passed(),
                  ],
                ),
                const SizedBox(height: 4),
                if (isCurrent)
                  // Hide gateText on current rank — user is here.
                  const SizedBox.shrink()
                else if (isPassed)
                  Text(
                    earnedAt != null
                        ? 'Earned · ${_formatMonthYear(earnedAt!)}'
                        : 'Earned',
                    style: AppTypography.bodyS.copyWith(
                      color: AppColors.textMute,
                    ),
                  )
                else
                  Text(
                    view.gateText ?? '',
                    style: AppTypography.bodyS.copyWith(
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
}

class _StateChip extends StatelessWidget {
  const _StateChip._({
    required this.label,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color border;

  factory _StateChip.current() => const _StateChip._(
        label: 'CURRENT',
        background: AppColors.accent,
        foreground: AppColors.bg,
        border: AppColors.accent,
      );

  factory _StateChip.passed() => const _StateChip._(
        label: 'PASSED',
        background: Colors.transparent,
        foreground: AppColors.textDim,
        border: AppColors.border,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: AppTypography.mono.copyWith(
          fontSize: 8,
          letterSpacing: 1,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

String _formatMonthYear(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.year}';
}

// ══════════════════════════════════════════════════════════════════
// Bottom summary tile — DEPLOYMENTS · SERVICE · VOLUME
// ══════════════════════════════════════════════════════════════════

class _SummaryTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final progress = UserRepository.instance.getProgress() ?? {};
    final deployments = (progress['total_workouts_done'] as int?) ?? 0;

    final serviceDays = _serviceDays(progress);

    final volumeKg = WorkoutRepository.instance.totalLifetimeVolumeKg();

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        14,
        AppSpacing.gutter,
        0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCol(
              label: 'DEPLOYMENTS',
              value: '$deployments',
              unit: 'COMPLETE',
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.line2),
          Expanded(
            child: _SummaryCol(
              label: 'SERVICE',
              value: '$serviceDays',
              unit: serviceDays == 1 ? 'DAY' : 'DAYS',
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.line2),
          Expanded(
            child: _SummaryCol(
              label: 'VOLUME',
              value: _volumeLabel(volumeKg),
              unit: volumeKg >= 1000 ? 'TONNES' : 'KG',
            ),
          ),
        ],
      ),
    );
  }

  /// Days since the user joined. Mirrors `_readEvaluationState` priority:
  /// `phase_started_at` (IST midnight, set on plan generate) > auth.users
  /// `created_at`. Returns 0 when neither is available.
  int _serviceDays(Map<String, dynamic> progress) {
    final profile = UserRepository.instance.getProfile() ?? {};
    final phaseStartedAtIso = profile['phase_started_at'] as String?;
    DateTime? signup;
    if (phaseStartedAtIso != null) {
      signup = DateTime.tryParse(phaseStartedAtIso);
    }
    if (signup == null) {
      final user = SupabaseService.instance.currentUser;
      if (user != null) signup = DateTime.tryParse(user.createdAt);
    }
    if (signup == null) return 0;
    final diff = DateTime.now().difference(signup).inDays;
    return diff < 0 ? 0 : diff;
  }

  String _volumeLabel(double kg) {
    if (kg >= 1000) {
      final tonnes = kg / 1000;
      return tonnes >= 10
          ? tonnes.toStringAsFixed(0)
          : tonnes.toStringAsFixed(1);
    }
    return kg.toStringAsFixed(0);
  }
}

class _SummaryCol extends StatelessWidget {
  const _SummaryCol({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.mono.copyWith(
            fontSize: 9,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
            color: AppColors.textMute,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.titleL.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          unit,
          style: AppTypography.mono.copyWith(
            fontSize: 9,
            letterSpacing: 1.0,
            color: AppColors.textDim,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
