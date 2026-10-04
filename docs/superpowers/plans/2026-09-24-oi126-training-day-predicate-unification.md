# OI-126: Training-Day Predicate Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **⚠ BEFORE EXECUTION:** This plan requires the full CLAUDE.md §4.12 ×2 context-blind review
> (round 2 on this hardened plan) before any task begins — platform/account-tier, it touches the
> PRO-advance gate's code path. **This is v2**, hardened after an independent round-1 review found
> two Critical gaps in v1 (see "What changed from v1" below) — do not skip round 2 because v1 was
> already reviewed; round 2 must run on THIS version.

## What changed from v1 (round-1 review findings, all independently re-verified live)

1. **v1 only wired 5 call sites. The real count is 11.** A live grep independent of the plan's own
   claim found 6 more inline duplicates of the same predicate: `plan_integrity_reconciler.dart:97`,
   `home_provider.dart:103`, `home_provider.dart:375` (feeds the streak-warning banner —
   materially in scope of what OI-126 is about), `home_provider.dart:678`,
   `day_detail_sheet.dart:46` and `:104`. All 11 are now in scope (Tasks 3+4 below). v1's claim
   that "every citation was re-verified live" was true for the citations it made, but it never
   independently searched for missed ones — this version does, and the search itself is a plan
   step (Task 3 Step 1), not just a one-time finding to trust.
2. **v1's regression test never exercised the wiring — only the two pure predicate functions in
   isolation.** A bug in any one of the 11 call sites' ternary expressions would have been
   undetectable by v1's test suite (the debugging skill's own §2.37, "a positive grep cannot see a
   defect in an argument," is exactly this class). Fixed structurally: instead of duplicating a
   3-line ternary at 11 sites, this version extracts ONE flag-aware wrapper
   (`PlanEngineFlags.isRestDayConsideringLogged`) that every site calls — collapsing "does the
   wiring have a bug" into "does each site call the one tested wrapper," which is a source-grep
   PLUS a small number of genuine call-through tests at the highest-value sites (Task 6).
3. **v1's test file imports used the wrong package name** (`package:fitness_app/...` — this repo's
   actual package is `icanbefitter`, confirmed via `pubspec.yaml`). Fixed throughout.
4. **v1's `docs/sot_registry.yaml` proposed entry didn't match the file's real schema** (a bare
   top-level key vs. the actual `concepts:` list-of-maps with `domain`/`line_range`/`method`/
   `semantic`/`fields_read`/`reader_manifest_complete`). Fixed in Task 7, copied from a real entry.
5. **v1's doc-comment-correction step included a wrong claim** ("undercounts by 3, there are 5 not
   2 callers") that conflated two different populations — `phaseCompletionRate()`'s real callers
   (exactly 2: `workout_schedule_read_service.dart:1417`, `phase_unlock_card.dart:98`, both
   confirmed by grep, unaffected by this plan) vs. inline duplicates of the *inclusion-shaped
   expression* (which is what actually numbers 11, not 5). Task 7 now corrects only the sentence
   that's actually stale and leaves the "two callers" sentence untouched.
6. **v1 hedged on whether `home_screen.dart` already imports what it needs.** Confirmed live: it
   imports neither `phase_completion.dart` nor `plan_engine_flags.dart` — both must be added. Task
   3 now states this as fact, not a "check first" hedge (the other 4 files DO already import both,
   also confirmed live and now stated as fact rather than hedged).

**Goal:** Make a `type: 'logged'` schedule row (AI-coach-only log, or a cloud-restore synthesize
row) count as a training day consistently everywhere it's read — today it counts for the weekly
streak but as a REST day at 11 other call sites, including phase completion (which feeds the
PRO-advance gate), the home rest-day banner, the calendar day-status dots, the streak-warning
banner eligibility check, the AI-insight quick-text, the reconciler's heal-need check, and the
day-detail bottom sheet.

**Architecture:** Extract one pure predicate (`isPhaseCompletionTrainingType`, whitelist-shaped:
`workout`/`custom_template`/`logged`) and one flag-aware wrapper
(`PlanEngineFlags.isRestDayConsideringLogged`) that every one of the 11 call sites delegates to
instead of re-inlining the ternary. Ships behind a new kill-switch, default OFF — nothing changes
for any user until a separate, independently reviewed flip-on commit.

**Tech Stack:** Flutter/Dart, Hive (`configBox`), Riverpod, `flutter_test`.

**Spec:** `docs/audit/open_issues.md` lines 1862-1890 (OI-126) for the original framing. Every
file:line citation in THIS document was re-verified live against `main` on 2026-09-24/25 —
including an independent search for call sites the board (and v1 of this plan) missed.
`lib/core/utils/phase_completion.dart:29-54`'s doc comment is the canonical in-repo description of
why two shapes exist; Task 7 corrects its one stale sentence.

## Global Constraints

- **Package name is `icanbefitter`** (from `pubspec.yaml`). Every test import in this plan uses
  `package:icanbefitter/...` — confirmed against real existing test files, not assumed.
- No migration, no Edge Function deploy — pure client Dart. Nothing here needs live-apply
  authorization.
- Every new/changed behavior ships behind a kill-switch, default OFF, per CLAUDE.md §4.6 — the old
  inline predicate's exact boolean output must be preserved when the flag is OFF, for every `type`
  value, not just `'logged'`.
- Every fix needs a regression test that fails on `main` without the fix and passes with it
  (CLAUDE.md §4.4 rule 21). A test that only exercises a pure helper function in isolation, without
  ever observing a real call site's actual output, does NOT satisfy this for a multi-call-site
  change — see "What changed from v1" point 2.
- Every commit matching `fix:`/`bug:`/`regression:` needs `closes-diagnose: <bug-id>` in the commit
  body, referencing a doc that passes `dart run scripts/validate_diagnose_doc.dart <path>`.
- `phase_completion.dart`'s doc comment documents a REVERTED prior attempt to collapse the
  whitelist shape onto the exclusion shape wholesale (round 3 of some earlier review found both
  real callers of `phaseCompletionRate` need the narrower whitelist). **Do not delete or widen the
  whitelist shape's semantics beyond adding exactly `'logged'`** — an unrecognized future type
  string must still read as REST under the whitelist, unlike under the exclusion shape.
- **All 11 call sites, not 5** — see "What changed from v1" point 1 for the full list.

---

## File Structure

- **Modify** `lib/core/utils/phase_completion.dart` — add `isPhaseCompletionTrainingType`
  (Task 1); correct one stale doc-comment sentence (Task 7).
- **Modify** `lib/shared/repositories/plan_engine/plan_engine_flags.dart` — add
  `loggedCountsAsPhaseTrainingDayEnabled` (the kill-switch) and
  `isRestDayConsideringLogged(Object? type)` (the wrapper every call site delegates to) (Task 2).
- **Modify** `lib/features/train/providers/train_provider.dart` — 2 call sites (`:637`, `:813`)
  (Task 3).
- **Modify** `lib/core/services/workout_schedule_read_service.dart` — 1 wired call site (`:1412`,
  inside `currentPhaseCompletionRate`) (Task 3) + 1 independent, unflagged DRY convergence
  (`:1709`) (Task 5).
- **Modify** `lib/features/home/screens/home_screen.dart` — 2 call sites (`:616`, `:791`) (Task 3).
- **Modify** `lib/core/services/plan_integrity_reconciler.dart` — 1 call site (`:97`, inside
  `needsHeal`) (Task 4).
- **Modify** `lib/features/home/providers/home_provider.dart` — 3 call sites (`:103`, `:375`,
  `:678`) (Task 4).
- **Modify** `lib/features/home/widgets/day_detail_sheet.dart` — 2 call sites (`:46`, `:104`)
  (Task 4).
