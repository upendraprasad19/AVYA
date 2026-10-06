# APK Test #6 Plan A — Workout Data Integrity (WorkoutWriteService Rewrite)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the duplicate-rows bug class structurally — all workout-touching code paths route through one canonical WorkoutWriteService with mutex-guarded upserts, 60s per-set dedup, and 3-tier cloud sync.

**Architecture:** New WorkoutWriteService (6 atomic methods) is the only writer for workout_logs / workout_log_exercises / workout_log_sets. Per-(date, exerciseName) mutex serializes concurrent writes. Hive `exlog_*` keys become deterministic on (date, exerciseName) instead of timestamp. All 7+ existing callsites migrate.

**Estimated effort:** 17-24h.

**Spec reference:** `docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md` §4.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `pubspec.yaml` | MODIFY | Bump versionCode +5 → +6 |
| `lib/core/services/write_result.dart` | CREATE | `WriteResult`, `WriteSource` enum, `ExerciseSet` data class |
| `lib/core/services/workout_write_service.dart` | CREATE | `WorkoutWriteService` singleton — 6 atomic write methods + mutex map |
| `lib/core/services/sync_service.dart` | MODIFY | Extend `_projectExerciseLog` to write 3-tier (workout_logs + workout_log_exercises + N workout_log_sets) |
| `lib/features/ai_coach/services/tool_dispatcher.dart` | MODIFY | Route `logSet`, `markWorkoutComplete`, `swapExercise`, `rescheduleWeek`, `pausePlan`, `regeneratePlanBlock` through service |
| `lib/features/train/providers/train_provider.dart` | MODIFY | Active Workout `Save` button calls `logExercise` + `markCompleted`; remove direct Hive writes |
| `lib/features/train/widgets/edit_workout_log_sheet.dart` | MODIFY | "Save changes" calls `editLog`; trash icon calls `deleteLog` |
| `lib/core/services/workout_schedule_service.dart` | MODIFY | `generateAndScheduleFromDate` wraps each schedule_* write in `upsertScheduled`; `swapDay` delegates to `rescheduleDay` |
| `lib/features/profile/screens/edit_profile_screen.dart` | MODIFY | Regen path routes through `regenerateWeek` |
| `lib/features/train/repositories/workout_repository.dart` | MODIFY | First-launch migration: re-key all `exlog_*` from timestamp to `exlog_<istDateStr>_<hash(name)>`; merge dupes |
| `test/workout_write_service/log_exercise_dedup_60s_test.dart` | CREATE | Same (weight, reps) twice within 60s → 1 entry in sets[] |
| `test/workout_write_service/log_exercise_appends_sets_test.dart` | CREATE | Multiple calls same day same exercise → one row, sets[] grows |
| `test/workout_write_service/log_exercise_new_day_test.dart` | CREATE | Same exercise next day → new row |
| `test/workout_write_service/log_exercise_concurrency_test.dart` | CREATE | Two simultaneous calls → mutex serializes; final state has both sets merged |
| `test/workout_write_service/mark_completed_test.dart` | CREATE | Marks schedule_<date> status='completed' + writes wlog_* |
| `test/workout_write_service/upsert_scheduled_test.dart` | CREATE | Closes #3 — verify `unawaited(syncWorkoutData)` invoked |
| `test/workout_write_service/edit_log_pr_rescan_test.dart` | CREATE | Edit a past log → re-scan PRs chronologically |
| `test/workout_write_service/delete_log_undo_test.dart` | CREATE | Soft-delete with undo + provider invalidation |
| `test/workout_write_service/migration_old_keys_test.dart` | CREATE | Old `exlog_<ts>_<hash>` keys re-hash to deterministic + dedup |
| `docs/superpowers/notes/2026-05-01-workout-write-service-verification.md` | CREATE | Manual on-device test guide for C1-C4 |

---

## Task A-1 — Branch setup + version bump

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Confirm Test #5 merge state and pick branch base**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
git fetch origin
git status --short
```

Expected: clean working tree (or only the spec file pending commit).

```bash
git log feat/apk-test-5-batch..main --oneline 2>&1 | head -5
```

Decision rule:
- If output is **non-empty** (main has commits past test-5 tip) → Test #5 was merged. Branch from `main`.
- If output is **empty** → Test #5 NOT yet merged. Branch from `feat/apk-test-5-batch`.

At plan-write time (2026-05-01), Test #5 is NOT merged (output empty). Proceed off `feat/apk-test-5-batch`.

```bash
git checkout feat/apk-test-5-batch
git pull origin feat/apk-test-5-batch || true   # may have no remote tracking
git checkout -b feat/apk-test-6-batch
git branch --show-current
```

Expected: `feat/apk-test-6-batch`.

- [ ] **Step 2: Bump versionCode +5 → +6**

```bash
grep "^version:" pubspec.yaml
```

Expected: `version: 1.0.0+5`.

Edit `pubspec.yaml`:

```yaml
# BEFORE
version: 1.0.0+5

# AFTER
version: 1.0.0+6
```

- [ ] **Step 3: Confirm spec is on this branch**

The Test #6 spec `docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md` was committed onto `feat/apk-test-5-batch` (HEAD `5fdf294`). Verify it's reachable from the new branch:

```bash
git log --oneline -- docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md | head -3
```

Expected: at least one commit listed (the original spec commit). If empty, abort and investigate before continuing.

- [ ] **Step 4: Commit branch setup**

```bash
git add pubspec.yaml
git commit -m "$(cat <<'EOF'
chore: branch setup for APK Test #6 batch

Bump versionCode 1.0.0+5 -> 1.0.0+6 for APK Test #6 ship.

Branch created off feat/apk-test-5-batch (Test #5 not yet merged to
main as of plan-write time). Will rebase onto main if Test #5 merges
before Test #6 ships.

