import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `water_logs`
/// from docs/sot_registry.yaml.
///
/// Writers: nutrition_provider.WaterNotifier.addWater + increment + decrement,
///          health_write_service.setWaterMl (canonical water_logs writer)
/// Readers: nutrition_repository.getWaterForDate,
///          ai_coach_repository._getTodayNutrition (water_ml field)
///
/// Key: water_ml_<IST-date>. UNIQUE(user_id, date) cloud constraint.
void main() {
  late String nutritionProvSrc;
  late String nutritionRepoSrc;
  late String aiRepoSrc;

  setUpAll(() {
    final nf = File('lib/features/nutrition/providers/nutrition_provider.dart');
    expect(nf.existsSync(), isTrue,
        reason: 'nutrition_provider.dart must exist (WaterNotifier writer)');
    nutritionProvSrc = nf.readAsStringSync();

    final nr = File('lib/features/nutrition/repositories/nutrition_repository.dart');
    expect(nr.existsSync(), isTrue,
        reason: 'nutrition_repository.dart must exist (reader for water_logs)');
    nutritionRepoSrc = nr.readAsStringSync();

    final af =
        File('lib/features/ai_coach/repositories/ai_coach_repository.dart');
    expect(af.existsSync(), isTrue, reason: 'ai_coach_repository.dart must exist');
    aiRepoSrc = af.readAsStringSync();
  });

  group('water_logs writer↔reader source contract', () {
    test('writer WaterNotifier.addWater exists in nutrition_provider', () {
      expect(nutritionProvSrc.contains('addWater'), isTrue,
          reason: 'nutrition_provider must define WaterNotifier.addWater');
    });

    test('writer uses water_ml_ key prefix (IST-anchored)', () {
      expect(
          nutritionProvSrc.contains('water_ml_') ||
              nutritionProvSrc.contains("'water_ml"),
          isTrue,
          reason:
              'WaterNotifier must write water_ml_<IST-date> keys per sot_registry.hive.key_prefix');
    });

    test('writer uses istDateStr for IST-anchored date key', () {
      expect(nutritionProvSrc.contains('istDateStr'), isTrue,
          reason:
              'WaterNotifier.addWater must use istDateStr to prevent UTC/IST date mismatch');
    });

    test('reader getWaterForDate exists in nutrition_repository', () {
      expect(nutritionRepoSrc.contains('getWaterForDate') ||
          nutritionRepoSrc.contains('water_ml_'), isTrue,
          reason:
              'nutrition_repository must define getWaterForDate or read water_ml_ keys');
    });

    test('reader _getTodayNutrition includes water_ml field in AI snapshot', () {
      expect(aiRepoSrc.contains('water_ml') || aiRepoSrc.contains('water'), isTrue,
          reason:
              'ai_coach_repository._getTodayNutrition must include water data '
              'in AI snapshot so coach can advise on hydration');
    });

    test('increment and decrement exist in WaterNotifier', () {
      expect(nutritionProvSrc.contains('increment'), isTrue,
          reason: 'WaterNotifier must define increment (+250ml)');
      expect(nutritionProvSrc.contains('decrement'), isTrue,
          reason: 'WaterNotifier must define decrement');
    });

    test('canonical water writer HealthWriteService.setWaterMl exists', () {
      // audit-fixwave 2026-07-02 / F14 — the real water writer is
      // HealthWriteService.setWaterMl (water_ml_<istDate> → water_logs). The
      // dead NutritionWriteService.logWater (water_<date>, zero callers, never
      // synced) was removed; this contract now pins the writer that actually runs.
      final hf = File('lib/core/services/health_write_service.dart');
      expect(hf.existsSync(), isTrue);
      final src = hf.readAsStringSync();
      expect(src.contains('setWaterMl'), isTrue,
          reason: 'HealthWriteService must define setWaterMl (canonical water writer)');
    });
  });
}
