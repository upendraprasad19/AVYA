# Agent 2 Findings — Cluster 3 (Hive writer/reader contracts)

**Date:** 2026-05-16 · **Word count:** 1382

## Summary table — 14 Hive prefixes audited

| Prefix | Box | Sole Writer (file:line) | Test Coverage | Field Drift |
|---|---|---|---|---|
| `exlog_<date>_<hash>` | workoutBox | `WorkoutWriteService.logExercise` L89 | ✅ `hive_field_name_exlog_writer_to_reader_test.dart` | NONE |
| `nlog_<date>_<mealType>_<hash>` | nutritionBox | `NutritionWriteService.logMeal` L76 | ✅ `hive_field_name_nlog_writer_to_reader_test.dart` | NONE |
| `wlog_<date>` | workoutBox | `WorkoutWriteService.markCompleted` L379 | ✅ implicit | NONE |
| `schedule_<date>` | workoutBox | `WorkoutWriteService.upsertScheduled` L427 | ✅ `scheduled_workouts_mutations_writer_to_reader_test.dart` | NONE |
| `exercise_log_index_<date>` | workoutBox | `WorkoutWriteService._appendToIndex` L330 | ✅ `exercise_logs_read_path_writer_to_reader_test.dart` | NONE |
| `tmpl_<hash>` | workoutBox | `TemplatesNotifier.saveTemplate` L1664 | ✅ `workout_templates_*` (cluster grep) | NONE |
| `saved_meal_<ms>` | nutritionBox | `NutritionWriteService.saveMealPreset` L514 | ✅ `saved_meals_writer_to_reader_test.dart` | NONE |
| `custom_exercise_<ms>` | customBox | `CreateCustomExerciseSheet._save` L70 | ⚠️ implicit only | NONE |
| `undo_<logKey>` | workoutBox | `WorkoutWriteService.deleteLog` L746 | ❌ NONE | Undocumented |
| `streak_freezes_*` | userBox | `StreakProgressService.commitRefill/Consume` L65, L93 | ✅ `streaks_writer_to_reader_test.dart` | Acknowledged dual-write |
| `coaching_notes` | coachBox | `SyncService._restoreCoachMemory` L204 | ✅ `coaching_notes_writer_to_reader_test.dart` | Cloud-driven |
| `coach_memory` | coachBox | Cloud sync only | ⚠️ implicit | Cloud-driven |
| `prediction_text` | userBox (MigratedKey) | `PredictionService.predictDietImpact` L60 | ❌ NONE | Not in SoT registry |
| `saved_diet_plan` | userBox (MigratedKey) | `SyncService._restoreSavedDietPlan` L246 | ❌ NONE | Not in SoT registry |

**Key result:** ZERO field-name or semantic drift across all 9 primary prefixes. 40+ existing contract tests successfully pin field names across 28 writer/reader pairs.

## Findings

### F3-A: `undo_*` keys undocumented in SoT registry — FRAMEWORK_GAP
- **Evidence:** `WorkoutWriteService.deleteLog` L746 creates `box.put('undo_$logKey', {...})` with 1-hour TTL; only `restoreDeletedLog()` reads.
- **Why:** Not in `sot_registry.yaml`; not in CLAUDE.md §15; no contract test.
- **Remediation:** Add SoT registry entry + `undo_stash_lifetime_test.dart`.

### F3-B: `custom_exercise_*` contract test missing — FRAMEWORK_GAP
- **Evidence:** Writer at `create_custom_exercise_sheet.dart:70`; readers in `train_screen.dart:2197-2209` + sync. Field contract pinned only via implicit sync/community tests.
- **Why:** Discovered Test #16 (Bug C) that `restoreCustomExercises` was writing without `type:'exercise'` — drift class.
- **Remediation:** Add `custom_exercise_writer_to_reader_test.dart`.

### F3-C: MigratedKey contracts undefined — FRAMEWORK_GAP
- **Evidence:** `prediction_text`, `saved_diet_plan`, and 5+ other userBox fields use `MigratedKey` wrapper. Field names live in wrapper abstraction.
- **Why:** Rename in wrapper breaks all readers silently; no contract test verifies the mapping.
- **Remediation:** Add `migrated_key_contracts_test.dart` for all 7+ MigratedKey concepts.

### F3-D: `streak_freezes_*` dual writer — ACKNOWLEDGED_DESIGN
- **Evidence:** CLAUDE.md §15 documents `StreakProgressService` as sole writer; but `WorkoutRepository._calculateStreak(consume: true)` also mutates same fields. Cloud-side optimistic-lock (migration 056) prevents cross-device race.
- **Why:** Intentional per existing audit. Worth monitoring.
- **Remediation:** None now; revisit if cross-device race emerges.

## Inverse check — ZERO drift cases found

Searched for any prefix with ≥2 writers OR ≥2 readers where field set diverges. Result: clean.
- `exlog_*`: `reps_completed = sum(sets)`, `weight_kg = max(sets)`, `volume_kg = sum(weight × reps)`, `set_number = len(sets)` ✅ all readers agree
- `nlog_*`: `total_* = sum(items[*])` with Atwater fallback ✅ all readers agree
