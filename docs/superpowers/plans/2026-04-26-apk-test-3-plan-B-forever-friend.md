# APK Test #3 — Plan B — Forever-Friend Rank System

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the lifetime rank ladder (Indian Navy 9-rung, see spec) end-to-end across client + cron + UI: a `RankService` singleton that computes the user's current/next rank from existing Hive + Postgres state, a nightly Edge Function that catches users whose client never fired, two new Wardroom primitives (`RankInsignia`, `RankChip`) that read the ladder, and surface integration on Home (one-line below streak), Train (chip top + Roadmap pill above This Week + roadmap redesigned as vertical timeline), and Profile (SERVICE RECORD section above bio stats). Also fixes the previewPlanProvider experience-key mismatch and pipes `current_rank` + `weeks_until_next_rank` into the AI snapshot.

**Architecture:** Plan A migration 039 already shipped the schema (`rank_ladder` seeded with 10 rows, `rank_promotions` per-user history with RLS, denormalized `user_profile.current_rank_code`). Plan B is the read/write layer. `RankService.evaluateAndPromote()` is idempotent (UNIQUE on `(user_id, rank_code)`) and called from three places — splash boot, after every `completeWorkout`, and a nightly Edge Function `evaluate-rank-promotions`. UI surfaces all read the denormalized `current_rank_code` for fast paint, then async-fill ladder + next-rank progress via the service. SVG insignia don't exist yet (per spec F20); `RankInsignia` falls back to text inside a gold-ringed seal — SVGs swap in automatically once `assets/rank/*.svg` files appear in `pubspec.yaml`. Ranks are FREE for everyone — no `subscription.gate()` calls anywhere in this batch.

**Tech Stack:** Flutter (Dart 3.4+) + Riverpod for state, Hive offline storage, Supabase Postgres + Edge Function (Deno + TypeScript), pg_cron migration for the nightly schedule. No new packages — uses `flutter_svg` only if-and-when SVG assets land (text fallback never imports it).

**Spec:** `docs/superpowers/specs/2026-04-26-apk-test-3-batch-design.md` (Forever-Friend Story / Obs 1 section + Phase exercise count fix sub-section + AI Snapshot Expansion Q6.3).

**Predecessor:** Plan A (`2026-04-26-apk-test-3-plan-A-db-sync-bugs.md`). Migration 039 must be applied before any task in this plan runs against prod.

---

## File Structure

