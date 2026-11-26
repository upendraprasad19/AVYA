# OI-348 Landing 3b — coach meals: one row per food, saved only on a tap (B4 + P5)

Status: revised after plan review rounds 1 (10 findings, 7 P2) and 2 (12 findings, 6 P2); no P0/P1 in either; all folded in (logs at the end). Round 3 (a check of the round-2 folds) found 2 P2 + 3 P3 plan-text defects, folded below; no code-shape change. Converged. Branch `oi348-landing3b` off main `238bb44f` (2026-11-26).
Blast radius: **platform** expected (ai-proxy / ai-media-proxy prompt + `lib/features/ai_coach/**`); confirm with `blast_radius_from_diff.dart` on the draft. Tier **L** (EF prompt): full ×2 plan review, gate loop + CI before each review, B-pass before merge, plan-review record.
Execution mode (decided at start, §4.12.7): **inline**, one worktree, one coordinator.

Founder decisions:
- P5 (locked 2026-11-22, "all 5 recommendations are fine"): coach meals show a per-item macro card, save only on APPLY, no 5 s auto-save for food.
- "Start 3b" (2026-11-26). The photo-path question was put to the founder and left open; this plan takes the default that completes P5 for every coach door (photo meals get the same card and the same tap), stated here so a reviewer or the founder can overrule it.
- The ai-proxy / ai-media-proxy redeploy after the merge is its own founder go (§4.3).

---

## 1. Symptom (walk A18, Chintamani, AAB +50, 2026-11-22 16:52Z)
"2 rotis and dal" told to the coach was saved as ONE item `roti and dal`, 200 g, 280 kcal, slot lunch, by a card that saved itself after 5 s. The same food logged on the Nutrition screen 90 s later: Roti 100 g 210 kcal + Dal 100 g 150 kcal = 360 kcal (that row is the "snacks" one; the walk note had the slots reversed).

## 2. Root cause (verified 2026-11-26 against main 238bb44f)
- The model answered with the legacy `log_food` TAG, not the `logMealByText` tool, and copied the tag protocol's only food example: `write_claim_prompt.ts:41` (ai-proxy) and `:69` (ai-media-proxy), `{"food_name":"Dal Rice","meal_type":"lunch","quantity_g":200,"calories_estimate":280,...}`. 200 g / 280 kcal / lunch are the example's numbers.
- A tag holds ONE food: `coachItemFromTag` `coach_meal_log.dart:131-146` -> one `FoodItem`; `_logFood` `conversational_log_handler.dart:130-149` writes `[item]`.
- The tag card saves on its own: `LogConfirmCard.initState` `log_confirm_card.dart:32-38` starts a 5 s `AnimationController` whose completion calls `_execute`.
- The typed tool is already the good path (second Gemini parse, per-item rows with fibre, waits for APPLY: `tool_dispatcher.dart:1810-1846`, `coachItemsFromParsedMeal` `coach_meal_log.dart:92-126`), but its card shows only the totals: `ToolConfirmCard._buildSummary` `tool_confirm_card.dart:315-325` (`food_name — N kcal · Pg protein`).

