// Unit 3B (OI-487, founder d4 / d69 / d72 / d73, 2026-11-16): Build, Cut and Maintain are the only goals a user can
// choose; Strength and Recomposition are stored legacy values only.
//
// Plan `docs/plans/2026-11-16-generator-step3b-goal-list.md` §2.1 / §2.3.
//
// Behavioural:
//   - `FitnessGoals`: the selectable list (pinned LITERALLY, so a new goal row never becomes choosable silently), the
//     legacy targets == tokens minus selectable == the goal gate's allowlist, the labels (d73).
//   - Edit Profile's seed (`goalFormSeed`) and change label (`goalChangeLabel`).
//   - The coach: `SwitchGoalDiff` / `RegeneratePlanDiff` refuse a non-selectable goal before planning (nothing cached);
//     the dispatcher refuses it with the same sentence BEFORE the cached-plan check, and lets a selectable goal through
//     to that check.
// PRESENCE (stated): Edit Profile's dropdown, the compass chips and the chat onboarding options read the selectable
// list.
//
// Mutations (diagnose table): dispatcher back to `isKnown`; compass back to `tokens`; either diff's refusal removed;
// the seed falls back to the raw goal.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/regenerate_plan_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/ai_coach/widgets/compass_form_sheet.dart' show compassSwitchGoalMessage;
import 'package:icanbefitter/features/ai_coach/widgets/diff_preview/regenerate_plan_diff.dart';
import 'package:icanbefitter/features/ai_coach/widgets/diff_preview/switch_goal_diff.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/profile/screens/edit_profile_screen.dart' show goalFormSeed, goalChangeLabel;

import '../../scripts/goal_token_exhaustiveness_lib.dart' show kLegacyReachableOnlyGoalTokens;
import '../helpers/hive_test_setup.dart';

final _refProvider = Provider<Ref>((ref) => ref);

ToolIntent _intent(String id, String type, Map<String, dynamic> payload) => ToolIntent(
      id: id,
      type: type,
      payload: payload,
      confirmationClass: ConfirmationClass.destructive,
      previewSummary: '',
      createdAt: DateTime.now(),
    );

