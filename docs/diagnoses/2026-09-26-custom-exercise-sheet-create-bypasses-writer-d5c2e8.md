---
bug_id: d5c2e8
date: 2026-09-26
batch: reuse-audit-fixes (founder-requested reuse audit — "are we using the common functions across screens")
status: fixed
blast_radius: feature
symptom: |
  Found by the reuse audit, not by a user report. `CreateCustomExerciseSheet`
  created a custom exercise with a raw `HiveService.instance.customBox.put`
  plus a hand-rolled `syncCustomItemsNow()` / `pushSnapshot()`, then popped
  and called `onCreated` unconditionally. It never called the canonical
  writer. So a sheet-created exercise skipped, versus the AI-coach path:
  the duplicate-name guard (two rows with the same deterministic v5 id), the
  60-char name cap, the `WorkoutWriteService` lock, and the `source` /
  `updated_at` / `created_at` stamps (sheet rows carried none). A failed put
  was unawaited, so the user saw the exercise "created" even when it wasn't.
  The EDIT branch of the same sheet already used the writer correctly.
concept: custom_exercises_mutations
sot_registry_entry: custom_exercises_mutations
related_bugs:
  - 7ad0c9 — same class: nutrition mutations bypassing NutritionWriteService (C-12)
  - 7ad0cc — WriteService-bypass guardrail for Hive prefixes
  - s1n4c0 — the inline CreateCustomExerciseSheet inside the swap sheet
  - e7b2d4 — custom-picker-fix, which made this sheet's rows reach the pickers
recurrence: yes — the WriteService-bypass class (7ad0c9). Known-good pattern
  applied: route the widget through the one canonical writer, never a raw put.
writers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "WorkoutRepository.createCustomExercise — now the ONE create path; defaultReps is String? (the sheet accepts '8-12'), equipment optional (null ⇒ []); judges the write by the stored row via customExerciseRowLanded", line: 1366 }
  - { file: lib/features/train/widgets/create_custom_exercise_sheet.dart, method_or_widget: "_CreateCustomExerciseSheetState._save create branch — calls createCustomExercise, shows the exception message and stays open on failure, passes the STORED row to onCreated", line: 280 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeCreateCustomExercise — defaultReps now passed as a String", line: 559 }
readers:
  - { file: lib/shared/repositories/exercise_repository.dart, method_or_widget: "ExerciseRepository.getCustomExercises — pickers, template builder; the sheet reads the created row back through it", line: 427 }
hive_key_prefix: custom_exercise_
hive_key_formula: "'custom_exercise_${DateTime.now().millisecondsSinceEpoch}' (unchanged)"
sync_methods: [syncCustomItemsNow]
restore_methods: []
cloud_table: user_custom_exercises (unchanged — the writer's existing sync fan-out)
cloud_columns: []
contract_test_path: test/contracts/custom_exercises_mutations_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Unchanged — the write goes through WorkoutWriteService,
  whose customBox access is wrapUserScopedBox-guarded like before.
forbidden_patterns_checked:
  - "throwing on `!WriteResult.success` — rejected (plan-review R2-9): upsertCustomExercise can return fail AFTER a successful put because its sync kick sits inside the same try. Throwing then would tell the user the save failed while the row exists, and their retry would hit duplicate_name. The write is judged by the row instead."
  - "keeping the sheet's own id computation — rejected: one create path means one id computation."
proposed_fix: |
  The sheet's create branch calls WorkoutRepository.createCustomExercise.
  The repository takes defaultReps as String? and equipment as optional,
  and throws write_failed only when the row is absent after the write
  (pure customExerciseRowLanded). The name field gets maxLength: 60 to
  match the writer's cap.
regression_test_planned:
  - test/contracts/custom_exercises_mutations_behavioral_test.dart — new group "sheet-create through the one writer": '8-12' round-trips; null equipment ⇒ []; row carries source/created_at/updated_at; customExerciseRowLanded table; source pin that the check + write_failed are wired.
  - test/contracts/custom_exercise_writer_to_reader_test.dart — REPOINTED (not deleted) from the sheet to the repository's createCustomExercise body; new pin that the sheet calls createCustomExercise and contains no customBox.put / syncCustomItemsNow.
  - test/contracts/custom_picker_capability_wiring_test.dart — REPOINTED: the primary_muscles selection is pinned at the call argument; approved_for_library is stamped 0× in the sheet and exactly 1× (create) in the repository.
mutation_proven: |
  Four mutations, each left the code compiling and reddened exactly one test
  in custom_exercises_mutations_behavioral_test.dart (10 green → 1 red each):
  customExerciseRowLanded → `true` (the table test); the landed check →
  `if (false)` (the wiring pin); null equipment → normalize(['dumbbell'])
  (the empty-requirement test); default_reps → split('-').first (the range
  test). Every mutation restored from a cp backup, not git checkout.
  B-pass F2 (added same batch): deleting `await previous;` (the create
  serialization) reddened "concurrent creates of one name write ONE row";
  deleting the same-millisecond key bump reddened "concurrent creates of
  DIFFERENT names never share a Hive key" — both 2/2 runs, not timing luck.
b_pass_followups: |
  F2 (P2, fixed): the duplicate guard was a read before an awaited write and
  the writer's lock keys on the ms Hive key, so a double-tapped SAVE (or a UI +
  AI create of one name) wrote two rows sharing an id. createCustomExercise now
  serializes its check-then-write (static Completer chain) and never reuses a
  same-millisecond key; the sheet also ignores SAVE while a save is in flight.
  F3 (P3, fixed): the read-back-miss branch said "could not save" about a row
  the writer had just proven landed; it now pops and says "Saved — find it
  under YOUR EXERCISES." F1 (referral) belongs to c7b4d2.
impact_analysis: |
  Sheet-created exercises now carry source/created_at/updated_at like AI-created
  ones, and a duplicate name shows "A custom exercise named X already exists"
  instead of writing a second row with the same id. The AI tool path is
  unchanged except that its int reps are passed as a string, which is what the
  row already stored (`defaultReps?.toString()` before). No migration: existing
  sheet rows without source/created_at are read the same as before.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze on every changed lib file — clean; 40/40 custom-exercise tests green." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "custom_exercises_mutations_behavioral_test.dart does a real Hive write → getCustomExercises read." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No column added or read differently; the sync projection is unchanged." }
---

## Summary

The custom-exercise sheet wrote its CREATE with a raw Hive put, skipping the
canonical `createCustomExercise` writer that the AI coach tool uses. It now
goes through that writer, so both create paths share the duplicate guard, the
name cap, the lock and the stamps.

## Fix

See `proposed_fix`. Device check owed: create a custom exercise from the Train
tab, then try the same name again. The second attempt should show the
duplicate message and keep the sheet open.
