---
bug_id: 9e2c1a
date: 2026-05-12
batch: APK Test #15.3
status: in_progress
symptom: |
  Founder on +22 fresh install (Hive wiped, restored from cloud) sees
  Monday 2026-05-11 day card header rendering the original
  plan-generator name "PUSH A" instead of the assigned template name
  "Leg Day A" — even though cloud `scheduled_workouts` for that date
  carries `template_id = 06f6e0bd-... (Leg Day A)` and `status =
  completed`. Logged exercises render correctly (they came back via
  `workout_log_exercises` restore) but the schedule header is stale.
concept: scheduled_workouts_mutations
sot_registry_entry: scheduled_workouts_mutations
writers:
  - { file: lib/core/services/workout_schedule_service.dart, method_or_widget: assignTemplateToDate, line: 1441 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreScheduledWorkouts, line: 4235 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: todayWorkoutProvider, line: 430 }
  - { file: lib/features/home/widgets/weekly_calendar.dart, method_or_widget: WeeklyCalendar.build, line: 31 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: currentPlanProvider, line: 1 }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods:
  - SyncService._syncScheduledWorkouts
restore_methods:
  - SyncService._restoreScheduledWorkouts
cloud_table: scheduled_workouts
cloud_columns:
  - id
  - user_id
  - template_id
  - scheduled_date
  - week_number
  - day_of_week
  - status
  - completed_at
  - created_at
contract_test_path: test/contracts/restore_template_schedule_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations:
  - calendarWeekProvider
  - todayWorkoutProvider
  - currentPlanProvider
telemetry_op_types:
  success: []
  failure:
    - restore_scheduled_workouts
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "'template_id': map['template_id']", absent: false }
proposed_fix: |
  `_restoreScheduledWorkouts` modified to embed the parent
  `workout_templates` row + its `template_exercises` rows via
  PostgREST select syntax (`*, template:template_id(name,
  workout_type, template_exercises(*))`). For each restored
  scheduled-workout row where `template_id IS NOT NULL` AND the
  embed resolved a template, hydrate the Hive `schedule_<date>`
  entry's `workout_name`, `workout_focus`, `exercises[]` (mapped
  via the same exercise normalization used by
  `_restoreWorkoutTemplates` — `prescribed_sets` → `sets` (int
  via `_coerceInt`), `prescribed_reps` → `reps` (String), etc.).
  Rows with `template_id IS NULL` keep existing behavior — local
  Hive plan-generator entry preserved.
  Defensive: if `template_id` is set but the embed returned null
  (template deleted / FK SET NULL), don't overwrite local
  `workout_name` / `exercises` — log telemetry.
regression_test_planned:
  - test/contracts/restore_template_schedule_test.dart
---

# Bug 4a — Restore loses template-assigned schedule names on fresh install

## Symptom

On 2026-05-11 (Monday), founder used the in-app schedule UI to assign the "Leg Day A" template to Monday, logged exercises, and completed the workout. Everything worked end-of-day Monday.

On 2026-05-12 (Tuesday), founder installed a fresh +22 APK (Hive wiped). The post-auth restore pulled `workout_logs` / `workout_log_exercises` correctly — the leg exercises render correctly in receipts. But the Monday day card header reads "PUSH A" (the original plan-generator default for that slot), NOT "Leg Day A".

## Root cause

`SyncService._restoreScheduledWorkouts` (lib/core/services/sync_service.dart:4235) fetches the `scheduled_workouts` rows via `_fetchAllRows('scheduled_workouts', ...)` and then merges each row into the Hive `schedule_<date>` Map. The merge code (lines 4309-4326) carries forward only the cloud columns that actually exist on that table:

```dart
final merged = <String, dynamic>{
  ...existingMap,
  'date': date,
  'type': existingMap['type'] ??
      (map['template_id'] != null ? 'custom_template' : 'workout'),
  if (map['template_id'] != null) 'template_id': map['template_id'],
  // ... status, completed_at, week_number, day_of_week
  'source': 'cloud_restore',
};
```

The cloud `scheduled_workouts` table only has these columns (verified live 2026-05-12 against `dedsavbjuwgarrhphgnl`):

```
id, user_id, template_id, scheduled_date, week_number,
day_of_week, status, completed_at, created_at
```

**No `workout_name`. No `exercises` column.** The display content lives in `workout_templates.name` and `template_exercises.*` rows, joined via `template_id`. Restore never executes this join, so the Hive map keeps whatever `workout_name` + `exercises[]` the plan-generator path (`_restoreWorkoutPlan`, line 4023+) wrote first — which is the auto-generated default ("PUSH A"), not the user's template assignment.

