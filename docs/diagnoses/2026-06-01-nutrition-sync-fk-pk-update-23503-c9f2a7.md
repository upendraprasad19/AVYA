---
bug_id: c9f2a7
date: 2026-06-01
batch: derive-only-ai-coach-tool-surface
status: fixed
blast_radius: platform
symptom: >
  Driving the AI coach live as amar (a year-sim power user), a coach
  `logMealByText` wrote to Hive correctly — the Nutrition Today's Summary card
  bumped exactly right (4314 -> 4644 kcal, protein 290 -> 309, after APPLY of a
  330 kcal / 19 g meal) — but the meal NEVER reached the cloud. The console
  showed, on EVERY nutrition sync:
  `[SyncService._syncNutritionLogs] PostgrestException(... violates foreign key
  constraint "nutrition_log_items_log_id_fkey", code: 23503, ... Key is still
  referenced from table "nutrition_log_items".)`.
  Offline-first hid the failure (the screen read Hive and looked fine), but the
  cloud backup of nutrition silently failed for the user — a reinstall or
  device-switch would lose every client-side meal. Affects any user whose local
  (date, meal_type) ends up referencing a cloud row under a different id.
concept: sync_fanout_nutrition_domain
sot_registry_entry: sync_fanout_nutrition_domain
recurrence: "3rd instance of the natural-key-upsert-rewrites-a-FK-referenced-PK (23503) class. Prior: workout_templates (APK Test #12.8 / Bug #4, a8b2c7) + scheduled_workouts (APK Test #14 / Bug B.1, c8e4a1). nutrition_logs was the last sync still sending a derived id; same cure (omit id) applied."
related_bugs:
  - a8b2c7
  - c8e4a1
writers:
  - lib/core/services/sync/sync_nutrition.dart _syncNutritionLogs (cloud projection of nlog_* Hive rows → nutrition_logs parent + nutrition_log_items children; FIX: resolve the existing nutrition_logs id for the (user,date,meal_type) natural key and reuse it before the upsert)
readers:
  - lib/core/services/sync_service.dart _restoreNutritionLogs (cloud → Hive round-trip; rebuilds nlog_* from nutrition_logs + nutrition_log_items)
  - supabase/functions (weekly-report / analytics) reading nutrition_logs as the cloud projection
hive_key_prefix: nlog_
hive_key_formula: nlog_${istDateStr(date)}_${mealType}_${itemsHash} (NutritionWriteService.computeLogKey, nutrition_write_service.dart:740) — itemsHash is part of the key, so the SAME (date,meal_type) yields DIFFERENT keys (and thus different _deterministicId) when the item set changes.
sync_methods: _syncNutritionLogs (lib/core/services/sync/sync_nutrition.dart) — the single canonical cloud writer; NutritionRepository.syncLogToSupabase was removed (audit 2026-05-20 / A8, zero callers).
restore_methods: _restoreNutritionLogs (sync_service.dart) — rebuilds nlog_* Hive rows from cloud nutrition_logs + nutrition_log_items.
cloud_table: nutrition_logs (parent) + nutrition_log_items (child)
cloud_columns: >
  nutrition_logs(id, user_id, date, meal_type, total_calories, total_protein,
  total_carbs, total_fat, total_fiber, created_at);
  nutrition_log_items(id, log_id, food_id, food_name, quantity_g, calories,
  protein, carbs, fat, fiber, created_at). FK nutrition_log_items_log_id_fkey:
  log_id → nutrition_logs(id) ON DELETE CASCADE, ON UPDATE NO ACTION (verified
  live: confdeltype='c', confupdtype='a'). UNIQUE uniq_nutrition_logs_user_date_meal
  (user_id, date, meal_type) — NON-partial.
