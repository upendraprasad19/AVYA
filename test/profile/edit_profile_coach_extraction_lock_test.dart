import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/screens/edit_profile_screen.dart';

// a2b-2 (single-owner batch, 2026-09-27): pins computeCoachExtractionFieldsToLock,
// the pure helper that decides which of diet_preference / lifestyle_activity /
// injuries actually changed this save — the caller (edit_profile_screen's
// _save) passes the result to UserRepository.lockCoachExtractionFields
// (migration 148). Mirrors the existing computePlanChanged test file's shape.
void main() {
  group('computeCoachExtractionFieldsToLock', () {
    List<String> callWith({
      String dietPreference = 'vegetarian',
      String originalDietPreference = 'vegetarian',
      String lifestyleActivity = 'desk_job',
      String originalLifestyleActivity = 'desk_job',
      List<String> injuries = const ['none'],
      List<String> originalInjuries = const ['none'],
    }) {
      return computeCoachExtractionFieldsToLock(
        dietPreference: dietPreference,
        originalDietPreference: originalDietPreference,
        lifestyleActivity: lifestyleActivity,
        originalLifestyleActivity: originalLifestyleActivity,
        injuries: injuries,
        originalInjuries: originalInjuries,
      );
    }

    test('nothing changed -> empty list', () {
      expect(callWith(), isEmpty);
    });

    test('diet_preference changed -> locks only diet_preference', () {
      final result = callWith(dietPreference: 'non_veg');
      expect(result, ['diet_preference']);
    });

    test('lifestyle_activity changed -> locks only lifestyle_activity', () {
      final result = callWith(lifestyleActivity: 'very_active_job');
      expect(result, ['lifestyle_activity']);
    });

    test('injuries changed -> locks only injuries', () {
      final result = callWith(injuries: ['knee']);
      expect(result, ['injuries']);
    });

    test('identical injuries list (same instance content, same order) -> NOT locked', () {
      final result = callWith(
        injuries: ['knee', 'shoulder'],
        originalInjuries: ['knee', 'shoulder'],
      );
      expect(result, isEmpty);
    });

    test('injuries reordered with the SAME elements -> IS locked (matches computePlanChanged\'s existing order-sensitive listEquals convention — the chip UI writes a stable order, so a real reorder without a genuine edit should not happen in practice)', () {
      final result = callWith(
        injuries: ['knee', 'shoulder'],
        originalInjuries: ['shoulder', 'knee'],
      );
      expect(result, ['injuries']);
    });

    test('all three changed -> locks all three, in field order', () {
      final result = callWith(
        dietPreference: 'non_veg',
        lifestyleActivity: 'very_active_job',
        injuries: ['knee'],
      );
      expect(result, ['diet_preference', 'lifestyle_activity', 'injuries']);
    });
  });
}
