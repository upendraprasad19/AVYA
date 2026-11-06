# Food Logging & Nutrition UX Observations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 7 nutrition/diet-plan UX and reliability observations from a founder testing session: no meal retagging, confusable diet-plan-suggestion visuals, an image-size bug breaking Scan Meal, no admin visibility into Gemini failures, a log-sheet tab mismatch, a redundant diet-plan modal, and a slow cold start.

**Architecture:** Ten self-contained tasks touching `lib/features/nutrition/`, `lib/core/services/`, `lib/features/auth/` (splash/restore), and `supabase/functions/ai-proxy` + `_shared/gemini.ts`. Client and server work are independent; only the last two tasks (Part G) touch the Edge Function and are sequenced last since they carry the batch's `account`-tier blast radius.

**Tech Stack:** Flutter/Dart (client), Riverpod, Hive, Deno/TypeScript (Edge Functions), Supabase Postgres.

**Spec:** `docs/superpowers/specs/2026-09-20-food-logging-observations-design.md`

## Global Constraints

- Hive-first: every write goes through the existing `NutritionWriteService` — never a raw `Hive.box(...).put()` from a widget (root CLAUDE.md §4.4 rule 1/4).
- Wardroom palette / DM Sans only for any new UI (`AppColors`, `AppTypography`) — no new colors, no system fonts.
- Every new writer/reader contract gets a `docs/sot_registry.yaml` entry + a `test/contracts/*_writer_to_reader_test.dart` (root CLAUDE.md §4.4 rule 21).
- Every genuine bug fix (not feature work) gets a diagnose-doc under `docs/diagnoses/` per root CLAUDE.md §4.4 rule 22 — Task 1 (image size) and Task 2 (diet-plan modal) are bug fixes; Tasks 3-4, 6-7 are feature/consolidation work and do not need one.
- Server-side (`_shared/gemini.ts`, `ai-proxy/index.ts`) changes need `deno check --node-modules-dir=none <file>` before commit, and a live deploy needs separate, explicit founder authorization (never bundled into "the plan was approved").
- Client-facing error message text for AI failures does NOT change in this batch — only server-side classification/alerting is added (founder decision, spec Founder Decision #4).

---

### Task 1: Fix Scan Meal / Cart Auditor image-size bug + scan telemetry

**Files:**
- Modify: `lib/features/nutrition/widgets/scan_meal_section.dart:282-283`
- Modify: `lib/features/nutrition/widgets/cart_auditor_section.dart:170-171`
- Modify: `lib/features/nutrition/providers/nutrition_provider.dart:1421-1426` (`ScanMealNotifier.scanImage` catch block)
- Create: `docs/diagnoses/2026-09-20-scan-meal-image-too-large-<id>.md` (bug-id placeholder `<id>` — generate a fresh 6-char hex per convention, e.g. via `openssl rand -hex 3`)
- Test: `test/contracts/scan_meal_image_downscale_test.dart`
- Test: `test/contracts/ai_breakdown_notifier_scan_meal_telemetry_test.dart` (mirrors the existing `ai_breakdown_notifier_save_meal_telemetry_test.dart` fault-injection pattern)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new — this is a pure bug fix, no new public API.

- [ ] **Step 1: Write the failing test for image downscaling**

`ImagePicker` itself can't be unit-tested at the byte-size level cheaply (it's a platform channel), so this is a source-grep presence test — it fails today because neither call site passes the constraint.

```dart
// test/contracts/scan_meal_image_downscale_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scan_meal_section.dart downscales the picked image', () {
    final src = File('lib/features/nutrition/widgets/scan_meal_section.dart').readAsStringSync();
    final call = RegExp(r'picker\.pickImage\(([^)]*)\)').firstMatch(src);
    expect(call, isNotNull, reason: 'pickImage call not found');
    final args = call!.group(1)!;
    expect(args, contains('imageQuality'),
        reason: 'scan_meal_section.dart must downscale the picked image (obs 2, diagnose scan-meal-image-too-large)');
    expect(args, contains('maxWidth'));
  });

  test('cart_auditor_section.dart downscales the picked image', () {
    final src = File('lib/features/nutrition/widgets/cart_auditor_section.dart').readAsStringSync();
    final call = RegExp(r'picker\.pickImage\(([^)]*)\)').firstMatch(src);
    expect(call, isNotNull, reason: 'pickImage call not found');
    final args = call!.group(1)!;
    expect(args, contains('imageQuality'));
    expect(args, contains('maxWidth'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/contracts/scan_meal_image_downscale_test.dart`
Expected: FAIL — both assertions on `contains('imageQuality')` fail because neither call site has it yet.

- [ ] **Step 3: Fix both `pickImage` call sites**

In `lib/features/nutrition/widgets/scan_meal_section.dart`, change line 283 from:
```dart
    final image = await picker.pickImage(source: source);
```
to:
```dart
    final image = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
```

In `lib/features/nutrition/widgets/cart_auditor_section.dart`, change line 171 from:
```dart
    final image = await picker.pickImage(source: ImageSource.gallery);
```
to:
```dart
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
```

Rationale (for the diagnose-doc): `ai-proxy/index.ts:517-518` rejects any base64 image payload over ~7.5M chars (≈5.6MB decoded) with an immediate `400`, before ever calling Gemini. A modern phone camera photo at full resolution routinely exceeds this. 1600px @ quality 85 keeps a typical food/cart photo well under 1MB.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/contracts/scan_meal_image_downscale_test.dart`
Expected: PASS

- [ ] **Step 5: Add scan-failure telemetry (currently zero telemetry on this path)**

Write the failing telemetry test first, mirroring the existing `ai_breakdown_notifier_save_meal_telemetry_test.dart` fault-injection pattern (read that file first to copy its harness shape exactly — it injects a throw into the write path and asserts `ErrorTelemetry.recordNonFatal` was called with a specific `reason`).

```dart
// test/contracts/ai_breakdown_notifier_scan_meal_telemetry_test.dart
// (Harness mirrors ai_breakdown_notifier_save_meal_telemetry_test.dart —
// copy its ProviderContainer + fault-injection setup verbatim, then:)
test('ScanMealNotifier.scanImage records telemetry on failure', () async {
  // ... (same container setup as the AI-breakdown telemetry test) ...
  // Force SupabaseService.instance.callFunction to throw for this call.
  await container.read(scanMealProvider.notifier).scanImage([1, 2, 3]);
  expect(recordedTelemetry.any((e) => e.reason == 'scan_meal_notifier_scan_image'), isTrue);
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/contracts/ai_breakdown_notifier_scan_meal_telemetry_test.dart`
Expected: FAIL — no telemetry call exists yet in the catch block.

- [ ] **Step 7: Add the telemetry call**

In `lib/features/nutrition/providers/nutrition_provider.dart`, change the catch block at lines 1421-1426 from:
```dart
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        error: 'Scan failed. Check your connection and try again.',
      );
    }
```
to:
```dart
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'scan_meal_notifier_scan_image'));
      state = state.copyWith(
        isScanning: false,
        error: 'Scan failed. Check your connection and try again.',
      );
    }
```
(`ErrorTelemetry` is already imported in this file — confirm via `grep -n "import.*error_telemetry" lib/features/nutrition/providers/nutrition_provider.dart`; if not, add `import '../../../core/services/error_telemetry.dart';`.)

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test test/contracts/scan_meal_image_downscale_test.dart test/contracts/ai_breakdown_notifier_scan_meal_telemetry_test.dart`
Expected: both PASS

- [ ] **Step 9: Write the diagnose-doc**

Create `docs/diagnoses/2026-09-20-scan-meal-image-too-large-<id>.md` following this repo's diagnose-doc template (run `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-09-20-scan-meal-image-too-large-<id>.md` after writing to confirm it validates). Content must name: symptom (Scan Meal fails instantly with "Check your connection"), writer (`scan_meal_section.dart:282-283`, `cart_auditor_section.dart:170-171` — no compression before upload), reader/rejector (`ai-proxy/index.ts:517-518`, the 5.6MB decoded cap), the fix, and the two test paths above. Confirmed live via Supabase `function_edge_logs` query: 5× `400` on `ai-proxy` at 2026-09-19T16:38-16:39 UTC, timestamp-matching the founder's screenshot.

- [ ] **Step 10: Commit**

```bash
git add lib/features/nutrition/widgets/scan_meal_section.dart lib/features/nutrition/widgets/cart_auditor_section.dart lib/features/nutrition/providers/nutrition_provider.dart test/contracts/scan_meal_image_downscale_test.dart test/contracts/ai_breakdown_notifier_scan_meal_telemetry_test.dart docs/diagnoses/2026-09-20-scan-meal-image-too-large-*.md
git commit -m "$(cat <<'EOF'
fix(nutrition): downscale scan/cart images before upload, add scan telemetry

Scan Meal failed instantly on any full-resolution camera photo because
ai-proxy rejects payloads over ~5.6MB decoded before ever calling Gemini.
Neither picker.pickImage() call constrained size. Also adds the missing
client-side telemetry on scan failure (previously zero).

closes-diagnose: <id>
EOF
)"
```

---

### Task 2: Diet Plan screen — remove the blocking "Saved Diet Plan Found" modal

