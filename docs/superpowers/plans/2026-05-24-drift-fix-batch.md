# Drift-Fix Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all 9 writer/reader drift findings (1 P0 + 3 P1 + 5 P2) from the 2026-05-24 drift-detector first run on workout + nutrition domains, in a single mega-commit (Approach C, founder-locked).

**Architecture:** Each task stages files via `git add` but does NOT commit. The final task (T17) creates one mega-commit containing migration 068 + Gate 23 + 9 fix sites + 8 new contract tests + closure YAML + diagnose-doc. Pre-commit hook (~8 min) runs once at the end. Migration apply + Edge Function redeploy happen LIVE before the final commit so we can verify the system works.

**Tech Stack:** Flutter (Dart) + Hive + Riverpod (client); Supabase Postgres + Edge Functions (TS); MCP `apply_migration` for live schema changes; host-shell deploy (`.claude/deploy_via_api.js`) for Edge Function deploys.

**Branch:** `claude/frosty-bardeen-cce54b` (base `8f6a007` — spec commit). Single commit on top.

**Spec:** [docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md](docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md).

**Founder direction:** "everything including structural. brainstorm. make a plan" (locks scope to all 9 + 2 schema migrations).

---

## Pre-execution checklist

Implementer agent must confirm before starting Task 0:
- [ ] Branch is `claude/frosty-bardeen-cce54b` and HEAD is `8f6a007` (the spec commit).
- [ ] `flutter pub get` runs clean.
- [ ] `flutter analyze --no-fatal-infos` exits 0 (no pre-existing warnings to confuse later runs).
- [ ] No local uncommitted changes (`git status` is clean except `docs/superpowers/skills-log.md` which is untracked from the prior session — leave it alone for this batch).

---

## Task 0: Pre-flight verification

**Files:**
- Read-only: `supabase/functions/**/*.ts` (Edge Function readers of `workout_logs.exercise_name`)
- Read-only: `lib/features/train/repositories/workout_repository.dart` (verify F5 line range)
- Write: `docs/audit/2026-05-24-drift-fix-preflight.md` (capture findings for downstream tasks)

- [ ] **Step 1: Query live UNIQUE constraint name for workout_logs**

Run via MCP:
```
mcp__ba7b5e8e__execute_sql(
  project_id: "dedsavbjuwgarrhphgnl",
  query: "SELECT conname FROM pg_constraint WHERE conrelid = 'public.workout_logs'::regclass AND contype = 'u';"
)
```
Expected output: 1-2 rows with constraint name(s). Record the exact name containing `exercise_name` (likely `workout_logs_user_id_date_exercise_name_key` per Postgres convention, but may be `uniq_workout_logs_user_date_exercise` or similar). Write the exact name into `preflight.md`.

- [ ] **Step 2: Verify `workout_logs.exercise_name` is the correct column (not `workout_log_exercises.exercise_name`)**

Run via MCP:
```
mcp__ba7b5e8e__execute_sql(
  project_id: "dedsavbjuwgarrhphgnl",
  query: "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='workout_logs' ORDER BY ordinal_position;"
)
```
Expected: includes `exercise_name TEXT`. Confirm in preflight.md.

