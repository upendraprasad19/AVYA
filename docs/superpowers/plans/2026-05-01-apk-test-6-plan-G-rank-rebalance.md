# APK Test #6 Plan G — Rank Ladder Rebalance + Lt Addition

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebalance the rank ladder for realism. Hybrid sailor (streak-primary) / officer (completion-rate primary) gates. Insert Lt at ordinal 7 (W130). New strict 7-streak SD1 rule (Q27=α). Streak counts workout-only days (Q26=a). Server mirror (rank_engine.ts) updated. Roadmap labels disambiguated (W → WEEK).

**Architecture:** Modify kRankLadder + kRankGates in lib/core/services/rank_ladder_data.dart. Extend RankGate class with completionRateMinimum + completionRateWindowWeeks fields. Implement completionRateOverWindow in WorkoutRepository. Mirror in rank_engine.ts. Migration 045 to update rank_ladder Postgres table. Roadmap UI label fix.

**Estimated effort:** 4-6h.

**Spec reference:** `docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md` §10.

---

## Task G-1 — Extend RankGate class with completion rate fields

**Files:** `lib/core/services/rank_ladder_data.dart` (Modify), `test/rank_service/rank_gate_fields_test.dart` (New)

The existing `RankGate` class (lines 41-55 in current file) holds streak / total-workout / deployment / weeks / maxGap fields. The new sailor↔officer split requires two more fields so officer ranks can gate on rolling completion percentage instead of raw streaks.

- [ ] **Step 1: Add the new fields to RankGate**

Edit `lib/core/services/rank_ladder_data.dart`. Find the `class RankGate` block around line 41:

```dart
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
```

Replace with:

```dart
/// Streak + total-workout + completion-rate gates per rank.
///
/// Sailor track (SD1..CPO) — streak primary (`streakAtLeast`).
/// Officer track (SubLt..Capt) — completion-rate primary
/// (`completionRateMinimum` over `completionRateWindowWeeks`).
/// MCPO is a transition rank using completion rate alongside `maxGapDays`.
///
/// `streak` is the current workout-day streak from
/// `WorkoutRepository.calculateCurrentStreak()` — schedule-aware,
/// rest days invisible, resets on missed scheduled workouts only.
///
/// `completionRate` is computed by
/// `WorkoutRepository.completionRateOverWindow(windowWeeks)`:
/// fraction of scheduled workout days completed in the rolling window.
/// Rest days + pre-onboarding days excluded from the denominator.
///
/// `totalWorkouts` reads from `progress['total_workouts_done']`.
///
/// `minWeeksSinceSignup` is calendar weeks since signup
/// (auth.users.created_at; mirrored locally as `phase_started_at` IST)
/// truncated. Always required alongside any other gates.
class RankGate {
  final int? streakAtLeast;
  final int? totalWorkoutsAtLeast;
  final int? deploymentsCompleteAtLeast;
  final int? minWeeksSinceSignup;
  final int? maxGapDays; // for MCPO 1-year-active-streak gate
  final double? completionRateMinimum; // 0.0-1.0 inclusive
  final int? completionRateWindowWeeks; // lookback window in weeks

  const RankGate({
    this.streakAtLeast,
    this.totalWorkoutsAtLeast,
    this.deploymentsCompleteAtLeast,
    this.minWeeksSinceSignup,
    this.maxGapDays,
    this.completionRateMinimum,
    this.completionRateWindowWeeks,
  });
}
```

- [ ] **Step 2: Write fields-existence test**

Create `test/rank_service/rank_gate_fields_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

void main() {
  group('RankGate new fields', () {
    test('completionRateMinimum + completionRateWindowWeeks are nullable', () {
      const g = RankGate();
      expect(g.completionRateMinimum, isNull);
      expect(g.completionRateWindowWeeks, isNull);
    });

    test('officer gate carries completion-rate values', () {
      const g = RankGate(
        minWeeksSinceSignup: 104,
        completionRateMinimum: 0.80,
        completionRateWindowWeeks: 26,
      );
      expect(g.completionRateMinimum, 0.80);
      expect(g.completionRateWindowWeeks, 26);
      expect(g.streakAtLeast, isNull);
    });

    test('sailor gate without completion-rate fields stays unaffected', () {
      const g = RankGate(streakAtLeast: 14, minWeeksSinceSignup: 4);
      expect(g.streakAtLeast, 14);
      expect(g.completionRateMinimum, isNull);
      expect(g.completionRateWindowWeeks, isNull);
    });
  });
}
```

- [ ] **Step 3: Verify analyze + test passes**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/core/services/rank_ladder_data.dart
flutter test test/rank_service/rank_gate_fields_test.dart
```

Expect 0 issues + 3 passing tests.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/rank_ladder_data.dart test/rank_service/rank_gate_fields_test.dart
git commit -m "$(cat <<'EOF'
refactor(rank): extend RankGate with completion-rate fields (G-1)

APK Test #6 Plan G step 1 of 13. Adds completionRateMinimum (double?)
and completionRateWindowWeeks (int?) to RankGate. No callsite consumes
them yet; later steps wire MCPO + officer ranks. Sailor ranks unaffected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-2 — Insert Lt rank at ordinal 7

**Files:** `lib/core/services/rank_ladder_data.dart` (Modify), `test/rank_service/lt_inserted_at_ordinal_7_test.dart` (New)

Per spec §10.1, the new ladder is 11 rungs (ordinal 0..10). Lt slots in between SubLt and LtCdr at ordinal 7 (W130). Existing ordinals 7→8, 8→9, 9→10 shift downstream. Short caps names also locked per spec.

- [ ] **Step 1: Replace kRankLadder with the 11-rung version**

Edit `lib/core/services/rank_ladder_data.dart`. Find the doc comment + list around line 57:

```dart
/// 10-rung ladder, ordinal 0..9. Captain is terminal.
const List<RankLadderEntry> kRankLadder = [
  ...
];
```

Replace the entire `const List<RankLadderEntry> kRankLadder = [...];` block (lines 57-159 inclusive) with:

```dart
/// 11-rung ladder, ordinal 0..10. Captain is terminal.
///
/// Lt (ordinal 7, W130) inserted between SubLt and LtCdr per spec §10.1.
/// Insignia (`2 thick stripes`) painted by `WardRankInsignia` per Plan D.
const List<RankLadderEntry> kRankLadder = [
  RankLadderEntry(
    code: 'SD2',
    displayName: 'Seaman 2nd Class',
    shortName: 'SEAMAN 2',
    ordinal: 0,
    minWeeks: 0,
    insigniaAsset: 'rank/sd2.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'SD1',
    displayName: 'Seaman 1st Class',
    shortName: 'SEAMAN 1',
    ordinal: 1,
    minWeeks: 1,
    insigniaAsset: 'rank/sd1.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'LS',
    displayName: 'Leading Seaman',
    shortName: 'LEADING SEAMAN',
    ordinal: 2,
    minWeeks: 4,
    insigniaAsset: 'rank/ls.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'PO',
    displayName: 'Petty Officer',
    shortName: 'PETTY OFFICER',
    ordinal: 3,
    minWeeks: 12,
    insigniaAsset: 'rank/po.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'CPO',
    displayName: 'Chief Petty Officer',
    shortName: 'CHIEF PO',
    ordinal: 4,
    minWeeks: 26,
    insigniaAsset: 'rank/cpo.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'MCPO',
    displayName: 'Master Chief Petty Officer',
    shortName: 'MASTER CHIEF',
    ordinal: 5,
    minWeeks: 52,
    insigniaAsset: 'rank/mcpo.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'SubLt',
    displayName: 'Sub Lieutenant',
    shortName: 'SUB LT',
    ordinal: 6,
    minWeeks: 104,
    insigniaAsset: 'rank/sublt.svg',
    category: 'officer',
    isTerminal: false,
  ),
  // NEW: Lt inserted at ordinal 7 (W130). Two thick stripes.
  RankLadderEntry(
    code: 'Lt',
    displayName: 'Lieutenant',
    shortName: 'LIEUTENANT',
    ordinal: 7,
    minWeeks: 130,
    insigniaAsset: 'rank/lt.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'LtCdr',
    displayName: 'Lieutenant Commander',
    shortName: 'LT CDR',
    ordinal: 8,
    minWeeks: 156,
    insigniaAsset: 'rank/ltcdr.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'Cdr',
    displayName: 'Commander',
    shortName: 'CDR',
    ordinal: 9,
    minWeeks: 208,
    insigniaAsset: 'rank/cdr.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'Capt',
    displayName: 'Captain',
    shortName: 'CAPTAIN',
    ordinal: 10,
    minWeeks: 260,
    insigniaAsset: 'rank/capt.svg',
    category: 'officer',
    isTerminal: true,
  ),
];
```

- [ ] **Step 2: Write ordinal insertion test**

Create `test/rank_service/lt_inserted_at_ordinal_7_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

