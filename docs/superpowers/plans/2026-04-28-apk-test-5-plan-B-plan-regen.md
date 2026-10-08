# APK Test #5 Plan B — Plan Regen Triggers

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Save Advanced + 6 days + Full Gym + 90min on Edit Profile → today's plan regenerates to 8-10 exercises (not 4) within seconds. 6-vs-5-days mismatch (OBS-2) auto-resolved or surfaced + fixed.

**Architecture:** Surgical extension to `edit_profile_screen.dart::_save`'s `planChanged` flag — currently watches only `daysPerWeek` / `goal` / `equipment` / `fitness_experience`, must also watch `session_duration_minutes`, `physique_focus`, `injuries` (all V4 plan-driving inputs). Plus a 1h investigation of OBS-2 to determine if it's the same root cause or a separate `WorkoutScheduleService` bug.

**Estimated effort:** 2.5-3h.

**Spec reference:** `docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md` §4 + §10 (C4-C5).

---

## Task B-1 — Capture original values in initState

**Files:** `lib/features/profile/screens/edit_profile_screen.dart` (Modify)

`_originalFitnessExperience` is already in place (lines 73, 177). Add the remaining three originals.

- [ ] **Step 1: Extend the `late` field declarations**

Edit `lib/features/profile/screens/edit_profile_screen.dart`. Find the original-tracking block around line 69-76:

```dart
// Track original plan-affecting values for rescheduling detection
late int _originalDaysPerWeek;
late String _originalGoal;
late String _originalEquipment;
late String _originalFitnessExperience;

// Track original target weight for prediction invalidation (Bug #12)
late double _originalTargetWeight;
```

Replace with:

```dart
// Track original plan-affecting values for rescheduling detection.
// V4 pipeline plan-driving inputs (per CLAUDE.md §12 + plan_engine/):
//   daysPerWeek + goal + equipment + fitness_experience drive the split
//   resolver + volume filter + exercise selector. session_duration_minutes
//   + physique_focus + injuries drive sequencing + warmup/cooldown +
//   exclusion masks. ALL must trigger reschedule on change.
late int _originalDaysPerWeek;
late String _originalGoal;
late String _originalEquipment;
late String _originalFitnessExperience;
late int? _originalSessionDuration;
late String _originalPhysiqueFocus;
late List<String> _originalInjuries;

// Track original target weight for prediction invalidation (Bug #12)
late double _originalTargetWeight;
```

- [ ] **Step 2: Capture each in initState**

Find the existing capture block around line 173-178:

```dart
// Capture original values for rescheduling detection
_originalDaysPerWeek = _daysPerWeek;
_originalGoal = _goal;
_originalEquipment = _equipment;
_originalFitnessExperience = _fitnessExperience;
_originalTargetWeight = targetKgRaw ?? 0.0;
```

Replace with:

```dart
// Capture original values for rescheduling detection.
// _injuries is captured as List.of(...) so later edits via the chip
// row don't mutate the original snapshot (List references are aliased
// in Dart; without List.of we'd compare a list to itself).
_originalDaysPerWeek = _daysPerWeek;
_originalGoal = _goal;
_originalEquipment = _equipment;
_originalFitnessExperience = _fitnessExperience;
_originalSessionDuration = _sessionDuration;
_originalPhysiqueFocus = _physiqueFocus;
_originalInjuries = List<String>.of(_injuries);
_originalTargetWeight = targetKgRaw ?? 0.0;
```

- [ ] **Step 3: Verify analyze passes**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/features/profile/screens/edit_profile_screen.dart
```

Expect 0 issues. (planChanged still references only the existing 4 fields, so no logic change yet.)

- [ ] **Step 4: Commit**

```bash
git add lib/features/profile/screens/edit_profile_screen.dart
git commit -m "$(cat <<'EOF'
refactor(profile): capture session/physique/injuries originals in initState (B-1)

APK Test #5 Plan B step 1 of 3. Adds _originalSessionDuration,
_originalPhysiqueFocus, _originalInjuries late fields + initState
capture. No behavior change yet — planChanged still references only
the existing 4 fields. Following commits (B-2/B-3) wire these in.

_originalInjuries uses List.of(_injuries) to snapshot — Dart Lists
are reference types, a direct = would alias the original to live edits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-2 — Extend planChanged check