| File | Responsibility | New / Modified |
|---|---|---|
| `lib/core/services/rank_service.dart` | Singleton with `evaluateAndPromote`, `getCurrentRank`, `getNextRank`, `getLadder`. Reads streak via `WorkoutRepository.calculateCurrentStreak()`, weeks-since-signup via `auth.users.created_at`, total workouts via `progress['total_workouts_done']`. Writes to `rank_promotions` + updates denorm `user_profile.current_rank_code`. Fire-and-forget; catches its own errors. | New |
| `lib/core/services/rank_ladder_data.dart` | Static const ladder mirror (10 rows from migration 039). Avoids a network call on every `getLadder()`. | New |
| `supabase/functions/evaluate-rank-promotions/index.ts` | Cron-triggered (`verify_jwt: false`). Iterates all `public.users`; for each, recomputes rank ceiling from Postgres data; upserts missing `rank_promotions` rows + updates `user_profile.current_rank_code`. | New |
| `supabase/functions/_shared/rank_engine.ts` | Pure rank-evaluation logic shared between Edge Function + future server consumers. Mirror of `RankService._qualifiedRankCode` for parity. | New |
| `supabase/migrations/040_rank_promotions_cron.sql` | pg_cron schedule registering nightly run of `evaluate-rank-promotions` at 18:30 UTC (00:00 IST). | New |
| `lib/shared/widgets/wardroom/rank_insignia.dart` | Renders SVG from `rank/<code>.svg` if asset exists, else text fallback (`SD2`, `LEADING`, `CAPTAIN`) inside a gold-ringed seal. | New |
| `lib/shared/widgets/wardroom/rank_chip.dart` | Compact chip: `[insignia 16dp] SEAMAN 2ND CLASS · NEXT IN 12 DAYS`. Single mono row. Reads `RankService.getCurrentRank()` + `getNextRank()`. | New |
| `lib/shared/widgets/wardroom/wardroom.dart` | Add exports for `rank_insignia.dart` + `rank_chip.dart`. | Modified |
| `lib/features/profile/widgets/service_record_section.dart` | Profile section: ladder vertical list (earned bright + insignia + earned date; locked grayed + gate). Lifetime stats row (deployments completed / service days / total volume). | New |
| `lib/features/train/screens/phase_roadmap_screen.dart` | Full rewrite — vertical timeline with W1 marker, Phase blocks, Year 1/2/3-5 dividers, rank promotion markers up to W260. Tap rank marker → detail sheet. | Modified |
| `lib/features/train/screens/train_screen.dart` | Insert `RankChip` at top of content; reorder so `DEPLOYMENT 01 — FOUNDATION` mono header + Roadmap pill sit ABOVE `THIS WEEK` (was below). | Modified |
| `lib/features/home/screens/home_screen.dart` | Insert `RankChip` ONE LINE below streak counter. No spacing changes. | Modified |
| `lib/features/profile/screens/profile_screen.dart` | Insert `ServiceRecordSection` ABOVE `ProfileIdentity` bio block. | Modified |
| `lib/features/train/providers/train_provider.dart` | `completeWorkout`: fire `unawaited(RankService.instance.evaluateAndPromote())` after the existing sync triple. | Modified |
| `lib/features/train/providers/preview_plan_provider.dart` | Phase exercise count fix: bump fallback `experienceLevel` from `'beginner'` to `'intermediate'` to match onboarding default (mirrors F6 lesson); add a debug assertion when `fitness_experience` or `days_per_week` is null so silent default substitution becomes loud. | Modified |
| `lib/features/ai_coach/repositories/ai_coach_repository.dart` | Add `current_rank` + `weeks_until_next_rank` keys (read from `RankService`) to `buildAiContext` snapshot. | Modified |
| `lib/core/services/ai_service.dart` | Update `_compactContext` trim order to drop `current_rank` LAST (it's tiny + identity-bearing). | Modified |
| `lib/features/auth/screens/splash_screen.dart` | Wire one fire-and-forget call to `RankService.instance.evaluateAndPromote()` after `checkAndSync`. | Modified |
| `test/services/rank_service_test.dart` | Unit test: ladder math (`SD1` at 7 streak + 1 wk; `LS` at 16 + 4 wk; etc.); `getCurrentRank` reads denorm column; `getNextRank` returns null for `Capt`. | New |
| `test/widgets/rank_chip_test.dart` | Widget test: chip renders insignia + name + countdown; `Capt` shows `MAX RANK ACHIEVED` instead of countdown. | New |
| `test/contracts/rank_service_idempotent_test.dart` | Regex test: `evaluateAndPromote` body uses `.upsert(..., onConflict: 'user_id,rank_code')` — never plain `.insert()`. | New |
| `test/contracts/preview_plan_default_test.dart` | Regex test: fallback for `fitness_experience` is `'intermediate'` not `'beginner'` (locks F6 lesson). | New |

---

## Task 1: Static rank ladder mirror + RankService skeleton

**Files:**
- Create: `lib/core/services/rank_ladder_data.dart`
- Create: `lib/core/services/rank_service.dart` (skeleton + types only)

**Background:** The 10-row ladder from migration 039 is small + immutable. Mirroring it in Dart const space lets every read path (`getLadder`, `getNextRank`, UI render) skip a network round-trip. The Edge Function uses the same shape via `_shared/rank_engine.ts` (Task 4).

- [ ] **Step 1: Write the static ladder data file**

Create `lib/core/services/rank_ladder_data.dart`:

```dart
/// Static mirror of the `rank_ladder` Postgres table seeded by
/// migration 039. Order MUST match `ordinal` ascending.
///
/// When migration 039 ladder rows change, update this file and the
/// `_shared/rank_engine.ts` mirror in lockstep. The list is immutable.
library;

class RankLadderEntry {
  final String code;
  final String displayName;
  final String shortName;
  final int ordinal;
  final int minWeeks;
  final String insigniaAsset;
  final String category; // 'sailor' | 'officer'
  final bool isTerminal;

  const RankLadderEntry({
    required this.code,
    required this.displayName,
    required this.shortName,
    required this.ordinal,
    required this.minWeeks,
    required this.insigniaAsset,
    required this.category,
    required this.isTerminal,
  });
}

/// Streak + total-workout gates per rank, mirroring spec section
/// "Indian Navy 9-rung rank ladder (LOCKED)" — both must satisfy.
///
/// `streak` is the current workout-day streak from
/// `WorkoutRepository.calculateCurrentStreak()` — schedule-aware,
/// rest days invisible.
///
/// `totalWorkouts` reads from `progress['total_workouts_done']`.
///
/// `minWeeks` is calendar weeks since signup (auth.users.created_at)
/// truncated. Always the additional gate alongside streak / count.
class RankGate {
  final int? streakAtLeast;
  final int? totalWorkoutsAtLeast;
  final int? deploymentsCompleteAtLeast;
  final int? minWeeksSinceSignup;
  final int? maxGapDays; // for MCPO 1-year-active-streak gate

  const RankGate({
    this.streakAtLeast,
    this.totalWorkoutsAtLeast,
    this.deploymentsCompleteAtLeast,
    this.minWeeksSinceSignup,
    this.maxGapDays,
  });
}

/// 10-rung ladder, ordinal 0..9. Captain is terminal.
const List<RankLadderEntry> kRankLadder = [
  RankLadderEntry(
    code: 'SD2',
    displayName: 'Seaman 2nd Class',
    shortName: 'Seaman 2nd',
    ordinal: 0,
    minWeeks: 0,
    insigniaAsset: 'rank/sd2.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'SD1',
    displayName: 'Seaman 1st Class',
    shortName: 'Seaman 1st',
    ordinal: 1,
    minWeeks: 1,
    insigniaAsset: 'rank/sd1.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'LS',
    displayName: 'Leading Seaman',
    shortName: 'Leading',
    ordinal: 2,
    minWeeks: 4,
    insigniaAsset: 'rank/ls.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'PO',
    displayName: 'Petty Officer',
    shortName: 'Petty Off.',
    ordinal: 3,
    minWeeks: 12,
    insigniaAsset: 'rank/po.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'CPO',
    displayName: 'Chief Petty Officer',
    shortName: 'Chief PO',
    ordinal: 4,
    minWeeks: 26,
    insigniaAsset: 'rank/cpo.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'MCPO',
    displayName: 'Master Chief Petty Officer',
    shortName: 'Master Ch.',
    ordinal: 5,
    minWeeks: 52,
    insigniaAsset: 'rank/mcpo.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'SubLt',
    displayName: 'Sub Lieutenant',
    shortName: 'Sub Lt',
    ordinal: 6,
    minWeeks: 104,
    insigniaAsset: 'rank/sublt.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'LtCdr',
    displayName: 'Lieutenant Commander',
    shortName: 'Lt Cdr',
    ordinal: 7,
    minWeeks: 156,
    insigniaAsset: 'rank/ltcdr.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'Cdr',
    displayName: 'Commander',
    shortName: 'Cdr',
    ordinal: 8,
    minWeeks: 208,
    insigniaAsset: 'rank/cdr.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'Capt',
    displayName: 'Captain',
    shortName: 'Captain',
    ordinal: 9,
    minWeeks: 260,
    insigniaAsset: 'rank/capt.svg',
    category: 'officer',
    isTerminal: true,
  ),
];

/// Spec gates table, ordinal-keyed. Each rank requires BOTH the
/// `RankLadderEntry.minWeeks` gate AND its `RankGate` payload.
const Map<String, RankGate> kRankGates = {
  'SD2': RankGate(),
  'SD1': RankGate(streakAtLeast: 7, minWeeksSinceSignup: 1),
  'LS': RankGate(streakAtLeast: 16, minWeeksSinceSignup: 4),
  'PO': RankGate(streakAtLeast: 60, minWeeksSinceSignup: 12,
      deploymentsCompleteAtLeast: 1),
  'CPO': RankGate(streakAtLeast: 100, minWeeksSinceSignup: 26,
      deploymentsCompleteAtLeast: 2),
  'MCPO': RankGate(minWeeksSinceSignup: 52, maxGapDays: 14),
  'SubLt': RankGate(totalWorkoutsAtLeast: 100, minWeeksSinceSignup: 104),
  'LtCdr': RankGate(totalWorkoutsAtLeast: 200, minWeeksSinceSignup: 156),
  'Cdr': RankGate(totalWorkoutsAtLeast: 300, minWeeksSinceSignup: 208),
  'Capt': RankGate(
    totalWorkoutsAtLeast: 500,
    minWeeksSinceSignup: 260,
    deploymentsCompleteAtLeast: 3,
  ),
};

/// Lookup by code. Returns null for unknown codes.
RankLadderEntry? rankByCode(String code) {
  for (final r in kRankLadder) {
    if (r.code == code) return r;
  }
  return null;
}
```

- [ ] **Step 2: Write the RankService skeleton**

Create `lib/core/services/rank_service.dart` with types + method signatures only — implementation lands in Task 2.

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import 'rank_ladder_data.dart';

/// View model emitted from `RankService.getCurrentRank()` /
/// `getNextRank()`. UI-only — never round-trips to Supabase.
class RankInfo {
  final RankLadderEntry entry;
  final DateTime? achievedAt; // null for the not-yet-earned next rank
  final int? daysUntilEligible; // null if eligible now or terminal
  final int? workoutsRemaining; // for total-workout gated ranks

  const RankInfo({
    required this.entry,
    this.achievedAt,
    this.daysUntilEligible,
    this.workoutsRemaining,
  });
}

class LadderEntryView {
  final RankLadderEntry entry;
  final bool isEarned;
  final DateTime? earnedAt;
  final String? gateText; // e.g. "100 workouts to unlock Sub Lieutenant"

  const LadderEntryView({
    required this.entry,
    required this.isEarned,
    this.earnedAt,
    this.gateText,
  });
}

class RankService {
  RankService._();
  static final RankService instance = RankService._();

  /// Idempotent — evaluates the user's current state, computes the
  /// highest rank they qualify for, and writes a `rank_promotions`
  /// row + denorm `user_profile.current_rank_code` for any rank they
  /// newly qualify for. Fire-and-forget. Catches all errors.
  Future<void> evaluateAndPromote() async {
    // Implemented in Task 2.
    throw UnimplementedError();
  }

  /// Reads from `user_profile.current_rank_code` (denormalized for
  /// fast UI paint). Falls back to `'SD2'` on any read error so UI
  /// never shows blank.
  RankInfo getCurrentRank() {
    // Implemented in Task 2.
    throw UnimplementedError();
  }

  /// Returns the next rank above `getCurrentRank()`, with progress
  /// metrics (days remaining, workouts remaining). Returns null when
  /// user is at `Capt` (terminal).
  RankInfo? getNextRank() {
    // Implemented in Task 2.
    throw UnimplementedError();
  }

  /// Returns the full 10-rung ladder with earned/locked status for
  /// Profile Service Record rendering.
  List<LadderEntryView> getLadder() {
    // Implemented in Task 2.
    throw UnimplementedError();
  }
}
```

- [ ] **Step 3: Compile-check**

```bash
flutter analyze lib/core/services/rank_service.dart lib/core/services/rank_ladder_data.dart
```

Expected: zero errors. Warnings about `UnimplementedError` are fine — Task 2 fills them.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/rank_service.dart \
        lib/core/services/rank_ladder_data.dart
git commit -m "$(cat <<'EOF'
feat(rank): static rank ladder + RankService skeleton

Mirror of migration 039's rank_ladder table as Dart const data so
every UI read path skips a network round-trip. RankGate map encodes
both halves of the spec's "BOTH must satisfy" gates (streak floor +
calendar weeks since signup + total workouts).

RankService skeleton ships type-only; implementation lands in Task 2.
EOF
)"
```

---

## Task 2: RankService implementation (eligibility + promotion writes)

**Files:**
- Modify: `lib/core/services/rank_service.dart`
- Test: `test/services/rank_service_test.dart`

- [ ] **Step 1: Write the failing unit test**

Create `test/services/rank_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

/// Unit-level coverage of the eligibility table.
///
/// We test the *static* qualification function — the Hive-/Supabase-
/// reading paths are exercised by `rank_service_idempotent_test.dart`
/// as a regex contract (since they need a live Hive box to run).
void main() {
  test('SD2 always qualifies', () {
    expect(_qualifies('SD2', streak: 0, totalWorkouts: 0, weeks: 0,
                     deploymentsComplete: 0, longestGapDays: 0), isTrue);
  });

  test('SD1 needs streak 7 + 1 week', () {
    expect(_qualifies('SD1', streak: 6, totalWorkouts: 6, weeks: 1,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('SD1', streak: 7, totalWorkouts: 7, weeks: 0,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('SD1', streak: 7, totalWorkouts: 7, weeks: 1,
                     deploymentsComplete: 0, longestGapDays: 0), isTrue);
  });

  test('LS needs streak 16 + 4 weeks', () {
    expect(_qualifies('LS', streak: 15, totalWorkouts: 15, weeks: 4,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('LS', streak: 16, totalWorkouts: 16, weeks: 3,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('LS', streak: 16, totalWorkouts: 16, weeks: 4,
                     deploymentsComplete: 0, longestGapDays: 0), isTrue);
  });

  test('PO needs streak 60 + 12 weeks + deployment 1', () {
    expect(_qualifies('PO', streak: 60, totalWorkouts: 60, weeks: 12,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('PO', streak: 60, totalWorkouts: 60, weeks: 12,
                     deploymentsComplete: 1, longestGapDays: 0), isTrue);
  });

  test('SubLt needs 100 total workouts AND 104 weeks', () {
    expect(_qualifies('SubLt', streak: 0, totalWorkouts: 99, weeks: 104,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('SubLt', streak: 0, totalWorkouts: 100, weeks: 103,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('SubLt', streak: 0, totalWorkouts: 100, weeks: 104,
                     deploymentsComplete: 0, longestGapDays: 0), isTrue);
  });

  test('Capt is terminal — last lookup', () {
    expect(rankByCode('Capt')!.isTerminal, isTrue);
    final next = kRankLadder
        .where((r) => r.ordinal > rankByCode('Capt')!.ordinal)
        .toList();
    expect(next, isEmpty);
  });
}

/// Mirrors `RankService._qualifies` minus IO. Same semantics; if the
/// service-side helper is renamed/rewritten, update this mirror.
bool _qualifies(String code, {
  required int streak,
  required int totalWorkouts,
  required int weeks,
  required int deploymentsComplete,
  required int longestGapDays,
}) {
  final entry = rankByCode(code);
  if (entry == null) return false;
  if (weeks < entry.minWeeks) return false;
  final gate = kRankGates[code]!;
  if (gate.streakAtLeast != null && streak < gate.streakAtLeast!) {
    return false;
  }
  if (gate.totalWorkoutsAtLeast != null &&
      totalWorkouts < gate.totalWorkoutsAtLeast!) {
    return false;
  }
  if (gate.minWeeksSinceSignup != null &&
      weeks < gate.minWeeksSinceSignup!) {
    return false;
  }
  if (gate.deploymentsCompleteAtLeast != null &&
      deploymentsComplete < gate.deploymentsCompleteAtLeast!) {
    return false;
  }
  if (gate.maxGapDays != null && longestGapDays > gate.maxGapDays!) {
    return false;
  }
  return true;
}
```

- [ ] **Step 2: Run the test to verify it fails on SD1/LS edge cases first**

```bash
flutter test test/services/rank_service_test.dart
```

Expected: PASS (this test exercises only `kRankGates`, not the service IO). If it fails, re-check the gate map you wrote in Task 1.

- [ ] **Step 3: Implement the four service methods**

Open `lib/core/services/rank_service.dart` and replace the body with:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import 'rank_ladder_data.dart';

class RankInfo {
  final RankLadderEntry entry;
  final DateTime? achievedAt;
  final int? daysUntilEligible;
  final int? workoutsRemaining;

  const RankInfo({
    required this.entry,
    this.achievedAt,
    this.daysUntilEligible,
    this.workoutsRemaining,
  });
}

class LadderEntryView {
  final RankLadderEntry entry;
  final bool isEarned;
  final DateTime? earnedAt;
  final String? gateText;

  const LadderEntryView({
    required this.entry,
    required this.isEarned,
    this.earnedAt,
    this.gateText,
  });
}

class RankService {
  RankService._();
  static final RankService instance = RankService._();

  // ── Public API ─────────────────────────────────────────────────

  Future<void> evaluateAndPromote() async {
    try {
      final user = SupabaseService.instance.currentUser;
      if (user == null) return; // not signed in — nothing to write

      final state = _readEvaluationState(signupAt: user.createdAt);
      final qualifiedCode = _qualifiedRankCode(state);
      final qualified = rankByCode(qualifiedCode)!;

      // Read currently-recorded promotions to find which (if any)
      // ranks we still need to insert. `rank_promotions` has UNIQUE
      // (user_id, rank_code) so upsert is safe under retries.
      final supa = SupabaseService.instance.client;
      final existing = await supa
          .from('rank_promotions')
          .select('rank_code')
          .eq('user_id', user.id);
      final existingCodes = (existing as List)
          .map((e) => (e as Map)['rank_code'] as String)
          .toSet();

      // Promote every rank up to and including `qualified` that
      // hasn't been recorded yet. (User might leap multiple rungs in
      // one evaluation — e.g. server cron after long absence.)
      final toInsert = <Map<String, dynamic>>[];
      for (final r in kRankLadder) {
        if (r.ordinal > qualified.ordinal) break;
        if (existingCodes.contains(r.code)) continue;
        toInsert.add({
          'user_id': user.id,
          'rank_code': r.code,
          'trigger_type': _triggerTypeFor(r.code),
          'trigger_metadata': {
            'streak': state.streakDays,
            'total_workouts': state.totalWorkouts,
            'weeks': state.weeksSinceSignup,
            'source': 'client',
          },
        });
      }

      if (toInsert.isNotEmpty) {
        await supa.from('rank_promotions').upsert(
              toInsert,
              onConflict: 'user_id,rank_code',
            );
      }

      // Update denormalized current_rank_code only when it actually
      // changed — avoids a no-op write on every call.
      final currentDenorm = await supa
          .from('user_profile')
          .select('current_rank_code')
          .eq('user_id', user.id)
          .maybeSingle();
      final currentCode = currentDenorm == null
          ? null
          : (currentDenorm as Map)['current_rank_code'] as String?;
      if (currentCode != qualified.code) {
        await supa.from('user_profile').update({
          'current_rank_code': qualified.code,
          'current_rank_achieved_at': DateTime.now().toIso8601String(),
        }).eq('user_id', user.id);
      }
    } catch (e) {
      // Fire-and-forget contract — errors must never propagate to UI.
      debugPrint('[RankService.evaluateAndPromote] $e');
    }
  }

  RankInfo getCurrentRank() {
    try {
      final profile = UserRepository.instance.getProfile() ?? {};
      final code = (profile['current_rank_code'] as String?) ?? 'SD2';
      final entry = rankByCode(code) ?? rankByCode('SD2')!;
      final achievedAtRaw = profile['current_rank_achieved_at'];
      final achievedAt = achievedAtRaw is String
          ? DateTime.tryParse(achievedAtRaw)
          : null;
      return RankInfo(entry: entry, achievedAt: achievedAt);
    } catch (e) {
      debugPrint('[RankService.getCurrentRank] $e');
      return RankInfo(entry: rankByCode('SD2')!);
    }
  }

  RankInfo? getNextRank() {
    final current = getCurrentRank();
    if (current.entry.isTerminal) return null;
    final nextOrdinal = current.entry.ordinal + 1;
    if (nextOrdinal >= kRankLadder.length) return null;
    final nextEntry = kRankLadder[nextOrdinal];

    // Compute how many days / workouts away the user is.
    final state = _readEvaluationState();
    final gate = kRankGates[nextEntry.code]!;

    int? daysOut;
    if (gate.minWeeksSinceSignup != null) {
      final weeksOut = gate.minWeeksSinceSignup! - state.weeksSinceSignup;
      if (weeksOut > 0) daysOut = weeksOut * 7;
    }
    int? workoutsOut;
    if (gate.totalWorkoutsAtLeast != null) {
      workoutsOut =
          gate.totalWorkoutsAtLeast! - state.totalWorkouts;
      if (workoutsOut < 0) workoutsOut = 0;
    }
    if (gate.streakAtLeast != null) {
      final streakOut = gate.streakAtLeast! - state.streakDays;
      // Convert "10 streak workouts away" into a soft "days away"
      // estimate by assuming workout cadence ~ 4/week → 1.75d/workout.
      // Surfaces in chip copy as "NEXT IN 18 DAYS" — a hint, not a
      // promise.
      if (streakOut > 0) {
        final streakDays = (streakOut * 1.75).ceil();
        daysOut = (daysOut == null)
            ? streakDays
            : (streakDays > daysOut ? streakDays : daysOut);
      }
    }

    return RankInfo(
      entry: nextEntry,
      daysUntilEligible: daysOut,
      workoutsRemaining: workoutsOut,
    );
  }

  List<LadderEntryView> getLadder() {
    final current = getCurrentRank();
    return kRankLadder.map((entry) {
      final isEarned = entry.ordinal <= current.entry.ordinal;
      final earnedAt =
          (entry.code == current.entry.code) ? current.achievedAt : null;
      return LadderEntryView(
        entry: entry,
        isEarned: isEarned,
        earnedAt: earnedAt,
        gateText: isEarned ? null : _humanGateText(entry),
      );
    }).toList();
  }

  // ── Internals ──────────────────────────────────────────────────

  String _triggerTypeFor(String code) {
    switch (code) {
      case 'SD2':
        return 'signup';
      case 'PO':
      case 'CPO':
        return 'deployment_complete';
      case 'SubLt':
      case 'LtCdr':
      case 'Cdr':
      case 'Capt':
        return 'workout_count';
      case 'MCPO':
        return 'calendar';
      default:
        return 'combined';
    }
  }

  String _humanGateText(RankLadderEntry entry) {
    final gate = kRankGates[entry.code]!;
    if (gate.totalWorkoutsAtLeast != null) {
      return '${gate.totalWorkoutsAtLeast} workouts to unlock '
          '${entry.displayName}';
    }
    if (gate.streakAtLeast != null) {
      return '${gate.streakAtLeast}-workout streak + ${entry.minWeeks} '
          'weeks to unlock ${entry.displayName}';
    }
    if (gate.maxGapDays != null) {
      return '${entry.minWeeks}-week active streak (no >${gate.maxGapDays}-day '
          'gap) to unlock ${entry.displayName}';
    }
    return '${entry.minWeeks} weeks to unlock ${entry.displayName}';
  }

  _EvalState _readEvaluationState({DateTime? signupAt}) {
    final repo = WorkoutRepository.instance;
    final progress = UserRepository.instance.getProgress() ?? {};
    final streakDays = repo.calculateCurrentStreak();
    final totalWorkouts =
        (progress['total_workouts_done'] as int?) ?? 0;

    final signup = signupAt ??
        SupabaseService.instance.currentUser?.createdAt.let((s) {
          return DateTime.tryParse(s);
        });
    final weeks = signup == null
        ? 0
        : DateTime.now().difference(signup).inDays ~/ 7;

    // Deployments complete = count of rank_promotions rows with
    // trigger_type='deployment_complete'. Reading that requires a
    // network call; for the *client-side* fast path used by getNextRank
    // we approximate via Hive `progress['deployments_complete']` which
    // is updated when Plan A's W12 path lands (defer until F18 ships;
    // for now this stays at 0 → PO/CPO gate doesn't flip prematurely).
    final deployments =
        (progress['deployments_complete'] as int?) ?? 0;
    final longestGap =
        (progress['longest_gap_days'] as int?) ?? 0;

    return _EvalState(
      streakDays: streakDays,
      totalWorkouts: totalWorkouts,
      weeksSinceSignup: weeks,
      deploymentsComplete: deployments,
      longestGapDays: longestGap,
    );
  }

  String _qualifiedRankCode(_EvalState s) {
    String winner = 'SD2';
    for (final r in kRankLadder) {
      if (_qualifies(r.code, s)) winner = r.code;
    }
    return winner;
  }

  bool _qualifies(String code, _EvalState s) {
    final entry = rankByCode(code);
    if (entry == null) return false;
    if (s.weeksSinceSignup < entry.minWeeks) return false;
    final gate = kRankGates[code]!;
    if (gate.streakAtLeast != null &&
        s.streakDays < gate.streakAtLeast!) {
      return false;
    }
    if (gate.totalWorkoutsAtLeast != null &&
        s.totalWorkouts < gate.totalWorkoutsAtLeast!) {
      return false;
    }
    if (gate.minWeeksSinceSignup != null &&
        s.weeksSinceSignup < gate.minWeeksSinceSignup!) {
      return false;
    }
    if (gate.deploymentsCompleteAtLeast != null &&
        s.deploymentsComplete < gate.deploymentsCompleteAtLeast!) {
      return false;
    }
    if (gate.maxGapDays != null &&
        s.longestGapDays > gate.maxGapDays!) {
      return false;
    }
    return true;
  }
}

class _EvalState {
  final int streakDays;
  final int totalWorkouts;
  final int weeksSinceSignup;
  final int deploymentsComplete;
  final int longestGapDays;

  const _EvalState({
    required this.streakDays,
    required this.totalWorkouts,
    required this.weeksSinceSignup,
    required this.deploymentsComplete,
    required this.longestGapDays,
  });
}

// Tiny helper extension to keep the read path readable.
extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
```

The `currentUser.createdAt` field is the Supabase auth timestamp — confirmed available on `User` (sdk 2.x). Returns the raw ISO string; we parse to DateTime defensively.

- [ ] **Step 4: Write the regex contract test for upsert idempotency**

Create `test/contracts/rank_service_idempotent_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Locks the contract that `evaluateAndPromote` uses an UPSERT
/// (with onConflict on the (user_id, rank_code) UNIQUE constraint),
/// not a plain INSERT. A regression here means duplicate rows or
/// 23505 errors flooding logs the moment the cron + client both
/// fire on the same day.
void main() {
  test('evaluateAndPromote uses upsert with onConflict', () {
    final src =
        File('lib/core/services/rank_service.dart').readAsStringSync();

    // Find the method body.
    final start = src.indexOf('Future<void> evaluateAndPromote()');
    expect(start, isNot(-1), reason: 'evaluateAndPromote must exist');

    // Take a generous body slice (4000 chars covers the method).
    final body = src.substring(start, start + 4000);

    expect(
      body.contains('rank_promotions'),
      isTrue,
      reason: 'method must reference rank_promotions table',
    );
    expect(
      body.contains('.upsert('),
      isTrue,
      reason: 'must use upsert, not insert (idempotency)',
    );
    expect(
      body.contains("onConflict: 'user_id,rank_code'"),
      isTrue,
      reason: "upsert must specify onConflict: 'user_id,rank_code' "
          'matching the UNIQUE constraint from migration 039.',
    );
  });
}
```

- [ ] **Step 5: Run all rank tests**

```bash
flutter test test/services/rank_service_test.dart \
             test/contracts/rank_service_idempotent_test.dart
```

Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/rank_service.dart \
        test/services/rank_service_test.dart \
        test/contracts/rank_service_idempotent_test.dart
git commit -m "$(cat <<'EOF'
feat(rank): RankService eligibility + promotion writes

evaluateAndPromote: walks kRankLadder, finds highest qualified rank,
upserts any missing rank_promotions rows (onConflict user_id,rank_code
matches migration 039 UNIQUE), updates denorm user_profile.current_rank_code
only when it actually changes. Fire-and-forget contract — all errors
caught + debugPrint.

getCurrentRank: reads denormalized column from Hive profile (fast UI
path). Falls back to SD2 on any read error so chip never shows blank.

getNextRank: computes days/workouts remaining from gate map; converts
streak gap into soft day estimate (1.75d/workout cadence) for chip
copy. Returns null at Captain (terminal).

Unit tests cover gate map edge cases (SD1 boundary 6→7, LS 15→16,
PO needs deployment, SubLt needs both 100 workouts AND 104 weeks).
Regex contract test locks the upsert + onConflict invariant.
EOF
)"
```

---

## Task 3: Migration 040 — pg_cron schedule for nightly rank evaluation

**Files:**
- Create: `supabase/migrations/040_rank_promotions_cron.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/040_rank_promotions_cron.sql`:

```sql
-- ============================================================================
-- 040_rank_promotions_cron.sql
--
-- Register a pg_cron schedule for the nightly evaluate-rank-promotions
-- Edge Function. Catches users whose client-side firings missed
-- (background install, app uninstalled while a milestone passed, etc.).
--
-- Schedule: 18:30 UTC nightly  =  00:00 IST
-- Function: evaluate-rank-promotions  (verify_jwt: false, cron-only)
--
-- Uses the same private.morning_alert_get_service_key() helper as
-- migrations 031 + compute_coach_signals — auth header consistency.
--
-- Idempotent — DO/EXCEPTION wrapper unschedules any prior version
-- before re-creating, so re-applying the migration is safe.
-- ============================================================================

DO $$
BEGIN
  PERFORM cron.unschedule('evaluate_rank_promotions');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'evaluate_rank_promotions',
  '30 18 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/evaluate-rank-promotions',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $cron$
);
```

- [ ] **Step 2: Apply migration via MCP `apply_migration` tool**

Use `mcp__ba7b5e8e-...__apply_migration`:
- `project_id: "dedsavbjuwgarrhphgnl"`
- `name: "040_rank_promotions_cron"`
- `query`: paste the SQL from Step 1.

Expected: returns success.

- [ ] **Step 3: Verify the schedule is registered**

Run via `execute_sql`:

```sql
SELECT jobname, schedule, active
FROM cron.job
WHERE jobname = 'evaluate_rank_promotions';
```

Expected: one row, `schedule = '30 18 * * *'`, `active = t`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/040_rank_promotions_cron.sql
git commit -m "feat(db): migration 040 — pg_cron for evaluate-rank-promotions

Nightly 00:00 IST (18:30 UTC) job calls the new
evaluate-rank-promotions Edge Function as a safety net so users
whose client never fired (background install, uninstall during a
milestone window) still get caught up.

Same DO/EXCEPTION + cron.schedule pattern as migration 031 — uses
private.morning_alert_get_service_key for the Bearer header so the
auth flow matches every other cron job in the project."
```

---

## Task 4: Edge Function — evaluate-rank-promotions

**Files:**
- Create: `supabase/functions/_shared/rank_engine.ts`
- Create: `supabase/functions/evaluate-rank-promotions/index.ts`

- [ ] **Step 1: Write the shared rank engine**

Create `supabase/functions/_shared/rank_engine.ts`:

```typescript
// Mirror of `lib/core/services/rank_ladder_data.dart`. Update both
// files in lockstep when migration 039 ladder rows change.

export interface RankEntry {
  code: string;
  ordinal: number;
  minWeeks: number;
  isTerminal: boolean;
}

export interface RankGate {
  streakAtLeast?: number;
  totalWorkoutsAtLeast?: number;
  deploymentsCompleteAtLeast?: number;
  minWeeksSinceSignup?: number;
  maxGapDays?: number;
}

export const LADDER: RankEntry[] = [
  { code: "SD2",   ordinal: 0, minWeeks: 0,   isTerminal: false },
  { code: "SD1",   ordinal: 1, minWeeks: 1,   isTerminal: false },
  { code: "LS",    ordinal: 2, minWeeks: 4,   isTerminal: false },
  { code: "PO",    ordinal: 3, minWeeks: 12,  isTerminal: false },
  { code: "CPO",   ordinal: 4, minWeeks: 26,  isTerminal: false },
  { code: "MCPO",  ordinal: 5, minWeeks: 52,  isTerminal: false },
  { code: "SubLt", ordinal: 6, minWeeks: 104, isTerminal: false },
  { code: "LtCdr", ordinal: 7, minWeeks: 156, isTerminal: false },
  { code: "Cdr",   ordinal: 8, minWeeks: 208, isTerminal: false },
  { code: "Capt",  ordinal: 9, minWeeks: 260, isTerminal: true  },
];

export const GATES: Record<string, RankGate> = {
  SD2: {},
  SD1: { streakAtLeast: 7, minWeeksSinceSignup: 1 },
  LS:  { streakAtLeast: 16, minWeeksSinceSignup: 4 },
  PO:  { streakAtLeast: 60, minWeeksSinceSignup: 12, deploymentsCompleteAtLeast: 1 },
  CPO: { streakAtLeast: 100, minWeeksSinceSignup: 26, deploymentsCompleteAtLeast: 2 },
  MCPO: { minWeeksSinceSignup: 52, maxGapDays: 14 },
  SubLt: { totalWorkoutsAtLeast: 100, minWeeksSinceSignup: 104 },
  LtCdr: { totalWorkoutsAtLeast: 200, minWeeksSinceSignup: 156 },
  Cdr:   { totalWorkoutsAtLeast: 300, minWeeksSinceSignup: 208 },
  Capt:  { totalWorkoutsAtLeast: 500, minWeeksSinceSignup: 260, deploymentsCompleteAtLeast: 3 },
};

export interface EvalState {
  streakDays: number;
  totalWorkouts: number;
  weeksSinceSignup: number;
  deploymentsComplete: number;
  longestGapDays: number;
}

export function qualifies(code: string, s: EvalState): boolean {
  const entry = LADDER.find((r) => r.code === code);
  if (!entry) return false;
  if (s.weeksSinceSignup < entry.minWeeks) return false;
  const gate = GATES[code];
  if (gate.streakAtLeast !== undefined && s.streakDays < gate.streakAtLeast) return false;
  if (gate.totalWorkoutsAtLeast !== undefined && s.totalWorkouts < gate.totalWorkoutsAtLeast) return false;
  if (gate.minWeeksSinceSignup !== undefined && s.weeksSinceSignup < gate.minWeeksSinceSignup) return false;
  if (gate.deploymentsCompleteAtLeast !== undefined && s.deploymentsComplete < gate.deploymentsCompleteAtLeast) return false;
  if (gate.maxGapDays !== undefined && s.longestGapDays > gate.maxGapDays) return false;
  return true;
}

export function highestQualified(s: EvalState): RankEntry {
  let winner = LADDER[0];
  for (const r of LADDER) {
    if (qualifies(r.code, s)) winner = r;
  }
  return winner;
}

export function ranksUpTo(code: string): RankEntry[] {
  const target = LADDER.find((r) => r.code === code);
  if (!target) return [LADDER[0]];
  return LADDER.filter((r) => r.ordinal <= target.ordinal);
}
```

- [ ] **Step 2: Write the Edge Function**

Create `supabase/functions/evaluate-rank-promotions/index.ts`:

```typescript
/**
 * evaluate-rank-promotions — nightly cron (00:00 IST / 18:30 UTC).
 *
 * Iterates every signed-up user. For each user, recomputes the rank
 * ceiling from Postgres data (workout_logs total, signup date,
 * deployments_complete from user_progress) and upserts any missing
 * rank_promotions rows + updates the denormalized
 * user_profile.current_rank_code if it lags.
 *
 * Idempotent — UNIQUE (user_id, rank_code) means re-runs are no-ops
 * unless the user's qualified ceiling actually changed.
 *
 * verify_jwt: false  (cron-only). Auth header sent for header-shape
 * consistency with sibling cron functions.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  EvalState,
  highestQualified,
  ranksUpTo,
} from "../_shared/rank_engine.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const requestId = crypto.randomUUID().split("-")[0];

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 1. Pull the user roster (id + signup time).
    const { data: users, error: usersErr } = await supabase
      .from("users")
      .select("id, created_at");

    if (usersErr || !users) {
      console.error(`[evaluate-rank-promotions] request_id=${requestId}`, usersErr);
      return new Response(
        JSON.stringify({ error: "Internal server error", request_id: requestId }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let evaluated = 0;
    let promoted = 0;
    const now = new Date();

    for (const u of users as Array<Record<string, unknown>>) {
      const userId = u.id as string;
      const signupAt = new Date(u.created_at as string);
      const weeksSinceSignup = Math.floor(
        (now.getTime() - signupAt.getTime()) / (7 * 24 * 3600 * 1000),
      );

      // Total workouts done (cloud source of truth).
      const { count: totalWorkouts } = await supabase
        .from("workout_logs")
        .select("*", { count: "exact", head: true })
        .eq("user_id", userId);

      // Read the per-user progress row for streak + deployments.
      const { data: progressRow } = await supabase
        .from("user_progress")
        .select("current_streak_days, deployments_complete, longest_gap_days")
        .eq("user_id", userId)
        .maybeSingle();

      const state: EvalState = {
        streakDays: (progressRow?.current_streak_days as number | undefined) ?? 0,
        totalWorkouts: totalWorkouts ?? 0,
        weeksSinceSignup,
        deploymentsComplete:
          (progressRow?.deployments_complete as number | undefined) ?? 0,
        longestGapDays:
          (progressRow?.longest_gap_days as number | undefined) ?? 0,
      };

      const winner = highestQualified(state);
      const eligibleCodes = ranksUpTo(winner.code).map((r) => r.code);

      // What's already on file?
      const { data: existing } = await supabase
        .from("rank_promotions")
        .select("rank_code")
        .eq("user_id", userId);
      const existingCodes = new Set(
        (existing ?? []).map((e: Record<string, unknown>) => e.rank_code as string),
      );

      const toInsert = eligibleCodes
        .filter((c) => !existingCodes.has(c))
        .map((c) => ({
          user_id: userId,
          rank_code: c,
          trigger_type: "combined",
          trigger_metadata: {
            streak: state.streakDays,
            total_workouts: state.totalWorkouts,
            weeks: state.weeksSinceSignup,
            source: "cron",
          },
        }));

      if (toInsert.length > 0) {
        const { error: insertErr } = await supabase
          .from("rank_promotions")
          .upsert(toInsert, { onConflict: "user_id,rank_code" });
        if (insertErr) {
          console.error(
            `[evaluate-rank-promotions] user=${userId} insert err`,
            insertErr,
          );
          continue;
        }
        promoted += toInsert.length;
      }

      // Sync denormalized current rank.
      await supabase.from("user_profile").update({
        current_rank_code: winner.code,
        current_rank_achieved_at: now.toISOString(),
      }).eq("user_id", userId);

      evaluated += 1;
    }

    return new Response(
      JSON.stringify({
        status: "success",
        evaluated,
        promoted,
        request_id: requestId,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[evaluate-rank-promotions] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
```

- [ ] **Step 3: Deploy via host-shell pipeline (`verify_jwt: false`)**

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js evaluate-rank-promotions --auto --functions-dir "C:/Upendra/Claude Code/Fitness App/supabase/functions"
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl evaluate-rank-promotions ".claude/_payload_evaluate-rank-promotions.json" false --dry-run
```

Inspect dry-run output for clean payload + correct file count (expect `index.ts` + the shared helper). Then drop `--dry-run` to deploy. Expect HTTP 201.

- [ ] **Step 4: Smoke-test against the test account**

Use `mcp__ba7b5e8e-...__execute_sql` to invoke once manually:

```sql
SELECT net.http_post(
  url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/evaluate-rank-promotions',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
  ),
  body := '{}'::jsonb
);
```

Then verify:

```sql
SELECT user_id, rank_code, achieved_at, trigger_type, trigger_metadata->>'source' AS src
FROM rank_promotions
ORDER BY achieved_at DESC
LIMIT 10;
```

Expected: at minimum, `SD2` rows for every user (newly inserted by this run), with `src='cron'`.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/rank_engine.ts \
        supabase/functions/evaluate-rank-promotions/index.ts
git commit -m "$(cat <<'EOF'
feat(rank): evaluate-rank-promotions Edge Function

Nightly cron iterates every public.users row, recomputes the rank
ceiling from authoritative Postgres data, and upserts any missing
rank_promotions rows + the denorm user_profile.current_rank_code.

Catches users whose client-side firings missed (background install,
uninstall during a milestone window). Idempotent via UNIQUE
(user_id, rank_code).

Shared rank_engine.ts mirrors lib/core/services/rank_ladder_data.dart
1:1 — change both in lockstep when ladder rows change.
EOF
)"
```

---

## Task 5: RankInsignia primitive (text fallback)

**Files:**
- Create: `lib/shared/widgets/wardroom/rank_insignia.dart`

**Background:** Per spec F20, SVG asset files don't exist yet. The primitive renders the rank `shortName` (`SEAMAN 2ND`, `LEADING`, `CAPTAIN`) inside a gold-ringed seal. When `assets/rank/<code>.svg` files appear in `pubspec.yaml`, the widget can be enhanced to detect + render the SVG; for this batch we ship the text-only path.

- [ ] **Step 1: Write the primitive**

Create `lib/shared/widgets/wardroom/rank_insignia.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Renders a rank insignia badge.
///
/// In this APK Test #3 batch, SVG assets at `rank/<code>.svg` do
/// not yet exist (per spec F20). The widget therefore falls back to
/// rendering the rank's `shortName` inside a gold-ringed circular
/// seal. Once SVGs land in `pubspec.yaml`, a future PR can detect
/// the asset (via `rootBundle.load` or a build-time map) and swap
/// in the SVG.
///
/// Sizes follow Wardroom seal proportions:
///   small  16 dp — used in `RankChip`
///   medium 28 dp — used in roadmap markers + ladder rows
///   large  56 dp — used in ladder header / detail sheet
class RankInsignia extends StatelessWidget {
  const RankInsignia({
    super.key,
    required this.rankCode,
    this.size = 28,
    this.dimmed = false,
  });

  final String rankCode;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final entry = rankByCode(rankCode) ?? rankByCode('SD2')!;
    final ringColor = dimmed
        ? AppColors.textMute.withValues(alpha: 0.45)
        : AppColors.accent;
    final textColor = dimmed
        ? AppColors.textMute
        : AppColors.accent;

    // Font scales with the badge — keep the label legible at 16 dp
    // (chip) and tasteful at 56 dp (ladder header).
    final fontSize = size <= 18 ? 6.0 : size <= 32 ? 8.0 : 10.0;
    final letterSpacing = size <= 18 ? 0.6 : 1.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            entry.shortName.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: AppTypography.mono.copyWith(
              fontSize: fontSize,
              color: textColor,
              letterSpacing: letterSpacing,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Export from the Wardroom barrel**

Edit `lib/shared/widgets/wardroom/wardroom.dart` and append (in alphabetical order with the other rank exports added in Task 6):

```dart
export 'rank_insignia.dart';
```

Place it between `export 'phase_dots.dart';` (line 44) and `export 'ward_radio_row.dart';` (line 45) — keeping alphabetical order.

- [ ] **Step 3: Compile-check**

```bash
flutter analyze lib/shared/widgets/wardroom/
```

Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/widgets/wardroom/rank_insignia.dart \
        lib/shared/widgets/wardroom/wardroom.dart
git commit -m "feat(wardroom): RankInsignia primitive (text fallback)

Renders rank shortName inside a gold-ringed circular seal. Three
preset sizes (16 chip / 28 marker / 56 ladder-header). Dimmed mode
tints the ring + text textMute for locked rungs.

Per spec F20, no SVG assets ship in this batch — text fallback is
the only path. Future PR can detect rank/<code>.svg in pubspec and
swap to flutter_svg without touching call sites."
```

---

## Task 6: RankChip primitive

**Files:**
- Create: `lib/shared/widgets/wardroom/rank_chip.dart`
- Test: `test/widgets/rank_chip_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/rank_chip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/rank_chip.dart';

void main() {
  testWidgets('RankChip shows rank name + countdown', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RankChip(
            rankCode: 'SD2',
            displayName: 'SEAMAN 2ND CLASS',
            countdownText: 'NEXT IN 12 DAYS',
          ),
        ),
      ),
    );

    expect(find.text('SEAMAN 2ND CLASS'), findsOneWidget);
    expect(find.text('NEXT IN 12 DAYS'), findsOneWidget);
  });

  testWidgets('RankChip shows MAX RANK when terminal', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RankChip(
            rankCode: 'Capt',
            displayName: 'CAPTAIN',
            countdownText: null, // terminal — no next rank
            isTerminal: true,
          ),
        ),
      ),
    );

    expect(find.text('CAPTAIN'), findsOneWidget);
    expect(find.text('MAX RANK ACHIEVED'), findsOneWidget);
    expect(find.text('NEXT IN 12 DAYS'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails (file doesn't exist yet)**

```bash
flutter test test/widgets/rank_chip_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 3: Write the primitive**

Create `lib/shared/widgets/wardroom/rank_chip.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

import 'rank_insignia.dart';

/// Compact rank chip rendered as a single mono row:
///
///   [insignia 16dp] SEAMAN 2ND CLASS · NEXT IN 12 DAYS
///
/// Used on Train (top of tab content), Home (one line below streak),
/// and Profile detail sheets.
///
/// Dumb widget — pass `displayName` + `countdownText` already
/// computed from `RankService.getCurrentRank()` /
/// `RankService.getNextRank()`. Keeps the chip portable + testable
/// without spinning up Hive in a widget test.
///
/// `isTerminal` swaps the countdown for a constant `MAX RANK ACHIEVED`
/// string when the user is at Captain.
class RankChip extends StatelessWidget {
  const RankChip({
    super.key,
    required this.rankCode,
    required this.displayName,
    required this.countdownText,
    this.isTerminal = false,
    this.onTap,
  });

  final String rankCode;
  final String displayName;
  final String? countdownText;
  final bool isTerminal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final trail = isTerminal
        ? 'MAX RANK ACHIEVED'
        : (countdownText ?? 'NEXT IN —');

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.27),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RankInsignia(rankCode: rankCode, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              displayName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '·',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trail,
            maxLines: 1,
            style: AppTypography.mono.copyWith(
              fontSize: 9,
              letterSpacing: 1.0,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}
```

- [ ] **Step 4: Export from Wardroom barrel**

Edit `lib/shared/widgets/wardroom/wardroom.dart` and add `export 'rank_chip.dart';` immediately after the `rank_insignia.dart` export added in Task 5.

- [ ] **Step 5: Run the widget test**

```bash
flutter test test/widgets/rank_chip_test.dart
```

Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/widgets/wardroom/rank_chip.dart \
        lib/shared/widgets/wardroom/wardroom.dart \
        test/widgets/rank_chip_test.dart
git commit -m "feat(wardroom): RankChip primitive — single mono row

[insignia 16dp] DISPLAY NAME · NEXT IN N DAYS  (or MAX RANK ACHIEVED).

Dumb widget — caller passes display name + countdown text already
computed by RankService. Keeps the chip portable + testable without
spinning up Hive in a widget test.

Used by Home, Train, and Profile rank surfaces in subsequent tasks."
```

---

## Task 7: Wire RankService into splash + completeWorkout

**Files:**
- Modify: `lib/features/auth/screens/splash_screen.dart`
- Modify: `lib/features/train/providers/train_provider.dart` (around line 1494)

**Background:** `evaluateAndPromote` is the writer; we need it to fire on three paths — splash boot (catches users returning after a milestone-passing absence), every `completeWorkout` (catches in-session promotions like SD1 at workout 7), and the cron from Task 4 (catches everyone else).

- [ ] **Step 1: Wire into completeWorkout**

In `lib/features/train/providers/train_provider.dart`, find the existing sync triple at line 1492-1494:

```dart
    unawaited(SyncService.instance.syncWorkoutData());
    unawaited(SyncService.instance.syncProgressNow());
    unawaited(SyncService.instance.pushSnapshot());
```

Add the rank call as a fourth `unawaited` line, immediately after `pushSnapshot`:

```dart
    unawaited(SyncService.instance.syncWorkoutData());
    unawaited(SyncService.instance.syncProgressNow());
    unawaited(SyncService.instance.pushSnapshot());
    // APK Test #3 / Obs 1: re-evaluate rank on every workout. Idempotent —
    // upsert with onConflict on (user_id, rank_code). Catches in-session
    // promotions (e.g. SD1 firing on workout 7) the moment they qualify.
    unawaited(RankService.instance.evaluateAndPromote());
```

Also add the import at the top of `train_provider.dart` alongside the existing service imports:

```dart
import 'package:icanbefitter/core/services/rank_service.dart';
```

- [ ] **Step 2: Wire into splash**

Read the splash screen to find the `checkAndSync` integration point.

```bash
flutter test --no-pub --no-test-assets test/widgets/rank_chip_test.dart  # quick sanity that imports still compile
```

In `lib/features/auth/screens/splash_screen.dart`, find the place that calls `unawaited(SyncService.instance.checkAndSync(...))` (or similar) inside `_runDeferredInit` / equivalent. Append, on the line directly after the existing `unawaited(checkAndSync(...))`:

```dart
      // APK Test #3 / Obs 1: catch-up promotions for users who passed a
      // milestone while the app was uninstalled / signed out.
      unawaited(RankService.instance.evaluateAndPromote());
```

Add the import alongside the other service imports near the top of the file:

```dart
import 'package:icanbefitter/core/services/rank_service.dart';
```

- [ ] **Step 3: Compile-check**

```bash
flutter analyze lib/features/train/providers/train_provider.dart \
                lib/features/auth/screens/splash_screen.dart
```

Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/train/providers/train_provider.dart \
        lib/features/auth/screens/splash_screen.dart
git commit -m "feat(rank): fire evaluateAndPromote from splash + completeWorkout

Three writer paths now live:
  1. Splash boot (catches returning users after milestone absence)
  2. Every completeWorkout (catches in-session SD1 / LS firings)
  3. Nightly cron (catches everyone else — Task 4)

All three are unawaited fire-and-forget. Idempotent via UNIQUE
(user_id, rank_code) so race conditions between the three paths
result in 23505s the service catches and ignores."
```

---

## Task 8: Train screen — RankChip at top + Roadmap pill above This Week

**Files:**
- Modify: `lib/features/train/screens/train_screen.dart`

**Background:** Two visual changes:
1. Insert a `RankChip` at the very top of the scrolling content (above plan header).
2. The Roadmap pill currently sits between `THIS WEEK` label (line 153) and `WeekSelector` (line 200). Spec wants `DEPLOYMENT 01 — FOUNDATION (Week 1 of 12)` mono header + Roadmap pill ABOVE `THIS WEEK`. The existing position (between label and selector) becomes "above THIS WEEK" by simply lifting the label too.

- [ ] **Step 1: Insert RankChip at the top of content**

In `lib/features/train/screens/train_screen.dart`, locate the `SingleChildScrollView` body around line 104. Right after `crossAxisAlignment: CrossAxisAlignment.stretch,` (line 107) and BEFORE the `// 1. Plan header with progress bar` comment (line 109), insert:

```dart
                  // APK Test #3 / Obs 1: rank chip at top of Train
                  // tab content. Tap → roadmap. Reads denormalized
                  // current_rank_code via RankService.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding, 14, AppSpacing.screenPadding, 0),
                    child: Builder(builder: (context) {
                      final current = RankService.instance.getCurrentRank();
                      final next = RankService.instance.getNextRank();
                      return RankChip(
                        rankCode: current.entry.code,
                        displayName: current.entry.displayName,
                        countdownText: next == null
                            ? null
                            : (next.daysUntilEligible != null
                                ? 'NEXT IN ${next.daysUntilEligible} DAYS'
                                : 'NEXT IN —'),
                        isTerminal: current.entry.isTerminal,
                        onTap: () => context.push('/train/roadmap'),
                      );
                    }),
                  ),
```

Add the import alongside existing service imports near the top of the file:

```dart
import 'package:icanbefitter/core/services/rank_service.dart';
```

- [ ] **Step 2: Add the DEPLOYMENT 01 mono header above the Roadmap pill**

Still in `train_screen.dart`, find the `'THIS WEEK'` label section at line 148-159. We want the order to be:

1. `DEPLOYMENT 01 — FOUNDATION (Week N of 12)` mono header (NEW)
2. Roadmap pill (already exists, currently at line 162-197)
3. `THIS WEEK` label (already exists, currently at line 148-159)
4. `WeekSelector` (already at line 200)

So we need to **move** the `THIS WEEK` label block down and **insert** the deployment header at the top. Locate the block from line 148 (`// 3. This Week section label`) through line 197 (closing `),` of the Roadmap pill `Padding`). The cleanest swap is:

Find this block (currently line 148-160):

```dart
                    // 3. This Week section label
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      child: Text(
                        'THIS WEEK',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textMute,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
```

Replace it with the deployment header:

```dart
                    // APK Test #3 / Obs 1: deployment header above
                    // Roadmap pill. Communicates that THIS WEEK is one
                    // chapter of a 12-week deployment, not the whole story.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      child: Text(
                        'DEPLOYMENT 01 — FOUNDATION  (WEEK ${plan.currentWeek} OF 12)',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textMute,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
```

Then locate the Roadmap pill block at line 162-197 (the `// VIEW ROADMAP pill` comment + its `Padding` + `GestureDetector`) and append a `THIS WEEK` label block immediately AFTER its closing `),`:

```dart
                    // (Roadmap pill closes here at line ~197)

                    // 3. This Week section label — moved BELOW Roadmap
                    // pill per APK Test #3 / Obs 1 ordering decision.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      child: Text(
                        'THIS WEEK',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textMute,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
```

Final order in the build is:
1. RankChip
2. PlanHeader (existing)
3. Today's Workout hero card (existing)
4. **DEPLOYMENT 01 mono header** (new position)
5. **Roadmap pill** (existing, repositioned implicitly by the header swap)
6. **THIS WEEK label** (moved here from old position)
7. WeekSelector (existing)

- [ ] **Step 3: Compile + visual check**

```bash
flutter analyze lib/features/train/screens/train_screen.dart
```

Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/train/screens/train_screen.dart
git commit -m "feat(train): rank chip + deployment header reorder

Rank chip pinned at top of Train scroll content (above plan header),
tap navigates to /train/roadmap.

Section ordering above WeekSelector is now:
  DEPLOYMENT 01 — FOUNDATION (WEEK N OF 12)
  [VIEW THE 12-WEEK ROADMAP →] pill
  THIS WEEK

Was: THIS WEEK → roadmap pill → selector. New ordering communicates
the 12-week chapter framing before the user even looks at this
week's workouts."
```

---

## Task 9: Home screen — rank line below streak

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart` (header block lines 286-339; insert below header before _buildDateDisplay at line 203)

**Background:** Spec is explicit — the rank line goes "ONE LINE below streak counter, no spacing changes." The streak badge lives inside `_buildHeader` at line 332 and the header returns at line 340. The cleanest insertion is in the build method (line 200-274) immediately after `_buildHeader(ref)` (line 202).

- [ ] **Step 1: Insert RankChip in the home build**

In `lib/features/home/screens/home_screen.dart`, find the children list at line 201-204:

```dart
      padding: EdgeInsets.zero,
      children: [
        _buildHeader(ref),
        _buildDateDisplay(),
```

Replace with:

```dart
      padding: EdgeInsets.zero,
      children: [
        _buildHeader(ref),
        // APK Test #3 / Obs 1: one-line rank chip directly below the
        // streak counter inside the header. No spacing changes — sits
        // in the natural gap between header and date display.
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 6),
          child: Builder(builder: (context) {
            final current = RankService.instance.getCurrentRank();
            final next = RankService.instance.getNextRank();
            return Align(
              alignment: Alignment.centerLeft,
              child: RankChip(
                rankCode: current.entry.code,
                displayName: current.entry.displayName,
                countdownText: next == null
                    ? null
                    : (next.daysUntilEligible != null
                        ? 'NEXT IN ${next.daysUntilEligible} DAYS'
                        : 'NEXT IN —'),
                isTerminal: current.entry.isTerminal,
                onTap: () => context.push('/train/roadmap'),
              ),
            );
          }),
        ),
        _buildDateDisplay(),
```

Add the import near the existing service imports at the top:

```dart
import 'package:icanbefitter/core/services/rank_service.dart';
```

- [ ] **Step 2: Compile + smoke**

```bash
flutter analyze lib/features/home/screens/home_screen.dart
```

Expected: zero errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/home/screens/home_screen.dart
git commit -m "feat(home): rank chip below streak counter

One-line RankChip sits between header and date display. Tap routes
to /train/roadmap. Reads denormalized current_rank_code via
RankService.

Spec instruction: 'no spacing changes; slots into the existing
block.' Inserted into the natural 6-dp gap between _buildHeader and
_buildDateDisplay so the streak badge layout is untouched."
```

---

## Task 10: Profile — Service Record section above bio stats

**Files:**
- Create: `lib/features/profile/widgets/service_record_section.dart`
- Modify: `lib/features/profile/screens/profile_screen.dart` (around line 422 — insert before `ProfileIdentity`)

- [ ] **Step 1: Write the section widget**

Create `lib/features/profile/widgets/service_record_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/rank_insignia.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Profile SERVICE RECORD section.
///
/// Sits ABOVE bio stats. Two parts:
///
///   (a) Letterhead + ladder vertical list. Earned rungs render
///       with full-color insignia + earned date. Locked rungs
///       render dimmed insignia + gate description.
///
///   (b) Lifetime stats row — deployments completed / service days
///       (from auth.users.created_at) / total volume (kg).
class ServiceRecordSection extends ConsumerWidget {
  const ServiceRecordSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ladder = RankService.instance.getLadder();
    final lifetime = _readLifetimeStats();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter, 14, AppSpacing.gutter, 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WardLetterhead(
            eyebrow: 'SERVICE · RECORD',
            title: 'Lifetime ladder',
            padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
            divider: true,
          ),
          for (final entry in ladder)
            _LadderRow(entry: entry),
          const SizedBox(height: 14),
          _LifetimeStatsRow(stats: lifetime),
        ],
      ),
    );
  }

  _LifetimeStats _readLifetimeStats() {
    final user = SupabaseService.instance.currentUser;
    final progress = UserRepository.instance.getProgress() ?? {};
    final repo = WorkoutRepository.instance;

    int serviceDays = 0;
    if (user != null) {
      final createdAt = DateTime.tryParse(user.createdAt);
      if (createdAt != null) {
        serviceDays = DateTime.now().difference(createdAt).inDays;
      }
    }

    final deployments =
        (progress['deployments_complete'] as int?) ?? 0;

    // Sum lifetime volume across all exercise logs in Hive.
    double totalVolumeKg = 0;
    final hiveKeys = repo.getAllExerciseLogKeysForLifetimeSum();
    for (final v in hiveKeys) {
      totalVolumeKg += v;
    }

    return _LifetimeStats(
      deployments: deployments,
      serviceDays: serviceDays,
      totalVolumeKg: totalVolumeKg.round(),
    );
  }
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({required this.entry});

  final LadderEntryView entry;

  @override
  Widget build(BuildContext context) {
    final dim = !entry.isEarned;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          RankInsignia(
            rankCode: entry.entry.code,
            size: 28,
            dimmed: dim,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.entry.displayName.toUpperCase(),
                  style: AppTypography.mono.copyWith(
                    fontSize: 11,
                    letterSpacing: 1.3,
                    color: dim ? AppColors.textMute : AppColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.isEarned
                      ? (entry.earnedAt != null
                          ? 'Earned ${_fmtDate(entry.earnedAt!)}'
                          : 'Earned')
                      : (entry.gateText ?? 'Locked'),
                  style: AppTypography.bodyS.copyWith(
                    color: dim ? AppColors.textGhost : AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _LifetimeStats {
  final int deployments;
  final int serviceDays;
  final int totalVolumeKg;
  const _LifetimeStats({
    required this.deployments,
    required this.serviceDays,
    required this.totalVolumeKg,
  });
}

class _LifetimeStatsRow extends StatelessWidget {
  const _LifetimeStatsRow({required this.stats});
  final _LifetimeStats stats;

  @override
  Widget build(BuildContext context) {
    return WardCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(child: _stat('DEPLOYMENTS', '${stats.deployments}')),
            Container(width: 1, height: 28, color: AppColors.line2),
            Expanded(child: _stat('SERVICE DAYS', '${stats.serviceDays}')),
            Container(width: 1, height: 28, color: AppColors.line2),
            Expanded(
              child: _stat(
                'TOTAL VOLUME',
                '${stats.totalVolumeKg} kg',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTypography.mono.copyWith(
            fontSize: 9,
            letterSpacing: 1.2,
            color: AppColors.textMute,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.h3.copyWith(
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Add the lifetime-volume helper to WorkoutRepository**

The widget calls `repo.getAllExerciseLogKeysForLifetimeSum()` which doesn't exist yet. Open `lib/features/train/repositories/workout_repository.dart` and add this method anywhere in the class (e.g. near the bottom, before the closing `}`):

```dart
  /// Sum of `volume_kg` across every exercise log in Hive. Returned
  /// as a list of doubles so callers can sum / aggregate. Reads
  /// raw box once — O(n) over the workoutBox key set, called only
  /// from Profile Service Record on screen build (rare).
  List<double> getAllExerciseLogKeysForLifetimeSum() {
    final out = <double>[];
    for (final v in _hive.workoutBox.values) {
      if (v is! Map) continue;
      final type = v['type']?.toString();
      if (type != 'exercise_log') continue;
      final raw = v['volume_kg'];
      if (raw is num) out.add(raw.toDouble());
    }
    return out;
  }
```

- [ ] **Step 3: Insert ServiceRecordSection above ProfileIdentity**

In `lib/features/profile/screens/profile_screen.dart`, find the children list around line 410-422:

```dart
            children: [
              // Wardroom letterhead — mono eyebrow + Fraunces title above identity card
              const WardLetterhead(
                eyebrow: 'OFFICER · DOSSIER',
                title: 'Profile',
                padding: EdgeInsets.fromLTRB(22, 14, 22, 12),
                divider: true,
              ),
              const SizedBox(height: 10),

              // 1. Profile identity with banner + avatar
              ProfileIdentity(
```

Insert the SERVICE RECORD section between the closing `),` of the `WardLetterhead` and the `// 1. Profile identity` comment. The new block:

```dart
              const WardLetterhead(
                eyebrow: 'OFFICER · DOSSIER',
                title: 'Profile',
                padding: EdgeInsets.fromLTRB(22, 14, 22, 12),
                divider: true,
              ),
              const SizedBox(height: 10),

              // APK Test #3 / Obs 1: SERVICE RECORD above bio stats.
              // Ladder + lifetime stats. ServiceRecordSection reads
              // RankService.getLadder() + WorkoutRepository lifetime
              // volume on each rebuild (cheap; called rarely).
              const ServiceRecordSection(),

              // 1. Profile identity with banner + avatar
              ProfileIdentity(
```

Add the import to the top of the file alongside the other widget imports:

```dart
import '../widgets/service_record_section.dart';
```

- [ ] **Step 4: Compile-check**

```bash
flutter analyze lib/features/profile/screens/profile_screen.dart \
                lib/features/profile/widgets/service_record_section.dart \
                lib/features/train/repositories/workout_repository.dart
```

Expected: zero errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/widgets/service_record_section.dart \
        lib/features/profile/screens/profile_screen.dart \
        lib/features/train/repositories/workout_repository.dart
git commit -m "$(cat <<'EOF'
feat(profile): SERVICE RECORD section above bio stats

Vertical 10-rung ladder list. Earned rungs show full-color insignia
+ earned date; locked rungs show dimmed insignia + gate description
(e.g. '100 workouts to unlock Sub Lieutenant').

Lifetime stats row underneath: deployments completed (from progress
Hive map) / service days (from auth.users.created_at) / total volume
kg (sum of volume_kg across every exlog_* entry).

WorkoutRepository.getAllExerciseLogKeysForLifetimeSum is a new O(n)
helper used only from this section; called rarely on Profile build.
EOF
)"
```

---

## Task 11: Phase Roadmap rewrite — vertical timeline

**Files:**
- Modify: `lib/features/train/screens/phase_roadmap_screen.dart` (full rewrite — replaces 280 lines of card-grid layout with vertical timeline)

**Background:** The existing `PhaseRoadmapScreen` is a 3-card grid (Phase I active, II/III locked). Spec wants a vertical scroll timeline that goes from W1 to W260+ with year dividers, rank promotion markers, phase blocks, and Captain faintly visible at the far edge.

- [ ] **Step 1: Rewrite the file**

Replace `lib/features/train/screens/phase_roadmap_screen.dart` entirely:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet_phase_variant.dart';
import 'package:icanbefitter/shared/widgets/wardroom/rank_insignia.dart';

/// 12-week + lifetime phase roadmap.
///
/// Route: `/train/roadmap` (registered in app_router.dart).
///
/// Vertical timeline. Sections (top to bottom):
///   1. Header: DEPLOYMENT 01 · FOUNDATION  WK N/12  X% complete
///   2. W1 marker (current position when user is in week 1)
///   3. Phase I — Foundation (W1-4)
///      Promotion marker at W2 (SD1)
///   4. Phase II — Strength (W5-8) — PRO 🔒 for free users
///      Promotion marker at W4 (LS — between phase blocks)
///   5. Phase III — Hypertrophy (W9-12) — PRO 🔒 for free users
///   6. W12 promotion marker → PETTY OFFICER · DEBRIEF + DEPLOYMENT 02
///   7. Year 1 divider band
///   8. W26 (CPO), W52 (MCPO 1-Year Service Pin)
///   9. Year 2 divider band
///  10. W104 (Sub Lieutenant — Officer Commission, gold stripe)
///  11. Years 3-5 divider band
///  12. W156 (LtCdr), W208 (Cdr), W260 (Captain — faint)
///
/// Tap any rank marker → small detail sheet with insignia + gate +
/// progress.
class PhaseRoadmapScreen extends ConsumerWidget {
  const PhaseRoadmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = SubscriptionService.instance.isPro();
    final currentWeek = WorkoutScheduleService.instance.getCurrentWeekNumber();
    final completePct = ((currentWeek / 12) * 100).clamp(0, 100).round();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          'Roadmap',
          style: AppTypography.titleL.copyWith(fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          _DeploymentHeader(
            currentWeek: currentWeek,
            completePct: completePct,
          ),
          const SizedBox(height: 16),

          // ── Phase I (free) ────────────────────────────
          _PhaseBlock(
            number: 'I',
            name: 'FOUNDATION',
            weekRange: 'W1 – W4',
            description: 'Push / Pull / Legs · 6 ex/day',
            isLocked: false,
            isActive: currentWeek <= 4,
          ),

          _PromotionMarker(rankCode: 'SD1', whenLabel: 'W2'),
          _PromotionMarker(rankCode: 'LS', whenLabel: 'W4'),

          // ── Phase II (PRO) ────────────────────────────
          _PhaseBlock(
            number: 'II',
            name: 'STRENGTH',
            weekRange: 'W5 – W8',
            description: 'Heavier compounds, lower reps, real progression.',
            isLocked: !isPro,
            isActive: currentWeek >= 5 && currentWeek <= 8,
            onTapPreview: isPro
                ? () => context.push('/train/preview?phase=II&week=5&day=1')
                : null,
          ),

          // ── Phase III (PRO) ───────────────────────────
          _PhaseBlock(
            number: 'III',
            name: 'HYPERTROPHY',
            weekRange: 'W9 – W12',
            description: 'Volume push. Muscle-building emphasis.',
            isLocked: !isPro,
            isActive: currentWeek >= 9 && currentWeek <= 12,
            onTapPreview: isPro
                ? () => context.push('/train/preview?phase=III&week=9&day=1')
                : null,
          ),

          _PromotionMarker(
            rankCode: 'PO',
            whenLabel: 'W12 — DEBRIEF + DEPLOYMENT 02',
            emphasised: true,
          ),

          // ── Year 1 band ───────────────────────────────
          const _YearBand(label: 'YEAR 1'),
          _PromotionMarker(rankCode: 'CPO', whenLabel: 'W26'),
          _PromotionMarker(
            rankCode: 'MCPO',
            whenLabel: 'W52 · 1-YEAR SERVICE PIN',
          ),

          // ── Year 2 band ───────────────────────────────
          const _YearBand(label: 'YEAR 2'),
          _PromotionMarker(
            rankCode: 'SubLt',
            whenLabel: 'W104 · OFFICER COMMISSION',
            emphasised: true,
          ),

          // ── Years 3-5 band ────────────────────────────
          const _YearBand(label: 'YEARS 3 — 5'),
          _PromotionMarker(rankCode: 'LtCdr', whenLabel: 'W156'),
          _PromotionMarker(rankCode: 'Cdr', whenLabel: 'W208'),
          _PromotionMarker(rankCode: 'Capt', whenLabel: 'W260', faint: true),
          const SizedBox(height: 20),
        ],
      ),
      bottomNavigationBar: isPro
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => showPaywallSheetPhaseVariant(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.bg,
                    elevation: 0,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'UPGRADE TO PRO  →',
                    style: AppTypography.mono.copyWith(
                      fontSize: 13,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: AppColors.bg,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────

class _DeploymentHeader extends StatelessWidget {
  const _DeploymentHeader({
    required this.currentWeek,
    required this.completePct,
  });
  final int currentWeek;
  final int completePct;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DEPLOYMENT 01 · FOUNDATION',
          style: AppTypography.mono.copyWith(
            color: AppColors.accent,
            fontSize: 11,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'WK $currentWeek / 12  —  $completePct% complete',
          style: AppTypography.h3.copyWith(
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (currentWeek / 12).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Phase block ───────────────────────────────────────────────────

class _PhaseBlock extends StatelessWidget {
  const _PhaseBlock({
    required this.number,
    required this.name,
    required this.weekRange,
    required this.description,
    required this.isLocked,
    required this.isActive,
    this.onTapPreview,
  });

  final String number;
  final String name;
  final String weekRange;
  final String description;
  final bool isLocked;
  final bool isActive;
  final VoidCallback? onTapPreview;

  @override
  Widget build(BuildContext context) {
    final borderColor = isActive
        ? AppColors.accent
        : (isLocked
            ? AppColors.line2
            : AppColors.accent.withValues(alpha: 0.3));

    return GestureDetector(
      onTap: isLocked
          ? () => showPaywallSheetPhaseVariant(context)
          : onTapPreview,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isActive ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent),
              ),
              alignment: Alignment.center,
              child: Text(
                number,
                style: AppTypography.mono.copyWith(
                  fontSize: 12,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: AppTypography.titleL.copyWith(fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        weekRange,
                        style: AppTypography.mono.copyWith(
                          fontSize: 9,
                          letterSpacing: 1.0,
                          color: AppColors.textMute,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTypography.bodyS.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            if (isLocked)
              const Icon(Icons.lock, size: 14, color: AppColors.accent)
            else if (isActive)
              const Icon(Icons.check_circle, size: 16, color: AppColors.ok),
          ],
        ),
      ),
    );
  }
}

// ── Promotion marker ──────────────────────────────────────────────

class _PromotionMarker extends StatelessWidget {
  const _PromotionMarker({
    required this.rankCode,
    required this.whenLabel,
    this.emphasised = false,
    this.faint = false,
  });

  final String rankCode;
  final String whenLabel;
  final bool emphasised;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final entry = rankByCode(rankCode) ?? rankByCode('SD2')!;
    final opacity = faint ? 0.4 : 1.0;

    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: () => _showRankDetail(context, entry),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 32),
              Container(
                width: 1,
                height: 30,
                color: AppColors.line2,
              ),
              const SizedBox(width: 14),
              RankInsignia(
                rankCode: rankCode,
                size: emphasised ? 32 : 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName.toUpperCase(),
                      style: AppTypography.mono.copyWith(
                        fontSize: emphasised ? 11 : 10,
                        letterSpacing: 1.3,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      whenLabel,
                      style: AppTypography.bodyS.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRankDetail(BuildContext context, RankLadderEntry entry) {
    final next = RankService.instance.getNextRank();
    final current = RankService.instance.getCurrentRank();
    final isEarned = entry.ordinal <= current.entry.ordinal;
    final progressText = isEarned
        ? 'Earned'
        : (next != null && next.entry.code == entry.code
            ? (next.daysUntilEligible != null
                ? '${next.daysUntilEligible} days to go'
                : 'Working toward this rank')
            : 'Locked');

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RankInsignia(rankCode: entry.code, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayName,
                        style: AppTypography.titleL.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.minWeeks} weeks since signup minimum',
                        style: AppTypography.bodyS.copyWith(
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              progressText,
              style: AppTypography.mono.copyWith(
                color: AppColors.accent,
                fontSize: 11,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Year band ─────────────────────────────────────────────────────

class _YearBand extends StatelessWidget {
  const _YearBand({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: AppColors.line2)),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              letterSpacing: 2.0,
              color: AppColors.textMute,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: AppColors.line2)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Compile-check**

```bash
flutter analyze lib/features/train/screens/phase_roadmap_screen.dart
```

Expected: zero errors.

- [ ] **Step 3: Smoke-test in app**

(Skipped if running headless; verify manually in `/build-apk` round.) Open app → Train → tap Roadmap pill → confirm vertical timeline with W1 marker, Phase I/II/III blocks, year dividers, faint Captain at end. Tap any rank → detail sheet opens.

- [ ] **Step 4: Commit**

```bash
git add lib/features/train/screens/phase_roadmap_screen.dart
git commit -m "$(cat <<'EOF'
feat(train): roadmap rewritten as vertical timeline

Replaces the 3-card phase grid with a vertical timeline that goes
W1 → W260+ with year dividers and rank promotion markers.

Structure:
  Header — DEPLOYMENT 01 · FOUNDATION + progress bar
  Phase I/II/III blocks (II/III locked for free users)
  Promotion markers at W2/W4/W12 (SD1/LS/PO)
  YEAR 1 band → W26 (CPO), W52 (MCPO 1-Year Service Pin)
  YEAR 2 band → W104 (Sub Lt — Officer Commission, emphasised)
  YEARS 3-5 band → W156 (LtCdr), W208 (Cdr), W260 (Captain — faint)

Tap any rank marker → detail sheet with 56dp insignia, gate
description, and your progress toward it.

Free-user UPGRADE TO PRO bottom CTA preserved. Phase II/III preview
nav (PRO only) routes to /train/preview?phase=II&week=5&day=1.
EOF
)"
```

---

## Task 12: previewPlanProvider — phase exercise count fix

**Files:**
- Modify: `lib/features/train/providers/preview_plan_provider.dart` (line 60-61)
- Test: `test/contracts/preview_plan_default_test.dart`

**Background:** Spec calls out a phase exercise count mismatch: Today card shows 8 EX, roadmap preview shows 6/7/8. Root cause is the experience-level fallback in `previewPlanProvider` (line 60-61):

```dart
final experienceLevel =
    (profile['fitness_experience'] as String?) ?? 'beginner';
```

When the fallback fires, `VolumeFilter.targetCount('beginner', 5)` returns 4 — different from the user's actual onboarding default of `'intermediate'` → 6. This is the same class as APK Test #2 / F6 (`detected_experience_level` was a non-existent key — the canonical key is `fitness_experience`). For this batch, we don't need to fix the canonical key (it's already right), but the FALLBACK must match onboarding's pre-selected default.

Same applies to `daysPerWeek` (defaults to 4 — onboarding pre-selects 4 too, so already correct), and `equipment_access` (defaults to `full_gym` — onboarding pre-selects "Basic Gym" so this could drift, but spec scope is "experience + days_per_week," not equipment).

- [ ] **Step 1: Write the failing contract test**

Create `test/contracts/preview_plan_default_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #3 — phase exercise count fix.
///
/// previewPlanProvider's fallback for `fitness_experience` MUST match
/// onboarding's pre-selected default ('intermediate'). Otherwise the
/// roadmap preview generates with a beginner profile and shows 4
/// exercises while the user's actual plan (built from intermediate)
/// shows 6 — the count mismatch users surfaced in APK Test #2.
void main() {
  test('fitness_experience fallback is intermediate, not beginner', () {
    final src = File('lib/features/train/providers/preview_plan_provider.dart')
        .readAsStringSync();

    // Find the fallback line.
    final fallbackPattern = RegExp(
      r"\(profile\['fitness_experience'\] as String\?\)\s*\?\?\s*'(\w+)'",
    );
    final match = fallbackPattern.firstMatch(src);

    expect(match, isNotNull,
        reason: 'previewPlanProvider must read fitness_experience '
            'with a string fallback (NEVER null-pass to PlanGenerator).');
    expect(
      match!.group(1),
      'intermediate',
      reason: 'Fallback MUST be "intermediate" to match onboarding\'s '
          'pre-selected default. APK Test #2 / F6 lesson — using '
          '"beginner" generates a different exercise count than the '
          'user\'s actual plan (4 vs 6 ex/day for 5-day plans).',
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/contracts/preview_plan_default_test.dart
```

Expected: FAIL with reason "Fallback MUST be 'intermediate'".

- [ ] **Step 3: Fix the fallback + add a debug assertion**

In `lib/features/train/providers/preview_plan_provider.dart`, find lines 57-61:

```dart
  final goal = (profile['primary_goal'] as String?) ?? 'general_fitness';
  final equipment = (profile['equipment_access'] as String?) ?? 'full_gym';
  final daysPerWeek = (profile['days_per_week'] as int?) ?? 4;
  final experienceLevel =
      (profile['fitness_experience'] as String?) ?? 'beginner';
```

Replace with:

```dart
  final goal = (profile['primary_goal'] as String?) ?? 'general_fitness';
  final equipment = (profile['equipment_access'] as String?) ?? 'full_gym';
  final daysPerWeek = (profile['days_per_week'] as int?) ?? 4;
  // APK Test #3 / Phase exercise count fix: fallback must match
  // onboarding's pre-selected default. APK Test #2 / F6 lesson: a
  // 'beginner' fallback drives VolumeFilter.targetCount(beginner, 5) = 4
  // exercises, but the user's actual plan was built with their
  // 'intermediate' default → 6 exercises. The mismatch is the 6/7/8 vs
  // 8 confusion in roadmap previews. NEVER reset to 'beginner' here.
  final experienceLevel =
      (profile['fitness_experience'] as String?) ?? 'intermediate';

  // Debug-mode loud signal when key fields are missing — prevents the
  // silent default from hiding a profile-shape regression.
  assert(() {
    if (profile['fitness_experience'] == null) {
      // ignore: avoid_print
      print('[previewPlanProvider] WARN — fitness_experience missing on '
          'profile, falling back to "intermediate". If this fires for a '
          'real user post-onboarding, the profile shape has regressed.');
    }
    if (profile['days_per_week'] == null) {
      // ignore: avoid_print
      print('[previewPlanProvider] WARN — days_per_week missing on '
          'profile, falling back to 4.');
    }
    return true;
  }());
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/contracts/preview_plan_default_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/train/providers/preview_plan_provider.dart \
        test/contracts/preview_plan_default_test.dart
git commit -m "$(cat <<'EOF'
fix(train): previewPlanProvider fallback matches onboarding default

APK Test #3 phase exercise count fix. The roadmap preview was
generating with experience='beginner' as fallback, producing a
4-exercise day. The user's actual plan was generated with
experience='intermediate' (onboarding's pre-selected default),
producing a 6-exercise day. The 6 vs 8 vs 4 confusion users
reported in APK Test #2 traces back here.

Fallback now matches the onboarding default 1:1. Debug-mode warning
fires when the canonical key is actually missing — surfaces real
profile-shape regressions instead of silently degrading.

Same lesson class as APK Test #2 / F6 (detected_experience_level
was a non-existent key — fitness_experience is canonical).
EOF
)"
```

---

## Task 13: AI snapshot — current_rank + weeks_until_next_rank

**Files:**
- Modify: `lib/features/ai_coach/repositories/ai_coach_repository.dart` (around line 76, inside `buildAiContext`)
- Modify: `lib/core/services/ai_service.dart` (around line 119, `_compactContext` trim list)

**Background:** The AI coach should know the user's rank for greeting + nudge copy ("Promoted to Leading Seaman this week — 16-workout streak"). Two new keys, both small (~50 bytes combined). Trim order keeps them in the protected lane (drop LAST under pressure).

- [ ] **Step 1: Add rank keys to buildAiContext**

In `lib/features/ai_coach/repositories/ai_coach_repository.dart`, find the snapshot map at line 41-89. Add two new keys after `'coach_memory': _getCoachMemoryForContext(),` (line 76):

```dart
      'coach_memory': _getCoachMemoryForContext(),

      // APK Test #3 / Obs 1: rank context. Coach uses these for greeting
      // and nudge copy ("Promoted to Leading Seaman" / "16 workouts to
      // make Petty Officer"). ~50 bytes typical.
      'current_rank': _getCurrentRankSnapshot(),
      'weeks_until_next_rank': _getWeeksUntilNextRank(),

      'fitness_summary': _getFitnessSummary(),
```

Then add the two helper methods anywhere inside the class (e.g. just after `_getCoachMemoryForContext`):

```dart
  /// Compact rank summary for AI context. Reads denormalized
  /// current_rank_code (no network round-trip).
  Map<String, dynamic> _getCurrentRankSnapshot() {
    try {
      final current = RankService.instance.getCurrentRank();
      return {
        'code': current.entry.code,
        'name': current.entry.displayName,
        'category': current.entry.category,
        'ordinal': current.entry.ordinal,
      };
    } catch (e) {
      debugPrint('[AiCoachRepository._getCurrentRankSnapshot] $e');
      return {'code': 'SD2', 'name': 'Seaman 2nd Class', 'ordinal': 0};
    }
  }

  /// Weeks/workouts until the user's next promotion. Returns null when
  /// already at Capt (terminal).
  Map<String, dynamic>? _getWeeksUntilNextRank() {
    try {
      final next = RankService.instance.getNextRank();
      if (next == null) return null;
      return {
        'next_code': next.entry.code,
        'next_name': next.entry.displayName,
        if (next.daysUntilEligible != null)
          'days_remaining': next.daysUntilEligible,
        if (next.workoutsRemaining != null)
          'workouts_remaining': next.workoutsRemaining,
      };
    } catch (e) {
      debugPrint('[AiCoachRepository._getWeeksUntilNextRank] $e');
      return null;
    }
  }
```

Add the import at the top of the file alongside the existing service imports:

```dart
import 'package:icanbefitter/core/services/rank_service.dart';
```

- [ ] **Step 2: Update _compactContext trim order**

In `lib/core/services/ai_service.dart`, find the `trimSteps` const list at line 112-119:

```dart
    const trimSteps = [
      'step_history_7d',
      'weight_trend',
      'nutrition_trend',
      'exercise_history',
      'personal_records',
      'coach_notices',
    ];
```

The two new rank keys are tiny + identity-bearing — they should NEVER be trimmed (the snapshot would have to fall below `current_rank` size — ~50 bytes — for that to matter, by which point we've already dropped everything else). No change to the trim list is necessary; both keys will survive every trim path automatically because they're not in the list.

However, add a brief comment so the next reader knows this is intentional:

Replace the const block with:

```dart
    // Drop order — least load-bearing first.
    // NOTE: `current_rank` + `weeks_until_next_rank` are deliberately
    // NOT in this list. They are tiny (~50 bytes combined) and identity-
    // bearing — the coach's greeting depends on them. They survive
    // every trim path automatically.
    const trimSteps = [
      'step_history_7d',
      'weight_trend',
      'nutrition_trend',
      'exercise_history',
      'personal_records',
      'coach_notices',
    ];
```

- [ ] **Step 3: Compile-check**

```bash
flutter analyze lib/features/ai_coach/repositories/ai_coach_repository.dart \
                lib/core/services/ai_service.dart
```

Expected: zero errors.

- [ ] **Step 4: Smoke-test the snapshot shape**

```bash
flutter test test/contracts/rank_service_idempotent_test.dart
```

(Just to confirm the chain still compiles end-to-end.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_coach/repositories/ai_coach_repository.dart \
        lib/core/services/ai_service.dart
git commit -m "$(cat <<'EOF'
feat(ai): add current_rank + weeks_until_next_rank to coach snapshot

Coach now sees the user's lifetime rank context. ~50 bytes typical.

Greeting copy paths can now reference rank by name ('Welcome back,
Leading Seaman') and the next-promotion countdown ('16 workouts to
Petty Officer — you're 5 sessions deep this week, keep going').

Both keys are intentionally OUT of _compactContext's trim list —
they're tiny + identity-bearing. The fallback returns 'SD2' on any
error so the coach is never sent a bad rank shape.
EOF
)"
```

---

## Task 14: End-to-end verification

**Files:** None (verification only).

- [ ] **Step 1: Run full test suite**

```bash
flutter test
```

Expected: 100% pass. New tests added by this plan:
- `test/services/rank_service_test.dart` (gate map edge cases)
- `test/widgets/rank_chip_test.dart` (chip + terminal state)
- `test/contracts/rank_service_idempotent_test.dart` (upsert/onConflict)
- `test/contracts/preview_plan_default_test.dart` (intermediate fallback)

If anything fails, fix before proceeding to APK build.

- [ ] **Step 2: Build prod APK**

Use the `/build-apk` skill (per CLAUDE.md memory `feedback_use_build_apk_skill.md` — never `flutter build apk` directly):

```
/build-apk
```

Expected: clean build, prod flavor, release mode, output `.apk` at `build/app/outputs/flutter-apk/app-prod-release.apk`.

- [ ] **Step 3: On-device acceptance against the test account**

Install on device. Sign in as the existing test user (`upendra.prasad@thinkingcode.com` post Plan A's Bug A cleanup). Walk the spec's verification scenarios 4–8:

1. **Rank ladder.** Open Home — confirm `[insignia] SEAMAN 2ND CLASS · NEXT IN ~7 DAYS` chip below streak. Open Profile — confirm SERVICE RECORD section above bio. Tap any locked rung → detail sheet opens.
2. **Train layout.** Open Train. Confirm rank chip top, Today's Workout, then `DEPLOYMENT 01 — FOUNDATION (WEEK 1 OF 12)` mono header, then Roadmap pill, then `THIS WEEK`, then WeekSelector. Roadmap pill is ABOVE THIS WEEK (was below pre-batch).
3. **Roadmap modal.** Tap Roadmap pill → vertical scroll. W1 implicit at top, Phase I active card, year 1 / 2 / 3-5 dividers, Captain marker faintly at end. Tap a rank → detail sheet shows insignia + gate + progress.
4. **Phase exercise count.** Open Today's Workout, note the exercise count (e.g. 6 ex). Open Roadmap → tap Phase II preview → confirm preview shows the SAME exercise count (6 ex). No 4 vs 6 mismatch.
5. **Promotion firing.** Complete a workout. Open Profile → SERVICE RECORD → confirm the earned-date timestamp updated for the current rank. Use SQL `SELECT * FROM rank_promotions WHERE user_id = '00cc3dd5-...' ORDER BY achieved_at DESC` to confirm a row landed.

- [ ] **Step 4: Cron sanity (optional)**

Manually fire the cron Edge Function once via SQL:

```sql
SELECT net.http_post(
  url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/evaluate-rank-promotions',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
  ),
  body := '{}'::jsonb
);
```

Then check:

```sql
SELECT user_id, rank_code, achieved_at, trigger_metadata->>'source' AS src
FROM rank_promotions
ORDER BY achieved_at DESC
LIMIT 20;
```

Expected: at least one `src='cron'` row per existing user (newly inserted SD2 rows for any user who previously lacked them; any newly-qualified higher rungs also appear).

- [ ] **Step 5: No commit**

This is a confidence checkpoint. Plan B is complete when all four steps pass.

---

## Self-Review

**Spec coverage map (Obs 1 + Phase exercise count fix + Q6.3):**

| Spec requirement | Task # |
|---|---|
| `lib/core/services/rank_service.dart` (evaluateAndPromote, getCurrentRank, getNextRank, getLadder) | Tasks 1–2 |
| `supabase/functions/evaluate-rank-promotions/index.ts` (cron Edge Function) | Task 4 |
| Migration 040 pg_cron schedule | Task 3 |
| `lib/shared/widgets/wardroom/rank_insignia.dart` | Task 5 |
| `lib/shared/widgets/wardroom/rank_chip.dart` | Task 6 |
| Splash + completeWorkout fire `evaluateAndPromote` | Task 7 |
| Train: rank chip top + Roadmap pill above This Week + DEPLOYMENT 01 header | Task 8 |
| Home: rank line below streak | Task 9 |
| Profile: SERVICE RECORD above bio + ladder + lifetime stats row | Task 10 |
| `/train/roadmap` vertical timeline (W1, Phase I/II/III, year dividers, W260 Captain faint, tap rank → detail) | Task 11 |
| Phase exercise count fix (previewPlanProvider experience fallback) | Task 12 |
| AI snapshot expansion (`current_rank` + `weeks_until_next_rank`) — Q6.3 partial | Task 13 |
| End-to-end verification (rank fires, ladder paints, roadmap navigates, count matches) | Task 14 |

**Out of scope (filed correctly):**
- `meals_today` + `nutrition_trend_7d` (rest of Q6.3) — belongs in Plan D's nutrition redesign, not Plan B.
- W12 Debrief flow (F18) — spec out-of-scope.
- Adaptive seasons UI (F19) — spec out-of-scope.
- Rank insignia SVG asset pack (F20) — text fallback ships in Task 5; SVG swap is post-batch asset work.

**Placeholder scan:** None. Every task has concrete Dart / TypeScript / SQL with no `// TODO: implement` or `// X here` placeholders.

**Type consistency checks:**
- `rank_promotions` upsert payload (Task 2) matches the schema from Plan A migration 039 (`user_id`, `rank_code`, `trigger_type`, `trigger_metadata` JSONB; UNIQUE on `(user_id, rank_code)`). ✓
- `current_rank_code` denorm column written by Task 2 + Task 4 — both via `user_profile.update`. The column was added by migration 039 with default `'SD2'`. ✓
- `RankLadderEntry` Dart class fields match `_shared/rank_engine.ts` `RankEntry` 1:1 (code, ordinal, minWeeks, isTerminal). The Dart class has extra display fields (`displayName`, `shortName`, `insigniaAsset`, `category`) that the server doesn't need; harmless. ✓
- `RankService.evaluateAndPromote` reads `progress['total_workouts_done']` (existing Hive key, written by `train_provider.completeWorkout` line 1447). ✓
- `WorkoutRepository.calculateCurrentStreak()` is the canonical streak source per CLAUDE.md (`workout_repository.dart:84`). RankService never re-derives it. ✓
- `SupabaseService.instance.currentUser.createdAt` is a String (raw Postgres TIMESTAMPTZ) — Task 2's `DateTime.tryParse` handles. ✓
- `previewPlanProvider` fallback for `fitness_experience` is now `'intermediate'` (matches onboarding default per APK Test #2 / F6); regex test locks the value. ✓

**Cross-task dependency order:**
- Task 1 (data) → Task 2 (service) → Tasks 5, 6 (primitives can compile against service skeletons via stubs but only need the static ladder data — order is interchangeable post-Task 1).
- Task 3 (migration 040) → Task 4 (Edge Function deploy depends on the cron registration but not strictly — the schedule fires even without the function existing yet, just produces a 404 that pg_cron logs; clean order is migration first).
- Task 7 (splash + completeWorkout wiring) requires Task 2 implementation.
- Tasks 8/9/10/11 (UI) require Tasks 5/6 (primitives) and Task 2 (service).
- Task 13 (AI snapshot) requires Task 2 (service).
- Task 14 (verification) is last.

**Cross-plan dependency:** All tasks in Plan B require Plan A's Migration 039 to be applied first. If Plan A hasn't shipped, every Task 2/4 SQL upsert hits `relation "rank_promotions" does not exist` and the rank chip on UI surfaces falls back to default `'SD2'` permanently. Verify Plan A's Task 5 (live verification) passed before starting Plan B.

**Files created/modified summary:**
- 7 new Dart files (rank_ladder_data, rank_service, rank_insignia, rank_chip, service_record_section, 4 test files)
- 2 new TypeScript files (rank_engine.ts, evaluate-rank-promotions/index.ts)
- 1 new SQL migration (040_rank_promotions_cron.sql)
- 6 modified Dart files (wardroom barrel, train_screen, home_screen, profile_screen, train_provider, splash_screen, preview_plan_provider, ai_coach_repository, ai_service)
- 1 modified screen (phase_roadmap_screen full rewrite)
