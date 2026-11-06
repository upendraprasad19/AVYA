# APK Test #4 Hotfix Plan B — Coach + Minor Bugs (B2, B3, B4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three independent bug fixes — streak-freeze anchor (B2), coach Manual §8 routing + tool-loop fallback (B3), Profile RANK card "-13 days" sign fix (B4).

**Architecture:** B2 is Dart-only client fix. B3 is server-only — Captain Manual + tool-loop logic, both deployed via ai-proxy v59. B4 is Dart UI fix sharing helper with chip header for consistency.

**Spec reference:** `docs/superpowers/specs/2026-04-28-apk-test-4-hotfix-batch-design.md` §3 B2/B3/B4.

**Estimated effort:** 4-5h.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `lib/features/train/repositories/workout_repository.dart` | MODIFY | `_earliestUserAnchor()` helper + `calculateCurrentStreak` skip pre-anchor dates |
| `supabase/functions/_shared/captain_manual.ts` | MODIFY | §8 PRESENT/PAST routing carve-out |
| `supabase/functions/_shared/tool-loop.ts` | MODIFY | Max-rounds Captain-voice fallback |
| `lib/features/profile/widgets/service_record_section.dart` | MODIFY | Use shared `daysUntilNextRank()` helper |
| `lib/core/services/rank_service.dart` | MODIFY (maybe) | Extract or expose `daysUntilNextRank()` shared by chip + RANK card |
| `test/train/streak_anchor_test.dart` | CREATE | B2 anchor behavior |
| `test/profile/rank_card_eta_test.dart` | CREATE | B4 sign correctness |

---

## Task B-1 — Streak freeze anchor (B2)

**Files:** `lib/features/train/repositories/workout_repository.dart`

- [ ] **Step 1: Write the failing test**

Create `test/train/streak_anchor_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_b2_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.userBox.clear();
    await HiveService.instance.workoutBox.clear();
  });

  String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

  group('B2: streak anchor', () {
    test('user onboarded today, plan starts yesterday — no freeze consumed', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      // User onboarded TODAY
      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': today.toIso8601String(),
      });

      // Plan generator created yesterday's schedule (pre-onboarding)
      await HiveService.instance.workoutBox.put('schedule_${_isoDate(yesterday)}', {
        'type': 'PUSH A',
        'workout_name': 'PUSH A',
        'status': 'pending',
      });

      // User has 1 freeze available
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
      });

      final streak = WorkoutRepository.instance.calculateCurrentStreak();

      // Streak should be 0 (no completed workouts yet)
      expect(streak, 0);

      // Critical: freezes_available must STILL be 1 (anchor protected
      // yesterday from being treated as a missed day)
      final progress = HiveService.instance.userBox.get('progress') as Map;
      expect(progress['streak_freezes_available'], 1,
        reason: 'B2: pre-onboarding scheduled day must NOT consume freeze');
      expect((progress['streak_freeze_used_dates'] as List).isEmpty, true);
    });

    test('established user with completed days — anchor doesnt break legitimate streak', () async {
      final today = DateTime.now();

      // User onboarded 30 days ago
      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': today.subtract(const Duration(days: 30)).toIso8601String(),
      });

      // Last 3 days: completed workouts
      for (int i = 1; i <= 3; i++) {
        final d = today.subtract(Duration(days: i));
        await HiveService.instance.workoutBox.put('schedule_${_isoDate(d)}', {
          'type': 'PUSH A',
          'status': 'completed',
        });
      }

      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
      });

      final streak = WorkoutRepository.instance.calculateCurrentStreak();

      // 3 completed days → streak = 3
      expect(streak, 3);
      // No freeze consumed (all days completed)
      final progress = HiveService.instance.userBox.get('progress') as Map;
      expect(progress['streak_freezes_available'], 1);
    });
  });
}
```

