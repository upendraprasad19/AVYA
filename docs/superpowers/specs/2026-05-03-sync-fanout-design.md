# Sync Fan-out Fix + Rank Chip Hit-test — Design Spec

**Date:** 2026-05-03
**Branch (proposed):** `feat/sync-fanout-fix` off `main` (post-Test #8 merge `a394e0c`).
**Trigger:** APK Test #8 install audit revealed `workout_templates`, `scheduled_workouts`, and `streaks` at 0 cloud rows for `upendraprasad19@gmail.com` despite local Hive holding the data and the user explicitly creating a template + scheduling + completing a workout. User reported recurring frustration: "I have been harping upon since ages that everything should be synced."

A second user observation from the same APK install — the new Theme B rank chip in the profile banner is unclickable on device — is bundled into this batch as theme F7. Same surface (touched by the user during the same install), already-implemented patch sitting in the working tree.

---

## 1. Problem statement

Local Hive writes for templates, scheduled workouts, streaks, and saved meals are not reaching cloud reliably. Two distinct failure modes compound:

1. **Incomplete fan-out at the per-mutation sync entry points.** `SyncService.syncWorkoutData()` is the canonical fire-and-forget call wired into every workout-domain mutation site, but it only pushes 3 of the 6 workout-domain tables. Templates, full schedule rows, and streaks are excluded from the per-mutation path — they wait for `weeklyFullSync()` which runs at most once per 24 hours.

2. **Latent UUID-coercion bugs in 2 projection helpers.** Even when `weeklyFullSync()` does fire, two of the projections silently 400-reject:
   - `_syncScheduledWorkouts` sends `entry['template_id']` raw (e.g. `'tmpl_1747128000000'`) to a `uuid NOT NULL` FK column.
   - `_syncSavedMeals` sends `meal['id']` raw (e.g. `'saved_meal_<hash>'`) to a `uuid NOT NULL` PK column.

Both throw `invalid input syntax for type uuid`. The catch in each helper swallows the error and reports via `_reportSyncFailure`, so the user sees no symptom — just a permanently-empty cloud table. This is the deeper root cause of "everything should be synced": even when the sync fires, half the upserts silently reject.

The 2026-04-18 fix that introduced UUID coercion in `_syncWorkoutTemplates` was incomplete. It made the parent insert work but left two cross-references and one sibling table broken.

The 2026-04-24 `fix/sync-gaps` PR closed callsite drift (mutations not firing the fan-out) and added regression tests asserting "mutation X fires `syncX()`". Those tests still pass today. They never asserted "syncX() pushes everything in domain X" — that's the structural blind spot.

## 2. Goals

- Templates, scheduled workouts, streaks, and saved meals reach cloud within seconds of the local write (same fire-and-forget cadence as logs).
- Cloud upserts for these tables actually succeed (no more silent UUID rejection).
- A regression test makes the next "writer adds a new prefix without updating syncX()" failure visible at test time.
- The contract is documented so a future agent or developer can find it without code archaeology.
- The Theme B rank chip in the profile banner row registers taps on device (it currently doesn't because its hit-test region is outside the parent Stack's bounds).

## 3. Non-goals

- Health-domain tables (`weight_logs`, `body_measurements`, `sleep_logs`, `daily_steps`) stay in `weeklyFullSync()` only. User decision — those flow from Health Connect on a daily cadence and 24h tolerance is acceptable.
- Per-write sync inside `WorkoutWriteService` / `NutritionWriteService` (pushing the responsibility from screen-level callers down to the writer itself). Bigger refactor; defer.
- Surfacing silent sync failures to a UI / admin debug screen. Flag as a follow-up if Test #9 doesn't fully resolve.
- The "Hive vanished after APK install" question. Separate observation, separate brainstorm.
- Backfill RPC for already-affected users. Not needed — F1+F3 means the next workout-domain mutation auto-pushes everything sitting in local Hive.

## 4. Architecture

The sync architecture today is two-tier:

```
Tier 1 (per-mutation, fire-and-forget):
  syncWorkoutData()      → 3 helpers
  syncNutritionData()    → 2 helpers

Tier 2 (every 24h on app launch):
  weeklyFullSync()       → 17 helpers (covers everything)
```

The fix broadens Tier 1 to cover the workout + nutrition domains exhaustively while leaving Tier 2 unchanged as the safety net for everything else (health domain, saved meals' rare gaps if any, custom items, etc.).

```
Tier 1 (broadened):
  syncWorkoutData()      → 6 helpers (logs, exercises, schedule completions,
                                       templates, scheduled_workouts, streaks)
  syncNutritionData()    → 3 helpers (logs, water, saved meals)

Tier 2 (unchanged):
  weeklyFullSync()       → 17 helpers
```

## 5. Components

### 5.1 — `syncWorkoutData()` fan-out broadening

**File:** `lib/core/services/sync_service.dart` (around line 490)

```dart
Future<void> syncWorkoutData() async {
  try {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return;

    await Future.wait(
      [
        _safeRestoreOp('sync_workout_logs', _syncWorkoutLogs(userId)),
        _safeRestoreOp('sync_exercise_logs', _syncExerciseLogs(userId)),
        _safeRestoreOp('sync_schedule_completions', _syncScheduleCompletions(userId)),
        // Test #9 · F1 — close the templates/schedules/streaks gap.
        // These used to wait up to 24h for weeklyFullSync(); now push
        // on the same fire-and-forget cycle as logs.
        _safeRestoreOp('sync_workout_templates', _syncWorkoutTemplates(userId)),
        _safeRestoreOp('sync_scheduled_workouts', _syncScheduledWorkouts(userId)),
        _safeRestoreOp('sync_streaks', _syncStreaks(userId)),
      ],
      eagerError: false,
    );
  } catch (e) {
    debugPrint('[SyncService.syncWorkoutData] $e');
    try {
      await _reportSyncFailure(opType: 'sync_workout_data', error: e);
    } catch (_) {}
  }
}
```

### 5.2 — `syncNutritionData()` fan-out broadening

**File:** same (around line 518)

```dart
Future<void> syncNutritionData() async {
  try {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return;

    await Future.wait(
      [
        _safeRestoreOp('sync_nutrition_logs', _syncNutritionLogs(userId)),
        _safeRestoreOp('sync_water_logs', _syncWaterLogs(userId)),
        // Test #9 · F2 — saved meals join the per-mutation path so they
        // reach cloud immediately on save instead of next-day-batch.
        _safeRestoreOp('sync_saved_meals', _syncSavedMeals(userId)),
      ],
      eagerError: false,
    );
  } catch (e) {
    debugPrint('[SyncService.syncNutritionData] $e');
    try {
      await _reportSyncFailure(opType: 'sync_nutrition_data', error: e);
    } catch (_) {}
  }
}
```

### 5.3 — `_syncScheduledWorkouts` UUID coercion (F3 — bug fix)

**File:** same (around line 3140)

Current (broken — sends raw Hive `'tmpl_<ms>'` to uuid column):
```dart
await _supabase.client.from('scheduled_workouts').upsert({
  'user_id': userId,
  'template_id': entry['template_id'],   // ❌ raw Hive string
  'scheduled_date': date,
  ...
}, onConflict: 'user_id,scheduled_date');
```

Fixed:
```dart
// Test #9 · F3 — coerce template_id from Hive 'tmpl_<ms>' to deterministic
// v5 UUID matching what _syncWorkoutTemplates wrote for the parent row.
// Schema requires uuid; raw Hive strings throw "invalid input syntax for
// type uuid" and the catch silently swallowed it (root cause of the
// scheduled_workouts table sitting at 0 rows for weeks).
final rawTemplateId = entry['template_id']?.toString();
final cloudTemplateId = (rawTemplateId != null && rawTemplateId.isNotEmpty)
    ? _deterministicId(rawTemplateId)
    : null;

await _supabase.client.from('scheduled_workouts').upsert({
  'user_id': userId,
  if (cloudTemplateId != null) 'template_id': cloudTemplateId,
  'scheduled_date': date,
  'week_number': entry['week'] ?? entry['week_number'],
  'day_of_week': parsedDate?.weekday ?? entry['day_of_week'],
  'status': entry['status'] ?? 'planned',
  'completed_at': entry['completed_at'],
}, onConflict: 'user_id,scheduled_date');
```

The conditional `if (cloudTemplateId != null)` allows ad-hoc workout completions (no parent template) — they get null template_id which the schema permits.

### 5.4 — `_syncSavedMeals` UUID coercion (F4 — bug fix)

**File:** same (around line 3208)

Current (broken — sends raw `'saved_meal_<hash>'` to uuid PK):
```dart
await _supabase.client.from('user_saved_meals').upsert({
  'id': meal['id'] ?? key,   // ❌ raw Hive key
  'user_id': userId,
  ...
}, onConflict: 'id');
```

Fixed:
```dart
// Test #9 · F4 — coerce id from raw Hive key 'saved_meal_<hash>' to
// deterministic v5 UUID. Same failure class as _syncScheduledWorkouts
// (silent uuid syntax rejection); same fix pattern as
// _syncWorkoutTemplates (since 2026-04-18).
final hiveId = (meal['id'] as String?) ?? key;
await _supabase.client.from('user_saved_meals').upsert({
  'id': _deterministicId(hiveId),
  'user_id': userId,
  'name': meal['name'] ?? 'Unnamed Meal',
  'items': meal['items'],
  'total_calories': meal['total_calories'],
  'total_protein': meal['total_protein'],
  'times_used': meal['times_used'] ?? 0,
  'created_at': meal['created_at'] ?? DateTime.now().toIso8601String(),
}, onConflict: 'id');
```

The `_restoreSavedMeals` reverse path (line 3228) already handles either-format ids when computing `hiveKey` — no change needed there.

### 5.5 — Fan-out contract test (F5 — structural guard)

**File:** `test/contracts/sync_fanout_contract_test.dart` (NEW)

Source-grep test in the same style as `test/contracts/hive_key_contracts_test.dart`. Two assertions per domain (4 tests total):

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String syncServiceSrc;
  late Map<String, String> libSources;

  setUpAll(() {
    syncServiceSrc =
        File('lib/core/services/sync_service.dart').readAsStringSync();
    libSources = <String, String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        libSources[entity.path] = entity.readAsStringSync();
      }
    }
  });

  /// Extracts the body of a named method as a string.
  String methodBody(String src, String methodName) {
    final pattern = RegExp(r'Future<void>\s+' + methodName + r'\s*\(.*?\)\s*async\s*\{');
    final match = pattern.firstMatch(src);
    expect(match, isNotNull, reason: 'method $methodName not found in sync_service.dart');
    final start = match!.end - 1;
    int depth = 1;
    int i = start + 1;
    while (i < src.length && depth > 0) {
      final ch = src[i];
      if (ch == '{') depth++;
      if (ch == '}') depth--;
      i++;
    }
    return src.substring(start, i);
  }

  /// Scans every .dart file under lib/ for `<box>.put('<prefix>_*'...)`
  /// and similar deterministic-key writes.
  Set<String> writtenPrefixesFor(String boxAccessor) {
    final prefixes = <String>{};
    final patterns = [
      // box.put('prefix_$x', ...)
      RegExp(boxAccessor + r"\.put\(\s*['\"](\w+_)"),
      // 'prefix_$x' style key construction near box.put
      RegExp(r"['\"](\w+_)\$\{?[\w.]+\}?['\"]\s*,"),
    ];
    libSources.forEach((path, src) {
      // Only count files that touch the box accessor.
      if (!src.contains(boxAccessor)) return;
      for (final p in patterns) {
        for (final m in p.allMatches(src)) {
          prefixes.add(m.group(1)!);
        }
      }
    });
    return prefixes;
  }

  group('Sync fan-out contract', () {
    test('every workoutBox prefix is synced inside syncWorkoutData()', () {
      final body = methodBody(syncServiceSrc, 'syncWorkoutData');

      // Workout-domain prefixes the codebase actually writes.
      // Add to this allowlist intentionally if you add a new prefix; the
      // matching _sync*() projection is required at the same time.
      const expectedPrefixes = {
        'wlog_',                    // → _syncWorkoutLogs
        'exlog_',                   // → _syncExerciseLogs
        'schedule_',                // → _syncScheduleCompletions + _syncScheduledWorkouts
        'tmpl_',                    // → _syncWorkoutTemplates
        // 'exercise_log_index_' is an index, not synced separately
      };
      const expectedHelpers = {
        '_syncWorkoutLogs',
        '_syncExerciseLogs',
        '_syncScheduleCompletions',
        '_syncWorkoutTemplates',
        '_syncScheduledWorkouts',
        '_syncStreaks',
      };

      for (final helper in expectedHelpers) {
        expect(body.contains(helper), isTrue,
            reason: 'syncWorkoutData() must fan out to $helper '
                    '(see CLAUDE.md §15 sync fan-out contract).');
      }

      // Catch new prefixes we haven't accounted for.
      final actualPrefixes = writtenPrefixesFor('workoutBox');
      final unexpected = actualPrefixes.difference(expectedPrefixes)
          .difference({'exercise_log_index_'});
      expect(unexpected, isEmpty,
          reason: 'New workoutBox prefix(es) detected without an entry in '
                  'this contract test: $unexpected. Either add a matching '
                  '_sync*() helper inside syncWorkoutData() AND add the '
                  'prefix here, OR add to the explicit-skip set with a '
                  'comment justifying why this prefix is local-only.');
    });

    test('every nutritionBox prefix is synced inside syncNutritionData()', () {
      final body = methodBody(syncServiceSrc, 'syncNutritionData');

      const expectedPrefixes = {
        'nlog_',                    // → _syncNutritionLogs
        'water_',                   // → _syncWaterLogs
        'saved_meal_',              // → _syncSavedMeals
      };
      const expectedHelpers = {
        '_syncNutritionLogs',
        '_syncWaterLogs',
        '_syncSavedMeals',
      };

      for (final helper in expectedHelpers) {
        expect(body.contains(helper), isTrue,
            reason: 'syncNutritionData() must fan out to $helper '
                    '(see CLAUDE.md §15 sync fan-out contract).');
      }

      final actualPrefixes = writtenPrefixesFor('nutritionBox');
      final unexpected = actualPrefixes.difference(expectedPrefixes);
      expect(unexpected, isEmpty,
          reason: 'New nutritionBox prefix(es) detected without an entry in '
                  'this contract test: $unexpected. Update both syncNutritionData() '
                  'and this test, or add to the explicit-skip set.');
    });

    test('streaks healthBox key is synced inside syncWorkoutData()', () {
      // streaks lives in healthBox but is workout-domain (written by
      // train_provider.completeWorkout). Per the contract, syncWorkoutData()
      // owns the projection.
      final body = methodBody(syncServiceSrc, 'syncWorkoutData');
      expect(body.contains('_syncStreaks'), isTrue);
    });
  });
}
```

The test errs on the side of false-positive: any new prefix without an explicit allowlist entry breaks the test. There is no "mitigation" — that's the bug-catch we want.

### 5.6 — CLAUDE.md sub-section (F6 — discoverability)

**File:** `CLAUDE.md`, append to §15 "Source of Truth Rules"

```markdown
### Sync fan-out contract

