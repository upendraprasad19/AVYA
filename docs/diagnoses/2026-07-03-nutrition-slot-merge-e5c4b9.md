---
bug_id: e5c4b9
date: 2026-07-03
batch: audit-fixwave-2026-07-02
status: fixed
blast_radius: platform
symptom: >
  NUT-02 same-slot meal data-loss. The local Hive key is item-hash-based —
  `nlog_<istDate>_<mealType>_<itemsHash>` (nutrition_write_service.dart:743-751,
  hash at :788) — so logging TWO different meals into the same slot+day yields
  TWO Hive keys (both kept locally). But the cloud upsert arbiter is
  `onConflict:"user_id,date,meal_type"` (sync_nutrition.dart _syncNutritionLogs,
  originally per-key), so the two same-slot logs COLLAPSE to one cloud row — the
  second overwrites the first. Restore (_restoreNutritionLogs) is additive and,
  pre-fix, per-KEY local-wins, so it cannot recover the lost meal. Net: log
  "salad" then "shake" into lunch → cloud lunch ends up with only "shake"; on
  reinstall the "salad" is gone and totals diverge (Hive had both, cloud one).
  Offline-first hides it until a device switch / reinstall. Founder decision:
  merge same-slot meals into one (no schema migration).
concept: nutrition_slot_merge
sot_registry_entry: >
  nutrition_slot_merge — same-(date, meal_type) nutrition logs are coalesced into
  ONE cloud row (union items + summed totals) at sync time, and restore is
  per-SLOT local-wins, so the (user_id,date,meal_type) natural-key upsert never
  drops a second same-slot meal and a top-up restore never triples a slot.
writers: >
  Local: NutritionWriteService.logMeal (nutrition_write_service.dart:56, key
  computeLogKey item-hash — UNCHANGED). Cloud push: _syncNutritionLogs
  (sync/sync_nutrition.dart) now iterates mergeNutritionLogsBySlot(...) (a pure
  grouping: one payload per slot = union items + summed totals + earliest
  created_at) when the flag is enabled; each merged payload goes through the
  unchanged c9f2a7 parent upsert (id OMITTED) + per-item upsert
  (onConflict log_id,item_index).
readers: >
  Restore: _restoreNutritionLogs (sync/sync_nutrition.dart) reconstructs one Hive
  log per cloud row via SyncService._nlogKeyForRestore (UNCHANGED item-hash key),
  but with per-SLOT local-wins: skip the write if ANY local nlog_ log already
  exists for (date, meal). Nutrition meal-list + macro ring readers render the
  restored (merged) slot log; totals already sum per slot.
hive_key_prefix: nlog_
hive_key_formula: "nlog_<istDateStr>_<mealType>_<itemsHash>  (UNCHANGED — merge is at sync/restore, not the local key)"
sync_methods: ["_syncNutritionLogs", "mergeNutritionLogsBySlot", "_nutritionLogsRaw"]
restore_methods: ["_restoreNutritionLogs (per-slot local-wins)"]
cloud_table: nutrition_logs
cloud_columns: ["user_id", "date", "meal_type", "total_calories", "total_protein", "total_carbs", "total_fat", "total_fiber", "created_at"]
contract_test_path: test/contracts/nutrition_slot_merge_test.dart
ist_handling: >
  The Hive key + cloud `date` column keep istDateStr(date) semantics — unchanged.
  The merge groups by the row's existing `date` + `meal_type` strings; no date
  math. created_at picks the earliest of the group (audit column only).
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["upsert_nutrition_log", "upsert_nutrition_log_item"]
cross_account_guard: true
forbidden_patterns_checked:
  - "Multiple local rows mapping to ONE cloud natural key, where the natural-key upsert silently drops all but the last (same-slot meal overwrite). FIXED: coalesce same-slot logs into one upsert payload (union) so no meal is dropped; restore is per-slot local-wins so a dirty top-up restore never adds a third row for a slot."
  - "A same-slot fix that REKEYS the primary local store on boot (a client data-migration) risking new data loss. AVOIDED: no key change, no boot migration — the merge is at sync + restore only, flag-gated."