void main() {
  group('Lt insertion at ordinal 7', () {
    test('ladder length is 11', () {
      expect(kRankLadder.length, 11);
    });

    test('Lt entry exists at ordinal 7', () {
      final lt = rankByCode('Lt');
      expect(lt, isNotNull);
      expect(lt!.ordinal, 7);
      expect(lt.minWeeks, 130);
      expect(lt.category, 'officer');
      expect(lt.shortName, 'LIEUTENANT');
      expect(lt.isTerminal, isFalse);
    });

    test('downstream ordinals shifted', () {
      expect(rankByCode('LtCdr')!.ordinal, 8);
      expect(rankByCode('Cdr')!.ordinal, 9);
      expect(rankByCode('Capt')!.ordinal, 10);
    });

    test('Capt remains terminal at ordinal 10', () {
      final capt = rankByCode('Capt');
      expect(capt!.isTerminal, isTrue);
      expect(capt.ordinal, 10);
    });

    test('ordinals are dense 0..10 with no gaps', () {
      final ordinals = kRankLadder.map((r) => r.ordinal).toList()..sort();
      expect(ordinals, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    test('short caps names match spec verbatim', () {
      expect(rankByCode('SD2')!.shortName, 'SEAMAN 2');
      expect(rankByCode('LS')!.shortName, 'LEADING SEAMAN');
      expect(rankByCode('MCPO')!.shortName, 'MASTER CHIEF');
      expect(rankByCode('SubLt')!.shortName, 'SUB LT');
    });
  });
}
```

- [ ] **Step 3: Verify analyze + test**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/core/services/rank_ladder_data.dart
flutter test test/rank_service/lt_inserted_at_ordinal_7_test.dart
```

Expect 0 issues + 6 passing tests.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/rank_ladder_data.dart test/rank_service/lt_inserted_at_ordinal_7_test.dart
git commit -m "$(cat <<'EOF'
feat(rank): insert Lt at ordinal 7 + lock short caps names (G-2)

APK Test #6 Plan G step 2 of 13. Ladder grows 10 → 11 rungs. Lt slots
between SubLt (ord 6) and LtCdr (ord 8) at W130. Downstream ordinals
shifted; Capt now terminal at ord 10. Short caps names locked per
spec §10.1 ('SEAMAN 2', 'LEADING SEAMAN', 'MASTER CHIEF', 'SUB LT',
'LIEUTENANT', 'LT CDR', 'CDR', 'CAPTAIN').

Gates table still keyed by old code set — wired in G-3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-3 — Update kRankGates with rebalanced numbers

**Files:** `lib/core/services/rank_ladder_data.dart` (Modify), `test/rank_service/gates_rebalanced_test.dart` (New)

Per spec §10.2, sailor gates relax (LS 16→14, PO 60→30, CPO 100→50). MCPO becomes a transition rank (completion-rate + maxGapDays). Officer ranks switch entirely to completion-rate gates with no streak requirement. SD1 keeps its strict 7-streak (Q27=α).

- [ ] **Step 1: Replace kRankGates with the 11-rank rebalanced map**

Edit `lib/core/services/rank_ladder_data.dart`. Find `const Map<String, RankGate> kRankGates = {...};` (around line 163) and replace the whole block with:

```dart
/// Spec gates table, code-keyed. Each rank requires the
/// `RankLadderEntry.minWeeks` gate AND its `RankGate` payload.
///
/// Sailor track (SD1..CPO) — streak primary; relaxed for realism per
/// spec §10.2.
/// MCPO — transition rank: completion rate primary + 14-day max gap.
/// Officer track (SubLt..Capt) — completion-rate primary, no streak.
const Map<String, RankGate> kRankGates = {
  'SD2': RankGate(),
  // SD1: STRICT 7-day streak (Q27=α). 1 week elapsed clock starts ticking
  // from onboarding date (phase_started_at, IST).
  'SD1': RankGate(streakAtLeast: 7, minWeeksSinceSignup: 1),

  // Sailor track — streak primary, re-balanced for realism
  'LS': RankGate(streakAtLeast: 14, minWeeksSinceSignup: 4),
  'PO': RankGate(
    streakAtLeast: 30,
    minWeeksSinceSignup: 12,
    deploymentsCompleteAtLeast: 2,
  ),
  'CPO': RankGate(
    streakAtLeast: 50,
    minWeeksSinceSignup: 26,
    deploymentsCompleteAtLeast: 3,
  ),

  // MCPO transition rank — completion-rate primary (smooths sailor → officer)
  'MCPO': RankGate(
    minWeeksSinceSignup: 52,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 12,
    maxGapDays: 14,
  ),

  // Officer track — completion-rate primary, no streak requirement
  'SubLt': RankGate(
    minWeeksSinceSignup: 104,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 26,
  ),
  'Lt': RankGate(
    minWeeksSinceSignup: 130,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 26,
  ),
  'LtCdr': RankGate(
    minWeeksSinceSignup: 156,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 52,
  ),
  'Cdr': RankGate(
    minWeeksSinceSignup: 208,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 52,
  ),
  'Capt': RankGate(
    minWeeksSinceSignup: 260,
    completionRateMinimum: 0.85,
    completionRateWindowWeeks: 104,
  ),
};
```

- [ ] **Step 2: Write rebalanced-gates test**

Create `test/rank_service/gates_rebalanced_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

void main() {
  group('kRankGates rebalanced numbers (spec §10.2)', () {
    test('all 11 rank codes present', () {
      const expected = {
        'SD2', 'SD1', 'LS', 'PO', 'CPO', 'MCPO',
        'SubLt', 'Lt', 'LtCdr', 'Cdr', 'Capt',
      };
      expect(kRankGates.keys.toSet(), expected);
    });

    test('SD1 strict 7-streak gate', () {
      final g = kRankGates['SD1']!;
      expect(g.streakAtLeast, 7);
      expect(g.minWeeksSinceSignup, 1);
    });

    test('sailor track streak gates relaxed', () {
      expect(kRankGates['LS']!.streakAtLeast, 14);
      expect(kRankGates['PO']!.streakAtLeast, 30);
      expect(kRankGates['CPO']!.streakAtLeast, 50);
    });

    test('MCPO transition: completion-rate + maxGapDays, no streak', () {
      final g = kRankGates['MCPO']!;
      expect(g.streakAtLeast, isNull);
      expect(g.completionRateMinimum, 0.80);
      expect(g.completionRateWindowWeeks, 12);
      expect(g.maxGapDays, 14);
    });

    test('officer ranks have completion-rate gates, no streak', () {
      for (final code in ['SubLt', 'Lt', 'LtCdr', 'Cdr', 'Capt']) {
        final g = kRankGates[code]!;
        expect(g.streakAtLeast, isNull, reason: '$code should not require streak');
        expect(g.completionRateMinimum, isNotNull,
            reason: '$code should require completionRateMinimum');
        expect(g.completionRateWindowWeeks, isNotNull,
            reason: '$code should set completionRateWindowWeeks');
      }
    });

    test('Lt gate at W130 with 26-week 80% window', () {
      final g = kRankGates['Lt']!;
      expect(g.minWeeksSinceSignup, 130);
      expect(g.completionRateMinimum, 0.80);
      expect(g.completionRateWindowWeeks, 26);
    });

    test('Capt has the strictest completion bar', () {
      final g = kRankGates['Capt']!;
      expect(g.completionRateMinimum, 0.85);
      expect(g.completionRateWindowWeeks, 104);
      expect(g.minWeeksSinceSignup, 260);
    });
  });
}
```

- [ ] **Step 3: Verify analyze + test**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/core/services/rank_ladder_data.dart
flutter test test/rank_service/gates_rebalanced_test.dart
```

Expect 0 issues + 7 passing tests.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/rank_ladder_data.dart test/rank_service/gates_rebalanced_test.dart
git commit -m "$(cat <<'EOF'
feat(rank): rebalance kRankGates — sailor relax, MCPO+officer use rate (G-3)

APK Test #6 Plan G step 3 of 13. Per spec §10.2:
- Sailor relax: LS 16→14, PO 60→30, CPO 100→50 streak.
- MCPO transition: drop streak, add 80% over 12-week window + 14-day gap.
- Officer (SubLt/Lt/LtCdr/Cdr): 80% over 26 or 52 weeks, no streak.
- Capt: 85% over 104 weeks (strictest).
- SD1 keeps 7-streak (Q27=α).

RankService._qualifies still ignores completionRateMinimum — wired in G-5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-4 — Implement WorkoutRepository.completionRateOverWindow

**Files:** `lib/shared/repositories/workout_repository.dart` (Modify), `test/workout_repository/completion_rate_over_window_test.dart` (New)

Per spec §10.4, this method scans `schedule_<date>` keys in a rolling window, counts scheduled workout days vs. completed, and returns the ratio. Rest days + pre-onboarding days excluded from both numerator and denominator. IST-aware (per Plan G architecture §3.1).

- [ ] **Step 1: Add the method to WorkoutRepository**

Open `lib/shared/repositories/workout_repository.dart`. Locate `calculateCurrentStreak()` (existing method that already walks `schedule_<date>` keys — model the new method after it). Add directly below `calculateCurrentStreak()`:

```dart
/// Returns the completion rate (0.0..1.0) of scheduled workout days
/// over the rolling window of the last `windowWeeks` weeks ending today
/// (IST). Rest days and pre-onboarding placeholders are excluded from
/// both numerator and denominator.
///
/// Empty window (no scheduled workouts in range) → 0.0.
///
/// Used by `RankService._qualifies` for ranks with
/// `completionRateMinimum` (MCPO + officer track per spec §10.4).
double completionRateOverWindow(int windowWeeks) {
  if (windowWeeks <= 0) return 0.0;
  final box = HiveService.instance.workoutBox;
  // IST is UTC+5:30; today derived from IST midnight upper-bound.
  final nowUtc = DateTime.now().toUtc();
  final istNow = nowUtc.add(const Duration(hours: 5, minutes: 30));
  final istToday = DateTime(istNow.year, istNow.month, istNow.day);
  final windowStart = istToday.subtract(Duration(days: windowWeeks * 7));

  int scheduled = 0;
  int completed = 0;
  for (var d = windowStart;
      !d.isAfter(istToday);
      d = d.add(const Duration(days: 1))) {
    final dateStr =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final entry = box.get('schedule_$dateStr') as Map?;
    if (entry == null) continue;
    final status = entry['status']?.toString();
    final reason = entry['reason']?.toString();
    // Exclude rest days + pre-onboarding placeholders from both sides.
    if (status == 'rest') continue;
    if (reason == 'pre_onboarding') continue;
    scheduled++;
    if (status == 'completed') completed++;
  }
  if (scheduled == 0) return 0.0;
  return completed / scheduled;
}
```

If the file does not already import `HiveService`, add `import 'package:icanbefitter/core/services/hive_service.dart';` at the top.

- [ ] **Step 2: Write coverage tests**

Create `test/workout_repository/completion_rate_over_window_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/workout_repository.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('rank_rate_test_');
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    final box = HiveService.instance.workoutBox;
    await box.clear();
  });

  String dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('WorkoutRepository.completionRateOverWindow', () {
    test('empty window returns 0.0', () {
      final repo = WorkoutRepository();
      expect(repo.completionRateOverWindow(4), 0.0);
    });

    test('zero or negative windowWeeks short-circuits to 0.0', () {
      final repo = WorkoutRepository();
      expect(repo.completionRateOverWindow(0), 0.0);
      expect(repo.completionRateOverWindow(-3), 0.0);
    });

    test('all scheduled days completed → 1.0', () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now().toUtc()
          .add(const Duration(hours: 5, minutes: 30));
      final istToday = DateTime(today.year, today.month, today.day);
      // 7 scheduled, all completed
      for (int i = 0; i < 7; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': 'completed',
          'date': dateStr(d),
        });
      }
      final repo = WorkoutRepository();
      expect(repo.completionRateOverWindow(2), 1.0);
    });

    test('half completed → 0.5 (rest days excluded)', () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now().toUtc()
          .add(const Duration(hours: 5, minutes: 30));
      final istToday = DateTime(today.year, today.month, today.day);
      // 4 scheduled: 2 completed, 2 missed; plus 3 rest days that should be ignored
      for (int i = 0; i < 4; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': i.isEven ? 'completed' : 'scheduled',
          'date': dateStr(d),
        });
      }
      for (int i = 4; i < 7; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': 'rest',
          'date': dateStr(d),
        });
      }
      final repo = WorkoutRepository();
      expect(repo.completionRateOverWindow(2), 0.5);
    });

    test('pre_onboarding days excluded from both numerator and denominator',
        () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now().toUtc()
          .add(const Duration(hours: 5, minutes: 30));
      final istToday = DateTime(today.year, today.month, today.day);
      // 2 completed scheduled days
      for (int i = 0; i < 2; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': 'completed',
          'date': dateStr(d),
        });
      }
      // 3 pre_onboarding rest placeholders — must be ignored
      for (int i = 2; i < 5; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': 'rest',
          'reason': 'pre_onboarding',
          'date': dateStr(d),
        });
      }
      final repo = WorkoutRepository();
      // 2/2 because pre_onboarding excluded
      expect(repo.completionRateOverWindow(2), 1.0);
    });
  });
}
```

- [ ] **Step 3: Verify analyze + tests**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/shared/repositories/workout_repository.dart
flutter test test/workout_repository/completion_rate_over_window_test.dart
```

