import 'models.dart';

/// Stage 1.5: Trims MuscleSlot lists based on experience level and
/// training frequency (days per week).
///
/// Slots are ordered by priority in the split spec (trainer wisdom).
/// This filter takes the first N slots where N = f(experience, daysPerWeek).
///
/// Inverse scaling: fewer training days → more exercises per session.
/// More experience → more volume per session.
class VolumeFilter {
  /// Target exercise count per day based on experience and training frequency.
  ///
  /// | Experience   | 3-day | 4-day | 5/6-day |
  /// |-------------|-------|-------|---------|
  /// | Beginner     |   6   |   5   |    4    |
  /// | Intermediate |   8   |   7   |    6    |
  /// | Advanced     |  10   |   9   |    8    |
  static int targetCount(String experience, int daysPerWeek) {
    if (experience == 'beginner') {
      if (daysPerWeek <= 3) return 6;
      if (daysPerWeek == 4) return 5;
      return 4; // 5/6-day
    }
    if (experience == 'intermediate') {
      if (daysPerWeek <= 3) return 8;
      if (daysPerWeek == 4) return 7;
      return 6; // 5/6-day
    }
    // advanced
    if (daysPerWeek <= 3) return 10;
    if (daysPerWeek == 4) return 9;
    return 8; // 5/6-day
  }

  /// Filter a flat list of MuscleSlots down to what fits the user's constraints.
  ///
  /// [experience] — beginner | intermediate | advanced.
  /// [weekCharacter] — baseline | overreach | peak | deload. (A lifted deload
  /// is stamped `working` in the blob, but that happens after generation, so
  /// this filter never sees it.)
  /// [daysPerWeek] — training days per week (3-6).
  static List<MuscleSlot> filter(
    List<MuscleSlot> slots, {
    required String experience,
    required String weekCharacter,
    required int daysPerWeek,
  }) {
    // Deload: P1 only regardless of experience/frequency
    if (weekCharacter == 'deload') {
      return slots.where((s) => s.priority == 1).toList();
    }

    final target = targetCount(experience, daysPerWeek);
    // Slots are already in priority order from split_resolver.
    // Take the first N to match the target count.
    // If fewer slots exist than target, return all (split defines the ceiling).
    if (slots.length <= target) return slots;
    return slots.take(target).toList();
  }

  /// Apply volume filter to every day in a MuscleSlotDay list.
  /// Infers daysPerWeek from the length of [days].
  static List<MuscleSlotDay> filterDays(
    List<MuscleSlotDay> days, {
    required String experience,
    required String weekCharacter,
  }) {
    final daysPerWeek = days.length;
    return days.map((day) {
      final filteredA = filter(day.slotsA,
          experience: experience,
          weekCharacter: weekCharacter,
          daysPerWeek: daysPerWeek);
      final filteredB = day.slotsB != null
          ? filter(day.slotsB!,
              experience: experience,
              weekCharacter: weekCharacter,
              daysPerWeek: daysPerWeek)
          : null;
      return MuscleSlotDay(
        name: day.name,
        focus: day.focus,
        dayType: day.dayType,
        intensity: day.intensity,
        slotsA: filteredA,
        slotsB: filteredB,
      );
    }).toList();
  }
}