Plan A scope: WorkoutWriteService rewrite — eliminates duplicate-row
bug class (#16, #20) structurally; closes #3 (plan generator sync gap)
and #12 (provider invalidation after AI coach writes).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Verify branch + commit**

```bash
git log --oneline -1
git branch --show-current
```

Expected: latest commit subject `chore: branch setup for APK Test #6 batch`, branch `feat/apk-test-6-batch`.

---

## Task A-2 — Define data types

**Files:**
- Create: `lib/core/services/write_result.dart`

- [ ] **Step 1: Create the file with shared types**

Write `lib/core/services/write_result.dart`:

```dart
/// Shared write-result types for WorkoutWriteService and (Plan B)
/// NutritionWriteService.
///
/// `WriteResult` is the canonical return shape for every atomic write
/// method. Callers should treat `success == true` as authoritative —
/// the Hive write succeeded and providers were invalidated. Cloud
/// sync is fire-and-forget per CLAUDE.md §15; failure to sync does
/// NOT flip `success` to false.

class WriteResult {
  final bool success;
  final String? logKey;
  final String? errorMessage;

  const WriteResult({
    required this.success,
    this.logKey,
    this.errorMessage,
  });

  factory WriteResult.ok(String logKey) =>
      WriteResult(success: true, logKey: logKey);

  factory WriteResult.fail(String message) =>
      WriteResult(success: false, errorMessage: message);

  @override
  String toString() =>
      'WriteResult(success=$success, logKey=$logKey, error=$errorMessage)';
}

/// Source identifier for telemetry + future per-source policy.
/// Logged into Hive entry's `source` field on every write.
enum WriteSource {
  activeWorkout,
  aiCoach,
  editSheet,
  planGenerator,
  schedSwap,
  restore,
}

extension WriteSourceCode on WriteSource {
  /// Stable string code persisted to Hive + cloud. Never rename
  /// these without a migration.
  String get code {
    switch (this) {
      case WriteSource.activeWorkout:
        return 'active_workout';
      case WriteSource.aiCoach:
        return 'ai_coach';
      case WriteSource.editSheet:
        return 'edit_sheet';
      case WriteSource.planGenerator:
        return 'plan_generator';
      case WriteSource.schedSwap:
        return 'sched_swap';
      case WriteSource.restore:
        return 'restore';
    }
  }
}

/// Single set in an exercise log. Always belongs to a parent
/// `exlog_*` Hive entry's `sets[]` array.
class ExerciseSet {
  final double weightKg;       // 0 for bodyweight
  final int reps;              // 0 for timed exercises
  final int? durationSec;      // null for non-timed; populated for plank/cardio
  final int? loggedAtMs;       // millisecondsSinceEpoch — used for 60s dedup window

  const ExerciseSet({
    required this.weightKg,
    required this.reps,
    this.durationSec,
    this.loggedAtMs,
  });

  Map<String, dynamic> toMap() => {
        'weight_kg': weightKg,
        'reps': reps,
        if (durationSec != null) 'duration_sec': durationSec,
        'logged_at_ms': loggedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      };

  factory ExerciseSet.fromMap(Map<dynamic, dynamic> m) => ExerciseSet(
        weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0.0,
        reps: (m['reps'] as num?)?.toInt() ?? 0,
        durationSec: (m['duration_sec'] as num?)?.toInt(),
        loggedAtMs: (m['logged_at_ms'] as num?)?.toInt(),
      );

  /// True if this set is a (weightKg, reps) duplicate of [other]
  /// logged within the dedup window (default 60s).
  bool isDuplicateWithin(ExerciseSet other, {int windowMs = 60000}) {
    if (weightKg != other.weightKg) return false;
    if (reps != other.reps) return false;
    if (durationSec != other.durationSec) return false;
    final a = loggedAtMs ?? 0;
    final b = other.loggedAtMs ?? 0;
    return (a - b).abs() <= windowMs;
  }
}
```

- [ ] **Step 2: Verify analyzer**

```bash
flutter analyze lib/core/services/write_result.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/write_result.dart
git commit -m "$(cat <<'EOF'
feat(write-service): add WriteResult / WriteSource / ExerciseSet types

Plan A Task A-2. Shared types for the new WorkoutWriteService (this
plan) and the upcoming NutritionWriteService (Plan B).

- WriteResult — canonical return shape; `success` decoupled from
  cloud-sync outcome (sync is fire-and-forget per CLAUDE.md §15).
- WriteSource enum — telemetry + future per-source policy hook.
- ExerciseSet — single set in an exlog_* sets[] array; carries
  loggedAtMs so the 60s per-set dedup window can compare to other
  sets in the same array.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-3 — Stub WorkoutWriteService skeleton

**Files:**
- Create: `lib/core/services/workout_write_service.dart`
- Create: `test/workout_write_service/log_exercise_dedup_60s_test.dart` (scaffold only — TDD next task)

- [ ] **Step 1: Create the service skeleton**

Write `lib/core/services/workout_write_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'hive_service.dart';
import 'sync_service.dart';
import 'write_result.dart';

/// The ONE writer for workout_logs / workout_log_exercises /
/// workout_log_sets. All Hive `exlog_*`, `wlog_*`, and `schedule_<date>`
/// mutations flow through this service.
///
/// Per-(date, exerciseName) mutex serializes concurrent writes — two
/// simultaneous logExercise calls for the same exercise will merge
/// their sets into a single Hive entry rather than racing.
///
/// Hive key scheme (post Plan A):
/// - `exlog_<istDateStr>_<hash(name)>`  — deterministic; one row per
///   (date, exerciseName).
/// - `wlog_<istDateStr>`                — workout-level summary.
/// - `schedule_<istDateStr>`            — schedule entry.
///
/// Cloud sync is 3-tier (writes 1 + 1 + N rows):
/// - `workout_logs`             (1 per date)
/// - `workout_log_exercises`    (1 per (date, exerciseName))
/// - `workout_log_sets`         (N per (date, exerciseName) — one per
///                               ExerciseSet)
///
/// Cloud sync fires fire-and-forget after the Hive write succeeds.
class WorkoutWriteService {
  WorkoutWriteService._();
  static final WorkoutWriteService instance = WorkoutWriteService._();

  /// Per-key mutex. Key format: `<istDateStr>::<exerciseName>` for
  /// per-exercise methods, `<istDateStr>` for schedule-only methods.
  final Map<String, Completer<void>> _locks = {};

  /// 60-second dedup window for per-set duplicate detection.
  static const int kDedupWindowMs = 60000;

  /// Provider invalidation batch fired after every successful write.
  /// Caller injects [ref] when running under Riverpod; pure-Hive
  /// callers (tests, headless paths) pass null.
  void Function(WidgetRef ref)? onInvalidate;

  // ─────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────

  Future<WriteResult> logExercise({
    required DateTime date,
    required String exerciseName,
    required List<ExerciseSet> sets,
    String? notes,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('logExercise — implemented in Task A-4');
  }

  Future<WriteResult> markCompleted({
    required DateTime date,
    required String workoutName,
    required int durationSec,
    int? rpe,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('markCompleted — implemented in Task A-6');
  }

  Future<WriteResult> upsertScheduled({
    required DateTime date,
    required Map<String, dynamic> entry,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('upsertScheduled — implemented in Task A-7');
  }

  Future<WriteResult> rescheduleDay({
    required DateTime fromDate,
    required DateTime toDate,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('rescheduleDay — implemented in Task A-8');
  }

  Future<WriteResult> regenerateWeek({
    required DateTime fromDate,
    required Map<String, dynamic> params,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('regenerateWeek — implemented in Task A-8');
  }

  Future<WriteResult> editLog({
    required String logKey,
    required Map<String, dynamic> updates,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('editLog — implemented in Task A-9');
  }

  Future<WriteResult> deleteLog({
    required String logKey,
    bool allowUndo = true,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('deleteLog — implemented in Task A-9');
  }

  // ─────────────────────────────────────────────────────────────
  //  Helpers (used by methods implemented in later tasks)
  // ─────────────────────────────────────────────────────────────

  /// IST-derived YYYY-MM-DD string. Public for callers that already
  /// have an IST-aware DateTime and need the same hashing rule.
  static String istDateStr(DateTime dt) {
    // Convert to IST regardless of input zone.
    final ist = dt.toUtc().add(const Duration(hours: 5, minutes: 30));
    final y = ist.year.toString().padLeft(4, '0');
    final m = ist.month.toString().padLeft(2, '0');
    final d = ist.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Deterministic Hive key for an exercise log.
  static String exlogKey(DateTime date, String exerciseName) {
    final d = istDateStr(date);
    final h = exerciseName.toLowerCase().trim().hashCode;
    return 'exlog_${d}_$h';
  }

  /// Deterministic Hive key for a workout-level summary.
  static String wlogKey(DateTime date) => 'wlog_${istDateStr(date)}';

  /// Deterministic Hive key for a schedule entry.
  static String scheduleKey(DateTime date) =>
      'schedule_${istDateStr(date)}';

  /// Acquire mutex for the given key. Returns the completer the
  /// caller MUST `complete()` in a finally block.
  Future<Completer<void>> _acquireLock(String key) async {
    while (_locks.containsKey(key)) {
      await _locks[key]!.future;
    }
    final c = Completer<void>();
    _locks[key] = c;
    return c;
  }

  void _releaseLock(String key, Completer<void> c) {
    _locks.remove(key);
    if (!c.isCompleted) c.complete();
  }
}
```

- [ ] **Step 2: Create test scaffold (will fail with UnimplementedError — that's expected)**

Write `test/workout_write_service/log_exercise_dedup_60s_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();
  });

  tearDown(() async {
    await wwsTestTeardown();
  });

  test('SCAFFOLD: logExercise throws UnimplementedError until Task A-4', () async {
    expect(
      () => WorkoutWriteService.instance.logExercise(
        date: DateTime(2026, 5, 1),
        exerciseName: 'Bench Press',
        sets: const [ExerciseSet(weightKg: 60, reps: 8)],
        source: WriteSource.activeWorkout,
      ),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
```

- [ ] **Step 3: Create test setup helper**

Write `test/workout_write_service/helpers/wws_test_setup.dart`:

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

Directory? _tempDir;

Future<void> wwsTestSetup() async {
  _tempDir = await Directory.systemTemp.createTemp('wws_test_');

  // Mock path_provider so Hive.initFlutter-equivalent calls resolve
  // in pure-unit-test mode.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => _tempDir!.path,
  );

  Hive.init(_tempDir!.path);

  // HiveService.instance.init() registers adapters + opens shared
  // boxes. Must be called before HiveUserSession.openForUser so the
  // user-scoped boxes pick up the same adapter registry.
  await HiveService.instance.init();

  // Test user — 8-hex suffix used by HiveUserSession.
  await HiveService.instance.openUserScopedBoxes(
    'test-user-id-12345678-aaaa-bbbb-cccc-dddddddddddd',
  );
}

Future<void> wwsTestTeardown() async {
  await Hive.deleteFromDisk();
  await Hive.close();
  if (_tempDir != null && await _tempDir!.exists()) {
    await _tempDir!.delete(recursive: true);
  }
  _tempDir = null;
}
```

NOTE: `HiveService.instance.openUserScopedBoxes(...)` is the entry point added by Plan A of Test #5. If the existing API is `HiveUserSession.openForUser(...)`, swap the line. Verify:

```bash
grep -n "openForUser\|openUserScopedBoxes" lib/core/services/hive_user_session.dart lib/core/services/hive_service.dart | head -10
```

Adjust the import + call to match the actual API.

- [ ] **Step 4: Run scaffold test**

```bash
flutter test test/workout_write_service/log_exercise_dedup_60s_test.dart
```

Expected: 1 test passes (it asserts `UnimplementedError` is thrown).

- [ ] **Step 5: Analyze**

```bash
flutter analyze lib/core/services/workout_write_service.dart test/workout_write_service/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/workout_write_service.dart test/workout_write_service/
git commit -m "$(cat <<'EOF'
feat(write-service): scaffold WorkoutWriteService skeleton + test setup

Plan A Task A-3. Singleton WorkoutWriteService with 6 public methods
all throwing UnimplementedError; per-key mutex map; deterministic key
helpers (exlogKey / wlogKey / scheduleKey using IST-derived date).

Test setup helper wwsTestSetup() handles path_provider mock + Hive
init + HiveUserSession opening for unit tests. Scaffold test confirms
the throws contract before TDD-replacing each method body.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-4 — Implement `logExercise` with merge + 60s dedup

**Files:**
- Modify: `lib/core/services/workout_write_service.dart`
- Modify: `test/workout_write_service/log_exercise_dedup_60s_test.dart`
- Create: `test/workout_write_service/log_exercise_appends_sets_test.dart`
- Create: `test/workout_write_service/log_exercise_new_day_test.dart`

- [ ] **Step 1: Write failing test for 60s dedup**

Replace `test/workout_write_service/log_exercise_dedup_60s_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('60s dedup: same (weight, reps) twice within 60s → 1 entry in sets[]',
      () async {
    final date = DateTime(2026, 5, 1, 10);
    final now = date.millisecondsSinceEpoch;

    final r1 = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [
        ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now),
      ],
      source: WriteSource.aiCoach,
    );
    expect(r1.success, isTrue);

    // Same (weight, reps) 30s later — should be deduped.
    final r2 = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [
        ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now + 30000),
      ],
      source: WriteSource.aiCoach,
    );
    expect(r2.success, isTrue);

    final box = HiveService.instance.workoutBox;
    final key = WorkoutWriteService.exlogKey(date, 'Lat Pulldown');
    final entry = (box.get(key) as Map?)!.cast<String, dynamic>();
    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.length, 1, reason: 'duplicate inside 60s window must be dropped');
  });

  test('60s dedup: same (weight, reps) AFTER 60s → 2 entries in sets[]',
      () async {
    final date = DateTime(2026, 5, 1, 10);
    final now = date.millisecondsSinceEpoch;

    await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now)],
      source: WriteSource.aiCoach,
    );

    // Same set 90s later — different rest interval, treat as a new
    // legitimate set.
    await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now + 90000)],
      source: WriteSource.aiCoach,
    );

    final box = HiveService.instance.workoutBox;
    final key = WorkoutWriteService.exlogKey(date, 'Lat Pulldown');
    final entry = (box.get(key) as Map?)!.cast<String, dynamic>();
    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.length, 2);
  });
}
```

- [ ] **Step 2: Write failing test for append-sets-across-calls**

Write `test/workout_write_service/log_exercise_appends_sets_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('appends sets across calls: 4 calls → 1 row, sets[].length=4', () async {
    final date = DateTime(2026, 5, 1);
    final progression = [
      ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: date.millisecondsSinceEpoch),
      ExerciseSet(weightKg: 60, reps: 10, loggedAtMs: date.millisecondsSinceEpoch + 90_000),
      ExerciseSet(weightKg: 80, reps: 10, loggedAtMs: date.millisecondsSinceEpoch + 180_000),
      ExerciseSet(weightKg: 100, reps: 7, loggedAtMs: date.millisecondsSinceEpoch + 270_000),
    ];

    for (final s in progression) {
      final r = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Lat Pulldown',
        sets: [s],
        source: WriteSource.aiCoach,
      );
      expect(r.success, isTrue);
    }

    final box = HiveService.instance.workoutBox;
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 1, reason: 'exactly ONE row across 4 calls');

    final entry =
        (box.get(exlogKeys.first) as Map?)!.cast<String, dynamic>();
    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.length, 4);

    // Aggregates
    expect(entry['set_number'], 4);
    expect(entry['reps_completed'], 37);
    expect(entry['weight_kg'], 100);
    expect((entry['volume_kg'] as num).toInt(), 40 * 10 + 60 * 10 + 80 * 10 + 100 * 7);
  });

  test('multiple sets in single call: one logExercise(sets: [4 sets]) → 1 row, sets[].length=4',
      () async {
    final date = DateTime(2026, 5, 1);
    final base = date.millisecondsSinceEpoch;

    final r = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [
        ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: base),
        ExerciseSet(weightKg: 60, reps: 10, loggedAtMs: base + 90_000),
        ExerciseSet(weightKg: 80, reps: 10, loggedAtMs: base + 180_000),
        ExerciseSet(weightKg: 100, reps: 7, loggedAtMs: base + 270_000),
      ],
      source: WriteSource.aiCoach,
    );
    expect(r.success, isTrue);

    final box = HiveService.instance.workoutBox;
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 1);
    final entry = (box.get(exlogKeys.first) as Map?)!.cast<String, dynamic>();
    expect((entry['sets'] as List).length, 4);
  });
}
```

- [ ] **Step 3: Write failing test for new-day-creates-new-entry**

Write `test/workout_write_service/log_exercise_new_day_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('new day creates new entry; old day untouched', () async {
    final mon = DateTime(2026, 5, 4);
    final tue = DateTime(2026, 5, 5);

    await WorkoutWriteService.instance.logExercise(
      date: mon,
      exerciseName: 'Lat Pulldown',
      sets: [ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: mon.millisecondsSinceEpoch)],
      source: WriteSource.activeWorkout,
    );

    await WorkoutWriteService.instance.logExercise(
      date: tue,
      exerciseName: 'Lat Pulldown',
      sets: [ExerciseSet(weightKg: 60, reps: 8, loggedAtMs: tue.millisecondsSinceEpoch)],
      source: WriteSource.activeWorkout,
    );

    final box = HiveService.instance.workoutBox;
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 2, reason: 'two distinct days → two distinct entries');

    final monKey = WorkoutWriteService.exlogKey(mon, 'Lat Pulldown');
    final tueKey = WorkoutWriteService.exlogKey(tue, 'Lat Pulldown');
    expect(monKey == tueKey, isFalse);
    expect(box.containsKey(monKey), isTrue);
    expect(box.containsKey(tueKey), isTrue);
  });
}
```

- [ ] **Step 4: Run all three tests — they should FAIL with UnimplementedError**

```bash
flutter test test/workout_write_service/log_exercise_dedup_60s_test.dart \
            test/workout_write_service/log_exercise_appends_sets_test.dart \
            test/workout_write_service/log_exercise_new_day_test.dart
