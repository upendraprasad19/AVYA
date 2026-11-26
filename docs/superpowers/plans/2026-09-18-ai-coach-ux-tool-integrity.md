# AI Coach UX & Tool-Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix AI-coach verbosity at the prompt layer, replace the Compass text-prefill palette with structured in-coach capture, and land every interference fix from the 2026-09-18 tool audit (paused-streak break, reschedule holes, silent un-pause, staleness gaps).

**Architecture:** Three workstreams on one branch. Server: a `chat` channel suffix in `captainPrompt()` (ai-proxy redeploy is founder-gated, done separately). Client state: streak/rate readers gain an "invisible status" set (`paused`/`moved`/`dropped`), rescheduleWeek stops raw-deleting source rows, overwrite tools gain paused guards. Client UI: Compass chips become launchers — two new capture sheets (log workout, swap) that build `ToolIntent`s through the EXISTING dispatcher/confirmation plumbing, dead chips removed, placeholder prefills replaced by a light form sheet.

**Tech Stack:** Flutter + Riverpod (manual providers), Hive (offline-first), Deno Edge Function (`ai-proxy`), `flutter_test` contract tests in `test/contracts/`.

**Spec:** `docs/superpowers/specs/2026-09-18-ai-coach-ux-tool-integrity-design.md`
**Worktree:** `.claude/worktrees/ai-coach-ux-tool-integrity` — ALL work happens here. Never `git add`/commit in the shared main folder.
**Commit discipline:** commits via `sh scripts/safe_commit.sh "<message>"` (stage files first — it does NOT stage). Bash on this machine: `& "C:\Program Files\Git\bin\bash.exe" -c "..."` from the worktree dir. Pre-commit gate loop takes ~100-200s — use a 600s timeout.

**Key APIs the executor needs (verified 2026-09-18):**
- `ToolDispatcher.instance.execute(Ref ref, ToolIntent intent)` → `Future<ToolExecutionResult>` — `tool_dispatcher.dart:88`. Runs the full tail (invalidations, sync, marker) on success.
- `ref.read(pendingToolIntentsProvider.notifier).addIntents([intent])` — `pending_tool_intents_provider.dart:25` — renders the confirmation card in the chat thread.
- `ToolIntent(id:, type:, payload:, confirmationClass:, previewSummary:, createdAt: DateTime.now())` — `models/tool_intent.dart:42`. `confirmationClass:` `trivial`/`reviewable`/`destructive` (from `ConfirmationClass` enum).
- Test harness: `setUpHiveForTests()` / `tearDownHiveForTests(tempDir)` from `test/helpers/hive_test_setup.dart`; `WorkoutRepository.instance.currentStreak()`; seed `HiveService.instance.workoutBox` / `userBox` directly (pattern proven in `test/contracts/streak_frozen_day_persists_protection_test.dart`).
- IST date keys: `istDateStr(date)` from `package:icanbefitter/core/utils/ist_date.dart`. Schedule key: `'schedule_${istDateStr(d)}'`.

---

### Task 1 (C1): Paused/moved/dropped days are invisible to streak + completion-rate

**Files:**
- Modify: `lib/features/train/repositories/workout_repository.dart` (walker at :350-355, rate at :440-446, new static helper near top of class)
- Modify: `docs/architecture/business-rules.md` (document the rule)
- Test: `test/contracts/streak_paused_day_not_missed_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/contracts/streak_paused_day_not_missed_test.dart` (mirror the harness of `streak_frozen_day_persists_protection_test.dart` exactly):

