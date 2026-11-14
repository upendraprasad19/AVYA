---
bug_id: e2a418
date: 2026-10-21
batch: train-coach-log-refresh (OI-370)
status: fixed_in_code
tier: m_fix
blast_radius: account
symptom: >-
  Founder's A12 web walk 2026-10-21 (app.icanbefitter.com): today was already DONE on Train with two exercises logged
  in Active Workout. A workout logged from the coach chat (`CONFIRM · LOG WORKOUT` on the chat workout card) saved, but
  Train's expanded day row still showed only the first two exercises until a page reload. The same log through the
  coach's typed `logSet` tool (APPLY) refreshed the row at once.
concept: workout_surface_invalidation — every coach write path refreshes the same workout surfaces through one helper.
sot_registry_entry: workout_surface_invalidation
writers:
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method_or_widget: "submitWorkoutDraft: invalidateWorkoutSurfaces(container.invalidate, source: 'chat_draft') after a save", line: 415 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_invalidateWorkoutProviders delegates to the helper", line: 1832 }
  - { file: lib/features/ai_coach/screens/ai_coach/screen.dart, method_or_widget: "completion-prompt handler delegates to the helper", line: 371 }
  - { file: lib/features/train/providers/workout_surface_invalidation.dart, method_or_widget: "workoutSurfaceProviders + invalidateWorkoutSurfaces (per-entry guarded)", line: 16 }
readers:
  - { file: lib/features/train/screens/train/screen.dart, method_or_widget: "TrainScreen.build watches currentPlanProvider; the expanded row reads getExerciseLogsForDate in that build", line: 118 }
  - { file: lib/features/train/screens/train/expanded_exercises.dart, method_or_widget: "_buildExpandedExercises: WorkoutRepository.instance.getExerciseLogsForDate(day.date!)", line: 7 }
  - { file: lib/features/train/screens/train/week_rows.dart, method_or_widget: "the expanded row is built only for a done day", line: 78 }
hive_key_prefix: exlog_
hive_key_formula: "exlog_<istDateStr>_<hash(name)> (WorkoutWriteService.logExercise); unchanged"
sync_methods: [syncWorkoutData]
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/coach_chat_log_train_refresh_behavioral_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, fn: istDateStr, note: "unchanged; the chat path writes with the draft's first-attempt date" }
provider_invalidations:
  - "currentPlanProvider, workoutStatsProvider, calendarWeekProvider, streakProvider, todayWorkoutProvider, allExercisePRsProvider, lastPerformanceProvider (the whole family) — workoutSurfaceProviders"
telemetry_op_types:
  success: ["none new"]
  failure: ["ErrorTelemetry.recordNonFatal reason workout_surface_invalidate_<source> (chat_draft | tool_dispatcher | completion_prompt), one per failing entry"]
cross_account_guard: "unchanged: the invalidated providers watch authUserIdTokenProvider; the chat submit stops before any further write or invalidation when the draft id changes mid-submit (an auth change)."
forbidden_patterns_checked:
  - "a fourth hand-kept copy of the invalidation list in submitWorkoutDraft — REJECTED: the drift between copies is the bug; the three coach paths call one helper, pinned by test/contracts/workout_surface_invalidation_test.dart."
  - "relying on WorkoutWriteService.onInvalidate — REJECTED: it is declared and never assigned (workout_write_service.dart:86); its callers' comments claimed it 'handles the full batch', which is how this hid. Tracked as OI-376."
  - "invalidating through the card's WidgetRef after the await — REJECTED: the card can be unmounted mid-submit (b7f3e2 class); the container is captured before the first await."
proposed_fix: >-
  One helper `invalidateWorkoutSurfaces(invalidate, source:)` in lib/features/train/providers/workout_surface_invalidation.dart
  invalidates the seven workout surfaces, each entry guarded with a tagged non-fatal. `submitWorkoutDraft` calls it
  through the container captured before its first await whenever anything saved; the ToolDispatcher and the
  completion-prompt handler delegate to it instead of their own lists.
regression_test_planned:
  - "test/contracts/coach_chat_log_train_refresh_behavioral_test.dart: real Hive + real TrainScreen, today DONE and expanded; the chat path (Train visible and Train offstage under TickerMode(false)) shows the new row after one pump with no manual invalidate; the tool path control; the card unmounted mid-submit still refreshes. Riverpod's upstream paused-count assertion (OI-378) is collected by a zone that keeps only that assertion (collector self-test included); the offstage tool case asserts it fired, as the OI's tripwire."
  - "test/contracts/workout_surface_invalidation_test.dart: exactly the seven providers in order; one throwing entry does not stop the rest and is reported; source pins that the three coach paths call the helper."
mutation_proof: >-
  Run by a scripted harness (scratchpad mut/run.py: exact-one-match replace, flutter test on the named files, restore in
  a finally, byte-compared). chat path back to its old list without currentPlanProvider: behavioural chat cases red;
  helper without currentPlanProvider: behavioural + unit red; helper without lastPerformanceProvider: unit red;
  dispatcher / prompt handler not delegating: unit pins red; per-entry try/catch collapsed into one: unit red;
  invalidation through ref instead of the captured container: disposed-card case red; collector accepting any error:
  collector self-test red. After the B-pass (fb5048e68fae): the prompt call commented out, the insight reading instead
  of watching todayWorkoutProvider, the helper's account rule removed: all red. Counts per mutation are in
  docs/audit/train-coach-log-refresh.closure.yaml. Self-attested.
impact_analysis: >-
  The chat path now refreshes Train, Home's today card, stats, streak, calendar, PRs and the last-performance hints. On
  a done day it also refreshes the "LAST" hint of an open Active Workout, which can re-baseline on today's sets
  (OI-376 notes it; pre-existing for the tool path). No data shape changes.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ clean; the behavioural and unit tests above green" }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "exlog_/wlog_ keys unchanged; the behavioural test writes through the real WorkoutWriteService into a real Hive temp dir" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no schema change" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "client-only fix" }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "the sync fan-out after logExercise is unchanged" }
recurrence: "Recurrence of the provider-invalidation-miss class: 344121 (foodLogProvider missing from the invalidation set, 2026-05-06), bae4dd (day rollover missed providers, 2026-09-28). The known-good fix, one shared list instead of hand-kept copies, is applied to the three coach paths; the remaining copies are OI-376. Searched INDEX for invalidat/stale/refresh and the concept tokens (currentPlanProvider, submitWorkoutDraft)."
related_bugs:
  - 344121
  - bae4dd
  - b7f3e2
---

# The coach chat log did not refresh Train's expanded day row

## What was wrong

`submitWorkoutDraft` (`conversational_log_handler.dart:282` on origin/main) wrote the sets and then invalidated only
`calendarWeekProvider`, `streakProvider` and `todayWorkoutProvider` (`:326-328`). Train's expanded row is built inside
`TrainScreen.build`, which watches `currentPlanProvider`; nothing invalidated it, so the row kept the logs it had read
before the chat log. The coach's typed `logSet` tool goes through `ToolDispatcher._invalidateWorkoutProviders`, which
does invalidate `currentPlanProvider`, so the same workout logged that way showed at once.

## Fix

One helper, one list, three callers. The chat path calls it through the container it captured before its first await,
so it works when the card is gone.

## Not changed here

The other hand-written copies of the batch (edit sheet, `completeWorkout`, day swap, day rollover, template delete) and
the dead `WorkoutWriteService.onInvalidate` hook: OI-376. The duplicate exlog reader `getExerciseLogsForDate`: OI-377.
The upstream Riverpod assertion seen offstage in debug: OI-378.
