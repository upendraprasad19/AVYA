import 'models.dart';

/// Stage 1: Maps goal + daysPerWeek + experience → training split structure.
///
/// Beginner-aware: 3-4 day beginners get full-body splits.
/// Intermediate/advanced splits are unchanged from V2.
class SplitResolver {
  // Intensity profiles assigned per position within a week.
  static const _profiles3 = ['strength', 'hypertrophy', 'endurance'];
  static const _profiles4 = ['strength', 'hypertrophy', 'strength', 'endurance'];
  static const _profiles5 = ['strength', 'hypertrophy', 'endurance', 'strength', 'hypertrophy'];

  static List<DaySlot> select(String goal, int daysPerWeek, {String experienceLevel = 'intermediate'}) {
    // V3: Beginner-aware routing
    final isBeginner = experienceLevel == 'beginner';

    if (isBeginner && daysPerWeek <= 4) {
      return _getBeginnerFullBody(daysPerWeek, goal);
    }

    // Intermediate/advanced or beginner 5-6 days: use existing splits
    switch (daysPerWeek) {
      case 3:
        return _get3Day(goal);
      case 5:
        return _get5Day(goal);
      case 6:
        return _get6Day(goal);
      default:
        return _get4Day(goal);
    }
  }

  // ── V3: Beginner full-body splits (3-4 days) ─────────────────

  static List<DaySlot> _getBeginnerFullBody(int daysPerWeek, String goal) {
    final slots = <DaySlot>[
      DaySlot(
        name: 'Full Body A', focus: 'Push-focused — chest & shoulders lead',
        dayType: 'full_body', intensity: _profiles3[0],
        specsA: [CSpec('Push', 2), CSpec('Pull', 1), CSpec('Legs', 1), CSpec('Core', 1)],
      ),
      DaySlot(
        name: 'Full Body B', focus: 'Pull-focused — back & biceps lead',
        dayType: 'full_body', intensity: _profiles3[1],
        specsA: [CSpec('Push', 1), CSpec('Pull', 2), CSpec('Legs', 1), CSpec('Core', 1)],
      ),
      DaySlot(
        name: 'Full Body C', focus: 'Legs-focused — quads & glutes lead',
        dayType: 'full_body', intensity: _profiles3[2],
        specsA: [CSpec('Push', 1), CSpec('Pull', 1), CSpec('Legs', 2), CSpec('Core', 1)],
      ),
    ];

    if (daysPerWeek >= 4) {
      slots.add(DaySlot(
        name: 'Full Body D', focus: 'Balanced — core & conditioning',
        dayType: 'full_body', intensity: 'endurance',
        specsA: [CSpec('Push', 1), CSpec('Pull', 1), CSpec('Legs', 1), CSpec('Core', 2)],
      ));
    }

    return slots;
  }

  // ── 3-day splits ───────────────────────────────────────────────