The `_restoreWorkoutTemplates` method (line 3889) DOES bring template content back into Hive — but at the `tmpl_<hash>` key, not into the `schedule_<date>` map. The schedule lookup in `home_provider.todayWorkoutProvider` reads `schedule_<date>['workout_name']` directly; nothing materializes the `template_id → tmpl_<hash> → name+exercises` cross-reference during restore.

Note from live DB: Monday 2026-05-11 actually has TWO `scheduled_workouts` rows for the founder — one `status='planned'` with `template_id=null` (the original plan-gen entry) and one `status='completed'` with `template_id=06f6e0bd` (Leg Day A). Restore iterates ordered by `scheduled_date`; the completed-with-template row arrives second and currently overlays only the bare cloud columns. The fix must hydrate `workout_name`/`exercises` from the template on this row.

## Fix

Modify `_restoreScheduledWorkouts` to fetch with PostgREST embed:

```dart
final rows = await _supabase.client
    .from('scheduled_workouts')
    .select('*, template:template_id(id, name, workout_type, template_exercises(*))')
    .eq('user_id', userId)
    .gte('scheduled_date', since.substring(0, 10))
    .order('scheduled_date');
```

For each row where `template_id IS NOT NULL` AND `row['template'] IS NOT NULL`, hydrate the merged Hive map with:
- `workout_name = template.name`
- `workout_focus = template.workout_type ?? 'Custom'`
- `type = 'custom_template'`
- `exercises = normalize(template.template_exercises)` — same field translation as `_restoreWorkoutTemplates` (lines 3938-3962): `prescribed_sets` → `sets` via `_coerceInt(fallback: 3)`, `prescribed_reps` → `reps` (String), `prescribed_weight` → `weight_kg`, `rest_seconds` → `rest_seconds` + `rest_secs`.

For rows where `template_id IS NULL`: existing behavior — preserve local `workout_name`/`exercises` (plan-generator default), only overlay cloud-authoritative fields (status, completed_at, etc.).

Defensive: when `template_id` is set but embed is null (template deleted, FK was SET NULL, or RLS hid the row), skip the hydration and log telemetry instead of overwriting local fields with empties.

## Why this manifests on fresh install only

On an existing install, `assignTemplateToDate` (line 1441 in `workout_schedule_service.dart`) writes the full Hive map locally — `workout_name`, `exercises`, `type: 'custom_template'`, `template_id` — all together. No restore path is needed because Hive already has the data.

On a fresh install:
1. `_restoreWorkoutPlan` (line 4023) runs first and writes the plan-generator default `schedule_<date>` entries (workout_name="PUSH A", exercises=[plan-gen exercises]).
2. `_restoreScheduledWorkouts` runs second, finds the cloud row with `template_id=06f6e0bd`, and merges only `template_id`/`status`/`completed_at` into the Hive map. The plan-gen default `workout_name`/`exercises` survive.
3. Today card header reads `schedule_2026-05-11.workout_name` → "PUSH A". Bug visible.

## Class precedent

This is the same shape as Test #11 Theme A "Restore-completeness" bugs (freezes, notifications inbox, saved diet plan): a Hive surface that paying users lose on reinstall because the restore path didn't pull the full data needed to reconstruct the surface. The class fix in §15 of CLAUDE.md mandates: cloud column/table + sync write + restore method + contract test.

Here the cloud column DOES NOT exist on `scheduled_workouts` (and won't — the template content lives in `workout_templates`/`template_exercises` by design). The restore method must JOIN to reconstruct the Hive map.

## Verification

Source-grep contract test pins:
- `'template:template_id'` or equivalent embed string present
- Conditional hydration of `workout_name` only when template embed resolves
- Conditional hydration of `exercises[]` from `template_exercises` embed
- `_coerceInt(... 'prescribed_sets'` mapping present
- Forbidden: a bare merge that ignores the embed (no `workout_name` hydration logic at all)

## Related

- Bug 4b will audit whether `assignTemplateToDate` writes `template_id` to cloud (the cloud row has it, so SOMETHING pushed; need to confirm the path).
- Bug 4c (per parent's plan) addresses an adjacent restore concern; not in scope for 4a.
- CLAUDE.md §15 "Restore-completeness sync" class.
- Test #11 Theme A precedent (`feedback_source_of_truth_audit.md`).