contract_test_path: test/contracts/sync_nutrition_log_id_resolved_before_upsert_test.dart
ist_handling: not_applicable (no date math changed; date passes through from the Hive log['date'], already istDateStr at write time)
provider_invalidations: not_applicable (background cloud-replay path; the local Hive write at logMeal time already invalidated the nutrition provider set — the sync fan-out does not mutate Hive or providers)
telemetry_op_types: >
  not_applicable for new telemetry. Pre-existing sinks unchanged: a sync failure
  still routes through ErrorTelemetry.recordNonFatal(reason: 'sync_service_catch_6')
  + _reportSyncFailure(opType: 'upsert_nutrition_log'). The fix removes the 23503
  cause, so those stop firing for it. (A future enhancement could emit a
  `sync_nutrition_log_id_reused` debug event for observability.)
cross_account_guard: >
  preserved. _syncNutritionLogs iterates the user-scoped nutritionBox
  (HiveService.instance via wrapUserScopedBox). The new resolve-existing-id SELECT
  is scoped by .eq('user_id', userId), so it can only ever match the syncing
  user's own rows — no cross-account id leakage.
forbidden_patterns_checked:
  - "Upsert with onConflict on a natural key while sending a row `id` that may differ from the existing row's PK (rewrites a FK-referenced PK) — eliminated: `id` is OMITTED from the payload; pinned by test/contracts/sync_nutrition_log_id_resolved_before_upsert_test.dart."
  - "ON CONFLICT DO UPDATE that mutates a PK referenced by an ON UPDATE NO ACTION FK (23503) — cannot occur once `id` is omitted (DO UPDATE only sets the columns present in the payload)."
proposed_fix: >
  In `_syncNutritionLogs`, OMIT `id` from the `nutrition_logs` upsert payload —
  the established cure for this class (see a8b2c7 / workout_templates and c8e4a1 /
  scheduled_workouts). PostgREST's ON CONFLICT DO UPDATE sets only the columns
  present in the payload, so omitting `id` keeps the existing row's PK on conflict
  and lets the column default gen_random_uuid() assign it on first insert — the PK
  is NEVER rewritten, so the ON UPDATE NO ACTION FK is never tripped. Then resolve
  the real cloud id by the (user_id,date,meal_type) natural key
  (`SELECT id ... .maybeSingle()` — the key is a non-partial UNIQUE) for the
  children's `log_id`; if that lookup fails the parent has already landed safely,
  so skip the children this pass (next sync retries). The null-natural-key guard
  is hoisted first (date+meal_type are required both as the upsert arbiter and as
  the resolve key). Hive stays the source of truth; local totals still overwrite
  the cloud row.
regression_test_planned: >
  test/contracts/sync_nutrition_log_id_resolved_before_upsert_test.dart (4/4,
  comment-stripped source-grep): pins (1) the nutrition_logs upsert payload OMITS
  `id`, (2) the real cloud id is resolved AFTER the upsert by the
  (user,date,meal_type) natural key (maybeSingle + parentRow?['id']) for the
  children, (3) children are skipped when the parent id cannot be resolved,
  (4) the natural-key onConflict merge is preserved. Behavioral proof: the live
  FK mechanism check (ON DELETE CASCADE means a delete would not 23503 → the
  failing op must be the PK update) + the live web re-verification below (the sync
  layer has no fakeable Supabase-client harness, so an in-flutter-test behavioral
  test is not available).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "sync_nutrition.dart _syncNutritionLogs OMITS id from the nutrition_logs upsert (existing PK preserved on conflict, gen_random_uuid on insert) + resolves the real id by (user,date,meal_type) for the children; flutter analyze on the file = No issues found; contract test 4/4 pass" }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "live pg_constraint: nutrition_log_items_log_id_fkey confdeltype='c' (ON DELETE CASCADE) + confupdtype='a' (ON UPDATE NO ACTION) → a parent DELETE cascades cleanly, so the observed 'update or delete ... Key is still referenced' can ONLY be a PK UPDATE; uniq_nutrition_logs_user_date_meal is a NON-partial UNIQUE(user_id,date,meal_type) → maybeSingle is safe" }
  - { tier: 4, layer: postgres_data, status: fixed_in_this_batch, evidence: "before fix: amar 2026-06-01 cloud had only 3 sim-seeded nutrition_log_items; coach-logged meals absent. After fix + live re-sync: 'Paneer Bhurji with Roti and Rajma' (lunch, log_id d62ffb3f) AND 'Boiled Eggs and Banana' (breakfast, log_id 9a5ed263) present — parent ids PRESERVED (reused, not rewritten)" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "live web E2E (amar, real CanvasKit): coach logMealByText APPLY → Hive +330 kcal (4314→4644) AND after the fix the rows reach cloud; post-sync console shows ZERO 23503 / PostgrestException / foreign-key errors (pre-fix build threw 23503 on every _syncNutritionLogs)" }
