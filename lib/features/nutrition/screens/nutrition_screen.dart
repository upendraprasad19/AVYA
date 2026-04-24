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
import '../widgets/food_logger_section.dart';
import '../widgets/ai_breakdown_card.dart';
import '../widgets/todays_meals_card.dart';
import '../widgets/weekly_chart_card.dart';
import '../widgets/scan_meal_section.dart';
import '../widgets/cart_auditor_section.dart';
import '../widgets/saved_meals_section.dart';
import '../widgets/food_search_sheet.dart';
import '../widgets/barcode_scan_sheet.dart';
import '../widgets/custom_food_sheet.dart';
import '../widgets/log_to_slot_sheet.dart';

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  bool _isLoading = true;
  bool _isInsightsExpanded = false;
  bool _isWaterExpanded = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _retry() {
    setState(() => _isLoading = true);
    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(aiBreakdownProvider);
    ref.invalidate(macroTargetsProvider);
    ref.invalidate(weeklyNutritionProvider);
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                // -- Header --
                _buildHeader(now),

                // -- Content --
                Expanded(
                  child: _isLoading
                      ? const ScreenLoadingSkeleton(cardCount: 4)
                      : _buildMealsTabSafe(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps [_buildMealsTab] with try-catch for Hive read errors.
  Widget _buildMealsTabSafe() {
    try {
      return _buildMealsTab();
    } catch (e) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: ErrorState(
          title: 'Failed to load nutrition data',
          subtitle: 'Tap to retry',
          onRetry: _retry,
        ),
      );
    }
  }

  // ── Header ─────────────────────────────────────────────────────

  Widget _buildHeader(DateTime now) {
    // Handoff: eyebrow "GALLEY · TUE 14 APR" (3-letter weekday + day +
    // month-short) + Fraunces 30 title "Fueling the plan" + trailing
    // button + single gold rule.
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const monthShort = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final eyebrow =
        'GALLEY \u00B7 ${weekdays[now.weekday - 1]} ${now.day} ${monthShort[now.month - 1]}';
    return WardLetterhead(
      eyebrow: eyebrow,
      title: 'Fueling the plan',
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      divider: true,
      trailing: _buildDietPlanButton(),
    );
  }

  Widget _buildDietPlanButton() {
    // Compact pill (PR Part C.1, 2026-04-24) — shrunk to keep the
    // Fraunces serif title "Fueling the plan" on one line on 360dp
    // phones. Label 10sp / padding 8/4 / icon 14.
    return GestureDetector(
      onTap: () => context.go('/nutrition/diet-plan'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_menu,
                color: AppColors.accent, size: 14),
            const SizedBox(width: 4),
            Text(
              'DIET PLAN',
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                color: AppColors.accent,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Meals Content ─────────────────────────────────────────────

  Widget _buildMealsTab() {
    final nutrition = ref.watch(dailyNutritionProvider);
    final breakdown = ref.watch(aiBreakdownProvider);
    final targets = ref.watch(macroTargetsProvider);
    final profile = ref.watch(userProfileProvider);
    final weeklyData = ref.watch(weeklyNutritionProvider);
    final savedMeals = ref.watch(savedMealsProvider);

    // Layout reshuffle (PR Part C.2, 2026-04-24 — "Direction A+"):
    //   1. Today's Summary (projection inlined as italic under bars)
    //   2. Always-visible ⚡ AI input + SCAN peer (was 2-tab Log Food)
    //   3. Conditional AI breakdown card (appears after analyse)
    //   4. Today's Meals (4 fixed slots)
    //   5. Hydration
    //   6. Search & Custom (demoted, grouped under SEARCH & CUSTOM eyebrow)
    //   7. Insights & Trends accordion
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── 1. Today's Summary (calorie ring + macro bars + projection) ──
        _sectionLabel('TODAY\'S SUMMARY', topPadding: 10),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildCalorieCard(
            nutrition,
            targets: targets,
            profile: profile,
          ),
        ),
        const SizedBox(height: 10),

        // ── 2. Always-visible ⚡ AI input + SCAN peer ──
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildAiInputCard(),
        ),
        const SizedBox(height: 10),

        // ── 3. AI Breakdown (conditional) ──
        if (breakdown != null) ...[
          const AiBreakdownCard(),
          const SizedBox(height: 10),
        ],

        // ── 4. Today's Meals (moved up per C.2) ──
        _sectionLabel('TODAY\'S MEALS'),
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
              // C.4 — tapping "+ LOG" now opens LogToSlotSheet with the
              // slot locked. The sheet offers AI / SCAN / SEARCH tabs.
              onLogSlot: (slot) =>
                  LogToSlotSheet.show(context, slot: slot),
            );
          }),
        ),
        const SizedBox(height: 10),

        // ── 5. Hydration (unchanged content, position unchanged
        //      relative to meals per "Direction A+") ──
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildInlineWaterTracker(),
        ),
        const SizedBox(height: 10),

        // ── 6. Search & Custom (demoted under its own eyebrow) ──
        _sectionLabel('SEARCH & CUSTOM'),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildSearchAndCustomCard(),
        ),
        const SizedBox(height: 10),

        // ── 7. Saved Meals (hidden if empty, still above Insights) ──
        if (savedMeals.isNotEmpty) ...[
          _sectionLabel('SAVED MEALS'),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            child: const SavedMealsSection(),
          ),
          const SizedBox(height: 10),
        ],

        // ── 8. Insights & Trends (collapsed by default) ──
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildInsightsSection(weeklyData),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Section Label ──────────────────────────────────────────────

  Widget _sectionLabel(String text, {double topPadding = 12}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.gutter, topPadding, AppSpacing.gutter, 8),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.mono.copyWith(
          color: AppColors.textMute,
          letterSpacing: 2,
        ),
      ),
    );
  }

  // ── Calorie Ring + Macro Bars Card ─────────────────────────────

  Widget _buildCalorieCard(
    DailyNutritionData nutrition, {
    Map<String, double> targets = const {},
    Map<String, dynamic> profile = const {},
  }) {
    final consumed = nutrition.calories.round();
    final target = nutrition.calorieTarget.round();
    final remaining = (target - consumed).clamp(0, target);
    final progress =
        nutrition.calorieTarget > 0 ? consumed / nutrition.calorieTarget : 0.0;
    final waterMl = ref.watch(waterIntakeProvider);
    const waterTarget = 3000;

    final projectionLine = _projectionLine(profile);

    return WardCard(
      variant: WardCardVariant.hero,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
        children: [
          // Calorie ring — Wardroom animated ring with Fraunces big number
          SizedBox(
            width: 110,
            height: 110,
            child: WardRing(
              pct: progress.clamp(0.0, 1.0),
              size: 110,
              stroke: 6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$consumed',
                    style: AppTypography.h1.copyWith(
                      fontSize: 26,
                      color: AppColors.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'CONSUMED',
                    style: AppTypography.monoXs.copyWith(
                      fontSize: 7,
                      letterSpacing: 1.5,
                      color: AppColors.textMute,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$remaining',
                    style: AppTypography.h3.copyWith(
                      color: AppColors.accent,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'REMAINING',
                    style: AppTypography.monoXs.copyWith(
                      fontSize: 7,
                      letterSpacing: 1.5,
                      color: AppColors.textMute,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Macro bars + hydration
          Expanded(
            child: Column(
              children: [
                // Info icon row (compact)
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => _showBmrTdeeInfo(targets),
                    child: Icon(Icons.info_outline,
                        color: AppColors.textDim, size: 13),
                  ),
                ),
                const SizedBox(height: 2),
                _macroRow(
                  label: 'PROTEIN',
                  current: nutrition.protein.round(),
                  target: nutrition.proteinTarget.round(),
                  color: AppColors.accent,
                ),
                const SizedBox(height: 6),
                _macroRow(
                  label: 'CARBS',
                  current: nutrition.carbs.round(),
                  target: nutrition.carbTarget.round(),
                  color: AppColors.warn,
                ),
                const SizedBox(height: 6),
                _macroRow(
                  label: 'FAT',
                  current: nutrition.fat.round(),
                  target: nutrition.fatTarget.round(),
                  color: AppColors.bad,
                ),
                const SizedBox(height: 6),
                _macroRow(
                  label: 'FIBER',
                  current: nutrition.fiber.round(),
                  target: nutrition.fiberTarget.round(),
                  color: AppColors.ok,
                ),
                const SizedBox(height: 6),
                _macroRow(
                  label: 'WATER',
                  current: waterMl,
                  target: waterTarget,
                  color: AppColors.info,
                  suffix: 'ml',
                ),
              ],
            ),
          ),
        ],
      ),
          // Inline italic projection callout under the macro bars
          // (PR Part C.2, 2026-04-24). Was a standalone line under the
          // card; now lives inside the card body as a one-line Fraunces-
          // italic readout.
          if (projectionLine != null) ...[
            const SizedBox(height: 10),
            const WardRule(margin: EdgeInsets.zero),
            const SizedBox(height: 8),
            Text(
              projectionLine,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
                fontStyle: FontStyle.italic,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns a short projection sentence (e.g. "On track to hit 65kg by
  /// May 31 — ~8 wks") or null when the user has no goal / target set.
  /// Factored out of the old `_buildProjectionSubtitle` so the calorie
  /// card can inline it instead of rendering as a standalone line under
  /// the card.
  String? _projectionLine(Map<String, dynamic> profile) {
    final currentKg = (profile['current_weight_kg'] as num?)?.toDouble();
    final targetKg = (profile['target_weight_kg'] as num?)?.toDouble();
    final goal = (profile['primary_goal'] as String?) ?? 'general_fitness';
    final pace = profile['pace_preference'] is String
        ? profile['pace_preference'] as String
        : 'balanced';

    if ((goal != 'lose_fat' && goal != 'build_muscle') ||
        currentKg == null ||
        targetKg == null ||
        (currentKg - targetKg).abs() <= 0.1) {
      return null;
    }

    final p = BmrCalculator.projectGoalDate(
      currentKg: currentKg,
      targetKg: targetKg,
      pacePreference: pace,
    );

    if (p.weeks <= 0) return null;
    if (p.weeks > 104) {
      return 'On track to reach ${targetKg.toStringAsFixed(0)}kg in > 2 years';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateStr = '${months[p.date.month - 1]} ${p.date.day}';
    return 'On track to hit ${targetKg.toStringAsFixed(0)}kg by $dateStr'
        ' (~${p.weeks.round()} wks)';
  }


  Widget _macroRow({
    required String label,
    required int current,
    required int target,
    required Color color,
    String suffix = 'g',
  }) {
    final pct = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: AppTypography.mono.copyWith(
                fontSize: 9,
                letterSpacing: 1.8,
                color: color,
              ),
            ),
            Text(
              '$current / $target$suffix',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        WardBar(pct: pct, color: color, height: 4),
      ],
    );
  }

  // ── Always-visible AI input card (C.2) ───────────────────────

  /// Replaces the old 2-tab [AI | SCAN] `_buildUnifiedLogCard`. AI text
  /// input is always visible; SCAN is a peer button beside ANALYSE that
  /// opens the camera flow inline. Search + Custom Food moved to their
  /// own demoted section below Hydration (see `_buildSearchAndCustomCard`).
  Widget _buildAiInputCard() {
    return WardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.accent, size: 14),
              const SizedBox(width: 6),
              Text(
                'WHAT DID YOU JUST EAT?',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // AI text input + ANALYSE & LOG button (existing widget)
          const FoodLoggerSection(),

          const SizedBox(height: 10),

          // SCAN peer — opens the scan flow inline. The full ScanMealSection
          // widget lives here so state (loading, result editor) renders in
          // place once the user picks a photo.
          const ScanMealSection(),
        ],
      ),
    );
  }

  // ── Search & Custom card (C.2 demoted) ───────────────────────

  /// Groups Search foods + Create custom food + Cart Auditor + Barcode
  /// under a single "SEARCH & CUSTOM" eyebrow, demoted below Hydration.
  /// These were previously hoisted into the main Log Food tabs, which
  /// turned out to be noise for most users who prefer the AI input.
  Widget _buildSearchAndCustomCard() {
    return WardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search foods (C.5 — honest 93-item copy, not "5,000+")
          GestureDetector(
            onTap: () => showFoodSearchSheet(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 14, horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius:
                    BorderRadius.circular(AppRadius.sharp),
              ),
              child: Row(
                children: [
                  Icon(Icons.search,
                      color: AppColors.textDim, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'Search foods',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Create custom food
          GestureDetector(
            onTap: () => showCustomFoodSheet(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 13, horizontal: 14),
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    width: 2),
                color: AppColors.accentSoft,
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_outline,
                      color: AppColors.accent, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'CREATE CUSTOM FOOD',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Cart Auditor (grocery screenshot)
          const CartAuditorSection(),
          const SizedBox(height: 10),

          // Barcode scan
          GestureDetector(
            onTap: () => showBarcodeScanSheet(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 13, horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius:
                    BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner,
                      color: AppColors.accent, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'SCAN PRODUCT BARCODE',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  const WardChip(
                    label: 'FREE',
                    tone: WardChipTone.gold,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Delete Food Log (Confirmation + Undo) ─────────────────────

  /// Bug #20 — Confirmation dialog + 5s undo snackbar for food log delete.
  Future<void> _confirmAndDeleteFoodLog(String logId) async {
    final box = HiveService.instance.nutritionBox;
    final raw = box.get(logId);
    if (raw == null) return;
    final stashed = Map<String, dynamic>.from(raw as Map);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Text(
          'Delete this meal?',
          style: AppTypography.h3,
        ),
        content: Text(
          "This will remove it from today's totals. You'll have 5 seconds to undo.",
          style: AppTypography.body.copyWith(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('CANCEL',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textDim,
                  letterSpacing: 2,
                )),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('DELETE',
                style: AppTypography.mono.copyWith(
                  color: AppColors.bad,
                  letterSpacing: 2,
                )),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await ref.read(foodLogProvider.notifier).deleteFoodLog(logId);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Meal deleted',
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.card,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppColors.accent,
          onPressed: () {
            ref.read(foodLogProvider.notifier).restoreFoodLog(stashed);
          },
        ),
      ),
    );
  }

  // ── Edit Macros Sheet ────────────────────────────────────────

  void _showEditMacrosSheet(BuildContext context, Map<String, dynamic> meal) {
    final logId = meal['id'] as String?;
    if (logId == null) return;

    final calCtrl = TextEditingController(text: '${(meal['total_calories'] as num?)?.toInt() ?? 0}');
    final proteinCtrl = TextEditingController(text: '${(meal['total_protein'] as num?)?.toInt() ?? 0}');
    final carbsCtrl = TextEditingController(text: '${(meal['total_carbs'] as num?)?.toInt() ?? 0}');
    final fatCtrl = TextEditingController(text: '${(meal['total_fat'] as num?)?.toInt() ?? 0}');
    final fiberCtrl = TextEditingController(text: '${(meal['total_fiber'] as num?)?.toInt() ?? 0}');
    final foodName = meal['food_name'] as String? ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 14),
              Text(
                'EDIT MACROS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                foodName,
                style: AppTypography.h2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _macroField('Calories', calCtrl, AppColors.accent),
                  const SizedBox(width: 6),
                  _macroField('Protein (g)', proteinCtrl, AppColors.accent),
                  const SizedBox(width: 6),
                  _macroField('Carbs (g)', carbsCtrl, AppColors.warn),
                  const SizedBox(width: 6),
                  _macroField('Fat (g)', fatCtrl, AppColors.bad),
                  const SizedBox(width: 6),
                  _macroField('Fiber (g)', fiberCtrl, AppColors.ok),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.bgDeep,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
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
                  child: Text(
                    'SAVE',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.bgDeep,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _macroField(
      String label, TextEditingController ctrl, Color accentColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: AppTypography.h3.copyWith(color: accentColor),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.input,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 10),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.line2),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.line2),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: accentColor, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── BMR/TDEE Info Dialog ─────────────────────────────────────

  void _showBmrTdeeInfo(Map<String, double> targets) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'YOUR TARGETS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const WardRule(gold: true, margin: EdgeInsets.zero),
              const SizedBox(height: 8),
              WardKvRow(
                label: 'BMR',
                value: '${targets['bmr']?.round() ?? 0} kcal',
              ),
              WardKvRow(
                label: 'TDEE',
                value: '${targets['tdee']?.round() ?? 0} kcal',
              ),
              WardKvRow(
                label: 'Target',
                value: '${targets['calories']?.round() ?? 0} kcal',
                showDivider: false,
              ),
              const SizedBox(height: 14),
              Text(
                'BMR = Basal Metabolic Rate\nTDEE = Total Daily Energy Expenditure',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius:
                        BorderRadius.circular(AppRadius.sharp),
                  ),
                  child: Text(
                    'GOT IT',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.bgDeep,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Inline Water Tracker ──────────────────────────────────────

  static const _urineColors = [
    (color: Color(0xFFFFF9C4), status: 'Excellent', tip: 'Pale straw — optimal', statusColor: AppColors.ok),
    (color: Color(0xFFFFF176), status: 'Good', tip: 'Clear yellow — well hydrated', statusColor: AppColors.ok),
    (color: Color(0xFFFFD600), status: 'Adequate', tip: 'Yellow — drink more soon', statusColor: AppColors.warn),
    (color: Color(0xFFFFB300), status: 'Low', tip: 'Dark yellow — drink now', statusColor: AppColors.warn),
    (color: Color(0xFFE65100), status: 'Very low', tip: 'Amber — significantly dehydrated', statusColor: AppColors.bad),
    (color: Color(0xFFBF360C), status: 'Critical', tip: 'Brown — consult a doctor', statusColor: AppColors.bad),
    (color: Color(0xFF4E342E), status: 'Doctor!', tip: 'Dark brown — medical attention', statusColor: AppColors.bad),
  ];

  Widget _buildInlineWaterTracker() {
    final waterMl = ref.watch(waterIntakeProvider);
    const waterTarget = 3000;
    final progress = (waterMl / waterTarget).clamp(0.0, 1.0);
    final selectedUrine = ref.watch(urineColorProvider);

    return WardCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // -- Top row: label + amount + expand toggle --
          GestureDetector(
            onTap: () => setState(() => _isWaterExpanded = !_isWaterExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\u{1F4A7} HYDRATION',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.info,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                Text(
                  waterMl.toStringAsFixed(0),
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  ' / $waterTarget ml',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _isWaterExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.textDim,
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // -- 8-glass grid per handoff (one glass ≈ 375ml for a 3L goal) --
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

          // -- Thin progress bar (kept for precise ml tracking alongside glasses) --
          WardBar(pct: progress, color: AppColors.info, height: 4),
          const SizedBox(height: 10),

          // -- Quick-add buttons or goal-reached message --
          if (waterMl >= waterTarget)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.3)),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 13, color: AppColors.info),
                  const SizedBox(width: 6),
                  Text(
                    'GOAL REACHED',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.info,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [150, 250, 500, 750].map((amount) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: amount == 750 ? 0 : 6,
                    ),
                    child: GestureDetector(
                      onTap: () => ref
                          .read(waterIntakeProvider.notifier)
                          .addWater(amount),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppColors.input,
                          borderRadius:
                              BorderRadius.circular(AppRadius.sharp),
                          border: Border.all(
                              color: AppColors.info.withValues(alpha: 0.3)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '+${amount}ML',
                          style: AppTypography.mono.copyWith(
                            color: AppColors.info,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

          // -- Expanded section: urine color picker --
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _isWaterExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'URINE COLOR',
                          style: AppTypography.mono.copyWith(
                            color: AppColors.textMute,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(_urineColors.length, (i) {
                            final isSelected = selectedUrine == i;
                            return GestureDetector(
                              onTap: () => ref
                                  .read(urineColorProvider.notifier)
                                  .select(i),
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
                        if (selectedUrine >= 0 &&
                            selectedUrine < _urineColors.length) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              WardChip(
                                label:
                                    'STATUS \u00B7 ${_urineColors[selectedUrine].status.toUpperCase()}',
                                tone: _urineColors[selectedUrine]
                                            .statusColor ==
                                        AppColors.ok
                                    ? WardChipTone.ok
                                    : _urineColors[selectedUrine]
                                                .statusColor ==
                                            AppColors.warn
                                        ? WardChipTone.warn
                                        : WardChipTone.bad,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _urineColors[selectedUrine].tip,
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.textDim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ── Insights Section (collapsed by default) ──────────────────

  Widget _buildInsightsSection(WeeklyNutritionData weeklyData) {
    return WardCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(
                () => _isInsightsExpanded = !_isInsightsExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Text(
                    'INSIGHTS & TRENDS',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isInsightsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textDim,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_isInsightsExpanded) ...[
            const WardRule(margin: EdgeInsets.zero),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: WeeklyChartCard(
                title: 'This Week \u2014 Calories',
                emoji: '\u{1F4CA}',
                data: weeklyData.calories,
                barColor: AppColors.accent,
                avgLabel:
                    'Avg: ${weeklyData.avgCalories.round()} kcal/day',
                targetLabel:
                    'Target: ${weeklyData.calorieTarget.round()}',
                targetColor: AppColors.accent,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: WeeklyChartCard(
                title: 'This Week \u2014 Protein',
                emoji: '\u{1F4AA}',
                data: weeklyData.protein,
                barColor: AppColors.warn,
                avgLabel:
                    'Avg: ${weeklyData.avgProtein.round()}g/day',
                targetLabel:
                    'Target: ${weeklyData.proteinTarget.round()}g',
                targetColor: AppColors.warn,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
