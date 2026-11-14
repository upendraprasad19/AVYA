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
    'swapWorkoutDaysTool',
    // Coach workout parity S3 (OI-492): asks the app to re-show its own tile;
    // never completes (the slice group below).
    'requestCompletionTileTool',
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

    test('exactly 22 tools registered (FREE 10 / PRO 12)', () {
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
      expect(entries.length, 22,
          reason: 'Expected 22 distinct kept tools; found ${entries.length}: $entries');
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
      // Without the rest guard, an ad-hoc coach-logged set on a REST day would
      // mark the day "completed" and wrongly feed streak / deployment / rank.
      // Derive-only invariant: completion derives from a PLANNED workout being
      // logged, never from logging on a rest day.
      //
      // Coach workout parity 1b (OI-490): the guard moved into the ONE
      // coach-day rule `decideCoachDay` (shared with the chat card, the tile
      // and Train). Repointed, not loosened: the rule must return `rest` for
      // `type == 'rest'`, the dispatcher must decide through it, and its
      // `rest` case must return without marking. Behaviour:
      // coach_day_completion_behavioral_test.dart.
      final rule = _src('lib/features/train/services/coach_day_completion.dart');
      expect(
          rule.contains(
              "if (rawRow['type'] == 'rest') return CoachDayDecision.rest;"),
          isTrue,
          reason: 'The coach-day rule must classify a REST day as rest.');
      final at = dispatcher.indexOf('Future<void> _maybeCompleteScheduledDay(');
      expect(at, isNonNegative);
      final body = dispatcher.substring(at, dispatcher.indexOf('\n  }\n', at));
      expect(body, contains('decideCoachDay('),
          reason: 'Derived completion must decide through the shared rule.');
      final restCase = body.indexOf('case CoachDayDecision.rest:');
      expect(restCase, isNonNegative);
      expect(body.substring(restCase).trimLeft(),
          startsWith('case CoachDayDecision.rest:\n          return;'),
          reason: 'A REST day must return before any markCompleted.');
    });
  });

  // Coach workout parity S3 (OI-492; plan 3.1 1d, 5.1 S3; M3, M60). The tile
  // request asks the app to re-show its own tile and NEVER completes: the
  // dispatcher method and the Train service method it calls contain no
  // completion writer, and the only doors into the derived completion are the
  // two existing ones (a new door would also have to join the server's
  // TILE_SURFACING_TOOL_NAMES).
  group('Derive-only tool surface — the completion tile tool is derive-only', () {
    const forbidden = [
      'markCompleted(',
      'completeOnTap(',
      'afterCompletion(',
      'incrementTotalWorkouts',
      '_maybeCompleteScheduledDay(',
    ];

    // From [signature] to the next class-member line: two spaces, then
    // `Future<` or `///`.
    String slice(String src, String signature) {
      final at = src.indexOf(signature);
      expect(at, isNonNegative, reason: 'missing: $signature');
      final next = RegExp(r'\n  (Future<|///)').firstMatch(
          src.substring(at + signature.length));
      expect(next, isNotNull, reason: 'no member after $signature');
      return src.substring(at, at + signature.length + next!.start);
    }

    test('_executeRequestCompletionTile contains no completion writer', () {
      final body = slice(_src(dispatcherPath),
          'Future<ToolExecutionResult> _executeRequestCompletionTile(');
      expect(body, contains('offerTileIfPartial('));
      for (final f in forbidden) {
        expect(body.contains(f), isFalse, reason: 'tile dispatch calls $f');
      }
    });

    test('CoachDayCompletion.offerTileIfPartial contains no completion writer',
        () {
      final body = slice(
          _src('lib/features/train/services/coach_day_completion.dart'),
          'Future<CompletionTileOutcome> offerTileIfPartial(');
      expect(body, contains('CompletionPromptStore.instance.write('));
      for (final f in forbidden) {
        expect(body.contains(f), isFalse, reason: 'offerTileIfPartial calls $f');
      }
    });

    test('the surfacing door has exactly two call sites', () {
      final dispatcher = _src(dispatcherPath);
      const decl = 'Future<void> _maybeCompleteScheduledDay(';
      final declAt = dispatcher.indexOf(decl);
      expect(declAt, isNonNegative);
      final sites = RegExp(r'_maybeCompleteScheduledDay\(')
          .allMatches(dispatcher)
          .map((m) => m.start)
          .where((i) => i != declAt + decl.indexOf('_maybe'))
          .toList();
      expect(sites, hasLength(2),
          reason: 'A new caller of the derived completion is a new tile '
              'surfacing door: add it here AND to the server\'s '
              'TILE_SURFACING_TOOL_NAMES.');
      final logSet = slice(dispatcher, 'Future<ToolExecutionResult> _executeLogSet(');
      expect(logSet.contains('_maybeCompleteScheduledDay('), isTrue);
      final seamAt = dispatcher.indexOf('maybeCompleteScheduledDayForTest(');
      expect(seamAt, isNonNegative);
      expect(sites.first, lessThan(declAt),
          reason: 'the first call site sits in _executeLogSet, before the '
              'declaration');
      expect(sites.last, greaterThan(seamAt),
          reason: 'the second call site is the test seam');
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
