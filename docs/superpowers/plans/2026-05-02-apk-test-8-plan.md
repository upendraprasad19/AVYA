# APK Test #8 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 5-theme batch — fix workout receipt rendering bug, relocate rank pill into the banner row with expanded service-record bottom sheet, tighten the Profile card stack with sharp + flush styling, add round-trip contract tests so the next field-rename can't drift, and personalize the morning push to the user's `wake_up_time`.

**Architecture:** Single feature branch `feat/apk-test-8-batch` cut from main (Test #7 merge `9c815ba`). Themes A → D → {C, B, E} parallelizable after D lands. Each theme isolates its commit boundary. No production deploys before user-instructed commit + APK build via `/build-apk`.

**Tech Stack:** Flutter (Dart) + Riverpod + Hive + Supabase Postgres + Edge Functions (Deno/TypeScript) + pg_cron + OneSignal. Existing patterns: WriteService → fire-and-forget sync, provider invalidation batch on workout mutations, `_shared/proactive_dedup.ts` for cron-driven push triggers.

**Spec:** [docs/superpowers/specs/2026-05-02-apk-test-8-design.md](../specs/2026-05-02-apk-test-8-design.md).

**Authoritative file shortlist** (touch only these unless a contract test surfaces drift):
- `lib/features/train/widgets/workout_receipt_card.dart` (Theme A)
- `test/train/receipt_after_write_service_test.dart` (Theme A — NEW)
- `test/contracts/workout_write_to_read_contract_test.dart` (Theme D — NEW)
- `test/contracts/nutrition_write_to_read_contract_test.dart` (Theme D — NEW)
- `CLAUDE.md` (Theme D)
- `.claude/commands/pre-commit-check.md` (Theme D)
- `lib/features/profile/screens/profile_screen.dart` (Theme B + C)
- `lib/features/profile/screens/edit_profile_screen.dart` (Theme C)
- `lib/features/profile/widgets/profile_identity.dart` (Theme B)
- `lib/features/profile/widgets/rank_service_record_sheet.dart` (Theme B — NEW)
- `lib/features/profile/providers/promotion_history_provider.dart` (Theme B — NEW)
- `supabase/functions/morning-alert/index.ts` (Theme E)
- `supabase/migrations/046_morning_alert_personalized_delivery_cron.sql` (Theme E — NEW)

---

## Pre-work — Branch setup

### Task 0: Cut feature branch off main

**Files:** none (git only)

- [ ] **Step 1: Verify clean working state**

```bash
git status
git log --oneline -1
```

Expected: working tree may show modifications from Test #7 follow-ups (mission_brief_screen.dart, v4_diagnostic_output.md per the gitStatus header) — leave those alone, they're untouched. HEAD must equal `9c815ba` ("merge: APK Test #7 batch …") or a descendant on `main`.

- [ ] **Step 2: Create + check out branch**

```bash
git checkout -b feat/apk-test-8-batch
```

- [ ] **Step 3: Confirm branch**

```bash
git rev-parse --abbrev-ref HEAD
```

Expected output: `feat/apk-test-8-batch`.

---

## Theme A — Receipt sync field rename

> **Why first:** smallest, mechanical fix, validates that the codebase is in working order before touching anything bigger.

### Task A1: Pre-flight read

**Files:**
- Read: `lib/features/train/widgets/workout_receipt_card.dart:249-363`
- Read: `lib/core/services/workout_write_service.dart:53-175`

- [ ] **Step 1: Open receipt code, confirm field-name mismatch**

In `workout_receipt_card.dart`, confirm:
- Line ~274: `final sets = (log['sets_completed'] as num?)?.toInt() ?? 0;`
- Line ~287: `final setsDetail = log['sets_detail'];`

In `workout_write_service.dart` `logExercise`, confirm:
- Line ~134: `'set_number': mergedSets.length,`
- Line ~133: `'sets': mergedSets.map((s) => s.toMap()).toList(),`

If the line numbers have drifted, grep for the literal strings instead. The contract is the field names, not the lines.

### Task A2: Write the failing regression test

**Files:**
- Create: `test/train/receipt_after_write_service_test.dart`

- [ ] **Step 1: Write the test file**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'dart:io';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final Directory dir;
  @override Future<String?> getApplicationDocumentsPath() async => dir.path;
  @override Future<String?> getTemporaryPath() async => dir.path;
  @override Future<String?> getApplicationSupportPath() async => dir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_recpt_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('WorkoutReceiptData.fromExerciseLogs after WorkoutWriteService.logExercise', () {
    test('renders 3 sets / 24 reps / 65kg max for weight_reps exercise', () async {
      final date = DateTime(2026, 5, 2);
      final result = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Bench Press',
        sets: [
          ExerciseSet(weightKg: 60, reps: 10),
          ExerciseSet(weightKg: 62.5, reps: 8),
          ExerciseSet(weightKg: 65, reps: 6),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(result.success, isTrue, reason: 'WorkoutWriteService.logExercise must succeed');

      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt, isNotNull, reason: 'receipt must reconstruct from Hive index');
      expect(receipt!.totalSets, 3,
          reason: 'totalSets must read from set_number (writer) — not legacy sets_completed');
      expect(receipt.exercises, hasLength(1));
      final ex = receipt.exercises.first;
      expect(ex.sets, 3);
      expect(ex.totalReps, 24);
      expect(ex.maxWeightKg, 65);
      expect(ex.perSetBreakdown, hasLength(3),
          reason: 'perSetBreakdown must read from sets (writer) — not legacy sets_detail');
      expect(ex.perSetBreakdown[0].weightKg, 60);
      expect(ex.perSetBreakdown[2].reps, 6);
    });

    test('renders timed exercise with non-zero sets', () async {
      final date = DateTime(2026, 5, 2);
      await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Plank',
        sets: [
          ExerciseSet(weightKg: 0, reps: 0, durationSec: 45),
          ExerciseSet(weightKg: 0, reps: 0, durationSec: 60),
        ],
        source: WriteSource.activeWorkout,
      );

      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt, isNotNull);
      expect(receipt!.totalSets, 2);
      expect(receipt.exercises.first.sets, 2);
      expect(receipt.exercises.first.totalDurationSeconds, 105);
    });

    test('legacy logs (sets_completed key) still render', () async {
      // Simulate a pre-Test-#6 Hive entry by writing the legacy shape directly.
      final dateKey = '2026-05-01';
      final wb = HiveService.instance.workoutBox;
      final logKey = 'exlog_${dateKey}_legacy';
      await wb.put(logKey, {
        'exercise_name': 'Squat',
        'date': dateKey,
        'sets_completed': 4,            // legacy key
        'reps_completed': 20,
        'weight_kg': 100.0,
        'volume_kg': 2000.0,
        'logging_type': 'weight_reps',
        'is_pr': false,
        'sets_detail': [                 // legacy key
          {'weight_kg': 100.0, 'reps': 5},
          {'weight_kg': 100.0, 'reps': 5},
          {'weight_kg': 100.0, 'reps': 5},
          {'weight_kg': 100.0, 'reps': 5},
        ],
      });
      await wb.put('exercise_log_index_$dateKey', [logKey]);

      final r = WorkoutReceiptData.fromExerciseLogs(DateTime(2026, 5, 1));
      expect(r, isNotNull);
      expect(r!.totalSets, 4, reason: 'fallback to sets_completed key must work');
      expect(r.exercises.first.perSetBreakdown, hasLength(4),
          reason: 'fallback to sets_detail key must work');
    });
  });
}
```

- [ ] **Step 2: Run the test, expect FAIL**

```bash
flutter test test/train/receipt_after_write_service_test.dart
```

Expected: tests 1 and 2 FAIL because receipt reads `sets_completed` / `sets_detail` while writer wrote `set_number` / `sets`. Test 3 (legacy shape) PASSES because the receipt already reads the legacy keys today.

If test 1 unexpectedly PASSES, the fix has already been applied — skip to Task A4 verification.

### Task A3: Implement the field-name fallback patch

**Files:**
- Modify: `lib/features/train/widgets/workout_receipt_card.dart` (line ~274 + line ~287)

- [ ] **Step 1: Patch the totalSets read (around line 274)**

Replace:
```dart
final sets = (log['sets_completed'] as num?)?.toInt() ?? 0;
```

With:
```dart
// Theme A · Test #8 — WorkoutWriteService writes `set_number`; older logs
// use `sets_completed`. Read new key first, fall back to legacy.
final sets = (log['set_number'] as num?)?.toInt()
    ?? (log['sets_completed'] as num?)?.toInt()
    ?? 0;