**Files:** `lib/features/profile/screens/edit_profile_screen.dart` (Modify)

- [ ] **Step 1: Extend the foundation import to include `listEquals`**

Find line 4:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
```

Replace with:

```dart
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
```

- [ ] **Step 2: Extend the `planChanged` boolean**

Find the block around line 1555-1563:

```dart
// Detect plan-affecting field changes and offer rescheduling
// Experience drives VolumeFilter.targetCount → exercise count per day.
// Beginner/Inter/Advanced × 3-6 days = 4 to 10 exercises. Without this,
// bumping intermediate→advanced wouldn't trigger reschedule and today's
// plan would keep showing the old 4-7 exercises forever.
final planChanged = _daysPerWeek != _originalDaysPerWeek ||
    _goal != _originalGoal ||
    _equipment != _originalEquipment ||
    _fitnessExperience != _originalFitnessExperience;
```

Replace with:

```dart
// Detect plan-affecting field changes and offer rescheduling.
// Experience drives VolumeFilter.targetCount → exercise count per day.
// Beginner/Inter/Advanced × 3-6 days = 4 to 10 exercises. Without this,
// bumping intermediate→advanced wouldn't trigger reschedule and today's
// plan would keep showing the old 4-7 exercises forever.
//
// session_duration_minutes drives split count + cardio finisher length;
// physique_focus drives muscle slot weighting (e.g. glutes_legs adds
// posterior chain priority); injuries drive exclusion masks in the
// exercise selector. ALL must trigger reschedule on change to keep
// today's schedule consistent with the saved profile.
final planChanged = _daysPerWeek != _originalDaysPerWeek ||
    _goal != _originalGoal ||
    _equipment != _originalEquipment ||
    _fitnessExperience != _originalFitnessExperience ||
    _sessionDuration != _originalSessionDuration ||
    _physiqueFocus != _originalPhysiqueFocus ||
    !listEquals(_injuries, _originalInjuries);
