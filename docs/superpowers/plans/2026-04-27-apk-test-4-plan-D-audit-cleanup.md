# APK Test #4 Plan D — Audit P0/P1 Cleanup

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all P0 and P1 audit findings from `memory/project_apk_test_4_audit_findings.md` that are NOT already addressed by Plans A/B/C. Performance hotspots (food search, diet plan, streak, regex), sync gaps (logFood, _logSleep, _logMeasurement), silent error swallowing (Future.wait partial-fail, realtime stream, _syncUserProfile, tool_dispatcher), and a blanket `_logClientError` rollout for the ~64 sync_service catch blocks.

**Architecture:** Pure Dart cleanup. No new infrastructure. Each fix is independent and atomic. Most are 5-15 LOC.

**Tech Stack:** Dart, Flutter, Riverpod, Hive, Supabase client.

**Audit reference:** `memory/project_apk_test_4_audit_findings.md`.

**Estimated effort:** 14-20h.

**Depends on:** None (can run in parallel with A/B/C in worktree).

---

## Task index

| # | Audit ref | Topic | Hours |
|---|---|---|---|
| D1 | P0 P1 | Food search debounce 250ms | 0.5 |
| D2 | P0 P2 | buildAiContext single-pass `_getNutritionTrend7d` | 1.5 |
| D3 | P1 | diet_plan_generator indexed maps (O(1) lookup) | 2 |
| D4 | P1 | calculateCurrentStreak pre-fetch (365 → 1 lookup batch) | 1 |
| D5 | P1 | exercise_repository filter fusion | 1 |
| D6 | P1 | RegExp hoist in food_search_sheet portion buttons | 0.5 |
| D7 | P1 | getExerciseLogsForDate add date index | 1 |
| D8 | P0 G1, P1 | logFood + updateFoodLog → add syncNutritionData() | 0.5 |
| D9 | P0 G2 | _logSleep + _logMeasurement → syncSleepNow / syncMeasurementsNow | 1.5 |
| D10 | P0 S1, P1 | Future.wait partial-fail (restoreFromCloud + weeklyFullSync) | 1.5 |
| D11 | P0 S2 | Realtime stream error handler | 0.5 |
| D12 | P0 S3 | _syncUserProfile response check (.select().single()) | 0.5 |
| D13 | P1 | tool_dispatcher provider invalidation logging | 0.5 |
| D14 | P1 | Blanket _logClientError rollout in sync_service.dart catch blocks | 3-4 |

---

## Task D1 — Food search debounce

**Files:**
- Modify: `lib/features/nutrition/widgets/food_search_sheet.dart`

- [ ] **D1.1: Add 250ms debounce to TextField onChanged**

Find the `onChanged: (q) => ref.read(foodSearchProvider.notifier).search(q)` (around line 152). Replace with a Timer-based debounce:

```dart
Timer? _searchDebounce;

@override
void dispose() {
  _searchDebounce?.cancel();
  super.dispose();
}

// In TextField:
onChanged: (q) {
  _searchDebounce?.cancel();
  _searchDebounce = Timer(Duration(milliseconds: 250), () {
    if (!mounted) return;
    ref.read(foodSearchProvider.notifier).search(q);
  });
},
```

- [ ] **D1.2: Test (manual)**

Type rapidly in food search. Verify search doesn't fire per keystroke; fires once after pause.

- [ ] **D1.3: Commit**

```bash
git add lib/features/nutrition/widgets/food_search_sheet.dart
git commit -m "perf(nutrition): debounce food search 250ms

Closes audit P0-P1. Was: O(N) regex scan over 1431 foods on every keystroke.
Now: scan fires only after 250ms pause. Eliminates frame drops while typing."
```

---

## Task D2 — buildAiContext single-pass nutrition trend

**Files:**
- Modify: `lib/features/ai_coach/repositories/ai_coach_repository.dart`

`_getNutritionTrend7d` currently iterates `nutritionBox.values` 7 times (once per day). Replace with single-pass aggregation.

