---
bug_id: 9c8958
date: 2026-09-28
batch: reps-secs-invalidation-fixes
status: fixed
blast_radius: account
symptom: |
  Founder-reported (2026-09-28): "streak freeze being Monday should
  increase by 1. I had to close the app and restart it before it got
  reflected." Live Supabase/telemetry investigation (client_errors table,
  op_type ilike '%streak_freeze%') confirmed the Monday refill fired
  correctly and on time (07:30 IST, well before the founder observed the
  stale value) — the refill was NOT late or broken. The bug is purely
  that the already-open app's streak badge kept showing the pre-refill
  count until an app restart forced a fresh provider build.
concept: day_rollover_provider_invalidation
sot_registry_entry: |
  day_rollover_provider_invalidation — extends the EXISTING concept
  (docs/sot_registry.yaml:1390; lib/core/services/CLAUDE.md's WriteService
  table) rather than registering a new one. streakFreezeProvider is
  simply an omission from the invalidation set _doRolloverWithRef already
  maintains for ~24 other daily-scoped providers (streakProvider, two
  lines above it in the same file, was already correctly invalidated).
writers:
  - { file: lib/core/services/day_rollover_service.dart, method_or_widget: "_doRolloverWithRef — new invalidate call", line: 218 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: "refillIfNewWeek — the actual Hive write, called earlier in the same method and confirmed already correct", line: 169 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "StreakFreezeNotifier.build()", line: 276 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "streak badge render — ref.watch(streakFreezeProvider)", line: 317 }
hive_key_prefix: "user_progress (userBox)"
hive_key_formula: "UserRepository.getProgress()['streak_freezes_available']"
sync_methods:
  - "StreakProgressService writes trigger the standard workout-domain sync fan-out"
restore_methods:
  - "sync/sync_workout.dart (progress map restore — local-max-wins per feedback_monotonic_field_recompute_demotion.md; unaffected by this fix)"
cloud_table: user_progress
cloud_columns:
  - streak_freezes_available
ist_handling:
  - { file: lib/core/services/day_rollover_service.dart, method_or_widget: "_todayStr() — istTodayStr(), unaffected by this fix", line: 88 }
provider_invalidations:
  - streakFreezeProvider
telemetry_op_types:
  success:
    - day_rollover_streak_freeze_refill
  failure:
    - day_rollover_streak_freeze_refill
cross_account_guard: "wrapUserScopedBox ensures per-user Hive isolation; StreakFreezeNotifier resets on auth change via ref.watch(authUserIdTokenProvider). Not affected by this fix."
forbidden_patterns_checked:
  - { pattern: "StreakFreezeNotifier.build() performing a write (write-on-read anti-pattern)", absent: true }
proposed_fix: |
  Add `ref.invalidate(streakFreezeProvider);` to
  `DayRolloverObserver._doRolloverWithRef`, alongside the ~20 other daily
  providers already invalidated there. `StreakProgressService.instance.
  refillIfNewWeek()` (called a few lines earlier in the same method) was
  already correctly writing the new count to Hive on time — the ONLY gap
  was that nothing told the cached `NotifierProvider` to rebuild, so
  Riverpod kept serving the pre-refill value from cache until an
  unrelated invalidation (or a full app restart, which rebuilds every
  provider from scratch) happened to touch it.

  This is the SAME missing-invalidation shape as bug bae4dd
  (weeklyNutritionProvider, fixed in the same commit/batch) — see that
  diagnose-doc and CLAUDE.md's "design gap" discussion of why this class
  of bug recurs (a Riverpod NotifierProvider's cache has no way to know a
  Hive value it depends on changed outside of an explicit
  `ref.invalidate`; there is no automatic dependency tracking on raw Hive
  reads the way there is on `ref.watch(otherProvider)`).