  static List<DaySlot> _get3Day(String goal) {
    if (goal == 'lose_fat' || goal == 'general_fitness') {
      return [
        DaySlot(
          name: 'Full Body A', focus: 'Compound focus',
          dayType: 'full_body', intensity: _profiles3[0],
          specsA: [CSpec('Push', 2), CSpec('Pull', 2), CSpec('Legs', 1)],
        ),
        DaySlot(
          name: 'Full Body B', focus: 'Strength + cardio',
          dayType: 'full_body', intensity: _profiles3[1],
          specsA: [CSpec('Push', 2), CSpec('Pull', 2), CSpec('Legs', 1)],
        ),
        DaySlot(
          name: 'Full Body C', focus: 'Volume + core',
          dayType: 'full_body', intensity: _profiles3[2],
          specsA: [CSpec('Legs', 2), CSpec('Core', 2), CSpec('Cardio', 1)],
        ),
      ];
    }
    // build_muscle / strength
    return [
      DaySlot(
        name: 'Push + Core', focus: 'Chest, shoulders, triceps',
        dayType: 'push', intensity: _profiles3[0],
        specsA: [
          CSpec('Push', 3, target: ['Chest', 'Upper Chest', 'Lower Chest']),
          CSpec('Core', 2),
        ],
        specsB: [
          CSpec('Push', 3, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
          CSpec('Core', 2),
        ],
      ),
      DaySlot(
        name: 'Pull + Core', focus: 'Back, biceps',
        dayType: 'pull', intensity: _profiles3[1],
        specsA: [
          CSpec('Pull', 3, exclude: ['Biceps', 'Forearm']),
          CSpec('Core', 2),
        ],
        specsB: [
          CSpec('Pull', 3),
          CSpec('Core', 2),
        ],
      ),
      DaySlot(
        name: 'Legs', focus: 'Quads, hamstrings, glutes',
        dayType: 'legs', intensity: _profiles3[2],
        specsA: [CSpec('Legs', 5, target: ['Quad'])],
        specsB: [CSpec('Legs', 5, target: ['Hamstring', 'Glute'])],
      ),
    ];
  }

  // ── 4-day splits ───────────────────────────────────────────────

  static List<DaySlot> _get4Day(String goal) {
    if (goal == 'build_muscle') {
      return [
        DaySlot(
          name: 'Push', focus: 'Chest, shoulders, triceps',
          dayType: 'push', intensity: _profiles4[0],
          specsA: [
            CSpec('Push', 4, target: ['Chest', 'Upper Chest', 'Lower Chest']),
            CSpec('Push', 2, target: ['Triceps']),
          ],
          specsB: [
            CSpec('Push', 3, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            CSpec('Push', 2, target: ['Triceps']),
            CSpec('Push', 1, target: ['Chest']),
          ],
        ),
        DaySlot(
          name: 'Pull', focus: 'Back, biceps',
          dayType: 'pull', intensity: _profiles4[1],
          specsA: [
            CSpec('Pull', 4, exclude: ['Biceps', 'Forearm']),
            CSpec('Pull', 2, target: ['Biceps']),
          ],
          specsB: [
            CSpec('Pull', 4),
            CSpec('Pull', 2, target: ['Biceps']),
          ],
        ),
        DaySlot(
          name: 'Legs', focus: 'Quads, hamstrings, glutes',
          dayType: 'legs', intensity: _profiles4[2],
          specsA: [CSpec('Legs', 6, target: ['Quad'])],
          specsB: [CSpec('Legs', 6, target: ['Hamstring', 'Glute'])],
        ),
        DaySlot(
          name: 'Upper', focus: 'Shoulders, back, arms',
          dayType: 'upper', intensity: _profiles4[3],
          specsA: [
            CSpec('Push', 2, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            CSpec('Pull', 2, exclude: ['Biceps', 'Forearm']),
            CSpec('Push', 1, target: ['Triceps']),
            CSpec('Pull', 1, target: ['Biceps']),
          ],
          specsB: [
            CSpec('Push', 2, target: ['Chest']),
            CSpec('Pull', 2, target: ['Biceps']),
            CSpec('Push', 1, target: ['Triceps']),
            CSpec('Pull', 1, exclude: ['Biceps', 'Forearm']),
          ],
        ),
      ];
    }
    if (goal == 'strength') {
      return [
        DaySlot(
          name: 'Squat Day', focus: 'Squat + accessories',
          dayType: 'legs', intensity: _profiles4[0],
          specsA: [CSpec('Legs', 5)],
          specsB: [CSpec('Legs', 5, target: ['Hamstring', 'Glute'])],
        ),
        DaySlot(
          name: 'Bench Day', focus: 'Bench + upper push',
          dayType: 'push', intensity: _profiles4[1],
          specsA: [CSpec('Push', 5, target: ['Chest'])],
          specsB: [CSpec('Push', 5)],
        ),
        DaySlot(
          name: 'Deadlift Day', focus: 'Deadlift + back',
          dayType: 'pull', intensity: _profiles4[2],
          specsA: [
            CSpec('Pull', 3, exclude: ['Biceps', 'Forearm']),
            CSpec('Legs', 2, target: ['Hamstring', 'Glute']),
          ],
          specsB: [
            CSpec('Pull', 3),
            CSpec('Legs', 2),
          ],
        ),
        DaySlot(
          name: 'OHP Day', focus: 'Overhead press + accessories',
          dayType: 'push', intensity: _profiles4[3],
          specsA: [
            CSpec('Push', 3, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            CSpec('Core', 2),
          ],
          specsB: [
            CSpec('Push', 3, target: ['Deltoid', 'Shoulder']),
            CSpec('Core', 2),
          ],
        ),
      ];
    }
    // lose_fat / general_fitness
    return [
      DaySlot(
        name: 'Upper Push', focus: 'Chest, shoulders, triceps',
        dayType: 'push', intensity: _profiles4[0],
        specsA: [CSpec('Push', 5)],
      ),
      DaySlot(
        name: 'Lower Body', focus: 'Legs + cardio',
        dayType: 'legs', intensity: _profiles4[1],
        specsA: [CSpec('Legs', 3), CSpec('Cardio', 2)],
      ),
      DaySlot(
        name: 'Upper Pull', focus: 'Back, biceps',
        dayType: 'pull', intensity: _profiles4[2],
        specsA: [CSpec('Pull', 5)],
      ),
      DaySlot(
        name: 'Full Body + Core', focus: 'Total body + core',
        dayType: 'full_body', intensity: _profiles4[3],
        specsA: [CSpec('Legs', 2), CSpec('Core', 2), CSpec('Cardio', 1)],
      ),
    ];
  }

  // ── 5-day splits ───────────────────────────────────────────────

  static List<DaySlot> _get5Day(String goal) {
    if (goal == 'build_muscle') {
      return [
        DaySlot(
          name: 'Chest', focus: 'Chest focus',
          dayType: 'push', intensity: _profiles5[0],
          specsA: [CSpec('Push', 6, target: ['Chest', 'Upper Chest', 'Lower Chest'])],
        ),
        DaySlot(
          name: 'Back', focus: 'Back focus',
          dayType: 'pull', intensity: _profiles5[1],
          specsA: [CSpec('Pull', 6, exclude: ['Biceps', 'Forearm'])],
        ),
        DaySlot(
          name: 'Shoulders + Arms', focus: 'Delts, biceps, triceps',
          dayType: 'shoulders_arms', intensity: _profiles5[2],
          specsA: [
            CSpec('Push', 2, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            CSpec('Push', 2, target: ['Triceps']),
            CSpec('Pull', 2, target: ['Biceps']),
          ],
        ),
        DaySlot(
          name: 'Legs', focus: 'Quads, hams, glutes',
          dayType: 'legs', intensity: _profiles5[3],
          specsA: [CSpec('Legs', 6)],
          specsB: [CSpec('Legs', 6, target: ['Hamstring', 'Glute'])],
        ),
        DaySlot(
          name: 'Shoulders + Arms + Core', focus: 'Shoulders, arms, core',
          dayType: 'upper', intensity: _profiles5[4],
          specsA: [
            CSpec('Push', 1, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            CSpec('Pull', 1, target: ['Biceps']),
            CSpec('Core', 2),
          ],
        ),
      ];
    }
    // Default 5-day
    return [
      DaySlot(
        name: 'Push', focus: 'Chest, shoulders, triceps',
        dayType: 'push', intensity: _profiles5[0],
        specsA: [CSpec('Push', 6)],
      ),
      DaySlot(
        name: 'Pull', focus: 'Back, biceps',
        dayType: 'pull', intensity: _profiles5[1],
        specsA: [CSpec('Pull', 6)],
      ),
      DaySlot(
        name: 'Legs', focus: 'Quads, hamstrings, glutes',
        dayType: 'legs', intensity: _profiles5[2],
        specsA: [CSpec('Legs', 6)],
      ),
      DaySlot(
        name: 'Upper', focus: 'Shoulders, back, arms',
        dayType: 'upper', intensity: _profiles5[3],
        specsA: [
          CSpec('Push', 2, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
          CSpec('Pull', 2, exclude: ['Biceps', 'Forearm']),
          CSpec('Push', 1, target: ['Triceps']),
          CSpec('Pull', 1, target: ['Biceps']),
        ],
      ),
      DaySlot(
        name: 'Lower + Core', focus: 'Legs, core, conditioning',
        dayType: 'legs', intensity: _profiles5[4],
        specsA: [CSpec('Legs', 2), CSpec('Core', 2), CSpec('Cardio', 1)],
      ),
    ];
  }

  // ── 6-day splits (A/B baked into split — no week-to-week alternation) ─

  static List<DaySlot> _get6Day(String goal) {
    if (goal == 'build_muscle') {
      return [
        DaySlot(
          name: 'Push A', focus: 'Heavy chest focus',
          dayType: 'push', intensity: 'strength',
          specsA: [
            CSpec('Push', 4, target: ['Chest', 'Upper Chest', 'Lower Chest']),
            CSpec('Push', 2, target: ['Triceps']),
          ],
        ),
        DaySlot(
          name: 'Pull A', focus: 'Heavy back focus',
          dayType: 'pull', intensity: 'strength',
          specsA: [
            CSpec('Pull', 4, exclude: ['Biceps', 'Forearm']),
            CSpec('Pull', 2, target: ['Biceps']),
          ],
        ),
        DaySlot(
          name: 'Legs A', focus: 'Quad dominant',
          dayType: 'legs', intensity: 'strength',
          specsA: [CSpec('Legs', 6)],
        ),
        DaySlot(
          name: 'Push B', focus: 'Volume shoulders + triceps',
          dayType: 'push', intensity: 'hypertrophy',
          specsA: [
            CSpec('Push', 4, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            CSpec('Push', 2, target: ['Triceps']),
          ],
        ),
        DaySlot(
          name: 'Pull B', focus: 'Volume back + biceps',
          dayType: 'pull', intensity: 'hypertrophy',
          specsA: [
            CSpec('Pull', 3, exclude: ['Biceps', 'Forearm']),
            CSpec('Pull', 3, target: ['Biceps']),
          ],
        ),
        DaySlot(
          name: 'Legs B', focus: 'Hamstring + glute focus',
          dayType: 'legs', intensity: 'hypertrophy',
          specsA: [CSpec('Legs', 4), CSpec('Core', 2)],
        ),
      ];
    }
    // Default 6-day PPL
    return [
      DaySlot(name: 'Push', focus: 'Chest, shoulders, triceps',
          dayType: 'push', intensity: 'strength',
          specsA: [CSpec('Push', 6)]),
      DaySlot(name: 'Pull', focus: 'Back, biceps',
          dayType: 'pull', intensity: 'strength',
          specsA: [CSpec('Pull', 6)]),
      DaySlot(name: 'Legs', focus: 'Quads, hamstrings, glutes',
          dayType: 'legs', intensity: 'strength',
          specsA: [CSpec('Legs', 6)]),
      DaySlot(name: 'Push + Core', focus: 'Upper push + core',
          dayType: 'push', intensity: 'hypertrophy',
          specsA: [CSpec('Push', 4), CSpec('Core', 2)]),
      DaySlot(name: 'Pull + Cardio', focus: 'Upper pull + conditioning',
          dayType: 'pull', intensity: 'hypertrophy',
          specsA: [CSpec('Pull', 4), CSpec('Cardio', 2)]),
      DaySlot(name: 'Legs + Core', focus: 'Lower body + core',
          dayType: 'legs', intensity: 'hypertrophy',
          specsA: [CSpec('Legs', 4), CSpec('Core', 2)]),
    ];
  }

  // ══════════════════════════════════════════════════════════════════
  // V4: MuscleSlotDay splits — granular muscle-slot architecture
  // ══════════════════════════════════════════════════════════════════

  /// V4: Returns MuscleSlotDay list with granular muscle slots.
  static List<MuscleSlotDay> selectV4(String goal, int daysPerWeek, {String experienceLevel = 'intermediate'}) {
    final isBeginner = experienceLevel == 'beginner';
    if (isBeginner && daysPerWeek <= 4) {
      return _getBeginnerFullBodyV4(daysPerWeek, goal);
    }
    switch (daysPerWeek) {
      case 3: return _get3DayV4(goal);
      case 5: return _get5DayV4(goal);
      case 6: return _get6DayV4(goal);
      default: return _get4DayV4(goal);
    }
  }

  // ── V4: Beginner full-body splits (3-4 days) ──────────────────────

  static List<MuscleSlotDay> _getBeginnerFullBodyV4(int daysPerWeek, String goal) {
    final slots = <MuscleSlotDay>[
      MuscleSlotDay(
        name: 'Full Body A', focus: 'Push-focused', dayType: 'full_body', intensity: 'strength',
        slotsA: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        ],
      ),
      MuscleSlotDay(
        name: 'Full Body B', focus: 'Pull-focused', dayType: 'full_body', intensity: 'hypertrophy',
        slotsA: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        ],
      ),
      MuscleSlotDay(
        name: 'Full Body C', focus: 'Legs-focused', dayType: 'full_body', intensity: 'endurance',
        slotsA: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        ],
      ),
    ];
    if (daysPerWeek >= 4) {
      slots.add(MuscleSlotDay(
        name: 'Full Body D', focus: 'Balanced — core & conditioning', dayType: 'full_body', intensity: 'endurance',
        slotsA: [
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 3),
        ],
      ));
    }
    return slots;
  }

  // ── V4: 3-day splits ──────────────────────────────────────────────

  static List<MuscleSlotDay> _get3DayV4(String goal) {
    if (goal == 'lose_fat' || goal == 'general_fitness') {
      return [
        MuscleSlotDay(name: 'Full Body A', focus: 'Compound focus', dayType: 'full_body', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 5),
          const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        ]),
        MuscleSlotDay(name: 'Full Body B', focus: 'Strength + conditioning', dayType: 'full_body', intensity: 'hypertrophy', slotsA: [
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 5),
          const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        ]),
        MuscleSlotDay(name: 'Full Body C', focus: 'Volume + core', dayType: 'full_body', intensity: 'endurance', slotsA: [
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 4),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 5),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 5),
        ]),
      ];
    }
    // build_muscle / strength: Push+Core / Pull+Core / Legs
    return [
      MuscleSlotDay(name: 'Push + Core', focus: 'Chest, shoulders, triceps', dayType: 'push', intensity: 'strength', slotsA: [
        const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 2),
        const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 5),
        const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
      ], slotsB: [
        const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 1),
        const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 2),
        const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 3),
        const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 5),
        const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
      ]),
      MuscleSlotDay(name: 'Pull + Core', focus: 'Back, biceps', dayType: 'pull', intensity: 'hypertrophy', slotsA: [
        const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 3),
        const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 4),
        const MuscleSlot(targetMuscle: 'Rear Delts', subFocus: 'cable', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 5),
        const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
      ], slotsB: [
        const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 4),
        const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'short_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Rear Delts', subFocus: 'cable', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 5),
        const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
      ]),
      MuscleSlotDay(name: 'Legs', focus: 'Quads, hamstrings, glutes', dayType: 'legs', intensity: 'endurance', slotsA: [
        const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 4),
        const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        const MuscleSlot(targetMuscle: 'Calves', subFocus: 'soleus', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 5),
      ], slotsB: [
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 3),
        const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        const MuscleSlot(targetMuscle: 'Calves', subFocus: 'soleus', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 5),
      ]),
    ];
  }

  // ── V4: 4-day splits ──────────────────────────────────────────────

  static List<MuscleSlotDay> _get4DayV4(String goal) {
    if (goal == 'build_muscle') {
      return [
        MuscleSlotDay(name: 'Push', focus: 'Chest, shoulders, triceps', dayType: 'push', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 4),
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 5),
        ], slotsB: [
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 4),
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'lateral_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 5),
        ]),
        MuscleSlotDay(name: 'Pull', focus: 'Back, biceps', dayType: 'pull', intensity: 'hypertrophy', slotsA: [
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 4),
          const MuscleSlot(targetMuscle: 'Rear Delts', subFocus: 'cable', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'short_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 5),
        ], slotsB: [
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 4),
          const MuscleSlot(targetMuscle: 'Rear Delts', subFocus: 'cable', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'short_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 5),
        ]),
        MuscleSlotDay(name: 'Legs', focus: 'Quads, hams, glutes', dayType: 'legs', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Calves', subFocus: 'soleus', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 5),
        ], slotsB: [
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Calves', subFocus: 'soleus', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 5),
        ]),
        MuscleSlotDay(name: 'Upper', focus: 'Shoulders, back, arms', dayType: 'upper', intensity: 'endurance', slotsA: [
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        ], slotsB: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        ]),
      ];
    }
    if (goal == 'strength') {
      return [
        MuscleSlotDay(name: 'Squat Day', focus: 'Squat + accessories', dayType: 'legs', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Calves', subFocus: 'soleus', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 5),
        ], slotsB: [
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Calves', subFocus: 'soleus', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 5),
        ]),
        MuscleSlotDay(name: 'Bench Day', focus: 'Bench + upper push', dayType: 'push', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 5),
        ], slotsB: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 5),
        ]),
        MuscleSlotDay(name: 'Deadlift Day', focus: 'Deadlift + back', dayType: 'pull', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 4),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        ], slotsB: [
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 4),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        ]),
        MuscleSlotDay(name: 'OHP Day', focus: 'Overhead press + accessories', dayType: 'push', intensity: 'hypertrophy', slotsA: [
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 1),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        ], slotsB: [
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
        ]),
      ];
    }
    // lose_fat / general_fitness
    return [
      MuscleSlotDay(name: 'Upper Push', focus: 'Chest, shoulders, triceps', dayType: 'push', intensity: 'strength', slotsA: [
        const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 2),
        const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
      ]),
      MuscleSlotDay(name: 'Lower Body', focus: 'Legs + conditioning', dayType: 'legs', intensity: 'hypertrophy', slotsA: [
        const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 5),
        const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
      ]),
      MuscleSlotDay(name: 'Upper Pull', focus: 'Back, biceps', dayType: 'pull', intensity: 'strength', slotsA: [
        const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 3),
        const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'short_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Rear Delts', subFocus: 'cable', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
      ]),
      MuscleSlotDay(name: 'Full Body + Core', focus: 'Total body + core', dayType: 'full_body', intensity: 'endurance', slotsA: [
        const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 3),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 4),
        const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 5),
      ]),
    ];
  }

  // ── V4: 5-day splits ──────────────────────────────────────────────

  static List<MuscleSlotDay> _get5DayV4(String goal) {
    if (goal == 'build_muscle') {
      return [
        // Day 1: Chest
        MuscleSlotDay(name: 'Chest', focus: 'Chest focus', dayType: 'push', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Mid Chest', subFocus: 'cable', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
        ]),
        // Day 2: Back — THE KEY FIX (was curls-on-back-day)
        MuscleSlotDay(name: 'Back', focus: 'Back focus', dayType: 'pull', intensity: 'hypertrophy', slotsA: [
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Rear Delts', subFocus: 'cable', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
        ]),
        // Day 3: Shoulders + Arms
        MuscleSlotDay(name: 'Shoulders + Arms', focus: 'Delts, biceps, triceps', dayType: 'shoulders_arms', intensity: 'endurance', slotsA: [
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 1),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Lateral Delts', subFocus: 'cable', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
        ]),
        // Day 4: Legs
        MuscleSlotDay(name: 'Legs', focus: 'Quads, hams, glutes', dayType: 'legs', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 4),
        ], slotsB: [
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 4),
        ]),
        // Day 5: Upper + Core
        MuscleSlotDay(name: 'Upper + Core', focus: 'Shoulders, arms, core', dayType: 'upper', intensity: 'hypertrophy', slotsA: [
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 4),
        ]),
      ];
    }
    // Default 5-day (PPL + Upper + Lower)
    return [
      MuscleSlotDay(name: 'Push', focus: 'Chest, shoulders, triceps', dayType: 'push', intensity: 'strength', slotsA: [
        const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 2),
        const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
      ]),
      MuscleSlotDay(name: 'Pull', focus: 'Back, biceps', dayType: 'pull', intensity: 'hypertrophy', slotsA: [
        const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 2),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 4),
        const MuscleSlot(targetMuscle: 'Rear Delts', subFocus: 'cable', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
      ]),
      MuscleSlotDay(name: 'Legs', focus: 'Quads, hamstrings, glutes', dayType: 'legs', intensity: 'endurance', slotsA: [
        const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
      ]),
      MuscleSlotDay(name: 'Upper', focus: 'Shoulders, back, arms', dayType: 'upper', intensity: 'strength', slotsA: [
        const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 3),
        const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
      ]),
      MuscleSlotDay(name: 'Lower + Core', focus: 'Legs, core, conditioning', dayType: 'legs', intensity: 'hypertrophy', slotsA: [
        const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 3),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
      ]),
    ];
  }

  // ── V4: 6-day splits ──────────────────────────────────────────────

  static List<MuscleSlotDay> _get6DayV4(String goal) {
    if (goal == 'build_muscle') {
      return [
        // Push A: Heavy chest
        MuscleSlotDay(name: 'Push A', focus: 'Heavy chest focus', dayType: 'push', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 4),
        ]),
        // Pull A: Heavy back
        MuscleSlotDay(name: 'Pull A', focus: 'Heavy back focus', dayType: 'pull', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 4),
        ]),
        // Legs A: Quad dominant
        MuscleSlotDay(name: 'Legs A', focus: 'Quad dominant', dayType: 'legs', intensity: 'strength', slotsA: [
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Calves', subFocus: 'soleus', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
        ]),
        // Push B: Volume shoulders + triceps
        MuscleSlotDay(name: 'Push B', focus: 'Volume shoulders + triceps', dayType: 'push', intensity: 'hypertrophy', slotsA: [
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Lateral Delts', subFocus: 'cable', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 4),
        ]),
        // Pull B: Volume back + biceps
        MuscleSlotDay(name: 'Pull B', focus: 'Volume back + biceps', dayType: 'pull', intensity: 'hypertrophy', slotsA: [
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 3),
          const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'short_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 4),
        ]),
        // Legs B: Hamstring + glute
        MuscleSlotDay(name: 'Legs B', focus: 'Hamstring + glute focus', dayType: 'legs', intensity: 'hypertrophy', slotsA: [
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
          const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
          const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 4),
        ]),
      ];
    }
    // Default 6-day PPL
    return [
      MuscleSlotDay(name: 'Push', focus: 'Chest, shoulders, triceps', dayType: 'push', intensity: 'strength', slotsA: [
        const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 2),
        const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 4),
      ]),
      MuscleSlotDay(name: 'Pull', focus: 'Back, biceps', dayType: 'pull', intensity: 'strength', slotsA: [
        const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 2),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 4),
        const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 4),
      ]),
      MuscleSlotDay(name: 'Legs', focus: 'Quads, hamstrings, glutes', dayType: 'legs', intensity: 'strength', slotsA: [
        const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
      ]),
      MuscleSlotDay(name: 'Push + Core', focus: 'Upper push + core', dayType: 'push', intensity: 'hypertrophy', slotsA: [
        const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 4),
      ]),
      MuscleSlotDay(name: 'Pull + Core', focus: 'Upper pull + conditioning', dayType: 'pull', intensity: 'hypertrophy', slotsA: [
        const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Biceps', subFocus: 'long_head', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 4),
        const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 4),
      ]),
      MuscleSlotDay(name: 'Legs + Core', focus: 'Lower body + core', dayType: 'legs', intensity: 'hypertrophy', slotsA: [
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
        const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
        const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 4),
        const MuscleSlot(targetMuscle: 'Hip', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 4),
      ]),
    ];
  }
}
