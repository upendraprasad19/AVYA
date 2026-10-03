# Qualification Exam — Plan 1: Brevet Engine + State (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the brevet/Acting rank-confirmation engine — consistency still promotes, but a single flag-gated clamp caps forward climb at one rung above the highest exam the user has passed.

**Architecture:** One new monotonic field `user_profile.highest_passed_exam_code` (null = SD2 baseline). A pure `clampToConfirmed()` helper mirrored in client Dart (`rank_service.dart`) and server TS (`rank_engine.ts`) lowers the behavioral ceiling to `min(behavioral, ordinal(highest_passed)+1)`. The clamp is **flag-gated, default OFF** (CLAUDE.md §4.6 feature-flag protocol) so this plan is a behavioral no-op until Plan 3's exam UI ships. No bank, no UI, no exam-taking in this plan — only the engine, the state, the rollout backfill, and tests.

**Tech Stack:** Flutter/Dart (client), Deno/TypeScript Edge Function (server cron), Supabase Postgres (migration), Hive (offline profile map), `flutter_test`.

**Spec:** `docs/architecture/qualification-exam.md` (§4 mechanic, §11 retroactivity).

**Scope guard (YAGNI):** This plan deliberately does NOT touch: the question bank / `examBox` / sync (Plan 2), the exam-taking UI / Learn / `subscription.gate` / Acting insignia rendering / notifications (Plan 3). `recordExamPass()` is built + unit-tested here as the seam Plan 3 calls; it is not wired to any UI yet.

---

## File structure

| File | Create / Modify | Responsibility |
|---|---|---|
| `lib/core/services/rank_feature_flags.dart` | **Create** | Default-OFF kill-switch `isExamGateEnabled` (configBox-backed + test seam). |
| `supabase/migrations/084_qualification_exam_confirmation.sql` | **Create** | Add `highest_passed_exam_code` + `_at` to `user_profile`; backfill existing users (spec §11). |
| `backups/applied_migrations.json` | **Modify** | Ledger the 084 apply (same commit). |
| `lib/core/services/rank_service.dart` | **Modify** | Add pure `clampToConfirmed` + `nextPassedExamCode` helpers; wire clamp into `evaluateAndPromote` (flag-gated); add `recordExamPass`, `highestPassedExamCode()`, `isCurrentRankActing()`. |
| `lib/core/services/sync/sync_profile.dart` | **Modify** | Add the two new columns to the `_syncUserProfile` upward payload. |
| `lib/core/services/rank_confirmation_reconciler.dart` | **Create** | Boot backfill mirroring migration 084 for offline/not-yet-synced existing users. |
| (boot call site, grep `PhaseProgressReconciler`) | **Modify** | Invoke `RankConfirmationReconciler.reconcile()` adjacent to the existing phase reconciler. |
| `supabase/functions/_shared/rank_engine.ts` | **Modify** | Add exported pure `clampToConfirmed` (mirror of client). |
| `supabase/functions/evaluate-rank-promotions/index.ts` | **Modify** | Read `highest_passed_exam_code`; clamp `winner` (flag-gated via `EXAM_GATE_ENABLED` env). |
| `docs/sot_registry.yaml` | **Modify** | New concept `rank_exam_confirmation_monotonic`. |
| `docs/naming_conventions.md` | **Modify** | Glossary terms (Acting / Confirmed / highest_passed_exam_code / clampToConfirmed). |
| `test/contracts/rank_exam_clamp_behavioral_test.dart` | **Create** | Pure clamp + nextPassedExamCode tests. |
| `test/contracts/rank_exam_confirmation_writer_to_reader_test.dart` | **Create** | Hive: recordExamPass + reconciler monotonic round-trip. |
| `test/contracts/rank_clamp_parity_test.dart` | **Create** | Source-grep: client Dart clamp ≡ server TS clamp formula. |

---

### Task 1: Feature flag (default OFF kill-switch)

**Files:**
- Create: `lib/core/services/rank_feature_flags.dart`
- Test: `test/contracts/rank_exam_clamp_behavioral_test.dart` (flag default asserted here in Task 3 setup; this task just lands the flag)

- [ ] **Step 1: Create the flag**

