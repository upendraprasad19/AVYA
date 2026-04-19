import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/train_provider.dart';

class StatsGrid extends ConsumerWidget {
  const StatsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prs = _loadPRs(ref);
    final hasData = prs.values.any((pr) => pr.current > 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR STATS',
            style: AppTypography.mono.copyWith(letterSpacing: 2),
          ),
          const SizedBox(height: AppSpacing.inlineGap),

          if (!hasData)
            _buildNoDataAlert()
          else ...[
            // Dynamic 2×2 grid — shows key lifts or top exercises
            _buildDynamicGrid(prs),
          ],
          const SizedBox(height: 10),

          // View All Exercise PRs button
          WardButton(
            label: 'VIEW ALL EXERCISE PRS',
            onPressed: () => _showAllPRsSheet(context, ref),
            variant: WardButtonVariant.outline,
            trailing: const Icon(Icons.arrow_forward,
                size: 14, color: AppColors.accent),
          ),
        ],
      ),
    );
  }

  /// Derive display unit from exercise logging type.
  static String _unitForLoggingType(String loggingType) {
    switch (loggingType) {
      case 'weight_reps':
      case 'weighted_bodyweight':
        return 'kg';
      case 'bodyweight_reps':
        return 'reps';
      case 'timed':
        return 's';
      case 'cardio':
      case 'distance':
        return 'km';
      default:
        return 'kg';
    }
  }

  /// Build adaptive grid from the PR map — adapts to 1-4 exercises.
  /// Keys may be standard lift names (bench, squat) or actual exercise names.
  Widget _buildDynamicGrid(Map<String, _PRData> prs) {
    const standardLabels = {
      'bench': 'BENCH PRESS',
      'squat': 'SQUAT',
      'deadlift': 'DEADLIFT',
      'ohp': 'OHP',
    };

    final entries = prs.entries.where((e) => e.value.current > 0).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    Widget cardFor(MapEntry<String, _PRData> e, {bool expanded = true}) {
      final std = standardLabels[e.key];
      // Title-case exercise names: "dumbbell curl" → "Dumbbell Curl"
      final label = std ??
          e.key
              .split(' ')
              .map((w) =>
                  w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
              .join(' ')
              .toUpperCase();
      final child = _StatCard.fromPR(label, e.value);
      return expanded ? Expanded(child: child) : child;
    }

    // Adaptive layout: 1→full, 2→row, 3→2+1, 4→2+2
    if (entries.length == 1) {
      return Row(children: [cardFor(entries[0])]);
    }
    if (entries.length == 2) {
      return Row(children: [
        cardFor(entries[0]),
        const SizedBox(width: AppSpacing.inlineGap),
        cardFor(entries[1]),
      ]);
    }
    if (entries.length == 3) {
      return Column(children: [
        Row(children: [
          cardFor(entries[0]),
          const SizedBox(width: AppSpacing.inlineGap),
          cardFor(entries[1]),
        ]),
        const SizedBox(height: AppSpacing.inlineGap),
        Row(children: [cardFor(entries[2])]),
      ]);
    }
    // 4+
    return Column(children: [
      Row(children: [
        cardFor(entries[0]),
        const SizedBox(width: AppSpacing.inlineGap),
        cardFor(entries[1]),
      ]),
      const SizedBox(height: AppSpacing.inlineGap),
      Row(children: [
        cardFor(entries[2]),
        const SizedBox(width: AppSpacing.inlineGap),
        cardFor(entries[3]),
      ]),
    ]);
  }

  Widget _buildNoDataAlert() {
    return WardCard(
      variant: WardCardVariant.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'NO DATA · LOG A WORKOUT TO UNLOCK',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'No stats yet',
            style: AppTypography.h3,
          ),
          const SizedBox(height: 4),
          Text(
            'Complete your first workout to start tracking PRs',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  /// Reads workout_logs via provider so the grid refreshes after workout completion.
  /// Uses allExercisePRsProvider (same as Home screen) for consistent data,
  /// falling back to the 4 key lifts grid if the user has bench/squat/deadlift/OHP data.
  Map<String, _PRData> _loadPRs(WidgetRef ref) {
    // First try the key lifts (legacy behavior)
    final rawPRs = ref.watch(workoutStatsProvider);
    final hasKeyLifts = rawPRs.values.any((v) => (v['current'] ?? 0) > 0);
    if (hasKeyLifts) {
      return rawPRs.map((key, value) => MapEntry(
            key,
            _PRData(
              current: value['current'] ?? 0,
              previous: value['previous'] ?? 0,
            ),
          ));
    }

    // Fallback: use top 4 from ALL exercise PRs (same source as Home screen)
    final allPRs = ref.watch(allExercisePRsProvider);
    final top4 = allPRs.where((pr) => pr.bestValue > 0).take(4).toList();
    if (top4.isEmpty) {
      // Return empty key lifts so hasData check fails → shows empty state
      return rawPRs.map((key, value) => MapEntry(
            key, _PRData(current: 0, previous: 0)));
    }

    // Build a dynamic map using exercise names as keys, with correct unit
    final result = <String, _PRData>{};
    for (final pr in top4) {
      result[pr.exerciseName] = _PRData(
        current: pr.bestValue,
        previous: 0,
        unit: _unitForLoggingType(pr.loggingType),
      );
    }
    return result;
  }

  void _showAllPRsSheet(BuildContext context, WidgetRef ref) {
    final allPRs = ref.read(allExercisePRsProvider);

    if (allPRs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Start logging workouts to see your PRs!',
            style: AppTypography.bodySm.copyWith(color: AppColors.bgDeep),
          ),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sharp),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.card),
            ),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events,
                        size: 16, color: AppColors.proGold),
                    const SizedBox(width: 8),
                    Text(
                      'ALL EXERCISE PRS',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    WardChip(
                      label: '${allPRs.length} EXERCISES',
                      tone: WardChipTone.gold,
                    ),
                  ],
                ),
              ),
              const WardRule(margin: EdgeInsets.zero),
              // List
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: allPRs.length,
                  separatorBuilder: (_, _) =>
                      const WardRule(margin: EdgeInsets.zero),
                  itemBuilder: (_, i) {
                    final pr = allPRs[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.proGold,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sharp),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pr.exerciseName,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.h3.copyWith(
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  pr.formattedDate,
                                  style: AppTypography.monoXs.copyWith(
                                    color: AppColors.textDim,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            pr.formattedValue,
                            style: AppTypography.h2.copyWith(
                              fontSize: 18,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PRData {
  final double current;
  final double previous;
  final String unit; // kg, reps, s, km

  const _PRData(
      {required this.current, required this.previous, this.unit = 'kg'});

  String get changeText {
    if (current <= 0) return 'No data yet';
    final diff = current - previous;
    if (diff > 0 && previous > 0) {
      return '\u2191 ${diff.toStringAsFixed(1)} $unit this month';
    }
    if (previous > 0) return 'Last: ${previous.toStringAsFixed(0)} $unit';
    return 'First logged!';
  }

  Color get changeColor {
    if (current <= 0) return AppColors.textDim;
    final diff = current - previous;
    if (diff > 0 && previous > 0) return AppColors.ok;
    return AppColors.textDim;
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.change,
    required this.changeColor,
  });

  final String label;
  final String value;
  final String change;
  final Color changeColor;

  factory _StatCard.fromPR(String label, _PRData pr) {
    return _StatCard(
      label: label,
      value: pr.current > 0
          ? '${pr.current.toStringAsFixed(0)} ${pr.unit}'
          : '—',
      change: pr.changeText,
      changeColor: pr.changeColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              letterSpacing: 1.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.h2.copyWith(
              color: AppColors.accent,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            change,
            style: AppTypography.bodySm.copyWith(color: changeColor),
          ),
        ],
      ),
    );
  }
}