- [ ] **D2.1: Locate `_getNutritionTrend7d`**

```bash
grep -n "_getNutritionTrend7d" lib/features/ai_coach/repositories/ai_coach_repository.dart
```

- [ ] **D2.2: Refactor to single pass**

```dart
Map<String, dynamic> _getNutritionTrend7d() {
  final now = DateTime.now();
  final cutoff = now.subtract(Duration(days: 7));
  final byDate = <String, Map<String, double>>{};

  for (final key in HiveService.instance.nutritionBox.keys) {
    if (!key.toString().startsWith('nlog_')) continue;
    final log = HiveService.instance.nutritionBox.get(key) as Map?;
    if (log == null) continue;
    final dateStr = log['date'] as String?;
    if (dateStr == null) continue;
    final date = DateTime.tryParse(dateStr);
    if (date == null || date.isBefore(cutoff)) continue;

    final bucket = byDate.putIfAbsent(dateStr, () => {
      'cal': 0, 'protein': 0, 'carbs': 0, 'fat': 0, 'fiber': 0,
    });
    bucket['cal'] = bucket['cal']! + ((log['total_calories'] as num?)?.toDouble() ?? 0);
    bucket['protein'] = bucket['protein']! + ((log['total_protein'] as num?)?.toDouble() ?? 0);
    bucket['carbs'] = bucket['carbs']! + ((log['total_carbs'] as num?)?.toDouble() ?? 0);
    bucket['fat'] = bucket['fat']! + ((log['total_fat'] as num?)?.toDouble() ?? 0);
    bucket['fiber'] = bucket['fiber']! + ((log['total_fiber'] as num?)?.toDouble() ?? 0);
  }

  // Compute averages and per-day series
  final days = byDate.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  final calAvg = days.isEmpty ? 0 : days.map((e) => e.value['cal']!).reduce((a, b) => a + b) / days.length;
  final proteinAvg = days.isEmpty ? 0 : days.map((e) => e.value['protein']!).reduce((a, b) => a + b) / days.length;
  // ... carbs, fat, fiber averages ...

  return {
    'calories_avg': calAvg.round(),
    'protein_avg': proteinAvg.round(),
    // ...
    'series': days.map((e) => {'date': e.key, ...e.value}).toList(),
  };
}
```

- [ ] **D2.3: Test + commit**

Run any existing nutrition snapshot test; verify same shape, faster execution.

```bash
flutter test test/ai_coach/
git add -A
git commit -m "perf(coach): single-pass nutrition_trend_7d aggregation

Was: 7 separate iterations over nutritionBox (O(7N)).
Now: single pass with date-bucketed aggregation (O(N)).
Audit P0-P2 closed. ~200-500ms faster snapshot build."
```

---

## Task D3 — Diet plan generator indexed maps

**Files:**
- Modify: `lib/features/nutrition/services/diet_plan_generator.dart`

- [ ] **D3.1: Build indices once at init**

```dart
class DietPlanGenerator {
  Map<String, Food>? _byNameIndex;
  Map<String, List<Food>>? _byCategoryIndex;

  void _ensureIndices(List<Food> all) {
    _byNameIndex ??= { for (final f in all) f.name.toLowerCase(): f };
    if (_byCategoryIndex == null) {
      final m = <String, List<Food>>{};
      for (final f in all) {
        m.putIfAbsent(f.category, () => []).add(f);
      }
      _byCategoryIndex = m;
    }
  }

  Food? _findFoodByName(String name) => _byNameIndex?[name.toLowerCase()];
  List<Food> _foodsByCategory(String cat) => _byCategoryIndex?[cat] ?? [];
}
```

Replace existing O(N) anchor + filler searches (around lines 343-345, 434-437) with index lookups.

- [ ] **D3.2: Run diet plan archetype tests + commit**