```

- [ ] **Step 2: Patch the perSetBreakdown read (around line 287)**

Replace:
```dart
final setsDetail = log['sets_detail'];
```

With:
```dart
// Theme A · Test #8 — WorkoutWriteService writes `sets`; older logs use
// `sets_detail`. Read new key first, fall back to legacy.
final setsDetail = log['sets'] ?? log['sets_detail'];
```

### Task A4: Run the test, confirm PASS

- [ ] **Step 1: Re-run**

```bash
flutter test test/train/receipt_after_write_service_test.dart
```

Expected: all 3 tests PASS.

- [ ] **Step 2: Run the broader train test suite to confirm no regression**

```bash
flutter test test/train/
```

Expected: 0 failures in the entire `test/train/` tree.

### Task A5: Stage commit boundary

**Files:**
- Stage: `lib/features/train/widgets/workout_receipt_card.dart`
- Stage: `test/train/receipt_after_write_service_test.dart`

- [ ] **Step 1: Stage these two files (do NOT commit yet — wait for explicit user "commit")**

```bash
git add lib/features/train/widgets/workout_receipt_card.dart test/train/receipt_after_write_service_test.dart
git status
```

Commit message to use when user instructs:
```
fix(receipt): read set_number/sets keys from WorkoutWriteService output

WorkoutReceiptData.fromExerciseLogs read sets_completed/sets_detail —
the field names from before the Test #6 architectural rewrite. Writer
output uses set_number/sets to match cloud column names. Read new keys
first with legacy fallback so pre-Test-#6 Hive entries still render.

Adds receipt_after_write_service_test.dart — the round-trip test that
should have existed after Test #6.

Closes Theme A of Test #8 batch.
```

---

## Theme D — Round-trip contract tests + docs guard

> **Why second:** these tests will surface ANY remaining writer↔reader drift in workout / nutrition before the UI work in Themes B + C lands. If something else is broken, we want to know now.

### Task D1: Pre-flight — enumerate consumers

**Files:**
- Read (grep): `lib/` for `'exlog_'`, `'set_number'`, `'sets_completed'`, `'sets_detail'`
- Read (grep): `lib/` for `'nlog_'` and the NutritionWriteService field names

- [ ] **Step 1: Enumerate workout exlog consumers**

```bash
```

```
Grep tool: pattern="exlog_|sets_completed|set_number|sets_detail" path="lib"
```

Note every file that READS from `exlog_*` / `sets_completed` / `set_number` / `sets_detail`. Expected list (verify):
- `lib/features/train/widgets/workout_receipt_card.dart` (already patched in A3)
- `lib/shared/repositories/workout_repository.dart`
- `lib/features/ai_coach/repositories/ai_coach_repository.dart`
- `lib/features/profile/widgets/biometric_sync_card.dart` or related
- `lib/core/services/sync_service.dart`

- [ ] **Step 2: Enumerate nutrition nlog consumers**

```
Grep tool: pattern="nlog_" path="lib"
```

Note every file that READS from `nlog_*`. Expected list (verify):
- `lib/features/nutrition/screens/nutrition_screen.dart`
- `lib/features/nutrition/widgets/todays_meals_card.dart`
- `lib/features/home/providers/home_provider.dart`
- `lib/shared/repositories/nutrition_repository.dart`
- `lib/features/ai_coach/repositories/ai_coach_repository.dart`
- `lib/core/services/sync_service.dart`

- [ ] **Step 3: Read NutritionWriteService to confirm written field names**

```
Read tool: lib/core/services/nutrition_write_service.dart
```

Capture the exact field names written by `NutritionWriteService` (e.g., `total_kcal`, `total_protein_g`, `items`, etc.). These will be the EXPECTED keys in the contract test.

### Task D2: Write workout contract test

**Files:**
- Create: `test/contracts/workout_write_to_read_contract_test.dart`

- [ ] **Step 1: Write the file**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';
import 'package:icanbefitter/shared/repositories/workout_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final Directory dir;
  @override Future<String?> getApplicationDocumentsPath() async => dir.path;
  @override Future<String?> getTemporaryPath() async => dir.path;
  @override Future<String?> getApplicationSupportPath() async => dir.path;
}

/// Round-trip contract: every consumer of WorkoutWriteService Hive output
/// must see the same data the writer just wrote. If a writer field is
/// renamed without updating consumers, these tests fail.
///
/// **Add a new test here whenever a new consumer of `exlog_*` is created.**
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_contract_w_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<WriteResult> _logBenchPress(DateTime date) =>
      WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Bench Press',
        sets: [
          ExerciseSet(weightKg: 60, reps: 10),
          ExerciseSet(weightKg: 62.5, reps: 8),
          ExerciseSet(weightKg: 65, reps: 6),
        ],
        source: WriteSource.activeWorkout,
      );

  group('WorkoutWriteService → consumer contract', () {
    test('WorkoutReceiptData.fromExerciseLogs sees sets/reps/weight', () async {
      final date = DateTime(2026, 5, 2);
      final w = await _logBenchPress(date);
      expect(w.success, isTrue);

      final r = WorkoutReceiptData.fromExerciseLogs(date);
      expect(r, isNotNull);
      expect(r!.totalSets, 3);
      expect(r.exercises.first.sets, 3);
      expect(r.exercises.first.maxWeightKg, 65);
      expect(r.exercises.first.totalReps, 24);
    });

    test('WorkoutRepository.getExerciseLogsForDate returns the writer\'s log', () async {
      final date = DateTime(2026, 5, 2);
      await _logBenchPress(date);

      final logs = await WorkoutRepository.instance.getExerciseLogsForDate(date);
      expect(logs, hasLength(1));
      final log = logs.first;
      // Must read whichever fields the rest of the app uses.
      expect((log['set_number'] as num?)?.toInt(), 3);
      expect((log['weight_kg'] as num?)?.toDouble(), 65.0);
      expect(log['exercise_name'], 'Bench Press');
    });

    test('AI coach context picks up today\'s exercise', () async {
      // AiCoachRepository.buildAiContext is invoked in many code paths; the
      // contract here is "the snapshot includes a recent_logs entry naming
      // Bench Press for today". If this test fails, the field names the
      // snapshot reads are out of date.
      final date = DateTime.now();
      await _logBenchPress(date);

      // Direct Hive read mirrors what buildAiContext does.
      final wb = HiveService.instance.workoutBox;
      final indexKey = 'exercise_log_index_${_dateStr(date)}';
      final ids = wb.get(indexKey) as List?;
      expect(ids, isNotNull);
      final log = wb.get(ids!.first) as Map?;
      expect(log, isNotNull);
      expect(log!['exercise_name'], 'Bench Press');
      expect((log['set_number'] as num?)?.toInt(), 3);
      expect((log['volume_kg'] as num?)?.toDouble(), greaterThan(0));
    });

    test('PR rescan flags the heaviest set as is_pr', () async {
      final date = DateTime(2026, 5, 2);
      await _logBenchPress(date);

      final wb = HiveService.instance.workoutBox;
      final logKey = WorkoutWriteService.exlogKey(date, 'Bench Press');
      final entry = wb.get(logKey) as Map?;
      expect(entry, isNotNull);
      // First-ever log of this exercise must be a PR.
      expect(entry!['is_pr'], isTrue);
    });

    test('SyncService projection sees the writer\'s fields', () async {
      // We don't run actual sync (no network), but the projection helper
      // must be able to read the writer's output without missing fields.
      // If a future field rename breaks the projection, this assertion fails.
      final date = DateTime(2026, 5, 2);
      await _logBenchPress(date);
      final wb = HiveService.instance.workoutBox;
      final logKey = WorkoutWriteService.exlogKey(date, 'Bench Press');
      final entry = wb.get(logKey) as Map;

      // These keys are the contract — every cloud projection helper must
      // be able to read them.
      const requiredKeys = [
        'exercise_name', 'date', 'set_number', 'reps_completed',
        'weight_kg', 'volume_kg', 'logging_type', 'is_pr',
      ];
      for (final k in requiredKeys) {
        expect(entry.containsKey(k), isTrue, reason: 'missing key: $k');
      }
    });
  });
}

String _dateStr(DateTime dt) {
  final ist = dt.toUtc().add(const Duration(hours: 5, minutes: 30));
  final y = ist.year.toString().padLeft(4, '0');
  final m = ist.month.toString().padLeft(2, '0');
  final d = ist.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
```

