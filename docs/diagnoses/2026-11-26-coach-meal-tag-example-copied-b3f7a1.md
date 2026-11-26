---
bug_id: b3f7a1
date: 2026-11-26
batch: oi348-landing3b
status: fixed
blast_radius: platform
symptom: >-
  OI-348 walk A18 (Chintamani, AAB +50, 2026-11-22 16:52Z): "2 rotis and dal" told to the AI coach was stored as ONE
  item "roti and dal", 200 g, 280 kcal, slot lunch, by a card that saved itself 5 s after it appeared. 200 g / 280 kcal
  / lunch are the numbers of the prompt's only food tag example ("Dal Rice"). The same food logged on the Nutrition
  screen 90 s later was two items, Roti 210 kcal + Dal 150 kcal = 360 kcal. The coach's typed meal tool (per-item parse)
  showed only a one-line total on its card. Founder decision P5 (2026-11-22): coach meals show a per-item macro card and
  save only on a tap; no 5 s auto-save for food.
concept: coach_meal_log
sot_registry_entry: coach_write_claim_wording
writers:
  - file: supabase/functions/_shared/write_claim_prompt.ts
    method: icbfLogInstructions (ai-proxy tag protocol; the log_food example line)
    line: 97
  - file: supabase/functions/_shared/write_claim_prompt.ts
    method: mediaIcbfLogInstructions (ai-media-proxy tag protocol)
    line: 140
  - file: lib/features/ai_coach/services/conversational_log_handler.dart
    method: _logFood (tag writer; now coachItemsFromTag)
    line: 151
  - file: lib/features/ai_coach/services/tool_dispatcher.dart
    method: _executeLogMealByText (tool writer; now coachToolOverrides)
    line: 1810
  - file: lib/core/services/nutrition_write_service.dart
    method: mealTotals (extracted verbatim from logMeal; the one stored-total rule)
    line: 69
readers:
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method_or_widget: PendingLogActionsNotifier._parse (log_food), addActions stale-food sweep
    line: 1680
  - file: lib/features/ai_coach/widgets/log_confirm_card.dart
    method_or_widget: LogConfirmCard (food variant, no countdown, 1 h expiry)
    line: 23
  - file: lib/features/ai_coach/widgets/tool_confirm_card.dart
    method_or_widget: ToolConfirmCard._buildMealItems
    line: 27
  - file: lib/features/ai_coach/widgets/coach_meal_items_view.dart
    method_or_widget: CoachMealItemsView
    line: 16
hive_key_prefix: nlog_
hive_key_formula: "nutritionBox['nlog_<istDateStr(date)>_<meal_type>_<v5 8 hex of sorted name|grams>'] plus the first free occurrence suffix (computeLogKey / firstFreeLogKey; unchanged)"
sync_methods:
  - NutritionWriteService.logMeal -> syncNutritionData (unchanged)
restore_methods: []
cloud_table: nutrition_logs
cloud_columns: [total_calories, total_protein, items]
contract_test_path: test/contracts/coach_meal_items_card_behavioral_test.dart
ist_handling:
  - The meal still logs on the IST day of the instant it was reported (the food card's createdAt, the tool intent's createdAt), applied once by logMeal's istDateStr. A food card now waits for a tap, so a 23:50 IST meal confirmed at 00:49 lands on the evening it was eaten (test T11 across midnight).
  - The card's hour is measured on nowWall() against createdAt, which is stamped with nowWall() at parse: one clock on both sides (setTestClockTo in tests).
provider_invalidations:
  - weeklyNutritionProvider after a tag meal (unchanged)
  - the dispatcher's _invalidateNutritionProviders after a tool meal (unchanged)
  - pendingLogActionsProvider (stale food actions removed in addActions)
telemetry_op_types:
  success: []
  failure:
    - coach_food_tag_dropped_no_calories
    - tool_dispatch_log_meal_by_text_failed