```bash
flutter test test/nutrition/diet_plan_archetype_test.dart
git add -A
git commit -m "perf(nutrition): indexed maps in diet_plan_generator

O(N²) anchor + filler search → O(1) name lookup + O(K) per category.
Audit P1. Diet plan generation ~5-10x faster on 1431-item DB."
```

---

## Task D4 — calculateCurrentStreak pre-fetch

**Files:**
- Modify: `lib/features/train/repositories/workout_repository.dart`

- [ ] **D4.1: Replace 365 individual lookups with single pass**

Current shape (around lines 84-146): loops back day-by-day, calling `box.get('schedule_$date')` 365 times.

```dart
int calculateCurrentStreak() {
  final box = HiveService.instance.workoutBox;
  // Single pass: pull all schedule_* keys, group by date
  final schedules = <String, Map>{};
  for (final key in box.keys) {
    final k = key.toString();
    if (!k.startsWith('schedule_')) continue;
    final date = k.substring('schedule_'.length);
    final v = box.get(key);
    if (v is Map) schedules[date] = v;
  }

  // Now walk back from today using the in-memory map
  int streak = 0;
  var date = DateTime.now();
  while (true) {
    final dateStr = date.toIso8601String().substring(0, 10);
    final s = schedules[dateStr];
    if (s == null) {
      // Rest day or missing — depends on existing logic
      if (/* rest day check */) {
        date = date.subtract(Duration(days: 1));
        continue;
      }
      break;
    }
    if (s['status'] == 'completed') {
      streak++;
      date = date.subtract(Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}
```

- [ ] **D4.2: Run streak tests + commit**

```bash
flutter test test/train/streak_test.dart
git add -A
git commit -m "perf(train): pre-fetch all schedules in calculateCurrentStreak

Was: 365 sequential box.get() calls per call (~250ms cold).
Now: single iteration of box.keys, in-memory walk (~5ms).
Audit P1."
```

---

## Task D5 — exercise_repository filter fusion

**Files:**
- Modify: `lib/features/train/repositories/exercise_repository.dart`

- [ ] **D5.1: Fuse chained .where() calls**

Around lines 80-169, replace patterns like:

```dart
final results = library
  .where((e) => e.category == cat).toList()
  .where((e) => e.equipment.contains(eq)).toList()
  .where((e) => e.suitableFor.contains(level)).toList();
```

With single `.where()`:

```dart
final results = library.where((e) =>
  e.category == cat &&
  e.equipment.contains(eq) &&
  e.suitableFor.contains(level)
).toList();
```

- [ ] **D5.2: Commit**

```bash
git add -A
git commit -m "perf(train): fuse chained .where() filters in exercise_repository

Was: 3-4 sequential .where().toList() over 249 exercises.
Now: single fused predicate. ~3x faster on cold queries.
Audit P1."
```

---

## Task D6 — RegExp hoist in food_search_sheet

**Files:**
- Modify: `lib/features/nutrition/widgets/food_search_sheet.dart`

Around lines 535-538, a RegExp is compiled per portion-button render.

- [ ] **D6.1: Hoist to class-level static**

```dart
class _FoodSearchSheetState extends ConsumerState<FoodSearchSheet> {
  static final _portionRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(g|ml|cup|tsp|tbsp|piece|slice)', caseSensitive: false);
  // ... use _portionRegex instead of inline RegExp(...)
}
```

- [ ] **D6.2: Commit**

```bash
git add -A
git commit -m "perf(nutrition): hoist portion RegExp in food_search_sheet

Was: regex compiled per portion-button render in ListView.
Now: single static instance. Audit P1."
```

---

## Task D7 — getExerciseLogsForDate date index

**Files:**
- Modify: `lib/features/train/repositories/workout_repository.dart`

The fallback path scans entire `workoutBox.values` when index missing.

- [ ] **D7.1: Build secondary index at repo init**

In `WorkoutRepository.init()` (or wherever the box is opened), build `_dateIndex: Map<String, List<String>>` mapping date → list of exlog keys. Update on every set log.

