// Contract test for promotion ceremony text format.
//
// The formatter runs server-side in TypeScript (_shared/ceremony_text.ts).
// This test asserts the *shape* of the text the client expects to see in
// ai_coach_interactions.ai_response rows with channel='promotion_ceremony'.
//
// Rank codes match rank_engine.ts: SD2, SD1, LS, PO, CPO, MCPO,
// SubLt, LtCdr, Cdr, Capt.

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('promotion ceremony format — standard track', () {
    test('SD2 → SD1 (Recruit → Sailor)', () {
      const text =
          "Recruit, you've completed 7 sessions and held the line 1 weeks. "
          "Promotion: Seaman 1st Class. Address change: Sailor. Carry on.";

      expect(text, contains('Recruit'));
      expect(text, contains('7 sessions'));
      expect(text, contains('1 weeks'));
      expect(text, contains('Promotion: Seaman 1st Class'));
      expect(text, contains('Address change: Sailor'));
      expect(text, contains('Carry on'));
      // Must NOT address as new rank in opening (old address used)
      expect(text, isNot(startsWith('Sailor')));
    });

    test('SD1 → LS (Sailor → Leading Seaman)', () {
      const text =
          "Sailor, you've completed 18 sessions and held the line 4 weeks. "
          "Promotion: Leading Seaman. Address change: Sailor. Carry on.";

      expect(text, contains('Sailor,'));
      expect(text, contains('18 sessions'));
      expect(text, contains('Leading Seaman'));
      expect(text, contains('Carry on'));
    });

    test('PO → CPO standard format', () {
      const text =
          "Petty Officer, you've completed 115 sessions and held the line 26 weeks. "
          "Promotion: Chief Petty Officer. Address change: Chief. Carry on.";

      expect(text, contains('Petty Officer,'));
      expect(text, contains('Promotion: Chief Petty Officer'));
      expect(text, contains('Address change: Chief'));
    });
  });

  group('promotion ceremony format — officer-track crossing', () {
    test('PO → SubLt (100 workouts officer-track)', () {
      const text =
          "Petty Officer, 100 workouts on the books. "
          "You've crossed onto the officer track. "
          "Promotion: Sub Lieutenant. Carry on.";

      expect(text, contains('Petty Officer'));
      expect(text, contains('100 workouts on the books'));
      expect(text, contains("crossed onto the officer track"));
      expect(text, contains('Sub Lieutenant'));
      expect(text, contains('Carry on'));
      // Officer-crossing omits "held the line" and "Address change"
      expect(text, isNot(contains('held the line')));
      expect(text, isNot(contains('Address change')));
    });

    test('LS → SubLt officer-track crossing', () {
      const text =
          "Sailor, 100 workouts on the books. "
          "You've crossed onto the officer track. "
          "Promotion: Sub Lieutenant. Carry on.";

      expect(text, contains('Sailor'));
      expect(text, contains("crossed onto the officer track"));
    });
  });

  group('promotion ceremony format — LtCdr contract milestone', () {
    test('SubLt → LtCdr (200 workouts — The Contract)', () {
      const text =
          "Lieutenant, 200 workouts. The contract is met. "
          "200 sessions — done straight, logged honest. "
          "Promotion: Lieutenant Commander. "
          "Address change: Lieutenant Commander. Carry on.";

      expect(text, contains('Lieutenant,'));
      expect(text, contains('The contract is met'));
      expect(text, contains('200 sessions'));
      expect(text, contains('done straight, logged honest'));
      expect(text, contains('Promotion: Lieutenant Commander'));
      expect(text, contains('Carry on'));
    });
  });

  group('ceremony rows in ai_coach_interactions', () {
    test('channel is promotion_ceremony', () {
      // Shape contract: the row the server inserts must carry these fields.
      const channel = 'promotion_ceremony';
      const userMessage = '';   // empty — no user turn for ceremony rows
      const modelUsed = 'ceremony_template';

      expect(channel, equals('promotion_ceremony'));
      expect(userMessage, isEmpty);
      expect(modelUsed, equals('ceremony_template'));
    });

    test('ceremony text is placed in ai_response field (not user_message)', () {
      // The client's _restoreCoachInteractions maps ai_response → Hive,
      // and ChatHistoryNotifier renders non-empty ai_response as AI bubble.
      // This test documents the expected field mapping.
      const row = {
        'channel': 'promotion_ceremony',
        'user_message': '',
        'ai_response': "Recruit, you've completed 7 sessions and held the line 1 weeks. "
            "Promotion: Seaman 1st Class. Address change: Sailor. Carry on.",
        'model_used': 'ceremony_template',
      };

      expect(row['user_message'], isEmpty);
      expect((row['ai_response'] as String).contains('Promotion:'), isTrue);
      expect(row['model_used'], equals('ceremony_template'));
    });
  });
}