Also query:
```
mcp__ba7b5e8e__execute_sql(
  project_id: "dedsavbjuwgarrhphgnl",
  query: "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='workout_log_exercises' AND column_name='exercise_name';"
)
```
Confirm `workout_log_exercises.exercise_name` ALSO exists (and is intentionally NOT renamed — it's the per-exercise identity per CLAUDE.md §11).

- [ ] **Step 3: Grep all Edge Function readers of `workout_logs.exercise_name`**

Run via Grep tool:
```
pattern: "exercise_name"
path: "supabase/functions"
glob: "*.ts"
output_mode: "content"
-n: true
```

For each match, classify by reading 5 lines of context: does it read from `workout_logs` (affected — must update) or `workout_log_exercises`/other (not affected)? Write a list to `preflight.md` like:
```
AFFECTED (reads workout_logs.exercise_name):
- supabase/functions/weekly-report/index.ts:167 — .from("workout_logs").select("date, exercise_name, ...")
- supabase/functions/weekly-report/index.ts:182 — projection `exercise_name: e.exercise_name`
- (any others discovered)

NOT AFFECTED (reads workout_log_exercises or other source):
- supabase/functions/weekly-report/index.ts:153 — .from("workout_log_exercises").select("exercise_name, ...")
- supabase/functions/weekly-recalc/index.ts:* — reads workout_log_exercises
- supabase/functions/i-see-you-callout/index.ts:203 — reads from PR table (verify)
- (etc.)
```

- [ ] **Step 4: Verify F5 method line range**

Run Read tool on `lib/features/train/repositories/workout_repository.dart` starting at line 1110, limit 100. Confirm the `Future<String> logSetWithPrRescan({` declaration starts at the listed line; find the closing `}` of the method body. Record the exact start–end range in `preflight.md`.

- [ ] **Step 5: Grep for any active production callers of logSetWithPrRescan**

Run Grep tool:
```
pattern: "logSetWithPrRescan\("
path: "lib"
glob: "*.dart"
output_mode: "content"
-n: true
```

Confirm: only the declaration site at `workout_repository.dart` matches (zero active callers). If ANY other match exists, STOP and surface to founder — do not proceed with F5 deletion until callers are migrated.

- [ ] **Step 6: Write preflight.md summarizing findings**

```bash
# Write file (paste output of all 5 steps above into structured sections):
# docs/audit/2026-05-24-drift-fix-preflight.md
```

Sections:
1. **UNIQUE constraint name** (exact value, e.g. `workout_logs_user_id_date_exercise_name_key`)
2. **workout_logs schema confirmed** (exercise_name TEXT present)
3. **workout_log_exercises.exercise_name retained** (intentional — per-exercise identity)
4. **Edge Function callers to update** (numbered list with file:line + brief)
5. **F5 method line range** (e.g. lines 1114-1205)
6. **F5 caller count** (must be 0)

- [ ] **Step 7: Stage preflight.md**

```bash
git add docs/audit/2026-05-24-drift-fix-preflight.md
```

Do NOT commit yet.

---

## Task 1: Gate 23 — `nlog_*` canonical writer enforcement

**Files:**
- Create: `scripts/check_nlog_key_canonical.dart`
- Create: `test/contracts/nlog_key_canonical_test.dart`

- [ ] **Step 1: Write Gate 23 script (mirror of Gate 17)**

Create `scripts/check_nlog_key_canonical.dart`:

```dart
// scripts/check_nlog_key_canonical.dart
//
// Drift-fix batch 2026-05-24 / F2 nutrition — source-grep gate. Pins
// the rule that `nlog_*` Hive keys are constructed in exactly ONE
// place: `lib/core/services/nutrition_write_service.dart` via the
// static helper `NutritionWriteService.computeLogKey(...)`.
//
// Two documented mirrors exist (and are allowlisted):
//
//   - `lib/core/services/sync_service.dart` — `_nlogKeyForRestore`
//     reconstructs the canonical key from a raw cloud nutrition_logs
//     row during restore. Cloud doesn't carry the FoodItem[] list
//     directly; the mirror is documented and round-trip-tested.
//
//   - `lib/core/services/nlog_key_migrator.dart` — one-shot migrator
//     that legitimately walks legacy `nlog_*` key shapes and rewrites
//     them to canonical. Migration mirrors are necessary.
//
// Mirrors gate 17 (`check_exlog_key_canonical.dart`) shipped APK Test
// #16.1. Closes follow-up risk surface F2 from the 2026-05-24
// writer-reader-drift-detector first run.
//
// Usage: dart run scripts/check_nlog_key_canonical.dart

import 'dart:io';

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[nlog-key-canonical] FAIL: lib/ does not exist');
    exit(1);
  }

  // Only the canonical helper + the documented restore + migration
  // mirrors may emit `nlog_` literals.
  const allowlist = <String>{
    'lib/core/services/nutrition_write_service.dart',
    'lib/core/services/sync_service.dart',
    'lib/core/services/nlog_key_migrator.dart',
  };

  // Patterns that indicate an `nlog_*` Hive key is being CONSTRUCTED
  // by hand (string concat or interpolation), NOT just referenced as
  // a prefix.
  final patterns = <RegExp>[
    RegExp(r"""['"]nlog_\$"""),       // 'nlog_$var or "nlog_$var
    RegExp(r"""['"]nlog_\$\{"""),     // 'nlog_${expr or "nlog_${expr
    RegExp(r"""['"]nlog_['"]\s*\+"""),// 'nlog_' + … or "nlog_" + …
  ];

  final offenders = <String>[];

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;

    final relPath = entity.path.replaceAll('\\', '/');
    if (allowlist.contains(relPath)) continue;

    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      // Strip line comments so commentary about the old shape doesn't
      // trigger the gate.
      final idx = raw.indexOf('//');
      final line = idx >= 0 ? raw.substring(0, idx) : raw;
      for (final p in patterns) {
        if (p.hasMatch(line)) {
          offenders.add('$relPath:${i + 1}: ${raw.trimRight()}');
          break;
        }
      }
    }
  }

  if (offenders.isEmpty) {
    stdout.writeln('[nlog-key-canonical] PASS — every `nlog_*` Hive '
        'key in lib/ is constructed via '
        'NutritionWriteService.computeLogKey or the documented '
        'restore/migration mirrors.');
    exit(0);
  }

  stderr.writeln(
      '[nlog-key-canonical] FAIL — ${offenders.length} site(s) '
      'construct an `nlog_*` Hive key outside the canonical helper:');
  for (final v in offenders) {
    stderr.writeln('  $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: delegate to '
      'NutritionWriteService.computeLogKey(istDate, mealType, items). '
      'The helper lives at lib/core/services/nutrition_write_service.dart '
      'and produces `nlog_<istDateStr>_<mealType>_<v5hash8>`. See '
      'docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md.');
  exit(1);
}
```

- [ ] **Step 2: Run script against current lib/ — must PASS**

Run:
```bash
dart run scripts/check_nlog_key_canonical.dart
```
Expected output: `[nlog-key-canonical] PASS — every `nlog_*` Hive key in lib/ is constructed via NutritionWriteService.computeLogKey or the documented restore/migration mirrors.`
Exit code: 0.

If FAIL: an unexpected writer site exists (good catch — surface to founder; fix it OR add to allowlist if documented mirror).

- [ ] **Step 3: Write contract test for Gate 23**

Create `test/contracts/nlog_key_canonical_test.dart`:

```dart
// test/contracts/nlog_key_canonical_test.dart
//
// Drift-fix batch 2026-05-24 / F2 nutrition — contract test pinning
// the Gate 23 allowlist. If a future commit introduces a rogue
// `nlog_*` writer outside the 3 allowlisted files, this test fails.
//
// Mirrors `exlog_key_canonical_test.dart` shipped APK Test #16.1.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('nlog_* canonical writer allowlist', () {
    test('only 3 files emit `nlog_*` Hive key construction', () {
      const allowlist = <String>{
        'lib/core/services/nutrition_write_service.dart',
        'lib/core/services/sync_service.dart',
        'lib/core/services/nlog_key_migrator.dart',
      };

      final patterns = <RegExp>[
        RegExp(r"""['"]nlog_\$"""),
        RegExp(r"""['"]nlog_\$\{"""),
        RegExp(r"""['"]nlog_['"]\s*\+"""),
      ];

      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

      final offenders = <String>[];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final relPath = entity.path.replaceAll('\\', '/');
        if (allowlist.contains(relPath)) continue;

        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final raw = lines[i];
          // Strip line + block comments (per
          // feedback_source_grep_strip_comments_first.md)
          final idx = raw.indexOf('//');
          final line = idx >= 0 ? raw.substring(0, idx) : raw;
          for (final p in patterns) {
            if (p.hasMatch(line)) {
              offenders.add('$relPath:${i + 1}: ${raw.trimRight()}');
              break;
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Found ${offenders.length} site(s) constructing '
            '`nlog_*` outside the allowlist. Route through '
            'NutritionWriteService.computeLogKey. Offenders:\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
```

- [ ] **Step 4: Run the contract test — must PASS**

Run:
```bash
flutter test test/contracts/nlog_key_canonical_test.dart
```
Expected: `+1: All tests passed!`

- [ ] **Step 5: Stage Gate 23 files**

```bash
git add scripts/check_nlog_key_canonical.dart test/contracts/nlog_key_canonical_test.dart
```

Do NOT commit yet.

---

## Task 2: Nutrition F1 P0 — IST fix in `computeLogKey`

**Files:**
- Modify: `lib/core/services/nutrition_write_service.dart` lines 87-88 (inline build in `logMeal`) AND lines 739-740 (canonical `computeLogKey`)
- Create: `test/contracts/nutrition_write_service_ist_anchored_test.dart`

- [ ] **Step 1: Write the failing behavioral test (TDD — test first)**

Create `test/contracts/nutrition_write_service_ist_anchored_test.dart`:

```dart
// test/contracts/nutrition_write_service_ist_anchored_test.dart
//
// Drift-fix batch 2026-05-24 / F1 nutrition (P0).
//
// `NutritionWriteService.computeLogKey` parameter `istDate` asserts
// the caller pre-shifts to IST, but 7 production callers pass raw
// `DateTime.now()` (device-local). On any device in a timezone west
// of IST, a meal logged just past local midnight would produce a
// Hive key with yesterday's IST date — but readers (TodaysMealsCard,
// _getMealsToday) use `istDateStr(DateTime.now())` so the meal would
// vanish from "Today's Meals."
//
// This test pins the fix: `computeLogKey` MUST internally route
// through `istDateStr(date)` from lib/core/utils/ist_date.dart so
// the parameter-name assertion is no longer a load-bearing caller
// contract.
//
// Test design: pass a UTC instant that crosses the IST date boundary
// (UTC May 24 22:00 = IST May 25 03:30). The Hive key must reflect
// IST's date, not UTC's.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

void main() {
  group('NutritionWriteService IST anchoring', () {
    test('computeLogKey resolves IST date from UTC input crossing midnight', () {
      // UTC 2026-05-24 22:00 == IST 2026-05-25 03:30.
      final utcLate = DateTime.utc(2026, 5, 24, 22, 0);

      final key = NutritionWriteService.computeLogKey(
        istDate: utcLate,
        mealType: 'breakfast',
        items: [
          FoodItem(
            name: 'Test',
            quantityG: 100,
            calories: 100,
            protein: 10,
            carbs: 10,
            fat: 5,
            fiber: 2,
          ),
        ],
      );

      // Must use IST's date (2026-05-25), not UTC's (2026-05-24).
      expect(
        key.startsWith('nlog_2026-05-25_'),
        isTrue,
        reason:
            'computeLogKey must IST-anchor the date. Got key="$key" — '
            'expected prefix "nlog_2026-05-25_". If this assertion '
            'fails with "nlog_2026-05-24_" the fix has not been '
            'applied: replace hand-built `\${date.year}-...` with '
            '`istDateStr(date)` from lib/core/utils/ist_date.dart.',
      );
    });

    test('computeLogKey resolves IST date from local DateTime far from midnight', () {
      // Mid-afternoon local — should never produce date confusion.
      final localAfternoon = DateTime(2026, 5, 24, 14, 0);
      final key = NutritionWriteService.computeLogKey(
        istDate: localAfternoon,
        mealType: 'lunch',
        items: [
          FoodItem(
            name: 'X',
            quantityG: 50,
            calories: 50,
            protein: 5,
            carbs: 5,
            fat: 2,
            fiber: 1,
          ),
        ],
      );

      // For a device-local DateTime in IST, the date should be 2026-05-24.
      // For a device-local DateTime in UTC (when tests run on CI), the
      // shift may bump to 2026-05-24 19:30 IST → still 2026-05-24.
      expect(key.startsWith('nlog_2026-05-24_'), isTrue,
        reason: 'mid-afternoon log should always reflect the same '
            'IST date as the input. Got key="$key"');
    });
  });
}
```

- [ ] **Step 2: Run the test — must FAIL (no fix yet)**

Run:
```bash
flutter test test/contracts/nutrition_write_service_ist_anchored_test.dart
```
Expected: First test fails with message about `nlog_2026-05-24_` prefix when expected `nlog_2026-05-25_`.

If it unexpectedly passes, STOP — the writer may already have been fixed, or the test setup is wrong.

- [ ] **Step 3: Apply the fix to `computeLogKey` (canonical helper)**

Edit `lib/core/services/nutrition_write_service.dart` lines 739-740. Current:
```dart
    final dateStr =
        '${istDate.year.toString().padLeft(4, '0')}-${istDate.month.toString().padLeft(2, '0')}-${istDate.day.toString().padLeft(2, '0')}';
```

Replace with:
```dart
    final dateStr = istDateStr(istDate);
```

Add import at top of file if not present:
```dart
import 'package:icanbefitter/core/utils/ist_date.dart';
```
(Check the file's import block first; the helper may already be imported. Run a grep for `ist_date.dart` before adding.)

- [ ] **Step 4: Apply the fix to the inline build in `logMeal` (lines 87-88)**

Edit `lib/core/services/nutrition_write_service.dart` lines 87-88. Current:
```dart
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
```

Replace with:
```dart
    final dateStr = istDateStr(date);
```

- [ ] **Step 5: Run the test — must PASS**

Run:
```bash
flutter test test/contracts/nutrition_write_service_ist_anchored_test.dart
```
Expected: `+2: All tests passed!`

- [ ] **Step 6: Run the full nutrition write-to-read contract test suite to confirm no regression**

Run:
```bash
flutter test test/contracts/nutrition_write_to_read_contract_test.dart
```
Expected: All existing tests still pass.

- [ ] **Step 7: Stage the changes**

```bash
git add lib/core/services/nutrition_write_service.dart test/contracts/nutrition_write_service_ist_anchored_test.dart
```

Do NOT commit yet.

---

## Task 3: Nutrition F3 P2 — Drop dead fallback reads in `sync_nutrition.dart`

**Files:**
- Modify: `lib/core/services/sync/sync_nutrition.dart` lines 172-174

- [ ] **Step 1: Read the current per-item projection block**

Run Read tool on `lib/core/services/sync/sync_nutrition.dart` lines 165-185 to confirm exact current shape before editing.

Expected current shape (around lines 172-174):
```dart
'food_name': item['name'] ?? item['food_name'] ?? '',
'quantity_g': item['serving_g'] ?? item['quantity_g'],
```

- [ ] **Step 2: Apply the dead-fallback removal**

Edit those lines. New shape:
```dart
'food_name': item['name'] ?? '',
'quantity_g': item['quantity_g'],
```

- [ ] **Step 3: Verify with the existing contract test (no new test needed)**

Run:
```bash
flutter test test/contracts/nutrition_write_to_read_contract_test.dart
```
Expected: still passes — the existing contract test asserts the canonical shape, and we just removed dead-code fallbacks.

- [ ] **Step 4: Stage the change**

```bash
git add lib/core/services/sync/sync_nutrition.dart
```

Do NOT commit yet.

---

## Task 4: Nutrition F4 P2 — Add per-item `fiber` to cloud projection

**Files:**
- Modify: `lib/core/services/sync/sync_nutrition.dart` (per-item projection)
- Create: `test/contracts/nutrition_log_items_fiber_projection_test.dart`

Note: the schema column add happens in Task 9 (migration 068) — that task applies the column live. Client changes here are gated by Task 9's migration being applied first. Coordinate ordering.

- [ ] **Step 1: Read the current per-item projection block (post-Task 3)**

Run Read tool on `lib/core/services/sync/sync_nutrition.dart` lines 165-185.

After Task 3 it should look approximately like:
```dart
return {
  'id': itemId,
  'nutrition_log_id': parentId,
  'food_name': item['name'] ?? '',
  'quantity_g': item['quantity_g'],
  'calories': item['calories'],
  'protein': item['protein'],
  'carbs': item['carbs'],
  'fat': item['fat'],
};
```

- [ ] **Step 2: Add `fiber` to the projection**

Insert after `'fat'`:
```dart
  'fat': item['fat'],
  'fiber': item['fiber'] ?? 0,
};
```

- [ ] **Step 3: Write the contract test (source-grep)**

Create `test/contracts/nutrition_log_items_fiber_projection_test.dart`:

```dart
// test/contracts/nutrition_log_items_fiber_projection_test.dart
//
// Drift-fix batch 2026-05-24 / F4 nutrition (P2).
//
// Pins that the cloud `nutrition_log_items` projection in
// `sync_nutrition.dart` includes the `fiber` key — added 2026-05-24
// alongside migration 068 which ships the column. Without this key
// in the projection, the cloud column would stay 0 forever for new
// logs, defeating the purpose of the additive schema change.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('sync_nutrition.dart projects fiber to nutrition_log_items', () {
    final file = File('lib/core/services/sync/sync_nutrition.dart');
    expect(file.existsSync(), isTrue,
        reason: 'sync_nutrition.dart must exist at the expected path');

    final source = file.readAsStringSync();

    // Strip block + line comments so explanatory comments don't
    // trigger a false positive when the projection is removed.
    final stripped = _stripComments(source);

    // The fiber key must appear in the per-item projection. We don't
    // pin exact line content — just that the string `'fiber':` (or
    // `"fiber":`) appears in the file's executable code.
    final hasFiber = stripped.contains("'fiber':") ||
        stripped.contains('"fiber":');

    expect(
      hasFiber,
      isTrue,
      reason: 'sync_nutrition.dart must project `fiber` to '
          '`nutrition_log_items`. Add `\'fiber\': item[\'fiber\'] ?? 0,` '
          'to the per-item projection block. See migration 068.',
    );
  });
}

