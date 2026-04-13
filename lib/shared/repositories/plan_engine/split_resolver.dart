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
}
