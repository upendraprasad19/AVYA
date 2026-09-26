// test/ai_coach/get_nutrition_history_tool_test.dart
//
// B-9: pin the contract that the registered nutrition tool list now
// includes getNutritionHistory and that its tool registration carries
// the expected wire shape (name + selectionHints + free tier).
//
// The full server-side handler logic is tested via Deno in
// supabase/functions/_shared/tools/__tests__/ (when Deno is available);
// this file pins the Dart-side / client-side discoverability contract
// — i.e. the model declaration in the registry.ts source.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getNutritionHistory tool registration', () {
    test('registry.ts imports getNutritionHistoryTool', () async {
      final file = File(
          'supabase/functions/_shared/tools/registry.ts');
      expect(file.existsSync(), isTrue, reason: 'registry.ts must exist');
      final content = await file.readAsString();
      expect(content, contains('getNutritionHistoryTool'),
          reason:
              'registry must import + register getNutritionHistoryTool so '
              'the model sees the tool in its function declarations.');
    });

    test('tool source carries free tier + selectionHints', () async {
      final file = File(
          'supabase/functions/_shared/tools/nutrition/getNutritionHistory.ts');
      expect(file.existsSync(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('tier: "free"'));
      expect(content, contains('selectionHints:'));
      expect(content, contains('Use ONLY for past dates'));
      expect(content, contains('per_day'));
      expect(content, contains('total'));
    });

    test('captain manual instructs snapshot grounding for today', () async {
      final file = File('supabase/functions/_shared/captain_manual.ts');
      expect(file.existsSync(), isTrue);
      final content = await file.readAsString();
      expect(content, contains("Today's nutrition"),
          reason: 'B-1/B-6 added this section to the manual.');
      expect(content, contains('meals_today'));
      expect(content, contains('getNutritionHistory'),
          reason:
              "Manual must reference the past-date tool name so the "
              "model is told where to route past queries.");
    });
  });
}