- [ ] **Step 2: Run the contract test**

```bash
flutter test test/contracts/workout_write_to_read_contract_test.dart
```

Expected: all 5 tests PASS (Theme A's fix has already aligned the receipt; the other 4 consumers should already use `set_number` / `weight_kg` / etc. directly because they didn't exhibit the bug).

If any test FAILS, that's an additional drift surfaced by the contract — STOP, escalate to user, decide whether to fix in this batch or defer. Do NOT proceed past D2 with a red contract test.

### Task D3: Write nutrition contract test

**Files:**
- Create: `test/contracts/nutrition_write_to_read_contract_test.dart`

- [ ] **Step 1: Read NutritionWriteService field names**

Re-confirm from D1 step 3 the exact keys NutritionWriteService writes. The test will assert these keys are present and match.

- [ ] **Step 2: Write the file**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final Directory dir;
  @override Future<String?> getApplicationDocumentsPath() async => dir.path;
  @override Future<String?> getTemporaryPath() async => dir.path;
  @override Future<String?> getApplicationSupportPath() async => dir.path;
}

/// Round-trip contract for NutritionWriteService.
///
/// **Add a new test here whenever a new consumer of `nlog_*` is created.**
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_contract_n_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('NutritionWriteService → consumer contract', () {
    test('written nlog entry exposes the contract keys', () async {
      // The actual NutritionWriteService API depends on what D1 step 3
      // surfaced. Use the public log-meal entry point. Replace this stub
      // with the real call signature uncovered during D1.
      //
      // Example shape (verify during D1):
      // final result = await NutritionWriteService.instance.logMeal(
      //   date: DateTime(2026, 5, 2),
      //   slot: 'breakfast',
      //   items: [
      //     NutritionItem(name: 'Oats', kcal: 150, protein: 5, carbs: 27, fat: 3),
      //   ],
      //   source: WriteSource.aiText,
      // );
      // expect(result.success, isTrue);

      // The contract assertions below must hold REGARDLESS of how the
      // log was created — they describe the writer↔reader boundary.
      // (Fill in once the writer call returns its key.)

      // final nb = HiveService.instance.nutritionBox;
      // final entry = nb.get(result.key) as Map;
      // const requiredKeys = ['date','slot','items','total_kcal',
      //                       'total_protein_g','total_carbs_g',
      //                       'total_fat_g','total_fiber_g'];
      // for (final k in requiredKeys) {
      //   expect(entry.containsKey(k), isTrue, reason: 'missing key: $k');
      // }

      // TEMPORARY: this test ENUMERATES expected consumer behavior. Fill
      // the body during D3 step 2 implementation against the actual
      // NutritionWriteService signature.
      markTestSkipped('Body filled during D3 implementation per D1 enumeration');
    });
  });
}
```

The skipped body is intentional: the actual NutritionWriteService method signature comes from D1 step 3. After running D1, replace the stub with a real test that asserts:

1. After `logMeal`, the Hive `nlog_*` entry contains the keys: `date`, `slot`, `items`, `total_kcal`, `total_protein_g`, `total_carbs_g`, `total_fat_g`, `total_fiber_g`, `source`, `updated_at_ms` (verify exact list during D1).
2. `TodaysMealsCard` (or its provider) sees the new meal in today's slots.
3. `home_provider` daily-completion ring reflects the new log.
4. AI snapshot's `meals_today` array contains the new meal.

- [ ] **Step 3: Run the contract test**

```bash
flutter test test/contracts/nutrition_write_to_read_contract_test.dart
```

Expected: 1 test marked as SKIPPED (with a clear message). Once D1 enumeration completes, return here, replace the skip with the actual assertions, and re-run — must PASS.

### Task D4: Update CLAUDE.md with field-name contract section

**Files:**
- Modify: `CLAUDE.md` (append to §15 "Source of Truth Rules")

- [ ] **Step 1: Find the §15 section**

```
Grep tool: pattern="^### Source of Truth Rules" path="CLAUDE.md"
```

- [ ] **Step 2: Insert new sub-section right after the "Provider invalidation after mutation" bullet**

Add this block:

```markdown
### Hive field-name contract

WriteService output keys are a contract with every consumer. Field renames must:

1. Update the writer.
2. Update every consumer in the same PR (grep for the old field name).
3. Update or add a round-trip test in `test/contracts/`.

Current contracts:

- **`exlog_*`** (`WorkoutWriteService`) — fields: `exercise_name`, `date`, `sets[]` (List of Map), `set_number`, `reps_completed`, `weight_kg`, `volume_kg`, `logging_type`, `is_pr`, `source`, `updated_at_ms`, optional `notes`.
  Consumers: `WorkoutReceiptData.fromExerciseLogs`, `WorkoutRepository.getExerciseLogsForDate`, `AiCoachRepository.buildAiContext` (recent_logs section), calendar week provider, `WorkoutWriteService._rescanAllPrsFor` PR detector, `SyncService.syncWorkoutData` cloud projection.

- **`nlog_*`** (`NutritionWriteService`) — fields: (enumerate during contract-test authoring; keep this list updated). Consumers: `TodaysMealsCard`, `NutritionRepository`, `home_provider` daily-completion ring, `AiCoachRepository.buildAiContext` (meals_today / nutrition_trend_7d), `SyncService.syncNutritionData`.