String _stripComments(String src) {
  // Remove /* ... */ blocks first.
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  // Then remove // line comments (preserve string-literal // — best
  // effort; for this test the file has no `//` inside string literals
  // in the projection block).
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
```

- [ ] **Step 4: Run the test — must PASS (we already added the key in Step 2)**

Run:
```bash
flutter test test/contracts/nutrition_log_items_fiber_projection_test.dart
```
Expected: `+1: All tests passed!`

- [ ] **Step 5: Stage the changes**

```bash
git add lib/core/services/sync/sync_nutrition.dart test/contracts/nutrition_log_items_fiber_projection_test.dart
```

Do NOT commit yet.

---

## Task 5: Workout F1 P1 — PR snapshot uses PR-set reps

**Files:**
- Modify: `lib/features/ai_coach/repositories/ai_coach_repository.dart` around line 1939 (PR snapshot projection)
- Create: `test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart`

- [ ] **Step 1: Read the current PR snapshot projection**

Run Read tool on `lib/features/ai_coach/repositories/ai_coach_repository.dart` lines 1920-1960 to confirm exact current shape.

Expected: the block iterates `is_pr == true` logs and projects something like:
```dart
{
  'exercise': log['exercise_name'],
  'weight_kg': log['weight_kg'],
  'reps': log['reps_completed'],
  'date': log['date'],
}
```

The `reps` field reads `log['reps_completed']` which (post-Test-#6 WriteService contract) is the SUM across sets.

- [ ] **Step 2: Write the failing behavioral test (TDD — test first)**

Create `test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart`:

```dart
// test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart
//
// Drift-fix batch 2026-05-24 / F1 workout (P1).
//
// Per CLAUDE.md §15 Hive field-name contract: `reps_completed` on
// `exlog_*` is SUM across sets (writer contract). The AI coach PR
// snapshot was reading it as if it were per-set reps, producing
// nonsense like "PR: 100kg × 28 reps" for a 5-set workout.
//
// Fix (founder-locked decision): find the set within `sets[]` whose
// `weight_kg` matches the PR weight (max across sets), report THAT
// set's reps. Legacy rows lacking `sets[]` fall through to
// `reps_completed` (best effort).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  group('PR snapshot uses PR-set reps (not SUM)', () {
    test('finds the set matching PR weight and reports its reps', () {
      // Exlog shape from WorkoutWriteService — pyramid pattern.
      // PR weight = 100 (max). Set #3 hit 100 × 5 → THAT is the PR set.
      final exlog = <String, dynamic>{
        'exercise_name': 'Bench Press',
        'date': '2026-05-24',
        'is_pr': true,
        'weight_kg': 100, // PR weight (max across sets)
        'reps_completed': 28, // SUM: 10+8+5+5 = 28
        'sets': [
          {'weight_kg': 60, 'reps': 10},
          {'weight_kg': 80, 'reps': 8},
          {'weight_kg': 100, 'reps': 5}, // PR set
          {'weight_kg': 100, 'reps': 5},
        ],
      };

      final reps = AiCoachRepository.prSetRepsForExlog(exlog);
      expect(reps, 5,
          reason: 'PR set reps should be 5 (the reps at PR weight 100), '
              'not 28 (SUM across sets) nor 10 (first set). '
              'Got $reps.');
    });

    test('falls through to reps_completed for legacy rows without sets[]', () {
      final legacyExlog = <String, dynamic>{
        'exercise_name': 'Bench Press',
        'date': '2024-01-01',
        'is_pr': true,
        'weight_kg': 100,
        'reps_completed': 5,
        // No `sets[]` field — pre-Test-#6 row.
      };

      final reps = AiCoachRepository.prSetRepsForExlog(legacyExlog);
      expect(reps, 5,
          reason: 'Legacy rows without sets[] should fall through to '
              'reps_completed. Got $reps.');
    });

    test('handles empty sets[] gracefully', () {
      final degenerate = <String, dynamic>{
        'exercise_name': 'Bench Press',
        'is_pr': true,
        'weight_kg': 100,
        'reps_completed': 5,
        'sets': [],
      };

      final reps = AiCoachRepository.prSetRepsForExlog(degenerate);
      expect(reps, 5,
          reason: 'Empty sets[] should fall through to reps_completed.');
    });

    test('returns null when neither sets[] nor reps_completed has data', () {
      final empty = <String, dynamic>{
        'exercise_name': 'Bench Press',
        'is_pr': true,
        'weight_kg': 100,
      };

      final reps = AiCoachRepository.prSetRepsForExlog(empty);
      expect(reps, isNull,
          reason: 'No data sources → null, not 0 (so downstream can '
              'differentiate "missing" from "zero reps").');
    });
  });
}
```

- [ ] **Step 3: Run the test — must FAIL (helper doesn't exist yet)**

Run:
```bash
flutter test test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart
```
Expected: compilation error — `AiCoachRepository.prSetRepsForExlog` is undefined.

- [ ] **Step 4: Add the helper to `AiCoachRepository`**

Open `lib/features/ai_coach/repositories/ai_coach_repository.dart`. Find a good location for a static helper (top of class body, or right above the existing PR projection block — usually around line 1920). Add:

```dart
  /// Drift-fix batch 2026-05-24 / F1 workout (P1).
  ///
  /// Returns the reps achieved at the PR weight (the heaviest set in
  /// the log), NOT the SUM across sets. Falls through to
  /// `reps_completed` for legacy rows without a `sets[]` array.
  ///
  /// Why: per CLAUDE.md §15 Hive field-name contract, `reps_completed`
  /// is SUM across sets (writer-side semantic). The AI coach PR
  /// snapshot used to surface this as "PR: 100kg × 28 reps" for a
  /// 4-set pyramid — nonsense lifting semantics.
  @visibleForTesting
  static int? prSetRepsForExlog(Map<String, dynamic> log) {
    final sets = (log['sets'] as List?) ?? const [];
    if (sets.isNotEmpty) {
      final prWeight = (log['weight_kg'] as num?)?.toDouble();
      if (prWeight != null) {
        for (final s in sets) {
          if (s is! Map) continue;
          final w = (s['weight_kg'] as num?)?.toDouble();
          if (w == prWeight) {
            final r = (s['reps'] as num?)?.toInt();
            if (r != null) return r;
          }
        }
      }
    }
    // Fall through: legacy rows without sets[] OR no set matched PR
    // weight (degenerate data) OR empty sets[] array.
    return (log['reps_completed'] as num?)?.toInt();
  }