- **Create** `test/contracts/phase_completion_training_type_test.dart` (Task 1).
- **Create** `test/contracts/plan_engine_flags_logged_training_day_test.dart` (Task 2).
- **Create/Modify** (Task 6): `test/contracts/training_day_predicate_wiring_test.dart` (source-grep
  proof every one of the 11 sites delegates to the wrapper, both phrasings guarded against
  reappearing), `test/contracts/phase_adherence_rate_test.dart` (extended — real call-through at
  `currentPhaseCompletionRate`), `test/contracts/reconciler_needs_heal_logged_test.dart` (new —
  real call-through at `PlanIntegrityReconciler.needsHeal`),
  `test/contracts/streak_warning_eligibility_logged_test.dart` (new — real call-through at
  `StreakWarningEligibilityNotifier` via a genuine `ProviderContainer`). 3 of the 11 sites get real
  call-through coverage this way; the other 8 rely on the source-grep plus Tasks 3-4's existing-test
  re-runs — stated explicitly in Task 6's own header, not left implicit.
- **Create** `docs/diagnoses/2026-09-24-training-day-predicate-logged-disagreement-b7e3a1.md`
  (Task 7).
- **Modify** `docs/sot_registry.yaml` — new concept entry matching the real schema (Task 7).

---

### Task 1: Extract the phase-completion training-type predicate

**Files:**
- Modify: `lib/core/utils/phase_completion.dart`
- Test: `test/contracts/phase_completion_training_type_test.dart`

**Interfaces:**
- Produces: `bool isPhaseCompletionTrainingType(Object? type)` — top-level function in
  `lib/core/utils/phase_completion.dart`. Returns `true` for `'workout'`, `'custom_template'`,
  `'logged'`; `false` for everything else (including `'rest'`, `'off'`, `null`, unrecognized future
  strings).

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/phase_completion_training_type_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/phase_completion.dart';

