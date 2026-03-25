import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import '../providers/train_provider.dart';

/// Expandable day card matching the mockup:
/// - Collapsed: day number badge, workout name, subtitle, chevron
/// - Expanded: cyan border, exercise list with numbered badges, "Log This Workout" button
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: const Color(0xFF0e1219),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isExpanded
                ? AppColors.accent.withValues(alpha: 0.35)
                : const Color(0xFF1c2535),
          ),
        ),
        child: Column(
          children: [
            // Collapsed row (always visible)
            GestureDetector(
              onTap: () =>
                  ref.read(expandedDayProvider.notifier).toggle(dayIndex),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    // Day number badge
                    _DayNumberBadge(
                      dayNumber: dayData.dayNumber,
                      isExpanded: isExpanded,
                    ),
                    const SizedBox(width: 12),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dayData.name,
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dayData.isDone
                                ? '\u2713 ${dayData.subtitle}'
                                : dayData.subtitle,
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                              color: dayData.isDone
                                  ? AppColors.green
                                  : AppColors.textSecondary,
                            ),
                          ),
                          if (dayData.dateLabel != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              dayData.dateLabel!,
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Chevron
                    AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        '\u203a',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: isExpanded
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
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
        // Divider
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          color: AppColors.accent.withValues(alpha: 0.1),
        ),

        if (dayData.isRest)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '\u{1f9d8} Rest & recover. Stretch or walk.',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else ...[
          // Exercise list
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

                // Log This Workout button
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: onStartWorkout,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            AppColors.accent.withValues(alpha: 0.08),
                        border: Border.all(
                          color:
                              AppColors.accent.withValues(alpha: 0.2),
                        ),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Center(
                        child: Text(
                          '\u{1f4dd} Log This Workout',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Day number badge: 38x38 with "DAY" label on top, number below.
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
        color: isExpanded
            ? AppColors.accent.withValues(alpha: 0.12)
            : const Color(0xFF161d28),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'DAY',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            '$dayNumber',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: isExpanded ? AppColors.accent : AppColors.textPrimary,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Single exercise row inside expanded day card.
/// Uses Consumer to access lastPerformanceProvider for ghost line.
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF161d28),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Number badge
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Exercise info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    // Last performance ghost line
                    if (lastPerf.hasData && lastPerf.lastWeight != null && lastPerf.lastWeight! > 0) ...[
                      const SizedBox(height: 1),
                      Text(
                        'Last: ${lastPerf.lastWeight!.toStringAsFixed(1)}kg \u00d7 ${lastPerf.lastReps ?? 0}',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      'Rest: ${exercise.rest}',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Sets x Reps + Weight
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${exercise.sets} \u00d7 ${exercise.reps}',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    exercise.weight,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
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