```

- [ ] **Step 3: Verify analyze passes**

```bash
flutter analyze lib/features/profile/screens/edit_profile_screen.dart
```

Expect 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/profile/screens/edit_profile_screen.dart
git commit -m "$(cat <<'EOF'
feat(profile): planChanged watches session/physique/injuries (B-2)

APK Test #5 Plan B step 2 of 3. Extends planChanged in _save to fire
on session_duration_minutes, physique_focus, or injuries change — all
are plan-driving inputs per V4 pipeline. Closes spec C4 success
criterion: bumping experience Beginner → Advanced in conjunction with
session 60→90 now triggers the reschedule dialog reliably.

listEquals from package:flutter/foundation handles the List<String>
comparison; direct == on Lists checks identity not contents.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-3 — Extend changes-list dialog entries

**Files:** `lib/features/profile/screens/edit_profile_screen.dart` (Modify)

- [ ] **Step 1: Add 3 new conditionals to the changes list**

Find the `if (planChanged && WorkoutScheduleService.instance.hasPlan() && mounted)` block around line 1565-1580. After the existing `if (_fitnessExperience != _originalFitnessExperience)` block (ends ~line 1580), append three new conditionals BEFORE the `final shouldReschedule = await showDialog<bool>(...)` line:

```dart
if (_sessionDuration != _originalSessionDuration) {
  String fmt(int? d) => d == null ? '—' : '${d} min';
  changes.add('Session: ${fmt(_originalSessionDuration)} → ${fmt(_sessionDuration)}');
}
if (_physiqueFocus != _originalPhysiqueFocus) {
  String label(String f) {
    switch (f) {
      case 'glutes_legs':
        return 'Glutes & Legs';
      case 'chest_shoulders_arms':
        return 'Chest, Shoulders & Arms';
      case 'strength':
        return 'Strength';
      case 'balanced':
      default:
        return 'Balanced';
    }
  }
  changes.add('Focus: ${label(_originalPhysiqueFocus)} → ${label(_physiqueFocus)}');
}
if (!listEquals(_injuries, _originalInjuries)) {
  changes.add('Injuries: ${_originalInjuries.length} → ${_injuries.length} listed');
}
```

The full updated changes-list block (for clarity — context around line 1565-1583) reads:

```dart
if (planChanged && WorkoutScheduleService.instance.hasPlan() && mounted) {
  final changes = <String>[];
  if (_daysPerWeek != _originalDaysPerWeek) {
    changes.add('$_originalDaysPerWeek → $_daysPerWeek days/week');
  }
  if (_goal != _originalGoal) {
    changes.add('Goal: ${_goals[_originalGoal]} → ${_goals[_goal]}');
  }
  if (_equipment != _originalEquipment) {
    changes.add('Equipment: ${_equipmentOptions[_originalEquipment]} → ${_equipmentOptions[_equipment]}');
  }
  if (_fitnessExperience != _originalFitnessExperience) {
    String label(String e) =>
        e[0].toUpperCase() + e.substring(1);
    changes.add('Experience: ${label(_originalFitnessExperience)} → ${label(_fitnessExperience)}');
  }
  if (_sessionDuration != _originalSessionDuration) {
    String fmt(int? d) => d == null ? '—' : '${d} min';
    changes.add('Session: ${fmt(_originalSessionDuration)} → ${fmt(_sessionDuration)}');
  }
  if (_physiqueFocus != _originalPhysiqueFocus) {
    String label(String f) {
      switch (f) {
        case 'glutes_legs':
          return 'Glutes & Legs';
        case 'chest_shoulders_arms':
          return 'Chest, Shoulders & Arms';
        case 'strength':
          return 'Strength';
        case 'balanced':
        default:
          return 'Balanced';
      }
    }
    changes.add('Focus: ${label(_originalPhysiqueFocus)} → ${label(_physiqueFocus)}');
  }
  if (!listEquals(_injuries, _originalInjuries)) {
    changes.add('Injuries: ${_originalInjuries.length} → ${_injuries.length} listed');
  }

  final shouldReschedule = await showDialog<bool>(/* ... unchanged ... */);
  // ... rest of dialog unchanged
}
```

- [ ] **Step 2: Verify analyze + format**

```bash
flutter analyze lib/features/profile/screens/edit_profile_screen.dart
```

Expect 0 issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/profile/screens/edit_profile_screen.dart
git commit -m "$(cat <<'EOF'
feat(profile): reschedule dialog lists session/focus/injuries diffs (B-3)

APK Test #5 Plan B step 3 of 3. Extends the 'You changed:' list inside
the Reschedule Workouts dialog with 3 new conditional entries:
  - 'Session: 60 min → 90 min'
  - 'Focus: Balanced → Glutes & Legs'
  - 'Injuries: 1 → 2 listed' (count-only — list contents are noisy)

Matches the planChanged trigger expansion from B-2 so the dialog text
explains every reason the prompt fired. Closes the user-facing half
of spec C4 success criterion.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-4 — Test scaffolding (TDD)

**Files:** `test/profile/edit_profile_plan_changed_test.dart` (Create)

Extract a pure helper from `_save`'s `planChanged` boolean into a top-level testable function so we can unit-test it without spinning up Flutter widgets / Hive / Supabase.

- [ ] **Step 1: Add a top-level helper to `edit_profile_screen.dart`**

At the bottom of `lib/features/profile/screens/edit_profile_screen.dart` (after the `_EditProfileScreenState` class closes), append:

```dart
/// Pure helper extracted from `_EditProfileScreenState._save` so the
/// reschedule trigger can be unit-tested without instantiating the
/// widget. Mirrors the boolean exactly — keep in sync with B-2.
@visibleForTesting
bool computePlanChanged({
  required int daysPerWeek,
  required int originalDaysPerWeek,
  required String goal,
  required String originalGoal,
  required String equipment,
  required String originalEquipment,
  required String fitnessExperience,
  required String originalFitnessExperience,
  required int? sessionDuration,
  required int? originalSessionDuration,
  required String physiqueFocus,
  required String originalPhysiqueFocus,
  required List<String> injuries,
  required List<String> originalInjuries,
}) {
  return daysPerWeek != originalDaysPerWeek ||
      goal != originalGoal ||
      equipment != originalEquipment ||
      fitnessExperience != originalFitnessExperience ||
      sessionDuration != originalSessionDuration ||
      physiqueFocus != originalPhysiqueFocus ||
      !listEquals(injuries, originalInjuries);
}
```

Add the `@visibleForTesting` import at the top of the file. Find the existing line:

```dart
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
```

Replace with:

```dart
import 'package:flutter/foundation.dart' show kIsWeb, listEquals, visibleForTesting;
```

Also update `_save` (around line 1560) to delegate to the helper so the production path and the tested path are byte-identical. Replace the entire `final planChanged = _daysPerWeek != _originalDaysPerWeek || ... !listEquals(_injuries, _originalInjuries);` block with:

```dart
final planChanged = computePlanChanged(
  daysPerWeek: _daysPerWeek,
  originalDaysPerWeek: _originalDaysPerWeek,
  goal: _goal,
  originalGoal: _originalGoal,
  equipment: _equipment,
  originalEquipment: _originalEquipment,
  fitnessExperience: _fitnessExperience,
  originalFitnessExperience: _originalFitnessExperience,
  sessionDuration: _sessionDuration,
  originalSessionDuration: _originalSessionDuration,
  physiqueFocus: _physiqueFocus,
  originalPhysiqueFocus: _originalPhysiqueFocus,
  injuries: _injuries,
  originalInjuries: _originalInjuries,
);
```

- [ ] **Step 2: Create the test file**

Create `test/profile/edit_profile_plan_changed_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/screens/edit_profile_screen.dart';

