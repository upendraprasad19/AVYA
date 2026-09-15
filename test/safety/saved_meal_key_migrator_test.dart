import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/saved_meal_key_migrator.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

/// Behavioral test for SavedMealKeyMigrator (diagnose b8d5c2): re-keys legacy
/// `saved_meal_<ms>` rows to the canonical `saved_meal_<nameHash>`, MERGES the
/// restore-dup collision keeping max times_used, is idempotent, leaves nameless
/// rows alone, and the writer now keys canonically.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await nwsTestSetup();
    // The nutrition harness opens user-scoped boxes but not the GLOBAL configBox
    // the migrator's gate flag lives in (prod opens it in main.dart before boot).
    for (final n in [HiveService.configBoxName, HiveService.migrationBoxName]) {
      if (!Hive.isBoxOpen(n)) await Hive.openBox<dynamic>(n);
    }
  });
  tearDown(nwsTestTeardown);

  Future<void> resetFlag() =>
      HiveService.instance.configBox.delete('saved_meal_key_migration_v1');

  test('re-keys legacy saved_meal_<ms> → canonical saved_meal_<nameHash>',
      () async {
    await resetFlag();
    final box = HiveService.instance.nutritionBox;
    await box.put('saved_meal_1748900000000', {
      'id': 'saved_meal_1748900000000',
      'is_saved_meal': true,
      'name': 'Chicken Rice',
      'total_calories': 500,
      'times_used': 2,
      'created_at': '2026-06-01T10:00:00.000Z',
    });
    await SavedMealKeyMigrator.runIfNeeded();
    final canonical = NutritionWriteService.savedMealKey('Chicken Rice');
    expect(box.get('saved_meal_1748900000000'), isNull,
        reason: 'legacy ms key removed');
    expect(box.get(canonical), isNotNull, reason: 're-keyed to name-hash');
    expect((box.get(canonical) as Map)['name'], 'Chicken Rice');
  });

  test('MERGES a legacy <ms> row INTO an existing canonical row (restore-dup), '
      'keeping max times_used', () async {
    await resetFlag();
    final box = HiveService.instance.nutritionBox;
    final canonical = NutritionWriteService.savedMealKey('Paneer Bowl');
    // canonical row already present (e.g. from a prior cloud restore)
    await box.put(canonical, {
      'id': canonical,
      'is_saved_meal': true,
      'name': 'Paneer Bowl',
      'times_used': 1,
      'created_at': '2026-05-30T08:00:00.000Z',
      'source': 'cloud_restore',
    });
    // legacy ms row for the SAME meal (the writer's duplicate)
    await box.put('saved_meal_1748999999999', {
      'id': 'saved_meal_1748999999999',
      'is_saved_meal': true,
      'name': 'Paneer Bowl',
      'times_used': 5,
      'created_at': '2026-06-02T08:00:00.000Z',
    });
    await SavedMealKeyMigrator.runIfNeeded();
    final paneer = box.keys
        .where((k) =>
            k.toString().startsWith('saved_meal_') &&
            (box.get(k) as Map)['name'] == 'Paneer Bowl')
        .toList();
    expect(paneer.length, 1, reason: 'dup collapsed to ONE canonical row');
    expect(paneer.first, canonical);
    expect(box.get('saved_meal_1748999999999'), isNull);
    expect((box.get(canonical) as Map)['times_used'], 5,
        reason: 'max re-log count kept on merge');
  });

  test('idempotent — second run is a no-op (flag gate)', () async {
    await resetFlag();
    final box = HiveService.instance.nutritionBox;
    await box.put('saved_meal_1748900000001', {
      'id': 'saved_meal_1748900000001',
      'is_saved_meal': true,
      'name': 'Egg Bhurji',
      'times_used': 0,
      'created_at': '2026-06-01T10:00:00.000Z',
    });
    await SavedMealKeyMigrator.runIfNeeded();
    // inject another legacy key AFTER the flag is set
    await box.put('saved_meal_1748900000002', {
      'id': 'saved_meal_1748900000002',
      'is_saved_meal': true,
      'name': 'Sneaky',
      'times_used': 0,
      'created_at': '2026-06-01T10:00:00.000Z',
    });
    await SavedMealKeyMigrator.runIfNeeded();
    expect(box.get('saved_meal_1748900000002'), isNotNull,
        reason: 'gated → second run did not migrate');
  });

  test('nameless legacy row is left untouched (cannot name-key it)', () async {
    await resetFlag();
    final box = HiveService.instance.nutritionBox;
    await box.put('saved_meal_1748900000003', {
      'id': 'saved_meal_1748900000003',
      'is_saved_meal': true,
      'name': '',
      'times_used': 0,
      'created_at': '2026-06-01T10:00:00.000Z',
    });
    await SavedMealKeyMigrator.runIfNeeded();
    expect(box.get('saved_meal_1748900000003'), isNotNull);
  });

  test('writer now keys Hive by canonical name-hash (matches restore)',
      () async {
    await resetFlag();
    final box = HiveService.instance.nutritionBox;
    await NutritionWriteService.instance.saveMealPreset(
      name: 'Test Meal',
      totalCalories: 100,
      totalProtein: 10,
      totalCarbs: 5,
      totalFat: 2,
      items: [
        {'name': 'X', 'quantityG': 100},
      ],
    );
    expect(box.get(NutritionWriteService.savedMealKey('Test Meal')), isNotNull);
    final msKeys = box.keys
        .where((k) => RegExp(r'^saved_meal_\d{13}$').hasMatch(k.toString()))
        .toList();
    expect(msKeys, isEmpty,
        reason: 'writer no longer keys by a 13-digit ms timestamp');
  });
}