**Files:**
- Modify: `lib/features/nutrition/screens/diet_plan_screen.dart:57-68` (`_generatePlan`)
- Modify: `lib/features/nutrition/screens/diet_plan_screen.dart:300-349` (delete `_showLoadSavedPlanDialog`)
- Create: `docs/diagnoses/2026-09-20-diet-plan-blocking-modal-<id2>.md`
- Test: `test/widgets/diet_plan_screen_no_modal_test.dart`

**Interfaces:**
- Consumes: `UserRepository.instance.getSavedDietPlan()` (unchanged), `_loadSavedPlan(Map<String, dynamic>)` (unchanged, now called directly).
- Produces: nothing new — `_showLoadSavedPlanDialog` is deleted.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/widgets/diet_plan_screen_no_modal_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/nutrition/screens/diet_plan_screen.dart';
// ... existing test harness imports for Hive setup, mirroring
// diet_plan_screen's existing widget tests (find one via
// `grep -rl DietPlanScreen test/` and copy its setUp).

void main() {
  testWidgets('renders saved plan immediately with no dialog', (tester) async {
    // Seed Hive with a saved plan via UserRepository.instance.saveDietPlan(...)
    // (use the same seeding helper any existing diet_plan_screen test uses).
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: DietPlanScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'obs 8 — the saved-plan-found dialog must not appear');
    expect(find.text('Saved Diet Plan Found'), findsNothing);
    // The saved plan's meal content should be visible on the first settle.
    expect(find.byIcon(Icons.refresh), findsOneWidget); // toolbar Regenerate
    expect(find.byIcon(Icons.save_outlined), findsOneWidget); // toolbar Save
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/diet_plan_screen_no_modal_test.dart`
Expected: FAIL — `find.byType(AlertDialog)` finds one.

- [ ] **Step 3: Remove the dialog, load the saved plan directly**

In `lib/features/nutrition/screens/diet_plan_screen.dart`, change `_generatePlan` (lines 57-68) from:
```dart
    // Check for saved plan on first entry only
    if (!_checkedSaved) {
      _checkedSaved = true;
      final savedPlan = UserRepository.instance.getSavedDietPlan();
      if (savedPlan != null) {
        _showLoadSavedPlanDialog(savedPlan);
        return;
      }
    }

    _generateFreshPlan();
```
to:
```dart
    // Check for saved plan on first entry only. Obs 8 fix: load it
    // immediately instead of gating behind a dialog — the AppBar's
    // existing Regenerate (:498) and Save (:514) icons already give
    // the user both actions without a blocking modal.
    if (!_checkedSaved) {
      _checkedSaved = true;
      final savedPlan = UserRepository.instance.getSavedDietPlan();
      if (savedPlan != null) {
        _loadSavedPlan(savedPlan);
        return;
      }
    }

    _generateFreshPlan();
```

Then delete the entire `_showLoadSavedPlanDialog` method (lines 300-349 — from `void _showLoadSavedPlanDialog(Map<String, dynamic> savedPlan) {` through its closing `}`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/diet_plan_screen_no_modal_test.dart`
Expected: PASS

- [ ] **Step 5: Run flutter analyze to confirm no dead-code warnings**

Run: `flutter analyze lib/features/nutrition/screens/diet_plan_screen.dart`
Expected: No issues (confirms no other call site references the deleted method).

- [ ] **Step 6: Write the diagnose-doc**

Create `docs/diagnoses/2026-09-20-diet-plan-blocking-modal-<id2>.md`. Symptom: opening Diet Plan shows a blank spinner behind a confirmation dialog. Writer: `_generatePlan` at `diet_plan_screen.dart:57-68` (pre-fix). Root cause: the saved plan is read synchronously from local Hive with no async barrier, yet gated behind a dialog instead of rendered. Fix + test path as above.

- [ ] **Step 7: Commit**

```bash
git add lib/features/nutrition/screens/diet_plan_screen.dart test/widgets/diet_plan_screen_no_modal_test.dart docs/diagnoses/2026-09-20-diet-plan-blocking-modal-*.md
git commit -m "$(cat <<'EOF'
fix(nutrition): show saved diet plan immediately, drop blocking modal

The saved plan was already available synchronously from local Hive but
was gated behind a "Load or regenerate?" dialog over a blank screen.
The AppBar's existing Regenerate/Save icons already give the user both
actions, so the dialog was pure friction.

closes-diagnose: <id2>
EOF
)"
```

---

### Task 3: Diet-plan slot visual distinction — "SUGGESTED" chip

**Files:**
- Modify: `lib/features/nutrition/widgets/todays_meals_card.dart:395-447` (`_EmptySlotCard.build`, the `hasPlan` branch)
- Test: `test/widgets/todays_meals_card_suggested_chip_test.dart`

**Interfaces:**
- Consumes: `PlannedSlot` (unchanged — `planned!.summary`, `planned!.calories`).
- Produces: nothing new — pure rendering change.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/widgets/todays_meals_card_suggested_chip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/widgets/todays_meals_card.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_plan_provider.dart';

void main() {
  testWidgets('planned-only slot shows a SUGGESTED chip, not a bare eyebrow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodaysMealsCard(
            meals: const [],
            plannedSlots: {
              'breakfast': const PlannedSlot(
                summary: 'Oats + banana',
                calories: 320,
                firstFoodName: 'Oats',
              ),
            },
          ),
        ),
      ),
    );
    expect(find.text('SUGGESTED'), findsOneWidget,
        reason: 'obs 7 — a diet-plan hint must read as a suggestion, not a logged entry');
  });
}
```

(Check `PlannedSlot`'s actual constructor field names via `grep -n "class PlannedSlot" -A 10 lib/features/nutrition/providers/diet_plan_provider.dart` before finalizing this test — use whatever fields it actually declares.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/todays_meals_card_suggested_chip_test.dart`
Expected: FAIL — no "SUGGESTED" text exists yet.

- [ ] **Step 3: Add the chip + dim the planned text**