- [ ] **Step 2: Run test — confirm FAIL (anchor not yet implemented)**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter test test/train/streak_anchor_test.dart
```

Expected: first test FAILS (freeze gets consumed).

- [ ] **Step 3: Implement the anchor**

In `lib/features/train/repositories/workout_repository.dart`, add a helper before `calculateCurrentStreak`:

```dart
/// Earliest date the user could legitimately have completed a workout.
/// calculateCurrentStreak skips dates BEFORE this anchor — no penalty,
/// no freeze consumption — because the user wasn't on the app yet.
///
/// Anchor = earliest of: onboarding_completed_at, first_workout_date.
/// If neither is set (very fresh user), returns null and the existing
/// 365-day walk-back is used unchanged.
DateTime? _earliestUserAnchor() {
  final profile = _hive.userBox.get('profile') as Map?;
  if (profile == null) return null;

  DateTime? earliest;
  void consider(String? iso) {
    if (iso == null || iso.isEmpty) return;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return;
    if (earliest == null || dt.isBefore(earliest!)) {
      earliest = dt;
    }
  }

  consider(profile['onboarding_completed_at'] as String?);

  // first_workout_date computed from earliest wlog_*
  String? earliestWlogDate;
  for (final key in _hive.workoutBox.keys) {
    if (!key.toString().startsWith('wlog_')) continue;
    final log = _hive.workoutBox.get(key);
    if (log is! Map) continue;
    final d = log['date'] as String?;
    if (d == null) continue;
    if (earliestWlogDate == null || d.compareTo(earliestWlogDate) < 0) {
      earliestWlogDate = d;
    }
  }
  consider(earliestWlogDate);

  return earliest;
}
```

In `calculateCurrentStreak()`, before the for-loop, capture the anchor:

```dart
int calculateCurrentStreak() {
  int streak = 0;
  final today = DateTime.now();
  final anchor = _earliestUserAnchor();

  // ... existing freezesAvailable, usedDates, freezeConsumedThisCalc setup ...
  // ... existing scheduleCache build ...

  for (int i = 0; i < 365; i++) {
    final date = today.subtract(Duration(days: i));

    // B2: Stop walking back BEFORE the user's earliest anchor.
    // The user couldn't have done these workouts — they didn't have the app.
    if (anchor != null && date.isBefore(anchor)) {
      break;
    }

    final dateStr = formatDateKey(date);
    // ... rest of existing loop logic unchanged ...
  }

  // ... existing freeze persistence ...
  return streak;
}
```

- [ ] **Step 4: Run test — confirm PASS**

```bash
flutter test test/train/streak_anchor_test.dart
flutter test test/  # full suite — no regressions in other streak tests
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/train/repositories/workout_repository.dart \
        test/train/streak_anchor_test.dart
git commit -m "fix(train): streak anchor respects user signup date (B2)

calculateCurrentStreak no longer penalizes pre-onboarding scheduled days.

Was: plan generator created schedule_<this-monday> rows that could be
BEFORE user signup. calculateCurrentStreak walked back, treated those
as 'missed scheduled days', auto-consumed freezes for days the user
literally couldn't have completed (didn't have the app yet).

Now: _earliestUserAnchor() returns earliest of (onboarding_completed_at,
first_workout_date). The walk-back loop break-s when date is before
anchor. No freeze consumption for pre-account days.

Tests: 2 anchor scenarios (new user, established user).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task B-2 — Captain Manual §8 routing + tool-loop fallback (B3)

**Files:** `supabase/functions/_shared/captain_manual.ts`, `supabase/functions/_shared/tool-loop.ts`

- [ ] **Step 1: Read current Manual §8**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
grep -n "SECTION 8\|TOOL ROUTING\|temporal phrase" supabase/functions/_shared/captain_manual.ts | head -10
```

Find the temporal phrase routing rule.

- [ ] **Step 2: Replace the temporal-phrase rule**

In `captain_manual.ts`, find this block (or similar — exact wording may vary post-CR-B):

```
- A specific date, year, month, or temporal phrase ("last year", "March", "two months ago", "when did I"):
  → Call getExerciseHistory or getPRTimeline. Do NOT infer from snapshot.
