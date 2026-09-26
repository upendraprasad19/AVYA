// Derive-only AI tool-surface audit (2026-05-31).
//
// Founder principle: the AI coach lets users log RAW input; the app COMPUTES
// derived state. Four tools that let the AI assert a derived/future value were
// removed from the surface:
//   • logPR              — PRs derive from logSet's auto-rescan (is_pr).
//   • adjustCaloricTarget — calorie target stays derived from goal/weight.
//   • prelog             — no pre-logging of future meals; log daily.
//   • markWorkoutComplete — completion derives from logging the day's sets.
//
// This source-grep pins the removal at both chokepoints (server registry +
// client dispatcher) AND the completion-derivation wiring that replaces
// markWorkoutComplete. The full behavioral proof of derived completion is the
// live-web E2E; the PR-derive + completion primitives are pinned behaviorally
// in `coach_derived_pr_and_completion_test.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _src(String relPath) => _stripComments(File(relPath).readAsStringSync());

void main() {
  const registryPath = 'supabase/functions/_shared/tools/registry.ts';
  const dispatcherPath = 'lib/features/ai_coach/services/tool_dispatcher.dart';
  const nutritionRepoPath =
      'lib/features/nutrition/repositories/nutrition_repository.dart';

  const removedTools = ['logPRTool', 'adjustCaloricTargetTool', 'prelogTool', 'markWorkoutCompleteTool'];
  const removedIntentTypes = ['log_pr', 'adjust_caloric_target', 'prelog', 'mark_workout_complete'];
  const keptTools = [
    'logSetTool',
    'logMealByTextTool',
    'createCustomExerciseTool',
    'createCustomTemplateTool',
    'scheduleTemplateTool',
    'swapExerciseTool',
    'shortenWorkoutTool',
    'generateHotelWorkoutTool',
    'modifyWorkoutForInjuryTool',
    'rescheduleWeekTool',
    'regeneratePlanBlockTool',
    'pausePlanTool',
    'switchGoalTool',
    'getProgressSummaryTool',
    'getNutritionHistoryTool',
    'getExerciseHistoryTool',
    'getPRTimelineTool',
    'getPromotionStatusTool',
    'getFormCuesTool',
    'suggestMealTool',
  ];

  group('Derive-only tool surface — server registry', () {
    final registry = _src(registryPath);

    for (final t in removedTools) {
      test('registry no longer references $t', () {
        expect(registry.contains(t), isFalse,
            reason: '$t must be removed from ALL_TOOLS + imports (derive-only).');
      });
    }

    for (final t in keptTools) {
      test('registry still offers $t', () {
        expect(registry.contains(t), isTrue,
            reason: '$t is a kept tool and must remain in the registry.');
      });
    }

    test('exactly 20 tools registered (FREE 9 / PRO 11, down from 24)', () {
      // Count the ALL_TOOLS array entries: `  <name>Tool,` lines that are NOT
      // inside an import block. Import lines also end in `Tool,`, so scope to
      // the array body between `ALL_TOOLS` and its closing `];`.
      final raw = File(registryPath).readAsStringSync();
      final start = raw.indexOf('ALL_TOOLS');
      final end = raw.indexOf('];', start);
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final body = _stripComments(raw.substring(start, end));
      final entries =
          RegExp(r'\b\w+Tool\b').allMatches(body).map((m) => m.group(0)).toSet();
      expect(entries.length, 20,
          reason: 'Expected 20 distinct kept tools; found ${entries.length}: $entries');
    });
  });

  group('Derive-only tool surface — client dispatcher', () {
    final dispatcher = _src(dispatcherPath);

    for (final type in removedIntentTypes) {
      test("dispatcher has no case '$type'", () {
        expect(dispatcher.contains("case '$type'"), isFalse,
            reason: "Removed tool intent '$type' must not be dispatchable.");
      });
    }

    test('log_set still dispatched', () {
      expect(dispatcher.contains("case 'log_set'"), isTrue);
    });

    test('completion is derived from logging (logSet wires markCompleted)', () {
      // _executeLogSet calls _maybeCompleteScheduledDay, which reuses the
      // canonical WorkoutWriteService.markCompleted — replacing the removed
      // markWorkoutComplete tool.
      expect(dispatcher.contains('_maybeCompleteScheduledDay('), isTrue,
          reason: 'logSet must trigger derived completion.');
      expect(dispatcher.contains('markCompleted('), isTrue,
          reason: 'Derived completion must reuse the canonical markCompleted writer.');
    });

    test('derived completion skips REST days (logSet on a rest day must not '
        'flip it to completed)', () {
      // _maybeCompleteScheduledDay guards rest days: `if (raw['type'] == 'rest')
      // return;`. Without it, an ad-hoc coach-logged set on a REST day would
      // mark the day "completed" and wrongly feed streak / deployment / rank.
      // Derive-only invariant: completion derives from a PLANNED workout being
      // logged, never from logging on a rest day. (The exact `raw['type'] ==
      // 'rest'` string appears only in dispatcher CODE, not its comments.)
      expect(dispatcher.contains("raw['type'] == 'rest'"), isTrue,
          reason: 'Derived completion must skip REST days — a coach logSet on a '
              'rest day must not auto-complete it.');
    });
  });

  group('Derive-only tool surface — calorie target writer removed', () {
    test('NutritionRepository.adjustDailyTarget writer is gone', () {
      final repo = _src(nutritionRepoPath);
      expect(repo.contains('adjustDailyTarget('), isFalse,
          reason: 'The AI calorie-target override writer must be removed; '
              'the target is derived. (The read-only drain reader may remain.)');
    });
  });
}