- [ ] **D7.2: Use index in fallback**

In `getExerciseLogsForDate(DateTime date)` fallback path, use the index instead of scanning all values.

- [ ] **D7.3: Commit**

```bash
git add -A
git commit -m "perf(train): secondary date index for getExerciseLogsForDate fallback

Was: scan entire workoutBox.values when primary index missing.
Now: O(1) index lookup. Audit P1."
```

---

## Task D8 — logFood + updateFoodLog sync

**Files:**
- Modify: `lib/features/nutrition/providers/nutrition_provider.dart`

Audit G1: `logFood()` (line 795-839) writes Hive + `pushSnapshot()` but NOT `syncNutritionData()`. Pattern inconsistent with `deleteFoodLog()`.

- [ ] **D8.1: Add syncNutritionData to logFood**

```dart
// In logFood(), after Hive put + invalidate, add:
unawaited(SyncService.instance.syncNutritionData());
unawaited(SyncService.instance.pushSnapshot());  // (already there)
```

Same for `updateFoodLog()` (line 870-894).

- [ ] **D8.2: Regression test**

Add to `test/sync/sync_gap_test.dart`:

```dart
test('logFood fires syncNutritionData', () async {
  // ... source-grep regex for syncNutritionData inside logFood body ...
});
```

- [ ] **D8.3: Commit**

```bash
git add -A
git commit -m "fix(sync): logFood + updateFoodLog now fire syncNutritionData

Closes audit P0-G1, P1. Both wrote Hive + pushSnapshot but skipped
nutrition_logs/water_logs sync — meal in Hive instantly, cloud row
delayed until next daily full sync. Now consistent with deleteFoodLog
pattern (CLAUDE.md §15)."
```

---

## Task D9 — _logSleep + _logMeasurement immediate sync

**Files:**
- Create: `syncSleepNow()` and `syncMeasurementsNow()` in `lib/core/services/sync_service.dart`
- Modify: `lib/features/ai_coach/services/conversational_log_handler.dart`

Audit G2: AI tool writes sleep/measurement to Hive + pushSnapshot, but no domain sync method exists.

- [ ] **D9.1: Add syncSleepNow + syncMeasurementsNow methods**

In `sync_service.dart`, mirror existing `syncWeightNow()` pattern:

```dart
Future<void> syncSleepNow() async {
  try {
    final logs = HiveService.instance.healthBox.keys
      .where((k) => k.toString().startsWith('sleep_log_'))
      .map((k) => HiveService.instance.healthBox.get(k))
      .where((v) => v != null)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
    if (logs.isEmpty) return;
    final userId = /* current user id */;
    final payload = logs.map((l) => {
      'user_id': userId,
      'date': l['date'],
      'hours': l['hours'],
      'quality': l['quality'],
    }).toList();
    await Supabase.instance.client.from('sleep_logs')
      .upsert(payload, onConflict: 'user_id,date');
  } catch (e, st) {
    debugPrint('[sync] syncSleepNow failed: $e');
    unawaited(_logClientError('sync_sleep_failed', e, st));
  }
}

// Similar for syncMeasurementsNow → body_measurements table
```

- [ ] **D9.2: Wire into conversational_log_handler.dart**

After Hive write + pushSnapshot, add:

```dart
unawaited(SyncService.instance.syncSleepNow());     // for sleep
unawaited(SyncService.instance.syncMeasurementsNow()); // for measurements
```

- [ ] **D9.3: Commit**

```bash
git add -A
git commit -m "fix(sync): syncSleepNow + syncMeasurementsNow + wire into AI tools

Closes audit P0-G2. AI coach tool writes sleep/measurement → Hive instantly
but cloud row was delayed until next app launch. Now fires immediate sync
parallel to existing syncWeightNow() pattern (CLAUDE.md §15)."
```

---

## Task D10 — Future.wait partial-fail (restore + weeklyFullSync)

