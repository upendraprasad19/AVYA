---
bug_id: b4e7d2
date: 2026-09-22
batch: tool-dispatcher-telemetry-gaps (OI-226 follow-up, spawn_task task_f581ec43)
status: fixed
blast_radius: account
symptom: |
  tool_dispatcher.dart's own comment near _executePausePlan asserts "every
  dispatcher failure path logs ErrorTelemetry" (C5 comment, originally added
  to justify that method's own telemetry call). This was false for 6 sites:
  each returned a user-visible ToolExecutionResult.failure (rendered as a
  persistent red card via ToolConfirmCard._buildFailedState, or an immediate
  SnackBar) with NO ErrorTelemetry call, while every structurally-identical
  sibling in the same file did call it. A user hitting one of these 6 paths
  left zero breadcrumb in client_errors — founder/ops had no visibility into
  which failure class fired, how often, or with what underlying exception.
  Originally found during the OI-226 exhaustive sweep of every AI/network
  catch block in this file (diagnose f7a2c9, 2026-09-21) and deliberately
  deferred as a separate follow-up (spawn_task task_f581ec43) rather than
  bundled into that batch — these are business-validation-rejection paths
  (concurrent-edit races, swap/create/shorten/template exceptions, a
  partial-profile-write failure), a different bug class from f7a2c9's scope
  (Gemini-exhaustion alerting on AI/network calls).
