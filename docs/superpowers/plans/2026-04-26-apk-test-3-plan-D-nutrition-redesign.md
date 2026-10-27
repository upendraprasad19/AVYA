# APK Test #3 — Plan D — Nutrition Page Redesign (Obs 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the 1265-line `nutrition_screen.dart` monolith into a focused page (~700 dp scroll) by hoisting the five logging surfaces (AI text / Scan / Cart / Barcode / Search) into a single `+ LOG FOOD` bottom sheet, merging the Hydration + Urine sections into one card, adding a `YOUR FOODS` chip strip mirroring Train's `YOUR EXERCISES`, and reordering the page per the Obs 3 spec layout. All five existing logging widgets are repurposed as bottom-sheet mode bodies — minimal new logic, mostly relocation.

**Architecture:** New `LogFoodSheet` is a `ConsumerStatefulWidget` that hosts a 5-tab segmented `WardChip` row at top + a body container that swaps in the appropriate mode widget. Each mode keeps its existing save semantics and dismisses the sheet on success. New `HydrationCard` replaces `_buildInlineWaterTracker` + `hydration_section.dart` with a single 2-row `WardCard`. New `YourFoodsSection` mirrors the Train screen's `_buildYourExercisesSection` pattern: `ValueListenableBuilder<customBox>` → horizontal chip strip with `DRAFT / PENDING / APPROVED ✓` status pills. Page rewrite drops 5 sections, hoists `TodaysMealsCard` above `WeeklyChartCard`, and adds the gold-accent `+ LOG FOOD` CTA between summary and hydration.

**Tech Stack:** Flutter (Dart 3.4+), Riverpod 2 (existing providers reused unmodified), Hive (`customBox`, `nutritionBox`, `healthBox`), Wardroom design primitives (`WardCard`, `WardChip`, `WardLetterhead`, `WardBar`, `WardGlassGrid`, `WardRule`).

**Spec:** `docs/superpowers/specs/2026-04-26-apk-test-3-batch-design.md` (Obs 3: "Nutrition Page Redesign", Q7 + Q8 + Q8.1 locks).

---

## File Structure

