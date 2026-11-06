---
bug_id: b1bfea
date: 2026-09-28
batch: reps-secs-invalidation-fixes
status: fixed
blast_radius: account
symptom: |
  Found during plan-review round 1 of this same batch (context-blind,
  independent review of the streakFreezeProvider/weeklyNutritionProvider
  fixes and the founder-requested invalidation audit), while independently
  verifying a DIFFERENT finding the review raised about `UserStatsNotifier`
  (that finding was checked and RULED OUT — see Related below). The
  reviewer separately flagged `weeklyReportDataProvider` (Profile PRO
  Weekly Report card's 4-up sparkline: weight/calories/protein/workouts)
  as "never invalidated anywhere, identical bug shape" to the two
  confirmed bugs already in this batch. Not founder-observed directly —
  confirmed present by code before being counted as a bug, per this
  repo's no-false-positive discipline.
concept: day_rollover_provider_invalidation
sot_registry_entry: |
  day_rollover_provider_invalidation — extends the EXISTING concept
  (docs/sot_registry.yaml:1390). Also updates the weekly_report_data
  concept's own reader note (docs/sot_registry.yaml, WeeklyReportCard
  reader entry), which had already flagged "invalidate manually if real-time
  refresh needed" as a KNOWN gap but nobody had actually wired it.
writers:
  - { file: lib/core/services/day_rollover_service.dart, method_or_widget: "_doRolloverWithRef — new invalidate call", line: 254 }
readers:
  - { file: lib/features/profile/providers/weekly_report_data_provider.dart, method_or_widget: "WeeklyReportDataNotifier.build()", line: 43 }
  - { file: lib/features/profile/widgets/weekly_report_card.dart, method_or_widget: "WeeklyReportCard build — sole consumer, ref.watch(weeklyReportDataProvider)", line: 40 }
hive_key_prefix: "weight_*/healthBox, nutritionBox raw values, workoutBox wlog_* keys"
hive_key_formula: "N/A — provider scans ALL box values for the last-7-IST-days date window, not a single key"
sync_methods:
  - "N/A — pure local Hive read, no sync fan-out of its own"
restore_methods:
  - "N/A — reads whatever is already in healthBox/nutritionBox/workoutBox at build time, restored or locally-logged alike"
cloud_table: "N/A — client-only aggregation over already-synced local data"
cloud_columns: []
ist_handling:
  - { file: lib/features/profile/providers/weekly_report_data_provider.dart, method_or_widget: "WeeklyReportDataNotifier._fmt — istDateStr(d), correct", line: 118 }
provider_invalidations:
  - weeklyReportDataProvider
telemetry_op_types:
  success:
    - day_rollover_all_providers_invalidated
  failure: []
cross_account_guard: "wrapUserScopedBox ensures per-user Hive isolation; WeeklyReportDataNotifier resets on auth change via ref.watch(authUserIdTokenProvider). Not affected by this fix."
forbidden_patterns_checked:
  - { pattern: "WeeklyReportDataNotifier.build() performing a write (write-on-read anti-pattern)", absent: true }
proposed_fix: |
  Add `ref.invalidate(weeklyReportDataProvider);` to
  `DayRolloverObserver._doRolloverWithRef`, alongside the other daily/
  weekly providers already invalidated there. This is the ROLLOVER leg
  only — unlike weeklyNutritionProvider (bug bae4dd, same batch), which
  already had write-time invalidation via `nutrition_provider.dart`'s
  `logFood` and was only missing this leg, weeklyReportDataProvider had
  NO invalidation at all (confirmed: `grep -rn weeklyReportDataProvider
  lib/` found zero `ref.invalidate` call sites anywhere before this fix).
  The write-time leg (invalidate on a new weight/meal/workout log, so the
  sparkline reflects a log made TODAY without waiting for tomorrow's
  rollover) is a materially larger fix spanning 3 domains and 15+ raw
  call sites — `HealthWriteService.logWeight`, `NutritionWriteService.
  logMeal` and `WorkoutWriteService.markCompleted` are plain service
  methods with no `WidgetRef`, so the invalidation has to be added at each
  Riverpod-layer wrapper around them, not inside the services themselves.
  Filed as OI-267 (`docs/audit/open_issues.md`) rather than silently
  expanded into this batch or silently dropped.
contract_test_path: test/contracts/day_rollover_provider_invalidation_behavioral_test.dart
regression_test_planned: |
  - test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart
    (source-grep, PRESENCE only): asserts 'weeklyReportDataProvider' appears
    in day_rollover_service.dart.
  - test/contracts/day_rollover_provider_invalidation_behavioral_test.dart
    (BEHAVIORAL — canonical behavioral_test_path for this concept, Test F):
    clears healthBox, reads weeklyReportDataProvider (caches today's weight
    slot at 0), writes a healthBox weight entry directly for "today"
    (istDateStr(DateTime.now()), matching the notifier's own date-key
    scheme), re-reads without invalidation (still 0 — proves staleness),
    calls runRolloverNow, re-reads again and asserts today's weight slot
    now shows 72.5.
  Mutated and run: commenting out the new
  ref.invalidate(weeklyReportDataProvider) line reddened Test F with
  `Expected: <72.5>, Actual: <0.0>`.