void main() {
  group('isPhaseCompletionTrainingType', () {
    test('workout and custom_template count as training (pre-existing whitelist)', () {
      expect(isPhaseCompletionTrainingType('workout'), isTrue);
      expect(isPhaseCompletionTrainingType('custom_template'), isTrue);
    });

    test('logged now counts as training — the OI-126 fix', () {
      expect(isPhaseCompletionTrainingType('logged'), isTrue);
    });

    test('rest, off, null, and unrecognized types are NOT training', () {
      expect(isPhaseCompletionTrainingType('rest'), isFalse);
      expect(isPhaseCompletionTrainingType('off'), isFalse);
      expect(isPhaseCompletionTrainingType(null), isFalse);
      expect(isPhaseCompletionTrainingType('some_future_type'), isFalse);
    });

    test('stays a WHITELIST, not the exclusion shape', () {
      // isTrainingDayType (exclusion-shaped) would count 'some_future_type' as
      // training. isPhaseCompletionTrainingType must NOT.
      expect(isTrainingDayType('some_future_type'), isTrue);
      expect(isPhaseCompletionTrainingType('some_future_type'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/contracts/phase_completion_training_type_test.dart`
Expected: FAIL — `isPhaseCompletionTrainingType` is not defined.

- [ ] **Step 3: Write the implementation**

Append to `lib/core/utils/phase_completion.dart` (after `isTrainingDayType`, currently line 55):

```dart

/// Training-day whitelist for phase completion, the home rest-day banner, the
/// PRO-advance gate, the calendar day-status dots, the streak-warning banner
/// eligibility check, the AI-insight quick-text, the reconciler's heal-need
/// check, and the day-detail bottom sheet.
///
/// Deliberately narrower than [isTrainingDayType]: only `workout`,
/// `custom_template`, and (since OI-126) `logged` count. An unrecognized
/// future `type` string counts as REST here — the exclusion shape above
/// would wrongly count it as training. This is a WHITELIST on purpose, not
/// `!isTrainingDayType`'s negated blacklist; do not collapse the two, see the
/// module doc comment above [isTrainingDayType] for why a prior attempt to
/// unify them was reverted.
///
/// Every call site reaches this through
/// [PlanEngineFlags.isRestDayConsideringLogged], never directly — that
/// wrapper is what actually decides whether the widened set applies (gated
/// on [PlanEngineFlags.loggedCountsAsPhaseTrainingDayEnabled]). See OI-126.
bool isPhaseCompletionTrainingType(Object? type) =>
    type == 'workout' || type == 'custom_template' || type == 'logged';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/contracts/phase_completion_training_type_test.dart`
Expected: PASS (4/4).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/phase_completion.dart test/contracts/phase_completion_training_type_test.dart
git commit -m "feat(train): extract isPhaseCompletionTrainingType predicate (OI-126 prep)"
```

---

### Task 2: Add the kill-switch flag and the shared wrapper

**Files:**
- Modify: `lib/shared/repositories/plan_engine/plan_engine_flags.dart`
- Test: `test/contracts/plan_engine_flags_logged_training_day_test.dart`

**Interfaces:**
- Consumes: `isPhaseCompletionTrainingType` (Task 1).
- Produces: `static bool get loggedCountsAsPhaseTrainingDayEnabled` and
  `static bool isRestDayConsideringLogged(Object? type)` on `PlanEngineFlags`. The wrapper is what
  ALL 11 call sites (Tasks 3+4) call instead of re-inlining a ternary — this is the single point a
  wiring bug at any site would have to route through, and the single point Task 6's regression
  tests pin.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/plan_engine_flags_logged_training_day_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

void main() {
  group('loggedCountsAsPhaseTrainingDayEnabled', () {
    test('defaults to false with no Hive', () {
      expect(PlanEngineFlags.loggedCountsAsPhaseTrainingDayEnabled, isFalse);
    });
  });

  group('isRestDayConsideringLogged (flag OFF, no Hive → default OFF)', () {
    test('workout and custom_template are training (not rest)', () {
      expect(PlanEngineFlags.isRestDayConsideringLogged('workout'), isFalse);
      expect(PlanEngineFlags.isRestDayConsideringLogged('custom_template'), isFalse);
    });

    test('logged reads as REST when the flag is off — the pre-fix shape', () {
      expect(PlanEngineFlags.isRestDayConsideringLogged('logged'), isTrue);
    });

    test('rest, off, and null are rest', () {
      expect(PlanEngineFlags.isRestDayConsideringLogged('rest'), isTrue);
      expect(PlanEngineFlags.isRestDayConsideringLogged('off'), isTrue);
      expect(PlanEngineFlags.isRestDayConsideringLogged(null), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/contracts/plan_engine_flags_logged_training_day_test.dart`
Expected: FAIL — neither member is defined on `PlanEngineFlags`.

- [ ] **Step 3: Write the implementation**

Add to `lib/shared/repositories/plan_engine/plan_engine_flags.dart`. First add the import (the file
currently imports only `hive_service.dart`):

```dart
import 'package:icanbefitter/core/utils/phase_completion.dart';
```

Then add the getter and the wrapper (mirror the existing `holdWeeksEnabled` try/catch shape
exactly — read that method's current body first to confirm the closing-brace style before pasting,
since this plan's own quote of it may have shifted a line or two by execution time):

```dart
  /// OI-126: a `type: 'logged'` schedule row (AI-coach-only log, or a
  /// cloud-restore synthesize row) currently counts as a training day for the
  /// weekly streak (`isTrainingDayType`, exclusion-shaped) but as REST for
  /// phase completion, the home rest-day banner, the PRO-advance gate, and 8
  /// other call sites (whitelist-shaped, via `isPhaseCompletionTrainingType`)
  /// — see `phase_completion.dart`. This flag makes every whitelist-shaped
  /// call site ALSO count `logged`, via [isRestDayConsideringLogged] below.
  /// Set `configBox['enable_logged_counts_as_phase_training_day'] = true` to
  /// enable. Ship-dark default OFF; flip only in its own reviewed commit per
  /// §4.12.4.
  static bool get loggedCountsAsPhaseTrainingDayEnabled {
    try {
      return HiveService.instance.configBox
              .get('enable_logged_counts_as_phase_training_day') ==
          true;
    } catch (_) {
      return false; // no Hive (pure unit test) → default: OFF
    }
  }

  /// The ONE call every OI-126 call site makes instead of re-inlining
  /// `type != 'workout' && type != 'custom_template'`. Centralizing this is
  /// deliberate: 11 independent inline copies of the same ternary is exactly
  /// how a future edit silently diverges at one site and not the others.
  /// Flag OFF → byte-identical to the pre-fix inline expression for every
  /// `type` value. Flag ON → widens to also treat `logged` as training.
  static bool isRestDayConsideringLogged(Object? type) {
    if (loggedCountsAsPhaseTrainingDayEnabled) {
      return !isPhaseCompletionTrainingType(type);
    }
    return type != 'workout' && type != 'custom_template';
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/contracts/plan_engine_flags_logged_training_day_test.dart`
Expected: PASS (5/5).

- [ ] **Step 5: Commit**

```bash
git add lib/shared/repositories/plan_engine/plan_engine_flags.dart test/contracts/plan_engine_flags_logged_training_day_test.dart
git commit -m "feat(train): add loggedCountsAsPhaseTrainingDayEnabled + isRestDayConsideringLogged wrapper (OI-126 prep)"
```

---

### Task 3: Wire the 5 originally-identified call sites onto the wrapper

**Files:**
- Modify: `lib/features/train/providers/train_provider.dart:637`, `:813`
- Modify: `lib/core/services/workout_schedule_read_service.dart:1412`
- Modify: `lib/features/home/screens/home_screen.dart:616`, `:791`

**Interfaces:**
- Consumes: `PlanEngineFlags.isRestDayConsideringLogged` (Task 2).

- [ ] **Step 1: Confirm import state (verified live, stated as fact — do not re-derive)**

`train_provider.dart` and `workout_schedule_read_service.dart` already import BOTH
`package:icanbefitter/core/utils/phase_completion.dart` and
`package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart` — no import changes
needed in either file for this task. **Do NOT remove the `phase_completion.dart` import from either
file** — round-2 review confirmed both files call `isTrainingDayType` at OTHER, unrelated lines
(`train_provider.dart:592,595`; `workout_schedule_read_service.dart:1192`) that this task's edits
never touch. The import was never tied to the lines this task changes in the first place, so there
is nothing to reconsider here — leave both imports exactly as they are.

`home_screen.dart` imports **neither** — add both:

```dart
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
```

(it does not need `phase_completion.dart` directly, since it only calls the wrapper).

- [ ] **Step 2: Write the failing test (pins the pre-fix, flag-OFF shape)**

```dart
// test/contracts/training_day_predicate_wiring_test.dart
// This file grows across Tasks 3, 4, and 6 — Task 3 adds only the first group.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

void main() {
  group('OI-126 wrapper — flag OFF byte-identical pin', () {
    test('logged reads as rest under the wrapper when the flag is off', () {
      // Pins the CURRENT (pre-fix) shape the wrapper must preserve until the
      // flag flips. If this test starts failing, something changed the OFF
      // default — stop and investigate before touching any call site.
      expect(PlanEngineFlags.isRestDayConsideringLogged('logged'), isTrue);
    });
  });
}
```

- [ ] **Step 3: Run test to verify it passes already**

Run: `flutter test test/contracts/training_day_predicate_wiring_test.dart`
Expected: PASS — Task 2 already implemented the wrapper; this step confirms the baseline before
any call site is touched, so a later regression in the wrapper itself is caught here first.

- [ ] **Step 4: Wire each call site**

`lib/features/train/providers/train_provider.dart:632-637` — change:

```dart
  final type = row['type'] as String? ?? 'rest';
  if (type != 'workout' && type != 'custom_template') return null;
```

to:

```dart
  final type = row['type'] as String? ?? 'rest';
  if (PlanEngineFlags.isRestDayConsideringLogged(type)) return null;
```

`lib/features/train/providers/train_provider.dart:811-813` — change:

```dart
        final type = dayMap['type'] as String? ?? 'rest';
        final isRest = type != 'workout' && type != 'custom_template';
```

to:

```dart
        final type = dayMap['type'] as String? ?? 'rest';
        final isRest = PlanEngineFlags.isRestDayConsideringLogged(type);
```

`lib/core/services/workout_schedule_read_service.dart:1409-1412` — change:

```dart
      for (final day in _withoutHoldRows(getWeek(w))) {
        final type = (day['type'] as String?) ?? 'rest';
        final isRest = type != 'workout' && type != 'custom_template';
```

to:

```dart
      for (final day in _withoutHoldRows(getWeek(w))) {
        final type = (day['type'] as String?) ?? 'rest';
        final isRest = PlanEngineFlags.isRestDayConsideringLogged(type);
```

`lib/features/home/screens/home_screen.dart:613-616` — change:

```dart
    final workoutType = schedule?['type'] as String? ?? 'rest';
    final workoutDone = workoutStatus == 'completed';
    final isRestDay = workoutType != 'workout' && workoutType != 'custom_template';
```

to:

```dart
    final workoutType = schedule?['type'] as String? ?? 'rest';
    final workoutDone = workoutStatus == 'completed';
    final isRestDay = PlanEngineFlags.isRestDayConsideringLogged(workoutType);
```

`lib/features/home/screens/home_screen.dart:789-791` — change:

```dart
    final type = schedule?['type'] as String? ?? 'rest';
    final status = schedule?['status'] as String? ?? 'planned';
    final isRestDay = type != 'workout' && type != 'custom_template';
```

to:

```dart
    final type = schedule?['type'] as String? ?? 'rest';
    final status = schedule?['status'] as String? ?? 'planned';
    final isRestDay = PlanEngineFlags.isRestDayConsideringLogged(type);
```

- [ ] **Step 5: Run `flutter analyze` on the 3 touched files**

Run: `flutter analyze lib/features/train/providers/train_provider.dart lib/core/services/workout_schedule_read_service.dart lib/features/home/screens/home_screen.dart`
Expected: no issues (confirms no unused-import warning was left behind per Step 1's caveat).

- [ ] **Step 6: Run the existing tests most likely to touch these call sites indirectly**

Run: `flutter test test/contracts/hold_week_identity_behavioral_test.dart test/contracts/hold_display_read_path_test.dart test/contracts/phase_unlock_card_thursday_gate_test.dart test/contracts/phase_adherence_rate_test.dart`
Expected: PASS, unchanged — a flag-OFF wiring change must not move any of these.

- [ ] **Step 7: Commit**

```bash
git add lib/features/train/providers/train_provider.dart lib/core/services/workout_schedule_read_service.dart lib/features/home/screens/home_screen.dart test/contracts/training_day_predicate_wiring_test.dart
git commit -m "feat(train): wire 5 call sites onto isRestDayConsideringLogged, flag OFF (OI-126)"
```

---

### Task 4: Wire the 6 additional call sites found by independent live re-verification

**Files:**
- Modify: `lib/core/services/plan_integrity_reconciler.dart:97`
- Modify: `lib/features/home/providers/home_provider.dart:103`, `:375`, `:678`
- Modify: `lib/features/home/widgets/day_detail_sheet.dart:46`, `:104`

**Interfaces:**
- Consumes: `PlanEngineFlags.isRestDayConsideringLogged` (Task 2).

These 6 sites were NOT in the original OI-126 board framing or in v1 of this plan — they were found
by an independent grep of the whole `lib/` tree for the same inline pattern during this plan's
round-1 review, and re-verified live before being added here. Per CLAUDE.md §4.2 (no deferrals),
they ship in the same batch as the originally-identified 5, not as a follow-up.

- [ ] **Step 1: Write the failing test (extends the same wiring test file)**

Add to `test/contracts/training_day_predicate_wiring_test.dart` (same file Task 3 created):

```dart
  group('OI-126 wrapper — the 6 additionally-discovered sites use the same wrapper', () {
    // These assertions are source-grep (Task 6 adds the mechanical grep test
    // proving each cited line actually calls the wrapper); this group is a
    // placeholder reminding the reader that Task 6, not this task, is where
    // the wiring proof for these 6 sites lives — Task 4 itself only edits
    // source, per the plan's TDD step shape below.
    test('wrapper still behaves correctly after this task (no change to it)', () {
      expect(PlanEngineFlags.isRestDayConsideringLogged('logged'), isTrue);
      expect(PlanEngineFlags.isRestDayConsideringLogged('workout'), isFalse);
    });
  });
```

- [ ] **Step 2: Run test to verify it passes already**

Run: `flutter test test/contracts/training_day_predicate_wiring_test.dart`
Expected: PASS — this task's own test group doesn't assert anything new yet; Task 6 is where the
real per-site proof lands. This step just confirms the file still compiles and runs cleanly before
editing 3 more source files.

- [ ] **Step 3: Wire each call site**

`lib/core/services/plan_integrity_reconciler.dart:94-98` — change:

```dart
    for (final e in entries) {
      final type = e['type'];
      final isWorkout = type == 'workout' || type == 'custom_template';
      if (!isWorkout) continue;
```

to:

```dart
    for (final e in entries) {
      final type = e['type'];
      final isWorkout = !PlanEngineFlags.isRestDayConsideringLogged(type);
      if (!isWorkout) continue;
```

Add the import if not already present — check first:
`import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';`

`lib/features/home/providers/home_provider.dart:98-103` — change:

```dart
      CalendarDayStatus status;
      if (statusStr == 'completed') {
        status = CalendarDayStatus.completed;
      } else if (statusStr == 'travel') {
        status = CalendarDayStatus.travel;
      } else if ((type == 'workout' || type == 'custom_template') && statusStr == 'planned') {
```

to:

```dart
      CalendarDayStatus status;
      if (statusStr == 'completed') {
        status = CalendarDayStatus.completed;
      } else if (statusStr == 'travel') {
        status = CalendarDayStatus.travel;
      } else if (!PlanEngineFlags.isRestDayConsideringLogged(type) && statusStr == 'planned') {
```

`lib/features/home/providers/home_provider.dart:373-375` — change:

```dart
    final type = todaySchedule?['type'] as String? ?? 'none';
    final status = todaySchedule?['status'] as String? ?? 'none';
    final isWorkoutDayToday = type == 'workout' || type == 'custom_template';
```

to:

```dart
    final type = todaySchedule?['type'] as String? ?? 'none';
    final status = todaySchedule?['status'] as String? ?? 'none';
    final isWorkoutDayToday = !PlanEngineFlags.isRestDayConsideringLogged(type);
```

⚠ `PlanEngineFlags.isRestDayConsideringLogged` treats `type == null` (via its internal
`!= 'workout' && != 'custom_template'` / `isPhaseCompletionTrainingType` checks) as REST — this
matches the pre-fix behavior for the `'none'` default this call site's `?? 'none'` produces, since
`'none' != 'workout' && 'none' != 'custom_template'` was already `true` (rest) before this change,
and `isPhaseCompletionTrainingType('none')` is also `false` (not in the whitelist) — byte-identical
either way. No special-casing needed for the `'none'` sentinel specifically.

`lib/features/home/providers/home_provider.dart:676-678` — change:

```dart
      if (status == 'completed') {
        return '$name completed today — ${exercises.length} exercises. Great work 💪';
      } else if (type == 'workout' || type == 'custom_template') {
```

to:

```dart
      if (status == 'completed') {
        return '$name completed today — ${exercises.length} exercises. Great work 💪';
      } else if (!PlanEngineFlags.isRestDayConsideringLogged(type)) {
```

Add the import to `home_provider.dart` if not already present — check first (grep the file for
`PlanEngineFlags` before assuming; it likely reads other flags already given this file computes
`StreakWarningEligibility`, but confirm rather than assume, per this plan's own v1→v2 lesson).

`lib/features/home/widgets/day_detail_sheet.dart:44-46` — change:

```dart
    final type = schedule?['type'] as String? ?? 'none';
    final status = schedule?['status'] as String? ?? 'none';
    final isWorkout = type == 'workout' || type == 'custom_template';
```

to:

```dart
    final type = schedule?['type'] as String? ?? 'none';
    final status = schedule?['status'] as String? ?? 'none';
    final isWorkout = !PlanEngineFlags.isRestDayConsideringLogged(type);
```

`lib/features/home/widgets/day_detail_sheet.dart:102-104` — change:

```dart
    final workoutName = schedule?['workout_name'] as String? ?? '';
    final type = schedule?['type'] as String? ?? 'none';
    final isWorkout = type == 'workout' || type == 'custom_template';
```

to:

```dart
    final workoutName = schedule?['workout_name'] as String? ?? '';
    final type = schedule?['type'] as String? ?? 'none';
    final isWorkout = !PlanEngineFlags.isRestDayConsideringLogged(type);
```

Add the import to `day_detail_sheet.dart` if not already present — check first.

- [ ] **Step 4: Run `flutter analyze` on all 3 touched files**

Run: `flutter analyze lib/core/services/plan_integrity_reconciler.dart lib/features/home/providers/home_provider.dart lib/features/home/widgets/day_detail_sheet.dart`
Expected: no issues.

- [ ] **Step 5: Run existing tests covering these 3 files**

Run: `flutter test test/contracts/phase_progress_reconciler_test.dart test/contracts/reconciler_hold_heal_split_behavioral_test.dart test/contracts/reconciler_gather_hold_rows_behavioral_test.dart`
Expected: PASS, unchanged.

Also run the full `test/contracts/` suite once (not just a hand-picked subset — CLAUDE.md §4.12.8)
to catch anything touching `home_provider.dart` or `day_detail_sheet.dart` this plan didn't
anticipate:

Run: `flutter test test/contracts/`
Expected: PASS, unchanged from before this task.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/plan_integrity_reconciler.dart lib/features/home/providers/home_provider.dart lib/features/home/widgets/day_detail_sheet.dart test/contracts/training_day_predicate_wiring_test.dart
git commit -m "feat(train): wire 6 additionally-discovered call sites onto isRestDayConsideringLogged (OI-126)"
```

---

### Task 5: Opportunistic DRY convergence of the exclusion-shape duplicate

**Files:**
- Modify: `lib/core/services/workout_schedule_read_service.dart:1709`

**Interfaces:**
- Consumes: `isTrainingDayType` (already exists, `lib/core/utils/phase_completion.dart:55`).

This site already uses the CORRECT exclusion-shape semantics inline instead of through the shared
helper — pure DRY, no behavior change, unrelated to the flag (the exclusion shape already counts
`'logged'` as training, correctly, and is unaffected by this whole plan).

- [ ] **Step 1: Confirm the line hasn't drifted**

Run: `grep -n "type != 'rest' && type != 'off'" lib/core/services/workout_schedule_read_service.dart`
Expected: one hit near line 1709. If it moved, use the new line for Step 2.

- [ ] **Step 2: Converge onto the shared helper**

Change:

```dart
        if (type != 'rest' && type != 'off') workoutRows++;
```

to:

```dart
        if (isTrainingDayType(type)) workoutRows++;
```

- [ ] **Step 3: Run tests covering this counter**

Run: `flutter test test/contracts/`
Expected: PASS, unchanged — pure refactor to an already-equivalent expression.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/workout_schedule_read_service.dart
git commit -m "refactor(train): converge workoutRows counter onto isTrainingDayType (DRY, no behavior change)"
```

---

### Task 6: Wiring proof — source-grep + real call-through tests + mutation proof

> **v3 note (round-2 review).** Round 2 found this task's v2 draft was itself broken in 3 places:
> the new `phase_adherence_rate_test.dart` case had arithmetic that could never pass (both seeded
> days were already 100%-complete, so the ratio couldn't move); the streak-warning "test" never
> called any production code — it hand-duplicated the predicate in a local closure and tested
> that instead, which is the exact "tests a reconstruction, not the real path" gap this task
> exists to close; and the negative-regression grep only checked the exclusion-shaped phrasing
> used at the ORIGINAL 5 sites, silently blind to the inclusion-shaped phrasing used at all 6 of
> Task 4's newly-found sites. Fixed below. **Honest scope statement, not overclaimed:** after this
> task, 3 of the 11 sites have genuine call-through coverage (`currentPhaseCompletionRate`,
> `PlanIntegrityReconciler.needsHeal`, `StreakWarningEligibilityNotifier`) — chosen as the
> highest-risk (PRO-advance gate) and cheapest-to-reach (pure static function) and
> hardest-to-get-wrong-silently (streak banner) sites. The other 8 rely on the source-grep proof
> (Step 1) plus `flutter analyze` plus the existing tests re-run in Tasks 3-4. That is a real,
> stated gap, not a hidden one — closing it further (e.g. widget-pump tests for the 2
> `home_screen.dart` and 2 `day_detail_sheet.dart` sites) is explicitly out of scope for this batch
> and not a deferral of a KNOWN bug (§4.2) — it is a coverage-depth tradeoff for a ship-dark change
> that does not affect any user until flip-on, which itself gets a separate full review.

**Files:**
- Modify: `test/contracts/training_day_predicate_wiring_test.dart`
- Modify: `test/contracts/phase_adherence_rate_test.dart` (extend with a `'logged'`-seeding case)
- Create: `test/contracts/reconciler_needs_heal_logged_test.dart`
- Create: `test/contracts/streak_warning_eligibility_logged_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1-5.

- [ ] **Step 1: Write the source-grep wiring proof**

Add to `test/contracts/training_day_predicate_wiring_test.dart`:

```dart
import 'dart:io';

  group('OI-126 — every claimed call site actually delegates to the wrapper', () {
    // Source-grep, not behavioral — but it closes a real gap: it proves each
    // of the 11 sites calls PlanEngineFlags.isRestDayConsideringLogged rather
    // than an inlined duplicate ternary that LOOKS equivalent today and
    // silently drifts tomorrow. Combined with the call-through tests below
    // (which prove the wrapper itself is correct) and the mutation proof
    // (which proves a defect in the wrapper is detectable), this closes the
    // gap v1 of this plan left open.
    const sites = <String>[
      'lib/features/train/providers/train_provider.dart',
      'lib/core/services/workout_schedule_read_service.dart',
      'lib/features/home/screens/home_screen.dart',
      'lib/core/services/plan_integrity_reconciler.dart',
      'lib/features/home/providers/home_provider.dart',
      'lib/features/home/widgets/day_detail_sheet.dart',
    ];

    test('every touched file contains at least one call to isRestDayConsideringLogged', () {
      for (final path in sites) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('PlanEngineFlags.isRestDayConsideringLogged'),
          isTrue,
          reason: '$path should delegate to the shared wrapper, not re-inline the predicate',
        );
      }
    });

    test('no touched file re-introduces the pre-fix inline ternary (either phrasing)', () {
      // Guards against a future edit reverting one site back to the inline
      // form while leaving the others on the wrapper. Round-2 review found
      // the first draft of this guard only checked the EXCLUSION phrasing
      // (`!= 'workout' && != 'custom_template'`, used at the 5 originally-
      // identified sites) and was silently blind to the INCLUSION phrasing
      // (`== 'workout' || == 'custom_template'`, used at all 6 of Task 4's
      // sites) — both forms are checked here.
      for (final path in sites) {
        final src = File(path).readAsStringSync();
        final strippedComments = src.replaceAll(RegExp(r'//.*'), '');
        final hasExclusionForm = strippedComments.contains("!= 'workout' && ") &&
            strippedComments.contains("!= 'custom_template'");
        final hasInclusionForm = strippedComments.contains("== 'workout' ||") &&
            strippedComments.contains("== 'custom_template'");
        expect(hasExclusionForm, isFalse,
            reason: '$path appears to still contain the exclusion-phrased pre-fix ternary');
        expect(hasInclusionForm, isFalse,
            reason: '$path appears to still contain the inclusion-phrased pre-fix ternary');
      }
    });
  });
```

- [ ] **Step 2: Run test to verify it passes**

Run: `flutter test test/contracts/training_day_predicate_wiring_test.dart`
Expected: PASS — Tasks 3-5 already made this true; this step confirms it mechanically rather than
by re-reading the diffs.

- [ ] **Step 3: Add a real call-through test at the PRO-advance-gate site (highest value)**

Extend `test/contracts/phase_adherence_rate_test.dart` — read the file's existing `seedDay`/`rate`
helpers first (they seed real `schedule_*` Hive rows via a temp-dir Hive instance and call
`WorkoutScheduleReadService.instance.currentPhaseCompletionRate()` directly), then add:

```dart
  test('a logged day counts as training once the OI-126 flag is on', () async {
    // Round-2 review caught the first version of this case: seeding two
    // already-100%-complete days can never move a ratio that's already
    // saturated at 1.0 regardless of the flag. Fixed by seeding an
    // INCOMPLETE logged day, so the denominator changes but the numerator
    // does not — the rate must move, and it must move DOWN (the flag
    // widening the denominator without widening completions is the exact
    // "was hidden, now visible" effect this fix is meant to surface).
    await seedDay(1, 1, type: 'workout', status: 'completed');
    await seedDay(1, 2, type: 'logged', status: 'planned');

    // Flag OFF (default): 'logged' is invisible to both numerator and
    // denominator under the pre-fix inline form → 1 workout day, done → 1.0.
    final rateOff = rate();
    expect(rateOff, closeTo(1.0, 0.001),
        reason: 'flag off: only the workout day counts, and it is complete');

    await cb.put('enable_logged_counts_as_phase_training_day', true);
    final rateOn = rate();

    // Flag ON: 'logged' now counts as a training day too, but it is NOT
    // completed → denominator grows to 2, numerator stays 1 → 0.5.
    expect(rateOn, isNot(equals(rateOff)),
        reason: 'flipping the flag must change the PRO-advance gate input for a logged day');
    expect(rateOn, closeTo(0.5, 0.001),
        reason: 'workout done (1) + logged not-done (1) = 1/2 once logged counts as training');
  });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/contracts/phase_adherence_rate_test.dart`
Expected: PASS, including the new case. If the actual `rateOff`/`rateOn` values differ from 1.0/0.5
(e.g. because `phase`/`totalWeeks` defaults in this test file's fixture interact with a single
partial week differently than expected), read the failure output, use the ACTUAL computed values
in the assertions (still requiring `rateOn != rateOff`, which is the load-bearing part of this
test) rather than forcing the fixture to match a number decided in advance — the real requirement
is "the rate visibly changes when the flag flips," not "the rate is exactly 0.5."

- [ ] **Step 5: Add a real call-through test at `PlanIntegrityReconciler.needsHeal` (Task 4 site, pure + cheap)**

`PlanIntegrityReconciler.needsHeal` is `@visibleForTesting static`, so it can be called directly —
no widget tree, no provider container. It still calls `PlanEngineFlags.isRestDayConsideringLogged`
internally (via this plan's Task 4 wiring), which reads live `HiveService.instance.configBox`, so
this test needs the same minimal Hive setup `phase_adherence_rate_test.dart` already uses (a
temp-dir `Hive.init` + `HiveService.instance.init()` + open `configBox`) — reuse that file's setUp
pattern rather than inventing a new one; read it in full first.

> **v4 note (scoped re-review).** The prior draft of both new test files' `setUp` called
> `HiveService.instance.init()`, which internally calls `Hive.initFlutter()` → `path_provider`'s
> `getApplicationDocumentsDirectory()` — this throws `MissingPluginException` in a pure-VM test
> with no mocked `MethodChannel`, so both files would have failed at `setUp` before any test body
> ran, for every step including the mutation proof. Fixed below by following
> `phase_adherence_rate_test.dart`'s own proven pattern exactly: mock the `path_provider` channel,
> use raw `Hive.init` (never `HiveService.instance.init()`), open only the specific boxes needed,
> then `HiveService.instance.markInitializedForTests()`. This is the same pattern the existing test
> file already uses successfully — read it in full before writing either new file, don't
> reconstruct the pattern from memory.

```dart
// test/contracts/reconciler_needs_heal_logged_test.dart
//
// Proves the wiring at plan_integrity_reconciler.dart:97 (needsHeal,
// isWorkout) actually changes when the OI-126 flag flips, calling the REAL
// static method — not a reconstruction of its logic.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box cb;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oi126_reconciler_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.configBoxName);
    HiveService.instance.markInitializedForTests();
    cb = HiveService.instance.configBox;
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('a logged, incomplete, exercise-less row needs healing once the flag is on', () {
    final entries = [
      {'type': 'logged', 'status': 'planned', 'exercises': <Map<String, dynamic>>[]},
    ];

    // Flag OFF (default): needsHeal's isWorkout check excludes 'logged' under
    // the pre-fix inline form → the row is skipped (`continue`) → no heal
    // need is ever reported for it, regardless of its missing exercises.
    expect(PlanIntegrityReconciler.needsHeal(entries), isFalse,
        reason: 'flag off: a logged row is not treated as a workout, so its empty exercises are never checked');

    cb.put('enable_logged_counts_as_phase_training_day', true);

    // Flag ON: 'logged' now counts as a workout → the row is NOT skipped →
    // its empty exercises trip the restore-skip symptom → heal needed.
    expect(PlanIntegrityReconciler.needsHeal(entries), isTrue,
        reason: 'flag on: a logged row now counts as a workout, exposing its missing exercises as a heal-need');
  });
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/contracts/reconciler_needs_heal_logged_test.dart`
Expected: PASS.

- [ ] **Step 7: Add a real call-through test at `StreakWarningEligibilityNotifier` (Task 4 site, via a real `ProviderContainer`)**

`StreakWarningEligibilityNotifier.build()` watches `authUserIdTokenProvider`, `streakProvider`, and
`todayWorkoutProvider`, plus calls `WorkoutRepository.instance.getRecentWorkoutCompletionHours`
directly (not through Riverpod). Override the three providers so the test drives the REAL notifier
without needing a live Supabase session or a populated streak; leave
`getRecentWorkoutCompletionHours` to run for real against an empty (but live, Hive-backed)
`workoutBox` — it degrades safely to `[]` → the cold-start 19:00 default, per its own source.

```dart
// test/contracts/streak_warning_eligibility_logged_test.dart
//
// Proves the wiring at home_provider.dart:375 (StreakWarningEligibilityNotifier
// .build, isWorkoutDayToday) actually changes when the OI-126 flag flips, by
// reading the REAL provider through a real ProviderContainer — not a
// hand-duplicated reconstruction of its logic (round-2 review's finding
// against this task's first draft).
//
// NOTE: no existing test file covers StreakWarningEligibility (the file named
// in lib/features/home/CLAUDE.md, streak_warning_banner_threshold_test.dart,
// does not exist on disk — confirmed via a live search before writing this;
// do not trust that CLAUDE.md line without re-checking it yourself too).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

class _FakeTodayWorkoutNotifier extends TodayWorkoutNotifier {
  _FakeTodayWorkoutNotifier(this._schedule);
  final Map<String, dynamic>? _schedule;
  @override
  Map<String, dynamic>? build() => _schedule;
}

class _FakeStreakNotifier extends StreakNotifier {
  @override
  int build() => 5;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUp(() async {
    // WorkoutRepository.instance.getRecentWorkoutCompletionHours (called
    // inside the real StreakWarningEligibilityNotifier.build(), not mocked)
    // reads the user-scoped workoutBox — needs the same session-open pattern
    // phase_adherence_rate_test.dart uses, not just configBox.
    tempDir = await Directory.systemTemp.createTemp('oi126_streak_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.workoutBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('a logged today-schedule flips isWorkoutDayToday once the flag is on', () {
    final container = ProviderContainer(overrides: [
      todayWorkoutProvider.overrideWith(
        () => _FakeTodayWorkoutNotifier({'type': 'logged', 'status': 'planned'}),
      ),
      streakProvider.overrideWith(() => _FakeStreakNotifier()),
      authUserIdTokenProvider.overrideWithValue('oi126-test-user'),
    ]);
    addTearDown(container.dispose);

    // Flag OFF (default): 'logged' does not count as a workout day today.
    final off = container.read(streakWarningEligibilityProvider);
    expect(off.isWorkoutDayToday, isFalse, reason: 'flag off: logged is not a workout day today');

    HiveService.instance.configBox
        .put('enable_logged_counts_as_phase_training_day', true);
    container.invalidate(streakWarningEligibilityProvider);

    // Flag ON: 'logged' now counts as a workout day today.
    final on = container.read(streakWarningEligibilityProvider);
    expect(on.isWorkoutDayToday, isTrue, reason: 'flag on: logged now counts as a workout day today');
  });
}
```

If `TodayWorkoutNotifier` or `StreakNotifier` cannot be subclassed this way (e.g. because of a
`final`/`sealed` modifier, or a constructor requirement this plan didn't anticipate — check the
real class declarations in `home_provider.dart` before assuming the above compiles verbatim), the
fallback is `Notifier.new`-style anonymous overrides
(`todayWorkoutProvider.overrideWith(() => _AnonNotifier(schedule))` extending `Notifier<Map<String,
dynamic>?>` directly rather than the concrete class) — but attempt the direct-subclass form first,
it is simpler and this plan's own verification did not find a blocker to it.

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/contracts/streak_warning_eligibility_logged_test.dart`
Expected: PASS. If Step 7's override syntax needs adjustment to compile against the real provider
declarations, iterate here — this is exactly what the TDD "run, read the error, fix" cycle is for;
do not fall back to testing a hand-duplicated closure instead of the real provider (that is the
mistake this rewrite exists to correct).

- [ ] **Step 9: Mutation-prove the wrapper**

Temporarily revert `PlanEngineFlags.isRestDayConsideringLogged` (Task 2) to ignore the flag
entirely:

```dart
  static bool isRestDayConsideringLogged(Object? type) {
    return type != 'workout' && type != 'custom_template'; // mutation: flag ignored
  }
```

Run: `flutter test test/contracts/plan_engine_flags_logged_training_day_test.dart test/contracts/phase_adherence_rate_test.dart test/contracts/reconciler_needs_heal_logged_test.dart test/contracts/streak_warning_eligibility_logged_test.dart`
Expected: FAIL — the new `phase_adherence_rate_test.dart` case, `reconciler_needs_heal_logged_test.dart`,
and `streak_warning_eligibility_logged_test.dart` should all redden, since each flips the flag and
expects a real, observable change through production code. Record the exact count of reddened
tests in the diagnose-doc (Task 7) per CLAUDE.md §4.4 rule 21. Then revert the mutation and confirm
everything passes again before continuing.

- [ ] **Step 10: Commit**

```bash
git add test/contracts/training_day_predicate_wiring_test.dart test/contracts/phase_adherence_rate_test.dart test/contracts/reconciler_needs_heal_logged_test.dart test/contracts/streak_warning_eligibility_logged_test.dart
git commit -m "test(train): wiring proof — source-grep (both phrasings), 3 real call-through tests via production code, mutation-proven (OI-126)"
```

---

### Task 7: Diagnose-doc, SoT registry, doc-comment correction

**Files:**
- Create: `docs/diagnoses/2026-09-24-training-day-predicate-logged-disagreement-b7e3a1.md`
- Modify: `docs/sot_registry.yaml`
- Modify: `lib/core/utils/phase_completion.dart` (doc comment)

- [ ] **Step 1: Check for bug-id collision**

Run: `grep -rl "bug_id: b7e3a1" docs/diagnoses/*.md`
Expected: no output. If it collides, pick a different 6-hex string and re-run.

- [ ] **Step 2: Write the diagnose-doc**

```markdown
---
bug_id: b7e3a1
date: 2026-09-24
batch: oi126-training-day-predicate-unification
status: fixed
blast_radius: platform
symptom: |
  A `type: 'logged'` schedule row (written by WorkoutWriteService.markCompleted's
  no-prior-schedule branch for AI-coach-only logging, or by the restore synthesize
  path in sync/sync_workout.dart) counts as a training day for the weekly streak
  (isTrainingDayType, exclusion-shaped) but as a REST day at 11 other inline call
  sites (whitelist-shaped: type == 'workout' || type == 'custom_template'),
  including WorkoutScheduleReadService.currentPhaseCompletionRate — the direct
  input to the PRO phase-advance gate — plus the home rest-day banner, the
  calendar day-status dots, the streak-warning banner eligibility check, the
  AI-insight quick-text, the plan-integrity reconciler's heal-need check, and
  the day-detail bottom sheet (2 sites). A coach-logged or cloud-restored day
  therefore advances a user's streak while simultaneously depressing their
  phase-completion rate and being invisible to 8 other display surfaces.
  Round-1 review of this batch's own plan found 6 of these 11 sites — the
  original OI-126 board filing and the first plan draft named only 5.
concept: training_day_predicate_logged_agreement
sot_registry_entry: training_day_predicate_logged_agreement (new — see docs/sot_registry.yaml)
writers:
  - { file: lib/core/services/workout_write_service.dart, method: "markCompleted (no-prior-schedule branch)", line: 510 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "restore synthesize path", line: 985 }
readers:
  - { file: lib/core/utils/phase_completion.dart, method: "isTrainingDayType (exclusion shape, unaffected)", line: 55 }
  - { file: lib/core/utils/phase_completion.dart, method: "isPhaseCompletionTrainingType (new whitelist, widened to include logged)", line: 56 }
  - { file: lib/shared/repositories/plan_engine/plan_engine_flags.dart, method: "isRestDayConsideringLogged (the shared wrapper every call site delegates to)", line: "new" }
  - { file: lib/features/train/providers/train_provider.dart, method: "workoutDayForDate", line: 637 }
  - { file: lib/features/train/providers/train_provider.dart, method: "week builder (isRest)", line: 813 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "currentPhaseCompletionRate", line: 1412 }
  - { file: lib/features/home/screens/home_screen.dart, method: "today-card isRestDay (build)", line: 616 }
  - { file: lib/features/home/screens/home_screen.dart, method: "today-card isRestDay (row builder)", line: 791 }
  - { file: lib/core/services/plan_integrity_reconciler.dart, method: "needsHeal (isWorkout)", line: 97 }
  - { file: lib/features/home/providers/home_provider.dart, method: "calendar day status", line: 103 }
  - { file: lib/features/home/providers/home_provider.dart, method: "StreakWarningEligibility.build (isWorkoutDayToday)", line: 375 }
  - { file: lib/features/home/providers/home_provider.dart, method: "AI-insight quick-text", line: 678 }
  - { file: lib/features/home/widgets/day_detail_sheet.dart, method: "build (isWorkout)", line: 46 }
  - { file: lib/features/home/widgets/day_detail_sheet.dart, method: "_buildHeader (isWorkout)", line: 104 }
hive_key_prefix: "schedule_ — the per-date rows every reader reads the 'type' field from."
hive_key_formula: "schedule_${formatDateKey(date)}"
sync_methods: not_applicable — no sync method changed, only local read-path predicates.
restore_methods: not_applicable — the restore WRITER (sync_workout.dart:985) is unchanged; only
  downstream READERS of the type it writes changed.
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/training_day_predicate_wiring_test.dart
ist_handling: not_applicable — no date-key logic touched.
provider_invalidations: none — pure predicate change, no new write, no new invalidation needed.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — reads the current session's already-scoped schedule rows,
  no new box or query scope introduced.
forbidden_patterns_checked:
  - "Did NOT collapse isPhaseCompletionTrainingType onto isTrainingDayType wholesale — a prior
     review round tried exactly that and it was reverted in round 3 (phase_completion.dart's own
     doc comment), because phaseCompletionRate's 2 real callers need the narrower whitelist."
  - "Did NOT scope this batch to only the 5 sites the OI-126 board named — an independent live grep
     found 6 more of the identical pattern; all 11 ship in this batch per CLAUDE.md §4.2."
proposed_fix: |
  Extracted isPhaseCompletionTrainingType(type) — a whitelist widened by exactly one value
  ('logged') from the pre-existing inline predicate. Extracted PlanEngineFlags.isRestDayConsideringLogged
  as the ONE wrapper all 11 call sites delegate to (rather than 11 independent inline copies of the
  ternary, which is how the original disagreement went unnoticed at some sites and would let a
  future edit silently diverge again). Wired behind a new kill-switch
  (PlanEngineFlags.loggedCountsAsPhaseTrainingDayEnabled, default OFF) — nothing changes for any
  user until a separate, independently reviewed flip-on commit per CLAUDE.md §4.6/§4.12.4. Also
  converged a 6th, un-DRY exclusion-shape inline site (workout_schedule_read_service.dart:1709)
  onto the existing isTrainingDayType helper — pure refactor, unflagged, no behavior change.
regression_test_planned: |
  test/contracts/training_day_predicate_wiring_test.dart — source-grep proof all 11 sites delegate
  to the wrapper (not a re-inlined duplicate) + a negative check against the pre-fix ternary
  reappearing in EITHER phrasing (exclusion, used at the 5 originally-identified sites; inclusion,
  used at Task 4's 6 additionally-discovered sites). Real call-through coverage at 3 of the 11
  sites, chosen for risk + reachability: test/contracts/phase_adherence_rate_test.dart (extended)
  proves currentPhaseCompletionRate's actual output changes — the PRO-advance gate input.
  test/contracts/reconciler_needs_heal_logged_test.dart proves PlanIntegrityReconciler.needsHeal's
  actual output changes, calling the real @visibleForTesting static method.
  test/contracts/streak_warning_eligibility_logged_test.dart proves StreakWarningEligibilityNotifier's
  actual isWorkoutDayToday output changes, driven through a real ProviderContainer (not a
  hand-duplicated reconstruction of the predicate — an earlier draft of this test made exactly that
  mistake and was rewritten after round-2 review caught it). The other 8 of 11 sites rely on the
  source-grep plus flutter analyze plus the existing tests re-run in Tasks 3-4 — a stated, not
  hidden, coverage gap; closing it further (e.g. widget-pump tests for the 4 UI-layer sites in
  home_screen.dart and day_detail_sheet.dart) is out of scope for this ship-dark batch. Mutation-
  proven: reverting the wrapper to ignore the flag entirely reddens all 3 real call-through tests
  (exact count recorded by whoever executes Task 6 Step 9 — record it here once run, do not leave
  this sentence as a placeholder in the committed doc).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "11 call sites + 1 DRY convergence; flutter analyze clean; wiring test green, 2 real call-through tests green, mutation-proven." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No new Hive key beyond the flag itself; reads the existing schedule_* 'type' field only." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No server-side data touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function involved." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No new query; existing own-rows reads unchanged." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No cloud contract changed — local-read-path predicate only." }
impact_analysis: |
  Severity: P2. Affects any user who has ever had a coach-logged (no prior schedule) or
  cloud-restored-synthesized training day: their phase-completion rate, PRO-advance gate input,
  streak-warning banner, and 7 other display surfaces under-report relative to their real
  (streak-counted) training days. Shipped ship-dark (flag default OFF) — zero live behavior change
  in this batch. The flip-on commit is deliberately out of scope here and needs its own full ×2
  review per §4.12.4, since it changes the PRO-advance gate and 7 display surfaces for every user
  with no further code change of its own.
---

# Training-day predicate disagreement on 'logged' rows (OI-126)

See `docs/audit/open_issues.md` OI-126 for the original board-level framing (which named only 5 of
the 11 real call sites — corrected here) and `lib/core/utils/phase_completion.dart:29-54`'s doc
comment for the in-repo explanation of why two shapes exist at all. This fix closes the one
*unintended* disagreement (on `'logged'`) without collapsing the two shapes into one — they remain
deliberately different, now differing only on truly unrecognized future type strings, which is
documented and out of scope.
```

- [ ] **Step 3: Validate the diagnose-doc**

Run: `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-09-24-training-day-predicate-logged-disagreement-b7e3a1.md`
Expected: PASS.

- [ ] **Step 4: Add the SoT registry entry, matching the real schema**

Read `docs/sot_registry.yaml`'s existing `workout_receipt_rendering` entry (starts at line 47) as
the template for exact indentation and required fields before pasting — the shape below mirrors it
field-for-field. Append under the `concepts:` list:

```yaml
  - concept: training_day_predicate_logged_agreement
    domain: workout
    behavioral_test_path: test/contracts/training_day_predicate_wiring_test.dart
    description: |
      Whether a 'logged' schedule-row type counts as a training day. Two
      shapes: isTrainingDayType (exclusion, streak — unaffected) and
      isPhaseCompletionTrainingType (whitelist, phase-completion/rest-banner/
      PRO-gate/calendar/streak-banner/AI-insight/reconciler/day-detail-sheet).
      All 11 whitelist-shaped call sites now delegate to the single wrapper
      PlanEngineFlags.isRestDayConsideringLogged, which agrees with the
      exclusion shape on 'logged' once loggedCountsAsPhaseTrainingDayEnabled
      is ON (default OFF, ship-dark, OI-126).
    writers:
      - file: lib/core/services/workout_write_service.dart
        line_range: 505-515
        method: markCompleted (no-prior-schedule branch)
        notes: stamps type:'logged' for AI-coach-only logging with no prior scheduled day
      - file: lib/core/services/sync/sync_workout.dart
        line_range: 980-990
        method: restore synthesize path
        notes: stamps type:'logged' when a cloud-restored log has no matching local schedule row
    reader_manifest_complete: true
    readers:
      - file: lib/core/utils/phase_completion.dart
        line_range: 55-56
        method: "isTrainingDayType / isPhaseCompletionTrainingType"
        semantic: flag-check
        fields_read: [type]
      - file: lib/shared/repositories/plan_engine/plan_engine_flags.dart
        line_range: new
        method: isRestDayConsideringLogged
        semantic: flag-check
        fields_read: [type]
        notes: the single wrapper every whitelist-shaped call site below delegates to
      - file: lib/features/train/providers/train_provider.dart
        line_range: 632-813
        method: "workoutDayForDate / week builder"
        semantic: flag-check
        fields_read: [type]
      - file: lib/core/services/workout_schedule_read_service.dart
        line_range: 1409-1412
        method: currentPhaseCompletionRate
        semantic: flag-check
        fields_read: [type]
        notes: feeds the PRO phase-advance gate — highest-risk reader
      - file: lib/features/home/screens/home_screen.dart
        line_range: 613-791
        method: "today-card isRestDay (2 sites)"
        semantic: flag-check
        fields_read: [type]
      - file: lib/core/services/plan_integrity_reconciler.dart
        line_range: 94-98
        method: needsHeal
        semantic: flag-check
        fields_read: [type]
      - file: lib/features/home/providers/home_provider.dart
        line_range: 98-678
        method: "calendar day status / StreakWarningEligibility / AI-insight quick-text (3 sites)"
        semantic: flag-check
        fields_read: [type]
      - file: lib/features/home/widgets/day_detail_sheet.dart
        line_range: 44-104
        method: "build / _buildHeader (2 sites)"
        semantic: flag-check
        fields_read: [type]
```

- [ ] **Step 5: Correct the one stale doc-comment sentence**

`lib/core/utils/phase_completion.dart`'s doc comment above `isTrainingDayType` currently says (lines
52-54):

```dart
/// The repo-wide split between the two shapes (5 call sites still use the
/// inclusion form, so they treat a `logged` day as REST) is pre-existing and
/// tracked on the open-issues board — deliberately NOT changed here.
```

**Do not touch the earlier sentence about `phaseCompletionRate`'s "two callers"** (lines 33-34) —
that sentence is accurate: `phaseCompletionRate()` genuinely has exactly 2 callers
(`workout_schedule_read_service.dart:1417`, `phase_unlock_card.dart:98`), confirmed live, and this
plan does not touch either. It describes a different population than the sentence below, which is
the one this step corrects.

Change the 52-54 sentence to:

```dart
/// The repo-wide split between the two shapes is deliberate and permanent
/// (see [isPhaseCompletionTrainingType] below) — but the disagreement on
/// `type: 'logged'` across the 11 inline call sites using the inclusion form
/// was a bug, not a feature, closed by OI-126 behind
/// [PlanEngineFlags.isRestDayConsideringLogged].
```

- [ ] **Step 6: Run full analyze + targeted tests**

Run: `flutter analyze lib/core/utils/phase_completion.dart lib/shared/repositories/plan_engine/plan_engine_flags.dart lib/features/train/providers/train_provider.dart lib/core/services/workout_schedule_read_service.dart lib/features/home/screens/home_screen.dart lib/core/services/plan_integrity_reconciler.dart lib/features/home/providers/home_provider.dart lib/features/home/widgets/day_detail_sheet.dart`
Expected: no issues.

Run: `flutter test test/contracts/`
Expected: all green, whole suite (not a hand-picked subset — CLAUDE.md §4.12.8).

- [ ] **Step 7: Commit**

```bash
git add docs/diagnoses/2026-09-24-training-day-predicate-logged-disagreement-b7e3a1.md docs/sot_registry.yaml lib/core/utils/phase_completion.dart
git commit -m "$(cat <<'EOF'
docs(train): diagnose-doc + SoT registry + doc-comment fix for OI-126

closes-diagnose: b7e3a1
EOF
)"
```

---

## After this plan: the full gate loop, then merge

Before merging to `main`:

1. Run the FULL local gate loop, not a hand-picked subset (CLAUDE.md §4.12.8):
   ```bash
   flutter analyze lib/
   flutter test
   sh scripts/pre-commit.sh
   ```
2. Confirm the ×2 context-blind plan-review record exists and converged on THIS (v2) plan.
3. Self-initiate `/code-review` (B-pass) before the `--no-ff` merge per §4.3.
4. Merge via `sh scripts/safe_merge.sh <branch>` from the primary worktree (never a raw
   `git merge`), then `sh scripts/safe_push.sh`.
5. This plan does NOT flip the flag. Flipping `enable_logged_counts_as_phase_training_day` to
   `true` is a separate, later commit needing its own full ×2 review, since that is the moment 8
   display surfaces and the PRO-advance gate's actual output change for real users.