cross_account_guard: n/a (logMeal's GuardedBox owner guard, unchanged)
forbidden_patterns_checked:
  - { pattern: "\"action\":\"log_food\" in the ai-proxy ICBF block with the meal-items rule on", absent: true }
  - { pattern: "Dal Rice in either ON block", absent: true }
  - { pattern: "a water, weight, food in either ON suffix", absent: true }
  - { pattern: "a third mutable expired flag on PendingLogAction", absent: true }
  - { pattern: "a cast of total_calories in a widget build", absent: true }
proposed_fix: >-
  Server (switch DISABLE_COACH_MEAL_ITEMS_RULE, exactly "true" disables, read once per request next to ruleOn): ai-proxy's
  ICBF block drops the log_food example, drops "I ate" from the tag rule and adds "Food the user ate is never a tag: call
  logMealByText ..."; the media block's food example becomes a two-food items[] example (Idli and Sambar, every flat key
  the current app reads kept) with a never-copy rule and "omit meal_type"; both write-claim suffixes say a food tag waits
  for CONFIRM. Every edit is a .replace of an exported exact substring asserted present; OFF is byte-identical to main
  238bb44f (golden). The detector gains a legacy_food count. Client (switch configBox disable_coach_meal_items_card, a
  closed box = fix ON): coachItemsFromTag (one row per usable food, else the flat item; items alone are enough);
  NutritionWriteService.mealTotals (logMeal's rule moved verbatim) and coachToolOverrides (the dispatcher's toInt parse,
  without a cast) so each card shows the total that is stored; CoachMealItemsView (one row per food, slot, total) in both
  cards; the food tag card waits for CONFIRM with no countdown, for at most an hour (PendingLogAction.isStaleFood,
  derived; the tap refuses a stale card; addActions removes stale idle food cards, never a logged one or one whose save
  is in flight via ConversationalLogHandler.isInFlight).
regression_test_planned:
  - test/contracts/coach_meal_items_card_behavioral_test.dart
  - supabase/functions/_shared/write_claim_prompt_test.ts
  - supabase/functions/_shared/write_claim_detector_test.ts
  - test/contracts/coach_write_claim_wiring_test.dart
  - test/ai_coach/log_confirm_card_single_write_test.dart
related_bugs:
  - ec6f6c  # OI-493 Landing A: both coach doors through CoachMealLog.write; the tag kept ONE item and its 5 s card; "no prompt change"
  - a1d7c3  # coach dual-path double-log: one confirm affordance per log (dedup kept)
  - 90a784  # coach-log-truth write-claim wording and golden (edited here, OFF unchanged)
  - 4cb58f  # OI-493 Landing B: one tag, one write (_inFlight; reused for the sweep exemption)
recurrence: |
  Recurrence of the class "a coach door drifts from the reference door" (debugging skill class 2.151; ec6f6c is its
  first instance). ec6f6c made the tag and the tool write through one writer but left the tag with one item, its 5 s
  card and the prompt's concrete example ("No prompt change" was a stated choice). New shape here: the PROMPT's own
  example became the stored data. Known-good fix applied: the tag door now produces the same per-item rows as the tool
  and the screen, and the example that fed the copy is gone from the door that has a tool.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "coach_meal_log.dart (coachItemsFromTag, coachToolOverrides, switch), nutrition_write_service.dart (mealTotals), ai_coach_provider.dart (isStaleFood, sweep, _parse), conversational_log_handler.dart (_logFood, isInFlight), log_confirm_card.dart (food variant), tool_confirm_card.dart (meal rows), coach_meal_items_view.dart (new). coach_meal_items_card_behavioral_test 20/20 green under TZ=Asia/Kolkata; 158 related tests green; whole-project analyze clean of warnings." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "The card tests write through the real LogConfirmCard / ConversationalLogHandler / ToolDispatcher on real Hive and read the nlog_ row: two items for a two-food tag, total == the card's total for three tool payload shapes." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; nutrition_logs / nutrition_log_items rows keep their shape (more item rows per coach meal)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No backfill: tester data only, pre-launch; only new coach meals change." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "write_claim_prompt.ts, write_claim_detector.ts, ai-proxy/index.ts, ai-media-proxy/index.ts changed; deno test over supabase/functions 1974 passed; deno check ai-proxy and ai-media-proxy clean. Deploy of both from main after the merge is its own founder go (closure ledger EF-DEPLOY)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: verified, evidence: "New env read DISABLE_COACH_MEAL_ITEMS_RULE is a kill switch whose absence means ON; nothing to set at deploy." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "Compatibility both ways (plan 5.3): the +50 app ignores items[] and logs one item from the flat keys the new example keeps (T12 strips items and gets one item); a new app on the old prompt still gets one-item tags, which now wait for CONFIRM. No live trace yet: the deploy and the next AAB come after the merge." }
impact_analysis: >-
  A coach meal from text chat goes through the meal tool: each food is its own row with its own macros, shown on the card
  before APPLY. A coach meal from a photo lists each food in the tag and waits for CONFIRM. Nothing a coach proposes for
  food saves without a tap; an untapped food card expires after an hour. Water, weight, sleep and measurement cards keep
  their 5 s save. The +50 app keeps its 5 s food card until the next AAB, while a coach on the new prompt says "Tap
  CONFIRM" there (pre-launch testers only, accepted).
---

# A coach meal copied the prompt's example and saved itself (b3f7a1, OI-348 Landing 3b)

Plan: `docs/plans/oi348-landing3b.md` (three review rounds, converged). Founder decision P5 (2026-11-22); "Start 3b"
(2026-11-26). The photo-path question was left open by the founder; the plan's default (photo meals get the same card
and tap) is what shipped.

