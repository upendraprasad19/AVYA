# APK Test #5 Plan C — AI Coach Tool Dispatch UX

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping a "Reshuffle week" or "Pause 1 day" review card actually dispatches — schedule changes, Hive updates, cloud syncs, card auto-dismisses. Every WRITE tool (16 of 20 per CLAUDE.md §11) follows the same reliable pattern.

**Architecture:** Surgical fix for the two reported tools (`rescheduleWeek`, `pausePlan`) with explicit Apply/Dismiss buttons + auto-dismiss after dispatch + Hive write + sync wired correctly. Then a checklist audit of all 16 WRITE tools to find/fix the same class of silent-failure bugs.

**Estimated effort:** 9-12h.

**Spec reference:** `docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md` §5 + §10 (C6-C7).

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `lib/features/ai_coach/services/tool_dispatcher.dart` | MODIFY | Wire `rescheduleWeek` + `pausePlan` (and audit-found gaps); fire sync; mark dispatched |
| `lib/features/ai_coach/widgets/review_card.dart` (or inline in screen) | MODIFY | Explicit Apply/Dismiss buttons; filter dispatched intents |
| `lib/features/ai_coach/screens/ai_coach_screen.dart` | MODIFY (likely) | Render path for ToolIntent → review card |
| `test/ai_coach/dispatch_reschedule_pause_test.dart` | CREATE | C-7 end-to-end dispatch coverage |
| `docs/superpowers/notes/2026-04-28-coach-dispatch-trace.md` | CREATE | C-1/C-2 investigation findings |
| `docs/superpowers/notes/2026-04-28-coach-tool-audit.md` | CREATE | C-8 16-tool checklist + C-11 manual smoke results |

---

## Task C-1 — Investigation: tool dispatcher path

**Files:** `lib/features/ai_coach/services/tool_dispatcher.dart` (READ ONLY) → `docs/superpowers/notes/2026-04-28-coach-dispatch-trace.md` (CREATE)

- [ ] **Step 1: Read the dispatcher.**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
wc -l lib/features/ai_coach/services/tool_dispatcher.dart
```

Expected: file exists, line count > 0. Read the entire file. Catalogue every `case 'tool_name':` branch.

- [ ] **Step 2: Identify rescheduleWeek + pausePlan handlers.**

Grep the file for the two tool names:

```bash
grep -n "rescheduleWeek\|pausePlan" lib/features/ai_coach/services/tool_dispatcher.dart
```

Note: (a) presence/absence of each case, (b) whether the handler calls `WorkoutScheduleService`, (c) whether `unawaited(SyncService.instance.syncWorkoutData())` + `unawaited(SyncService.instance.pushSnapshot())` fire after the Hive write, (d) whether a `dispatched_at` Hive flag is written.

- [ ] **Step 3: Catalogue all 20 tool cases (and gaps).**

For each of the 20 tools listed in CLAUDE.md §11, mark in the trace doc whether the dispatcher has: (i) a `case` branch, (ii) the validate→mutate→sync→mark sequence, (iii) try/catch with snackbar.

- [ ] **Step 4: Write findings to trace doc.**

Create `docs/superpowers/notes/2026-04-28-coach-dispatch-trace.md` with this exact scaffold:

```markdown
# Coach Dispatch Trace — 2026-04-28

## Dispatcher file

Path: `lib/features/ai_coach/services/tool_dispatcher.dart`
Line count: <N>

## Per-tool handler status

| Tool | Case exists? | Calls service? | Fires sync? | Marks dispatched? | Try/catch? |
|---|---|---|---|---|---|
| swapExercise | ... | ... | ... | ... | ... |
| logSet | ... | ... | ... | ... | ... |
| markWorkoutComplete | ... | ... | ... | ... | ... |
| shortenWorkout | ... | ... | ... | ... | ... |
| createCustomExercise | ... | ... | ... | ... | ... |
| modifyWorkoutForInjury | ... | ... | ... | ... | ... |
| rescheduleWeek | ... | ... | ... | ... | ... |
| generateHotelWorkout | ... | ... | ... | ... | ... |
| logMealByText | ... | ... | ... | ... | ... |
| adjustCaloricTarget | ... | ... | ... | ... | ... |
| prelog | ... | ... | ... | ... | ... |
| regeneratePlanBlock | ... | ... | ... | ... | ... |
| pausePlan | ... | ... | ... | ... | ... |
| switchGoal | ... | ... | ... | ... | ... |
| createCustomTemplate | ... | ... | ... | ... | ... |
| scheduleTemplate | ... | ... | ... | ... | ... |