```

Expected: failures (UnimplementedError). Confirm before implementing.

- [ ] **Step 5: Implement `logExercise`**

Replace the `logExercise` method body in `lib/core/services/workout_write_service.dart`:

```dart
  Future<WriteResult> logExercise({
    required DateTime date,
    required String exerciseName,
    required List<ExerciseSet> sets,
    String? notes,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    // 1. Validate
    if (exerciseName.trim().isEmpty) {
      return WriteResult.fail('exerciseName must be non-empty');
    }
    if (sets.isEmpty) {
      return WriteResult.fail('sets must be non-empty');
    }
    for (final s in sets) {
      if (s.weightKg < 0) return WriteResult.fail('weightKg must be >= 0');
      if (s.reps < 0) return WriteResult.fail('reps must be >= 0');
    }

    final dateStr = istDateStr(date);
    final lockKey = '$dateStr::${exerciseName.toLowerCase().trim()}';
    final c = await _acquireLock(lockKey);

    try {
      final box = HiveService.instance.workoutBox;
      final key = exlogKey(date, exerciseName);
      final existing = box.get(key);

      // 2. Build merged sets[] list with 60s dedup
      final List<ExerciseSet> mergedSets;
      if (existing != null) {
        final m = (existing as Map).cast<String, dynamic>();
        final existingSets = (m['sets'] as List? ?? const [])
            .cast<Map>()
            .map((e) => ExerciseSet.fromMap(e))
            .toList();

        final List<ExerciseSet> additions = [];
        for (final candidate in sets) {
          // Stamp loggedAtMs if caller didn't.
          final stamped = candidate.loggedAtMs == null
              ? ExerciseSet(
                  weightKg: candidate.weightKg,
                  reps: candidate.reps,
                  durationSec: candidate.durationSec,
                  loggedAtMs: DateTime.now().millisecondsSinceEpoch,
                )
              : candidate;

          // Dedup against existing sets (60s window).
          final isDup = existingSets.any((existing) =>
              stamped.isDuplicateWithin(existing, windowMs: kDedupWindowMs));
          if (!isDup) additions.add(stamped);
        }

        mergedSets = [...existingSets, ...additions];
      } else {
        mergedSets = sets
            .map((s) => s.loggedAtMs == null
                ? ExerciseSet(
                    weightKg: s.weightKg,
                    reps: s.reps,
                    durationSec: s.durationSec,
                    loggedAtMs: DateTime.now().millisecondsSinceEpoch,
                  )
                : s)
            .toList();
      }

      // 3. Recompute aggregates
      final totalReps = mergedSets.fold<int>(0, (a, s) => a + s.reps);
      final maxWeight = mergedSets.fold<double>(
          0.0, (a, s) => s.weightKg > a ? s.weightKg : a);
      final volume = mergedSets.fold<double>(
          0.0, (a, s) => a + (s.weightKg * s.reps));

      final entry = <String, dynamic>{
        'exercise_name': exerciseName,
        'date': dateStr,
        'sets': mergedSets.map((s) => s.toMap()).toList(),
        'set_number': mergedSets.length,
        'reps_completed': totalReps,
        'weight_kg': maxWeight,
        'volume_kg': volume,
        'logging_type': _inferLoggingType(mergedSets),
        'source': source.code,
        if (notes != null) 'notes': notes,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };

      // 4. PR rescan (chronological — strict > comparison; existing
      // pattern from EditWorkoutLogSheet).
      entry['is_pr'] = _rescanPrFor(box, exerciseName, dateStr, maxWeight);

      // 5. Write Hive
      await box.put(key, entry);

      // 6. Update exercise_log_index_<date>
      _appendToIndex(box, dateStr, key);

      // 7. Fire-and-forget cloud sync
      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      // 8. Provider invalidation
      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService] invalidation failed: $e\n$st');
        }
      }

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.logExercise] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  String _inferLoggingType(List<ExerciseSet> sets) {
    final hasDur = sets.any((s) => s.durationSec != null && s.durationSec! > 0);
    final hasWeight = sets.any((s) => s.weightKg > 0);
    if (hasDur && !hasWeight) return 'timed';
    if (hasWeight) return 'weight_reps';
    return 'bodyweight_reps';
  }

  bool _rescanPrFor(
    Box box,
    String exerciseName,
    String dateStr,
    double maxWeight,
  ) {
    final lower = exerciseName.toLowerCase().trim();
    double bestBefore = 0.0;
    for (final k in box.keys) {
      if (!k.toString().startsWith('exlog_')) continue;
      final v = box.get(k);
      if (v is! Map) continue;
      final n = (v['exercise_name'] as String?)?.toLowerCase().trim();
      if (n != lower) continue;
      final d = v['date'] as String?;
      if (d == null) continue;
      if (d.compareTo(dateStr) >= 0) continue; // strict before
      final w = (v['weight_kg'] as num?)?.toDouble() ?? 0.0;
      if (w > bestBefore) bestBefore = w;
    }
    return maxWeight > bestBefore;
  }

  void _appendToIndex(Box box, String dateStr, String key) {
    final indexKey = 'exercise_log_index_$dateStr';
    final raw = box.get(indexKey);
    final List<String> list = (raw is List)
        ? raw.cast<String>().toList()
        : <String>[];
    if (!list.contains(key)) list.add(key);
    box.put(indexKey, list);
  }
```

- [ ] **Step 6: Run all three tests — should now PASS**

```bash
flutter test test/workout_write_service/log_exercise_dedup_60s_test.dart \
            test/workout_write_service/log_exercise_appends_sets_test.dart \
            test/workout_write_service/log_exercise_new_day_test.dart
```

Expected: all green.

- [ ] **Step 7: Analyze**

```bash
flutter analyze lib/core/services/workout_write_service.dart test/workout_write_service/
```

Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/core/services/workout_write_service.dart test/workout_write_service/
git commit -m "$(cat <<'EOF'
feat(write-service): logExercise with merge + 60s per-set dedup

Plan A Task A-4. logExercise() now atomically:

1. Validates input (non-empty name, non-empty sets, weight/reps >= 0)
2. Acquires (date, exerciseName) mutex
3. Reads existing exlog_<date>_<hash> entry
4. Merges new sets into sets[] with 60s dedup against existing
5. Recomputes aggregates (set_number, reps_completed, weight_kg=max,
   volume_kg=sum)
6. Chronologically rescans is_pr (strict > comparison vs prior dates)
7. Writes Hive + appends key to exercise_log_index_<date>
8. Fires unawaited(syncWorkoutData) + unawaited(pushSnapshot)
9. Invalidates canonical provider batch (if ref + onInvalidate set)
10. Releases mutex

3 TDD tests pass:
- 60s dedup window (within drops, after keeps)
- Append across multiple calls (1 row, sets[] grows)
- New day creates new entry (2 distinct exlog_* rows)

Cloud sync schema upgrade (3-tier writes) is wired in Task A-5.
The unawaited(syncWorkoutData) call here is the trigger.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-5 — Implement `logExercise` cloud sync (3-tier)

**Files:**
- Modify: `lib/core/services/sync_service.dart`
- Create: `test/workout_write_service/sync_three_tier_test.dart`

- [ ] **Step 1: Locate the existing exercise-log projector**

```bash
grep -nB 2 -A 40 "_projectExerciseLog\|_syncExerciseLogs\|_pushExerciseLogs" lib/core/services/sync_service.dart | head -80
```

Note the function name + signature in the working tree. The new behavior must extend (not replace) it.

- [ ] **Step 2: Extend the projector to write 3-tier**

In `lib/core/services/sync_service.dart`, locate `_projectExerciseLog` (or equivalent) and update it so each `exlog_*` Hive entry projects:

(a) one upsert into `workout_logs` (1 row per `wlog_<date>` — derived from the date)
(b) one upsert into `workout_log_exercises` (1 row per (date, exerciseName))
(c) **N upserts into `workout_log_sets`** (one row per `ExerciseSet` in `sets[]`)

```dart
  /// Project a single Hive `exlog_<date>_<hash>` entry into 3 cloud
  /// tables. Replaces the old single-table projector.
  ///
  /// Tier 1: workout_logs (UPSERT by deterministic UUID from date)
  /// Tier 2: workout_log_exercises
  ///         (UPSERT by (workout_log_id, exercise_id))
  /// Tier 3: workout_log_sets — N rows (one per set)
  ///         (UPSERT by (workout_log_id, exercise_id, set_number))
  Future<void> _projectExerciseLogThreeTier(
    String hiveKey,
    Map<String, dynamic> entry,
    String supabaseUserId,
  ) async {
    final dateStr = entry['date'] as String?;
    final exerciseName = entry['exercise_name'] as String?;
    if (dateStr == null || exerciseName == null) return;

    final workoutLogId = _deterministicId('wlog_$dateStr');
    final exerciseId = exerciseName; // stable cross-week identity

    // Tier 1 — workout_logs row (idempotent — many exercises same day)
    await _client.from('workout_logs').upsert({
      'id': workoutLogId,
      'user_id': supabaseUserId,
      'workout_date': dateStr,
      'completed_at': _completedAtFor(dateStr),
    }, onConflict: 'id');

    // Tier 2 — workout_log_exercises (per-exercise summary)
    await _client.from('workout_log_exercises').upsert({
      'workout_log_id': workoutLogId,
      'exercise_id': exerciseId,
      'set_number': entry['set_number'] ?? 0,
      'reps': entry['reps_completed'] ?? 0,
      'weight_kg': entry['weight_kg'] ?? 0,
      'volume_kg': entry['volume_kg'] ?? 0,
      'is_pr': entry['is_pr'] ?? false,
      'updated_at_ms': entry['updated_at_ms'],
    }, onConflict: 'workout_log_id,exercise_id');

    // Tier 3 — workout_log_sets (one row per ExerciseSet)
    final sets = (entry['sets'] as List? ?? const []).cast<Map>();
    for (var i = 0; i < sets.length; i++) {
      final s = sets[i].cast<String, dynamic>();
      await _client.from('workout_log_sets').upsert({
        'workout_log_id': workoutLogId,
        'exercise_id': exerciseId,
        'set_number': i + 1,
        'weight_kg': s['weight_kg'] ?? 0,
        'reps': s['reps'] ?? 0,
        if (s['duration_sec'] != null) 'duration_sec': s['duration_sec'],
        'logged_at_ms': s['logged_at_ms'],
      }, onConflict: 'workout_log_id,exercise_id,set_number');
    }
  }

  String _completedAtFor(String dateStr) {
    // 23:59 IST of `dateStr` (UTC = -5:30 IST → 18:29 UTC).
    return '${dateStr}T18:29:00+00:00';
  }
```

Wire `_projectExerciseLogThreeTier` into the existing `syncWorkoutData()` loop — replace the single-table call with the 3-tier call.

If the codebase's sync function uses a different `_deterministicId` helper, reuse it (don't invent a new UUID generator). If `workout_log_id` field is `bigint` not `uuid` in the schema, adapt to `int.parse(dateStr.replaceAll('-', ''))` instead — confirm the column type via `mcp__ba7b5e8e__execute_sql`:

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'workout_log_sets';
```

- [ ] **Step 3: Test (mock-based)**

Write `test/workout_write_service/sync_three_tier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('logExercise writes Hive entry with all fields needed for 3-tier sync',
      () async {
    final date = DateTime(2026, 5, 1);
    final now = date.millisecondsSinceEpoch;

    await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [
        ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now),
        ExerciseSet(weightKg: 60, reps: 10, loggedAtMs: now + 90_000),
        ExerciseSet(weightKg: 80, reps: 10, loggedAtMs: now + 180_000),
        ExerciseSet(weightKg: 100, reps: 7, loggedAtMs: now + 270_000),
      ],
      source: WriteSource.aiCoach,
    );

    final box = HiveService.instance.workoutBox;
    final key = WorkoutWriteService.exlogKey(date, 'Lat Pulldown');
    final entry = (box.get(key) as Map?)!.cast<String, dynamic>();

    // Tier 1 fields (workout_logs)
    expect(entry['date'], '2026-05-01');

    // Tier 2 fields (workout_log_exercises)
    expect(entry['exercise_name'], 'Lat Pulldown');
    expect(entry['set_number'], 4);
    expect(entry['reps_completed'], 37);
    expect(entry['weight_kg'], 100);
    expect((entry['volume_kg'] as num).toInt(), 2300);

    // Tier 3 fields (workout_log_sets) — one map per ExerciseSet
    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.length, 4);
    expect(sets[0]['weight_kg'], 40);
    expect(sets[3]['weight_kg'], 100);
    expect(sets.every((s) => s['logged_at_ms'] != null), isTrue);
  });
}
```

- [ ] **Step 4: Run tests + analyze**

```bash
flutter test test/workout_write_service/
flutter analyze lib/core/services/sync_service.dart
```

Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/sync_service.dart test/workout_write_service/sync_three_tier_test.dart
git commit -m "$(cat <<'EOF'
feat(sync): 3-tier exercise log projection (workout_logs + exercises + sets)

Plan A Task A-5. _projectExerciseLogThreeTier replaces the old
single-table projector. Each exlog_<date>_<hash> Hive entry now
projects to:

- 1 upsert into workout_logs (per date)
- 1 upsert into workout_log_exercises (per (date, exerciseName))
- N upserts into workout_log_sets (per ExerciseSet in sets[])

Closes spec C2: cloud `workout_log_sets` actually populates with
per-set granularity instead of staying empty (CLAUDE.md §11 noted
this table was unused).

Idempotent via ON CONFLICT — re-sync of the same exlog_* key
produces identical cloud state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-6 — Implement `markCompleted`

**Files:**
- Modify: `lib/core/services/workout_write_service.dart`
- Create: `test/workout_write_service/mark_completed_test.dart`

- [ ] **Step 1: Write failing test**

Write `test/workout_write_service/mark_completed_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('markCompleted: schedule status=completed + wlog_<date> written',
      () async {
    final date = DateTime(2026, 5, 1);
    final box = HiveService.instance.workoutBox;
    final scheduleKey = WorkoutWriteService.scheduleKey(date);
    final wlogKey = WorkoutWriteService.wlogKey(date);

    // Seed a scheduled workout
    await box.put(scheduleKey, {
      'workout_name': 'Push Day',
      'status': 'pending',
      'type': 'plan',
    });

    final r = await WorkoutWriteService.instance.markCompleted(
      date: date,
      workoutName: 'Push Day',
      durationSec: 3600,
      rpe: 7,
    );
    expect(r.success, isTrue);

    final scheduleAfter =
        (box.get(scheduleKey) as Map).cast<String, dynamic>();
    expect(scheduleAfter['status'], 'completed');

    final wlog = (box.get(wlogKey) as Map?)!.cast<String, dynamic>();
    expect(wlog['workout_name'], 'Push Day');
    expect(wlog['duration_seconds'], 3600);
    expect(wlog['rpe'], 7);
  });

  test('markCompleted is idempotent (second call doesn\'t duplicate wlog)',
      () async {
    final date = DateTime(2026, 5, 1);

    await WorkoutWriteService.instance.markCompleted(
      date: date,
      workoutName: 'Push Day',
      durationSec: 3600,
    );
    await WorkoutWriteService.instance.markCompleted(
      date: date,
      workoutName: 'Push Day',
      durationSec: 3700, // updated duration
    );

    final box = HiveService.instance.workoutBox;
    final wlogKeys =
        box.keys.where((k) => k.toString().startsWith('wlog_')).toList();
    expect(wlogKeys.length, 1);
    final wlog = (box.get(wlogKeys.first) as Map).cast<String, dynamic>();
    expect(wlog['duration_seconds'], 3700, reason: 'second call updates');
  });
}
```

