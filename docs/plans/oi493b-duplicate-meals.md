# OI-493 Landing B: the same meal logged twice adds two entries (rev 2.1)

Split from `docs/plans/oi493-nutrition-parity.md` (§4.12.1); Landing A merged 2026-11-12 (PR #251, `e1becc8d`).
Founder decision F4 (2026-11-12): "if we are logging same meal twice it should log twice", for the coach and the
screen. Worktree `oi493b-duplicate-meals` from main `e1becc8d`. Execution mode: inline (one worktree, one writer).
Blast radius `account` (shared writer `nutrition_write_service.dart`, the migrator) plus `ai_coach` (M tier by path).
Writes the closure ledger `docs/audit/oi493-nutrition-parity.closure.yaml` (Landing A's rows + B's); OI-493 stays OPEN until the `ai-proxy` deploy and the device check.

## 0. The bug, writers and readers (lines at `e1becc8d`)

**Symptom.** Logging the same meal again (same day, same slot, same item names and grams) replaces the first entry
instead of adding a second: the day's calories count it once.

**Writer.** `NutritionWriteService.logMeal` (`lib/core/services/nutrition_write_service.dart:66`) computes
`key = computeLogKey(date, mealType, items)` (:87; def :977, `nlog_<IST date>_<slot>_<8 hex of v5 over sorted
name|grams>`) and `box.put(key, payload)` (:124), which OVERWRITES a row already at that key. No `await` sits between
:87 and :124 (checked); Hive 2.2.3 `BoxImpl._writeFrames` inserts into the keystore synchronously
(`keystore.beginTransaction`, before `await backend.writeFrames`), so a key chosen and put with no `await` between is
atomic on the one isolate.

**Other writers of an `nlog_` key** (all put to a key without checking it is free):
- `moveMealLog` (:381): recomputes the key in the new slot; on a collision MERGES the moved items into the
  destination row (:420-441), then `put(newKey)` + `delete(logKey)` (:468-470).
- `restoreLastDeleted` (:589-596) and `restoreFoodLog` (:881-887): put the stashed row back under its old key.
- `appendItemsToMeal` (:248) and `editLog` (:303): rewrite the same key (unchanged by B).
- Restore `_restoreNutritionLogs` (`lib/core/services/sync/sync_nutrition.dart:609`, merge loop :683-760): ONE local row
  per (date, slot) when the cloud has items the device lacks (multiset union `nutritionSlotUnion`, deletes the slot's
  other keys); skips when the local slot is a multiset superset (`nutritionLocalSlotIsSuperset`).
- `NlogKeyMigrator.runIfNeeded` (`lib/core/services/nlog_key_migrator.dart:22`, gated once per device by
  `configBox['nlog_key_migration_v7']`, called after a restore from `restoring_screen.dart:431` and
  `heal_after_restore.dart:24`): regroups EVERY `nlog_` row by `_computeLogKey` = hashCode over `quantityG` (a key the
  writer never writes, so every grams value reads 0.0) on the UTC date of `logged_at`, and keeps ONLY the latest row per
  group (:58-87). On a device that has not run v7 (a fresh install, after its first restore) two servings would collapse.

**Callers that can now add twice on a repeat or a race** (today a repeat overwrote the same key, so it was harmless):
- Screen: search result tap (`search_mode_body.dart:204` -> `FoodLogNotifier.logFood`), recent list tap
  (`_relogFromHistory`, :334), barcode `_logFood` (`barcode_scan_sheet.dart:166`), saved-meal relog
  (`saved_meals_section.dart:216` and :225). Already guarded: AI-text save (`lib/features/nutrition/widgets/ai_breakdown_card.dart`
  `_saving`), scan save (`scan_meal_section.dart` `_saving`), but both flags are widget `State`, so a card unmounted and
  remounted mid-save gets a fresh `false` (round 1): they move to the shared guard (B7). The saved-meal sheet pops its
  route before the relog (`saved_meals_section.dart:206-207`), so it has no double-tap window (left unchanged). The dev
  simulation (`simulation_service.dart:558`) clears its `nlog_` rows first and logs each slot once per day (unaffected).
- Coach tool: NOT a double-write path (round 1, verified): `PendingToolIntentsNotifier.confirm`
  (`pending_tool_intents_provider.dart:66-79`) checks `isActionable` (pending or failed, `tool_intent.dart:141`) and
  sets `executing` before its first `await`; `retry` is `confirm`; the only auto-run intent is `request_completion_tile`
  (`tool_intent.dart:46`). A second APPLY or retry of one intent is refused ("Already handled.").
- Coach tag: `LogConfirmCard._execute` (`log_confirm_card.dart:55-72`): `_isExecuting` is widget state, and
  `markLogged` runs only `if (success && mounted)`, so a card unmounted during the save (chat scrolled, rebuilt) and
  mounted again restarts its 5 s countdown and saves again.

**Readers.** Every `nlog_` reader walks rows by key prefix and sums `total_*` (`NutritionReadService.totalMacrosForDate`,
`DailyNutritionNotifier`, `TodaysMealsCard`, `_getMealsToday`, weekly notifiers); none parses the key's shape (grep
`RegExp(r'nlog_` / `split('_')` in lib/: none). A second row is a second entry everywhere.