## rescheduleWeek detail

<paste actual case body or "MISSING">

## pausePlan detail

<paste actual case body or "MISSING">
```

- [ ] **Step 5: Commit.**

```bash
git add docs/superpowers/notes/2026-04-28-coach-dispatch-trace.md
git commit -m "docs(coach): trace tool_dispatcher for rescheduleWeek + pausePlan (C-1)"
```

NO production code changes in this task.

---

## Task C-2 — Investigation: review card render path

**Files:** `lib/features/ai_coach/screens/ai_coach_screen.dart` (READ ONLY), `lib/features/ai_coach/widgets/` (READ ONLY) → trace doc (APPEND)

- [ ] **Step 1: Find the ToolIntent renderer.**

```bash
grep -rn "ToolIntent\|review_card\|ReviewCard" lib/features/ai_coach/
```

Identify: (a) which widget receives the `ToolIntent`, (b) where the tap handler is wired, (c) whether explicit Apply/Dismiss buttons exist or only a chevron/tap-anywhere pattern.

- [ ] **Step 2: Read the renderer file end-to-end.**

Read whichever file Step 1 surfaced (likely `lib/features/ai_coach/widgets/review_card.dart` OR inline in `ai_coach_screen.dart`). Note line numbers for: build method, tap handler, button row.

- [ ] **Step 3: Append findings to trace doc.**

Append a section to `docs/superpowers/notes/2026-04-28-coach-dispatch-trace.md`:

```markdown
## Review card render path