- [ ] **Step 2: Implement `markCompleted`**

In `lib/core/services/workout_write_service.dart` replace the stub:

```dart
  Future<WriteResult> markCompleted({
    required DateTime date,
    required String workoutName,
    required int durationSec,
    int? rpe,
    WidgetRef? ref,
  }) async {
    if (workoutName.trim().isEmpty) {
      return WriteResult.fail('workoutName must be non-empty');
    }
    if (durationSec < 0) {
      return WriteResult.fail('durationSec must be >= 0');
    }

    final dateStr = istDateStr(date);
    final c = await _acquireLock(dateStr);
    try {
      final box = HiveService.instance.workoutBox;
      final sKey = scheduleKey(date);
      final wKey = wlogKey(date);

      // 1. Update schedule entry status='completed' (preserve other fields)
      final sched = box.get(sKey);
      if (sched is Map) {
        final m = sched.cast<String, dynamic>();
        m['status'] = 'completed';
        m['completed_at_ms'] = DateTime.now().millisecondsSinceEpoch;
        await box.put(sKey, m);
      } else {
        // No prior schedule (e.g. AI-coach-only logging) — synthesize one.
        await box.put(sKey, {
          'workout_name': workoutName,
          'status': 'completed',
          'type': 'logged',
          'completed_at_ms': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // 2. Upsert wlog_<date>
      final wlog = <String, dynamic>{
        'workout_name': workoutName,
        'date': dateStr,
        'duration_seconds': durationSec,
        if (rpe != null) 'rpe': rpe,
        'completed_at_ms': DateTime.now().millisecondsSinceEpoch,
      };
      await box.put(wKey, wlog);

      // 3. Fire-and-forget cloud sync
      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      // 4. Provider invalidation
      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.markCompleted] inv: $e\n$st');
        }
      }

      return WriteResult.ok(wKey);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.markCompleted] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(dateStr, c);
    }
  }
```

- [ ] **Step 3: Run + analyze**

```bash
flutter test test/workout_write_service/mark_completed_test.dart
flutter analyze lib/core/services/workout_write_service.dart
```

Expected: green.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/workout_write_service.dart test/workout_write_service/mark_completed_test.dart
git commit -m "$(cat <<'EOF'
feat(write-service): markCompleted updates schedule + writes wlog_<date>

Plan A Task A-6. markCompleted() atomically:
1. Sets schedule_<date>.status = 'completed' (preserves other fields)
   or synthesizes the schedule row if absent (AI-coach-only log path).
2. Upserts wlog_<date> with workout_name, duration, optional RPE.
3. Fires unawaited(syncWorkoutData) + unawaited(pushSnapshot).
4. Invalidates canonical provider batch.

Idempotent — second call same date updates fields rather than
duplicating wlog rows. Fixes #12 perception (workout screen reflects
AI coach completion immediately) once the providers in the canonical
batch include todayWorkoutProvider.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-7 — Implement `upsertScheduled` (closes #3)

**Files:**
- Modify: `lib/core/services/workout_write_service.dart`
- Create: `test/workout_write_service/upsert_scheduled_test.dart`

- [ ] **Step 1: Write failing test**

Write `test/workout_write_service/upsert_scheduled_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('upsertScheduled writes schedule_<date> and queues sync', () async {
    final date = DateTime(2026, 5, 1);

    final r = await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: {
        'workout_name': 'Push Day',
        'status': 'pending',
        'type': 'plan',
        'week': 1,
        'exercises': [
          {'exercise_name': 'Bench Press', 'sets': 4, 'reps': '5-8'},
        ],
      },
      source: WriteSource.planGenerator,
    );
    expect(r.success, isTrue);

    final box = HiveService.instance.workoutBox;
    final stored =
        (box.get(WorkoutWriteService.scheduleKey(date)) as Map).cast<String, dynamic>();
    expect(stored['workout_name'], 'Push Day');
    expect(stored['status'], 'pending');
    expect(stored['exercises'], isA<List>());
    expect(stored['source'], 'plan_generator');
  });

  test('upsertScheduled with status=rest preserves reason field', () async {
    final date = DateTime(2026, 5, 1);

    await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: {
        'workout_name': 'Rest',
        'status': 'rest',
        'type': 'plan',
        'reason': 'pre_onboarding',
      },
      source: WriteSource.planGenerator,
    );

    final box = HiveService.instance.workoutBox;
    final stored =
        (box.get(WorkoutWriteService.scheduleKey(date)) as Map).cast<String, dynamic>();
    expect(stored['status'], 'rest');
    expect(stored['reason'], 'pre_onboarding');
  });
}
```

- [ ] **Step 2: Implement**

```dart
  Future<WriteResult> upsertScheduled({
    required DateTime date,
    required Map<String, dynamic> entry,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final dateStr = istDateStr(date);
    final c = await _acquireLock(dateStr);
    try {
      final box = HiveService.instance.workoutBox;
      final key = scheduleKey(date);

      final stamped = <String, dynamic>{
        ...entry,
        'date': dateStr,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };
      await box.put(key, stamped);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.upsertScheduled] inv: $e\n$st');
        }
      }

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.upsertScheduled] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(dateStr, c);
    }
  }
```

- [ ] **Step 3: Run + analyze**

```bash
flutter test test/workout_write_service/upsert_scheduled_test.dart
flutter analyze lib/core/services/workout_write_service.dart
```

Expected: green.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/workout_write_service.dart test/workout_write_service/upsert_scheduled_test.dart
git commit -m "$(cat <<'EOF'
feat(write-service): upsertScheduled — closes #3 (plan generator sync gap)

Plan A Task A-7. upsertScheduled() is the atomic writer for
schedule_<date> entries. Stamps:
- date (IST-derived)
- source (telemetry — plan_generator | sched_swap | restore | etc.)
- updated_at_ms

Then fires unawaited(syncWorkoutData) + unawaited(pushSnapshot). This
closes spec obs #3 — pre-A6 the plan generator wrote schedule_*
keys directly to Hive without firing sync, so cloud
`scheduled_workouts` stayed empty (0 rows).

Hooked into the plan generator path in Task A-15.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-8 — Implement `rescheduleDay` + `regenerateWeek`

**Files:**
- Modify: `lib/core/services/workout_write_service.dart`
- Create: `test/workout_write_service/reschedule_day_test.dart`
- Create: `test/workout_write_service/regenerate_week_test.dart`

- [ ] **Step 1: Write failing test for `rescheduleDay`**

Write `test/workout_write_service/reschedule_day_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('rescheduleDay swaps from→to atomically; original becomes rest', () async {
    final friday = DateTime(2026, 5, 1);
    final today = DateTime(2026, 4, 30);

    final box = HiveService.instance.workoutBox;
    await box.put(WorkoutWriteService.scheduleKey(friday), {
      'workout_name': 'Pull Day',
      'status': 'pending',
      'type': 'plan',
    });
    await box.put(WorkoutWriteService.scheduleKey(today), {
      'workout_name': 'Push Day',
      'status': 'pending',
      'type': 'plan',
    });

    final r = await WorkoutWriteService.instance.rescheduleDay(
      fromDate: friday,
      toDate: today,
      source: WriteSource.aiCoach,
    );
    expect(r.success, isTrue);

    final fri = (box.get(WorkoutWriteService.scheduleKey(friday)) as Map)
        .cast<String, dynamic>();
    final tod = (box.get(WorkoutWriteService.scheduleKey(today)) as Map)
        .cast<String, dynamic>();

    expect(tod['workout_name'], 'Pull Day');
    expect(fri['workout_name'], 'Push Day');
    expect(fri['source'], 'ai_coach');
    expect(tod['source'], 'ai_coach');
  });
}
```

- [ ] **Step 2: Implement `rescheduleDay`**

```dart
  Future<WriteResult> rescheduleDay({
    required DateTime fromDate,
    required DateTime toDate,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final fromStr = istDateStr(fromDate);
    final toStr = istDateStr(toDate);
    if (fromStr == toStr) {
      return WriteResult.fail('fromDate and toDate are the same');
    }

    // Lock both dates (deterministic order to avoid deadlock)
    final keys = [fromStr, toStr]..sort();
    final c1 = await _acquireLock(keys[0]);
    final c2 = await _acquireLock(keys[1]);
    try {
      final box = HiveService.instance.workoutBox;
      final fromKey = scheduleKey(fromDate);
      final toKey = scheduleKey(toDate);

      final fromEntry =
          (box.get(fromKey) as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final toEntry =
          (box.get(toKey) as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

      // Swap (entries keep their original date stamps but the
      // workout content moves).
      final newFrom = <String, dynamic>{
        ...toEntry,
        'date': fromStr,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };
      final newTo = <String, dynamic>{
        ...fromEntry,
        'date': toStr,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };

      await box.put(fromKey, newFrom);
      await box.put(toKey, newTo);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.rescheduleDay] inv: $e\n$st');
        }
      }

      return WriteResult.ok(toKey);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.rescheduleDay] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(keys[1], c2);
      _releaseLock(keys[0], c1);
    }
  }
```

- [ ] **Step 3: Write failing test for `regenerateWeek`**

Write `test/workout_write_service/regenerate_week_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('regenerateWeek replaces 7 schedule entries from fromDate forward',
      () async {
    final mon = DateTime(2026, 5, 4);
    final box = HiveService.instance.workoutBox;

    // Seed an old plan (incomplete)
    for (var i = 0; i < 7; i++) {
      final d = mon.add(Duration(days: i));
      await box.put(WorkoutWriteService.scheduleKey(d), {
        'workout_name': 'OLD Plan Day ${i + 1}',
        'status': 'pending',
        'type': 'plan',
      });
    }

    final r = await WorkoutWriteService.instance.regenerateWeek(
      fromDate: mon,
      params: {
        'days_per_week': 6,
        'goal': 'build_muscle',
        'experience': 'intermediate',
        'equipment': 'basic_gym',
        'workouts': List.generate(
          7,
          (i) => {
            'workout_name': i == 6 ? 'Rest' : 'NEW Plan Day ${i + 1}',
            'status': i == 6 ? 'rest' : 'pending',
            'type': 'plan',
          },
        ),
      },
      source: WriteSource.editSheet,
    );
    expect(r.success, isTrue);

    for (var i = 0; i < 7; i++) {
      final d = mon.add(Duration(days: i));
      final entry =
          (box.get(WorkoutWriteService.scheduleKey(d)) as Map).cast<String, dynamic>();
      expect(entry['workout_name'],
          i == 6 ? 'Rest' : 'NEW Plan Day ${i + 1}');
      expect(entry['source'], 'edit_sheet');
    }
  });
}
```

- [ ] **Step 4: Implement `regenerateWeek`**

```dart
  Future<WriteResult> regenerateWeek({
    required DateTime fromDate,
    required Map<String, dynamic> params,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final workouts = (params['workouts'] as List?)?.cast<Map>() ?? const [];
    if (workouts.isEmpty) {
      return WriteResult.fail('params.workouts must be non-empty');
    }

    final dateStr = istDateStr(fromDate);
    final c = await _acquireLock('week_$dateStr');
    try {
      final box = HiveService.instance.workoutBox;

      for (var i = 0; i < workouts.length; i++) {
        final d = fromDate.add(Duration(days: i));
        final m = workouts[i].cast<String, dynamic>();
        await box.put(scheduleKey(d), {
          ...m,
          'date': istDateStr(d),
          'source': source.code,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        });
      }

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.regenerateWeek] inv: $e\n$st');
        }
      }

      return WriteResult.ok('week_$dateStr');
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.regenerateWeek] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock('week_$dateStr', c);
    }
  }
```

- [ ] **Step 5: Run + analyze**

```bash
flutter test test/workout_write_service/reschedule_day_test.dart \
            test/workout_write_service/regenerate_week_test.dart
flutter analyze lib/core/services/workout_write_service.dart
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/workout_write_service.dart test/workout_write_service/reschedule_day_test.dart test/workout_write_service/regenerate_week_test.dart
git commit -m "$(cat <<'EOF'
feat(write-service): rescheduleDay + regenerateWeek atomic writes

Plan A Task A-8.

rescheduleDay() — atomic two-day swap. Locks both dates in sorted
order (deadlock-free), swaps content while preserving date stamps,
fires sync. Used by AI coach `rescheduleDay` tool + Train tab manual
swap UI.

regenerateWeek() — bulk replacement of N schedule_<date> entries
starting from fromDate. Used by Edit Profile regen path + AI coach
`regeneratePlanBlock` tool.

Both methods stamp source + updated_at_ms on every entry for
telemetry + idempotent re-sync.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-9 — Implement `editLog` + `deleteLog`

**Files:**
- Modify: `lib/core/services/workout_write_service.dart`
- Create: `test/workout_write_service/edit_log_pr_rescan_test.dart`
- Create: `test/workout_write_service/delete_log_undo_test.dart`

- [ ] **Step 1: Write failing test for `editLog` PR rescan**

Write `test/workout_write_service/edit_log_pr_rescan_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('editLog: lowering an old PR reassigns is_pr to a later log', () async {
    final apr1 = DateTime(2026, 4, 1);
    final apr8 = DateTime(2026, 4, 8);
    final apr15 = DateTime(2026, 4, 15);

    // Seed three logs in chronological order
    await WorkoutWriteService.instance.logExercise(
      date: apr1,
      exerciseName: 'Bench Press',
      sets: [ExerciseSet(weightKg: 80, reps: 5, loggedAtMs: apr1.millisecondsSinceEpoch)],
      source: WriteSource.activeWorkout,
    );
    await WorkoutWriteService.instance.logExercise(
      date: apr8,
      exerciseName: 'Bench Press',
      sets: [ExerciseSet(weightKg: 100, reps: 5, loggedAtMs: apr8.millisecondsSinceEpoch)],
      source: WriteSource.activeWorkout,
    );
    await WorkoutWriteService.instance.logExercise(
      date: apr15,
      exerciseName: 'Bench Press',
      sets: [ExerciseSet(weightKg: 90, reps: 5, loggedAtMs: apr15.millisecondsSinceEpoch)],
      source: WriteSource.activeWorkout,
    );

    final box = HiveService.instance.workoutBox;
    final apr8Key = WorkoutWriteService.exlogKey(apr8, 'Bench Press');
    final apr8Before =
        (box.get(apr8Key) as Map).cast<String, dynamic>();
    expect(apr8Before['is_pr'], isTrue);

    // Edit the apr8 log down to 70 kg — apr1's 80 should now hold the PR
    final r = await WorkoutWriteService.instance.editLog(
      logKey: apr8Key,
      updates: {
        'sets': [
          {'weight_kg': 70, 'reps': 5, 'logged_at_ms': apr8.millisecondsSinceEpoch}
        ],
      },
      source: WriteSource.editSheet,
    );
    expect(r.success, isTrue);

    final apr1Key = WorkoutWriteService.exlogKey(apr1, 'Bench Press');
    final apr1After = (box.get(apr1Key) as Map).cast<String, dynamic>();
    final apr8After = (box.get(apr8Key) as Map).cast<String, dynamic>();
    expect(apr1After['is_pr'], isTrue,
        reason: 'apr1 80kg now has the PR (apr8 lowered to 70)');
    expect(apr8After['is_pr'], isFalse);
  });
}
```

- [ ] **Step 2: Implement `editLog`**

Add to `lib/core/services/workout_write_service.dart`:

```dart
  Future<WriteResult> editLog({
    required String logKey,
    required Map<String, dynamic> updates,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final box = HiveService.instance.workoutBox;
    final existing = box.get(logKey);
    if (existing is! Map) {
      return WriteResult.fail('logKey not found: $logKey');
    }

    final m = existing.cast<String, dynamic>();
    final exerciseName = m['exercise_name'] as String?;
    final dateStr = m['date'] as String?;
    if (exerciseName == null || dateStr == null) {
      return WriteResult.fail('log missing exercise_name or date');
    }

    final lockKey = '$dateStr::${exerciseName.toLowerCase().trim()}';
    final c = await _acquireLock(lockKey);
    try {
      // Apply updates
      final updated = <String, dynamic>{...m, ...updates};

      // If sets[] was updated, recompute aggregates
      if (updates.containsKey('sets')) {
        final newSets = (updates['sets'] as List).cast<Map>().map((e) {
          return ExerciseSet.fromMap(e);
        }).toList();
        updated['sets'] = newSets.map((s) => s.toMap()).toList();
        updated['set_number'] = newSets.length;
        updated['reps_completed'] =
            newSets.fold<int>(0, (a, s) => a + s.reps);
        updated['weight_kg'] = newSets.fold<double>(
            0, (a, s) => s.weightKg > a ? s.weightKg : a);
        updated['volume_kg'] = newSets.fold<double>(
            0.0, (a, s) => a + (s.weightKg * s.reps));
      }

      updated['source'] = source.code;
      updated['updated_at_ms'] = DateTime.now().millisecondsSinceEpoch;

      // Pre-write the updated entry so PR rescan sees the new weight
      await box.put(logKey, updated);

      // Chronologically rescan PR for ALL logs of this exercise
      _rescanAllPrsFor(box, exerciseName);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.editLog] inv: $e\n$st');
        }
      }

      return WriteResult.ok(logKey);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.editLog] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// Walk all logs of [exerciseName] in date-ascending order, mark
  /// is_pr=true for each weight that strictly exceeds the prior best.
  void _rescanAllPrsFor(Box box, String exerciseName) {
    final lower = exerciseName.toLowerCase().trim();
    final logs = <MapEntry<String, Map<String, dynamic>>>[];
    for (final k in box.keys) {
      final ks = k.toString();
      if (!ks.startsWith('exlog_')) continue;
      final v = box.get(k);
      if (v is! Map) continue;
      final m = v.cast<String, dynamic>();
      final n = (m['exercise_name'] as String?)?.toLowerCase().trim();
      if (n != lower) continue;
      logs.add(MapEntry(ks, m));
    }
    logs.sort((a, b) {
      final ad = a.value['date'] as String? ?? '';
      final bd = b.value['date'] as String? ?? '';
      return ad.compareTo(bd);
    });

    double best = 0.0;
    for (final entry in logs) {
      final w = (entry.value['weight_kg'] as num?)?.toDouble() ?? 0.0;
      final isPr = w > best;
      if (isPr) best = w;
      final mut = <String, dynamic>{...entry.value, 'is_pr': isPr};
      box.put(entry.key, mut);
    }
  }
