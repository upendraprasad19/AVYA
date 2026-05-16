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

/// Profile RANK card.
///
/// Collapsed (default): shows current rank name + total workouts +
/// next-rank ETA. Tap the header to expand.
///
/// Expanded: reveals the full ladder list under a "SERVICE RECORD"
/// sub-label, plus the lifetime stats row (deployments / service days
/// / total volume).
class ServiceRecordSection extends ConsumerStatefulWidget {
  const ServiceRecordSection({super.key});

  @override
  ConsumerState<ServiceRecordSection> createState() =>
      _ServiceRecordSectionState();
}

class _ServiceRecordSectionState extends ConsumerState<ServiceRecordSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final current = RankService.instance.getCurrentRank();
    final next = RankService.instance.getNextRank();
    final ladder = RankService.instance.getLadder();
    final lifetime = _readLifetimeStats();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter, 0, AppSpacing.gutter, 0,
      ),
      child: WardCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Tappable header row ─────────────────────────────
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.card),
                bottom: Radius.circular(AppRadius.card),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Text(
                      'RANK',
                      style: AppTypography.mono.copyWith(
                        fontSize: 10,
                        letterSpacing: 1.6,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textDim,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),

            // ── Always-visible: current rank summary ────────────
            Container(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: _buildCurrentRankSummary(current, next),
            ),

            // ── Conditionally-visible: full ladder ──────────────
            if (_expanded) ...[
              Container(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Text(
                  'SERVICE RECORD',
                  style: AppTypography.mono.copyWith(
                    fontSize: 9,
                    letterSpacing: 1.4,
                    color: AppColors.textMute,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final entry in ladder)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                  child: _LadderRow(entry: entry),
                ),
              const SizedBox(height: 10),
              Container(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: _LifetimeStatsRow(stats: lifetime),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One-line (or two-line) current rank summary:
  ///   Current: "Seaman 2nd Class"
  ///   Subline:  "2 workouts · Next: Seaman 1st Class in ~5 workouts"
  ///   OR if at top rank: "2 workouts · Top rank achieved"
  Widget _buildCurrentRankSummary(RankInfo current, RankInfo? next) {
    final nextLabel = _nextRankLabel(next);

    return Row(
      children: [
        // audit-2026-05-16 E.11 — migrated from legacy RankInsignia.
        WardRankInsignia(
          rankCode: current.entry.code,
          size: 32,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current.entry.displayName.toUpperCase(),
                style: AppTypography.mono.copyWith(
                  fontSize: 11,
                  letterSpacing: 1.3,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (nextLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  nextLabel,
                  style: AppTypography.bodyS.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Tap hint chip
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            _expanded ? 'HIDE' : 'VIEW ALL',
            style: AppTypography.mono.copyWith(
              fontSize: 8,
              letterSpacing: 1.2,
              color: AppColors.textMute,
            ),
          ),
        ),
      ],
    );
  }

  String? _nextRankLabel(RankInfo? next) {
    if (next == null) return 'Top rank achieved';
    final name = next.entry.displayName;
    if (next.workoutsRemaining != null && next.workoutsRemaining! > 0) {
      return 'Next: $name in ~${next.workoutsRemaining} workouts';
    }
    if (next.daysUntilEligible != null && next.daysUntilEligible! > 0) {
      return 'Next: $name in ~${next.daysUntilEligible} days';
    }
    return 'Next: $name — almost there';
  }

  _LifetimeStats _readLifetimeStats() {
    final user = SupabaseService.instance.currentUser;
    final progress = UserRepository.instance.getProgress() ?? {};
    final repo = WorkoutRepository.instance;

    int serviceDays = 0;
    if (user != null) {
      final createdAt = DateTime.tryParse(user.createdAt);
      if (createdAt != null) {
        // B4: clamp to non-negative — createdAt can be a UTC timestamp
        // that, when compared to device local time, produces a negative
        // inDays value (clock skew or timezone mismatch).
        serviceDays = DateTime.now().difference(createdAt).inDays.clamp(0, 36500);
      }
    }

    final deployments = (progress['deployments_complete'] as int?) ?? 0;

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
          // audit-2026-05-16 E.11 — migrated from legacy RankInsignia.
          // `dimmed: dim` → `color: dim ? AppColors.textMute : null`
          // (legacy ringColor mapped to textMute.withAlpha(0.45);
          // textMute is the closest semantic match in the canonical palette).
          WardRankInsignia(
            rankCode: entry.entry.code,
            size: 28,
            color: dim ? AppColors.textMute : null,
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
    return Row(
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