**Cloud.** One `nutrition_logs` row per (user, date, meal_type): the push `mergeNutritionLogsBySlot`
(`sync_nutrition.dart:10-55`) concatenates the slot's rows' items, and the item vacuum `.gte('item_index',
items.length)` trims items a delete removed. A second serving reaches the cloud as a second item.

**History (§4.1.5).** e5c4b9 (same-slot data loss, the NUT-02 slot merge), the Hermes P1 that made the restore union a
multiset ("a food logged twice stays twice", `sync_nutrition.dart:57-90`), H-17 (hashCode -> v5 keys, the v7 migrator).
Not a recurrence of a fixed bug: the overwrite was the design; F4 changes it. OI-281 (a fully deleted meal comes back
from the cloud) is unchanged by B and stays open.

## 1. Design

One anchored key shape is used everywhere (round 1, A1: about 2.3% of 8-hex hashes are all digits, so a bare `_\d+$`
strip would cut a hash): `kNlogKeyShape = ^(nlog_\d{4}-\d{2}-\d{2}_[a-z]+_[0-9a-f]{8})(_\d+)?$`, declared once in
`nutrition_write_service.dart` (allowlisted by `check_nlog_key_canonical.dart`). `baseLogKey(k)` returns group 1 when
`k` matches, else `k`. `firstFreeLogKey(bool Function(String) taken, String base)` returns `base` when free, else the
first free `base_2`, `base_3`, ...

### B1. A repeat adds an entry (logMeal)
`logMeal` computes `base = computeLogKey(...)` and chooses `key = firstFreeLogKey(box.containsKey, base)` INSIDE the
existing `try` that holds `box.put` (`HiveService.instance.nutritionBox` can throw, `guarded_box.dart:170`; round 1, B5),
with no `await` between the choice and the put, so two un-awaited `logMeal` calls with equal input write two rows. `id`
/ `log_key` in the payload carry the chosen key; `WriteResult.logKey` returns it.

### B2. UNDO never overwrites, never restores the wrong row, never crosses accounts
- `restoreLastDeleted({required String expectedKey})`: restores only when the stash's key equals `expectedKey` (the
  snackbar at `nutrition_screen.dart:729` passes the key it deleted). After two deletes in a row the first snackbar's
  UNDO is a no-op (`WriteResult.fail('nothing to restore')`) instead of restoring the second row (round 1, B4).
- Owner binding for BOTH UNDO paths (round 1 B4, round 2 F3/F4): `deleteLog` records
  `HiveUserSession.currentOwnerHash` for the deleted key in a small bounded map (last 16 keys; also when
  `allowUndo: false`, because the food-log snackbar at `nutrition_screen.dart:897` deletes that way and restores the
  screen's own copy through `restoreFoodLog`). `restoreLastDeleted` and `restoreFoodLog` refuse (and drop the record /
  stash) when the recorded or the current hash is null, or when they differ. A sign-out and the same user back gives
  the same hash, so UNDO still works.
- Both `restoreLastDeleted` and `restoreFoodLog` restore under `firstFreeLogKey(box.containsKey, baseLogKey(key))` when
  the stashed key is taken (the same meal was logged again inside the UNDO window), on a COPY of the payload with `id` /
  `log_key` rewritten; a free stashed key is reused as today. `restoreFoodLog` never mutates the caller's map.

### B3. Move keeps two entries apart
`moveMealLog`: the destination is `firstFreeLogKey(box.containsKey, <new slot's base key>)`; the collision MERGE
(:420-441) is removed (it existed so an overwrite would not lose items; a merge would now turn two entries into one).
`macroUpdates` and the post-recompute clamp apply to the moved row as today.