```dart
// C1 (ai-coach-ux-tool-integrity spec 2026-09-18) — founder rule: PAUSED =
// INVISIBLE. A past paused day must neither break the streak nor burn a
// freeze (writer: pauseRange, workout_schedule_write_service.dart:140; the
// old reader fell through to the missed arm: workout_repository.dart:384).
// Same for the 'moved'/'dropped' terminal rows Task 2 introduces.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  Future<void> seedAnchor(int daysBack) async {
    await HiveService.instance.userBox.put('profile', {
      'id': 'A',
      'onboarding_completed_at':
          nowWall().subtract(Duration(days: daysBack)).toIso8601String(),
    });
  }

  group('C1 — paused days are invisible to the streak', () {
    test('a paused past day neither breaks the streak nor burns a freeze',
        () async {
      await seedAnchor(20);
      final today = nowWall();
      DateTime daysAgo(int n) => today.subtract(Duration(days: n));
      String key(DateTime d) => istDateStr(d);

      await HiveService.instance.workoutBox
          .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(1))}',
          {'type': 'PUSH', 'status': 'paused', 'paused_via': 'ai_coach'});
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(2))}', {'type': 'PUSH', 'status': 'completed'});
      // ZERO freezes available — pre-fix the paused day broke the walk here.
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[],
      });

      expect(WorkoutRepository.instance.currentStreak(), 2,
          reason: 'paused day-1 is invisible: today(+1) day-1(skip) day-2(+1) = 2');
    });

    test('a moved/dropped terminal row is equally invisible', () async {
      await seedAnchor(20);
      final today = nowWall();
      DateTime daysAgo(int n) => today.subtract(Duration(days: n));
      String key(DateTime d) => istDateStr(d);

      await HiveService.instance.workoutBox
          .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox.put('schedule_${key(daysAgo(1))}',
          {'type': 'PUSH', 'status': 'moved', 'moved_to': istDateStr(today)});
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(2))}',
          {'type': 'PUSH', 'status': 'dropped', 'moved_via': 'ai_coach'});
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(3))}', {'type': 'PUSH', 'status': 'completed'});

      expect(WorkoutRepository.instance.currentStreak(), 2,
          reason: 'moved+dropped invisible: today(+1) day-1(skip) day-2(skip) day-3(+1)');
    });

    test('a genuinely missed day with no freeze still breaks (no over-protection)',
        () async {
      await seedAnchor(20);
      final today = nowWall();
      DateTime daysAgo(int n) => today.subtract(Duration(days: n));
      String key(DateTime d) => istDateStr(d);

      await HiveService.instance.workoutBox
          .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(1))}', {'type': 'PUSH', 'status': 'pending'});
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(2))}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[],
      });

      expect(WorkoutRepository.instance.currentStreak(), 1,
          reason: 'missed day-1 still breaks — the rule protects pauses, not skips');
    });
  });

  group('C1 — completionRateOverWindow excludes paused/moved/dropped', () {
    test('paused day is out of BOTH numerator and denominator', () async {
      await seedAnchor(20);
      final today = nowWall();
      DateTime daysAgo(int n) => today.subtract(Duration(days: n));
      String key(DateTime d) => istDateStr(d);

      await HiveService.instance.workoutBox
          .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(1))}',
          {'type': 'PUSH', 'status': 'paused', 'paused_via': 'ai_coach'});
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(2))}', {'type': 'PUSH', 'status': 'completed'});
      // Only today + day-2 count: 1 completed / 2 scheduled = 0.5.
      // Pre-fix: 1/3 ≈ 0.33 (paused counted as scheduled-not-completed).
      expect(WorkoutRepository.instance.completionRateOverWindow(1), 0.5);
    });
  });
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `flutter test test/contracts/streak_paused_day_not_missed_test.dart`
Expected: the paused-day tests FAIL (streak 0/1 instead of 2; rate ≈0.33 instead of 0.5). The missed-day-still-breaks test PASSES already (it pins existing behaviour).

- [ ] **Step 3: Implement**

In `lib/features/train/repositories/workout_repository.dart`, add inside the class (near `currentStreak`):

```dart
  /// C1/C2 (ai-coach-ux-tool-integrity, spec 2026-09-18) — schedule-row
  /// statuses INVISIBLE to streak + completion-rate math. `paused` is the
  /// user CHOOSING not to train (founder rule: never breaks, never burns a
  /// freeze). `moved`/`dropped` are terminal rows left by rescheduleWeek in
  /// place of the old raw delete — the day's workout lives elsewhere now, so
  /// the row must never fall through to the missed arm (the raw-delete HOLE
  /// class: an absent row broke the walk unconditionally, freeze-proof).
  static const Set<String> invisibleScheduleStatuses = {
    'paused',
    'moved',
    'dropped',
  };

  static bool isInvisibleToStreak(String? status) =>
      status != null && invisibleScheduleStatuses.contains(status);
```

In `_calculateStreak`, replace line 355:

```dart
      if (status == 'travel') continue;
```

with:

```dart
      if (status == 'travel') continue;
      // C1 — paused/moved/dropped are invisible (see isInvisibleToStreak).
      if (isInvisibleToStreak(status)) continue;
```

In `completionRateOverWindow`, replace line 443:

```dart
      if (status == 'rest') continue;
```

with:

```dart
      if (status == 'rest') continue;
      // C1 — same invisible set as the streak walk.
      if (isInvisibleToStreak(status)) continue;
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `flutter test test/contracts/streak_paused_day_not_missed_test.dart`
Expected: all PASS.

- [ ] **Step 5: MUTATE-PROOF the test (§4.4 r21)**

Neuter the fix: change `isInvisibleToStreak` to `=> false;`. Run the test file — expect the paused/moved/dropped tests to RED (≥3) while missed-day-still-breaks stays GREEN. Revert. Record in the Task 11 diagnose-doc: what was mutated, how many reddened.

- [ ] **Step 6: Document the business rule**

In `docs/architecture/business-rules.md`, under the streak section (grep for `HOME-04` / "streak"), add:

```markdown
### Paused days × streak (spec 2026-09-18, founder decision)

A scheduled day with `status='paused'` (coach pausePlan / future manual pause)
is INVISIBLE to the streak walk-back and to `completionRateOverWindow`: it
never breaks the streak, never consumes a freeze, and never counts against
rank completion-rate gates. Same for `moved`/`dropped` terminal rows left by
rescheduleWeek. Rationale: pausing is a legitimate choice, not a miss; the
alternative (scored as missed) guaranteed a dead streak after every vacation.
Writer: `WorkoutScheduleService.pauseRange`; readers: `WorkoutRepository
._calculateStreak` / `.completionRateOverWindow` via the shared
`isInvisibleToStreak` set.
```

- [ ] **Step 7: Commit**

```bash
git add lib/features/train/repositories/workout_repository.dart docs/architecture/business-rules.md test/contracts/streak_paused_day_not_missed_test.dart
sh scripts/safe_commit.sh "fix(streak): paused/moved/dropped days invisible to streak + completion-rate — C1, spec 2026-09-18"
```

---

### Task 2 (C2): rescheduleWeek — terminal rows instead of raw deletes, logs move with the day

**Files:**
- Modify: `lib/features/ai_coach/services/tool_dispatcher.dart:639-751` (`_executeRescheduleWeek`)
- Test: `test/contracts/reschedule_week_terminal_row_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/contracts/reschedule_week_terminal_row_test.dart`:

```dart
// C2 (spec 2026-09-18) — rescheduleWeek used to raw-delete the source
// schedule row (tool_dispatcher.dart:710/:719). A DELETED row is a HOLE in
// the streak walk-back (workout_repository.dart:343-347 breaks unconditionally
// on null) — freeze-proof, worse than a missed day. Fix: the source row
// becomes a TERMINAL 'moved'/'dropped' row (invisible per C1) instead of
// vanishing, and partial exlog_<fromDate>_* rows move to the destination
// date so the log stays attached to the workout.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/ai_coach/services/reschedule_week_planner.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await tearDownHiveForTests(tempDir);
  });

  test('move: source row becomes terminal moved, not a hole', () async {
    final today = nowWall();
    final fromDate = istDateStr(today);
    final toDate = istDateStr(today.add(const Duration(days: 1)));

    await HiveService.instance.workoutBox.put('schedule_$fromDate', {
      'date': fromDate,
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'PUSH A',
      'exercises': <Map<String, dynamic>>[
        {'name': 'Bench Press', 'sets': 4, 'reps': 8, 'weight': 60.0},
      ],
    });

    // Seed the planner cache the executor reads (same shape the diff preview writes).
    RescheduleWeekPlanner.instance.cacheForTest(intentIdForTest, [
      RescheduleMove(
        action: RescheduleAction.move,
        fromDate: fromDate,
        toDate: toDate,
        workoutName: 'PUSH A',
      ),
    ]);

    final intent = ToolIntent(
      id: intentIdForTest,
      type: 'reschedule_week',
      payload: const {'moves': 'cached'},
      confirmationClass: ConfirmationClass.destructive,
      previewSummary: 'Move PUSH A',
      createdAt: DateTime.now(),
    );

    final result = await ToolDispatcher.instance.execute(container.ref, intent);
    expect(result.success, isTrue, reason: result.errorMessage);

    final src = HiveService.instance.workoutBox.get('schedule_$fromDate') as Map?;
    final dst = HiveService.instance.workoutBox.get('schedule_$toDate') as Map?;
    expect(src, isNotNull, reason: 'source row must EXIST as a terminal row');
    expect(src!['status'], 'moved');
    expect(src['moved_to'], toDate);
    expect(dst!['status'], 'planned');
    expect(dst['date'], toDate);
  });
}

const intentIdForTest = 'c2-test-intent';
```

⚠ **Executor note (verify before writing):** `RescheduleWeekPlanner`'s cache API (`getCached(intent.id)`, cache entry type, `RescheduleMove` shape) is read from `lib/features/ai_coach/services/reschedule_week_planner.dart` — adapt the seed block above to the REAL planner API (it may be `cacheMoves(...)` with a different record class). The existing test `grep -rn "RescheduleWeekPlanner" test/` shows how other tests seed it — mirror that instead of inventing a `cacheForTest` if the planner has no test seam; if it has none, ADD one (a `@visibleForTesting` setter), exactly like `_registerToolForTesting` in the tools registry.

- [ ] **Step 2: Run — expect FAIL** (`flutter test test/contracts/reschedule_week_terminal_row_test.dart` — source row is null post-move today).

- [ ] **Step 3: Implement**

In `_executeRescheduleWeek` (`tool_dispatcher.dart`), replace the move-path delete (:707-711):

```dart
            // Only delete the old key if it isn't the same as the new one
            // (defensive — shouldn't happen but a no-op move would dupe).
            if (move.fromDate != move.toDate) {
              await box.delete('schedule_${move.fromDate}');
            }
```

with:

```dart
            if (move.fromDate != move.toDate) {
              // C2 (spec 2026-09-18): the source row becomes a TERMINAL
              // 'moved' row, never a raw delete. A deleted row was a HOLE in
              // the streak walk-back (workout_repository._calculateStreak
              // breaks unconditionally on a null row — freeze-proof) and
              // never reached cloud. 'moved' is in isInvisibleToStreak (C1),
              // and upsertScheduled fans the terminal status out to cloud.
              final fromDateTime =
                  _utcDateFromIstDateStr(move.fromDate!) ?? destDate;
              final movedOut = Map<String, dynamic>.from(from)
                ..['status'] = 'moved'
                ..['moved_to'] = move.toDate
                ..['moved_via'] = 'ai_coach'
                ..['moved_at'] = DateTime.now().toIso8601String();
              await WorkoutWriteService.instance.upsertScheduled(
                date: fromDateTime,
                entry: movedOut,
                source: WriteSource.aiCoach,
              );
              // Partial logs move WITH the day so the log stays attached to
              // the workout it belongs to (daily-total readers key on the
              // exlog date prefix). Cloud tombstones for the OLD exlog rows
              // remain an OI-174 residual (no cloud delete protocol exists).
              _moveExlogRows(fromDate: move.fromDate!, toDate: move.toDate!);
            }
```

Replace the drop-path delete (:718-719):

```dart
          case RescheduleAction.drop:
            await box.delete('schedule_${move.fromDate}');
```

with:

```dart
          case RescheduleAction.drop:
            // C2 — terminal 'dropped' row, same rationale as the move path.
            final dropRaw = box.get('schedule_${move.fromDate}');
            if (dropRaw is Map) {
              final droppedOut = Map<String, dynamic>.from(dropRaw)
                ..['status'] = 'dropped'
                ..['dropped_via'] = 'ai_coach'
                ..['dropped_at'] = DateTime.now().toIso8601String();
              final dropDate =
                  _utcDateFromIstDateStr(move.fromDate!) ?? DateTime.now();
              await WorkoutWriteService.instance.upsertScheduled(
                date: dropDate,
                entry: droppedOut,
                source: WriteSource.aiCoach,
              );
            }
```

Add the helper method (in the same class, near `_utcDateFromIstDateStr`):