```

Make sure the file imports `package:meta/meta.dart` for `@visibleForTesting` (likely already imported).

- [ ] **Step 5: Update the PR snapshot projection to use the helper**

Find the existing PR projection block (around line 1939 — verify exact line via Read tool). The block looks approximately like:

```dart
{
  'exercise': log['exercise_name'],
  'weight_kg': log['weight_kg'],
  'reps': log['reps_completed'],
  'date': log['date'],
}
```

Replace `'reps': log['reps_completed']` with `'reps': prSetRepsForExlog(Map<String, dynamic>.from(log))`.

If `log` is already a `Map<String, dynamic>` at that callsite, drop the `.from(log)` cast.

- [ ] **Step 6: Run the test — must PASS**

Run:
```bash
flutter test test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart
```
Expected: `+4: All tests passed!`

- [ ] **Step 7: Run the full ai_coach test directory to confirm no regression**

Run:
```bash
flutter test test/ai_coach/
```
Expected: all existing tests still pass.

- [ ] **Step 8: Stage the changes**

```bash
git add lib/features/ai_coach/repositories/ai_coach_repository.dart test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart
```

Do NOT commit yet.

---

## Task 6: Workout F2 P1 — Drop top-level `duration_seconds` reads

**Files:**
- Modify: `lib/features/train/widgets/workout_receipt_card.dart` (line ~368)
- Modify: `lib/features/train/screens/train_screen.dart` (multiple sites)
- Create: `test/contracts/no_top_level_duration_seconds_reads_test.dart`

- [ ] **Step 1: Identify all sites reading `log['duration_seconds']` at top level**

Run Grep tool:
```
pattern: "log\\['duration_seconds'\\]|log\\[\"duration_seconds\"\\]"
path: "lib/features/train"
glob: "*.dart"
output_mode: "content"
-n: true
```

Record file:line for every match. Each one needs to be replaced.

- [ ] **Step 2: Read `WorkoutReadService.bestPerSetDuration` to confirm signature**

Run Grep tool:
```
pattern: "bestPerSetDuration"
path: "lib"
glob: "*.dart"
output_mode: "content"
-n: true
```

Confirm: it's a static method on `WorkoutReadService` at `lib/core/services/workout_read_service.dart` (or similar) and returns `int?` (nullable, sums per-set durations from `sets[].duration_sec`).

If the helper doesn't exist with that exact name, find the canonical per-set-duration reader (likely in `workout_read_service.dart` or `workout_repository.dart`). Use whatever the codebase's canonical helper is.

- [ ] **Step 3: Replace each `log['duration_seconds'] ?? 0` site**

For each site identified in Step 1, replace:
```dart
log['duration_seconds'] ?? 0
```
with:
```dart
WorkoutReadService.bestPerSetDuration(log) ?? 0
```

Add the import to each affected file if not already present:
```dart
import 'package:icanbefitter/core/services/workout_read_service.dart';
```

- [ ] **Step 4: Write the contract test**

Create `test/contracts/no_top_level_duration_seconds_reads_test.dart`:

```dart
// test/contracts/no_top_level_duration_seconds_reads_test.dart
//
// Drift-fix batch 2026-05-24 / F2 workout (P1).
//
// `WorkoutWriteService` does NOT emit a top-level `duration_seconds`
// field on `exlog_*` rows — per-set duration lives at
// `sets[].duration_sec` only. Reading `log['duration_seconds']` at
// top level silently returns 0 for every modern row.
//
// This test pins that the receipt + train_screen do NOT read
// `log['duration_seconds']` at top level. The canonical client-side
// derivation is `WorkoutReadService.bestPerSetDuration(log)`.
// (The cloud projection at sync_workout.dart:250 DOES write the
// aggregate to `workout_log_exercises.duration_seconds` — that's
// for downstream analytics and is unrelated to client reads.)
//
// Strips block + line comments per
// feedback_source_grep_strip_comments_first.md so explanatory
// comments about the old pattern don't false-positive.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('No top-level duration_seconds reads in client', () {
    test('workout_receipt_card.dart does not read log[duration_seconds]', () {
      _assertNoTopLevelDurationRead(
        'lib/features/train/widgets/workout_receipt_card.dart',
      );
    });

    test('train_screen.dart does not read log[duration_seconds]', () {
      _assertNoTopLevelDurationRead(
        'lib/features/train/screens/train_screen.dart',
      );
    });
  });
}

void _assertNoTopLevelDurationRead(String relPath) {
  final file = File(relPath);
  expect(file.existsSync(), isTrue,
      reason: 'Expected file to exist: $relPath');

  final source = file.readAsStringSync();
  final stripped = _stripComments(source);

  // Patterns that read `log['duration_seconds']` or
  // `log["duration_seconds"]` at top level.
  final patterns = <RegExp>[
    RegExp(r"""log\s*\[\s*['"]duration_seconds['"]\s*\]"""),
  ];

  final hits = <String>[];
  final lines = stripped.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final p in patterns) {
      if (p.hasMatch(lines[i])) {
        hits.add('$relPath:${i + 1}: ${lines[i].trim()}');
      }
    }
  }

  expect(
    hits,
    isEmpty,
    reason: 'Found ${hits.length} top-level duration_seconds read(s) '
        'in $relPath. WriteService never emits this field at top '
        'level. Use `WorkoutReadService.bestPerSetDuration(log) ?? 0` '
        'instead. Hits:\n${hits.join('\n')}',
  );
}