void main() {
  group('computePlanChanged', () {
    // Baseline: nothing changed.
    bool callWith({
      int daysPerWeek = 4,
      int originalDaysPerWeek = 4,
      String goal = 'build_muscle',
      String originalGoal = 'build_muscle',
      String equipment = 'full_gym',
      String originalEquipment = 'full_gym',
      String fitnessExperience = 'intermediate',
      String originalFitnessExperience = 'intermediate',
      int? sessionDuration = 60,
      int? originalSessionDuration = 60,
      String physiqueFocus = 'balanced',
      String originalPhysiqueFocus = 'balanced',
      List<String> injuries = const ['none'],
      List<String> originalInjuries = const ['none'],
    }) {
      return computePlanChanged(
        daysPerWeek: daysPerWeek,
        originalDaysPerWeek: originalDaysPerWeek,
        goal: goal,
        originalGoal: originalGoal,
        equipment: equipment,
        originalEquipment: originalEquipment,
        fitnessExperience: fitnessExperience,
        originalFitnessExperience: originalFitnessExperience,
        sessionDuration: sessionDuration,
        originalSessionDuration: originalSessionDuration,
        physiqueFocus: physiqueFocus,
        originalPhysiqueFocus: originalPhysiqueFocus,
        injuries: injuries,
        originalInjuries: originalInjuries,
      );
    }

    test('no plan-driving fields changed → false', () {
      expect(callWith(), isFalse);
    });

    test('only experience changed → true', () {
      expect(
        callWith(fitnessExperience: 'advanced'),
        isTrue,
      );
    });

    test('only session duration changed → true', () {
      expect(
        callWith(sessionDuration: 90),
        isTrue,
      );
    });

    test('only physique focus changed → true', () {
      expect(
        callWith(physiqueFocus: 'glutes_legs'),
        isTrue,
      );
    });

    test('only injuries list changed → true', () {
      expect(
        callWith(injuries: const ['none', 'knee']),
        isTrue,
      );
    });

    test('injuries list contents reordered but same set → true (order matters)', () {
      // listEquals is order-sensitive. Profile model never reorders the
      // injuries list at rest, so order-flip should still trigger
      // regen — the saved chips list IS the order. If we wanted a
      // set-equal semantics, we'd switch to Set comparison.
      expect(
        callWith(
          injuries: const ['knee', 'none'],
          originalInjuries: const ['none', 'knee'],
        ),
        isTrue,
      );
    });

    test('session duration null → 60 → true', () {
      expect(
        callWith(sessionDuration: 60, originalSessionDuration: null),
        isTrue,
      );
    });

    test('legacy 4 fields still trigger (regression guard)', () {
      expect(callWith(daysPerWeek: 6), isTrue);
      expect(callWith(goal: 'lose_fat'), isTrue);
      expect(callWith(equipment: 'home_dumbbells'), isTrue);
    });
  });
}
```

- [ ] **Step 3: Run tests**

```bash
flutter test test/profile/edit_profile_plan_changed_test.dart
```

Expect: 8 passed, 0 failed.

- [ ] **Step 4: Run analyze on the touched files**

```bash
flutter analyze lib/features/profile/screens/edit_profile_screen.dart \
                test/profile/edit_profile_plan_changed_test.dart