impact_analysis: >
  Platform blast radius — touches the single canonical nutrition cloud-projection
  writer that every user's meals flow through. The bug manifested whenever a local
  (date, meal_type) referenced a cloud nutrition_logs row under an id different
  from the current nlog key's deterministic id. Triggers in normal production: a
  meal re-logged or edited the same day (itemsHash → new key → new deterministic
  id), a coach-merge, or any prior writer (legacy keys, the headless sim) that
  seeded the row under another id. Once tripped, the natural-key upsert tried to
  rewrite the parent PK, the FK (ON UPDATE NO ACTION) rejected it (23503), and the
  WHOLE parent + items upsert failed — so nutrition stopped backing up to cloud
  for that user, silently, while the offline-first UI kept looking correct. The
  fix is conservative and backward compatible: when no cloud row exists for the
  natural key it falls back to the prior deterministic-id behavior (fresh insert);
  when one exists it reuses that id (no PK mutation). It only ever makes a
  previously-FAILING sync succeed — strictly better. Verified live: the
  previously-stuck meals reached cloud under their preserved parent ids with no
  23503. Found live via the Claude-in-Chrome E2E on amar during the derive-only
  AI-coach batch's cross-surface SoT verification — exactly the writer→sync→cloud
  drift class the E2E was designed to catch.
  Known limitation (pre-existing, out of scope, NOT introduced by this fix): when
  duplicate local nlog keys map to one (date, meal_type) — e.g. the sim's restored
  row plus a fresh coach log — the cloud parent total_calories reflects the
  last-synced nlog while child items accumulate under the shared parent. The
  Hive-summed UI total (NutritionReadService.totalMacrosForDate sums all rows)
  stays correct; only the cloud projection's parent total is imprecise. The
  NlogKeyMigrator collapses to one nlog per (date, meal_type) in steady state. A
  follow-up could sum items into the parent total on sync.
---

# Coach meals never reached cloud — nutrition sync rewrote a FK-referenced PK (23503)

## What happened

Driving the AI coach as amar in the live web E2E, a coach `logMealByText` was
APPLY-confirmed and the Nutrition screen updated perfectly (Today's Summary
4314 → 4644 kcal, protein 290 → 309). But the meal never appeared in the cloud
`nutrition_log_items`. The browser console showed, on every nutrition sync:

> `[SyncService._syncNutritionLogs] PostgrestException(... violates foreign key
> constraint "nutrition_log_items_log_id_fkey", code: 23503, ... Key is still
> referenced from table "nutrition_log_items".)`

Offline-first masked it — the screen reads Hive — but the cloud backup of
nutrition silently failed.

## Root cause

`_syncNutritionLogs` upserts the `nutrition_logs` parent with
`onConflict: "user_id,date,meal_type"` while including `id: _deterministicId(key)`
in the payload. The `nlog_` Hive key embeds an `itemsHash`, so the SAME
(date, meal_type) yields a DIFFERENT deterministic id whenever the item set
changes (re-log / edit / coach-merge); other writers (the headless sim, legacy
keys) seeded rows under yet other ids. When a cloud row already exists for the
natural key under a DIFFERENT id, `ON CONFLICT DO UPDATE` tries to rewrite the
row's PK `id`.

