// Pure-logic tests for scripts/goal_token_exhaustiveness_lib.dart — the extraction
// behind scripts/check_goal_token_exhaustiveness.dart (Check 1). Mutation-proven
// per CLAUDE.md §4.4 rule 24 for the legacy-reachable-only allowlist added when
// the Recompose / Perform cards left the onboarding picker (2026-11-01).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../scripts/goal_token_exhaustiveness_lib.dart';

const _tokens = {
  'build_muscle',
  'lose_fat',
  'general_fitness',
  'recompose',
  'strength',
};
const _arms = {
  'recomp': 'recompose',
  'strength': 'strength',
};


void main() {
  // The three offered keys map to themselves via the default; model that with
  // identity arms so build/cut/maintain resolve.
  Map<String, String> arms() => {
        ..._arms,
        'build_muscle': 'build_muscle',
        'lose_fat': 'lose_fat',
        'general_fitness': 'general_fitness',
      };

  List<String> check({
    Set<String> tokens = _tokens,
    Set<String> cards = const {'build_muscle', 'lose_fat', 'general_fitness'},
    Set<String> legacy = const {'recompose', 'strength'},
  }) =>
      goalCardReachabilityProblems(
        tokens: tokens,
        cardKeys: cards,
        mapArms: arms(),
        mapDefault: null,
        legacyReachableOnly: legacy,
      );

  test('the shipped allowlist is exactly recompose + strength', () {
    expect(kLegacyReachableOnlyGoalTokens, {'recompose', 'strength'});
  });

  test('allowlisted tokens with no card pass', () {
    expect(check(), isEmpty);
  });

  test('WITHOUT the allowlist the same tree fails with both orphans', () {
    final p = check(legacy: const {});
    expect(p.length, 2, reason: '$p');
    expect(p.any((e) => e.contains('"recompose"')), isTrue);
    expect(p.any((e) => e.contains('"strength"')), isTrue);
  });

  test('an UNEXPLAINED orphan token still fails', () {
    final p = check(tokens: {..._tokens, 'new_goal'});
    expect(p.length, 1, reason: '$p');
    expect(p.single, contains('"new_goal"'));
  });

  test('an allowlisted token that IS card-reachable is a stale entry', () {
    final p = check(cards: const {
      'build_muscle',
      'lose_fat',
      'general_fitness',
      'recomp',
    });
    expect(p.length, 1, reason: '$p');
    expect(p.single, contains('stale'));
  });

  test('a card key mapping to a non-token fails', () {
    final p = goalCardReachabilityProblems(
      tokens: _tokens,
      cardKeys: const {'mystery'},
      mapArms: const {'mystery': 'not_a_token'},
      mapDefault: null,
      legacyReachableOnly: const {'recompose', 'strength'},
    );
    expect(p.any((e) => e.contains('not a FitnessGoals token')), isTrue);
  });

  test('a card key with no arm and no default fails', () {
    final p = goalCardReachabilityProblems(
      tokens: _tokens,
      cardKeys: const {'orphan_key'},
      mapArms: const {},
      mapDefault: null,
    );
    expect(p.any((e) => e.contains('no _mapGoal arm')), isTrue);
  });

  test('no parsed cards skips the orphan sweep (missing goal_screen.dart)', () {
    expect(
      goalCardReachabilityProblems(
        tokens: _tokens,
        cardKeys: const {},
        mapArms: const {},
        mapDefault: null,
      ),
      isEmpty,
    );
  });

  // Unit 3B (founder d69): Check 4 compares a server goal enum with the SELECTABLE
  // goals, tokens minus the legacy set.
  group('serverGoalEnumProblems (Check 4)', () {
    List<String> run(Set<String> enumTokens) => serverGoalEnumProblems(
          path: 'x.ts',
          tokens: _tokens,
          enumTokens: enumTokens,
          legacyReachableOnly: kLegacyReachableOnlyGoalTokens,
        );

    test('exactly the selectable goals passes', () {
      expect(run({'build_muscle', 'lose_fat', 'general_fitness'}), isEmpty);
    });

    test('a missing selectable goal fails', () {
      final p = run({'build_muscle', 'lose_fat'});
      expect(p, hasLength(1));
      expect(p.single, contains('missing selectable FitnessGoals token "general_fitness"'));
    });

    test('a legacy goal in the enum fails', () {
      for (final legacy in ['strength', 'recompose']) {
        final p = run({'build_muscle', 'lose_fat', 'general_fitness', legacy});
        expect(p, hasLength(1), reason: legacy);
        expect(p.single, contains('legacy goal "$legacy"'));
      }
    });

    test('a phantom goal fails', () {
      final p = run({'build_muscle', 'lose_fat', 'general_fitness', 'powerlifting'});
      expect(p, hasLength(1));
      expect(p.single, contains('"powerlifting", which is not a FitnessGoals token'));
    });

    test('with no legacy set every token is required (the pre-3B rule)', () {
      final p = serverGoalEnumProblems(
          path: 'x.ts', tokens: _tokens, enumTokens: {'build_muscle', 'lose_fat', 'general_fitness'});
      expect(p.where((e) => e.contains('missing')), hasLength(2));
    });
  });

  // Unit 3B B-pass: the client's selectableTokens list agrees with the gate's selectable set.
  group('selectableListProblems', () {
    List<String> run(String src) => selectableListProblems(
        selectableSource: src, tokens: _tokens, legacyReachableOnly: kLegacyReachableOnlyGoalTokens);

    test('the real fitness_goals.dart passes', () {
      expect(run(File('lib/core/constants/fitness_goals.dart').readAsStringSync()), isEmpty);
    });

    test('a token in neither list fails', () {
      final p = selectableListProblems(
          selectableSource: "selectableTokens = ['build_muscle', 'lose_fat', 'general_fitness'];",
          tokens: {..._tokens, 'powerlifting'},
          legacyReachableOnly: kLegacyReachableOnlyGoalTokens);
      expect(p, hasLength(1));
      expect(p.single, contains('"powerlifting" is neither'));
    });

    test('a legacy goal in the selectable list fails', () {
      final p = run("selectableTokens = ['build_muscle', 'lose_fat', 'general_fitness', 'strength'];");
      expect(p, hasLength(1));
      expect(p.single, contains('lists "strength"'));
    });

    test('an unparseable list fails closed', () {
      expect(run('nothing here'), hasLength(1));
    });
  });
}