```

Expect 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/screens/edit_profile_screen.dart \
        test/profile/edit_profile_plan_changed_test.dart
git commit -m "$(cat <<'EOF'
test(profile): unit-test computePlanChanged for 7 plan-driving fields (B-4)

Extracts the planChanged boolean from _save into a top-level
@visibleForTesting helper computePlanChanged so the production widget
and the test call into the same code path. 8 cases pin behavior:
  - no fields changed → false
  - each of 7 fields, isolated → true
  - injuries reorder → true (order-sensitive, intentional)
  - legacy 4-field regression guard

Future expansion (e.g. adding diet_preference to plan-driving inputs)
must add a corresponding test or this guard fires.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-5 — Investigation: OBS-2 6-vs-5-days mismatch

**Files:** `docs/superpowers/notes/2026-04-28-obs2-six-days-investigation.md` (Create) — investigation only, no code.

Goal: rule out (or confirm) a `WorkoutScheduleService` bug separate from B-2.

- [ ] **Step 1: Read the regen entry point**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
grep -n "generateAndScheduleFromDate\|daysPerWeek\|preserveCompleted\|workoutDays\|restDay" lib/core/services/workout_schedule_service.dart | head -40
```

Read `lib/core/services/workout_schedule_service.dart` lines 270-350 (around the `generateAndScheduleFromDate` signature, line 281 per grep).

- [ ] **Step 2: Trace the daysPerWeek=6 path**

Specifically verify:

1. Does `generateAndScheduleFromDate(daysPerWeek: 6, ...)` produce 6 schedule rows in the next 7 days? (Walk the loop bounds.)
2. Does the function preserve already-completed Mon/Tue rows from a pre-existing 5-day plan when regenerating with `daysPerWeek=6`? Or does it wipe and rebuild?
3. If it preserves: does it correctly insert 4 NEW workout rows (since Mon/Tue are kept = 2 existing + 4 new = 6) or does it insert only 3 (kept Mon/Tue + Wed/Thu/Fri = 5)?

- [ ] **Step 3: Cross-check the V4 split resolver**

```bash
grep -n "daysPerWeek\|6\b" lib/shared/repositories/plan_engine/split_resolver.dart | head -20
```

Verify the 6-day split actually returns 6 `MuscleSlotDay` entries (not 5 + a rest stub).

- [ ] **Step 4: Diagnose into one of three branches**

Per spec §4.3:

- **A.** Same root cause as OBS-1 — user changed days_per_week with experience in the same save; pre-B-2 planChanged was true (days IS in the legacy check); user dismissed the dialog ("Keep Current Plan"). Already fixed by B-2's reliability improvement, no service change needed.
- **B.** `WorkoutScheduleService.generateAndScheduleFromDate` doesn't honour `daysPerWeek=6` correctly. Bug in the loop bounds or split-resolver call. Service-layer fix required.
- **C.** The regen logic preserves completed days but inserts only 5 new (rest of week) instead of 6. Bug in the preserved-completed insertion logic. Service-layer fix required.

- [ ] **Step 5: Write findings**

Create `docs/superpowers/notes/2026-04-28-obs2-six-days-investigation.md`:

```markdown
# OBS-2 Investigation — 6-vs-5-Days Mismatch (APK Test #5 Plan B-5)

**Date:** 2026-04-28
**Source observation:** Spec §2 OBS-2.

## Repro context (per OBS-2)
User selected 6 days/week on Edit Profile, saved, schedule strip
showed only 5 workout days that week.

## Code path traced
1. `edit_profile_screen.dart::_save` →
   `WorkoutScheduleService.instance.generateAndScheduleFromDate(...)` →
2. `WorkoutScheduleService.generateAndScheduleFromDate` (line 281) →
   `PlanGenerator.instance.generateV4(...)` →
3. `plan_engine/plan_generator.dart` →
   `split_resolver.dart::resolveSplit(daysPerWeek: 6, ...)` →
   `MuscleSlotDay[6]` ← does this return 6 elements?
4. Schedule writer: writes N `schedule_<date>` keys for N
   workouts in `MuscleSlotDay[]`.

## Findings

[Fill in branch A / B / C diagnosis here. Keep notes from Step 1-3
verbatim — what you saw in each file, with line numbers.]

## Branch chosen
[A / B / C — pick one based on findings.]

## Implication for Plan B
- If A → Task B-6 is empty (delete from plan during execution).
- If B → Task B-6 fixes daysPerWeek loop in WorkoutScheduleService.
- If C → Task B-6 fixes preserved-completed insertion logic.
```

Fill in Steps 1-3 findings + the chosen branch. NO CODE CHANGES this task.

- [ ] **Step 6: Commit the investigation**

```bash
git add docs/superpowers/notes/2026-04-28-obs2-six-days-investigation.md
git commit -m "$(cat <<'EOF'
docs(notes): OBS-2 six-vs-five-days investigation diagnosis (B-5)

APK Test #5 Plan B step 5 (investigation only). Traces
generateAndScheduleFromDate → V4 pipeline → schedule writer for
daysPerWeek=6 input. Diagnoses one of three branches per spec §4.3
(A: already fixed by B-2; B: service loop bug; C: preserved-completed
insertion bug). Drives Task B-6 scope.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-6 — OBS-2 fix (conditional on B-5)

**Files:** `lib/core/services/workout_schedule_service.dart` (Modify, conditional)

Conditional task — execute ONLY if Task B-5 found a service-layer bug. If B-5 chose branch A, this task is a no-op: delete it from the plan during execution and skip to B-7.

- [ ] **Step 1: Branch A — no code, mark closed**

If B-5 chose branch A:

```bash
echo "B-5 chose branch A — already fixed by B-2. No code change for B-6."
```

Skip remaining steps in this task. Proceed to B-7.

- [ ] **Step 2: Branch B — fix the daysPerWeek loop**

If B-5 chose branch B: the bug is in `WorkoutScheduleService.generateAndScheduleFromDate` — the loop that creates `schedule_<date>` rows iterates `daysPerWeek - 1` times instead of `daysPerWeek`, OR calls `split_resolver` with a clamped value.

Read the section flagged in B-5's findings doc. Identify the exact line. Most likely candidates:

- A `for (int i = 0; i < daysPerWeek; i++)` that's `<` vs `<=` confused.
- A `daysPerWeek.clamp(1, 5)` that hardcodes max 5 (would be a leftover from before 6-day was supported).
- A `Phase.workouts.length` bound that's stale.

Apply the surgical fix. Keep the diff minimal — single-line if possible. Add a comment marker:

```dart
// B-6 fix (APK Test #5): <description of root cause>. Pre-fix, daysPerWeek=6
// produced N rows instead of 6.
```

- [ ] **Step 3: Branch C — fix preserved-completed logic**

If B-5 chose branch C: the function preserves already-completed Mon/Tue rows from a pre-existing 5-day plan, then inserts only 3 new workout rows (Wed/Thu/Fri) plus 2 rest rows (Sat/Sun) → 5 workout days, not 6. The fix is to count preserved-completed rows against the new `daysPerWeek` budget correctly.

Pseudocode of the fix:

```dart
// Before:
//   workoutDaysToInsert = daysPerWeek - existingCompleted.length;
//   for (i = 0; i < workoutDaysToInsert; i++) { insert workout }
//   // BUG: this assumes existingCompleted occupy "workout day" slots,
//   // but they may have been from a different daysPerWeek configuration.
//
// After:
//   final remainingWorkoutDays = (daysPerWeek - existingCompleted.length).clamp(0, 7);
//   final remainingCalendarDays = 7 - existingCompleted.length;
//   // Distribute remainingWorkoutDays workouts across remainingCalendarDays
//   // (rest days fill the gap).
//   ...
```

The exact fix depends on B-5's diagnosis. Apply per the notes doc.

- [ ] **Step 4: Verify (branches B + C only)**

```bash
flutter analyze lib/core/services/workout_schedule_service.dart
flutter test test/  # run the full suite — schedule-touching tests live throughout
```

Expect 0 issues + all green.

- [ ] **Step 5: Commit (branches B + C only)**

```bash
git add lib/core/services/workout_schedule_service.dart
git commit -m "$(cat <<'EOF'
fix(schedule): honour daysPerWeek=6 in regen path (B-6)