Two domain entry points are the contract for "everything in the
{workout, nutrition} domain is now in cloud":

- `SyncService.syncWorkoutData()` MUST fan out to every workoutBox
  prefix and the workout-domain healthBox keys. Currently:
  `_syncWorkoutLogs`, `_syncExerciseLogs`, `_syncScheduleCompletions`,
  `_syncWorkoutTemplates`, `_syncScheduledWorkouts`, `_syncStreaks`.
- `SyncService.syncNutritionData()` MUST fan out to every nutritionBox
  prefix. Currently: `_syncNutritionLogs`, `_syncWaterLogs`,
  `_syncSavedMeals`.

Adding a new Hive prefix in either domain requires updating the matching
`syncX()` AND the contract test
(`test/contracts/sync_fanout_contract_test.dart`).

The 2026-05-03 sync gap (templates / schedules / streaks invisible to
cloud for >24h, **with `scheduled_workouts.template_id` and
`user_saved_meals.id` silently uuid-rejecting since 2026-04-18**) was the
canonical multi-failure-mode this contract prevents. `weeklyFullSync()`
remains the safety net but is no longer the only path for workout-domain
or nutrition-domain rows reaching cloud.
```

### 5.7 — Rank chip hit-test fix (F7 — bundled UX bug)

**File:** `lib/features/profile/widgets/profile_identity.dart` (already patched in working tree from earlier in the session, awaiting commit)

**Bug:** The Theme B compact rank chip rendered in the banner-overlap row but never received taps. Root cause: the outer `Stack(clipBehavior: Clip.none)` auto-sized to the 140-px banner, and the `Positioned(bottom: -40)` row pushed the chip 4–36 px BELOW the Stack's render bottom. Stack only hit-tests within its own render bounds → chip body is outside → taps fall through to the next sibling (`SizedBox(height: 50)`).

The avatar in the same row still works because the avatar's 80 px container straddles the Stack's bottom edge — its top half stays inside hit-test bounds. The chip and the GO PRO pill are both fully below the bottom edge; both were silently broken (the user only noticed the chip because GO PRO is a paid action they hadn't tried).

**Fix:**

```dart
// Before
Stack(
  clipBehavior: Clip.none,
  children: [
    GestureDetector(child: bannerStack),       // 140 px tall
    Positioned(bottom: -40, ..., child: row),  // overflow → not hit-tested
  ],
),
const SizedBox(height: 50),