```dart
// lib/core/services/rank_feature_flags.dart
import 'package:icanbefitter/core/services/hive_service.dart';

/// Kill-switch for the qualification-exam rank gate (brevet/Acting clamp).
///
/// DEFAULT OFF (CLAUDE.md §4.6 feature-flag protocol). The rank engine is a
/// risky surface; the old no-clamp path stays reachable while this is false.
/// Roll to true only after Plan 3 (exam UI) ships and the founder verifies —
/// otherwise a new user clamps to "Acting SD1" with no screen to take the
/// SD1 exam. Backed by configBox so it can be flipped without a rebuild.
class RankFeatureFlags {
  RankFeatureFlags._();

  static const String examGateKey = 'exam_gate_enabled';

  /// Test seam — when non-null, overrides the configBox read.
  static bool? debugExamGateOverride;

  static bool get isExamGateEnabled {
    final override = debugExamGateOverride;
    if (override != null) return override;
    try {
      return HiveService.instance.configBox.get(examGateKey) == true;
    } catch (_) {
      return false; // boxes not open / any error → safe default OFF
    }
  }
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/core/services/rank_feature_flags.dart`
Expected: `No issues found!` (If `HiveService.instance.configBox` getter name differs, grep `get configBox` in `lib/core/services/hive_service.dart` and match it.)

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/rank_feature_flags.dart
git commit -m "feat(rank): add default-off exam-gate feature flag"
```

---

### Task 2: Migration 084 — confirmation columns + retroactivity backfill

**Files:**
- Create: `supabase/migrations/084_qualification_exam_confirmation.sql`
- Modify: `backups/applied_migrations.json`

- [ ] **Step 1: Verify the rank_ladder reference table has ordinals**

Run (MCP `execute_sql` against project `dedsavbjuwgarrhphgnl`):
```sql
SELECT rank_code, ordinal FROM rank_ladder ORDER BY ordinal;
```
Expected: 11 rows, SD2=0 … Capt=10. (Confirms the backfill JOIN target exists.)

- [ ] **Step 2: Write the migration file**

```sql
-- Intent: Qualification-exam brevet state. Add user_profile.highest_passed_exam_code (FK rank_ladder, nullable) + highest_passed_exam_at. Backfill existing users per spec §11: everything BELOW current rank auto-confirmed; current rank left "Acting" → highest_passed = the rank one ordinal below current (NULL when current is SD2 or SD1, since SD2 has no exam).
-- Destructive?: no   -- additive columns + forward-only backfill; no rows rewritten or lost.
-- Rollback strategy: inline   -- reverse DDL commented at file end.
-- Linked diagnose-doc: n/a   -- feature; spec docs/architecture/qualification-exam.md

ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS highest_passed_exam_code TEXT REFERENCES rank_ladder(rank_code),
  ADD COLUMN IF NOT EXISTS highest_passed_exam_at TIMESTAMPTZ;

-- Retroactivity backfill (spec §11): highest_passed = rank one ordinal below
-- current; skipped (stays NULL) when current ordinal < 2, since SD2 has no exam
-- and an SD1 holder's SD1 exam is still unpassed (SD1 becomes "Acting").
UPDATE user_profile up
SET highest_passed_exam_code = prev.rank_code,
    highest_passed_exam_at   = NOW()
FROM rank_ladder cur
JOIN rank_ladder prev ON prev.ordinal = cur.ordinal - 1
WHERE cur.rank_code = COALESCE(up.current_rank_code, 'SD2')
  AND cur.ordinal >= 2
  AND up.highest_passed_exam_code IS NULL;

-- Rollback (inline):
-- ALTER TABLE user_profile DROP COLUMN IF EXISTS highest_passed_exam_code;
-- ALTER TABLE user_profile DROP COLUMN IF EXISTS highest_passed_exam_at;
```

- [ ] **Step 3: Apply via MCP**

Use `mcp__ba7b5e8e__apply_migration` with name `084_qualification_exam_confirmation` and the SQL above. Confirm project_id = `dedsavbjuwgarrhphgnl` first.

- [ ] **Step 4: Verify applied state**

Run (MCP `execute_sql`):
```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'user_profile' AND column_name LIKE 'highest_passed_exam%';
```
Expected: 2 rows (`highest_passed_exam_code` text, `highest_passed_exam_at` timestamp with time zone).

- [ ] **Step 5: Add ledger entry**

Append to the array in `backups/applied_migrations.json`:
```json
{
  "migration": "084",
  "applied_at": "<IST timestamp at apply, e.g. 2026-06-04T11:00:00+05:30>",
  "hash": "<sha256 of the migration file>",
  "applier": "claude",
  "slug": "qualification_exam_confirmation"
}
```

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/084_qualification_exam_confirmation.sql backups/applied_migrations.json
git commit -m "feat(rank): migration 084 — exam confirmation columns + retroactivity backfill"
```

---

### Task 3: Pure clamp + monotonic helpers (TDD)

