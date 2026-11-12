---
bug_id: ec6f6c
date: 2026-11-12
batch: oi493-nutrition-parity
status: fixed
blast_radius: platform
symptom: >-
  A meal logged from the AI coach was stored differently from the same meal logged on the Nutrition screen (OI-493).
  The logMealByText tool wrote ONE synthetic item (the parsed items and their fibre dropped), under `snacks` when the
  coach named no slot, on a payload date parsed at host-local midnight, and spent a client AI-text unit the server never
  counts. The legacy log_food tag saved a food-database match or invented 200/10/25/5 defaults instead of the coach's
  own estimate. Separately, six readers took the meal name from a top-level `food_name` that logMeal never writes, so
  the coach snapshot named every meal "Unknown", the Search tab's recent list was always empty, the delete title and the
  template default name fell back to generic text, and the recent_deletes audit (the coach's correction history) was
  never written.
concept: nutrition_total_calories
sot_registry_entry: hive_field_name_nlog
writers:
  - file: lib/features/ai_coach/services/coach_meal_log.dart
    method: CoachMealLog.write (NEW, the one coach meal writer; calls NutritionWriteService.logMeal)
    line: 33
  - file: lib/features/ai_coach/services/tool_dispatcher.dart
    method: _executeLogMealByText (was _writeFoodLogFromIntent, deleted)
    line: 1629
  - file: lib/features/ai_coach/services/conversational_log_handler.dart
    method: _logFood (was FoodRepository.search + FoodLogNotifier.logFood)
    line: 96
  - file: lib/core/services/nutrition_write_service.dart
    method: logMeal (unchanged; items[] carry the names, no top-level food_name)
    line: 62
readers:
  - file: lib/features/ai_coach/services/ai_snapshot_builder.dart
    method_or_widget: _getMealsToday (meals_today names)
    line: 845
  - file: lib/features/nutrition/screens/nutrition_screen.dart
    method_or_widget: _confirmAndDeleteLog title, _saveAsTemplate default name
    line: 644
  - file: lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart
    method_or_widget: _RecentLogs via recentLoggedItems, _relogFromHistory via relogItem
    line: 276
  - file: lib/core/services/nutrition_write_service.dart
    method_or_widget: deleteLog hasFoodMeta + recent_deletes entry
    line: 525
hive_key_prefix: nlog_
hive_key_formula: "nutritionBox['nlog_<istDateStr(date)>_<meal_type>_<v5 8 hex of sorted name|grams>'] (computeLogKey; unchanged)"
sync_methods:
  - NutritionWriteService.logMeal -> syncNutritionData (unchanged)
restore_methods: []
cloud_table: nutrition_logs
cloud_columns: [date, meal_type, total_fiber]
contract_test_path: test/contracts/coach_vs_screen_meal_log_parity_test.dart
ist_handling:
  - The day is the IST date of the instant the meal was reported, applied once by logMeal's istDateStr. For the tool that instant is the server's intent createdAt (ToolIntent.fromJson parses an ISO Z string, so it is UTC-flagged); for the tag it is the card's createdAt (nowWall() at parse).
  - The slot uses the screen's clock rule inferMealSlot on the DEVICE-LOCAL hour, so the instant goes through .toLocal() first (a UTC-flagged createdAt read raw would turn a 13:00 IST lunch into breakfast). Tested under TZ=Asia/Kolkata, UTC and Asia/Tokyo with a per-zone table.
  - The payload date is ignored on the client; the server refuses any date other than istDateStr() (D2), so a past or future meal is answered in chat instead of landing on today.
provider_invalidations:
  - tool: the dispatcher's _invalidateNutritionProviders (unchanged)
  - tag: weeklyNutritionProvider after a successful write (was inside FoodLogNotifier.logFood)
telemetry_op_types:
  success: []
  failure:
    - coach_food_tag_dropped_no_calories
    - coach_meal_log_badge_check
    - tool_dispatch_log_meal_by_text_failed
cross_account_guard: n/a (logMeal's own GuardedBox owner guard, unchanged)
forbidden_patterns_checked:
  - { pattern: "_writeFoodLogFromIntent", absent: true }
  - { pattern: "UsageCounterService in tool_dispatcher._executeLogMealByText", absent: true }
  - { pattern: "FoodRepository in conversational_log_handler.dart", absent: true }
  - { pattern: "food_name token outside the 6-file allowlist in lib/", absent: true }
proposed_fix: >-
  One writer, CoachMealLog.write, for both coach doors: logMeal with source aiCoachTool, the day and slot from the
  reported instant (slot = the coach's named slot, else inferMealSlot(at.toLocal())), then the badge check in a
  try/catch. The tool writes the parsed items with fibre (coachItemsFromParsedMeal, 100 g sentinel, totals fallback);
  the tag writes the coach's own estimate (coachItemFromTag; a tag without calories_estimate shows no card and logs
  coach_food_tag_dropped_no_calories). No AI-text counter unit for a coach meal (the dead source->counter mapping now
  says null for aiCoachTool too). Server: logMealByText refuses a non-today date with a message the model reads
  (invalid_args) and tells the model to omit date and mealType; food_parser gains fiber_g through a pure
  normaliseParsedItems. Readers: NutritionReadService.shortMealDisplayName (items[] names, cut to 80 runes, never a
  lone surrogate) for meals_today, the delete title, the template name and the recent_deletes entry; deleteLog's
  hasFoodMeta accepts a non-empty items[]; the recent list reads items (recentLoggedItems) and relogs them as stored
  (relogItem: 0 g -> 100 g). The dead MealSection widget and its three registry rows are deleted. A source guard pins
  every food_name token in lib/ per file. No prompt change (the ICBF golden and size pin stay byte-identical).
regression_test_planned:
  - test/contracts/coach_vs_screen_meal_log_parity_test.dart
  - test/contracts/nlog_food_name_reader_guard_test.dart
  - supabase/functions/_shared/tools/__tests__/logMealByText_test.ts
  - supabase/functions/_shared/food_parser_test.ts
related_bugs:
  - 8b3d4e  # Home recent logs read a top-level food_name (docs/diagnoses/2026-06-05-home-recent-logs-unknown-name-8b3d4e.md)
  - 4f9b2e  # istNow() double shift, OI-494 (same date-into-the-wrong-zone family as the payload date at host-local midnight)
  - 0f8d54  # counters at the API-call site
recurrence: |
  Recurrence of 8b3d4e (2026-06-05): that fix moved Home recent logs from a top-level food_name to
  NutritionReadService.deriveMealDisplayName and pinned that one reader. Five more readers of the same absent key
  (meals_today, the delete title, the template name, the recent list, the deleteLog audit test) and one dead widget
  stayed, because the pin was per-reader and nothing scanned for the key. Known-good fix applied (derive from items[])
  to every remaining reader, plus a guard this time: nlog_food_name_reader_guard_test counts the food_name token in
  every lib/ file with comments stripped (the OI-494 scanner, now shared in test/helpers/dart_source_scan.dart) against
  an exact per-file allowlist with a reason each.
  The coach-door half is a new shape in this class (two writer doors drifting from the reference door); debugging
  skill class 2.151 records it.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "coach_meal_log.dart (new), tool_dispatcher.dart, conversational_log_handler.dart, ai_coach_provider.dart, ai_snapshot_builder.dart, nutrition_screen.dart, nutrition_read_service.dart, nutrition_write_service.dart, search_mode_body.dart; meal_section.dart deleted. 22 parity tests green under TZ=Asia/Kolkata, UTC and Asia/Tokyo; guard test green; 15 mutants red (table below)." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "The parity test writes through the real dispatcher, the real tag handler (a captured WidgetRef) and AiBreakdownNotifier.saveMeal on real Hive and compares the nlog_ rows field for field." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "information_schema on dedsavbjuwgarrhphgnl 2026-11-12: nutrition_logs has no source column (the plan's residual 'cloud source column, no reader' was wrong: there is no such column); nutrition_log_items has food_name and fiber. No schema change." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Read-only query 2026-11-12: 82 nutrition_logs rows (breakfast 36, lunch 21, dinner 14, snacks 11), 245 items, 118 with fibre 0. Coach rows cannot be told apart (no source column). Not healed: testers only (app not live), and only new writes change." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "logMealByText.ts and food_parser.ts changed; deno test green (19), deno check ai-proxy + ai-media-proxy clean. The ai-proxy deploy needs the founder's go after the merge; until then the live server still accepts a past date and the client logs such a meal on the createdAt day (D2)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "Compatibility both ways (plan D5): old client + new server ignores fiber_g and never receives a non-today date; new client + old server infers the slot, ignores the payload date, writes fibre 0. The intent shape is driven through ToolIntent.fromJson in the test. No live trace; the device check is on the OI board after the next build." }
impact_analysis: >-
  A coach meal now lands on the day it was reported, under the slot the Nutrition screen would pick at that time (or the
  slot the coach named), with each parsed item and its fibre, and no longer spends the user's AI-text allowance. A food
  tag stores the coach's own estimate. The coach can name today's meals and is told what was deleted; the Search tab's
  recent list works and relogs the item as first written. A coach meal for another day is answered in chat ("add it from
  the Nutrition tab") once ai-proxy is deployed. Same meal logged twice still overwrites (Landing B).
---

# A coach meal stores and counts like a screen meal (ec6f6c, OI-493 Landing A)

Plan: `docs/plans/oi493-nutrition-parity.md` (rev 5.1, converged after 5 review rounds). Founder decisions F1-F4
(2026-11-12): slot from the clock, one result for every coach door, today only, the same meal twice logs twice
(Landing B).

## Root cause
Two coach doors each built their own `nlog_` row while the Nutrition screen's AI-text tab (`AiBreakdownNotifier.saveMeal`)
was the reference:
- Tool `logMealByText` -> `ToolDispatcher._executeLogMealByText` -> `_writeFoodLogFromIntent`: one synthetic item named
  `food_name` (items[] and fibre dropped), `DateTime.tryParse('<YYYY-MM-DD>') ?? DateTime.now()` (host-local midnight),
  `_validateMealType` defaulting to `snacks`, and a `featureAiTextLogPro` increment (the server's `food_text` cap,
  migration 129, counts only `food_text_analysis` rows; `parseFoodText` writes none).
- Tag `log_food` -> `ConversationalLogHandler._logFood`: `FoodRepository.search(name).first` or fabricated defaults,
  through `FoodLogNotifier.logFood` with `source: manualSearch`.
And six readers of a top-level `food_name` that `logMeal` never writes (section 1.4 of the plan).

## Fix
See `proposed_fix`. The server change ships with the merge; the deploy is a separate founder go.

## Mutations (rule 21)
Each mutant applied (count checked), the named test run, file restored.

| # | Mutant | Red |
|---|---|---|
| S1 | refine `d === istDateStr()` -> `d.length > 0` | 2 (yesterday, tomorrow refused) |
| S2 | fibre rule without `>= 0` | 1 |
| S3 | fibre always 0 | 1 |
| M1 | dispatcher `at: nowWall()` | 1 (P1/P2 door) |
| M2 | drop `.toLocal()` in the slot rule (Kolkata) | 7 |
| M3 | parsed item fibre 0 | 1 (P5) |
| M4 | tag calories forced to 200 | 1 (P6) |
| M5 | tag `_logFood(action.data, nowWall())` | 1 (P6 midnight) |
| M6 | badge hook called outside the try | 2 (P8) |
| M7 | `cutToRunes` by UTF-16 `substring` | 1 (P9 emoji) |
| M8a | audit legacy `food_name` leg off | 0 at first (only items rows were tested); a legacy flat-row case was added: 1 |
| M8b | audit items leg off | 1 |
| M9 | recent list needs a top-level `food_name` | 1 |
| M10 | relog keeps a 0 g item | 1 |
| M11 | counter increment re-added in `CoachMealLog.write` | 1 (P7; first attempt was a compile error, re-run with imports) |
| M12 | dispatcher reads the payload date | 2 (yesterday, tomorrow; a malformed date is equivalent: `tryParse` null) |
| G1 | double-quoted `log["food_name"]` read in ai_snapshot_builder | 1 (guard) |
| G2 | `const _k = 'food_name'` in nutrition_screen | 1 (guard) |

## Residuals (accepted, plan section 5)
- Landing B: the same meal twice adds an entry, the zero-override fallback, concurrent dispatch of one intent.
- Entry UI differs (APPLY card vs 5 s auto-save card).
- `inferMealSlot` reads the device-local hour: the screen's own rule.
- A tag in one turn and the tool in a later turn for one meal log it twice (different names and grams, different keys);
  unchanged, and the intended behaviour once Landing B lands.
- A calorie-less tag is dropped and counted (`coach_food_tag_dropped_no_calories`); reopen if the event shows up in
  tester data.
- Until `ai-proxy` is deployed the live server accepts a past date; the client logs such a meal on the createdAt day.
- A meal reported in the last seconds before IST midnight and parsed after it lands on the next day (createdAt is
  stamped after the parse).
- Devanagari: the 80-rune cut can split a grapheme cluster (never a surrogate pair).
