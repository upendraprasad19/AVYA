---
bug_id: e6c2a9
date: 2026-09-18
batch: Task 4 (C4) — ai-coach-ux-tool-integrity spec 2026-09-18
tier: s_fix
status: fixed
blast_radius: account
symptom: |
  Tool-integrity audit (2026-09-18, spec docs/superpowers/specs/2026-09-18-ai-coach-ux-tool-integrity-design.md)
  found that after the AI coach logs a meal from chat (log_meal_by_text), the
  Nutrition tab's "X remaining" AI-text-log read goes stale: the coach path
  increments UsageCounterService.featureAiTextLogPro, but the dispatcher's
  _invalidateNutritionProviders never invalidated aiTextLogRemainingProvider.
  The MANUAL path (LogFood sheet AI tab) invalidates the same provider right
  after its increment (food_logger_section.dart:92), so the display refreshes
  there but not after a coach log. Writer/reader drift by omission — same
  reader, two writers, one never refreshed it.
concept: nutrition_ai_text_log_remaining
sot_registry_entry: null
writers:
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executeLogMealByText (UsageCounterService.increment featureAiTextLogPro), line: 1521 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: aiTextLogRemainingProvider (decl :1548), line: 1548 }
  - { file: lib/features/nutrition/widgets/food_logger_section.dart, method_or_widget: food_logger_section ref.watch(aiTextLogRemainingProvider), line: 103 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/coach_meal_log_invalidates_remaining_test.dart
ist_handling:
  - "No date surface touched — the counter and its remaining() read are UsageCounterService internals already IST-keyed; this fix only refreshes a Riverpod read."
provider_invalidations:
  - { provider: aiTextLogRemainingProvider, added_in_this_batch: true, reason: "Coach meal path increments featureAiTextLogPro; the 'X remaining' read must rebuild exactly as it does after the manual path's increment." }
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — no new Hive key or cloud column; invalidation-only change on an existing provider read.
forbidden_patterns_checked:
  - { pattern: "over-invalidation: the provider is invalidated after EVERY tool dispatch, not only meal logs", absent: false }
proposed_fix: |
  In _invalidateNutritionProviders (tool_dispatcher.dart), after the
  macroTargetsProvider block, add ref.invalidate(aiTextLogRemainingProvider)
  in the same try/catch pattern as its siblings, and add the provider to the
  show clause of the nutrition_provider.dart import. Mirrors the manual path's
  invalidation so both writers of the counter refresh the same reader.
regression_test_planned:
  - test/contracts/coach_meal_log_invalidates_remaining_test.dart
impact_analysis: |
  One extra provider invalidation in the dispatcher's existing post-write tail.
  The provider build body is a pure UsageCounterService read (nutrition_provider.dart:1548-1556),
  so the rebuild cost is a counter lookup. No writer changes, no Hive key
  changes, no schema changes. No over-invalidation concern beyond the existing
  pattern — the tail already invalidates 5 nutrition providers on the same
  dispatch.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "tool_dispatcher.dart: show-clause import + invalidate block added; flutter analyze lib/: 45 pre-existing infos elsewhere, zero issues in tool_dispatcher.dart." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "n/a to the defect but the counter's Hive state was verified read correctly: UsageCounterService.increment + remaining() round-trip is pinned by test/contracts/usage_counter_service_race_behavioral_test.dart and the seed test aiTextLogRemainingProvider exists in nutrition_provider.dart:1548; the defect was purely the missing Riverpod refresh." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change — the daily cap enforcement stays server-side (migration 024 trigger, untouched)." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "No wire change: the fix alters only a client-side Riverpod invalidation; ai-proxy request/response shape untouched." }
mutation_proven:
  mutated: "sed replaced `ref.invalidate(aiTextLogRemainingProvider);` with a comment (the exact pre-fix defect), confirmed applied by grep count 1 -> 0"
  result: "1 of 3 tests reddened — the _invalidateNutritionProviders pin; the import and provider-exists pins stayed green, correctly"
  confirmed_applied: "grep -c returned 0 post-mutation (the removed token), failure observed in run output (compile-clean)"
---

## Summary

The AI coach's meal-log tool path and the manual LogFood path write the SAME
visible counter (`featureAiTextLogPro`) but refreshed different provider sets.
The coach path's invalidation tail (`_invalidateNutritionProviders`) covered
daily/weekly/summary/recent/macro providers but never
`aiTextLogRemainingProvider`, so the Nutrition tab's "X remaining" chip kept
showing the pre-coach-log value until some other invalidation happened to
fire.

## Root cause

`_executeLogMealByText` (tool_dispatcher.dart) increments the counter via
`UsageCounterService.increment(AppConstants.featureAiTextLogPro, …)` and then
fires `_invalidateNutritionProviders(ref)` — but that method's invalidation
set was copied from FoodLogNotifier.logFood's set (its own header comment
says so) and the manual path's `aiTextLogRemainingProvider` invalidation
lives in food_logger_section.dart:92, OUTSIDE that copied set. Same reader
(nutrition_provider.dart:1548), two writers, one never refreshed it — the
recurring writer/reader-drift class.

## Fix

`_invalidateNutritionProviders` (tool_dispatcher.dart, after the
macroTargetsProvider block): `ref.invalidate(aiTextLogRemainingProvider)` in
the same independently-try/caught pattern as its siblings, plus the provider
added to the show clause of the nutrition_provider.dart import. The manual
path needed no change.

## Verification

- RED phase: 2 of 3 new tests failed — the method-body pin (invalidate
  absent) and the show-clause import pin. The provider-existence test passed
  (pins the reader exists at the declared path).
- GREEN phase: 3/3 after the fix; meal-log-related files green
  (conversational_log_handler_uses_write_service_test,
  counter_increment_on_analyse_test, food_log_counter_increments_from_chat_test,
  logMeal_increments_counter_per_source_test — 25 tests total).
- Mutation-proof: removed the invalidate line (grep count 1→0, confirmed
  applied), the body pin reddened; reverted, all green.
- `flutter analyze lib/` — 45 pre-existing infos elsewhere; zero issues in
  tool_dispatcher.dart.

## Behavioral-layer note (implementer, 2026-09-18)

The plan preferred a behavioral test asserting
`ref.read(aiTextLogRemainingProvider)` reflects the decrement after a coach
meal log. No existing harness drives ToolDispatcher with a ProviderContainer:
construction requires live Hive boxes, SubscriptionService and the full write
service stack — the exact intractability
conversational_log_handler_uses_write_service_test.dart's header documents
for the same service. All existing dispatcher meal-log tests are source-grep
(counter_increment_on_analyse_test pins the increment the same way). The
wiring pin alone ships here, per the plan's stated fallback, and is stated
explicitly.

## Custom-exercise half — verified_clean

Task 4 also asked whether a Riverpod provider holds a custom-exercise list
that the coach's createCustomExercise tool leaves stale. Grep found NO
provider under lib/features/train/providers/, lib/shared/ or
lib/features/train/widgets/ holding custom exercises
(`customExercise.*provider` → 0 hits): ExerciseSwapSheet._loadExercises
(exercise_swap_sheet.dart:80-86) re-reads
`ExerciseRepository.instance.getCustomExercises()` from Hive in initState on
EVERY sheet open. No stale-provider surface exists; no code changed for this
half.

## Related bugs

- Task 1 (C1, same batch, `c1a9d4`) — same batch's writer/reader-drift-by-
  omission class on a different reader set.