```dart
  /// C2 — re-key partial `exlog_<fromDate>_*` rows to `exlog_<toDate>_*`.
  /// Keys are `exlog_${istDateStr(date)}_${exerciseName.hashCode...}` so the
  /// new key derives from the SAME exercise name (hash unchanged, date changed).
  /// Local-only delete of the old key; cloud residual tracked on OI-174.
  void _moveExlogRows({required String fromDate, required String toDate}) {
    final box = HiveService.instance.workoutBox;
    final prefix = 'exlog_$fromDate';
    final doomed = box.keys.where((k) => k is String && k.startsWith(prefix))
        .toList();
    for (final k in doomed) {
      final raw = box.get(k);
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final name = row['exercise_name']?.toString() ?? '';
      row['date'] = toDate;
      final newKey =
          'exlog_${toDate}_${name.hashCode.toUnsigned(32).toRadixString(16)}';
      box.put(newKey, row);
      box.delete(k);
    }
  }
```

- [ ] **Step 4: Run — expect PASS.** Also run the pre-existing reschedule tests: `flutter test test/contracts/ test/ai_coach/ --tags` is NOT a thing — run `grep -rln reschedule test/ | xargs flutter test` shape: `flutter test $(grep -rln "reschedule" test/ | tr '\n' ' ')`. All green.

- [ ] **Step 5: MUTATE-PROOF** — revert the move-path to `await box.delete('schedule_${move.fromDate}');` and run the test: expect RED on the terminal-row assertions. Revert. Log the mutation in the diagnose-doc.

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_coach/services/tool_dispatcher.dart test/contracts/reschedule_week_terminal_row_test.dart
sh scripts/safe_commit.sh "fix(reschedule): terminal moved/dropped rows replace raw source deletes; partial logs move with the day — C2"
```

---

### Task 3 (C3): paused-overwrite guards (hotel, scheduleTemplate, regeneratePlanBlock)

**Files:**
- Modify: `lib/features/ai_coach/services/tool_dispatcher.dart:774-777` (hotel guard), `:905-909` (regen guard)
- Modify: `lib/core/services/template_service.dart:95-111` (paused rejection) + its `AssignTemplateRejectionReason` enum + the dispatcher's rejection mapping in `_executeScheduleTemplate` (:1320)
- Test: extend existing per-tool tests (find via `grep -rln "generate_hotel_workout\|schedule_template\|regenerate_plan_block" test/`)

- [ ] **Step 1: Write the failing tests.** In each existing test file for the three tools, add one test: seed `schedule_<date>` with `{'status': 'paused', 'paused_via': 'ai_coach'}`, run the executor, assert the paused row is UNCHANGED (status still 'paused') and the tool reports it skipped. For `template_service`, the service-level test asserts `AssignTemplateRejected(reason: alreadyPaused)`. Mirror each file's existing seeding helpers exactly — do not invent new harnesses.

- [ ] **Step 2: Run — expect FAIL** (today all three overwrite the paused row to `planned`/custom content).

- [ ] **Step 3: Implement.**

Hotel (`tool_dispatcher.dart:774-777`), replace:

```dart
        final existing = box.get('schedule_$date');
        if (existing is Map && existing['status'] == 'completed') {
          continue;
        }
```

with:

```dart
        final existing = box.get('schedule_$date');
        if (existing is Map) {
          final st = existing['status']?.toString();
          // C3 — a paused row must survive a hotel overwrite (it previously
          // silently un-paused; symmetric with the completed guard).
          if (st == 'completed' || st == 'paused') {
            continue;
          }
        }
```

RegeneratePlanBlock (`tool_dispatcher.dart:905-909`) — identical replacement (keep the existing `// Concurrent-edit safety net.` comment, add the paused arm with a `// C3 —` line).

Template service (`template_service.dart`, after the `alreadyCompleted` branch at :104): add

```dart
      if (existingMap['status'] == 'paused') {
        // C3 — a paused day must not be silently overwritten by a template
        // assign (symmetric with completed; the displaced-row backup does not
        // apply here — the user PAUSED this day deliberately).
        unawaited(ErrorTelemetry.logEvent(
          'template_assign_rejected_paused',
          message: 'date=$dateKey templateId=$templateId',
        ));
        return const AssignTemplateRejected(
            AssignTemplateRejectionReason.alreadyPaused);
      }
```

Add `alreadyPaused` to `AssignTemplateRejectionReason` and map it in the dispatcher's `_executeScheduleTemplate` rejection handler to a user-facing failure message: `'That day is paused — lift the pause first or pick another day.'`

- [ ] **Step 4: Run all three tool-test files + `flutter test test/contracts/pause_range_routes_through_write_service_test.dart` — expect PASS.**

- [ ] **Step 5: MUTATE-PROOF** — remove the `|| st == 'paused'` arm from the hotel guard only; the new hotel test reddens. Revert. Log it.

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_coach/services/tool_dispatcher.dart lib/core/services/template_service.dart test/
sh scripts/safe_commit.sh "fix(tools): paused schedule rows survive hotel/scheduleTemplate/regeneratePlanBlock overwrites — C3"
```

---

### Task 4 (C4): provider-staleness fixes

**Files:**
- Modify: `lib/features/ai_coach/services/tool_dispatcher.dart` (`_invalidateNutritionProviders` :1559-1593)
- Test: extend `test/contracts/conversational_log_handler_uses_write_service_test.dart` OR create `test/contracts/coach_meal_log_invalidates_remaining_test.dart`

- [ ] **Step 1: Verify the custom-exercise claim first.** `grep -rn "customExercise\|custom_exercise" lib/features/train/providers/ lib/shared/ --include=*.dart | grep -i provider`. If NO provider exists (ExerciseSwapSheet queries Hive directly per `train_provider.dart:292` comment), record `verified_clean` for the custom-exercise half — no code. Only the counter provider needs the fix.

- [ ] **Step 2: Write the failing test.** Source-grep + wiring pin: the dispatcher's `_invalidateNutritionProviders` must name `aiTextLogRemainingProvider`. Add to the meal-log contract test:

```dart
  test('C4 — coach meal log refreshes aiTextLogRemainingProvider', () {
    final src = File('lib/features/ai_coach/services/tool_dispatcher.dart')
        .readAsStringSync();
    expect(src.contains('aiTextLogRemainingProvider'), isTrue,
        reason: '_invalidateNutritionProviders must invalidate '
            'aiTextLogRemainingProvider — the Nutrition "X remaining" read '
            'went stale after every coach meal log (manual path invalidates '
            'it at food_logger_section.dart:92)');
  });
