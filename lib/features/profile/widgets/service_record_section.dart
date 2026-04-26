import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Profile SERVICE RECORD section.
///
/// Sits ABOVE bio stats. Two parts:
///
///   (a) Letterhead + ladder vertical list. Earned rungs render
///       with full-color insignia + earned date. Locked rungs
///       render dimmed insignia + gate description.
///
///   (b) Lifetime stats row — deployments completed / service days
///       (from auth.users.created_at) / total volume (kg).
class ServiceRecordSection extends ConsumerWidget {
  const ServiceRecordSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ladder = RankService.instance.getLadder();
    final lifetime = _readLifetimeStats();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter, 14, AppSpacing.gutter, 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WardLetterhead(
            eyebrow: 'SERVICE · RECORD',
            title: 'Lifetime ladder',
            padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
            divider: true,
          ),
          for (final entry in ladder)
            _LadderRow(entry: entry),
          const SizedBox(height: 14),
          _LifetimeStatsRow(stats: lifetime),
        ],
      ),
    );
  }

  _LifetimeStats _readLifetimeStats() {
    final user = SupabaseService.instance.currentUser;
    final progress = UserRepository.instance.getProgress() ?? {};
    final repo = WorkoutRepository.instance;

    int serviceDays = 0;
    if (user != null) {
      final createdAt = DateTime.tryParse(user.createdAt);
      if (createdAt != null) {
        serviceDays = DateTime.now().difference(createdAt).inDays;
      }
    }

    final deployments =
        (progress['deployments_complete'] as int?) ?? 0;

    // Sum lifetime volume across all exercise logs in Hive.
    double totalVolumeKg = 0;
    final volumes = repo.getAllExerciseLogKeysForLifetimeSum();
    for (final v in volumes) {
      totalVolumeKg += v;
    }

    return _LifetimeStats(
      deployments: deployments,
      serviceDays: serviceDays,
      totalVolumeKg: totalVolumeKg.round(),
    );
  }
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({required this.entry});

  final LadderEntryView entry;

  @override
  Widget build(BuildContext context) {
    final dim = !entry.isEarned;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          RankInsignia(
            rankCode: entry.entry.code,
            size: 28,
            dimmed: dim,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.entry.displayName.toUpperCase(),
                  style: AppTypography.mono.copyWith(
                    fontSize: 11,
                    letterSpacing: 1.3,
                    color: dim ? AppColors.textMute : AppColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.isEarned
                      ? (entry.earnedAt != null
                          ? 'Earned ${_fmtDate(entry.earnedAt!)}'
                          : 'Earned')
                      : (entry.gateText ?? 'Locked'),
                  style: AppTypography.bodyS.copyWith(
                    color: dim ? AppColors.textGhost : AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _LifetimeStats {
  final int deployments;
  final int serviceDays;
  final int totalVolumeKg;
  const _LifetimeStats({
    required this.deployments,
    required this.serviceDays,
    required this.totalVolumeKg,
  });
}

class _LifetimeStatsRow extends StatelessWidget {
  const _LifetimeStatsRow({required this.stats});
  final _LifetimeStats stats;

  @override
  Widget build(BuildContext context) {
    return WardCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(child: _stat('DEPLOYMENTS', '${stats.deployments}')),
            Container(width: 1, height: 28, color: AppColors.line2),
            Expanded(child: _stat('SERVICE DAYS', '${stats.serviceDays}')),
            Container(width: 1, height: 28, color: AppColors.line2),
            Expanded(
              child: _stat(
                'TOTAL VOLUME',
                '${stats.totalVolumeKg} kg',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTypography.mono.copyWith(
            fontSize: 9,
            letterSpacing: 1.2,
            color: AppColors.textMute,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.h3.copyWith(
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
