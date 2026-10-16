---
bug_id: bae4dd
date: 2026-09-28
batch: reps-secs-invalidation-fixes
status: fixed
blast_radius: account
symptom: |
  Found during the same-batch audit the founder requested ("check where
  all should be using invalidation etc, in the app — possible areas where
  we might have missed it?"), triggered by the confirmed streakFreezeProvider
  gap (bug 9c8958). weeklyNutritionProvider — the weekly calories/protein
  chart + averages on the Nutrition screen — is invalidated on every meal
  log (NutritionWriteService.logMeal) but was NEVER invalidated by
  DayRolloverObserver. A week-boundary crossing (Sunday→Monday) while the
  provider was already cached would leave the weekly chart/avg pinned to
  the OLD week's data until an unrelated invalidation or app restart —
  same shape as 9c8958, different provider, not founder-observed directly
  but confirmed present by code + a reproducing behavioral test before
  being counted as a confirmed bug (per the audit's own no-false-positive
  discipline — two OTHER candidates the same audit fork flagged were
  independently verified and ruled OUT, not included here).
concept: day_rollover_provider_invalidation
sot_registry_entry: |
  day_rollover_provider_invalidation — extends the EXISTING concept
  (docs/sot_registry.yaml:1390), same as bug 9c8958's doc.
  weeklyNutritionProvider is simply a second omission from the same
  invalidation set.
writers:
  - { file: lib/core/services/day_rollover_service.dart, method_or_widget: "_doRolloverWithRef — new invalidate call", line: 234 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "logFood — calls NutritionWriteService.logMeal then invalidates weeklyNutritionProvider itself (already-correct, pre-existing)", line: 1081 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "WeeklyNutritionNotifier.build()", line: 1657 }
  - { file: lib/features/nutrition/screens/nutrition_screen.dart, method_or_widget: "weekly chart render — ref.watch(weeklyNutritionProvider)", line: 239 }
hive_key_prefix: "nlog_* (nutritionBox)"
hive_key_formula: "nlog_${istDateStr(date)}_${hashCode}"
sync_methods:
  - "NutritionWriteService.logMeal → unawaited(syncNutritionData())"
restore_methods:
  - "sync/sync_nutrition.dart (_restoreNutritionLogs — unaffected by this fix; weeklyNutritionProvider recomputes from whatever is in nutritionBox at build time, restored or locally-logged alike)"
cloud_table: nutrition_logs
cloud_columns:
  - total_calories
  - total_protein
  - date
ist_handling:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "WeeklyNutritionNotifier.build() weekStart — uses raw DateTime.now(), NOT the istDateStr/istMidnight seam (pre-existing, out of scope for this fix)", line: 1665 }
provider_invalidations:
  - weeklyNutritionProvider
telemetry_op_types:
  success:
    - day_rollover_all_providers_invalidated
  failure: []
cross_account_guard: "wrapUserScopedBox ensures per-user Hive isolation; WeeklyNutritionNotifier resets on auth change via ref.watch(authUserIdTokenProvider). Not affected by this fix."
forbidden_patterns_checked:
  - { pattern: "WeeklyNutritionNotifier.build() performing a write (write-on-read anti-pattern)", absent: true }
proposed_fix: |
  Add `ref.invalidate(weeklyNutritionProvider);` to
  `DayRolloverObserver._doRolloverWithRef`, alongside `waterIntakeProvider`
  and the other nutrition-domain daily providers already invalidated
  there. `WeeklyNutritionNotifier.build()` always recomputes `weekStart`
  fresh from `DateTime.now()` — unlike bug 9c8958, there is no possibility
  of a stale WRITE; this is purely a missing REBUILD trigger. The provider
  is already correctly invalidated on every meal log
  (`nutrition_provider.dart:1081` and `:1115`) — the gap is
  specifically the rollover path, which never touched it.
