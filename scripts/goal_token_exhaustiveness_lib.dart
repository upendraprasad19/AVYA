// scripts/goal_token_exhaustiveness_lib.dart
//
// Pure logic behind scripts/check_goal_token_exhaustiveness.dart (Check 1 —
// onboarding card key -> _mapGoal -> FitnessGoals token reachability). Extracted
// 2026-11-01 so the allowlist added when the Recompose / Perform cards left the
// onboarding picker is mutation-proven by test/scripts/
// goal_token_exhaustiveness_lib_test.dart (CLAUDE.md §4.4 rule 24).
library;

/// Tokens that are deliberately NOT reachable from any onboarding goal card any
/// more, but stay live in `FitnessGoals` because a STORED value can still hold
/// them: older app builds write them, cloud restore brings them back, and
/// `LegacyGoalHealer` moves them (Unit 3B, founder d69 / d72; it equals
/// `FitnessGoals.legacyTargets.keys`, pinned by `fitness_goals_selectable_test.dart`).
/// Since Unit 3B no picker and no coach tool offers them: Check 4 requires the
/// server goal enums to list `tokens` MINUS this set ([serverGoalEnumProblems]).
/// Keep this NARROW: a token added here stops being checked for card reachability.
const Set<String> kLegacyReachableOnlyGoalTokens = {'recompose', 'strength'};

/// Problems for Check 1 + the orphan-token sweep.
///
/// * every card key must resolve (arm or default) to a known token;
/// * every token must be reachable from a card, unless it is in
///   [legacyReachableOnly];
/// * an allowlisted token that IS card-reachable is a stale allowlist entry.
///
/// The `cardKeys.isNotEmpty` guard is kept: with no parsed cards the orphan sweep
/// is skipped (a missing goal_screen.dart is reported elsewhere).
List<String> goalCardReachabilityProblems({
  required Set<String> tokens,
  required Set<String> cardKeys,
  required Map<String, String> mapArms,
  required String? mapDefault,
  Set<String> legacyReachableOnly = const {},
}) {
  final problems = <String>[];
  final reachable = <String>{};
  for (final k in cardKeys) {
    final t = mapArms[k] ?? mapDefault;
    if (t == null) {
      problems.add(
          'Onboarding key "$k" has no _mapGoal arm and there is no default.');
      continue;
    }
    reachable.add(t);
    if (!tokens.contains(t)) {
      problems.add('Onboarding key "$k" maps to "$t", which is not a '
          'FitnessGoals token (${tokens.join(", ")}).');
    }
  }
  for (final t in tokens) {
    if (cardKeys.isNotEmpty &&
        !reachable.contains(t) &&
        !legacyReachableOnly.contains(t)) {
      problems.add(
          'FitnessGoals token "$t" is not reachable from any onboarding goal card.');
    }
  }
  if (cardKeys.isNotEmpty) {
    for (final t in legacyReachableOnly) {
      if (reachable.contains(t)) {
        problems.add('"$t" is in the legacy-reachable-only allowlist but IS '
            'reachable from an onboarding goal card — remove the stale entry.');
      }
    }
  }
  return problems;
}

/// Problems for Check 4 (Unit 3B): a server AI-coach goal enum ([enumTokens], parsed from [path]) must list exactly
/// the SELECTABLE goals, i.e. [tokens] minus [legacyReachableOnly]. A selectable goal missing from the enum means the
/// model cannot emit it (the F19 class, one tool over); a legacy or unknown goal in the enum means the model can
/// propose a goal the client refuses.
List<String> serverGoalEnumProblems({
  required String path,
  required Set<String> tokens,
  required Set<String> enumTokens,
  Set<String> legacyReachableOnly = const {},
}) {
  final problems = <String>[];
  final selectable = tokens.difference(legacyReachableOnly);
  for (final t in selectable) {
    if (!enumTokens.contains(t)) {
      problems.add('$path goal enum is missing selectable FitnessGoals token "$t" — '
          'the AI cannot act on this goal (F19 class).');
    }
  }
  for (final e in enumTokens) {
    if (legacyReachableOnly.contains(e)) {
      problems.add('$path goal enum lists legacy goal "$e" — a stored value only, never '
          'offered (Unit 3B); the client refuses it.');
    } else if (!tokens.contains(e)) {
      problems.add('$path goal enum lists "$e", which is not a FitnessGoals token '
          '(${tokens.join(", ")}).');
    }
  }
  return problems;
}