**Files:**
- Modify: `lib/core/services/rank_service.dart` (add two static methods near `shouldPromote`, line ~67)
- Test: `test/contracts/rank_exam_clamp_behavioral_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/rank_exam_clamp_behavioral_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

void main() {
  group('clampToConfirmed — brevet clamp (spec §4.2)', () {
    test('null passed → ceiling clamps to SD1 (one above baseline SD2)', () {
      // Behavioral LS(2), nothing passed → min(2, 0+1) = 1 → SD1 (Acting SD1).
      expect(RankService.clampToConfirmed(rankByCode('LS')!, null).code, 'SD1');
    });

    test('passed SD1 → ceiling clamps to LS (one above SD1)', () {
      expect(RankService.clampToConfirmed(rankByCode('PO')!, 'SD1').code, 'LS');
    });

    test('test-ahead: passed beyond behavior does not raise the rank', () {
      // Behavioral SD1(1), passed LS(2) → min(1, 3) = 1 → SD1 (behavior limits).
      expect(RankService.clampToConfirmed(rankByCode('SD1')!, 'LS').code, 'SD1');
    });

    test('confirmed up to current → no clamp (current is Confirmed)', () {
      // Behavioral LS(2), passed LS(2) → min(2, 3) = 2 → LS.
      expect(RankService.clampToConfirmed(rankByCode('LS')!, 'LS').code, 'LS');
    });

    test('exhaustive: result ordinal == min(behavioral, passed+1)', () {
      for (final behavioral in kRankLadder) {
        for (final passed in [null, ...kRankLadder.map((r) => r.code)]) {
          final passedOrd =
              passed == null ? 0 : rankByCode(passed)!.ordinal;
          final expected = behavioral.ordinal < passedOrd + 1
              ? behavioral.ordinal
              : passedOrd + 1;
          expect(
            RankService.clampToConfirmed(behavioral, passed).ordinal,
            expected,
            reason: 'behavioral=${behavioral.code} passed=$passed',
          );
        }
      }
    });
  });

  group('nextPassedExamCode — monotonic', () {
    test('raises when passing a higher exam', () {
      expect(RankService.nextPassedExamCode(null, 'SD1'), 'SD1');
      expect(RankService.nextPassedExamCode('SD1', 'LS'), 'LS');
    });
    test('never lowers when re-passing a lower exam', () {
      expect(RankService.nextPassedExamCode('LS', 'SD1'), 'LS');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/contracts/rank_exam_clamp_behavioral_test.dart`
Expected: FAIL — `clampToConfirmed`/`nextPassedExamCode` not defined.

- [ ] **Step 3: Add the helpers to `RankService`**

Insert after `shouldPromote(...)` (after line 67 of `lib/core/services/rank_service.dart`):

```dart
  /// Brevet clamp (qualification-exam spec §4.2). Lowers the behavioral
  /// ceiling to at most one rung above the highest rank whose graded exam
  /// the user has passed. Pure + static so it's unit-testable without I/O,
  /// exactly like [shouldPromote]. Mirrored verbatim by
  /// `_shared/rank_engine.ts clampToConfirmed` — keep in lockstep.
  ///
  /// [highestPassedExamCode] null = no exam passed yet (baseline SD2,
  /// ordinal 0). Callers gate on [RankFeatureFlags.isExamGateEnabled] BEFORE
  /// calling this — when the gate is off they pass the behavioral ceiling
  /// through unchanged.
  static RankLadderEntry clampToConfirmed(
    RankLadderEntry behavioralCeiling,
    String? highestPassedExamCode,
  ) {
    final passedOrdinal = highestPassedExamCode == null
        ? 0
        : (rankByCode(highestPassedExamCode)?.ordinal ?? 0);
    final capped = passedOrdinal + 1;
    final ceilingOrdinal =
        behavioralCeiling.ordinal < capped ? behavioralCeiling.ordinal : capped;
    return kRankLadder[ceilingOrdinal];
  }

  /// Monotonic next value for `highest_passed_exam_code` after passing
  /// [justPassedCode]. Never lowers. [currentCode] null = none passed yet.
  static String nextPassedExamCode(String? currentCode, String justPassedCode) {
    final curOrd =
        currentCode == null ? -1 : (rankByCode(currentCode)?.ordinal ?? -1);
    final passOrd = rankByCode(justPassedCode)?.ordinal ?? -1;
    return passOrd > curOrd ? justPassedCode : (currentCode ?? justPassedCode);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/contracts/rank_exam_clamp_behavioral_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/rank_service.dart test/contracts/rank_exam_clamp_behavioral_test.dart
git commit -m "feat(rank): pure clampToConfirmed + nextPassedExamCode helpers"
```

---

### Task 4: Wire the clamp into `evaluateAndPromote` (flag-gated)