## 3. Writers / readers
| Role | file:line |
|---|---|
| Prompt writer (tag protocol, ai-proxy) | `_shared/write_claim_prompt.ts:35-57` `icbfLogInstructions`, called `ai-proxy/index.ts:1094` |
| Prompt writer (tag protocol, media) | `write_claim_prompt.ts:64-83` `mediaIcbfLogInstructions`, called `ai-media-proxy/index.ts:750` |
| Prompt writer (queued wording) | `WRITE_CLAIM_RULE` `:86-91`, `MEDIA_WRITE_CLAIM_RULE` `:94-99`, via `writeClaimSuffix` `:105-111` (ai-proxy `:1205`, media `:750`) |
| Tag extractor | `extractLogActions` `ai-proxy/index.ts:211-230` (malformed JSON skipped silently), media twin `ai-media-proxy/index.ts:181` |
| Client tag reader | `PendingLogActionsNotifier._parse` `ai_coach_provider.dart:1719` (`log_food` case `:1747-1766`), dedup `:1696-1698` (`foodCovered` drops a tag when the tool intent is in the same reply) |
| Log-only reader | `_shared/write_claim_detector.ts:99-105` `LEGACY_AUTO` (counts `log_food` as an auto-saving tag) |
| Tag card (auto-save) | `log_confirm_card.dart:32-38` timer, `:55-82` `_execute` |
| Tag writer | `ConversationalLogHandler._logFood` `conversational_log_handler.dart:130-149` -> `CoachMealLog.write` `coach_meal_log.dart:33-66` |
| Tool card | `ToolConfirmCard._buildSummary` `tool_confirm_card.dart:315-325` |
| Tool writer | `_executeLogMealByText` `tool_dispatcher.dart:1810-1846` (`overrideTotalCals` = payload total, same as the screen's `saveMeal`, which also overrides; `logMeal` applies an override only when > 0) |
| Store | `NutritionWriteService.logMeal` (unchanged) -> `nlog_` rows, `nutrition_logs` / `nutrition_log_items` |

## 4. Bug history (§4.1.5)
- ec6f6c (2026-11-12, OI-493 Landing A): made both coach doors write through `CoachMealLog.write`; the tag kept ONE item (`coachItemFromTag`) and its 5 s card; "No prompt change" was a stated choice. This landing finishes what A left: the tag's example and the card. Same class (coach door drifts from the screen door), new shape (the prompt's own example becomes the data). Not a regression of A's fix.
- a1d7c3 (2026-07-03): one confirm affordance per log (`coveredLegacyLogKinds`, `disable_coach_log_dedup`). Kept; this plan does not touch the dedup.
- 90a784 (2026-10-21, OI-368/369): write-claim wording + golden pin. This plan edits the same strings; OFF stays byte-identical to that golden.
- 4cb58f / Landing B: one tag, one write (`_inFlight`, `SingleFlight`). Kept.
- Recurrence: YES of the class "two coach doors drift from the reference door" (debugging skill class 2.151); the diagnose doc cites ec6f6c and a1d7c3.

## 5. Fix

### 5.1 Server (ai-proxy + ai-media-proxy), behind kill switch `DISABLE_COACH_MEAL_ITEMS_RULE`
Exactly `"true"` disables (reader `isCoachMealItemsRuleDisabled(get)` in `write_claim_prompt.ts`, the `isWriteClaimRuleDisabled` shape), read ONCE per request in each handler next to `ruleOn`, passed down. OFF = every builder output byte-identical to main 238bb44f (new golden `_shared/testdata/icbf_blocks_pre_meal_items.json`, captured from main BEFORE any edit by a scratch script; command and sha in the diagnose doc). The size log line gains `meal_items_rule=<bool>`.

The ON text is built by `.replace` of named exact substrings exported as constants (the `MEAL_OLD_CARD` pattern), each asserted present by a test (R2-5: the ICBF-block constants in both the write-claim ON and OFF block texts; the three suffix constants in `WRITE_CLAIM_RULE` and `MEDIA_WRITE_CLAIM_RULE`, since `writeClaimSuffix(false)` is `""`, so write-claim OFF + meal ON has an empty suffix), so a later edit of the base text fails loudly instead of silently skipping a replacement. The `log_food` line differs per builder (R1-4: a template-literal line ending `\n` in `icbfLogInstructions` `:41`, a `'\n<ICBF_LOG>…'` concatenation in the media builder `:69`), so it gets TWO constants, `AI_FOOD_TAG_LINE` and `MEDIA_FOOD_TAG_LINE`, each including its newline.
- **ai-proxy ICBF block** (`icbfLogInstructions(enabled, { mealItems })`):
  - drop the `log_food` example line (`AI_FOOD_TAG_LINE`);
  - `(I drank, I weighed, I ate, I slept, my waist is)` -> `(I drank, I weighed, I slept, my waist is)`;
  - after `- One tag per response maximum.` add `- Food the user ate is never a tag: call logMealByText with the user's own words, every food and amount they named.`
  - Channel check (R1-7): the ICBF block is pushed on every request that reaches the prompt build (`ai-proxy/index.ts:1094`), but every non-chat `type` (food_text_analysis, scan_meal, cart_auditor, prediction) returns earlier (`:382`, `:616`, `:715`, `:761`, `:809`; the comment at `:1003-1007`), and `runToolLoop` (`:1251`) offers `logMealByText` (`tier: "free"`, `logMealByText.ts:38`) to every caller. So "call logMealByText" is always backed by an offered tool.
  - Accepted behaviour, stated (R1-7): when the tool's parse fails (the second Gemini call), there is no tag to fall back on; the tool loop reports the failure to the model, and the write-claim rule already says "If the user asked you to log something and you proposed nothing … say what you still need". The coach then asks again or points to the Nutrition tab. A tag fallback is what produced the copied example, so it is not kept.