// After
SizedBox(
  height: 180,
  child: Stack(
    children: [
      GestureDetector(child: bannerStack),    // still 140 px tall, anchored top
      Positioned(bottom: 0, ..., child: row), // bottom of 180-px Stack
    ],
  ),
),
const SizedBox(height: 10),                   // was 50; SizedBox absorbed the +40
```

Visual position preserved exactly:
- Banner: Y=0 → Y=140 (unchanged)
- Row.bottom: Y=180 (unchanged — was banner.bottom + 40 = 180; now Stack.bottom = 180)
- Name row: starts at Y=190 (unchanged — was 140+50; now 180+10)

Hit-test region of the Stack now covers Y=0 → Y=180 instead of Y=0 → Y=140. The chip + GO PRO body (Y≈143–178) is entirely inside.

This fix is ALREADY APPLIED in the working tree from earlier in the same session, with `Theme B fix · Test #8 follow-up` comments documenting the change. It compiles, `flutter analyze lib/features/profile/widgets/profile_identity.dart` returns "No issues found!", and `flutter test test/profile/` passes 20/20.

**Side-effect benefit:** the GO PRO pill (also previously inside the Stack overflow region) becomes tappable too. No code change needed — the fix to Stack hit-test bounds inherently reaches every Positioned child in that row.