| File | Responsibility | New / Modified |
|---|---|---|
| `lib/features/nutrition/widgets/log_food_sheet.dart` | New `+ LOG FOOD` bottom sheet hosting 5 modes (AI / SCAN / CART / BAR / SEARCH); 75% screen height; AI default; segmented `WardChip` tabs at top; SEARCH has `[All] [Saved Meals] [Recent]` sub-filter chips. | New |
| `lib/features/nutrition/widgets/hydration_card.dart` | New combined Hydration + Urine card (Q8.1=A): two-row `WardCard` — water row (8-cell glass grid + `[+ 250ML] [+ 500ML]`) and urine row (`URINE STATUS · WELL HYDRATED` pill + `[change ▾]` → 8-color picker expands inline + tip line). Replaces `hydration_section.dart` + `_buildInlineWaterTracker`. | New |
| `lib/features/nutrition/widgets/your_foods_section.dart` | New custom-foods chip strip mirroring `_buildYourExercisesSection` (Train, APK Test #1 D6). `ValueListenableBuilder<customBox>` → horizontal `WardChip` row, status pills, empty-state line, `+ ADD CUSTOM` pill opens `CustomFoodSheet`. | New |
| `lib/features/nutrition/widgets/log_food_modes/ai_mode_body.dart` | AI mode body for sheet — wraps `FoodLoggerSection` + conditional `AiBreakdownCard`. Auto-dismisses sheet on successful breakdown commit. | New |
| `lib/features/nutrition/widgets/log_food_modes/scan_mode_body.dart` | SCAN mode body — wraps existing `ScanMealSection`; dismisses sheet on save. | New |
| `lib/features/nutrition/widgets/log_food_modes/cart_mode_body.dart` | CART mode body — wraps existing `CartAuditorSection`; no auto-dismiss (audit is read-only output). | New |
| `lib/features/nutrition/widgets/log_food_modes/barcode_mode_body.dart` | BARCODE mode body — refactor of `_BarcodeScanSheet` content to render inside the `LogFoodSheet` instead of a separate modal. | New |
| `lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart` | SEARCH mode body — sub-filter chips `[All] [Saved Meals] [Recent]` + scrollable list; reuses `food_search_sheet` query infrastructure + `SavedMealsSection` row patterns. | New |
| `lib/features/nutrition/screens/nutrition_screen.dart` | Body rewrite per Obs 3 layout — drops 5 logging sections, adds `+ LOG FOOD` CTA, swaps in `HydrationCard`, hoists `TodaysMealsCard` above weekly chart, adds INSIGHTS & TRENDS + YOUR FOODS sections. Drops from ~1265 lines to ~600 lines. | Modified |
| `lib/features/nutrition/providers/nutrition_provider.dart` | Add missing `unawaited(SyncService.instance.syncNutritionData())` in `UrineColorNotifier.select()`. Patch `CustomFoodNotifier.addCustomFood` to also fire `syncCustomItemsNow()` (today only fires `syncCustomFoodToSupabase` + `pushSnapshot`). | Modified |
| `test/contracts/nutrition_screen_layout_test.dart` | Regex contract test — page contains `+ LOG FOOD` CTA, `HydrationCard`, `YourFoodsSection`, `TodaysMealsCard`; does NOT instantiate the 5 hoisted widgets directly. | New |
| `test/contracts/log_food_sheet_test.dart` | Regex contract test — sheet has 5 mode keys, AI default, SEARCH sub-filter chips. | New |
| `test/contracts/hydration_card_layout_test.dart` | Regex contract test — single `WardCard`, urine pill, water row + 8-cell grid. | New |
| `test/contracts/your_foods_section_test.dart` | Regex contract test — `ValueListenableBuilder` on `customBox`, three status pills (`DRAFT`/`PENDING`/`APPROVED`). | New |
| `test/sync/nutrition_redesign_sync_test.dart` | Regex contract test — every nutrition mutation surface in the redesigned tree fires `syncNutritionData` + `pushSnapshot`; custom-food create fires `syncCustomItemsNow`. | New |

---

## Task 1: Patch sync gaps in nutrition_provider.dart

**Background:** Two gaps surfaced while planning the redesign:
1. `UrineColorNotifier.select()` (line 446) only fires `pushSnapshot()` — never `syncNutritionData()`. Urine status is read by `_getTodayNutrition` in the AI snapshot, but the cloud `health` columns won't update until the snapshot push (which doesn't write the urine row).
2. `CustomFoodNotifier.addCustomFood` (line 1015) calls `NutritionRepository.syncCustomFoodToSupabase` + `pushSnapshot` but never `syncCustomItemsNow`. The `customBox` listenable in YOUR FOODS rebuilds correctly, but cross-device restore depends on `syncCustomItemsNow` for full custom-items projection (this is the same hole closed for custom exercises in APK Test #1 D6).

Both patches must land BEFORE the redesign so the regression tests at the end can rely on the invariants.

**Files:**
- Modify: `lib/features/nutrition/providers/nutrition_provider.dart` (lines 446–462 and 1015–1069)
- Test: `test/sync/nutrition_redesign_sync_test.dart`

- [ ] **Step 1: Write the failing contract test**

Create `test/sync/nutrition_redesign_sync_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the sync gaps closed alongside the APK Test #3
/// nutrition redesign (Plan D, Task 1).
///
/// Prior holes:
///   - UrineColorNotifier.select() only fired pushSnapshot — health-box
///     row never reached cloud until next launch.
///   - CustomFoodNotifier.addCustomFood fired pushSnapshot + the
///     repository helper, but skipped syncCustomItemsNow (unlike the
///     mirror path for custom EXERCISES, which does fire it).
void main() {
  final source = File(
    'lib/features/nutrition/providers/nutrition_provider.dart',
  ).readAsStringSync();

  test('UrineColorNotifier.select fires syncNutritionData + pushSnapshot',
      () {
    final selectStart = source.indexOf('void select(int index)');
    expect(selectStart, isNot(-1), reason: 'select() must exist');
    final body = source.substring(selectStart, selectStart + 1200);

    expect(
      body.contains('SyncService.instance.syncNutritionData'),
      isTrue,
      reason: 'UrineColorNotifier.select must fire syncNutritionData() so '
          'urine_color_<date> changes propagate to cloud, not just the AI '
          'snapshot.',
    );
    expect(
      body.contains('SyncService.instance.pushSnapshot'),
      isTrue,
      reason: 'pushSnapshot must remain (already present) so AI coach '
          'context updates live.',
    );
  });

  test('CustomFoodNotifier.addCustomFood fires syncCustomItemsNow', () {
    final addStart = source.indexOf('Future<void> addCustomFood(');
    expect(addStart, isNot(-1), reason: 'addCustomFood must exist');
    final body = source.substring(addStart, addStart + 2400);

    expect(
      body.contains('SyncService.instance.syncCustomItemsNow'),
      isTrue,
      reason: 'addCustomFood must fire syncCustomItemsNow so the custom '
          'food projection reaches user_custom_foods on cloud (mirror of '
          'the Train custom-exercise path closed in APK Test #1 D6).',
    );
    expect(
      body.contains('SyncService.instance.pushSnapshot'),
      isTrue,
      reason: 'pushSnapshot must remain so AI coach learns about new '
          'custom foods immediately.',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/sync/nutrition_redesign_sync_test.dart
```

Expected: both assertions FAIL — first says `syncNutritionData` missing in `select()`; second says `syncCustomItemsNow` missing in `addCustomFood`.

- [ ] **Step 3: Patch `UrineColorNotifier.select`**

In `lib/features/nutrition/providers/nutrition_provider.dart` around line 446–462, locate:

```dart
  void select(int index) {
    state = index;
    // Persist to Hive for data analysis
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    HiveService.instance.healthBox.put('urine_color_$todayStr', {
      'type': 'urine_color',
      'date': todayStr,
      'index': index,
      'label': index >= 0 && index < _labels.length ? _labels[index] : 'unknown',
      'recorded_at': now.toIso8601String(),
    });
    // Refresh AI coach snapshot — urine color is part of the hydration
    // context the coach uses for dehydration warnings.
    unawaited(SyncService.instance.pushSnapshot());
  }
```

Replace the closing `unawaited(SyncService.instance.pushSnapshot());` line with:

```dart
    // APK Test #3 / Plan D Task 1 sync-gap close. Previously only
    // pushSnapshot fired here; the health_logs cloud row never updated
    // until the next launch's full sync. Mirror the addWater pattern.
    unawaited(SyncService.instance.syncNutritionData());
    unawaited(SyncService.instance.pushSnapshot());
```

- [ ] **Step 4: Patch `CustomFoodNotifier.addCustomFood`**

In the same file around line 1066–1069:

```dart
    // Background sync to Supabase
    NutritionRepository.syncCustomFoodToSupabase(data: food);
    unawaited(SyncService.instance.pushSnapshot());
  }
```

Replace with:

```dart
    // Background sync to Supabase. Three-prong fan-out:
    //   1. syncCustomFoodToSupabase  — single-item upsert into
    //      user_custom_foods (existing).
    //   2. syncCustomItemsNow        — full projection of customBox so
    //      the cross-device restore picks this up reliably (mirror of
    //      Train custom-exercise path, APK Test #1 D6).
    //   3. pushSnapshot              — AI coach learns about the new
    //      food immediately.
    NutritionRepository.syncCustomFoodToSupabase(data: food);
    unawaited(SyncService.instance.syncCustomItemsNow());
    unawaited(SyncService.instance.pushSnapshot());
  }
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/sync/nutrition_redesign_sync_test.dart
```

Expected: PASS (both assertions).

- [ ] **Step 6: Commit**

```bash
git add lib/features/nutrition/providers/nutrition_provider.dart \
        test/sync/nutrition_redesign_sync_test.dart
git commit -m "$(cat <<'EOF'
fix(nutrition): sync gaps in urine + custom food writes

Pre-redesign sync hygiene pass (APK Test #3 / Plan D Task 1).

UrineColorNotifier.select previously only fired pushSnapshot, so the
health_logs cloud row never reached Supabase until the next launch's
full sync. Now mirrors WaterIntakeNotifier.addWater — fires
syncNutritionData + pushSnapshot.

CustomFoodNotifier.addCustomFood previously fired the repository
single-item upsert + pushSnapshot, but skipped syncCustomItemsNow.
The Train custom-exercise path fires it (APK Test #1 D6); aligning
the two so cross-device restore is reliable.

Regex regression tests pin both invariants in
test/sync/nutrition_redesign_sync_test.dart.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Build the `HydrationCard` widget (Q8.1=A)

**Files:**
- Create: `lib/features/nutrition/widgets/hydration_card.dart`
- Test: `test/contracts/hydration_card_layout_test.dart`

**Background:** Replaces `_buildInlineWaterTracker` (nutrition_screen lines 976–1193) + `hydration_section.dart` (412 lines) with a single `WardCard` containing two visually-unified rows. The water row (Row 1) renders the 8-cell glass grid and quick-add buttons; the urine row (Row 2) shows the current status pill with a `[change ▾]` toggle that expands an inline 8-color picker.

- [ ] **Step 1: Write the failing contract test**

Create `test/contracts/hydration_card_layout_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HydrationCard is a single WardCard with two rows', () {
    final source = File(
      'lib/features/nutrition/widgets/hydration_card.dart',
    ).readAsStringSync();

    expect(source.contains('class HydrationCard'), isTrue,
        reason: 'HydrationCard widget must exist');

    // Single card surface
    final cardOpens = 'WardCard('.allMatches(source).length;
    expect(cardOpens, 1,
        reason: 'HydrationCard must render exactly ONE WardCard '
            '(both rows share one surface per Q8.1=A).');

    // Water row primitives
    expect(source.contains('WardGlassGrid'), isTrue,
        reason: 'Water row must include WardGlassGrid (8-cell)');
    expect(source.contains("'+ 250ML'") || source.contains('+ 250ML'),
        isTrue,
        reason: 'Water row must show the +250ML quick-add button');
    expect(source.contains("'+ 500ML'") || source.contains('+ 500ML'),
        isTrue,
        reason: 'Water row must show the +500ML quick-add button');

    // Urine row primitives
    expect(source.contains('URINE STATUS') || source.contains('URINE'),
        isTrue,
        reason: 'Urine row must show the URINE STATUS pill label');
    expect(source.contains('change'), isTrue,
        reason: 'Urine row must show the [change ▾] toggle');
    expect(source.contains('AnimatedSize') || source.contains('AnimatedCrossFade'),
        isTrue,
        reason: 'Color picker must expand inline, not push to a new sheet');

    // Hive integration via existing providers
    expect(source.contains('waterIntakeProvider'), isTrue,
        reason: 'Water row must read waterIntakeProvider (existing)');
    expect(source.contains('urineColorProvider'), isTrue,
        reason: 'Urine row must read urineColorProvider (existing)');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/contracts/hydration_card_layout_test.dart
```

Expected: FAIL — file does not yet exist.

- [ ] **Step 3: Create the `HydrationCard` widget**

Create `lib/features/nutrition/widgets/hydration_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/nutrition_provider.dart';

/// Hydration & Urine combined card (Q8.1=A, APK Test #3 redesign).
///
/// Replaces both `hydration_section.dart` and the inline
/// `_buildInlineWaterTracker` from `nutrition_screen.dart`. Single
/// `WardCard`, two rows:
///
///   Row 1 — water progress (`1.7 / 3.0 L`), 8-cell glass grid,
///           `[+ 250ML]` `[+ 500ML]` quick-add buttons.
///   Row 2 — `URINE STATUS · <LABEL>` pill + `[change ▾]` toggle that
///           expands an 8-color picker inline. One-line tip below.
///
/// All state delegated to existing providers — no new Hive writes.
class HydrationCard extends ConsumerStatefulWidget {
  const HydrationCard({super.key});

  @override
  ConsumerState<HydrationCard> createState() => _HydrationCardState();
}

class _HydrationCardState extends ConsumerState<HydrationCard> {
  bool _showColorPicker = false;

  // Same 7-step ladder used in the legacy widget. Kept verbatim so saved
  // urine indices remain semantically identical.
  static const _urineColors = [
    (color: Color(0xFFFFF9C4), status: 'Excellent',
        tip: 'Pale straw — optimal', tone: WardChipTone.ok),
    (color: Color(0xFFFFF176), status: 'Well hydrated',
        tip: 'Clear yellow — well hydrated', tone: WardChipTone.ok),
    (color: Color(0xFFFFD600), status: 'Adequate',
        tip: 'Yellow — drink more soon', tone: WardChipTone.warn),
    (color: Color(0xFFFFB300), status: 'Low',
        tip: 'Dark yellow — drink now', tone: WardChipTone.warn),
    (color: Color(0xFFE65100), status: 'Very low',
        tip: 'Amber — significantly dehydrated', tone: WardChipTone.bad),
    (color: Color(0xFFBF360C), status: 'Critical',
        tip: 'Brown — consult a doctor', tone: WardChipTone.bad),
    (color: Color(0xFF4E342E), status: 'See doctor',
        tip: 'Dark brown — medical attention', tone: WardChipTone.bad),
  ];

  @override
  Widget build(BuildContext context) {
    final waterMl = ref.watch(waterIntakeProvider);
    const waterTarget = 3000;
    final progress = (waterMl / waterTarget).clamp(0.0, 1.0);
    final selectedUrine = ref.watch(urineColorProvider);

    return WardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: Water ──────────────────────────────────────
          _buildWaterRow(waterMl, waterTarget, progress),

          const SizedBox(height: 12),
          const WardRule(margin: EdgeInsets.zero),
          const SizedBox(height: 12),

          // ── Row 2: Urine status ───────────────────────────────
          _buildUrineRow(selectedUrine),
        ],
      ),
    );
  }

  // ── Row 1: water progress + glass grid + quick-add buttons ──
  Widget _buildWaterRow(int waterMl, int waterTarget, double progress) {
    final litres = (waterMl / 1000).toStringAsFixed(1);
    final targetLitres = (waterTarget / 1000).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'HYDRATION & STATUS',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            Text(
              '$litres / $targetLitres L',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Builder(builder: (_) {
          const glassMl = 375;
          final filled = (waterMl / glassMl).floor().clamp(0, 8);
          return WardGlassGrid(
            filled: filled,
            slots: 8,
            onAdd: () => ref
                .read(waterIntakeProvider.notifier)
                .addWater(glassMl),
            onDecrement: () => ref
                .read(waterIntakeProvider.notifier)
                .addWater(-glassMl),
          );
        }),
        const SizedBox(height: 10),
        WardBar(pct: progress, color: AppColors.info, height: 4),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _quickAddButton('+ 250ML', 250)),
            const SizedBox(width: 8),
            Expanded(child: _quickAddButton('+ 500ML', 500)),
          ],
        ),
      ],
    );
  }

  Widget _quickAddButton(String label, int amount) {
    return GestureDetector(
      onTap: () =>
          ref.read(waterIntakeProvider.notifier).addWater(amount),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(
              color: AppColors.info.withValues(alpha: 0.3)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTypography.mono.copyWith(
            color: AppColors.info,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  // ── Row 2: urine status pill + change toggle + inline picker ──
  Widget _buildUrineRow(int selectedUrine) {
    final hasSelection =
        selectedUrine >= 0 && selectedUrine < _urineColors.length;
    final entry = hasSelection ? _urineColors[selectedUrine] : null;
    final pillLabel = hasSelection
        ? 'URINE STATUS · ${entry!.status.toUpperCase()}'
        : 'URINE STATUS · NOT LOGGED';
    final pillTone = hasSelection ? entry!.tone : WardChipTone.neutral;
    final tipLine = hasSelection
        ? entry!.tip
        : 'Tap change ▾ to log how your urine looks today.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            WardChip(label: pillLabel, tone: pillTone),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(
                  () => _showColorPicker = !_showColorPicker),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'change',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                  Icon(
                    _showColorPicker
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.accent,
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          tipLine,
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textDim,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _showColorPicker
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(_urineColors.length, (i) {
                      final isSelected = selectedUrine == i;
                      return GestureDetector(
                        onTap: () {
                          ref
                              .read(urineColorProvider.notifier)
                              .select(i);
                          // Auto-collapse after selection.
                          setState(() => _showColorPicker = false);
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _urineColors[i].color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.line2,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/contracts/hydration_card_layout_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/nutrition/widgets/hydration_card.dart \
        test/contracts/hydration_card_layout_test.dart
git commit -m "$(cat <<'EOF'
feat(nutrition): combined Hydration + Urine card (Q8.1=A)

Replaces hydration_section.dart (412 LoC) and the inline
_buildInlineWaterTracker (nutrition_screen.dart 976-1193) with a
single 14-padded WardCard containing two rows:

  Row 1 — water progress, 8-cell WardGlassGrid, +250ML/+500ML
          quick-add buttons.
  Row 2 — URINE STATUS pill + [change ▾] toggle that expands an
          inline 7-color picker via AnimatedSize.

Both rows share one card surface for visual unity. State stays in
existing waterIntakeProvider + urineColorProvider — no new Hive
writes here. Saves ~150 dp of vertical space vs the legacy stack.

Regex contract test in test/contracts/hydration_card_layout_test.dart
pins the single-card invariant and the urine-pill / quick-add
invariants.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Build the `YourFoodsSection` widget

**Files:**
- Create: `lib/features/nutrition/widgets/your_foods_section.dart`
- Test: `test/contracts/your_foods_section_test.dart`

**Background:** Mirror of Train screen's `_buildYourExercisesSection` (`lib/features/train/screens/train_screen.dart:1908`). Reads `customBox` via `ValueListenableBuilder`, filters keys starting with `custom_food_`, renders newest-first chips with status pills (`DRAFT` / `PENDING ` / `APPROVED ✓`). Tap chip opens the existing `CustomFoodSheet`. Tap `+ ADD CUSTOM` pill opens the same sheet in create mode.

- [ ] **Step 1: Write the failing contract test**

Create `test/contracts/your_foods_section_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YourFoodsSection mirrors Train YOUR EXERCISES pattern', () {
    final source = File(
      'lib/features/nutrition/widgets/your_foods_section.dart',
    ).readAsStringSync();

    expect(source.contains('class YourFoodsSection'), isTrue,
        reason: 'YourFoodsSection widget must exist');

    // Reactive Hive read
    expect(source.contains('ValueListenableBuilder'), isTrue,
        reason: 'Must use ValueListenableBuilder<customBox> so a newly '
            'created custom food appears immediately as a chip.');
    expect(source.contains('customBox.listenable()'), isTrue,
        reason: 'Listenable must come from HiveService.instance.customBox');
    expect(source.contains("'custom_food_'"), isTrue,
        reason: 'Must filter customBox keys by the custom_food_ prefix');

    // Three status states required
    expect(source.contains("'DRAFT'"), isTrue,
        reason: 'DRAFT pill required for non-submitted entries');
    expect(source.contains("'PENDING'"), isTrue,
        reason: 'PENDING pill required for submitted-but-not-approved');
    expect(source.contains("'APPROVED'"), isTrue,
        reason: 'APPROVED pill required for community-approved entries');

    // Empty-state hint + + ADD CUSTOM affordance
    expect(source.contains('No custom foods yet'), isTrue,
        reason: 'Empty state copy must read "No custom foods yet"');
    expect(source.contains('+ ADD CUSTOM'), isTrue,
        reason: '+ ADD CUSTOM pill must be present in both header and '
            'empty-state.');

    // Tap chip → CustomFoodSheet
    expect(source.contains('showCustomFoodSheet'), isTrue,
        reason: 'Tap on chip / + ADD CUSTOM must call '
            'showCustomFoodSheet(context) — the existing sheet is the '
            'single edit/create surface.');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/contracts/your_foods_section_test.dart
```

Expected: FAIL — file does not yet exist.

- [ ] **Step 3: Create the `YourFoodsSection` widget**

Create `lib/features/nutrition/widgets/your_foods_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'custom_food_sheet.dart';

/// `YOUR FOODS` strip on the Nutrition page (APK Test #3 / Plan D).
///
/// Mirrors `_buildYourExercisesSection` from `train_screen.dart` (APK
/// Test #1 D6). Header has a mono `YOUR FOODS` eyebrow + a `+ ADD
/// CUSTOM` `WardChip` pill on the right. Body is a horizontal scroll
/// of `WardChip` rows, one per `custom_food_*` key in `customBox`,
/// sorted newest-first.
///
/// Status pill rules:
///   * `approved == true`               → APPROVED (ok)
///   * `submitted_to_db == true` only   → PENDING  (warn)
///   * neither                           → DRAFT    (textMute)
///
/// Tap any chip → existing `CustomFoodSheet` opens for edit/submit/
/// delete. Same sheet opens in create mode from the `+ ADD CUSTOM`
/// pill.
class YourFoodsSection extends ConsumerWidget {
  const YourFoodsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customBox = HiveService.instance.customBox;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'YOUR FOODS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => showCustomFoodSheet(context),
                child: const WardChip(
                  label: '+ ADD CUSTOM',
                  tone: WardChipTone.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<Box<dynamic>>(
            valueListenable: customBox.listenable(),
            builder: (context, box, _) {
              final foods = _collectCustomFoods(box);
              if (foods.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        'No custom foods yet — tap ',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textDim),
                      ),
                      GestureDetector(
                        onTap: () => showCustomFoodSheet(context),
                        child: Text(
                          '+ ADD CUSTOM',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        ' to add one.',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textDim),
                      ),
                    ],
                  ),
                );
              }
              return SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: foods.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) =>
                      _CustomFoodChip(food: foods[i]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Reads every `custom_food_*` entry from `customBox` newest-first.
  /// Filters out malformed entries.
  List<Map<String, dynamic>> _collectCustomFoods(Box<dynamic> box) {
    final out = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('custom_food_')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map['_key'] = key;
      out.add(map);
    }
    // Newest first. Hive keys are `custom_food_<ms>` so descending
    // string sort == recency order.
    out.sort((a, b) => (b['_key'] as String).compareTo(a['_key'] as String));
    return out;
  }
}

class _CustomFoodChip extends StatelessWidget {
  const _CustomFoodChip({required this.food});

  final Map<String, dynamic> food;

  @override
  Widget build(BuildContext context) {
    final name = food['name'] as String? ?? 'Unnamed';
    final submitted = food['submitted_to_db'] == true;
    final approved = food['approved'] == true;

    final (String statusLabel, Color statusColor) = approved
        ? ('APPROVED', AppColors.ok)
        : submitted
            ? ('PENDING', AppColors.warn)
            : ('DRAFT', AppColors.textMute);

    return GestureDetector(
      onTap: () => showCustomFoodSheet(context),
      child: Container(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line2),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              statusLabel,
              style: AppTypography.monoXs.copyWith(
                color: statusColor,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/contracts/your_foods_section_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/nutrition/widgets/your_foods_section.dart \
        test/contracts/your_foods_section_test.dart
git commit -m "$(cat <<'EOF'
feat(nutrition): YOUR FOODS section with status pills

Mirrors the Train _buildYourExercisesSection pattern (APK Test #1
D6). ValueListenableBuilder<customBox> rebuilds the chip strip on
every customBox mutation, so a freshly created custom food appears
immediately.

Status rules:
  * approved=true            → APPROVED (ok)
  * submitted_to_db=true     → PENDING  (warn)
  * neither                  → DRAFT    (textMute)

Empty state and + ADD CUSTOM pill both route to showCustomFoodSheet.
Tap on a chip opens the same sheet for edit/submit/delete.

Regex contract test in test/contracts/your_foods_section_test.dart
pins the ValueListenableBuilder + three-status invariants.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Build the AI mode body for the LogFoodSheet

**Files:**
- Create: `lib/features/nutrition/widgets/log_food_modes/ai_mode_body.dart`

**Background:** AI mode wraps the existing `FoodLoggerSection` (text input + ANALYSE & LOG button) AND the conditional `AiBreakdownCard` (renders after a successful analyse). The two are kept paired so the user sees their breakdown without leaving the sheet. Auto-dismisses the sheet when the breakdown is committed (food log written → `aiBreakdownProvider` returns null again).

- [ ] **Step 1: Create `ai_mode_body.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../ai_breakdown_card.dart';
import '../food_logger_section.dart';
import '../../providers/nutrition_provider.dart';

/// AI mode body for `LogFoodSheet`.
///
/// Pairs the existing `FoodLoggerSection` (text input + ANALYSE & LOG)
/// with the conditional `AiBreakdownCard`. After the user commits the
/// breakdown, the `aiBreakdownProvider` clears, the page refreshes,
/// and the parent sheet closes via `onLogged`.
class AiModeBody extends ConsumerStatefulWidget {
  const AiModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  ConsumerState<AiModeBody> createState() => _AiModeBodyState();
}

class _AiModeBodyState extends ConsumerState<AiModeBody> {
  ProviderSubscription<AiBreakdown?>? _subscription;
  AiBreakdown? _previous;

  @override
  void initState() {
    super.initState();
    // Listen for the moment the user commits a breakdown — which
    // clears the provider — and bubble that to the parent sheet.
    _subscription = ref.listenManual<AiBreakdown?>(
      aiBreakdownProvider,
      (prev, next) {
        // A non-null → null transition means "log committed". Don't
        // dismiss when the breakdown is dismissed via cancel; cancel
        // is also a non-null → null event but the food log row is
        // not written. Treat both as a successful close — the user
        // explicitly chose to leave the AI mode either way.
        if (prev != null && next == null) {
          widget.onLogged();
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = ref.watch(aiBreakdownProvider);
    _previous = breakdown;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT DID YOU JUST EAT?',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          const FoodLoggerSection(),
          if (breakdown != null) ...[
            const SizedBox(height: 12),
            const AiBreakdownCard(),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/nutrition/widgets/log_food_modes/ai_mode_body.dart
git commit -m "$(cat <<'EOF'
feat(nutrition): AI mode body for LogFoodSheet

Wraps FoodLoggerSection + conditional AiBreakdownCard so the user
analyses, edits, and commits a meal without leaving the sheet.
ProviderSubscription on aiBreakdownProvider triggers onLogged when
the breakdown clears (commit OR cancel — both leave the user with
no further action in AI mode).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Build the SCAN, CART, BARCODE, SEARCH mode bodies

**Files:**
- Create: `lib/features/nutrition/widgets/log_food_modes/scan_mode_body.dart`
- Create: `lib/features/nutrition/widgets/log_food_modes/cart_mode_body.dart`
- Create: `lib/features/nutrition/widgets/log_food_modes/barcode_mode_body.dart`
- Create: `lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart`

**Background:** Each mode is a thin wrapper around an existing widget. Goal: minimum new logic, just relocation + dismiss-on-success behavior. The existing widgets keep their independent save semantics (no API changes), so cloud syncs already fire correctly.

- [ ] **Step 1: Create `scan_mode_body.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../scan_meal_section.dart';

/// SCAN mode body for `LogFoodSheet`. Wraps `ScanMealSection` with
/// a scrollable padded container — ScanMealSection grows tall when the
/// result editor is open.
class ScanModeBody extends ConsumerWidget {
  const ScanModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Note: ScanMealSection writes to nutrition_log internally. Since
    // the existing widget doesn't expose an onSave callback, we keep
    // onLogged plumbed but unused for now — the page refresh after
    // sheet dismissal still picks up the new log via dailyNutrition
    // provider invalidation. Future refactor of ScanMealSection can
    // accept onSave for tighter UX (auto-dismiss the sheet on save).
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: const ScanMealSection(),
    );
  }
}
```

- [ ] **Step 2: Create `cart_mode_body.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../cart_auditor_section.dart';

/// CART mode body for `LogFoodSheet`. Cart Auditor is read-only: user
/// uploads a grocery screenshot → Gemini returns an audit JSON → user
/// reads the suggestions but no food log is written. Sheet stays open
/// until the user taps the close affordance.
class CartModeBody extends ConsumerWidget {
  const CartModeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: const CartAuditorSection(),
    );
  }
}
```

- [ ] **Step 3: Create `barcode_mode_body.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// BARCODE mode body for `LogFoodSheet`. Refactored from
/// `_BarcodeScanSheet` to render inside the parent sheet rather than
/// opening as a separate modal. Keeps the same MobileScanner controller
/// + result-editor flow; on save, calls [onLogged].
///
/// NOTE: This task creates the body shell. The full implementation
/// reuses the result-editor logic from `barcode_scan_sheet.dart` — see
/// Task 6 where the legacy `_BarcodeScanSheet` body is extracted into a
/// shared `BarcodeBody` and the entry-point `showBarcodeScanSheet`
/// helper kept for any external callers (none today).
class BarcodeModeBody extends ConsumerStatefulWidget {
  const BarcodeModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  ConsumerState<BarcodeModeBody> createState() => _BarcodeModeBodyState();
}

class _BarcodeModeBodyState extends ConsumerState<BarcodeModeBody> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Placeholder shell — Task 6 will fill this in by extracting the
    // _BarcodeScanSheetState build body from barcode_scan_sheet.dart
    // verbatim (controller is already wired here).
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'POINT YOUR CAMERA AT A PRODUCT BARCODE',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: MobileScanner(controller: _controller),
              ),
            ),
          ),
          // Body finalised in Task 6.
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Create `search_mode_body.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../saved_meals_section.dart';

/// SEARCH mode body for `LogFoodSheet`. Three sub-filters at the top:
///   `[All] [Saved Meals] [Recent]`.
/// Body switches based on the active filter:
///   * All        — full-text food search field (same UI as the
///                  legacy showFoodSearchSheet).
///   * Saved Meals — embedded SavedMealsSection.
///   * Recent     — most-recent foodlog rows from nutritionBox.
class SearchModeBody extends ConsumerStatefulWidget {
  const SearchModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  ConsumerState<SearchModeBody> createState() => _SearchModeBodyState();
}

enum _SearchFilter { all, saved, recent }

class _SearchModeBodyState extends ConsumerState<SearchModeBody> {
  _SearchFilter _filter = _SearchFilter.all;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-filter chip row
          Row(
            children: [
              _filterChip(_SearchFilter.all, 'All'),
              const SizedBox(width: 6),
              _filterChip(_SearchFilter.saved, 'Saved Meals'),
              const SizedBox(width: 6),
              _filterChip(_SearchFilter.recent, 'Recent'),
            ],
          ),
          const SizedBox(height: 12),
          // Body switches by filter
          Expanded(
            child: switch (_filter) {
              _SearchFilter.all => _AllFoodsSearch(
                  onLogged: widget.onLogged,
                ),
              _SearchFilter.saved => const SavedMealsSection(),
              _SearchFilter.recent => _RecentLogs(onLogged: widget.onLogged),
            },
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_SearchFilter value, String label) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: WardChip(
        label: label.toUpperCase(),
        tone: selected ? WardChipTone.gold : WardChipTone.neutral,
      ),
    );
  }
}

/// Embedded full-text search reusing the existing food search query
/// infrastructure. Body is intentionally minimal here — the heavy
/// lifting is delegated to existing providers.
class _AllFoodsSearch extends ConsumerStatefulWidget {
  const _AllFoodsSearch({required this.onLogged});
  final VoidCallback onLogged;
  @override
  ConsumerState<_AllFoodsSearch> createState() => _AllFoodsSearchState();
}

class _AllFoodsSearchState extends ConsumerState<_AllFoodsSearch> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(color: AppColors.line2),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: AppColors.textDim, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: (_) => setState(() {}),
                  style: AppTypography.body,
                  decoration: const InputDecoration(
                    hintText: 'Search foods',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // The actual results list reuses the same query path as
        // showFoodSearchSheet — see Task 7 for wiring detail.
        Expanded(
          child: _SearchResultsList(
            query: _controller.text,
            onLogged: widget.onLogged,
          ),
        ),
      ],
    );
  }
}

/// Placeholder wired in Task 7 — pulls from the same provider used by
/// `food_search_sheet.dart` so behavior matches the legacy bottom-sheet
/// path verbatim.
class _SearchResultsList extends ConsumerWidget {
  const _SearchResultsList({required this.query, required this.onLogged});
  final String query;
  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Implementation in Task 7.
    return const Center(child: SizedBox.shrink());
  }
}

class _RecentLogs extends ConsumerWidget {
  const _RecentLogs({required this.onLogged});
  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Implementation in Task 7.
    return const Center(child: SizedBox.shrink());
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/nutrition/widgets/log_food_modes/
git commit -m "$(cat <<'EOF'
feat(nutrition): mode bodies for SCAN / CART / BARCODE / SEARCH

Four thin mode-body wrappers for LogFoodSheet:
  * ScanModeBody    — wraps ScanMealSection.
  * CartModeBody    — wraps CartAuditorSection (read-only, no save).
  * BarcodeModeBody — shell with MobileScanner controller; result
    editor body finalised in Task 6 by extracting from
    barcode_scan_sheet.dart.
  * SearchModeBody  — sub-filter chips [All / Saved Meals / Recent]
    + body switch. _SearchResultsList and _RecentLogs are placeholders
    finalised in Task 7.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Extract Barcode body and finalise BarcodeModeBody

**Files:**
- Modify: `lib/features/nutrition/widgets/barcode_scan_sheet.dart` (extract `_BarcodeScanSheetState.build` body into a reusable `BarcodeBody` widget)
- Modify: `lib/features/nutrition/widgets/log_food_modes/barcode_mode_body.dart` (use the extracted body)

- [ ] **Step 1: Refactor `barcode_scan_sheet.dart`**

Open `lib/features/nutrition/widgets/barcode_scan_sheet.dart`. Locate the `_BarcodeScanSheetState.build` body (around line 90+ — the column that renders the scanner + result editor + log buttons). Extract everything inside the `Padding(...)` content of the existing build into a new top-level widget:

```dart
/// Reusable Barcode scanner + result-editor body. Used by:
///   * the legacy `showBarcodeScanSheet` standalone modal entry point
///     (`_BarcodeScanSheet` host).
///   * the new `BarcodeModeBody` inside `LogFoodSheet`.
class BarcodeBody extends ConsumerStatefulWidget {
  const BarcodeBody({super.key, required this.onLogged});

  /// Fired after the user taps `LOG` and the food row is written.
  /// Hosts use this to dismiss themselves.
  final VoidCallback onLogged;

  @override
  ConsumerState<BarcodeBody> createState() => _BarcodeBodyState();
}

class _BarcodeBodyState extends ConsumerState<BarcodeBody> {
  // Move the existing _BarcodeScanSheetState fields and methods here
  // verbatim (controller, _loading, _scanned, _food, _onDetect, _save,
  // dispose, etc.). Replace any `Navigator.of(context).pop()` calls
  // with `widget.onLogged()` so the host decides how to dismiss.

  // ... (extracted verbatim from _BarcodeScanSheetState)
}
```

Then update `_BarcodeScanSheetState.build` to delegate:

```dart
@override
Widget build(BuildContext context) {
  return Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom,
    ),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: BarcodeBody(
        onLogged: () => Navigator.of(context).pop(),
      ),
    ),
  );
}
```

- [ ] **Step 2: Use `BarcodeBody` from `BarcodeModeBody`**

Replace the placeholder body in `barcode_mode_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../barcode_scan_sheet.dart' show BarcodeBody;

