import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `water_target`
/// from docs/sot_registry.yaml.
///
/// Writer: WaterTargetService.currentTargetMl + computeFromProfile
/// Readers: nutrition_provider.waterTargetProvider, water_quick_sheet.WaterQuickSheet
///
/// Forbidden: never hardcode 3000 (use WaterTargetService).
/// Floor: 2500 ml per founder direction 2026-05-04.
void main() {
  late String waterSvcSrc;
  late String nutritionProvSrc;

  setUpAll(() {
    final wf = File('lib/core/services/water_target_service.dart');
    expect(wf.existsSync(), isTrue,
        reason: 'water_target_service.dart must exist (writer for water_target)');
    waterSvcSrc = wf.readAsStringSync();

    final nf = File('lib/features/nutrition/providers/nutrition_provider.dart');
    expect(nf.existsSync(), isTrue, reason: 'nutrition_provider.dart must exist');
    nutritionProvSrc = nf.readAsStringSync();
  });

  group('water_target writer↔reader source contract', () {
    test('writer WaterTargetService exists with currentTargetMl', () {
      expect(waterSvcSrc.contains('WaterTargetService'), isTrue,
          reason: 'WaterTargetService class must be present');
      expect(waterSvcSrc.contains('currentTargetMl'), isTrue,
          reason:
              'WaterTargetService must expose currentTargetMl() — the ONE read path for water target');
    });

    test('writer computeFromProfile exists', () {
      expect(waterSvcSrc.contains('computeFromProfile'), isTrue,
          reason:
              'WaterTargetService must have computeFromProfile() for onboarding seed routing');
    });

    test('floor is 2500 ml (not 2000, not 3000)', () {
      expect(waterSvcSrc.contains('2500'), isTrue,
          reason:
              'WaterTargetService must enforce 2500 ml floor per founder direction 2026-05-04');
    });

    test('ceiling is 4000 ml', () {
      expect(waterSvcSrc.contains('4000'), isTrue,
          reason: 'WaterTargetService must cap at 4000 ml per sot_registry');
    });

    test('water_target_override_ml key is read', () {
      expect(waterSvcSrc.contains('water_target_override_ml'), isTrue,
          reason:
              'WaterTargetService must read the manual override key water_target_override_ml');
    });

    test('reader waterTargetProvider exists in nutrition_provider', () {
      expect(nutritionProvSrc.contains('waterTargetProvider'), isTrue,
          reason:
              'nutrition_provider must define waterTargetProvider so widgets can watch it');
    });

    test('reader waterTargetProvider calls WaterTargetService', () {
      expect(
          nutritionProvSrc.contains('WaterTargetService'), isTrue,
          reason:
              'waterTargetProvider must delegate to WaterTargetService (not inline the computation)');
    });

    test('reader WaterQuickSheet exists', () {
      final wqs = File('lib/features/home/widgets/water_quick_sheet.dart');
      expect(wqs.existsSync(), isTrue,
          reason: 'water_quick_sheet.dart must exist (reader for water_target)');
      final src = wqs.readAsStringSync();
      // Must reference the provider, not hardcode 3000
      expect(src.contains('waterTargetProvider') || src.contains('WaterTargetService'),
          isTrue,
          reason:
              'WaterQuickSheet must read waterTargetProvider or WaterTargetService '
              '(not hardcode 3000 ml)');
    });

    test('forbidden: 3000 absent from key reader files', () {
      // Hardcoded 3000 is the forbidden pattern for all readers
      final files = {
        'lib/features/home/widgets/water_quick_sheet.dart': 'WaterQuickSheet',
        'lib/features/nutrition/screens/nutrition_screen.dart': 'NutritionScreen',
      };
      for (final entry in files.entries) {
        final f = File(entry.key);
        if (!f.existsSync()) continue;
        final src = f.readAsStringSync();
        // A literal '3000' related to water target is the forbidden pattern.
        // We look for it NOT preceded by valid identifiers (like '30000')
        // The rough check: if '3000' appears but not as part of a longer number
        final hasHardcoded3000 = RegExp(r'[^0-9]3000[^0-9]').hasMatch(src);
        expect(hasHardcoded3000, isFalse,
            reason:
                '${entry.value} must not hardcode 3000 ml; use WaterTargetService.instance.currentTargetMl() '
                '(see sot_registry: forbidden_legacy_patterns)');
      }
    });
  });
}