String _noComments(String s) => s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('FitnessGoals selectable / legacy (d69 / d72 / d73)', () {
    test('the selectable list is exactly Build, Cut, Maintain, in the onboarding cards\' order', () {
      expect(FitnessGoals.selectableTokens, ['build_muscle', 'lose_fat', 'general_fitness']);
      expect(FitnessGoals.selectableTokens.map(FitnessGoals.label), ['Build', 'Cut', 'Maintain']);
      for (final legacy in ['strength', 'recompose', null, '', 'powerlifting']) {
        expect(FitnessGoals.isSelectable(legacy), isFalse, reason: '$legacy');
      }
    });

    test('legacy targets == tokens minus selectable == the goal gate\'s allowlist; legacy labels kept', () {
      final legacy = FitnessGoals.tokens.toSet().difference(FitnessGoals.selectableTokens.toSet());
      expect(FitnessGoals.legacyTargets.keys.toSet(), legacy);
      expect(kLegacyReachableOnlyGoalTokens, legacy);
      expect(FitnessGoals.legacyTargets, {'strength': 'build_muscle', 'recompose': 'lose_fat'});
      expect(FitnessGoals.label('strength'), 'Strength');
      expect(FitnessGoals.label('recompose'), 'Recomposition');
    });
  });

  group('Edit Profile seed (goalFormSeed) and change label', () {
    test('a legacy goal opens healed, with the RAW originals', () {
      final s = goalFormSeed({'primary_goal': 'strength', 'physique_focus': 'balanced'});
      expect((s.goal, s.focus, s.originalGoal, s.originalFocus), ('build_muscle', 'strength', 'strength', 'balanced'));
      final g = goalFormSeed({'primary_goal': 'strength', 'physique_focus': 'glutes_legs'});
      expect((g.goal, g.focus), ('build_muscle', 'glutes_legs'), reason: 'a chosen focus is kept (d71)');
      final n = goalFormSeed({'primary_goal': 'strength'});
      expect((n.goal, n.focus, n.originalFocus), ('build_muscle', 'strength', 'balanced'));
      final r = goalFormSeed({'primary_goal': 'recompose', 'physique_focus': 'chest_shoulders_arms'});
      expect((r.goal, r.focus, r.originalGoal), ('lose_fat', 'chest_shoulders_arms', 'recompose'));
    });

    test('a selectable goal is unchanged; junk and a missing goal open on Maintain', () {
      for (final g in FitnessGoals.selectableTokens) {
        final s = goalFormSeed({'primary_goal': g, 'physique_focus': 'glutes_legs'});
        expect((s.goal, s.focus, s.originalGoal, s.originalFocus), (g, 'glutes_legs', g, 'glutes_legs'));
      }
      expect(goalFormSeed({'primary_goal': 'powerlifting'}).goal, 'general_fitness');
      expect(goalFormSeed({'primary_goal': 'powerlifting'}).originalGoal, 'powerlifting');
      expect(goalFormSeed(const {}).goal, 'general_fitness');
    });

    test('the change label never prints null', () {
      expect(goalChangeLabel('strength'), 'Strength');
      expect(goalChangeLabel('build_muscle'), 'Build');
      expect(goalChangeLabel('powerlifting'), 'powerlifting');
    });
  });

  group('coach previews refuse before planning', () {
    testWidgets('SwitchGoalDiff with a legacy goal shows the refusal and caches no plan', (tester) async {
      for (final goal in ['strength', 'recompose']) {
        final id = 'sg_$goal';
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SwitchGoalDiff(key: ValueKey(id), intent: _intent(id, 'switch_goal', {'new_goal': goal}))),
        ));
        await tester.pump();
        expect(find.text(FitnessGoals.notOfferedMessage), findsOneWidget, reason: goal);
        expect(find.text('GOAL CHANGE'), findsNothing);
        expect(RegeneratePlanPlanner.instance.getCachedRawSchedules(id), isNull);
      }
    });

    testWidgets('RegeneratePlanDiff with a legacy goal shows the refusal and caches no plan', (tester) async {
      for (final goal in ['strength', 'recompose']) {
        final id = 'rp_$goal';
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RegeneratePlanDiff(
                  key: ValueKey(id), intent: _intent(id, 'regenerate_plan_block', {'weeks': 4, 'goal': goal}))),
        ));
        await tester.pump();
        expect(find.text(FitnessGoals.notOfferedMessage), findsOneWidget, reason: goal);
        expect(RegeneratePlanPlanner.instance.getCachedRawSchedules(id), isNull);
      }
    });
  });

  group('ToolDispatcher refuses a non-selectable goal before the cache check (real Hive)', () {
    late Directory tempDir;
    setUp(() async => tempDir = await setUpHiveForTests());
    tearDown(() => tearDownHiveForTests(tempDir));

    Ref ref() {
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(c.dispose);
      return c.read(_refProvider);
    }

    test('switch_goal / regenerate_plan_block with strength or recompose: the sentence, no write', () async {
      await HiveService.instance.userBox.put('profile', {'primary_goal': 'general_fitness'});
      for (final goal in ['strength', 'recompose']) {
        final sw = await ToolDispatcher.instance.execute(ref(), _intent('d_sw_$goal', 'switch_goal', {'new_goal': goal}));
        expect(sw.success, isFalse);
        expect(sw.errorMessage, FitnessGoals.notOfferedMessage, reason: 'refused before "Open the diff preview first"');
        final rp = await ToolDispatcher.instance
            .execute(ref(), _intent('d_rp_$goal', 'regenerate_plan_block', {'weeks': 4, 'goal': goal}));
        expect(rp.success, isFalse);
        expect(rp.errorMessage, FitnessGoals.notOfferedMessage);
      }
      expect((HiveService.instance.userBox.get('profile') as Map)['primary_goal'], 'general_fitness');
    });

    test('a selectable goal passes the guard and reaches the cached-plan check', () async {
      await HiveService.instance.userBox.put('profile', {'primary_goal': 'general_fitness'});
      final sw =
          await ToolDispatcher.instance.execute(ref(), _intent('d_sw_ok', 'switch_goal', {'new_goal': 'lose_fat'}));
      expect(sw.success, isFalse);
      expect(sw.errorMessage, 'Open the diff preview first to compute the plan.');
    });
  });

  test('PRESENCE: every goal picker reads the selectable list', () {
    final edit = _noComments(File('lib/features/profile/screens/edit_profile_screen.dart').readAsStringSync());
    expect(edit.contains('for (final t in FitnessGoals.selectableTokens) t: FitnessGoals.label(t)'), isTrue);
    expect(edit.contains("'strength': 'Build Strength'"), isFalse);
    final compass = _noComments(File('lib/features/ai_coach/widgets/compass_form_sheet.dart').readAsStringSync());
    expect(compass.contains('FitnessGoals.selectableTokens'), isTrue);
    expect(compass.contains('FitnessGoals.tokens'), isFalse);
    final chat = _noComments(File('lib/features/onboarding/providers/onboarding_provider.dart').readAsStringSync());
    expect(chat.contains("options: ['build_muscle', 'lose_fat', 'general_fitness'],"), isTrue);
    // B-pass (d73): the legacy chat onboarding names its goal chips from the same table.
    final chatScreen =
        _noComments(File('lib/features/onboarding/screens/onboarding_chat_screen.dart').readAsStringSync());
    expect(chatScreen.contains('if (FitnessGoals.isKnown(option)) return FitnessGoals.label(option);'), isTrue);
    for (final old in ["'Build Muscle'", "'Lose Fat'", "'General Fitness'", "'Recomposition'"]) {
      expect(chatScreen.contains(old), isFalse, reason: old);
    }
    expect(compass.contains('message = compassSwitchGoalMessage(_choice!);'), isTrue);
  });

  test('the compass Switch-goal message names the goal as its chip does (d73, B-pass)', () {
    expect(compassSwitchGoalMessage('build_muscle'), 'Switch my goal to Build');
    expect(compassSwitchGoalMessage('lose_fat'), 'Switch my goal to Cut');
    expect(compassSwitchGoalMessage('general_fitness'), 'Switch my goal to Maintain');
  });
}
