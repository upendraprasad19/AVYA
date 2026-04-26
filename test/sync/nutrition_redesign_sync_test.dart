import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the sync gaps closed alongside the APK Test #3
/// nutrition redesign (Plan D, Task 1).
///
/// Prior holes:
///   - UrineColorNotifier.select() only fired pushSnapshot — health-box
///     row never reached cloud until next launch.
///   - CustomFoodNotifier.addCustomFood fired pushSnapshot + the
///     repository helper, but skipped syncCustomItemsNow (unlike the
///     mirror path for custom EXERCISES, which does fire it).
void main() {
  final source = File(
    'lib/features/nutrition/providers/nutrition_provider.dart',
  ).readAsStringSync();

  test('UrineColorNotifier.select fires syncNutritionData + pushSnapshot',
      () {
    final selectStart = source.indexOf('void select(int index)');
    expect(selectStart, isNot(-1), reason: 'select() must exist');
    final body = source.substring(selectStart, selectStart + 1200);

    expect(
      body.contains('SyncService.instance.syncNutritionData'),
      isTrue,
      reason: 'UrineColorNotifier.select must fire syncNutritionData() so '
          'urine_color_<date> changes propagate to cloud, not just the AI '
          'snapshot.',
    );
    expect(
      body.contains('SyncService.instance.pushSnapshot'),
      isTrue,
      reason: 'pushSnapshot must remain (already present) so AI coach '
          'context updates live.',
    );
  });

  test('CustomFoodNotifier.addCustomFood fires syncCustomItemsNow', () {
    final addStart = source.indexOf('Future<void> addCustomFood(');
    expect(addStart, isNot(-1), reason: 'addCustomFood must exist');
    final body = source.substring(addStart, addStart + 2400);

    expect(
      body.contains('SyncService.instance.syncCustomItemsNow'),
      isTrue,
      reason: 'addCustomFood must fire syncCustomItemsNow so the custom '
          'food projection reaches user_custom_foods on cloud (mirror of '
          'the Train custom-exercise path closed in APK Test #1 D6).',
    );
    expect(
      body.contains('SyncService.instance.pushSnapshot'),
      isTrue,
      reason: 'pushSnapshot must remain so AI coach learns about new '
          'custom foods immediately.',
    );
  });
}
