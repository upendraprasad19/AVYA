---
bug_id: e2b9d4
date: 2026-09-26
batch: day-swapper-sync-load
status: in_progress
blast_radius: platform
symptom: |
  The only shipped day-swap path, `SwapService.swapDays` (lib/core/services/swap_service.dart:113-169),
  reached solely via a long-press on the Home calendar strip, has nine independent defects, each read
  directly in code (spec §1.2): (1) no eligibility guards — every day of the week is offered, including
  completed and past days, so swapping a completed day moves its completion to another date; (2) not
  atomic and it counts failures — two separate `upsertScheduled` calls (:155, :160) with both
  `WriteResult`s ignored and the counter incremented regardless, so a failed or half-applied swap still
  costs a swap; (3) it copies the other day's row wholesale, keeping only `date`/`day_of_week`
  (:143-153), so identity fields (`week`, `phase`, `week_character`, `is_hold`, `hold_ordinal`) travel
  with the content — harmless only because both days are always in the same week today; (4) the
  `is_swapped`/`original_date` markers are stamped on both rows and never cleared, so swapping twice
  leaves both days permanently marked "swapped" with `original_date` overwritten by the latest origin
  instead of the first; (5) the swap counter is one local slot (`swaps_this_week`/`swap_week_start`,
  :105-106, :567) that uses the device-local week instead of IST, resets on sign-out/reinstall, and
  counts failures; (6) `_hasThreeConsecutiveRest` (:519-530) checks the whole post-swap week and
  refuses any swap in a week that already contains a 3-rest run, instead of warning; (7) the scheduled-
  workouts push omits a null `template_id` (lib/core/services/sync/sync_workout.dart:1714), so a moved
  template's old cloud row keeps pointing at it, and the reinstall restore
  (sync_workout.dart:2097-2100) force-hydrates that stale template back onto the day, duplicating it;
  (8) `_liftWeekFour` skips `is_swapped` rows (lib/core/services/deload_evaluator.dart:210), so a
  swapped day never gets the deload lift, with no recorded reason for the skip; (9)
  `WorkoutWriteService.rescheduleDay` (lib/core/services/workout_write_service.dart:648) is an atomic
  two-date-lock implementation with no production caller — its only caller is
  `test/workout_write_service/reschedule_day_test.dart`.
concept: day_swap_engine
sot_registry_entry: swap_counters (interim until Task 29 registers day_swap_engine; Task 31 re-points this line to it — see docs/sot_registry.yaml; the atomic write, the field
  partition, the swap markers and the server-backed allowance are all part of this one concept)
writers:
  - { file: lib/core/services/swap_service.dart, method: swapDays, line: 113 }
  - { file: lib/core/services/swap_service.dart, method: _hasThreeConsecutiveRest, line: 519 }
  - { file: lib/core/services/swap_service.dart, method: _normalizeToMonday, line: 567 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_syncScheduledWorkouts template_id omission", line: 1700 }
  - { file: lib/core/services/deload_evaluator.dart, method: "_liftWeekFour (is_swapped skip)", line: 210 }
readers:
  - { file: lib/core/services/workout_write_service.dart, method: "rescheduleDay (dead sibling, no production caller)", line: 648 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_restoreScheduledWorkouts (force-hydrates the stale template)", line: 1904 }
hive_key_prefix: "schedule_ (the swapped rows) and the two dead counter keys swaps_this_week / swap_week_start"
hive_key_formula: "schedule_${formatDateKey(date)}"
sync_methods: [_syncScheduledWorkouts]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [template_id, is_swapped, original_date]
contract_test_path: "must add: test/services/day_swap/day_swap_engine_atomic_write_test.dart (atomic
  write both-or-neither, no count on failure, displaced_ backup travel, swap-back clears MOVED) plus
  test/services/day_swap/day_swap_rules_test.dart (eligibility, field partition, 3-rest warning)"
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 113, fn: mondayOfIst }
provider_invalidations: [currentPlanProvider, workoutStatsProvider, calendarWeekProvider, streakProvider, todayWorkoutProvider, allExercisePRsProvider]
telemetry_op_types:
  success: [day_swap_done]
  failure: [day_swap_refused, day_swap_failed, swap_merge_conflict]
cross_account_guard: n/a — the engine operates only on the current session's own schedule rows and
  allowance counter; no cross-account read or write is introduced.
forbidden_patterns_checked:
  - { pattern: "Keeping the old swap's counter behavior (device-local week, counts failures) as a fallback path", absent: true }
  - { pattern: "Blocking the swap outright when a 3-rest run would result, instead of warning", absent: true }
  - { pattern: "Reviving rescheduleDay instead of building swapScheduledDays on the same two-date-lock pattern", absent: true }