```

(Plus, if the meal-log test harness executes the dispatcher, assert the provider re-read returns the decremented value behaviorally.)

- [ ] **Step 3: Run — expect FAIL. Then implement:** in `_invalidateNutritionProviders` (after the `macroTargetsProvider` block):

```dart
    // C4 — the coach meal path increments featureAiTextLogPro
    // (:1437-1440) but never refreshed the "X remaining" read; the manual
    // path invalidates it (food_logger_section.dart:92). Same reader, same
    // invalidation.
    try {
      ref.invalidate(aiTextLogRemainingProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate aiTextLogRemainingProvider failed: $e\n$st');
    }
```

- [ ] **Step 4: Run — PASS. Commit:**

```bash
git add lib/features/ai_coach/services/tool_dispatcher.dart test/
sh scripts/safe_commit.sh "fix(coach): coach meal log invalidates aiTextLogRemainingProvider — C4"
```

---

### Task 5 (C5): coach_memory mutex + pausePlan telemetry + doc-drift fix

**Files:**
- Modify: `lib/features/ai_coach/services/tool_dispatcher.dart` (`_appendInjuryToCoachMemory` :1528-1555, `_executePausePlan` catch :1055-1057)
- Modify: `lib/features/ai_coach/CLAUDE.md` (SoT row "per-date lock" wording)
- Test: extend `test/contracts/` injury/coach-memory coverage (grep `coach_memory` in test/) + a source pin for telemetry

- [ ] **Step 1: Failing test.** (a) Behavioral: fire two concurrent `_appendInjuryToCoachMemory`-equivalent writes (expose the method `@visibleForTesting` if private) via `Future.wait` with distinct parts; assert BOTH injuries survive. (b) Source pin: `_executePausePlan`'s `on PausePlanException` block calls `ErrorTelemetry.logEvent('tool_dispatch_pause_plan_failed', ...)`.

- [ ] **Step 2: Run — expect FAIL. Implement:**

Mutex (add a static field + rework the method):

```dart
  /// C5 — serializes coach_memory read-modify-writes. Two intent cards from
  /// one multi-intent turn can execute concurrently (each card guards only
  /// itself); without this lock one injury append was lost.
  static Future<void> _coachMemoryLock = Future<void>.value();

  Future<void> _appendInjuryToCoachMemory(
      String bodyPart, String severity) async {
    final prev = _coachMemoryLock;
    final completer = Completer<void>();
    _coachMemoryLock = completer.future;
    await prev;
    try {
      final box = HiveService.instance.coachBox;
      final raw = box.get('coach_memory');
      final mem = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      final existing = mem['injuries'];
      final injuries = existing is List
          ? existing
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      injuries.add({
        'part': bodyPart,
        'severity': severity,
        'since': DateTime.now().toIso8601String().split('T').first,
      });

      mem['injuries'] = injuries;
      await box.put('coach_memory', mem);
    } finally {
      completer.complete();
    }
  }
```

(Add `import 'dart:async';` if absent.)

Telemetry — in `_executePausePlan`:

```dart
    } on PausePlanException catch (e) {
      // C5 — pausePlan was the only write tool whose failure path skipped
      // ErrorTelemetry (reschedule :740, hotel :807, regen :1003 all log).
      unawaited(ErrorTelemetry.logEvent('tool_dispatch_pause_plan_failed',
          message: '${e.code}: ${e.message}'));
      return ToolExecutionResult.failure(_pausePlanErrorMessage(e));
    }
```

Doc drift — in `lib/features/ai_coach/CLAUDE.md` `coach_derived_completion` row, replace `Idempotent: per-date lock + under-lock status re-check.` with `Idempotent: the per-date lock lives inside markCompleted (workout_write_service.dart:424) — _maybeCompleteScheduledDay's own status re-check (:389) runs OUTSIDE it; the benign-race posture is documented at workout_write_service.dart:430-439. (Corrected 2026-09-18 — this cell previously claimed the re-check was under the lock.)`

- [ ] **Step 3: Run — PASS. MUTATE-PROOF:** delete the `await prev;` line → the concurrent test reddens. Revert. Commit:

```bash
git add lib/features/ai_coach/services/tool_dispatcher.dart lib/features/ai_coach/CLAUDE.md test/
sh scripts/safe_commit.sh "fix(coach): coach_memory RMW mutex + pausePlan failure telemetry + lock doc-drift — C5"
```

---

### Task 6 (C6/B4): Compass redesign — dead chips out, placeholder-free prefills, launcher plumbing