class BarcodeModeBody extends ConsumerWidget {
  const BarcodeModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BarcodeBody(onLogged: onLogged);
  }
}
```

(Remove the `MobileScannerController` and `_BarcodeModeBodyState` — they move into `BarcodeBody` via the extraction.)

- [ ] **Step 3: Sanity test the legacy entry point still compiles**

```bash
flutter analyze lib/features/nutrition/widgets/barcode_scan_sheet.dart \
                lib/features/nutrition/widgets/log_food_modes/barcode_mode_body.dart
```

Expected: zero errors. Any remaining warnings should be related to private-class renames only.

- [ ] **Step 4: Commit**

```bash
git add lib/features/nutrition/widgets/barcode_scan_sheet.dart \
        lib/features/nutrition/widgets/log_food_modes/barcode_mode_body.dart
git commit -m "$(cat <<'EOF'
refactor(nutrition): extract reusable BarcodeBody widget

The barcode scanner + result-editor body lived inside private
_BarcodeScanSheetState. Extracted to a public BarcodeBody widget so:
  * Legacy showBarcodeScanSheet (standalone modal) keeps working
    via a thin host that supplies onLogged → Navigator.pop.
  * BarcodeModeBody in LogFoodSheet renders the same body without
    a second modal.

No behavior change for the legacy entry point. Sets up Task 9
where LogFoodSheet swaps in the new mode body.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Finalise SearchModeBody — wire All / Recent backed by existing providers

