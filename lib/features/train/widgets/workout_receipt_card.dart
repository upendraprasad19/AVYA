import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/shareable_card.dart';
import '../providers/train_provider.dart';

// ── Category-specific taglines ───────────────────────────────────
const _taglinesPull = <String>[
  'Back wider than your comfort zone.',
  'Pulled more weight than your excuses.',
  'Lats loading... rows complete.',
  'Back day done. Posture improved by 1%.',
  'If rowing was easy, they\'d call it sitting.',
  'Deadlifts hit. Grip strength secured.',
  'The bar came up. So did you.',
  'Wide back energy activated.',
];

const _taglinesPush = <String>[
  'Chest pressed. Triceps fired. Mission complete.',
  'Push day: shoulders, ego, and reps — all up.',
  'Bench done. Pressing on.',
  'Pressed more than yesterday\'s bad decisions.',
  'Shoulders like boulders. Almost.',
  'OHP? Done. Respect? Earned.',
  'Chest day energy. Arm day regrets.',
  'Push it. Then push it some more.',
];

const _taglinesLegs = <String>[
  'Legs? Destroyed. Ego? Inflated.',
  'Squats done. Stairs now optional.',
  'Skipping leg day? Couldn\'t be me. (Today.)',
  'Ground shook. Quads spoke.',
  'Deadlift + Squat combo. The classic.',
  'Legs trained. Walking tomorrow: unlikely.',
  'Don\'t skip legs. You didn\'t.',
  'The squat rack was afraid of me today.',
];

const _taglinesCore = <String>[
  'Core locked in. Spine approved.',
  'Six-pack in progress. Beer not included.',
  'Abs worked. Excuses destroyed.',
  'Planked longer than my attention span.',
  'Core strong. Everything else negotiable.',
  'Crunched the numbers. And my abs.',
];

const _taglinesCardio = <String>[
  'Cardio done. Dignity optional.',
  'Ran from nothing. Felt great.',
  'Heart rate elevated. Life improved.',
  'Sweat is just fat crying. You made a lot cry today.',
  'Calories burned > Excuses made.',
  'Distance covered. Goals closer.',
];

const _taglinesGeneric = <String>[
  'Muscles confused. Gains secured.',
  'Gym done. Personality still under construction.',
  'Another day of being better than yesterday\'s lazy version.',
  'My therapist said lift heavy. So here we are.',
  'The only drama I need is in my set count.',
  'Protein shake incoming in 3... 2... 1...',
  'Not bad for someone who almost skipped today.',
  'Built different. Also built sore.',
  'Your workout is my warm-up. (Just kidding. I\'m dying.)',
  'Zero missed reps. Infinite missed calls.',
  'Did I PR? Maybe. Am I sore? Definitely.',
  'Coach said one more set. That was four sets ago.',
  'Crushed it like a protein bar wrapper.',
  'Rest days are for people without goals. (Jk rest is important.)',
  'One step closer to looking like my profile picture.',
  'Workout complete. Nap pending.',
  'Discipline hit. Brain still buffering.',
];

String _pickTagline(String workoutName) {
  final upper = workoutName.toUpperCase();
  final rng = Random();
  if (upper.contains('PULL') || upper.contains('BACK') ||
      upper.contains('ROW') || upper.contains('DEADLIFT') ||
      upper.contains('BICEP') || upper.contains('CURL')) {
    return _taglinesPull[rng.nextInt(_taglinesPull.length)];
  }
  if (upper.contains('PUSH') || upper.contains('CHEST') ||
      upper.contains('PRESS') || upper.contains('SHOULDER') ||
      upper.contains('TRICEP')) {
    return _taglinesPush[rng.nextInt(_taglinesPush.length)];
  }
  if (upper.contains('LEG') || upper.contains('SQUAT') ||
      upper.contains('LUNGE') || upper.contains('GLUTE') ||
      upper.contains('QUAD') || upper.contains('HAMSTRING') ||
      upper.contains('CALF')) {
    return _taglinesLegs[rng.nextInt(_taglinesLegs.length)];
  }
  if (upper.contains('CORE') || upper.contains('ABS') ||
      upper.contains('PLANK') || upper.contains('CRUNCH')) {
    return _taglinesCore[rng.nextInt(_taglinesCore.length)];
  }
  if (upper.contains('CARDIO') || upper.contains('RUN') ||
      upper.contains('HIIT') || upper.contains('JUMP')) {
    return _taglinesCardio[rng.nextInt(_taglinesCardio.length)];
  }
  return _taglinesGeneric[rng.nextInt(_taglinesGeneric.length)];
}