contract_test_path: test/contracts/day_rollover_provider_invalidation_behavioral_test.dart
regression_test_planned: |
  - test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart
    (source-grep, PRESENCE only): asserts 'streakFreezeProvider' appears
    in day_rollover_service.dart.
  - test/contracts/day_rollover_provider_invalidation_behavioral_test.dart
    (BEHAVIORAL — canonical behavioral_test_path for this concept, Test D):
    seeds streak_freezes_available=0, reads streakFreezeProvider (caches
    0), writes streak_freezes_available=1 directly to Hive (simulating a
    refill landing while the provider is cached), re-reads without
    invalidation (still 0 — proves the staleness), calls runRolloverNow,
    re-reads again and asserts it now matches a fresh ground-truth
    getProgress() read (not a hard-coded "1", so the assertion is robust
    to whatever refillIfNewWeek itself does on the day the suite runs) AND
    is NOT 0 (guards against a vacuous pass).
  Mutated and run: commenting out the new ref.invalidate(streakFreezeProvider)
  line reddened Test D with `Expected: <1>, Actual: <0>` — exactly the
  founder's reported symptom, reproduced and confirmed fixed.
impact_analysis: |
  Scoped to: the streak-freeze badge on Home + the freeze-count display
  on Nutrition/Train screens (`freezesAvailable: ref.watch(streakFreezeProvider)`
  call sites) staying stale from the Monday refill until the next
  unrelated invalidation or app restart.

  No impact on:
  - The refill LOGIC itself (StreakProgressService.refillIfNewWeek) — was
    already correct, confirmed via live telemetry before proposing any fix
    (CLAUDE.md §4.1: never reflexively fix without naming writer+reader
    first — the writer here was already correct, the reader-invalidation
    link was the gap).
  - streakProvider (workout-completion streak count) — was already
    correctly invalidated two lines above this fix in the same method.
  - Any OTHER daily provider in the invalidation list — untouched.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "day_rollover_service.dart now invalidates streakFreezeProvider in _doRolloverWithRef. Mutation-proven: commenting out the new line reddened Test D (Expected 1, Actual 0)." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "UserRepository.getProgress()['streak_freezes_available'] was already being written correctly by refillIfNewWeek — confirmed via live client_errors telemetry (07:30 IST refill, non-error) before this fix was proposed, per CLAUDE.md §4.1's writer-before-fix naming requirement." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Live query on user_progress for the founder's account confirmed streak_freezes_available=1, last_refill=2026-09-28 — the refill DID land correctly and on time; this ruled out the initial 'is the refill late' hypothesis before any fix was proposed." }
---

## Summary

The Monday streak-freeze refill wrote the correct new count to Hive on
time. The badge showing it stayed stale until the app was restarted — a
missing Riverpod invalidation, not a broken or late refill.

## Root Cause

Writer: `StreakProgressService.instance.refillIfNewWeek()`
(`streak_progress_service.dart:169`), called from
`DayRolloverObserver._doRolloverWithRef` (`day_rollover_service.dart:161`,
a few lines before the invalidation block). Confirmed correct
via live telemetry BEFORE proposing any fix, per CLAUDE.md §4.1 (never
reflexively fix; name writer + reader first).

Reader: `StreakFreezeNotifier.build()` (`home_provider.dart:276`) — a
`Notifier<int>` that reads `UserRepository.instance.getProgress()` once
per build and caches the result. `_doRolloverWithRef` invalidates ~20
other daily-scoped providers (workout, nutrition, health, AI, misc) but
`streakFreezeProvider` — despite `streakProvider`, its neighbour two
lines above in the same invalidation block, being correctly present — was
simply never added to the list.

## Fix

`ref.invalidate(streakFreezeProvider);` added to `_doRolloverWithRef`,
day_rollover_service.dart:218.

## Related

Same missing-invalidation class as bug bae4dd (weeklyNutritionProvider),
fixed in the same batch/commit. Both are instances of the general design
gap the founder asked about directly: a Riverpod `NotifierProvider`
caching a Hive-derived value has no automatic way to detect that the
underlying Hive value changed outside of `ref.watch`-tracked dependencies
— every such provider needs an EXPLICIT `ref.invalidate` call at every
point its backing data can change. `DayRolloverObserver`'s ~20-provider
list is exactly this pattern's central registry, and is exactly where a
new daily-scoped provider is easy to add without remembering to also add
it here. See the sibling `feat` commit in this batch (foreground
midnight-timer backstop) for the SEPARATE, second design gap the founder
raised in the same conversation — the rollover mechanism itself is only
lifecycle-triggered (resume/cold-launch), so an app left open in the
foreground straight through midnight never even reaches this invalidation
block at all until the next resume. That gap is orthogonal to the
missing-provider gap this doc fixes (both were present simultaneously,
but each is independently sufficient to cause a stale-badge report).