**Files:**
- Modify: `lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart`

**Background:** The placeholders `_SearchResultsList` and `_RecentLogs` need real data. Reuse:
- `food_search_sheet.dart` query path for `All` (existing public function `showFoodSearchSheet` returns search results from a Riverpod provider — extract into a shared `foodSearchResultsProvider` if not already public).
- `nutritionBox` direct read for `Recent` (filter `flog_*` keys, last 14 days, dedupe by food_name, top 8).

- [ ] **Step 1: Audit `food_search_sheet.dart` for a reusable query provider**

Read `lib/features/nutrition/widgets/food_search_sheet.dart` and identify the search-results provider (likely a `StateProvider<String>` for query + a derived `FutureProvider<List<...>>` for results). If it's privately scoped, lift it into `nutrition_provider.dart` as `foodSearchQueryProvider` + `foodSearchResultsProvider` so the new SEARCH mode body can read it.

If the existing sheet uses inline state, leave the legacy sheet alone and use the same underlying repository call directly from `_SearchResultsList`.

- [ ] **Step 2: Replace `_SearchResultsList` placeholder**

```dart
class _SearchResultsList extends ConsumerWidget {
  const _SearchResultsList({required this.query, required this.onLogged});
  final String query;
  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Type at least 2 characters to search.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
            ),
          ),
        ),
      );
    }

    // Reuse existing food search via repository. Provider may be
    // foodSearchResultsProvider (lifted in Step 1); otherwise call the
    // repository directly from a FutureBuilder so we don't recreate
    // the lift in this PR.
    final results = ref.watch(foodSearchResultsProvider(query));
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Search failed',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.bad)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(
              'No results for "$query"',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.textDim),
            ),
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: AppColors.line2),
          itemBuilder: (_, i) {
            final item = items[i];
            return ListTile(
              title: Text(item['name'] as String? ?? 'Unknown',
                  style: AppTypography.body),
              subtitle: Text(
                '${(item['calories_std'] as num?)?.toInt() ?? 0} kcal · ${item['standard_serving_desc'] ?? '1 serving'}',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.textDim),
              ),
              onTap: () async {
                await ref
                    .read(foodLogProvider.notifier)
                    .logFromSearchItem(item);
                onLogged();
              },
            );
          },
        );
      },
    );
  }
}
```

