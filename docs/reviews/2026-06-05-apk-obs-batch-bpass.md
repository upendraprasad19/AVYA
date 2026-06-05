---
reviewed_at: 2026-06-05
blast_radius: platform
reviewer: claude-sonnet-bpass
findings_count: 7
verdict: accepted
---

# B-pass Review — APK Obs Batch 2026-06-05

Files reviewed (all changed files read in full):
- `lib/core/services/workout_schedule_read_service.dart`
- `lib/features/train/widgets/workout_receipt_card.dart`
- `lib/features/train/screens/active_workout/completion_sheet.dart`
- `lib/core/services/nutrition_read_service.dart`
- `lib/features/nutrition/widgets/todays_meals_card.dart`
- `lib/features/home/providers/home_provider.dart`
- `lib/features/profile/screens/profile/health_sync_sheet.dart`
- `lib/features/profile/providers/profile_provider.dart`
- `lib/features/train/widgets/week_selector.dart`
- `lib/core/services/supabase_service.dart`
- `lib/features/auth/screens/splash_screen.dart`
- `lib/core/services/sync_service.dart`
- `lib/features/home/screens/home_screen.dart`
- `lib/features/auth/screens/restoring_screen.dart`
- `scripts/check_hive_map_field_drift.dart`

---

## F-1 (P1) — `mounted` check in `onToggleSync` uses the WRONG `mounted`

**File:** `lib/features/profile/screens/profile/health_sync_sheet.dart:44`

**Claim:**
```dart
onToggleSync: () async {
  final newValue = !b.isSyncEnabled;
  await ref.read(biometricProvider.notifier).toggleSync(newValue);
  if (newValue && mounted) {        // ← 'mounted' refers to _ProfileScreenState
    ref.invalidate(todayStepsProvider);
  }
},
```

