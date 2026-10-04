# APK Test #14 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. One fresh subagent per task. Two-stage review (spec compliance → code quality) after each task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make completed-workout state survive every cold-start / force-restart / logout-login / IST-midnight crossing; expose streak-freeze inventory honestly with `x/y` and a ladder refill.

**Spec:** `docs/superpowers/specs/2026-05-10-apk-test-14-design.md`

**Tech stack:** Flutter / Riverpod / Hive / Supabase Postgres. No new packages.

**Branch:** `feat/apk-test-14-batch` off `main` @ `27a6f09`. Final merge `--no-ff` to main.

**Discipline:** every bug fix gets a `docs/diagnoses/<id>.md` per CLAUDE.md §6.22. Every fix gets a contract or unit test that fails on `main` without the fix and passes with it (cite test path in commit message). Subagents must be dispatched with `docs/agent_brief_preamble.md` as prompt prefix.

---

## File structure

| Concept | Files touched |
|---|---|
| Bug A — stale-completion guard | `lib/core/services/workout_schedule_service.dart` (modify lines 530-568) + `test/contracts/stale_completion_guard_test.dart` (new) + `docs/diagnoses/2026-05-10-stale-guard-overeager.md` (new) |
| Bug B.1 — FK violation root-cause + self-healing push | `lib/core/services/sync_service.dart` (modify `_syncScheduledWorkouts` 3707-3755 + sequencing in callers 558-559, 597-598) + `test/contracts/scheduled_workouts_fk_resilience_test.dart` (new) + `test/contracts/sync_template_before_schedule_order_test.dart` (new) + `docs/diagnoses/2026-05-10-fk-violation-saturday.md` (new) |
| Bug B.2 — non-destructive restore | `lib/core/services/sync_service.dart` (modify `_restoreScheduledWorkouts` 3758-3814) + `test/contracts/restore_non_destructive_test.dart` (new) + `docs/diagnoses/2026-05-10-restore-overwrite.md` (new) |
| Bug B.3 — one-shot heal migrator | `lib/core/services/scheduled_workouts_resync_migrator.dart` (new) + `lib/main.dart` (wire in init sequence) + `test/safety/scheduled_workouts_resync_migrator_test.dart` (new) + `docs/diagnoses/2026-05-10-resync-migrator.md` (new) |
| Bug D.1 — ladder refill | `lib/features/home/providers/home_provider.dart` (modify `_refillIfNewWeek` 247-274) + `test/home/streak_freeze_refill_ladder_test.dart` (new) + `docs/diagnoses/2026-05-10-freeze-ladder.md` (new) |
| Bug D.2 — cloud default + restore fallback | `supabase/migrations/050_streak_freezes_default_one.sql` (new) + `lib/core/services/sync_service.dart` (modify lines 4117 + 4228) |
| Bug D.3 — pill UI | `lib/features/home/widgets/streak_freeze_pill.dart` (or wherever pill renders today — locate first) + `lib/features/home/providers/home_provider.dart` (add `streakFreezeMaxProvider`) + widget test |
| Discipline files | Update `CLAUDE.md` §15 "Restore-completeness sync" + `docs/sot_registry.yaml` (streak_freeze refill semantics + restore non-destructive rule) + `MEMORY.md` index |

---

## Task list

### Task 1 — Branch + scaffolding

**Files:** N/A (git only)

- [ ] **Step 1.1: Create branch off main**
  ```bash
  git checkout main
  git pull --ff-only
  git checkout -b feat/apk-test-14-batch
  ```
- [ ] **Step 1.2: Verify clean tree**
  ```bash
  git status --porcelain
  ```
  Expected: empty.
- [ ] **Step 1.3: Confirm parent SHA**
  ```bash
  git log --oneline -1
  ```
  Expected: `27a6f09 chore: record APK 1.0.0+18 …`

---

### Task 2 — Bug A: relax stale-completion guard

**Files:**
- Modify: `lib/core/services/workout_schedule_service.dart:530-568`
- Create: `test/contracts/stale_completion_guard_test.dart`
- Create: `docs/diagnoses/2026-05-10-stale-guard-overeager.md`

- [ ] **Step 2.1: Write the failing test first**