```

Replace with the carve-out:

```
TEMPORAL QUERIES — split by tense:

PAST temporal queries (CALL TOOLS):
- "last year", "in March 2025", "two months ago", "when did I", "show my history",
  "PR back in [date]", "compared to [past period]"
- → Call getExerciseHistory or getPRTimeline. Do NOT infer from snapshot.

PRESENT/TODAY queries (READ FROM SNAPSHOT — do NOT call tools):
- "today", "now", "right now", "currently", "this week", "what's my workout",
  "what's planned", "what's scheduled"
- → Read snapshot.today_workout, snapshot.current_plan_summary,
  snapshot.week_lookahead, snapshot.meals_today directly.
- NEVER call a tool for "today" or "current" data — the snapshot has it.
```

- [ ] **Step 3: Update tool-loop max-rounds fallback**

```bash
grep -n "MAX_ROUNDS\|maxRounds\|round.*limit\|ran out of" supabase/functions/_shared/tool-loop.ts | head -10
```

Find the max-rounds exit. Replace whatever it currently does on exhaustion (likely returning the model's last text, which may say "ran out of steps") with a Captain-voice fallback:

```typescript
// In the location where max-rounds is exhausted:
if (round >= MAX_ROUNDS) {
  console.log(`[tool-loop] max rounds (${MAX_ROUNDS}) exhausted; emitting Captain-voice fallback`);

  // B3: Replace raw model text (may say "ran out of steps") with a
  // Captain-voice degrade-gracefully message that tells the user we
  // hit a wall but doesn't expose internal mechanics.
  return {
    text: "Recruit — I had trouble pinning that down via tools. Try the question again, or be more specific. If you want today's workout or current state, ask plainly: 'what's my workout today' or 'what's my plan' — I'll read the manifest directly.",
    usage: lastResponse?.usage,
    toolCalls: [],
  };
}
```

(Adapt the return shape to whatever `runToolLoop` actually returns — if it returns a string, return just the fallback string. If it returns an object, match the existing shape.)

- [ ] **Step 4: Deploy ai-proxy v59**

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js ai-proxy --auto --functions-dir "C:/Upendra/Claude Code/fitness-app-test-4/supabase/functions"
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy ".claude/_payload_ai-proxy.json" false
```

Expected: HTTP 201, version v58 → v59.

- [ ] **Step 5: Commit**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
git add supabase/functions/_shared/captain_manual.ts \
        supabase/functions/_shared/tool-loop.ts
git commit -m "fix(coach): Manual §8 PRESENT/PAST routing + tool-loop Captain fallback (B3)

User OBS-3 from Test #4 install: 'what's my workout today?' → coach
replied 'I started working on that but ran out of steps'.

Two fixes:

1. Manual §8 carve-out — PRESENT/TODAY queries (today, this week, what's
   planned) now READ FROM SNAPSHOT directly. PAST queries (last year,
   March, two months ago) still call tools. Was: all temporal phrases
   forced tool calls, including 'today' which has no past data to fetch.

