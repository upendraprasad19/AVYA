---
bug_id: 7ad0cb
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: `TemplatesNotifier.saveTemplate` + `.updateTemplate` wrote `tmpl_*` rows to Hive but fired NO cloud sync — `workout_templates`/`template_exercises` rows only reached cloud via weekly full sync (up to 24h delay). `TemplatesNotifier.deleteTemplate` fired `pushSnapshot` but missed `syncWorkoutData`, so the cloud `workout_templates` row stayed orphaned forever — next restore re-imported the "deleted" template.
concept: templates_sync_fanout
sot_registry_entry: workout_templates
writers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: TemplatesNotifier.saveTemplate, line: 1616 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: TemplatesNotifier.updateTemplate, line: 1627 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: TemplatesNotifier.deleteTemplate, line: 1654 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncWorkoutTemplates, line: 1 }
hive_key_prefix: "tmpl_*"
hive_key_formula: "tmpl_<millisecondsSinceEpoch>"
sync_methods: ["SyncService.syncWorkoutData()", "SyncService.pushSnapshot()"]
restore_methods: []
cloud_table: workout_templates
cloud_columns: [id, user_id, name, exercise_count, assigned_days, created_at, updated_at]
contract_test_path: test/sync/template_sync_gap_test.dart
ist_handling: []
provider_invalidations: [currentPlanProvider, calendarWeekProvider, todayWorkoutProvider, workoutStatsProvider, streakProvider]
telemetry_op_types:
  success: [sync_workout_templates]
  failure: [sync_workout_templates_failed]
cross_account_guard: yes
forbidden_patterns_checked: ["templates_mutation_without_syncWorkoutData", "templates_mutation_without_pushSnapshot"]
proposed_fix: Add `unawaited(SyncService.instance.syncWorkoutData())` + `unawaited(SyncService.instance.pushSnapshot())` after the Hive put in all 3 template mutation methods. workoutBox `tmpl_*` is already covered by `_syncWorkoutTemplates` inside `syncWorkoutData` — the fix only adds the missing fire-and-forget call sites.
regression_test_planned:
  - test/sync/template_sync_gap_test.dart
---
# Audit C-11: template mutations bypassed cloud sync

## Bug

`workoutBox` prefix `tmpl_*` is part of the workout-domain fan-out
contract per CLAUDE.md §15 — `syncWorkoutData()` includes
`_syncWorkoutTemplates`. Pre-fix:

- `saveTemplate` (new template) — only `ref.invalidateSelf()`. No sync.
- `updateTemplate` (rename / exercise edit) — only `ref.invalidateSelf()`. No sync.
- `deleteTemplate` — fired `pushSnapshot` but missed `syncWorkoutData`.

Effects:

1. **Saved template invisible to cloud for 24h.** A user creating a
   new template would have it stay Hive-only until the next weekly
   full sync. AI coach reading templates via cloud (rolling-context
   path) would not see it.
2. **Edited template name / exercise list stale on other devices.**
3. **"Deleted" template re-appears on restore.** Local Hive deletes
   but cloud row stays. Next sign-in on another device pulls the
   cloud row back into Hive. User has to delete twice (or thrice).

## Cause

The `TemplatesNotifier` predates the sync fan-out contract
formalisation in Test #11. When the sync-gap audit ran (Test #11
Theme A — restore-completeness), templates were considered "covered
by syncWorkoutData inside weeklyFullSync" — true, but only on the
weekly cadence, not on the user's actual save action.

## Fix

```dart
Future<void> saveTemplate(Map<String, dynamic> template) async {
  // ... Hive put + invalidateSelf ...
  unawaited(SyncService.instance.syncWorkoutData());
  unawaited(SyncService.instance.pushSnapshot());
}
```

Same pattern in `updateTemplate` and `deleteTemplate`.

## Regression test

`test/sync/template_sync_gap_test.dart` — 3 cases, one per method,
each asserts the body contains BOTH `syncWorkoutData` and `pushSnapshot`
unawaited calls.

Suite: 1550 pass / 0 fail / 2 skip.

## Related

- CLAUDE.md §15 (Sync fan-out contract)
- Test #11 Theme A (restore-completeness sync)
- 7ad0c9 (C-12 — sibling sync-gap fix on nutrition side)