In `lib/features/nutrition/widgets/todays_meals_card.dart`, inside `_EmptySlotCard.build`'s `if (hasPlan) ...[` block (lines 418-447), change:
```dart
              if (hasPlan) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FROM YOUR DIET PLAN',
                      style: AppTypography.monoXs.copyWith(
                        fontSize: 9,
                        color: AppColors.accent.withValues(alpha: 0.75),
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        planned!.summary,
                        style: AppTypography.body.copyWith(
                          fontSize: 12,
                          color: AppColors.textDim,
                          height: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
```
to:
```dart
              if (hasPlan) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Obs 7 fix: a visible chip (not just an eyebrow label)
                    // so a planned-but-unlogged slot can't be mistaken for
                    // a real entry — mirrors the state-chip vocabulary
                    // Train's DayCard already uses for planned vs done.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'SUGGESTED',
                        style: AppTypography.monoXs.copyWith(
                          fontSize: 8,
                          color: AppColors.accent.withValues(alpha: 0.75),
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        planned!.summary,
                        style: AppTypography.body.copyWith(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textGhost,
                          height: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
```
(The "FROM YOUR DIET PLAN" label text moves into the chip; `AppColors.textGhost` is the dimmer of the two greys already used elsewhere in this same file at line 401 — confirm it's dimmer than `textDim` via `grep -n "textGhost\|textDim" lib/core/theme/colors.dart` before applying, and swap to whichever constant is actually the dimmer one if the names don't match this assumption.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/todays_meals_card_suggested_chip_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/nutrition/widgets/todays_meals_card.dart test/widgets/todays_meals_card_suggested_chip_test.dart
git commit -m "feat(nutrition): distinguish diet-plan suggestions from logged meals with a SUGGESTED chip"
```

---

### Task 4: `NutritionWriteService.moveMealLog` — the retag write path

**Files:**
- Modify: `lib/core/services/nutrition_write_service.dart` (add new method after `editLog`, i.e. after line 352)
- Modify: `docs/sot_registry.yaml` (new `nutrition_log_retag` entry)
- Test: `test/contracts/nutrition_log_retag_writer_to_reader_test.dart`

**Interfaces:**
- Consumes: `computeLogKey` (`nutrition_write_service.dart:786-795`, existing `@visibleForTesting static`), `FoodItem.fromMap`/`.toMap()` (existing), `HiveService.instance.nutritionBox` (existing), `_invalidateNutritionProviders()` (existing private method), `SyncService.instance.syncNutritionData()` (existing).
- Produces: `Future<WriteResult> moveMealLog({required String logKey, required String newMealType, Map<String, dynamic>? macroUpdates})` — later tasks (Task 5) call this exact signature.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/nutrition_log_retag_writer_to_reader_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
// ... standard Hive test-harness imports (mirror
// test/contracts/nutrition_total_calories_writer_to_reader_test.dart's
// setUp exactly — temp dir + path_provider mock + HiveService.instance.init()).

void main() {
  setUp(() async {
    // (copy the exact setUp from nutrition_total_calories_writer_to_reader_test.dart)
  });

  test('moveMealLog rekeys a log to a new slot and the new slot reads it', () async {
    final date = DateTime(2026, 9, 20);
    final logResult = await NutritionWriteService.instance.logMeal(
      date: date,
      mealType: 'breakfast',
      items: [FoodItem(name: 'Oats', quantityG: 100, calories: 300, protein: 10, carbs: 50, fat: 5, fiber: 4)],
      source: NutritionWriteSource.manualSearch,
    );
    final oldKey = logResult.value as String;

    final moveResult = await NutritionWriteService.instance.moveMealLog(
      logKey: oldKey,
      newMealType: 'lunch',
    );
    expect(moveResult.success, isTrue);
    final newKey = moveResult.value as String;
    expect(newKey, isNot(equals(oldKey)));

    final box = HiveService.instance.nutritionBox;
    expect(box.get(oldKey), isNull, reason: 'old slot key must be gone');
    final moved = Map<String, dynamic>.from(box.get(newKey) as Map);
    expect(moved['meal_type'], 'lunch');
    expect(moved['id'], newKey);
    expect(moved['log_key'], newKey);
    expect(moved['items'], isNotEmpty);
  });

  test('moveMealLog applies macroUpdates atomically with the rekey', () async {
    final date = DateTime(2026, 9, 20);
    final logResult = await NutritionWriteService.instance.logMeal(
      date: date,
      mealType: 'breakfast',
      items: [FoodItem(name: 'Oats', quantityG: 100, calories: 300, protein: 10, carbs: 50, fat: 5, fiber: 4)],
      source: NutritionWriteSource.manualSearch,
    );
    final oldKey = logResult.value as String;

    final moveResult = await NutritionWriteService.instance.moveMealLog(
      logKey: oldKey,
      newMealType: 'dinner',
      macroUpdates: {'total_calories': 999},
    );
    final newKey = moveResult.value as String;
    final moved = Map<String, dynamic>.from(
        HiveService.instance.nutritionBox.get(newKey) as Map);
    expect(moved['total_calories'], 999);
    expect(moved['meal_type'], 'dinner');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/contracts/nutrition_log_retag_writer_to_reader_test.dart`
Expected: FAIL with "The method 'moveMealLog' isn't defined".

- [ ] **Step 3: Implement `moveMealLog`**

In `lib/core/services/nutrition_write_service.dart`, insert immediately after `editLog`'s closing brace (after line 352):

```dart
  /// Moves a logged meal to a different meal-type slot (obs 1 retag), and
  /// optionally applies macro edits in the same atomic write.
  ///
  /// Mirrors `WorkoutWriteService.moveExerciseLogs` (workout_write_service.dart
  /// :728-854): recompute the canonical key with the new slot, write there
  /// (merging item lists on collision), delete the old key.
  ///
  /// LOCAL-ONLY cloud consistency, same accepted residual as
  /// moveExerciseLogs and as this file's own deleteLog/editLog: this method
  /// just mutates Hive and fires the general `syncNutritionData()` fan-out,
  /// which upserts the NEW slot by natural key (user_id, date, meal_type).
  /// The vacated OLD slot's cloud row is not explicitly tombstoned here —
  /// neither is it by deleteLog or editLog anywhere else in this file, so
  /// this does not introduce a new class of gap, only inherits the existing
  /// one. See sync_nutrition.dart:296-314 for the natural-key upsert this
  /// depends on (id deliberately omitted per diagnose c9f2a7).
  Future<WriteResult> moveMealLog({
    required String logKey,
    required String newMealType,
    Map<String, dynamic>? macroUpdates,
  }) async {
    if (!isAllowedMealType(newMealType)) {
      return WriteResult.fail(
        'moveMealLog: mealType "$newMealType" not in {breakfast,lunch,dinner,snacks}',
      );
    }
    final box = HiveService.instance.nutritionBox;
    final raw = box.get(logKey);
    if (raw == null) {
      return WriteResult.fail('logKey $logKey not found');
    }
    final row = Map<String, dynamic>.from(raw as Map);
    if (row['meal_type'] == newMealType) {
      // No-op move — just apply macro updates via the existing path.
      if (macroUpdates != null && macroUpdates.isNotEmpty) {
        return editLog(logKey: logKey, updates: macroUpdates);
      }
      return WriteResult.ok(logKey);
    }

    final rawItems = ((row['items'] as List?) ?? const [])
        .map((e) => FoodItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final dateStr = row['date'] as String?;
    if (dateStr == null || dateStr.isEmpty) {
      return WriteResult.fail('moveMealLog: source row has no date');
    }
    final date = DateTime.parse(dateStr);
    final newKey =
        computeLogKey(istDate: date, mealType: newMealType, items: rawItems);

    row['meal_type'] = newMealType;
    row['id'] = newKey;
    row['log_key'] = newKey;
    if (macroUpdates != null) {
      row.addAll(macroUpdates);
    }
    row['logged_at'] = DateTime.now().toUtc().toIso8601String();
    _clampMealPayload(row);

    final existingAtDestination = box.get(newKey);
    if (existingAtDestination is Map) {
      // Collision — two logs landing in the same slot+item-hash bucket.
      // Merge items (union) and recompute totals, same shape as editLog's
      // items-changed branch.
      final destRow = Map<String, dynamic>.from(existingAtDestination);
      final destItems = ((destRow['items'] as List?) ?? const [])
          .map((e) => FoodItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final mergedItems = [...destItems, ...rawItems];
      row['items'] = mergedItems.map((i) => i.toMap()).toList();
      row['total_calories'] = mergedItems.fold<double>(
          0, (a, i) => a + i.kcalWithFallback).round();
      row['total_protein'] =
          mergedItems.fold<double>(0, (a, i) => a + i.protein).round();
      row['total_carbs'] =
          mergedItems.fold<double>(0, (a, i) => a + i.carbs).round();
      row['total_fat'] =
          mergedItems.fold<double>(0, (a, i) => a + i.fat).round();
      row['total_fiber'] =
          mergedItems.fold<double>(0, (a, i) => a + i.fiber).round();
    }

    try {
      await box.put(newKey, row);
      await box.delete(logKey);
    } catch (e, st) {
      debugPrint('[NutritionWriteService] moveMealLog put/delete failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_move_meal_log'));
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(newKey);
  }

```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/contracts/nutrition_log_retag_writer_to_reader_test.dart`
Expected: PASS

- [ ] **Step 5: Add the SoT registry entry**

Append to `docs/sot_registry.yaml` (same top-level list `sot_concepts:` the other nutrition entries live under — insert near the other nutrition entries, e.g. after the `nutrition_total_calories` entry around line 482):

```yaml
  - concept: nutrition_log_retag
    domain: nutrition
    behavioral_test_path: test/contracts/nutrition_log_retag_writer_to_reader_test.dart
    description: |
      Moving a logged meal to a different meal-type slot (obs 1, 2026-09-20
      brainstorm). Rekeys the nlog_* Hive row (meal_type is embedded in the
      key: nlog_<date>_<mealType>_<hash>) rather than a field-only update,
      because the cloud natural key is (user_id, date, meal_type) and a
      field-only update risks the FK-violation class fixed by diagnose
      c9f2a7. LOCAL-ONLY cloud consistency (same accepted residual as
      moveExerciseLogs and this file's own deleteLog/editLog) — the vacated
      old slot's cloud row is not explicitly tombstoned.
    writers:
      - file: lib/core/services/nutrition_write_service.dart
        line_range: 354-430
        method: moveMealLog
        notes: |
          Reads the row at the old key, recomputes the key via
          computeLogKey with the new mealType, merges on collision,
          writes at the new key, deletes the old key.
    reader_manifest_complete: true
    readers:
      - file: lib/features/nutrition/widgets/todays_meals_card.dart
        line_range: 73-86
        method: TodaysMealsCard.build (grouping by meal_type)
        semantic: aggregated
        fields_read: [meal_type, id, log_key]
```

- [ ] **Step 6: Run the full nutrition contract test file set to confirm no regressions**

Run: `flutter test test/contracts/nutrition_write_service_*_test.dart test/contracts/nutrition_log_retag_writer_to_reader_test.dart`
Expected: all PASS

- [ ] **Step 7: Commit**

```bash
git add lib/core/services/nutrition_write_service.dart docs/sot_registry.yaml test/contracts/nutrition_log_retag_writer_to_reader_test.dart
git commit -m "feat(nutrition): add NutritionWriteService.moveMealLog for meal-slot retagging"
```

---

### Task 5: Edit Macros sheet — meal-slot selector wired to `moveMealLog`

**Files:**
- Modify: `lib/features/nutrition/screens/nutrition_screen.dart:948-1064` (`_showEditMacrosSheet`)
- Test: `test/widgets/edit_macros_sheet_retag_test.dart`

**Interfaces:**
- Consumes: `NutritionWriteService.instance.moveMealLog` (Task 4), `foodLogProvider.notifier.updateFoodLog` (existing, unchanged for the no-retag case).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/widgets/edit_macros_sheet_retag_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ... same harness as any existing nutrition_screen widget test.

void main() {
  testWidgets('Edit Macros sheet has a meal-slot selector defaulted to the log\'s current slot', (tester) async {
    // Pump NutritionScreen (or a minimal harness that can invoke
    // _showEditMacrosSheet — check how existing edit-sheet tests, if any,
    // drive this; if none exist, pump the full NutritionScreen and tap a
    // populated meal item to open the sheet).
    // ... pump + tap to open the sheet for a 'breakfast' log ...
    expect(find.text('BREAKFAST'), findsWidgets); // slot selector shows current slot selected
    expect(find.text('LUNCH'), findsOneWidget);
    expect(find.text('DINNER'), findsOneWidget);
    expect(find.text('SNACK'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/edit_macros_sheet_retag_test.dart`
Expected: FAIL — no slot selector exists yet.

- [ ] **Step 3: Add the slot selector + retag-aware SAVE**

In `lib/features/nutrition/screens/nutrition_screen.dart`, inside `_showEditMacrosSheet` (after the existing controller declarations around line 970, before `showModalBottomSheet(`), add:

```dart
    final currentMealType =
        (meal['meal_type'] as String? ?? 'snacks').toLowerCase();
    final selectedMealType = ValueNotifier<String>(
      _allowedSlotKeys.contains(currentMealType) ? currentMealType : 'snacks',
    );
```

(Add a top-of-file or class-level constant `static const _allowedSlotKeys = {'breakfast', 'lunch', 'dinner', 'snacks'};` near the other private constants in this file if one doesn't already exist matching this set — check `grep -n "_allowedSlotKeys\|breakfast.*lunch.*dinner.*snack" lib/features/nutrition/screens/nutrition_screen.dart` first to reuse an existing one if present.)

Then, inside the `Column` children, immediately after the macro-fields `Row` (after line 1031's closing `),` for the `Row` containing `_macroField` calls) and before the `SizedBox(height: 18)` that precedes the SAVE button, insert:

```dart
              const SizedBox(height: 14),
              Text(
                'MEAL SLOT',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<String>(
                valueListenable: selectedMealType,
                builder: (context, value, _) => Row(
                  children: [
                    for (final slot in const ['breakfast', 'lunch', 'dinner', 'snacks'])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => selectedMealType.value = slot,
                          child: WardChip(
                            label: mealSlotLabel(slot),
                            tone: value == slot
                                ? WardChipTone.gold
                                : WardChipTone.neutral,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
```

(`mealSlotLabel` is already available from `meal_slot_inference.dart` — confirm it's imported in `nutrition_screen.dart`, add `import '../services/meal_slot_inference.dart';` if not. `WardChip`/`WardChipTone` are already used elsewhere in this same sheet's neighboring widgets per the Wardroom import at the top of the file.)

Then change the SAVE button's `onPressed` (lines 1045-1055) from:
```dart
                  onPressed: () {
                    ref.read(foodLogProvider.notifier).updateFoodLog(
                          logId: logId,
                          calories: double.tryParse(calCtrl.text) ?? 0,
                          protein: double.tryParse(proteinCtrl.text) ?? 0,
                          carbs: double.tryParse(carbsCtrl.text) ?? 0,
                          fat: double.tryParse(fatCtrl.text) ?? 0,
                          fiber: double.tryParse(fiberCtrl.text) ?? 0,
                        );
                    Navigator.of(context).pop();
                  },
```
to:
```dart
                  onPressed: () {
                    final newSlot = selectedMealType.value;
                    final macroUpdates = {
                      'total_calories': double.tryParse(calCtrl.text) ?? 0,
                      'total_protein': double.tryParse(proteinCtrl.text) ?? 0,
                      'total_carbs': double.tryParse(carbsCtrl.text) ?? 0,
                      'total_fat': double.tryParse(fatCtrl.text) ?? 0,
                      'total_fiber': double.tryParse(fiberCtrl.text) ?? 0,
                    };
                    if (newSlot != currentMealType) {
                      NutritionWriteService.instance.moveMealLog(
                        logKey: logId,
                        newMealType: newSlot,
                        macroUpdates: macroUpdates,
                      );
                    } else {
                      ref.read(foodLogProvider.notifier).updateFoodLog(
                            logId: logId,
                            calories: macroUpdates['total_calories']!,
                            protein: macroUpdates['total_protein']!,
                            carbs: macroUpdates['total_carbs']!,
                            fat: macroUpdates['total_fat']!,
                            fiber: macroUpdates['total_fiber']!,
                          );
                    }
                    Navigator.of(context).pop();
                  },
```

(Confirm `NutritionWriteService` is imported in `nutrition_screen.dart` — add `import '../../../core/services/nutrition_write_service.dart';` if not.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/edit_macros_sheet_retag_test.dart`
Expected: PASS

- [ ] **Step 5: Run the nutrition screen's existing widget tests to confirm no regression**

Run: `flutter test test/widgets/ -t nutrition` (or the specific existing nutrition_screen test file(s) found via `grep -rl "_showEditMacrosSheet\|EDIT MACROS" test/`)
Expected: all PASS — the non-retag (same-slot) SAVE path must behave identically to before.

- [ ] **Step 6: Commit**

```bash
git add lib/features/nutrition/screens/nutrition_screen.dart test/widgets/edit_macros_sheet_retag_test.dart
git commit -m "feat(nutrition): add meal-slot retag selector to the Edit Macros sheet"
```

---

### Task 6: Consolidate `LogFoodSheet`/`LogToSlotSheet` — retire the per-slot sheet

**Files:**
- Modify: `lib/features/nutrition/widgets/log_food_sheet.dart`
- Modify: `lib/features/nutrition/screens/nutrition_screen.dart:27-28,294-295`
- Delete: `lib/features/nutrition/widgets/log_to_slot_sheet.dart`
- Test: `test/widgets/log_food_sheet_locked_slot_test.dart`

**Interfaces:**
- Consumes: `mealTypeProvider` (existing, `nutrition_provider.dart:1367-1368`).
- Produces: `showLogFoodSheet(BuildContext, {LogFoodMode? initial, String? lockedSlot})` — new optional param later call sites (Task 7 doesn't need it, this is the terminal consumer).

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets/log_food_sheet_locked_slot_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/nutrition/widgets/log_food_sheet.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

void main() {
  testWidgets('lockedSlot sets mealTypeProvider and shows all 5 tabs', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: LogFoodSheet(initial: LogFoodMode.ai, lockedSlot: 'lunch')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(mealTypeProvider), 'lunch');
    expect(find.text('LOG TO LUNCH'), findsOneWidget);
    expect(find.textContaining('CART'), findsOneWidget);
    expect(find.textContaining('BAR'), findsOneWidget);
  });

  testWidgets('no lockedSlot keeps the default LOG FOOD title', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: LogFoodSheet(initial: LogFoodMode.ai)),
        ),
      ),
    );
    expect(find.text('LOG FOOD'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/log_food_sheet_locked_slot_test.dart`
Expected: FAIL — `LogFoodSheet` has no `lockedSlot` constructor parameter.

- [ ] **Step 3: Add `lockedSlot` to `LogFoodSheet`**

In `lib/features/nutrition/widgets/log_food_sheet.dart`, change the top-level function (lines 17-24) from:
```dart
void showLogFoodSheet(BuildContext context, {LogFoodMode? initial}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LogFoodSheet(initial: initial ?? LogFoodMode.ai),
  );
}
```
to:
```dart
void showLogFoodSheet(BuildContext context, {LogFoodMode? initial, String? lockedSlot}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LogFoodSheet(
      initial: initial ?? LogFoodMode.ai,
      lockedSlot: lockedSlot,
    ),
  );
}
```

Add the import: `import '../providers/nutrition_provider.dart' show mealTypeProvider;` and `import '../services/meal_slot_inference.dart' show mealSlotLabel;` near the top with the other imports.

Change the class declaration (lines 34-40) from:
```dart
class LogFoodSheet extends ConsumerStatefulWidget {
  const LogFoodSheet({super.key, required this.initial});
  final LogFoodMode initial;

  @override
  ConsumerState<LogFoodSheet> createState() => _LogFoodSheetState();
}
```
to:
```dart
class LogFoodSheet extends ConsumerStatefulWidget {
  const LogFoodSheet({super.key, required this.initial, this.lockedSlot});
  final LogFoodMode initial;

  /// When set (opened from a specific meal-slot's `+ LOG` CTA), the sheet
  /// locks `mealTypeProvider` to this slot for the sheet's lifetime and
  /// titles itself "LOG TO {SLOT}" instead of the generic "LOG FOOD".
  final String? lockedSlot;

  @override
  ConsumerState<LogFoodSheet> createState() => _LogFoodSheetState();
}
```

Change `_LogFoodSheetState.initState` (lines 48-52) from:
```dart
  @override
  void initState() {
    super.initState();
    _active = widget.initial;
  }
```
to:
```dart
  @override
  void initState() {
    super.initState();
    _active = widget.initial;
    final slot = widget.lockedSlot;
    if (slot != null) {
      // Deferred so Riverpod isn't mutated during build/init — mirrors
      // the retired LogToSlotSheet's identical pattern.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(mealTypeProvider.notifier).select(slot);
      });
    }
  }
```

Change `_buildHeader` (lines 87-119) so the title reflects the lock — change:
```dart
          const Spacer(),
          Text(
            'LOG FOOD',
            style: AppTypography.mono.copyWith(
              color: AppColors.textPrimary,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
```
to:
```dart
          const Spacer(),
          Text(
            widget.lockedSlot == null
                ? 'LOG FOOD'
                : 'LOG TO ${mealSlotLabel(widget.lockedSlot!)}',
            style: AppTypography.mono.copyWith(
              color: AppColors.textPrimary,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/log_food_sheet_locked_slot_test.dart`
Expected: PASS

- [ ] **Step 5: Wire `nutrition_screen.dart`'s per-slot callback to the consolidated sheet**

In `lib/features/nutrition/screens/nutrition_screen.dart`, remove line 28 (`import '../widgets/log_to_slot_sheet.dart';`).

Change lines 294-295 from:
```dart
              onLogSlot: (slot) =>
                  LogToSlotSheet.show(context, slot: slot),
```
to:
```dart
              onLogSlot: (slot) =>
                  showLogFoodSheet(context, lockedSlot: slot),
```

- [ ] **Step 6: Delete the retired sheet**

```bash
git rm lib/features/nutrition/widgets/log_to_slot_sheet.dart
```

- [ ] **Step 7: Run flutter analyze to confirm nothing else references the deleted file**

Run: `flutter analyze lib/`
Expected: No issues — if any other file still imports `log_to_slot_sheet.dart`, update it to use `showLogFoodSheet(..., lockedSlot: ...)` the same way.

- [ ] **Step 8: Run the full nutrition widget test suite**

Run: `flutter test test/widgets/ -t nutrition`
Expected: all PASS (any test that previously referenced `LogToSlotSheet` needs updating to `showLogFoodSheet`/`LogFoodSheet` with `lockedSlot` — find via `grep -rl LogToSlotSheet test/`).

- [ ] **Step 9: Commit**

```bash
git add lib/features/nutrition/widgets/log_food_sheet.dart lib/features/nutrition/screens/nutrition_screen.dart test/widgets/log_food_sheet_locked_slot_test.dart
git commit -m "$(cat <<'EOF'
refactor(nutrition): consolidate LogFoodSheet/LogToSlotSheet into one widget

LogToSlotSheet (3 tabs) and LogFoodSheet (5 tabs) were two independent
implementations that drifted apart 2 days after creation (LogFoodSheet
added Cart/Barcode; LogToSlotSheet was never updated). LogFoodSheet now
takes an optional lockedSlot param that locks mealTypeProvider and
retitles the sheet, giving both entry points parity and one place to
maintain going forward.
EOF
)"
```

---

### Task 7: Fix Search-tab and Barcode-tab meal-slot drift (found while implementing Task 6)

**Context for the implementer:** While consolidating the sheets (Task 6), reading every mode body found that `search_mode_body.dart` and `barcode_scan_sheet.dart` each carry their OWN independent, slightly-different inline copy of the time-of-day meal-slot inference (three total, counting `MealTypeNotifier.build()` itself — `nutrition_provider.dart:1350-1362`), and neither one reads `mealTypeProvider` at all. Without this fix, opening "LOG TO LUNCH" → Search tab (or Barcode tab) would silently log to whatever time-of-day says instead of the slot the user explicitly tapped — a functional regression relative to the retired `LogToSlotSheet`, which routed Search through a slot-aware redirect. This is the same writer/reader-drift bug class this codebase's own CLAUDE.md flags as the default suspect (root CLAUDE.md §4.1) — fixed in this batch, not deferred.

**Files:**
- Modify: `lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart:202-209,271-274,293-325`
- Modify: `lib/features/nutrition/widgets/barcode_scan_sheet.dart:123-134,572-590` (read the surrounding 20 lines of each before editing — the exact line numbers may shift slightly; anchor on the `_mealType` field and `_buildMealTypeSelector` method names, which are stable identifiers)
- Create: `docs/diagnoses/2026-09-20-meal-slot-inference-drift-<id3>.md`
- Test: `test/widgets/log_food_sheet_search_respects_locked_slot_test.dart`

**Interfaces:**
- Consumes: `mealTypeProvider` (existing).
- Produces: nothing new — both files lose their local inference in favor of the shared provider.

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets/log_food_sheet_search_respects_locked_slot_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/nutrition/widgets/log_food_sheet.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
// ... Hive/food-repository test harness (mirror any existing
// food_search_sheet or saved_meals_section widget test's setUp).

void main() {
  testWidgets('Search tab logs to the locked slot, not time-of-day inference', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Force a mealTypeProvider value that DISAGREES with whatever the
    // real wall-clock time would infer, to prove the lock — not the
    // clock — decides the outcome.
    container.read(mealTypeProvider.notifier).select('dinner');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: LogFoodSheet(initial: LogFoodMode.search, lockedSlot: 'dinner')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Type a query, tap the first result, then assert the written Hive
    // row's meal_type is 'dinner' regardless of the current wall-clock
    // time. (Exact drive steps depend on FoodRepository's seeded test
    // data — mirror whatever existing search_mode_body/food-search test
    // seeds a findable food item.)
    await tester.enterText(find.byType(TextField), 'oat');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    final box = HiveService.instance.nutritionBox;
    final written = box.keys
        .whereType<String>()
        .where((k) => k.startsWith('nlog_'))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList();
    expect(written, isNotEmpty);
    expect(written.first['meal_type'], 'dinner');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/log_food_sheet_search_respects_locked_slot_test.dart`
Expected: FAIL when the wall-clock time doesn't happen to also say "dinner" (i.e. most of the time) — `_mealTypeForNow()` wins over the lock.

- [ ] **Step 3: Fix `search_mode_body.dart`**

Delete the local helper (lines 318-324):
```dart
String _mealTypeForNow() {
  final hour = DateTime.now().hour;
  if (hour < 11) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 19) return 'dinner';
  return 'snacks';
}
```

Change the tap handler in `_SearchResultsList` (lines 202-209) from:
```dart
          onTap: () async {
            final qty =
                (item['standard_serving_g'] as num?)?.toDouble() ?? 100.0;
            await ref.read(foodLogProvider.notifier).logFood(
                  food: item,
                  mealType: _mealTypeForNow(),
                  quantityG: qty,
                );
            onLogged();
          },
```
to:
```dart
          onTap: () async {
            final qty =
                (item['standard_serving_g'] as num?)?.toDouble() ?? 100.0;
            await ref.read(foodLogProvider.notifier).logFood(
                  food: item,
                  mealType: ref.read(mealTypeProvider),
                  quantityG: qty,
                );
            onLogged();
          },
```

Change `_relogFromHistory` (lines 293-316) from:
```dart
Future<void> _relogFromHistory(
    WidgetRef ref, Map<String, dynamic> source) async {
  final item = FoodItem(
    name: (source['food_name'] ?? 'Unknown') as String,
    quantityG: (source['quantity_g'] as num?)?.toDouble() ?? 100.0,
    calories: (source['total_calories'] as num?)?.toDouble() ?? 0,
    protein: (source['total_protein'] as num?)?.toDouble() ?? 0,
    carbs: (source['total_carbs'] as num?)?.toDouble() ?? 0,
    fat: (source['total_fat'] as num?)?.toDouble() ?? 0,
    fiber: (source['total_fiber'] as num?)?.toDouble() ?? 0,
  );
  await NutritionWriteService.instance.logMeal(
    date: DateTime.now(),
    mealType: _mealTypeForNow(),
    items: [item],
    source: NutritionWriteSource.manualSearch,
  );
```
to:
```dart
Future<void> _relogFromHistory(
    WidgetRef ref, Map<String, dynamic> source) async {
  final item = FoodItem(
    name: (source['food_name'] ?? 'Unknown') as String,
    quantityG: (source['quantity_g'] as num?)?.toDouble() ?? 100.0,
    calories: (source['total_calories'] as num?)?.toDouble() ?? 0,
    protein: (source['total_protein'] as num?)?.toDouble() ?? 0,
    carbs: (source['total_carbs'] as num?)?.toDouble() ?? 0,
    fat: (source['total_fat'] as num?)?.toDouble() ?? 0,
    fiber: (source['total_fiber'] as num?)?.toDouble() ?? 0,
  );
  await NutritionWriteService.instance.logMeal(
    date: DateTime.now(),
    mealType: ref.read(mealTypeProvider),
    items: [item],
    source: NutritionWriteSource.manualSearch,
  );
```
(`_RecentLogs.build`'s `onTap` at line 271-274 calls `_relogFromHistory(ref, item)` unchanged — the fix is inside `_relogFromHistory` itself.)

Add `import '../../providers/nutrition_provider.dart' show mealTypeProvider;` if `nutrition_provider.dart` isn't already imported with that symbol visible (it's already imported without a `show` clause per line 14 of the original file — no import change needed, just confirm `mealTypeProvider` is exported from that file, which it is).

- [ ] **Step 4: Fix `barcode_scan_sheet.dart`**

Read the full surrounding context first: `grep -n "_mealType\b" lib/features/nutrition/widgets/barcode_scan_sheet.dart` to see every read/write site (there are at least 5: the field declaration, the `initState`-style inference block, the save-call usage, the selector's `isActive` check, and the selector's `onTap`). Replace the local `String _mealType = 'snacks';` field and its inline time-window initializer with reads/writes of `mealTypeProvider`:

- Remove the field declaration and the inference block that sets it in `initState` (or wherever it's set — the exact block found via the grep above).
- Wherever the code currently reads `_mealType` (the save call, the selector's active-check), replace with `ref.watch(mealTypeProvider)` (in `build`) or `ref.read(mealTypeProvider)` (inside a callback).
- Wherever the code currently does `setState(() => _mealType = types[i])`, replace with `ref.read(mealTypeProvider.notifier).select(types[i])` — this widget must become (or already be, if it's a `ConsumerStatefulWidget`/`ConsumerWidget`) Riverpod-aware; check its class declaration and convert `StatefulWidget`/`State` to `ConsumerStatefulWidget`/`ConsumerState` if it isn't already (the file already has `ref` available somewhere if any sibling `ScanMealSection`-style pattern is followed — confirm via `grep -n "extends State\|extends ConsumerState\|final WidgetRef ref" lib/features/nutrition/widgets/barcode_scan_sheet.dart` before editing).

This mirrors `scan_meal_section.dart`'s already-correct pattern at lines 417 (`ref.read(mealTypeProvider)` at save time) and 475/494 (`ref.watch(mealTypeProvider)` + `.select()` for the in-sheet pill selector) — copy that file's exact shape for consistency rather than inventing a new one.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/widgets/log_food_sheet_search_respects_locked_slot_test.dart`
Expected: PASS, deterministically (no longer depends on wall-clock time).

- [ ] **Step 6: Run the full nutrition widget/contract suite**

Run: `flutter test test/widgets/ test/contracts/ -t nutrition`
Expected: all PASS.

- [ ] **Step 7: Write the diagnose-doc**

This is a genuine bug fix (three independently-drifted, disagreeing meal-slot-inference implementations, none of them respecting an explicit lock), so it needs a diagnose-doc per root CLAUDE.md §4.4 rule 22 — the commit message below is `fix(...)`-prefixed, which the pre-commit hook requires a `closes-diagnose:` trailer for.

Create `docs/diagnoses/2026-09-20-meal-slot-inference-drift-<id3>.md` following this repo's diagnose-doc template (run `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-09-20-meal-slot-inference-drift-<id3>.md` after writing to confirm it validates). Content must name: symptom (opening "LOG TO LUNCH" and logging via Search or Barcode could land in a different slot than the one tapped), the three writers found (`nutrition_provider.dart:1350-1362` `MealTypeNotifier.build()`, `search_mode_body.dart:318-324` `_mealTypeForNow()` pre-fix, `barcode_scan_sheet.dart`'s local `_mealType` inference pre-fix), the fix (both now defer to `mealTypeProvider`), and the test path above. Note this was found while implementing Task 6 (sheet consolidation), not from a founder-reported observation.

- [ ] **Step 8: Commit**

```bash
git add lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart lib/features/nutrition/widgets/barcode_scan_sheet.dart test/widgets/log_food_sheet_search_respects_locked_slot_test.dart docs/diagnoses/2026-09-20-meal-slot-inference-drift-*.md
git commit -m "$(cat <<'EOF'
fix(nutrition): Search and Barcode log tabs now respect mealTypeProvider

Both carried their own independent inline time-of-day meal-slot
inference, disagreeing with each other and with mealTypeProvider at the
boundaries, and neither honored an explicit slot lock — found while
consolidating LogFoodSheet/LogToSlotSheet (obs 5), where it would have
made "LOG TO LUNCH" -> Search silently log to the wrong slot.

closes-diagnose: <id3>
EOF
)"
```

---

### Task 8: Parallelize Hive user-scoped box open (cold-start perf)

**Files:**
- Modify: `lib/core/services/hive_user_session.dart:177-190`
- Test: `test/contracts/hive_user_session_box_open_parallel_test.dart`

**Interfaces:**
- Consumes: `userScopedBoxRoots` (existing), `namespacedBoxName` (existing).
- Produces: nothing new — same method, faster.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/hive_user_session_box_open_parallel_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
// ... standard Hive test-harness imports.

void main() {
  test('user-scoped boxes open concurrently, not sequentially', () async {
    // (Harness note: this asserts wall-clock behavior, which is inherently
    // approximate. Use a generous margin — e.g. assert total time is well
    // under N × single-box-open-time rather than a tight bound.)
    final stopwatch = Stopwatch()..start();
    await HiveUserSession.instance.openForUser('test-user-parallel');
    stopwatch.stop();
    // With 7 boxes opening in parallel on a fast test-disk temp dir, this
    // should complete in roughly the time of ONE box open, not seven.
    // A regression to the sequential form would show as this test's
    // wall-clock time scaling with box COUNT if boxes were made
    // artificially slow to open (out of scope to fake here) — so this
    // test's primary value is the source-shape assertion below, backed
    // by this timing assertion as a secondary signal.
    expect(stopwatch.elapsedMilliseconds, lessThan(2000));
  });

  test('openForUser source uses Future.wait for the box-open loop', () {
    final src = File('lib/core/services/hive_user_session.dart').readAsStringSync();
    final loopSection = src.substring(
      src.indexOf('for (final root in userScopedBoxRoots)'),
      src.indexOf('_currentOwnerHash = hash;'),
    );
    expect(loopSection, contains('Future.wait'),
        reason: 'obs 4 — the 7 user-scoped boxes must open in parallel, mirroring hive_service.dart:77-82');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/contracts/hive_user_session_box_open_parallel_test.dart`
Expected: FAIL on the source-shape assertion (`contains('Future.wait')`).

- [ ] **Step 3: Parallelize the loop**

In `lib/core/services/hive_user_session.dart`, change (lines 177-190):
```dart
    final hash = userId.replaceAll('-', '').substring(0, 8);
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, userId);
      try {
        await Hive.openBox(boxName);
      } catch (e, st) {
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[HiveUserSession] failed to open $boxName: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'hive_user_session_open_box_corrupt'));
        await Hive.deleteBoxFromDisk(boxName);
        await Hive.openBox(boxName);
      }
    }
```
to:
```dart
    final hash = userId.replaceAll('-', '').substring(0, 8);
    // Obs 4 (cold-start perf): open all 7 user-scoped boxes in parallel,
    // mirroring the shared-box pattern already used in hive_service.dart
    // :77-82. No box here has a documented open-order dependency on
    // another — each box's adapter registration is independent.
    Future<void> openOne(String root) async {
      final boxName = namespacedBoxName(root, userId);
      try {
        await Hive.openBox(boxName);
      } catch (e, st) {
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[HiveUserSession] failed to open $boxName: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'hive_user_session_open_box_corrupt'));
        await Hive.deleteBoxFromDisk(boxName);
        await Hive.openBox(boxName);
      }
    }
    await Future.wait(userScopedBoxRoots.map(openOne));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/contracts/hive_user_session_box_open_parallel_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full auth/session contract suite**

Run: `flutter test test/contracts/auth_hive_owner_agreement_behavioral_test.dart test/sync/restore_completeness_test.dart`
Expected: all PASS — this confirms the cross-account guard and restore sequencing still hold with parallel box opens.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/hive_user_session.dart test/contracts/hive_user_session_box_open_parallel_test.dart
git commit -m "perf(auth): open user-scoped Hive boxes in parallel, cutting cold-start time"
```

---

### Task 9: `gemini.ts` — capture the real failure reason instead of discarding it

**Files:**
- Modify: `supabase/functions/_shared/gemini.ts:80-87` (`GeminiResult` interface), `:96-178` (`geminiChat`), `:181-311` (`_callOnce`)
- Test: `supabase/functions/_shared/gemini_test.ts` (Deno — check whether this file already exists via `ls supabase/functions/_shared/gemini_test.ts`; create it if not, extend it if so)

**Interfaces:**
- Consumes: nothing new.
- Produces: `GeminiResult.lastError?: { status: number | null; message: string } | null` — Task 10 consumes this field at the three `ai-proxy` call sites.

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/_shared/gemini_test.ts (add to existing file, or create)
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { geminiChat, MODEL_FLASH } from "./gemini.ts";

Deno.test("geminiChat surfaces lastError when all attempts fail", async () => {
  // GEMINI_API_KEY is read at module load — if unset in the test env this
  // exercises the !GEMINI_API_KEY branch directly, which is the cheapest
  // deterministic way to hit total failure without a real network call.
  const originalKey = Deno.env.get("GEMINI_API_KEY");
  Deno.env.delete("GEMINI_API_KEY");
  try {
    // Dynamic re-import isn't available for a module-scope const, so this
    // test instead asserts the SHAPE via a fresh process-level check:
    // if GEMINI_API_KEY is already unset when this test file's gemini.ts
    // import evaluated, the module-scope check already fired. Prefer
    // asserting behavior through a real (or mocked-fetch) _callOnce path
    // if this repo's existing Deno tests already inject a fetch stub for
    // gemini.ts — check `grep -rn "globalThis.fetch =" supabase/functions/_shared/gemini_test.ts`
    // first and follow that existing seam rather than deleting the env var,
    // which cannot be un-done mid-process for a module-scope const.
    const result = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "test",
      userPrompt: "test",
      maxTokens: 10,
    });
    assertEquals(result.content, null);
    assertEquals(result.lastError !== undefined, true);
  } finally {
    if (originalKey) Deno.env.set("GEMINI_API_KEY", originalKey);
  }
});
```

(**Implementer note:** `GEMINI_API_KEY` is read into a module-scope `const` at `gemini.ts:34`, so deleting the env var after the module has already loaded has no effect — check this repo's existing `gemini_test.ts` for whichever fetch-mocking seam it already uses to force a failure deterministically, and use THAT pattern instead of the env-var approach sketched above if one exists. If no such file/seam exists yet, the simplest deterministic failure to test is a `globalThis.fetch` stub returning `{ok: false, status: 429, text: async () => "quota exceeded"}` — mock `fetch` before calling `geminiChat` and restore it in a `finally`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini_test.ts`
Expected: FAIL — `result.lastError` is `undefined` today (property doesn't exist on the returned object at all, but TS doesn't error on reading an absent optional property, so the assertion `!== undefined` is `false` and fails as expected).

- [ ] **Step 3: Extend `GeminiResult` and thread `lastError` through**

In `supabase/functions/_shared/gemini.ts`, change the interface (lines 80-87) from:
```typescript
export interface GeminiResult {
  /** Trimmed text content. null if every attempt failed. */
  content: string | null;
  /** The model slug that produced `content`. null on total failure. */
  modelUsed: string | null;
  /** Approximate token usage — totalTokenCount from Gemini's usageMetadata. */
  tokensUsed: number;
}
```
to:
```typescript
export interface GeminiResult {
  /** Trimmed text content. null if every attempt failed. */
  content: string | null;
  /** The model slug that produced `content`. null on total failure. */
  modelUsed: string | null;
  /** Approximate token usage — totalTokenCount from Gemini's usageMetadata. */
  tokensUsed: number;
  /**
   * Present only when content is null: the LAST attempt's raw failure,
   * for server-side classification/alerting (obs 6, 2026-09-20). Never
   * surfaced to the client — callers pass this to reportGeminiExhaustion,
   * never into an HTTP response body.
   */
  lastError?: { status: number | null; message: string } | null;
}
```

In `_callOnce`, add `lastError` to every failure return. Change the `!response.ok` branch (lines 260-270) from:
```typescript
    if (!response.ok) {
      const status = response.status;
      let preview = "";
      try {
        preview = (await response.text()).slice(0, 200);
      } catch (_) { /* body read may also fail */ }
      console.warn(
        `[geminiChat] ${opts.model} HTTP ${status}: ${preview}`,
      );
      return { content: null, modelUsed: null, tokensUsed: 0 };
    }
```
to:
```typescript
    if (!response.ok) {
      const status = response.status;
      let preview = "";
      try {
        preview = (await response.text()).slice(0, 200);
      } catch (_) { /* body read may also fail */ }
      console.warn(
        `[geminiChat] ${opts.model} HTTP ${status}: ${preview}`,
      );
      return {
        content: null,
        modelUsed: null,
        tokensUsed: 0,
        lastError: { status, message: preview || `HTTP ${status}` },
      };
    }
```

Change the no-candidate branch (lines 276-281) from:
```typescript
    if (!candidate || !candidate.content?.parts) {
      console.warn(
        `[geminiChat] ${opts.model} no candidate (finishReason=${candidate?.finishReason ?? "unknown"})`,
      );
      return { content: null, modelUsed: null, tokensUsed: 0 };
    }
```
to:
```typescript
    if (!candidate || !candidate.content?.parts) {
      const finishReason = candidate?.finishReason ?? "unknown";
      console.warn(
        `[geminiChat] ${opts.model} no candidate (finishReason=${finishReason})`,
      );
      return {
        content: null,
        modelUsed: null,
        tokensUsed: 0,
        lastError: { status: null, message: `no candidate (finishReason=${finishReason})` },
      };
    }
```

Change the empty-text branch (lines 289-291) from:
```typescript
    if (!text) {
      return { content: null, modelUsed: null, tokensUsed: 0 };
    }
```
to:
```typescript
    if (!text) {
      return {
        content: null,
        modelUsed: null,
        tokensUsed: 0,
        lastError: { status: null, message: "empty text in candidate" },
      };
    }
```

Change the catch block (lines 300-310) from:
```typescript
  } catch (err) {
    clearTimeout(timer);
    if (err instanceof DOMException && err.name === "AbortError") {
      console.warn(
        `[geminiChat] ${opts.model} timed out (${opts.timeoutMs}ms)`,
      );
    } else {
      console.warn(`[geminiChat] ${opts.model} threw: ${err}`);
    }
    return { content: null, modelUsed: null, tokensUsed: 0 };
  }
```
to:
```typescript
  } catch (err) {
    clearTimeout(timer);
    let message: string;
    if (err instanceof DOMException && err.name === "AbortError") {
      message = `timed out after ${opts.timeoutMs}ms`;
      console.warn(`[geminiChat] ${opts.model} ${message}`);
    } else {
      message = `threw: ${String(err).slice(0, 200)}`;
      console.warn(`[geminiChat] ${opts.model} ${message}`);
    }
    return {
      content: null,
      modelUsed: null,
      tokensUsed: 0,
      lastError: { status: null, message },
    };
  }
```

In `geminiChat`, capture the last failure across the attempt loop and surface it at total exhaustion. Change the `!GEMINI_API_KEY` guard (lines 111-114) from:
```typescript
  if (!GEMINI_API_KEY) {
    console.error("[geminiChat] GEMINI_API_KEY not configured");
    return { content: null, modelUsed: null, tokensUsed: 0 };
  }
```
to:
```typescript
  if (!GEMINI_API_KEY) {
    console.error("[geminiChat] GEMINI_API_KEY not configured");
    return {
      content: null,
      modelUsed: null,
      tokensUsed: 0,
      lastError: { status: null, message: "GEMINI_API_KEY not configured" },
    };
  }
```

Change the attempt loop to track the last result. Immediately before the `for (let pass = 0; pass <= retries; pass++) {` line (line 134), add:
```typescript
  let lastFailure: GeminiResult | null = null;
```

Inside the inner loop, after `const result = await _callOnce({...});` (ends around line 146) and its `if (result.content !== null) { ... return result; }` block, capture the failure — change:
```typescript
      if (result.content !== null) {
        // Success on the first attempt is the common path; log the
        // fallback / retry case so we can monitor Flash quota health in prod.
        if (attemptModel !== model || pass > 0) {
          console.warn(
            `[geminiChat] recovered (${model} → ${attemptModel}, pass ${pass})`,
          );
        }
        return result;
      }
      console.warn(
        `[geminiChat] ${attemptModel} returned null — ${attempts.indexOf(attemptModel) < attempts.length - 1 ? "trying fallback" : "attempt list exhausted"}`,
      );
```
to:
```typescript
      if (result.content !== null) {
        // Success on the first attempt is the common path; log the
        // fallback / retry case so we can monitor Flash quota health in prod.
        if (attemptModel !== model || pass > 0) {
          console.warn(
            `[geminiChat] recovered (${model} → ${attemptModel}, pass ${pass})`,
          );
        }
        return result;
      }
      lastFailure = result;
      console.warn(
        `[geminiChat] ${attemptModel} returned null — ${attempts.indexOf(attemptModel) < attempts.length - 1 ? "trying fallback" : "attempt list exhausted"}`,
      );
```

Finally, change the exhausted-return (line 177) from:
```typescript
  console.error(
    `[geminiChat] All attempts failed for primary=${model} (retries=${retries})`,
  );
  return { content: null, modelUsed: null, tokensUsed: 0 };
```
to:
```typescript
  console.error(
    `[geminiChat] All attempts failed for primary=${model} (retries=${retries})`,
  );
  return { content: null, modelUsed: null, tokensUsed: 0, lastError: lastFailure?.lastError ?? null };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini_test.ts`
Expected: PASS

- [ ] **Step 5: `deno check`**

Run: `deno check --node-modules-dir=none supabase/functions/_shared/gemini.ts`
Expected: no type errors.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/_shared/gemini.ts supabase/functions/_shared/gemini_test.ts
git commit -m "feat(ai-proxy): surface Gemini's real failure reason via GeminiResult.lastError"
```

---

### Task 10: `ai-proxy` — classify and alert on total Gemini exhaustion

**Files:**
- Create: `supabase/functions/_shared/gemini_failure_alert.ts`
- Create: `supabase/functions/_shared/gemini_failure_alert_test.ts`
- Modify: `supabase/functions/ai-proxy/index.ts:391,435-442` (food_text_analysis)
- Modify: `supabase/functions/ai-proxy/index.ts:586,599-601` (scan_meal)
- Modify: `supabase/functions/ai-proxy/index.ts:628,641-643` (cart_auditor)
- Test: `docs/audit/gate_test_ledger.yaml` — NOT touched (this is not a new `check_*.dart` gate, no ledger entry needed)

**Interfaces:**
- Consumes: `GeminiResult.lastError` (Task 9), the existing service-role `supabaseClient` already constructed at `ai-proxy/index.ts:247`.
- Produces: `reportGeminiExhaustion(client: SupabaseClient, source: string, lastError: {status: number|null; message: string} | null): Promise<void>` — never throws.

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/_shared/gemini_failure_alert_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { reportGeminiExhaustion } from "./gemini_failure_alert.ts";

function fakeClient(overrides: {
  selectResult?: { data: unknown[] | null; error: unknown };
  insertError?: unknown;
}) {
  const inserted: Record<string, unknown>[] = [];
  return {
    inserted,
    from(_table: string) {
      return {
        select: (_cols: string) => ({
          eq: (_a: string, _b: string) => ({
            eq: (_c: string, _d: string) => ({
              is: (_e: string, _f: null) => ({
                gte: (_g: string, _h: string) => ({
                  limit: (_n: number) =>
                    Promise.resolve(overrides.selectResult ?? { data: [], error: null }),
                }),
              }),
            }),
          }),
        }),
        insert: (row: Record<string, unknown>) => {
          inserted.push(row);
          return Promise.resolve({ error: overrides.insertError ?? null });
        },
      };
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

Deno.test("reportGeminiExhaustion classifies 429 as quota/billing", async () => {
  const client = fakeClient({ selectResult: { data: [], error: null } });
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 429, message: "quota exceeded" });
  assertEquals(client.inserted.length, 1);
  assertEquals(client.inserted[0].severity, "critical");
  assertEquals(
    (client.inserted[0].suggested_action as string).includes("quota"),
    true,
  );
});

Deno.test("reportGeminiExhaustion classifies 401/403 as key/secret issue", async () => {
  const client = fakeClient({ selectResult: { data: [], error: null } });
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 403, message: "forbidden" });
  assertEquals(
    (client.inserted[0].suggested_action as string).includes("GEMINI_API_KEY"),
    true,
  );
});

Deno.test("reportGeminiExhaustion downgrades to warn inside the dedup window", async () => {
  const client = fakeClient({ selectResult: { data: [{ id: 1 }], error: null } });
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 429, message: "quota exceeded" });
  assertEquals(client.inserted[0].severity, "warn");
});

Deno.test("reportGeminiExhaustion never throws when insert fails", async () => {
  const client = fakeClient({ selectResult: { data: [], error: null }, insertError: new Error("boom") });
  // Must not throw.
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 500, message: "server error" });
});

Deno.test("reportGeminiExhaustion never throws when the dedup select errors", async () => {
  const client = fakeClient({ selectResult: { data: null, error: new Error("boom") } });
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 500, message: "server error" });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini_failure_alert_test.ts`
Expected: FAIL — the module doesn't exist yet (import error).

- [ ] **Step 3: Implement `gemini_failure_alert.ts`**

```typescript
// supabase/functions/_shared/gemini_failure_alert.ts
/**
 * Reports a TERMINAL Gemini failure (every model in ai-proxy's attempt list
 * exhausted) into the existing `public.alerts` table, reusing the
 * `trg_dispatch_critical_alert_notify` trigger (migration 133) that already
 * pushes a `severity='critical'` insert to the founder's Telegram — no new
 * Telegram wiring. Client-facing error text is unchanged; this is
 * additive, admin-only visibility (obs 6, 2026-09-20 brainstorm).
 *
 * Never throws — a failure here must never break the caller's actual
 * error response to the client.
 */

// deno-lint-ignore no-explicit-any
type SupabaseLike = any;

const DEDUP_WINDOW_MINUTES = 30;

function classify(status: number | null): string {
  if (status === 429) {
    return "Check Gemini quota/billing on the Google Cloud project owning GEMINI_API_KEY — a recharge doesn't always attach to the right project or raise RPM limits.";
  }
  if (status === 401 || status === 403) {
    return "Check the GEMINI_API_KEY secret is valid.";
  }
  if (status !== null && status >= 500) {
    return "Likely a transient Gemini-side outage — no action needed unless it persists.";
  }
  return "Unclassified Gemini failure — check function_logs for the full response.";
}

export async function reportGeminiExhaustion(
  client: SupabaseLike,
  source: string,
  lastError: { status: number | null; message: string } | null,
): Promise<void> {
  try {
    const status = lastError?.status ?? null;
    const message = lastError?.message ?? "unknown failure (no lastError captured)";
    const suggestedAction = classify(status);
    const summary = `${source}: Gemini exhausted all attempts — ${
      status !== null ? `HTTP ${status}` : "no HTTP status"
    }: ${message}`.slice(0, 500);

    const dedupWindowStart = new Date(
      Date.now() - DEDUP_WINDOW_MINUTES * 60 * 1000,
    ).toISOString();
    const { data: recent, error: recentErr } = await client
      .from("alerts")
      .select("id")
      .eq("source", source)
      .eq("severity", "critical")
      .is("resolved_at", null)
      .gte("detected_at", dedupWindowStart)
      .limit(1);
    if (recentErr) {
      console.error(`[gemini_failure_alert] dedup check failed for ${source}:`, recentErr);
    }
    const severity = !recentErr && recent && recent.length > 0 ? "warn" : "critical";

    const { error: insertErr } = await client.from("alerts").insert({
      source,
      severity,
      summary,
      context_json: { status, message },
      suggested_action: suggestedAction,
    });
    if (insertErr) {
      console.error(`[gemini_failure_alert] alerts insert failed for ${source}:`, insertErr);
    }
  } catch (err) {
    console.error(`[gemini_failure_alert] threw for ${source}:`, err);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini_failure_alert_test.ts`
Expected: PASS

- [ ] **Step 5: Wire into the three `ai-proxy` call sites**

In `supabase/functions/ai-proxy/index.ts`, add the import near the other `_shared` imports:
```typescript
import { reportGeminiExhaustion } from "../_shared/gemini_failure_alert.ts";
```

Change the food_text_analysis destructure (line 391) from:
```typescript
      const { content, modelUsed, tokensUsed } = await geminiChat({
```
to:
```typescript
      const { content, modelUsed, tokensUsed, lastError } = await geminiChat({
```
and its `!content` branch (lines 435-442) from:
```typescript
      if (!content) {
        // Gemini failed — close the placeholder so it doesn't orphan.
        await resolvePlaceholder(
          "failed_gemini",
          JSON.stringify({ error: "Gemini returned no content" }),
          0,
        );
        return err(502, "Food analysis failed");
      }
```
to:
```typescript
      if (!content) {
        // Gemini failed — close the placeholder so it doesn't orphan.
        await resolvePlaceholder(
          "failed_gemini",
          JSON.stringify({ error: "Gemini returned no content" }),
          0,
        );
        await reportGeminiExhaustion(supabaseClient, "ai_proxy_gemini_exhausted", lastError ?? null);
        return err(502, "Food analysis failed");
      }
```

Change the scan_meal destructure (line 586) from `const { content, tokensUsed } = await geminiChat({` to `const { content, tokensUsed, lastError } = await geminiChat({`, and its `!content` branch (lines 599-601) from:
```typescript
      if (!content) {
        await resolveVisionPlaceholder("failed_gemini", JSON.stringify({ error: "Gemini returned no content" }), 0);
        return err(502, "Image analysis failed");
      }
```
to:
```typescript
      if (!content) {
        await resolveVisionPlaceholder("failed_gemini", JSON.stringify({ error: "Gemini returned no content" }), 0);
        await reportGeminiExhaustion(supabaseClient, "ai_proxy_gemini_exhausted", lastError ?? null);
        return err(502, "Image analysis failed");
      }
```

Change the cart_auditor destructure (line 628) from `const { content, tokensUsed } = await geminiChat({` to `const { content, tokensUsed, lastError } = await geminiChat({`, and its `!content` branch (lines 641-643) from:
```typescript
      if (!content) {
        await resolveVisionPlaceholder("failed_gemini", JSON.stringify({ error: "Gemini returned no content" }), 0);
        return err(502, "Cart analysis failed");
      }
```
to:
```typescript
      if (!content) {
        await resolveVisionPlaceholder("failed_gemini", JSON.stringify({ error: "Gemini returned no content" }), 0);
        await reportGeminiExhaustion(supabaseClient, "ai_proxy_gemini_exhausted", lastError ?? null);
        return err(502, "Cart analysis failed");
      }
```

- [ ] **Step 6: `deno check`**

Run: `deno check --node-modules-dir=none supabase/functions/ai-proxy/index.ts`
Expected: no type errors — confirms `lastError` is a valid destructure key on every `geminiChat` return site now that Task 9 landed.

- [ ] **Step 7: Run the full Deno test suite for this function**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/ai-proxy/`
Expected: all PASS (existing `ai-proxy/index_test.ts` tests must still pass unchanged — this is purely additive).

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/_shared/gemini_failure_alert.ts supabase/functions/_shared/gemini_failure_alert_test.ts supabase/functions/ai-proxy/index.ts
git commit -m "$(cat <<'EOF'
feat(ai-proxy): alert founder's Telegram on terminal Gemini failures

Reuses the existing alerts table + trg_dispatch_critical_alert_notify
trigger (migration 133) -- no new Telegram wiring. Classifies the real
Gemini status (429 quota/billing, 401/403 key issue, 5xx outage) into a
suggested_action, with a 30-minute same-source dedup so a quota storm
downgrades to severity=warn after the first ping instead of spamming.
Client-facing error text is unchanged (founder decision).
EOF
)"
```

- [ ] **Step 9: STOP — do not deploy**

This task's Edge Function changes are committed but NOT deployed. A live deploy of `ai-proxy` requires separate, explicit founder authorization per root CLAUDE.md §4.3 (live-apply needs its own explicit go, even though this plan was approved) — surface this to the founder as its own request when the batch is otherwise ready to ship, using the `/edge-function-deploy-rollback` skill's emit-payload → byte-identical-deploy → smoke flow.

---

## End-of-batch checklist (before `--no-ff` merge)

This batch's blast-radius is `account` (Tasks 9-10 touch `ai-proxy`), so per root CLAUDE.md §4.3/§4.12:

1. Self-trigger `/code-review` (B-pass) on the full diff before merge.
2. This plan constitutes round 1 of the required ×2 plan review (it was reviewed via the brainstorming skill's spec self-review) — run round 2 as a context-blind pass over the implemented diff before merge, per §4.12.
3. Walk the §5 per-batch maintenance checklist (diagnose-docs present for Tasks 1-2, SoT registry entry present for Task 4, no migration to record in `backups/applied_migrations.json` since no schema change was made, project retrospective memory file).
4. Merge `--no-ff` to `main` only after the above.
5. Founder-authorized live deploy of `ai-proxy` (Task 10, Step 9) is a separate action after merge.