### B4. The migrator stops collapsing and leaves current-shape rows alone
`NlogKeyMigrator`:
- a row whose key matches `kNlogKeyShape` is skipped (neither regrouped nor rewritten): restored v5 rows keep their key
  and their IST day (today they are re-keyed to a hashCode key on the UTC day of `logged_at`, round 1 A4);
- legacy rows (`nlog_<ms>`, `nlog_<uuid>`) are still re-keyed, but each row keeps its own entry: a group of N rows takes
  `firstFreeLogKey(box.containsKey, ...)` occurrences of its computed key, read against the live box after each put,
  instead of collapsing to the latest (round 1 B6, round 2 F6);
- the class comment is corrected: the migrator's key is `String.hashCode` over `quantityG` (a key `FoodItem.toMap`
  never writes, `quantity_g`), not the writer's v5 key. Legacy keys stay that shape (testers only; no reader parses
  the key).
Same flag (`v7`) and gate; a device that already ran v7 is unchanged.

### B5. Coach tool: no change
Dropped in round 1 (B3): `confirm` already refuses a second APPLY or retry of an intent while it executes (section 0).
The dispatcher marker still answers a replay after completion.

### B6. One tag card, one write
- `ConversationalLogHandler.executeAction`: a STATIC in-flight map `action id -> Future<bool>` (the handler is built
  fresh per call, `log_confirm_card.dart:59`, round 1 B2); a second call for the same id while the first runs returns
  the same future (the same bool; round 1 A7); the entry is removed in `finally`.
