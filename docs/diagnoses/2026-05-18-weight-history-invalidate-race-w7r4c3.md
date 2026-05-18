---
bug_id: w7r4c3
date: 2026-05-18
batch: APK Test #16.2 observations (2026-05-18)
status: shipped
symptom: |
  User logged the first weight entry for 2026-05-18 (IST) via the Home
  bottom-sheet weight logger. The "WEIGHT TREND" home card x-axis
  rendered the new dot at MAY 18 with the correct value (77.9 kg), but
  the entries-count footer continued to display "5 ENTRIES" instead of
  bumping to 6. The Hive write itself succeeded — only the entries-count
  reader showed a stale value after the save.
concept: weight_log_provider_invalidation_race
sot_registry_entry: weight_logs
writers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: WeightLogNotifier.logWeight, line: 735 }
  - { file: lib/core/services/health_write_service.dart, method_or_widget: HealthWriteService.logWeight, line: 114 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: WeightHistoryNotifier.build, line: 484 }
  - { file: lib/features/home/widgets/weight_log_sheet.dart, method_or_widget: WeightLogSheet._save invalidate site, line: 91 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: TodayWeightLoggedNotifier.build (device-local date, separate IST drift), line: 770 }
hive_key_prefix: "weight_"
hive_key_formula: "weight_<istDateStr(DateTime.now())>"
sync_methods: [syncWeightNow, pushSnapshot, syncProfileNow]
restore_methods: [restoreFromCloudForUser]
cloud_table: weight_logs
cloud_columns: [user_id, date, weight_kg, source, updated_at]
contract_test_path: test/contracts/weight_log_invalidation_awaitable_test.dart
ist_handling:
  - { file: lib/core/services/health_write_service.dart, line: 122, source: writer uses istDateStr correctly }
  - { file: lib/features/home/providers/home_provider.dart, line: 774, source: TodayWeightLoggedNotifier reads device-local YYYY-MM-DD instead of istDateStr — adjacent IST drift, separate fix tracked here for visibility }
provider_invalidations: [weightHistoryProvider, todayWeightLoggedProvider, userProfileProvider]
telemetry_op_types:
  success: [upsert_weight_log]
  failure: [health_write_service_log_weight]
cross_account_guard: WeightHistoryNotifier.build watches authUserIdTokenProvider at line 485 — cross-account isolation passes the audit-2026-05-12 contract.
forbidden_patterns_checked:
  - "Void-returning Notifier method that fire-and-forgets an async write before caller invalidates the reader provider"
  - "Hand-rolled YYYY-MM-DD from device-local DateTime.now() in any reader of a weight_<istDate> Hive key"
proposed_fix: |
  Root cause is a writer-completes-after-reader-rebuilds race:

  1. WeightLogSheet._save (weight_log_sheet.dart:90) calls the void
     WeightLogNotifier.logWeight synchronously.
  2. WeightLogNotifier.logWeight (home_provider.dart:735) wraps
     HealthWriteService.instance.logWeight in unawaited(...) at line 741
     and returns immediately.
  3. HealthWriteService.logWeight (health_write_service.dart:114) does
     await _acquireLock(lockKey) at line 125 BEFORE calling
     await box.put at line 136. The acquireLock await yields a microtask
     even when no contention exists (Completer.future).
  4. weight_log_sheet.dart:91 fires ref.invalidate(weightHistoryProvider)
     synchronously after step 1 returns — which schedules
     WeightHistoryNotifier.build to run on the next microtask.
  5. The Hive box.put microtask and the provider rebuild microtask race;
     in practice the provider rebuild wins because Riverpod schedules
     invalidations eagerly and Hive's put resolves after the lock acquire
     yields.
  6. WeightHistoryNotifier.build at home_provider.dart:484 iterates
     healthBox.values BEFORE the new weight_<istDate> entry has landed,
     so it returns the stale 5-entry list. The widget's _filteredEntries
     then renders "5 ENTRIES" footer + the May 18 dot value, the latter
     coming from a subsequent rebuild triggered by either pushSnapshot's
     side-effects or the user navigating back to home.

  Fix: turn WeightLogNotifier.logWeight into a Future<void> that awaits
  HealthWriteService.logWeight, and update WeightLogSheet._save to await
  it before calling ref.invalidate. The 3 affected sites:
  - lib/features/home/providers/home_provider.dart:735 — signature
  - lib/features/home/widgets/weight_log_sheet.dart:90 — await
  - lib/features/ai_coach/services/conversational_log_handler.dart:62 —
    chat path also needs await + post-await invalidate

  Adjacent IST drift in TodayWeightLoggedNotifier at line 770-775 is
  folded into this fix: replace the hand-rolled device-local
  YYYY-MM-DD with istDateStr(DateTime.now()) so the today-logged check
  matches the writer's key formula at IST 00:00-05:30 boundary.
regression_test_planned:
  - test/contracts/weight_log_invalidation_awaitable_test.dart — asserts that after WeightLogNotifier.logWeight resolves AND ref.invalidate runs, weightHistoryProvider's snapshot contains the new entry.
  - test/contracts/today_weight_logged_ist_test.dart — asserts TodayWeightLoggedNotifier returns true for a key written at IST 02:00 (device local would be prior day).
  - source-grep contract that forbids unawaited(HealthWriteService.instance.<any>) inside any Notifier method whose caller invokes ref.invalidate synchronously after.
---
# Body

## Eighth instance of writer/reader drift class

Per `feedback_writer_reader_field_drift_recurring.md` (already at 7
instances as of Test #16.1), this is the eighth. Unlike instances 1-7
which were FIELD-name drift (e.g. `set_number` vs `sets_completed`),
this one is TIMING drift: writer and reader agree on the field shape
but the reader executes before the writer's microtask resolves.

The fire-and-forget pattern in `WeightLogNotifier.logWeight` was
introduced in audit-2026-05-16 task E.7 when the writer was migrated
from direct Hive writes to `HealthWriteService`. The migration kept the
`void` signature for source-compat with `WeightLogSheet._save`, but the
new writer's internal `await _acquireLock` makes the put strictly
asynchronous — which the old direct-write version was not.

## Why count drifted but the value did not

The chart's x-axis dot at MAY 18 displays the correct value because the
sparkline widget re-reads on every Riverpod rebuild, not just the one
that ran during the save. Once the Hive put completes and a downstream
provider (e.g. via `pushSnapshot`'s ancillary invalidations) triggers
another rebuild, the chart picks up the new entry. But the entries
COUNT footer is computed in the same widget build pass — the user
visually sees the stale "5 ENTRIES" alongside the updated chart because
the two reads happen at different rebuild ticks.

## Adjacent IST drift surfaced during investigation

`TodayWeightLoggedNotifier.build` at `home_provider.dart:770-775` reads
`weight_<deviceLocalDate>` to decide whether today's weight was already
logged. The writer at `HealthWriteService.logWeight:122` uses
`istDateStr(date)`. At IST 00:00-05:30, device-local UTC date is the
prior day, so the reader returns false for a freshly-written today-IST
weight. This is a separate user-visible bug (the "log weight" pill
would not flip to its done state in that window) and is folded into
this fix because the surface is the same provider file.