```

- [ ] **Step 3: Write failing test for `deleteLog`**

Write `test/workout_write_service/delete_log_undo_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('deleteLog removes entry + drops from index', () async {
    final date = DateTime(2026, 5, 1);

    await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Bench Press',
      sets: [ExerciseSet(weightKg: 80, reps: 5, loggedAtMs: date.millisecondsSinceEpoch)],
      source: WriteSource.activeWorkout,
    );

    final box = HiveService.instance.workoutBox;
    final key = WorkoutWriteService.exlogKey(date, 'Bench Press');
    expect(box.containsKey(key), isTrue);

    final r = await WorkoutWriteService.instance.deleteLog(
      logKey: key,
      source: WriteSource.editSheet,
    );
    expect(r.success, isTrue);
    expect(box.containsKey(key), isFalse);

    // Index should no longer contain the key
    final indexKey = 'exercise_log_index_${WorkoutWriteService.istDateStr(date)}';
    final idx = (box.get(indexKey) as List?) ?? const [];
    expect(idx.contains(key), isFalse);
  });
}
```

- [ ] **Step 4: Implement `deleteLog`**

```dart
  Future<WriteResult> deleteLog({
    required String logKey,
    bool allowUndo = true,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    final box = HiveService.instance.workoutBox;
    final existing = box.get(logKey);
    if (existing is! Map) {
      return WriteResult.fail('logKey not found: $logKey');
    }
    final m = existing.cast<String, dynamic>();
    final exerciseName = m['exercise_name'] as String?;
    final dateStr = m['date'] as String?;
    if (exerciseName == null || dateStr == null) {
      return WriteResult.fail('log missing exercise_name or date');
    }

    final lockKey = '$dateStr::${exerciseName.toLowerCase().trim()}';
    final c = await _acquireLock(lockKey);
    try {
      // Stash for undo (1-hour TTL)
      if (allowUndo) {
        await box.put('undo_$logKey', {
          'data': jsonEncode(m),
          'expires_at_ms': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        });
      }

      await box.delete(logKey);

      // Drop from exercise_log_index_<date>
      final indexKey = 'exercise_log_index_$dateStr';
      final idx = (box.get(indexKey) as List?)?.cast<String>().toList() ?? [];
      idx.remove(logKey);
      if (idx.isEmpty) {
        await box.delete(indexKey);
      } else {
        await box.put(indexKey, idx);
      }

      // PR rescan (a deleted PR may promote a prior log)
      _rescanAllPrsFor(box, exerciseName);

      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());

      if (ref != null && onInvalidate != null) {
        try {
          onInvalidate!(ref);
        } catch (e, st) {
          debugPrint('[WorkoutWriteService.deleteLog] inv: $e\n$st');
        }
      }

      return WriteResult.ok(logKey);
    } catch (e, st) {
      debugPrint('[WorkoutWriteService.deleteLog] $e\n$st');
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }
```

- [ ] **Step 5: Run + analyze**

```bash
flutter test test/workout_write_service/edit_log_pr_rescan_test.dart \
            test/workout_write_service/delete_log_undo_test.dart
flutter analyze lib/core/services/workout_write_service.dart
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/workout_write_service.dart test/workout_write_service/edit_log_pr_rescan_test.dart test/workout_write_service/delete_log_undo_test.dart
git commit -m "$(cat <<'EOF'
feat(write-service): editLog + deleteLog with chronological PR rescan

Plan A Task A-9.

editLog() — atomic update of an existing exlog_<date>_<hash> entry.
If sets[] is in the updates map, recomputes set_number /
reps_completed / weight_kg=max / volume_kg=sum, then runs a full
chronological PR rescan across all logs of the same exercise.
Replaces EditWorkoutLogSheet's in-place rewrite.

deleteLog() — soft-delete with 1-hour undo TTL. Removes the entry,
drops it from exercise_log_index_<date>, runs PR rescan (a deleted
PR may promote a prior log).

_rescanAllPrsFor walks all logs of [exerciseName] in date-asc
order, marking is_pr=true on each weight that strictly exceeds the
running best. Replaces the per-write rescan in logExercise for
edit/delete paths where multiple logs may need flag flips.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-10 — Migrate Hive `exlog_*` key scheme on first launch

**Files:**
- Modify: `lib/features/train/repositories/workout_repository.dart` (or wherever the boot sequence calls Hive init)
- Create: `lib/core/services/exlog_key_migrator.dart`
- Create: `test/workout_write_service/migration_old_keys_test.dart`

- [ ] **Step 1: Locate the bootstrap path**

```bash
grep -rn "exercise_log_index_\|exlog_" lib/main.dart lib/core/services/hive_service.dart lib/features/auth/screens/splash_screen.dart 2>&1 | head -20
```

Identify where to call the migrator. Splash screen's `_runDeferredInit` is the most natural fit (already runs after Hive is open + before first read).

- [ ] **Step 2: Create the migrator**

Write `lib/core/services/exlog_key_migrator.dart`:

```dart
import 'package:flutter/foundation.dart';

import 'hive_service.dart';
import 'workout_write_service.dart';

/// One-shot migration from `exlog_<timestamp>_<hash>` (Test #5 and
/// earlier) to `exlog_<istDateStr>_<hash(name)>` (Plan A).
///
/// Hash function MUST match WorkoutWriteService.exlogKey — i.e.
/// `exerciseName.toLowerCase().trim().hashCode`.
///
/// Idempotent — guarded by configBox['exlog_key_migration_v6'].
class ExlogKeyMigrator {
  ExlogKeyMigrator._();
  static const _migrationKey = 'exlog_key_migration_v6';

  static Future<void> runIfNeeded() async {
    final config = HiveService.instance.configBox;
    if (config.get(_migrationKey) == true) return;

    final box = HiveService.instance.workoutBox;
    final oldKeys = box.keys
        .where((k) => k.toString().startsWith('exlog_'))
        .cast<String>()
        .toList();

    int rekeyed = 0;
    int merged = 0;

    // Group existing entries by their NEW key.
    final byNewKey = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final oldKey in oldKeys) {
      final v = box.get(oldKey);
      if (v is! Map) continue;
      final m = v.cast<String, dynamic>();
      final name = m['exercise_name'] as String?;
      final dateStr = m['date'] as String?;
      if (name == null || dateStr == null) continue;

      // Parse the IST date from the entry to feed exlogKey().
      DateTime? d;
      try {
        d = DateTime.parse(dateStr);
      } catch (_) {
        continue;
      }
      final newKey = WorkoutWriteService.exlogKey(d, name);
      byNewKey.putIfAbsent(newKey, () => []).add(MapEntry(oldKey, m));
    }

    // For each newKey, merge entries (concat sets[], pick latest
    // updated_at_ms for top-level fields).
    for (final entry in byNewKey.entries) {
      final newKey = entry.key;
      final group = entry.value;
      group.sort((a, b) {
        final at = (a.value['updated_at_ms'] as num?)?.toInt() ?? 0;
        final bt = (b.value['updated_at_ms'] as num?)?.toInt() ?? 0;
        return at.compareTo(bt);
      });

      // Concat sets[] in updated_at_ms order.
      final List<Map> mergedSets = [];
      for (final mEntry in group) {
        final sets = (mEntry.value['sets'] as List?)?.cast<Map>() ?? const [];
        if (sets.isNotEmpty) {
          mergedSets.addAll(sets);
        } else {
          // Legacy entry — synthesize a single ExerciseSet from
          // top-level weight_kg + reps_completed
          final w = (mEntry.value['weight_kg'] as num?)?.toDouble() ?? 0.0;
          final r = (mEntry.value['reps_completed'] as num?)?.toInt() ?? 0;
          mergedSets.add({
            'weight_kg': w,
            'reps': r,
            'logged_at_ms':
                (mEntry.value['updated_at_ms'] as num?)?.toInt() ??
                    DateTime.now().millisecondsSinceEpoch,
          });
        }
      }

      // Use latest entry as the base for top-level fields, override
      // sets[] + aggregates.
      final base = group.last.value;
      final maxWeight = mergedSets.fold<double>(
          0.0,
          (a, s) => ((s['weight_kg'] as num?)?.toDouble() ?? 0.0) > a
              ? (s['weight_kg'] as num).toDouble()
              : a);
      final totalReps = mergedSets.fold<int>(
          0, (a, s) => a + ((s['reps'] as num?)?.toInt() ?? 0));
      final volume = mergedSets.fold<double>(
          0.0,
          (a, s) =>
              a +
              (((s['weight_kg'] as num?)?.toDouble() ?? 0.0) *
                  ((s['reps'] as num?)?.toInt() ?? 0)));

      final merged = <String, dynamic>{
        ...base,
        'sets': mergedSets,
        'set_number': mergedSets.length,
        'weight_kg': maxWeight,
        'reps_completed': totalReps,
        'volume_kg': volume,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };

      // Delete old keys
      for (final mEntry in group) {
        if (mEntry.key != newKey) {
          await box.delete(mEntry.key);
          rekeyed++;
          if (group.length > 1) merged++;
        }
      }
      // Write under new key
      await box.put(newKey, merged);
    }

    // Rebuild exercise_log_index_<date> from current state
    final indexKeys = box.keys
        .where((k) => k.toString().startsWith('exercise_log_index_'))
        .toList();
    for (final ik in indexKeys) {
      await box.delete(ik);
    }
    for (final k in box.keys) {
      final ks = k.toString();
      if (!ks.startsWith('exlog_')) continue;
      final v = box.get(k);
      if (v is! Map) continue;
      final dateStr = (v as Map)['date'] as String?;
      if (dateStr == null) continue;
      final indexKey = 'exercise_log_index_$dateStr';
      final raw = box.get(indexKey);
      final list = (raw is List) ? raw.cast<String>().toList() : <String>[];
      if (!list.contains(ks)) list.add(ks);
      await box.put(indexKey, list);
    }

    debugPrint(
        '[ExlogKeyMigrator] rekeyed=$rekeyed merged=$merged total_after=${box.keys.where((k) => k.toString().startsWith('exlog_')).length}');
    await config.put(_migrationKey, true);
  }
}
```

- [ ] **Step 3: Wire into splash boot**

In `lib/features/auth/screens/splash_screen.dart`, find `_runDeferredInit` (or equivalent post-Hive init point) and add:

```dart
import 'package:icanbefitter/core/services/exlog_key_migrator.dart';

// inside _runDeferredInit, after HiveService init + (Plan-A-test-5)
// HiveUserSession.openForUser, BEFORE any code reads exlog_* keys:
await ExlogKeyMigrator.runIfNeeded();
```

Order matters: the migrator must run AFTER per-user box namespacing is open (so it reads the right user's data) but BEFORE any provider that lists exlog keys.

- [ ] **Step 4: Test**

Write `test/workout_write_service/migration_old_keys_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/exlog_key_migrator.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('two old timestamp-keyed exlogs same date+exercise → 1 merged entry',
      () async {
    final box = HiveService.instance.workoutBox;
    final config = HiveService.instance.configBox;

    // Seed two legacy entries with different timestamps but same
    // date + exercise — exactly the #16 bug.
    await box.put('exlog_1714560000000_${'Lat Pulldown'.hashCode}', {
      'exercise_name': 'Lat Pulldown',
      'date': '2026-05-01',
      'sets': [
        {'weight_kg': 40, 'reps': 10, 'logged_at_ms': 1714560000000},
        {'weight_kg': 60, 'reps': 10, 'logged_at_ms': 1714560090000},
      ],
      'set_number': 2,
      'reps_completed': 20,
      'weight_kg': 60,
      'volume_kg': 1000,
      'updated_at_ms': 1714560090000,
    });
    await box.put('exlog_1714560200000_${'Lat Pulldown'.hashCode}', {
      'exercise_name': 'Lat Pulldown',
      'date': '2026-05-01',
      'sets': [
        {'weight_kg': 80, 'reps': 10, 'logged_at_ms': 1714560200000},
        {'weight_kg': 100, 'reps': 7, 'logged_at_ms': 1714560290000},
      ],
      'set_number': 2,
      'reps_completed': 17,
      'weight_kg': 100,
      'volume_kg': 1500,
      'updated_at_ms': 1714560290000,
    });

    expect(
      box.keys.where((k) => k.toString().startsWith('exlog_')).length,
      2,
    );
    expect(config.get('exlog_key_migration_v6'), isNot(true));

    await ExlogKeyMigrator.runIfNeeded();

    // After migration: 1 entry under deterministic key with merged sets
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 1);
    final newKey = WorkoutWriteService.exlogKey(
        DateTime(2026, 5, 1), 'Lat Pulldown');
    expect(exlogKeys.first, newKey);

    final m = (box.get(newKey) as Map).cast<String, dynamic>();
    expect(m['set_number'], 4);
    expect(m['reps_completed'], 37);
    expect(m['weight_kg'], 100);
    expect((m['volume_kg'] as num).toInt(), 2500);

    // Idempotent
    await ExlogKeyMigrator.runIfNeeded();
    expect(
      box.keys.where((k) => k.toString().startsWith('exlog_')).length,
      1,
    );
  });
}
```

- [ ] **Step 5: Run + analyze**

```bash
flutter test test/workout_write_service/migration_old_keys_test.dart
flutter analyze lib/core/services/exlog_key_migrator.dart lib/features/auth/screens/splash_screen.dart
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/exlog_key_migrator.dart lib/features/auth/screens/splash_screen.dart test/workout_write_service/migration_old_keys_test.dart
git commit -m "$(cat <<'EOF'
feat(write-service): one-shot exlog key migration on splash boot

Plan A Task A-10. ExlogKeyMigrator.runIfNeeded() walks all
exlog_<timestamp>_<hash> keys, re-keys them to
exlog_<istDateStr>_<hash(name)>, and merges entries that collapse to
the same new key (concat sets[] in updated_at_ms order, recompute
aggregates).

Idempotent — guarded by configBox['exlog_key_migration_v6']. Wired
into splash_screen._runDeferredInit AFTER HiveUserSession opens (per
user) and BEFORE any provider that lists exlog keys.

Closes #16 retroactively for users with leftover legacy duplicates
from earlier APKs. Combined with Task A-11 onward (which routes all
new writes through WorkoutWriteService), the duplicate row class
becomes structurally impossible.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-11 — Migrate AI coach `logSet` tool dispatcher

**Files:**
- Modify: `lib/features/ai_coach/services/tool_dispatcher.dart`

- [ ] **Step 1: Read the existing logSet handler**

```bash
grep -nB 5 -A 60 "logSetWithPrRescan\|case 'logSet'\|case ToolName.logSet" lib/features/ai_coach/services/tool_dispatcher.dart | head -80
```

Note the function name + how it's called (per-set or batched).

- [ ] **Step 2: Replace the body**

The current pattern in `tool_dispatcher.dart` calls `WorkoutRepository.instance.logSetWithPrRescan(...)` once per set in a loop, producing N exlog_<ts>_<hash> rows. Replace with a SINGLE `WorkoutWriteService.logExercise(sets: [...all sets at once])` call.

Locate the dispatch handler for the `logSet` ToolIntent (or whatever the intent class is named in this codebase) and replace the body:

```dart
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

// inside the case handler:
Future<WriteResult> _dispatchLogSet(LogSetIntent intent, WidgetRef ref) async {
  final sets = intent.sets.map((s) {
    return ExerciseSet(
      weightKg: s.weightKg,
      reps: s.reps,
      durationSec: s.durationSec,
      loggedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }).toList();

  return WorkoutWriteService.instance.logExercise(
    date: intent.date ?? DateTime.now(),
    exerciseName: intent.exerciseName,
    sets: sets,
    notes: intent.notes,
    source: WriteSource.aiCoach,
    ref: ref,
  );
}
```

The exact intent shape lives in `lib/features/ai_coach/services/intents.dart` (or similar) — read it first to confirm field names. The principle: every set the AI coach claims for one exercise on one day → ONE call with `sets: [all of them]`.

- [ ] **Step 3: Find + remove the old per-set loop**

```bash
grep -nB 2 -A 20 "logSetWithPrRescan\|exlog_\${.*millisecondsSinceEpoch\|exlog_\${ts}" lib/features/ai_coach/services/ lib/features/ai_coach/services/conversational_log_handler.dart 2>&1 | head -40
```

Any remaining direct `workoutBox.put('exlog_${ts}_...', ...)` patterns in AI-coach paths must be removed. The old `WorkoutRepository.logSetWithPrRescan` may still be called from other places (Active Workout, conversational logger) — those migrate in Tasks A-12 + A-13.

- [ ] **Step 4: Analyze**

```bash
flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart
```

Expected: `No issues found!` (any unused imports of removed APIs must be cleaned up).

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_coach/services/tool_dispatcher.dart
git commit -m "$(cat <<'EOF'
feat(ai-coach): logSet routes through WorkoutWriteService (1 row not N)

Plan A Task A-11. The AI coach `logSet` tool dispatcher now batches
every set in one logExercise() call rather than looping
logSetWithPrRescan() per set.

Closes #16 — Gemini emits one ToolCall with sets=[40×10, 60×10,
80×10, 100×7]; dispatcher passes sets[] verbatim to
WorkoutWriteService.logExercise(); deterministic key produces ONE
exlog_<date>_<hash> row with sets[].length=4. Cloud
workout_log_exercises gets 1 upserted row; workout_log_sets gets 4
upserted rows.

The 60s per-set dedup still drops legitimate Gemini re-emissions
(retry on 5xx, etc.).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-12 — Migrate AI coach remaining write tools

**Files:**
- Modify: `lib/features/ai_coach/services/tool_dispatcher.dart`

- [ ] **Step 1: Migrate `markWorkoutComplete`**

Locate the markWorkoutComplete handler and replace:

```dart
Future<WriteResult> _dispatchMarkComplete(
    MarkCompleteIntent intent, WidgetRef ref) async {
  return WorkoutWriteService.instance.markCompleted(
    date: intent.date ?? DateTime.now(),
    workoutName: intent.workoutName,
    durationSec: intent.durationSec ?? 0,
    rpe: intent.rpe,
    ref: ref,
  );
}
```

- [ ] **Step 2: Migrate `swapExercise`** — atomic exercise replacement within a day's schedule

The existing AI coach `swapExercise` tool replaces a single exercise within `schedule_<date>.exercises[]`. Wrap as `upsertScheduled` with the modified entry:

```dart
Future<WriteResult> _dispatchSwapExercise(
    SwapExerciseIntent intent, WidgetRef ref) async {
  final box = HiveService.instance.workoutBox;
  final key = WorkoutWriteService.scheduleKey(intent.date ?? DateTime.now());
  final existing = (box.get(key) as Map?)?.cast<String, dynamic>();
  if (existing == null) {
    return WriteResult.fail('No schedule entry found for ${intent.date}');
  }

  final exercises =
      (existing['exercises'] as List?)?.cast<Map>().toList() ?? [];
  final idx = exercises.indexWhere((e) =>
      (e['exercise_name'] as String?)?.toLowerCase().trim() ==
      intent.fromExerciseName.toLowerCase().trim());
  if (idx < 0) {
    return WriteResult.fail(
        '${intent.fromExerciseName} not found in today\'s schedule');
  }
  exercises[idx] = {
    ...exercises[idx],
    'exercise_name': intent.toExerciseName,
    'logging_type': intent.toLoggingType ?? exercises[idx]['logging_type'],
  };

  return WorkoutWriteService.instance.upsertScheduled(
    date: intent.date ?? DateTime.now(),
    entry: {...existing, 'exercises': exercises},
    source: WriteSource.aiCoach,
    ref: ref,
  );
}
```

- [ ] **Step 3: Migrate `rescheduleWeek`**

```dart
Future<WriteResult> _dispatchRescheduleWeek(
    RescheduleWeekIntent intent, WidgetRef ref) async {
  return WorkoutWriteService.instance.regenerateWeek(
    fromDate: intent.fromDate,
    params: {
      'workouts': intent.workouts.map((w) => w.toMap()).toList(),
    },
    source: WriteSource.aiCoach,
    ref: ref,
  );
}
```

- [ ] **Step 4: Migrate `pausePlan`**

```dart
Future<WriteResult> _dispatchPausePlan(
    PausePlanIntent intent, WidgetRef ref) async {
  return WorkoutWriteService.instance.upsertScheduled(
    date: intent.date ?? DateTime.now(),
    entry: {
      'workout_name': 'Rest',
      'status': 'rest',
      'type': 'plan',
      'reason': intent.reason ?? 'user_paused',
    },
    source: WriteSource.aiCoach,
    ref: ref,
  );
}
```

- [ ] **Step 5: Migrate `regeneratePlanBlock`**

```dart
Future<WriteResult> _dispatchRegenerateBlock(
    RegenerateBlockIntent intent, WidgetRef ref) async {
  return WorkoutWriteService.instance.regenerateWeek(
    fromDate: intent.fromDate,
    params: intent.params,
    source: WriteSource.aiCoach,
    ref: ref,
  );
}
```

- [ ] **Step 6: Analyze + run AI coach test suite**

```bash
flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart
flutter test test/ai_coach/
```

Expected: `No issues found!` Any AI-coach tests that mocked the OLD repository call patterns may need to be updated to mock `WorkoutWriteService` instead — fix at the test file.

- [ ] **Step 7: Commit**

```bash
git add lib/features/ai_coach/services/tool_dispatcher.dart test/ai_coach/
git commit -m "$(cat <<'EOF'
feat(ai-coach): markComplete/swap/reschedule/pause/regen route through service

Plan A Task A-12. All 5 remaining AI coach WRITE tools now dispatch
through WorkoutWriteService:

- markWorkoutComplete -> markCompleted()
- swapExercise        -> upsertScheduled() (modify exercises[] in place)
- rescheduleWeek      -> regenerateWeek()
- pausePlan           -> upsertScheduled() with status='rest'
- regeneratePlanBlock -> regenerateWeek()

Every dispatch fires fire-and-forget syncWorkoutData + pushSnapshot
via the service, plus the canonical provider invalidation batch on
the supplied WidgetRef. AI-coach screen subscribers refresh
immediately (closes #12).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-13 — Migrate Active Workout screen Save button

**Files:**
- Modify: `lib/features/train/providers/train_provider.dart`

- [ ] **Step 1: Locate the Save handler**

```bash
grep -nB 5 -A 50 "completeWorkout\|finishWorkout\|saveActiveWorkout" lib/features/train/providers/train_provider.dart | head -80
```

The Active Workout flow currently writes one `exlog_<ts>_<hash>` per exercise via `WorkoutRepository.logSetWithPrRescan` per-set (or similar) and then writes `wlog_<date>` + flips schedule status.

- [ ] **Step 2: Replace with service calls**

Inside the Save handler (likely `completeWorkout` or `submitWorkoutDraft`), build per-exercise `List<ExerciseSet>` from the in-memory active-workout state and dispatch:

```dart
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

// inside completeWorkout:
final today = DateTime.now();
for (final exercise in activeExercises) {
  final sets = exercise.completedSets.map((s) {
    return ExerciseSet(
      weightKg: s.weightKg,
      reps: s.reps,
      durationSec: s.durationSec,
      loggedAtMs: s.loggedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }).toList();

  if (sets.isEmpty) continue; // skip exercises with no completed sets

  final result = await WorkoutWriteService.instance.logExercise(
    date: today,
    exerciseName: exercise.name,
    sets: sets,
    source: WriteSource.activeWorkout,
    // ref: pass through the ref this method has access to
  );
  if (!result.success) {
    debugPrint('[completeWorkout] log failed for ${exercise.name}: ${result.errorMessage}');
  }
}

await WorkoutWriteService.instance.markCompleted(
  date: today,
  workoutName: workoutName,
  durationSec: durationSec,
  rpe: rpe,
);
```

Remove the old direct `workoutBox.put('exlog_${ts}_...')` writes + the manual schedule status flip + the manual `pushSnapshot`/`syncWorkoutData` calls (the service does them internally).

- [ ] **Step 3: Analyze + run train tests**

```bash
flutter analyze lib/features/train/providers/train_provider.dart
flutter test test/train/
```

Expected: `No issues found!` Any test that asserted "Save writes 1 exlog_<ts>_<hash> per set" needs updating to "Save writes 1 exlog_<date>_<hash> per exercise with sets[]".

- [ ] **Step 4: Commit**

```bash
git add lib/features/train/providers/train_provider.dart test/train/
git commit -m "$(cat <<'EOF'
feat(train): Active Workout Save button routes through service

Plan A Task A-13. Active Workout flow's completeWorkout now:
1. Loops active exercises, builds List<ExerciseSet> per exercise
2. Calls WorkoutWriteService.logExercise(sets: [...]) once per exercise
3. Calls WorkoutWriteService.markCompleted() once for the wlog_<date>

Removes direct workoutBox.put('exlog_${ts}_...') writes and the
manual schedule flip + manual sync calls (the service fires both
fire-and-forget).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-14 — Migrate Edit Sheet "Save changes" + trash icon

**Files:**
- Modify: `lib/features/train/widgets/edit_workout_log_sheet.dart`

- [ ] **Step 1: Locate the Save handler**

```bash
grep -nB 5 -A 40 "_save\|_handleSave\|onSave\|saveChanges" lib/features/train/widgets/edit_workout_log_sheet.dart | head -60
```

- [ ] **Step 2: Replace the Save body with `editLog`**

Inside the save handler, replace the in-place rewrite logic with:

```dart
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

Future<void> _save() async {
  final updates = <String, dynamic>{
    'sets': _sets.map((s) => s.toMap()).toList(),
    if (_notes != null) 'notes': _notes,
  };

  final result = await WorkoutWriteService.instance.editLog(
    logKey: widget.logKey,
    updates: updates,
    source: WriteSource.editSheet,
    ref: ref,
  );
  if (!mounted) return;
  if (!result.success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Save failed: ${result.errorMessage}')),
    );
    return;
  }
  Navigator.of(context).pop(true);
}
```

- [ ] **Step 3: Replace the trash icon handler with `deleteLog`**

```dart
Future<void> _delete() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete this log?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ),
  );
  if (confirmed != true) return;

  final result = await WorkoutWriteService.instance.deleteLog(
    logKey: widget.logKey,
    source: WriteSource.editSheet,
    ref: ref,
  );
  if (!mounted) return;
  if (result.success) {
    Navigator.of(context).pop(true);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Delete failed: ${result.errorMessage}')),
    );
  }
}
```

- [ ] **Step 4: Analyze**

```bash
flutter analyze lib/features/train/widgets/edit_workout_log_sheet.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/train/widgets/edit_workout_log_sheet.dart
git commit -m "$(cat <<'EOF'
feat(train): Edit Sheet Save + trash route through service

