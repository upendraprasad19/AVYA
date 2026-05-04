import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/home/widgets/streak_explainer_sheet.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
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

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  bool _isLoading = true;
  bool _isInsightsExpanded = false;

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                // Test #10 obs 3 — Nutrition header compacted to 2 rows.
                // Linear KCAL `WardBar` removed (the body's 110dp WardRing
                // already shows consumed + remaining — same data twice was
                // redundant). Streak pill collapses onto the title row,
                // saving ~38 dp.
                Builder(builder: (_) {
                  final now = DateTime.now();
                  const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
                  const monthShort = [
                    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
                    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
                  ];
                  final eyebrow =
                      'GALLEY · ${weekdays[now.weekday - 1]} ${now.day} '
                      '${monthShort[now.month - 1]}';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ROW 1 — eyebrow + DIET PLAN chip right
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const AnchorGlyph(size: 12),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                eyebrow,
                                style: AppTypography.monoXs.copyWith(
                                  color: AppColors.accent,
                                  letterSpacing: 3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _buildDietPlanButton(),
                          ],
                        ),
                      ),
                      // ROW 2 — title + streak pill inline-right
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'Fueling the plan',
                                style: AppTypography.h1.copyWith(height: 1.05),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () => StreakExplainerSheet.show(
                                context,
                                freezesAvailable: ref.read(streakFreezeProvider),
                                isPro: SubscriptionService.instance.isPro(),
                              ),
                              child: WardStatusStrip(
                                streakDays: ref.watch(streakProvider),
                                freezesAvailable: ref.watch(streakFreezeProvider),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Single gold rule closes the header
                      Container(
                        height: 1,
                        margin: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                        color: AppColors.accent.withValues(alpha: 0.33),
                      ),
                    ],
                  );
                }),

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
              onLongPressMeal: (meal) => _showLogActionMenu(context, meal),
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
              '+ LOG FOOD',
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
    final waterTarget = ref.watch(waterTargetProvider);

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

  // ── Long-press action menu (Plan C-14 / C-15) ─────────────────

  /// Long-press on a logged meal row -> Edit / Delete / Save-as-template
  /// bottom sheet. Plan C-14 + C-15.
  Future<void> _showLogActionMenu(
      BuildContext context, Map<String, dynamic> meal) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
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
            const SizedBox(height: 6),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: AppColors.textPrimary),
              title: Text('Edit', style: AppTypography.body),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.bookmark_add_outlined,
                  color: AppColors.textPrimary),
              title: Text('Save as template', style: AppTypography.body),
              onTap: () => Navigator.pop(ctx, 'save_template'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.bad),
              title: Text(
                'Delete',
                style: AppTypography.body.copyWith(color: AppColors.bad),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        _showEditMacrosSheet(context, meal);
        break;
      case 'delete':
        await _confirmAndDeleteLog(context, meal);
        break;
      case 'save_template':
        await _saveAsTemplate(context, meal);
        break;
    }
  }

  /// Plan C-14 — Confirm sheet + 10s UNDO snackbar via
  /// `NutritionWriteService.deleteLog(allowUndo: true)` +
  /// `restoreLastDeleted()`.
  Future<void> _confirmAndDeleteLog(
      BuildContext context, Map<String, dynamic> meal) async {
    final logKey = meal['id'] as String?;
    if (logKey == null) return;
    final name = meal['food_name'] as String? ?? 'this meal';
    final kcal = (meal['total_calories'] as num?)?.round() ?? 0;
    final protein = (meal['total_protein'] as num?)?.round() ?? 0;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete $name?', style: AppTypography.h3),
            const SizedBox(height: 10),
            Text(
              "$kcal kcal · ${protein}g protein will be removed from today's totals.",
              style: AppTypography.body.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('CANCEL',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textDim,
                          letterSpacing: 2,
                        )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.bad,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sharp),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('DELETE',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textPrimary,
                          letterSpacing: 2,
                        )),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await NutritionWriteService.instance
        .deleteLog(logKey: logKey, allowUndo: true);
    if (!mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete: ${result.errorMessage ?? "unknown"}'),
          backgroundColor: AppColors.card,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Meal deleted',
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.card,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppColors.accent,
          onPressed: () async {
            await NutritionWriteService.instance.restoreLastDeleted();
          },
        ),
      ),
    );
  }

  /// Plan C-15 — Save-as-template handler. Asks for a name,
  /// then calls `NutritionWriteService.saveMealAsTemplate`.
  Future<void> _saveAsTemplate(
      BuildContext context, Map<String, dynamic> meal) async {
    final logKey = meal['id'] as String?;
    if (logKey == null) return;
    final defaultName = meal['food_name'] as String? ?? 'Saved Meal';
    final controller = TextEditingController(text: defaultName);
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SAVE AS TEMPLATE',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                )),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: AppTypography.body,
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: AppTypography.body
                    .copyWith(color: AppColors.textDim),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.line2),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bgDeep,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () =>
                    Navigator.pop(ctx, controller.text.trim()),
                child: Text(
                  'SAVE',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.bgDeep,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;

    final result = await NutritionWriteService.instance.saveMealAsTemplate(
      sourceLogKey: logKey,
      customName: name,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Saved "$name" — find it in SAVED MEALS next time'
              : 'Save failed: ${result.errorMessage ?? "unknown"}',
          style: AppTypography.body,
        ),
        backgroundColor: AppColors.card,
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
