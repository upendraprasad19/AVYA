---
bug_id: b7f3e2
date: 2026-09-27
batch: reuse-audit-fixes (unit 2a — template-stable-identity, OI-252) — surfaced while merging
status: fixed
blast_radius: platform
symptom: |
  The `main` push (after merging `template-stable-identity`) ran the full
  `flutter test` suite under `scripts/pre-push.sh` and hit one failure:
  `test/widgets/log_food_sheet_search_respects_locked_slot_test.dart` —
  "Search tab logs to the locked slot, not time-of-day inference" — reported
  `[E]` with:
    The following UnmountedRefException was thrown running a test (but after
    the test had completed): Cannot use the Ref of
    NotifierProvider<FoodLogNotifier, void>#... after it has been disposed.
    #1 Ref.invalidate ... #2 FoodLogNotifier.logFood
    (nutrition_provider.dart:1076) #3 _SearchResultsList.build...
    (search_mode_body.dart:204)
  The test's own assertions had already passed — the exception fired async,
  after test completion, and only under full-suite concurrent execution (a
  direct, isolated re-run of the file passed cleanly, consistent with a
  timing-dependent race rather than a deterministic failure).

  UPDATE (same day, self-triggered B-pass on the merge that landed the
  initial single-site fix — `docs/reviews/merge-reconciliation-82844bfd-review.md`,
  Finding 2): the single-site fix left **6 more call sites in the SAME
  file** with the structurally identical shape — an async write/network
  call followed by `ref.invalidate(...)` / `ref.invalidateSelf()` with no
  `ref.mounted` check: `FoodLogNotifier.deleteFoodLog` (reachable from the
  meal-list swipe-to-delete gesture, 30 lines below the original fix),
  `SavedMealsNotifier.saveMealPreset`, `SavedMealsNotifier.relogSavedMeal`,
  `SavedMealsNotifier.deleteSavedMeal`, `ScanMealNotifier.scanImage`, and
  `CartAuditorNotifier.analyseCart`. This promotes the bug from a single
  instance to a recurring pattern within this one file — all 7 sites are
  now fixed with the identical guard.
concept: food_log_provider_invalidation
sot_registry_entry: not_applicable — a provider-lifecycle safety gap, not a writer/reader field contract
writers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "FoodLogNotifier.logFood — after awaiting NutritionWriteService.instance.logMeal(...), unconditionally called ref.invalidate(weeklyNutritionProvider) with no check that this Notifier's ProviderContainer was still mounted", line: 1076 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "FoodLogNotifier.deleteFoodLog — after awaiting NutritionWriteService.instance.deleteLog(...), unconditionally called ref.invalidate(weeklyNutritionProvider)", line: 1112 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "SavedMealsNotifier.saveMealPreset — after awaiting NutritionWriteService.instance.saveMealPreset(...), unconditionally called ref.invalidateSelf()", line: 1220 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "SavedMealsNotifier.relogSavedMeal — after awaiting NutritionWriteService.instance.relogSavedMeal(...), unconditionally called ref.invalidateSelf()", line: 1251 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "SavedMealsNotifier.deleteSavedMeal — after awaiting NutritionWriteService.instance.deleteSavedMeal(...), unconditionally called ref.invalidateSelf()", line: 1258 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "ScanMealNotifier.scanImage — after awaiting SupabaseService.instance.callFunction(...), unconditionally called ref.invalidate(scanMealRemainingProvider)", line: 1417 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "CartAuditorNotifier.analyseCart — after awaiting SupabaseService.instance.callFunction(...) and a further await on the usage-counter increment, unconditionally called ref.invalidate(cartAuditorRemainingProvider)", line: 1521 }
readers:
  - { file: lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart, method_or_widget: "_SearchResultsList.build — awaits FoodLogNotifier.logFood() and, when the calling sheet/widget tree has already been popped/disposed before that await resolves, the subsequent ref.invalidate call throws", line: 204 }
  - { file: lib/features/nutrition/widgets/todays_meals_card.dart, method_or_widget: "swipe-to-delete dismissible calling FoodLogNotifier.deleteFoodLog — same disposal-mid-flight risk", line: not_precisely_cited — call site not individually re-traced; guard applied at the writer per the established pattern }
  - { file: lib/features/nutrition/widgets/saved_meals_section.dart, method_or_widget: "quick-log / save / delete affordances calling SavedMealsNotifier's three async methods — same disposal-mid-flight risk", line: not_precisely_cited — call site not individually re-traced; guard applied at the writer per the established pattern }
  - { file: lib/features/nutrition/scan_meal_section.dart, method_or_widget: "scan capture flow calling ScanMealNotifier.scanImage — same disposal-mid-flight risk", line: not_precisely_cited — call site not individually re-traced; guard applied at the writer per the established pattern }
  - { file: lib/features/nutrition/cart_auditor_section.dart, method_or_widget: "cart audit flow calling CartAuditorNotifier.analyseCart — same disposal-mid-flight risk", line: not_precisely_cited — call site not individually re-traced; guard applied at the writer per the established pattern }
