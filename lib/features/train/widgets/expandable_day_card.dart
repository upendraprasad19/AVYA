import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/train_provider.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';

/// Expandable day card matching the Wardroom mockup:
/// - Collapsed: day tile, workout name, subtitle, chevron
/// - Expanded: gold border, exercise list, "Log This Workout" slab
/// - Rest days: rest message
class ExpandableDayCard extends ConsumerWidget {
  final WorkoutDayData dayData;
  final int dayIndex;
  final VoidCallback onStartWorkout;

  const ExpandableDayCard({
    super.key,
    required this.dayData,
    required this.dayIndex,
    required this.onStartWorkout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expandedDay = ref.watch(expandedDayProvider);
    final isExpanded = expandedDay == dayIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isExpanded
                ? AppColors.accent.withValues(alpha: 0.35)
                : AppColors.line2,
          ),
        ),
        child: Column(
          children: [
            // Collapsed row
            GestureDetector(
              onTap: () =>
                  ref.read(expandedDayProvider.notifier).toggle(dayIndex),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    _DayNumberBadge(
                      dayNumber: dayData.dayNumber,
                      isExpanded: isExpanded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dayData.name,
                            style: AppTypography.h3,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dayData.isDone
                                ? '\u2713 ${dayData.subtitle}'
                                : dayData.subtitle,
                            style: AppTypography.bodySm.copyWith(
                              color: dayData.isDone
                                  ? AppColors.ok
                                  : AppColors.textDim,
                            ),
                          ),
                          if (dayData.dateLabel != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              dayData.dateLabel!.toUpperCase(),
                              style: AppTypography.monoXs.copyWith(
                                color: AppColors.textMute,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: isExpanded
                            ? AppColors.accent
                            : AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Expanded panel
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: _buildExpandedPanel(),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPanel() {
    return Column(
      children: [
        const WardRule(margin: EdgeInsets.symmetric(horizontal: 14)),
        if (dayData.isRest)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Rest & recover. Stretch or walk.',
              style: AppTypography.body.copyWith(color: AppColors.textDim),
              textAlign: TextAlign.center,
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              children: [
                ...dayData.exercises.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final exercise = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ExerciseRow(
                      index: idx,
                      exercise: exercise,
                    ),
                  );
                }),
                const SizedBox(height: 4),
                WardButton(
                  label: 'LOG THIS WORKOUT',
                  onPressed: onStartWorkout,
                  variant: WardButtonVariant.outline,
                  size: WardButtonSize.small,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Day number tile: 38x38 inset rail with Mono "DAY" cap and Fraunces number.
class _DayNumberBadge extends StatelessWidget {
  final int dayNumber;
  final bool isExpanded;

  const _DayNumberBadge({required this.dayNumber, required this.isExpanded});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isExpanded ? AppColors.accentSoft : AppColors.bgRaise,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'DAY',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              fontSize: 7,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            '$dayNumber',
            style: AppTypography.h3.copyWith(
              color: isExpanded ? AppColors.accent : AppColors.textPrimary,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

/// Single exercise row inside expanded day card.
class _ExerciseRow extends StatelessWidget {
  final int index;
  final ExerciseData exercise;

  const _ExerciseRow({required this.index, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final lastPerf = ref.watch(lastPerformanceProvider(exercise.name));

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgRaise,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              // The plate replaces the index badge — see exercise_card.dart.
              ExercisePlateThumb(
                exerciseName: exercise.name,
                size: 44,
                onTap: () => ExercisePlateSheet.show(context, exercise.name),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (lastPerf.hasData &&
                        lastPerf.lastWeight != null &&
                        lastPerf.lastWeight! > 0) ...[
                      const SizedBox(height: 1),
                      Text(
                        'Last: ${lastPerf.lastWeight!.toStringAsFixed(1)}kg \u00d7 ${lastPerf.lastReps ?? 0}',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.textMute,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      'Rest: ${exercise.rest}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${exercise.sets} \u00d7 ${exercise.reps}',
                    style: AppTypography.h3.copyWith(
                      color: AppColors.accent,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    exercise.weight,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
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