**Files:**
- Modify: `lib/features/ai_coach/widgets/compass_tools_sheet.dart` (the `_families` list + a new `action` field on `_Cmd`)
- Modify: `lib/features/ai_coach/screens/ai_coach/input_bar.dart:81-91` (onSelect routes actions)
- Create: `lib/features/ai_coach/widgets/log_workout_sheet.dart` (Task 7), `swap_exercise_coach_sheet.dart` (Task 8), `compass_form_sheet.dart` (light form for placeholder commands)
- Test: `test/widgets/compass_tools_sheet_test.dart` (create/extend — check for an existing one first: `grep -rln compass test/widgets/ test/`)

- [ ] **Step 1: Failing widget test** — pump `CompassToolsSheet` in a `MaterialApp`; assert:

```dart
      expect(find.text('Log a PR'), findsNothing,
          reason: 'C6/B4 — /PR advertised logPR, removed 2026-05-31 (ADR-0012 '
              'derive-only). Dead-end conversation by construction.');
      expect(find.text('Adjust calorie target'), findsNothing,
          reason: 'C6/B4 — /TARGET advertised adjustCaloricTarget, removed '
              '2026-05-31 (ADR-0012).');
      expect(find.textContaining('['), findsNothing,
          reason: 'B4 — no placeholder token may remain in any prefill; '
              'placeholder commands become launcher actions or light forms.');
```

- [ ] **Step 2: Run — FAIL. Implement (two halves):**

**(a) Rework `_Cmd` + `_families`.** Give `_Cmd` a nullable action enum:

```dart
enum CompassAction { logWorkout, swap, logMeal, injuryForm, scheduleForm, switchForm, historyForm, prefill }

class _Cmd {
  final String slash;
  final String desc;
  final String prefill;
  final CompassAction action;
  const _Cmd(this.slash, this.desc, this.prefill,
      {this.action = CompassAction.prefill});
}
```

New families (prefills carry NO `[...]` token — placeholder commands either launch a sheet or get a form):

```dart
const List<_Family> _families = [
  _Family('DRILL · WORKOUT', [
    _Cmd('/LOG', 'Log workout', '', action: CompassAction.logWorkout),
    _Cmd('/SWAP', 'Swap exercise', '', action: CompassAction.swap),
    _Cmd('/SHORTEN', 'Shorten today', 'Cut today\'s workout to 30 min'),
    _Cmd('/HOTEL', 'Travel workout',
        'I\'m travelling — give me a hotel-room workout'),
    _Cmd('/INJURY', 'Modify for injury', '',
        action: CompassAction.injuryForm),
  ]),
  _Family('GALLEY · NUTRITION', [
    _Cmd('/LOG MEAL', 'Log a meal', 'Log meal: ',
        action: CompassAction.logMeal),
    _Cmd('/SUGGEST', 'Meal idea', 'Suggest a 600 kcal high-protein meal'),
  ]),
  _Family('ORDERS · PLAN', [
    _Cmd('/SHUFFLE', 'Regenerate plan', 'Regenerate this week\'s plan'),
    _Cmd('/SCHEDULE', 'Reschedule day', '',
        action: CompassAction.scheduleForm),
    _Cmd('/PAUSE', 'Pause plan', 'Pause my plan for '),
    _Cmd('/SWITCH', 'Change goal', '', action: CompassAction.switchForm),
  ]),
  _Family('INTEL · PROGRESS', [
    _Cmd('/PROGRESS', 'Progress summary', 'Show my progress this month'),
    _Cmd('/HISTORY', 'Exercise history', '',
        action: CompassAction.historyForm),
  ]),
];
```

`_Family`/`_Cmd` are currently `const` with a non-const default enum — keep const by making `CompassAction` a plain enum (enums are const) — fine.

**(b) Route actions in `input_bar.dart`.** Change `onSelect` to receive the `_Cmd`-level decision: since `_Cmd` is private to the sheet, change the sheet's public callback to `onSelect(String prefill, CompassAction action)` — export `CompassAction` from the sheet file. In `input_bar.dart`:

```dart
onPressed: isSending
    ? null
    : () => CompassToolsSheet.show(
          context,
          onSelect: (prefill, action) {
            switch (action) {
              case CompassAction.logWorkout:
                showLogWorkoutSheet(context, ref);
                break;
              case CompassAction.swap:
                showCoachSwapSheet(context, ref);
                break;
              case CompassAction.logMeal:
              case CompassAction.prefill:
                _applyPrefill(prefill);
                break;
              case CompassAction.injuryForm:
              case CompassAction.scheduleForm:
              case CompassAction.switchForm:
              case CompassAction.historyForm:
                showCompassFormSheet(context, action,
                    onCompose: _applyPrefill);
                break;
            }
          },
        ),
```

Extract today's inline body into `void _applyPrefill(String prefill)` (controller text + selection + focus — the exact lines at :84-89).

The meal-log action (B3) deliberately keeps the conversational prefill `Log meal: ` — the AI-breakdown card is a RESULT renderer, not an input form; building a new input surface would duplicate `food_logger_section` for zero new capability. The canonical `logMealByText` writer is reached either way. (Spec B3 satisfied through the same writer; deviation note goes in the retrospective.)