hive_key_prefix: not_applicable — no Hive involvement; provider-lifecycle bug only
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: "test/widgets/log_food_sheet_search_respects_locked_slot_test.dart (pre-existing; repairs the production code the test's own teardown was exposing) + test/contracts/nutrition_provider_ref_mounted_guard_test.dart (NEW — source-grep pinning ALL ref.invalidate/ref.invalidateSelf call sites in this file are ref.mounted-guarded; mutation-proven, see below)"
ist_handling: []
provider_invalidations: [weeklyNutritionProvider, scanMealRemainingProvider, cartAuditorRemainingProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no per-user data path touched; this is a Riverpod ref-lifecycle safety gap
forbidden_patterns_checked:
  - "guarding with a try/catch around ref.invalidate instead of ref.mounted — rejected: swallowing the exception would hide a genuine future misuse if the guard clause is ever accidentally removed; ref.mounted is Riverpod's own documented API for exactly this check and fails silently-but-correctly (skips the invalidate) rather than silently-but-wrongly (catches everything)."
proposed_fix: |
  Wrapped every `ref.invalidate(...)` / `ref.invalidateSelf()` call in this
  file that follows an `await` in `if (ref.mounted) { ... }`, matching the
  pattern Riverpod's own UnmountedRefException message recommends ("check
  `ref.mounted` after async gaps") — 7 sites total (1 originally fixed +
  6 found by the self-triggered B-pass on that fix). `BadgeService.instance
  .checkAll()` (FoodLogNotifier.logFood) is left unguarded — it is a plain
  singleton call with no `ref` involvement, so it cannot throw this
  exception and disposal state is irrelevant to it.
regression_test_planned:
  - "test/widgets/log_food_sheet_search_respects_locked_slot_test.dart itself is the regression test for the ORIGINAL site — it failed intermittently under full-suite concurrent execution before this fix (observed once, in the main push's full-suite log) and passed cleanly after (flutter test on the file directly: 3/3 green, 'All tests passed!'). The race is timing-dependent on full-suite concurrency and not reliably reproducible in isolation for any of the 7 sites, so no new BEHAVIORAL test was added for the 6 additional sites — matching this doc's own original accepted approach."
  - "test/contracts/nutrition_provider_ref_mounted_guard_test.dart (NEW) is the structural regression test covering all 7 sites plus any future addition: source-greps every ref.invalidate(...)/ref.invalidateSelf() call in the file and asserts the immediately-preceding code line is an `if (ref.mounted)` guard. MUTATION-PROVEN: removed the guard at SavedMealsNotifier.deleteSavedMeal (restoring the exact pre-fix line), re-ran — 1 of 2 tests reddened with the correct file:line and a message naming the exact unguarded call, the other (ref.invalidate lens) stayed green as expected since that mutation only touched an invalidateSelf site. Restored via file backup + diff-confirmed-clean afterward."
impact_analysis: |
  A user (or, in a test, a simulated interaction) that triggers any of these
  7 async nutrition-logging actions — log via Search, delete a food log via
  swipe, save/re-log/delete a saved meal, complete a scan-meal analysis, or
  complete a cart audit — and then leaves the screen (or the widget tree is
  otherwise disposed) while the underlying await is still in flight no
  longer throws an uncaught async exception when the pending call resumes.
  Each provider still invalidates normally on the common path (still
  mounted); only the disposed-mid-flight edge case now skips the invalidate
  instead of throwing. No change to any successful, still-mounted flow.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/features/nutrition/providers/nutrition_provider.dart -- 7 ref.mounted guards added (lines 1080, 1114, 1225, 1259, 1269, 1431, 1538 post-fix). flutter analyze lib/features/nutrition/providers/nutrition_provider.dart -> No issues found! (36.5s). flutter test test/widgets/log_food_sheet_search_respects_locked_slot_test.dart --reporter expanded -> All tests passed! (3/3). flutter test test/contracts/nutrition_provider_ref_mounted_guard_test.dart --reporter expanded -> All tests passed! (2/2), mutation-proven." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive read/write in any of the 7 changed lines." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema touched." }
---

## Summary

`FoodLogNotifier.logFood` called `ref.invalidate(weeklyNutritionProvider)`
unconditionally after an `await`, with no check that the notifier's provider
container was still mounted — a documented Riverpod anti-pattern that throws
`UnmountedRefException` when the caller's widget tree is disposed while the
awaited write is still in flight. Surfaced only under full-suite concurrent
execution, first visible on this machine because this was the first
Windows-local full-suite run since the touching commit (`86f0c487`,
`single-owner-a` batch, 2026-09-26) landed on `main`. Fixed by adding the
`ref.mounted` guard Riverpod's own exception message recommends.

A self-triggered B-pass on that single-site fix
(`docs/reviews/merge-reconciliation-82844bfd-review.md`, Finding 2 —
`guard_without_its_mirror`) found the identical unguarded shape at 6 more
call sites in the same file, none reviewed or fixed by the original commit.
All 7 are now fixed with the same guard, and a new structural regression
test (`test/contracts/nutrition_provider_ref_mounted_guard_test.dart`,
mutation-proven) pins the pattern across the whole file so a future
unguarded addition is caught mechanically rather than by luck of a
full-suite race.