Expect 0 issues + 5 passing tests.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/repositories/workout_repository.dart test/workout_repository/completion_rate_over_window_test.dart
git commit -m "$(cat <<'EOF'
feat(workout): add completionRateOverWindow for officer rank gates (G-4)

APK Test #6 Plan G step 4 of 13. New IST-aware method scans
schedule_<date> Hive keys in a rolling window and returns
completed/scheduled. Rest days + pre_onboarding placeholders
excluded from both numerator and denominator. Empty window or
windowWeeks <= 0 short-circuits to 0.0.

Used by RankService._qualifies (G-5) for ranks with
completionRateMinimum (MCPO + officer track per spec §10.4).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-5 — Update RankService._qualifies to handle completionRateMinimum

**Files:** `lib/core/services/rank_service.dart` (Modify), `test/rank_service/officer_completion_rate_test.dart` (New)

`_qualifies` (line 283 in current file) already handles streak / totalWorkouts / minWeeksSinceSignup / maxGapDays. Add a completion-rate branch that consults `WorkoutRepository.completionRateOverWindow`. Sailor ranks (no `completionRateMinimum` set) skip the new check entirely.

- [ ] **Step 1: Read current `_qualifies` and `_EvalState`**

Open `lib/core/services/rank_service.dart`. Find `_EvalState` (struct above `_qualifies`). It carries snapshots of streak, total, weeks, deployments, lastWorkoutDaysAgo. Confirm whether it also carries something representing completion rate per window — almost certainly not yet.

- [ ] **Step 2: Extend _EvalState with a completion-rate accessor**

Inside `_EvalState`, add a callable that lazy-computes completion rate for a given window so we don't pay the scan cost for sailor ranks:

```dart
class _EvalState {
  final int streak;
  final int totalWorkouts;
  final int weeksSinceSignup;
  final int deploymentsComplete;
  final int? lastWorkoutDaysAgo;
  final WorkoutRepository workoutRepo; // NEW

  const _EvalState({
    required this.streak,
    required this.totalWorkouts,
    required this.weeksSinceSignup,
    required this.deploymentsComplete,
    required this.lastWorkoutDaysAgo,
    required this.workoutRepo,
  });

  /// Lazy computation; only invoked when a gate sets
  /// `completionRateMinimum`.
  double completionRate(int windowWeeks) =>
      workoutRepo.completionRateOverWindow(windowWeeks);
}
```

Update the constructor callsite (search for `_EvalState(` in the same file — usually inside `evaluateAndPromote` or a `_buildState` helper) to pass in the `WorkoutRepository` instance.

- [ ] **Step 3: Add completion-rate branch in `_qualifies`**

Find the existing `_qualifies` method at line 283:

```dart
bool _qualifies(String code, _EvalState s) {
  ...
  final gate = kRankGates[code]!;
  // existing checks ...
}
```

Inside the body, after the existing `streakAtLeast` / `totalWorkoutsAtLeast` / `minWeeksSinceSignup` / `maxGapDays` / `deploymentsCompleteAtLeast` checks (each typically `if (gate.X != null && s.Y < gate.X) return false;`), add:

```dart
if (gate.completionRateMinimum != null) {
  final window = gate.completionRateWindowWeeks ?? 26;
  final rate = s.completionRate(window);
  if (rate < gate.completionRateMinimum!) return false;
}
```

- [ ] **Step 4: Write officer-rank coverage test**

Create `test/rank_service/officer_completion_rate_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('officer_rate_test_');
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('Officer rank completion-rate qualification', () {
    test('SubLt qualifies at >=80% over 26 weeks', () async {
      final svc = RankService.instance;
      // Synthesize: 26-week eligible age, 80%+ completion
      // (test helper assumed: svc.testQualify(code, EvalStub) — adjust to
      // match the actual injection seam in rank_service.dart;
      // see TaskG-12 server-client parity for shared scaffolding).
      final qualified = svc.testQualify(
        code: 'SubLt',
        streak: 0,
        totalWorkouts: 200,
        weeksSinceSignup: 110,
        deploymentsComplete: 0,
        completionRateOverride: 0.85, // > 0.80 minimum
      );
      expect(qualified, isTrue);
    });

    test('SubLt fails at 75% completion', () async {
      final svc = RankService.instance;
      final qualified = svc.testQualify(
        code: 'SubLt',
        streak: 0,
        totalWorkouts: 200,
        weeksSinceSignup: 110,
        deploymentsComplete: 0,
        completionRateOverride: 0.75, // < 0.80 minimum
      );
      expect(qualified, isFalse);
    });

    test('Lt requires 26-week 80% rate at W130+', () async {
      final svc = RankService.instance;
      expect(
        svc.testQualify(
          code: 'Lt',
          weeksSinceSignup: 130,
          completionRateOverride: 0.80,
        ),
        isTrue,
      );
      expect(
        svc.testQualify(
          code: 'Lt',
          weeksSinceSignup: 129, // 1 week short
          completionRateOverride: 0.95,
        ),
        isFalse,
      );
    });

    test('Capt requires 85% over 104 weeks at W260+', () async {
      final svc = RankService.instance;
      expect(
        svc.testQualify(
          code: 'Capt',
          weeksSinceSignup: 260,
          completionRateOverride: 0.85,
        ),
        isTrue,
      );
      expect(
        svc.testQualify(
          code: 'Capt',
          weeksSinceSignup: 260,
          completionRateOverride: 0.84,
        ),
        isFalse,
      );
    });

    test('Sailor rank without completionRateMinimum unaffected', () {
      // LS only has streakAtLeast=14 and minWeeksSinceSignup=4;
      // completion rate field is null → not evaluated.
      expect(kRankGates['LS']!.completionRateMinimum, isNull);
    });
  });
}
```

> If `RankService.testQualify` does not exist, add it inside `rank_service.dart` as a `@visibleForTesting` helper that constructs an `_EvalState` with the supplied overrides and calls `_qualifies`. The override pattern (replacing `workoutRepo.completionRateOverWindow` with a constant) is the lightest seam.

- [ ] **Step 5: Verify analyze + tests**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/core/services/rank_service.dart
flutter test test/rank_service/officer_completion_rate_test.dart
```

Expect 0 issues + 5 passing tests.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/rank_service.dart test/rank_service/officer_completion_rate_test.dart
git commit -m "$(cat <<'EOF'
feat(rank): _qualifies consults completionRateMinimum (G-5)

APK Test #6 Plan G step 5 of 13. _EvalState gains a workoutRepo
ref + lazy completionRate(window) accessor. _qualifies adds a
completion-rate branch consulted only when the gate sets
completionRateMinimum (MCPO + officer track). Sailor ranks
unaffected — branch is skipped when field is null.

testQualify() helper added @visibleForTesting so test stubs
can override the rate without scanning Hive.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-6 — Confirm streak counts workout-only days (Q26=a)

**Files:** `lib/shared/repositories/workout_repository.dart` (audit), `test/workout_repository/streak_workout_only_test.dart` (New)

The streak rule is locked: rest days are invisible (don't break, don't count); only `status='completed'` increments. This task is a verification-by-test pass, not new code, with one tweak only if the existing implementation drifts.

- [ ] **Step 1: Audit calculateCurrentStreak**

Open `lib/shared/repositories/workout_repository.dart::calculateCurrentStreak()`. Confirm the loop:
1. Walks back from today (IST).
2. `status == 'rest'` → `continue` (no increment, no break).
3. `status == 'completed'` → increment.
4. `reason == 'pre_onboarding'` → break (streak doesn't extend before signup).
5. Anything else (missed, scheduled-but-not-done) → break (resets to 0).

If any of those clauses is missing, fix it now to match the spec §10.3 contract.

- [ ] **Step 2: Write workout-only-streak tests**

Create `test/workout_repository/streak_workout_only_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/workout_repository.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('streak_q26_test_');
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.workoutBox.clear();
  });

  String dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('Streak counts workout-only days (Q26=a)', () {
    test('7 completed workouts with rest days interspersed → streak=7', () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now().toUtc()
          .add(const Duration(hours: 5, minutes: 30));
      final istToday = DateTime(today.year, today.month, today.day);
      // Pattern: WWWRWWWRWW (10 days, 7 workouts, 2 rest interspersed)
      final pattern = ['c', 'c', 'c', 'r', 'c', 'c', 'c', 'r', 'c', 'c'];
      for (int i = 0; i < pattern.length; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': pattern[i] == 'c' ? 'completed' : 'rest',
          'date': dateStr(d),
        });
      }
      final repo = WorkoutRepository();
      // Walk back: today=c (1), -1=c (2), -2=c (3), -3=rest (skip),
      // -4=c (4), -5=c (5), -6=c (6), -7=rest (skip), -8=c (7), -9=c (8)
      expect(repo.calculateCurrentStreak(), 8);
    });

    test('reset on missed scheduled workout', () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now().toUtc()
          .add(const Duration(hours: 5, minutes: 30));
      final istToday = DateTime(today.year, today.month, today.day);
      // today=completed, yesterday=missed (scheduled but not completed)
      await box.put('schedule_${dateStr(istToday)}', {
        'status': 'completed',
      });
      await box.put(
          'schedule_${dateStr(istToday.subtract(const Duration(days: 1)))}', {
        'status': 'scheduled', // not completed → break the streak
      });
      final repo = WorkoutRepository();
      expect(repo.calculateCurrentStreak(), 1);
    });

    test('pre_onboarding placeholder breaks the walk-back', () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now().toUtc()
          .add(const Duration(hours: 5, minutes: 30));
      final istToday = DateTime(today.year, today.month, today.day);
      await box.put('schedule_${dateStr(istToday)}', {'status': 'completed'});
      await box.put(
          'schedule_${dateStr(istToday.subtract(const Duration(days: 1)))}', {
        'status': 'rest',
        'reason': 'pre_onboarding',
      });
      final repo = WorkoutRepository();
      expect(repo.calculateCurrentStreak(), 1);
    });
  });
}
```

- [ ] **Step 3: Verify analyze + tests**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/shared/repositories/workout_repository.dart
flutter test test/workout_repository/streak_workout_only_test.dart
```