/// Data required to render a Workout Receipt card.
class WorkoutReceiptData {
  final DateTime date;
  final String workoutName;
  final int phase;
  final List<ReceiptExercise> exercises;
  final double totalVolumeKg;
  final int totalSets;
  final List<String> prs;
  final int streakWeeks;

  const WorkoutReceiptData({
    required this.date,
    required this.workoutName,
    this.phase = 1,
    required this.exercises,
    required this.totalVolumeKg,
    required this.totalSets,
    this.prs = const [],
    this.streakWeeks = 0,
  });

  int get totalExercises => exercises.length;

  /// Build from ActiveWorkoutData after completion.
  factory WorkoutReceiptData.fromActiveWorkout(ActiveWorkoutData data) {
    final now = DateTime.now();
    double totalVolume = 0;
    int totalSets = 0;
    final receiptExercises = <ReceiptExercise>[];

    for (int exIdx = 0; exIdx < data.exercises.length; exIdx++) {
      final ex = data.exercises[exIdx];
      final numSets = int.tryParse(ex.sets) ?? 3;
      final defaultReps = int.tryParse(ex.reps) ?? 10;

      double bestWeight = 0;
      int totalReps = 0;
      int completedSets = 0;

      // Scan for dynamically added sets beyond the template's prescribed count.
      int maxSet = numSets;
      for (final key in data.checkedSets.keys) {
        if (key.startsWith('$exIdx-')) {
          final s = int.tryParse(key.split('-').last) ?? 0;
          if (s + 1 > maxSet) maxSet = s + 1;
        }
      }

      for (int s = 0; s < maxSet; s++) {
        final key = '$exIdx-$s';
        if (data.checkedSets.containsKey(key)) {
          // Skip warm-up sets in volume
          if (data.warmUpSets.containsKey(key)) continue;
          completedSets++;
          final vals = data.setInputValues[key];
          final reps = vals?.reps ?? defaultReps;
          final weight = vals?.weight ?? 0.0;

          // Per-set volume: reps × weight for this specific set
          totalVolume += reps * weight;

          if (weight > bestWeight) bestWeight = weight;
          totalReps += reps;
        }
      }

      totalSets += completedSets;
      receiptExercises.add(ReceiptExercise(
        name: ex.name,
        sets: completedSets > 0 ? completedSets : numSets,
        reps: completedSets > 0 ? (totalReps / completedSets.clamp(1, 999)).round() : defaultReps,
        weightKg: bestWeight,
        loggingType: ex.loggingType,
      ));
    }

    // Deduplicate: if the plan contains the same exercise twice (e.g. superset
    // added twice), merge them into one entry — sum sets, max weight, avg reps.
    final seen = <String, ReceiptExercise>{};
    for (final ex in receiptExercises) {
      final key = ex.name.toLowerCase().trim();
      final existing = seen[key];
      if (existing == null) {
        seen[key] = ex;
      } else {
        final mergedSets = existing.sets + ex.sets;
        final maxWeight = existing.weightKg > ex.weightKg
            ? existing.weightKg
            : ex.weightKg;
        final avgReps = mergedSets > 0
            ? ((existing.reps * existing.sets + ex.reps * ex.sets) / mergedSets).round()
            : existing.reps;
        seen[key] = ReceiptExercise(
          name: existing.name,
          sets: mergedSets,
          reps: avgReps,
          weightKg: maxWeight,
          loggingType: existing.loggingType,
        );
      }
    }

    return WorkoutReceiptData(
      date: now,
      workoutName: data.workoutDay?.name ?? 'WORKOUT',
      exercises: seen.values.toList(),
      totalVolumeKg: totalVolume,
      totalSets: totalSets,
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
    final tagline = _pickTagline(data.workoutName);

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
    // "22 sets · 6 exercises" label replaces duration
    final setsExLabel = '${data.totalSets} sets \u00b7 ${data.totalExercises} exercises';

    return Row(
      children: [
        _summaryChip(
          '${data.totalVolumeKg.toStringAsFixed(0)} kg',
          'VOLUME',
        ),
        const SizedBox(width: 12),
        _summaryChip(setsExLabel, 'WORKOUT'),
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
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
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