String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
```

- [ ] **Step 5: Run the test — must PASS (we already removed the reads in Step 3)**

Run:
```bash
flutter test test/contracts/no_top_level_duration_seconds_reads_test.dart
```
Expected: `+2: All tests passed!`

If FAIL, an unintended read remains — re-run Grep + replace.

- [ ] **Step 6: Run any existing receipt + train_screen tests to check for regressions**

Run:
```bash
flutter test test/widgets/ test/train/
```
Expected: all existing tests pass. If something fails (e.g., expects the old `?? 0` path), the test was implicitly tied to the broken contract — fix the test to assert the new path.

- [ ] **Step 7: Stage the changes**

```bash
git add lib/features/train/widgets/workout_receipt_card.dart lib/features/train/screens/train_screen.dart test/contracts/no_top_level_duration_seconds_reads_test.dart
```

If additional files were modified (e.g., other train/ widgets discovered in Step 1), `git add` those too.

Do NOT commit yet.

---

## Task 7: Workout F3 P2 — Drop dead `notes: log['id']` stuffing

**Files:**
- Modify: `lib/core/services/sync/sync_workout.dart` (line ~133)
- Create: `test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart`

- [ ] **Step 1: Read the current `workout_logs` upsert projection**

Run Read tool on `lib/core/services/sync/sync_workout.dart` lines 125-145.

Expected current shape (around line 133):
```dart
return {
  'user_id': userId,
  'date': log['date'],
  'exercise_name': wlogName,  // (will rename to workout_name in Task 8)
  // ... other fields ...
  'notes': log['id'],  // store local ID for reference
  // ... possibly more fields ...
};
```

- [ ] **Step 2: Remove the `notes: log['id']` line**

Delete the line entirely (don't replace with `'notes': null` — the column defaults to NULL).

If the trailing comma needs adjustment to keep the map literal valid, fix it.

- [ ] **Step 3: Write the contract test**

Create `test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart`:

```dart
// test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart
//
// Drift-fix batch 2026-05-24 / F3 workout (P2).
//
// Pre-fix sync_workout.dart stuffed `log['id']` into the cloud
// `workout_logs.notes` column. `log['id']` is never set by
// `WorkoutWriteService` — the projection wrote NULL for every
// modern row, and the comment "store local ID for reference"
// described dead intent.
//
// This test pins that the `workout_logs` upsert projection block
// in sync_workout.dart does NOT contain `'notes': log[`.
//
// Strips block + line comments per
// feedback_source_grep_strip_comments_first.md.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('sync_workout.dart does not stuff log[id] into notes', () {
    final file = File('lib/core/services/sync/sync_workout.dart');
    expect(file.existsSync(), isTrue);

    final source = file.readAsStringSync();
    final stripped = _stripComments(source);

    // Disallow any of these patterns inside the workout_logs upsert:
    //   'notes': log['id']
    //   'notes': log["id"]
    //   "notes": log['id']
    final patterns = <RegExp>[
      RegExp(r"""['"]notes['"]\s*:\s*log\s*\[\s*['"]id['"]\s*\]"""),
    ];

    final hits = <String>[];
    final lines = stripped.split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final p in patterns) {
        if (p.hasMatch(lines[i])) {
          hits.add('sync_workout.dart:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason: 'Found ${hits.length} site(s) stuffing log[id] into '
          'workout_logs.notes. Remove the projection — the field is '
          'dead. Hits:\n${hits.join('\n')}',
    );
  });
}

String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
```

- [ ] **Step 4: Run the test — must PASS**

Run:
```bash
flutter test test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart
```
Expected: `+1: All tests passed!`

- [ ] **Step 5: Stage the changes**

```bash
git add lib/core/services/sync/sync_workout.dart test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart
```

Do NOT commit yet.

---

## Task 8: Workout F4 P2 — Client write switch to `workout_name`

**Files:**
- Modify: `lib/core/services/sync/sync_workout.dart` (lines 125-145 — the `workout_logs` projection + `onConflict` clause)
- Create: `test/contracts/cloud_workout_logs_uses_workout_name_test.dart`

Note: the migration that renames the column lives in Task 9. The client write switch MUST be staged before migration apply so the new APK won't write to a dropped column. Order: stage client (T8) → apply migration live (T9) → deploy Edge Functions (T10) → final commit (T17).

- [ ] **Step 1: Read the current `workout_logs` upsert projection (post-Task 7)**

Run Read tool on `lib/core/services/sync/sync_workout.dart` lines 125-150.

Expected current shape (post-Task 7 — notes line removed):
```dart
final payload = {
  'user_id': userId,
  'date': log['date'],
  'exercise_name': wlogName,
  // ... other fields ...
};

await supa.from('workout_logs').upsert(
  payload,
  onConflict: 'user_id,date,exercise_name',
);
```

- [ ] **Step 2: Rename `exercise_name` → `workout_name` in projection**

Replace `'exercise_name': wlogName,` with `'workout_name': wlogName,`.

- [ ] **Step 3: Update `onConflict` clause**

Replace `onConflict: 'user_id,date,exercise_name'` with `onConflict: 'user_id,date,workout_name'`.

Note: this MUST match the new UNIQUE constraint name created in migration 068 (Task 9). The constraint targets the same 3 columns in the same order.

- [ ] **Step 4: Write the contract test**

Create `test/contracts/cloud_workout_logs_uses_workout_name_test.dart`:

```dart
// test/contracts/cloud_workout_logs_uses_workout_name_test.dart
//
// Drift-fix batch 2026-05-24 / F4 workout (P2).
//
// Pins that the cloud `workout_logs` upsert projection uses
// `workout_name` (renamed from `exercise_name` in migration 068).
// The value coming from Hive is the session label (e.g. "Push A"),
// never a per-exercise identifier — the column name now matches the
// semantic.
//
// Strips block + line comments per
// feedback_source_grep_strip_comments_first.md.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Cloud workout_logs uses workout_name (not exercise_name)', () {
    final file = File('lib/core/services/sync/sync_workout.dart');

    test('source file exists', () {
      expect(file.existsSync(), isTrue);
    });

    test('workout_logs projection emits workout_name', () {
      final source = file.readAsStringSync();
      final stripped = _stripComments(source);

      final hasWorkoutName = stripped.contains("'workout_name':") ||
          stripped.contains('"workout_name":');

      expect(
        hasWorkoutName,
        isTrue,
        reason: 'sync_workout.dart must project `workout_name` to '
            '`workout_logs`. See migration 068.',
      );
    });

    test('workout_logs upsert does NOT project exercise_name to workout_logs', () {
      final source = file.readAsStringSync();
      final stripped = _stripComments(source);

      // Find the workout_logs upsert block (not workout_log_exercises).
      // Heuristic: look for `'workout_logs'` followed within ~60 lines
      // by `.upsert(`. Within that block, no `'exercise_name':` key.
      //
      // For test simplicity we just check that anywhere a line
      // contains `from('workout_logs')` or `.from("workout_logs")`,
      // the next ~80 lines contain `'workout_name':` and do NOT
      // contain `'exercise_name': wlogName` style.
      final tablePattern = RegExp(
        r"""\.from\(\s*['"]workout_logs['"]\s*\)""",
      );
      final lines = stripped.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (tablePattern.hasMatch(lines[i])) {
          // Scan back ~30 lines to find the payload literal (Dart
          // commonly defines the map BEFORE calling .upsert).
          final start = (i - 50).clamp(0, lines.length);
          final end = (i + 5).clamp(0, lines.length);
          final block = lines.sublist(start, end).join('\n');

          // The block is the workout_logs upsert region. Within it,
          // the wlogName/session-label projection key must be
          // `workout_name`, NOT `exercise_name`. (Note: the same
          // block may legitimately reference exercise_name elsewhere
          // in a comment — we strip those.)
          expect(
            block.contains("'workout_name':") ||
                block.contains('"workout_name":'),
            isTrue,
            reason: 'workout_logs upsert near line ${i + 1} must '
                'project `workout_name`. Block was:\n$block',
          );
        }
      }
    });

    test('workout_logs upsert onConflict targets workout_name', () {
      final source = file.readAsStringSync();
      final stripped = _stripComments(source);

      // The new onConflict clause must reference workout_name.
      final hasNewConflict = stripped.contains("user_id,date,workout_name");

      expect(
        hasNewConflict,
        isTrue,
        reason: 'workout_logs upsert must use '
            'onConflict: "user_id,date,workout_name" matching the '
            'new UNIQUE constraint in migration 068.',
      );
    });
  });
}