`mounted` inside the `Consumer` builder closure refers to the **enclosing `_ProfileScreenState`** (`this.mounted`), NOT to whether the Consumer/sheet is still alive. The Consumer lives in a bottom sheet that may be dismissed while `toggleSync` is in-progress. The profile State could still be mounted after the sheet is dismissed (it is still on-screen behind the sheet), so `mounted` returns `true` even though `sheetRef` (and the Consumer's context) is already gone. The `ref.invalidate(todayStepsProvider)` call then runs on a live `ref` after the Consumer is dead — which is safe for Riverpod but conceptually wrong: it invalidates from the STATE's mounting perspective, not the sheet's.

The deeper risk: if the `Consumer` is rebuilt (sheet dismissed → rebuilt) while `toggleSync` awaits, `b.isSyncEnabled` captured at call-start may be stale compared to the provider's current value. This can cause `newValue` to be the wrong polarity and call `toggleSync(!current)` unexpectedly.

**Verification:**
```
grep -n "mounted" lib/features/profile/screens/profile/health_sync_sheet.dart
```
Should show `mounted` used without `consumerCtx.mounted` or `sheetRef`-scoped guard.

**Suggested fix:** Use `consumerCtx.mounted` (the Consumer's BuildContext) instead of the bare `mounted` from the enclosing State. Also capture `newValue` before the `await` (already done) but add a `if (!consumerCtx.mounted) return;` guard after the await.

**Status:** pending

---

## F-2 (P1) — `bucketPastRows` phase-identity path ignores mixed-phase batches: a SINGLE non-int `phase` drops ALL stamped rows back to 28-day bucketing

**File:** `lib/core/services/workout_schedule_read_service.dart:626`

**Claim:**
```dart
if (sorted.every((r) => r.$2['phase'] is int)) {
  // phase-identity grouping
} else {
  // 28-day fallback for ALL rows
}
```

The guard is an all-or-nothing gate: if even ONE row among all past rows has a non-int `phase` (e.g. a legacy rest day row that predates the stamp, a row that was swapped and rewritten by SwapService without carrying `phase`, or a row written by a path the diff says does NOT stamp `phase`), the whole dataset falls back to 28-day bucketing. The problem is that `generateAndScheduleFromDate` (line ~288–314) writes pre-onboarding "Joined later" rest rows explicitly without a `phase` key:

```dart
entry: {
  'date': dateKey,
  'phase': phase,    // ← 'phase' IS stamped here
  'week': 1,
  ...
  'reason': 'pre_onboarding',
  ...
}
```

Those entries do stamp `phase`. However, the fix is fragile: any future code path that writes a `schedule_*` row without stamping `phase` will silently downgrade ALL past-phase bucketing to 28-day calendar windows, which is the same over-count bug this batch claims to fix. There is no Gate or contract test enforcing that every `schedule_*` writer stamps an int `phase`.

Additionally, `phaseForDate` catches ALL exceptions from its inner calls (`catch (_)`), including legitimate programming errors in `bucketPastRows`. This means a logic bug in phase grouping silently falls back to returning 1 (the wrong phase number) for all past workouts — a silent display regression.

**Verification:**
```
grep -n "'phase'" lib/core/services/workout_schedule_read_service.dart
# Check ALL schedule_* write sites for 'phase': field
grep -rn "upsertScheduled" lib/ --include="*.dart" | grep -v "test"
```

**Suggested fix:**
1. Change the guard to use the phase-identity path for any row that HAS an int `phase`, and group the remainder (no-phase rows) as a single "pre-phase" bucket or discard them — do not let one non-int row degrade the whole dataset.
2. Add a `check_*.dart` gate asserting every `schedule_*` write path emits an int `phase`.

**Status:** pending

---

## F-3 (P1) — CONCURRENCY: `_healAfterRestoreInBackground` migrators race with the in-flight `restoreFuture`

**File:** `lib/features/auth/screens/restoring_screen.dart:183`

**Claim:**
```dart
unawaited(restoreFuture.then((_) => _healAfterRestoreInBackground()));
```

The comment says "runs AFTER the in-flight cloud restore finishes (no concurrent Hive writer)". This is ONLY true if `restoreFuture` is the sole writer. However, `restoreFuture` was started via `ref.read(syncServiceProvider).restoreFromCloudForUser()` in `_kickoffRestore`. The `restoreFromCloudForUser` contract typically calls multiple domain-specific restore methods (nutrition, workout, health, profile) sequentially or concurrently. The question is whether `.then((_) => _healAfterRestoreInBackground())` is attached to the same Future that `restoreFuture` refers to, or to a copy.

In Dart, `restoreFuture.then(...)` chains directly on the same Future — it fires when `restoreFromCloudForUser()` completes (all domains restored). The migrators in `_healAfterRestoreInBackground` then run after that. This part is correct.

**However**, there is a subtler race: the `restoreFuture` Future could complete with any `RestoreResult` — including `RestoreResult.cancelled()` (if `cancelInflightRestore()` was called) or `RestoreResult.failed(error)`. The `.then((_) => ...)` callback fires for ALL completion states including cancellation and failure. If the restore was CANCELLED (e.g. the user got routed to onboarding mid-flight), `_healAfterRestoreInBackground` still runs — running key migrators and `PhaseProgressReconciler.reconcile` on potentially partial Hive state.

In the bg path, cancellation is not called (the code explicitly says "The in-flight restore is NOT cancelled"). But if a future code change adds a cancel call before this `.then(...)` handler is registered, there is no guard. More pressing: the `.then` is attached AFTER `context.go('/home')`, and there is no check inside `_healAfterRestoreInBackground` for whether the restore actually succeeded.

**Verification:**
```
grep -n "RestoreResult" lib/features/auth/screens/restoring_screen.dart
grep -n "cancelInflightRestore" lib/features/auth/screens/restoring_screen.dart
```

**Suggested fix:** Change to `restoreFuture.then((result) { if (result.succeeded) _healAfterRestoreInBackground(); })` to guard against running heals on a cancelled or failed restore.

**Status:** pending

---

## F-4 (P2) — `_WeekChip` `Icons.check_circle` renders for current-phase weeks but the new `completedWeeks` set is computed each build (expensive Hive walk)

**File:** `lib/features/train/widgets/week_selector.dart:116–120`

**Claim:**
```dart
final completedWeeks = service.completedWeekNumbers();
```

`completedWeekNumbers()` walks all 12 weeks × 7 days (up to 84 `getScheduleForDate` calls), each of which decodes a Hive map, on every `build()` call of `WeekSelector`. `WeekSelector` is a `ConsumerStatefulWidget` whose `build()` is called whenever `subscriptionInfoProvider` or the parent rebuilds. On the Train screen this happens frequently (provider invalidations on workout completion etc.).

`getScheduleForDate` also clones maps and does date string parsing on every call. For 84 calls per build this is not catastrophically slow but is unnecessary work that bypasses the per-rebuild caching Riverpod normally provides. The proper fix is to move this into a Provider so it's cached until invalidated by a write.

**Verification:**
```
grep -n "completedWeekNumbers\|completedWeeks" lib/features/train/widgets/week_selector.dart
```

**Suggested fix:** Expose `completedWeekNumbers` as a Riverpod provider computed from `workoutScheduleReadServiceProvider`, so builds read cached state instead of re-walking Hive.

**Status:** pending

---

## F-5 (P2) — `phaseForDate` try/catch swallows real errors including `UserRepository` / Hive failures

**File:** `lib/core/services/workout_schedule_read_service.dart:677–688`

**Claim:**
```dart
int phaseForDate(DateTime date) {
  try {
    final progress = UserRepository.instance.getProgress();
    ...
    return phaseForDatePure(...);
  } catch (_) {
    return 1;
  }
}
```

The `catch (_)` is over-broad. It matches:
- `HiveError` / `BoxNotOpenException` (legitimate defensive fallback)
- `StateError` from `UserRepository` when state is corrupt
- **Programming errors** such as `CastError` / `TypeError` in `phaseForDatePure` or `bucketPastRows` — which are bugs, not recoverable conditions

Falling back to `1` on a programming error causes silent wrong-phase display. The receipt will show "PHASE 1" for all past workouts even after phase progression happens, and there is no telemetry to detect this. The intent was to guard against Hive-not-open in unit tests, but that could be achieved with a narrower `on BoxNotOpenException` or a simple null-check on `HiveService.instance.workoutBox.isOpen`.

**Verification:**
```
grep -n "catch (_)" lib/core/services/workout_schedule_read_service.dart
```

**Suggested fix:** Narrow the catch to `on HiveError` or add an `ErrorTelemetry.recordNonFatal` inside the broad catch so silent failures are at least observable in production.

**Status:** pending

---

## F-6 (P2) — `completedWeekNumbers` uses a hardcoded `maxWeek = 12` but never queries past-phase weeks; past-phase completions are silently excluded

**File:** `lib/core/services/workout_schedule_read_service.dart:483–499`

**Claim:**
```dart
Set<int> completedWeekNumbers({int maxWeek = 12}) {
  final planStart = getPlanStartDate();
  if (planStart == null) return const {};
  final ps = DateTime(planStart.year, planStart.month, planStart.day);
  final result = <int>{};
  for (var w = 1; w <= maxWeek; w++) {
    final weekStart = ps.add(Duration(days: (w - 1) * 7));
    for (var d = 0; d < 7; d++) {
      final sched = getScheduleForDate(weekStart.add(Duration(days: d)));
      ...
```

This method only queries dates **within the current plan window** (from `plan_start_date`, up to 12 weeks forward). Past-phase rows live at dates BEFORE `plan_start_date`. The `_WeekChip` in the current-phase group shows ✓ when a week number is in `completedWeeks`, but week numbers 1–4 in the CURRENT phase are computed from `planStart` → these are correct. The issue is conceptual: the method is documented as "global week numbers … in the CURRENT plan window" (line 479–480), which is correct, but the widget passes `completedWeeks` to both the current-phase `_PhaseGroup` AND the two future-phase `_PhaseGroup` widgets (lines 154–179). Future-phase weeks (5–12) will never be in `completedWeeks` because those weeks are beyond planStart+28. This is correct behavior for future phases. The past-phase chips use `hasCompletedDayInWeek` independently. So this is not a bug in the current rendering, but it IS a subtle footgun: the name `completedWeekNumbers` suggests it covers all weeks but it only covers the current phase. If a future caller tries to use it for past-phase completion checking, it will silently return empty.

Severity lowered to P2 because the current rendering is correct; the risk is future misuse.

**Verification:**
```
grep -n "completedWeeks" lib/features/train/widgets/week_selector.dart
```

**Suggested fix:** Rename to `currentPhaseCompletedWeekNumbers` or add a doc comment clarifying the scope is current-plan only.

**Status:** pending

---

## F-7 (P2) — `generateAndScheduleFromDate` pre-onboarding fill rows stamp `phase` via parameter but the parameter default is `phase = 1`

**File:** `lib/core/services/workout_schedule_read_service.dart:288–315`

**Claim:**
The "Joined later" rest rows emitted by `generateAndScheduleFromDate` (when `isFirstGeneration == true`) stamp `'phase': phase` where `phase` is the caller-supplied parameter defaulting to `1`. This is correct for onboarding (always Phase 1). However, `autoGenerateNextPhaseIfNeeded` (line 433–446) calls `generateAndSchedule` (not `generateAndScheduleFromDate`), so this path is unreachable for phase >1 new-phase generation. The specific concern is whether the `phase` stamp on "Joined later" rows (written once at initial onboarding) will confuse `bucketPastRows`'s phase-identity grouping when that user later completes Phase 1 and Phase 2 generates: at that point those pre-onboarding rows will have `phase: 1`, which is correct. No bug here in the happy path.

**However**, the interaction with `bucketPastRows`'s all-or-nothing `every((r) => r.$2['phase'] is int)` guard (F-2 above) is relevant: if ANY SwapService-written `schedule_*` row for a past date lacks `phase`, the guard falls to the 28-day path. SwapService was not in the diff — it needs to be audited independently.

**Verification:**
```
grep -rn "upsertScheduled\|'phase'" lib/core/services/workout_write_service.dart | head -30
```

**Suggested fix:** Audit `SwapService` and any other `upsertScheduled` callers to confirm they always stamp `'phase'`.

**Status:** pending

---

## Lens-by-lens clean results

### Lens 1 — writer_reader_drift
The new shared `NutritionReadService.deriveMealDisplayName` is correctly used by both `todays_meals_card.dart` (forwarding) and `home_provider.dart` (direct call). The `'phase'` stamp at schedule write sites (`generateAndSchedule` lines 156/186/298/359/386) aligns with the reader in `bucketPastRows` (`r.$2['phase'] is int`) and `phaseForDate`. No field-name mismatch detected. The `istDateStr` switch in `RecentFoodLogsNotifier.build` (line 641) now matches the writer's IST key format. CLEAN except for the fragility captured in F-2.

### Lens 2 — unawaited_no_error_sink
- `unawaited(SupabaseService.instance.warmConnection())` — `warmConnection()` has an inner `catch (_)` that swallows all errors. Safe.
- `unawaited(restoreFuture.then((_) => _healAfterRestoreInBackground()))` — `_healAfterRestoreInBackground` wraps every step in `try {} catch (_) {}`. The `.then()` callback itself can throw if `_healAfterRestoreInBackground` throws before its first try-block; this is impossible given the function starts with a `try`. No unhandled rejection path. But see F-3 for the cancelled-restore concern.
- `SyncService.instance.bumpRestoreCompleted()` at the end of `_healAfterRestoreInBackground` is synchronous (ValueNotifier.value++), not async. CLEAN.
- `unawaited(ErrorTelemetry.logEvent(...))` calls throughout have their own internal error handling. CLEAN.

### Lens 3 — function_exception_swallow
- `phaseForDate`'s `catch (_)` is over-broad (F-5 above — P2).
- `_healAfterRestoreInBackground` per-step `try {} catch (_) {}` is intentional for a best-effort background function. ACCEPTABLE.
- `warmConnection`'s `catch (_)` is intentional (latency-only). ACCEPTABLE.

### Lens 4 — CONCURRENCY/ORDERING
- `openForUser` is awaited BEFORE `context.go('/home')` (line 170 awaited, line 179 go). Ownership gate is correctly blocking. CLEAN.
- `_healAfterRestoreInBackground` migrators run via `.then()` on the same `restoreFuture` Future — strictly after restore. Correct. But see F-3 for cancelled-restore case.
- `restoreCompletedTick` listener: `addListener` in `initState` (line 63), `removeListener` in `dispose` (line 72). Both sides present. No leak. CLEAN.
- `phaseForDate` singleton call from `WorkoutReceiptData.fromExerciseLogs` (a static method): the `@Deprecated` singleton is used with `// ignore: deprecated_member_use`. The `try/catch` inside `phaseForDate` handles Hive-not-open. CLEAN (with the caveat in F-5).
- `DayRolloverObserver.instance.runRolloverNow(ref)` is called with a live `ref` only when `mounted` (line 173–176). After `context.go('/home')`, `ref` from `RestoringScreen` is still valid (the widget is in the tree until GoRouter removes it). GoRouter's `context.go` schedules the route change; it does not immediately unmount the current widget. So there is no use-after-dispose here. CLEAN.

### Lens 5 — nullability / edge cases
- `bucketPastRows` with `phase` present but not int: caught by `sorted.every((r) => r.$2['phase'] is int)` — non-int falls back to 28-day path. CLEAN for runtime safety, but see F-2 for the fragility.
- `phaseForDatePure` date-boundary: normalizes `date` to midnight (`DateTime(date.year, date.month, date.day)`) and block starts to midnight. Consistent. CLEAN.
- `completedWeekNumbers` with null `planStart`: returns `const {}` immediately. CLEAN.
- `health_sync_sheet.dart` Consumer `mounted` check: see F-1 (P1).
- `deriveMealDisplayName` with single-char `mealType` (e.g. "b"): `mealType[0].toUpperCase() + mealType.substring(1)` would return "B" (just the one char). Not a crash. ACCEPTABLE.

### Lens 6 — blast_radius / flag safety
- `bgEnabled` is `configBox.get('bg_restore_enabled') == true`. If the key is absent, `get` returns `null`; `null == true` is `false`. Default is correctly OFF. CLEAN.
- `isReturning` checks `localProfile is Map && localProfile['primary_goal'] != null`. A fresh install has no `profile` in `userBox`, so `localProfile is Map` is false → default path. CLEAN.
- Default path (`await restoreFuture; if (!mounted) return; ...`) is byte-equivalent to the pre-diff path. CLEAN.

### Lens 7 — secrets_in_tree
No credential-shaped literals found in any of the diff files. CLEAN.

---

## Triage outcome (2026-06-05) — verdict: accepted

- **F-1 (mounted)** — FALSE ALARM. The `onToggleSync` callback uses the **State's**
  `ref` (for `toggleSync` + `invalidate`) AND the **State's** `mounted` — a
  consistent pair. `_ProfileScreenState` outlives the bottom sheet, so its `ref`
  stays valid and `mounted` is the correct guard for that ref. The post-await
  `ref.invalidate(todayStepsProvider)` is safe (no crash). No change.
- **F-2 (all-or-nothing bucketing)** — FIXED. `bucketPastRows` now carry-forwards:
  any int `phase` enables identity grouping; unstamped rows (e.g. SwapService)
  inherit the nearest preceding stamped phase, so one unstamped row can't collapse
  the dataset to 28-day. New `past_phase_bucketing_test` case added.
- **F-3 (heals on cancelled/failed restore)** — FIXED. `restoreFuture.then` now
  guards on `result.succeeded` before running the heals.
- **F-5 (broad catch in phaseForDate)** — FIXED. The catch records a non-fatal
  `phase_for_date_fallback` so a silent wrong-phase regression is observable;
  the fallback-to-1 behaviour (Hive unready in tests) is unchanged.
- **F-4 (per-build completedWeekNumbers)** — ACCEPTED (P2). ~84 O(1) Hive reads
  per build is sub-millisecond; a provider is cleaner but not a correctness issue.
- **F-6 (completedWeekNumbers naming)** — ACCEPTED (P2). The doc comment already
  scopes it to the current plan window; rendering is correct.
- **F-7 (SwapService unstamped rows)** — ADDRESSED by F-2's carry-forward (the
  robust runtime cure); the swap callsites remain unstamped but are absorbed.