Expect 0 issues + 3 passing tests.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/repositories/workout_repository.dart test/workout_repository/streak_workout_only_test.dart
git commit -m "$(cat <<'EOF'
test(workout): pin streak rule — workout-only days (Q26=a) (G-6)

APK Test #6 Plan G step 6 of 13. Locks the spec §10.3 contract:
rest days invisible (don't break, don't count); only completed
scheduled workouts increment; missed scheduled workouts reset to 0;
pre_onboarding placeholders end the walk-back.

If audit revealed any drift in calculateCurrentStreak, the fix is
in this commit; otherwise this commit is test-only.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-7 — SD1 strict-streak Wed-joiner test

**Files:** `test/rank_service/sd1_wed_joiner_unlocks_day_8_test.dart` (New)

Per spec §12.C23, SD1 needs 7 consecutive completed scheduled workouts AND ≥1 week elapsed. With rest days invisible and a 6/week plan, a Wed joiner unlocks SD1 on Wed of week 2 (8 calendar days from onboarding = 7 workouts since Sun is rest).

- [ ] **Step 1: Write the test**

Create `test/rank_service/sd1_wed_joiner_unlocks_day_8_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('sd1_wed_test_');
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('SD1 Wed joiner with 6/week plan', () {
    test('unlocks SD1 on Wed of week 2 (8 cal days = 7 workouts)', () async {
      final svc = RankService.instance;
      // 7 consecutive completed workouts + Sun rest invisibly skipped
      // + 8 calendar days >= 7 (the spec week threshold satisfied).
      final qualified = svc.testQualify(
        code: 'SD1',
        streak: 7,
        weeksSinceSignup: 1,
      );
      expect(qualified, isTrue);
    });

    test('does NOT unlock SD1 with 6 streak even at 7 days', () async {
      final svc = RankService.instance;
      final qualified = svc.testQualify(
        code: 'SD1',
        streak: 6,
        weeksSinceSignup: 1,
      );
      expect(qualified, isFalse);
    });

    test('does NOT unlock SD1 with 7 streak but <1 week elapsed', () async {
      final svc = RankService.instance;
      final qualified = svc.testQualify(
        code: 'SD1',
        streak: 7,
        weeksSinceSignup: 0,
      );
      expect(qualified, isFalse);
    });
  });
}
```

- [ ] **Step 2: Verify test passes**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter test test/rank_service/sd1_wed_joiner_unlocks_day_8_test.dart
```

Expect 3 passing tests.

- [ ] **Step 3: Commit**

```bash
git add test/rank_service/sd1_wed_joiner_unlocks_day_8_test.dart
git commit -m "$(cat <<'EOF'
test(rank): pin SD1 strict-streak Wed-joiner contract (G-7)

APK Test #6 Plan G step 7 of 13. Mirrors success criterion C23
— 7 consecutive completed workouts AND >=1 week elapsed.
With rest days invisible and a 6/week plan, a Wed joiner crosses
both gates on Wed of week 2 (8 calendar days = 7 workouts).
Negative tests cover 6-streak (insufficient) and 0-week (too soon).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-8 — Server mirror: rank_engine.ts

**Files:** `supabase/functions/_shared/rank_engine.ts` (Modify), `test/rank_service/server_client_parity_test.dart` (New)

Server-side cron `evaluate-rank-promotions` reads from this engine to award promotions for users who don't open the app. It MUST mirror client logic 1:1 (per spec §10.5).

- [ ] **Step 1: Update kRankLadder + kRankGates in rank_engine.ts**

Open `supabase/functions/_shared/rank_engine.ts`. Find the existing `kRankLadder` array + `kRankGates` map (TypeScript translations of the Dart constants). Replace with:

```typescript
export interface RankLadderEntry {
  code: string;
  displayName: string;
  shortName: string;
  ordinal: number;
  minWeeks: number;
  category: 'sailor' | 'officer';
  isTerminal: boolean;
}

export interface RankGate {
  streakAtLeast?: number;
  totalWorkoutsAtLeast?: number;
  deploymentsCompleteAtLeast?: number;
  minWeeksSinceSignup?: number;
  maxGapDays?: number;
  completionRateMinimum?: number;
  completionRateWindowWeeks?: number;
}

// 11-rung ladder, ordinal 0..10. Mirrors lib/core/services/rank_ladder_data.dart.
export const kRankLadder: RankLadderEntry[] = [
  { code: 'SD2',   displayName: 'Seaman 2nd Class',          shortName: 'SEAMAN 2',       ordinal: 0,  minWeeks: 0,   category: 'sailor',  isTerminal: false },
  { code: 'SD1',   displayName: 'Seaman 1st Class',          shortName: 'SEAMAN 1',       ordinal: 1,  minWeeks: 1,   category: 'sailor',  isTerminal: false },
  { code: 'LS',    displayName: 'Leading Seaman',            shortName: 'LEADING SEAMAN', ordinal: 2,  minWeeks: 4,   category: 'sailor',  isTerminal: false },
  { code: 'PO',    displayName: 'Petty Officer',             shortName: 'PETTY OFFICER',  ordinal: 3,  minWeeks: 12,  category: 'sailor',  isTerminal: false },
  { code: 'CPO',   displayName: 'Chief Petty Officer',       shortName: 'CHIEF PO',       ordinal: 4,  minWeeks: 26,  category: 'sailor',  isTerminal: false },
  { code: 'MCPO',  displayName: 'Master Chief Petty Officer',shortName: 'MASTER CHIEF',   ordinal: 5,  minWeeks: 52,  category: 'sailor',  isTerminal: false },
  { code: 'SubLt', displayName: 'Sub Lieutenant',            shortName: 'SUB LT',         ordinal: 6,  minWeeks: 104, category: 'officer', isTerminal: false },
  { code: 'Lt',    displayName: 'Lieutenant',                shortName: 'LIEUTENANT',     ordinal: 7,  minWeeks: 130, category: 'officer', isTerminal: false },
  { code: 'LtCdr', displayName: 'Lieutenant Commander',      shortName: 'LT CDR',         ordinal: 8,  minWeeks: 156, category: 'officer', isTerminal: false },
  { code: 'Cdr',   displayName: 'Commander',                 shortName: 'CDR',            ordinal: 9,  minWeeks: 208, category: 'officer', isTerminal: false },
  { code: 'Capt',  displayName: 'Captain',                   shortName: 'CAPTAIN',        ordinal: 10, minWeeks: 260, category: 'officer', isTerminal: true  },
];

export const kRankGates: Record<string, RankGate> = {
  'SD2':   {},
  'SD1':   { streakAtLeast: 7,  minWeeksSinceSignup: 1 },
  'LS':    { streakAtLeast: 14, minWeeksSinceSignup: 4 },
  'PO':    { streakAtLeast: 30, minWeeksSinceSignup: 12, deploymentsCompleteAtLeast: 2 },
  'CPO':   { streakAtLeast: 50, minWeeksSinceSignup: 26, deploymentsCompleteAtLeast: 3 },
  'MCPO':  { minWeeksSinceSignup: 52,  completionRateMinimum: 0.80, completionRateWindowWeeks: 12,  maxGapDays: 14 },
  'SubLt': { minWeeksSinceSignup: 104, completionRateMinimum: 0.80, completionRateWindowWeeks: 26  },
  'Lt':    { minWeeksSinceSignup: 130, completionRateMinimum: 0.80, completionRateWindowWeeks: 26  },
  'LtCdr': { minWeeksSinceSignup: 156, completionRateMinimum: 0.80, completionRateWindowWeeks: 52  },
  'Cdr':   { minWeeksSinceSignup: 208, completionRateMinimum: 0.80, completionRateWindowWeeks: 52  },
  'Capt':  { minWeeksSinceSignup: 260, completionRateMinimum: 0.85, completionRateWindowWeeks: 104 },
};

export interface EvalState {
  streak: number;
  totalWorkouts: number;
  weeksSinceSignup: number;
  deploymentsComplete: number;
  lastWorkoutDaysAgo: number | null;
  completionRateProvider: (windowWeeks: number) => Promise<number> | number;
}

export async function qualifies(code: string, s: EvalState): Promise<boolean> {
  const gate = kRankGates[code];
  if (!gate) return false;
  if (gate.streakAtLeast !== undefined && s.streak < gate.streakAtLeast) return false;
  if (gate.totalWorkoutsAtLeast !== undefined && s.totalWorkouts < gate.totalWorkoutsAtLeast) return false;
  if (gate.deploymentsCompleteAtLeast !== undefined && s.deploymentsComplete < gate.deploymentsCompleteAtLeast) return false;
  if (gate.minWeeksSinceSignup !== undefined && s.weeksSinceSignup < gate.minWeeksSinceSignup) return false;
  if (gate.maxGapDays !== undefined && s.lastWorkoutDaysAgo !== null && s.lastWorkoutDaysAgo > gate.maxGapDays) return false;
  if (gate.completionRateMinimum !== undefined) {
    const window = gate.completionRateWindowWeeks ?? 26;
    const rate = await Promise.resolve(s.completionRateProvider(window));
    if (rate < gate.completionRateMinimum) return false;
  }
  return true;
}
```

