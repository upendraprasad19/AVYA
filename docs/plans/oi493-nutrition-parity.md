# OI-493 Landing A: a meal logged from the coach stores and counts the same as one logged on the Nutrition screen

Branch `oi493-nutrition-parity`, base `775b99f4` (main after OI-494). Blast radius `platform` (computed per file with
`dart run scripts/blast_radius_from_diff.dart`: client files `account`, `supabase/functions/_shared/**` `platform`). Tier L
(Edge Function tool description and parser text): two plan reviews, B-pass, plan-review record. Execution mode: inline (one
session, one worktree). Diagnose doc: `docs/diagnoses/2026-11-12-coach-meal-parity-<id>.md` (full template: the
`food_name` reader is a recurrence, section 1.5). Closure ledger: `docs/audit/oi493a-coach-meal-parity.closure.yaml`.

## Revision history
- rev 1 (2026-11-12): one unit with 13 differences.
- rev 2 (2026-11-12, after plan review #1, two seats): SPLIT (§4.12.1: round 1 found 9 P1 across the two halves). This
  file is Landing A, coach-door parity. The shared-writer changes (founder decision F4 "same meal twice logs twice":
  occurrence keys, a lock, the delete/undo paths, the key-migrator fix, double-tap guards; and the zero-override fallback)
  move to Landing B, `docs/plans/oi493b-duplicate-meals.md`, on the same board, landed right after A in this session.
  Round-1 changes in A: today = the IST day the user told the coach (D2, midnight); `CoachMealLog.write` takes a callback
  for provider refresh and the tool door keeps its own invalidation (D1); the ai-proxy prompt change is gated on the
  write-claim switch so the OFF golden stays byte-identical (D4); five more `food_name` readers plus a source guard (D9);
  `_writeFoodLogFromIntent` deleted (no other caller; prelog was removed 2026-05-31); migration cited as 129 (D8);
  the tag card refuses a tag with no calories and shows the slot that will be used (D4); repointed tests listed (section 4).
- rev 3 (2026-11-12, after plan review #2, two seats; simplified rather than extended):
  - D3: `createdAt` is a UTC-flagged SERVER timestamp (`tool-loop.ts:686`), and `inferMealSlot` reads the raw hour, so the
    slot is inferred from `createdAt.toLocal()` (device-local hour, the screen's rule); without it a 13:00 IST lunch
    read as breakfast.
  - D2: the server refuses a non-today `date` in the schema (field `.refine`, the `swapWorkoutDays` precedent; a failed
    parse returns its message to the model as `invalid_args`), so no card is ever shown for it; the client check stays as
    a terminal defence. The tag door takes its day from the card's creation time, not the countdown's end.
  - D4: NO prompt change. The ai-proxy text, the write-claim rule, its golden and its size pin stay byte-identical. A tag
    the text-chat model still emits now writes the same result as the tool (and is suppressed when the tool covers it).
  - D1: no callback. `CoachMealLog.write` returns the `logMeal` result; the badge check runs in a try/catch after a
    success and can never turn a stored meal into a failure; the tag door adds only `weeklyNutritionProvider` (the one
    provider `logMeal`'s own refresh does not cover), in a try/catch.
  - D8: only the increment goes; the shared invalidation of `aiTextLogRemainingProvider` stays (harmless refresh), so
    its pin test stays green; the stale comments go.
  - D9: recent list built from `FoodItem.fromMap(item)` and relogged as stored (no rescale); names truncated to 80
    characters in the coach snapshot and the delete audit entry; the guard counts the `food_name` token in any quote
    style per file; `MealSection`'s three registry rows are removed with the file.
  - D5: the parser fibre rule lives in a pure `normaliseParsedItems` helper (no Gemini seam exists).
- rev 4 (2026-11-12, after plan review #3, two seats; no P0, one design P1, the rest build mechanics):
  - D2: the client no longer refuses a date. The server checks `date` BEFORE its multi-second parse while `createdAt` is
    stamped AFTER it, so a client comparison refused a 23:59:58 meal. The client logs on the payload `date` when present
    (server-checked), on the IST day of `createdAt` otherwise, and never on a day after `createdAt`'s.
  - D9: names cut by runes (never a lone surrogate, which jsonb rejects); recent entries skip a malformed item and relog a
    0 g item at the 100 g sentinel; the guard allowlist includes `coach_meal_log.dart`, with exact counts taken from the
    finished tree; the template default name is cut too.
  - `PendingLogAction.createdAt` is optional (defaults to `nowWall()`): two tests construct it directly.
  - Tests: `logMealByText_test.ts` already exists (EDIT, its past-date fixture becomes today);
    `food_log_notifier_to_nutrition_log_items_test.dart:188-200` added to the repoint list; bounded slices in the counter
    test; `_logFood` keeps the binding `r` and no `return true;`; residuals stated (section 5).
- rev 5 (2026-11-12, after plan review #4, convergence seat): the client IGNORES the payload `date`. Rev 4's payload-date
  path would have fed a 00:00Z instant into the slot rule (a dated lunch read as breakfast). One instant,
  `intent.createdAt`, now drives both the day and the slot; the server's check is the only date rule. Two stale D5
  sentences fixed (client refusal, NEW test file).
- rev 5.1 (2026-11-12, plan review #5: converged, no P0/P1): the P4 cross-zone sentence corrected to the per-zone table.

## 0. Founder decisions (2026-11-12, this session)
- F1. A coach meal with no slot named takes the slot from the clock, the same rule as the screen (`inferMealSlot`).
- F2. Every way of logging gives the same stored and counted result. Read here as one result shape for every coach door;
  the photo-chat door is kept because it is the only way to log a meal from a photo chat (D4).
- F3. A coach meal is logged for TODAY only (IST). Read here as the day the user told the coach (D2).
- F4. The same meal logged twice adds two entries: Landing B.

## 1. Writers and readers (§4.1; lines at 775b99f4, verified by round-1 seat A)

### 1.1 The one writer
`NutritionWriteService.logMeal` (`lib/core/services/nutrition_write_service.dart:61`): key `computeLogKey` (:82, def :961,
v5 over sorted `name|quantityG(1 dp)`, first 8 hex, :1006-1016), `box.put` (:119, overwrites), totals
`overrideTotalCals ?? sum(kcalWithFallback)` (:85), payload :95-113 (items[] carry `name`; no top-level `food_name`).

### 1.2 Coach doors
- D1, the tool (text chat, APPLY card). Server `logMealByText` (`supabase/functions/_shared/tools/nutrition/logMealByText.ts`)
  parses with `parseFoodText` (`_shared/food_parser.ts:83`; `ParsedMealItem` = name, quantity STRING, calories,
  protein_g, carbs_g, fat_g; no fibre) and sends `{date?, meal_type?, food_name, total_*, serving_description, items[]}`.
  Client `ToolDispatcher.execute` (`tool_dispatcher.dart:104`; expiry 1 h from `ToolIntent.createdAt`,
  `tool_intent.dart:136-138`; marker stamped after success, :107-131) -> `_executeLogMealByText` (:1625) ->
  `_writeFoodLogFromIntent` (:1700, its only caller is :1651) -> `logMeal`: one synthetic item (`food_name`, 100 g,
  fibre 0), `items[]` dropped, date `DateTime.tryParse('<YYYY-MM-DD>') ?? DateTime.now()` (:1712, host-local midnight),
  slot `_validateMealType` (:1743, default `snacks`), `featureAiTextLogPro` increment (:1666). After success `execute`
  calls `_invalidateNutritionProviders(ref)` (:228, def :1806) and `syncNutritionData`.
- D2, the food tag (`<ICBF_LOG>{"action":"log_food",...}`, `LogConfirmCard` auto-saves after 5 s). Taught by
  `icbfLogInstructions` (`_shared/write_claim_prompt.ts:33-52`, ai-proxy) and `mediaIcbfLogInstructions` (:60-80,
  ai-media-proxy, which has no tool loop). Parsed by `ai_coach_provider.dart:1569-1578` (card text `name — slot`, slot
  default `snacks`); suppressed when a typed intent covers it (:1518). Client `ConversationalLogHandler._logFood`
  (`conversational_log_handler.dart:90`) logs `FoodRepository.search(name).first` (a database food) or fabricated
  200/10/25/5 defaults (:228-250) via `FoodLogNotifier.logFood` (`source: manualSearch`, weekly invalidation with a
  `ref.mounted` guard :1075-1083, `BadgeService.checkAll` :1086); slot `_validateMealType` (:92, def :218).

### 1.3 Screen doors (the parity target)
- Free text: AI-text tab, `AiBreakdownNotifier.saveMeal` (`nutrition_provider.dart:935`): per-item `FoodItem`s, 100 g
  sentinel, item fibre, `overrideTotalCals: data.totalKcal`, `source: aiText`, the sheet's slot (`mealTypeProvider` =
  `inferMealSlot(DateTime.now())`, :1365, or the tapped slot).
- Search: `FoodLogNotifier.logFood` (def :1020): `date: nowWall()`, real grams, badge check.

### 1.4 Readers of the `nlog_` row
- Totals sum `total_*` (`ai_snapshot_builder.dart:795-820`, Daily/Weekly notifiers).
- Names: `NutritionReadService.deriveMealDisplayName` (`nutrition_read_service.dart:55-75`, items[].name, then meal_type).
- Readers of a top-level `food_name` that the writer never writes (all show a fallback today):
  `_getMealsToday` (`ai_snapshot_builder.dart:864`, "Unknown"), `_RecentLogs` / `_relogFromHistory`
  (`lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart:236, 263, 295`, list always empty),
  `_confirmAndDeleteLog` (`nutrition_screen.dart:642`, "this meal"), `_saveAsTemplate` (`nutrition_screen.dart:740`,
  "Saved Meal"), `deleteLog`'s `hasFoodMeta` (`nutrition_write_service.dart:518-528`, so `recent_deletes`, the coach's
  correction log, is never written), and `MealSection` (`lib/features/nutrition/widgets/meal_section.dart:76`), which has
  no caller in `lib/` (dead widget).
- Sync push `mergeNutritionLogsBySlot` (`sync_nutrition.dart:10-55`, concatenates items) and restore
  `nutritionSlotUnion` (:92, used :747, multiset): unchanged by Landing A.
- Counter readers of `featureAiTextLogPro`: `food_logger_section.dart:77-92`, `subscription_section.dart:173`.

### 1.5 History (§4.1.5)
- Obs 2 (home recent logs read `food_name`, fixed with `deriveMealDisplayName`): the six readers above are the same
  writer/reader drift the Obs 2 fix did not reach. Recurrence -> full template, debugging-skill instance count, and a
  source guard this time (D9).
- 4f9b2e / OI-494 (`istNow()` double shift): D1's date is the same family (a date turned into a DateTime in the wrong zone).
- e5c4b9 (same-slot data loss): one cloud row per slot; not changed by A.
- 0f8d54 (counters at the API-call site), acdcfb (flat rows without items[]), c9f2a7 (coach `logMealByText` live trace).

## 2. The differences and what Landing A does

| # | difference | Landing A |
|---|---|---|
| 1 | two coach doors; D2 swaps in a database food | D4 |
| 2 | D1 date is host-local midnight (previous IST day east of IST) | D2 |
| 3 | coach can log any date, incl. future | D2 |
| 4 | coach slot defaults to snacks | D3 |
| 5 | D1 writes one synthetic item, drops items[], fibre 0 | D1 + D5 |
| 6 | D2 uses database macros / fabricated defaults | D4 |
| 7 | override of 0 skips the Atwater fallback | Landing B |
| 8 | the same meal twice overwrites | Landing B (F4) |
| 9 | D1 spends the client AI-text allowance the server never charges | D8 |
| 10 | D1 skips the badge check | D1 |
| 11 | `source` not in the cloud row; double dispatch | verified_clean for `source` (no reader); the concurrent double dispatch is Landing B (it only matters once a repeat adds) |
| 12 | coach `meals_today` names every meal "Unknown" | D9 |
| 13 | APPLY card vs 5 s auto-save vs tap | none: entry UI |
| 14 | five more `food_name` readers (1.4) | D9 |

## 3. Design

### D1. One coach meal writer
New `lib/features/ai_coach/services/coach_meal_log.dart`:
```
Future<WriteResult> CoachMealLog.write({
  required DateTime at,             // the instant the meal was reported (D2); its IST day is the log day
  required String? mealType,        // the model's slot, or null (D3)
  required List<FoodItem> items,
  int? overrideTotalCals, int? overrideTotalProtein,
})
```
It resolves the slot (D3), calls `NutritionWriteService.instance.logMeal(date: at, ..., source: aiCoachTool)` and, only
when that succeeded, runs `BadgeService.instance.checkAll()` (synchronous, as in `logFood`) inside a try/catch that only
records telemetry. It returns the `logMeal` result unchanged: nothing after a successful write can turn it into a failure.
`logMeal` already refreshes the core provider batch and starts the sync (:139, :144-145).
Doors:
- Tool: `_executeLogMealByText` calls it; `execute`'s own `_invalidateNutritionProviders(ref)` (:228, which includes
  `weeklyNutritionProvider`) still runs after success, unchanged.
- Tag: `_logFood` calls it and, on success, invalidates `weeklyNutritionProvider` through its `WidgetRef` in a try/catch
  (a disposed widget cannot fail the save), the one provider `logMeal`'s refresh does not cover (`logFood`'s own comment,
  `nutrition_provider.dart:1075-1083`).
Item builders, pure and unit-tested:
- `coachItemsFromParsedMeal(Map payload)`: one `FoodItem` per `items[]` entry (`name`, `quantityG: 100.0`, `calories`,
  `protein_g`, `carbs_g`, `fat_g`, `fiber_g` or 0), the shape `AiBreakdownNotifier.saveMeal` writes; empty `items[]`: one
  item from the totals. Overrides `total_calories` / `total_protein_g`, as saveMeal passes its total, so the stored total
  equals the number the APPLY card showed (the 0-override fallback is Landing B).
- `coachItemFromTag(Map data)`: one item (`food_name`, `quantity_g` or 100, `*_estimate`, fibre 0); null when
  `calories_estimate` is missing or not a finite number >= 0.
`_writeFoodLogFromIntent` (single caller) and its stale doc comments (:1612-1624, :1688-1700) are deleted.

### D2. Today = the IST day the meal was reported (F3, midnight)
- Server (the only refusal): `logMealByText`'s `date` gains `.refine(d => d === istDateStr(), { message: "Only today's
  meals can be logged. Ask the user to add an earlier meal from the Nutrition tab." })`. A failed parse returns
  `invalid_args` with that message to the model (`tool-loop.ts:514-535`), so no intent and no card exist for it.
  Field-level `.refine` is supported by `zodToGemini.ts:51` (the `swapWorkoutDays.ts:44` precedent).
- Tool, client: the client ignores the payload `date` (the server has already checked it). One instant,
  `at = intent.createdAt` (stamped by the server after the parse, `tool-loop.ts:686`), drives both the log day (its IST
  day) and the slot (D3). Nothing is refused on the client. Residuals (stated in section 5): a meal reported in the last
  seconds before IST midnight whose parse finishes after it lands on the next day; until the `ai-proxy` deploy the live
  server still accepts a past `date`, which the client now logs today instead.
- Tag: `at` = the card's creation instant: `PendingLogAction` (`ai_coach_provider.dart:1433`) gains an optional
  `DateTime? createdAt` defaulting to `nowWall()` in the initializer (two tests construct it directly:
  `measurement_chat_path_off_identity_test.dart:94`, `log_measurement_site_whitelist_test.dart:141`), and
  `executeAction` passes it to `_logFood` (the 5 s countdown can cross midnight).
- `logMeal` shifts the instant to IST once; the host zone never enters. `logged_at`/`created_at` stay the write time
  (stated in the diagnose doc).

### D3. Slot from the clock (F1)
`resolveCoachMealSlot(String? raw, DateTime at)`: a valid slot from the model is kept; null or invalid ->
`inferMealSlot(at.toLocal())`. `.toLocal()` is required: `createdAt` is UTC-flagged and `inferMealSlot` reads
`now.hour` (`meal_slot_inference.dart:18`); the device-local hour is the screen's rule (`mealTypeProvider`). Replaces both
private `_validateMealType` copies (`tool_dispatcher.dart:1743`, `conversational_log_handler.dart:218`; no test calls
them). The tag card text (`ai_coach_provider.dart:1569-1578`) shows the same resolved slot. Server text (D5) stops
inviting `snacks`; a model that still names `snacks` is kept, since it named a slot.

### D4. The food tag writes what the tool writes (F2)
- No prompt change: ai-proxy and ai-media-proxy keep their ICBF text byte for byte (golden, size pin and the write-claim
  rule untouched). The tag stays the photo-chat door (no tools there) and a rare stray in text chat; both now write the
  tool's result, and a tag is still suppressed when a typed intent covers it (`ai_coach_provider.dart:1518`).
- Client: `_parse` drops a `log_food` tag whose `calories_estimate` is missing or unusable (returns null, as for an unusable
  water or weight tag) and records `coach_food_tag_dropped_no_calories` (`ErrorTelemetry.logEvent`, no values), so the
  rate is measurable. Residual (accepted, stated in the diagnose doc): the coach's reply may have said the meal queues;
  the prompt's own example always carries the estimate, and the old behaviour saved a database food or an invented
  200 kcal, which is worse.
- `_logFood` uses `coachItemFromTag` (no database search, no fabricated defaults) and `CoachMealLog.write`, and still
  returns the write's `success` (the pin in `coach_no_dual_log_path_test.dart:60-72`: keep `Future<bool> _logFood(`, no
  `)` inside its parameter list, the result bound to `r`, `return r.success`, no `return true;`).

### D5. Server tool and parser (Edge Function deploy needs the founder's go)
- `logMealByText.ts`: the `date` refine (D2) and describe "Only today's meals can be logged; omit it."; `mealType`
  describe "Omit unless the user named the meal; the app picks it from the time of day." The main description is
  untouched (its `MEAL_OLD_*` substrings are pinned by `write_claim_prompt_test.ts`).
- `food_parser.ts`: `ParsedMealItem.fiber_g` (prompt schema line and example). The item rules (array guard, Atwater
  recompute, fibre `Number.isFinite` and >= 0 else 0) move into a pure exported `normaliseParsedItems(raw)` that
  `parseFoodText` calls; there is no Gemini seam, so the helper is what the test covers.
- Deno tests: EDIT the existing `_shared/tools/__tests__/logMealByText_test.ts` (see section 4), NEW
  `_shared/food_parser_test.ts` (`normaliseParsedItems`: fibre kept,
  missing/NaN/negative -> 0, Atwater recompute unchanged). `deno check --node-modules-dir=none` on ai-proxy (and
  ai-media-proxy, which imports nothing changed).
- Compatibility: old client + new server (extra `fiber_g` ignored; a non-today date never reaches it); new client + old
  server (null slot -> inferred, a payload date ignored and the meal logged on `createdAt`'s day, no `fiber_g` -> 0). Deploy `ai-proxy` after the
  merge, from main, per the deploy-rollback skill (ai-media-proxy's bundle is unchanged, no deploy).

### D8. No AI-text allowance for a coach meal
Remove the `featureAiTextLogPro` increment (`tool_dispatcher.dart:1666-1668`) and the imports it alone used (unused-import
sweep of `tool_dispatcher.dart` and `conversational_log_handler.dart`; whole-project analyze must stay at 0 warnings). The
shared `_invalidateNutritionProviders` keeps its `aiTextLogRemainingProvider` refresh (harmless; its pin test
`coach_meal_log_invalidates_remaining_test.dart` stays green); its comment that the coach path increments is corrected.
Why: the server's food-text cap (live definition migration 129, `consume_quota` on usage key `food_text`; 127 sets the
free cap; 153 maps `food_text_analysis` to `food_text`) fires only for `ai_coach_interactions` rows with channel
`food_text_analysis`; `parseFoodText` writes no such row, so the client counter (read by `food_logger_section.dart`
and `lib/features/profile/screens/profile/subscription_section.dart:172`) drifted below the server's. Residual
(accepted): the tool's Gemini parse is bounded only by the chat cap. Live confirmation of the cap rows: a read-only query
at build time (tier 4 of the diagnose doc). Update the counter rows in `lib/core/services/CLAUDE.md` and
`lib/features/nutrition/CLAUDE.md` (also its stale "migration 127" and `hashCode` key text).

### D9. Every reader takes the name from items
- `_getMealsToday`, `_confirmAndDeleteLog`, `_saveAsTemplate`: `NutritionReadService.deriveMealDisplayName(...)`; in the
  coach snapshot, the delete audit entry and the template default name it is cut to 80 runes
  (`String.fromCharCodes(name.runes.take(80))`: never a lone surrogate, which jsonb rejects; a Devanagari cluster can
  still be split at the cut, accepted).
- `deleteLog` `hasFoodMeta`: `meal_type` plus a non-empty `items[]` (or the legacy `food_name`/`name`); the audit entry's
  `food_name` is the derived, cut name (its one reader, `_getRecentMealDeletes`, passes it through).
- `_RecentLogs`: entries are `FoodItem.fromMap(item)` for each item of the last 14 days' rows (newest first, dedup by
  lowercased name, top 8); an item that throws in `fromMap` or has an empty name is skipped (one bad item never blanks
  the list); legacy flat rows without `items[]` contribute nothing (stated). `_relogFromHistory` relogs that `FoodItem` as
  stored (name, grams, macros, fibre; no rescale), with a 0 g item relogged at the 100 g sentinel, so a coach item and a
  real-grams screen item each relog as first written.
- `MealSection`: delete the file (no caller in `lib/`, `test/` or `scripts/`) and its three registry rows
  (`docs/sot_registry.yaml:712-714`, `:2028-2030`, `:9048`).
- Guard `test/contracts/nlog_food_name_reader_guard_test.dart`: counts the `food_name` token in any quote style in every
  `lib/**/*.dart` (comments stripped, the OI-494 scanner) per file against an allowlist of file -> count with a reason
  each (tag and tool payloads: `ai_coach_provider.dart`, `conversational_log_handler.dart`, `tool_dispatcher.dart`,
  `tool_confirm_card.dart`, and the new `coach_meal_log.dart`; cloud and item mappers: `sync_nutrition.dart`,
  `sync_service.dart`; the audit entry and its legacy fallback in `nutrition_write_service.dart`). Counts are EXACT and
  taken from the finished tree: a new token anywhere, an extra one in an allowed file, or a dropped allowed reader reds it.
  Mutants: a double-quoted read and a `const k = 'food_name'` read both red.

### D10. Docs and registry
SoT registry `nutrition_total_calories` / `hive_field_name_nlog`: add `coach_meal_log.dart` as a writer path and the new
readers, remove the three `meal_section.dart` rows, recompute every `line_range` citing a touched file from method bounds. Nested CLAUDE.md: ai_coach (coach meal
path, tag behaviour, `_logFood` doc), nutrition (counter list, stale `hashCode` key text), core/services (counter list),
supabase/functions (`food_text` live migration 129). Debugging skill: the `food_name`
reader instances. Closure ledger rows for every item in section 2, A's rows terminal (`closed_in_commit` or
`verified_clean`), 7, 8 and 11's double dispatch `closed_in_commit` by Landing B's commit (the ledger lands with B).

## 4. Tests (each mutated once, rule 21; run under TZ=Asia/Kolkata, UTC and Asia/Tokyo)
New `test/contracts/coach_vs_screen_meal_log_parity_test.dart` (real Hive, clock seam). Intents are built with
`createdAt: DateTime.parse('<...>Z')` exactly as `ToolIntent.fromJson` does:
- P1 date: an intent created at 01:00 IST (19:30Z the day before), host TZ=Asia/Tokyo, no date: today's IST key (red on main).
- P2 midnight: intent created 23:55 IST, applied at 00:05 IST (clock seam): logged on the creation day.
- P3 dates: a payload date of yesterday, tomorrow or a malformed string is ignored: the meal logs on `createdAt`'s IST
  day (mutant: read the payload date -> red).
- P4 slot: no meal_type, `createdAt` 07:30Z: lunch under TZ=Asia/Kolkata (13:00 local), and equal to
  `inferMealSlot(createdAt.toLocal())` in every zone (mutant: drop `.toLocal()` -> red under Kolkata); under
  TZ=Asia/Tokyo the tool door and the screen's rule give the same (IST day, slot) pair for one instant; a named slot is
  kept; a payload date (today, another day, malformed) never changes the result: the (IST day, slot) pair for one
  `createdAt` is the same with and without it. Expected for `createdAt` 2026-11-12T07:30:00Z (IST day 2026-11-12 in every
  zone): TZ=Asia/Kolkata 13:00 -> lunch; TZ=Asia/Tokyo 16:30 -> snacks; TZ=UTC 07:30 -> breakfast. The tag card text
  shows the slot that is written.
- P5 items: a two-item parsed meal writes two items with fibre, equal in shape to `saveMeal` given the same items; empty
  items -> one item from the totals.
- P6 tag: the tag's own name and calories are written (no database food); a tag without calories yields no
  `PendingLogAction` and one `coach_food_tag_dropped_no_calories` event; a card created at 23:59:58 IST that saves after
  midnight logs on the earlier day.
- P7 counter: a tool log leaves `featureAiTextLogPro` unchanged.
- P8 badges: both doors run the badge check once; a badge check that throws still returns success with the meal stored.
- P9 readers: for a row written by `logMeal`, `meals_today`, the delete confirmation title, the template default name,
  the recent list and the `recent_deletes` entry show the item names; a 12-item row's snapshot name is <= 80 runes and
  a cut through an emoji at rune 79/80 leaves no lone surrogate; relogging a recent item writes the same name, grams and
  macros (one sentinel item, one real-grams item, one 0 g item); a malformed item is skipped, the rest of the list shows.
- P10 guard (D9 mutants).
Deno: EDIT the existing `_shared/tools/__tests__/logMealByText_test.ts` (its :15-22 fixture `date: "2026-04-20"` becomes
`istDateStr()`; add yesterday/tomorrow refused with the message, absent accepted, the two describe strings; keep its other
tests); NEW `_shared/food_parser_test.ts`; `write_claim_prompt_test.ts` stays green untouched (no prompt change).
Repoint (file:line at 775b99f4): `test/ai_coach/meals_today_snapshot_test.dart:37-124` and
`test/contracts/ai_snapshot_building_behavioral_test.dart` (~45-135) (fixtures carry a top-level `food_name`; rewrite to
the real writer shape), `test/features/nutrition/counter_increment_on_analyse_test.dart:170-200` (now asserts NO
increment in `_executeLogMealByText`, sliced to the method's own end with `indexOf('\n  }\n', idx)`, never a fixed
2000-char window) and `:255-281` (the method is deleted: repoint to `coach_meal_log.dart` `coachItemsFromParsedMeal`,
`quantityG: 100.0` and not `quantityG: 0`), `test/contracts/food_log_notifier_to_nutrition_log_items_test.dart:188-200`
(asserts the handler calls `.logFood(`: now `_logFood` calls `CoachMealLog.write(` and no `FoodRepository`),
`test/contracts/coach_no_dual_log_path_test.dart:60-72` (keep matching), `test/features/ai_coach/coach_single_confirm_per_log_intent_test.dart:63`
(its tag fixture has no `calories_estimate`: add one, keep its dedup assertions, and prove the unsuppressed case yields
exactly one food action so the suppression test cannot pass vacuously). Read before the build:
`nutrition_recent_logs_name_behavioral_test.dart`, `nutrition_recent_logs_name_test.dart`, `food_log_id_and_name_test.dart`,
`closeout_snapshot_keys_test.dart`. Must stay green: `nlog_key_canonical_test.dart`, `scripts/check_nlog_key_canonical.dart`,
`coach_meal_log_invalidates_remaining_test.dart`.

## 5. Not in scope of A, and accepted residuals
- Landing B: F4 duplicate entries, the zero-override fallback, concurrent dispatch.
- Entry-UI differences (APPLY vs 5 s auto-save).
- Cloud `source` column (no reader).
- `inferMealSlot` reading device-local hour: the screen's rule.
- A tag in one turn and the tool in a later turn for the same meal log it twice (different names/grams, different keys);
  unchanged from today and, with Landing B, the intended "logged twice" behaviour.
- A calorie-less tag is dropped with `coach_food_tag_dropped_no_calories`; reopen when that event appears in tester data
  (closure ledger `reopen_when`).
- Until the `ai-proxy` deploy, the live server still accepts a past date; the client logs such a meal today (D2).
- A meal reported in the last seconds before IST midnight, parsed after it, lands on the next day (D2).

## 6. Open after the merge
- Edge Function deploy of `ai-proxy` (founder go).
- Device check after the next founder-started build: a coach meal at lunchtime with no slot lands under Lunch with its
  items and fibre; the coach can name today's meals; deleting a meal tells the coach its name.