Plan A Task A-14. EditWorkoutLogSheet._save -> editLog(), trash icon
-> deleteLog(). Service handles aggregate recompute + chronological
PR rescan + provider invalidation + sync. Replaces the old in-place
Hive map rewrite.

Closes #20 (Edit Sheet "Review sets" duplicate row) — once Task A-10
migration runs, the underlying duplicates collapse into a single
exlog_<date>_<hash> entry with merged sets[]; Edit Sheet displays
that single row.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-15 — Migrate plan generator (REPORT FOR DUTY) + edit profile regen

**Files:**
- Modify: `lib/core/services/workout_schedule_service.dart`
- Modify: `lib/features/profile/screens/edit_profile_screen.dart`

- [ ] **Step 1: Locate `generateAndScheduleFromDate`**

```bash
grep -nB 2 -A 30 "generateAndScheduleFromDate\|workoutBox\.put.*schedule_" lib/core/services/workout_schedule_service.dart | head -60
```

The function currently calls `workoutBox.put('schedule_$dateStr', entry)` directly inside a loop, with no sync trigger. This is exactly obs #3 — `scheduled_workouts` cloud table stays empty.

- [ ] **Step 2: Replace the direct put with `upsertScheduled`**

In `lib/core/services/workout_schedule_service.dart`, replace each `workoutBox.put('schedule_...', entry)` call site:

```dart
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

// inside generateAndScheduleFromDate, replace:
//   await workoutBox.put('schedule_$dateStr', entry);
// with:
await WorkoutWriteService.instance.upsertScheduled(
  date: d,
  entry: entry,
  source: WriteSource.planGenerator,
);
```

If the function is performance-sensitive (regenerating 84 days at once), prefer a single mutex acquisition + inline writes — but for v1 the per-day call is fine; the mutex is uncontested during plan generation.

- [ ] **Step 3: Migrate Edit Profile regen path**

```bash
grep -nB 2 -A 15 "generateAndScheduleFromDate\|regenerate.*[Pp]lan\|_regenerate" lib/features/profile/screens/edit_profile_screen.dart | head -40
```

The Edit Profile Save handler may call `generateAndScheduleFromDate` directly (which now routes through the service) — in that case no further code change needed; sync fires automatically.

If there's a separate regen path that bypasses `generateAndScheduleFromDate`, replace it with `WorkoutWriteService.instance.regenerateWeek(...)` for each week of the new plan.

- [ ] **Step 4: Analyze**

```bash
flutter analyze lib/core/services/workout_schedule_service.dart lib/features/profile/screens/edit_profile_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/workout_schedule_service.dart lib/features/profile/screens/edit_profile_screen.dart
git commit -m "$(cat <<'EOF'
feat(plan-gen): schedule writes route through WorkoutWriteService — closes #3

Plan A Task A-15. WorkoutScheduleService.generateAndScheduleFromDate
now writes each schedule_<date> via
WorkoutWriteService.upsertScheduled(source: planGenerator). The
service fires unawaited(syncWorkoutData) per write — the cloud
scheduled_workouts table actually populates after REPORT FOR DUTY
(was 0 rows before, per obs #3).

Edit Profile regen path inherits the fix transparently (it already
delegates to generateAndScheduleFromDate).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-16 — Migrate Schedule swap UI + Delete log UI

**Files:**
- Modify: `lib/core/services/workout_schedule_service.dart` (delegate `swapDay` to service)
- Modify: any Train tab UI that calls `swapDay` directly

- [ ] **Step 1: Locate `swapDay` callsites**

```bash
grep -rn "swapDay\|WorkoutScheduleService.*swap" lib/features/train/ lib/core/services/workout_schedule_service.dart 2>&1 | head -20
```

- [ ] **Step 2: Delegate `swapDay` to the service**

In `lib/core/services/workout_schedule_service.dart`:

```dart
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

Future<bool> swapDay(DateTime fromDate, DateTime toDate) async {
  final r = await WorkoutWriteService.instance.rescheduleDay(
    fromDate: fromDate,
    toDate: toDate,
    source: WriteSource.schedSwap,
  );
  return r.success;
}
```

Existing UI callsites that invoke `WorkoutScheduleService.instance.swapDay(...)` need no change — the surface contract is preserved while the implementation routes through the service.

- [ ] **Step 3: Locate non-Edit-Sheet delete callsites**

```bash
grep -rn "workoutBox\.delete.*exlog\|deleteExerciseLog" lib/features/train/ 2>&1 | head -10
```

Any direct `workoutBox.delete('exlog_...')` outside Edit Sheet (e.g. swipe-to-delete in a calendar day detail) routes to `WorkoutWriteService.deleteLog`:

```dart
final r = await WorkoutWriteService.instance.deleteLog(
  logKey: logKey,
  source: WriteSource.editSheet,
);
```

- [ ] **Step 4: Analyze + run tests**

```bash
flutter analyze lib/core/services/workout_schedule_service.dart
flutter test test/train/
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/workout_schedule_service.dart lib/features/train/
git commit -m "$(cat <<'EOF'
feat(train): swap UI + delete UI route through WorkoutWriteService

Plan A Task A-16. WorkoutScheduleService.swapDay() is a thin
delegate to WorkoutWriteService.rescheduleDay(source: schedSwap).
Direct exlog_* deletions outside Edit Sheet (e.g. calendar day
detail swipe) call WorkoutWriteService.deleteLog().

UI surface preserved; implementation now goes through the canonical
write path with mutex + sync + provider invalidation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-17 — Concurrency tests

**Files:**
- Create: `test/workout_write_service/log_exercise_concurrency_test.dart`

- [ ] **Step 1: Write concurrency test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('two simultaneous logExercise calls same exercise → mutex serializes',
      () async {
    final date = DateTime(2026, 5, 1);
    final base = date.millisecondsSinceEpoch;

    final f1 = WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Bench Press',
      sets: [
        ExerciseSet(weightKg: 60, reps: 8, loggedAtMs: base + 5000),
        ExerciseSet(weightKg: 70, reps: 6, loggedAtMs: base + 95000),
      ],
      source: WriteSource.activeWorkout,
    );
    final f2 = WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Bench Press',
      sets: [
        ExerciseSet(weightKg: 80, reps: 4, loggedAtMs: base + 185000),
        ExerciseSet(weightKg: 90, reps: 2, loggedAtMs: base + 275000),
      ],
      source: WriteSource.aiCoach,
    );
    final results = await Future.wait([f1, f2]);
    expect(results.every((r) => r.success), isTrue);

    final box = HiveService.instance.workoutBox;
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 1, reason: 'mutex serialized into one entry');

    final m = (box.get(exlogKeys.first) as Map).cast<String, dynamic>();
    final sets = (m['sets'] as List).cast<Map>();
    expect(sets.length, 4, reason: 'all 4 sets present');
    final weights = sets.map((s) => s['weight_kg']).toList();
    expect(weights, containsAll([60, 70, 80, 90]));
  });

  test('concurrent calls different exercises → both succeed independently',
      () async {
    final date = DateTime(2026, 5, 1);
    final base = date.millisecondsSinceEpoch;

    final f1 = WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Bench Press',
      sets: [ExerciseSet(weightKg: 60, reps: 8, loggedAtMs: base)],
      source: WriteSource.activeWorkout,
    );
    final f2 = WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Squat',
      sets: [ExerciseSet(weightKg: 100, reps: 5, loggedAtMs: base + 5000)],
      source: WriteSource.activeWorkout,
    );
    final results = await Future.wait([f1, f2]);
    expect(results.every((r) => r.success), isTrue);

    final box = HiveService.instance.workoutBox;
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 2, reason: 'separate exercises → separate entries');
  });
}
```

- [ ] **Step 2: Run + analyze**

```bash
flutter test test/workout_write_service/log_exercise_concurrency_test.dart
flutter analyze test/workout_write_service/log_exercise_concurrency_test.dart
```

Expected: green.

- [ ] **Step 3: Commit**

```bash
git add test/workout_write_service/log_exercise_concurrency_test.dart
git commit -m "$(cat <<'EOF'
test(write-service): concurrency contract — mutex serializes per-exercise

