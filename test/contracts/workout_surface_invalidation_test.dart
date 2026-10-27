// OI-370 (diagnose: docs/diagnoses/2026-10-21-coach-chat-log-train-stale-*.md)
//
// Every coach write path refreshes the same workout surfaces through ONE
// helper, `invalidateWorkoutSurfaces`. This pins (1) the exact provider set,
// (2) that one failing invalidation never stops the rest and is reported as a
// tagged non-fatal, and (3) that the three coach paths call the helper.
// Behavioural proof that the chat path refreshes Train:
// coach_chat_log_train_refresh_behavioral_test.dart.
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/providers/workout_surface_invalidation.dart';

import '../helpers/read_screen_source.dart';

/// The body of the top-level function or method whose declaration line
/// contains [signature], up to the next line that is exactly `}` at the
/// declaration's own indent.
String bodyOf(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, isNot(-1), reason: 'signature not found: $signature');
  final lineStart = src.lastIndexOf('\n', start) + 1;
  final indent = RegExp(r'^ *').stringMatch(src.substring(lineStart))!;
  final end = src.indexOf('\n$indent}\n', start);
  expect(end, isNot(-1), reason: 'end of body not found: $signature');
  return src.substring(start, end);
}

void main() {
  tearDown(() => ErrorTelemetry.debugOnRecordNonFatalForTests = null);

  test('invalidates exactly the seven workout surfaces, in order', () {
    final seen = <ProviderOrFamily>[];
    invalidateWorkoutSurfaces(seen.add, source: 'unit');
    expect(seen, <ProviderOrFamily>[
      currentPlanProvider,
      workoutStatsProvider,
      calendarWeekProvider,
      streakProvider,
      todayWorkoutProvider,
      allExercisePRsProvider,
      lastPerformanceProvider,
    ]);
    expect(seen.toSet(), hasLength(7));
  });

  test('aiInsightProvider is left out because it follows todayWorkoutProvider',
      () {
    // B-pass fb5048e68fae F9: the omission is safe only while the insight
    // WATCHES todayWorkoutProvider (c7e3a9), which the helper invalidates.
    expect(workoutSurfaceProviders, isNot(contains(aiInsightProvider)));
    expect(workoutSurfaceProviders, contains(todayWorkoutProvider));
    final home = readSourceFileStripped(
        'lib/features/home/providers/home_provider.dart');
    final at = home.indexOf('class AiInsightNotifier');
    expect(at, isNot(-1));
    final build = home.indexOf('String? build()', at);
    final end = home.indexOf('\n  }\n', build);
    expect(home.substring(build, end),
        contains('ref.watch(todayWorkoutProvider)'));
  });

  test('one throwing invalidation does not stop the rest and is reported', () {
    final reasons = <String>[];
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) => reasons.add(reason);
    final seen = <ProviderOrFamily>[];
    invalidateWorkoutSurfaces((p) {
      if (identical(p, streakProvider)) throw StateError('boom');
      seen.add(p);
    }, source: 'unit');
    expect(seen, hasLength(6));
    expect(seen, isNot(contains(streakProvider)));
    expect(seen.last, lastPerformanceProvider,
        reason: 'entries after the failing one still run');
    expect(reasons, ['workout_surface_invalidate_unit']);
  });

  test('every throwing invalidation is reported on its own', () {
    final reasons = <String>[];
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) => reasons.add(reason);
    invalidateWorkoutSurfaces((_) => throw StateError('boom'), source: 'x');
    expect(reasons, List.filled(7, 'workout_surface_invalidate_x'));
  });

  group('the three coach write paths call the helper', () {
    test('chat draft: submitWorkoutDraft', () {
      final src = File(
              'lib/features/ai_coach/services/conversational_log_handler.dart')
          .readAsStringSync();
      final body = bodyOf(src,
          'Future<DraftSubmitOutcome> submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref)');
      expect(
          body,
          contains(
              "invalidateWorkoutSurfaces(container.invalidate, source: 'chat_draft');"));
      // B-pass fb5048e68fae F8: the card's WidgetRef may be disposed
      // mid-submit, so no write-service call is handed it (comment-stripped,
      // so a commented-out `ref: ref` does not count either way).
      final live = readSourceFileStripped(
          'lib/features/ai_coach/services/conversational_log_handler.dart');
      final liveBody = bodyOf(live,
          'Future<DraftSubmitOutcome> submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref)');
      expect(liveBody, isNot(matches(RegExp(r'\bref:\s*ref\b'))));
      expect(liveBody, contains('ProviderScope.containerOf(ref.context, listen: false)'));
    });

    test('tool dispatcher: _invalidateWorkoutProviders delegates', () {
      final src = File('lib/features/ai_coach/services/tool_dispatcher.dart')
          .readAsStringSync();
      final body = bodyOf(src, 'void _invalidateWorkoutProviders(Ref ref)');
      expect(
          body,
          contains(
              "invalidateWorkoutSurfaces(ref.invalidate, source: 'tool_dispatcher');"));
      for (final p in [
        'currentPlanProvider',
        'workoutStatsProvider',
        'calendarWeekProvider',
        'streakProvider',
        'todayWorkoutProvider',
      ]) {
        expect(body, isNot(contains('ref.invalidate($p)')),
            reason: 'no hand-kept copy of the list next to the helper');
      }
    });

    test('completion prompt handler', () {
      // AiCoachScreen needs Firebase and Supabase singletons, so this pin is
      // structural: over comment-stripped source, the call is the first
      // statement of the handler's success branch, before its else
      // (B-pass fb5048e68fae F2: a commented-out or moved call must fail).
      final src = readSourceFileStripped(
          'lib/features/ai_coach/screens/ai_coach/screen.dart');
      final handler =
          src.indexOf('Future<void> _onCompleteWorkoutFromPrompt(String date)');
      expect(handler, isNot(-1));
      final success = src.indexOf('if (result.success) {', handler);
      final orElse = src.indexOf('} else {', success);
      expect(success, greaterThan(handler));
      expect(orElse, greaterThan(success));
      final branch = src.substring(success, orElse);
      final call =
          "invalidateWorkoutSurfaces(ref.invalidate, source: 'completion_prompt');";
      expect(RegExp(RegExp.escape(call)).allMatches(src).length, 1);
      expect(
          branch.replaceAll(RegExp(r'\s+'), ' '),
          startsWith('if (result.success) { $call'),
          reason: 'the refresh is the first thing a successful completion does');
      expect(src, isNot(contains('ref.invalidate(currentPlanProvider)')));
    });
  });
}