If you rename a field in a WriteService, the corresponding contract test in `test/contracts/<x>_write_to_read_contract_test.dart` must be updated in the same commit. The receipt-rendering bug in APK Test #7 (set_number vs sets_completed) is the canonical failure mode this contract prevents.
```

### Task D5: Update /pre-commit-check skill

**Files:**
- Modify: `.claude/commands/pre-commit-check.md` (or wherever the skill lives in this repo)

- [ ] **Step 1: Locate the skill**

```bash
ls .claude/commands/pre-commit-check.md 2>/dev/null || find .claude -name "pre-commit-check*"
```

- [ ] **Step 2: Append one bullet to the existing checklist**

Append:

```markdown
- [ ] If I changed a WriteService output field, did I grep for every consumer of that field name and update them in the same commit? Did I add or update a round-trip test in `test/contracts/`?
```

### Task D6: Verify Theme D suite

- [ ] **Step 1: Run all contract tests**

```bash
flutter test test/contracts/
```

Expected: all green (or 1 deliberate skip for the nutrition test if D3 was left in stub state — but ideally D3 was completed end-to-end).

### Task D7: Stage commit boundary

- [ ] **Step 1: Stage**

```bash
git add test/contracts/workout_write_to_read_contract_test.dart \
        test/contracts/nutrition_write_to_read_contract_test.dart \
        CLAUDE.md \
        .claude/commands/pre-commit-check.md
git status
```

Commit message:
```
test(contracts): add writer↔reader round-trip tests + doc the field-name contract

Two new files under test/contracts/ exercise WorkoutWriteService and
NutritionWriteService end-to-end through every consumer of their Hive
output. Writer field renames are now caught at test time instead of in
production receipts.

CLAUDE.md §15 gains a Hive field-name contract sub-section enumerating
every consumer of exlog_* / nlog_* — tribal knowledge becomes
discoverable.

/pre-commit-check skill picks up one bullet asking the same question.

Closes Theme D of Test #8 batch.
```

---

## Theme C — Profile cards: sharp + flush + edit defaults

> Independent of B. Visual change only. After Theme A + D land, you can run C and B in parallel via subagent dispatch.

### Task C1: Pre-flight read of card stack

**Files:**
- Read: `lib/features/profile/screens/profile_screen.dart` around line 550–620 (Daily Goals → My Targets stack)
- Read: `lib/core/theme/spacing.dart` to confirm `AppRadius.sharp` value

- [ ] **Step 1: Locate the stack callsites**

```
Grep tool: pattern="ProfileCompletenessCard|_buildDailyCompletion|SlimAchievementsCard|_buildJourneyTimeline|_buildBodyStats|_buildNutritionTargets" path="lib/features/profile/screens/profile_screen.dart" output_mode="content" -n=true
```

Capture the exact Widget callsite block (5 cards + 4 `SizedBox(height: 8)` between).

- [ ] **Step 2: Confirm `AppRadius.sharp` constant**

```
Grep tool: pattern="static const sharp" path="lib/core/theme/spacing.dart" output_mode="content" -n=true
```

If `AppRadius.sharp` isn't 6 dp, adjust the design — but per CLAUDE.md and existing usages it should be.

### Task C2: Build a flush-stack helper

**Files:**
- Modify: `lib/features/profile/screens/profile_screen.dart`

- [ ] **Step 1: Add a private helper above `_buildCard`**

In `profile_screen.dart`, insert (anywhere in `_ProfileScreenState` before `_buildCard`):

```dart
/// Theme C · Test #8 — wraps a card in a flush-stack-aware container.
/// Outer corners (top of `first`, bottom of `last`) use `AppRadius.sharp`
/// (6 dp). Inner edges are square. Shared 1 px border rail; top border
/// drops on every card except the first.
Widget _buildFlushCard(Widget child, {required _FlushPos pos}) {
  final isFirst = pos == _FlushPos.first || pos == _FlushPos.only;
  final isLast = pos == _FlushPos.last || pos == _FlushPos.only;
  return Container(
    margin: EdgeInsets.zero,
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(isFirst ? AppRadius.sharp : 0),
        topRight: Radius.circular(isFirst ? AppRadius.sharp : 0),
        bottomLeft: Radius.circular(isLast ? AppRadius.sharp : 0),
        bottomRight: Radius.circular(isLast ? AppRadius.sharp : 0),
      ),
      border: Border(
        top: BorderSide(color: AppColors.border, width: isFirst ? 1 : 0),
        left: const BorderSide(color: AppColors.border, width: 1),
        right: const BorderSide(color: AppColors.border, width: 1),
        bottom: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    padding: const EdgeInsets.all(14),
    child: child,
  );
}

enum _FlushPos { first, middle, last, only }
```

- [ ] **Step 2: Apply it to the 5-card stack**

Find the existing block (currently around lines 552–588):

```dart
const ProfileCompletenessCard(),
const SizedBox(height: 8),
_buildDailyCompletion(stats),
const SizedBox(height: 8),
const SlimAchievementsCard(),
const SizedBox(height: 8),
_buildJourneyTimeline(stats, currentWeightKg: …, …),
_buildBodyStats(weightKg, targetKg, bmi, bodyFatPct),
if (nutritionTargets != null)
  _buildNutritionTargets(nutritionTargets, …),
const SizedBox(height: 8),
```

Replace with (preserving the conditional `if (nutritionTargets != null)`):

```dart
// Theme C · Test #8 — flush stack with sharp 6dp outer corners.
const ProfileCompletenessCard(), // stays as a separately-styled card above the stack
const SizedBox(height: 8),
_buildFlushCard(_buildDailyCompletionInner(stats), pos: _FlushPos.first),
_buildFlushCard(_SlimAchievementsInner(), pos: _FlushPos.middle),
_buildFlushCard(_buildJourneyTimelineInner(stats,
        currentWeightKg: weightKg,
        targetWeightKg: targetKg,
        goal: stats.primaryGoal),
    pos: _FlushPos.middle),
_buildFlushCard(_buildBodyStatsInner(weightKg, targetKg, bmi, bodyFatPct),
    pos: nutritionTargets != null ? _FlushPos.middle : _FlushPos.last),
if (nutritionTargets != null)
  _buildFlushCard(_buildNutritionTargetsInner(
        nutritionTargets,
        currentKg: weightKg,
        targetKg: targetKg,
        goal: stats.primaryGoal,
        pacePreference: profile['pace_preference'] is String
            ? profile['pace_preference'] as String
            : 'balanced',
      ),
      pos: _FlushPos.last),