- `LogConfirmCard._execute`: the `pendingLogActionsProvider` notifier (a non-autoDispose `NotifierProvider`,
  `ai_coach_provider.dart:1694`) is captured BEFORE the await; on success `markLogged` runs whether or not the card is
  still mounted (it sets `isLogged` on the shared action object, so a remounted card's `_onAutoConfirm` stops), then
  `removeSettled` after the 1.5 s "Logged" state when mounted, or at once when not (so an unmounted card's action is
  cleared, round 1 B2).

### B7. One tap, one entry (screen)
`lib/core/utils/single_flight.dart`: `SingleFlight.run<T>(String key, Future<T> Function() op) -> Future<T?>`; a static
set of in-flight keys; returns null without calling `op` while `key` is in flight; releases in `finally`. Keys are the
write identity, so two different foods never block each other (round 1, B1):
- search result tap: `search|<food id, else name>|<grams>|<slot>`;
- recent tap (`_relogFromHistory`): `recent|<name>|<grams>|<slot>`;
- barcode `_logFood`: `barcode|<name>|<grams>|<slot>`;
- AI-text save: inside `AiBreakdownNotifier.saveMeal`, key `aitext`, so the guard survives a card remount (round 1, A5);
  a null run returns a new `WriteResult.inFlight()` (`isInFlight`), which the card shows as a neutral "Saving meal…"
  (card colour, no haptic) and resets its `_saving` (round 2 F2: "Already saved." would be false if the first save
  then fails);
- scan save (`scan_meal_section.dart` `_save`): key `scan`; the flight is taken BEFORE `_saving` is set (the op sets
  it), so a null run leaves the button usable (round 2 F1).
A null result shows no toast, no haptic and does not call `onLogged` (round 1, B1). A tap after the first save finishes
logs again (F4). The search tap keeps no `.success` read within 200 characters after `.logFood(` (pin
`food_log_notifier_to_nutrition_log_items_test.dart` about :160-185; round 1, A3).

### B8. A zero override falls back to the items
`logMeal`: `overrideTotalCals` / `overrideTotalProtein` apply only when > 0; a 0 (or absent) total is the items' sum, so
a meal whose AI total came back 0 but whose items carry calories is not stored as 0 kcal. A meal whose items are all 0
stays 0. Callers that pass an override: `AiBreakdownNotifier.saveMeal` (`totalKcal`), `scan_meal_section.dart:447`, the
coach tool (`total_calories` / `total_protein_g`, which default a missing total to 0,
`lib/features/ai_coach/services/tool_dispatcher.dart:1637-1638`).
Intended consequence (round 1, B7): a scan total the user edits to 0 is stored as the items' sum.

### B9. Totals vs items: kept
A positive override can differ from the item sum (the AI's total is what the user confirmed); `editLog` recomputes from
items when items change (unchanged). Documented, no change.

## 2. Tests (each new test mutated once, rule 21; run under TZ=Asia/Kolkata and UTC)
New `test/contracts/nlog_repeat_adds_entry_behavioral_test.dart` (real Hive, `nws_test_setup` + shared boxes):
- R1 the same meal logged twice -> two rows, `base` and `base_2`, totals counted twice
  (`NutritionReadService.totalMacrosForDate`); a third -> `base_3`. Mutant: `put(base)` -> one row.
- R2 two un-awaited `logMeal` calls with equal input -> two rows. Mutant: an `await Future.delayed(Duration.zero)`
  between the key choice and the put -> one row.
- R3 UNDO: delete `base`, log again (takes `base`), UNDO -> both rows (UNDO lands on `base_2`), via `restoreLastDeleted`
  and via `restoreFoodLog` (the caller's map unchanged); UNDO with the key free reuses it; two deletes then the first
  snackbar's UNDO -> no row restored; an owner change, or a null owner, between delete and UNDO -> nothing restored
  on either path, stash cleared.
- R3b key shape: `baseLogKey` of `..._12345678_2` is `..._12345678`; `..._12345678` stays itself; a non-matching key
  stays itself. Mutant: the regex to `_\d+$`.
- R4 move an occurrence row into a slot holding the same meal -> `dest` and `dest_2`, no source row.
- R5 migrator on a fresh flag: two current-shape occurrence rows and one restored v5 row whose `logged_at` UTC day
  differs from its IST day are untouched; two equal legacy `nlog_<ms>` rows become two rows; the flag is set.
- R6 coach tag: two `executeAction` of one action with the first pending -> one row, both get `true`; a widget test
  (captured `WidgetRef`) in which the card is unmounted during its save and a new card for the same action mounts ->
  one row, the action is `isLogged` and removed from `pendingLogActionsProvider`.
- R7 `SingleFlight`: a second `run` with the same key while the first is pending returns null and does not call the op;
  a different key runs; after completion it runs again; a throwing op releases the key. `saveMeal` called twice
  un-awaited -> one row, second result `isInFlight`; a scan save's null run leaves `_saving` false. Source pins that the search, recent, barcode and scan sites call
  `SingleFlight.run` with the identity key.
- R8 zero override: items 300 kcal + override 0 -> 300; items all 0 + override 0 -> 0; override 450 -> 450; protein
  override 0 with items carrying 20 g -> 20.
- R9 restore on a second device (cloud row with two equal items) -> one row with two items, 2x calories (the accepted
  residual, pinned).
Repoint: `test/contracts/nutrition_log_retag_writer_to_reader_test.dart` (the whole file read; at least the union test
~:120-170 -> two rows `dest` / `dest_2`; the "clamps the POST-merge total" test ~:172-215 -> a clamp on the single moved
row via `macroUpdates`, so the FC6 clamp-after-recompute coverage stays; the macroUpdates-on-collision test ~:217-300 ->
against the moved occurrence row); `restoreLastDeleted` callers take `expectedKey`:
`test/contracts/food_log_delete_with_undo_behavioral_test.dart` (:69, :98, :144),
`test/nutrition_write_service/deleteLog_with_undo_test.dart` (:43, :69), `nutrition_screen.dart:729`, and the comment at
`nutrition_provider.dart:1104`; the source pin in
`food_log_notifier_to_nutrition_log_items_test.dart` stays green. `nlog_key_canonical_test.dart` /
`check_nlog_key_canonical.dart` stay green.

## 3. Residuals (accepted)
- A second device restores two servings as ONE row with two items (one cloud row per slot); deleting that entry
  removes both servings on that device. Pinned by R9.
- OI-281 (a fully deleted meal returns from the cloud at cold start) is unchanged.
- When the cloud slot holds items this device lacks (another device logged to the same day and slot), the restore
  (`_restoreNutritionLogs`, `sync_nutrition.dart:740-775`) replaces ALL of this device's rows for that slot with ONE
  merged row of the multiset union: no item is lost, but separate entries (including occurrence rows) become one, and
  a per-row total override is re-summed from item fields. Pre-existing for any two meals in one slot (one cloud row per
  slot); B-pass seat A F3. Not reached while a single device logs.
- `meals_today` lists two equal entries (they are two servings).
- A tap after the first save completes logs again: that is F4, not a double tap.
- Legacy `nlog_<ms>` rows (testers only) are re-keyed to the hashCode shape, not v5.