## Root cause
The model answered with the legacy `log_food` tag, not the `logMealByText` tool, and copied the tag protocol's only
food example (`write_claim_prompt.ts`, the "Dal Rice" line in both ICBF blocks). A tag carried one food
(`coachItemFromTag`) and its card saved after 5 s (`LogConfirmCard.initState`). The tool already parsed per item but its
card showed one line of totals (`ToolConfirmCard._buildSummary`).

## Fix
See `proposed_fix`. Two deliberate behaviour changes beyond the cards:
- `coachToolOverrides` never casts: a wrong-typed `total_calories` used to throw in `_executeLogMealByText` before its own
  `try` (the dispatch's outer catch then failed the intent); now it is 0 and the items' sum is stored (T10 wrong-typed
  case), the same number the card showed.
- CLAUDE.md 4.6 step 3 (roll the gate after manual verification): both switches default to the fix ON without a device
  check first, as Landing 3a and OI-493 did: pre-launch testers only, the founder locked P5, and each switch is a
  one-step rollback. The old paths are tracked for deletion on OI-529.
- The write-claim-OFF copy of `logMealByText.ts`'s description still says "5-second auto-confirm" (that is OI-368/369's
  switch, unchanged).

## Golden capture
`supabase/functions/_shared/testdata/icbf_blocks_pre_meal_items.json` was recorded from main `238bb44f` before any edit by
a scratch Deno script that imported that tree's `write_claim_prompt.ts` and wrote
`icbfLogInstructions(true) + writeClaimSuffix(true)` and `mediaIcbfLogInstructions(true) + writeClaimSuffix(true, { tools: false })`
with their sha256 (`deno run --no-check --allow-read --allow-env --node-modules-dir=none capture_meal_golden.ts <tree> <sha>`).

## Mutations (rule 21)
Each mutant applied once (match count checked), the named test run, the file restored by copy and compared byte for byte
(`restored=true` for every row). Server mutants ran `write_claim_prompt_test.ts`, app mutants
`coach_meal_items_card_behavioral_test.dart`.

| # | Mutant | Red |
|---|---|---|
| M1 | food card starts the countdown again | 5 |
| M2 | `coachItemsFromTag` keeps only the first item (first try matched twice: re-anchored) | 4 |
| M3 | closed configBox reads as switch OFF | 3 |
| M4 | tool card back to the one-line summary | 4 |
| M5 | media example `calories_estimate` != item sum | 1 |
| M6 | ai-proxy "never a tag" line dropped | 1 |
| M7 | meal OFF path applies the edits | 4 |
| M8 | suffix keeps food in the 5-second list | 1 |
| M9 | `coachToolOverrides` rounds instead of truncating | 2 |
| M10 | expiry check removed from the tap | 2 |
| M11 | `mealTotals` takes a 0 override | 2 |
| M12 | sweep drops the in-flight exemption | 2 |
| M13 | `isStaleFood` true from the first second | 6 |
| M14 | `_logFood` writes the flat item only | 1 |
| M15 | server switch reader accepts any value | 1 |

## B-pass fixes (`docs/reviews/oi348-landing3b-bpass.md`)
A context-blind B-pass on commit 92e94286 found 0 P0/P1, 1 P2, 3 P3. All four were fixed in this batch:
- **F1 (P2):** an expired food card had no SKIP, and the sweep ran only on a reply that carried a tag. Now the expired
  card keeps SKIP (`coach_food_card_skip`), and every reply path (media, send, auth retry) calls the public
  `dropStaleFood()` before its tag guard.
- **F2 (P3):** `meal_type` was cast at four coach sites. Now they all read it through `coachMealTypeOf`, which returns
  a String or null.
- **F3 (P3):** a listed food the parse skipped was silent. Now `coachTagUnusableItemCount` feeds the
  `coach_food_tag_items_partial` event from `_parse`. The 100 g grams default stays: it is the same sentinel as the
  tool path.
- **F4 (P3):** with the write-claim rule off and the meal rule on, the `logMealByText` description still promised a
  5-second auto-confirm. Now `runToolLoop` takes `mealItemsRule`, and `applyWriteClaimDescriptions(tools, false,
  {mealItems: true})` rewrites only that sentence. With the meal rule off it returns the input array itself.

Mutants on the fixes ran with the same protocol. App mutants count `[E]` lines, like M1-M15. Server mutants also ran
`tool-loop_write_claim_note_test.ts`.

| # | Mutant | Red |
|---|---|---|
| M16 | expired card hides SKIP | 3 |
| M17 | the auth-retry path stops sweeping | 3 |
| M18 | `coachMealTypeOf` casts | 3 |
| M19 | unusable-item count always 0 | 3 |
| M20 | write-claim OFF ignores the meal rule | 2 |
| M21 | `runToolLoop` stops passing the meal rule | 1 |