**Files:**
- Modify: `lib/core/services/rank_service.dart` (`evaluateAndPromote`, lines 86–204)

- [ ] **Step 1: Add the import** (top of `rank_service.dart`, with the other `package:` imports)

```dart
import 'package:icanbefitter/core/services/rank_feature_flags.dart';
```

- [ ] **Step 2: Insert the clamp right after `qualified` is resolved**

Find (lines 86–87):
```dart
      final qualifiedCode = _qualifiedRankCode(state);
      final qualified = rankByCode(qualifiedCode)!;
```
Replace with:
```dart
      final qualifiedCode = _qualifiedRankCode(state);
      final behavioralQualified = rankByCode(qualifiedCode)!;
      // Qualification-exam brevet clamp (spec §4.2). Flag-gated: a no-op when
      // the exam gate is OFF (default), so this is byte-for-byte the old
      // behavior until Plan 3 ships + the founder rolls the flag.
      final passedExamCode =
          (UserRepository.instance.getProfile() ?? const {})['highest_passed_exam_code']
              as String?;
      final qualified = RankFeatureFlags.isExamGateEnabled
          ? clampToConfirmed(behavioralQualified, passedExamCode)
          : behavioralQualified;
```
Everything downstream already uses the local `qualified` variable (the promotion loop, `shouldPromote`, the denorm update, the pending stamp), so no other edits are needed — `qualified` is now the clamped ceiling.

- [ ] **Step 3: Verify analyze + existing rank tests still pass (flag off = unchanged behavior)**

Run: `flutter analyze lib/core/services/rank_service.dart`
Expected: `No issues found!`

