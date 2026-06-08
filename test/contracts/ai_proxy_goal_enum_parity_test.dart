import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F19 sibling (audit 2026-06-07 follow-up, 2026-06-08): the canonical
/// `FitnessGoals` tokens are the source of truth for which fitness goals exist.
/// The two server AI-coach plan tools — `switchGoal` and `regeneratePlanBlock`
/// — each expose a `goal` enum to the model. If a token is missing from a server
/// enum, the AI either CANNOT emit that goal (zod rejects the tool call) or emits
/// one the client rejects: the exact F19 fallthrough class, one tool over.
///
/// 'recompose' had been added to switchGoal.ts but NOT regeneratePlanBlock.ts —
/// so a recompose user whose "regenerate my plan for a recomp" routed to
/// regeneratePlanBlock would hit a hard zod rejection. This pins BOTH server
/// enums to the client SoT so neither can drift (missing OR phantom goal) again.
///
/// The original `scripts/check_goal_token_exhaustiveness.dart` gate only scanned
/// client Dart — this test (+ that gate's new Check 4) closes the server blind
/// spot that let the drift exist. Comment-stripped to match the parity pattern
/// in `ai_message_limit_parity_test.dart`.
void main() {
  String stripComments(String s) {
    final noBlock = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    return noBlock
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i >= 0 ? l.substring(0, i) : l;
        })
        .join('\n');
  }

  Set<String> fitnessGoalTokens() {
    final src = stripComments(
        File('lib/core/constants/fitness_goals.dart').readAsStringSync());
    return RegExp(r"'(\w+)':\s*FitnessGoalSpec\(")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toSet();
  }

  Set<String> serverGoalEnum(String path, RegExp enumRe) {
    final src = stripComments(File(path).readAsStringSync());
    final body = enumRe.firstMatch(src)?.group(1);
    expect(body, isNotNull, reason: 'goal z.enum not found in $path');
    return RegExp(r'"(\w+)"').allMatches(body!).map((m) => m.group(1)!).toSet();
  }

  const switchGoalPath =
      'supabase/functions/_shared/tools/plan/switchGoal.ts';
  const regenPath =
      'supabase/functions/_shared/tools/plan/regeneratePlanBlock.ts';

  test('FitnessGoals tokens parse and include recompose (sanity)', () {
    final tokens = fitnessGoalTokens();
    expect(tokens, isNotEmpty,
        reason: 'no FitnessGoalSpec tokens parsed from fitness_goals.dart');
    expect(tokens, contains('recompose'),
        reason: 'recompose is a canonical goal (F19) — must be in the SoT');
  });

  test('switchGoal.ts newGoal enum == FitnessGoals tokens (no missing, no phantom)',
      () {
    final tokens = fitnessGoalTokens();
    final enumTokens = serverGoalEnum(
      switchGoalPath,
      RegExp(r'newGoal:\s*z\.enum\(\[([\s\S]*?)\]\)'),
    );
    expect(tokens.difference(enumTokens), isEmpty,
        reason: 'switchGoal newGoal enum is MISSING FitnessGoals token(s): '
            '${tokens.difference(enumTokens)} — the AI cannot switch to that '
            'goal (F19 fallthrough class).');
    expect(enumTokens.difference(tokens), isEmpty,
        reason: 'switchGoal newGoal enum lists non-token goal(s): '
            '${enumTokens.difference(tokens)} — the client would reject it.');
  });

  test('regeneratePlanBlock.ts goal enum == FitnessGoals tokens (no missing, no phantom)',
      () {
    final tokens = fitnessGoalTokens();
    final enumTokens = serverGoalEnum(
      regenPath,
      RegExp(r'goal:\s*z\.enum\(\[([\s\S]*?)\]\)'),
    );
    expect(tokens.difference(enumTokens), isEmpty,
        reason: 'regeneratePlanBlock goal enum is MISSING FitnessGoals '
            'token(s): ${tokens.difference(enumTokens)} — recompose was the '
            'one that drifted (F19 sibling).');
    expect(enumTokens.difference(tokens), isEmpty,
        reason: 'regeneratePlanBlock goal enum lists non-token goal(s): '
            '${enumTokens.difference(tokens)} — the client would reject it.');
  });
}