- Renderer file: <path>
- Renderer widget class: <ClassName>
- Tap handler location: <file>:<line>
- Buttons present: [Apply ❌ / Dismiss ❌ / Chevron ✅ / Other: ___]
- Filter for dispatched intents: [yes / no — if yes describe]
- ToolIntent stream/source: <provider name + file>
```

- [ ] **Step 4: Commit.**

```bash
git add docs/superpowers/notes/2026-04-28-coach-dispatch-trace.md
git commit -m "docs(coach): trace review card render path (C-2)"
```

---

## Task C-3 — UI: add Apply/Dismiss buttons to review cards

**Files:** Whichever file Task C-2 surfaced (assume `lib/features/ai_coach/widgets/review_card.dart`)

- [ ] **Step 1: Replace chevron-only pattern with explicit button row.**

In the review card widget's `build` method, replace the existing tap target / chevron with a row of two `WardButton`s. Below is the canonical replacement — adapt the surrounding card chrome verbatim from the existing widget:

```dart
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/app_colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.intent});

  final ToolIntent intent;

  @override
  Widget build(BuildContext context) {
    return WardCard(
      padding: const EdgeInsets.all(AppSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Existing eyebrow + summary text — keep verbatim from current widget.
          WardEyebrow(text: intent.title.toUpperCase()),
          const SizedBox(height: AppSpacing.section),
          Text(intent.summary, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.section),
          Row(
            children: [
              Expanded(
                child: WardButton(
                  label: 'APPLY',
                  onPressed: () => _onApply(context),
                ),
              ),
              const SizedBox(width: AppSpacing.inline),
              Expanded(
                child: WardButton(
                  label: 'DISMISS',
                  secondary: true,
                  onPressed: () => _onDismiss(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onApply(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ToolDispatcher.instance.dispatch(intent);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not apply: $e')),
      );
    }
  }

  Future<void> _onDismiss(BuildContext context) async {
    await ToolDispatcher.instance.markDismissed(intent);
  }
}
```

If the existing widget signature differs (e.g., takes a `VoidCallback onTap` rather than the intent directly), adapt the constructor while preserving the Apply/Dismiss row exactly.

- [ ] **Step 2: Verify it compiles.**

```bash
flutter analyze lib/features/ai_coach/widgets/review_card.dart
```

Expect: 0 issues.

- [ ] **Step 3: Commit.**

```bash
git add lib/features/ai_coach/widgets/review_card.dart
git commit -m "feat(coach): explicit Apply/Dismiss buttons on review cards (C-3)"
```

---

## Task C-4 — Wire `rescheduleWeek` dispatch

**Files:** `lib/features/ai_coach/services/tool_dispatcher.dart`

- [ ] **Step 1: Locate the `rescheduleWeek` case.**

If Task C-1 found it missing, add a new case. If present, update it. Either way, the final case body must read:

```dart
case 'rescheduleWeek':
  {
    final days = (intent.payload['days'] as num?)?.toInt();
    if (days == null || days < 3 || days > 7) {
      throw ArgumentError('rescheduleWeek requires days in [3..7], got $days');
    }
    try {
      await WorkoutScheduleService.instance.regenerateForDays(days);
      await _markDispatched(intent);
      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      debugPrint('[ToolDispatcher] rescheduleWeek failed: $e\n$st');
      rethrow;
    }
    break;
  }
```

- [ ] **Step 2: Add the `_markDispatched` helper if it does not already exist.**

Append to the same file (private helper at the bottom of the class):

```dart
Future<void> _markDispatched(ToolIntent intent) async {
  final box = HiveService.instance.coachBox;
  await box.put('intent_${intent.id}_dispatched_at', DateTime.now().toIso8601String());
}

Future<void> markDismissed(ToolIntent intent) async {
  final box = HiveService.instance.coachBox;
  await box.put('intent_${intent.id}_dismissed_at', DateTime.now().toIso8601String());
}

bool isResolved(String intentId) {
  final box = HiveService.instance.coachBox;
  return box.containsKey('intent_${intentId}_dispatched_at') ||
      box.containsKey('intent_${intentId}_dismissed_at');
}
```

- [ ] **Step 3: Verify imports.**

The file must import `dart:async` (for `unawaited`), `package:flutter/foundation.dart` (for `debugPrint`), `package:icanbefitter/core/services/hive_service.dart`, `package:icanbefitter/core/services/sync_service.dart`, `package:icanbefitter/features/train/services/workout_schedule_service.dart`, and the local `tool_intent.dart` model. Add any missing import.

- [ ] **Step 4: Compile + commit.**

```bash
flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart
git add lib/features/ai_coach/services/tool_dispatcher.dart
git commit -m "fix(coach): wire rescheduleWeek dispatch with sync + dispatched flag (C-4)"
```

Expect: 0 analyzer issues.

---

## Task C-5 — Wire `pausePlan` dispatch

**Files:** `lib/features/ai_coach/services/tool_dispatcher.dart`

- [ ] **Step 1: Locate / add the `pausePlan` case.**

Final case body:

```dart
case 'pausePlan':
  {
    final dateStr = intent.payload['date'] as String?;
    final date = dateStr == null ? DateTime.now() : DateTime.parse(dateStr);
    try {
      await WorkoutScheduleService.instance.markRestDay(date);
      await _markDispatched(intent);
      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      debugPrint('[ToolDispatcher] pausePlan failed: $e\n$st');
      rethrow;
    }
    break;
  }
```

- [ ] **Step 2: Verify `WorkoutScheduleService.markRestDay` exists.**

```bash
grep -n "markRestDay" lib/features/train/services/workout_schedule_service.dart
```

If absent, add this method to `WorkoutScheduleService`:

```dart
Future<void> markRestDay(DateTime date) async {
  final iso = date.toIso8601String().substring(0, 10);
  final key = 'schedule_$iso';
  final existing = (HiveService.instance.workoutBox.get(key) as Map?) ?? <String, dynamic>{};
  final updated = Map<String, dynamic>.from(existing)
    ..['type'] = 'rest'
    ..['workout_name'] = 'REST DAY'
    ..['status'] = 'rest';
  await HiveService.instance.workoutBox.put(key, updated);
}
```

- [ ] **Step 3: Compile + commit.**

```bash
flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart lib/features/train/services/workout_schedule_service.dart
git add lib/features/ai_coach/services/tool_dispatcher.dart lib/features/train/services/workout_schedule_service.dart
git commit -m "fix(coach): wire pausePlan dispatch with rest-day write + sync (C-5)"
```

Expect: 0 analyzer issues.

---

## Task C-6 — Auto-dismiss after dispatch

**Files:** Whichever file Task C-2 surfaced as the renderer (likely `lib/features/ai_coach/screens/ai_coach_screen.dart`)

- [ ] **Step 1: Filter resolved intents from the render list.**

In the widget that builds the chat thread, the section that maps `ToolIntent` items to `ReviewCard`s must skip resolved (dispatched OR dismissed) intents:

```dart
// Inside the chat list builder, where ToolIntents render:
final visibleIntents = intents.where(
  (i) => !ToolDispatcher.instance.isResolved(i.id),
).toList();

return Column(
  children: [
    for (final intent in visibleIntents) ReviewCard(intent: intent),
  ],
);
```

If the renderer reads from a Riverpod provider, add a `ValueListenableBuilder` on `HiveService.instance.coachBox.listenable()` so the list rebuilds when `_markDispatched` writes the flag:

```dart
return ValueListenableBuilder(
  valueListenable: HiveService.instance.coachBox.listenable(),
  builder: (context, _, __) {
    final visibleIntents = intents.where(
      (i) => !ToolDispatcher.instance.isResolved(i.id),
    ).toList();
    return Column(
      children: [
        for (final intent in visibleIntents) ReviewCard(intent: intent),
      ],
    );
  },
);
```

- [ ] **Step 2: Compile + commit.**

```bash
flutter analyze lib/features/ai_coach/
git add lib/features/ai_coach/
git commit -m "feat(coach): auto-dismiss review cards after dispatch (C-6)"
```

---

## Task C-7 — Test rescheduleWeek + pausePlan dispatch end-to-end

**Files:** `test/ai_coach/dispatch_reschedule_pause_test.dart` (CREATE)

- [ ] **Step 1: Write the test.**

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_c7_');
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
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.coachBox.clear();
  });

  String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

  group('C-7: rescheduleWeek + pausePlan dispatch', () {
    test('rescheduleWeek dispatch updates schedule + marks dispatched', () async {
      final intent = ToolIntent(
        id: 'r1',
        toolName: 'rescheduleWeek',
        title: 'Reshuffle to 6 days',
        summary: 'Switch from 4 days to 6 days this week',
        payload: const {'days': 6},
      );

      await ToolDispatcher.instance.dispatch(intent);

      // Assert dispatched flag written
      expect(
        HiveService.instance.coachBox.containsKey('intent_r1_dispatched_at'),
        isTrue,
      );

      // Assert schedule got rebuilt for at least 6 distinct dates this week
      final today = DateTime.now();
      final weekKeys = <String>{};
      for (var i = 0; i < 7; i++) {
        final d = today.add(Duration(days: i));
        final key = 'schedule_${_isoDate(d)}';
        if (HiveService.instance.workoutBox.containsKey(key)) {
          weekKeys.add(key);
        }
      }
      expect(weekKeys.length, greaterThanOrEqualTo(6));
    });

    test('pausePlan dispatch sets today to rest + marks dispatched', () async {
      final today = DateTime.now();
      final intent = ToolIntent(
        id: 'p1',
        toolName: 'pausePlan',
        title: 'Rest day today',
        summary: 'Mark today as a rest day',
        payload: {'date': today.toIso8601String()},
      );

      await ToolDispatcher.instance.dispatch(intent);

      expect(
        HiveService.instance.coachBox.containsKey('intent_p1_dispatched_at'),
        isTrue,
      );

      final entry = HiveService.instance.workoutBox
          .get('schedule_${_isoDate(today)}') as Map?;
      expect(entry, isNotNull);
      expect(entry!['status'], equals('rest'));
    });

    test('isResolved returns true after dispatch', () async {
      final intent = ToolIntent(
        id: 'r2',
        toolName: 'pausePlan',
        title: 'Rest',
        summary: 'Rest',
        payload: {'date': DateTime.now().toIso8601String()},
      );
      await ToolDispatcher.instance.dispatch(intent);
      expect(ToolDispatcher.instance.isResolved('r2'), isTrue);
    });

    test('markDismissed resolves the intent without mutation', () async {
      final intent = ToolIntent(
        id: 'd1',
        toolName: 'pausePlan',
        title: 'x',
        summary: 'x',
        payload: const {},
      );
      await ToolDispatcher.instance.markDismissed(intent);
      expect(ToolDispatcher.instance.isResolved('d1'), isTrue);
      // No schedule write for dismissed intents
      final today = DateTime.now();
      expect(
        HiveService.instance.workoutBox.containsKey('schedule_${_isoDate(today)}'),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run.**

```bash
flutter test test/ai_coach/dispatch_reschedule_pause_test.dart
```

Expect: 4 tests pass.

- [ ] **Step 3: Commit.**

```bash
git add test/ai_coach/dispatch_reschedule_pause_test.dart
git commit -m "test(coach): cover rescheduleWeek + pausePlan dispatch (C-7)"
```

---

## Task C-8 — Audit all 16 WRITE tools — checklist scaffold

**Files:** `docs/superpowers/notes/2026-04-28-coach-tool-audit.md` (CREATE)

- [ ] **Step 1: Create audit scaffold.**

Write `docs/superpowers/notes/2026-04-28-coach-tool-audit.md`:

```markdown
# Coach WRITE Tool Audit — 2026-04-28

Source of truth for the 16 WRITE tools per CLAUDE.md §11 + Plan C spec §5.3.

## Scoring

For each tool, mark ✅ or write a one-line description of the gap.

| # | Family | Tool | (i) Handler exists | (ii) Apply/Dismiss buttons | (iii) Sync fires | (iv) Auto-dismiss flag |
|---|---|---|---|---|---|---|
| 1 | Workout | `swapExercise` | | | | |
| 2 | Workout | `logSet` | | | | |
| 3 | Workout | `markWorkoutComplete` | | | | |
| 4 | Workout | `shortenWorkout` | | | | |
| 5 | Workout | `createCustomExercise` | | | | |
| 6 | Workout | `modifyWorkoutForInjury` | | | | |
| 7 | Workout | `rescheduleWeek` | ✅ (C-4) | ✅ (C-3) | ✅ (C-4) | ✅ (C-4) |
| 8 | Workout | `generateHotelWorkout` | | | | |
| 9 | Nutrition | `logMealByText` | | | | |
| 10 | Nutrition | `adjustCaloricTarget` | | | | |
| 11 | Nutrition | `prelog` | | | | |
| 12 | Plan | `regeneratePlanBlock` | | | | |
| 13 | Plan | `pausePlan` | ✅ (C-5) | ✅ (C-3) | ✅ (C-5) | ✅ (C-5) |
| 14 | Plan | `switchGoal` | | | | |
| 15 | Plan | `createCustomTemplate` | | | | |
| 16 | Plan | `scheduleTemplate` | | | | |

## Per-tool gap notes

(One subsection per fix-needed tool, filled in during execution.)

### swapExercise

(fill during C-9)

...

## Manual smoke results (C-11)

(filled during C-11)
```

- [ ] **Step 2: Fill rows by re-reading the trace doc + dispatcher.**

Use the trace findings from Task C-1 to populate columns (i) through (iv) for each row. For tools where any column is empty, write a one-line gap description in the per-tool subsection (e.g., "swapExercise — handler exists but missing pushSnapshot after Hive write").

- [ ] **Step 3: Commit the filled audit.**

```bash
git add docs/superpowers/notes/2026-04-28-coach-tool-audit.md
git commit -m "docs(coach): WRITE tool audit checklist filled (C-8)"
```

---

## Task C-9 — Fix every broken WRITE tool found in audit

**Files:** `lib/features/ai_coach/services/tool_dispatcher.dart` (and possibly individual service files for the dependency calls)

> **Dynamic scope:** apply the same template fix to every tool that scored less than ✅ across all four columns in C-8. One commit per tool.

### Generic fix template

For each broken tool `<toolName>`, the case body must end up in this exact shape:

```dart
case '<toolName>':
  {
    // 1. VALIDATE intent payload — throw ArgumentError on bad input.
    final <typedFields> = intent.payload['<key>'] as <Type>?;
    if (<typedFields> == null) {
      throw ArgumentError('<toolName> requires <key>');
    }

    // 2. MUTATE Hive via the canonical service for this domain
    //    (WorkoutScheduleService / NutritionService / PlanGenerator / etc).
    try {
      await <CanonicalService>.instance.<doTheWrite>(<typedFields>);

      // 3. MARK dispatched in coachBox (so the card auto-dismisses).
      await _markDispatched(intent);

      // 4. SYNC fire-and-forget (CLAUDE.md §15 rule).
      //    Workout family → syncWorkoutData
      //    Nutrition family → syncNutritionData
      //    Plan family → syncWorkoutData (plan changes write schedule rows)
      unawaited(SyncService.instance.<syncWorkoutData|syncNutritionData>());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      debugPrint('[ToolDispatcher] <toolName> failed: $e\n$st');
      rethrow; // ReviewCard._onApply catches and shows snackbar.
    }
    break;
  }
```

### Sync-method-by-family quick reference

| Family | Sync call |
|---|---|
| Workout | `syncWorkoutData()` |
| Nutrition | `syncNutritionData()` |
| Plan | `syncWorkoutData()` (plan tools rewrite schedule rows) |

### Concrete example — `swapExercise`

Assume C-8 audit found the case exists but is missing `pushSnapshot` and the dispatched flag. Replace its body with:

```dart
case 'swapExercise':
  {
    final dateStr = intent.payload['date'] as String?;
    final dayIndex = (intent.payload['day_index'] as num?)?.toInt();
    final fromName = intent.payload['from_name'] as String?;
    final toName = intent.payload['to_name'] as String?;

    if (dateStr == null || dayIndex == null || fromName == null || toName == null) {
      throw ArgumentError(
        'swapExercise requires date, day_index, from_name, to_name',
      );
    }

    try {
      await WorkoutScheduleService.instance.swapExerciseInDay(
        date: DateTime.parse(dateStr),
        dayIndex: dayIndex,
        fromName: fromName,
        toName: toName,
      );
      await _markDispatched(intent);
      unawaited(SyncService.instance.syncWorkoutData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      debugPrint('[ToolDispatcher] swapExercise failed: $e\n$st');
      rethrow;
    }
    break;
  }
```

### Step list (per tool)

- [ ] **Step 1: For each fix-needed tool from C-8, apply the template.**

Reference the canonical service for each domain:
- Workout family → `WorkoutScheduleService` / `WorkoutRepository`
- Nutrition family → `NutritionRepository` / `SyncService.syncNutritionData`
- Plan family → `WorkoutScheduleService` / `PlanGenerator`

If a canonical service method does not exist for the requested mutation, add a thin method on the service that performs the Hive write + provider invalidations, then call it from the dispatcher case.

- [ ] **Step 2: Re-run analyzer after each tool.**

```bash
flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart
```

Expect: 0 issues per fix.

- [ ] **Step 3: Commit each tool fix as a separate commit.**

```bash
git commit -m "fix(coach): wire <toolName> dispatch (sync + dispatched flag) (C-9)"
```

Do NOT batch multiple tools into one commit. Reviewers must be able to bisect a regression to a single tool.

- [ ] **Step 4: Update the audit doc as you go.**

After each tool fix, re-mark its row in `docs/superpowers/notes/2026-04-28-coach-tool-audit.md` to ✅ across all four columns. Final doc commit:

```bash
git add docs/superpowers/notes/2026-04-28-coach-tool-audit.md
git commit -m "docs(coach): mark all 16 WRITE tools ✅ post-audit (C-9)"
```

---

## Task C-10 — Full test suite + analyze

**Files:** none

- [ ] **Step 1: Analyze the AI coach package.**

```bash
flutter analyze lib/features/ai_coach/
```

Expect: 0 issues. If pre-existing warnings unrelated to this batch surface, document them in the audit doc under "Pre-existing analyzer noise (NOT fixed in this batch)" — do not silence them.

- [ ] **Step 2: Run the AI coach tests.**

```bash
flutter test test/ai_coach/
```

Expect: all pass. Document any pre-existing failures separately in the audit doc.

- [ ] **Step 3: Run the full test suite.**

```bash
flutter test
```

Expect: no NEW failures introduced by this batch. Pre-existing failures (if any) listed in the audit doc.

- [ ] **Step 4: Commit any test-fixture updates required by C-9 changes.**

If C-9 changes broke an unrelated existing test (e.g., a contract test that pinned the old broken behavior), update it and commit:

```bash
git commit -m "test(coach): update fixtures for new dispatch contract (C-10)"
```

---

## Task C-11 — Manual end-to-end smoke (documented, not automated)

**Files:** `docs/superpowers/notes/2026-04-28-coach-tool-audit.md` (APPEND)

- [ ] **Step 1: Build dev APK.**

```bash
# Use the build-apk skill rather than direct flutter build apk —
# the skill does pre-flight cleanup that prevents silent hangs on this machine.
# Per CLAUDE.md: always --flavor prod --release for distribution; but for
# local smoke a debug install on a connected device is fine.
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

Wait for app to install + launch on connected device.

- [ ] **Step 2: Run pausePlan flow.**

In the AI coach tab, send: `Mark today as rest day.`

Expected:
1. Coach replies + a review card appears with title "Pause 1 day from <today>" and body summarizing the rest day.
2. Card has visible **APPLY** (gold) and **DISMISS** (secondary) buttons.
3. Tap **APPLY**.
4. Snackbar / no error.
5. Card disappears from the chat thread.
6. Switch to Train tab → today's calendar entry shows REST DAY badge.
7. Restart app → card stays gone (Hive flag persisted).

- [ ] **Step 3: Run rescheduleWeek flow.**

In the AI coach tab, send: `Reshuffle my week to 6 days.`

Expected:
1. Review card appears with current vs proposed split summary, APPLY + DISMISS buttons.
2. Tap **APPLY**.
3. Card disappears.
4. Switch to Train tab → week selector now shows 6 training days, 1 rest day.
5. Cloud sync — check Supabase `scheduled_workouts` rows for the user → 6 rows with `workout_name != 'REST DAY'` for the next 7 days.

- [ ] **Step 4: Run DISMISS path.**

Send: `Mark tomorrow as rest day.` Card appears. Tap **DISMISS**. Card disappears. Train tab shows tomorrow unchanged.

- [ ] **Step 5: Append outcomes.**

Append to `docs/superpowers/notes/2026-04-28-coach-tool-audit.md`:

```markdown
## Manual smoke results (C-11)

| Flow | Card appears | Apply/Dismiss visible | Apply mutates state | Card auto-dismisses | Cloud sync confirmed |
|---|---|---|---|---|---|
| pausePlan (today) | ✅ / ❌ | ✅ / ❌ | ✅ / ❌ | ✅ / ❌ | ✅ / ❌ |
| rescheduleWeek (4→6 days) | ✅ / ❌ | ✅ / ❌ | ✅ / ❌ | ✅ / ❌ | ✅ / ❌ |
| pausePlan DISMISS | ✅ / ❌ | ✅ / ❌ | n/a | ✅ / ❌ | n/a |

Tested on: <device + OS version>
APK build: <commit sha>
Date: <YYYY-MM-DD>
```

Fill in the actual ✅/❌ values from the device test.

- [ ] **Step 6: Commit.**

```bash
git add docs/superpowers/notes/2026-04-28-coach-tool-audit.md
git commit -m "docs(coach): manual smoke results for rescheduleWeek + pausePlan (C-11)"
```

---

## Success criteria mapping

| Spec ID | Met by |
|---|---|
| C6 — pausePlan review card → Apply → today becomes Rest → card disappears | C-3 + C-5 + C-6 + C-11 Step 2 |
| C7 — rescheduleWeek review card → Apply → schedule updates → card disappears | C-3 + C-4 + C-6 + C-11 Step 3 |
| Audit + fix all 16 WRITE tools | C-8 + C-9 |

## CLAUDE.md compliance checklist

- [x] Every WRITE dispatch fires `unawaited(SyncService.instance.syncWorkoutData())` (or `syncNutritionData()` for nutrition family) + `unawaited(SyncService.instance.pushSnapshot())` after the Hive write — §15 fire-and-forget rule.
- [x] Hive writes use `HiveService.instance.coachBox` (not raw `Hive.box('coach')`) — §19 Hive box safety.
- [x] Dispatch errors `rethrow` so ReviewCard surfaces a snackbar — never silent failure.
- [x] `unawaited` + `dart:async` import present — sync calls do not block UI.
- [x] No new direct `configBox` reads, no inline `isPro` checks, no new paywall surfaces — Plan C touches dispatch only.

---

## Notes for the executor

- **Read C-1 + C-2 trace doc before writing any code.** The investigation is load-bearing — don't skip it. Many of the audit findings can be recycled directly into C-9 fix scope.
- **Don't redesign the review card from card → bottom sheet.** Spec §5.4 explicitly defers that. Apply/Dismiss buttons inside the card is the agreed shape.
- **One commit per tool in C-9.** No batching. Reviewers must be able to bisect.
- **The dispatched flag survives app restart.** That's why we write to `coachBox`, not in-memory state. Test C-7 implicitly verifies this via the second test (`isResolved` after dispatch).
- **Manual smoke is mandatory.** Spec success criteria C6/C7 require on-device verification — no automated test alone can satisfy them.