Plan A Task A-17.

Test 1: two simultaneous logExercise calls on the same (date,
exerciseName) → mutex serializes; final state has all sets merged
into ONE entry. Defends against race where Active Workout Save
fires concurrently with AI coach logSet.

Test 2: concurrent calls on different exercises run independently
(different lock keys) → no false serialization.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task A-18 — Full test suite + analyze

**Files:** none (verification only)

- [ ] **Step 1: Run analyze across `lib/`**

```bash
flutter analyze lib/
```

Expected: `No issues found!` Any pre-existing issues (not introduced by Plan A) get flagged in the trace doc rather than fixed here.

- [ ] **Step 2: Run the full test suite**

```bash
flutter test
```

Expected: all tests pass. Common pre-existing failures introduced by Plan A:

- Tests that mocked `WorkoutRepository.logSetWithPrRescan` directly → switch to mocking `WorkoutWriteService.logExercise`.
- Tests that asserted `exlog_<ts>_<hash>` key shape → update to `exlog_<dateStr>_<hash>`.
- Tests that read raw Hive entries with the old per-set summary shape (`set_number=1, reps=10, weight_kg=60`) → expect aggregated shape (`set_number=N, reps=sum, weight_kg=max`).

For each broken pre-existing test:
- If the test's INTENT survives the refactor (e.g. "PR rescan works"), update the test plumbing to use `WorkoutWriteService` and keep the assertions.
- If the test's INTENT is gone (e.g. "verify per-set Hive entry exists"), DELETE the test and document in the commit body.

- [ ] **Step 3: Capture broken test output**

```bash
flutter test 2>&1 | tee /tmp/wws-test-output.txt
grep -E "FAIL|FAILED|Error" /tmp/wws-test-output.txt | head -40
```

- [ ] **Step 4: Fix or document**

For test fixes, add to a single follow-up commit:

```bash
git add test/
git commit -m "$(cat <<'EOF'
test: adapt pre-existing tests to WorkoutWriteService routing (Plan A)

Tests that mocked the old per-set logSetWithPrRescan or asserted
exlog_<ts>_<hash> key format updated to the new
exlog_<dateStr>_<hash> + aggregated entry shape. Tests whose intent
no longer applies (per-set entries are an implementation detail
now) deleted with rationale in this commit body:

[list each deleted test + 1-line rationale]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If tests pass without modification, append a green-state note instead:

```bash
echo "" >> docs/superpowers/notes/2026-05-01-workout-write-service-verification.md
echo "## Plan A green-state confirmation" >> docs/superpowers/notes/2026-05-01-workout-write-service-verification.md
echo "" >> docs/superpowers/notes/2026-05-01-workout-write-service-verification.md
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — \`flutter analyze lib/\` clean; \`flutter test\` all pass. Plan A code-complete." >> docs/superpowers/notes/2026-05-01-workout-write-service-verification.md
```

(The verification doc itself is created in Task A-19; if you reach this step before A-19, defer the green-state append until then.)

---

## Task A-19 — Verification doc

**Files:**
- Create: `docs/superpowers/notes/2026-05-01-workout-write-service-verification.md`

- [ ] **Step 1: Write the verification doc**

Create `docs/superpowers/notes/2026-05-01-workout-write-service-verification.md`:

```markdown
# APK Test #6 Plan A — WorkoutWriteService verification

**Run after installing the APK Test #6 build for verification of Plan A.**

References:
- Plan: `docs/superpowers/plans/2026-05-01-apk-test-6-plan-A-workout-write-service.md`
- Spec: `docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md` §4 + §12

## Step 1 — Wipe the Supabase test account (if reusing)

```sql
DELETE FROM auth.users
WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com');
```

(per migration 039 cascade chain — cleans `workout_logs`,
`workout_log_exercises`, `workout_log_sets`, `scheduled_workouts`
along with everything else.)

## Step 2 — Uninstall + install +6 APK

1. Settings → Apps → AVYA → Uninstall.
2. Install `app-prod-release.apk` (versionCode +6).
3. Open the app — Welcome screen, no auto-restore.

## Step 3 — Walk through C1-C4

### C1 — Single row per exercise per workout (closes #16, #20)

1. Sign up fresh (e.g. `upendra.prasad@thinkingcode.com`).
2. Complete onboarding through REPORT FOR DUTY.
3. Open AI coach. Send: "lat pulldown 4 sets 40×10 60×10 80×10 100×7"
4. Tap APPLY on the confirmation card.
5. SQL verification:
   ```sql
   SELECT exercise_id, set_number, reps, weight_kg, volume_kg, is_pr
   FROM workout_log_exercises
   WHERE workout_log_id IN (
     SELECT id FROM workout_logs
     WHERE user_id = (SELECT id FROM auth.users WHERE email = 'upendra.prasad@thinkingcode.com')
     ORDER BY workout_date DESC LIMIT 1
   )
   ORDER BY exercise_id;
   ```
   **Expected:** ONE row for `Lat Pulldown`. `set_number=4`, `reps=37`, `weight_kg=100`, `volume_kg=2300`.

   **Failure mode (pre-Plan-A):** 4 rows, each with `set_number=1`.

### C2 — Per-set granularity intact

```sql
SELECT set_number, weight_kg, reps, logged_at_ms
FROM workout_log_sets
WHERE workout_log_id IN (
  SELECT id FROM workout_logs
  WHERE user_id = (SELECT id FROM auth.users WHERE email = 'upendra.prasad@thinkingcode.com')
  ORDER BY workout_date DESC LIMIT 1
)
ORDER BY set_number;
```

**Expected:** 4 rows. (1, 40, 10), (2, 60, 10), (3, 80, 10), (4, 100, 7).

### C3 — Plan generator syncs `scheduled_workouts` (closes #3)

After REPORT FOR DUTY (already done in C1):

```sql
SELECT scheduled_date, workout_name, status
FROM scheduled_workouts
WHERE user_id = (SELECT id FROM auth.users WHERE email = 'upendra.prasad@thinkingcode.com')
ORDER BY scheduled_date
LIMIT 14;
```

**Expected:** 14 rows (next 14 days), with rest days marked
`status='rest'` and active workout days as `status='pending'`.

**Failure mode (pre-Plan-A):** 0 rows (plan generated locally,
never synced).

### C4 — AI coach action reflects on Workout screen (closes #12)

1. From the AI-coach C1 step above (workout already logged).
2. Tap the Train tab.
3. Today's session card should show the green "DONE" chip + "View
   Card" button — NOT the pre-completion "START WORKOUT" CTA.

**Failure mode (pre-Plan-A):** Train tab still shows START WORKOUT
because `todayWorkoutProvider` was never invalidated.

## Step 4 — Optional regression checks

- **Active Workout flow still works:** start a workout from Train,
  log 3 sets manually, tap Save. Verify ONE exlog row in cloud.
- **Edit Sheet still works:** tap into a logged exercise, change a
  weight, Save. Verify cloud reflects new weight + PR rescan.
- **Concurrency:** open AI coach + Active Workout in different tabs
  (web build only — Android can't show two screens). Trigger a save
  in both for the same exercise. Verify ONE row with merged sets.

## Plan A green-state confirmation

[Appended automatically by Task A-18 step 4 when tests pass.]
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/notes/2026-05-01-workout-write-service-verification.md
git commit -m "$(cat <<'EOF'
docs(test-6): WorkoutWriteService on-device verification guide

Plan A Task A-19. Manual test guide for C1 (1-row-per-exercise),
C2 (per-set granularity), C3 (scheduled_workouts populates), C4
(provider invalidation visible in Train tab) plus regression checks
on Active Workout, Edit Sheet, and concurrent-source writes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review

- [ ] **Spec coverage table:**

| Spec §4 requirement | Task |
|---|---|
| §4.1 — Bug class extinction (#16, duplicate rows) | A-4 (60s dedup) + A-10 (legacy migration) + A-11 (AI coach routing) |
| §4.1 — Plan generator scheduled_workouts sync (#3) | A-7 (upsertScheduled) + A-15 (plan-gen migration) |
| §4.1 — Workout screen reflects AI actions (#12) | A-4/A-6/A-7/A-8/A-9 (provider invalidation in every method) + A-12 (AI coach passes ref) |
| §4.1 — Edit Sheet single row per exercise (#20) | A-10 (migration merges legacy dupes) + A-14 (Edit Sheet routes through editLog) |
| §4.2 — Service: 6 atomic methods | A-3 (skeleton), A-4/A-6/A-7/A-8/A-9 (implementations) |
| §4.3 — Mutex per (date, exerciseName) | A-3 (lock map) + A-4 (used in logExercise) + A-17 (concurrency test) |
| §4.3 — Per-set 60s dedup | A-2 (ExerciseSet.isDuplicateWithin) + A-4 (test + impl) |
| §4.3 — PR rescan chronological | A-4 (per-write rescan) + A-9 (full rescan on edit/delete) |
| §4.4 — 3-tier cloud sync | A-5 (`_projectExerciseLogThreeTier`) |
| §4.4 — workout_log_sets populated | A-5 (Tier 3 upserts) |
| §4.5 — All 7+ callsites migrated | A-11 (AI logSet), A-12 (4 more AI tools), A-13 (Active Workout), A-14 (Edit Sheet), A-15 (plan gen + edit profile), A-16 (swap UI + delete UI) |
| §4.5 — Hive key scheme migration | A-10 (ExlogKeyMigrator) |
| §4.6 — Tests | A-3/A-4/A-6/A-7/A-8/A-9/A-10/A-17 |
| §12 C1 (1 row, agg correct) | A-4 + A-11 + verification A-19 |
| §12 C2 (workout_log_sets has 4 rows) | A-5 + verification A-19 |
| §12 C3 (scheduled_workouts populates) | A-7 + A-15 + verification A-19 |
| §12 C4 (Train tab shows completion immediately) | A-6 (markCompleted) + canonical invalidation batch + verification A-19 |

- [ ] **Placeholder scan:** No "TBD", "TODO", "implement later", or empty function bodies in any code block. Every method body shipped is complete and runs against the types defined in Task A-2.

- [ ] **Type consistency check:**
  - `WorkoutWriteService` (singleton class) — Tasks A-3 through A-19 all use this exact name. ✅
  - `WriteResult { success, logKey, errorMessage }` — defined in A-2; used by every public method in A-4, A-6, A-7, A-8, A-9, A-11, A-12, A-13, A-14. ✅
  - `WriteSource` enum (`activeWorkout`, `aiCoach`, `editSheet`, `planGenerator`, `schedSwap`, `restore`) — defined in A-2; used by every public method via the `source: WriteSource.X` parameter. ✅
  - `ExerciseSet { weightKg, reps, durationSec }` — defined in A-2 (with the additional `loggedAtMs` field for dedup window comparison); used by `logExercise` callers in A-11, A-13, A-17 and in test fixtures throughout. ✅
  - Helper names `exlogKey`, `wlogKey`, `scheduleKey`, `istDateStr` — defined in A-3; used in A-4 onward. ✅

- [ ] **CLAUDE.md compliance:**
  - Hive-first writes, fire-and-forget cloud sync — every service method writes Hive synchronously then `unawaited(syncWorkoutData)` + `unawaited(pushSnapshot)`. ✅
  - No raw `Hive.box('workoutBox')` — all access via `HiveService.instance.workoutBox`. ✅
  - No client-supplied `featureActiveWorkoutMode` gate around the service (per Test #2 Q6 it's always free). ✅
  - Provider invalidation batch matches §15 source-of-truth list. ✅

## Out of scope for Plan A (deferred to Plans B/C/D/E/F/G)

- **Theme B** (AI coach intelligence — multi-intent dispatch, confirm gate, getNutritionHistory tool) → Plan B.
- **Theme C** (NutritionWriteService — same architectural pattern, different domain) → Plan C.
- **Theme D** (Profile restructure — rank pill replaces Edit Profile button at top) → Plan D.
- **Theme E** (Mission Brief copy + founder photo) → Plan E.
- **Theme F** (Onboarding edge cases — mid-week joiner phase backdating, plan screen days_per_week, weight graph seed, streak freeze chip dedup) → Plan F.
- **Theme G** (Rank ladder rebalance + Lt insertion + completion-rate gates) → Plan G.
- **Cascade undo for full workout sessions** — current `deleteLog` only soft-deletes single exlog entries. Multi-exercise undo deferred to Test #7.
- **`AiCoachRepository._getCurrentRankFromLadder` vs `RankService.getCurrentRank` consolidation** — two client read paths exist; not a Plan A concern.
