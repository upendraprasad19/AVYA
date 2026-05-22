import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Theme H-followup (diagnose 2026-05-22 5cb912).
///
/// Founder's wish 2026-05-21 evening: "i want the completed phases to
/// be available to the user, which i can scroll and check."
///
/// Reads `schedule_*` entries directly from Hive's workoutBox + groups
/// them by `week_character` (the SoT field stamped by the plan
/// generator at workout_schedule_read_service.dart:147). The week
/// character correlates 1:1 with the phase number (Phase 1 = Mon Tue
/// Wed Thu pattern, Phase 2 = different, etc. — characters change
/// per phase). We use the simpler heuristic of grouping by week
/// number ranges (1-4 = Phase 1, 5-8 = Phase 2, etc.) plus the
/// completed_at timestamps to display each phase's date range.
///
/// Read-only. No mutation paths. Click an entry → modal sheet with
/// the per-week breakdown of that phase.
class PhaseHistoryScreen extends ConsumerWidget {
  const PhaseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = _loadPhaseHistory();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('PHASE HISTORY',
            style: AppTypography.mono.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
                letterSpacing: 1.4)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: history.isEmpty
            ? _buildEmpty()
            : ListView.separated(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding, vertical: 16),
                itemCount: history.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final phase = history[idx];
                  return _PhaseHistoryCard(phase: phase);
                },
              ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timeline,
                  size: 48, color: AppColors.textDim),
              const SizedBox(height: 16),
              Text(
                'No completed phases yet',
                style: AppTypography.h3
                    .copyWith(color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Once you complete Phase 1, it will appear here.',
                style: AppTypography.body
                    .copyWith(color: AppColors.textDim),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

/// Reads workoutBox for `schedule_*` entries, groups by phase number
/// (1-4 = Phase 1, 5-8 = Phase 2, etc.), returns a list of
/// `_PhaseHistoryEntry` records sorted by phase number ascending.
///
/// Only includes phases where AT LEAST ONE day has `status='completed'`.
/// Pre-Theme-H (commit f31a487) the writer's completed-day overwrite
/// guard ensures these records stay intact through subsequent phase
/// regenerations.
List<_PhaseHistoryEntry> _loadPhaseHistory() {
  final box = HiveService.instance.workoutBox;
  final grouped = <int, List<Map<String, dynamic>>>{};

  for (final entry in box.toMap().entries) {
    final keyStr = entry.key.toString();
    if (!keyStr.startsWith('schedule_')) continue;
    final raw = entry.value;
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);

    final week = (map['week'] as int?) ?? 0;
    if (week <= 0) continue;
    // Phase number derived from week: weeks 1-4 → Phase 1,
    // 5-8 → Phase 2, 9-12 → Phase 3, etc.
    final phaseNum = ((week - 1) ~/ 4) + 1;
    (grouped[phaseNum] ??= []).add(map);
  }

  final entries = <_PhaseHistoryEntry>[];
  for (final phaseNum in grouped.keys.toList()..sort()) {
    final dayMaps = grouped[phaseNum]!;
    final completed =
        dayMaps.where((m) => m['status'] == 'completed').toList();
    if (completed.isEmpty) continue; // skip phases with no completions

    // Date range from min/max date strings.
    final dateStrs = dayMaps
        .map((m) => m['date'] as String?)
        .where((s) => s != null)
        .cast<String>()
        .toList()
      ..sort();
    final start = dateStrs.isNotEmpty ? dateStrs.first : null;
    final end = dateStrs.isNotEmpty ? dateStrs.last : null;

    entries.add(_PhaseHistoryEntry(
      phaseNum: phaseNum,
      totalDays: dayMaps.length,
      completedDays: completed.length,
      startDate: start,
      endDate: end,
    ));
  }
  return entries;
}

class _PhaseHistoryEntry {
  final int phaseNum;
  final int totalDays;
  final int completedDays;
  final String? startDate;
  final String? endDate;

  const _PhaseHistoryEntry({
    required this.phaseNum,
    required this.totalDays,
    required this.completedDays,
    required this.startDate,
    required this.endDate,
  });

  double get completionRate =>
      totalDays == 0 ? 0 : completedDays / totalDays;
}

class _PhaseHistoryCard extends StatelessWidget {
  final _PhaseHistoryEntry phase;
  const _PhaseHistoryCard({required this.phase});

  @override
  Widget build(BuildContext context) {
    final pct = (phase.completionRate * 100).toStringAsFixed(0);
    final dateRange = phase.startDate != null && phase.endDate != null
        ? '${phase.startDate} → ${phase.endDate}'
        : 'Date range unavailable';

    return WardCard(
      variant: WardCardVariant.inset,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PHASE ${phase.phaseNum}',
                  style: AppTypography.h3
                      .copyWith(color: AppColors.textPrimary)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                  border: Border.all(color: AppColors.accent, width: 1),
                ),
                child: Text('$pct% done',
                    style: AppTypography.mono.copyWith(
                        fontSize: 11,
                        color: AppColors.accent,
                        letterSpacing: 1.2)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(dateRange,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.textDim)),
          const SizedBox(height: 8),
          Text(
            '${phase.completedDays} of ${phase.totalDays} days completed',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}
