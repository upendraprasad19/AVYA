---
bug_id: f2a6c8
date: 2026-11-25
batch: oi348-walk-rest (A16 device walk, AAB +50)
status: fixed
tier: m_fix
blast_radius: feature
symptom: |
  Founder walk 2026-11-25 (A16, the custom-exercise duplicate message): creating a custom exercise whose name the exercise list already holds ("Barbell Bench Press") was ACCEPTED, the row was kept in the user's exercises, and only the step after it (adding the name to today's workout) was refused with "already in this workout". Founder: "why should we allow him to add the custom exercise with the same name? ... This is an incorrect thing." Founder decision: refuse ANY duplicate name, at creation, for every door. The create guard compared only the deterministic v5 id among the user's own customs (`<user>|exercise|<lower(name)>`), so it never looked at the exercise list, never looked at an older name of a list exercise, and missed a custom stored under an older id scheme. Logs are keyed by the exercise name (`exlogKey` hashes `exerciseNameKey`), so a second exercise with a taken name shares the first one's history, and the pickers show two rows that look the same.
concept: custom_exercises_mutations
sot_registry_entry: custom_exercises_mutations
writers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "_createCustomExerciseLocked: the duplicate-name guard (now: the exercise list by name and older name, the id scan, the name scan over the user's exercise rows)", line: 1599 }
readers:
  - { file: lib/features/train/widgets/create_custom_exercise_sheet.dart, method_or_widget: "_saveOnce shows CreateCustomExerciseException.message in a snackbar and keeps the sheet open", line: 322 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeCreateCustomExercise returns CreateCustomExerciseException.message as the failure", line: 624 }
hive_key_prefix: custom_exercise_
hive_key_formula: "unchanged: custom_exercise_<millisSinceEpoch>; only the refusal before the write changed"
sync_methods: []
restore_methods: []
cloud_table: user_custom_exercises
cloud_columns: []
contract_test_path: test/contracts/custom_exercise_name_unique_behavioral_test.dart
ist_handling: []
provider_invalidations: "none: a refused create writes nothing"
telemetry_op_types:
  success: []
  failure: [custom_exercise_sheet_create_failed, tool_dispatch_create_custom_exercise_failed]
cross_account_guard: "not applicable: the guard reads the signed-in user's own boxes (the shared exercise list and that user's custom box)."
forbidden_patterns_checked:
  - { pattern: "a custom exercise row created with a name the exercise list, an older list name, or another custom exercise already carries", absent: true }
proposed_fix: |
  In `_createCustomExerciseLocked` a name is TAKEN when (a) `ExerciseRepository.isNameTaken(name)` finds it as a list row's name or one of its `name_aliases`, or as one of the user's exercise rows (`customNamesLower`, so templates sharing the box are not compared), whatever id scheme it was stored with; or (b) a custom row carries the same v5 id (the earlier guard, kept). Names are compared by `exerciseDuplicateKey`: `exerciseNameKey` (trim, lower case; the identity `exlogKey` hashes, left unchanged) with runs of spaces, non-breaking ones too, read as one and curly apostrophes as straight ones. A taken name throws `duplicate_name` with `WardroomCopy.customExerciseNameTakenTemplate`; the sheet shows it and stays open, and the coach tool reports the same words. The copy's second sentence points at the equipment setting, because the pickers hide list exercises the user's equipment cannot do (plan review round 1: "Search for it instead" was a dead end for those; the coach also said "You already have an exercise called …" for a list name). Only an EXACT match refuses: a longer or shorter name creates. Rows already in the box are not touched (no migration); the edit sheet keeps its name read-only, so there is no rename door.
regression_test_planned: |
  test/contracts/custom_exercise_name_unique_behavioral_test.dart (real Hive, real repository): refused = the exact list name, case, leading, repeated inner and non-breaking spaces, a curly apostrophe, an alias (stored with stray spaces and capitals), a custom under an older id scheme, a custom with the same id under another name, an earlier user-created custom, the message names the exercise; mirror = a new name, a longer name containing a list name, a shorter name that is part of one, a TEMPLATE of that name; the coach intent for a list name fails with exactly the shared copy and writes nothing. Screens: test/features/train/exercise_name_unique_screen_test.dart and template_builder_unique_names_test.dart: the sheet stays open with the message and no row is stored; and, for a name in the session or template that is in NO list (so the create is allowed), the workout add, the auto-swap (no UNDO) and the builder each refuse it with their own message.
mutation_proof: |
  Rule 21, backup/mutate/run/restore (the file compared by hash after). Fixed code: new contract test 10 of 10 pass. Pre-fix shape (guard removed): 6 of the new tests failed before the fix was written. MA the list lookup removed: 5 RED in the contract test, and 5 RED in the screen tests (the three create-custom tests, the auto-swap test and the template-builder test). MB the user-exercise name scan removed: 1 RED (the older-id custom). MC the custom name compared case-sensitively: 1 RED. MD the list lookup widened to a substring search: 1 RED (the shorter-name mirror). A first screen run passed two paths as one string and failed at load; it was discarded and re-run with an argument list.
  Plan review round 1 (2026-11-26), each 1 RED: the builder's writer guard off; the swap's refused-change guard off; the add refusal's message off; the id scan off; the space folding removed; the curly-apostrophe folding removed; the user's own names not checked; the old coach words put back.
impact_analysis: |
  Feature blast radius: one create path, two doors (the sheet, the coach). Existing custom rows, their ids, sync and restore are untouched. A name that was creatable before and is now refused: any exact (case and space insensitive) list name or older list name. The exercise name tests that encoded "the custom row stays, the workout refuses it" were changed to the new rule.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "_createCustomExerciseLocked guard; WardroomCopy.customExerciseNameTakenTemplate; new contract test 10/10; 183 related tests pass; flutter analyze 0 errors 0 warnings." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The contract test reads the custom box back after each refusal: nothing is written." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No cloud row is written by a refused create." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "createCustomExercise.ts only builds the intent; the client creates the row, so no Edge Function changes and none needs a deploy." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The coach intent payload is unchanged; the failure path of tool_dispatcher _executeCreateCustomExercise returns before any provider refresh (the contract test dispatches a real intent)." }
recurrence: "Same concept as d5c2e8 (the sheet bypassed the one create path) and e6a4d9 (one name once per workout day); not a recurrence of either bug. d5c2e8 made the guard reachable from every door; this batch widens what the guard compares."
related_bugs: [d5c2e8, e6a4d9]
---

# f2a6c8 - A custom exercise could be created with a name the exercise list already holds

## What happened
`createCustomExercise` refused a duplicate only among the user's own customs, by id. The exercise list was never read, so a custom "Barbell Bench Press" was created beside the list's own, kept, and only refused when it was added to a workout.

## Fix
One rule at the one create path: a name the list holds (by name or older name), or any of the user's exercises carries, is refused with a message that says where it already is. Only an exact match (case and spaces ignored) refuses.

## Open calls (for the founder, not decided here)
A custom exercise that already shares a list name and was created before this fix is left as it is. Renaming or merging those rows would change their logs' keys.

A list exercise the user's equipment cannot do is hidden by every Train picker (a deliberate equipment rule). Before this fix the user could still add it as their own custom exercise; now that is refused, so the way in is changing their equipment. Showing an exact typed name despite the equipment filter would change that rule.