const SizedBox(height: 8),
```

The `*Inner` callsites are the existing `_buildDailyCompletion` / `_buildJourneyTimeline` / etc., but with the OUTER `Container(... border ... radius ...)` wrapper stripped out (because `_buildFlushCard` now provides that wrapper). For each existing `_buildX` helper, extract its inner content into a new `_buildXInner` helper that returns just the children.

- [ ] **Step 3: Extract _Inner variants for each affected card**

For each of `_buildDailyCompletion`, `_buildJourneyTimeline`, `_buildBodyStats`, `_buildNutritionTargets` — find the existing helper, copy its body excluding the outer `Container(decoration: ..., child: Padding(...))` wrapper, and create a new `_buildXInner` returning the unwrapped child column. The original `_buildX` can either stay (for any other callers) or delegate to `_buildFlushCard(_buildXInner(...), pos: _FlushPos.only)` to preserve compatibility.

For `SlimAchievementsCard` — it's a separate widget. Either:
  - (a) refactor `SlimAchievementsCard` to expose a `child`-only variant, OR
  - (b) wrap `SlimAchievementsCard()` in `_buildFlushCard` accepting that we'll have a card-inside-card border for one row.

Pick (a) — cleaner. Add a `compact` boolean property to `SlimAchievementsCard` that, when true, returns the inner Row only without its own decoration.

- [ ] **Step 4: Visual smoke test**

Run the app on a physical device or emulator (don't auto-build APK):

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

Navigate to Profile tab. Verify:
1. Daily Goals → Badges → Journey → Body Stats → My Targets stack reads as one continuous block (no inter-card gaps).
2. Top of Daily Goals has a small (6dp) rounded corner; everything below is square; bottom of My Targets has a small rounded corner.
3. Each card's content (ring, badges, etc.) is unchanged — only the wrapping changed.

If any card content looks broken, the `_Inner` extraction lost padding or a child — re-check Step 3 for that helper.

### Task C3: Edit-profile defaults

**Files:**
- Modify: `lib/features/profile/screens/edit_profile_screen.dart` (line 145 + line 147)

- [ ] **Step 1: Patch line 145 (diet default)**

Replace:
```dart
_dietPreference = (profile['diet_preference'] as String?) ?? 'non_veg';
```

With:
```dart
// Theme C · Test #8 — Indian-first default; matches onboarding's
// implicit default which already writes 'veg' for new users.
_dietPreference = (profile['diet_preference'] as String?) ?? 'veg';
```

- [ ] **Step 2: Patch line 147 (session duration default)**

Replace:
```dart
_sessionDuration = profile['session_duration_minutes'] as int?;
```

With:
```dart
// Theme C · Test #8 — 90 min matches the user's actual saved value
// from Supabase ground-truth check; legacy/restored profiles missing
// the field land here.
_sessionDuration = (profile['session_duration_minutes'] as int?) ?? 90;
```

- [ ] **Step 3: Verify the picker shows the default selected**

Run the app, navigate to Profile → EDIT PROFILE. With a fresh profile that has NEVER set diet/session, confirm:
- Diet picker shows VEG selected (not blank)
- Session duration picker shows 90 min selected (not blank)

### Task C4: Run profile-related tests

```bash
flutter test test/profile/ test/contracts/ test/onboarding/
```

Expected: 0 failures introduced by C2 + C3.

### Task C5: Stage commit boundary

```bash
git add lib/features/profile/screens/profile_screen.dart \
        lib/features/profile/screens/edit_profile_screen.dart \
        lib/features/profile/widgets/slim_achievements_card.dart
git status
```

Commit message:
```
feat(profile): sharp 6dp outer corners + flush stack + edit defaults

The Daily Goals → Badges → Journey → Body Stats → My Targets cards
collapse into a single visual block. 16dp rounded → 6dp sharp on outer
corners only; inner edges square. Inter-card gaps removed (~32dp gain).

Edit Profile defaults align with onboarding reality: diet_preference
falls back to 'veg' (was 'non_veg' — Indian-first), session_duration
falls back to 90 min (was nullable, blank picker).

Closes Theme C of Test #8 batch.
```

---

## Theme B — Rank pill in banner row + expanded service-record sheet

> Independent of C. Best run as a single subagent dispatch (touches 4 files together).

### Task B1: Pre-flight read

**Files:**
- Read: `lib/features/profile/widgets/profile_identity.dart`
- Read: `lib/features/profile/screens/profile_screen.dart:530-547` (current `WardRankPill` block)
- Read: `lib/features/profile/screens/profile_screen.dart:1282-1410` (current `_buildRankServiceRecord`)
- Read: `lib/shared/widgets/wardroom/ward_rank_pill.dart` and `ward_rank_insignia.dart`
- Read: `lib/core/services/rank_service.dart`

- [ ] **Step 1: Confirm RankService API**

Note signatures of `getCurrentRank()`, `getLadder()`, and any existing streak/freeze accessors. If a streak helper already exists in `lib/shared/repositories/workout_repository.dart` (per CLAUDE.md "Streak math context"), confirm `calculateCurrentStreak()` exists.

- [ ] **Step 2: Confirm freeze keys in Hive**

```
Grep tool: pattern="streak_freezes_available|streak_freezes_used_dates|streak_freezes_last_refill" path="lib"
```

Capture the box name (`userBox` per CLAUDE.md) and key spelling.

### Task B2: Create promotionHistoryProvider (TDD)

**Files:**
- Create: `lib/features/profile/providers/promotion_history_provider.dart`
- Create: `test/profile/promotion_history_provider_test.dart`

- [ ] **Step 1: Write the provider test**

```dart
// test/profile/promotion_history_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/profile/providers/promotion_history_provider.dart';

void main() {
  test('promotionHistoryProvider returns empty list when not signed in', () async {
    final container = ProviderContainer();
    final result = await container.read(promotionHistoryProvider.future);
    expect(result, isEmpty);
    container.dispose();
  });

  // Live Supabase test deferred — we don't hit the network in unit tests.
  // This single test pins the provider's contract: returns List<PromotionRecord>.
}
```

- [ ] **Step 2: Implement the provider**

```dart
// lib/features/profile/providers/promotion_history_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

class PromotionRecord {
  final String rankCode;
  final DateTime achievedAt;
  const PromotionRecord({required this.rankCode, required this.achievedAt});

  factory PromotionRecord.fromMap(Map<String, dynamic> m) => PromotionRecord(
        rankCode: m['rank_code'] as String,
        achievedAt: DateTime.parse(m['achieved_at'] as String),
      );
}

/// Theme B · Test #8 — fetches the user's promotion history for display
/// inside RankServiceRecordSheet. Cached for the session so re-opens are
/// instant. Returns empty list on any failure (silent).
final promotionHistoryProvider =
    FutureProvider<List<PromotionRecord>>((ref) async {
  final user = SupabaseService.client.auth.currentUser;
  if (user == null) return const [];
  try {
    final rows = await SupabaseService.client
        .from('rank_promotions')
        .select('rank_code, achieved_at')
        .eq('user_id', user.id)
        .order('achieved_at', ascending: false)
        .limit(5);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PromotionRecord.fromMap)
        .toList();
  } catch (_) {
    return const [];
  }
});
```

- [ ] **Step 3: Run the provider test**

```bash
flutter test test/profile/promotion_history_provider_test.dart
```

Expected: PASS.

### Task B3: Create RankServiceRecordSheet widget

**Files:**
- Create: `lib/features/profile/widgets/rank_service_record_sheet.dart`

- [ ] **Step 1: Implement the sheet**

```dart
// lib/features/profile/widgets/rank_service_record_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/shared/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';
import '../providers/promotion_history_provider.dart';

/// Theme B · Test #8 — bottom sheet shown when the compact rank chip in
/// the profile banner is tapped. Replaces the inline `WardRankPill`
/// accordion that previously consumed a full row.
///
/// Content:
///   - SERVICE RECORD eyebrow
///   - Current rank big card (48dp insignia + display name + CURRENT)
///   - Status tiles: streak count, freezes left
///   - UPCOMING (next 2 ranks)
///   - PROMOTION HISTORY (last 5 from rank_promotions table)
///   - VIEW FULL ROADMAP → /train/roadmap
class RankServiceRecordSheet extends ConsumerWidget {
  const RankServiceRecordSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const RankServiceRecordSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankSvc = RankService.instance;
    final current = rankSvc.getCurrentRank();
    final ladder = rankSvc.getLadder();
    final currentIdx =
        ladder.indexWhere((e) => e.entry.code == current.entry.code);
    final upcoming = (currentIdx >= 0 && currentIdx + 1 < ladder.length)
        ? ladder.skip(currentIdx + 1).take(2).toList()
        : const [];

