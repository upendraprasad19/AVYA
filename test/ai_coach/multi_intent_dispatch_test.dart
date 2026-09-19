// test/ai_coach/multi_intent_dispatch_test.dart
//
// B-3: pin the contract that a multi-intent ai-proxy response yields multiple
// ToolIntents (not one collapsed intent). Pairs with B-1 captain manual
// hardening + selectionHints on logSet/rescheduleWeek/swapExercise/pausePlan.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

void main() {
  group('multi-intent parser', () {
    test('"I did back today + move Friday to today" emits 2 ToolIntents', () {
      // Simulated ai-proxy response carrying TWO functionCalls in one turn.
      // Shape mirrors what tool-loop.ts emits when Gemini fires multiple
      // function calls in the same model turn.
      final responseJson = <String, dynamic>{
        'tool_intents': [
          {
            'id': 'intent_1',
            'type': 'log_set',
            'payload': <String, dynamic>{
              'exerciseName': 'Lat Pulldown',
              'sets': [
                {'weight_kg': 40, 'reps': 10},
                {'weight_kg': 60, 'reps': 10},
              ],
            },
            'confirmationClass': 'reviewable',
            'previewSummary': 'Log Lat Pulldown 2 sets',
            'createdAt': DateTime.now().toIso8601String(),
          },
          {
            'id': 'intent_2',
            'type': 'reschedule_week',
            'payload': <String, dynamic>{
              'fromDate': '2026-05-08',
              'toDate': '2026-05-01',
            },
            'confirmationClass': 'reviewable',
            'previewSummary': 'Move Friday → today',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      };

      final intents = AiService.parseToolIntents(responseJson);

      expect(intents.length, 2,
          reason: 'multi-intent message must yield 2 ToolIntents, not 1');
      expect(intents[0].type, 'log_set');
      expect(intents[1].type, 'reschedule_week');
    });

    test('single-intent message still parses as 1 ToolIntent', () {
      final responseJson = <String, dynamic>{
        'tool_intents': [
          {
            'id': 'intent_only',
            'type': 'log_set',
            'payload': <String, dynamic>{
              'exerciseName': 'Squat',
              'sets': <Map<String, dynamic>>[],
            },
            'confirmationClass': 'reviewable',
            'previewSummary': 'Log Squat',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      };
      final intents = AiService.parseToolIntents(responseJson);
      expect(intents.length, 1);
    });

    test('empty/missing tool_intents → empty list', () {
      expect(AiService.parseToolIntents(<String, dynamic>{}), isEmpty);
      expect(
        AiService.parseToolIntents(<String, dynamic>{'tool_intents': []}),
        isEmpty,
      );
    });

    test('malformed intent skipped, valid intent kept', () {
      final responseJson = <String, dynamic>{
        'tool_intents': [
          // malformed — missing id
          {
            'type': 'log_set',
            'payload': <String, dynamic>{},
            'createdAt': DateTime.now().toIso8601String(),
          },
          // valid
          {
            'id': 'good',
            'type': 'log_set',
            'payload': <String, dynamic>{},
            'confirmationClass': 'trivial',
            'previewSummary': '',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      };
      final intents = AiService.parseToolIntents(responseJson);
      expect(intents.length, 1);
      expect(intents.first.id, 'good');
    });
  });
}
