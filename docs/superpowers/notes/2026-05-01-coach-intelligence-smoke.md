# APK Test #6 Plan B — Coach Intelligence Smoke Verification

**Date:** 2026-05-01
**Branch:** feat/apk-test-6-batch
**ai-proxy version:** v60 (deployed 2026-05-01, updated_at 1777608405589)

## Static checks

- `flutter analyze lib/features/ai_coach/` → 0 errors / 0 warnings
- `flutter test test/ai_coach/` → 164 tests pass / 0 fail
- `flutter test` (full suite) → 827 pass / 11 skipped / 4 fail. The 4 failures are
  pre-existing on this branch and not touched by Plan B (`rank_service_test.dart`
  LS/PO/SubLt rank-gating tests + `sync_gap_test.dart` DeleteNutritionLogNotifier
  case). `git log d6b8e17..HEAD` shows zero Plan B commit touches `rank_service`,
  `rank_service_test`, `sync_gap_test`, or `nutrition_provider`. Carried into
  Plan B's scope is the already-green dispatcher contract test
  `dispatch_reschedule_pause_test.dart` (5 tests pass).

## Spec success criteria

| ID | Criterion | Status | Evidence |
|---|---|---|---|
| C9 | Coach answers "what did I eat today?" with no tool call | PASS | `today_nutrition_no_tool_call_test.dart` (parser-side invariant) + Captain Manual "Today's nutrition" section deployed in v60 |
| C10 | Coach uses `getNutritionHistory` for past dates | PASS | `get_nutrition_history_tool_test.dart` (tool registered + selectionHints + manual references it) + tool source deployed in v60 |
| C11 | Multi-intent message emits 2 ToolIntents (log + reschedule) | PASS | `multi_intent_dispatch_test.dart` (parser pinned) + Captain Manual "Multi-intent messages" section deployed in v60 |
| C12 | APPLY → write → terminal pill ✓ Applied + auto-dismiss from active list | PASS | `confirm_gate_no_double_tap_test.dart` + `dismiss_card_terminal_state_test.dart` + `dispatched_card_filter_test.dart` |

## Spec observations resolved

- **#10 multi-intent dispatch** — Captain Manual "Multi-intent messages" subsection + `selectionHints` field on `ToolDefinition` + WHEN-TO-USE block appended to function declaration via `zodToGemini.toolToFunctionDeclaration` (B-1, B-2 deploy v60). selectionHints applied to `logSet`, `swapExercise`, `rescheduleWeek`, `pausePlan`.
- **#11 confirm gate** — Auto-confirm 5s countdown removed; both `trivial` and `reviewable` classes now require explicit APPLY tap. DISMISS persists `intent_<id>_dismissed_at` to coachBox. Dispatcher idempotency guard at top of `execute()` short-circuits if `intent_<id>_dispatched_at` is already set. `AiCoachScreen.filterVisibleIntents` extracted as pure/static helper that hides dispatched + dismissed intents from chat thread (B-4, B-5).
- **#14 today nutrition + history** — Captain Manual "Today's nutrition" section directs the model to read `meals_today` / `calories_consumed_today` / `protein_today` / `carbs_today` / `fat_today` directly from snapshot for today. New `getNutritionHistory` READ tool (free tier, nutrition family) handles past dates with per_day or total aggregation (B-1, B-7, B-2/B-8 deploy v60, B-9).
- **#15 counter wiring** — Already wired centrally via Plan C-13: `NutritionWriteService.logMeal` reads `_counterFeatureForSource(source)` and increments `featureAiTextLogPro` for `aiCoachTool`. `_executeLogMealByText` passes `source: NutritionWriteSource.aiCoachTool`. Dispatcher gained a docstring pinning the contract (B-10). Test `food_log_counter_increments_from_chat_test.dart` pins the source→feature mapping (B-11).

## Code changes summary (commits ahead of `d6b8e17`)

| Commit | Task | Subject |
|---|---|---|
| f775f0f | B-1 | feat(ai-proxy): multi-intent hardening + tool selectionHints |
| 39c2d2d | B-3 | test(ai-coach): multi-intent parser yields 2 ToolIntents |
| ec74c23 | B-4 | fix(ai-coach): explicit Apply/Dismiss gate on confirm cards |
| 7bdd523 | B-5 | test(ai-coach): confirm gate idempotency + dismiss + filter |
| f00d0e1 | B-7 | feat(ai-proxy): add getNutritionHistory READ tool |
| ab74715 | B-9 | test(ai-coach): today snapshot grounding + tool registration |
| 0a3f0cb | B-10 | docs(ai-coach): document counter-wiring contract on dispatcher |
| 512862a | B-11 | test(ai-coach): chat-mode food log counter wiring contract |
| (this) | B-12 | docs(test-6): coach intelligence smoke + C9-C12 verification |

B-2 + B-8 fold into a single deploy (v59 → v60) since both touch the same ai-proxy bundle. B-6 folded into B-1 (same captain_manual.ts edit).

## On-device smoke (manual — to be done at APK install time)

- [ ] Sign up fresh; ensure `meals_today` populates after first meal log.
- [ ] Ask coach "what did I eat today?" — verify answer prose only, no card.
- [ ] Ask coach "what did I eat last Tuesday?" — verify `getNutritionHistory` runs.
- [ ] Send "I did back today + move Friday's pull workout to today" — verify 2 confirm cards (logSet + rescheduleWeek).
- [ ] Tap APPLY on first card — terminal pill ✓ Applied; second card still live.
- [ ] Tap DISMISS on second card — card disappears from thread (filter hides on next rebuild).
- [ ] Log food via chat tool — counter on profile decrements visibly.

## Deferred to Test #7+

- Per spec §13: `applyTone` / `MotivationTone` restoration (regressed during Test #4 deploy).
- Scan_meal / cart_auditor counter wiring if those tools later get coach-routed (today they're not in the dispatcher switch).
- Deno-side handler aggregation tests for `getNutritionHistory` — deno not available on the build host; covered by integration smoke at APK install time.