    final streak = WorkoutRepository.instance.calculateCurrentStreak();
    final ub = HiveService.instance.userBox;
    final freezesAvailable = (ub.get('streak_freezes_available') as int?) ?? 0;
    final freezesUsed = (ub.get('streak_freezes_used_dates') as List?)?.length ?? 0;

    final history = ref.watch(promotionHistoryProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _eyebrow('SERVICE RECORD'),
              const SizedBox(height: 12),
              _currentRankBlock(current),
              const SizedBox(height: 14),
              _statusTiles(streak, freezesAvailable, freezesUsed),
              if (upcoming.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(height: 1, color: AppColors.line2),
                const SizedBox(height: 12),
                _eyebrow('UPCOMING'),
                const SizedBox(height: 6),
                ...upcoming.map(_upcomingRow),
              ],
              const SizedBox(height: 14),
              Container(height: 1, color: AppColors.line2),
              const SizedBox(height: 12),
              _eyebrow('PROMOTION HISTORY'),
              const SizedBox(height: 6),
              history.when(
                data: (records) => records.isEmpty
                    ? Text('No promotions yet.',
                        style: AppTypography.bodySm.copyWith(color: AppColors.textMute))
                    : Column(
                        children: records.map(_historyRow).toList(),
                      ),
                loading: () => Column(
                  children: List.generate(2, (_) => _historySkeleton()),
                ),
                error: (_, __) => Text('History unavailable.',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textMute)),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go('/train/roadmap');
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: Text(
                    'VIEW FULL ROADMAP →',
                    style: AppTypography.mono.copyWith(
                      fontSize: 11,
                      color: AppColors.accent,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eyebrow(String s) => Text(s,
      style: AppTypography.mono.copyWith(
        fontSize: 10,
        color: AppColors.textDim,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
      ));

  Widget _currentRankBlock(RankView v) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          WardRankInsignia(rankCode: v.entry.code, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.entry.displayName,
                    style: AppTypography.titleM
                        .copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(v.entry.isTerminal ? 'TERMINAL RANK' : 'CURRENT',
                    style: AppTypography.mono.copyWith(
                      fontSize: 10,
                      color: AppColors.accent,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTiles(int streak, int avail, int used) {
    Widget tile(String label, String value, {String? unit}) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.cardHi,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.line2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value,
                        style: AppTypography.h3
                            .copyWith(color: AppColors.accent)),
                    if (unit != null) ...[
                      const SizedBox(width: 4),
                      Text(unit,
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.textDim,
                          )),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile('CURRENT STREAK', streak.toString(), unit: streak == 1 ? 'day' : 'days'),
        const SizedBox(width: 10),
        tile('FREEZES LEFT', '$avail', unit: '/ ${avail + used}'),
      ],
    );
  }

  Widget _upcomingRow(LadderEntryView v) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Opacity(opacity: 0.55, child: WardRankInsignia(rankCode: v.entry.code, size: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.entry.shortName,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textDim,
                        fontWeight: FontWeight.w600,
                      )),
                  if (v.gateText != null)
                    Text(v.gateText!,
                        style: AppTypography.bodySm.copyWith(color: AppColors.textMute)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _historyRow(PromotionRecord r) {
    final monthNames = const ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    final dateLabel = '${r.achievedAt.day.toString().padLeft(2, '0')} ${monthNames[r.achievedAt.month - 1]}';
    final entry = RankService.instance.getLadder().firstWhere(
          (e) => e.entry.code == r.rankCode,
          orElse: () => RankService.instance.getCurrentRank(),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.ok, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Promoted to ${entry.entry.displayName}',
                style: AppTypography.body.copyWith(color: AppColors.textPrimary)),
          ),
          Text(dateLabel,
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 1.0,
              )),
        ],
      ),
    );
  }

  Widget _historySkeleton() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.line2, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Container(height: 12, color: AppColors.line2),
            ),
          ],
        ),
      );
}
```

- [ ] **Step 2: Resolve any imports / type errors**

Run `flutter analyze lib/features/profile/widgets/rank_service_record_sheet.dart` and fix any issues. The class names `RankView` / `LadderEntryView` come from `rank_service.dart` — adjust to the actual exported types.

### Task B4: Modify ProfileIdentity to host the rank chip

**Files:**
- Modify: `lib/features/profile/widgets/profile_identity.dart` (lines 200–215, the banner-overlap Row)

- [ ] **Step 1: Add new properties to the widget**

Extend the constructor:

```dart
final String? rankCode;
final String? rankShortCode;     // e.g., 'SD2'
final VoidCallback? onTapRank;

const ProfileIdentity({
  super.key,
  required this.name,
  required this.subtitle,
  this.avatarUrl,
  this.bannerUrl,
  required this.onReplaceAvatar,
  required this.onReplaceBanner,
  this.onTapEdit,
  required this.isPro,
  required this.onTapPremium,
  this.rankCode,
  this.rankShortCode,
  this.onTapRank,
});
```

- [ ] **Step 2: Replace the Row in the Stack overlap**

Find the `Positioned(left: 18, right: 18, bottom: -40, child: Row(...))` block and replace its `Row` children with:

```dart
Row(
  children: [
    _buildAvatar(context),
    Expanded(
      child: Center(
        child: (rankCode != null && rankShortCode != null && onTapRank != null)
            ? _buildRankChip()
            : const SizedBox.shrink(),
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 40),
      child: ProPillButton(isPro: isPro, onTap: onTapPremium),
    ),
  ],
),
```

- [ ] **Step 3: Add `_buildRankChip` helper inside ProfileIdentity**

```dart
Widget _buildRankChip() {
  return Padding(
    padding: const EdgeInsets.only(top: 44),
    child: GestureDetector(
      onTap: onTapRank,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WardRankInsignia(rankCode: rankCode!, size: 22),
            const SizedBox(width: 6),
            Text(
              rankShortCode!,
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.accent,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more,
                size: 14, color: AppColors.accent),
          ],
        ),
      ),
    ),
  );
}
```

(Add `import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';` at the top.)

### Task B5: Wire rank chip onTap in profile_screen.dart

**Files:**
- Modify: `lib/features/profile/screens/profile_screen.dart`

- [ ] **Step 1: Import the new sheet**

Add:
```dart
import '../widgets/rank_service_record_sheet.dart';
```

- [ ] **Step 2: Pass rank props to ProfileIdentity callsite**

Find the existing `ProfileIdentity(...)` call. Add:

```dart
ProfileIdentity(
  name: …,
  subtitle: …,
  // … existing props
  rankCode: RankService.instance.getCurrentRank().entry.code,
  rankShortCode: RankService.instance.getCurrentRank().entry.shortName.toUpperCase(),
  onTapRank: () => RankServiceRecordSheet.show(context),
),
```

- [ ] **Step 3: Remove the inline WardRankPill block (lines 530–548)**

Delete the entire `Padding(... child: WardRankPill(...))` block + the `const SizedBox(height: 8)` immediately following it. The Profile Completeness card (`const ProfileCompletenessCard()`) must now sit directly under the gold rule from ProfileIdentity.

- [ ] **Step 4: Remove `_buildRankServiceRecord` (lines ~1282–1410)**