## 6. Data flow

After the fix, every workout-domain mutation site (Train screen, Active Workout, Edit Log, Template Builder, Schedule reschedule, AI tool dispatcher write paths, etc.) executes the existing pattern:

```
mutation → Hive write → unawaited(SyncService.instance.syncWorkoutData())
                     ↓
                     ├─ _syncWorkoutLogs        (wlog_*)
                     ├─ _syncExerciseLogs       (exlog_*)
                     ├─ _syncScheduleCompletions (schedule_*.status updates)
                     ├─ _syncWorkoutTemplates   (tmpl_*)
                     ├─ _syncScheduledWorkouts  (schedule_* full rows, F3 fixed)
                     └─ _syncStreaks            (healthBox['streaks'])
```

Same shape for nutrition. The fan-out runs in parallel via `Future.wait(eagerError: false)` so a single helper failing doesn't block the others.

## 7. Error handling

Existing pattern preserved:
- Each helper wraps its upsert in try/catch.
- Failure logs locally and posts a `client_errors` row via `_reportSyncFailure`.
- The next mutation retries the full fan-out — no manual retry needed.

After F3+F4, the upserts that were silently throwing should now succeed. If they still throw post-fix (e.g. a column was added or RLS changed), the existing `client_errors` telemetry catches it.

