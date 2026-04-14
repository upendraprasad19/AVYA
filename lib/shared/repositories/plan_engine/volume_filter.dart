import 'models.dart';

/// Stage 1.5: Trims MuscleSlot lists based on session duration,
/// experience level, and phase archetype (week character).
///
/// Priority is hardcoded in the split spec (trainer wisdom).
/// The CUTOFF (which priorities survive) is dynamic.
class VolumeFilter {
  /// Filter a flat list of MuscleSlots down to what fits the user's constraints.
  ///
  /// [sessionMinutes] — user's session duration (default 45 if null).
  /// [experience] — beginner | intermediate | advanced.
  /// [weekCharacter] — baseline | overreach | peak | deload.
  static List<MuscleSlot> filter(
    List<MuscleSlot> slots, {
    required int? sessionMinutes,
    required String experience,
    required String weekCharacter,
  }) {
    final minutes = sessionMinutes ?? 45;

    // Deload: P1 only regardless of time/experience
    if (weekCharacter == 'deload') {
      return slots.where((s) => s.priority == 1).toList();
    }

    // Determine max priority based on time
    int maxPriority;
    if (minutes >= 60) {
      maxPriority = 3; // all
    } else if (minutes >= 45) {
      maxPriority = 2; // P1 + P2
    } else {
      maxPriority = 1; // P1 only
    }

    // Beginner override: max P2, and only 1 P2 slot
    if (experience == 'beginner') {
      maxPriority = maxPriority.clamp(1, 2);
      final p1 = slots.where((s) => s.priority == 1).toList();
      if (maxPriority >= 2) {
        final firstP2 = slots.where((s) => s.priority == 2).take(1);
        return [...p1, ...firstP2];
      }
      return p1;
    }

    return slots.where((s) => s.priority <= maxPriority).toList();
  }

  /// Apply volume filter to every day in a MuscleSlotDay list.
  static List<MuscleSlotDay> filterDays(
    List<MuscleSlotDay> days, {
    required int? sessionMinutes,
    required String experience,
    required String weekCharacter,
  }) {
    return days.map((day) {
      final filteredA = filter(day.slotsA,
          sessionMinutes: sessionMinutes,
          experience: experience,
          weekCharacter: weekCharacter);
      final filteredB = day.slotsB != null
          ? filter(day.slotsB!,
              sessionMinutes: sessionMinutes,
              experience: experience,
              weekCharacter: weekCharacter)
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
