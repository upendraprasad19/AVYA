---
bug_id: b7f3e2
date: 2026-09-27
batch: reuse-audit-fixes (unit 2a — template-stable-identity, OI-252) — surfaced while merging
status: fixed
blast_radius: feature
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
  timing-dependent race rather than a deterministic failure). Ruled out as a
  consequence of this batch's own migration-number collision (OI-255) or the
  Windows path-separator fix (d4a7c1) — neither touches nutrition code.
  `git log` on `nutrition_provider.dart` traces the touched region to
  `86f0c487` ("fix: saved-meal use count, sign-up referral code, custom-
  exercise create path"), landed on `main` via the `single-owner-a` batch
  2026-09-26 — unrelated to and pre-dating this merge; this is the first
  Windows-local full-suite run since that batch landed.
concept: food_log_provider_invalidation
sot_registry_entry: not_applicable — a provider-lifecycle safety gap, not a writer/reader field contract
writers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "FoodLogNotifier.logFood — after awaiting NutritionWriteService.instance.logMeal(...), unconditionally called ref.invalidate(weeklyNutritionProvider) with no check that this Notifier's ProviderContainer was still mounted", line: 1076 }
readers:
  - { file: lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart, method_or_widget: "_SearchResultsList.build — awaits FoodLogNotifier.logFood() and, when the calling sheet/widget tree has already been popped/disposed before that await resolves, the subsequent ref.invalidate call throws", line: 204 }
hive_key_prefix: not_applicable — no Hive involvement; provider-lifecycle bug only
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: "test/widgets/log_food_sheet_search_respects_locked_slot_test.dart (pre-existing; this fix repairs the production code the test's own teardown was exposing, not the test itself)"
ist_handling: []
provider_invalidations: [weeklyNutritionProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no per-user data path touched; this is a Riverpod ref-lifecycle safety gap
forbidden_patterns_checked:
  - "guarding with a try/catch around ref.invalidate instead of ref.mounted — rejected: swallowing the exception would hide a genuine future misuse if the guard clause is ever accidentally removed; ref.mounted is Riverpod's own documented API for exactly this check and fails silently-but-correctly (skips the invalidate) rather than silently-but-wrongly (catches everything)."
proposed_fix: |
  Wrapped `ref.invalidate(weeklyNutritionProvider)` in `if (ref.mounted)`,
  matching the pattern Riverpod's own UnmountedRefException message
  recommends ("check `ref.mounted` after async gaps"). `BadgeService.instance
  .checkAll()` is left unguarded — it is a plain singleton call with no `ref`
  involvement, so it cannot throw this exception and disposal state is
  irrelevant to it.
regression_test_planned:
  - "test/widgets/log_food_sheet_search_respects_locked_slot_test.dart itself is the regression test — it failed intermittently under full-suite concurrent execution before this fix (observed once, in the main push's full-suite log) and passed cleanly after (flutter test on the file directly: 3/3 green, 'All tests passed!'). No new test added: the race is timing-dependent on full-suite concurrency and not reliably reproducible in isolation, so an isolated pass/fail is necessary evidence but not sufficient proof by itself — the stronger evidence is the next full-suite push run, tracked in this batch's own retrospective."
impact_analysis: |
  A user (or, in the test, a simulated interaction) that logs food via the
  Search tab and then leaves the screen (or the widget tree is otherwise
  disposed) while `NutritionWriteService.instance.logMeal` is still
  in-flight no longer throws an uncaught async exception when the pending
  `logFood` call resumes. The weekly nutrition provider still invalidates
  normally on the common path (still mounted); only the disposed-mid-flight
  edge case now skips the invalidate instead of throwing. No change to any
  successful, still-mounted logging flow.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/features/nutrition/providers/nutrition_provider.dart:1076 edited (ref.mounted guard added). flutter test test/widgets/log_food_sheet_search_respects_locked_slot_test.dart --reporter expanded -> All tests passed! (3/3)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive read/write in the changed lines." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema touched." }
---

## Summary

`FoodLogNotifier.logFood` called `ref.invalidate(weeklyNutritionProvider)`
unconditionally after an `await`, with no check that the notifier's provider
container was still mounted — a documented Riverpod anti-pattern that throws
`UnmountedRefException` when the caller's widget tree is disposed while the
awaited write is still in flight. Surfaced only under full-suite concurrent
execution (a timing race), first visible on this machine because this was
the first Windows-local full-suite run since the touching commit
(`86f0c487`, `single-owner-a` batch, 2026-09-26) landed on `main`. Fixed by
adding the `ref.mounted` guard Riverpod's own exception message recommends.
