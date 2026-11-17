/// Unit 3A (OI-487, founder d3 / d4 / d58-d60): the goal's rep rule for a rep-based row with a library rep range.
/// Pure: no Hive, no flag read ([SessionBudgetContext.goalTraining] carries both inputs).
///
/// A MAIN lift is archetype H or M (d58: every compound, plus calisthenics whose range starts at 10 or less); every
/// other row is an accessory. The phase archetype cycles hypertrophy / strength / metabolic / deload (phases 1-4, then
/// again). The level is the EFFECTIVE level (d68: a beginner trains as intermediate from phase 3, as the bands do), so
/// "deload = phase 1's reps" (d59) is phase 1's entry at that level. The returned base is week 1's; the caller
/// applies the week wave and clamps into the row's range (a lift whose range cannot reach the table stops at its
/// bound, d58).
class GoalReps {
  GoalReps._();

  /// Cut and Maintain accessories (founder: "accessories 10-15 for all").
  static const int accessoryMin = 10;
  static const int accessoryMax = 15;

  /// The week-1 base for a main lift under [planGoal] (`lose_fat` = Cut, `general_fitness` = Maintain) at the
  /// EFFECTIVE [level] in phase [archetype], or null when the goal keeps today's rule (Build, the legacy strength
  /// token, an unknown goal). Deload uses phase 1's value (d59).
  static int? mainBase(String planGoal, String level, String archetype) {
    final beginner = level == 'beginner';
    switch (planGoal) {
      case 'lose_fat':
        return archetype == 'strength' ? (beginner ? 8 : 6) : (beginner ? 10 : 8);
      case 'general_fitness':
        return archetype == 'strength' ? 8 : 10;
      default:
        return null;
    }
  }

  /// Whether [planGoal]'s accessories are clamped into [accessoryMin]..[accessoryMax] (Cut and Maintain).
  static bool clampsAccessories(String planGoal) => planGoal == 'lose_fat' || planGoal == 'general_fitness';

  /// Today's archetype lean over a range (the rule Build keeps): strength the low end, metabolic the high end,
  /// hypertrophy and deload the middle.
  static int todayBase(String archetype, int minReps, int maxReps) {
    final mid = ((minReps + maxReps) / 2).round();
    return switch (archetype) {
      'strength' => minReps,
      'metabolic' => maxReps,
      _ => mid,
    };
  }

  /// The week-1 base for a row: [isMain] is H or M. Under the Strength focus (d4) a main lift takes the range's low end
  /// in every phase but the deload, which keeps the goal's rule.
  static int base({
    required bool strengthFocus,
    required bool isMain,
    required String planGoal,
    required String level,
    required String archetype,
    required int minReps,
    required int maxReps,
  }) {
    if (!isMain) return todayBase(archetype, minReps, maxReps);
    if (strengthFocus && archetype != 'deload') return minReps;
    return mainBase(planGoal, level, archetype) ?? todayBase(archetype, minReps, maxReps);
  }
}
