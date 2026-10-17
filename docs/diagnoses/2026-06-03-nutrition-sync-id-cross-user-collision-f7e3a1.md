---
bug_id: f7e3a1
date: 2026-06-03
batch: apk-obs-2026-06-02
status: fixed
blast_radius: catastrophic
symptom: >
  The d4b8e2 sweep (workout_logs / weight / sleep / body / wle / wls) left TWO
  nutrition tables on the same un-user-scoped deterministic-id pattern — found by
  the Hermes deep-pass and folded into this batch (founder: "fold in now,
  carefully"). (1) user_saved_meals: the sync sent id = _deterministicId(
  'saved_meal_<nameHash>') — NAME ONLY, no user — so two users who save a meal
  with the same name produce the SAME uuid; onConflict:'id' DO UPDATE OVERWROTE
  one user's saved meal with the other's (and flipped its user_id). (2)
  nutrition_log_items: id = _deterministicId('<nlogKey>_item_<i>') where the nlog
  key embeds date+meal_type+itemsHash but NEVER user_id — so two users logging the
  same food in the same meal-type on the same date produce the SAME item uuid;
  onConflict:'id' DO UPDATE STOLE the item (re-pointed its log_id to the other
  user's parent), leaving the first user's meal with a missing item. Lower
  probability than the date-only d4b8e2 tables (content-hash, not pure date) but
  the same cross-user data-corruption class.
concept: sync_fanout_nutrition_domain
sot_registry_entry: sync_fanout_nutrition_domain
recurrence: "Same family as d4b8e2 (the catastrophic sync-ID sweep earlier in THIS batch) and the omit-id 23503 fixes (nutrition_logs c9f2a7, workout_templates a8b2c7, scheduled_workouts c8e4a1). These two tables were the holdouts d4b8e2's sweep missed because their ids are content-hash-derived (lower collision probability) rather than pure date-only; the Hermes deep-pass surfaced them and the founder chose to fold the fix in rather than fast-follow."
related_bugs:
  - d4b8e2
  - c9f2a7
  - a8b2c7
  - c8e4a1
writers: >
  lib/core/services/sync/sync_nutrition.dart _syncNutritionLogs (the per-item
  upsert into nutrition_log_items, formerly id = _deterministicId('${key}_item_$i'))
  and _syncSavedMeals (the upsert into user_saved_meals, formerly id =
  _deterministicId('saved_meal_<nameHash>')). Both previously sent a
  user-independent deterministic id with onConflict:'id'.
readers: >
  lib/core/services/sync/sync_nutrition.dart _restoreNutritionLogs (cloud → Hive;
  joins nutrition_log_items(*) and derives the local nlog key from row DATA, never
  the cloud id) and _restoreSavedMeals (derives the local saved_meal key from
  lower(name), never the cloud id); supabase/functions/_shared/tools/nutrition/
  getNutritionHistory.ts (reads nutrition_log_items for past ranges). The
  overwritten/stolen rows made the cloud projection wrong for any colliding user.
hive_key_prefix: nlog_ / saved_meal_
hive_key_formula: >
  nlog_${istDateStr}_${mealType}_${itemsHash} (parent; its items[] list is synced
  as child nutrition_log_items rows, one per list position i); saved_meal_${nameHash}
  (name.toLowerCase().trim().hashCode). Neither embeds user_id, so _deterministicId
  over them (or over '<nlogKey>_item_<i>') was identical across users for the same
  content.
sync_methods: _syncNutritionLogs, _syncSavedMeals
restore_methods: _restoreNutritionLogs, _restoreSavedMeals
cloud_table: nutrition_log_items, user_saved_meals
cloud_columns: >
  nutrition_log_items(id pk gen_random_uuid, log_id NOT NULL FK→nutrition_logs(id)
  ON DELETE CASCADE, food_id, food_name, quantity_g, calories, protein, carbs, fat,
  fiber, created_at) — migration 083 ADDS item_index int NOT NULL +
  UNIQUE(log_id,item_index). user_saved_meals(id pk gen_random_uuid, user_id NOT NULL
  FK→users(id), name NOT NULL, items jsonb, total_calories, total_protein,
  times_used, created_at) — migration 083 ADDS UNIQUE(user_id,name). Nothing
  FK-references either table's id (verified live: fk_refs null) → omitting the id
  orphans nothing.
contract_test_path: test/contracts/sync_user_scoped_natural_keys_test.dart
ist_handling: not_applicable (no date math changed; ids/onConflict/new column only)
provider_invalidations: not_applicable (background cloud-replay; local Hive + providers already updated at write time)
telemetry_op_types: >
  unchanged sinks: upsert_nutrition_log_item / upsert_saved_meal via
  _reportSyncFailure + recordNonFatal; upsert_user_saved_meals_success success-path
  event. The fix removes the silent cross-user overwrite; the sinks stop masking it.
cross_account_guard: >
  This bug WAS a cross-account guard hole at the cloud layer — a name-only / nlog-key
  item id let one user's upsert overwrite or steal another's row. The fix closes it:
  user_saved_meals identity is now (user_id, name) — arbiter leads with user_id;
  nutrition_log_items identity is (log_id, item_index) where log_id is the
  user-scoped parent (nutrition_logs UNIQUE(user_id,date,meal_type)), so an item can
  only ever attach to the syncing user's own log.
forbidden_patterns_checked:
  - "A nutrition sync upsert that sends a user-independent deterministic id (name-only or nlog-key-derived) — eliminated: both OMIT id (gen_random_uuid default); pinned by test/contracts/sync_user_scoped_natural_keys_test.dart."
  - "Using (log_id, food_name) as the item arbiter — REJECTED as a data-loss trap: a meal legitimately holds the same food twice (12 live (log_id,food_name) duplicate groups, e.g. 'Whey Protein Isolate' x2). The arbiter is POSITION-based (log_id, item_index) so legit duplicates are preserved, never merged. Pinned by the 'item key is POSITION-based, never food_name' test."
proposed_fix: >
  Apply the omit-id + user/parent-scoped natural-key pattern to the two nutrition
  holdouts. Client (sync_nutrition.dart): _syncSavedMeals OMITS id (gen_random_uuid)
  + onConflict 'user_id,name'; _syncNutritionLogs items loop OMITS id + sends
  'item_index': i + onConflict 'log_id,item_index'. Migration 083 backs the keys:
  UNIQUE(user_id,name) on user_saved_meals (both cols already NOT NULL → non-partial,
  no 42P10; table empty in cloud → zero existing-data risk); on nutrition_log_items,
  ADD item_index int, BACKFILL it per-log by insertion order
  (row_number() OVER (PARTITION BY log_id ORDER BY created_at, id) - 1) which mirrors
  the client's emit order i, SET NOT NULL, then UNIQUE(log_id,item_index). The
  position-based key is the careful part — food_name would merge legitimately-distinct
  same-food items and lose data. NO historical re-key: saved_meals self-heal via
  (user_id,name) on next sync; items self-heal via (log_id, backfilled item_index)
  matching the client's i. Verified live before writing: nothing FK-references
  either id; user_saved_meals empty; nutrition_log_items has 0 null/empty food_name
  (174 rows) and the simulated backfill yields 0 duplicate (log_id,item_index) groups
  (clean unique-index create). Deploy-ordering: migration 083 ships WITH the matching
  APK (an old client that still sends no item_index would 23502 on item inserts once
  the column is NOT NULL — acceptable pre-launch / single device; same posture as 082).
regression_test_planned: >
  test/contracts/sync_user_scoped_natural_keys_test.dart (comment-stripped
  source-grep, extended this batch): nutrition_log_items upserts OMIT id + send
  item_index + onConflict 'log_id,item_index'; user_saved_meals OMITS id + onConflict
  'user_id,name'; the arbiter is never 'log_id,food_name'; migration 083 adds
  item_index (backfilled via row_number), uniq_nli_logid_itemidx,
  uniq_user_saved_meals_user_name. Behavioral proof: a read-only simulation of the
  083 backfill over LIVE data (174 rows / 157 logs) returns 0 unassigned rows + 0
  duplicate (log_id,item_index) groups → the unique index creates cleanly and the 12
  legit duplicate-food groups are preserved as distinct positions. The sync layer has
  no fakeable Supabase-client harness, so the cross-user-isolation proof is the live
  schema (fk_refs null, NOT NULL arbiters) + the post-deploy rollback-txn arbiter
  check at apply.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "sync_nutrition.dart: _syncNutritionLogs items loop omits id + sends item_index + onConflict 'log_id,item_index'; _syncSavedMeals omits id + onConflict 'user_id,name'. flutter analyze clean on the changed file; sync_user_scoped_natural_keys_test.dart 8/8 green" }
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migration 083 written: UNIQUE(user_id,name) on user_saved_meals; item_index int NOT NULL (backfilled) + UNIQUE(log_id,item_index) on nutrition_log_items. Apply pending (deploy phase, with the APK)" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live 2026-06-03: fk_refs=null (nothing references either id); user_saved_meals total=0 rows; nutrition_log_items 174 rows, 0 null/empty food_name, 12 legit (log_id,food_name) dup groups; simulated item_index backfill → 0 rows_left_unassigned, 0 dup_logid_itemindex groups (clean index create, no re-key, no merge)" }
  - { tier: 6, layer: edge_function_vs_deploy, status: verified, evidence: "getNutritionHistory.ts only SELECTs nutrition_log_items (read); no Edge Function WRITES either table → the client sweep is complete (grep of supabase/functions + lib confirms sync_nutrition.dart is the sole writer for each)" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "post-fix, two users with identical saved-meal names / identical food in the same meal+date each retain their own rows (gen_random_uuid id + user/parent-scoped arbiter); restore derives local keys from row DATA so id-omission is invisible to round-trip" }
