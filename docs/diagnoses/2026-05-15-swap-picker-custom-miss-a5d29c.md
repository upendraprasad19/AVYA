---
bug_id: a5d29c
date: 2026-05-15
batch: APK Test #15.4 / A5
status: fixed
symptom: |
  Founder searched "Single Leg Front" in the active-workout SWAP
  EXERCISE picker on a fresh install. The picker returned "No matching
  exercises found" even though his custom exercise
  `Single Leg Front Lever` is in cloud
  `user_custom_exercises.id=29aeaa20-7c10-5012-b89a-209a3692f150`
  (created 2026-05-02) and `restoreFromCloud()` had run. The custom
  exercise existed locally in `customBox` keyed
  `custom_exercise_29aeaa20-...` but was invisible to every reader.
concept: custom_exercises_mutations
sot_registry_entry: custom_exercises_mutations
writers:
  - { file: lib/features/train/widgets/create_custom_exercise_sheet.dart, method_or_widget: _save, line: 86 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: createCustomExercise, line: 1464 }
  - { file: lib/core/services/sync/sync_community.dart, method_or_widget: _restoreCustomExercises, line: 307 }
readers:
  - { file: lib/shared/repositories/exercise_repository.dart, method_or_widget: getCustomExercises, line: 322 }
  - { file: lib/features/train/widgets/exercise_swap_sheet.dart, method_or_widget: _loadExercises, line: 67 }
  - { file: lib/features/train/screens/active_workout_screen.dart, method_or_widget: _showExercisePickerSheet, line: 1915 }
  - { file: lib/features/train/screens/template_builder_screen.dart, method_or_widget: _customExercises, line: 518 }
hive_key_prefix: custom_exercise_
hive_key_formula: "'custom_exercise_${cloudRow.id}'"
sync_methods:
  - SyncService._syncCustomItems
restore_methods:
  - SyncService._restoreCustomExercises
cloud_table: user_custom_exercises
cloud_columns:
  - id
  - user_id
  - name
  - category
  - logging_type
  - movement_pattern
  - target_focus
  - default_weight_kg
  - default_reps
  - default_rest_secs
  - default_duration_secs
  - submitted_to_library
  - approved_for_library
  - times_used
  - created_at
contract_test_path: test/widgets/swap_sheet_custom_exercises_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - restore_custom_exercises
cross_account_guard: wrapUserScopedBox(customBox)
forbidden_patterns_checked:
  - { pattern: "ex['type'] == 'exercise' as sole discriminator", absent: true }
root_cause: |
  Writer/reader field drift. Cloud table `user_custom_exercises` has
  no `type` column (it's redundant — the table itself IS the
  exercise table). On restore, `_restoreCustomExercises` (in
  `lib/core/services/sync/sync_community.dart`) wrote each cloud row
  verbatim into `customBox` keyed `custom_exercise_<id>` — without
  stamping a `type: 'exercise'` field.

  The reader `ExerciseRepository.getCustomExercises()` filtered
  `if (ex['type'] == 'exercise')` to skip non-exercise entries
  (custom foods are also stored in `customBox` under
  `custom_food_*` keys with `type: 'food'`). Restored entries had
  no `type` → filter dropped them silently → every consumer
  (swap sheet, train screen, active-workout add-picker, template
  builder) showed zero custom exercises post-restore. The bug
  surfaced only on fresh installs of paying / returning users with
  custom exercises in cloud.

  This is the recurring writer/reader drift class — same shape as
  Tests #6 → #15.3 covered by `feedback_writer_reader_field_drift_recurring.md`.
  H-13 (audit-2026-05-11) fixed the per-key restore shape; that fix
  shipped the type-stamp gap in the same change.
proposed_fix: |
  Two-layer defense in depth:

  (1) Reader robustness — `getCustomExercises()` now accepts an
  entry as a custom exercise when EITHER `ex['type'] == 'exercise'`
  (legacy create path) OR the Hive key starts with
  `custom_exercise_` (canonical restore path). Iterates
  `customBox.keys` instead of `.values` so the key is available.
  This unblocks devices that already restored before the writer
  fix landed.

  (2) Restore stamp — `_restoreCustomExercises` now writes
  `item['type'] = 'exercise'` before `customBox.put` so any legacy
  reader that doesn't grow the key-prefix fallback still sees the
  entry. Belt-and-suspenders.

  Plus a UX fix: the swap sheet's "No matching exercises found"
  empty-state now fires only when BOTH the filtered library AND
  the filtered custom list are empty. Pre-fix it rendered when the
  library half was empty even if the custom half had a matching
  result — visually hiding the custom result above. Custom entries
  also render with a small CUSTOM badge so users can tell which
  exercises they added themselves.
verification: |
  - test/widgets/swap_sheet_custom_exercises_test.dart — source-grep
    + behavioral. Pins reader key-prefix fallback, restore type
    stamp, sheet empty-state two-condition guard, CUSTOM badge
    presence. Behavioral test plants a typeless `custom_exercise_*`
    entry (the restore shape) and asserts `getCustomExercises()`
    returns it. Search-query test mirrors `_filteredCustom` to
    confirm the founder's exact query "Single Leg Front" matches
    "Single Leg Front Lever".
  - Manual repro: fresh install → sign in as user with custom
    exercise in cloud → open active workout → tap swap on any
    exercise → search "Single" → custom exercise renders under
    "YOUR CUSTOM EXERCISES" with CUSTOM badge.
followups:
  - "Audit other customBox readers that filter by type — confirm "
  - "active_workout_screen + template_builder_screen also surface "
  - "restored items. (They route through getCustomExercises(); "
  - "fixed transitively.)"

---
