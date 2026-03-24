import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import '../providers/nutrition_provider.dart';
import '../widgets/calorie_ring_painter.dart';
import '../widgets/food_logger_section.dart';
import '../widgets/ai_breakdown_card.dart';
import '../widgets/todays_meals_card.dart';
import '../widgets/hydration_section.dart';
import '../widgets/weekly_chart_card.dart';
import '../widgets/scan_meal_section.dart';
import '../widgets/cart_auditor_section.dart';
import '../widgets/saved_meals_section.dart';
import '../widgets/food_search_sheet.dart';
import '../widgets/custom_food_sheet.dart';

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen>
    with SingleTickerProviderStateMixin {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late TabController _tabController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

                // -- Tabs --
                _buildTabBar(),

                // -- Tab Content --
                Expanded(
                  child: _isLoading
                      ? const ScreenLoadingSkeleton(cardCount: 4)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildMealsTabSafe(),
                            _buildWaterTab(),
                          ],
                        ),
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
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NUTRITION',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Today \u00B7 ${now.day} ${_months[now.month - 1]}',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Quick actions
          _headerAction(
            icon: Icons.search,
            onTap: () => showFoodSearchSheet(context),
          ),
          const SizedBox(width: 6),
          _headerAction(
            icon: Icons.add,
            onTap: () => showCustomFoodSheet(context),
          ),
          const SizedBox(width: 6),
          _headerAction(
            icon: Icons.restaurant_menu,
            onTap: () => context.go('/nutrition/diet-plan'),
          ),
        ],
      ),
    );
  }

  Widget _headerAction({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 16),
      ),
    );
  }

  // ── Tab Bar ────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: AppColors.header,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.accent,
        indicatorWeight: 2,
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        tabs: const [
          Tab(text: 'Meals'),
          Tab(text: 'Water'),
        ],
      ),
    );
  }

  // ── Meals Tab ──────────────────────────────────────────────────

  Widget _buildMealsTab() {
    final nutrition = ref.watch(dailyNutritionProvider);
    final breakdown = ref.watch(aiBreakdownProvider);
    final targets = ref.watch(macroTargetsProvider);
    final weeklyData = ref.watch(weeklyNutritionProvider);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── BMR/TDEE Snapshot ──
        _sectionLabel('BMR / TDEE', topPadding: 10),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildBmrTdeeRow(targets),
        ),
        const SizedBox(height: 10),

        // ── Today's Summary ──
        _sectionLabel('TODAY\'S SUMMARY'),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildCalorieCard(nutrition),
        ),
        const SizedBox(height: 10),

        // ── Log Meal ──
        _sectionLabel('LOG MEAL'),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: const FoodLoggerSection(),
        ),
        const SizedBox(height: 10),

        // ── AI Breakdown Card ──
        if (breakdown != null) ...[
          const AiBreakdownCard(),
          const SizedBox(height: 12),
        ],

        // ── Quick Log Buttons ──
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: Row(
            children: [
              Expanded(
                child: _quickLogButton(
                  icon: Icons.search,
                  label: 'Search Food',
                  onTap: () => showFoodSearchSheet(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _quickLogButton(
                  icon: Icons.add_circle_outline,
                  label: 'Custom Food',
                  onTap: () => showCustomFoodSheet(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Scan Meal ──
        _sectionLabel('AI SCAN'),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: const ScanMealSection(),
        ),
        const SizedBox(height: 10),

        // ── Cart Auditor ──
        _sectionLabel('CART AUDITOR'),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: const CartAuditorSection(),
        ),
        const SizedBox(height: 10),

        // ── Today's Meals ──
        _sectionLabel('TODAY\'S MEALS'),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: TodaysMealsCard(meals: nutrition.allMeals),
        ),
        const SizedBox(height: 10),

        // ── Saved Meals ──
        _sectionLabel('SAVED MEALS'),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: const SavedMealsSection(),
        ),
        const SizedBox(height: 10),

        // ── Insights & Trends ──
        _sectionLabel('INSIGHTS & TRENDS'),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: WeeklyChartCard(
            title: 'This Week \u2014 Calories',
            emoji: '\u{1F4CA}',
            data: weeklyData.calories,
            barColor: AppColors.accent,
            avgLabel: 'Avg: ${weeklyData.avgCalories.round()} kcal/day',
            targetLabel: 'Target: ${weeklyData.calorieTarget.round()}',
            targetColor: AppColors.accent,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: WeeklyChartCard(
            title: 'This Week \u2014 Protein',
            emoji: '\u{1F4AA}',
            data: weeklyData.protein,
            barColor: AppColors.orange,
            avgLabel: 'Avg: ${weeklyData.avgProtein.round()}g/day',
            targetLabel: 'Target: ${weeklyData.proteinTarget.round()}g',
            targetColor: AppColors.orange,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Water Tab ──────────────────────────────────────────────────

  Widget _buildWaterTab() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _sectionLabel('HYDRATION', topPadding: 10),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: const HydrationSection(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Section Label ──────────────────────────────────────────────

  Widget _sectionLabel(String text, {double topPadding = 12}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding, topPadding, AppSpacing.screenPadding, 8),
      child: Text(
        text,
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ── BMR/TDEE Row ───────────────────────────────────────────────

  Widget _buildBmrTdeeRow(Map<String, double> targets) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _miniStat('BMR', '${targets['bmr']?.round() ?? 0}', 'kcal'),
          Container(width: 1, height: 30, color: AppColors.border),
          _miniStat('TDEE', '${targets['tdee']?.round() ?? 0}', 'kcal'),
          Container(width: 1, height: 30, color: AppColors.border),
          _miniStat(
              'TARGET', '${targets['calories']?.round() ?? 0}', 'kcal'),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          unit,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 9,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── Calorie Ring + Macro Bars Card ─────────────────────────────

  Widget _buildCalorieCard(DailyNutritionData nutrition) {
    final consumed = nutrition.calories.round();
    final target = nutrition.calorieTarget.round();
    final remaining = (target - consumed).clamp(0, target);
    final progress =
        nutrition.calorieTarget > 0 ? consumed / nutrition.calorieTarget : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border:
            Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          // Calorie ring
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(120, 120),
                  painter: CalorieRingPainter(
                    progress: progress.clamp(0.0, 1.0),
                    trackColor: AppColors.input,
                    fillColor: AppColors.accent,
                    strokeWidth: 11,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$consumed',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'consumed',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$remaining',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.accent,
                        height: 1,
                      ),
                    ),
                    Text(
                      'remaining',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Macro bars
          Expanded(
            child: Column(
              children: [
                _macroRow(
                  label: 'PROTEIN',
                  current: nutrition.protein.round(),
                  target: nutrition.proteinTarget.round(),
                  color: AppColors.orange,
                ),
                const SizedBox(height: 8),
                _macroRow(
                  label: 'CARBS',
                  current: nutrition.carbs.round(),
                  target: nutrition.carbTarget.round(),
                  color: AppColors.blue,
                ),
                const SizedBox(height: 8),
                _macroRow(
                  label: 'FAT',
                  current: nutrition.fat.round(),
                  target: nutrition.fatTarget.round(),
                  color: AppColors.purple,
                ),
                const SizedBox(height: 8),
                _macroRow(
                  label: 'FIBER',
                  current: nutrition.fiber.round(),
                  target: nutrition.fiberTarget.round(),
                  color: AppColors.green,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _macroRow({
    required String label,
    required int current,
    required int target,
    required Color color,
  }) {
    final pct = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
            Text(
              '$current / ${target}g',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Container(
          height: 5,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: pct,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Quick Log Button ───────────────────────────────────────────

  Widget _quickLogButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.row),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.accent, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
