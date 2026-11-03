import 'models.dart';

/// Stage 1.5: the deload-week slot filter.
///
/// B2 flip (2026-11-02): the session set budget sizes every day by the user's
/// minutes, so this stage no longer trims a day to a fixed exercise count
/// (the old `targetCount(experience, daysPerWeek)` table is deleted): every split
/// slot is kept and the allocator admits as many as the time allows. Only the
/// deload rule stays.
class VolumeFilter {
  /// Filter a flat list of MuscleSlots for [weekCharacter] — baseline |
  /// overreach | peak | deload. (A lifted deload is stamped `working` in the
  /// blob, but that happens after generation, so this filter never sees it.)
  /// Deload: priority-1 slots only. Anything else: every slot, in the split's
  /// priority order.
  static List<MuscleSlot> filter(
    List<MuscleSlot> slots, {
    required String weekCharacter,
  }) {
    if (weekCharacter == 'deload') {
      return slots.where((s) => s.priority == 1).toList();
    }
    return slots;
  }

  /// Apply [filter] to every day in a MuscleSlotDay list.
  static List<MuscleSlotDay> filterDays(
    List<MuscleSlotDay> days, {
    required String weekCharacter,
  }) {
    return days.map((day) {
      final filteredA = filter(day.slotsA, weekCharacter: weekCharacter);
      final filteredB = day.slotsB != null
          ? filter(day.slotsB!, weekCharacter: weekCharacter)
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