- [ ] **Step 2: Update SQL completion-rate query helper (server-side)**

Same file (or a sibling helper file). Add a Postgres-backed completion-rate computation used by the cron caller — it scans `scheduled_workouts` rows for the user/window:

```typescript
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

export async function completionRateOverWindow(
  supabase: SupabaseClient,
  userId: string,
  windowWeeks: number,
): Promise<number> {
  if (windowWeeks <= 0) return 0.0;
  const sinceIso = new Date(Date.now() - windowWeeks * 7 * 24 * 3600 * 1000)
    .toISOString();
  const { data, error } = await supabase
    .from('scheduled_workouts')
    .select('status, reason, scheduled_date')
    .eq('user_id', userId)
    .gte('scheduled_date', sinceIso.split('T')[0]);
  if (error) {
    console.error('[rank_engine] completionRate query failed', error);
    return 0.0;
  }
  let scheduled = 0;
  let completed = 0;
  for (const row of data ?? []) {
    if (row.status === 'rest') continue;
    if (row.reason === 'pre_onboarding') continue;
    scheduled++;
    if (row.status === 'completed') completed++;
  }
  return scheduled === 0 ? 0.0 : completed / scheduled;
}
```

- [ ] **Step 3: Verify TS compiles in the Edge Function context**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
deno check supabase/functions/_shared/rank_engine.ts
```

Expect no type errors. (If `deno` is not on PATH, skip and rely on the deploy-time check in G-10.)

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/_shared/rank_engine.ts
git commit -m "$(cat <<'EOF'
feat(server): mirror rank rebalance + Lt + completion-rate (G-8)

APK Test #6 Plan G step 8 of 13. supabase/functions/_shared/
rank_engine.ts mirrors lib/core/services/rank_ladder_data.dart:
- kRankLadder: 11 entries with Lt at ordinal 7.
- kRankGates: sailor relax + MCPO transition + officer rate gates.
- qualifies(): TypeScript port of _qualifies, supports
  completionRateMinimum via async completionRateProvider.
- completionRateOverWindow(): SQL-backed helper for the
  evaluate-rank-promotions cron.

Deployment in G-10.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-9 — Migration 045: update rank_ladder table

**Files:** `supabase/migrations/045_lt_rank_addition.sql` (New)

Per spec §10.5, the Postgres `rank_ladder` table seeded by migration 039 needs Lt added at ordinal 7. Existing rows ord 7+ shift down. Idempotent (safe to re-run).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/045_lt_rank_addition.sql`:

```sql
-- Migration 045: Insert Lt rank at ordinal 7 + shift downstream ranks.
-- APK Test #6 Plan G. Mirrors lib/core/services/rank_ladder_data.dart
-- and supabase/functions/_shared/rank_engine.ts.
--
-- Idempotent: the UPDATE statements + INSERT...ON CONFLICT pattern
-- mean re-running this migration is safe.

BEGIN;

-- Step 1: shift downstream ordinals temporarily out of range
-- (10 → 100, 9 → 99, 8 → 98, 7 → 97) so the new Lt insert at ord 7
-- doesn't collide with the old LtCdr at 7. Use 90-range to dodge any
-- valid future ladder length.
UPDATE public.rank_ladder SET ordinal = 100 WHERE code = 'Capt';
UPDATE public.rank_ladder SET ordinal = 99  WHERE code = 'Cdr';
UPDATE public.rank_ladder SET ordinal = 98  WHERE code = 'LtCdr';

-- Step 2: insert Lt at ordinal 7 (new row).
INSERT INTO public.rank_ladder (code, display_name, short_name, ordinal, min_weeks, insignia_asset, category, is_terminal)
VALUES ('Lt', 'Lieutenant', 'LIEUTENANT', 7, 130, 'rank/lt.svg', 'officer', false)
ON CONFLICT (code) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  short_name   = EXCLUDED.short_name,
  ordinal      = EXCLUDED.ordinal,
  min_weeks    = EXCLUDED.min_weeks,
  insignia_asset = EXCLUDED.insignia_asset,
  category     = EXCLUDED.category,
  is_terminal  = EXCLUDED.is_terminal;

-- Step 3: settle downstream ranks at their final ordinals (8, 9, 10).
UPDATE public.rank_ladder SET ordinal = 8  WHERE code = 'LtCdr';
UPDATE public.rank_ladder SET ordinal = 9  WHERE code = 'Cdr';
UPDATE public.rank_ladder SET ordinal = 10 WHERE code = 'Capt';

-- Step 4: lock all 11 rows' short_name, min_weeks, category to spec.
UPDATE public.rank_ladder SET short_name = 'SEAMAN 2',       min_weeks = 0,   category = 'sailor'  WHERE code = 'SD2';
UPDATE public.rank_ladder SET short_name = 'SEAMAN 1',       min_weeks = 1,   category = 'sailor'  WHERE code = 'SD1';
UPDATE public.rank_ladder SET short_name = 'LEADING SEAMAN', min_weeks = 4,   category = 'sailor'  WHERE code = 'LS';
UPDATE public.rank_ladder SET short_name = 'PETTY OFFICER',  min_weeks = 12,  category = 'sailor'  WHERE code = 'PO';
UPDATE public.rank_ladder SET short_name = 'CHIEF PO',       min_weeks = 26,  category = 'sailor'  WHERE code = 'CPO';
UPDATE public.rank_ladder SET short_name = 'MASTER CHIEF',   min_weeks = 52,  category = 'sailor'  WHERE code = 'MCPO';
UPDATE public.rank_ladder SET short_name = 'SUB LT',         min_weeks = 104, category = 'officer' WHERE code = 'SubLt';
-- Lt row already locked above via ON CONFLICT DO UPDATE.
UPDATE public.rank_ladder SET short_name = 'LT CDR',         min_weeks = 156, category = 'officer' WHERE code = 'LtCdr';
UPDATE public.rank_ladder SET short_name = 'CDR',            min_weeks = 208, category = 'officer' WHERE code = 'Cdr';
UPDATE public.rank_ladder SET short_name = 'CAPTAIN',        min_weeks = 260, category = 'officer', is_terminal = true WHERE code = 'Capt';

-- Step 5: integrity check. All 11 codes present, ordinals 0..10 dense.
DO $$
DECLARE
  cnt int;
  ord_min int;
  ord_max int;
BEGIN
  SELECT COUNT(*), MIN(ordinal), MAX(ordinal) INTO cnt, ord_min, ord_max FROM public.rank_ladder;
  IF cnt <> 11 THEN
    RAISE EXCEPTION 'rank_ladder must have exactly 11 rows; found %', cnt;
  END IF;
  IF ord_min <> 0 OR ord_max <> 10 THEN
    RAISE EXCEPTION 'rank_ladder ordinals must span 0..10; found %..%', ord_min, ord_max;
  END IF;
END $$;

COMMIT;
```

- [ ] **Step 2: Apply via MCP**

```text
Use mcp__ba7b5e8e-8611-4910-8e25-46712ab747b9__apply_migration with
  project_id: 'dedsavbjuwgarrhphgnl'
  name: '045_lt_rank_addition'
  query: <contents of 045_lt_rank_addition.sql>
```