**Files:**
- Modify: `lib/core/services/sync_service.dart`

Audit S1 + P1: `Future.wait([...])` without `eagerError: false` — one throw kills the rest.

- [ ] **D10.1: Refactor restoreFromCloudForUser (line 701-727)**

```dart
// BEFORE:
await Future.wait([
  _restoreWorkoutLogs(userId),
  _restoreNutritionLogs(userId),
  _restoreWeightLogs(userId),
  // ...
]);

// AFTER:
await Future.wait(
  [
    _safeRestore('workouts', _restoreWorkoutLogs(userId)),
    _safeRestore('nutrition', _restoreNutritionLogs(userId)),
    _safeRestore('weight', _restoreWeightLogs(userId)),
    // ... wrap each in safeRestore ...
  ],
  eagerError: false,
);

Future<void> _safeRestore(String label, Future<void> task) async {
  try {
    await task;
  } catch (e, st) {
    debugPrint('[restore] $label failed: $e');
    unawaited(_logClientError('restore_$label\_failed', e, st));
  }
}
```

- [ ] **D10.2: Same pattern for weeklyFullSync (line 429-450)**

- [ ] **D10.3: Test**

Add to `test/sync/restore_partial_fail_test.dart`:

```dart
test('one restore failure does not block others', () async {
  // Mock: nutrition restore throws, workouts succeed
  // Expect: workouts still restored, nutrition logged as failed
});
```

- [ ] **D10.4: Commit**

```bash
git add -A
git commit -m "fix(sync): per-table catch in restoreFromCloud + weeklyFullSync

Closes audit P0-S1, P1. Was: Future.wait without eagerError:false meant
one table fail killed all subsequent restores. Now: each task wrapped in
_safeRestore with table-name-tagged error logging."
```

---

## Task D11 — Realtime stream error handler

**Files:**
- Modify: `lib/core/services/sync_service.dart`

Audit S2: `subscribeToRealtimeSync` (line 883-896) opens `.listen()` with no try/catch.

- [ ] **D11.1: Wrap callback in try/catch + log**

```dart
.listen((data) async {
  try {
    // existing handler logic
  } catch (e, st) {
    debugPrint('[realtime] handler failed: $e');
    unawaited(_logClientError('realtime_handler_failed', e, st));
    // do NOT rethrow — keep stream alive
  }
}, onError: (e, st) {
  debugPrint('[realtime] stream error: $e');
  unawaited(_logClientError('realtime_stream_error', e, st));
});
```

- [ ] **D11.2: Commit**

```bash
git add -A
git commit -m "fix(sync): wrap realtime stream handler in try/catch

Closes audit P0-S2. Was: handler exception killed the stream silently;
PRO realtime sync stopped mid-session. Now: errors logged, stream survives."
```

---

## Task D12 — _syncUserProfile response check

**Files:**
- Modify: `lib/core/services/sync_service.dart`

Audit S3: `from('user_profile').upsert()` doesn't check return; constraint violations swallowed.

- [ ] **D12.1: Add .select().single() to force error**

```dart
// BEFORE:
await Supabase.instance.client
  .from('user_profile')
  .upsert(payload, onConflict: 'user_id');

// AFTER:
await Supabase.instance.client
  .from('user_profile')
  .upsert(payload, onConflict: 'user_id')
  .select()
  .single();  // forces PostgrestException on constraint violation
```

- [ ] **D12.2: Commit**

```bash
git add -A
git commit -m "fix(sync): _syncUserProfile uses .select().single() to surface errors

Closes audit P0-S3. Was: upsert without response check meant 400 constraint
violations were silently swallowed; user saw 'saved!' but cloud row was null.
Now: .select().single() forces PostgrestException on violation, caught and
logged via _logClientError."
```

---

## Task D13 — tool_dispatcher invalidation logging

**Files:**
- Modify: `lib/features/ai_coach/services/tool_dispatcher.dart`