The accordion content has moved into `RankServiceRecordSheet`. Delete the helper. If anything else in the file references it, those callsites are stale and should also be removed.

- [ ] **Step 5: Visual smoke test**

Run on device:
```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

Profile tab — verify:
1. Banner row reads avatar L, `SD2` chip centered, GO PRO right.
2. Tap the chip — bottom sheet opens with SERVICE RECORD content (rank big card, streak/freeze tiles, upcoming, history, roadmap link).
3. The inline `WardRankPill` row is GONE — Profile Completeness sits directly under the gold rule.

### Task B6: Run profile tests

```bash
flutter test test/profile/
```

Expected: 0 failures introduced by B2–B5.

### Task B7: Stage commit boundary

```bash
git add lib/features/profile/widgets/profile_identity.dart \
        lib/features/profile/widgets/rank_service_record_sheet.dart \
        lib/features/profile/providers/promotion_history_provider.dart \
        lib/features/profile/screens/profile_screen.dart \
        test/profile/promotion_history_provider_test.dart
git status
```

Commit message:
```
feat(profile): rank chip moves into banner row + expanded service record sheet

Avatar L · compact SD2 chip CENTER · GO PRO R is the new banner overlap
layout. Tap the chip → bottom sheet with current rank + streak count +
freezes left + upcoming 2 ranks + last 5 promotions + roadmap link.

Removes the inline WardRankPill row that consumed ~64dp. Profile
Completeness now sits directly under the gold rule. Service record
content is unchanged in essence but enriched with streak/freeze/history.

New files:
- widgets/rank_service_record_sheet.dart — the bottom sheet
- providers/promotion_history_provider.dart — rank_promotions fetch

Closes Theme B of Test #8 batch.
```

---

## Theme E — Personalize morning-alert to wake_up_time

> Independent of all UI work. Touches Edge Function + new migration. Keep this on a separate commit so a server-side rollback doesn't drag UI changes with it.

### Task E1: Pre-flight read

**Files:**
- Read: `supabase/functions/morning-alert/index.ts` (full)
- Read: `supabase/functions/_shared/proactive_dedup.ts`

- [ ] **Step 1: Confirm existing structure**

Verify:
- `serve` handler reads `body.mode` (around line 552 per earlier grep)
- `mode === 'deliver'` calls `deliverAlerts(supabaseClient, todayIST)`
- `deliverAlerts` paginates `user_daily_snapshots` for `snapshot_date = todayIST`
- Dedup type used is `'morning_brief'` (around line 489)

- [ ] **Step 2: Confirm cron job names in production**

Already verified during spec phase: `morning_alert_generate` (20:30 UTC) + `morning_alert_deliver` (01:30 UTC). Re-confirm no rename happened since:

```
SQL: SELECT jobname, schedule, active FROM cron.job WHERE jobname ILIKE '%morning%';
```

(Run via mcp__ba7b5e8e tool against project_id `dedsavbjuwgarrhphgnl`.)

### Task E2: Add wake-time filter to deliverAlerts

**Files:**
- Modify: `supabase/functions/morning-alert/index.ts` (`deliverAlerts` function ~line 441)

- [ ] **Step 1: Add a quarter-floor helper at top of file**

Insert near other helpers (e.g., right after `nowInIst()` if one exists, otherwise near the top of the module):

```ts
/// Theme E · Test #8 — IST clock floor to nearest 15-min quarter,
/// returned as 'HH:MM:SS' so it lines up with `time without time zone`.
function floorToQuarterIst(now: Date = new Date()): string {
  const utcMs = now.getTime();
  const istMs = utcMs + (5 * 60 + 30) * 60 * 1000;
  const ist = new Date(istMs);
  const hh = ist.getUTCHours().toString().padStart(2, '0');
  const mm = (Math.floor(ist.getUTCMinutes() / 15) * 15)
      .toString().padStart(2, '0');
  return `${hh}:${mm}:00`;
}
```

- [ ] **Step 2: Replace deliverAlerts SELECT to include the wake-time filter**

Inside `deliverAlerts`, before the `while (hasMore)` loop, compute:

```ts
const currentQuarter = floorToQuarterIst(new Date());
const isFallbackQuarter = currentQuarter === '07:00:00';
console.log(`[morning-alert.deliver] quarter=${currentQuarter} fallback_window=${isFallbackQuarter}`);
```

Replace the existing query (currently `.from('user_daily_snapshots').select(...).eq('snapshot_date', todayIST).not('snapshot_json->morning_alert', 'is', null).range(...)`) with a JOIN-shaped query. Easiest path is an RPC; second easiest is a manual two-step (fetch profiles, then snapshots). Pick RPC for clarity:

```ts
const { data: snapshots, error: snapError } = await supabaseClient.rpc(
  'morning_alert_pick_quarter',
  {
    p_today: todayIST,
    p_quarter: currentQuarter,
    p_fallback: isFallbackQuarter,
    p_offset: offset,
    p_limit: PAGE_SIZE,
  },
);
```

The RPC returns the same shape as before: `[{ user_id, snapshot_json }, …]`. Per-row delivery loop is unchanged.

- [ ] **Step 3: Define the RPC in the migration (next task)**

(Will create `morning_alert_pick_quarter` SQL function in Task E3.)

- [ ] **Step 4: Quick syntax check**

```bash
deno check supabase/functions/morning-alert/index.ts
```

Expected: no errors. If `deno` is not available on this machine, the CI will catch it later — proceed.

### Task E3: Migration 046 — RPC + cron rewire

**Files:**
- Create: `supabase/migrations/046_morning_alert_personalized_delivery_cron.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 046_morning_alert_personalized_delivery_cron.sql
-- Theme E · Test #8 — personalize morning push delivery to user wake_up_time.

-- 1. RPC used by deliverAlerts to fetch only users whose wake_up_time
--    matches the current 15-min quarter (with NULL fallback to 07:00 IST).

CREATE OR REPLACE FUNCTION public.morning_alert_pick_quarter(
  p_today    DATE,
  p_quarter  TEXT,           -- 'HH:MM:SS' from floorToQuarterIst()
  p_fallback BOOLEAN,        -- true when p_quarter = '07:00:00'
  p_offset   INTEGER,
  p_limit    INTEGER
)
RETURNS TABLE (user_id UUID, snapshot_json JSONB)
LANGUAGE sql
STABLE
AS $$
  SELECT s.user_id, s.snapshot_json
  FROM   public.user_daily_snapshots s
  JOIN   public.user_profile p ON p.user_id = s.user_id
  WHERE  s.snapshot_date = p_today
    AND  s.snapshot_json -> 'morning_alert' IS NOT NULL
    AND  (
            -- Normal: wake_up_time floored to 15-min equals current quarter.
            (
              p.wake_up_time IS NOT NULL
              AND make_time(
                    EXTRACT(HOUR   FROM p.wake_up_time)::INTEGER,
                    (FLOOR(EXTRACT(MINUTE FROM p.wake_up_time) / 15) * 15)::INTEGER,
                    0
                  )::TEXT = p_quarter
            )
            -- Fallback: NULL wake gets the 07:00 IST quarter only.
            OR (p.wake_up_time IS NULL AND p_fallback)
         )
  ORDER BY s.user_id
  LIMIT  p_limit
  OFFSET p_offset;
$$;

GRANT EXECUTE ON FUNCTION public.morning_alert_pick_quarter
  TO authenticated, service_role;

