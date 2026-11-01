// Pure-logic tests for scripts/goal_token_exhaustiveness_lib.dart — the extraction
// behind scripts/check_goal_token_exhaustiveness.dart (Check 1). Mutation-proven
// per CLAUDE.md §4.4 rule 24 for the legacy-reachable-only allowlist added when
// the Recompose / Perform cards left the onboarding picker (2026-11-01).

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
}
