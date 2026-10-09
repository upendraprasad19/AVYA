import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the sync gaps closed alongside the APK Test #3
/// nutrition redesign (Plan D, Task 1) — plus the broader sync-hygiene
/// invariants locked in Task 10 covering the new code paths
/// (LogFoodSheet mode bodies, HydrationCard, YourFoodsSection).
///
/// Prior holes (Task 1):
///   - UrineColorNotifier.select() only fired pushSnapshot — health-box
///     row never reached cloud until next launch.
///   - CustomFoodNotifier.addCustomFood fired pushSnapshot + the
///     repository helper, but skipped syncCustomItemsNow (unlike the
///     mirror path for custom EXERCISES, which does fire it).
void main() {
  final source = File(
    'lib/features/nutrition/providers/nutrition_provider.dart',
  ).readAsStringSync();

  test('UrineColorNotifier.select routes through HealthWriteService (audit-2026-05-16 E.7)',
      () {
    final selectStart = source.indexOf('void select(int index)');
    expect(selectStart, isNot(-1), reason: 'select() must exist');
    final body = source.substring(selectStart, selectStart + 1200);

    // Post-E.7: writes go through HealthWriteService.logUrine which
    // internally fires syncNutritionData + pushSnapshot. The canonical
    // path is the WriteService — calling `SyncService.instance.*`
    // directly is now a regression. Pin the routing instead.
    expect(
      body.contains('HealthWriteService.instance.logUrine'),
      isTrue,
      reason: 'UrineColorNotifier.select must route through '
          'HealthWriteService.logUrine (E.7 canonical writer). The '
          'WriteService internally fires syncNutritionData + pushSnapshot — '
          'do NOT call them in addition.',
    );
  });

  test('CustomFoodNotifier.addCustomFood fires syncCustomItemsNow', () {
    final addStart = source.indexOf('Future<void> addCustomFood(');
    expect(addStart, isNot(-1), reason: 'addCustomFood must exist');
    final body = source.substring(addStart, addStart + 3000);

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

  // ── Task 10 — broader regression locks ────────────────────────────

  test('addWater routes through HealthWriteService.setWaterMl (audit-2026-05-16 E.7)', () {
    // Post-E.7: writes go through HealthWriteService.setWaterMl which
    // internally fires syncNutritionData + pushSnapshot. Direct calls
    // to SyncService.instance.* from addWater are now redundant — the
    // WriteService is the canonical fan-out point.
    final addStart = source.indexOf('Future<void> addWater(int ml)');
    expect(addStart, isNot(-1));
    final body = source.substring(addStart, addStart + 600);
    expect(body.contains('HealthWriteService.instance.setWaterMl'), isTrue,
        reason: 'addWater must route through HealthWriteService.setWaterMl '
            '(E.7 canonical writer).');
  });

  test('LogFoodSheet mode bodies use HiveService, never raw Hive.box(...)',
      () {
    // Each mode body either uses an existing widget that already syncs
    // (FoodLoggerSection, ScanMealSection — both fire unawaited sync
    // internally) or routes through foodLogProvider.logFromSearchItem /
    // .relogFromHistory. This test asserts none of them inline a Hive
    // put without a sync.
    for (final modeFile in const [
      'lib/features/nutrition/widgets/log_food_modes/ai_mode_body.dart',
      'lib/features/nutrition/widgets/log_food_modes/scan_mode_body.dart',
      'lib/features/nutrition/widgets/log_food_modes/cart_mode_body.dart',
      'lib/features/nutrition/widgets/log_food_modes/barcode_mode_body.dart',
      'lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart',
    ]) {
      final body = File(modeFile).readAsStringSync();
      // Must not use raw Hive.box calls — must go through HiveService.
      expect(
        body.contains("Hive.box('"),
        isFalse,
        reason: 'Mode body $modeFile must not use raw Hive.box() — '
            'route through HiveService.instance.<box> per CLAUDE.md '
            '"Raw Hive.box(...) in cold-start-reachable path" rule.',
      );
    }
  });

  test('HydrationCard delegates to existing providers (no inline writes)',
      () {
    final body = File(
      'lib/features/nutrition/widgets/hydration_card.dart',
    ).readAsStringSync();
    expect(body.contains('healthBox.put'), isFalse,
        reason: 'HydrationCard must NOT write to healthBox directly — '
            'all writes go through urineColorProvider + '
            'waterIntakeProvider, which already fire syncs.');
  });

  test('YourFoodsSection performs no writes — read-only chip strip', () {
    final body = File(
      'lib/features/nutrition/widgets/your_foods_section.dart',
    ).readAsStringSync();
    expect(body.contains('customBox.put'), isFalse,
        reason: 'YourFoodsSection is read-only. Writes go through the '
            'CustomFoodSheet -> CustomFoodNotifier.addCustomFood path, '
            'which fires syncCustomItemsNow + pushSnapshot.');
  });
}