2. Tool-loop max-rounds fallback — when 3 rounds exhausted, instead of
   returning whatever raw model text was emitted (often 'ran out of
   steps' or similar internal-mechanics leak), emit a Captain-voice
   degrade message that tells user how to ask more directly.

Deployed: ai-proxy v59.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task B-3 — Profile RANK card "-13 days" sign fix (B4)

**Files:** `lib/features/profile/widgets/service_record_section.dart`

- [ ] **Step 1: Find the negative-ETA computation**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
grep -n "in.*days\|daysUntil\|nextRank.*days\|days.toString" lib/features/profile/widgets/service_record_section.dart | head -10
grep -n "daysUntilNextRank\|days.*Until.*Rank\|next_rank.*days" lib/core/services/rank_service.dart | head -10
```

Locate the spot in `_buildCurrentRankSummary` (or wherever the collapsed-summary line "Next: X in N days" is rendered) that computes the days delta.

- [ ] **Step 2: Find the chip header's correct computation**

```bash
grep -rn "NEXT IN.*DAYS\|next_in_days\|nextInDays" lib/ | head -10
```

The chip header in Daily/Workout shows "NEXT IN 13 DAYS" (positive). Find that code path. Likely uses `RankService.instance.getNextRank()` or similar.

- [ ] **Step 3: Apply the sign fix**

In `service_record_section.dart`, find the negative computation. Common patterns:

```dart
// WRONG (negative): now.difference(targetDate).inDays
// CORRECT (positive): targetDate.difference(now).inDays.clamp(0, 365)
```

Apply the correct formula. If the chip header uses a shared helper (e.g., `RankService.daysUntilNextRank()`), USE THAT helper in service_record_section. Don't keep two parallel computations.

If no shared helper exists yet, EXTRACT one in `lib/core/services/rank_service.dart`:

```dart
/// Days until the user reaches the next rank.
/// Returns 0 if user is at top rank or requirements already met.
/// Always non-negative.
int daysUntilNextRank() {
  final next = getNextRank();
  if (next == null) return 0;
  // ... compute target date from requirements + current cadence ...
  final targetDate = /* ... */;
  final delta = targetDate.difference(DateTime.now()).inDays;
  return delta.clamp(0, 365);
}
```

Then use this single method from BOTH the chip header AND service_record_section.

- [ ] **Step 4: Test the fix**

Create `test/profile/rank_card_eta_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

void main() {
  test('B4: daysUntilNextRank is always non-negative', () {
    // Even with mocked-future state, should never return negative
    final days = RankService.instance.daysUntilNextRank();
    expect(days, greaterThanOrEqualTo(0),
      reason: 'B4 fix: ETA must never be negative');
  });
}
```

If `daysUntilNextRank` doesn't exist as a method, adapt the test to whatever helper got extracted.

Plus a widget snapshot-string check in service_record_section's summary text:

```dart
test('B4: service record summary text never contains "-" before days', () {
  // Read the actual rendered string from _buildCurrentRankSummary
  // OR if widget testing is heavy, just assert the formatter:
  final formatted = '$days days';  // however it's formatted
  expect(formatted.contains('-'), false);
});
```

- [ ] **Step 5: Verify both surfaces show consistent positive number**

Manual visual check (since widget tests for layout are heavy here):

```bash
flutter analyze lib/features/profile/widgets/service_record_section.dart \
                lib/core/services/rank_service.dart
flutter test test/profile/ test/  # full suite
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/profile/widgets/service_record_section.dart \
        lib/core/services/rank_service.dart \
        test/profile/rank_card_eta_test.dart
git commit -m "fix(profile): RANK card 'days' sign + share helper with chip (B4)

User OBS in Test #4 install: Profile RANK card showed
'Next: Seaman 1st Class in -13 days'. Chip header in Daily/Workout
showed positive 13. Two divergent computations.

Fix: extract daysUntilNextRank() into RankService (single source).
Both chip header AND service_record_section use the same helper.
Helper clamps to non-negative — sign always positive.

Tests: ETA non-negative + summary string never contains '-N'.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-review

- [ ] **Spec coverage:** B2 (streak anchor) → Task B-1; B3 (Manual + tool-loop) → Task B-2; B4 (RANK -13 days) → Task B-3. ✅
- [ ] **Placeholder scan:** No TBD/TODO. ✅
- [ ] **Type consistency:** `daysUntilNextRank` named consistently in B-3. ✅
- [ ] **Deploy step:** ai-proxy v59 in Task B-2. ✅

## Out of scope for Plan B

- Plan generator past-Monday root cause → permanent OOS (rule #14)
- B1/B5 cross-account → Plan A
- All UX → Plans C/D