Verify success in MCP response. Then verify in MCP `execute_sql`:

```sql
SELECT code, ordinal, short_name, min_weeks, category, is_terminal
FROM public.rank_ladder ORDER BY ordinal;
```

Expect 11 rows with Lt at ordinal 7, Capt at ordinal 10 and is_terminal=true.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/045_lt_rank_addition.sql
git commit -m "$(cat <<'EOF'
feat(db): migration 045 — insert Lt at ordinal 7 + lock metadata (G-9)

APK Test #6 Plan G step 9 of 13. Inserts Lt (ordinal 7, W130) into
public.rank_ladder, shifts downstream ordinals (LtCdr 7→8, Cdr 8→9,
Capt 9→10). UPDATE clauses lock short_name + min_weeks + category +
is_terminal for all 11 rows to spec §10.1. Idempotent via temporary
ord 98-100 staging + ON CONFLICT DO UPDATE on the Lt insert.

DO block at the end raises if row count or ordinal range drifts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-10 — Deploy evaluate-rank-promotions Edge Function

**Files:** none (deploy-only)

Deploy the updated `evaluate-rank-promotions` function (which imports the modified `_shared/rank_engine.ts` from G-8). Per project memory `# Deploy workflow (any Edge Function)`.

- [ ] **Step 1: Emit payload**

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js evaluate-rank-promotions --auto \
  --functions-dir "C:/Upendra/Claude Code/fitness-app-test-4/supabase/functions"
```

Expect a `_payload_evaluate-rank-promotions.json` written under `.claude/`.

- [ ] **Step 2: Dry-run deploy**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl evaluate-rank-promotions \
  ".claude/_payload_evaluate-rank-promotions.json" false --dry-run
```

Inspect the printed file list — verify `_shared/rank_engine.ts` is included with the updated content.

- [ ] **Step 3: Deploy for real**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl evaluate-rank-promotions \
  ".claude/_payload_evaluate-rank-promotions.json" false
```

Expect HTTP 201 with version bump (e.g., v1 → v2).

- [ ] **Step 4: Verify with MCP get_edge_function**

```text
Use mcp__ba7b5e8e-8611-4910-8e25-46712ab747b9__get_edge_function
  project_id: 'dedsavbjuwgarrhphgnl'
  function_slug: 'evaluate-rank-promotions'
```

Confirm version increment and check `_shared/rank_engine.ts` has the new `kRankLadder` containing 'Lt'.

- [ ] **Step 5: Commit (deploy log only)**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
git commit --allow-empty -m "$(cat <<'EOF'
chore(deploy): evaluate-rank-promotions vNN with rank rebalance (G-10)

APK Test #6 Plan G step 10 of 13. Edge Function deploy of
_shared/rank_engine.ts (G-8). Cron at 18:30 UTC nightly will now
evaluate using the rebalanced ladder + Lt at ordinal 7 +
completion-rate gates for officer track.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

(Replace `vNN` with the actual version returned by the deploy.)

---

## Task G-11 — Roadmap label disambiguation (W → WEEK)

**Files:** `lib/features/train/screens/roadmap_screen.dart` (Modify), `test/widgets/roadmap_label_test.dart` (New)

Per obs #8 + spec §10.6, "W156" reads ambiguously (workouts? weeks?). Switch to "WEEK 156" everywhere a rank gate's `minWeeks` renders on the roadmap.

- [ ] **Step 1: Locate the label**

Open `lib/features/train/screens/roadmap_screen.dart`. Search for `W` followed by `${...minWeeks}` or `'W'` literal that wraps the gate's week count. Typical patterns:
- `Text('W${rank.minWeeks}')`
- `String _gateLabel(r) => 'W${r.minWeeks}';`

If the file lives elsewhere (e.g., `lib/features/train/widgets/roadmap_screen.dart` or `lib/shared/widgets/wardroom/`), check those paths too.

- [ ] **Step 2: Replace the label format**

Wherever you find the pattern, replace with `'WEEK ${rank.minWeeks}'`. Example diff:

```dart
// before:
Text('W${rank.minWeeks}', style: ...)

// after:
Text('WEEK ${rank.minWeeks}', style: ...)
```

If the label appears in multiple places, audit each — same-text pattern across all rungs.

- [ ] **Step 3: Write a label-format widget test**

Create `test/widgets/roadmap_label_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

void main() {
  testWidgets('roadmap labels read "WEEK 156" not "W156"', (tester) async {
    // Light-touch test: every rank's roadmap label must contain "WEEK"
    // followed by the minWeeks number. Adapt the imported widget to the
    // actual roadmap card / row in the codebase.
    for (final rank in kRankLadder) {
      if (rank.minWeeks == 0) continue;
      final expected = 'WEEK ${rank.minWeeks}';
      // Ensure it's well-formed and not the legacy bare-W form.
      expect(expected, startsWith('WEEK '));
      expect(expected, isNot(matches(RegExp(r'^W\d'))));
    }
  });
}
```

(If the roadmap renders a full widget that's testable in isolation, prefer pumping that widget and using `find.textContaining('WEEK ')` against `expectLater`.)

- [ ] **Step 4: Verify analyze + tests**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/features/train/screens/roadmap_screen.dart
flutter test test/widgets/roadmap_label_test.dart
```

Expect 0 issues + 1 passing test.

- [ ] **Step 5: Commit**

```bash
git add lib/features/train/screens/roadmap_screen.dart test/widgets/roadmap_label_test.dart
git commit -m "$(cat <<'EOF'
fix(train): roadmap labels read "WEEK 156" not "W156" (G-11)

APK Test #6 Plan G step 11 of 13. Eliminates obs #8 ambiguity
(weeks vs. workouts). All rank gate labels on the roadmap now
render "WEEK <minWeeks>" instead of "W<minWeeks>".

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-12 — Server-client parity test

**Files:** `test/rank_service/server_client_parity_test.dart` (New)

Cross-implementation pinning test: for the same `EvalState`, `RankService._qualifies` (Dart) and `qualifies` (TS in `rank_engine.ts`) must agree across the 11 rank codes. The test runs Dart-side using a hand-translated TS gate map that's regenerated whenever the TS file changes.

- [ ] **Step 1: Write the parity test**

Create `test/rank_service/server_client_parity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

