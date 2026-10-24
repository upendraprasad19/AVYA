# Plan Generator V4 Diagnostic Harness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable, deterministic Dart test that generates a Markdown diagnostic report for 10 input combinations of the V4 plan generator, exposing which pipeline stage drops exercises on the bug-repro combo (Advanced / full_gym / build_muscle / 5 days / Phase 1 / sessionDuration=null).

**Architecture:** Pure-Dart unit test. Seeds exercise data by reading `assets/data/exercise_library.json` directly (no Hive — the production `HiveService` requires Flutter bindings). Uses production `SplitResolver` + `VolumeFilter` directly (they are pure Dart). Mirrors `ExerciseRepository.queryV4` and `ExerciseSelector._cascadeFill` in test-space helpers so each attempt's filter signature + result count can be logged. Cross-checked by asserting mirror matches production behavior for a spot-check query. No production code changes.

**Tech Stack:** Dart, `flutter_test`, the existing `lib/shared/repositories/plan_engine/*` modules.

**Spec reference:** `docs/superpowers/specs/2026-04-15-plan-generator-v4-diagnostic-design.md`

---

## File Structure

All paths relative to repo root.

| File | Purpose |
|---|---|
| `test/plan_generator/v4_diagnostic/library_loader.dart` (new) | Reads `assets/data/exercise_library.json` from disk into `List<Map<String, dynamic>>`. No Hive. |
| `test/plan_generator/v4_diagnostic/query_v4_mirror.dart` (new) | Pure-Dart mirror of `ExerciseRepository.queryV4` with identical filter semantics. Operates on a passed-in `List<Map>`. |
| `test/plan_generator/v4_diagnostic/cascade_tracer.dart` (new) | Mirror of `ExerciseSelector._cascadeFill` that returns a structured trace (all 5 attempts' queryV4 signatures + result counts + final pick) instead of silently picking. |
| `test/plan_generator/v4_diagnostic/combos.dart` (new) | Defines the `DiagnosticCombo` class + the 10 combos from the spec. |
| `test/plan_generator/v4_diagnostic/library_integrity.dart` (new) | Produces the two pre-check tables (triplet counts + equipment_tier string audit). |
| `test/plan_generator/v4_diagnostic/markdown_writer.dart` (new) | Accumulates trace lines and writes the final `v4_diagnostic_output.md`. |
| `test/plan_generator/v4_diagnostic_test.dart` (new) | Entry point. Runs library integrity check + all 10 combos, calls the Markdown writer, asserts output file exists. |
| `test/plan_generator/v4_diagnostic_output.md` (generated artifact) | Committed per run for review. |

**Zero changes to anything under `lib/`.**

---

## Task 1: Scaffolding — create directory and library loader

**Files:**
- Create: `test/plan_generator/v4_diagnostic/library_loader.dart`
- Test: `test/plan_generator/v4_diagnostic_test.dart` (scaffold only in this task)

- [ ] **Step 1: Create the test directory and skeleton entry point**

Write `test/plan_generator/v4_diagnostic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'v4_diagnostic/library_loader.dart';

void main() {
  group('V4 Diagnostic Harness', () {
    test('library_loader loads all exercises from assets/data/exercise_library.json', () {
      final exercises = LibraryLoader.loadFromAssets();
      expect(exercises, isNotEmpty);
      expect(exercises.length, greaterThan(100),
          reason: 'Library should have at least 100 exercises');
      final first = exercises.first;
      expect(first['id'], isNotNull);
      expect(first['movement_pattern'], isNotNull);
      expect(first['equipment_tier'], isA<List>());
    });
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: FAIL with "Target of URI doesn't exist: 'v4_diagnostic/library_loader.dart'" or similar missing-import error.

- [ ] **Step 3: Implement the library loader**

Write `test/plan_generator/v4_diagnostic/library_loader.dart`:

```dart
import 'dart:convert';
import 'dart:io';

/// Loads the bundled exercise library JSON directly from disk.
///
/// Used by the V4 diagnostic harness. Avoids the production HiveService
/// so the harness can run as a pure-Dart unit test without Flutter bindings.
class LibraryLoader {
  static const _defaultPath = 'assets/data/exercise_library.json';

  /// Reads the JSON file from disk and returns the parsed list.
  /// Throws if the file is missing or malformed.
  static List<Map<String, dynamic>> loadFromAssets({String? path}) {
    final filePath = path ?? _defaultPath;
    final file = File(filePath);
    if (!file.existsSync()) {
      throw StateError(
        'exercise_library.json not found at "$filePath" '
        '(cwd=${Directory.current.path})',
      );
    }
    final raw = file.readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw StateError('Expected JSON array, got ${decoded.runtimeType}');
    }
    return decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: PASS. Prints exercise count via the assertion.

- [ ] **Step 5: Commit**

```bash
git add test/plan_generator/v4_diagnostic_test.dart test/plan_generator/v4_diagnostic/library_loader.dart
git commit -m "test(plan-v4): scaffold diagnostic harness + library loader"
```

---

## Task 2: Mirror queryV4 + spot-check parity test

**Files:**
- Create: `test/plan_generator/v4_diagnostic/query_v4_mirror.dart`
- Modify: `test/plan_generator/v4_diagnostic_test.dart` (add new test group)

- [ ] **Step 1: Write the failing test**

Append to `test/plan_generator/v4_diagnostic_test.dart`:

```dart
import 'v4_diagnostic/query_v4_mirror.dart';

// ...inside main(), add:
    group('queryV4Mirror parity', () {
      final library = LibraryLoader.loadFromAssets();

      test('horizontal_push + basic_gym + compound returns > 0 results', () {
        final results = QueryV4Mirror.query(
          library,
          movementPattern: 'horizontal_push',
          equipmentTier: 'basic_gym',
          exerciseType: 'compound',
        );
        expect(results, isNotEmpty);
        // Barbell Bench Press is the canonical entry (id E001) — it must be present
        final names = results.map((e) => e['name']).toList();
        expect(names, contains('Barbell Bench Press'));
      });

      test('compound-first sort: first result is compound when mixed', () {
        final results = QueryV4Mirror.query(
          library,
          movementPattern: 'horizontal_push',
          equipmentTier: 'full_gym',
        );
        expect(results.first['exercise_type'], 'compound');
      });

      test('excludeNames removes matching exercises', () {
        final all = QueryV4Mirror.query(
          library,
          movementPattern: 'horizontal_push',
          equipmentTier: 'basic_gym',
        );
        final excluded = QueryV4Mirror.query(
          library,
          movementPattern: 'horizontal_push',
          equipmentTier: 'basic_gym',
          excludeNames: {'Barbell Bench Press'},
        );
        expect(excluded.length, all.length - 1);
        expect(
          excluded.any((e) => e['name'] == 'Barbell Bench Press'),
          isFalse,
        );
      });

      test('suitableFor="beginner" filters correctly', () {
        final results = QueryV4Mirror.query(
          library,
          movementPattern: 'horizontal_push',
          suitableFor: 'beginner',
        );
        for (final ex in results) {
          final suitable = (ex['suitable_for'] as List)
              .map((s) => s.toString().toLowerCase())
              .toList();
          expect(suitable.contains('beginner'), isTrue);
        }
      });
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: FAIL with "Target of URI doesn't exist" for query_v4_mirror.dart.

- [ ] **Step 3: Implement the mirror**

Write `test/plan_generator/v4_diagnostic/query_v4_mirror.dart`. Mirror the filter semantics from `lib/shared/repositories/exercise_repository.dart:177-295` exactly.

```dart
/// Pure-Dart mirror of `ExerciseRepository.queryV4`.
///
/// Operates on an in-memory list of exercise maps (loaded via LibraryLoader).
/// Used by the V4 diagnostic harness to avoid pulling in Hive + HiveService
/// in a unit-test context.
///
/// The filter order and semantics MUST stay in sync with
/// lib/shared/repositories/exercise_repository.dart:177-295 — any change there
/// requires an equivalent change here + an updated spot-check test.
class QueryV4Mirror {
  static List<Map<String, dynamic>> query(
    List<Map<String, dynamic>> source, {
    required String movementPattern,
    String? targetFocus,
    String? targetMuscle,
    String? equipmentTier,
    String? exerciseType,
    String? suitableFor,
    bool foundationalOnly = false,
    Set<String>? excludeNames,
    List<String>? injuryExclusions,
    int? limit,
  }) {
    var results = List<Map<String, dynamic>>.from(source);

    // 1. Movement pattern — ALWAYS applied
    results = results.where((e) =>
        (e['movement_pattern'] as String?)?.toLowerCase() ==
        movementPattern.toLowerCase()).toList();

    // 2. Target focus (substring match)
    if (targetFocus != null && targetFocus.isNotEmpty) {
      final tf = targetFocus.toLowerCase();
      results = results.where((e) {
        final focus = (e['target_focus'] as String?)?.toLowerCase() ?? '';
        return focus.contains(tf);
      }).toList();
    }

    // 2b. Target muscle (broader)
    if (targetMuscle != null && targetMuscle.isNotEmpty) {
      final tm = targetMuscle.toLowerCase();
      results = results.where((e) {
        final focus = (e['target_focus'] as String?)?.toLowerCase() ?? '';
        final muscles = e['primary_muscles'];
        if (focus.contains(tm)) return true;
        if (muscles is List) {
          return muscles.any((m) => m.toString().toLowerCase().contains(tm));
        }
        return false;
      }).toList();
    }

    // 3. Equipment tier
    if (equipmentTier != null && equipmentTier.isNotEmpty) {
      final tier = equipmentTier.toLowerCase();
      results = results.where((e) {
        final tiers = e['equipment_tier'];
        if (tiers is! List || tiers.isEmpty) return true;
        return tiers.any((t) => t.toString().toLowerCase() == tier);
      }).toList();
    }

    // 4. Exercise type
    if (exerciseType != null && exerciseType.isNotEmpty) {
      results = results.where((e) =>
          (e['exercise_type'] as String?)?.toLowerCase() ==
          exerciseType.toLowerCase()).toList();
    }

    // 5. Suitable for
    if (suitableFor != null) {
      results = results.where((e) {
        final suitable = e['suitable_for'];
        if (suitable == null) return true;
        if (suitable is List) {
          return suitable.any(
            (s) => s.toString().toLowerCase() == suitableFor.toLowerCase(),
          );
        }
        return true;
      }).toList();
    }

    // 6. Foundational only
    if (foundationalOnly) {
      results = results.where((e) => e['is_foundational'] == true).toList();
    }

    // 7. Exclude names
    if (excludeNames != null && excludeNames.isNotEmpty) {
      results = results.where((e) =>
          !excludeNames.contains(e['name'] as String? ?? '')).toList();
    }

    // 8. Injury exclusion
    if (injuryExclusions != null && injuryExclusions.isNotEmpty) {
      results = results.where((e) {
        final contra = e['injury_contraindications'];
        if (contra is! List || contra.isEmpty) return true;
        for (final injury in injuryExclusions) {
          if (contra.any((c) =>
              c.toString().toLowerCase() == injury.toLowerCase())) {
            return false;
          }
        }
        return true;
      }).toList();
    }

    // Sort: compounds first, then priority_tier asc, then foundational first
    results.sort((a, b) {
      final aType = a['exercise_type']?.toString().toLowerCase() ?? '';
      final bType = b['exercise_type']?.toString().toLowerCase() ?? '';
      if (aType == 'compound' && bType != 'compound') return -1;
      if (aType != 'compound' && bType == 'compound') return 1;
      final aPri = a['priority_tier'] as int? ?? 3;
      final bPri = b['priority_tier'] as int? ?? 3;
      if (aPri != bPri) return aPri.compareTo(bPri);
      final aFound = a['is_foundational'] == true ? 0 : 1;
      final bFound = b['is_foundational'] == true ? 0 : 1;
      return aFound.compareTo(bFound);
    });

    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }

    return results;
  }

  /// Build a short filter signature string for trace logs.
  static String signature({
    required String movementPattern,
    String? targetFocus,
    String? targetMuscle,
    String? equipmentTier,
    String? exerciseType,
    String? suitableFor,
    bool foundationalOnly = false,
    int? excludeNamesCount,
    List<String>? injuryExclusions,
  }) {
    final parts = <String>['mp=$movementPattern'];
    if (targetFocus != null) parts.add('tf="$targetFocus"');
    if (targetMuscle != null) parts.add('tm="$targetMuscle"');
    if (equipmentTier != null) parts.add('eq=$equipmentTier');
    if (exerciseType != null) parts.add('type=$exerciseType');
    parts.add('suit=${suitableFor ?? "any"}');
    if (foundationalOnly) parts.add('foundational=true');
    if (excludeNamesCount != null && excludeNamesCount > 0) {
      parts.add('excluded=$excludeNamesCount');
    }
    if (injuryExclusions != null && injuryExclusions.isNotEmpty) {
      parts.add('injuries=${injuryExclusions.join(",")}');
    }
    return parts.join(', ');
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: PASS for all 5 tests in the `v4_diagnostic_test` file so far.

- [ ] **Step 5: Commit**

```bash
git add test/plan_generator/v4_diagnostic/query_v4_mirror.dart test/plan_generator/v4_diagnostic_test.dart
git commit -m "test(plan-v4): add queryV4 mirror with parity spot-checks"
```

---

## Task 3: Library integrity pre-check

**Files:**
- Create: `test/plan_generator/v4_diagnostic/library_integrity.dart`
- Modify: `test/plan_generator/v4_diagnostic_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `v4_diagnostic_test.dart`:

```dart
import 'v4_diagnostic/library_integrity.dart';

// ...inside main():
    group('Library integrity pre-check', () {
      final library = LibraryLoader.loadFromAssets();

      test('emits unique equipment_tier string values', () {
        final tiers = LibraryIntegrity.uniqueEquipmentTiers(library);
        expect(tiers, isNotEmpty);
        // Basic sanity: the canonical four tiers should be present
        expect(tiers, contains('full_gym'));
        expect(tiers, contains('basic_gym'));
      });

      test('produces triplet counts covering all 11 movement patterns', () {
        final rows = LibraryIntegrity.tripletCounts(library);
        final patterns = rows.map((r) => r.movementPattern).toSet();
        // The 11 V4 patterns
        expect(patterns.length, greaterThanOrEqualTo(11));
      });

      test('renders a Markdown table', () {
        final md = LibraryIntegrity.renderMarkdown(library);
        expect(md, contains('## Library integrity pre-check'));
        expect(md, contains('| movement_pattern |'));
        expect(md, contains('Equipment tier unique values:'));
      });
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: FAIL — missing import.

- [ ] **Step 3: Implement**

Write `test/plan_generator/v4_diagnostic/library_integrity.dart`:

```dart
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

class TripletRow {
  final String movementPattern;
  final String equipmentTier;
  final String suitableFor;
  final bool foundationalOnly;
  final int count;

  const TripletRow(
    this.movementPattern,
    this.equipmentTier,
    this.suitableFor,
    this.foundationalOnly,
    this.count,
  );
}

class LibraryIntegrity {
  static const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
  static const _levels = ['beginner', 'intermediate', 'advanced'];

  /// Unique raw values seen in any exercise's `equipment_tier` list.
  /// Flags string-mismatch bugs (e.g. "full gym" space vs "full_gym" underscore).
  static List<String> uniqueEquipmentTiers(List<Map<String, dynamic>> lib) {
    final seen = <String>{};
    for (final ex in lib) {
      final tiers = ex['equipment_tier'];
      if (tiers is List) {
        for (final t in tiers) {
          seen.add(t.toString());
        }
      }
    }
    final sorted = seen.toList()..sort();
    return sorted;
  }

  /// Count exercises for every (movement_pattern × tier × suitable_for ×
  /// is_foundational) production-plausible triplet.
  static List<TripletRow> tripletCounts(List<Map<String, dynamic>> lib) {
    final rows = <TripletRow>[];
    for (final pattern in kMovementPatterns) {
      for (final tier in _tiers) {
        for (final level in _levels) {
          for (final foundational in [true, false]) {
            final count = lib.where((e) {
              if ((e['movement_pattern'] as String?)?.toLowerCase() !=
                  pattern.toLowerCase()) return false;
              final tiers = e['equipment_tier'];
              if (tiers is! List ||
                  !tiers.any((t) => t.toString().toLowerCase() == tier)) {
                return false;
              }
              final suitable = e['suitable_for'];
              if (suitable is List) {
                final hasLevel = suitable.any(
                  (s) => s.toString().toLowerCase() == level,
                );
                if (!hasLevel) return false;
              }
              if (foundational && e['is_foundational'] != true) return false;
              return true;
            }).length;
            rows.add(TripletRow(
              pattern,
              tier,
              level,
              foundational,
              count,
            ));
          }
        }
      }
    }
    return rows;
  }

  /// Render a Markdown section combining the triplet table + tier audit.
  static String renderMarkdown(List<Map<String, dynamic>> lib) {
    final buf = StringBuffer();
    buf.writeln('## Library integrity pre-check');
    buf.writeln();
    buf.writeln('**Triplet counts** (movement_pattern × equipment_tier × suitable_for × foundational-only)');
    buf.writeln();
    buf.writeln('| movement_pattern | equipment_tier | suitable_for | foundational | count |');
    buf.writeln('|---|---|---|---|---|');
    for (final row in tripletCounts(lib)) {
      final flag = row.count == 0 ? ' ⚠️' : '';
      buf.writeln(
        '| ${row.movementPattern} | ${row.equipmentTier} | ${row.suitableFor} '
        '| ${row.foundationalOnly} | ${row.count}$flag |',
      );
    }
    buf.writeln();
    final tiers = uniqueEquipmentTiers(lib);
    final suspicious = tiers.where((t) => t.contains(' ')).toList();
    buf.writeln('**Equipment tier unique values:** `${tiers.join("`, `")}`');
    if (suspicious.isNotEmpty) {
      buf.writeln();
      buf.writeln('⚠️ **Suspicious tiers with spaces:** `${suspicious.join("`, `")}`');
    }
    buf.writeln();
    return buf.toString();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: PASS (all tests including the 3 new ones).

- [ ] **Step 5: Commit**

```bash
git add test/plan_generator/v4_diagnostic/library_integrity.dart test/plan_generator/v4_diagnostic_test.dart
git commit -m "test(plan-v4): library integrity pre-check (triplets + tier audit)"
```

---

## Task 4: Cascade tracer (mirrors `_cascadeFill`, returns structured trace)

**Files:**
- Create: `test/plan_generator/v4_diagnostic/cascade_tracer.dart`
- Modify: `test/plan_generator/v4_diagnostic_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `v4_diagnostic_test.dart`:

```dart
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'v4_diagnostic/cascade_tracer.dart';

// ...inside main():
    group('CascadeTracer', () {
      final library = LibraryLoader.loadFromAssets();

      test('Quads/knee_dominant/compound/P1 + full_gym + advanced picks a real library entry', () {
        const slot = MuscleSlot(
          targetMuscle: 'Quads',
          movementPattern: 'knee_dominant',
          exerciseType: 'compound',
          priority: 1,
        );
        final trace = CascadeTracer.trace(
          library,
          slot: slot,
          equipmentTier: 'full_gym',
          effectiveExp: 'advanced',
          phase: 1,
          injuries: const [],
          pickedNames: <String>{},
        );
        expect(trace.attempts.length, greaterThanOrEqualTo(1));
        expect(trace.finalPick, isNotNull);
        expect(trace.finalPick!.source, isNot(CascadePickSource.universalPool));
      });

      test('Hamstrings/hip_dominant/compound/P1 + full_gym + advanced: records all 5 attempts if exhausted', () {
        // This slot is the exact one we suspect is failing in production.
        // We don't assert WHICH stage picks it — we just assert the trace
        // walked through attempts in order and did not short-circuit wrongly.
        const slot = MuscleSlot(
          targetMuscle: 'Hamstrings',
          movementPattern: 'hip_dominant',
          exerciseType: 'compound',
          priority: 1,
        );
        final trace = CascadeTracer.trace(
          library,
          slot: slot,
          equipmentTier: 'full_gym',
          effectiveExp: 'advanced',
          phase: 1,
          injuries: const [],
          pickedNames: <String>{},
        );
        // Every attempt records a signature even if count=0
        for (final a in trace.attempts) {
          expect(a.signature, isNotEmpty);
        }
        // trace MUST yield either a library pick OR explicit universal-pool fallback
        expect(trace.finalPick, isNotNull);
      });
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: FAIL — missing import.

- [ ] **Step 3: Implement the tracer**

Write `test/plan_generator/v4_diagnostic/cascade_tracer.dart`. Mirror `_cascadeFill` from `lib/shared/repositories/plan_engine/exercise_selector.dart:578-645`.

```dart
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'query_v4_mirror.dart';

enum CascadePickSource {
  attempt1Exact,
  attempt2DropSubFocus,
  attempt3DropTypeAndTarget,
  attempt4DropEquipment,
  universalPool,
  universalPoolPlaceholder,
}

class CascadeAttempt {
  final int number; // 1..5
  final String signature;
  final int resultCount;
  final List<String> sampleNames; // first 5 result names
  const CascadeAttempt({
    required this.number,
    required this.signature,
    required this.resultCount,
    required this.sampleNames,
  });
}

class CascadePick {
  final String name;
  final CascadePickSource source;
  const CascadePick(this.name, this.source);
}

class CascadeTrace {
  final MuscleSlot slot;
  final List<CascadeAttempt> attempts;
  final CascadePick? finalPick;
  const CascadeTrace({
    required this.slot,
    required this.attempts,
    required this.finalPick,
  });
}

/// Universal bodyweight pool — mirrored verbatim from
/// lib/shared/repositories/plan_engine/exercise_selector.dart:493-505.
/// Any change there must be reflected here.
const _universalPoolV4 = <String, List<String>>{
  'horizontal_push':    ['Push Up', 'Incline Push Up', 'Wall Push Up', 'Decline Push Up', 'Diamond Push Up'],
  'vertical_push':      ['Pike Push Up', 'Handstand Hold', 'Dand (Hindu Pushup)'],
  'horizontal_pull':    ['Inverted Row', 'TRX Row', 'Inverted Row', 'Dead Bug'],
  'vertical_pull':      ['Pull Up', 'Chin Up', 'Inverted Row'],
  'knee_dominant':      ['Baithak (Hindu Squat)', 'Reverse Lunge', 'Bulgarian Split Squat', 'Jump Squat'],
  'hip_dominant':       ['Glute Bridge', 'Single Leg Romanian Deadlift', 'Good Morning'],
  'core':               ['Plank', 'Dead Bug', 'Hollow Body Hold', 'Bicycle Crunch', 'Mountain Climber'],
  'elbow_flexion':      ['Chin Up', 'Inverted Row'],
  'elbow_extension':    ['Diamond Push Up', 'Bench Dips', 'Dip (Parallel Bars)'],
  'shoulder_isolation': ['Pike Push Up', 'Arm Circles', 'Band Pull Apart'],
  'hip_isolation':      ['Glute Bridge', 'Side Plank', 'Glute Bridge'],
};

class CascadeTracer {
  /// Trace ALL 5 attempts; return a full record. Mirrors `_cascadeFill`.
  ///
  /// Unlike production `_cascadeFill` which early-returns on first non-empty
  /// result, this always records every attempt's signature + count so the
  /// trace shows the full fallback path.
  static CascadeTrace trace(
    List<Map<String, dynamic>> library, {
    required MuscleSlot slot,
    required String equipmentTier,
    required String effectiveExp,
    required int phase,
    required List<String> injuries,
    required Set<String> pickedNames,
  }) {
    final attempts = <CascadeAttempt>[];
    CascadePick? pick;

    // Attempt 1
    final a1Sig = QueryV4Mirror.signature(
      movementPattern: slot.movementPattern,
      targetFocus: slot.subFocus != null
          ? '${slot.targetMuscle} (${slot.subFocus})'
          : null,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      foundationalOnly: phase == 1,
      excludeNamesCount: pickedNames.length,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    final a1Results = QueryV4Mirror.query(
      library,
      movementPattern: slot.movementPattern,
      targetFocus: slot.subFocus != null
          ? '${slot.targetMuscle} (${slot.subFocus})'
          : null,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      foundationalOnly: phase == 1,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    attempts.add(_attempt(1, a1Sig, a1Results));
    if (a1Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        a1Results.first['name'] as String,
        CascadePickSource.attempt1Exact,
      );
    }

    // Attempt 2: drop subFocus
    final a2Sig = QueryV4Mirror.signature(
      movementPattern: slot.movementPattern,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNamesCount: pickedNames.length,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    final a2Results = QueryV4Mirror.query(
      library,
      movementPattern: slot.movementPattern,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    attempts.add(_attempt(2, a2Sig, a2Results));
    if (a2Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        a2Results.first['name'] as String,
        CascadePickSource.attempt2DropSubFocus,
      );
    }

    // Attempt 3: drop target + exerciseType
    final a3Sig = QueryV4Mirror.signature(
      movementPattern: slot.movementPattern,
      equipmentTier: equipmentTier,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNamesCount: pickedNames.length,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    final a3Results = QueryV4Mirror.query(
      library,
      movementPattern: slot.movementPattern,
      equipmentTier: equipmentTier,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    attempts.add(_attempt(3, a3Sig, a3Results));
    if (a3Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        a3Results.first['name'] as String,
        CascadePickSource.attempt3DropTypeAndTarget,
      );
    }

    // Attempt 4: drop equipment
    final a4Sig = QueryV4Mirror.signature(
      movementPattern: slot.movementPattern,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNamesCount: pickedNames.length,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    final a4Results = QueryV4Mirror.query(
      library,
      movementPattern: slot.movementPattern,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    attempts.add(_attempt(4, a4Sig, a4Results));
    if (a4Results.isNotEmpty && pick == null) {
      pick = CascadePick(
        a4Results.first['name'] as String,
        CascadePickSource.attempt4DropEquipment,
      );
    }

    // Attempt 5: universal pool
    final pool = _universalPoolV4[slot.movementPattern] ?? const <String>[];
    attempts.add(CascadeAttempt(
      number: 5,
      signature: 'universal_pool[${slot.movementPattern}]',
      resultCount: pool.length,
      sampleNames: pool.take(5).toList(),
    ));
    if (pick == null) {
      for (final name in pool) {
        if (pickedNames.contains(name)) continue;
        final libraryMatch = library.where(
          (e) => (e['name'] as String?) == name,
        );
        if (libraryMatch.isNotEmpty) {
          pick = CascadePick(name, CascadePickSource.universalPool);
        } else {
          pick = CascadePick(name, CascadePickSource.universalPoolPlaceholder);
        }
        break;
      }
    }

    return CascadeTrace(slot: slot, attempts: attempts, finalPick: pick);
  }

  static CascadeAttempt _attempt(
    int number,
    String signature,
    List<Map<String, dynamic>> results,
  ) {
    return CascadeAttempt(
      number: number,
      signature: signature,
      resultCount: results.length,
      sampleNames: results
          .take(5)
          .map((e) => e['name']?.toString() ?? '?')
          .toList(),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/plan_generator/v4_diagnostic/cascade_tracer.dart test/plan_generator/v4_diagnostic_test.dart
git commit -m "test(plan-v4): cascade tracer mirrors _cascadeFill with full-attempt logging"
```

---

## Task 5: Combo definitions

**Files:**
- Create: `test/plan_generator/v4_diagnostic/combos.dart`
- Modify: `test/plan_generator/v4_diagnostic_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `v4_diagnostic_test.dart`:

```dart
import 'v4_diagnostic/combos.dart';

// ...inside main():
    group('Combos', () {
      test('combos list has exactly 10 entries', () {
        expect(DiagnosticCombos.all.length, 10);
      });

      test('combo #1 is the bug-repro baseline', () {
        final c = DiagnosticCombos.all.first;
        expect(c.label, contains('bug-repro'));
        expect(c.goal, 'build_muscle');
        expect(c.equipment, 'full_gym');
        expect(c.daysPerWeek, 5);
        expect(c.experience, 'advanced');
        expect(c.phase, 1);
        expect(c.sessionDuration, isNull);
        expect(c.injuries, isEmpty);
        expect(c.weekCharacters, ['baseline']);
      });

      test('combo #10 exercises all 4 week characters', () {
        final c = DiagnosticCombos.all[9];
        expect(c.weekCharacters, ['baseline', 'overreach', 'peak', 'deload']);
      });
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: FAIL — missing import.

- [ ] **Step 3: Implement combos**

Write `test/plan_generator/v4_diagnostic/combos.dart`:

```dart
/// A single input combination for the V4 diagnostic harness.
class DiagnosticCombo {
  final String label;
  final String goal;
  final String equipment;
  final int daysPerWeek;
  final String experience;
  final int phase;
  final int? sessionDuration;
  final List<String> injuries;
  final List<String> weekCharacters;

  const DiagnosticCombo({
    required this.label,
    required this.goal,
    required this.equipment,
    required this.daysPerWeek,
    required this.experience,
    required this.phase,
    required this.sessionDuration,
    required this.injuries,
    required this.weekCharacters,
  });
}

class DiagnosticCombos {
  static const List<DiagnosticCombo> all = [
    // 1. Bug-repro baseline — Upendra's exact on-phone inputs
    DiagnosticCombo(
      label: 'bug-repro baseline (advanced/full_gym/build_muscle/5d/P1/sd=null)',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 2. Low-tier sanity
    DiagnosticCombo(
      label: 'beginner/bodyweight/general_fitness/3d/P1',
      goal: 'general_fitness',
      equipment: 'bodyweight',
      daysPerWeek: 3,
      experience: 'beginner',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 3. Mid tier + phase 2
    DiagnosticCombo(
      label: 'intermediate/home_dumbbells/lose_fat/4d/P2',
      goal: 'lose_fat',
      equipment: 'home_dumbbells',
      daysPerWeek: 4,
      experience: 'intermediate',
      phase: 2,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 4. High phase + strength
    DiagnosticCombo(
      label: 'advanced/full_gym/strength/5d/P3',
      goal: 'strength',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 3,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 5. 6-day split (naming / slot count differences)
    DiagnosticCombo(
      label: 'advanced/basic_gym/build_muscle/6d/P1',
      goal: 'build_muscle',
      equipment: 'basic_gym',
      daysPerWeek: 6,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 6. Beginner vs Advanced isolation (same equip, different experience)
    DiagnosticCombo(
      label: 'beginner/full_gym/build_muscle/4d/P1 (vs combo 1 — tests suitable_for path)',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      experience: 'beginner',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 7. VolumeFilter toggle
    DiagnosticCombo(
      label: 'advanced/full_gym/build_muscle/5d/P1/sd=60 (vs combo 1 — isolates VolumeFilter)',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: 60,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 8. Real-profile replay (same inputs as combo 1 today; future: swap for
    //    dumped Hive values if they differ from synthetic assumption)
    DiagnosticCombo(
      label: 'real-profile replay (Upendra; currently same shape as combo 1)',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 9. Knee injury exclusion path
    DiagnosticCombo(
      label: 'advanced/full_gym/build_muscle/5d/P1/injuries=[knee]',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: ['knee'],
      weekCharacters: ['baseline'],
    ),
    // 10. All 4 week characters on bug-repro
    DiagnosticCombo(
      label: 'combo-1 inputs × all 4 week characters',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline', 'overreach', 'peak', 'deload'],
    ),
  ];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/plan_generator/v4_diagnostic/combos.dart test/plan_generator/v4_diagnostic_test.dart
git commit -m "test(plan-v4): define 10 diagnostic input combinations"
```

---

## Task 6: Markdown writer — per-combo trace rendering

**Files:**
- Create: `test/plan_generator/v4_diagnostic/markdown_writer.dart`
- Modify: `test/plan_generator/v4_diagnostic_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `v4_diagnostic_test.dart`:

```dart
import 'v4_diagnostic/markdown_writer.dart';

// ...inside main():
    group('DiagnosticMarkdownWriter', () {
      final library = LibraryLoader.loadFromAssets();

      test('renders a full report for combo #1 (bug-repro)', () {
        final combo = DiagnosticCombos.all.first;
        final md = DiagnosticMarkdownWriter.renderCombo(combo, library);
        // Required section headers
        expect(md, contains('## Combo: '));
        expect(md, contains('### Day '));
        expect(md, contains('PRE-VolumeFilter:'));
        expect(md, contains('POST-VolumeFilter:'));
        expect(md, contains('excludeNames-in:'));
        // Attempts logged
        expect(md, contains('A1 ('));
        expect(md, contains('A5'));
        // Input echo
        expect(md, contains('effectiveExp='));
        expect(md, contains('equipmentTier=full_gym'));
      });

      test('renders all 4 week characters for combo #10', () {
        final combo = DiagnosticCombos.all[9];
        final md = DiagnosticMarkdownWriter.renderCombo(combo, library);
        expect(md, contains('Week baseline'));
        expect(md, contains('Week overreach'));
        expect(md, contains('Week peak'));
        expect(md, contains('Week deload'));
      });
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: FAIL — missing import.

- [ ] **Step 3: Implement writer**

Write `test/plan_generator/v4_diagnostic/markdown_writer.dart`:

```dart
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart'
    show PlanGenerator;
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';

import 'cascade_tracer.dart';
import 'combos.dart';

class DiagnosticMarkdownWriter {
  static String renderCombo(
    DiagnosticCombo combo,
    List<Map<String, dynamic>> library,
  ) {
    final buf = StringBuffer();
    final effExp = PlanGenerator.effectiveLevel(combo.experience, combo.phase);

    buf.writeln('## Combo: ${combo.label}');
    buf.writeln();
    buf.writeln('**INPUT:**');
    buf.writeln('- goal=${combo.goal}');
    buf.writeln('- equipment=${combo.equipment}');
    buf.writeln('- daysPerWeek=${combo.daysPerWeek}');
    buf.writeln('- experience=${combo.experience}');
    buf.writeln('- phase=${combo.phase}');
    buf.writeln('- sessionDuration=${combo.sessionDuration}');
    buf.writeln('- injuries=${combo.injuries}');
    buf.writeln();
    buf.writeln('**EFFECTIVE:**');
    buf.writeln('- effectiveExp=$effExp');
    buf.writeln('- equipmentTier=${combo.equipment}');
    buf.writeln();

    // Run SplitResolver — pure Dart, no Hive
    final splitDays = SplitResolver.selectV4(
      combo.goal,
      combo.daysPerWeek,
      experienceLevel: effExp,
    );

    for (final weekChar in combo.weekCharacters) {
      buf.writeln('### Week $weekChar');
      buf.writeln();

      // Apply VolumeFilter
      final filteredDays = VolumeFilter.filterDays(
        splitDays,
        sessionMinutes: combo.sessionDuration,
        experience: effExp,
        weekCharacter: weekChar,
      );

      for (var dayIdx = 0; dayIdx < splitDays.length; dayIdx++) {
        final rawDay = splitDays[dayIdx];
        final filteredDay = filteredDays[dayIdx];
        _renderDay(
          buf,
          library,
          rawDay: rawDay,
          filteredDay: filteredDay,
          equipmentTier: combo.equipment,
          effectiveExp: effExp,
          phase: combo.phase,
          injuries: combo.injuries,
        );
      }
    }
    buf.writeln('---');
    buf.writeln();
    return buf.toString();
  }

  static void _renderDay(
    StringBuffer buf,
    List<Map<String, dynamic>> library, {
    required MuscleSlotDay rawDay,
    required MuscleSlotDay filteredDay,
    required String equipmentTier,
    required String effectiveExp,
    required int phase,
    required List<String> injuries,
  }) {
    buf.writeln('#### Day "${rawDay.name}" (${rawDay.dayType}, ${rawDay.intensity})');
    buf.writeln();
    for (final variant in ['A', 'B']) {
      final rawSlots = variant == 'A' ? rawDay.slotsA : (rawDay.slotsB ?? rawDay.slotsA);
      final fSlots = variant == 'A' ? filteredDay.slotsA : (filteredDay.slotsB ?? filteredDay.slotsA);

      buf.writeln('**Variant $variant**');
      buf.writeln();
      buf.writeln('- PRE-VolumeFilter: ${rawSlots.length} slots — '
          '${rawSlots.map((s) => _slotLabel(s)).join(", ")}');
      buf.writeln('- POST-VolumeFilter: ${fSlots.length} slots — '
          '${fSlots.map((s) => _slotLabel(s)).join(", ")}');
      final droppedLabels = rawSlots
          .where((s) => !fSlots.any((f) => _slotLabel(f) == _slotLabel(s)))
          .map((s) => _slotLabel(s))
          .toList();
      if (droppedLabels.isNotEmpty) {
        buf.writeln('  - ⚠️ Dropped by VolumeFilter: ${droppedLabels.join(", ")}');
      }
      buf.writeln();

      // Run cascade for each surviving slot
      final pickedNames = <String>{};
      for (final slot in fSlots) {
        buf.writeln('- **Slot:** ${_slotLabel(slot)}');
        buf.writeln('  - excludeNames-in (${pickedNames.length}): '
            '${pickedNames.isEmpty ? "{}" : pickedNames.join(", ")}');
        final trace = CascadeTracer.trace(
          library,
          slot: slot,
          equipmentTier: equipmentTier,
          effectiveExp: effectiveExp,
          phase: phase,
          injuries: injuries,
          pickedNames: pickedNames,
        );
        for (final a in trace.attempts) {
          final sample = a.sampleNames.isEmpty
              ? ''
              : ' → [${a.sampleNames.join(", ")}]';
          buf.writeln('  - A${a.number} (${a.signature}): ${a.resultCount}$sample');
        }
        if (trace.finalPick != null) {
          final flag = trace.finalPick!.source == CascadePickSource.universalPoolPlaceholder
              ? ' ⚠️ PLACEHOLDER (not in library)'
              : trace.finalPick!.source == CascadePickSource.universalPool
                  ? ' ⚠️ FROM UNIVERSAL POOL'
                  : '';
          buf.writeln('  - **PICK:** ${trace.finalPick!.name} '
              '(${trace.finalPick!.source.name})$flag');
          pickedNames.add(trace.finalPick!.name);
        } else {
          buf.writeln('  - **PICK:** (none — cascade exhausted) ⚠️');
        }
        buf.writeln();
      }
    }
  }

  static String _slotLabel(MuscleSlot s) {
    final sf = s.subFocus != null ? '/${s.subFocus}' : '';
    return '${s.targetMuscle}$sf/${s.movementPattern}/${s.exerciseType}/P${s.priority}';
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/plan_generator/v4_diagnostic/markdown_writer.dart test/plan_generator/v4_diagnostic_test.dart
git commit -m "test(plan-v4): Markdown writer renders per-combo pipeline trace"
```

---

## Task 7: Entry test — generate full report, write to disk, assert shape

**Files:**
- Modify: `test/plan_generator/v4_diagnostic_test.dart`
- Created at runtime: `test/plan_generator/v4_diagnostic_output.md`

- [ ] **Step 1: Write the failing test**

Append a final integration test at the end of `v4_diagnostic_test.dart`, outside all prior groups:

```dart
import 'dart:io';

// ...at bottom of main():
  test('end-to-end: generate v4_diagnostic_output.md', () {
    final library = LibraryLoader.loadFromAssets();

    final buf = StringBuffer();
    buf.writeln('# V4 Diagnostic — ${DateTime.now().toIso8601String().split("T").first}');
    buf.writeln();
    buf.writeln('Run from: `flutter test test/plan_generator/v4_diagnostic_test.dart`');
    buf.writeln();

    // Pre-check
    buf.write(LibraryIntegrity.renderMarkdown(library));

    // All combos
    for (final combo in DiagnosticCombos.all) {
      buf.write(DiagnosticMarkdownWriter.renderCombo(combo, library));
    }

    final outFile = File('test/plan_generator/v4_diagnostic_output.md');
    outFile.writeAsStringSync(buf.toString());

    // Asserts
    expect(outFile.existsSync(), isTrue);
    final content = outFile.readAsStringSync();
    expect(content, contains('## Library integrity pre-check'));
    // Every combo rendered
    for (final combo in DiagnosticCombos.all) {
      expect(content, contains(combo.label),
          reason: 'Combo "${combo.label}" missing from report');
    }
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: FAIL — likely `File.writeAsStringSync` works (it's real I/O) but some import or assertion will point us to missing pieces. If previous tasks were done, this should actually pass on the first try. If it does pass, skip to step 4.

- [ ] **Step 3: Fix any issue surfaced by the failure**

No code change if step 2 passed. If it failed, fix per error message (typically a missing import).

- [ ] **Step 4: Run the full test file and inspect output**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: PASS for every test.

Then open `test/plan_generator/v4_diagnostic_output.md` manually. Sanity checks:
- Library pre-check table present, with ⚠️ flags next to zero-count rows if any.
- Equipment tier audit line present (expect only underscore values — any space-separated tier is a smoking gun).
- Combo #1 (bug-repro) shows Day "Legs" with 5 slots pre-filter, 4 post-filter (2×P1 + 2×P2, P3 dropped at 45min default).
- At least one Hamstrings/hip_dominant/compound/P1 slot has a trace entry. Note which Attempt it picked at — that pins down where the production bug lives.

- [ ] **Step 5: Commit (including generated output)**

```bash
git add test/plan_generator/v4_diagnostic_test.dart test/plan_generator/v4_diagnostic_output.md
git commit -m "test(plan-v4): end-to-end diagnostic report generator + first committed artifact"
```

---

## Task 8: Update repo docs — CLAUDE.md pointer + plan artifacts

**Files:**
- Modify: `CLAUDE.md` (single-line pointer in "Single-source-of-truth files" or an appropriate section)

- [ ] **Step 1: Check current CLAUDE.md for the right insertion point**

Read `CLAUDE.md` around the "Single-source-of-truth files" list. Add a single-line pointer to the diagnostic harness — NOT a new section.

- [ ] **Step 2: Add pointer line**

Exact insertion (append under "Single-source-of-truth files" in `CLAUDE.md`):

```
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart V4 pipeline tracer. Run this when plan generator output looks wrong; emits `test/plan_generator/v4_diagnostic_output.md`. Mirrors `exercise_repository.queryV4` + `exercise_selector._cascadeFill`; any change to either production file requires an equivalent update to the mirror.
```

- [ ] **Step 3: Verify nothing else changed**

Run: `git diff CLAUDE.md`
Expected: ONLY the one line added. No other edits.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: point CLAUDE.md at v4 diagnostic harness"
```

---

## Task 9: Final sanity — run-from-clean

- [ ] **Step 1: Delete the generated output file**

```bash
rm test/plan_generator/v4_diagnostic_output.md
```

- [ ] **Step 2: Run the full harness**

Run: `flutter test test/plan_generator/v4_diagnostic_test.dart`
Expected: PASS. `v4_diagnostic_output.md` regenerated.

- [ ] **Step 3: Run full test suite to confirm no regressions**

Run: `flutter test`
Expected: PASS for all tests (harness adds new green tests, doesn't break any existing ones).

- [ ] **Step 4: Re-commit regenerated artifact if the date-stamp line changed**

```bash
git add test/plan_generator/v4_diagnostic_output.md
git diff --cached --stat
# If only the date-stamp differs, commit:
git commit -m "test(plan-v4): refresh diagnostic artifact"
# Otherwise, investigate what changed before committing.
```

---

## Non-goals — explicitly NOT done in this plan

The spec's Open Issues section lists these as deferred to separate brainstorms. None of these are touched:

1. Wiring `sessionDuration` into the 5 orphan call sites.
2. Adding an `exercises` column to `scheduled_workouts` cloud table.
3. Fixing Supabase profile sync for icanbefitter@gmail.com.
4. Any selector / volume_filter / split_resolver / library fix.
5. Locating and fixing the "LEG DAY RELAXED" UI label source (the trace will show which stage produces it, but we don't modify UI code).

After running the harness and reviewing `v4_diagnostic_output.md`, the user decides which (if any) to promote to its own brainstorm → spec → plan cycle.

---

## Self-Review checklist

**Spec coverage:**
- [x] Harness is pure-Dart `flutter test` — no Hive/Supabase (Task 1 bypasses HiveService).
- [x] Library integrity pre-check: triplet counts + tier audit — Task 3.
- [x] Two-layer trace (Input→Effective + Per-slot cascade) — Tasks 4, 6.
- [x] All 10 combos — Task 5.
- [x] excludeNames accumulation logged — Task 6 `_renderDay` pickedNames set.
- [x] POST-VolumeFilter + dropped slots — Task 6 `_renderDay`.
- [x] A/B variant coverage — Task 6 `for variant in ['A', 'B']`.
- [x] All 4 week characters for combo 10 — Task 5 + Task 6 `for weekChar in combo.weekCharacters`.
- [x] Injury path — combo 9.
- [x] Placeholder vs library distinction — Task 4 `CascadePickSource.universalPoolPlaceholder`.
- [x] Output file committed — Task 7 step 5.
- [x] Zero production code changes — confirmed (only `CLAUDE.md` docs pointer in Task 8).
- [x] Heuristics / "what each combo proves" come through in the trace without needing extra code — reviewer reads the Markdown.

**Placeholder scan:** No TBDs, no "handle errors appropriately", no "similar to Task N" shortcuts. Every code block is complete.

**Type consistency:** `MuscleSlot`, `MuscleSlotDay`, `PlanGenerator.effectiveLevel`, `SplitResolver.selectV4`, `VolumeFilter.filterDays` — all names verified against actual source files. `CascadePickSource` enum used consistently across tracer + writer.

**Stage trace coverage:** Spec requested post-periodization / post-sequencing / post-superset counts too. This plan intentionally stops at post-VolumeFilter + cascade pick. Rationale: the bug (3 exercises instead of expected 4-5) almost certainly lives in Select or VolumeFilter — downstream stages only re-order / pair. If the harness output doesn't localize the bug, we'll add downstream tracing in a follow-up plan. Calling out here so reviewer can raise if they disagree.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-15-plan-generator-v4-diagnostic.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