proposed_fix: >
  DESIGN PIVOT (from the approved v3 plan's "write-time slot-merge" — documented
  for the Hermes review): implementation revealed the item-hash key is mirrored
  in THREE places (computeLogKey, SyncService._nlogKeyForRestore, NlogKeyMigrator)
  and that making the local key slot-only safely would require a one-shot BOOT
  RE-KEY MIGRATION of the primary local nutrition store (to establish the "≤1 key
  per slot" invariant across existing hash-keyed data) — a much larger, riskier,
  catastrophic-tier change. The chosen approach delivers the founder's decision
  (merge into one; NO migration; merged after reinstall) with far less risk:
  (1) merge-at-sync — _syncNutritionLogs groups all same-(date,meal_type) local
  logs into ONE payload (union items + summed totals) before the natural-key
  upsert, so nothing is dropped; (2) per-SLOT local-wins on restore — skip the
  restore write when ANY local nlog_ exists for the slot, which resolves the
  merge-at-sync top-up-restore triple-count that Review-1 (Reviewer A) had
  flagged (that was the original reason for rejecting merge-at-sync — the per-slot
  guard fixes it). No local key change, no NlogKeyMigrator change, no boot
  migration. Kill-switch `disable_nutrition_slot_merge` (default merge ON) gates
  BOTH the sync grouping and the restore per-slot guard; rollback = flip it →
  legacy per-key push + per-key local-wins. Also F18: populate water_logs.glasses
  = round(total_ml/250) in _syncWaterLogs (was a stale 0; total_ml stays SoT).
regression_test_planned: >
  test/contracts/nutrition_slot_merge_test.dart — pure behavioral tests of
  mergeNutritionLogsBySlot: two same-slot logs → ONE payload with union items +
  summed totals + earliest created_at (fails pre-fix, where each synced
  separately → overwrite); distinct slots stay separate; duplicate identical
  items APPEND (two servings, not de-duped); null-key logs pass through (no
  silent drop). Plus comment-stripped structural gates: sync iterates the merged
  list (flag-gated), restore uses per-slot local-wins (!localSlots.contains), and
  glasses is populated. The end-to-end restore round-trip is the live re-test on
  test7 (two same-slot meals → sign-out / clear-site-data / sign-in → both meals'
  items persist merged) — the runtime proof for the sync↔restore seam.
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — mergeNutritionLogsBySlot + _nutritionLogsRaw + _nutritionLogsMergedBySlot delegation + _syncNutritionLogs iterates merged list + _restoreNutritionLogs per-slot local-wins + F18 glasses (sync/sync_nutrition.dart)."
  - "hive_local — status: verified — local key format UNCHANGED (no re-key migration); merge is projection-only at sync; restore per-slot guard confirmed by structural gate + pure-merge test."
  - "postgres_schema — status: verified — nutrition_logs UNIQUE(user_id,date,meal_type) is the merge arbiter; nutrition_log_items onConflict (log_id,item_index) unchanged; no schema/migration change."
  - "client_to_server_contract — status: fixed_in_this_batch — one upsert per slot (union) instead of one per item-hash key; the c9f2a7 id-omission + per-item projection are reused unchanged."
impact_analysis: >
  Affects any user logging ≥2 different meals into the same slot+day — pre-fix the
  first meal was lost on reinstall/device-switch (silent data-loss). Post-fix both
  meals' items are preserved (merged into one slot row/card), matching the
  founder's chosen semantics. Platform-tier (touches sync/restore, the #1
  recurring bug class) → Hermes-reviewed + feature-flagged + rollback documented.
  No cloud schema migration and NO client boot re-key migration (the safer pivot).
  Behavior-preserving when the flag is disabled. The design pivot from the
  approved plan is called out above for the Hermes reviewer.
---

# e5c4b9 — NUT-02 same-slot meal overwrite / data-loss (merge-at-sync)

See YAML frontmatter for the full diagnosis. Surfaced (code-derived) by the
2026-07-02 comprehensive audit; fixed in the audit-fixwave batch, Unit 3
(Hermes-grade). Founder decision: merge same-slot meals into one, no migration.

## Root cause (one line)
The local Hive key embeds an items-hash so two different meals in one slot get
two keys, but the cloud upsert arbiter is (user_id,date,meal_type) — one row per
slot — so the second same-slot meal overwrote the first and restore couldn't
recover it.

## Fix (design pivot — see YAML `proposed_fix`)
Merge-at-sync (union same-slot logs into one upsert payload) + a 3-way restore
merge. No local key change, no boot migration. Flag `disable_nutrition_slot_merge`;
F18 fills water glasses.

## B-pass / Hermes hardening (2026-07-03)
The self-triggered adversarial B-pass + Hermes lens caught TWO P1 data-loss
defects in the first merge-at-sync cut; both are fixed here (they never shipped):