`nutrition_log_items.log_id` FK-references that PK. The FK is **`ON DELETE
CASCADE` but `ON UPDATE NO ACTION`** (verified live: `confdeltype='c'`,
`confupdtype='a'`). A parent DELETE would cascade cleanly — so the observed
"update or delete … Key is still referenced" can only be a **PK update**.
Postgres rejects it (23503), and the whole parent upsert + its child items fail
to reach cloud.

## Fix

OMIT `id` from the `nutrition_logs` upsert payload — the established cure for
this class (workout_templates `a8b2c7`, scheduled_workouts `c8e4a1`). PostgREST's
`ON CONFLICT DO UPDATE` sets only the columns present, so omitting `id` keeps the
existing PK on conflict and uses the `gen_random_uuid()` default on first insert
— the PK is never rewritten → no 23503. Then resolve the real cloud id by the
natural key (`SELECT id … maybeSingle()`) for the children's `log_id`; if that
lookup fails the parent already landed, so skip the children this pass (next sync
retries). The null-natural-key guard is hoisted first.

## Verification (live, end-to-end)

- `flutter analyze` on the file → No issues found.
- `test/contracts/sync_nutrition_log_id_resolved_before_upsert_test.dart` → 3/3.
- Live schema: FK `on_delete=c` / `on_update=a`; `uniq_nutrition_logs_user_date_meal`
  is non-partial UNIQUE.
- Live web (amar): after rebuilding with the fix, coach-logged
  "Paneer Bhurji with Roti and Rajma" (lunch) and "Boiled Eggs and Banana"
  (breakfast) reached cloud `nutrition_log_items` under their **preserved** parent
  ids (`d62ffb3f` lunch, `9a5ed263` breakfast); post-sync console showed **zero**
  23503 / PostgrestException / FK errors. The pre-fix build threw 23503 on every
  `_syncNutritionLogs`.

## Lesson / class

3rd instance of one class: a natural-key upsert that ALSO sends a row `id` will,
on conflict with a differently-id'd row, try to rewrite a PK; if a child FK
references that PK `ON UPDATE NO ACTION`, the whole upsert 23503s and the domain
stops syncing — silently, behind offline-first. The cure is uniform: OMIT `id`
from natural-key upserts so the PK is never touched (DO UPDATE only sets the
columns present), then resolve the real cloud id for any children. Prior
instances fixed workout_templates (`a8b2c7`) and scheduled_workouts (`c8e4a1`);
`nutrition_logs` was the last sync still sending a derived id. Source-grep
`onConflict:` tests prove the arbiter string, never the runtime id semantics — a
live behavioral check (FK mechanism + live E2E) is required. A standing
source-grep gate ("a natural-key upsert payload must not carry `id`") would catch
the next recurrence before merge.

## See also

- `lib/core/services/sync/sync_nutrition.dart` (`_syncNutritionLogs`)
- `lib/core/services/sync/sync_workout.dart` (`_syncWorkoutTemplates` ~line 1024 — the established omit-id pattern this fix mirrors)
- `test/contracts/sync_nutrition_log_id_resolved_before_upsert_test.dart`
- Prior instances of this class: `a8b2c7` (workout_templates, APK Test #12.8 / Bug #4), `c8e4a1` (scheduled_workouts, APK Test #14 / Bug B.1)
- `test/sql/onconflict_live_arbiter.sql` (sibling live-arbiter scaffold; pins ON
  CONFLICT acceptance, not FK-on-PK-update — note its `nutrition_log_items` case
  uses stale columns `nutrition_log_id`/`name` vs live `log_id`/`food_name`)
- `feedback_partial_unique_arbiter_trap.md`, `feedback_writer_reader_field_drift_recurring.md`
- ADR-0012 (the derive-only batch this surfaced in)