String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
```

- [ ] **Step 5: Run the test — should PASS (the change in Steps 2-3 wrote the new shape)**

Run:
```bash
flutter test test/contracts/cloud_workout_logs_uses_workout_name_test.dart
```
Expected: `+4: All tests passed!`

- [ ] **Step 6: Stage the changes**

```bash
git add lib/core/services/sync/sync_workout.dart test/contracts/cloud_workout_logs_uses_workout_name_test.dart
```

Do NOT commit yet. Continue to Task 9 (live migration apply).

---

## Task 9: Apply migration 068 to prod + record in backups/

**Files:**
- Create: `supabase/migrations/068b_drift_fix_batch.sql`
- Modify: `backups/applied_migrations.json`

**This task touches prod. Read carefully before executing.**

- [ ] **Step 1: Write the migration SQL file**

Create `supabase/migrations/068b_drift_fix_batch.sql`. Use the EXACT constraint name from Task 0 Step 1 (replace `<EXACT_CONSTRAINT_NAME>` below):

```sql
-- Migration 068 — drift-fix batch (2026-05-24)
-- Source spec: docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md
-- F4 workout — rename workout_logs.exercise_name → workout_name
-- F4 nutrition — add nutrition_log_items.fiber

BEGIN;

-- ============================================================================
-- F4 workout — rename column + recreate unique constraint
-- ============================================================================

-- Drop the old UNIQUE constraint referencing exercise_name. The exact
-- name was captured in Task 0 preflight (typically
-- `workout_logs_user_id_date_exercise_name_key` or
-- `uniq_workout_logs_user_date_exercise`).
ALTER TABLE public.workout_logs
  DROP CONSTRAINT IF EXISTS <EXACT_CONSTRAINT_NAME>;

-- Rename the column. Atomic — no dual-write phase since founder is
-- sole tester and controls all installs.
ALTER TABLE public.workout_logs RENAME COLUMN exercise_name TO workout_name;

-- Recreate the UNIQUE constraint with the new column name.
ALTER TABLE public.workout_logs
  ADD CONSTRAINT workout_logs_user_id_date_workout_name_key
  UNIQUE (user_id, date, workout_name);

COMMENT ON COLUMN public.workout_logs.workout_name IS
  'Workout session name (e.g. "Push A"). Renamed from exercise_name 2026-05-24 (drift-fix F4) — the value was always a session label, never a per-exercise identifier. Per-exercise data lives in workout_log_exercises.';

-- ============================================================================
-- F4 nutrition — add fiber column (additive only)
-- ============================================================================
ALTER TABLE public.nutrition_log_items
  ADD COLUMN IF NOT EXISTS fiber NUMERIC DEFAULT 0;

COMMENT ON COLUMN public.nutrition_log_items.fiber IS
  'Per-item fiber (g). Populated by NutritionWriteService→sync_nutrition projection (added 2026-05-24 drift-fix F4). Legacy rows default 0 — no backfill source (no fiber column existed pre-migration).';

COMMIT;
```

- [ ] **Step 2: FOUNDER GATE — present the migration SQL to the founder**

STOP. Output the exact contents of `068b_drift_fix_batch.sql` to the founder, including the substituted constraint name. Wait for explicit "apply" or "ok" before continuing to Step 3.

Rationale: this touches production schema. Per [[feedback_no_setup_confirmations]] routine steps don't need confirmation, but live schema changes DO.

- [ ] **Step 3: Apply migration via MCP**

After founder approval, run:
```
mcp__ba7b5e8e__apply_migration(
  project_id: "dedsavbjuwgarrhphgnl",
  name: "068b_drift_fix_batch",
  query: <full SQL content from Step 1>
)
```

Expected: success response. If error (e.g., constraint name guess wrong), STOP and surface to founder — do NOT retry with a different guess without re-querying live.

- [ ] **Step 4: Verify migration landed live**

Run:
```
mcp__ba7b5e8e__execute_sql(
  project_id: "dedsavbjuwgarrhphgnl",
  query: "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='workout_logs' AND column_name IN ('exercise_name', 'workout_name');"
)
```
Expected: 1 row with `workout_name`. Zero rows for `exercise_name`.

Run:
```
mcp__ba7b5e8e__execute_sql(
  project_id: "dedsavbjuwgarrhphgnl",
  query: "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='nutrition_log_items' AND column_name='fiber';"
)
```
Expected: 1 row.

- [ ] **Step 5: Update backups/applied_migrations.json**

Read the current file and append a new entry. Mirror the existing entry shape (read the last entry for the exact JSON schema this project uses):

```bash
# Read current state
cat backups/applied_migrations.json | tail -30
```

Append a new entry (adjust JSON shape to match existing entries):
```json
{
  "version": "068b_drift_fix_batch",
  "applied_at": "2026-05-24T<ISO_TIMESTAMP>Z",
  "applied_via": "mcp__ba7b5e8e__apply_migration",
  "summary": "Rename workout_logs.exercise_name → workout_name; add nutrition_log_items.fiber (drift-fix F4)"
}
```

- [ ] **Step 6: Stage the migration files**

```bash
git add supabase/migrations/068b_drift_fix_batch.sql backups/applied_migrations.json
```

Do NOT commit yet.

---

## Task 10: Update Edge Function readers + redeploy

**Files:**
- Modify: every Edge Function listed in Task 0 preflight as AFFECTED
- (For each affected `.ts` file: replace `exercise_name` with `workout_name` ONLY in queries against `workout_logs`. Do NOT change references to `workout_log_exercises.exercise_name` — that column is unchanged.)

- [ ] **Step 1: For each AFFECTED Edge Function from preflight, apply the rename**

Example: `supabase/functions/weekly-report/index.ts`. Read lines 160-200. Find:
```ts
const { data: logs } = await supa
  .from("workout_logs")
  .select("date, exercise_name, duration_seconds, rpe")
  // ...
```
Replace `exercise_name` with `workout_name` ONLY in the SELECT against `workout_logs`. Update any downstream projection that reads `e.exercise_name` from the `workout_logs` row to `e.workout_name`.

DO NOT touch any line that reads from `workout_log_exercises` or any other table.

Repeat for every file in the preflight AFFECTED list.

- [ ] **Step 2: Re-run preflight grep to confirm no `workout_logs` reader still references the old column**

Run Grep tool:
```
pattern: "exercise_name"
path: "supabase/functions"
glob: "*.ts"
output_mode: "content"
-n: true
-C: 5
```

For each match, confirm the table-of-record (within the 5 lines of context) is NOT `workout_logs`. If a `workout_logs` reader still references `exercise_name`, return to Step 1 and fix.

- [ ] **Step 3: For each modified Edge Function, deploy via host-shell pipeline**

For each function (e.g. `weekly-report`):

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js weekly-report --auto --functions-dir <worktree>/supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl weekly-report .claude/_payload_weekly-report.json false
```

(For functions with `verify_jwt: true`, pass `true` as the final arg. Check the existing function config first.)

Expected: each deploy returns success + new version number.

Record the deployed function names + new versions in the diagnose-doc (Task 15).

- [ ] **Step 4: Verify deploy via MCP**

For each deployed function:
```
mcp__ba7b5e8e__get_edge_function(
  project_id: "dedsavbjuwgarrhphgnl",
  function_slug: "<function-name>"
)
```
Expected: returns the function with version bumped, body containing the new `workout_name` reads.

- [ ] **Step 5: Stage the Edge Function source changes**

```bash
git add supabase/functions/
```

Do NOT commit yet.

---

## Task 11: Workout F5 P2 — Delete `logSetWithPrRescan`

**Files:**
- Modify: `lib/features/train/repositories/workout_repository.dart` (delete lines from preflight Step 4 — typically ~1114 to ~1205)
- Create: `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart`

- [ ] **Step 1: Read the method body to confirm exact line range**

Use the line range captured in Task 0 Step 4 (preflight). Open the file and confirm the method is still where preflight said it is (no concurrent edit drift).

- [ ] **Step 2: Delete the method body**