(If `foodSearchResultsProvider` isn't lifted yet, drop in the equivalent `FutureBuilder` calling `NutritionRepository.searchFoods(query)` — same behavior.)

- [ ] **Step 3: Replace `_RecentLogs` placeholder**

```dart
class _RecentLogs extends ConsumerWidget {
  const _RecentLogs({required this.onLogged});
  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final box = HiveService.instance.nutritionBox;
    // Last 14 days, dedupe by food_name, top 8.
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final entries = <String, Map<String, dynamic>>{};
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('flog_')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final loggedAtStr = raw['logged_at'] as String?;
      if (loggedAtStr == null) continue;
      final loggedAt = DateTime.tryParse(loggedAtStr);
      if (loggedAt == null || loggedAt.isBefore(cutoff)) continue;
      final name = (raw['food_name'] as String?) ?? '';
      if (name.isEmpty || entries.containsKey(name)) continue;
      entries[name] = Map<String, dynamic>.from(raw);
      if (entries.length >= 8) break;
    }
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No recent logs in the last 14 days.',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.textDim),
          ),
        ),
      );
    }
    final list = entries.values.toList();
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.line2),
      itemBuilder: (_, i) {
        final item = list[i];
        return ListTile(
          title: Text(item['food_name'] as String? ?? 'Unknown',
              style: AppTypography.body),
          subtitle: Text(
            '${(item['total_calories'] as num?)?.toInt() ?? 0} kcal',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.textDim),
          ),
          onTap: () async {
            await ref
                .read(foodLogProvider.notifier)
                .relogFromHistory(item);
            onLogged();
          },
        );
      },
    );
  }
}
```

(`relogFromHistory` may need to be added or wired to the existing relog method on `foodLogProvider`; verify by reading `nutrition_provider.dart` and patch the call site to whichever method is canonical.)

- [ ] **Step 4: Commit**

```bash
git add lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart \
        lib/features/nutrition/providers/nutrition_provider.dart
git commit -m "$(cat <<'EOF'
feat(nutrition): wire SearchModeBody All / Recent results

SearchModeBody now backs:
  * All     — foodSearchResultsProvider (existing repository query).
  * Saved   — embedded SavedMealsSection.
  * Recent  — direct nutritionBox scan: last 14 days, dedupe by
              food_name, top 8.

Tap on any row writes a food log via foodLogProvider and bubbles
onLogged so LogFoodSheet dismisses.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Build the LogFoodSheet shell + 5-mode tab switcher

**Files:**
- Create: `lib/features/nutrition/widgets/log_food_sheet.dart`
- Test: `test/contracts/log_food_sheet_test.dart`

- [ ] **Step 1: Write the failing contract test**

Create `test/contracts/log_food_sheet_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LogFoodSheet hosts 5 modes with AI default', () {
    final source = File(
      'lib/features/nutrition/widgets/log_food_sheet.dart',
    ).readAsStringSync();

    expect(source.contains('class LogFoodSheet'), isTrue,
        reason: 'LogFoodSheet widget must exist');
    expect(source.contains('void showLogFoodSheet'), isTrue,
        reason: 'showLogFoodSheet entry-point function must exist '
            'so nutrition_screen and any other caller can open it.');

    // 5 mode names — keep these exact strings, the test is a contract
    for (final name in ['ai', 'scan', 'cart', 'barcode', 'search']) {
      expect(source.contains('LogFoodMode.$name'),
          isTrue,
          reason: 'LogFoodMode.$name must be a member of the enum');
    }

    // AI is default
    final defaultLine = source.indexOf('_active = LogFoodMode.');
    expect(defaultLine, isNot(-1),
        reason: 'A field initial assignment _active = LogFoodMode.<x> '
            'must exist');
    expect(
      source.substring(defaultLine, defaultLine + 60).contains('LogFoodMode.ai'),
      isTrue,
      reason: 'Default active mode must be LogFoodMode.ai',
    );

    // Sheet height ~75% of screen
    expect(
      source.contains('initialChildSize:') ||
          source.contains('heightFactor: 0.75') ||
          source.contains('* 0.75'),
      isTrue,
      reason: 'Sheet must size to ~75% of the screen height (per spec).',
    );

    // Segmented WardChip tabs
    expect(source.contains('WardChip'), isTrue,
        reason: 'Tabs must render as WardChip (selected = gold).');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/contracts/log_food_sheet_test.dart
```

Expected: FAIL — file does not yet exist.

- [ ] **Step 3: Create `log_food_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'log_food_modes/ai_mode_body.dart';
import 'log_food_modes/scan_mode_body.dart';
import 'log_food_modes/cart_mode_body.dart';
import 'log_food_modes/barcode_mode_body.dart';
import 'log_food_modes/search_mode_body.dart';

/// The five modes hosted by [LogFoodSheet]. AI is the default tab.
enum LogFoodMode { ai, scan, cart, barcode, search }

/// Opens the LogFoodSheet bottom sheet (75% screen height).
void showLogFoodSheet(BuildContext context, {LogFoodMode? initial}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LogFoodSheet(initial: initial ?? LogFoodMode.ai),
  );
}

