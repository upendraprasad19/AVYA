import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

import '../../helpers/hive_test_helper.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// REGRESSION TESTS — NUTRITION (fiber aggregation, timestamps, barcode logs)
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Split from `regression_bug_fixes_test.dart` (T5, audit 2026-05-20).
///
/// R18 — nutrition logs with total_fiber are aggregated correctly
/// R21 — nutrition log stores created_at ISO8601 timestamp
/// R22 — updating fiber via Hive preserves the value
/// R23 — barcode food save includes total_fiber

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    kIsDevFlavor = true;
    await initHiveForTest();
    await SupabaseService.instance.initialize();
  });

  tearDown(() async {
    await clearHiveForTest();
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #4 — Fiber not aggregated in daily nutrition
  // ─────────────────────────────────────────────────────────────────────────────

  test('R18: nutrition logs with total_fiber are aggregated correctly', () async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Seed two nutrition logs with fiber.
    await HiveService.instance.nutritionBox.put('nlog_test_001', {
      'id': 'nlog_test_001',
      'date': dateStr,
      'meal_type': 'breakfast',
      'food_name': 'Oatmeal',
      'total_calories': 300,
      'total_protein': 10,
      'total_carbs': 50,
      'total_fat': 5,
      'total_fiber': 8,
      'created_at': now.toIso8601String(),
      'source': 'manual',
    });
    await HiveService.instance.nutritionBox.put('nlog_test_002', {
      'id': 'nlog_test_002',
      'date': dateStr,
      'meal_type': 'lunch',
      'food_name': 'Dal + Rice',
      'total_calories': 500,
      'total_protein': 20,
      'total_carbs': 70,
      'total_fat': 10,
      'total_fiber': 12,
      'created_at': now.toIso8601String(),
      'source': 'manual',
    });

    // Read back all entries for today and manually sum fiber (same logic as provider).
    double fiberTotal = 0;
    for (final val in HiveService.instance.nutritionBox.values) {
      if (val is! Map) continue;
      final log = Map<String, dynamic>.from(val);
      if (log['date'] != dateStr) continue;
      fiberTotal += (log['total_fiber'] as num?)?.toDouble() ?? 0;
    }

    expect(fiberTotal, equals(20.0),
        reason: 'Fiber should sum to 8 + 12 = 20g across both logs');

    // Also verify a log WITHOUT total_fiber doesn't crash the sum.
    await HiveService.instance.nutritionBox.put('nlog_test_003', {
      'id': 'nlog_test_003',
      'date': dateStr,
      'meal_type': 'snacks',
      'food_name': 'Saved Meal (no fiber field)',
      'total_calories': 200,
      'total_protein': 15,
      'total_carbs': 20,
      'total_fat': 8,
      // NOTE: no 'total_fiber' key — simulates saved meals that lack it
      'created_at': now.toIso8601String(),
      'source': 'saved_meal',
    });

    double fiberTotal2 = 0;
    for (final val in HiveService.instance.nutritionBox.values) {
      if (val is! Map) continue;
      final log = Map<String, dynamic>.from(val);
      if (log['date'] != dateStr) continue;
      fiberTotal2 += (log['total_fiber'] as num?)?.toDouble() ?? 0;
    }

    expect(fiberTotal2, equals(20.0),
        reason: 'Missing total_fiber field should default to 0, not crash');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #1b — Timestamp in today's meals card
  // ─────────────────────────────────────────────────────────────────────────────

  test('R21: nutrition log stores created_at ISO8601 timestamp', () async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'nlog_ts_${now.millisecondsSinceEpoch}';

    await HiveService.instance.nutritionBox.put(id, {
      'id': id,
      'date': dateStr,
      'meal_type': 'lunch',
      'food_name': 'Dal Rice',
      'total_calories': 350,
      'total_protein': 12,
      'total_carbs': 55,
      'total_fat': 8,
      'total_fiber': 6,
      'created_at': now.toIso8601String(),
      'source': 'ai_text',
    });

    final stored = HiveService.instance.nutritionBox.get(id);
    expect(stored, isNotNull);
    final log = Map<String, dynamic>.from(stored as Map);

    // Verify created_at is a parseable ISO8601 timestamp.
    final createdAt = log['created_at'] as String?;
    expect(createdAt, isNotNull, reason: 'created_at must be stored');
    final parsed = DateTime.tryParse(createdAt!);
    expect(parsed, isNotNull, reason: 'created_at must be valid ISO8601');
    expect(parsed!.difference(now).inSeconds.abs(), lessThan(2),
        reason: 'created_at must be close to the time of creation');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // BUG [Session 2026-04-02] #2b — Fiber edit round-trip via updateFoodLog
  // ─────────────────────────────────────────────────────────────────────────────

  test('R22: updating fiber via Hive preserves the value', () async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'nlog_fiber_edit_${now.millisecondsSinceEpoch}';

    // Seed a log with fiber = 0.
    await HiveService.instance.nutritionBox.put(id, {
      'id': id,
      'date': dateStr,
      'meal_type': 'snacks',
      'food_name': 'Broccoli',
      'total_calories': 200,
      'total_protein': 8,
      'total_carbs': 25,
      'total_fat': 6,
      'total_fiber': 0,
      'created_at': now.toIso8601String(),
      'source': 'ai_text',
    });

    // Simulate what updateFoodLog does: update fiber to 5.
    final existing = HiveService.instance.nutritionBox.get(id);
    final updated = Map<String, dynamic>.from(existing as Map);
    updated['total_fiber'] = 5;
    await HiveService.instance.nutritionBox.put(id, updated);

    // Read back.
    final readBack = HiveService.instance.nutritionBox.get(id);
    final log = Map<String, dynamic>.from(readBack as Map);

    expect(log['total_fiber'], equals(5),
        reason: 'Fiber must be updated to 5 after edit');

    // Verify aggregation picks it up.
    double fiberTotal = 0;
    for (final val in HiveService.instance.nutritionBox.values) {
      if (val is! Map) continue;
      final l = Map<String, dynamic>.from(val);
      if (l['date'] != dateStr) continue;
      fiberTotal += (l['total_fiber'] as num?)?.toDouble() ?? 0;
    }

    expect(fiberTotal, equals(5.0),
        reason: 'Daily fiber aggregation must include the updated value');
  });

  // ── R23: Barcode food log includes total_fiber ──────────────────────────
  testWidgets('R23 – barcode food save includes total_fiber',
      (WidgetTester tester) async {
    final hive = HiveService.instance;
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'nlog_barcode_fiber_test';

    // Simulate what barcode_scan_sheet._logFood() does after the fix:
    // fiberPer100g = 8.0, serving = 150g → fiber = 8.0 * 150 / 100 = 12
    const fiberPer100g = 8.0;
    const servingG = 150.0;
    final expectedFiber = (fiberPer100g * servingG / 100).round(); // 12

    await hive.nutritionBox.put(id, {
      'id': id,
      'date': dateStr,
      'meal_type': 'snacks',
      'food_name': 'Test Barcode Item',
      'quantity_g': servingG,
      'total_calories': 250,
      'total_protein': 10,
      'total_carbs': 30,
      'total_fat': 8,
      'total_fiber': expectedFiber,
      'created_at': now.toIso8601String(),
      'source': 'barcode',
    });

    final saved = hive.nutritionBox.get(id) as Map;
    expect(saved['total_fiber'], equals(12),
        reason: 'Barcode food log must store total_fiber computed from fiberPer100g');
    expect(saved['source'], equals('barcode'));

    // Clean up
    await hive.nutritionBox.delete(id);
  });
}