Delete the method, including its leading docstring/comments if the docstring exclusively describes this method (check for `///` lines immediately preceding the `Future<String> logSetWithPrRescan({`).

After deletion, run `flutter analyze --no-fatal-infos` to confirm no other code references symbols local to the deleted method:
```bash
flutter analyze lib/features/train/repositories/workout_repository.dart
```
Expected: 0 errors. If errors, examine — should not happen since preflight confirmed 0 callers.

- [ ] **Step 3: Write the contract test**

Create `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart`:

```dart
// test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart
//
// Drift-fix batch 2026-05-24 / F5 workout (P2).
//
// Per APK Test #16.1, `WorkoutRepository.logSetWithPrRescan` was
// one of three rogue exlog_* key writers and was migrated off (AI
// coach `logPR` tool now routes through
// `WorkoutWriteService.logExercise`). With zero active callers
// (verified at deletion time), the method has been deleted.
//
// This test pins that the method declaration does not reappear.
//
// Note: existing test
// `test/contracts/tool_dispatcher_log_pr_uses_writeservice_test.dart`
// already pins that the AI coach tool dispatcher does not CALL this
// method; this test pins that the method itself does not EXIST.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('logSetWithPrRescan method declaration is deleted from workout_repository', () {
    final file = File(
      'lib/features/train/repositories/workout_repository.dart',
    );
    expect(file.existsSync(), isTrue);

    final source = file.readAsStringSync();
    final stripped = _stripComments(source);

    // Pattern: method declaration `Future<String> logSetWithPrRescan(`.
    final pattern = RegExp(
      r"""Future\s*<\s*String\s*>\s+logSetWithPrRescan\s*\(""",
    );

    expect(
      pattern.hasMatch(stripped),
      isFalse,
      reason: 'Found `logSetWithPrRescan` method declaration in '
          'workout_repository.dart. The legacy method was deleted '
          'in the 2026-05-24 drift-fix batch (F5). If reinstating, '
          'route through WorkoutWriteService.logExercise and update '
          'this test.',
    );
  });
}

String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
```

- [ ] **Step 4: Run the test — must PASS (method already deleted in Step 2)**

Run:
```bash
flutter test test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart
```
Expected: `+1: All tests passed!`

- [ ] **Step 5: Run the existing tool-dispatcher contract test to verify it still passes**

Run:
```bash
flutter test test/contracts/tool_dispatcher_log_pr_uses_writeservice_test.dart
```
Expected: still passes (it tests for absence of CALL, which is still true).

- [ ] **Step 6: Stage the changes**

```bash
git add lib/features/train/repositories/workout_repository.dart test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart
```

Do NOT commit yet.

---

## Task 12: Wire Gate 23 into `/build-apk` skill

**Files:**
- Modify: `.claude/skills/build-apk/SKILL.md` (or wherever the gate list lives)

- [ ] **Step 1: Find where Gate 17 is registered**

Run Grep tool:
```
pattern: "check_exlog_key_canonical"
path: ".claude/skills"
output_mode: "content"
-n: true
```

Expected: a few hits in `build-apk/SKILL.md` or equivalent file documenting the gate list.

- [ ] **Step 2: Add Gate 23 to the list using the same shape as Gate 17**

Add an entry alongside Gate 17. Use parallel structure — the entry should say something like:

```
### Gate 23 — nlog_* canonical writer enforcement

Runs `dart run scripts/check_nlog_key_canonical.dart`. Fails the
build if any file outside the canonical NutritionWriteService /
documented restore mirror / migration mirror constructs an `nlog_*`
Hive key. Mirrors Gate 17 for the nutrition domain. Shipped in the
2026-05-24 drift-fix batch (F2).
```

Adjust exact wording / numbering to match the skill file's existing format.

- [ ] **Step 3: Stage the skill update**

```bash
git add .claude/skills/build-apk/SKILL.md
```
(Adjust path to match real file location found in Step 1.)

Do NOT commit yet.

---

## Task 13: Update CLAUDE.md §6 rule 22 cross-reference to Gate 23

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Find where CLAUDE.md enumerates gates**

Run Grep tool:
```
pattern: "Gate 17|Gate 18|Gate 22"
path: "CLAUDE.md"
output_mode: "content"
-n: true
```

- [ ] **Step 2: Add Gate 23 reference in the appropriate section**

If §6 rule 22's "build gates" list enumerates 22 build gates, bump to 23 and add a one-line description. If gates are listed in §19 instead, follow the existing pattern.

Use the same prose style as the surrounding text — concise, references the script path.

- [ ] **Step 3: Stage the CLAUDE.md update**

```bash
git add CLAUDE.md
```

Do NOT commit yet.

---

## Task 14: Update SoT registry

**Files:**
- Modify: `docs/sot_registry.yaml`

- [ ] **Step 1: Find existing entry for `nlog_*` canonical writer**

Run Grep tool:
```
pattern: "computeLogKey|nlog_"
path: "docs/sot_registry.yaml"
output_mode: "content"
-n: true
```

- [ ] **Step 2: Add or update entries**

If an entry exists for the NutritionWriteService canonical writer, update it to add Gate 23 + the new behavioral test path. If no entry exists, create one mirroring an `exlog_*`-style entry. Required fields:
- `concept: nlog_canonical_writer`
- `writer: lib/core/services/nutrition_write_service.dart`
- `readers:` (list — `nutrition_log_items` consumers + restore mirror + migrator)
- `regression_test:` `test/contracts/nlog_key_canonical_test.dart`
- `behavioral_test_path:` `test/contracts/nutrition_write_service_ist_anchored_test.dart`
- `build_gate:` `scripts/check_nlog_key_canonical.dart`

Run the validator to confirm valid yaml:
```bash
dart run scripts/validate_sot_registry.dart
```
(If a validator script exists — find via Grep on `validate_sot`.)

- [ ] **Step 3: Stage the registry update**

```bash
git add docs/sot_registry.yaml
```

Do NOT commit yet.

---

## Task 15: Closure YAML + diagnose-doc

**Files:**
- Create: `docs/audit/2026_05_24_drift_fix_closures.yaml`
- Create: `docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md`

- [ ] **Step 1: Write the closure YAML**

Create `docs/audit/2026_05_24_drift_fix_closures.yaml`:

```yaml
# Drift-fix batch closure tally — 2026-05-24
# Source spec: docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md
# Source findings: docs/audit/2026-05-24-drift-scan-workout.md + docs/audit/2026-05-24-drift-scan-nutrition.md
batch: 2026-05-24-drift-fix
total_findings: 9
closed_count: 9

findings:
  - id: nutrition-F1
    severity: P0
    title: NutritionWriteService.computeLogKey not IST-anchored
    terminal_state: closed_in_commit
    test_path: test/contracts/nutrition_write_service_ist_anchored_test.dart

  - id: nutrition-F2
    severity: P1
    title: Add Gate 23 (nlog_* canonical writer enforcement)
    terminal_state: closed_in_commit
    test_path: test/contracts/nlog_key_canonical_test.dart
    build_gate: scripts/check_nlog_key_canonical.dart

  - id: nutrition-F3
    severity: P2
    title: Drop dead fallback reads (food_name, serving_g) in sync_nutrition projection
    terminal_state: closed_in_commit
    test_path: test/contracts/nutrition_write_to_read_contract_test.dart  # existing, no new test needed

  - id: nutrition-F4
    severity: P2
    title: Add nutrition_log_items.fiber column + projection
    terminal_state: closed_in_commit
    migration: supabase/migrations/068b_drift_fix_batch.sql
    test_path: test/contracts/nutrition_log_items_fiber_projection_test.dart

  - id: workout-F1
    severity: P1
    title: AI snapshot PR-set reps semantic (was reporting SUM)
    terminal_state: closed_in_commit
    test_path: test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart

  - id: workout-F2
    severity: P1
    title: Drop top-level duration_seconds reads (writer never emits)
    terminal_state: closed_in_commit
    test_path: test/contracts/no_top_level_duration_seconds_reads_test.dart

  - id: workout-F3
    severity: P2
    title: Drop dead `notes: log['id']` stuffing in workout_logs sync
    terminal_state: closed_in_commit
    test_path: test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart

  - id: workout-F4
    severity: P2
    title: Rename workout_logs.exercise_name → workout_name (column was session label, not per-exercise)
    terminal_state: closed_in_commit
    migration: supabase/migrations/068b_drift_fix_batch.sql
    test_path: test/contracts/cloud_workout_logs_uses_workout_name_test.dart

  - id: workout-F5
    severity: P2
    title: Delete legacy logSetWithPrRescan method (zero callers — verified)
    terminal_state: closed_in_commit
    test_path: test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart
```

- [ ] **Step 2: Write the diagnose-doc**

Create `docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md`. Read an existing diagnose-doc from `docs/diagnoses/` first to confirm exact required-field structure (validator at `scripts/validate_diagnose_doc.dart` enforces a specific schema).

Use this skeleton (adjust fields to match the validator's required keys):

```markdown
---
id: 524d12
date: 2026-05-24
title: Drift-fix batch — 9 findings + 2 schema migrations
severity: mixed (1 P0 + 3 P1 + 5 P2)
status: closed
---

## Summary

First run of the `writer-reader-drift-detector` agent (ECC adoption
B1) against the workout + nutrition domains surfaced 9 findings.
Closed in a single mega-commit (Approach C per founder choice).

## The 9 findings

(One paragraph each — copy-paste the spec section headers + 2-line
summaries.)

## Migration 068

(Diff of the SQL applied live + verify queries that confirmed the
schema reached the desired state.)

## Edge Function deploys

(Function name + old → new version for each redeployed function.)

## Regression tests added

(List of test paths.)

## Build gate added

scripts/check_nlog_key_canonical.dart (Gate 23).

## Why this batch was a single commit

Approach C — founder selected, waiving feedback_gates_before_refactor
for this batch. Justification: 9 mostly-mechanical findings;
pre-commit hook (~8 min) only runs once. Rule still applies to
future structural batches.

## Re-run drift-detector for verification

(Note that the success criterion includes re-running the agent and
verifying 0 new findings.)
```

- [ ] **Step 3: Validate the diagnose-doc**

Run:
```bash
dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md
```
Expected: exits 0.

If validation fails, fix the doc to match the validator's required schema. Do NOT skip validation — the pre-commit hook will block the commit otherwise.

- [ ] **Step 4: Stage the closure files**

```bash
git add docs/audit/2026_05_24_drift_fix_closures.yaml docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md
```

Do NOT commit yet.

---

## Task 16: Re-run drift-detector for verification

**Goal:** Confirm zero new drift findings in workout + nutrition after all fixes.

- [ ] **Step 1: Dispatch the drift-detector agent**

Use the Task tool (Agent dispatch) on the `writer-reader-drift-detector` subagent:
```
Agent({
  subagent_type: "writer-reader-drift-detector",
  description: "Drift-fix batch verification",
  prompt: "Re-scan workout + nutrition domains for writer/reader drift after the 2026-05-24 drift-fix batch. Read the 9 closures in docs/audit/2026_05_24_drift_fix_closures.yaml. Verify each is closed in code: F1 nutrition IST in computeLogKey, F2 Gate 23 active, F3 dead fallbacks gone, F4 fiber present, workout F1 PR-set reps semantic, F2 no top-level duration_seconds reads, F3 no notes:log[id] stuffing, F4 workout_name not exercise_name in workout_logs sync, F5 logSetWithPrRescan deleted. Report any new drift findings outside this closure set. Under 400 words."
})
```

- [ ] **Step 2: Verify report shows zero new findings**

The agent should return P0 = 0, P1 = 0, P2 = 0 OR list new findings.

If new findings: STOP and surface to founder. Either (a) close them in this batch (no deferrals), or (b) escalate as a separate brainstorm per founder direction.

If zero findings: continue.

- [ ] **Step 3: Append the agent's report to the diagnose-doc**

Open `docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md` and append the agent's brief report under a new section `## Verification — drift-detector re-run`. This gives the future audit reader proof the batch closed cleanly.

```bash
git add docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md
```

---

## Task 17: Final mega-commit + push

**Files:**
- All staged changes from Tasks 0-16

- [ ] **Step 1: Review the full staged set**

Run:
```bash
git status
git diff --cached --stat
```

Expected output: ~15-25 files modified/created. Sanity-check the file list matches what each task touched. No surprises.

If anything unexpected (e.g., a generated file or vendored dependency staged), `git restore --staged <path>` to unstage.

- [ ] **Step 2: Run the full test suite once before commit (faster feedback than waiting for pre-commit)**

```bash
flutter analyze --no-fatal-infos && flutter test
```
Expected: 0 analyze errors, all tests pass.

If any test fails: STOP and investigate. Do NOT proceed to commit. Per CLAUDE.md rule 20, fix the failure before committing.

- [ ] **Step 3: Create the mega-commit**

```bash
git commit -m "$(cat <<'EOF'
fix(drift): close 9 drift-fix-batch findings + migration 068 + Gate 23

Closes all 9 writer/reader drift findings surfaced by the 2026-05-24
writer-reader-drift-detector first run (ECC adoption B1):

Nutrition (4):
  - F1 P0: NutritionWriteService.computeLogKey now IST-anchored via
    istDateStr() — closes the recurring IST drift bug class on the
    nutrition domain.
  - F2 P1: Gate 23 (scripts/check_nlog_key_canonical.dart) +
    contract test pin the 3-file allowlist for nlog_* writers.
  - F3 P2: Drop dead fallback reads (food_name, serving_g) in
    sync_nutrition per-item projection.
  - F4 P2: Add nutrition_log_items.fiber column (migration 068) +
    project from Hive on per-item sync.

Workout (5):
  - F1 P1: AI snapshot PR-set reps semantic — surface reps at the
    PR weight, not SUM across sets.
  - F2 P1: Drop top-level duration_seconds reads in receipt +
    train_screen. Route through WorkoutReadService.bestPerSetDuration.
  - F3 P2: Drop dead `notes: log['id']` stuffing in workout_logs
    sync projection.
  - F4 P2: Rename workout_logs.exercise_name → workout_name
    (migration 068) — column was session label, never a
    per-exercise identifier. Edge Functions redeployed.
  - F5 P2: Delete legacy WorkoutRepository.logSetWithPrRescan
    method (zero active callers — verified preflight).

Migration 068 (atomic — sole tester, controls all installs):
  - ALTER workout_logs RENAME exercise_name → workout_name.
  - Drop+recreate UNIQUE constraint on (user_id, date, workout_name).
  - ADD nutrition_log_items.fiber NUMERIC DEFAULT 0.

Edge Functions redeployed: weekly-report (+ any others listed in
diagnose-doc).

Approach C — single mega-commit (founder-locked). Waives
feedback_gates_before_refactor for this batch (justification:
9 mostly-mechanical findings, single pre-commit run).

8 new contract / behavioral tests (TDD shape — tests first).
1 new build gate (Gate 23).
0 deferrals — every finding closed.

closes-diagnose: 524d12

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Pre-commit hook runs (~8 min): flutter analyze + flutter test. Wait for it to complete.

Expected: commit lands. Verify:
```bash
git log --oneline -2
```

- [ ] **Step 4: FOUNDER GATE — confirm before push**

STOP. Present the commit details to the founder. Do NOT push without explicit "push" / "ship" / "ok push" from the founder per CLAUDE.md global rule "Never commit or push unless the user explicitly asks."

- [ ] **Step 5: Push to origin (after founder approval)**

```bash
git push origin claude/frosty-bardeen-cce54b
```

Verify the push reflected on remote:
```bash
git log origin/claude/frosty-bardeen-cce54b --oneline -1
```

---

## Out of scope (explicit)

No deferrals. Every finding closed in this batch.

The Edge Function deploys may surface unexpected `workout_logs.exercise_name` readers that preflight missed. Per the spec's "Edge Function deploy" note: any function NOT discovered in preflight that subsequently fails (visible in client_errors or cron telemetry) will be fixed in a hotfix commit if found — that's not a deferral, it's a normal post-deploy verification window.

---

## Success criteria (from spec — copied for handy reference)

1. Migration 068 applied live and visible in `list_migrations` MCP query.
2. All 9 contract tests pass on first run after fix.
3. Pre-commit hook passes without `--no-verify`.
4. `dart run scripts/check_nlog_key_canonical.dart` exits 0.
5. Closure YAML shows 9/9 closed.
6. Diagnose-doc `2026-05-24-drift-fix-batch-524d12.md` passes validator.
7. Re-running drift-detector surfaces ZERO new findings.
8. Pushed to remote (after founder approval).
