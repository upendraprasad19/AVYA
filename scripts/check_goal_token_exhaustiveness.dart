// scripts/check_goal_token_exhaustiveness.dart
//
// Gate (psych-skill-and-audit 2026-06-07, audit F19): guarantees a fitness-goal
// token can never again silently fall through a `default` branch — the bug where
// the default onboarding goal 'recompose' produced maintenance calories + the
// lowest protein because no calculator/plan-engine branch recognised it.
//
// Asserts:
//  1. Every onboarding goal card key (goal_screen.dart), once run through
//     plan_screen._mapGoal (explicit arm OR the `_ =>` default), yields a known
//     FitnessGoals token; and every FitnessGoals token is reachable from some
//     onboarding card (no orphan / no card mapping to a non-token).
//  2. BmrCalculator resolves the goal via `FitnessGoals.of(...)` and no longer
//     carries a raw `case 'build_muscle'` goal switch (the old fallthrough site).
//  3. The cardio gate is SoT-driven — plan_generator.dart + cardio_finisher.dart
//     no longer hardcode `goal == 'lose_fat'` / `goal == 'general_fitness'`.
//
// Exit 0 = pass. Exit 1 = a gap. `--warn-only` supported.

import 'dart:io';

String? _read(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsStringSync() : null;
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final problems = <String>[];

  final sot = _read('lib/core/constants/fitness_goals.dart');
  final goalScreen = _read('lib/features/onboarding/screens/goal_screen.dart');
  final planScreen = _read('lib/features/onboarding/screens/plan_screen.dart');
  final bmr = _read('lib/core/utils/bmr_calculator.dart');
  final planGen = _read('lib/shared/repositories/plan_engine/plan_generator.dart');
  final cardio = _read('lib/shared/repositories/plan_engine/cardio_finisher.dart');

  if (sot == null) {
    stderr.writeln('[Gate goal-tokens] ${warnOnly ? "WARN" : "FAIL"}: fitness_goals.dart missing');
    exit(warnOnly ? 0 : 1);
  }

  // FitnessGoals tokens.
  final tokens = RegExp(r"'(\w+)':\s*FitnessGoalSpec\(")
      .allMatches(sot)
      .map((m) => m.group(1)!)
      .toSet();
  if (tokens.isEmpty) problems.add('No FitnessGoals tokens parsed from fitness_goals.dart');

  // Onboarding card keys.
  final cardKeys = (goalScreen == null)
      ? <String>{}
      : RegExp(r"key:\s*'(\w+)'").allMatches(goalScreen).map((m) => m.group(1)!).toSet();

  // _mapGoal arms (input -> output) + default — SCOPED to the _mapGoal switch
  // body so sibling switches in plan_screen.dart (e.g. a goal→display-label
  // switch) aren't mistaken for goal-token arms.
  final mapArms = <String, String>{};
  String? mapDefault;
  if (planScreen == null) {
    problems.add('plan_screen.dart missing (cannot parse _mapGoal)');
  } else {
    final body = RegExp(r'_mapGoal\(String goal\)\s*=>\s*switch\s*\(goal\)\s*\{([\s\S]*?)\};')
        .firstMatch(planScreen)
        ?.group(1);
    if (body == null) {
      problems.add('Could not locate `_mapGoal(String goal) => switch (goal) {...}` in plan_screen.dart');
    } else {
      for (final m in RegExp(r"'(\w+)'\s*=>\s*'(\w+)'").allMatches(body)) {
        mapArms[m.group(1)!] = m.group(2)!;
      }
      mapDefault = RegExp(r"_\s*=>\s*'(\w+)'").firstMatch(body)?.group(1);
    }
  }

  // Check 1: every card key resolves (via arm or default) to a known token.
  final reachable = <String>{};
  for (final k in cardKeys) {
    final t = mapArms[k] ?? mapDefault;
    if (t == null) {
      problems.add('Onboarding key "$k" has no _mapGoal arm and there is no default.');
      continue;
    }
    reachable.add(t);
    if (!tokens.contains(t)) {
      problems.add('Onboarding key "$k" maps to "$t", which is not a FitnessGoals token '
          '(${tokens.join(", ")}).');
    }
  }
  // Every token should be reachable from a card (no orphan goal).
  for (final t in tokens) {
    if (cardKeys.isNotEmpty && !reachable.contains(t)) {
      problems.add('FitnessGoals token "$t" is not reachable from any onboarding goal card.');
    }
  }

  // Check 2: BmrCalculator uses the SoT, no raw goal switch.
  if (bmr != null) {
    if (!bmr.contains('FitnessGoals.of(')) {
      problems.add('bmr_calculator.dart must resolve goal targets via FitnessGoals.of(...).');
    }
    if (bmr.contains("case 'build_muscle'") || bmr.contains("case 'lose_fat'")) {
      problems.add('bmr_calculator.dart still has a raw goal `case` switch — route through FitnessGoals.');
    }
  }

  // Check 3: cardio gate is SoT-driven.
  for (final entry in {'plan_generator.dart': planGen, 'cardio_finisher.dart': cardio}.entries) {
    final src = entry.value;
    if (src == null) continue;
    if (src.contains("goal == 'lose_fat'") || src.contains("goal == 'general_fitness'")) {
      problems.add('${entry.key} hardcodes a goal-string cardio check — use FitnessGoals.of(goal).cardio.');
    }
  }

  // Check 4: the SERVER AI-coach plan tools expose a goal enum to the model.
  // Every FitnessGoals token MUST appear in each tool's enum, and neither may
  // list a goal that isn't a token. Otherwise the model can be unable to emit a
  // valid goal (zod rejects it) or can emit one the client rejects — the F19
  // fallthrough class, one tool over (recompose was added to switchGoal.ts but
  // not regeneratePlanBlock.ts). The original gate only scanned client Dart;
  // that server blind spot is exactly how this drifted.
  if (tokens.isNotEmpty) {
    final serverGoalEnums = <String, RegExp>{
      'supabase/functions/_shared/tools/plan/switchGoal.ts':
          RegExp(r'newGoal:\s*z\.enum\(\[([\s\S]*?)\]\)'),
      'supabase/functions/_shared/tools/plan/regeneratePlanBlock.ts':
          RegExp(r'goal:\s*z\.enum\(\[([\s\S]*?)\]\)'),
    };
    serverGoalEnums.forEach((path, enumRe) {
      final src = _read(path);
      if (src == null) {
        problems.add('Server goal tool missing: $path (cannot verify goal-enum parity).');
        return;
      }
      final body = enumRe.firstMatch(src)?.group(1);
      if (body == null) {
        problems.add('Could not locate the goal z.enum in $path.');
        return;
      }
      final enumTokens =
          RegExp(r'"(\w+)"').allMatches(body).map((m) => m.group(1)!).toSet();
      for (final t in tokens) {
        if (!enumTokens.contains(t)) {
          problems.add('$path goal enum is missing FitnessGoals token "$t" — '
              'the AI cannot act on this goal (F19 class).');
        }
      }
      for (final e in enumTokens) {
        if (!tokens.contains(e)) {
          problems.add('$path goal enum lists "$e", which is not a FitnessGoals '
              'token (${tokens.join(", ")}).');
        }
      }
    });
  }

  final tag = warnOnly ? '[Gate goal-tokens WARN]' : '[Gate goal-tokens]';
  if (problems.isEmpty) {
    stdout.writeln('$tag PASS: ${tokens.length} goal tokens, ${cardKeys.length} onboarding keys — all mapped + exhaustive; no raw goal fallthrough; server tools (switchGoal + regeneratePlanBlock) goal-enum parity OK.');
    exit(0);
  }
  stderr.writeln('${warnOnly ? "$tag WARN" : "$tag FAIL"}: ${problems.length} issue(s):');
  for (final p in problems) {
    stderr.writeln('  - $p');
  }
  exit(warnOnly ? 0 : 1);
}
