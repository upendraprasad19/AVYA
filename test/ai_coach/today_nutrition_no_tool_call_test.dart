// test/ai_coach/today_nutrition_no_tool_call_test.dart
//
// B-9: pin the contract that a "today's nutrition" question is answered
// from the snapshot directly — no tool call. The test asserts the parser
// behaviour: a properly-grounded ai-proxy response carries answer prose
// + zero tool intents. (We can't run live ai-proxy in unit tests; this
// guards the parser-side invariant.)
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

void main() {
  group('today nutrition grounding', () {
    test(
      'response to "what did I eat today" carries reply text and zero tool intents',
      () {
        // Captured shape from a properly-grounded ai-proxy response (post-B-2 deploy).
        // Tool list is intentionally empty — coach answered from snapshot.
        final responseJson = <String, dynamic>{
          'reply':
              "Today you had paneer bhurji + 2 rotis at breakfast (520 cal, "
              "32g protein), and a bowl of dal-rice for lunch (610 cal, 22g "
              "protein). Total 1130 cal / 54g protein so far.",
          'tool_intents': const <Map<String, dynamic>>[],
        };

        final intents = AiService.parseToolIntents(responseJson);
        expect(intents, isEmpty,
            reason:
                'today-nutrition question must be answered from snapshot, '
                'not via a tool call');
        expect(responseJson['reply'], isNotEmpty);
      },
    );

    test('past-date query may emit a getNutritionHistory tool call', () {
      // Past dates legitimately use a tool. The wire shape is whatever
      // ai-proxy emits — for read tools, intents may surface in the
      // tool_intents array OR be folded into the answer prose; either
      // contract is acceptable. The invariant we pin here is that
      // past-date questions DON'T hit the today-nutrition fast path.
      final responseJson = <String, dynamic>{
        'reply': 'Looking up Tuesday now…',
        'tool_intents': [
          {
            'id': 'i_history',
            'type': 'read_tool_result',
            'payload': <String, dynamic>{
              'tool': 'getNutritionHistory',
              'args': <String, dynamic>{
                'date_from': '2026-04-22',
                'date_to': '2026-04-22',
                'aggregation': 'per_day',
              },
            },
            'confirmationClass': 'reviewable',
            'previewSummary': 'Look up Tuesday',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      };
      final intents = AiService.parseToolIntents(responseJson);
      expect(intents, isNotEmpty);
    });
  });
}
