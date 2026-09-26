import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// OI-226 follow-up (spawn_task task_f581ec43) — 6 dispatcher failure paths
/// in tool_dispatcher.dart returned a user-visible ToolExecutionResult.failure
/// with NO ErrorTelemetry call, while every structurally-identical sibling in
/// the same file called it. The file's own comment near _executePausePlan
/// ("every dispatcher failure path logs ErrorTelemetry") was false for these
/// 6 sites. Originally found during the OI-226 exhaustive sweep (diagnose
/// f7a2c9, 2026-09-21) and deliberately deferred as a separate follow-up
/// rather than bundled into that batch (which scoped to Gemini-exhaustion
/// alerting only).
///
/// Bounded, position-scoped (not a whole-file `contains`, which would pass
/// even if a call were unreachable or landed in the wrong branch — the
/// feedback_green_check_input_set_width class): each test locates the exact
/// catch/branch window by its surrounding source and asserts the new
/// ErrorTelemetry.logEvent call + its op_type literal both fall inside it.
///
/// closes-diagnose: 2026-09-22-tool-dispatcher-telemetry-gaps-b4e7d2
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/services/tool_dispatcher.dart')
        .readAsStringSync();
  });

  group('6 previously-untelemetered dispatcher failure paths (OI-226 '
      'follow-up, b4e7d2, 2026-09-22)', () {
    test('1: on ConcurrentEditException catch (execute()) logs telemetry '
        'before returning', () {
      final catchStart =
          src.indexOf('on ConcurrentEditException catch (e) {');
      expect(catchStart, greaterThanOrEqualTo(0),
          reason: 'ConcurrentEditException catch not found in execute() — '
              'has the dispatcher been restructured?');
      final catchEnd = src.indexOf('} catch (e, stack) {', catchStart);
      expect(catchEnd, greaterThan(catchStart),
          reason: 'the outer generic catch (e, stack) that should '
              'immediately follow this one was not found — has execute() '
              'been restructured?');
      final telemetryCall =
          src.indexOf('ErrorTelemetry.logEvent(', catchStart);
      final opType = src.indexOf(
          r'tool_dispatch_${intent.type}_concurrent_edit_failed', catchStart);
      expect(
        telemetryCall >= 0 && telemetryCall < catchEnd,
        isTrue,
        reason: 'on ConcurrentEditException catch (e) in execute() must '
            'call ErrorTelemetry.logEvent before returning failure — this '
            'guard fires whenever a handler (currently only '
            '_executeSwapExercise) detects a concurrent-edit race, and a '
            'silently-swallowed race is exactly the kind of failure ops '
            'needs a breadcrumb for.',
      );
      expect(
        opType >= 0 && opType < catchEnd,
        isTrue,
        reason: 'expected op_type literal '
            "tool_dispatch_\${intent.type}_concurrent_edit_failed inside "
            'the ConcurrentEditException catch window (mirrors the '
            "adjacent catch (e, stack)'s own "
            'tool_dispatch_\${intent.type}_unexpected_failure naming).',
      );
    });

    test('2: on SwapExerciseException catch (_executeSwapExercise) logs '
        'telemetry before returning', () {
      final catchStart = src.indexOf('on SwapExerciseException catch (e) {');
      expect(catchStart, greaterThanOrEqualTo(0),
          reason: 'SwapExerciseException catch not found in '
              '_executeSwapExercise — has it been restructured?');
      final methodEnd = src.indexOf('_executeLogSet', catchStart);
      expect(methodEnd, greaterThan(catchStart),
          reason: 'the next method (_executeLogSet) was not found after '
              'this catch — has the file been restructured?');
      final telemetryCall =
          src.indexOf('ErrorTelemetry.logEvent(', catchStart);
      final opType =
          src.indexOf("'tool_dispatch_swap_exercise_failed'", catchStart);
      expect(
        telemetryCall >= 0 && telemetryCall < methodEnd,
        isTrue,
        reason: 'on SwapExerciseException catch (e) in _executeSwapExercise '
            'must call ErrorTelemetry.logEvent before returning failure — '
            'mirrors _executePausePlan\'s on PausePlanException catch, the '
            "file's own established pattern for a typed-exception failure "
            'path.',
      );
      expect(
        opType >= 0 && opType < methodEnd,
        isTrue,
        reason: 'expected op_type tool_dispatch_swap_exercise_failed inside '
            'the SwapExerciseException catch window.',
      );
    });

    test('3: on CreateCustomExerciseException catch '
        '(_executeCreateCustomExercise) logs telemetry before returning',
        () {
      final catchStart =
          src.indexOf('on CreateCustomExerciseException catch (e) {');
      expect(catchStart, greaterThanOrEqualTo(0),
          reason: 'CreateCustomExerciseException catch not found in '
              '_executeCreateCustomExercise — has it been restructured?');
      final methodEnd = src.indexOf('_executeShortenWorkout', catchStart);
      expect(methodEnd, greaterThan(catchStart),
          reason: 'the next method (_executeShortenWorkout) was not found '
              'after this catch — has the file been restructured?');
      final telemetryCall =
          src.indexOf('ErrorTelemetry.logEvent(', catchStart);
      final opType = src.indexOf(
          "'tool_dispatch_create_custom_exercise_failed'", catchStart);
      expect(
        telemetryCall >= 0 && telemetryCall < methodEnd,
        isTrue,
        reason: 'on CreateCustomExerciseException catch (e) in '
            '_executeCreateCustomExercise must call ErrorTelemetry.logEvent '
            'before returning failure — mirrors the PausePlanException '
            'pattern.',
      );
      expect(
        opType >= 0 && opType < methodEnd,
        isTrue,
        reason: 'expected op_type tool_dispatch_create_custom_exercise_failed '
            'inside the CreateCustomExerciseException catch window.',
      );
    });

    test('4: on ShortenDayException catch (_executeShortenWorkout) logs '
        'telemetry before returning', () {
      final catchStart = src.indexOf('on ShortenDayException catch (e) {');
      expect(catchStart, greaterThanOrEqualTo(0),
          reason: 'ShortenDayException catch not found in '
              '_executeShortenWorkout — has it been restructured?');
      final methodEnd =
          src.indexOf('_executeModifyWorkoutForInjury', catchStart);
      expect(methodEnd, greaterThan(catchStart),
          reason: 'the next method (_executeModifyWorkoutForInjury) was '
              'not found after this catch — has the file been '
              'restructured?');
      final telemetryCall =
          src.indexOf('ErrorTelemetry.logEvent(', catchStart);
      final opType =
          src.indexOf("'tool_dispatch_shorten_workout_failed'", catchStart);
      expect(
        telemetryCall >= 0 && telemetryCall < methodEnd,
        isTrue,
        reason: 'on ShortenDayException catch (e) in _executeShortenWorkout '
            'must call ErrorTelemetry.logEvent before returning failure — '
            'mirrors the PausePlanException pattern.',
      );
      expect(
        opType >= 0 && opType < methodEnd,
        isTrue,
        reason: 'expected op_type tool_dispatch_shorten_workout_failed '
            'inside the ShortenDayException catch window.',
      );
    });

    test('5: _executeSwitchGoal all-schedule-writes-failed branch logs '
        'telemetry before returning', () {
      final branchStart = src.indexOf(
          'Profile already changed but plan regen totally failed');
      expect(branchStart, greaterThanOrEqualTo(0),
          reason: '_executeSwitchGoal\'s all-writes-failed comment not '
              'found — has it been restructured?');
      final returnStart = src.indexOf(
          "'Goal updated but plan regenerate failed:", branchStart);
      expect(returnStart, greaterThan(branchStart),
          reason: 'the failure return that should follow this branch was '
              'not found — has _executeSwitchGoal been restructured?');
      final telemetryCall =
          src.indexOf('ErrorTelemetry.logEvent(', branchStart);
      final opType =
          src.indexOf("'tool_dispatch_switch_goal_failed'", branchStart);
      expect(
        telemetryCall >= 0 && telemetryCall < returnStart,
        isTrue,
        reason: '_executeSwitchGoal\'s all-per-date-writes-failed branch '
            'must call ErrorTelemetry.logEvent before returning failure — '
            'mirrors the aggregated-loop-failure pattern used by '
            '_executeRegeneratePlanBlock, _executeRescheduleWeek, '
            '_executeGenerateHotelWorkout and _executeScheduleTemplate. '
            'This site is worse than those siblings when it fires: the '
            'profile goal has already been changed, so a silent failure '
            'here also hides a partially-applied state.',
      );
      expect(
        opType >= 0 && opType < returnStart,
        isTrue,
        reason: 'expected op_type tool_dispatch_switch_goal_failed inside '
            'the all-writes-failed branch, before the failure return.',
      );
    });

    test('6: on CreateTemplateException catch (_executeCreateCustomTemplate) '
        'logs its OWN telemetry, distinct from the sibling generic catch',
        () {
      final catchStart = src.indexOf('on CreateTemplateException catch (e) {');
      expect(catchStart, greaterThanOrEqualTo(0),
          reason: 'CreateTemplateException catch not found in '
              '_executeCreateCustomTemplate — has it been restructured?');
      // This method ALSO has a generic `catch (e, stack)` two lines below
      // (pre-existing, op_type tool_dispatch_create_custom_template_failed)
      // — the window must end BEFORE that sibling's body so this test can't
      // be satisfied by the pre-existing call.
      final genericCatchBody = src.indexOf(
          '[ToolDispatcher] create_custom_template failed:', catchStart);
      expect(genericCatchBody, greaterThan(catchStart),
          reason: 'the sibling generic catch (e, stack) body was not found '
              'after this catch — has the method been restructured?');
      final telemetryCall =
          src.indexOf('ErrorTelemetry.logEvent(', catchStart);
      final opType = src.indexOf(
          "'tool_dispatch_create_custom_template_validation_failed'",
          catchStart);
      expect(
        telemetryCall >= 0 && telemetryCall < genericCatchBody,
        isTrue,
        reason: 'on CreateTemplateException catch (e) must call '
            'ErrorTelemetry.logEvent before returning failure. This method '
            'uniquely already had a generic catch (e, stack) with its own '
            'telemetry (tool_dispatch_create_custom_template_failed) — that '
            'pre-existing call must NOT be mistaken for covering this '
            'typed, more-informative validation-rejection catch, which '
            'fires for a different (and more common) failure class.',
      );
      expect(
        opType >= 0 && opType < genericCatchBody,
        isTrue,
        reason: 'expected a DISTINCT op_type '
            'tool_dispatch_create_custom_template_validation_failed inside '
            'the CreateTemplateException catch window — reusing the '
            'sibling generic catch\'s op_type would conflate two different '
            'failure classes in telemetry data.',
      );
    });
  });
}
