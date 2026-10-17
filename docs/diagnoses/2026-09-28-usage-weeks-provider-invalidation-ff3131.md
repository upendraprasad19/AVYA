---
bug_id: ff3131
date: 2026-09-28
batch: reps-secs-invalidation-fixes
status: fixed
blast_radius: account
symptom: |
  Found during plan-review round 2 of this same batch (context-blind,
  independent audit that started from a different angle than round 1:
  every top-level Provider/NotifierProvider under lib/features/*/providers/
  that computes from DateTime.now(), cross-checked against
  day_rollover_service.dart's invalidation list). Not founder-observed
  directly — confirmed present by code before being counted as a bug, per
  this repo's no-false-positive discipline.
concept: day_rollover_provider_invalidation
sot_registry_entry: |
  day_rollover_provider_invalidation — extends the EXISTING concept
  (docs/sot_registry.yaml:1390), same shape as bugs 9c8958/bae4dd/b1bfea/4018b3
  found earlier in this same batch. usageWeeksProvider is presence_only:
  true (see below) — same reason as 4018b3's referralEligibilityProvider:
  its staleness driver is real wall-clock time against a
  Supabase-auth-sourced signup date, with no Hive-mutable proxy and no
  existing test seam for injecting a fake
  `SupabaseService.instance.currentUser`.
writers:
  - { file: lib/core/services/day_rollover_service.dart, method_or_widget: "_doRolloverWithRef — new invalidate call", line: 279 }
readers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "UsageWeeksNotifier.build()", line: 590 }
  - { file: lib/features/profile/screens/profile/profile_content.dart, method_or_widget: "Weekly Report unlock gate — ref.watch(usageWeeksProvider)", line: 15 }
hive_key_prefix: "N/A — no Hive read; computes from SupabaseService.instance.currentUser.createdAt"
hive_key_formula: "N/A"
sync_methods:
  - "N/A — pure read, no writes of its own"
restore_methods:
  - "N/A"
cloud_table: "N/A — reads Supabase auth's createdAt directly, not a table row"
cloud_columns: []
ist_handling:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "UsageWeeksNotifier.build() — uses raw DateTime.now(), NOT the istDateStr/istMidnight seam (pre-existing, out of scope for this fix)", line: 602 }
provider_invalidations:
  - usageWeeksProvider
telemetry_op_types:
  success:
    - day_rollover_all_providers_invalidated
  failure: []
cross_account_guard: "ref.watch(authUserIdTokenProvider) inside the provider resets on auth change. Not affected by this fix."
forbidden_patterns_checked:
  - { pattern: "UsageWeeksNotifier.build() performing a write (write-on-read anti-pattern)", absent: true }
proposed_fix: |
  Add `ref.invalidate(usageWeeksProvider);` to
  `DayRolloverObserver._doRolloverWithRef`. This provider already had a
  working invalidation via `invalidateOnRetry` (`screen.dart:118`, which
  per `lib/features/home/CLAUDE.md`'s `cold_start_restore_refresh` row
  also doubles as `invalidateOnBackgroundRestore`) — but neither an
  explicit user retry tap nor a background-restore tick is a week-boundary
  event, so the ONLY gap was the rollover leg. A single clean addition
  with no fan-out complexity, so fixed directly rather than filed as an OI.
contract_test_path: test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart
regression_test_planned: |
  - test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart
    (source-grep, PRESENCE-ONLY — this concept's SOLE regression coverage,
    see presence_only_reason below): asserts the exact substring
    'ref.invalidate(usageWeeksProvider)' appears in day_rollover_service.dart
    — the full CALL, not just the bare provider name, for the same
    comment-blind-spot reason documented in bug 4018b3's diagnose-doc.
  Mutated and run: DELETING the `ref.invalidate(usageWeeksProvider);` line
  entirely reddened the presence test with `Expected: true, Actual: <false>`.
presence_only: true
presence_only_reason: |
  Same reasoning as bug 4018b3 (referralEligibilityProvider), which see
  for the full explanation: `UsageWeeksNotifier.build()`'s week count is
  computed purely from `DateTime.now().difference(createdAt).inDays ~/ 7`
  where `createdAt` comes from `SupabaseService.instance.currentUser` — a
  fixed real-auth value with no Hive-mutable proxy and no existing
  mock/override seam in this test suite. The presence test above is this
  concept's sole regression coverage, and its mutation-proof (delete, not
  comment-out — a `//`-prefixed line still contains the checked substring)
  is why it can be trusted despite being presence-only.
impact_analysis: |
  Scoped to: the Profile screen's Weekly Report card unlock gate ("Available
  after Week 1") staying pinned to whatever week count was cached at the
  last retry-tap or background-restore, for the rest of the app session —
  since Profile lives under StatefulShellRoute.indexedStack (never disposed
  on tab switch), a user who signs up, opens Profile once during week 0,
  and leaves the app running without triggering either existing trigger
  would keep seeing the card locked past the real Week 1 boundary.

  No impact on:
  - `WeeklyReportDataNotifier`/`weeklyReportDataProvider` (bug b1bfea,
    same batch) — a SEPARATE provider (the report's DATA), already fixed;
    this fix is for the UNLOCK GATE only.
  - `invalidateOnRetry`'s other 6 invalidated providers — untouched.
  - Any other provider in the invalidation list — untouched.

  Real-world severity: narrow (most users trigger a background restore or
  a retry within days of signup regardless) and purely a display-lock
  staleness — no data loss, no incorrect PRO gating (the Weekly Report
  screen itself, if reached directly, still gates correctly on its own
  data). Included in this batch because it is the SAME confirmed bug class
  already fixed 4 times in this batch, found by the same audit process,
  per CLAUDE.md §4.2's no-deferrals policy.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "day_rollover_service.dart now invalidates usageWeeksProvider in _doRolloverWithRef. Mutation-proven: deleting the line reddened the presence test." }
---

## Summary

`usageWeeksProvider` (the Profile screen's Weekly Report unlock gate) had
a working invalidation on retry-tap/background-restore but was never
invalidated on day-rollover. Found by plan-review round 2's independent
audit, applying the same rollover-invalidation lens this batch already
used 4 times.

## Root Cause

Writer: `UsageWeeksNotifier.build()` (`profile_provider.dart:590`)
computes its week count fresh from `DateTime.now()` on every rebuild —
there is no stale-write component; the underlying signup timestamp never
changes.

Reader-invalidation gap: `DayRolloverObserver._doRolloverWithRef`
(`day_rollover_service.dart`) never invalidated this provider — its ONLY
existing invalidation call site (`screen.dart:118`'s `invalidateOnRetry`,
which also serves as the background-restore hook) fires on a user action
or a sync event, neither of which is the week boundary itself.

## Fix

`ref.invalidate(usageWeeksProvider);` added to `_doRolloverWithRef`,
`day_rollover_service.dart:279`.

## Related

Fifth confirmed instance of the missing-day-rollover-invalidation class in
this batch (after 9c8958/streakFreezeProvider, bae4dd/weeklyNutritionProvider,
b1bfea/weeklyReportDataProvider, 4018b3/referralEligibilityProvider), all
found by the same founder-requested audit (extended by two independent
plan-review rounds) and fixed in the same batch/commit.