impact_analysis: |
  Scoped to: the Profile PRO Weekly Report card's 4-up sparkline (weight/
  calories/protein/workouts, last 7 IST days) staying pinned to whatever
  window was cached at first Profile-tab visit, for the rest of the app
  session — since Profile lives under StatefulShellRoute.indexedStack
  (never disposed on tab switch), this could mean the ENTIRE session,
  potentially spanning multiple real days, with zero refresh.

  No impact on:
  - dailyNutritionProvider / weeklyNutritionProvider — already correctly
    invalidated (weeklyNutritionProvider fixed earlier in this same batch,
    bug bae4dd), untouched by this fix.
  - Any daily-scoped Home/Train provider — untouched.
  - The underlying Hive data itself — this is purely a display-staleness
    bug, no data is lost or corrupted.

  Real-world severity: PRO-only feature (Weekly Report is gated), and this
  fix only closes the ROLLOVER leg — a user who logs weight/meals/workouts
  within the SAME day the app was opened will still see a stale sparkline
  until the next day's rollover or an app restart, per OI-267 (not fixed
  here). Included in this batch because the rollover leg specifically is
  the SAME confirmed bug class (day_rollover_provider_invalidation) this
  batch already fixes twice, found by the same audit, per CLAUDE.md §4.2's
  no-deferrals policy for confirmed bugs discovered mid-batch.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "day_rollover_service.dart now invalidates weeklyReportDataProvider in _doRolloverWithRef. Mutation-proven: commenting out the new line reddened Test F (Expected 72.5, Actual 0.0)." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "WeeklyReportDataNotifier.build() reads healthBox/nutritionBox/workoutBox correctly on every fresh build — confirmed by Test F's post-rollover assertion, which reads the SAME entry the pre-rollover cached build could not see." }
---

## Summary

`weeklyReportDataProvider` (the Profile PRO Weekly Report card's 4-up
sparkline) had NO invalidation anywhere in the app — not on day-rollover,
not on a new weight/meal/workout log. Found by plan-review round 1 during
this batch's founder-requested invalidation audit, while independently
verifying (and ruling out) a separate finding about `UserStatsNotifier`.

## Root Cause

Writer: `WeeklyReportDataNotifier.build()`
(`weekly_report_data_provider.dart:43`) computes a rolling 7-day window
from `DateTime.now()` directly and watches only `authUserIdTokenProvider`
— there is no stale-write component; the underlying Hive boxes are
already correct at all times.

Reader-invalidation gap: confirmed via `grep -rn weeklyReportDataProvider
lib/ test/` that this provider has never had a single
`ref.invalidate(weeklyReportDataProvider)` call site anywhere in the app
— not in `DayRolloverObserver`, not in any WriteService's Riverpod-layer
callers. The provider's OWN doc comment already named this as a gap
("invalidate when the user logs a workout or meal if you want the
sparkline to refresh without an app restart") but it was aspirational,
never wired.

## Fix

`ref.invalidate(weeklyReportDataProvider);` added to `_doRolloverWithRef`,
`day_rollover_service.dart:254` — the rollover leg only. See
`proposed_fix` for why the write-time leg is filed as OI-267 instead of
being included here.

## Related

Third confirmed instance of the missing-day-rollover-invalidation class
in this batch (after 9c8958/streakFreezeProvider and
bae4dd/weeklyNutritionProvider), all found by the same founder-requested
audit and fixed in the same batch/commit — see those diagnose-docs for
the general "Riverpod cache has no automatic dependency tracking on a raw
Hive read" design-gap discussion.

**A separate finding from the same plan-review round was checked and
RULED OUT before being counted here** (per CLAUDE.md's "Master Audit /
multi-agent surveys produce false-positive findings" pitfall, which
generalizes to a single review agent's findings too, not just
multi-agent audits): the review claimed `UserStatsNotifier.currentStreak`
(`profile_provider.dart:321`, `WorkoutRepository.instance.currentStreak()`
— a direct function call, not `ref.watch`'d) has no rollover-linked
invalidation and could go stale like the two bugs already fixed. Verified
FALSE by reading the actual watch chain: `UserStatsNotifier.build()` does
`ref.watch(weekIdentityProvider)` (`profile_provider.dart:292`), and
`weekIdentityProvider` itself does `ref.watch(currentPlanProvider)`
(`train_provider.dart:1067`) — which day-rollover DOES invalidate
(`day_rollover_service.dart:204`). So a rollover invalidates
`currentPlanProvider` → cascades through `weekIdentityProvider` →
cascades through `userStatsProvider`'s own watch → the ENTIRE `build()`
reruns, recomputing `currentStreak` fresh as a side effect, even though
`userStatsProvider` is never itself explicitly invalidated by
`DayRolloverObserver`. This transitive-watch-chain pattern is documented
and deliberate (`lib/features/train/CLAUDE.md`'s `hold_week_identity` SoT
row: "A consumer must `ref.watch` the provider... `userStatsProvider` did
[call the singleton before a prior fix], had no edge to the hold write" —
confirming the CURRENT code already uses `ref.watch`, not the singleton).
No fix needed for this sub-finding.