```dart
// test/contracts/stale_completion_guard_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
// ... hive bootstrap helper

void main() {
  setUp(() async {
    // open isolated workoutBox in temp dir
  });

  test('retroactive completion (next-IST-day completed_at) is NOT downgraded', () async {
    // schedule_date = 2026-05-05, completed_at = 2026-05-07T21:19:47Z (= May 8 IST)
    final box = Hive.box('workout');
    await box.put('schedule_2026-05-05', {
      'date': '2026-05-05',
      'status': 'completed',
      'completed_at': '2026-05-07T21:19:47Z',
      'type': 'workout',
    });
    final result = WorkoutScheduleService.instance
        .getScheduleForDate(DateTime(2026, 5, 5));
    expect(result?['status'], 'completed');
  });

  test('same-day completion is NOT downgraded', () async {
    final box = Hive.box('workout');
    await box.put('schedule_2026-05-04', {
      'date': '2026-05-04',
      'status': 'completed',
      'completed_at': '2026-05-04T15:00:00+05:30',
      'type': 'workout',
    });
    final result = WorkoutScheduleService.instance
        .getScheduleForDate(DateTime(2026, 5, 4));
    expect(result?['status'], 'completed');
  });

  test('impossible-past completion (completed_at BEFORE schedule_date) IS downgraded', () async {
    final box = Hive.box('workout');
    await box.put('schedule_2026-05-05', {
      'date': '2026-05-05',
      'status': 'completed',
      'completed_at': '2026-05-03T20:00:00+05:30',
      'type': 'workout',
    });
    final result = WorkoutScheduleService.instance
        .getScheduleForDate(DateTime(2026, 5, 5));
    expect(result?['status'], 'planned');
  });
}
```

- [ ] **Step 2.2: Run test, confirm fail**
  ```bash
  flutter test test/contracts/stale_completion_guard_test.dart
  ```
  Expected: first two FAIL (current guard downgrades them), third PASS by accident.

- [ ] **Step 2.3: Modify guard at workout_schedule_service.dart:543-562**

  Replace the `if (requestedDateStr != completedDateStr)` block with:

  ```dart
  // APK Test #14 / Bug A — guard fires only on impossible-past
  // completions (completed_at < schedule_date). Retroactive logging
  // and late-night IST-midnight crossings are legitimate; trusting
  // the cloud's status='completed' is correct in those cases.
  if (completedDateStr.compareTo(requestedDateStr) < 0) {
    final safe = Map<String, dynamic>.from(map);
    safe['status'] = 'planned';
    safe['completed_at'] = null;
    return safe;
  }
  ```

- [ ] **Step 2.4: Re-run test**
  ```bash
  flutter test test/contracts/stale_completion_guard_test.dart
  ```
  Expected: all 3 PASS.

- [ ] **Step 2.5: Run /diagnose-bug for documentation**

  Generate `docs/diagnoses/2026-05-10-stale-guard-overeager.md` with full YAML frontmatter per CLAUDE.md §6.22. Validate:
  ```bash
  dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-05-10-stale-guard-overeager.md
  ```

- [ ] **Step 2.6: Commit**
  ```bash
  git add lib/core/services/workout_schedule_service.dart \
          test/contracts/stale_completion_guard_test.dart \
          docs/diagnoses/2026-05-10-stale-guard-overeager.md
  git commit -m "$(cat <<'EOF'
fix(home): stale-completion guard fires only on impossible-past completions

Bug A — APK Test #14. Retroactive logs and late-night IST-midnight
crossings (cloud completed_at lands on next IST date vs schedule_date)
were being downgraded to 'planned' on every read of getScheduleForDate.
Founder's May 5/6/7 ticks vanished after restore for this reason.

closes-diagnose: 2026-05-10-stale-guard-overeager
test: test/contracts/stale_completion_guard_test.dart

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
  ```

---

### Task 3 — Bug B.1: investigate FK violation + self-healing push

**Files:**
- Modify: `lib/core/services/sync_service.dart` (`_syncScheduledWorkouts` 3707-3755 + sequencing at lines 558-559 and 597-598)
- Create: `test/contracts/scheduled_workouts_fk_resilience_test.dart`
- Create: `test/contracts/sync_template_before_schedule_order_test.dart`
- Create: `docs/diagnoses/2026-05-10-fk-violation-saturday.md`