Run: `flutter test test/contracts/rank_no_demotion_behavioral_test.dart test/contracts/rank_sequential_no_skip_test.dart`
Expected: PASS — the clamp is gated off by default, so these are unaffected.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/rank_service.dart
git commit -m "feat(rank): apply brevet clamp in evaluateAndPromote (flag-gated)"
```

---

### Task 5: `recordExamPass` confirmation write-path (TDD, Hive)

**Files:**
- Modify: `lib/core/services/rank_service.dart` (add `recordExamPass`, `highestPassedExamCode()`, `isCurrentRankActing()` in the Public API section, after `getLadder`, ~line 303)
- Modify: `lib/core/services/sync/sync_profile.dart` (add the two columns to `_syncUserProfile` payload)
- Test: `test/contracts/rank_exam_confirmation_writer_to_reader_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/rank_exam_confirmation_writer_to_reader_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_feature_flags.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    RankFeatureFlags.debugExamGateOverride = true; // exercise the gate-on path
  });

  tearDown(() async {
    RankFeatureFlags.debugExamGateOverride = null;
    await tearDownHiveForTests(tempDir);
  });

  test('recordExamPass raises highest_passed_exam_code; reader sees it', () async {
    await UserRepository.instance.updateProfileFields({'current_rank_code': 'SD1'});

    await RankService.instance.recordExamPass('SD1');
    expect(RankService.instance.highestPassedExamCode(), 'SD1');

    await RankService.instance.recordExamPass('LS');
    expect(RankService.instance.highestPassedExamCode(), 'LS');
  });

  test('recordExamPass is monotonic — re-passing a lower exam is a no-op', () async {
    await UserRepository.instance.updateProfileFields(
        {'current_rank_code': 'LS', 'highest_passed_exam_code': 'LS'});
    await RankService.instance.recordExamPass('SD1');
    expect(RankService.instance.highestPassedExamCode(), 'LS');
  });

  test('isCurrentRankActing reflects passed vs held rank', () async {
    // Holds LS, only SD1 passed → LS is Acting.
    await UserRepository.instance.updateProfileFields(
        {'current_rank_code': 'LS', 'highest_passed_exam_code': 'SD1'});
    expect(RankService.instance.isCurrentRankActing(), isTrue);
    // Pass LS → confirmed, not Acting.
    await UserRepository.instance
        .updateProfileFields({'highest_passed_exam_code': 'LS'});
    expect(RankService.instance.isCurrentRankActing(), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/contracts/rank_exam_confirmation_writer_to_reader_test.dart`
Expected: FAIL — `recordExamPass` / `highestPassedExamCode` / `isCurrentRankActing` not defined.

- [ ] **Step 3: Add the methods to `RankService`** (after `getLadder()`, ~line 303)

```dart
  /// Highest exam-passed rank code (null = none yet). Reads Hive profile.
  String? highestPassedExamCode() {
    final profile = UserRepository.instance.getProfile() ?? const {};
    return profile['highest_passed_exam_code'] as String?;
  }

  /// True when the user holds their current rank by behavior but hasn't
  /// passed its exam ("Acting <Rank>"). Always false when the gate is off.
  bool isCurrentRankActing() {
    if (!RankFeatureFlags.isExamGateEnabled) return false;
    final current = getCurrentRank().entry;
    final passed = highestPassedExamCode();
    final passedOrdinal =
        passed == null ? 0 : (rankByCode(passed)?.ordinal ?? 0);
    return current.ordinal > passedOrdinal;
  }

  /// Records a passing graded exam for [rankCode] and re-evaluates the
  /// ladder. Monotonic — never lowers `highest_passed_exam_code`. Hive-first
  /// via UserRepository (ProfileWriteService fires the upward sync). Called
  /// by the exam UI (Plan 3) on a passing score.
  Future<void> recordExamPass(String rankCode) async {
    try {
      final current = highestPassedExamCode();
      final next = nextPassedExamCode(current, rankCode);
      final curOrd = current == null ? -1 : (rankByCode(current)?.ordinal ?? -1);
      final nextOrd = rankByCode(next)?.ordinal ?? -1;
      if (nextOrd <= curOrd) return; // monotonic no-op
      await UserRepository.instance.updateProfileFields({
        'highest_passed_exam_code': next,
        'highest_passed_exam_at': istNow().toIso8601String(),
      });
      await evaluateAndPromote(); // re-eval with the raised ceiling
      try {
        onStateChanged?.call();
      } catch (_) {/* ProviderScope may be disposing */}
    } catch (e, st) {
      debugPrint('[RankService.recordExamPass] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'rank_service_record_exam_pass'));
    }
  }
```

Note: `istNow()` comes from `lib/core/utils/ist_date.dart` (already imported at line 8 alongside `nowWall`). If the analyzer reports it undefined, confirm the export name in `ist_date.dart` and adjust.

- [ ] **Step 4: Add the two columns to the upward sync payload**

In `lib/core/services/sync/sync_profile.dart`, inside `_syncUserProfile`'s `payload` map (after the `preferred_workout_time` entry, ~line 110):
```dart
      if (SyncService._hasValue(p['highest_passed_exam_code']))
        'highest_passed_exam_code': p['highest_passed_exam_code'],
      if (SyncService._hasValue(p['highest_passed_exam_at']))
        'highest_passed_exam_at': p['highest_passed_exam_at'],
```
(Restore needs no change — `_restoreUserProfile` merges all non-null cloud columns, verified at `sync_profile.dart:268-280`.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/contracts/rank_exam_confirmation_writer_to_reader_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/rank_service.dart lib/core/services/sync/sync_profile.dart test/contracts/rank_exam_confirmation_writer_to_reader_test.dart
git commit -m "feat(rank): recordExamPass + Acting derivation + upward sync of confirmation"
```

---

### Task 6: Boot rollout reconciler (TDD, Hive)

**Files:**
- Create: `lib/core/services/rank_confirmation_reconciler.dart`
- Modify: boot call site (grep `PhaseProgressReconciler`)
- Test: extend `test/contracts/rank_exam_confirmation_writer_to_reader_test.dart`

- [ ] **Step 1: Write the failing test** (append a group to the existing confirmation test file)

```dart
  group('RankConfirmationReconciler — rollout backfill (spec §11)', () {
    test('LS holder backfills highest_passed=SD1 (current is Acting)', () async {
      await UserRepository.instance.updateProfileFields({'current_rank_code': 'LS'});
      await RankConfirmationReconciler.reconcile();
      expect(RankService.instance.highestPassedExamCode(), 'SD1');
    });

    test('SD1 holder stays null (SD1 becomes Acting; SD2 has no exam)', () async {
      await UserRepository.instance.updateProfileFields({'current_rank_code': 'SD1'});
      await RankConfirmationReconciler.reconcile();
      expect(RankService.instance.highestPassedExamCode(), isNull);
    });

    test('idempotent + monotonic — never lowers an existing higher value', () async {
      await UserRepository.instance.updateProfileFields(
          {'current_rank_code': 'LS', 'highest_passed_exam_code': 'LS'});
      await RankConfirmationReconciler.reconcile();
      expect(RankService.instance.highestPassedExamCode(), 'LS'); // not lowered to SD1
    });
  });
```
Add the import at the top of the test file:
```dart
import 'package:icanbefitter/core/services/rank_confirmation_reconciler.dart';
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/contracts/rank_exam_confirmation_writer_to_reader_test.dart`
Expected: FAIL — `RankConfirmationReconciler` undefined.

- [ ] **Step 3: Create the reconciler**

```dart
// lib/core/services/rank_confirmation_reconciler.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/rank_feature_flags.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Boot backfill for the qualification-exam confirmation field (spec §11).
/// Mirrors migration 084's cloud backfill so the brevet clamp is correct
/// OFFLINE for an existing user before the backfilled value syncs down.
///
/// Rule: everything BELOW the current rank is auto-confirmed; the current
/// rank is left "Acting" → highest_passed_exam_code = the rank one ordinal
/// below current (null when current is SD2/SD1 — SD2 has no exam).
/// Monotonic (never lowers) + idempotent. No-op when the gate is off.
class RankConfirmationReconciler {
  RankConfirmationReconciler._();

  static Future<void> reconcile() async {
    if (!RankFeatureFlags.isExamGateEnabled) return;
    try {
      final profile = UserRepository.instance.getProfile();
      if (profile == null) return;
      final currentCode = (profile['current_rank_code'] as String?) ?? 'SD2';
      final currentOrdinal = rankByCode(currentCode)?.ordinal ?? 0;
      final targetOrdinal = currentOrdinal - 1;
      final derived = targetOrdinal >= 1 ? kRankLadder[targetOrdinal].code : null;
      if (derived == null) return;

      final existing = profile['highest_passed_exam_code'] as String?;
      final existingOrdinal =
          existing == null ? 0 : (rankByCode(existing)?.ordinal ?? 0);
      final derivedOrdinal = rankByCode(derived)?.ordinal ?? 0;
      if (derivedOrdinal > existingOrdinal) {
        await UserRepository.instance
            .updateProfileFields({'highest_passed_exam_code': derived});
      }
    } catch (e, st) {
      debugPrint('[RankConfirmationReconciler] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'rank_confirmation_reconciler'));
    }
  }
}
```

- [ ] **Step 4: Wire into boot**

Find the existing phase reconciler call site:
Run: `grep -rn "PhaseProgressReconciler" lib/` (use the Grep tool)
At that call site (e.g. splash bootstrap), add immediately after the phase reconcile call, before `RankService.instance.evaluateAndPromote()` if present:
```dart
      await RankConfirmationReconciler.reconcile();
```
Add the import to that file:
```dart
import 'package:icanbefitter/core/services/rank_confirmation_reconciler.dart';
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/contracts/rank_exam_confirmation_writer_to_reader_test.dart`
Expected: PASS (all groups).

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/rank_confirmation_reconciler.dart lib/ test/contracts/rank_exam_confirmation_writer_to_reader_test.dart
git commit -m "feat(rank): boot reconciler backfills exam-confirmation offline (spec §11)"
```

---

### Task 7: Server clamp mirror + cron wiring + parity test

**Files:**
- Modify: `supabase/functions/_shared/rank_engine.ts` (add exported `clampToConfirmed`)
- Modify: `supabase/functions/evaluate-rank-promotions/index.ts` (read column + clamp winner, env-gated)
- Test: `test/contracts/rank_clamp_parity_test.dart`

- [ ] **Step 1: Write the failing parity test**

```dart
// test/contracts/rank_clamp_parity_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Pins client (Dart) and server (TS) brevet clamps in lockstep — both must
/// compute min(behavioral.ordinal, passedOrdinal + 1). Source-grep presence +
/// formula match (the Dart behavioral correctness lives in
/// rank_exam_clamp_behavioral_test.dart).
void main() {
  test('client + server clampToConfirmed exist with the same formula', () {
    final dart = File('lib/core/services/rank_service.dart').readAsStringSync();
    final ts = File('supabase/functions/_shared/rank_engine.ts').readAsStringSync();

    expect(dart.contains('clampToConfirmed('), isTrue,
        reason: 'client clamp missing');
    expect(ts.contains('export function clampToConfirmed('), isTrue,
        reason: 'server clamp missing');
    // Formula: one rung above highest passed.
    expect(dart.contains('passedOrdinal + 1'), isTrue);
    expect(ts.contains('passedOrdinal + 1'), isTrue);
    // Cron must read the column + apply the clamp.
    final cron =
        File('supabase/functions/evaluate-rank-promotions/index.ts').readAsStringSync();
    expect(cron.contains('highest_passed_exam_code'), isTrue);
    expect(cron.contains('clampToConfirmed('), isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/contracts/rank_clamp_parity_test.dart`
Expected: FAIL — server clamp / cron references absent.

- [ ] **Step 3: Add the server clamp** to `supabase/functions/_shared/rank_engine.ts` (after `highestQualified`, ~line 110)

```ts
// Brevet clamp (qualification-exam spec §4.2). Mirror of the client
// `RankService.clampToConfirmed` — keep in lockstep. Lowers the behavioral
// ceiling to at most one rung above the highest exam-passed rank.
// highestPassedExamCode null = none passed yet (baseline SD2, ordinal 0).
export function clampToConfirmed(
  behavioralCeiling: RankLadderEntry,
  highestPassedExamCode: string | null,
): RankLadderEntry {
  const passedOrdinal = highestPassedExamCode === null
    ? 0
    : (kRankLadder.find((r) => r.code === highestPassedExamCode)?.ordinal ?? 0);
  const ceilingOrdinal = Math.min(behavioralCeiling.ordinal, passedOrdinal + 1);
  return kRankLadder[ceilingOrdinal];
}
```

- [ ] **Step 4: Wire the cron** (`supabase/functions/evaluate-rank-promotions/index.ts`)

Add to the import from `../_shared/rank_engine.ts` (line 19–25): add `clampToConfirmed,` to the named imports.

Add near the env constants (after line 42):
```ts
const EXAM_GATE_ENABLED = Deno.env.get("EXAM_GATE_ENABLED") === "true";
```

Replace line 132 (`const winner = await highestQualified(state);`) with:
```ts
      // Qualification-exam brevet clamp (spec §4.2). Env-gated, default OFF
      // (matches the client RankFeatureFlags default) so this is a no-op until
      // rollout. Reads the user's highest exam-passed rank.
      const { data: examRow } = await supabase
        .from("user_profile")
        .select("highest_passed_exam_code")
        .eq("user_id", userId)
        .maybeSingle();
      const highestPassedExamCode =
        (examRow?.highest_passed_exam_code as string | null) ?? null;
      const rawWinner = await highestQualified(state);
      const winner = EXAM_GATE_ENABLED
        ? clampToConfirmed(rawWinner, highestPassedExamCode)
        : rawWinner;
```
Everything downstream already uses `winner` — no further edits.

- [ ] **Step 5: Run to verify the parity test passes**

Run: `flutter test test/contracts/rank_clamp_parity_test.dart`
Expected: PASS.

- [ ] **Step 6: Deploy the Edge Function + smoke** (per `supabase/functions/CLAUDE.md` host-shell deploy)

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js evaluate-rank-promotions --auto --functions-dir "$(pwd)/supabase/functions"
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl evaluate-rank-promotions .claude/_payload_evaluate-rank-promotions.json false
```
Then verify deployed version via `mcp__ba7b5e8e__get_edge_function` (slug `evaluate-rank-promotions`) and use the `/edge-function-deploy-rollback` skill smoke step. Leave `EXAM_GATE_ENABLED` unset (off) — do NOT set it until rollout.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/_shared/rank_engine.ts supabase/functions/evaluate-rank-promotions/index.ts test/contracts/rank_clamp_parity_test.dart
git commit -m "feat(rank): server clampToConfirmed mirror + cron wiring (env-gated) + parity test"
```

---

### Task 8: SoT registry + naming glossary

**Files:**
- Modify: `docs/sot_registry.yaml` (new concept, after the `rank_monotonic_current_code` block ~line 4344)
- Modify: `docs/naming_conventions.md`

- [ ] **Step 1: Add the SoT concept** (insert under the `profile` domain, after the rank_monotonic_current_code entry)

```yaml
  - concept: rank_exam_confirmation_monotonic
    domain: profile
    behavioral_test_required: false
    behavioral_test_path: test/contracts/rank_exam_confirmation_writer_to_reader_test.dart
    description: |
      `user_profile.highest_passed_exam_code` (null = SD2 baseline) is the
      qualification-exam confirmation state (spec docs/architecture/qualification-exam.md
      §4). MONOTONIC: only ever raised (recordExamPass + boot reconciler +
      migration 084 backfill). The brevet clamp `clampToConfirmed` lowers the
      behavioral rank ceiling to min(behavioral, ordinal(highest_passed)+1).
      Flag-gated by RankFeatureFlags.isExamGateEnabled (client) / EXAM_GATE_ENABLED
      env (server cron); default OFF until Plan 3 ships.
    writers:
      - file: lib/core/services/rank_service.dart
        method: RankService.recordExamPass
        notes: Monotonic via nextPassedExamCode; Hive-first → upward sync.
      - file: lib/core/services/rank_confirmation_reconciler.dart
        method: RankConfirmationReconciler.reconcile
        notes: Boot backfill mirroring migration 084 (spec §11). Monotonic.
      - file: supabase/migrations/084_qualification_exam_confirmation.sql
        method: retroactivity backfill
        notes: Cloud backfill = rank one ordinal below current.
    reader_manifest_complete: true
    readers:
      - file: lib/core/services/rank_service.dart
        method: clampToConfirmed (via evaluateAndPromote) + isCurrentRankActing
        semantic: read
        fields_read: [highest_passed_exam_code]
      - file: supabase/functions/evaluate-rank-promotions/index.ts
        method: cron clamp
        semantic: read
        fields_read: [highest_passed_exam_code]
    cloud_table: user_profile
    cloud_columns:
      - highest_passed_exam_code
      - highest_passed_exam_at
    hive:
      box: userBox
      key: profile
      fields: [highest_passed_exam_code, highest_passed_exam_at]
    regression_test: test/contracts/rank_exam_confirmation_writer_to_reader_test.dart
    telemetry:
      failure_op_types:
        - rank_service_record_exam_pass
        - rank_confirmation_reconciler
    class_constraints: |
      Any writer to highest_passed_exam_code MUST route through
      nextPassedExamCode (or an equivalent ordinal-compare guard) — never
      lower it. Client clampToConfirmed and server rank_engine.ts
      clampToConfirmed MUST stay in lockstep (pinned by
      test/contracts/rank_clamp_parity_test.dart).
```

- [ ] **Step 2: Add glossary terms** to `docs/naming_conventions.md` (reserved-domain glossary section):

```markdown
- **Acting** — a rank held by behavioral consistency whose graded exam is not yet passed (`current_rank_ordinal > ordinal(highest_passed_exam)`). Display modifier, derived, never stored.
- **Confirmed** — a rank whose graded exam has been passed.
- **highest_passed_exam_code** — `user_profile` column + `userBox['profile']` field; the highest rank whose exam the user passed (null = SD2 baseline). Monotonic.
- **clampToConfirmed** — pure brevet clamp; mirrored in `rank_service.dart` (Dart) + `rank_engine.ts` (TS).
```

- [ ] **Step 3: Validate the SoT gate**

Run: `dart run scripts/check_sot_behavioral_test_paths.dart`
Expected: no new WARN for `rank_exam_confirmation_monotonic` (it has a `behavioral_test_path:`).

- [ ] **Step 4: Commit**

```bash
git add docs/sot_registry.yaml docs/naming_conventions.md
git commit -m "docs(rank): SoT concept rank_exam_confirmation_monotonic + glossary"
```

---

### Task 9: Full verification

- [ ] **Step 1: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Run the rank test suite**

Run: `flutter test test/contracts/rank_exam_clamp_behavioral_test.dart test/contracts/rank_exam_confirmation_writer_to_reader_test.dart test/contracts/rank_clamp_parity_test.dart test/contracts/rank_no_demotion_behavioral_test.dart test/contracts/rank_sequential_no_skip_test.dart`
Expected: ALL PASS. (The two pre-existing rank tests confirm no regression with the gate off.)

- [ ] **Step 3: Confirm the gate is OFF by default** (safety)

Run: `grep -n "exam_gate_enabled\|EXAM_GATE_ENABLED\|debugExamGateOverride" lib/ supabase/ -r` (Grep tool)
Expected: no code path sets the flag true outside tests. Confirm `EXAM_GATE_ENABLED` is NOT set as an Edge Function secret.

- [ ] **Step 4: Final batch commit** (if any task commits were deferred)

The pre-push hook runs the full suite at ≥account blast-radius (this touches the rank engine = account tier). Do NOT push until the founder asks; this plan ends at "committed on the `qualification-exam` branch."

---

## Self-review checklist (completed during authoring)

- **Spec coverage:** §4 clamp (T3/T4/T7) ✓; §4.4 confirmation write (T5) ✓; §4.3 Acting derivation (T5) ✓; §11 retroactivity — migration backfill (T2) + offline reconciler (T6) ✓; §4.6 flag (T1, gating in T4/T7) ✓; SoT + tests (T8, every task) ✓. Bank/UI/Learn/gate/notifications correctly deferred to Plans 2–3.
- **Placeholder scan:** none — every code step has complete code; the one grep-to-locate (boot call site, T6 S4) is an exact command, not a placeholder.
- **Type consistency:** `clampToConfirmed(RankLadderEntry, String?) → RankLadderEntry` and `nextPassedExamCode(String?, String) → String` used identically across T3/T4/T5/T7; field name `highest_passed_exam_code` consistent across migration, sync, reconciler, SoT, tests.

## Rollout note (post Plan 3)
After Plans 2 + 3 land and the founder verifies on a test account, roll the gate on: set `configBox['exam_gate_enabled'] = true` (client, via the dev panel or a RemoteConfig push) AND set Edge Function secret `EXAM_GATE_ENABLED=true`. Both must flip together so client and nightly cron agree.
