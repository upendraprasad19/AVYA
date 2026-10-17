// Contract — the injury CHIP vocabulary is a single source pinned to the library.
//
// Ship 3 (U5) extracted `InjuryVocab.chipTokens` + `chipLabel` + `toggleChip` as
// the ONE source consumed by BOTH the Edit-Profile chips AND onboarding's Details
// chip. This test pins the chip token set to `canonicalTokens` (the library
// vocab), so the two UIs can never drift from each other OR the engine — closing
// the vocab-drift surface Ship 1 (a1f6c3) fought. It also pins the pure
// none-toggle invariants the two screens rely on.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';

void main() {
  group('chipTokens vocab (pinned to the library)', () {
    test('chip real-injury tokens == canonicalTokens (no UI drift)', () {
      final chipReal = InjuryVocab.chipTokens.toSet()..remove('none');
      expect(chipReal, InjuryVocab.canonicalTokens,
          reason: 'the injury chips must offer EXACTLY the library injury tokens '
              '(plus the "none" sentinel) — a mismatch means an injured user '
              "can't select a token the engine can filter, OR selects one it can't");
    });

    test('chipTokens = "none" first + the 9 canonical, ordered, no dupes', () {
      expect(InjuryVocab.chipTokens.first, 'none');
      expect(InjuryVocab.chipTokens.length,
          InjuryVocab.canonicalTokens.length + 1);
      expect(InjuryVocab.chipTokens.toSet().length,
          InjuryVocab.chipTokens.length,
          reason: 'no duplicate chip tokens');
    });

    test('every chip token has a real display label', () {
      for (final t in InjuryVocab.chipTokens) {
        expect(InjuryVocab.chipLabel(t), isNotEmpty);
      }
      expect(InjuryVocab.chipLabel('lower_back'), 'Lower Back');
      expect(InjuryVocab.chipLabel('none'), 'No injuries');
      expect(InjuryVocab.chipLabel('hamstring'), 'Hamstring');
    });
  });

  group('toggleChip invariants', () {
    test('tapping "none" resets to [none]', () {
      expect(InjuryVocab.toggleChip(['knee', 'wrist'], 'none'), ['none']);
    });

    test('tapping a real injury clears "none"', () {
      expect(InjuryVocab.toggleChip(['none'], 'knee'), ['knee']);
    });

    test('toggling an already-selected injury off removes it', () {
      expect(InjuryVocab.toggleChip(['knee', 'wrist'], 'knee'), ['wrist']);
    });

    test('deselecting the LAST real injury falls back to [none]', () {
      expect(InjuryVocab.toggleChip(['knee'], 'knee'), ['none']);
    });

    test('adding a 2nd injury keeps both and never co-presents "none"', () {
      final r = InjuryVocab.toggleChip(['knee'], 'wrist');
      expect(r, ['knee', 'wrist']);
      expect(r, isNot(contains('none')));
    });

    test('result is always GROWABLE (chip mutation) + non-empty', () {
      final r = InjuryVocab.toggleChip(['none'], 'knee');
      r.add('shoulder'); // must not throw (growable, not a cast view)
      expect(r, isNotEmpty);
    });

    test('a tap sequence never yields "none" beside a real injury, never empty',
        () {
      var state = <String>['none'];
      for (final t in [
        'knee', 'none', 'wrist', 'wrist', 'shoulder', 'none', 'hip', 'hip'
      ]) {
        state = InjuryVocab.toggleChip(state, t);
        expect(state, isNotEmpty);
        if (state.any((x) => x != 'none')) {
          expect(state, isNot(contains('none')));
        }
      }
    });
  });
}