proposed_fix: |
  Rebuild `SwapService.swapDays` as the one entry point for every caller (Train drag, Train up-down,
  Home long-press, coach), backed by a new pure `DaySwapRules` class (eligibility: different dates,
  same Mon-Sun IST week, today or later, status planned/rest, no logged sets, not the in-progress
  date) and a new atomic `WorkoutWriteService.swapScheduledDays(dateA, rowA, dateB, rowB)` that reuses
  `rescheduleDay`'s two-date-lock pattern (sorted-order lock, re-read both rows, write both or restore
  the first on a second-write failure) before `rescheduleDay` itself is deleted and its test rewritten
  against the new method. The field partition (content moves: type, workout_name, exercises, etc.;
  identity stays: date, week, phase, hold_ordinal, etc.) replaces the wholesale-copy bug. Swap markers
  get correct semantics: `original_date` is the FIRST origin (kept across repeated swaps of the same
  content) and both markers clear when content lands back on its original date. The counter becomes a
  phone-copy `DayAllowance` per IST Monday plus a background `consume-day-swap` Edge Function call
  against a server ledger (`usage_counters` / `consume_quota`), replacing the local device-week slot;
  the two dead keys are deleted by the one-time repair migrator (Task 23). `_hasThreeConsecutiveRest`
  becomes a warn-only check limited to runs the swap itself creates or extends. The scheduled-workouts
  push sends an explicit `template_id: null` when the local row has none (sync_workout.dart:1714), and
  the deload evaluator's `is_swapped` skip at `deload_evaluator.dart:210` is removed (the `:209`
  shortened-row skip stays, and the existing behavioral test is split into two cases per plan deviation
  D9).
regression_test_planned: |
  Pure-rules tests cover every locked state, both sides of the Sunday 23:59/Monday 00:00 IST boundary,
  first-origin and back-home marker semantics, the 3-rest warning (creates vs pre-existing run), and
  the field partition (every content field moves, every identity field stays). Engine-against-real-Hive
  tests cover the atomic write (both or neither, including an injected failure of the second write), no
  count on a failed write, `displaced_` template backup travel (and exchange when both days carry
  templates), and swap-back clearing MOVED while keeping `arranged_at_ms`. The existing
  `test/contracts/deload_eval_behavioral_test.dart` is split per D9 into "a swapped row IS lifted" and
  "a shortened row is NOT rewritten". `test/contracts/swap_counters_behavioral_test.dart` is rewritten
  against the new `DayAllowance`. Mutation proof planned: reverting `swapScheduledDays` to the old
  two-independent-upsert shape must redden the atomic-write test; reverting the field partition to a
  wholesale copy must redden a fixture asserting `week`/`phase` stay put across a swap.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "DaySwapRules, the rebuilt SwapService.swapDays, WorkoutWriteService.swapScheduledDays and the deload_evaluator.dart:210 skip removal (Tasks 6, 10-12, per plan Wave 0/Wave 1)." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "is_swapped/original_date marker semantics corrected; swaps_this_week/swap_week_start deleted by the repair migrator (Task 23) and replaced by day_swap_allowance (Task 11)." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "The allowance ledger schema (usage_counters) already exists from migration 128; this bug's fixes need no new DDL of their own." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "Each of the nine defects was confirmed by reading the client code directly (spec §1.2, 'each read in code'), not by querying live Postgres data." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No new migration is needed for the engine rebuild itself." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "The counter-miscounting defect (point 5) is replaced by the new consume-day-swap Edge Function backed by the existing consume_quota RPC (spec §5.3), landing in Task 8 (U2)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job reads or writes any of the nine defect sites." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No RLS policy change is needed; usage_counters' existing policy is unchanged." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No Storage bucket or object is involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret is involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "The explicit null template_id fix (sync_workout.dart:1714) and the server-backed allowance both correct what the client sends and how the server's count is trusted (spec §5.3, §5.4)." }
impact_analysis: |
  Severity: P1. This is the ONLY shipped day-swap path today, reached from the Home calendar strip.
  Defects 1-2 (no guards, non-atomic) risk moving a completed workout's history to the wrong date or
  charging a swap for a write that never landed. Defect 6 (over-broad 3-rest block) makes the feature
  unusable in any week that already has a rest run, which is common. Defect 7-8 (stale template link,
  skipped deload) silently corrupt unrelated features (template duplication on reinstall, missed
  deload weeks) for any user who has ever swapped a template day. None of the nine can be fixed in
  isolation without touching the shared engine this batch rebuilds, so this diagnose-doc's fix is the
  full engine rebuild, not a patch to `SwapService.swapDays` in place.
---

# The existing day swap has no guards and is not atomic (spec §1.2)

## Why this is not a recurrence

Grepped `docs/diagnoses/INDEX.md` for `swap`, `atomic`, `counter`, `template_id`, `deload`. Every
`swap` hit is the unrelated exercise-swap picker (mid-workout exercise substitution) or the coach's
`rescheduleWeek` move-terminal-row bug (`e8f4a3`) — neither is the Home-calendar day-swap engine this
doc covers. Spec §1.2 explicitly notes this class of defect has never been diagnosed before, so this
is filed as new.

## Fix ownership in the plan

- `DaySwapRules`, `DaySwapResult`/`DayAllowance` types, the engine rebuild, the allowance phone copy:
  Tasks 10-12 (U4, Wave 1).
- `WorkoutWriteService.swapScheduledDays` + `WriteSource.daySwap`: Task 6 (coordinator, Wave 0) — lands
  first because U4 depends on it.
- `consume-day-swap` Edge Function: Task 8 (U2, Wave 1).
- The template-null-link fix and the deload skip removal: coordinator inline Tasks 13-20 territory for
  the sync fix; `deload_evaluator.dart` is U4-owned per the file-structure "Modify" table (U4 owns
  `lib/core/services/deload_evaluator.dart`).
- The dead-code deletion of `rescheduleDay`, `WorkoutScheduleService.swapDays` and
  `WorkoutRepository.swapDays`: Task 11 (U4), per plan deviation D9.

## Mutation evidence

Recorded at Task 31: each mutation, the grep that confirmed it applied, and the red count.