- **media ICBF block** (`mediaIcbfLogInstructions(enabled, { mealItems })`): the media proxy offers no tools, so the tag stays the only meal door. Replace `MEDIA_FOOD_TAG_LINE` with this exact two-food example (R1-3: it carries every flat key today's client reads, so a +50 build and the client's "items unusable" fallback still get a card):
  `<ICBF_LOG>{"action":"log_food","data":{"food_name":"Idli and Sambar","quantity_g":270,"calories_estimate":270,"protein_estimate":10,"carbs_estimate":50,"fat_estimate":4,"items":[{"name":"Idli","quantity_g":120,"calories":160,"protein_g":5,"carbs_g":34,"fat_g":1},{"name":"Sambar","quantity_g":150,"calories":110,"protein_g":5,"carbs_g":16,"fat_g":3}]}}</ICBF_LOG>`
  (totals are the item sums; no `meal_type`; the media block KEEPS "I ate" in its RULES line on purpose: its tag is still the only meal door, R2-5). Accepted residual (R2-7): the new example's numbers can be copied like "Dal Rice" was; the "never copy" rule and the tap-only card (nothing saves without the user reading the rows) bound the harm. Add rules: `- A food tag lists every food in items, one entry per food, each with your own estimate for the amount the user ate; the totals are the sums. The example's foods and numbers show the format only: never copy them.` and `- Omit meal_type unless the user named the meal.` Concrete numbers, not `<placeholders>`: a placeholder the model copies is invalid JSON, which `extractLogActions` drops silently (§3).
- **queued wording** (`writeClaimSuffix(enabled, { tools, mealItems })`, both variants): `A water, weight, food, sleep or measurement tag saves after a 5-second countdown unless the user taps SKIP.` -> `A water, weight, sleep or measurement tag saves after a 5-second countdown unless the user taps SKIP. A food tag waits for CONFIRM.`; `"Queued. Tap CONFIRM to log it." (a workout tag)` -> `(a workout or food tag)`; `(a water, weight, food, sleep or measurement tag)` -> `(a water, weight, sleep or measurement tag)`. With `writeClaimSuffix(false, …)` it stays `""`.
- The two flags compose: write-claim OFF + meal ON = the OLD header with the meal edits (the replaced substrings exist under both headers; asserted).
- **Log-only detector** (R1-5): `write_claim_detector.ts` gains an additive `legacy_food` count (actions named `log_food`) next to `legacy_auto`, so a food tag that now waits for CONFIRM can be told apart in the `[write-claim-detect]` line; `legacy_auto` keeps its meaning (field set unchanged for old readers). Test in `write_claim_detector_test.ts`.
- No change to `logMealByText.ts`, `food_parser.ts`, the tag extractors, or the dedup.

### 5.2 Client, behind kill switch `configBox['disable_coach_meal_items_card']`
Guarded read (closed box = fix ON), one helper `coachMealItemsCardEnabled()` in `coach_meal_log.dart` with a `@visibleForTesting` override (the `confirmVerifiedStageDisabledForTest` pattern). ON:
1. **Tag items** — `coachItemsFromTag(Map data)` (`coach_meal_log.dart`): when `data['items']` is a list with at least one usable entry (non-blank `name`, finite `calories` >= 0), one `FoodItem` per usable entry (`quantity_g` > 0 else 100, `protein_g` / `carbs_g` / `fat_g` via `_num`, fibre 0); otherwise `[coachItemFromTag(data)]` (today's single item) or `null`. Unusable entries are skipped; all unusable = the single-item fallback. OFF: always the single item (today).
2. `_parse` (`log_food`): with the switch ON the card exists when `coachItemsFromTag(data)` is non-null (usable `items[]` alone is enough, R2-6); with it OFF the old `coachItemFromTag` null check. No card = `coach_food_tag_dropped_no_calories` as today. NO new field on `PendingLogAction` (R3-1): the items are always derived from `action.data` by `coachItemsFromTag` (which reads the switch), by the card for display and by `_logFood` for the write. `displayText` is changed only when `coachItemFromTag` is null (an items-only tag, R3-3): then `NutritionReadService.shortMealDisplayName({'items': [{'name': n}, ...]})` (`nutrition_read_service.dart:83`, joins with ` · `, cut to 80 runes) + ` — <Slot>`.
3. `_logFood(data, at)` keeps its signature and writes `coachItemsFromTag(data)` instead of `[coachItemFromTag(data)]`; `null` returns false exactly as the current `if (item == null) return false;` (R3-2). No override totals, as today.
3a. **One totals rule (R1-2).** `logMeal`'s total computation (`nutrition_write_service.dart:100-109`: `round(sum kcalWithFallback)` and `round(sum protein)`, an override used only when > 0) moves VERBATIM into a pure static `NutritionWriteService.mealTotals(items, {overrideCals, overrideProtein})` returning `(kcal, protein)`; `logMeal` calls it (byte-identical results). The dispatcher's override parse (`tool_dispatcher.dart:1818-1819`, `(p['total_calories'] as num?)?.toInt() ?? 0`, truncating) moves into `coachToolOverrides(payload)` in `coach_meal_log.dart`, used by the dispatcher and by the tool card. It runs in widget `build`, so it never casts (R2-3): `v is num && v.isFinite ? v.toInt() : 0` (same truncation; a wrong-typed field gives 0 where the old cast threw in `_executeLogMealByText` before its own `try` (`:1818-1819`, try at `:1821`) and the dispatch's outer catch failed the intent (R3-5); that difference is stated in the diagnose doc and pinned). The cards never add numbers themselves: tag card = `mealTotals(items)`, tool card = `mealTotals(coachItemsFromParsedMeal(p), overrides from coachToolOverrides(p))`. Tested card == stored row for: fractional payload totals, payload total 0 with items, items empty (totals fallback item), an item with 0 kcal (Atwater fallback).
3b. **Staleness (R1-1, revised R2-1/R2-2).** A food card with no timer could sit for days in one session (`pendingLogActionsProvider` is pruned only by `removeSettled` and an auth change). Rule, matching the tool path's 1 h TTL (`pending_tool_intents_provider.dart:17`, `_expireStale` `:121`; the intent derives it, `tool_intent.dart:137` `isExpired`): a food action older than 1 h is EXPIRED, and expiry is DERIVED, never stored: `PendingLogAction.isStaleFood(DateTime now)` = `type == food && now.difference(createdAt) > 1 h` (no third mutable flag next to `isLogged` / `isDismissed`). Clock = `nowWall()` (the test seam `setTestClockTo`).
   - The CARD is the only place a tap is refused: `LogConfirmCard._execute` checks `isStaleFood(nowWall())` FIRST, before `_isExecuting` is set; a stale tap writes nothing, shows "This suggestion has expired." (the tool path's words) and dismisses the action. `ConversationalLogHandler.executeAction` is NOT changed (handler-level tests with fixed `createdAt`, `nlog_repeat_adds_entry_behavioral_test.dart:518,568`, keep passing). A CONFIRM at 59:59 runs to completion on `createdAt`'s IST day; a retry after a failed save past 60 min is refused by the same check.
   - `build` renders a stale, not-logged food card as an expired line (`Expired: meal`, no CONFIRM / SKIP), read from `isStaleFood(nowWall())` at build time.
   - Sweep: `PendingLogActionsNotifier.addActions` first REMOVES from `state` every food action that `isStaleFood(nowWall())` AND is not `isLogged` AND is not in flight. In flight = `ConversationalLogHandler.isInFlight(id)` (NEW public static over the existing `_inFlight` map, `conversational_log_handler.dart:46`). Removed, never `isDismissed` (dismissed fades the card to opacity 0, `log_confirm_card.dart:126`, and feeds `removeSettled`). So a save running at 60:01 keeps its action, `markLogged` finds it, and a failed save still shows its card (whose next tap is then refused as stale).
   - Within the hour the meal logs on `createdAt`'s IST day (a 23:50 dinner confirmed at 00:10 lands on the evening it was eaten, the tool rule). App restart: pending actions are in memory only (no Hive), gone after a restart as today; a cleared conversation (`CoachChatClear`) does not touch them today and the 1 h expiry bounds them.
   - `test/ai_coach/log_confirm_card_single_write_test.dart:77-99` seeds `createdAt: DateTime.utc(2026, 11, 12, 3)` and taps CONFIRM: it gets `setTestClockTo` inside the hour (R2-1).
4. **Tag card** (`LogConfirmCard`): for `LogActionType.food` with the switch ON the countdown controller is created but `forward()` is never called (asserted: `isAnimating == false`), the ring is not drawn. Layout (R2-4): today's card is one `Row` (strip, icon, `Expanded` label, ring, CONFIRM, SKIP; `log_confirm_card.dart:127-226`, right margin 48). The food variant is a `Column`: header row (strip, icon, the label `MEAL`), `CoachMealItemsView`, then an action row (CONFIRM, SKIP) aligned right; the LOGGED state keeps today's row. Widget test at 320 dp and 411 dp wide with a long food name and four items: no overflow error (the OI-455 class). Every other type keeps the 5 s countdown. OFF: today's card. Class doc (`:14`) updated.
5. **Tool card** (`ToolConfirmCard`): for `log_meal_by_text` with the switch ON, the summary `Text` is replaced by `CoachMealItemsView(items: coachItemsFromParsedMeal(payload), totals: mealTotals(...) per 3a, slot: resolveCoachMealSlot(meal_type, intent.createdAt), lowConfidence: confidence == 'low', showGrams: false)`. OFF: today's one line. Header comment (`:18`) left as is (it already says both classes wait for APPLY).
6. **`CoachMealItemsView`** (NEW, `lib/features/ai_coach/widgets/coach_meal_items_view.dart`, read-only, StatelessWidget, no providers, no loading or error state of its own (the card around it owns those); an empty list renders the totals line only, never a blank card; `AppColors` / `AppTypography` only, no raw hex, no `GoogleFonts` call (R1-10)): a slot line (`Lunch`), one row per item in the Nutrition screen's AI-breakdown style (`ai_breakdown_card.dart:231-305`: name + `120 g` under it, PRO / CARB / FAT / KCAL columns; the row is copied, not imported, because `AiBreakdownCard` reads global providers and has an edit button), then a `Total  N kcal · P g protein` line, and the low-confidence note when set. The parser gives no grams (the 100 g in `coachItemsFromParsedMeal` is a sentinel), so tool items show no grams line (`showGrams: false`); tag items carry the coach's grams and show them. Wardroom palette, DM Sans via `AppTypography`.

Not in scope (stated): editing an item or the slot on the card (P5 asks for a per-item card and APPLY; editing is the Nutrition screen's job), a cloud column for the source, the +50 client (it keeps its 5 s food card; a coach on the new prompt then says "Tap CONFIRM" while that card saves itself; pre-launch testers only, accepted).

### 5.3 Rollout and compatibility
| Client \ Server | old prompt | new prompt |
|---|---|---|
| +50 (old card) | today | text chat: food goes to the tool (per-item rows, APPLY, totals-only card); photo: tag with `items[]` ignored, single item from `food_name` + totals, 5 s save while the coach says CONFIRM |
| new client | tag still possible (one item, waits for CONFIRM); tool per-item card | per-item card on both doors, both wait for a tap |

## 6. Tests
- Deno `_shared/write_claim_prompt_test.ts` (extend) + `_shared/testdata/icbf_blocks_pre_meal_items.json` (new golden):
  - golden self-sha; meal OFF (both write-claim states) byte-identical to main (vs both goldens);
  - every replaced substring constant exists in its base text (ON and OFF headers);
  - ON ai-proxy: no `"action":"log_food"`, no `Dal Rice`, contains the logMealByText line; ON media: the items example parses as JSON (extract the line, `JSON.parse`), totals equal the item sums, no `Dal Rice`; both suffixes say `A food tag waits for CONFIRM.` and never `a water, weight, food`;
  - kill-switch reader: only exactly `"true"` disables;
  - the existing `2189` size pin stays (meal default off in that call);
  - meal OFF compared as `icbfLogInstructions(x, {mealItems:false}) + writeClaimSuffix(x, {mealItems:false})` against `ai_proxy_on` / `media_on` (x = true) and against the write-claim golden (x = false) (R1-4);
  - ON with write-claim OFF: the meal edits applied under the old header ("I ate" gone from the tag RULES line only; the word elsewhere is legal);
  - the media example line, extracted from the ON text and `JSON.parse`d: has `food_name`, `calories_estimate` (= sum of items' calories), `protein_estimate` / `carbs_estimate` / `fat_estimate` (= sums), two `items` with every key, no `meal_type` (R1-3). The SAME line is copied into a Dart fixture test (below) so the client is proven to build a card from it.
- `test/contracts/coach_write_claim_wiring_test.dart` (repoint): the three call-site literals (`:35`, `:37`, `:108`) change to pass `{ mealItems: mealOn }`; the ordering check (`:30-31`) gains the `mealOn` read; add the `isCoachMealItemsRuleDisabled()` read once per handler and `meal_items_rule=` in the size log.
- `supabase/functions/_shared/completion_tile_routing_test.ts:140-141` (repoint, R1-5): it greps `writeClaimSuffix(ruleOn)` in `ai-proxy/index.ts`.
- `supabase/functions/_shared/write_claim_detector_test.ts` (extend): `legacy_food` counts `log_food` only; `legacy_auto` unchanged.
- Dart `test/contracts/coach_meal_items_card_behavioral_test.dart` (NEW, real Hive, real `LogConfirmCard` / `ToolConfirmCard` / `ConversationalLogHandler` / `ToolDispatcher`):
  - T1 tag card, food, switch ON: pump 6 s -> no `nlog_` row, no LOGGED; tap CONFIRM -> one row with TWO items (Idli 120 g 160, Sambar 150 g 110), total 270;
  - T2 the same card shows both item rows, the slot and `Total 270 kcal`;
  - T3 water tag still auto-saves at 5 s (the mirror: only food lost its timer);
  - T4 switch OFF: food tag auto-saves at 5 s with ONE item (today);
  - T5 tool card ON: shows each parsed item, the payload total, the slot from `createdAt`; nothing written before APPLY; APPLY writes the items (the existing dispatcher path);
  - T6 tool card OFF: the old one-line summary;
  - T7 `coachItemsFromTag` table: no items / empty list / all unusable -> single item; mixed -> usable only; negative / NaN calories skipped; grams <= 0 -> 100;
  - T8 a remounted food card (Landing B) does not auto-save on remount either; asserted directly: the card's controller `isAnimating == false` after the first frame (R1-8);
  - T9 kill switch through the REAL `configBox`: a closed box and an absent key = fix ON; `disable_coach_meal_items_card = true` = OFF (R1-8);
  - T10 totals parity: for each 3a case the card's shown kcal / protein equal the stored `nlog_` row's `total_calories` / `total_protein` (tool and tag);
  - T11 expiry: a food action 61 min old renders `Expired`, CONFIRM absent; a tap that lands after expiry writes nothing; `addActions` expires an old food action; a 59 min one still logs, on `createdAt`'s IST day across midnight (run under Kolkata and UTC);
  - T11b the 59:59 race (R2-2): CONFIRM at 59:59 with the save held on a `Completer`, clock moved to 60:01, `addActions` sweep runs, then the save completes: one `nlog_` row, the action still in state and marked logged, nothing thrown; and a stale, not-in-flight action IS removed by the same sweep;
  - T13 layout (R2-4): the food tag card at 320 dp and 411 dp with a long name and four items renders without an overflow error;
  - T14 `coachToolOverrides` on wrong-typed fields (`"300"`, `null`, `NaN`, `[]`) returns 0 without throwing; the tool card builds;
  - T12 the media example line (fixture copied from the Deno test, with a comment naming its source) through `_parse` -> one food action with two items; with `items` stripped -> one item from the flat keys (the +50 shape).
- Extend `test/contracts/coach_vs_screen_meal_log_parity_test.dart`: a two-item tag writes the same `items[]` shape as the screen for the same foods (P6 case gains an items variant).
- Repoint any test that pins the food tag's countdown (grep `LogConfirmCard` + `seconds: 5` / `pump(const Duration(seconds: 6))` with food); list them in the diagnose doc.
- Mutations (rule 21): M1 start the countdown for food again; M2 `coachItemsFromTag` returns only the first item; M3 kill-switch default flipped (closed box = OFF); M4 tool card summary back to one line; M5 media example totals != sums (test must catch); M6 drop the "never a tag" line; M7 OFF path applies one replacement; M8 suffix keeps `food` in the 5-second list; M9 `coachToolOverrides` uses `round` instead of `toInt` (T10 red); M10 expiry check removed from the tap path (T11 red); M11 `mealTotals` ignores the > 0 override rule; M12 the sweep drops the in-flight exemption (T11b red); M13 `isStaleFood` uses `>=` 0 instead of the hour (T11 red).
- Source pins to keep green (R2-10): `coach_no_dual_log_path_test.dart:60-72` (`Future<bool> _logFood(` returns `r.success`), `food_log_notifier_to_nutrition_log_items_test.dart:193-205` (`CoachMealLog.write(` in `_logFood`), `nlog_repeat_adds_entry_behavioral_test.dart:693` (`_logFood(` after `_logWeight(`), `counter_increment_on_analyse_test.dart:33-52` (slices `logMeal`). `_logFood(Map<String, dynamic> data, DateTime at)` keeps its signature (R3-1).
- `docs/sot_registry.yaml` cites into `nutrition_write_service.dart` (`:692`, `:855`, `:904`, `:915`, `:2212`, `:2671-2680` per round 2) shift with the `mealTotals` extraction: re-take each after the edit.
- Existing tests to re-run and read (R1-5): `log_confirm_card_single_write_test.dart` (comment about a countdown save goes stale under the switch: update it), `nlog_repeat_adds_entry_behavioral_test.dart`, `coach_no_dual_log_path_test.dart`, `coach_single_confirm_per_log_intent_test.dart`, `coach_vs_screen_meal_log_parity_test.dart`, every test under `test/ai_coach/` and `test/contracts/` naming `LogConfirmCard`, `ToolConfirmCard`, `nutrition_write_service`.

## 7. Docs / registry
- Diagnose doc `docs/diagnoses/2026-11-26-coach-meal-tag-example-copied-b3f7a1.md` (full template: recurrence).
- `docs/sot_registry.yaml`: `coach_meal_log` (tag items, the card), `coach_write_claim_wording` (meal switch); re-take any line_range in the touched files (`check_sot_registry_parity.dart` + the hand re-open of bare cites).
- Header / class comments: `write_claim_prompt.ts:5-8`, `LogConfirmCard` class doc `:14`, `PendingLogAction.createdAt` doc `ai_coach_provider.dart:1614-1615`; the `logMealByText.ts:40` "5-second auto-confirm" text stays (it is the write-claim OFF path; noted in the diagnose doc).
- `docs/sot_registry.yaml` line ~19464 ("water/weight/food/sleep/measurement tag for a 5-second countdown").
- `lib/features/ai_coach/CLAUDE.md` rows `coach_meal_log`, `coach_workout_card_saved_state` (the "LogConfirmCard (meals/water/sleep) auto-saves 5 s" sentence), pitfall "The coach says Logged"; `supabase/functions/CLAUDE.md` row `coach_write_claim_wording`; `docs/naming_conventions.md` glossary (`DISABLE_COACH_MEAL_ITEMS_RULE`, `disable_coach_meal_items_card`); `docs/ship_dark_pending_review.yaml` NOT used (switches default to the fix ON; this is not ship-dark).
- §4.6 (R2-11): both switches default to the fix ON without a device check first. That departs from §4.6 step 3 ("roll the gate after manual verification") in the same way Landing 3a and OI-493 did: pre-launch testers only, the founder locked P5, and each switch is a one-step rollback (server env var / one configBox key). The old paths (server OFF branch + its golden, client OFF card) are tracked for deletion on a NEW OI minted with `scripts/mint_oi.sh` ("Remove DISABLE_COACH_MEAL_ITEMS_RULE + disable_coach_meal_items_card and their OFF paths", reopen when: the founder's device check of the per-item card on the next AAB passes), cited in the closure ledger and the diagnose doc. The diagnose doc states the §4.6 step-3 deviation in so many words.
- Closure ledger `docs/audit/oi348-landing3b.closure.yaml` (B4, P5-tool-card, P5-tag-card, P5-prompt, EF-DEPLOY = `blocked_on_user` until the founder's deploy go).
- OI-348 board + `project_oi348_*` memory after the merge.

## 8. Order
1. Golden capture (done before any edit: `icbf_blocks_pre_meal_items.json`).
2. Server: constants, builders, reader, wiring, Deno tests (`deno test --no-check --allow-all --node-modules-dir=none supabase/functions/`, `deno check` both proxies).
3. Client: `coachItemsFromTag`, action field, `_logFood`, `CoachMealItemsView`, both cards, switch; tests; mutations.
4. Docs, registry, diagnose, ledger; whole-project `flutter analyze --no-fatal-infos`; pre-commit gate loop.
5. Commit on the branch, PR, CI green, plan review rounds (round 2 on the post-round-1 plan), plan-review record, B-pass, founder go to merge, then the deploy go.

---

## Round 1 log (2026-11-26, one Sonnet reviewer, context-blind; 0 P0, 0 P1, 7 P2, 3 P3)
Each claim spot-checked by the coordinator before folding in (`nutrition_write_service.dart:100-109`, `ai-proxy/index.ts:1010` + early returns, `pending_tool_intents_provider.dart:17,121`, `write_claim_detector.ts:87-105`).
| # | Sev | Finding | Disposition |
|---|---|---|---|
| R1-1 | P2 | A food card with no timer can live for days; no expiry rule | 5.2 point 3b: 1 h expiry (the tool TTL), T11, M10 |
| R1-2 | P2 | Card total vs stored total (`toInt` truncation, Atwater fallback, > 0 override) | 5.2 point 3a: one `mealTotals` + `coachToolOverrides`, T10, M9/M11 |
| R1-3 | P2 | Media example must carry the flat keys the current client reads | 5.1: exact line pinned; Deno JSON test + Dart fixture T12 |
| R1-4 | P2 | `log_food` line differs per builder; OFF-golden comparison must be stated | 5.1: two constants with newline; section 6 comparison spelled out |
| R1-5 | P2 | Unnamed tests to repoint (`completion_tile_routing_test.ts:140-141`, wiring ordering) and the detector's `LEGACY_AUTO` | Section 6 repoints; 5.1 detector `legacy_food` field |
| R1-6 | P3 | Citations `~178`, `1747`, `1696` | Fixed in section 3 |
| R1-7 | P2 | Tool parse failure has no tag fallback; is the tool offered on every channel the block reaches | 5.1: channel evidence + accepted behaviour stated |
| R1-8 | P2 | Mutation/test gaps: real configBox read, reader test, no-timer assertion | T8/T9, M3 |
| R1-9 | P3 | Comments and a registry line that go stale | Section 7 |
| R1-10 | P3 | Copied view must stay Wardroom / DM Sans | 5.2 point 6 |

## Round 2 log (2026-11-26, a second Sonnet reviewer, context-blind, on the post-round-1 plan; 0 P0, 0 P1, 6 P2, 6 P3)
Coordinator spot-checks: `log_confirm_card_single_write_test.dart:77-99` fixed `createdAt` (confirmed), `ist_date.dart:35,65` `setTestClockTo` / `nowWall` (confirmed), `conversational_log_handler.dart:46-50` `_inFlight` private + count getter only (confirmed).
| # | Sev | Finding | Disposition |
|---|---|---|---|
| R2-1 | P2 | Expiry would redden `log_confirm_card_single_write_test` and handler tests with fixed `createdAt` | 3b: check in the card tap only, `nowWall()`, test gets `setTestClockTo` |
| R2-2 | P2 | Where "expired" lives; sweep vs in-flight save; isDismissed fade | 3b: derived `isStaleFood`, removal not dismiss, `isInFlight(id)` exemption, T11b, M12 |
| R2-3 | P2 | `coachToolOverrides` in `build` must not throw on wrong types | 3a: `is num` checks, T14 |
| R2-4 | P2 | Food card layout unspecified (single Row) | point 4: Column layout, T13 overflow test |
| R2-5 | P2 | Suffix constants cannot exist in the OFF suffix (empty) | 5.1: asserted against `WRITE_CLAIM_RULE` / `MEDIA_WRITE_CLAIM_RULE`; media keeps "I ate" on purpose |
| R2-6 | P3 | Usable items without flat calories still dropped | point 2: items alone are enough with the switch ON |
| R2-7 | P3 | New example numbers copyable | 5.1: accepted residual, stated |
| R2-8 | P3 | No other prompt teaches the tag | none |
| R2-9 | P3 | `mealTotals` extraction byte-identical; registry cites shift | Section 6 re-take note |
| R2-10 | P3 | Source pins on `_logFood` / `logMeal` | Section 6 list |
| R2-11 | P2 | §4.6: old paths need a removal owner; default-ON without device check | Section 7: OI minted, deviation stated |
| R2-12 | P3 | +50 scope note correct | none |

## Round 3 log (2026-11-26, a third Sonnet reviewer, narrow check of the round-2 folds; 0 P0, 0 P1, 2 P2, 3 P3, all plan text)
All twelve R2 dispositions verified closed; Q1 (no path where a stale card writes; `nowWall()` is the clock on both sides) and Q2 (a 0 override falls back to the item sum) answered with evidence.
| # | Sev | Finding | Disposition |
|---|---|---|---|
| R3-1 | P2 | `action.foodItems` has no path into `_logFood(data, at)` | Field dropped; items derived from `data` by `coachItemsFromTag` in the card and in `_logFood` (point 2, 3) |
| R3-2 | P2 | `[coachItemFromTag(data)]` is a `List<FoodItem?>`; the null guard must survive | Point 3: `coachItemsFromTag(data)`, null -> false |
| R3-3 | P3 | "displayText unchanged" contradicts the items-only case | Point 2 reworded |
| R3-4 | P3 | `shortMealDisplayName` takes a map | Point 2 names the call shape and file:line |
| R3-5 | P3 | "inside the dispatcher's try" imprecise | 3a reworded |