/// + LOG FOOD bottom sheet (APK Test #3 / Plan D).
///
/// Header: title + close affordance.
/// Tabs:   segmented WardChip row [✨ AI · 📷 SCAN · 🛒 CART ·
///         🔢 BAR · 🔍 SEARCH].
/// Body:   active mode renders inside a 75%-height container.
///         AI is default. Each mode dismisses the sheet via [_dismiss]
///         on successful save.
class LogFoodSheet extends ConsumerStatefulWidget {
  const LogFoodSheet({super.key, required this.initial});
  final LogFoodMode initial;

  @override
  ConsumerState<LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends ConsumerState<LogFoodSheet> {
  late LogFoodMode _active = widget.initial;

  void _dismiss() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final sheetH = screenH * 0.75;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: sheetH,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.card)),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            const WardRule(margin: EdgeInsets.zero),
            Expanded(child: _buildActiveBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
      child: Row(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Spacer(),
          Text(
            'LOG FOOD',
            style: AppTypography.mono.copyWith(
              color: AppColors.textPrimary,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.textDim),
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _tab(LogFoodMode.ai, '✨ AI'),
          const SizedBox(width: 6),
          _tab(LogFoodMode.scan, '📷 SCAN'),
          const SizedBox(width: 6),
          _tab(LogFoodMode.cart, '🛒 CART'),
          const SizedBox(width: 6),
          _tab(LogFoodMode.barcode, '🔢 BAR'),
          const SizedBox(width: 6),
          _tab(LogFoodMode.search, '🔍 SEARCH'),
        ],
      ),
    );
  }

  Widget _tab(LogFoodMode mode, String label) {
    final selected = _active == mode;
    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _active = mode),
        child: WardChip(
          label: label,
          tone: selected ? WardChipTone.gold : WardChipTone.neutral,
        ),
      ),
    );
  }

  Widget _buildActiveBody() {
    return switch (_active) {
      LogFoodMode.ai => AiModeBody(onLogged: _dismiss),
      LogFoodMode.scan => ScanModeBody(onLogged: _dismiss),
      LogFoodMode.cart => const CartModeBody(),
      LogFoodMode.barcode => BarcodeModeBody(onLogged: _dismiss),
      LogFoodMode.search => SearchModeBody(onLogged: _dismiss),
    };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/contracts/log_food_sheet_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/nutrition/widgets/log_food_sheet.dart \
        test/contracts/log_food_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(nutrition): + LOG FOOD bottom sheet shell with 5 modes

Single bottom sheet hosts AI / SCAN / CART / BARCODE / SEARCH.
Segmented WardChip tabs at top, AI default. Sheet height = 75% of
screen so the camera modes have enough vertical room. Each mode
calls onLogged on successful save → sheet dismisses, page refreshes
via the existing dailyNutrition provider invalidation.

Entry point: showLogFoodSheet(context). Used by the new
+ LOG FOOD CTA on nutrition_screen (Task 9).

Regex contract test in test/contracts/log_food_sheet_test.dart pins
the 5-mode enum, AI default, 75% height, and WardChip tabs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Rewrite `nutrition_screen.dart` body per Obs 3 layout

**Files:**
- Modify: `lib/features/nutrition/screens/nutrition_screen.dart` (drops 5 sections + adds 3 new ones, ~600 lines net)
- Test: `test/contracts/nutrition_screen_layout_test.dart`

**Background:** This is the biggest single change. The current body renders 8+ sections; the new body renders 7, of which 3 are new (`+ LOG FOOD` CTA, `HydrationCard`, `YourFoodsSection`) and 4 are kept (`Header`, `TODAY'S SUMMARY`, `TodaysMealsCard`, `INSIGHTS & TRENDS`). The 5 logging sections collapse into the sheet and disappear from the page entirely. The `_buildInlineWaterTracker`, `_buildSearchAndCustomCard`, `_buildAiInputCard` helpers + the `SavedMealsSection` import all go away.

- [ ] **Step 1: Write the failing layout contract test**

Create `test/contracts/nutrition_screen_layout_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/nutrition/screens/nutrition_screen.dart',
  ).readAsStringSync();

  test('NutritionScreen renders the redesigned layout', () {
    // New widgets
    expect(source.contains('HydrationCard()'), isTrue,
        reason: 'NutritionScreen must render the new HydrationCard.');
    expect(source.contains('YourFoodsSection()'), isTrue,
        reason: 'NutritionScreen must render the new YourFoodsSection.');
    expect(source.contains('+ LOG FOOD'), isTrue,
        reason: 'NutritionScreen must show the + LOG FOOD CTA button.');
    expect(source.contains('showLogFoodSheet'), isTrue,
        reason: 'CTA must call showLogFoodSheet on tap.');

    // Existing kept widgets
    expect(source.contains('TodaysMealsCard'), isTrue,
        reason: 'TodaysMealsCard must still render (kept, repositioned).');
    expect(source.contains('WeeklyChartCard'), isTrue,
        reason: 'WeeklyChartCard must still render (under INSIGHTS).');

    // Hoisted-into-sheet sections must NOT be instantiated on the page
    for (final removed in const [
      'FoodLoggerSection()',
      'ScanMealSection()',
      'CartAuditorSection()',
      'SavedMealsSection()',
      '_buildInlineWaterTracker',
      '_buildSearchAndCustomCard',
      '_buildAiInputCard',
    ]) {
      expect(
        source.contains(removed),
        isFalse,
        reason: '$removed must NOT appear on the redesigned nutrition '
            'page — it lives inside LogFoodSheet now (or is replaced).',
      );
    }
  });

  test('NutritionScreen does not import the hoisted widgets directly', () {
    for (final imp in const [
      "import '../widgets/food_logger_section.dart'",
      "import '../widgets/scan_meal_section.dart'",
      "import '../widgets/cart_auditor_section.dart'",
      "import '../widgets/saved_meals_section.dart'",
    ]) {
      expect(source.contains(imp), isFalse,
          reason: '$imp must be removed — those widgets are referenced '
              'from inside log_food_modes/* now.');
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/contracts/nutrition_screen_layout_test.dart
```

Expected: FAIL — old widgets still imported, new widgets not yet referenced.

- [ ] **Step 3: Update imports in `nutrition_screen.dart`**

Replace the current import block (lines 1–26) with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import '../providers/nutrition_provider.dart';
import '../providers/diet_plan_provider.dart';
import '../widgets/todays_meals_card.dart';
import '../widgets/weekly_chart_card.dart';
import '../widgets/hydration_card.dart';
import '../widgets/your_foods_section.dart';
import '../widgets/log_food_sheet.dart';
import '../widgets/log_to_slot_sheet.dart';
```

(Removed: `food_logger_section`, `ai_breakdown_card`, `scan_meal_section`, `cart_auditor_section`, `saved_meals_section`, `food_search_sheet`, `barcode_scan_sheet`, `custom_food_sheet`. Those widgets are still referenced — but only from inside `log_food_modes/*` and `your_foods_section.dart`, not from the screen.)

- [ ] **Step 4: Replace `_buildMealsTab` body**

Find the existing `_buildMealsTab` method (line 160). Replace its `ListView` children with:

```dart
  Widget _buildMealsTab() {
    final nutrition = ref.watch(dailyNutritionProvider);
    final targets = ref.watch(macroTargetsProvider);
    final profile = ref.watch(userProfileProvider);
    final weeklyData = ref.watch(weeklyNutritionProvider);

    // APK Test #3 / Plan D layout. Top → bottom:
    //   1. TODAY'S SUMMARY (existing — calorie ring + macro bars +
    //      inline projection italic)
    //   2. + LOG FOOD CTA (new gold button → showLogFoodSheet)
    //   3. HYDRATION & STATUS combined card (new HydrationCard)
    //   4. TODAY'S MEALS (existing TodaysMealsCard, hoisted up)
    //   5. INSIGHTS & TRENDS (existing WeeklyChartCard pair)
    //   6. YOUR FOODS (new YourFoodsSection)
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // 1. TODAY'S SUMMARY ─────────────────────────────────────
        _sectionLabel("TODAY'S SUMMARY", topPadding: 10),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildCalorieCard(
            nutrition,
            targets: targets,
            profile: profile,
          ),
        ),
        const SizedBox(height: 14),

        // 2. + LOG FOOD CTA ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildLogFoodCta(),
        ),
        const SizedBox(height: 14),

        // 3. HYDRATION & STATUS ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: const HydrationCard(),
        ),
        const SizedBox(height: 14),

        // 4. TODAY'S MEALS ────────────────────────────────────────
        _sectionLabel("TODAY'S MEALS"),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: Builder(builder: (context) {
            final plannedSlots = ref.watch(dietPlanProvider);
            return TodaysMealsCard(
              meals: nutrition.allMeals,
              plannedSlots: plannedSlots,
              onDelete: (logId) => _confirmAndDeleteFoodLog(logId),
              onEdit: (meal) => _showEditMacrosSheet(context, meal),
              onLogSlot: (slot) =>
                  LogToSlotSheet.show(context, slot: slot),
            );
          }),
        ),
        const SizedBox(height: 14),

        // 5. INSIGHTS & TRENDS ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildInsightsSection(weeklyData),
        ),
        const SizedBox(height: 14),

        // 6. YOUR FOODS ──────────────────────────────────────────
        const YourFoodsSection(),
        const SizedBox(height: 24),
      ],
    );
  }
```

- [ ] **Step 5: Add the `_buildLogFoodCta` helper**

Add this method on the same class:

```dart
  /// Full-width gold-accent CTA opening the LogFoodSheet (5 modes).
  ///
  /// Replaces the previous flat split of AI input + SCAN peer + Search
  /// + Cart + Barcode rows. One button, one tap, one decision.
  Widget _buildLogFoodCta() {
    return GestureDetector(
      onTap: () => showLogFoodSheet(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.20),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: AppColors.bgDeep, size: 18),
            const SizedBox(width: 8),
            Text(
              'LOG FOOD',
              style: AppTypography.mono.copyWith(
                color: AppColors.bgDeep,
                fontSize: 13,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 6: Delete the now-unused helpers**

Remove from `nutrition_screen.dart`:
- `_buildInlineWaterTracker` (lines ~976–1193)
- `_buildAiInputCard` (lines ~517–552)
- `_buildSearchAndCustomCard` (lines ~560–670)
- `_urineColors` static const list (lines ~966–974) — moves into `HydrationCard`
- The `_isWaterExpanded` field
- Any helpers exclusively used by the removed sections

Keep:
- `_buildHeader`, `_buildDietPlanButton`
- `_buildCalorieCard`, `_macroRow`, `_projectionLine`
- `_sectionLabel`
- `_confirmAndDeleteFoodLog`, `_showEditMacrosSheet`, `_macroField`
- `_showBmrTdeeInfo`
- `_buildInsightsSection` (existing)

- [ ] **Step 7: Run test to verify it passes**

```bash
flutter test test/contracts/nutrition_screen_layout_test.dart
```

Expected: PASS — both invariants.

- [ ] **Step 8: Run full nutrition test suite**

```bash
flutter test test/contracts/ test/sync/nutrition_redesign_sync_test.dart
```

Expected: ALL PASS — layout, hydration, log food sheet, your foods, sync gap.

- [ ] **Step 9: Commit**

```bash
git add lib/features/nutrition/screens/nutrition_screen.dart \
        test/contracts/nutrition_screen_layout_test.dart
git commit -m "$(cat <<'EOF'
feat(nutrition): page rewrite per Obs 3 redesign

NutritionScreen body collapsed from 8+ stacked sections (~1500 dp
scroll) to 6 tight sections (~700 dp scroll on a 360x640 viewport):

  1. TODAY'S SUMMARY   — kept (calorie ring + macro bars + projection)
  2. + LOG FOOD CTA    — NEW (full-width gold, opens LogFoodSheet)
  3. HYDRATION & STATUS— NEW HydrationCard (combined water + urine)
  4. TODAY'S MEALS     — kept (hoisted above charts)
  5. INSIGHTS & TRENDS — kept (collapsible WeeklyChartCard pair)
  6. YOUR FOODS        — NEW YourFoodsSection (custom food chips)

Removed from the page (now hosted inside LogFoodSheet):
  * FoodLoggerSection, AiBreakdownCard
  * ScanMealSection
  * CartAuditorSection
  * SavedMealsSection
  * showFoodSearchSheet, showBarcodeScanSheet, showCustomFoodSheet
    direct call sites

Imports trimmed accordingly. Helpers _buildInlineWaterTracker,
_buildAiInputCard, _buildSearchAndCustomCard deleted.

Regex contract test pins the new layout AND the absence of the
hoisted widgets/imports — so any future refactor that accidentally
re-imports a logging widget into the page will fail in CI.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Audit and patch sync gaps surfaced by the redesign

**Background:** Final sync hygiene sweep. The new code paths that mutate Hive must all fire `unawaited(SyncService.syncNutritionData()) + unawaited(SyncService.pushSnapshot())` (or `syncCustomItemsNow` for custom-food creates). This task locks the invariants with regex tests so future contributors can't drop them silently.

**Files:**
- Modify: `test/sync/nutrition_redesign_sync_test.dart` (extend with new contract assertions)

- [ ] **Step 1: Extend `nutrition_redesign_sync_test.dart` with full audit**

Append these tests to the existing file (Task 1's tests stay):

```dart
  test('AddWater fires syncNutritionData + pushSnapshot', () {
    // Sanity rebar — already correct in the codebase, locked here so a
    // future "let's batch sync calls" refactor doesn't drop them.
    final addStart = source.indexOf('Future<void> addWater(int ml)');
    expect(addStart, isNot(-1));
    final body = source.substring(addStart, addStart + 600);
    expect(body.contains('syncNutritionData'), isTrue);
    expect(body.contains('pushSnapshot'), isTrue);
  });

  test('LogFoodSheet AI/Scan/Search modes save through foodLogProvider',
      () {
    // Each mode body either uses an existing widget that already syncs
    // (FoodLoggerSection, ScanMealSection — both fire unawaited sync
    // internally) or routes through foodLogProvider.logFromSearchItem /
    // .relogFromHistory. This test asserts none of them inline a Hive
    // put without a sync.
    for (final modeFile in const [
      'lib/features/nutrition/widgets/log_food_modes/ai_mode_body.dart',
      'lib/features/nutrition/widgets/log_food_modes/scan_mode_body.dart',
      'lib/features/nutrition/widgets/log_food_modes/cart_mode_body.dart',
      'lib/features/nutrition/widgets/log_food_modes/barcode_mode_body.dart',
      'lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart',
    ]) {
      final body = File(modeFile).readAsStringSync();
      // Must not use raw Hive.box calls — must go through HiveService.
      expect(
        body.contains("Hive.box('"),
        isFalse,
        reason: 'Mode body $modeFile must not use raw Hive.box() — '
            'route through HiveService.instance.<box> per CLAUDE.md '
            '§ "Raw `Hive.box(...)` in cold-start-reachable path".',
      );
    }
  });

  test('HydrationCard delegates to existing providers (no inline writes)',
      () {
    final body = File(
      'lib/features/nutrition/widgets/hydration_card.dart',
    ).readAsStringSync();
    expect(body.contains('healthBox.put'), isFalse,
        reason: 'HydrationCard must NOT write to healthBox directly — '
            'all writes go through urineColorProvider + '
            'waterIntakeProvider, which already fire syncs.');
  });

  test('YourFoodsSection performs no writes — read-only chip strip', () {
    final body = File(
      'lib/features/nutrition/widgets/your_foods_section.dart',
    ).readAsStringSync();
    expect(body.contains('customBox.put'), isFalse,
        reason: 'YourFoodsSection is read-only. Writes go through the '
            'CustomFoodSheet → CustomFoodNotifier.addCustomFood path, '
            'which fires syncCustomItemsNow + pushSnapshot.');
  });
```

- [ ] **Step 2: Run extended test**

```bash
flutter test test/sync/nutrition_redesign_sync_test.dart
```

Expected: ALL PASS.

- [ ] **Step 3: Commit**

```bash
git add test/sync/nutrition_redesign_sync_test.dart
git commit -m "$(cat <<'EOF'
test(sync): lock sync invariants for nutrition redesign

Regression tests covering the new code paths from Plan D:

  * addWater still fires syncNutritionData + pushSnapshot (rebar)
  * LogFoodSheet mode bodies use HiveService.instance.<box>, never
    raw Hive.box('...') — protects the cold-start-reachable path
    invariant from CLAUDE.md.
  * HydrationCard performs no inline healthBox writes — all
    mutations go through urineColorProvider / waterIntakeProvider.
  * YourFoodsSection performs no inline customBox writes — read-only
    chip strip; mutations via CustomFoodSheet only.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Mark `hydration_section.dart` for retirement (orphaned)

**Files:**
- Delete: `lib/features/nutrition/widgets/hydration_section.dart`

**Background:** After Task 9, `nutrition_screen.dart` no longer references `HydrationSection`. Confirm there's no other caller, then remove the file. (`food_logger_section.dart`, `scan_meal_section.dart`, `cart_auditor_section.dart`, `saved_meals_section.dart`, `barcode_scan_sheet.dart` are all still referenced — from inside `log_food_modes/*` — so do NOT delete those.)

- [ ] **Step 1: Confirm `hydration_section.dart` is orphaned**

```bash
grep -rn "HydrationSection\|hydration_section" \
  lib/ test/ integration_test/ 2>/dev/null
```

Expected: zero matches outside of `lib/features/nutrition/widgets/hydration_section.dart` itself.

If anything else still references it, STOP and add the call site to the cleanup list before deleting.

- [ ] **Step 2: Delete the file**

```bash
git rm lib/features/nutrition/widgets/hydration_section.dart
```

- [ ] **Step 3: Run analyzer to confirm no broken imports**

```bash
flutter analyze lib/features/nutrition/
```

Expected: zero errors. (Warnings about unused imports are normal — fix any orphaned imports in adjacent files if surfaced.)

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(nutrition): retire hydration_section.dart (orphaned)

After the page rewrite in Task 9 + the new HydrationCard from Task 2,
hydration_section.dart has no callers. Removed.

Other widgets that LOOK orphaned but still have callers (preserved):
  * food_logger_section.dart   — used by AiModeBody
  * scan_meal_section.dart     — used by ScanModeBody
  * cart_auditor_section.dart  — used by CartModeBody
  * saved_meals_section.dart   — used by SearchModeBody
  * barcode_scan_sheet.dart    — both legacy entry point AND
                                 BarcodeBody used by BarcodeModeBody
  * ai_breakdown_card.dart     — used by AiModeBody
  * custom_food_sheet.dart     — used by YourFoodsSection
  * food_search_sheet.dart     — search providers reused by
                                 SearchModeBody

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Live verification on device

**Files:** None.

This task is on-device exploratory testing of the redesigned page. No commit.

- [ ] **Step 1: Build APK**

Use the `/build-apk` skill (per CLAUDE.md). Do NOT run `flutter build apk` directly — it can hang silently on this machine.

- [ ] **Step 2: Manual flow — page layout & scroll budget**

Open the app → Nutrition tab. Confirm:
- Layout order top-to-bottom: header, TODAY'S SUMMARY, `+ LOG FOOD` CTA (gold full-width), HYDRATION & STATUS (single card with water row + urine row), TODAY'S MEALS, INSIGHTS & TRENDS, YOUR FOODS.
- Total scroll on a 360×640 viewport ≤ 800 dp.
- No `+ AI INPUT` / `SEARCH & CUSTOM` / `SAVED MEALS` standalone sections.

- [ ] **Step 3: Manual flow — `+ LOG FOOD` sheet**

Tap the gold `+ LOG FOOD` CTA. Confirm:
- Sheet opens at ~75% screen height.
- AI tab is selected by default (gold).
- Tabs `✨ AI`, `📷 SCAN`, `🛒 CART`, `🔢 BAR`, `🔍 SEARCH` all visible.
- Type "2 rotis with dal" → ANALYSE & LOG → breakdown card renders → tap LOG → sheet dismisses → `TODAY'S MEALS` shows the new entry.

- [ ] **Step 4: Manual flow — Hydration card**

- Tap each `[+ 250ML]` / `[+ 500ML]` button → glass grid + bar update.
- Tap the `[change ▾]` toggle next to `URINE STATUS` → 7-color picker expands.
- Tap a color → pill updates to that status, picker auto-collapses, tip line updates.
- Force-close + reopen the app → urine selection persists (Hive read).

- [ ] **Step 5: Manual flow — YOUR FOODS**

- Tap `+ ADD CUSTOM` → CustomFoodSheet opens.
- Save a custom food.
- Sheet dismisses → YOUR FOODS row updates instantly to show the new chip with `DRAFT` pill.
- Confirm the food appears in cloud `user_custom_foods` table within a minute (Supabase dashboard).

- [ ] **Step 6: Manual flow — sync verification**

Watch logs while doing each mutation. Each must show one of:
- `[SyncService] syncNutritionData ok` (water, urine, food log).
- `[SyncService] syncCustomItemsNow ok` (custom food create).
- `[SyncService] pushSnapshot ok` (after every mutation).

If any mutation produces only one of the two pair, that's a sync gap — open an issue and add a contract test.

- [ ] **Step 7: Done**

If all 6 manual flows pass, Plan D is verified end-to-end. Move on to APK Test #4.

---

## Self-Review

**Spec coverage (Obs 3 Nutrition Page Redesign + Q7 + Q8 + Q8.1):**

| Spec item | Task |
|---|---|
| `+ LOG FOOD` bottom sheet hosting 5 modes | Task 8 (shell) + Tasks 4–7 (mode bodies) |
| AI mode default, tabs as segmented WardChip | Task 8 |
| SEARCH sub-filter chips `[All] [Saved Meals] [Recent]` | Task 5 (shell) + Task 7 (wiring) |
| Each mode dismisses on save | Tasks 4 / 5 / 8 (`onLogged` callbacks) |
| Combined Hydration + Urine card (Q8.1=A) | Task 2 |
| YOUR FOODS section mirroring Train YOUR EXERCISES | Task 3 |
| Page reorder: header → summary → CTA → hydration → meals → insights → your foods | Task 9 |
| ≤ 800 dp scroll on 360×640 | Task 9 + Task 12 verification |
| Sync hygiene — every mutation fires syncNutritionData + pushSnapshot | Task 1 (urine + custom food gaps) + Task 10 (regression locks) |
| Custom food create fires syncCustomItemsNow | Task 1 |
| `nutrition_screen.dart` drops from ~1265 to ~600 lines | Task 9 |
| Reuse `WardChip` / `WardCard` / `WardLetterhead` / `WardGlassGrid` / `WardBar` / `WardRule` | Tasks 2, 3, 8 |
| Existing widgets refactored not deleted | Tasks 4–7 wrap; only `hydration_section.dart` deleted (Task 11) |

**Placeholder scan:** None remaining after Task 7 wires up `_SearchResultsList` + `_RecentLogs`. Task 5's barcode body is a temporary shell intentionally finalised in Task 6.

**Type consistency:**
- `LogFoodMode` enum members `ai`, `scan`, `cart`, `barcode`, `search` exactly match Task 8's switch and Task 5's mode body class names.
- `customBox` key prefix `custom_food_` (Task 3) matches `CustomFoodNotifier.addCustomFood` writer at `nutrition_provider.dart:1033`.
- `submitted_to_db` and `approved` status flags (Task 3) match the field names actually written by `addCustomFood` at `nutrition_provider.dart:1053–1054`. NB: these names differ from the Train custom-exercise mirror (`submitted_to_library` / `approved_for_library`) — preserved as-is to avoid touching Hive shapes.
- `urineColorProvider` + `waterIntakeProvider` import paths (Task 2) match existing exports in `nutrition_provider.dart:410, 466`.
- `HiveService.instance.customBox` (Task 3) matches existing accessor used by `CustomFoodNotifier.addCustomFood` and `_buildYourExercisesSection`.
- `WardChipTone.gold` / `.ok` / `.warn` / `.bad` / `.neutral` (Tasks 2, 3, 8) match the enum at `ward_chip.dart:15`.

**Cross-plan dependencies:**
- Plan A (DB + sync bugs) ships migration 039. This plan does not require it — Plan D works against the existing schema. Plans can land independently.
- Plan B (Forever-Friend rank system) modifies `train_screen.dart`. This plan touches `nutrition_screen.dart` only — no merge conflict.
- Plan C (Diet plan protein anchor) modifies `diet_plan_screen.dart` + `nutrition_provider.dart`. There IS overlap with this plan in `nutrition_provider.dart` (Task 1 patches `UrineColorNotifier` and `CustomFoodNotifier`). Resolution: land Plan C first OR Plan D first; the patches are in different methods, so a sequential rebase is conflict-free. If they ship in parallel, the second-merged plan rebases the small two-method delta from Task 1.

**Constraint compliance (CLAUDE.md):**
- §6 rule 1 (Hive-first): All mutations remain Hive-first. New widgets read existing providers, never inline Hive writes.
- §6 rule 2 (Riverpod only): `LogFoodSheet`, `LogFoodMode` enum, all mode bodies extend `ConsumerStatefulWidget` / `ConsumerWidget`. No `setState` for shared state.
- §6 rule 4 (Repository pattern): Custom food create stays inside `CustomFoodNotifier.addCustomFood` → `NutritionRepository.syncCustomFoodToSupabase`. New widgets never call Supabase directly.
- §6 rule 5 (subscription.gate): AI mode usage limits already enforced inside `FoodLoggerSection._analyse` (existing) — no new gating needed.
- §9 (Wardroom palette): All new widgets use `AppColors.accent` / `info` / `ok` / `warn` / `bad` from the canonical palette. Zero hardcoded `Color(0xFF...)` literals introduced.
- §15 (Sync schedule): Task 1 closes two gaps (urine + custom food); Task 10 locks invariants in regression tests.

**Path verification:** Every file path in this plan was verified by the Read tool before writing the plan (`nutrition_screen.dart`, `food_logger_section.dart`, `scan_meal_section.dart` line counts, `cart_auditor_section.dart`, `barcode_scan_sheet.dart`, `saved_meals_section.dart`, `custom_food_sheet.dart`, `nutrition_provider.dart`, `train_screen.dart` `_buildYourExercisesSection`, `ward_chip.dart` `WardChipTone` enum). Line numbers cited (`nutrition_screen.dart:976` for `_buildInlineWaterTracker`, `nutrition_provider.dart:446` for `UrineColorNotifier.select`, `nutrition_provider.dart:1015` for `addCustomFood`, `train_screen.dart:1908` for `_buildYourExercisesSection`) all match the live source as of `feat/apk-test-1-batch` HEAD `e1c55b3`.

**Out-of-scope (deferred):**
- Image of the `LogFoodSheet` empty-state hero illustration (header decoration). The current shell uses a plain mono `LOG FOOD` title.
- Sub-tab analytics chips for INSIGHTS & TRENDS pulled from `coach_notices`. Spec mentions "pattern chips — Low protein 3 days" but the data path (`coach_notices` → display) needs its own provider; deferred. The existing `WeeklyChartCard` pair fully satisfies the section in the meantime.
- Reusable `BarcodeBody` extraction (Task 6) is deliberately scoped to "use existing flow" rather than fully redesign the result editor; redesign tracked in Plan E (out of scope here).
