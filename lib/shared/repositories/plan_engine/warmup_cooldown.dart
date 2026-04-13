import 'models.dart';
import 'superset_pairer.dart';

/// Stage 7: Attaches warm-up and cool-down to every workout day.
///
/// Extracted from V2 _WarmupCooldownSelector — logic is identical.
class WarmupCooldownSelector {
  /// General cardio options (bodyweight — always available).
  static const _bodyweightCardio = ['Spot Jogging', 'Jumping Jacks'];

  /// Additional cardio options when user has gym equipment.
  static const _gymCardio = ['Jump Rope', 'Cycling (Stationary)', 'Running (Treadmill)'];

  /// Dynamic warm-up exercises per dayType, by experience tier.
  static const _dynamicWarmup = <String, Map<String, List<String>>>{
    'push': {
      'beginner': ['Arm Circles', 'Torso Twists', 'Wall Push Up'],
      'advanced': ['Arm Circles', 'Push Up', 'Band Pull Apart'],
    },
    'pull': {
      'beginner': ['Arm Circles', 'Wrist Rotations', 'Neck Rotations'],
      'advanced': ['Arm Circles', 'Dead Hang', 'Neck Rotations'],
    },
    'legs': {
      'beginner': ['High Knees', 'Leg Swings', 'Hip Circles'],
      'advanced': ['High Knees', 'Baithak (Hindu Squat)', 'Leg Swings'],
    },
    'upper': {
      'beginner': ['Arm Circles', 'Torso Twists', 'Wrist Rotations'],
      'advanced': ['Arm Circles', 'Push Up', 'Dead Hang'],
    },
    'full_body': {
      'beginner': ['Jumping Jacks', 'Arm Circles', 'Hip Circles'],
      'advanced': ['High Knees', 'Push Up', 'Baithak (Hindu Squat)'],
    },
    'shoulders_arms': {
      'beginner': ['Arm Circles', 'Wrist Rotations', 'Neck Rotations'],
      'advanced': ['Arm Circles', 'Wrist Rotations', 'Band Pull Apart'],
    },
  };

  /// Static stretch cool-down exercises per dayType.
  static const _cooldownStretches = <String, List<String>>{
    'push': ['Chest Doorway Stretch', 'Cross-body Shoulder Stretch', 'Overhead Stretch'],
    'pull': ['Standing Toe Touch', 'Cross-body Shoulder Stretch', 'Side Bend Stretch'],
    'legs': ['Standing Quad Stretch', 'Standing Toe Touch', 'Side Bend Stretch'],
    'upper': ['Chest Doorway Stretch', 'Standing Toe Touch', 'Cross-body Shoulder Stretch'],
    'full_body': ['Standing Toe Touch', 'Standing Quad Stretch', 'Chest Doorway Stretch'],
    'shoulders_arms': ['Cross-body Shoulder Stretch', 'Overhead Stretch', 'Deep Breathing'],
  };

  /// Attach warm-up and cool-down to every WorkoutDay in every WeekPlan.
  static List<WeekPlan> attach(
    List<WeekPlan> weeks,
    String effectiveExp,
    List<String> equipmentList,
  ) {
    final isAdvanced = effectiveExp != 'beginner';
    final hasGymEquipment = equipmentList.any(
        (e) => e.toLowerCase().contains('gym') || e.toLowerCase().contains('full'));

    final cardioPool = [..._bodyweightCardio];
    if (hasGymEquipment) cardioPool.addAll(_gymCardio);

    return weeks.map((week) {
      final days = week.workoutDays.asMap().entries.map((entry) {
        final dayIndex = entry.key;
        final day = entry.value;
        final dayType = SupersetPairer.inferDayType(day);

        // --- WARM-UP ---
        final warmup = <PlannedExercise>[];

        final cardioName = cardioPool[dayIndex % cardioPool.length];
        warmup.add(_timedExercise(cardioName, '300', 'warmup'));

        final tier = isAdvanced ? 'advanced' : 'beginner';
        final dynamicMap = _dynamicWarmup[dayType] ?? _dynamicWarmup['upper']!;
        final dynamicList = dynamicMap[tier] ?? dynamicMap['beginner']!;
        for (final name in dynamicList) {
          warmup.add(_warmupExercise(name));
        }

        // --- COOL-DOWN ---
        final cooldown = <PlannedExercise>[];

        cooldown.add(_timedExercise('Slow Walking', '300', 'cooldown'));

        final stretches = _cooldownStretches[dayType] ?? _cooldownStretches['upper']!;
        for (final name in stretches) {
          cooldown.add(_timedExercise(name, '30', 'cooldown'));
        }

        return WorkoutDay(
          dayNumber: day.dayNumber,
          name: day.name,
          focus: day.focus,
          exercises: day.exercises,
          warmup: warmup,
          cooldown: cooldown,
          finisher: day.finisher,
        );
      }).toList();

      return WeekPlan(
        weekNumber: week.weekNumber,
        weekInPhase: week.weekInPhase,
        overloadNotes: week.overloadNotes,
        weekCharacter: week.weekCharacter,
        workoutDays: days,
      );
    }).toList();
  }

  static PlannedExercise _timedExercise(String name, String duration, String category) {
    return PlannedExercise(
      exerciseId: name,
      exerciseName: name,
      loggingType: 'timed',
      sets: 1,
      reps: '${duration}s',
      restSeconds: 0,
      category: category,
    );
  }

  static PlannedExercise _warmupExercise(String name) {
    const activationExercises = {
      'Push Up', 'Wall Push Up', 'Baithak (Hindu Squat)', 'Band Pull Apart',
    };
    if (activationExercises.contains(name)) {
      return PlannedExercise(
        exerciseId: name,
        exerciseName: name,
        loggingType: 'bodyweight_reps',
        sets: 1,
        reps: '10',
        restSeconds: 0,
        category: 'warmup',
      );
    }

    if (name == 'Dead Hang') {
      return _timedExercise(name, '30', 'warmup');
    }

    const durationMap = <String, String>{
      'Arm Circles': '60',
      'Neck Rotations': '30',
      'Torso Twists': '60',
      'Hip Circles': '60',
      'Leg Swings': '60',
      'Wrist Rotations': '30',
      'Ankle Rotations': '30',
      'Jumping Jacks': '60',
      'High Knees': '60',
      'Butt Kicks': '60',
      'Spot Jogging': '60',
    };
    final dur = durationMap[name] ?? '60';
    return _timedExercise(name, dur, 'warmup');
  }
}