- [ ] **Step 3: Run widget test — PASS. Commit** (sheets come next; the switch cases reference them, so land Tasks 7-8 code BEFORE this commit, or stub the two `show*Sheet` functions in this task and replace in 7-8 — prefer landing Task 6 together with Task 7+8 in one commit sequence: implement Tasks 7-8 first, then run this task's commit last across all three files).

---

### Task 7 (B1): Log-workout capture sheet

**Files:**
- Create: `lib/features/ai_coach/widgets/log_workout_sheet.dart`
- Test: `test/widgets/log_workout_sheet_test.dart`

- [ ] **Step 1: Failing widget test.** Pump the sheet inside a `ProviderScope` with Hive seeded (`schedule_<today>` with one exercise) using `setUpHiveForTests`; assert: today's exercise NAME renders; entering sets/reps/weight and tapping the confirm control creates a pending `log_set` intent (assert via `container.read(pendingToolIntentsProvider)` containing type `log_set` with the typed payload) and pops the sheet. Wardroom assertions: `AppColors` only (Gate `check_container_color_decoration.dart` blocks `Container(color:+decoration:)` — use `WardSet`/existing primitives or BoxDecoration only).

- [ ] **Step 2: Implement.** Shape (complete contract; follow `tool_confirm_sheet.dart` for sheet chrome + `AppTypography`/`AppSpacing`):

```dart
/// B1 (spec 2026-09-18) — structured capture for "Log my workout".
/// Reads today's scheduled exercises, prefills sets/reps/weight from the
/// plan prescription, and on confirm submits one `log_set` ToolIntent per
/// exercise through PendingToolIntentsNotifier — the SAME reviewable/confirm
/// plumbing the model's tool calls use, so completion derivation, provider
/// invalidation and sync all run through ToolDispatcher.execute unchanged.
/// Zero Gemini tokens: deterministic, works offline.
Future<void> showLogWorkoutSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const LogWorkoutSheet(),
  );
}
```

State logic:
- `initState`: read `HiveService.instance.workoutBox.get('schedule_${istDateStr(nowWall())}')`; parse `exercises[]` (each `{name, sets, reps, weight}` shape — confirm against a real row via a Hive inspection before finalizing parsing). Empty/absent row → empty state per §4.4 rule 13: "No workout scheduled today — log anything from the Train tab." + close button.
- Per exercise: `TextEditingController`s for sets/reps/weight prefilled from the row (weight fallback: last `exlog_<today-…>` for that name, else keep plan value).
- Confirm button (WardButton, disabled while any required field is empty): for each exercise with a non-empty weight+reps, `ref.read(pendingToolIntentsProvider.notifier).addIntents([ToolIntent(id: 'sheet_${DateTime.now().millisecondsSinceEpoch}_$i', type: 'log_set', payload: {'exerciseId': <resolved library id or name>, 'weightKg': w, 'reps': r, 'sets': s, 'date': istDateStr(nowWall())}, confirmationClass: ConfirmationClass.trivial, previewSummary: 'Log $name — $s×$r @ ${w}kg', createdAt: DateTime.now())])`; then `Navigator.pop`.
- **exerciseId resolution:** mirror `_resolveExerciseName`'s inverse — look the name up in `exerciseBox`/`customBox` to fetch the real id; if unresolvable, pass the name as id (the dispatcher already tolerates name-as-id: `tool_dispatcher.dart:302-303,337`).

- [ ] **Step 3: Run — PASS. Mutation:** make the confirm button submit payload with `weightKg: null` → test reddens (payload assertion). Revert. (Task 6's commit wraps 6+7+8.)

---

### Task 8 (B2): Coach swap sheet

**Files:**
- Create: `lib/features/ai_coach/widgets/swap_exercise_coach_sheet.dart`
- Test: `test/widgets/swap_exercise_coach_sheet_test.dart`

- [ ] **Step 1: Failing widget test** — same harness as Task 7. Assert: picker 1 lists today's exercises; tapping one advances to the substitute list; tapping a substitute + confirm adds ONE pending `swap_exercise` intent (`confirmationClass: ConfirmationClass.reviewable` — the existing reviewable preview card then renders the diff and confirm, exactly like the model path).

- [ ] **Step 2: Implement** (`showCoachSwapSheet(BuildContext context, WidgetRef ref)`):
- Picker 1: today's `schedule_<today> exercises[]` names (list tiles).
- Picker 2: `ExerciseRepository` search of the library filtered to the same primary equipment/movement family — read the guard source at `lib/core/services/swap_service.dart:253-273` and reuse its capability predicate (extract/import — do NOT copy it; if private, promote to a public static on SwapService with a behavioral pin).
- Confirm: `addIntents([ToolIntent(id: 'sheet_swap_${DateTime.now().millisecondsSinceEpoch}', type: 'swap_exercise', payload: {'exerciseId': <today's id>, 'newExerciseId': <chosen id>, 'reason': 'Chosen from Compass swap tool'}, confirmationClass: ConfirmationClass.reviewable, previewSummary: 'Swap $old for $new', createdAt: DateTime.now())])`, pop.
- Empty-day guard: same empty state as Task 7.

- [ ] **Step 3: Run — PASS. Mutation:** flip `confirmationClass` to `trivial` → test reddens. Revert.

- [ ] **Step 4: Land Tasks 6+7+8 together:**

```bash
git add lib/features/ai_coach/widgets/compass_tools_sheet.dart lib/features/ai_coach/widgets/log_workout_sheet.dart lib/features/ai_coach/widgets/swap_exercise_coach_sheet.dart lib/features/ai_coach/widgets/compass_form_sheet.dart lib/features/ai_coach/screens/ai_coach/input_bar.dart test/widgets/
sh scripts/safe_commit.sh "feat(coach): Compass becomes a launcher — structured log-workout + swap sheets, forms for placeholder commands, /PR + /TARGET removed — C6/B1/B2/B3/B4"
```

(`compass_form_sheet.dart`: one light form — 1-2 free-text fields + optional choice chips per `CompassAction` (injury: body-part chips knee/shoulder/back/wrist/other; schedule: day picker + target-date field; switch: `FitnessGoals.tokens` picker; history: exercise-name field) → composes the final string → `onCompose`. ~150 lines, same chrome as Task 7.)

---

### Task 9 (A): Captain chat-channel verbosity + anti-interrogation suffix

**Files:**
- Modify: `supabase/functions/_shared/captain_manual.ts:424-439` (`captainPrompt` chat suffix)
- Test: Deno — extend `supabase/functions/_shared/` test coverage only if a `captain_manual` test exists (`grep -rln captain_manual supabase/functions/`); otherwise `deno check` is the gate + one Deno test asserting the suffix contains the word-cap markers when channel==='chat'.

- [ ] **Step 1: Failing Deno test** (create `supabase/functions/_shared/captain_manual.test.ts` if none):

```typescript
import { assert, assertStringIncludes } from "jsr:@std/assert@1";
import { captainPrompt } from "./captain_manual.ts";

Deno.test("chat channel carries hard reply-length + anti-interrogation rules", () => {
  const p = captainPrompt("chat");
  assertStringIncludes(p, "100 words or fewer");
  assertStringIncludes(p, "60 words or fewer");
  assertStringIncludes(p, "NEVER ask the user for exercise IDs");
  assertStringIncludes(p, "ONE short question");
  // morning/proactive keep their own caps, unchanged:
  assertStringIncludes(captainPrompt("proactive"), "under 60 words");
});
```

- [ ] **Step 2: Run — FAIL** (`deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/captain_manual.test.ts`).

- [ ] **Step 3: Implement** — in `captainPrompt`, replace `chat: "",` with:

```typescript
    chat:
      "\n\nREPLY LENGTH (chat) — HARD RULES:\n" +
      "- Default reply: 100 words or fewer. Bullets over paragraphs. Numbers first, prose second.\n" +
      "- If the user's turn included a photo: 60 words or fewer, then at most ONE question.\n" +
      "- Never narrate what you are about to do. Do it, then report the result in one line.\n" +
      "ASKING FOR DATA — HARD RULES:\n" +
      "- NEVER ask the user for exercise IDs, slot IDs, or any identifier the snapshot already carries. Resolve names to IDs yourself from snapshot.today_workout.exercises[] / snapshot.custom_exercises.\n" +
      "- Ambiguous exercise name: offer 2-3 NAMED options in one short line.\n" +
      "- Required input genuinely missing: ask ONE short question. Never a checklist of demands (\"specify exercises, sets, reps and weights\" is banned).\n" +
      "- If the ask needs structured input (a full workout, a swap), say what you need in one line and point them to the Compass tools (/LOG, /SWAP) for three-tap capture.",
```

- [ ] **Step 4: Verify.** Run the Deno test (PASS) + `deno check --node-modules-dir=none supabase/functions/ai-proxy/index.ts` (clean — no `node_modules/` rewrite in `git status`).

- [ ] **Step 5: Commit:**

```bash
git add supabase/functions/_shared/captain_manual.ts supabase/functions/_shared/captain_manual.test.ts
sh scripts/safe_commit.sh "feat(ai-proxy): chat-channel reply-length caps + anti-interrogation rules in Captain manual — obs 1"
```

⚠ **Live deploy is a SEPARATE, founder-gated action** (§4.3): after merge + CI green, ask the founder, then host-shell deploy `ai-proxy` + smoke test via `/edge-function-deploy-rollback`.

---

### Task 10 (wrap-up): diagnose-docs, SoT registry, mutation ledger, retrospective

- [ ] **Step 1:** Diagnose-docs for C1 + C2 (bug-class fixes, `docs/diagnoses/2026-09-18-<slug>-<id>.md`) with `touched_layers_checked` covering tiers 1/2/3/12; validate: `dart run scripts/validate_diagnose_doc.dart <path>`. Each records its mutation evidence (what was mutated, red count).
- [ ] **Step 2:** SoT registry: update `streaks` concept readers (workout_repository) + `scheduled_workouts_mutations` (terminal statuses) if row-line citations changed.
- [ ] **Step 3:** Full local gates: `flutter analyze` (zero warnings) + targeted suite, then push via `sh scripts/safe_push.sh` — ≥account blast radius runs the full suite at pre-push. Run `scripts/blast_radius_from_diff.dart` to classify before pushing.
- [ ] **Step 4:** ×2 plan review (context-blind reviewers on the drafted diff) + B-pass BEFORE the `--no-ff` merge (§4.3/§4.12) — plan-review record `docs/plan-reviews/ai-coach-ux-tool-integrity.md`.
- [ ] **Step 5:** Merge via `sh scripts/safe_merge.sh ai-coach-ux-tool-integrity` from the main folder (integration-only), push, then founder-authorized `ai-proxy` deploy (Task 9 note).
- [ ] **Step 6:** §5 checklist walk + project retrospective `project_ai_coach_ux_tool_integrity.md` (memory dir) + retire the worktree after merge.

---

## Self-review notes (done at plan time)

- **Spec coverage:** A→Task 9; B1→7, B2→8, B3→6 (prefill retained — deviation documented), B4/C6→6; C1→1, C2→2, C3→3, C4→4, C5→5. Sequencing matches the spec (C-first, A, then B; Task 6 commit lands with 7-8 because the switch cases reference the sheets).
- **Placeholders:** the Task 2 executor-note about the planner's real cache API is a VERIFY step with a named fallback (add `@visibleForTesting` seam), not a TBD — the planner file and existing tests are named.
- **Type consistency:** `isInvisibleToStreak` used by both readers; statuses `moved`/`dropped` named identically in Tasks 1+2; `CompassAction` exported once from the sheet file and consumed in `input_bar.dart`.