- [ ] **Step 3.1: Investigation subagent**

  Dispatch a subagent (with `docs/agent_brief_preamble.md` prefix) to:
  1. Read `_syncWorkoutTemplates` (3437-3585) and `_syncScheduledWorkouts` (3707-3755) end-to-end.
  2. Confirm both use the same `_deterministicId` derivation.
  3. Trace what happens when `_syncScheduledWorkouts` runs without `_syncWorkoutTemplates` having completed for the referenced template.
  4. Identify the actual call sites that combine the two and whether order is enforced.
  5. Report: which of the 3 candidate root causes is the live one (or if it's a 4th).

  Subagent output must pass:
  ```bash
  dart run scripts/validate_agent_diagnose_stanza.dart <agent-output>
  ```

- [ ] **Step 3.2: Write failing tests based on subagent finding**

  Two tests:

  **`scheduled_workouts_fk_resilience_test.dart`** — mock Supabase client, simulate first upsert returning 23503 → assert sync retries `_syncWorkoutTemplates` then re-pushes the schedule. If second upsert still 23503, assert the third upsert sends `template_id: null` and the row writes successfully with `status='completed'`.

  **`sync_template_before_schedule_order_test.dart`** — instrument call order; assert `_syncWorkoutTemplates` always completes before `_syncScheduledWorkouts` starts in any combined push path.

- [ ] **Step 3.3: Confirm tests fail on main**
  ```bash
  flutter test test/contracts/scheduled_workouts_fk_resilience_test.dart \
               test/contracts/sync_template_before_schedule_order_test.dart
  ```
  Expected: both FAIL.

- [ ] **Step 3.4: Implement fix per subagent finding**

  Likely shape (subagent confirms specifics):
  - Wrap the `await _supabase.client.from('scheduled_workouts').upsert(...)` in a try/catch that distinguishes 23503 from other errors.
  - On 23503, call `await _syncWorkoutTemplates(userId)`, then re-attempt the same upsert.
  - On second 23503, fall back to `template_id: null` and re-upsert; log a `client_errors` row with `op_type='scheduled_workouts_template_orphaned'` for telemetry.
  - In the combined push paths (lines 558-559, 597-598), restructure to await `_syncWorkoutTemplates` before launching `_syncScheduledWorkouts` (drop `Future.wait` if it currently parallels them).

- [ ] **Step 3.5: Run tests**
  ```bash
  flutter test test/contracts/scheduled_workouts_fk_resilience_test.dart \
               test/contracts/sync_template_before_schedule_order_test.dart
  ```
  Expected: both PASS.

- [ ] **Step 3.6: Generate diagnose-doc + commit**
  ```bash
  git add lib/core/services/sync_service.dart \
          test/contracts/scheduled_workouts_fk_resilience_test.dart \
          test/contracts/sync_template_before_schedule_order_test.dart \
          docs/diagnoses/2026-05-10-fk-violation-saturday.md
  git commit -m "$(cat <<'EOF'
fix(sync): self-healing scheduled_workouts push survives template FK violations

Bug B.1 — APK Test #14. _syncScheduledWorkouts emitted 10 PostgrestException
23503 (FK violation) on the founder's account because the v5-UUID
template_id sent for Saturday's schedule didn't exist in cloud
workout_templates yet. Push now: (a) sequences template sync before
schedule sync, (b) on 23503 retries after re-running template sync,
(c) on persistent 23503 falls back to template_id: null so status='completed'
still reaches cloud.

closes-diagnose: 2026-05-10-fk-violation-saturday
test: test/contracts/scheduled_workouts_fk_resilience_test.dart
test: test/contracts/sync_template_before_schedule_order_test.dart

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
  ```

---

### Task 4 — Bug B.2: non-destructive restore

**Files:**
- Modify: `lib/core/services/sync_service.dart:3758-3814` (`_restoreScheduledWorkouts`)
- Create: `test/contracts/restore_non_destructive_test.dart`
- Create: `docs/diagnoses/2026-05-10-restore-overwrite.md`

- [ ] **Step 4.1: Write the failing test**

```dart
// test/contracts/restore_non_destructive_test.dart
test('local completed + cloud planned → keep local', () async {
  final box = Hive.box('workout');
  await box.put('schedule_2026-05-09', {
    'date': '2026-05-09',
    'status': 'completed',
    'completed_at': '2026-05-09T18:00:00+05:30',
    'type': 'workout',
  });

  // Simulate cloud row coming back as planned (sync push had failed)
  final cloudRow = {
    'scheduled_date': '2026-05-09',
    'status': 'planned',
    'completed_at': null,
    'template_id': null,
  };
  await invokeRestoreMerge(cloudRow);

  final after = box.get('schedule_2026-05-09') as Map;
  expect(after['status'], 'completed');
  expect(after['completed_at'], '2026-05-09T18:00:00+05:30');
});

test('local planned + cloud completed → take cloud (status + completed_at)', () async {
  // existing behavior — must not regress
});

test('local completed older + cloud completed newer → take cloud', () async {
  // both completed but timestamps differ — newest wins
});
```

- [ ] **Step 4.2: Confirm fail**
  ```bash
  flutter test test/contracts/restore_non_destructive_test.dart
  ```
  Expected: first FAIL, others PASS.

- [ ] **Step 4.3: Modify merge in `_restoreScheduledWorkouts`**

  Replace the `cloudStatus`/`cloudCompletedAt` overlay block with timestamp-aware merge:

  ```dart
  final localStatus = existingMap['status'] as String?;
  final localCompletedAt = existingMap['completed_at'] as String?;

  String? mergedStatus = cloudStatus;
  String? mergedCompletedAt = cloudCompletedAt;

  if (localStatus == 'completed' &&
      cloudStatus == 'planned' &&
      localCompletedAt != null) {
    // Cloud is stale (push must have failed). Keep local; queue re-push.
    mergedStatus = 'completed';
    mergedCompletedAt = localCompletedAt;
    _markPendingRePush(date);
  } else if (localStatus == 'completed' && cloudStatus == 'completed') {
    // Both completed; newest wins.
    if (localCompletedAt != null && cloudCompletedAt != null) {
      mergedCompletedAt = (localCompletedAt.compareTo(cloudCompletedAt) > 0)
          ? localCompletedAt : cloudCompletedAt;
    }
  }
  // else: existing rule (cloud authoritative) unchanged.
  ```

- [ ] **Step 4.4: Re-run + commit (same shape as Task 2.6)**

---

### Task 5 — Bug B.3: one-shot resync migrator

**Files:**
- Create: `lib/core/services/scheduled_workouts_resync_migrator.dart`
- Modify: `lib/main.dart` (wire migrator into init sequence after Hive open + auth)
- Create: `test/safety/scheduled_workouts_resync_migrator_test.dart`
- Create: `docs/diagnoses/2026-05-10-resync-migrator.md`

- [ ] **Step 5.1: Write the failing test**

```dart
// test/safety/scheduled_workouts_resync_migrator_test.dart
test('runs once, gated by userBox flag', () async {
  // seed userBox with no flag
  // call ScheduledWorkoutsResyncMigrator.runIfNeeded()
  // expect _syncScheduledWorkouts called for every local 'completed' row
  // expect userBox['apk_test_14_completion_resync_done'] == true

  // call again — expect no further sync calls
});
```

- [ ] **Step 5.2: Confirm fail**

- [ ] **Step 5.3: Implement migrator**

```dart
class ScheduledWorkoutsResyncMigrator {
  static const _flagKey = 'apk_test_14_completion_resync_done';

  static Future<void> runIfNeeded() async {
    final userBox = HiveService.instance.userBox;
    if (userBox.get(_flagKey) == true) return;

    final workoutBox = HiveService.instance.workoutBox;
    final candidates = <String>[];
    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('schedule_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      if (raw['status'] == 'completed' && raw['completed_at'] != null) {
        candidates.add(key);
      }
    }

    if (candidates.isNotEmpty) {
      // Reuse the standard fan-out — Bug B.1's hardened push handles failures.
      await SyncService.instance.syncWorkoutData();
    }

    await userBox.put(_flagKey, true);
  }
}
```

- [ ] **Step 5.4: Wire into main.dart init**

  After `HiveService.init()` + `auth_provider` ensures user, but before navigating to home:
  ```dart
  unawaited(ScheduledWorkoutsResyncMigrator.runIfNeeded());
  ```

- [ ] **Step 5.5: Run test + commit**

---

### Task 6 — Bug D.1: ladder refill

**Files:**
- Modify: `lib/features/home/providers/home_provider.dart:247-274` (`_refillIfNewWeek`)
- Create: `test/home/streak_freeze_refill_ladder_test.dart`
- Create: `docs/diagnoses/2026-05-10-freeze-ladder.md`

- [ ] **Step 6.1: Write the 6 failing tests** (per spec D.1)

- [ ] **Step 6.2: Confirm fail**

- [ ] **Step 6.3: Modify `_refillIfNewWeek`**

  Replace the reset:
  ```dart
  // OLD:
  // 'streak_freezes_available': maxFreezes,

  // NEW:
  final currentAvailable = (progress['streak_freezes_available'] as int?) ?? 0;
  final newAvailable = (currentAvailable + 1).clamp(0, maxFreezes);
  // ...
  'streak_freezes_available': newAvailable,
  ```

  Keep `streak_freeze_used_dates` reset (existing). Keep `streak_freezes_last_refill` write.

- [ ] **Step 6.4: Re-run + commit**

---

### Task 7 — Bug D.2: cloud default + restore fallback

**Files:**
- Create: `supabase/migrations/050_streak_freezes_default_one.sql`
- Modify: `lib/core/services/sync_service.dart:4117, 4228` (defaults 2 → 1)

- [ ] **Step 7.1: Write migration**

```sql
-- 050_streak_freezes_default_one.sql
-- APK Test #14 — cloud default for streak_freezes_available was 2 (legacy
-- conservative middle-ground). Per founder direction, free baseline is 1
-- and PRO clients overwrite to 3 within seconds of first launch. Change
-- default to 1 so a fresh user_progress row matches free-tier baseline.

ALTER TABLE public.user_progress
  ALTER COLUMN streak_freezes_available SET DEFAULT 1;

COMMENT ON COLUMN public.user_progress.streak_freezes_available IS
  'Streak freezes available. Default 1 (free baseline). PRO clients '
  'overwrite to 3 on first refill via _refillIfNewWeek.';
```

- [ ] **Step 7.2: Apply migration via MCP**

  ```
  mcp__ba7b5e8e..__apply_migration project_id=dedsavbjuwgarrhphgnl
    name=050_streak_freezes_default_one
    query=<contents above>
  ```

- [ ] **Step 7.3: Modify restore fallbacks**

  `sync_service.dart:4117` and `:4228`:
  ```dart
  // OLD: final available = (p['streak_freezes_available'] as int?) ?? 2;
  // NEW: final available = (p['streak_freezes_available'] as int?) ?? 1;
  ```

- [ ] **Step 7.4: Update CLAUDE.md §15 "Restore-completeness sync"** — note the ladder semantics + new default.

- [ ] **Step 7.5: Commit**

---

### Task 8 — Bug D.3: pill UI `❄ x/y`

**Files:**
- Locate the streak pill widget first (`grep -r "streak_pill\|StreakPill\|❄"`)
- Modify the located widget + provider
- Add widget test

- [ ] **Step 8.1: Locate widget**
- [ ] **Step 8.2: Add `streakFreezeMaxProvider` in `home_provider.dart`**

  ```dart
  final streakFreezeMaxProvider = Provider<int>((ref) {
    return SubscriptionService.instance.isPro() ? 3 : 1;
  });
  ```

- [ ] **Step 8.3: Update pill widget to read both providers + render `❄ $available/$max`**

- [ ] **Step 8.4: Widget test** — render with PRO + 2 available → expect text `2/3`. Render with free + 1 available → expect `1/1`.

- [ ] **Step 8.5: Commit**

---

### Task 9 — Documentation, MEMORY index, SoT registry

**Files:**
- Modify: `CLAUDE.md` §15 sub-sections (already in Task 7.4) + new §11.1 entry under "Common Bugs to Avoid" mapping the stale-guard, FK self-heal, and ladder semantics
- Modify: `docs/sot_registry.yaml` — add ladder semantics, non-destructive-restore rule, FK-self-heal rule
- Modify: `memory/MEMORY.md` — add `project_apk_test_14_batch.md` entry under "## Project"
- Create: `memory/project_apk_test_14_batch.md`

- [ ] **Step 9.1: Update CLAUDE.md**
- [ ] **Step 9.2: Update sot_registry.yaml**
- [ ] **Step 9.3: Write retrospective project memory file**
- [ ] **Step 9.4: Commit**

---

### Task 10 — Test suite + analyzer + merge

- [ ] **Step 10.1: Run full unit suite**
  ```bash
  flutter test
  ```
  Expected: 1140+ pass / 0 fail / 11 skip.

- [ ] **Step 10.2: Run analyzer**
  ```bash
  flutter analyze --no-fatal-infos
  ```
  Expected: zero errors / zero warnings on changed files.

- [ ] **Step 10.3: Merge to main**
  ```bash
  git checkout main
  git merge --no-ff feat/apk-test-14-batch -m "Merge APK Test #14 batch — calendar/sync/freeze hardening"
  ```

- [ ] **Step 10.4: Run /build-apk from main** — all 14 gates must pass.

---

## Self-review checklist (controller, before dispatching first subagent)

- [ ] Spec coverage: Bug A, B.1, B.2, B.3, C, D.1, D.2, D.3 all have a task. C is no-op (already shipped).
- [ ] Each task names exact file + line ranges.
- [ ] Each fix has a regression test + diagnose doc.
- [ ] No "TBD" / "TODO" / "fill in later".
- [ ] Migration 050 has matching restore-fallback updates in client.
- [ ] Pill UI task locates the widget first (don't hardcode a path I haven't grepped).
- [ ] /build-apk runs from main with clean tree (per `feedback_main_is_source_of_truth.md`).