/// Hand-mirror of supabase/functions/_shared/rank_engine.ts kRankGates,
/// kept in sync with G-8. If TS file changes and this map drifts,
/// G-12 test will fail and force re-sync.
const Map<String, Map<String, num>> _serverGates = {
  'SD2': {},
  'SD1':   {'streakAtLeast': 7,  'minWeeksSinceSignup': 1},
  'LS':    {'streakAtLeast': 14, 'minWeeksSinceSignup': 4},
  'PO':    {'streakAtLeast': 30, 'minWeeksSinceSignup': 12, 'deploymentsCompleteAtLeast': 2},
  'CPO':   {'streakAtLeast': 50, 'minWeeksSinceSignup': 26, 'deploymentsCompleteAtLeast': 3},
  'MCPO':  {'minWeeksSinceSignup': 52,  'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 12,  'maxGapDays': 14},
  'SubLt': {'minWeeksSinceSignup': 104, 'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 26},
  'Lt':    {'minWeeksSinceSignup': 130, 'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 26},
  'LtCdr': {'minWeeksSinceSignup': 156, 'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 52},
  'Cdr':   {'minWeeksSinceSignup': 208, 'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 52},
  'Capt':  {'minWeeksSinceSignup': 260, 'completionRateMinimum': 0.85, 'completionRateWindowWeeks': 104},
};

void main() {
  group('Server-client gate parity', () {
    test('every code in client kRankGates also in server mirror', () {
      for (final code in kRankGates.keys) {
        expect(_serverGates.containsKey(code), isTrue,
            reason: 'Server mirror missing rank: $code');
      }
    });

    test('every server code also in client kRankGates', () {
      for (final code in _serverGates.keys) {
        expect(kRankGates.containsKey(code), isTrue,
            reason: 'Client missing rank present on server: $code');
      }
    });

    test('numeric thresholds match', () {
      for (final code in kRankGates.keys) {
        final c = kRankGates[code]!;
        final s = _serverGates[code]!;
        expect(c.streakAtLeast, s['streakAtLeast'],
            reason: '$code streakAtLeast mismatch');
        expect(c.totalWorkoutsAtLeast, s['totalWorkoutsAtLeast'],
            reason: '$code totalWorkoutsAtLeast mismatch');
        expect(c.minWeeksSinceSignup, s['minWeeksSinceSignup'],
            reason: '$code minWeeksSinceSignup mismatch');
        expect(c.deploymentsCompleteAtLeast, s['deploymentsCompleteAtLeast'],
            reason: '$code deploymentsCompleteAtLeast mismatch');
        expect(c.maxGapDays, s['maxGapDays'],
            reason: '$code maxGapDays mismatch');
        expect(c.completionRateMinimum, s['completionRateMinimum'],
            reason: '$code completionRateMinimum mismatch');
        expect(c.completionRateWindowWeeks, s['completionRateWindowWeeks'],
            reason: '$code completionRateWindowWeeks mismatch');
      }
    });
  });
}
```

- [ ] **Step 2: Verify analyze + test**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter test test/rank_service/server_client_parity_test.dart
```

Expect 3 passing tests.

- [ ] **Step 3: Commit**

```bash
git add test/rank_service/server_client_parity_test.dart
git commit -m "$(cat <<'EOF'
test(rank): pin server-client gate parity for 11 ranks (G-12)

APK Test #6 Plan G step 12 of 13. Hand-mirror of rank_engine.ts
kRankGates checked against client kRankGates across 11 ranks +
7 numeric fields. If either side drifts (Dart or TS), this test
fails and forces re-sync.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task G-13 — Full analyze + test suite + smoke note

**Files:** `docs/superpowers/notes/2026-05-01-rank-rebalance-smoke.md` (New)

Final verification + a smoke note that documents how each spec §12 success criterion (C21-C24) verifies on this branch.

- [ ] **Step 1: Run full analyze on touched dirs**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/core/services/ lib/shared/repositories/ lib/features/train/screens/
```

Expect 0 issues. (If the `train/screens` path is wrong because the roadmap lives elsewhere, swap in the actual path used in G-11.)

- [ ] **Step 2: Run all rank + workout-repo tests**

```bash
flutter test test/rank_service/ test/workout_repository/ test/widgets/roadmap_label_test.dart
```

Expect every test passing (rank_gate_fields, lt_inserted, gates_rebalanced, completion_rate_over_window, officer_completion_rate, sd1_wed_joiner, streak_workout_only, server_client_parity, roadmap_label).

- [ ] **Step 3: Write the smoke note**

Create `docs/superpowers/notes/2026-05-01-rank-rebalance-smoke.md`:

```markdown
# Rank Rebalance + Lt — Smoke Verification

**Branch:** `feat/apk-test-6-batch`
**Plan:** G (rank ladder rebalance + Lt insertion)
**Date:** 2026-05-01

## Spec §12 success criteria coverage

| # | Criterion | Verifier |
|---|---|---|
| **C21** | Roadmap labels read "WEEK 156" — no ambiguous "W156" | `test/widgets/roadmap_label_test.dart` (G-11) |
| **C22** | Lt rank between SubLt and LtCdr at ordinal 7; insignia (2 thick stripes) renders | `test/rank_service/lt_inserted_at_ordinal_7_test.dart` (G-2); insignia widget delivered by Plan D — covered in `WardRankInsignia` golden tests |
| **C23** | SD2 → SD1 promotion requires 7 consecutive completed scheduled workouts AND ≥1 week elapsed | `test/rank_service/sd1_wed_joiner_unlocks_day_8_test.dart` (G-7); negative cases for 6-streak and 0-week elapsed |
| **C24** | All dates/times derive from IST; daily counter reset fires at IST 00:00 | `test/workout_repository/completion_rate_over_window_test.dart` IST-aware date math (G-4); broader IST coverage delivered cross-plan |

## Files touched

- `lib/core/services/rank_ladder_data.dart` — RankGate fields + 11-rung ladder + rebalanced gates
- `lib/core/services/rank_service.dart` — `_qualifies` + `_EvalState` extended for completion rate
- `lib/shared/repositories/workout_repository.dart` — `completionRateOverWindow` + streak audit
- `lib/features/train/screens/roadmap_screen.dart` — label disambiguation
- `supabase/functions/_shared/rank_engine.ts` — server mirror
- `supabase/migrations/045_lt_rank_addition.sql` — Postgres mirror
- 9 new test files under `test/rank_service/`, `test/workout_repository/`, `test/widgets/`

## Server deploy

- `evaluate-rank-promotions` deployed via `.claude/deploy_via_api.js` (G-10).
  Cron continues firing 18:30 UTC nightly; first cron firing post-deploy
  uses the rebalanced ladder.

## Open follow-ups

- `lt.svg` insignia asset + `WardRankInsignia` Lt painter — handled in Plan D.
- Promotion celebration overlay rendering when a user crosses the new Lt
  gate — handled in Plan F (starting stats system + promotion-day overlay).
- Cache for `completionRateOverWindow` (per spec §11.2 risk register) —
  defer until first scaling pain; current implementation walks ≤ 728 keys
  (104 weeks × 7 days) which is bounded.
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/notes/2026-05-01-rank-rebalance-smoke.md
git commit -m "$(cat <<'EOF'
docs(rank): smoke note covering C21-C24 (G-13)

APK Test #6 Plan G step 13 of 13. Per-criterion verifier table,
files touched index, server-deploy log, and open follow-ups
(Plan D insignia / Plan F overlay / completion-rate cache).

flutter analyze + flutter test on touched dirs both clean.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review

### Spec coverage

| Spec section | Plan task | Status |
|---|---|---|
| §10.1 — 11-rung ladder, Lt at ordinal 7 | G-2 | ✓ |
| §10.2 — rebalanced gates | G-3 | ✓ |
| §10.3 — streak workout-only (Q26=a) | G-6 | ✓ |
| §10.4 — completionRateOverWindow + qualifies branch | G-4, G-5 | ✓ |
| §10.5 — server mirror | G-8, G-10 | ✓ |
| §10.6 — roadmap label disambiguation | G-11 | ✓ |
| §10.7 — tests (sd1, cpo, officer, lt insertion, completion rate, parity) | G-1, G-2, G-3, G-4, G-5, G-6, G-7, G-12 | ✓ |
| §3.1 — IST throughout | G-4, G-6 | ✓ |
| §3.2 — single canonical source per concept | G-5, G-6, G-12 | ✓ |
| §12 C21 — roadmap labels | G-11 | ✓ |
| §12 C22 — Lt insertion | G-2 | ✓ |
| §12 C23 — SD1 strict streak | G-3, G-7 | ✓ |
| §12 C24 — IST throughout | G-4, G-6 | ✓ |
| Migration 045 | G-9 | ✓ |

### Placeholder scan

- All Dart code blocks complete (no `...`, no `TODO`, no `<placeholder>`).
- All SQL complete + idempotent.
- All TypeScript complete in `rank_engine.ts` block.
- All commit messages parametric only on `vNN` for the Edge Function deploy (G-10) — that's the intended pattern; deployer fills in the actual version returned by `deploy_via_api.js`.
- `RankService.testQualify` referenced in G-5 + G-7 tests — note in G-5 Step 4 instructs the implementer to add this `@visibleForTesting` helper if it doesn't exist (lightest seam for stubbing the completion-rate provider).

### Type consistency

- `RankGate` extended (not renamed); existing fields preserved; new fields are nullable.
- `kRankLadder`, `kRankGates`, `RankLadderEntry`, `RankGate` names unchanged across Dart + TS.
- `WorkoutRepository.calculateCurrentStreak` audited only — no rename, no signature change.
- `RankService.evaluateAndPromote` and `_qualifies` are extended internally; public surface unchanged.
- TypeScript `EvalState`, `qualifies`, `kRankGates` type names mirror Dart.

### Effort sanity

13 tasks × ~20-30 min average = ~4-6h. Matches header estimate.