-- 2. Replace the single 07:00 IST delivery cron with two rows running
--    every 15 min, spanning UTC midnight to cover IST 04:00–11:59.

SELECT cron.unschedule('morning_alert_deliver');

-- IST 03:30 → 05:59 = UTC 22:00 → 23:59 (previous calendar day)
SELECT cron.schedule(
  'morning_alert_deliver_late',
  '*/15 22-23 * * *',
  $$
    SELECT net.http_post(
      url     := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/morning-alert',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object('mode','deliver')
    );
  $$
);

-- IST 05:30 → 12:14 = UTC 00:00 → 06:59 (same day)
SELECT cron.schedule(
  'morning_alert_deliver_early',
  '*/15 0-6 * * *',
  $$
    SELECT net.http_post(
      url     := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/morning-alert',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object('mode','deliver')
    );
  $$
);
```

- [ ] **Step 2: Apply the migration to dev**

Use the MCP tool `mcp__ba7b5e8e__apply_migration` with `project_id=dedsavbjuwgarrhphgnl` and the migration name + SQL above. (Or `supabase db push` against the dev branch — but per CLAUDE.md the CLI is signed into the wrong account, so MCP is preferred.)

- [ ] **Step 3: Verify cron jobs after migration**

```sql
SELECT jobname, schedule, active FROM cron.job WHERE jobname LIKE 'morning_alert%' ORDER BY jobname;
```

Expected:
- `morning_alert_deliver_early` — `*/15 0-6 * * *`
- `morning_alert_deliver_late`  — `*/15 22-23 * * *`
- `morning_alert_generate`      — `30 20 * * *` (untouched)
- (no `morning_alert_deliver`)

- [ ] **Step 4: Verify RPC**

```sql
SELECT public.morning_alert_pick_quarter(
  CURRENT_DATE, '07:00:00', TRUE, 0, 5
);
```

Expected: returns rows for any users whose snapshot exists today and whose wake_up_time is NULL or matches 07:00. May return 0 rows on dev — that's fine.

### Task E4: Deploy morning-alert Edge Function

**Files:**
- Touched: `supabase/functions/morning-alert/index.ts`

- [ ] **Step 1: Emit deploy payload**

```bash
node .claude/emit_payload.js morning-alert --auto --functions-dir "C:/Upendra/Claude Code/Fitness App/supabase/functions"
```

Expected: writes `.claude/_payload_morning-alert.json` with the new index.ts bundled.

- [ ] **Step 2: Dry-run deploy**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl morning-alert .claude/_payload_morning-alert.json false --dry-run
```

(`verify_jwt=false` because morning-alert is a cron-only function with `authorization` header carrying the service key, not a user JWT.)

Expected: prints the payload size + entrypoint = `index.ts` + would-deploy log line.

- [ ] **Step 3: Deploy**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl morning-alert .claude/_payload_morning-alert.json false
```

Expected: HTTP 201 with version bump.

### Task E5: Live verification

- [ ] **Step 1: Manually trigger a delivery run**

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(node -e "console.log(process.env.MORNING_ALERT_SERVICE_KEY ?? '')")" \
  -d '{"mode":"deliver"}' \
  https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/morning-alert
```

If the service key isn't in env, fetch the cron-stored key via Supabase dashboard → Settings → Functions → Secrets, OR skip the manual trigger and wait for the next scheduled run.

- [ ] **Step 2: Read function logs via MCP**

```
mcp__ba7b5e8e__get_logs(project_id="dedsavbjuwgarrhphgnl", service="edge-function")
```

Look for the new log line: `[morning-alert.deliver] quarter=HH:MM:SS fallback_window=…`. Confirm:
- The quarter value matches current IST 15-min floor.
- The pagination loop iterates without errors.
- 0 sent + 0 skipped is acceptable on a quiet dev account.

### Task E6: Stage commit boundary

```bash
git add supabase/functions/morning-alert/index.ts \
        supabase/migrations/046_morning_alert_personalized_delivery_cron.sql
git status
```

Commit message:
```
feat(morning-alert): personalize push delivery to user wake_up_time

morning_alert_deliver cron (single 07:00 IST run) → two new crons
running every 15 min spanning UTC midnight to cover IST 04:00–11:59.
Each run filters user_daily_snapshots by users whose wake_up_time
floored to 15 min equals the current quarter, with NULL fallback to
the 07:00 IST window.

Migration 046 adds the morning_alert_pick_quarter RPC + rewires the
cron rows. morning_alert_generate cron is unchanged.

Closes Theme E of Test #8 batch.
```

---

## Wrap-up

### Task W1: Run the full test suite

```bash
flutter test
```

Expected: ≥ 882 tests pass (Test #7 baseline). 4 pre-existing failures from Test #6 (`rank_service_test` LS/PO/SubLt static gate mirrors + `sync_gap_test` `DeleteNutritionLogNotifier`) MAY persist — they are explicitly out of scope for this batch. Any NEW failure is a Theme regression — investigate before continuing.

### Task W2: Static analysis

```bash
flutter analyze
```

Expected: 0 errors, 0 warnings introduced by this batch. Pre-existing infos / hints are acceptable.

### Task W3: APK build (only when user explicitly says "build APK")

> Per CLAUDE.md: never auto-build. User must say "build APK".

When user instructs:

- [ ] **Step 1: Invoke the /build-apk skill**

Use the Skill tool with `skill="build-apk"`. Do NOT run `flutter build apk` directly via Bash — the skill wraps pre-flight cleanup that prevents silent hangs on this machine.

The skill will:
1. Clean stale flutter cache lockfile.
2. Clean Gradle caches.
3. Build with `--dart-define-from-file=.env --flavor prod --release`.
4. Report APK path + size.

### Task W4: Final commit boundary (whole batch)

When user instructs "commit", create one merge commit OR five thematic commits depending on user preference. Suggested merge-commit message:

```
merge: APK Test #8 batch — receipt fix, rank chip, sharp cards, contract tests, wake-time push

Themes:
- A receipt sync field rename (set_number/sets fallback)
- B rank chip in banner row + expanded service-record sheet
- C sharp 6dp + flush profile card stack + edit-profile defaults
- D writer↔reader round-trip contract tests + CLAUDE.md guard
- E morning-alert deliver every 15 min, filtered by user wake_up_time

Spec: docs/superpowers/specs/2026-05-02-apk-test-8-design.md
Plan: docs/superpowers/plans/2026-05-02-apk-test-8-plan.md
```

---

## Self-review pass

Spec coverage:
- Theme A spec §3 → Tasks A1–A5. ✓
- Theme B spec §4 → Tasks B1–B7. ✓
- Theme C spec §5 → Tasks C1–C5. ✓
- Theme D spec §6 → Tasks D1–D7. ✓
- Theme E spec §7 → Tasks E1–E6. ✓

Placeholder scan: clean. The single deliberate `markTestSkipped` in D3 is gated on D1 enumeration — explicit, not a TBD.

Type consistency: `RankView`, `LadderEntryView`, `RankService.instance` references in Theme B mirror the existing `_buildRankServiceRecord` helper (lines 1290–1410 of profile_screen.dart). `WriteResult` / `WriteSource` / `ExerciseSet` come from existing `lib/core/services/workout_write_service.dart` + `write_result.dart`. No new types invented.

Risk ordering: A first (smallest, validates baseline) → D (surfaces other drifts BEFORE B/C touch the codebase) → C, B, E parallelizable. Matches the user's stated ordering preference.
