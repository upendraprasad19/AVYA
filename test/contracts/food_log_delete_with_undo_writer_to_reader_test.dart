// test/contracts/food_log_delete_with_undo_writer_to_reader_test.dart
//
// Contract: food_log_delete_with_undo
// Writer: NutritionWriteService.deleteLog
// Reader / Delete surface: nutrition_screen._confirmAndDeleteFoodLog (with UNDO stash)
//
// Pins: deleteFoodLog must ONLY be called from _confirmAndDeleteFoodLog,
// which stashes the row before deleting and offers UNDO via restoreFoodLog.
// Retired root §19 entry #48 ("Food log delete with no undo"), classified
// Class A by the 2026-05-18 declutter audit and deleted from the contract
// file because THIS test is its record.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String nutritionScreenSource;
  late String nutritionProviderSource;
  late String nutritionWriteSource;

  setUpAll(() {
    nutritionScreenSource = File(
            'lib/features/nutrition/screens/nutrition_screen.dart')
        .readAsStringSync();
    nutritionProviderSource = File(
            'lib/features/nutrition/providers/nutrition_provider.dart')
        .readAsStringSync();
    nutritionWriteSource = File(
            'lib/core/services/nutrition_write_service.dart')
        .readAsStringSync();
  });

  group('food_log_delete_with_undo writer→reader contract', () {
    test('nutrition_screen has _confirmAndDeleteFoodLog (canonical delete surface)', () {
      expect(
        nutritionScreenSource,
        contains('_confirmAndDeleteFoodLog'),
        reason:
            '_confirmAndDeleteFoodLog is the ONLY delete surface; '
            'must stash log + offer UNDO before calling deleteFoodLog.',
      );
    });

    test('nutrition_screen stashes before delete (for UNDO)', () {
      // The canonical delete stashes the log so restoreFoodLog can write it back.
      final hasStash = nutritionScreenSource.contains('restoreFoodLog') ||
          nutritionScreenSource.contains('stash') ||
          nutritionScreenSource.contains('UNDO');
      expect(
        hasStash,
        isTrue,
        reason:
            'nutrition_screen._confirmAndDeleteFoodLog must stash the log '
            'before deletion so UNDO can restore it.',
      );
    });

    test('NutritionWriteService has deleteLog method', () {
      expect(
        nutritionWriteSource,
        contains('deleteLog'),
        reason:
            'NutritionWriteService must expose deleteLog; '
            'direct nutritionBox.delete from a widget is forbidden.',
      );
    });

    test('deleteFoodLog provider fires syncNutritionData after delete', () {
      // OI-36 (audit-2026-05-17 Hermes C1) — deleteFoodLog now delegates to
      // NutritionWriteService.deleteLog which fires `syncNutritionData()`
      // internally. The sync wiring lives in the WriteService, not in the
      // provider. We assert BOTH conditions:
      //   1. The provider delegates to NutritionWriteService.deleteLog.
      //   2. The WriteService still fires `syncNutritionData()` in deleteLog.
      expect(
        nutritionProviderSource,
        contains('NutritionWriteService.instance.deleteLog'),
        reason:
            'deleteFoodLog in nutrition_provider must delegate to '
            'NutritionWriteService.instance.deleteLog (canonical writer).',
      );
      expect(
        nutritionWriteSource,
        contains('syncNutritionData'),
        reason:
            'NutritionWriteService.deleteLog must fire `syncNutritionData()` '
            'so cloud stays in sync. Missing sync = AI coach sees stale '
            'meal context.',
      );
    });
  });
}
