---
bug_id: b3c8d2
date: 2026-05-12
batch: APK Test #15.1
status: in_progress
symptom: Founder's templates "Back Day A", "Leg Day A", "Push Day" each showed 14-15 exercise rows with only 4-5 distinct names ("triplicated"). Editing the template + removing duplicates + saving brought the dupes back on next reopen.
concept: template_exercises_cloud_tail_rows
sot_registry_entry: workout_templates
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncWorkoutTemplates upsert+vacuum, line: 3810 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreWorkoutTemplates, line: 3870 }
  - { file: lib/features/train/screens/template_builder_screen.dart, method_or_widget: build, line: 1 }
hive_key_prefix: tmpl_
hive_key_formula: "'tmpl_${tmplName.hashCode.toUnsigned(32).toRadixString(16)}'"
sync_methods: [_syncWorkoutTemplates]
restore_methods: [_restoreWorkoutTemplates]
cloud_table: template_exercises
cloud_columns:
  - template_id
  - order_index
  - exercise_name
  - prescribed_sets
  - prescribed_reps
contract_test_path: test/contracts/template_exercises_tail_vacuum_test.dart
ist_handling: []
provider_invalidations: [templatesProvider, currentPlanProvider, calendarWeekProvider]
telemetry_op_types:
  success: []
  failure: [sync_template_exercises_tail_vacuum]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "\\.from\\('template_exercises'\\)\\.delete\\(\\)\\.eq\\('template_id'.*(?!gte)", absent: true }
proposed_fix: |
  Add a tail-bounded DELETE after the per-exercise upsert loop in
  _syncWorkoutTemplates. The chain:
    await _supabase.client.from('template_exercises').delete()
        .eq('template_id', cloudTmplId)
        .gte('order_index', exercises.length);
  removes any rows whose order_index >= the current local exercises
  count, vacuuming the orphaned tail without touching the upserted
  body. Single round-trip per template, idempotent. Network failure
  on the DELETE leaves stale tail = pre-fix state (no regression).
  Wrapped in try/catch + telemetry event
  sync_template_exercises_tail_vacuum for ops visibility.

  Plus a one-shot cloud SQL cleanup to remove the existing 30 tail
  rows from the founder's 3 affected templates (executed via Supabase
  MCP at fix time, 2026-05-12). Post-cleanup row counts: Back Day A
  5/5, Leg Day A 5/5, Push Day 4/4.
regression_test_planned:
  - test/contracts/template_exercises_tail_vacuum_test.dart
---

# Bug B — template_exercises cloud tail rows on template shrink

## Symptom

Founder's templates rendered with way more exercises than he'd added: "Back Day A" 15 rows with only 5 distinct names (Pull Up ×1, Lat Pulldown ×2, Seated Cable Row ×4, Concentration Curl ×4, Hammer Curl ×4). Editing the template, removing duplicates, saving — duplicates came back on next reopen.

## Root cause

`_syncWorkoutTemplates` (lib/core/services/sync_service.dart:3810) upserts each local exercise into cloud `template_exercises` on `(template_id, order_index)`. Migration 051 (APK Test #15 / Backlog #2) added the UNIQUE constraint so upserts became idempotent per slot. That fix replaced the pre-fix DELETE-then-INSERT pattern, which was fragile on partial failure (a network blip mid-INSERT left torn templates).

**The Test #15 fix introduced this new bug** — when a template shrinks (15 exercises → 5), slots 0..4 are upserted with current values but slots 5..14 from the prior version remain in cloud as orphaned tail rows. `_restoreWorkoutTemplates` then pulls all 15 back into local Hive, the founder sees 15-exercise "triplicates," and editing/saving doesn't help because the next sync re-upserts the new 5 (or however many) without vacuuming the tail.

Cloud verification at fix time:

```sql
SELECT wt.name, COUNT(te.id) AS rows, COUNT(DISTINCT te.exercise_name)
FROM workout_templates wt
LEFT JOIN template_exercises te ON te.template_id = wt.id
WHERE wt.user_id = 'd7a67a37-...'
GROUP BY wt.name;
-- Back Day A: 15 rows, 5 distinct names
-- Leg Day A:  15 rows, 5 distinct names
-- Push Day:   14 rows, 4 distinct names
```

## Fix

Add a tail-bounded DELETE after the per-exercise upsert loop:

```dart
await _supabase.client
    .from('template_exercises')
    .delete()
    .eq('template_id', cloudTmplId)
    .gte('order_index', exercises.length);
```

Removes only rows whose `order_index >= local_count`. The upserted body (0..local_count-1) is untouched. Single round-trip per template, idempotent. Network failure on the DELETE leaves the stale tail = pre-fix state (no regression). Wrapped in try/catch + non-fatal telemetry event `sync_template_exercises_tail_vacuum`.

Also executed a one-shot cloud SQL cleanup via Supabase MCP at fix time to remove the existing 30 tail rows from the founder's 3 affected templates. Post-cleanup row counts match local: Back Day A 5/5, Leg Day A 5/5, Push Day 4/4.

## Verification

- 3 source-grep contract tests pass:
  - `from('template_exercises').delete()` chain present
  - `.gte('order_index', exercises.length)` bound present
  - Forbidden: bare `.delete().eq('template_id', ...)` WITHOUT `.gte('order_index', ...)` — that would wipe the entire template body
- Cloud cleanup verified: founder's 3 templates now 5/5, 5/5, 4/4 rows × distinct names.
- Next sync push of any of those templates will keep the row count tight via the new tail vacuum.

## Related

- Migration 051 (APK Test #15 / Backlog #2) — added UNIQUE(template_id, order_index) that this fix builds on
- `feedback_no_deferrals.md` — Bug B ships in same batch as A, C, D, E, F, G, H, I