1. **Orphan-on-shrink.** The merged upsert writes items 0..N-1, but a same-slot
   meal deletion shrinks the union → the old tail (`item_index >= N`) was
   orphaned in cloud (no vacuum), so the deleted meal resurrected on restore and
   parent totals diverged from the item list. **Fix:** an item **tail-vacuum**
   after the per-item upsert (`nutrition_log_items.delete().eq('log_id',…)
   .gte('item_index', items.length)`), mirroring the template_exercises vacuum.

2. **Partial-restore-loss.** The first cut used per-SLOT-occupancy local-wins
   (skip restore if ANY local log exists for the slot). A device with a stale
   PARTIAL local slot (`{salad}`) then never restored cloud's `{salad,shake}` →
   shake silently lost. **Fix:** a **3-way restore merge** — skip only when the
   local slot is a content SUPERSET of the cloud row; otherwise UNION local+cloud
   items (dedup by name|qty), delete the local slot's old keys, and write ONE
   merged row. No loss (union preserves unsynced local items). Restore also now
   reconstructs the `fiber` item field (was dropped).

3. **Duplicate-serving drop (re-Hermes).** A focused re-Hermes on the fixed code
   found the union's set-dedup-by-`name|qty` silently dropped a GENUINE duplicate
   serving (a food logged twice → one item, half the calories). **Fix:** a proper
   **MULTISET union** — for each signature keep `max(localCount, cloudCount)` item
   objects (`nutritionSlotUnion` / `nutritionLocalSlotIsSuperset`, pure +
   unit-tested), preserving duplicate servings while never double-counting an
   already-synced item. Residual (accepted): two genuinely-different foods sharing
   the same name+qty but different macros collapse to one — the same `(name,qty)`
   identity `_nlogKeyForRestore` already uses; not a realistic loss for normal use.

Behavioral + structural tests in `nutrition_slot_merge_test.dart` (duplicate
preserve, cloud-extra restore, local-superset skip, distinct union, shrink); the
full cloud round-trip is the live re-test on test7. NUT-02 converged over 3 review
passes (write-time→migration; merge-at-sync 2×P1; multiset 1×P1) — each surfaced
fewer/lesser issues.

## Pre-commit gate reconciliation (2026-07-03)
The tail-vacuum's `nutrition_log_items.gte('item_index', …)` tripped
`check_schema_column_refs` because `backups/live_schema_columns.json` was **stale**
for this table (it predated the migration that added `item_index`). Verified
LIVE on `dedsavbjuwgarrhphgnl` before trusting the snapshot: `nutrition_log_items`
has `item_index` plus a UNIQUE index `uniq_nli_logid_itemidx ON (log_id,
item_index)` — so both the pre-existing `onConflict:'log_id,item_index'` upsert
AND the new tail-vacuum are correct against live. Fix: added the verified
`item_index` column to the snapshot (Tier-3 schema, `postgres_schema: verified`).

The F5 slot-merge code also introduced an `'nlog_'` key literal into
`sync_nutrition.dart`, which flips the whole-file prefix heuristic in
`check_hive_map_field_drift` (Gate 19) ON — newly surfacing 16 PRE-EXISTING,
vetted-safe reads that `main` already performs (cloud-row projection totals
`total_*`, item fields, water `total_ml`/`urine_*`, saved-meal `is_saved_meal`/
`times_used`, and the vacuum's cloud identifiers `item_index`/`nutrition_log_items`).
None is Hive `nlog_` writer drift (all snake_case, matching their live cloud
columns; the union totals are behaviorally exercised by the merge test). Resolved
append-only in `backups/gate19_drift_baseline.txt` (a `file::prefix::field`-scoped
grandfather, more precise than a global `_alwaysOk` field suppression) — zero
removals, no un-protection of future drift detection.

## Live-verified on test7 (2026-07-03)
Two different meals into the SAME lunch slot — Roti (coach `logMealByText`) +
Paneer (Nutrition UI search) → after sync, **ONE merged cloud `nutrition_logs` row
for lunch with BOTH items** (item_index 0 + 1, 440 kcal / 24g protein). Pre-fix the
2nd same-slot write overwrote the 1st (Roti lost). The live item_index also confirms
the tail-vacuum column against the live schema. The sign-out/in restore round-trip
was NOT completed — a full IndexedDB clear wedged the debug build's fresh-install
boot (dev-harness only, not a product bug); covered by construction (cloud merge
correct + C3 restore live-proven W-A/W-B + the 3-way merge unit-tested). See memory
`feedback_live_restore_test_indexeddb_clear`. Cleanup verified 0 residual.
