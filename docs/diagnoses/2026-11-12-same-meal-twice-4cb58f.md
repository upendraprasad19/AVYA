---
bug_id: 4cb58f
date: 2026-11-12
batch: oi493b-duplicate-meals
status: fixed
blast_radius: account
symptom: >-
  Logging the same meal again (same IST day, same slot, same item names and grams) REPLACED the first entry instead of
  adding a second, so the day counted it once (OI-493, founder decision F4: "if we are logging same meal twice it
  should log twice"). Four more ways an `nlog_` key overwrote or collapsed entries came with it: UNDO put a deleted row
  back over a newer one; a move into a slot holding the same meal MERGED the two into one row; the v7 key migrator,
  on a device's first restore, re-keyed every current row to a hashCode key on the UTC day of `logged_at` and kept only
  the latest row per group; and an AI total of 0 was stored as 0 kcal even when the items carried calories. Two older
  UNDO defects surfaced in review: after two deletes in a row the first snackbar's UNDO restored the SECOND row, and an
  UNDO was not bound to the account it was made under.
concept: nutrition_total_calories
sot_registry_entry: hive_field_name_nlog
writers:
  - file: lib/core/services/nutrition_write_service.dart
    method: logMeal (first free occurrence key; override only when > 0)
    line: 66
  - file: lib/core/services/nutrition_write_service.dart
    method: moveMealLog (first free occurrence at the destination; collision merge removed)
    line: 420
  - file: lib/core/services/nutrition_write_service.dart
    method: deleteLog / restoreLastDeleted(expectedKey:) / restoreFoodLog (owner-bound, never overwrite)
    line: 520
  - file: lib/core/services/nlog_key_migrator.dart
    method: NlogKeyMigrator.runIfNeeded (skips current-shape keys; legacy rows keep one entry each)
    line: 36
  - file: lib/features/ai_coach/services/conversational_log_handler.dart
    method: executeAction (static in-flight map by action id)
    line: 45
readers:
  - file: lib/core/services/nutrition_read_service.dart
    method_or_widget: totalMacrosForDate (sums every nlog_ row of the day; a second row is a second entry)
    line: 112
  - file: lib/core/services/sync/sync_nutrition.dart
    method_or_widget: mergeNutritionLogsBySlot (push: one cloud row per slot, a second serving is a second item)
    line: 10
  - file: lib/core/services/sync/sync_nutrition.dart
    method_or_widget: nutritionLocalSlotIsSuperset / nutritionSlotUnion (restore, multiset)
    line: 72
  - file: lib/features/nutrition/screens/nutrition_screen.dart
    method_or_widget: the two UNDO snackbars (restoreLastDeleted at :732, restoreFoodLog at :900)
    line: 732
hive_key_prefix: nlog_
hive_key_formula: "nutritionBox['nlog_<istDateStr(date)>_<meal_type>_<v5 8 hex of sorted name|grams>'] plus an optional occurrence suffix '_<n>' (n >= 2) for the same meal logged again; shape NutritionWriteService.kNlogKeyShape"
sync_methods:
  - NutritionWriteService.logMeal -> syncNutritionData (unchanged; mergeNutritionLogsBySlot concatenates the slot's rows)
restore_methods:
  - SyncService._restoreNutritionLogs (unchanged; multiset union, superset skip)
cloud_table: nutrition_logs
cloud_columns: []
contract_test_path: test/contracts/nlog_repeat_adds_entry_behavioral_test.dart
ist_handling:
  - The base key's day is istDateStr(date), unchanged. The migrator no longer moves a current row to the UTC day of logged_at (R5 pins a row whose UTC day differs from its IST day).
provider_invalidations:
  - unchanged (logMeal / moveMealLog / both restores call _invalidateNutritionProviders)
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "deleteLog records HiveUserSession.currentOwnerHash per deleted key (last 16); both UNDO paths refuse when the recorded or the current hash is null or they differ (R3)."
forbidden_patterns_checked:
  - { pattern: "box.put(key, payload) on a computed nlog_ key without firstFreeLogKey in nutrition_write_service.dart", absent: true }
  - { pattern: "existingAtDestination merge in moveMealLog", absent: true }
  - { pattern: "restoreLastDeleted() with no expectedKey", absent: true }
proposed_fix: >-
  B1 logMeal writes the first FREE occurrence (base, base_2, ...) of computeLogKey, chosen and put inside the existing
  try with no await between (Hive 2.2.3 inserts into its keystore before its first await), and stamps id / log_key with
  it. B2 restoreLastDeleted takes the key its snackbar deleted, both UNDO paths refuse across an owner change or a null
  owner, and restore under the first free occurrence when the key was taken meanwhile, on a copy. B3 moveMealLog writes
  the first free occurrence at the destination; the collision merge is removed. B4 the migrator skips current-shape
  keys and gives each legacy row its own entry. B6 one tag action, one write (a static in-flight map in
  ConversationalLogHandler; LogConfirmCard captures the actions notifier before the await and clears the action even
  when unmounted). B7 SingleFlight on the write identity for the search, recent, barcode, AI-text (in the notifier,
  result WriteResult.inFlight shown as a neutral "Saving meal…") and scan saves. B8 an override applies only when > 0.
  The coach tool needs no change: confirm() already refuses a second APPLY or retry while the intent executes.
regression_test_planned:
  - test/contracts/nlog_repeat_adds_entry_behavioral_test.dart
  - test/ai_coach/log_confirm_card_single_write_test.dart
  - test/contracts/nutrition_log_retag_writer_to_reader_test.dart
related_bugs:
  - e5c4b9  # same-slot data loss on push (NUT-02 slot merge): one cloud row per slot, the reason a second serving is an item
  - ec6f6c  # OI-493 Landing A (coach meal parity); this is Landing B of the same issue
  - a3f6c9  # moveMealLog clamp-after-merge; the merge is removed, the clamp re-pinned on the moved row
recurrence: |
  Not a recurrence of a fixed bug: the overwrite was the design (one row per day+slot+items) and F4 changes it. The
  restore side already treated a repeat as two servings (the Hermes P1 that made nutritionSlotUnion a multiset), so the
  device was the only tier that collapsed them. The UNDO-restores-the-wrong-row defect is pre-existing (the stash was
  always single); it surfaced because occurrence keys made it visible.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "nutrition_write_service.dart, nlog_key_migrator.dart, conversational_log_handler.dart, log_confirm_card.dart, single_flight.dart (new), write_result.dart, nutrition_provider.dart, ai_breakdown_card.dart, scan_meal_section.dart, search_mode_body.dart, barcode_scan_sheet.dart, nutrition_screen.dart. flutter analyze lib/: no warning." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "Real Hive: repeats, un-awaited pairs, UNDO on both paths, move, migrator on a fresh flag, the tag handler (captured WidgetRef) and the AI-text notifier all checked by row count and day totals." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; the cloud keeps one nutrition_logs row per (user, date, meal_type)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data change; a second serving reaches the cloud as a second nutrition_log_items row through the unchanged push." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "R9 drives the pure push merge and the restore helpers: base + base_2 push as one slot row with two items (2x calories); this device's restore skips (superset); a second device restores ONE row with two items (the accepted residual)." }
impact_analysis: >-
  Logging the same meal twice now counts twice on every screen and in the coach snapshot, and reaches the cloud as two
  items. UNDO, move and the first-restore migrator never fold two servings into one. A double tap still logs once; a
  tap after the first save logs again. A meal whose AI total came back 0 is stored with its items' calories.
---

# The same meal logged twice is two entries (4cb58f, OI-493 Landing B)

Plan: `docs/plans/oi493b-duplicate-meals.md` (rev 2.1, converged after 2 review rounds, record
`docs/plan-reviews/oi493b-duplicate-meals.md`).

## Root cause
`logMeal` keyed a meal by `computeLogKey(date, slot, items)` and `box.put` OVERWROTE a row already at that key. The
other `nlog_` writers put to a key without checking it was free: `restoreLastDeleted` / `restoreFoodLog` (old key),
`moveMealLog` (merged on collision), and `NlogKeyMigrator` (regrouped by a hashCode key and kept the latest row).

## Fix
Section B of the plan, summarised in `proposed_fix` above.

## Mutations (rule 21)
A scripted harness applied each mutant (exact-string replace, count asserted == 1), ran the named test file(s) under
`TZ=Asia/Kolkata`, restored the file from a copy and compared it byte for byte (every restore: True). 20 of 20 red.

| # | Mutant | File | Test run | Red |
|---|---|---|---|---|
| M1 | logMeal puts the base key | nutrition_write_service | new file | 4 |
| M2 | `await` between key choice and put | nutrition_write_service | new file | 1 (R2) |
| M3 | `baseLogKey` strips a bare `_\d+$` | nutrition_write_service | new file | 1 (R3b) |
| M4 | no `expectedKey` check | nutrition_write_service | new file | 1 |
| M5 | owner guard always true | nutrition_write_service | new file | 2 |
| M7 | restore target is always the stashed key | nutrition_write_service | new file | 2 |
| M8 | `_withLogKey` mutates the caller's map | nutrition_write_service | new file | 1 |
| M9 | move puts the base key | nutrition_write_service | new file + retag | 3 |
| M10 | migrator regroups current-shape keys | nlog_key_migrator | new file | 2 |
| M11 | migrator ignores `migrated_from` | nlog_key_migrator | new file | 1 (R5b) |
| M12 | migrator keeps only the group's latest row | nlog_key_migrator | new file | 1 |
| M13 | handler without in-flight reuse | conversational_log_handler | new file | 1 (R6) |
| M14 | SingleFlight never skips | single_flight | new file | 2 |
| M15 | saveMeal bypasses the flight | nutrition_provider | new file | 2 |
| M16 | calorie override 0 kept | nutrition_write_service | new file | 1 |
| M17 | protein override 0 kept | nutrition_write_service | new file | 1 |
| M18 | card marks the action only when mounted | log_confirm_card | card test | 1 |
| M19 | unmounted card does not clear the action | log_confirm_card | card test | 1 |
| M20 | scan sets `_saving` before taking the flight | scan_meal_section | new file (source pin) | 1 |
| M21 | `restoreFoodLog` without the owner guard | nutrition_write_service | new file | 1 |

After the B-pass (its mutation seat found six unpinned mirrors, all test gaps, none a defect), the tests were extended
and a second batch run the same way, 12 of 12 red:

| # | Mutant | File | Red |
|---|---|---|---|
| B1 | `while` -> `if` in `firstFreeLogKey` (a 4th serving overwrites the 3rd) | nutrition_write_service | 1 (R1 five servings) |
| B2 | `restoreFoodLog` puts the raw map (stale `id` / `log_key`) | nutrition_write_service | 1 |
| B3 | `restoreFoodLog` keeps the owner record (a second UNDO adds a copy) | nutrition_write_service | 1 |
| B4a / B4b | owner record cap 1 / 17 | nutrition_write_service | 1 / 1 |
| B5 | a negative override kept | nutrition_write_service | 1 |
| B6 | restore target ignores the key shape | nutrition_write_service | 1 |
| B7 | migrator newest first | nlog_key_migrator | 1 |
| B8 | handler reuses ANY running save | conversational_log_handler | 1 (R6b) |
| B9 | search tap key without the slot | search_mode_body | 2 |
| B10 | scan clears only when mounted (B-pass seat A F1) | scan_meal_section | 1 |
| B11 | weight refresh unguarded (seat A F6) | conversational_log_handler | 1 |

Not mutated: the null half of the owner rule (`recorded != null && current != null`). A delete cannot run with no owner
(the user boxes are closed), so `null == null` is not reachable through the public API; the null check is kept as
defence in depth and the reachable case (signed in at delete, signed out at UNDO) is tested.

A build-time find worth its own class (debugging skill 2.152): `whenComplete(() => _inFlight.remove(id))` returned the
removed future, which is the future itself, so the first R6 run hung; a block body fixed it.

## Residuals (accepted, plan section 3)
- A second device restores two servings as ONE row with two items (one cloud row per slot); deleting that entry removes
  both servings on that device. Pinned by R9.
- OI-281 (a fully deleted meal returns from the cloud at cold start) is unchanged.
- When the cloud slot holds items this device lacks (another device logged to the same day and slot), the restore
  (`_restoreNutritionLogs`, `sync_nutrition.dart:740-775`) replaces ALL of this device's rows for that slot with ONE
  merged row of the multiset union: no item is lost, but separate entries (including occurrence rows) become one, and
  a per-row total override is re-summed from item fields. Pre-existing for any two meals in one slot (one cloud row per
  slot); B-pass seat A F3. Not reached while a single device logs.
- `meals_today` lists two equal entries (they are two servings).
- A tap after the first save completes logs again (F4).
- Legacy `nlog_<ms>` rows (testers only) are re-keyed to the hashCode shape, not v5. (A run interrupted between a put
  and its delete stays idempotent: each copy records `migrated_from`, and the next run only finishes the delete; R5.)