## 8. Testing strategy

| Layer | Test | Catches |
|---|---|---|
| Unit | `test/contracts/sync_fanout_contract_test.dart` (NEW, 3 tests) | Drift in fan-out coverage when new prefixes are added |
| Unit | Existing `test/sync/sync_gap_test.dart` (UNCHANGED) | Mutation sites that forget to call `syncX()` |
| Unit | Existing `test/contracts/workout_write_to_read_contract_test.dart` (UNCHANGED) | Hive writer↔reader contract |
| Unit | Existing `test/profile/` suite (UNCHANGED) | Profile widget tests; 20/20 still pass after F7 |
| Integration | Manual on-device verification post-deploy: (1) create a template, schedule it, complete it; then run `SELECT count(*) FROM workout_templates / scheduled_workouts / streaks WHERE user_id = …` against Supabase — all three should be ≥ 1 within seconds. (2) Tap the rank chip in the profile banner — the Service Record bottom sheet should open. Tap the GO PRO pill — paywall should open. |

The manual verification step is documented in the implementation plan; not automated for this batch (no Supabase mock infrastructure in the test suite).

## 9. Risk register

| Risk | Mitigation |
|---|---|
| F3's `_deterministicId(templateId)` produces a UUID that doesn't match the parent `workout_templates.id` already in cloud | Both projections use the same `_deterministicId(hiveTemplateString)` function with the same input → byte-identical UUIDs. Verified by reading both call sites — `_syncWorkoutTemplates` line 2991 and the new F3 path use `_deterministicId(hiveId)` with the same `tmpl_<ms>` input. |
| F4 `_deterministicId(saved_meal_<hash>)` collides with an existing cloud row written by a previous APK | `_deterministicId` is deterministic (same input → same UUID). Existing rows are pre-fix and don't exist (cloud `user_saved_meals` shows the same drought as templates). No collision risk on first push. |
| Fan-out broadening adds latency to each mutation (now 6 upserts in parallel instead of 3) | `Future.wait` runs them in parallel. Each individual helper iterates one Hive box prefix — typical user has <10 templates, <100 schedule entries, <30 streak weeks. Net latency dominated by network round-trip, not local work. Acceptable. |
| Contract test source-grep regex misses a non-standard prefix construction | The test fails-closed (any unmatched prefix = error), so a missed prefix becomes a future-detection event when someone adds a new write site. Better than the silent-success alternative. |
| Helper failures still get swallowed by `_safeRestoreOp` and surface only in `client_errors` | Out of scope for this batch (UI surfacing of sync failures is its own feature). Telemetry is sufficient — `client_errors` is queryable post-deploy to detect new failure modes. |
| F7 SizedBox(height: 180) might affect screens that compose ProfileIdentity in unusual ways | Only one consumer: `lib/features/profile/screens/profile_screen.dart`. Visual position of every sibling preserved by the +40 → -40 SizedBox compensation. 20/20 profile tests pass post-fix. |