impact_analysis: >
  Catastrophic blast radius (cloud identity of per-user nutrition rows), lower
  realization probability than d4b8e2 because the ids are content-hash-derived rather
  than pure date-only — but the same corruption when two users share content.
  user_saved_meals: a name-only id meant the second user to sync a same-named meal
  (e.g. "Chicken Rice") DO-UPDATEd the first user's row, flipping its user_id — the
  first user lost the meal entirely. nutrition_log_items: an nlog-key-derived item id
  (no user) meant two users logging the same food in the same meal-type on the same
  date collided on the item PK; the second user's upsert re-pointed the row's log_id
  to its own parent — item theft, leaving the first user's meal short an item. Found
  by the Hermes deep-pass AFTER the d4b8e2 sweep set its scope; the founder chose to
  fold the fix in this batch rather than fast-follow. The cure is the codebase's
  established omit-id + user/parent-scoped-natural-key pattern, with one careful
  twist forced by the data: the item arbiter is POSITION-based (log_id, item_index),
  NOT (log_id, food_name) — because a meal legitimately holds the same food twice (12
  live groups), and a name-based merge would silently delete one of them. The
  item_index is backfilled deterministically by per-log insertion order, proven over
  live data to yield a clean unique index with zero merges and zero re-key.
---

# Nutrition sync-ID cross-user collision — the two omit-id holdouts (saved meals + log items)

