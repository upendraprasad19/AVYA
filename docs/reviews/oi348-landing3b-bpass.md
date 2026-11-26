---
reviewed_at: 2026-11-26T15:30:00+05:30
staged_against: 92e94286
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, build_define, analyze_scope]
findings_count: 4
verdict: accepted
verdict_note: "Triaged by the author 2026-11-26: F1-F4 all fixed in the B-pass fix commit, each with a test and a mutant (M16-M21). Platform tier: advisory verdict."
---

# Code Review — oi348-landing3b at 92e94286 (vs origin/main 238bb44f)

PR #352, OI-348 Landing 3b (B4 + P5: coach meals show one row per food and save only on a tap). One fresh context-blind
Sonnet reviewer read the three-dot diff with the plan, the diagnose doc and the founder decisions (P5 locked; photo
meals get the same card; both kill switches default ON; rejected: a stored `expired` flag and casts in `build`). It
could run only read-only git, file reads, the three named flutter test files, the two Deno files and `dart analyze`.
It could not run scripts, the network or the database. It ran the three flutter files (31+ cases) and 34 Deno tests:
all green.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** lib/features/ai_coach/providers/ai_coach_provider.dart (the three `addActions` call sites, the sweep in `addActions`); lib/features/ai_coach/widgets/log_confirm_card.dart `_buildFoodCard`
- **claim:** The stale-food sweep ran only inside `addActions`, and every caller guards that call with `actions.isNotEmpty`. So a reply without tags never cleared an expired card. And the expired card drew no SKIP, so it could not be dismissed.
- **verification:** `grep -n "dropStaleFood();" lib/features/ai_coach/providers/ai_coach_provider.dart` (4 hits after the fix)
- **suggested-fix:** sweep on every reply and give the expired card a SKIP.
- **status:** accepted. The expired card keeps SKIP (`coach_food_card_skip`). The public `dropStaleFood()` runs before the tag guard on the media, send and auth-retry paths, and still runs in `addActions`. Tests "B-pass F1" (3); mutants M16, M17 red.

## Finding 2 — P3 — writer_reader_drift / guard_without_its_mirror
- **file:line:** log_confirm_card.dart `_buildFoodCard`, ai_coach_provider.dart `_parse`, conversational_log_handler.dart `_logFood`, tool_dispatcher.dart `_executeLogMealByText`
- **claim:** `data['meal_type'] as String?` throws on a number or a list from model JSON; the tool card was hardened, the tag sites were not.
- **verification:** `git grep -n "meal_type'\] as String" -- lib/features/ai_coach` (0 hits after the fix)
- **suggested-fix:** `m is String ? m : null` at every site.
- **status:** accepted. A single `coachMealTypeOf` now serves all five coach sites, including the tool card. Tests "B-pass F2" pure and widget; mutant M18 red.

## Finding 3 — P3 — writer_reader_drift
- **file:line:** lib/features/ai_coach/services/coach_meal_log.dart `coachItemsFromTag`
- **claim:** a listed food with unusable calories is skipped silently; a missing `quantity_g` becomes 100 g.
- **verification:** read `_tagListItem` and `coachTagUnusableItemCount`
- **suggested-fix:** telemetry on a partial parse; optionally drop the grams default.
- **status:** accepted (telemetry). `_parse` logs `coach_food_tag_items_partial` with the skipped count. The 100 g default stays: the tool path uses the same sentinel (`coachItemsFromParsedMeal`), and the card shows the grams the user can see. Tests "B-pass F3" and the F2/F3 widget test; mutant M19 red.

## Finding 4 — P3 — blast_radius_mismatch (copy drift)
- **file:line:** supabase/functions/_shared/tools/nutrition/logMealByText.ts (description), _shared/write_claim_prompt.ts `applyWriteClaimDescriptions`
- **claim:** with `DISABLE_WRITE_CLAIM_RULE` on and the meal rule on, the model is told food goes through `logMealByText` while its description promises a 5-second auto-confirm.
- **verification:** `deno test ... _shared/tool-loop_write_claim_note_test.ts` (the F4 test)
- **suggested-fix:** accept, or fix the description.
- **status:** accepted (fixed). `runToolLoop` takes `mealItemsRule` (`ai-proxy` passes `mealOn`). With the write-claim rule off and the meal rule on, only the card sentence is rewritten. With the meal rule off, the function returns the input array itself, byte-identical. Tests in `write_claim_prompt_test.ts`, `tool-loop_write_claim_note_test.ts` and the wiring pin; mutants M20, M21 red.

## Clean lenses (reviewer's record, summarised)
- Totals: the tag card and the tool card compute the same total as the stored `nlog_` row for items-only, flat-only and mixed payloads, with override 0, null, negative, NaN or a string. Every `sot_registry.yaml` cite into the changed files was re-read and found right. After the fix commit, 8 shifted cites were re-mapped and spot-checked.
- No `.invoke(`, no added `unawaited(` apart from the F3 event, which is `ErrorTelemetry.logEvent` (never throws). No credential literal, no `fromEnvironment`.
- The server kill switch is exactly "true". Every `.replace` anchor appears exactly once (Deno test). OFF is byte-identical in both write-claim states (goldens).

## Founder triage notes
Platform tier, advisory verdict, so the author triaged. No finding reverses a founder decision.

## Tuning entry
- **2026-11-26** - blast-radius platform - 4 findings; 0 false_alarm; tuning: the brief listed the plan's rejected alternatives and the founder decisions, and no finding re-opened one. The P2 came from asking the guard's call sites (lens 6, "follow the return value") rather than the guard itself: the sweep was correct, its only caller was gated.