## 10. Out of scope (deferred to future batches)

- Health-domain sync (weight, measurements, sleep, steps) — stays in `weeklyFullSync()`.
- Per-write sync inside `WorkoutWriteService` / `NutritionWriteService` — bigger refactor.
- UI surfacing of silent sync failures.
- Hive-vanish-on-APK-install investigation (separate brainstorm).
- Backfill RPC for users whose templates / schedules / streaks never made it to cloud — F1+F3 means automatic backfill on next mutation.

## 11. Approval & next step

Approved 2026-05-03 by Upendra after the Supabase audit surfaced F3 + F4 as latent UUID-coercion bugs that the original C scope would have left unfixed.

**Next:** invoke `superpowers:writing-plans` to convert this spec into a step-by-step implementation plan with TDD sub-tasks for the contract test, explicit manual-verification steps for the projection fixes, and a commit-the-already-staged-rank-chip-fix step for F7.

## 12. Scope summary

| # | Theme | Lines | Type | Status |
|---|---|---|---|---|
| F1 | `syncWorkoutData()` fan-out | ~6 | Mechanical | Pending implementation |
| F2 | `syncNutritionData()` fan-out | ~3 | Mechanical | Pending implementation |
| F3 | `_syncScheduledWorkouts` UUID coercion | ~5 | Bug fix | Pending implementation |
| F4 | `_syncSavedMeals` UUID coercion | ~3 | Bug fix | Pending implementation |
| F5 | `test/contracts/sync_fanout_contract_test.dart` (NEW) | ~120 | Test infra | Pending implementation |
| F6 | CLAUDE.md §15 sub-section | ~12 | Doc | Pending implementation |
| F7 | Rank chip hit-test fix in `profile_identity.dart` | ~12 net (15 added, 3 removed) | Bug fix | **Already applied in working tree** — needs commit boundary |