contract_test_path: test/contracts/day_rollover_provider_invalidation_behavioral_test.dart
regression_test_planned: |
  - test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart
    (source-grep, PRESENCE only): asserts 'weeklyNutritionProvider' appears
    in day_rollover_service.dart.
  - test/contracts/day_rollover_provider_invalidation_behavioral_test.dart
    (BEHAVIORAL — canonical behavioral_test_path for this concept, Test E):
    clears nutritionBox, reads weeklyNutritionProvider (caches
    avgCalories=0), writes a new log entry directly to nutritionBox for
    "today" (same DateTime.now() clock the notifier's own weekStart math
    uses, avoiding any device-timezone-vs-IST skew — orthogonal to the
    invalidation gap under test), re-reads without invalidation (still 0
    — proves staleness), calls runRolloverNow, re-reads again and asserts
    avgCalories now reflects the 850-calorie entry.
  Mutated and run: commenting out the new
  ref.invalidate(weeklyNutritionProvider) line reddened Test E with
  `Expected: <850>, Actual: <0.0>`.
impact_analysis: |
  Scoped to: the weekly calories/protein chart + averages +
  `isPartialWeek` flag on the Nutrition screen staying pinned to
  pre-rollover data until an unrelated invalidation (a meal log, which
  DOES already invalidate it) or app restart.

  No impact on:
  - Daily nutrition figures (dailyNutritionProvider) — already correctly
    invalidated on rollover, untouched by this fix.
  - Meal-log-triggered invalidation — already correct, untouched.
  - Any other provider in the invalidation list.

  Lower real-world severity than 9c8958: a meal log on the new week
  ALREADY invalidates this provider as a side effect, so the stale window
  only matters for a user who opens the Nutrition tab on a new week
  BEFORE logging anything that week — narrower than 9c8958, which has no
  such incidental self-healing path. Included in this batch anyway per
  the founder's explicit "check where all should be using invalidation...
  possible areas we might have missed it" request and this repo's
  no-deferrals discipline (CLAUDE.md §4.2) — a confirmed gap, however
  narrow its window, is fixed in the same batch it's found in, not
  tagged lower-priority.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "day_rollover_service.dart now invalidates weeklyNutritionProvider in _doRolloverWithRef. Mutation-proven: commenting out the new line reddened Test E (Expected 850, Actual 0.0)." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "WeeklyNutritionNotifier.build() reads nutritionBox correctly on every fresh build — confirmed by Test E's post-rollover assertion, which reads the SAME entry the pre-rollover cached build could not see." }
---

## Summary

`weeklyNutritionProvider` (the Nutrition screen's weekly chart + averages)
was never invalidated by `DayRolloverObserver`, unlike its daily
counterpart `dailyNutritionProvider`. Found via the founder-requested
audit of the app's invalidation coverage, following the streakFreezeProvider
bug (9c8958) in the same conversation.

## Root Cause

Writer: `WeeklyNutritionNotifier.build()` (`nutrition_provider.dart:1657`)
already correctly recomputes `weekStart` from `DateTime.now()` on every
build — there is no stale-write component to this bug at all.

Reader-invalidation gap: `DayRolloverObserver._doRolloverWithRef`
(`day_rollover_service.dart`) invalidates `dailyNutritionProvider`,
`waterIntakeProvider`, `recentFoodLogsProvider` and others in its
nutrition-domain block, but never `weeklyNutritionProvider` — a plain
omission, not a stale-name drift (grepping the invalidation list for the
literal string confirms it was simply absent).

## Fix

`ref.invalidate(weeklyNutritionProvider);` added to `_doRolloverWithRef`,
day_rollover_service.dart:234.

## Related

Same missing-invalidation class as bug 9c8958 (streakFreezeProvider),
found in the same audit and fixed in the same batch/commit — see that
diagnose-doc for the general "Riverpod cache has no automatic dependency
tracking on a raw Hive read" design-gap discussion, and for the SEPARATE
foreground-midnight-timer design gap this batch also addresses (a `feat`,
not a `fix` — no diagnose-doc of its own per CLAUDE.md rule 22's
`^(fix|bug|regression)` commit-type scope, but tested at
`test/contracts/day_rollover_midnight_timer_test.dart`).

Two other candidates the founder-requested audit's investigating fork
flagged as possible instances of this same class were independently
checked and RULED OUT before being counted here (per CLAUDE.md's
"Master Audit / multi-agent surveys produce false-positive findings"
pitfall — never apply a multi-agent finding without reading the cited
file:line + verifying live state first): `WeightHistoryNotifier`
(home_provider.dart) and `UserStatsNotifier` (profile_provider.dart) were
both confirmed to already have correct invalidation paths independent of
`DayRolloverObserver`, so including them here would have been a false
positive, not a third confirmed bug.
