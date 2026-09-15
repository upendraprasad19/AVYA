---
bug_id: b7e3f1
date: 2026-05-12
batch: APK Test #13
status: shipped
symptom: On Sunday morning cold start, home today-card showed Saturday's completed workout ("BACK DAY A · DONE · Lat Pulldown 40kg") even though the IST calendar had advanced to Sunday May 10.
concept: day_rollover_provider_invalidation
sot_registry_entry: day_rollover_provider_invalidation
writers:
  - { file: lib/core/services/day_rollover_service.dart, method: _doRolloverWithRef, line: 136 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: TodayWorkoutNotifier.build, line: 397 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: _buildTodayRow, line: 601 }
hive_key_prefix: "last_known_date"
hive_key_formula: "'last_known_date' (singleton key in configBox)"
sync_methods: []
restore_methods: []
cloud_table: "(none — device-local rollover state)"
cloud_columns: []
contract_test_path: "test/contracts/cold_start_day_rollover_test.dart"
ist_handling:
  - { file: lib/core/services/day_rollover_service.dart, line: 71, fn: _todayStr }
provider_invalidations: [todayWorkoutProvider, dailyNutritionProvider, streakProvider, aiInsightProvider, allExercisePRsProvider, calendarWeekProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "_ref = ref.*runRolloverNow", absent: false }
  - { pattern: "if \\(_ref == null\\) _ref = ref", absent: true }
proposed_fix: "In runRolloverNow(), do NOT overwrite _ref if it is already non-null. app.dart.initState() calls DayRolloverObserver.instance.init(app_ref) before any screen mounts, setting _ref to the long-lived root app WidgetRef. runRolloverNow() subsequently replaces _ref with the short-lived splash WidgetRef. When splash disposes its ref becomes stale. All subsequent resume-time calls to _doRollover() use the stale ref, ref.invalidate() silently no-ops, and providers never refresh. Fix: guard the _ref assignment in runRolloverNow — only set _ref when _ref is null (no init() call yet)."
regression_test_planned: ["test/contracts/cold_start_day_rollover_test.dart"]
---

# Bug b7e3f1 — Day Rollover Stale Ref Overwrites Long-Lived App Ref

## Symptom

On Sunday morning (IST), the founder opened AVYA after having logged Saturday's BACK DAY A
workout the previous night. The app had been put in the background (not killed) overnight.
Home today-card showed Saturday's completed workout content ("BACK DAY A · DONE · Lat Pulldown
40kg") instead of Sunday's plan.

## Writer

`DayRolloverObserver._doRollover()` at `lib/core/services/day_rollover_service.dart:112`.

Two call paths into `_doRollover`:
1. **Resume path** (`_checkAndRollover` → `_doRollover`) — gated: runs only when date changes.
2. **Cold-start path** (`runRolloverNow` → `_doRollover`) — unconditional: always invalidates on
   splash.

`_doRollover` reads `_ref` (instance field) to call `ref.invalidate(...)` on all daily providers.
`_ref` is set by two callers:
- `init(ref)` at `lib/app.dart:35` — the **root app widget**, whose ref is valid for the
  entire app lifetime.
- `runRolloverNow(ref)` at line 106 — which **overwrites** `_ref` with the splash screen's ref.

## Root Cause

`runRolloverNow()` line 106: `_ref = ref;` clobbers the long-lived `app_ref` (set by `init()`
in `app.dart.initState()`) with `splash_ref` (the ref belonging to `SplashScreen`, which
is a `ConsumerStatefulWidget` that disposes after navigating to `/restoring`).

Sequence of events:
1. App cold-starts. `app.dart.initState()` calls `DayRolloverObserver.instance.init(app_ref)`.
   `_ref = app_ref`. `_attached = true`. Lifecycle observer registered.
2. `SplashScreen` mounts. `_runDeferredInit()` eventually calls
   `DayRolloverObserver.instance.runRolloverNow(splash_ref)`.
   **`_ref = splash_ref`** — overwrites the durable `app_ref`.
3. `SplashScreen` navigates to `/restoring` → `/home` and is disposed.
   `splash_ref` becomes a stale dead ref.
4. Founder backgrounds the app (Saturday). All is fine — no date change yet.
5. Founder reopens the app Sunday morning. OS sends `AppLifecycleState.resumed`.
6. `didChangeAppLifecycleState(resumed)` fires → `_checkAndRollover()` runs.
   `last_known_date` = "2026-05-09" (Saturday). `today = _todayStr() = "2026-05-10"`.
   Date changed → calls `_doRollover("2026-05-10")`.
7. `_doRollover()` reads `_ref` = stale `splash_ref`. Calls `ref.invalidate(todayWorkoutProvider)`.
   In Riverpod 2, calling invalidate on a disposed WidgetRef silently no-ops (the ref's
   element is unmounted; no live listener is notified).
8. `todayWorkoutProvider` is NOT invalidated. Its cached state from Saturday's build
   (`schedule_2026-05-09`, status=completed) is returned on the next `ref.watch(...)`.
9. Home today-card renders Saturday's DONE state.

## Two-Reader Divergence

- **Calendar strip** reads `calendarWeekProvider` which also uses `DateTime.now()` as its
  date anchor. On resume, if the calendar provider DID rebuild (e.g., triggered by a
  different ref), it would show Sunday selected. The TODAY gold-border uses the device
  clock, not a cached provider value. This is why the calendar strip correctly showed
  Sunday while the today-card showed Saturday — two different read paths, one invalidated
  and one not.

## Fix

`runRolloverNow()` must NOT overwrite `_ref` when `_ref` is already non-null. `init()` from
`app.dart` always runs first (root widget initState fires before any child screen), so by the
time `runRolloverNow()` is called from splash, `_ref` is already the durable `app_ref`.

Change line 106 from:
```dart
_ref = ref; // store for any subsequent resume-time invalidations
```
to:
```dart
_ref ??= ref; // Only set if init() hasn't already provided a long-lived ref
```

`runRolloverNow` still uses the passed `ref` for the immediate `_doRollover` call by
extracting it into a local variable, so cold-start invalidations still work even if `_ref`
was null (first-launch before `init()` ran, which cannot happen in practice but is safe to
handle).

## Regression test

`test/contracts/cold_start_day_rollover_test.dart` — source-grep contract test asserting:
1. `runRolloverNow` does NOT contain the raw `_ref = ref` assignment (uses `??=` instead).
2. `_doRollover` contains `ref.invalidate(todayWorkoutProvider)`.
3. `app.dart` calls `DayRolloverObserver.instance.init(ref)` for long-lived ref setup.
4. `splash_screen.dart` calls `DayRolloverObserver.instance.runRolloverNow(ref)` on cold start.
