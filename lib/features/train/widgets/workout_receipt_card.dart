import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/shareable_card.dart';
import '../providers/train_provider.dart';

// ── Sarcastic taglines (rotated randomly) ───────────────────────
const _taglines = <String>[
  'Muscles confused. Gains secured.',
  'Sweat is just fat crying. You made a lot cry today.',
  'Gym done. Personality still under construction.',
  'Another day of being better than yesterday\u2019s lazy version.',
  'My therapist said lift heavy. So here we are.',
  'The only drama I need is in my set count.',
  'Protein shake incoming in 3... 2... 1...',
  'Lifted more than my ex\u2019s expectations.',
  'Legs? Destroyed. Ego? Inflated.',
  'The gym doesn\u2019t ask me stupid questions.',
  'Not bad for someone who almost skipped today.',
  'Built different. Also built sore.',
  'Your workout is my warm-up. (Just kidding. I\u2019m dying.)',
  'Zero missed reps. Infinite missed calls.',
  'Gym crush noticed me. Or it was the mirror. Either way.',
  'If being sore was a flex, I\u2019d be famous.',
  'Skipping leg day? Couldn\u2019t be me. (Today.)',
  'Did I PR? Maybe. Am I sore? Definitely.',
  'Coach said one more set. That was four sets ago.',
  'Calories burned > Excuses made.',
  'Crushed it like a protein bar wrapper.',
  'Rest days are for people without goals. (Jk rest is important.)',
  'One step closer to looking like my profile picture.',
  'Workout complete. Nap pending.',
  'Discipline hit. Brain still buffering.',
];

/// Data required to render a Workout Receipt card.
class WorkoutReceiptData {
  final DateTime date;
  final String workoutName;
  final int phase;
  final List<ReceiptExercise> exercises;
  final double totalVolumeKg;
  final int totalSets;
  final String duration;
  final List<String> prs;
  final int streakWeeks;

  const WorkoutReceiptData({
    required this.date,
    required this.workoutName,
    this.phase = 1,
    required this.exercises,
    required this.totalVolumeKg,
    required this.totalSets,
    required this.duration,
    this.prs = const [],
    this.streakWeeks = 0,
  });

  /// Build from ActiveWorkoutData after completion.
  factory WorkoutReceiptData.fromActiveWorkout(ActiveWorkoutData data) {
    final now = DateTime.now();
    double totalVolume = 0;
    int totalSets = 0;
    final receiptExercises = <ReceiptExercise>[];

    for (final ex in data.exercises) {
      final sets = int.tryParse(ex.sets) ?? 3;
      final reps = int.tryParse(ex.reps) ?? 10;
      final weight =
          double.tryParse(ex.weight.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      totalSets += sets;
      totalVolume += sets * reps * weight;
      receiptExercises.add(ReceiptExercise(
        name: ex.name,
        sets: sets,
        reps: reps,
        weightKg: weight,
        loggingType: ex.loggingType,
      ));
    }

    return WorkoutReceiptData(
      date: now,
      workoutName: data.workoutDay?.name ?? 'WORKOUT',
      exercises: receiptExercises,
      totalVolumeKg: totalVolume,
      totalSets: totalSets,
      duration: data.timerFormatted,
      prs: data.detectedPRs,
    );
  }
}

class ReceiptExercise {
  final String name;
  final int sets;
  final int reps;
  final double weightKg;
  final String loggingType;

  const ReceiptExercise({
    required this.name,
    required this.sets,
    required this.reps,
    required this.weightKg,
    this.loggingType = 'weight_reps',
  });
}

/// Workout Receipt Card — rendered inside a ShareableCard wrapper.
///
/// Tier: FREE for all users.
class WorkoutReceiptCard extends StatelessWidget {
  final WorkoutReceiptData data;
  final GlobalKey repaintKey;

  const WorkoutReceiptCard({
    super.key,
    required this.data,
    required this.repaintKey,
  });

  @override
  Widget build(BuildContext context) {
    final tagline = _taglines[Random().nextInt(_taglines.length)];

    return ShareableCard(
      repaintKey: repaintKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Date row
            _buildDateRow(),
            const SizedBox(height: 10),

            // Workout title
            _buildTitle(),
            const SizedBox(height: 14),

            // Exercise list
            ..._buildExerciseRows(),
            const SizedBox(height: 12),

            // Divider
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 12),

            // Summary row
            _buildSummaryRow(),

            // PRs
            if (data.prs.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildPRSection(),
            ],

            // Streak badge
            if (data.streakWeeks > 0) ...[
              const SizedBox(height: 10),
              _buildStreakBadge(),
            ],

            // Tagline
            const SizedBox(height: 14),
            Text(
              tagline,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const monthNames = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final dayName = dayNames[data.date.weekday - 1];
    final monthName = monthNames[data.date.month - 1];

    return Text(
      '$dayName, ${data.date.day} $monthName ${data.date.year}',
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      '${data.workoutName} \u00b7 PHASE ${data.phase}',
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
        letterSpacing: 0.5,
      ),
    );
  }

  List<Widget> _buildExerciseRows() {
    return data.exercises.map((ex) {
      final detail = _exerciseDetail(ex);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                ex.name,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              detail,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  String _exerciseDetail(ReceiptExercise ex) {
    switch (ex.loggingType) {
      case 'bodyweight_reps':
        return '${ex.sets}\u00d7${ex.reps}';
      case 'timed':
        return '${ex.sets}\u00d7${ex.reps}s';
      case 'cardio':
        return '${ex.reps} min';
      case 'distance':
        return '${ex.reps} km';
      case 'weighted_bodyweight':
        return '${ex.sets}\u00d7${ex.reps} +${ex.weightKg.toStringAsFixed(0)}kg';
      default: // weight_reps
        if (ex.weightKg > 0) {
          return '${ex.sets}\u00d7${ex.reps}\u00d7${ex.weightKg.toStringAsFixed(0)}kg';
        }
        return '${ex.sets}\u00d7${ex.reps}';
    }
  }

  Widget _buildSummaryRow() {
    return Row(
      children: [
        _summaryChip(
          '${data.totalVolumeKg.toStringAsFixed(0)} kg',
          'VOLUME',
        ),
        const SizedBox(width: 12),
        _summaryChip('${data.totalSets}', 'SETS'),
        const SizedBox(width: 12),
        _summaryChip(data.duration, 'DURATION'),
      ],
    );
  }

  Widget _summaryChip(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPRSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: AppColors.accent, size: 14),
              const SizedBox(width: 4),
              Text(
                'PERSONAL RECORDS',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...data.prs.map((pr) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  pr,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStreakBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentTint,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department,
              color: AppColors.accent, size: 14),
          const SizedBox(width: 4),
          Text(
            '${data.streakWeeks} WEEK STREAK',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.accent,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
