---
bug_id: 9d2a47
date: 2026-05-17
batch: open-issues OI-06 (audit-comprehensiveness sweep)
status: fixed
symptom: |
  No live symptom — preventive audit. Migration 064 (APK Test #16) fixed
  the 42P10 silent-data-loss class on 3 tables (workout_logs,
  workout_log_exercises, nutrition_logs). The audit-comprehensiveness
  review on 2026-05-17 questioned whether OTHER tables with partial
  UNIQUE indexes existed that could trip the same trap. Pre-fix the
  inventory was unknown — only those 3 tables had been examined.
concept: partial_unique_arbiter_safety
sot_registry_entry: hive_field_name_exlog
writers:
  - { file: lib/core/services/sync/sync_community.dart, method: _syncCustomItems, line: 115 }
readers:
  - { file: lib/core/services/sync/sync_community.dart, method: _syncCustomItems, line: 115 }
hive_key_prefix: "custom_exercise_"
hive_key_formula: "'custom_exercise_<msSinceEpoch>' / 'custom_food_<msSinceEpoch>'"
sync_methods: [_syncCustomItems]
restore_methods: [_restoreCustomExercises, _restoreCustomFoods]
cloud_table: user_custom_exercises
cloud_columns: [id, user_id, name, category, logging_type, submitted_to_library, approved_for_library]
contract_test_path: test/contracts/partial_unique_arbiter_inventory_test.dart
ist_handling: []
provider_invalidations: [customExercisesProvider, customFoodsProvider]
telemetry_op_types:
  success: []
  failure: [upsert_custom_exercise, upsert_custom_food]
cross_account_guard: "customBox user-scoped via HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "onConflict.*'(user_id|name|lower\\()'", absent: true }
proposed_fix: |
  No code fix needed — the audit confirmed safety. Live SQL query
  enumerated all partial UNIQUE indexes in `public` schema:

    user_custom_exercises (user_id, lower(name)) WHERE user_id IS NOT NULL AND name IS NOT NULL
    user_custom_foods     (user_id, lower(name)) WHERE user_id IS NOT NULL AND name IS NOT NULL

  Both have nullable `user_id` (NULL for "deleted user" pseudonymization
  per migration 049 DPDP §17). The migration-064-fixed tables are
  confirmed non-partial.

  Client `_syncCustomItems` uses `onConflict: 'id'` (the PK, non-partial)
  — NOT the partial UNIQUE arbiter. So no 42P10 trap is reachable from
  client code today.

  Regression test pins this: any new upsert to either table that uses
  onConflict containing `user_id`, `name`, or `lower(...)` will fail
  the new contract test, forcing the author to either target the PK
  OR drop the partial predicate first.
regression_test_planned:
  - test/contracts/partial_unique_arbiter_inventory_test.dart
---
# Body

## Live audit query (2026-05-17)

```sql
SELECT t.relname AS table_name, i.relname AS index_name,
       pg_get_indexdef(idx.indexrelid) AS index_def
FROM pg_index idx
JOIN pg_class i ON i.oid = idx.indexrelid
JOIN pg_class t ON t.oid = idx.indrelid
JOIN pg_namespace ns ON ns.oid = t.relnamespace
WHERE ns.nspname = 'public'
  AND idx.indisunique = true
  AND idx.indpred IS NOT NULL;
```

Result: 2 rows only.

| table | index | predicate |
|---|---|---|
| user_custom_exercises | uniq_user_custom_exercises_user_name | WHERE user_id IS NOT NULL AND name IS NOT NULL |
| user_custom_foods | uniq_user_custom_foods_user_name | WHERE user_id IS NOT NULL AND name IS NOT NULL |

Both arbiter columns: `user_id` nullable, `name` NOT NULL. Partial
predicate is NOT statically provable from arbiter column types
(user_id nullable) — would trip 42P10 if used as ON CONFLICT arbiter
with a row having user_id = NULL.

## Client safety verification

`grep` for both tables across `lib/core/services/sync/`. Two
upsert callsites:

```dart
// sync_community.dart:127-129
await _supabase.client
    .from('user_custom_exercises')
    .upsert(payload, onConflict: 'id');

// sync_community.dart:152-154
await _supabase.client
    .from('user_custom_foods')
    .upsert(payload, onConflict: 'id');
```

Both target `id` (the PK, always non-null, non-partial). The partial
UNIQUE is a secondary defense for cross-device dedup but is NOT used
as the conflict arbiter from client code. No 42P10 trap reachable.

## Why the partial predicate exists

Migration 049 (Test #11 / DPDP §17): community surfaces
(`user_custom_exercises`, `user_custom_foods`, 3 others) had their FK
relaxed from `ON DELETE CASCADE` to `ON DELETE SET NULL`. When a user
account is hard-deleted, their custom exercise/food rows survive with
`user_id = NULL` for community signal preservation. The partial
predicate `WHERE user_id IS NOT NULL` excludes these orphaned rows
from the UNIQUE constraint — correct, because they should not block
new live users from creating same-named entries.

The partial index is functionally correct for its purpose. It's only
unsafe if MISUSED as an ON CONFLICT arbiter — which the client
doesn't do.

## Conclusion

No code change needed. Inventory documented. Regression test pins the
safety invariant.

## Closing

closes-oi: OI-06
