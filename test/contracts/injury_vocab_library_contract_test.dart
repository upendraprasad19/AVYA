// Contract — the injury vocabulary MUST match the exercise library exactly.
//
// The plan engine's injury filter (exercise_repository.queryV4 :290 + the U2
// universal-pool filter) matches by exact lowercase equality against the
// library's `injury_contraindications` tokens. If InjuryVocab.canonicalTokens
// ever drifts from what the library actually tags, a UI chip / muster answer
// silently excludes ZERO exercises — the vocabulary-drift bug this whole batch
// fixes (UI `back` never matched library `lower_back`). This test FAILS the
// moment the library gains/loses/renames an injury token without updating
// InjuryVocab, so the drift can never recur silently.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';

void main() {
  test('canonicalTokens == distinct library injury_contraindications tokens', () {
    final lib = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;

    final tokens = <String>{};
    for (final e in lib) {
      final ic = (e as Map)['injury_contraindications'];
      if (ic is List) {
        for (final t in ic) {
          tokens.add(t.toString().toLowerCase().trim());
        }
      } else if (ic is String && ic.trim().isNotEmpty) {
        tokens.add(ic.toLowerCase().trim());
      }
    }

    expect(
      InjuryVocab.canonicalTokens,
      tokens,
      reason:
          'InjuryVocab.canonicalTokens drifted from the library. Library tags: '
          '${tokens.toList()..sort()}. If a token was intentionally added/'
          'removed in exercise_library.json, update InjuryVocab + the Edit-'
          'Profile chips in the same commit.',
    );
  });

  group('normalize', () {
    test('legacy chip value back → lower_back', () {
      expect(InjuryVocab.normalize(['back']), ['lower_back']);
    });

    test('free-text phrasings map to canonical tokens', () {
      expect(InjuryVocab.normalize(['lower back']), ['lower_back']);
      expect(InjuryVocab.normalize(['bad knee']), ['knee']);
      expect(InjuryVocab.normalize(['Shoulders']), ['shoulder']);
      expect(InjuryVocab.normalize(['rotator cuff']), ['shoulder']);
    });

    test('splits multi-token free text', () {
      expect(
        InjuryVocab.normalize(['lower back, bad knee']),
        ['lower_back', 'knee'],
      );
      expect(
        InjuryVocab.normalize(['shoulder and wrist']),
        ['shoulder', 'wrist'],
      );
    });

    test('drops none / empty / unmappable', () {
      expect(InjuryVocab.normalize(['none']), isEmpty);
      expect(InjuryVocab.normalize(['']), isEmpty);
      expect(InjuryVocab.normalize(['spaghetti']), isEmpty);
      expect(InjuryVocab.normalize(null), isEmpty);
      expect(InjuryVocab.normalize(['none', 'knee']), ['knee']);
    });

    test('de-duplicates preserving first-seen order', () {
      expect(
        InjuryVocab.normalize(['knee', 'back', 'lower back', 'knees']),
        ['knee', 'lower_back'],
      );
    });

    test('strips laterality (left/right) to the base library token', () {
      expect(InjuryVocab.normalize(['right_knee']), ['knee']);
      expect(InjuryVocab.normalize(['left_shoulder']), ['shoulder']);
      expect(InjuryVocab.normalize(['left knee', 'right shoulder']),
          ['knee', 'shoulder']);
      expect(InjuryVocab.normalize(['lower_back', 'right_knee']),
          ['lower_back', 'knee']);
    });

    test('already-canonical tokens pass through unchanged', () {
      expect(
        InjuryVocab.normalize(['shoulder', 'lower_back', 'hamstring']),
        ['shoulder', 'lower_back', 'hamstring'],
      );
    });
  });
}
