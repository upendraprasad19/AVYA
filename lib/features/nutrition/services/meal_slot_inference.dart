/// Time-window based meal-slot inference for nutrition logging.
///
/// When the user logs a meal via the always-visible AI input or SCAN flow
/// on the Nutrition screen, we auto-assign a `meal_type` based on the
/// current time. The user can override via the slot chip (PR Part C.3).
///
/// Windows (local time):
///   05:00 – 10:30 → breakfast
///   11:30 – 15:30 → lunch
///   18:00 – 22:00 → dinner
///   everything else → snacks
///
/// Returned strings match the existing `meal_type` conventions used by
/// `TodaysMealsCard` / `nutrition_provider.saveMeal` / `FoodLogNotifier`.
/// Note: the fourth slot is `snacks` (plural) to stay consistent with the
/// existing defaults in `FoodLogNotifier` and `_ScanResultEditor._save`.
String inferMealSlot(DateTime now) {
  // Minutes since midnight keeps the window boundaries precise (e.g. 10:30
  // end of breakfast, 11:30 start of lunch).
  final mins = now.hour * 60 + now.minute;

  // 05:00 – 10:30 → breakfast
  if (mins >= 5 * 60 && mins < 10 * 60 + 30) return 'breakfast';
  // 11:30 – 15:30 → lunch
  if (mins >= 11 * 60 + 30 && mins < 15 * 60 + 30) return 'lunch';
  // 18:00 – 22:00 → dinner
  if (mins >= 18 * 60 && mins < 22 * 60) return 'dinner';
  // everything else → snacks
  return 'snacks';
}

/// Human label for a slot key — used in the slot chip on the AI / SCAN
/// confirmation cards. Matches the TodaysMealsCard slot labels.
String mealSlotLabel(String slot) {
  switch (slot.toLowerCase()) {
    case 'breakfast':
      return 'BREAKFAST';
    case 'lunch':
      return 'LUNCH';
    case 'dinner':
      return 'DINNER';
    case 'snack':
    case 'snacks':
      return 'SNACK';
    default:
      return 'SNACK';
  }
}

/// Emoji glyph for a slot, used on the inline chip.
String mealSlotEmoji(String slot) {
  switch (slot.toLowerCase()) {
    case 'breakfast':
      return '\u{1F373}'; // 🍳
    case 'lunch':
      return '\u{1F35B}'; // 🍛
    case 'dinner':
      return '\u{1F37D}'; // 🍽
    case 'snack':
    case 'snacks':
      return '\u{1F36A}'; // 🍪
    default:
      return '\u{1F36A}';
  }
}

/// The four slot keys in display order.
const List<String> mealSlotKeys = ['breakfast', 'lunch', 'dinner', 'snacks'];