APK Test #5 Plan B step 6. B-5 investigation diagnosed branch <B|C>:
<one-line root cause from notes doc>. Fix is surgical — <one-line
description of change>. Closes spec C5 success criterion: bumping
days/week 5 → 6 now produces 6 workout rows in the schedule strip.

See docs/superpowers/notes/2026-04-28-obs2-six-days-investigation.md
for the full diagnosis.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-7 — Verification

**Files:** none (read-only verification).

- [ ] **Step 1: Run analyze on touched files**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/features/profile/ lib/core/services/workout_schedule_service.dart
```

Expect 0 issues.

- [ ] **Step 2: Run unit tests for the helper**

```bash
flutter test test/profile/edit_profile_plan_changed_test.dart
```

Expect 8 passed, 0 failed.

- [ ] **Step 3: Run the full test suite**

```bash
flutter test test/
```

Expect 0 failures (existing test count + 8 new from B-4).

- [ ] **Step 4: Manual unit-test simulation for the dialog text**

Add a transient test (or run via `dart` REPL inline) that exercises both criteria:

(i) Profile with experience=intermediate, save with experience=advanced via the helper. Build the changes list using the same conditionals from B-3. Expect the resulting `changes` list to contain `'Experience: Intermediate → Advanced'`.

(ii) Profile with daysPerWeek=5, save with daysPerWeek=6. Stub the call site for `generateAndScheduleFromDate(daysPerWeek: 6, ...)` and assert the produced schedule has 6 workout rows.

If you don't want a transient test, just walk the code paths visually and document which lines you confirmed. (The B-4 helper test plus the B-5 investigation cover the equivalent surface area without on-device verification.)

- [ ] **Step 5: Commit verification (if any new test artifacts created)**

If Step 4 produced a new test file, add + commit:

```bash
git add test/profile/<new-file>.dart
git commit -m "$(cat <<'EOF'
test(profile): manual verification harness for B-7

Verifies dialog text composition + 6-day schedule production end-to-end
for the B-2/B-3 + B-6 fixes. Pure-Dart simulation (no widget tree).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If Step 4 was visual-only, skip the commit and proceed.

---

## Self-review

- [ ] **Spec coverage:** §4.2 surgical fix (4 new fields → planChanged) → B-1/B-2/B-3. §4.3 OBS-2 investigation → B-5. §4.3 OBS-2 conditional fix → B-6. C4 success criterion → B-2/B-3 wire the dialog reliably. C5 success criterion → B-6 (or B-2 if branch A). ✅
- [ ] **Type consistency:** `_originalSessionDuration` is `late int?` (nullable, matches `_sessionDuration`); `_originalPhysiqueFocus` is `late String`; `_originalInjuries` is `late List<String>`. All match the live-state field types. ✅
- [ ] **Placeholder scan:** No TBD/TODO/"fill in" in any committed code. The notes doc in B-5 has a `[Fill in...]` block by design — that's investigation output, not code. ✅
- [ ] **CLAUDE.md compliance:** §15 fire-and-forget pattern at lines 1531-1535 of edit_profile_screen.dart is untouched. The plan's edits are above the sync calls; planChanged dialog blocks AFTER the sync fires (correct order: save first, then offer reschedule). ✅
- [ ] **Risk:** B-2 changes a boolean — easy to revert. B-6 is conditional and only fires if B-5 confirms a service bug. B-1 + B-3 are mechanical refactors with regression coverage in B-4.

## Out of scope for Plan B

- Theme A (cross-account isolation) → Plan A
- Theme C (AI coach tool dispatch) → Plan C
- Theme D (letterhead standardization) → Plan D
- Restructuring the regen confirmation UX (silent auto-regen vs dialog) — separate UX brainstorm if 4.2 isn't sufficient (per spec §4.4).
- Changing `targetCount(experience, daysPerWeek)` table values — out of audit scope (per spec §4.4).