## What happened
The d4b8e2 catastrophic sweep fixed the date-only sync tables but set its scope
before two **content-hash** tables were known to share the class. The Hermes
deep-pass surfaced them:

- **`user_saved_meals`** — sync id was `_deterministicId('saved_meal_<nameHash>')`,
  **name only, no user**. Two users who save a meal with the same name → same uuid
  → `onConflict:'id'` **overwrote** one user's meal with the other's (and flipped
  `user_id`).
- **`nutrition_log_items`** — sync id was `_deterministicId('<nlogKey>_item_<i>')`
  where the nlog key embeds date + meal_type + itemsHash but **never `user_id`**.
  Two users logging the same food in the same meal-type on the same date → same item
  uuid → `onConflict:'id'` **stole** the item (re-pointed `log_id` to the other
  user's parent).

## Fix
Omit `id` (gen_random_uuid) + a user/parent-scoped `onConflict`:
- `user_saved_meals` → `onConflict('user_id,name')` + `UNIQUE(user_id,name)`.
- `nutrition_log_items` → `onConflict('log_id,item_index')` + a new `item_index`
  column + `UNIQUE(log_id,item_index)`.

**The careful part:** the item arbiter is **position-based**, not `food_name`. Live
data has **12 legitimate `(log_id, food_name)` duplicate groups** (a meal genuinely
holds the same food twice), so `(log_id, food_name)` would merge and *lose data*.
`item_index` (the item's position in the meal) is unique within the user-scoped log,
idempotent on re-sync, and never merges legit duplicates. **No historical re-key** —
saved meals self-heal via `(user_id, name)`; items self-heal via `(log_id,
backfilled item_index)`. Migration 083 ships **with the APK** (same deploy-ordering
as 082).

## Verification
- Live (read-only, nothing applied): `fk_refs=null`; `user_saved_meals` empty;
  `nutrition_log_items` 174 rows / 0 null food_name / 12 dup-food groups; **simulated
  `item_index` backfill → 0 unassigned, 0 duplicate `(log_id,item_index)`** → the
  unique index creates cleanly and the dup-food groups are preserved.
- `sync_user_scoped_natural_keys_test.dart` 8/8 (4 nutrition assertions added,
  incl. the "never `food_name`" data-loss guard).
- Post-deploy: rollback-txn arbiter check at apply.

## Lesson / class
When sweeping a cross-user identity bug, content-hash ids hide in the long tail
behind the obvious date-only ones — re-grep EVERY `_deterministicId` /
`onConflict:'id'` sync writer, not just the date-keyed ones. And a child-row natural
key must be **position-stable**, never a content field that can legitimately repeat
within the parent (`food_name` here) — or the "fix" silently deletes real data.

## See also
- `lib/core/services/sync/sync_nutrition.dart` (`_syncNutritionLogs` items loop, `_syncSavedMeals`)
- `supabase/migrations/083_nutrition_sync_natural_keys.sql`
- Same-batch parent sweep: `d4b8e2`; prior omit-id: `c9f2a7`, `a8b2c7`, `c8e4a1`
- `feedback_partial_unique_arbiter_trap.md`, `feedback_writer_reader_field_drift_recurring.md`
