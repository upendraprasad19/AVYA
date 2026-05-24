// Test #11 M1+M2: Verify counter increment architectural contract.
//
// Source-scan tests (mirroring test/sync/sync_gap_test.dart pattern) that
// confirm:
//   - NutritionWriteService.logMeal does NOT call UsageCounterService.increment
//     (counter removed from save site in Test #11 M1)
//   - food_logger_section calls increment in the _analyse path (API-call site)
//   - scan_meal section: ScanMealNotifier.scanImage() in nutrition_provider
//     calls increment on success (API-call site)
//   - cart_auditor_section (via nutrition_provider CartAuditorNotifier) calls
//     increment at the analyseCart API-call site
//   - tool_dispatcher calls increment for aiCoachTool after successful write
//
// These tests are fast (file I/O only, no Hive, no Flutter) and run as part
// of `flutter test` without a device.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Test #11 M1 — counter at API-call site, not save site', () {
    test(
        'NutritionWriteService.logMeal does NOT call UsageCounterService.increment',
        () async {
      final source = await File(
              'lib/core/services/nutrition_write_service.dart')
          .readAsString();

      // Locate the logMeal method body
      final logMealIdx = source.indexOf('Future<WriteResult> logMeal');
      expect(logMealIdx, isNot(-1),
          reason: 'Could not find logMeal method in nutrition_write_service');

      final tail = source.substring(logMealIdx);
      // Find the next top-level method (two-space indent + Future/void/etc.)
      final nextMethodMatch =
          RegExp(r'\n  (Future|void|String|bool|WriteResult)', multiLine: true)
              .firstMatch(tail.substring(100)); // skip past the signature
      final body = nextMethodMatch != null
          ? tail.substring(0, 100 + nextMethodMatch.start)
          : tail;

      expect(
        body,
        isNot(contains('UsageCounterService')),
        reason:
            'Counter should be incremented at API-call site, not at save site '
            '(Test #11 M1). Found UsageCounterService reference inside logMeal body.',
      );
    });

    test('food_logger_section calls UsageCounterService.increment in _analyse path',
        () async {
      final source = await File(
              'lib/features/nutrition/widgets/food_logger_section.dart')
          .readAsString();

      // Verify the increment call exists
      expect(
        source,
        contains('UsageCounterService.instance.increment'),
        reason:
            'AI text counter must increment at the _analyse callsite in '
            'food_logger_section.dart (Test #11 M1).',
      );

      // Verify it is in the _analyse method, not a dead comment
      final analyseIdx = source.indexOf('Future<void> _analyse()');
      expect(analyseIdx, isNot(-1),
          reason: 'Could not find _analyse method');

      final analyseBody = source.substring(analyseIdx);
      expect(
        analyseBody.contains('UsageCounterService.instance.increment'),
        isTrue,
        reason:
            'UsageCounterService.increment must be called inside _analyse(), '
            'not outside it.',
      );
    });

    test(
        'ScanMealNotifier.scanImage calls UsageCounterService.increment on success',
        () async {
      final source = await File(
              'lib/features/nutrition/providers/nutrition_provider.dart')
          .readAsString();

      // Locate scanImage
      final scanImageIdx = source.indexOf('Future<void> scanImage(');
      expect(scanImageIdx, isNot(-1),
          reason: 'Could not find scanImage in nutrition_provider');

      // The increment should appear within a reasonable range after scanImage.
      // Use 2000 chars to safely cover the full method body.
      final scanImageBody = source.substring(scanImageIdx, scanImageIdx + 2000);
      // Tech-debt audit 2026-05-20 / A7 (B5 D9-D10) migrated
      // UsageCounterService from a singleton accessor to a Riverpod
      // provider. ScanMealNotifier.scanImage now reads via
      // `ref.read(usageCounterServiceProvider).increment(...)` instead
      // of `UsageCounterService.instance.increment(...)`. Accept either
      // shape — both express "increment at the API-call site".
      final hasSingletonForm =
          scanImageBody.contains('UsageCounterService.instance.increment');
      final hasProviderForm = RegExp(
              r'ref\.read\(\s*usageCounterServiceProvider\s*\)\.increment')
          .hasMatch(scanImageBody);
      expect(
        hasSingletonForm || hasProviderForm,
        isTrue,
        reason:
            'Scan counter must increment inside ScanMealNotifier.scanImage() '
            'on the API-success path (Test #11 M1). Accepts either '
            '`UsageCounterService.instance.increment` (legacy singleton) or '
            '`ref.read(usageCounterServiceProvider).increment` (post-A7).',
      );
      expect(
        scanImageBody,
        contains('featureScanMealPro'),
        reason:
            'scanImage increment must use featureScanMealPro constant.',
      );
    });

    test(
        'CartAuditorNotifier.analyseCart calls UsageCounterService.increment on success '
        '(Test #11 M2)',
        () async {
      final source = await File(
              'lib/features/nutrition/providers/nutrition_provider.dart')
          .readAsString();

      final analyseCartIdx = source.indexOf('Future<void> analyseCart(');
      expect(analyseCartIdx, isNot(-1),
          reason: 'Could not find analyseCart in nutrition_provider');

      final analyseCartBody =
          source.substring(analyseCartIdx, analyseCartIdx + 1000);
      // Same A7 migration as scanImage — accept both singleton + provider forms.
      final hasSingletonForm =
          analyseCartBody.contains('UsageCounterService.instance.increment');
      final hasProviderForm = RegExp(
              r'ref\.read\(\s*usageCounterServiceProvider\s*\)\.increment')
          .hasMatch(analyseCartBody);
      expect(
        hasSingletonForm || hasProviderForm,
        isTrue,
        reason:
            'Cart auditor counter must increment inside CartAuditorNotifier.analyseCart() '
            'on the API-success path (Test #11 M2). Accepts either singleton '
            'or provider form post-A7.',
      );
      expect(
        analyseCartBody,
        contains('featureCartAuditorPro'),
        reason:
            'analyseCart increment must use featureCartAuditorPro constant.',
      );
    });

    test(
        'tool_dispatcher._executeLogMealByText calls UsageCounterService.increment '
        'after successful write',
        () async {
      final source = await File(
              'lib/features/ai_coach/services/tool_dispatcher.dart')
          .readAsString();

      // Locate the method DEFINITION (not a call site), identified by its
      // full async signature. There may be multiple hits for the name alone
      // (e.g. in a switch case), so anchor on the 'Future<ToolExecutionResult>'
      // return type + name combo.
      final methodIdx =
          source.indexOf('Future<ToolExecutionResult> _executeLogMealByText(');
      expect(methodIdx, isNot(-1),
          reason:
              'Could not find _executeLogMealByText definition in '
              'tool_dispatcher.dart');

      // Use 2000 chars — the method is ~60 lines.
      final methodBody = source.substring(methodIdx, methodIdx + 2000);
      expect(
        methodBody,
        contains('UsageCounterService.instance.increment'),
        reason:
            'AI coach tool log_meal_by_text must increment the AI text counter '
            'after a successful write (Test #11 M1).',
      );
    });
  });

  group('Test #11 M4 — quantityG fallback to 100.0 (not 0)', () {
    test('AiBreakdownNotifier.saveMeal does not write quantityG: 0', () async {
      final source = await File(
              'lib/features/nutrition/providers/nutrition_provider.dart')
          .readAsString();

      // Locate saveMeal method
      final saveMealIdx = source.indexOf('Future<WriteResult> saveMeal(');
      expect(saveMealIdx, isNot(-1),
          reason: 'Could not find saveMeal in nutrition_provider');

      // The body of saveMeal should not have quantityG: 0
      final saveMealBody = source.substring(saveMealIdx, saveMealIdx + 1200);
      expect(
        saveMealBody,
        isNot(contains('quantityG: 0')),
        reason:
            'saveMeal must not write quantityG: 0 — use 100.0 as the canonical '
            '"per 100g" fallback (Test #11 M4).',
      );
      expect(
        saveMealBody,
        contains('quantityG: 100.0'),
        reason:
            'saveMeal must use quantityG: 100.0 as the fallback sentinel.',
      );
    });

    test('scan_meal_section _save does not write quantityG: 0', () async {
      final source = await File(
              'lib/features/nutrition/widgets/scan_meal_section.dart')
          .readAsString();

      // Find _save method
      final saveIdx = source.indexOf('Future<void> _save()');
      expect(saveIdx, isNot(-1),
          reason: 'Could not find _save in scan_meal_section.dart');

      // Use 1600 chars to cover the full _save body including the items map.
      final saveBody = source.substring(saveIdx, saveIdx + 1600);
      expect(
        saveBody,
        isNot(contains('quantityG: 0')),
        reason:
            'scan_meal_section._save must not write quantityG: 0 '
            '(Test #11 M4).',
      );
      expect(
        saveBody,
        contains('quantityG: 100.0'),
        reason:
            'scan_meal_section._save must use quantityG: 100.0 as fallback.',
      );
    });

    test('tool_dispatcher._writeFoodLogFromIntent does not write quantityG: 0',
        () async {
      final source = await File(
              'lib/features/ai_coach/services/tool_dispatcher.dart')
          .readAsString();

      final methodIdx = source.indexOf('Future<String> _writeFoodLogFromIntent(');
      expect(methodIdx, isNot(-1),
          reason:
              'Could not find _writeFoodLogFromIntent in tool_dispatcher.dart');

      final methodBody = source.substring(methodIdx, methodIdx + 1000);
      expect(
        methodBody,
        isNot(contains('quantityG: 0')),
        reason:
            '_writeFoodLogFromIntent must not write quantityG: 0 '
            '(Test #11 M4).',
      );
      expect(
        methodBody,
        contains('quantityG: 100.0'),
        reason:
            '_writeFoodLogFromIntent must use quantityG: 100.0 as fallback.',
      );
    });
  });
}
