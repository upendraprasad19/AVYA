// C4 (ai-coach-ux-tool-integrity) — the coach meal-log path
// (_executeLogMealByText in tool_dispatcher.dart) increments
// UsageCounterService.featureAiTextLogPro, but the dispatcher's
// _invalidateNutritionProviders never invalidated
// aiTextLogRemainingProvider — the Nutrition tab "X remaining" read
// went stale after a coach meal log. The MANUAL path invalidates it
// (food_logger_section.dart, right after its increment). Same reader,
// same rule.
//
// Wiring pin (source assertion). The behavioral layer (drive the
// dispatcher with a ProviderContainer + seeded UsageCounterService and
// assert ref.read(aiTextLogRemainingProvider) reflects the decrement)
// is not tractable in the unit harness: ToolDispatcher construction
// requires live Hive boxes, SubscriptionService and the full write
// service stack (same reason conversational_log_handler_uses_write_service_test.dart
// documents its source-grep style). The pin is scoped to the
// _invalidateNutritionProviders body, so removing the invalidate call
// reddens it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  const dispatcherPath =
      'lib/features/ai_coach/services/tool_dispatcher.dart';
  const providerPath =
      'lib/features/nutrition/providers/nutrition_provider.dart';

  String _methodBody(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0),
        reason: 'Expected to find `$signature` in source.');
    final end = src.indexOf('\n  }\n', idx);
    return src.substring(idx, end > idx ? end : src.length);
  }

  group('C4 coach meal log invalidates aiTextLogRemainingProvider', () {
    test('_invalidateNutritionProviders names aiTextLogRemainingProvider',
        () {
      final src = _src(dispatcherPath);
      final body = _methodBody(
          src, 'void _invalidateNutritionProviders(Ref ref)');

      expect(
        body,
        contains('ref.invalidate(aiTextLogRemainingProvider)'),
        reason:
            'The coach meal path increments featureAiTextLogPro '
            '(_executeLogMealByText) but never refreshed the "X remaining" '
            'read. The manual path invalidates the same provider '
            '(food_logger_section.dart). Same reader, same rule.',
      );
    });

    test('aiTextLogRemainingProvider is imported in tool_dispatcher.dart',
        () {
      final src = _src(dispatcherPath);

      expect(
        src,
        contains(
            "import '../../nutrition/providers/nutrition_provider.dart'"),
        reason: 'Provider must come from nutrition_provider.dart.',
      );
      final importIdx = src.indexOf(
          "import '../../nutrition/providers/nutrition_provider.dart'");
      final importEnd = src.indexOf(';', importIdx);
      final importClause = src.substring(importIdx, importEnd);

      expect(
        importClause,
        contains('aiTextLogRemainingProvider'),
        reason:
            'The show clause must expose aiTextLogRemainingProvider, or '
            'the invalidate call would not compile.',
      );
    });

    test('aiTextLogRemainingProvider exists in nutrition_provider.dart', () {
      final src = _src(providerPath);
      expect(
        src,
        contains(
            'final aiTextLogRemainingProvider = Provider<int>((ref) {'),
        reason: 'The provider under test must exist at the declared path.',
      );
    });
  });
}
