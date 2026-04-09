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
import '../widgets/weekly_chart_card.dart';
import '../widgets/scan_meal_section.dart';
import '../widgets/cart_auditor_section.dart';
import '../widgets/saved_meals_section.dart';
import '../widgets/food_search_sheet.dart';
import '../widgets/barcode_scan_sheet.dart';
import '../widgets/custom_food_sheet.dart';

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  bool _isLoading = true;
  bool _isInsightsExpanded = false;
  bool _isWaterExpanded = true;
  int _logTabIndex = 0;

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

  // ── Meals Content ─────────────────────────────────────────────

  Widget _buildMealsTab() {
    final nutrition = ref.watch(dailyNutritionProvider);
    final breakdown = ref.watch(aiBreakdownProvider);
    final targets = ref.watch(macroTargetsProvider);
    final weeklyData = ref.watch(weeklyNutritionProvider);
    final savedMeals = ref.watch(savedMealsProvider);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── 1. Today's Summary (calorie ring + macro bars + TDEE tooltip) ──
        _sectionLabel('TODAY\'S SUMMARY', topPadding: 10),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildCalorieCard(nutrition, targets: targets),
        ),
        const SizedBox(height: 10),

        // ── 2. Unified Log Food Card (AI + Scan + Search) ──
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildUnifiedLogCard(),
        ),
        const SizedBox(height: 10),

        // ── 3. AI Breakdown (conditional) ──
        if (breakdown != null) ...[
          const AiBreakdownCard(),
          const SizedBox(height: 10),
        ],

        // ── 4. Inline Water Tracker (moved above meals) ──
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: _buildInlineWaterTracker(),
        ),
        const SizedBox(height: 10),

        // ── 5. Today's Meals ──
        _sectionLabel('TODAY\'S MEALS'),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: TodaysMealsCard(
            meals: nutrition.allMeals,
            onDelete: (logId) {
              ref.read(foodLogProvider.notifier).deleteFoodLog(logId);
            },
            onEdit: (meal) => _showEditMacrosSheet(context, meal),
          ),
        ),
        const SizedBox(height: 10),

        // ── 6. Saved Meals (hidden if empty) ──
        if (savedMeals.isNotEmpty) ...[
          _sectionLabel('SAVED MEALS'),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            child: const SavedMealsSection(),
          ),
          const SizedBox(height: 10),
        ],

        // ── 7. Insights & Trends (collapsed by default) ──
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

  // ── Calorie Ring + Macro Bars Card ─────────────────────────────

  Widget _buildCalorieCard(DailyNutritionData nutrition,
      {Map<String, double> targets = const {}}) {
    final consumed = nutrition.calories.round();
    final target = nutrition.calorieTarget.round();
    final remaining = (target - consumed).clamp(0, target);
    final progress =
        nutrition.calorieTarget > 0 ? consumed / nutrition.calorieTarget : 0.0;
    final waterMl = ref.watch(waterIntakeProvider);
    const waterTarget = 3000;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.cardPadding, 10, AppSpacing.cardPadding, AppSpacing.cardPadding),
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
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(110, 110),
                  painter: CalorieRingPainter(
                    progress: progress.clamp(0.0, 1.0),
                    trackColor: AppColors.input,
                    fillColor: AppColors.accent,
                    strokeWidth: 10,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$consumed',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 24,
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
                    const SizedBox(height: 3),
                    Text(
                      '$remaining',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 15,
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
                    child: const Icon(Icons.info_outline,
                        color: AppColors.textSecondary, size: 13),
                  ),
                ),
                const SizedBox(height: 2),
                _macroRow(
                  label: 'PROTEIN',
                  current: nutrition.protein.round(),
                  target: nutrition.proteinTarget.round(),
                  color: AppColors.orange,
                ),
                const SizedBox(height: 6),
                _macroRow(
                  label: 'CARBS',
                  current: nutrition.carbs.round(),
                  target: nutrition.carbTarget.round(),
                  color: AppColors.blue,
                ),
                const SizedBox(height: 6),
                _macroRow(
                  label: 'FAT',
                  current: nutrition.fat.round(),
                  target: nutrition.fatTarget.round(),
                  color: AppColors.purple,
                ),
                const SizedBox(height: 6),
                _macroRow(
                  label: 'FIBER',
                  current: nutrition.fiber.round(),
                  target: nutrition.fiberTarget.round(),
                  color: AppColors.green,
                ),
                const SizedBox(height: 6),
                _macroRow(
                  label: 'WATER',
                  current: waterMl,
                  target: waterTarget,
                  color: const Color(0xFF06b6d4),
                  suffix: 'ml',
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
              '$current / $target$suffix',
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

  // ── Unified Log Food Card ────────────────────────────────────

  Widget _buildUnifiedLogCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LOG FOOD',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          // Tab bar — 3 pill buttons
          Row(
            children: [
              _logTab(0, '\u2728 AI'),
              const SizedBox(width: 6),
              _logTab(1, '\uD83D\uDCF7 Scan'),
              const SizedBox(width: 6),
              _logTab(2, '\uD83D\uDD0D Search'),
            ],
          ),
          const SizedBox(height: 12),
          // Tab content
          if (_logTabIndex == 0)
            const FoodLoggerSection()
          else if (_logTabIndex == 1)
            Column(
              children: const [
                ScanMealSection(),
                SizedBox(height: 12),
                CartAuditorSection(),
              ],
            )
          else
            _buildSearchTab(context),
        ],
      ),
    );
  }

  Widget _logTab(int index, String label) {
    final isActive = index == _logTabIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _logTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accent.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: isActive
                  ? AppColors.accent.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isActive ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchTab(BuildContext context) {
    return Column(
      children: [
        // Barcode scan button
        GestureDetector(
          onTap: () => showBarcodeScanSheet(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code_scanner,
                    color: AppColors.accent, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Scan product barcode',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                const Spacer(),
                Text(
                  'FREE',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Search button
        GestureDetector(
          onTap: () => showFoodSearchSheet(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.search,
                    color: AppColors.textSecondary, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Search 5,000+ foods...',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => showCustomFoodSheet(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
              color: AppColors.accent.withValues(alpha: 0.06),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_circle_outline, color: AppColors.accent, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Create custom food',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'FREE \u00B7 No daily limit \u00B7 Indian foods database',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.green,
            letterSpacing: 0.5,
          ),
        ),
      ],
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
          decoration: const BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'EDIT MACROS',
                style: GoogleFonts.getFont('DM Sans', fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1.2,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                foodName,
                style: GoogleFonts.getFont('DM Sans', fontSize: 16,
                    fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _macroField('Calories', calCtrl, AppColors.accent),
                  const SizedBox(width: 6),
                  _macroField('Protein (g)', proteinCtrl, AppColors.orange),
                  const SizedBox(width: 6),
                  _macroField('Carbs (g)', carbsCtrl, AppColors.textSecondary),
                  const SizedBox(width: 6),
                  _macroField('Fat (g)', fatCtrl, AppColors.textSecondary),
                  const SizedBox(width: 6),
                  _macroField('Fiber (g)', fiberCtrl, AppColors.green),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
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
                    style: GoogleFonts.getFont('DM Sans', fontSize: 14,
                        fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _macroField(String label, TextEditingController ctrl, Color accentColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: GoogleFonts.getFont('DM Sans', fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 0.5,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: GoogleFonts.getFont('DM Sans', fontSize: 16,
                fontWeight: FontWeight.w700, color: accentColor),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.input,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: accentColor),
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
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'YOUR TARGETS',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              _bmrInfoRow(
                  'BMR', '${targets['bmr']?.round() ?? 0} kcal'),
              const SizedBox(height: 8),
              _bmrInfoRow(
                  'TDEE', '${targets['tdee']?.round() ?? 0} kcal'),
              const SizedBox(height: 8),
              _bmrInfoRow(
                  'Target', '${targets['calories']?.round() ?? 0} kcal'),
              const SizedBox(height: 16),
              Text(
                'BMR = Basal Metabolic Rate\nTDEE = Total Daily Energy Expenditure',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Got it',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
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

  Widget _bmrInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // ── Inline Water Tracker ──────────────────────────────────────

  static const _urineColors = [
    (color: Color(0xFFFFF9C4), status: 'Excellent', tip: 'Pale straw — optimal', statusColor: AppColors.green),
    (color: Color(0xFFFFF176), status: 'Good', tip: 'Clear yellow — well hydrated', statusColor: AppColors.green),
    (color: Color(0xFFFFD600), status: 'Adequate', tip: 'Yellow — drink more soon', statusColor: Color(0xFFF59E0B)),
    (color: Color(0xFFFFB300), status: 'Low', tip: 'Dark yellow — drink now', statusColor: Color(0xFFF59E0B)),
    (color: Color(0xFFE65100), status: 'Very low', tip: 'Amber — significantly dehydrated', statusColor: AppColors.red),
    (color: Color(0xFFBF360C), status: 'Critical', tip: 'Brown — consult a doctor', statusColor: AppColors.red),
    (color: Color(0xFF4E342E), status: 'Doctor!', tip: 'Dark brown — medical attention', statusColor: AppColors.red),
  ];

  Widget _buildInlineWaterTracker() {
    final waterMl = ref.watch(waterIntakeProvider);
    const waterTarget = 3000;
    final progress = (waterMl / waterTarget).clamp(0.0, 1.0);
    final selectedUrine = ref.watch(urineColorProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // -- Top row: label + amount + expand toggle --
          GestureDetector(
            onTap: () => setState(() => _isWaterExpanded = !_isWaterExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text(
                  '\u{1F4A7} WATER',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${waterMl.toStringAsFixed(0)} / $waterTarget ml',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _isWaterExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // -- Progress bar --
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: const Color(0xFF161d28),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.blue),
            ),
          ),
          const SizedBox(height: 10),

          // -- Quick-add buttons or goal-reached message --
          if (waterMl >= waterTarget)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 13, color: AppColors.blue),
                  const SizedBox(width: 6),
                  Text(
                    'Goal reached! Great hydration today 💧',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue,
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
                            vertical: 6, horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppColors.input,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '+${amount}ml',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.blue,
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
                          'What is your urine color?',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
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
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _urineColors[i].color,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: Colors.white, width: 2)
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ),
                        if (selectedUrine >= 0 &&
                            selectedUrine < _urineColors.length) ...[
                          const SizedBox(height: 10),
                          Text(
                            '${_urineColors[selectedUrine].status} — ${_urineColors[selectedUrine].tip}',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _urineColors[selectedUrine].statusColor,
                            ),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() =>
                _isInsightsExpanded = !_isInsightsExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'INSIGHTS & TRENDS',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isInsightsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_isInsightsExpanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: WeeklyChartCard(
                title: 'This Week \u2014 Protein',
                emoji: '\u{1F4AA}',
                data: weeklyData.protein,
                barColor: AppColors.orange,
                avgLabel:
                    'Avg: ${weeklyData.avgProtein.round()}g/day',
                targetLabel:
                    'Target: ${weeklyData.proteinTarget.round()}g',
                targetColor: AppColors.orange,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