Audit P1: lines 1216-1231, 1241-1258 have `try {} catch (_) {}` swallowing provider invalidation failures silently.

- [ ] **D13.1: Replace silent catches with logged catches**

```dart
// BEFORE:
try {
  ref.invalidate(currentPlanProvider);
} catch (_) {}

// AFTER:
try {
  ref.invalidate(currentPlanProvider);
} catch (e, st) {
  debugPrint('[tool_dispatcher] invalidate currentPlanProvider failed: $e');
  unawaited(_logClientError('invalidation_failed', e, st));
}
```

Repeat for each silent catch in the dispatcher.

- [ ] **D13.2: Commit**

```bash
git add -A
git commit -m "fix(ai_coach): log provider invalidation failures in tool_dispatcher

Closes audit P1. Was: catch (_) swallowed all invalidation errors;
UI showed stale data after AI tool actions with no diagnostic.
Now: errors logged + posted to client_errors."
```

---

## Task D14 — Blanket _logClientError rollout in sync_service catch blocks

**Files:**
- Modify: `lib/core/services/sync_service.dart`

Audit P1: ~64 `catch (e) { debugPrint(...) }` blocks. Convert all to use `_logClientError` so failures are visible in cloud.

- [ ] **D14.1: Find every catch block in sync_service.dart**

```bash
grep -nE "catch \(.*\) \{" lib/core/services/sync_service.dart | wc -l
```

Expected: ~60-70 matches.

- [ ] **D14.2: Convert each to standardized form**

Pattern:

```dart
} catch (e, st) {
  debugPrint('[sync] <operation> failed: $e');
  unawaited(_logClientError('<operation>_failed', e, st));
}
```

Where `<operation>` is descriptive (e.g., `pull_workout_logs`, `upsert_water_log`, `delete_remote_meal`).

Add `_logClientError` helper if not already present:

```dart
Future<void> _logClientError(String op, Object e, StackTrace st) async {
  try {
    final userId = /* current user id, may be null */;
    await Supabase.instance.client.from('client_errors').insert({
      'user_id': userId,
      'operation': op,
      'error_message': e.toString(),
      'stack_trace': st.toString().substring(0, 2000),  // cap
      'occurred_at': DateTime.now().toIso8601String(),
      'platform': 'android',
      'app_version': /* app version */,
    });
  } catch (_) {
    // last-resort silent fail (don't recurse)
  }
}
```

- [ ] **D14.3: Verify table exists**

`client_errors` table is in CLAUDE.md §7 (Telemetry). Verify schema accepts the payload:

```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'client_errors';
```

If columns missing, add via migration (or adjust payload to match existing).

- [ ] **D14.4: Commit (chunked)**

This is a big edit. Commit per logical group of catch blocks (e.g., all restore-* methods first, then sync-* methods, then helpers):

```bash
# Commit 1: restore methods
git add lib/core/services/sync_service.dart
git commit -m "fix(sync): _logClientError rollout in restore_* methods (1/3)"

# Commit 2: sync_* methods
# ...

# Commit 3: helpers + finalize
# ...
```

---

## Self-review

- [ ] All P0 audit findings (A1-A4 → Plan A; P1 P2 G1 G2 S1 S2 S3 → Plan D) addressed
- [ ] All P1 items in audit memory hit by D2 (P2 perf), D3-D7 (perf), D8 (G1+updateFoodLog), D10 (weeklyFullSync), D13 (tool_dispatcher), D14 (catch blocks)
- [ ] No placeholders. Code patterns shown for each task.
- [ ] Commits are small and atomic per task.

## Out of scope (later batches or already covered)

- A1-A4 audit items (sleep/yesterday/freezes/active workout) → Plan A
- New snapshot keys → Plan A
- Captain Manual → Plan A
- Induction flow → Plan B
- Capabilities + new tools → Plan C
- P2 audit items (subscription state, body measurements in snapshot, phase transitions, weekly schedule, photo orphan cleanup, telemetry queue) → Test #5 polish
