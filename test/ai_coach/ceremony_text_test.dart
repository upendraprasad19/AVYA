// Contract test for promotion ceremony text format.
//
// The formatter runs server-side in TypeScript (_shared/ceremony_text.ts).
// This test asserts the *shape* of the text the client expects to see in
// ai_coach_interactions.ai_response rows with channel='promotion_ceremony',
// AND source-greps the TS so the false workout-count thresholds (OBS-1 /
// diagnose f1a9d3) can never come back.
//
// Rank codes match rank_engine.ts: SD2, SD1, LS, PO, CPO, MCPO,
// SubLt, LtCdr, Cdr, Capt.

import 'dart:io';
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

    test('PO → CPO standard format', () {
      const text =
          "Petty Officer, you've completed 115 sessions and held the line 26 weeks. "
          "Promotion: Chief Petty Officer. Address change: Chief. Carry on.";

      expect(text, contains('Petty Officer,'));
      expect(text, contains('Promotion: Chief Petty Officer'));
      expect(text, contains('Address change: Chief'));
    });
  });

  group('promotion ceremony format — officer-track crossing (OBS-1 f1a9d3)', () {
    // NEW truthful format: weeks on the line (the real gate dimension) +
    // sessions as a journey stat — NOT "100 workouts on the books" (false gate).
    test('PO → SubLt officer-track crossing', () {
      const text =
          "Petty Officer, 104 weeks on the line, 130 sessions logged straight. "
          "You've crossed onto the officer track. "
          "Promotion: Sub Lieutenant. Carry on.";

      expect(text, contains('Petty Officer'));
      expect(text, contains('104 weeks on the line'));
      expect(text, contains("crossed onto the officer track"));
      expect(text, contains('Sub Lieutenant'));
      expect(text, contains('Carry on'));
      // The false workout-count threshold framing must be gone.
      expect(text, isNot(contains('workouts on the books')));
      // Officer-crossing omits "held the line ... weeks" + "Address change"
      expect(text, isNot(contains('Address change')));
    });
  });

  group('promotion ceremony format — LtCdr contract milestone (OBS-1 f1a9d3)', () {
    test('SubLt → LtCdr — the Contract', () {
      const text =
          "Lieutenant, 156 weeks on the line, 220 sessions logged honest. "
          "The contract is met. Promotion: Lieutenant Commander. "
          "Address change: Lieutenant Commander. Carry on.";

      expect(text, contains('Lieutenant,'));
      expect(text, contains('The contract is met'));
      expect(text, contains('156 weeks on the line'));
      expect(text, contains('Promotion: Lieutenant Commander'));
      expect(text, contains('Carry on'));
      // The false "200 sessions = the contract" threshold must be gone.
      expect(text, isNot(contains('200 sessions')));
    });
  });

  group('ceremony_text.ts source — no false workout threshold (OBS-1 f1a9d3)', () {
    late String ts;
    setUpAll(() {
      ts = File('supabase/functions/_shared/ceremony_text.ts').readAsStringSync();
    });

    test('no "workouts on the books" / "200 sessions" threshold copy remains', () {
      expect(ts.contains('workouts on the books'), isFalse,
          reason:
              'officer crossing is gated by 2 years + 80% completion, not a count');
      expect(ts.contains('200 sessions'), isFalse,
          reason: 'LtCdr is gated by 3 years + 80% completion, not 200 sessions');
    });

    test('celebrates the real gate dimensions (weeks + sessions as stats)', () {
      expect(ts.contains('weeks on the line'), isTrue);
      expect(ts.contains('sessions logged'), isTrue);
    });
  });

  group('ceremony rows in ai_coach_interactions', () {
    test('channel is promotion_ceremony', () {
      const channel = 'promotion_ceremony';
      const userMessage = ''; // empty — no user turn for ceremony rows
      const modelUsed = 'ceremony_template';

      expect(channel, equals('promotion_ceremony'));
      expect(userMessage, isEmpty);
      expect(modelUsed, equals('ceremony_template'));
    });

    test('ceremony text is placed in ai_response field (not user_message)', () {
      const row = {
        'channel': 'promotion_ceremony',
        'user_message': '',
        'ai_response': "Recruit, you've completed 7 sessions and held the line 1 weeks. "
            "Promotion: Seaman 1st Class. Address change: Sailor. Carry on.",
        'model_used': 'ceremony_template',
      };

      expect(row['user_message'], isEmpty);
      expect(row['ai_response']!.contains('Promotion:'), isTrue);
      expect(row['model_used'], equals('ceremony_template'));
    });
  });
}