concept: tool_dispatcher_failure_telemetry
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "execute() — on ConcurrentEditException catch", line: 228 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeSwapExercise — on SwapExerciseException catch", line: 299 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeCreateCustomExercise — on CreateCustomExerciseException catch", line: 574 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeShortenWorkout — on ShortenDayException catch", line: 601 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeSwitchGoal — all-per-date-writes-failed branch", line: 1338 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeCreateCustomTemplate — on CreateTemplateException catch", line: 1407 }
readers:
  - { file: test/contracts/tool_dispatcher_telemetry_gaps_test.dart, method_or_widget: "test 1 (ConcurrentEditException)", line: 31 }
  - { file: test/contracts/tool_dispatcher_telemetry_gaps_test.dart, method_or_widget: "test 2 (SwapExerciseException)", line: 68 }
  - { file: test/contracts/tool_dispatcher_telemetry_gaps_test.dart, method_or_widget: "test 3 (CreateCustomExerciseException)", line: 99 }
  - { file: test/contracts/tool_dispatcher_telemetry_gaps_test.dart, method_or_widget: "test 4 (ShortenDayException)", line: 131 }
  - { file: test/contracts/tool_dispatcher_telemetry_gaps_test.dart, method_or_widget: "test 5 (_executeSwitchGoal)", line: 162 }
  - { file: test/contracts/tool_dispatcher_telemetry_gaps_test.dart, method_or_widget: "test 6 (CreateTemplateException)", line: 198 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: client_errors
cloud_columns: [op_type, message]
contract_test_path: test/contracts/tool_dispatcher_telemetry_gaps_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - "tool_dispatch_${intent.type}_concurrent_edit_failed"
    - "tool_dispatch_swap_exercise_failed"
    - "tool_dispatch_create_custom_exercise_failed"
    - "tool_dispatch_shorten_workout_failed"
    - "tool_dispatch_switch_goal_failed"
    - "tool_dispatch_create_custom_template_validation_failed"
cross_account_guard: Not applicable — writes go through the existing, already-shared ErrorTelemetry.logEvent/recordNonFatal service used by all 13 pre-existing call sites in this file; no new Hive/cloud domain data is read or written, only op_type + a clipped error string.
forbidden_patterns_checked:
  - "New op_type strings do not collide with any of the 13 pre-existing ones in this file (verified via grep — 19 total call sites, 19 distinct op_type literals)."
  - "The CreateTemplateException fix does NOT reuse the sibling generic catch's existing op_type (tool_dispatch_create_custom_template_failed) — a distinct tool_dispatch_create_custom_template_validation_failed was used so the two failure classes (validation-rejection vs unexpected/system) stay distinguishable in telemetry data."
  - "None of the 6 new op_types were added to ErrorTelemetry.isHighPriorityOpType's allowlist — verified none of the 13 pre-existing tool_dispatch_* op_types are registered there either, so this keeps uniform treatment with the established sibling convention rather than special-casing the new ones."
proposed_fix: |
  Re-verified all 6 sites and their exact current code shape directly (line
  numbers had drifted since the OI-226 sweep, as expected) rather than
  trusting the OI-226 diagnose-doc's citations. For each, added an
  `unawaited(ErrorTelemetry.logEvent(...))` call before the existing
  `return ToolExecutionResult.failure(...)`, mirroring the file's own
  established conventions exactly, confirmed by reading every sibling call
  site first:

  - 5 of the 6 are typed-exception catches (`on <X>Exception catch (e)`).
    _executePausePlan's `on PausePlanException catch (e)` was the closest
    live precedent — its own comment ("C5 — mirror the reschedule/
    modify-for-injury failure paths: every dispatcher failure path logs
    ErrorTelemetry") is the exact comment the OI-226 sweep's brief cited as
    now-false. All 5 exception classes involved (SwapExerciseException,
    CreateCustomExerciseException, ShortenDayException, CreateTemplateException,
    PausePlanException) were confirmed via grep to share an identical
    `{code, message}` shape, so each new call uses
    `message: '${e.code}: ${e.message}'`, matching PausePlanException's own
    call exactly — except ConcurrentEditException, which only has a `.reason`
    field (confirmed by reading its class body), so that one uses
    `message: e.reason`.
  - The 6th (_executeSwitchGoal's all-per-date-writes-failed branch) is an
    aggregated-loop-failure shape, not a typed catch. Its 4 structural
    siblings (_executeRegeneratePlanBlock, _executeRescheduleWeek,
    _executeGenerateHotelWorkout, _executeScheduleTemplate) all follow the
    same pattern: `errors.join('; ')`, clip to 500 chars, then
    `ErrorTelemetry.logEvent('tool_dispatch_<action>_failed', message: clipped)`
    before the failure return. Applied verbatim, op_type
    `tool_dispatch_switch_goal_failed`. This site is worse than its 4
    siblings when it fires: by this point in the method the profile's
    `primary_goal` has ALREADY been written (via `ProfileWriteService`)
    before the schedule-write loop runs, so a total schedule-write failure
    here leaves the user in a partially-applied state (new goal, old plan) —
    the existing comment at this site already says as much, but until now
    that partial-state failure left no telemetry trail either.

  Op_type naming: mirrored the file's own two conventions — a static
  `tool_dispatch_<action>_failed` name for calls scoped inside one named
  method (4 of the 6), and the file's own dynamic
  `tool_dispatch_${intent.type}_<suffix>_failed` convention (used one catch
  block below it, in the outer generic `catch (e, stack)`) for the
  ConcurrentEditException catch, which lives in the outer `execute()`
  dispatcher rather than inside one specific handler method.
regression_test_planned:
  - test/contracts/tool_dispatcher_telemetry_gaps_test.dart
impact_analysis: |
  Purely additive telemetry — no change to any existing return value, error
  message, or control-flow branch. Every new call is `unawaited` (fire-and-
  forget, matching all 13 pre-existing sibling calls in this file) and is
  inserted before an existing, unmodified `return` statement, so the
  synchronous behavior every existing test observes is unchanged (confirmed:
  the full pre-existing test suite for this file's call sites — the 19
  dispatch/reschedule/pause/etc. tests under test/ai_coach/ and
  test/contracts/ — needed no changes). The only observable effect is 6 new
  possible rows in the client_errors table on failure paths that previously
  wrote nothing. Zero risk to the running app; risk is entirely in "did I
  place the call in the right branch", which the mutation-proof below
  verifies directly.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart: No issues found (223.3s, cold). flutter test test/contracts/tool_dispatcher_telemetry_gaps_test.dart: 6/6 passed." }
mutation_proven:
  mutated: "Reverted all 6 additions in tool_dispatcher.dart to their exact pre-fix text (deleted the unawaited(ErrorTelemetry...) call text outright at each site, not commented out — a commented-out call would leave the searched op_type substring intact and falsely pass a position-scoped indexOf check). Confirmed applied: grep count of ErrorTelemetry.logEvent|recordNonFatal call sites in the file dropped from 19 back to the pre-fix 13."
  result: "flutter test test/contracts/tool_dispatcher_telemetry_gaps_test.dart against the reverted source: RED, exactly 6 of 6 failures, each citing its own correctly-attributed reason (e.g. test 6 failed on 'on CreateTemplateException catch (e) must call ErrorTelemetry.logEvent...', not a generic/shared message) — proving each test is independently discriminating for its own specific site rather than a check that would pass regardless. Re-applied all 6 additions (restoring the exact fixed text); grep count returned to 19; re-ran the same test file: GREEN, 6/6 passed again."
  confirmed_applied: "Grepped the op_type literal count before and after both the revert and the restore (13 -> 19 -> 13 -> 19) rather than trusting the Edit tool's own success report."
---

## Summary

6 dispatcher failure paths in `tool_dispatcher.dart` returned a user-visible
failure with no `ErrorTelemetry` breadcrumb, while every structurally
identical sibling in the same file did log one. Pre-identified during the
OI-226 exhaustive sweep (diagnose f7a2c9, 2026-09-21) and deliberately
deferred as a separate follow-up task rather than bundled into that batch.

## Root cause

Incremental accretion: as new tool-dispatcher handlers were added over time,
each one that introduced a typed exception or an aggregated-loop-failure
shape independently decided whether to add telemetry, and 6 either predated
the file's own "every dispatcher failure path logs ErrorTelemetry" convention
or were added without sweeping the file for that convention first — the same
`feedback_green_check_input_set_width` class this project has hit repeatedly
elsewhere (a fix/convention lands but not every existing site that should
honor it gets swept).

## Fix

Added `unawaited(ErrorTelemetry.logEvent(...))` at all 6 sites, matching the
file's own two existing patterns exactly (typed-exception `{code, message}`
shape mirroring `_executePausePlan`; aggregated-loop-failure shape mirroring
`_executeRegeneratePlanBlock` / `_executeRescheduleWeek` /
`_executeGenerateHotelWorkout` / `_executeScheduleTemplate`). See
`proposed_fix` above for the full per-site detail and exact line numbers.

## Verification

- `flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart`: No
  issues found.
- `flutter test test/contracts/tool_dispatcher_telemetry_gaps_test.dart`:
  6/6 green.
- Mutation proof: reverting all 6 additions reproduces exactly 6 distinct,
  correctly-attributed failures; restoring returns to 6/6 green. See
  `mutation_proven` above.

## Files changed

- Modified: `lib/features/ai_coach/services/tool_dispatcher.dart`
- Created: `test/contracts/tool_dispatcher_telemetry_gaps_test.dart`
- Created: this diagnose-doc.
